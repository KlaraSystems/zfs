// SPDX-License-Identifier: CDDL-1.0
/*
 * CDDL HEADER START
 *
 * The contents of this file are subject to the terms of the
 * Common Development and Distribution License (the "License").
 * You may not use this file except in compliance with the License.
 *
 * You can obtain a copy of the license at usr/src/OPENSOLARIS.LICENSE
 * or https://opensource.org/licenses/CDDL-1.0.
 * See the License for the specific language governing permissions
 * and limitations under the License.
 *
 * When distributing Covered Code, include this CDDL HEADER in each
 * file and include the License file at usr/src/OPENSOLARIS.LICENSE.
 * If applicable, add the following below this CDDL HEADER, with the
 * fields enclosed by brackets "[]" replaced with your own identifying
 * information: Portions Copyright [yyyy] [name of copyright owner]
 *
 * CDDL HEADER END
 */

/*
 * Copyright 2010 Sun Microsystems, Inc.  All rights reserved.
 * Use is subject to license terms.
 *
 * Portions Copyright 2012 Martin Matuska <martin@matuska.org>
 * Copyright (c) 2013, 2015 by Delphix. All rights reserved.
 * Portions Copyright 2026 Klara, Inc.
 */

#include <sys/dmu.h>
#include <sys/spa.h>
#include <sys/stat.h>
#include <sys/uio.h>
#include <sys/zap.h>
#include <sys/zap_impl.h>
#include <sys/zfs_ioctl.h>
#include <sys/zio.h>
#include <sys/zstd/zstd.h>
#include <sys/zvol.h>
#include <err.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "zstream.h"
#include "zstream_modules.h"
#include "zstream_util.h"

/*
 * Supported feature flags (in drr_versioninfo)
 *
 * Add bits here to allow e.g. compression, large blocks, etc.
 */
#define	SUPPORTED_FEATURES (DMU_BACKUP_FEATURE_EMBED_DATA | \
    DMU_BACKUP_FEATURE_LZ4 | DMU_BACKUP_FEATURE_LARGE_BLOCKS | \
    DMU_BACKUP_FEATURE_COMPRESSED | DMU_BACKUP_FEATURE_ZSTD)

typedef struct {
	int		raw_volume;
	size_t		raw_volume_size;
	boolean_t	isreg;
	boolean_t	inprop;
	boolean_t	inzvol;
	void		*zero_page;
	long		pagesize;
	long		iov_max;
	uint64_t	guid;
	uint64_t	featureflags;
} raw_context_t;

/*
 * write_zeros - zero a region.
 *
 * TODO: Optional secure erase, hole punching with fspacectl/fallocate/discard
 */
static void
write_zeros(raw_context_t *context, off_t offset, size_t len)
{
	static struct iovec *iov = NULL;
	int iovcnt = MIN(howmany(len, context->pagesize), context->iov_max);

	ASSERT3U(offset + len, >=, offset);

	if (iov == NULL)
		iov = safe_malloc(context->iov_max * sizeof (*iov));
	if (iovcnt == 0)
		return;

	size_t resid = len;
	while (resid > 0) {
		size_t iovsz = resid;
		int i;

		for (i = 0; i < iovcnt && resid > 0; i++) {
			iov[i].iov_base = context->zero_page;
			iov[i].iov_len = MIN(resid, context->pagesize);
			resid -= iov[i].iov_len;
		}
		ssize_t res = pwritev(context->raw_volume, iov, i, offset);
		if (res < 0)
			err(EXIT_FAILURE, "pwritev");
		iovsz -= resid;
		ASSERT3U(res, ==, iovsz);
		offset += iovsz;
	}
	ASSERT0(resid);
}

static inline void
extend(int raw_volume, size_t size)
{
	if (ftruncate(raw_volume, size) < 0)
		err(EXIT_FAILURE, "ftruncate");
}

/*
 * apply_properties - read the properties zap to adjust file size.
 *
 * Returns the value of the "size" property.
 */
static uint64_t
apply_properties(int raw_volume, uint8_t *buf, size_t len)
{
	const mzap_phys_t *mzap = (const mzap_phys_t *)buf;

	ASSERT3U(len, >=, sizeof (*mzap));
	ASSERT3U(MZAP_ENT_LEN, ==, sizeof (mzap_ent_phys_t));

	if (mzap->mz_block_type == BSWAP_64(ZBT_MICRO))
		zap_byteswap(buf, len);

	ASSERT3U(mzap->mz_block_type, ==, ZBT_MICRO);
	ASSERT0(strcmp(mzap->mz_chunk[0].mze_name, "size"));

	uint64_t size = mzap->mz_chunk[0].mze_value;
	extend(raw_volume, size);
	return (size);
}

static disposition_t
raw_begin_record(drr_packet_t *item, raw_context_t *context)
{
	struct drr_begin *drrb = &item->dp_drr.drr_u.drr_begin;
	context->featureflags =
	    DMU_GET_FEATUREFLAGS(drrb->drr_versioninfo);
	drr_headertype_t hdrtype =
	    DMU_GET_STREAM_HDRTYPE(drrb->drr_versioninfo);
	uint64_t unsupported_features =
	    context->featureflags & ~SUPPORTED_FEATURES;

	if (unsupported_features != 0) {
		errx(EXIT_FAILURE, "unsupported stream features: "
		    "%#llx of %#llx, aborting...",
		    (u_longlong_t)unsupported_features,
		    (u_longlong_t)context->featureflags);
	}
	if (hdrtype == DMU_SUBSTREAM) {
		boolean_t nonzero_guid = context->guid != 0;
		boolean_t guid_mismatch = context->guid != drrb->drr_fromguid;
		if (nonzero_guid && guid_mismatch) {
			errx(EXIT_FAILURE, "wrong fromguid: %llu != %llu, "
			    "aborting...",
			    (u_longlong_t)drrb->drr_fromguid,
			    (u_longlong_t)context->guid);
		}
		context->guid = drrb->drr_toguid;
	}
	return (D_OK);
}

static disposition_t
raw_object_record(drr_packet_t *item, raw_context_t *context)
{
	struct drr_object *drro = &item->dp_drr.drr_u.drr_object;

	if (context->featureflags & DMU_BACKUP_FEATURE_RAW &&
	    drro->drr_bonuslen > drro->drr_raw_bonuslen) {
		warnx("object %llu has bonuslen = "
		    "%u > raw_bonuslen = %u\n",
		    (u_longlong_t)drro->drr_object,
		    drro->drr_bonuslen, drro->drr_raw_bonuslen);
	}

	context->inzvol = drro->drr_object == ZVOL_OBJ &&
	    drro->drr_type == DMU_OT_ZVOL;
	context->inprop = drro->drr_object == ZVOL_ZAP_OBJ &&
	    drro->drr_type == DMU_OT_ZVOL_PROP;

	return (D_OK);
}

static disposition_t
raw_write_record(drr_packet_t *item, raw_context_t *context)
{
	struct drr_write *drrw = &item->dp_drr.drr_u.drr_write;

	if (context->inprop && context->isreg) {
		ASSERT0(drrw->drr_offset);
		context->raw_volume_size = apply_properties(context->raw_volume,
		    item->dp_payload, item->dp_payload_size);
	}

	if (context->inzvol) {
		safe_pwrite(context->raw_volume, item->dp_payload,
		    item->dp_payload_size, drrw->drr_offset);
	}
	return (D_OK);
}

static disposition_t
raw_free_record(drr_packet_t *item, raw_context_t *context)
{
	struct drr_free *drrf = &item->dp_drr.drr_u.drr_free;

	if (!context->inzvol)
		return (D_OK);

	off_t off = drrf->drr_offset;
	size_t len = drrf->drr_length;
	if (len == (size_t)-1) {
		if (context->isreg) {
			extend(context->raw_volume, off);
			if (off < context->raw_volume_size)
				extend(context->raw_volume,
				    context->raw_volume_size);
			else
				context->raw_volume_size = off;
		}
		return (D_OK);
	}
	write_zeros(context, off, len);
	return (D_OK);
}

static disposition_t
raw_write_embedded_record(drr_packet_t *item, raw_context_t *context)
{
	struct drr_write_embedded *drrwe =
	    &item->dp_drr.drr_u.drr_write_embedded;
	uint32_t lsize = drrwe->drr_lsize;
	uint8_t *debuff;

	ASSERT3U(item->dp_payload_size, <=, lsize);

	if (ctype_is_uncompressed(drrwe->drr_compression)) {
		debuff = item->dp_payload;
	} else {
		debuff = decompress_buffer(item->dp_payload,
		    item->dp_payload_size, lsize, drrwe->drr_compression);
		if (debuff == NULL) {
			err(EXIT_FAILURE, "decompression failed at offset %llu",
			    (u_longlong_t)drrwe->drr_offset);
		}
	}

	if (context->inprop && context->isreg) {
		ASSERT0(drrwe->drr_offset);
		context->raw_volume_size =
		    apply_properties(context->raw_volume, debuff, lsize);
	}

	if (context->inzvol)
		safe_pwrite(context->raw_volume, debuff, lsize,
		    drrwe->drr_offset);

	return (D_OK);
}

typedef disposition_t
raw_record_handler_f(drr_packet_t *item, raw_context_t *context);

static raw_record_handler_f *record_handlers[] = {
	raw_begin_record,
	raw_object_record,
	NULL,				/* DRR_FREEOBJECTS */
	raw_write_record,
	raw_free_record,
	NULL,				/* DRR_END */
	NULL,				/* DRR_WRITE_BYREF */
	NULL,				/* DRR_SPILL */
	raw_write_embedded_record,
	NULL,				/* DRR_OBJECT_RANGE */
	NULL				/* DRR_REDACT */
};

static disposition_t
chain_replay_raw(void *item_in, void *context_in)
{
	drr_packet_t *item = (drr_packet_t *)item_in;
	raw_context_t *context = (raw_context_t *)context_in;

	if (item == NULL)
		return (D_OK);

	raw_record_handler_f *handler = record_handlers[item->dp_drr.drr_type];
	if (handler == NULL) {
		/*
		 * Shouldn't happen since we're after the drop filter, but
		 * we can safely just ignore the record.
		 */
		return (D_OK);
	}
	return handler(item, context);
}

static chain_step_t
serial_replay_raw(raw_context_t *context)
{
	chain_step_t step = {
		.cs_type = CS_SERIAL,
		.cs_in_size = sizeof (drr_packet_t),
		.cs_out_size = sizeof (drr_packet_t),
		.cs_context = context,
		.cs_serial = {
			.process = chain_replay_raw
		}
	};
	return (step);
}

int
zstream_do_raw(int argc, char *argv[])
{
	chain_attrs_t attrs = { 0 };

	ENABLE_OPTION(&attrs, CA_FORBID_DEDUP);

	int c;
	uint64_t guid = 0;
	while ((c = getopt(argc, argv, ":g:v")) != -1) {
		switch (c) {
		case 'g':
			guid = strtoull(optarg, NULL, 0);
			if (guid == 0) {
				(void) fprintf(stderr, "invalid guid\n");
				zstream_usage();
			}
			break;
		case 'v':
			ENABLE_OPTION(&attrs, CA_VERBOSE);
			ENABLE_OPTION(&attrs, CA_DUMP_ALL_RECORDS);
			ENABLE_OPTION(&attrs, CA_DUMP_CHECKSUMS);
			break;
		case ':':
			warnx("missing argument for '%c' option", optopt);
			zstream_usage();
			break;
		case '?':
			warnx("invalid option '%c'", optopt);
			zstream_usage();
			break;
		}
	}

	argc -= optind;
	argv += optind;
	if (argc < 1) {
		warnx("missing path to raw volume");
		zstream_usage();
	}

	const char *raw_path = argv[0];
	struct stat64 st;
	long pagesize = sysconf(_SC_PAGESIZE);

	/*
	 * TODO: O_DIRECT, maybe as a command line flag? Avoid O_CREAT in /dev?
	 */
	int raw_volume = open(raw_path, O_WRONLY | O_CREAT, 0666);
	if (raw_volume < 0) {
		err(EXIT_FAILURE, "error while opening file '%s'", raw_path);
	}
	if (fstat64_blk(raw_volume, &st) < 0)
		err(EXIT_FAILURE, "fstat64_blk");

	raw_context_t context = {
		.raw_volume	 = raw_volume,
		.raw_volume_size = st.st_size,
		.isreg		 = S_ISREG(st.st_mode),
		.inprop		 = B_FALSE,
		.inzvol		 = B_FALSE,
		.zero_page	 = safe_calloc(pagesize),
		.pagesize	 = pagesize,
		.iov_max	 = sysconf(_SC_IOV_MAX),
		.guid		 = guid
	};

	uint32_t drop_mask = DROP_DRR_END | DROP_DRR_FREEOBJECTS |
	    DROP_DRR_SPILL | DROP_DRR_OBJECT_RANGE | DROP_DRR_REDACT;

	zstream_chain_t raw_chain = {
		STANDARD_INPUT_STACK((argc > 1) ? argv[1] : NULL),
		serial_dump_records(),
		serial_drop_record_types(drop_mask),
		parallel_decompress_writes(NULL),
		serial_replay_raw(&context),
		NULL_OUTPUT_STACK()
	};

	zstream_chain_exec(raw_chain, &attrs);

	if (fsync(raw_volume) != 0)
		err(EXIT_FAILURE, "fsync");

	if (OPTION_ENABLED(CA_VERBOSE))
		(void) printf("now at guid %llu\n",
		    (u_longlong_t)context.guid);
	else
		(void) printf("%llu\n", (u_longlong_t)context.guid);

	return (EXIT_SUCCESS);
}
