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
# Import writable, convert to RO, convert back to RW, then export.
# Exercises spa_make_readonly() followed by spa_resume_writeable().
#
# STRATEGY:
# 1. Create a pool (imported writable) and write a file
# 2. Convert the pool to readonly
# 3. Convert back to writable and verify writes succeed
# 4. Export the pool
#

verify_runnable "global"

function cleanup
{
	datasetexists $TESTPOOL1/$TESTFS && \
	    ismounted $TESTPOOL1/$TESTFS && \
	    log_must zfs unmount -f $TESTPOOL1/$TESTFS
	destroy_pool $TESTPOOL1
	rm -f $FILEVDEV
}

log_assert "import RW -> RO -> RW -> export round-trip succeeds"
log_onexit cleanup

FILEVDEV="$TEST_BASE_DIR/zpool_set_readonly_009.$$.dat"
TESTFILE="readonly-resume-file"
CONTENT_RW1="imported-writable"
CONTENT_RW2="resumed-writable"

log_must truncate -s $MINVDEVSIZE $FILEVDEV
log_must zpool create -O canmount=off $TESTPOOL1 $FILEVDEV
log_must zfs create $TESTPOOL1/$TESTFS
MNTPFS="$(get_prop mountpoint $TESTPOOL1/$TESTFS)"

log_must test "$(get_pool_prop readonly $TESTPOOL1)" == "off"
log_must eval "echo $CONTENT_RW1 > $MNTPFS/$TESTFILE"

log_must zpool set readonly=on $TESTPOOL1
log_must test "$(get_pool_prop readonly $TESTPOOL1)" == "on"
log_must test "$(get_prop readonly $TESTPOOL1/$TESTFS)" == "on"
log_must test "$(cat $MNTPFS/$TESTFILE)" == "$CONTENT_RW1"
log_mustnot eval "echo should-fail > $MNTPFS/$TESTFILE.new"

log_must zpool set readonly=off $TESTPOOL1
log_must test "$(get_pool_prop readonly $TESTPOOL1)" == "off"
log_must test "$(get_prop readonly $TESTPOOL1/$TESTFS)" == "off"
log_must eval "echo $CONTENT_RW2 > $MNTPFS/$TESTFILE"
log_must test "$(cat $MNTPFS/$TESTFILE)" == "$CONTENT_RW2"

log_must zpool export $TESTPOOL1
log_mustnot poolexists $TESTPOOL1

log_pass "import RW -> RO -> RW -> export round-trip succeeds"
