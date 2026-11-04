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
# zpool set readonly=on remounts multiple mounted filesystems readonly
#
# STRATEGY:
# 1. Create a pool with several filesystems mounted read-write
# 2. Convert the pool to readonly without manually remounting
# 3. Verify every previously RW filesystem was remounted readonly
#

verify_runnable "global"

function cleanup
{
	for ds in $TESTPOOL1/$TESTFS $TESTPOOL1/${TESTFS}_2 \
	    $TESTPOOL1/$TESTFS/$TESTFS1; do
		datasetexists $ds && ismounted $ds && \
		    log_must zfs unmount -f $ds
	done
	destroy_pool $TESTPOOL1
	rm -f $FILEVDEV
}

log_assert "zpool set readonly=on remounts multiple mounted filesystems"
log_onexit cleanup

FILEVDEV="$TEST_BASE_DIR/zpool_set_readonly_005.$$.dat"
FS1=$TESTPOOL1/$TESTFS
FS2=$TESTPOOL1/${TESTFS}_2
FS3=$TESTPOOL1/$TESTFS/$TESTFS1

log_must truncate -s $MINVDEVSIZE $FILEVDEV
log_must zpool create -O canmount=off $TESTPOOL1 $FILEVDEV
log_must zfs create $FS1
log_must zfs create $FS2
log_must zfs create $FS3

MNT1="$(get_prop mountpoint $FS1)"
MNT2="$(get_prop mountpoint $FS2)"
MNT3="$(get_prop mountpoint $FS3)"

log_must touch $MNT1/file1 $MNT2/file2 $MNT3/file3

log_must zpool set readonly=on $TESTPOOL1
log_must test "$(get_pool_prop readonly $TESTPOOL1)" == "on"

for ds in $FS1 $FS2 $FS3; do
	log_must test "$(get_prop readonly $ds)" == "on"
done

log_mustnot touch $MNT1/file1.new
log_mustnot touch $MNT2/file2.new
log_mustnot touch $MNT3/file3.new

log_pass "zpool set readonly=on remounts multiple mounted filesystems"
