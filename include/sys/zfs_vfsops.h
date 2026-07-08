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
 * Portions Copyright 2020 iXsystems, Inc.
 */

#ifndef _SYS_ZFS_VFSOPS_H
#define	_SYS_ZFS_VFSOPS_H

#ifdef _KERNEL
#include <sys/lockout.h>
#include <sys/dmu_objset.h>
#include <sys/spa_impl.h>
#include <sys/zfs_vfsops_os.h>

/*
 * Regardless of what happens inside ZFS a success code must never be returned
 * by mistake for critical operations like fsync() in case of forced exit.
 * Hence, zfsvfs' state must be re-checked on ZPL level as the final line of
 * defense.
 */
static inline int
zfsvfs_error(zfsvfs_t *zfsvfs)
{
	if (unlikely(zfsvfs == NULL ||
	    zfsvfs->z_os == NULL ||
	    zfsvfs->z_os->os_spa == NULL))
		return (SET_ERROR(EIO));

	if (SPA_EXITING(zfsvfs->z_os->os_spa))
		return (SET_ERROR(EIO));

	return (0);
}
#endif

extern void zfsvfs_update_fromname(const char *, const char *);

/*
 * XXX I'm pretty sure this doesn't really belong here; once the comment
 *     below is fulfilled and the lockout is in zfsvfs, it probably moves
 *     alongside zfsvfs_enter() and such -- robn, 2024-07-09
 */
#ifdef _KERNEL
extern void zfsvfs_apply_lockout(zfsvfs_t *zfsvfs, uint64_t lockout);

static inline int
zfsvfs_lockout_error(zfsvfs_t *zfsvfs)
{
	/*
	 * XXX this is actually checking pool lockout; change to dataset
	 *     once the lockout is propagated to datasets.
	 *
	 *     that said, it'd be better to actually wire this directly into
	 *     zfsvfs, for zfs_enter and such too, and also what the hell is
	 *     even the locking story for that path? for this we need a
	 *     callback mech, and also a condition filter (eg only writes for
	 *     LOCKOUT_READONLY). ideas already had, but maybe I didn't write
	 *     them down before? -- robn, 2024-07-09
	 */
	switch (atomic_load_64(&zfsvfs->z_os->os_spa->spa_lockout)) {
	case LOCKOUT_READONLY:
		return (SET_ERROR(EROFS));
	case LOCKOUT_SUSPEND:
		return (SET_ERROR(EIO));
	default:
		/* XXX idk I guess? -- robn, 2024-07-09 */
		return (SET_ERROR(EAGAIN));
	}
}
#endif

#endif /* _SYS_ZFS_VFSOPS_H */
