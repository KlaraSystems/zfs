#!/bin/ksh -p
# SPDX-License-Identifier: CDDL-1.0
#
# This file and its contents are supplied under the terms of the
# Common Development and Distribution License ("CDDL"), version 1.0.
# You may only use this file in accordance with the terms of version
# 1.0 of the CDDL.
#
# A full copy of the text of the CDDL should have accompanied this
# source.  A copy of the CDDL is also available via the Internet at
# https://opensource.org/license/CDDL-1.0.
#

. $STF_SUITE/include/libtest.shlib

#
# DESCRIPTION:
#
# A failed RW->RO conversion (with remount unwind) followed by a successful
# conversion and export still allows the ZFS kernel module to be unloaded.
#
# STRATEGY:
# 1. Create a pool with a mounted filesystem and a zvol
# 2. Force a failed readonly=on (zvol held open) to exercise remount unwind
# 3. Convert successfully, export both pools, and unload/reload the modules
#

verify_runnable "global"

function zfs_module_loaded
{
	if is_linux; then
		[[ -d /sys/module/zfs ]]
	elif is_freebsd; then
		kldstat -q -n openzfs
	else
		return 1
	fi
}

function cleanup
{
	exec 9<&-
	exec 9>&-

	if ! zfs_module_loaded; then
		log_must $ZFS_SH
	fi

	if ! poolexists $TESTPOOL; then
		log_must zpool import $TESTPOOL
	fi

	poolexists $TESTPOOL1 && destroy_pool $TESTPOOL1
	rm -f $FILEVDEV
}

log_assert "ZFS modules unload after failed then successful RW->RO and export"
log_onexit cleanup

if ! is_linux && ! is_freebsd; then
	log_unsupported "Module unload test supported on Linux and FreeBSD only"
fi

if ! zfs_module_loaded; then
	log_unsupported "ZFS is not a loadable kernel module"
fi

FILEVDEV="$TEST_BASE_DIR/zpool_set_readonly_007.$$.dat"
VOL=$TESTPOOL1/$TESTVOL
ZDEV=$ZVOL_DEVDIR/$VOL
TESTFILE="readonly-unload-file"

log_must truncate -s $MINVDEVSIZE $FILEVDEV
log_must zpool create -O canmount=off $TESTPOOL1 $FILEVDEV
log_must zfs create $TESTPOOL1/$TESTFS
MNTPFS="$(get_prop mountpoint $TESTPOOL1/$TESTFS)"
log_must zfs create -V 10m $VOL
block_device_wait $ZDEV

# Failed conversion: remounts then unwinds when the zvol is busy
exec 9<> "$ZDEV"
log_mustnot zpool set readonly=on $TESTPOOL1
log_must test "$(get_pool_prop readonly $TESTPOOL1)" == "off"
log_must eval "echo still-writable > $MNTPFS/$TESTFILE"
exec 9<&-
exec 9>&-

# Successful conversion and export
log_must zpool set readonly=on $TESTPOOL1
log_must test "$(get_pool_prop readonly $TESTPOOL1)" == "on"
log_must_busy zpool export $TESTPOOL1
log_must_busy zpool export $TESTPOOL

typeset remaining
remaining="$(zpool list -H -o name 2>/dev/null)"
if [[ -n $remaining ]]; then
	log_must zpool import $TESTPOOL
	log_unsupported "Cannot unload zfs module; pools still imported: " \
	    "$remaining"
fi

zed_stop

log_must $ZFS_SH -u
if zfs_module_loaded; then
	log_fail "ZFS module still loaded after unload"
fi

log_must $ZFS_SH
log_must zfs_module_loaded
log_must zpool import $TESTPOOL

log_pass "ZFS modules unload after failed then successful RW->RO and export"
