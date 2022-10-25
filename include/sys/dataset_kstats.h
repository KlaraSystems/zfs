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
 * Copyright (c) 2018 by Delphix. All rights reserved.
 * Copyright (c) 2018 Datto Inc.
 */

#ifndef _SYS_DATASET_KSTATS_H
#define	_SYS_DATASET_KSTATS_H

#include <sys/wmsum.h>
#include <sys/dmu.h>
#include <sys/kstat.h>
#include <sys/zil.h>

/*
 * Used for per-dataset metadata kstats.
 */
typedef struct meta_stats {
	kstat_named_t meta_open_count;
	kstat_named_t meta_stat_count;
	kstat_named_t meta_mkdir_count;
} meta_kstat_values_t;

typedef struct meta_sums {
	wmsum_t meta_open_count;
	wmsum_t meta_stat_count;
	wmsum_t meta_mkdir_count;
} meta_sums_t;

typedef struct dataset_sum_stats_t {
	wmsum_t dss_writes;
	wmsum_t dss_nwritten;
	wmsum_t dss_reads;
	wmsum_t dss_nread;
	wmsum_t dss_nunlinks;
	wmsum_t dss_nunlinked;
} dataset_sum_stats_t;

typedef struct dataset_kstat_values {
	kstat_named_t dkv_ds_name;
	kstat_named_t dkv_writes;
	kstat_named_t dkv_nwritten;
	kstat_named_t dkv_reads;
	kstat_named_t dkv_nread;
	/*
	 * nunlinks is initialized to the unlinked set size on mount and
	 * is incremented whenever a new entry is added to the unlinked set
	 */
	kstat_named_t dkv_nunlinks;
	/*
	 * nunlinked is initialized to zero on mount and is incremented when an
	 * entry is removed from the unlinked set
	 */
	kstat_named_t dkv_nunlinked;
	/*
	 * Per dataset zil kstats
	 */
	zil_kstat_values_t dkv_zil_stats;
	/*
	 * Per dataset zil kstats
	 */
	meta_kstat_values_t dkv_meta_stats;
} dataset_kstat_values_t;

typedef struct dataset_kstats {
	dataset_sum_stats_t dk_sums;
	zil_sums_t dk_zil_sums;
	meta_sums_t dk_meta_sums;
	kstat_t *dk_kstats;
} dataset_kstats_t;

#define	META_STAT_BUMP(kstats, stat) \
	do { \
		if (kstats.dk_meta_sums) \
			wmsum_add(kstats.dk_meta_sums.stat, 1); \
	} while (0)

int dataset_kstats_create(dataset_kstats_t *, objset_t *);
void dataset_kstats_destroy(dataset_kstats_t *);

void dataset_kstats_update_write_kstats(dataset_kstats_t *, int64_t);
void dataset_kstats_update_read_kstats(dataset_kstats_t *, int64_t);

void dataset_kstats_update_nunlinks_kstat(dataset_kstats_t *, int64_t);
void dataset_kstats_update_nunlinked_kstat(dataset_kstats_t *, int64_t);

#endif /* _SYS_DATASET_KSTATS_H */
