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
# zpool set readonly=on fails when a filesystem cannot be remounted readonly
# because a process has a file open for writing (contrast 001_pos, where a
# read-only open does not block conversion).
#
# STRATEGY:
# 1. Create a pool with a filesystem mounted read-write
# 2. Keep a writable file descriptor open on the filesystem
# 3. Verify zpool set readonly=on fails
# 4. Verify the pool and filesystem remain writable
#

verify_runnable "global"

function cleanup
{
	exec 9<&-
	exec 9>&-
	destroy_pool $TESTPOOL1
	rm -f $FILEVDEV
}

log_assert "zpool set readonly=on fails when a filesystem cannot be remounted RO"
log_onexit cleanup

FILEVDEV="$TEST_BASE_DIR/zpool_set_readonly_001_neg.$$.dat"
TESTFILE="readonly-neg-file"

log_must truncate -s $MINVDEVSIZE $FILEVDEV
log_must zpool create -O canmount=off $TESTPOOL1 $FILEVDEV
log_must zfs create $TESTPOOL1/$TESTFS
MNTPFS="$(get_prop mountpoint $TESTPOOL1/$TESTFS)"

log_must touch $MNTPFS/$TESTFILE
exec 9<> "$MNTPFS/$TESTFILE"

log_mustnot zpool set readonly=on $TESTPOOL1
log_must test "$(get_pool_prop readonly $TESTPOOL1)" == "off"
log_must test "$(get_prop readonly $TESTPOOL1/$TESTFS)" == "off"

exec 9<&-
exec 9>&-
log_must eval "echo still-writable > $MNTPFS/$TESTFILE"

log_pass "zpool set readonly=on fails when a filesystem cannot be remounted RO"
