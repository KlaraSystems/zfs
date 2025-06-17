#!/bin/ksh -p
#
# CDDL HEADER START
#
# The contents of this file are subject to the terms of the
# Common Development and Distribution License (the "License").
# You may not use this file except in compliance with the License.
#
# You can obtain a copy of the license at usr/src/OPENSOLARIS.LICENSE
# or https://opensource.org/licenses/CDDL-1.0.
# See the License for the specific language governing permissions
# and limitations under the License.
#
# When distributing Covered Code, include this CDDL HEADER in each
# file and include the License file at usr/src/OPENSOLARIS.LICENSE.
# If applicable, add the following below this CDDL HEADER, with the
# fields enclosed by brackets "[]" replaced with your own identifying
# information: Portions Copyright [yyyy] [name of copyright owner]
#
# CDDL HEADER END
#

#
# Copyright (c) 2025, Klara, Inc.
#

. $STF_SUITE/tests/functional/fsync/fsync.kshlib

typeset LOOPDEVS=""
typeset DATAFILE=""

verify_runnable "global"

function cleanup
{
	log_pos zinject -c all
	log_pos zpool clear $TESTPOOL
	log_pos destroy_pool $TESTPOOL
	for ld in $LOOPDEVS ; do
	    log_pos loop_device_destroy $ld
	done
	if [[ -n $DATAFILE ]] ; then
	    log_pos rm $DATAFILE
	fi
}

log_onexit cleanup

log_assert "verify fsync() behaviour when the pool suspends"

# create 128K of random data, and take its checksum. we do this up front to
# ensure we don't get messed up by any latency from reading /dev/random or
# checksumming the file on the pool
DATAFILE=$(mktemp)
log_must dd if=/dev/random of=$DATAFILE bs=128K count=1

for i in {1..4} ; do
	typeset ld=""
	log_must eval "ld=$(loop_device_create)"
	LOOPDEVS="$LOOPDEVS $ld"
done

log_must zpool create $TESTPOOL raidz1 $LOOPDEVS

# do a sync write up front to properly create the zil head
log_must dd if=/dev/zero of=/$TESTPOOL/datafile bs=128k count=1 conv=fsync
log_must zpool sync

# inject errors to simulate a backplane loss: writes fail, and the followup
# flushes and probes can't see the device at all
for ld in $LOOPDEVS ; do
	log_must zinject -d $ld -e io -T write $TESTPOOL
	log_must zinject -d $ld -e nxio -T flush $TESTPOOL
	log_must zinject -d $ld -e nxio -T probe $TESTPOOL
done

# write with a followup fsync
dd if=$DATAFILE of=/$TESTPOOL/data_file bs=128k count=1 conv=fsync &
fsync_pid=$!

# the pool should suspend almost immediately, but wait just in case
log_note "waiting for pool to suspend"
typeset -i tries=10
until [[ $(cat /proc/spl/kstat/zfs/$TESTPOOL/state) == "SUSPENDED" ]] ; do
	if ((tries-- == 0)); then
		log_fail "pool didn't suspend"
	fi
	sleep 1
done

# now find out what happened to dd. If it's still running, then it's blocked in
# fsync() (the traditional ZFS behaviour). If it exited, it's success or
# failure is representative of the fsync() result. We are expecting that
# fsync() failed when the pool suspended; success would be a surprise indeed!
typeset fsync_result=
if kill -0 $fsync_pid ; then
	log_note "dd is blocked; fsync() has not returned"
	fsync_result="blocked"
else
	wait $fsync_pid
	if [[ $? -eq 0 ]] ; then
		log_note "dd finished; fsync() returned success"
		fsync_result="success"
	else
		log_note "dd finished; fsync() returned failure"
		fsync_result="failed"
	fi
fi

log_must test "$fsync_result" = "failed"

log_pos zinject -c all
log_pos zpool clear $TESTPOOL

log_pass "fsync() behaves correctly when the pool suspends"
