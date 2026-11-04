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
# Failed readonly conversion unwinds auto-remounts but leaves already-RO
# mounts alone
#
# STRATEGY:
# 1. Create two filesystems; remount one readonly beforehand
# 2. Open a zvol writable so pool conversion fails after remounts
# 3. Verify conversion fails and the previously RW filesystem is writable
#    again, while the already-RO filesystem stays readonly
#

verify_runnable "global"

function cleanup
{
	exec 9<&-
	exec 9>&-
	for ds in $TESTPOOL1/$TESTFS $TESTPOOL1/${TESTFS}_ro; do
		datasetexists $ds && ismounted $ds && \
		    log_must zfs unmount -f $ds
	done
	destroy_pool $TESTPOOL1
	rm -f $FILEVDEV
}

log_assert "Failed readonly conversion unwinds remounts; keeps already-RO mounts"
log_onexit cleanup

FILEVDEV="$TEST_BASE_DIR/zpool_set_readonly_005_neg.$$.dat"
FS_RW=$TESTPOOL1/$TESTFS
FS_RO=$TESTPOOL1/${TESTFS}_ro
VOL=$TESTPOOL1/$TESTVOL
ZDEV=$ZVOL_DEVDIR/$VOL

log_must truncate -s $MINVDEVSIZE $FILEVDEV
log_must zpool create -O canmount=off $TESTPOOL1 $FILEVDEV
log_must zfs create $FS_RW
log_must zfs create $FS_RO
log_must zfs create -V 10m $VOL
block_device_wait $ZDEV

MNT_RW="$(get_prop mountpoint $FS_RW)"
MNT_RO="$(get_prop mountpoint $FS_RO)"

log_must touch $MNT_RW/rw-file $MNT_RO/ro-file
log_must zfs mount -o remount,ro $FS_RO
log_must test "$(get_prop readonly $FS_RO)" == "on"
log_mustnot touch $MNT_RO/ro-file.new

exec 9<> "$ZDEV"
log_mustnot zpool set readonly=on $TESTPOOL1
log_must test "$(get_pool_prop readonly $TESTPOOL1)" == "off"

# Auto-remounted filesystem should be writable again
log_must test "$(get_prop readonly $FS_RW)" == "off"
log_must eval "echo restored > $MNT_RW/rw-file"

# Already-RO filesystem should not have been remounted RW by unwind
log_must test "$(get_prop readonly $FS_RO)" == "on"
log_mustnot touch $MNT_RO/ro-file.new2

exec 9<&-
exec 9>&-

log_pass "Failed readonly conversion unwinds remounts; keeps already-RO mounts"
