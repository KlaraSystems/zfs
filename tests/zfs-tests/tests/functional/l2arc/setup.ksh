#!/bin/ksh -p
# SPDX-License-Identifier: CDDL-1.0
#
# CDDL HEADER START
#
# This file and its contents are supplied under the terms of the
# Common Development and Distribution License ("CDDL"), version 1.0.
# You may only use this file in accordance with the terms of version
# 1.0 of the CDDL.
#
# A full copy of the text of the CDDL should have accompanied this
# source.  A copy of the CDDL is also available via the Internet at
# http://www.illumos.org/license/CDDL.
#
# CDDL HEADER END
#

#
# Copyright (c) 2020, George Amanakis. All rights reserved.
#

. $STF_SUITE/tests/functional/l2arc/l2arc.cfg

verify_runnable "global"

log_must rm -rf $VDIR
log_must mkdir -p $VDIR
log_must mkfile $SIZE $VDEV
log_must mkfile $SIZE $VDEV1

log_must save_tunable ARC_MAX
log_must save_tunable ARC_MIN
log_must set_tunable32 ARC_MIN $((128 * 1024 * 1024))
log_must set_tunable32 ARC_MAX $((1024 * 1024 * 1024))

log_pass
