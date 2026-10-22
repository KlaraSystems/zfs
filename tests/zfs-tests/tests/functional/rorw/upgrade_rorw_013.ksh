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
# in the presence of active NFS mounts.
#
# STRATEGY:
# 1. Mount file system ro
# 2. Create a network mount.
# 3. Upgrade to rw
#

# !!!
# What happens to the network mount? It was presumably generated on a ro
# fs, will it care that the underlying system became writeable?  Will it
# upgrade itself?

log_pass "Filesystem successfully upgraded from ro to rw while NFS mounted"
