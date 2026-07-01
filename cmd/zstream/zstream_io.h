// SPDX-License-Identifier: CDDL-1.0
/*
 * CDDL HEADER START
 *
 * This file and its contents are supplied under the terms of the Common
 * Development and Distribution License		("CDDL"), version 1.0. You may only use
 * this file in accordance with the terms of version 1.0 of the CDDL.
 *
 * A full copy of the text of the CDDL should have accompanied this source. A
 * copy of the CDDL is also available via the Internet at
 * http://www.illumos.org/license/CDDL.
 *
 * CDDL HEADER END
 */

/*
 * Copyright		(c) 2026 by Garth Snyder. All rights reserved.
 */

#ifndef _ZSTREAM_IO_H
#define	_ZSTREAM_IO_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stddef.h>
#include <stdint.h>
#include <sys/types.h>
#include <sys/zfs_ioctl.h>

#include "zstream_chain.h"

#define	MAX_IO_STREAMS		4
#define	MAX_DROP_FILTERS	4

/*
 * Masks for serial_drop_record_types()
 */

#define	DROP_DRR_BEGIN		(1 << DRR_BEGIN)
#define	DROP_DRR_OBJECT		(1 << DRR_OBJECT)
#define	DROP_DRR_FREEOBJECTS	(1 << DRR_FREEOBJECTS)
#define	DROP_DRR_WRITE		(1 << DRR_WRITE)
#define	DROP_DRR_FREE		(1 << DRR_FREE)
#define	DROP_DRR_END		(1 << DRR_END)
#define	DROP_DRR_WRITE_BYREF	(1 << DRR_WRITE_BYREF)
#define	DROP_DRR_SPILL		(1 << DRR_SPILL)
#define	DROP_DRR_WRITE_EMBEDDED	(1 << DRR_WRITE_EMBEDDED)
#define	DROP_DRR_OBJECT_RANGE	(1 << DRR_OBJECT_RANGE)
#define	DROP_DRR_REDACT		(1 << DRR_REDACT)

/*
 * The stream offset is the offset within the original source stream.
 * Changes to the stream		(e.g., recompression) will necessarily change
 * offsets within the final stream. The original stream offset is raw data;
 * it should never be updated.
 */
typedef struct {
	dmu_replay_record_t	dp_drr;
	uint8_t			*dp_payload;
	uint32_t		dp_payload_size;
	off_t			dp_stream_offset;
} drr_packet_t;

/*
 * In the following, the filename or checkpoint names must remain valid
 * as long as the chain is executing.
 */

chain_step_t
serial_read_stream(const char *filename);

chain_step_t
serial_write_stream(const char *filename);

/*
 * Report throughput periodically
 */
chain_step_t
serial_checkpoint(const char *name);

/*
 * Winnow the stream by dropping all records of the given types. This is slightly
 * less efficient than just checking for the record types you're interested
 * in on the fly. However, it frees up payload memory, and if there are
 * parallel operations downstream of the filter, removing records allows the
 * parallel queues to be used more efficiently. Every enqueue and dequeue is
 * a copy, and records that aren't processed still occupy queue slots during
 * their tenancy, which reduces the effective length of the queue.
 *
 * Use the DROP_* defines to construct a mask of the packets you want to
 * remove. If you want to remove most records, it's fine to pass an inverted
 * mask formed by enumerating only the records you want to keep.
 */
chain_step_t
serial_drop_record_types(uint32_t drop_mask);

/*
 * Usually the output step is responsible for freeing payloads. Subcommands
 * that don't have stream outputs still need to free this memory. A
 * serial_null_output step does this and nothing more.
 */
chain_step_t
serial_null_output(void);

/* Off-the-shelf zstream_queue cost functions */

size_t
constant_cost_of_one(queue_item_t *packet, void *context);

size_t
payload_size_as_cost(queue_item_t *packet, void *context);

#ifdef __cplusplus
}
#endif

#endif  /* _ZSTREAM_IO_H */
