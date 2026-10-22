#!/bin/ksh -p
# SPDX-License-Identifier: CDDL-1.0
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
# Copyright 2007 Sun Microsystems, Inc.  All rights reserved.
# Use is subject to license terms.
#

#
# Copyright (c) 2013, 2016 by Delphix. All rights reserved.
#

#
# Copyright (c) 2026, Klara Systems, Inc.  All rights reserved.
#

. $STF_SUITE/include/libtest.shlib

#
# DESCRIPTION:
# Upgrading a read-only mounted filesystem to read/write should succeed
# when disks are in a degraded state.
#
# STRATEGY:
# 1. Mount file system ro
# 2. Upgrade to rw
# 3. Write a file.
#

DISK=${DISKS%% *}
create_pool $TESTPOOL "$DISK"
 
for i in 1 2 3; do
  dir=$TESTDIR.$i
  fs=$TESTPOOL/$TESTFS.$i

  log_must zfs create -o readonly=on $fs
  log_must mkdir -p $dir
  log_must zfs set mountpoint=$dir $fs

  log_must mounted $fs
done

# Degrade the pool.
# procfs/pool_state.ksh creates a degraded pool

read -r DISK1 _ <<<"$DISKS"
log_must zpool offline -tf $TESTPOOL $DISK1
#check_all $TESTPOOL "DEGRADED"
log_must zpool online $TESTPOOL $DISK1
log_must zpool clear $TESTPOOL

log_must zpool export $TESTPOOL
log_must zpool import -o readonly=on $TESTPOOL

log_must zpool set readonly=off $TESTPOOL

log_must printf "success" > $dir/TEST_FILE

# Cleanup

log_must destroy_pool $TESTPOOL

for i in 1 2 3; do
	dir=$TESTDIR.$i
	rm -rf $dir
done

log_pass "Filesystem successfully upgraded from ro->rw while degraded"
