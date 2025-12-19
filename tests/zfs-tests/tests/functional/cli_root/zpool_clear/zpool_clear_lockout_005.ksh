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
# Copyright 2017, loli10K <ezomori.nozomu@gmail.com>. All rights reserved.
#

. $STF_SUITE/include/libtest.shlib
. $STF_SUITE/tests/functional/cli_root/zpool_clear/zpool_clear.cfg

#
# DESCRIPTION:
# Use 'zpool clear -R' to force a pool read-only, and check write counts
# before and after to ensure no change.
#
# STRATEGY:
# 1. Create a pool.
# 2. Write some data to the pool.
# 3. Sync the pool.
# 4. Get the write count for the pool.
# 5. Force the pool read-only using "zpool -R clear"
# 6. Get the write count for the pool again.
# 7. Compare the two write counts to ensure they match.
# 8. Export the pool.
#

verify_runnable "global"

function cleanup
{
	destroy_pool $TESTPOOL1
	rm -f $TESTDIR/file1
}

log_assert "Verify writes stop after 'zpool clear -R'"
log_onexit cleanup

# 1. Create a pool.
log_must truncate -s $FILESIZE $TESTDIR/file1
log_must zpool create -f $TESTPOOL1 $TESTDIR/file1

# 2. Write some data to the pool.
log_must write_compressible /$TESTPOOL1 16 5

# 3. Sync the pool
log_must zpool sync $TESTPOOL1

# 4. Get the write count for the pool
pre_lock=$(zpool get -Hp -o value write_ops $TESTPOOL1 $TESTDIR/file1)

# 5. Force the pool read-only using "zpool -R clear"
log_must zpool clear -R $TESTPOOL1

# 6. Get the write count for the pool again
sleep 0.5
post_lock=$(zpool get -Hp -o value write_ops $TESTPOOL1 $TESTDIR/file1)

# 7. Compare the two counts to ensure they match

log_must test "$pre_lock" -eq "$post_lock"

# 8. Export the pool.
log_must zpool export $TESTPOOL1

log_pass "Locked out pool write count stops incrementing"

