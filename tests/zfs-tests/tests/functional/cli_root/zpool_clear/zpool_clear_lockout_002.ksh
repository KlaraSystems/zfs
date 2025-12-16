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
# Use 'zpool clear -R' to force an imported pool to read-only.
#
# STRATEGY:
# 1. Create a pool.
# 2. Create a file on the pool
# 3. Run 'zpool clear -R' on the pool
# 4. Export pool.
#

verify_runnable "global"

function cleanup
{
	destroy_pool $TESTPOOL1
	rm -f $TESTDIR/file1
}

log_assert "Verify 'zpool clear -R' runs without failure"
log_onexit cleanup

# 1. Create a pool.
log_must truncate -s $FILESIZE $TESTDIR/file1
log_must zpool create $TESTPOOL1 $TESTDIR/file1

# 2. Create a file on the pool
log_must touch /${TESTPOOL1}/empty.bin

# 3. Run 'zpool clear -R' on the pool.
log_must zpool clear -R $TESTPOOL1

# 4. Export pool
log_must zpool export $TESTPOOL1

log_pass "'zpool clear -R' with empty file succeeds as expected."
