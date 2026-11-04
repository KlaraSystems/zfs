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

MODINFO=${MODINFO:-/sbin/modinfo}

#
# DESCRIPTION:
#
# After converting a pool RW->RO and exporting it, the ZFS kernel module
# can be unloaded (no leftover holds from the conversion path).
#
# STRATEGY:
# 1. Create a pool with mounted filesystems and convert it to readonly
# 2. Export the converted pool and the default test pool
# 3. Stop ZED and verify no other pools remain imported
# 4. Unload the ZFS kernel module stack, then reload it
# 5. Re-import the default test pool for subsequent tests
#

verify_runnable "global"

function zfs_module_loaded
{
	if is_linux; then
		[[ -d /sys/module/zfs ]]
	elif is_freebsd; then
		kldstat -q -n openzfs
	else
		return 1
	fi
}

function cleanup
{
	#
	# Always try to leave the module loaded and TESTPOOL imported so
	# later tests in this group are not broken.
	#
	if ! zfs_module_loaded; then
		log_must $ZFS_SH
	fi

	if ! poolexists $TESTPOOL; then
		log_must zpool import $TESTPOOL
	fi

	poolexists $TESTPOOL1 && destroy_pool $TESTPOOL1
	rm -f $FILEVDEV
}

log_assert "ZFS modules unload after RW->RO conversion and pool export"
log_onexit cleanup

if ! is_linux && ! is_freebsd; then
	log_unsupported "Module unload test supported on Linux and FreeBSD only"
fi

if ! zfs_module_loaded; then
	log_unsupported "ZFS is not a loadable kernel module"
fi

FILEVDEV="$TEST_BASE_DIR/zpool_set_readonly_006.$$.dat"
FS1=$TESTPOOL1/$TESTFS
FS2=$TESTPOOL1/${TESTFS}_2

log_must truncate -s $MINVDEVSIZE $FILEVDEV
log_must zpool create -O canmount=off $TESTPOOL1 $FILEVDEV
log_must zfs create $FS1
log_must zfs create $FS2
MNT1="$(get_prop mountpoint $FS1)"
MNT2="$(get_prop mountpoint $FS2)"
log_must touch $MNT1/file1 $MNT2/file2

log_must zpool set readonly=on $TESTPOOL1
log_must test "$(get_pool_prop readonly $TESTPOOL1)" == "on"
log_mustnot touch $MNT1/file1.new
log_mustnot touch $MNT2/file2.new

#
# Export the converted pool, then the default test pool so nothing holds
# the module.  Skip if unrelated pools (e.g. rpool) remain imported.
#
log_must_busy zpool export $TESTPOOL1
log_must_busy zpool export $TESTPOOL

typeset remaining
remaining="$(zpool list -H -o name 2>/dev/null)"
if [[ -n $remaining ]]; then
	log_must zpool import $TESTPOOL
	log_unsupported "Cannot unload zfs module; pools still imported: " \
	    "$remaining"
fi

zed_stop

log_must $ZFS_SH -u
if zfs_module_loaded; then
	log_fail "ZFS module still loaded after unload"
fi

while :
do
    log_must $ZFS_SH
    log_must zfs_module_loaded
    loaded_vers="$(cat /sys/module/zfs/version)"
    mod_vers="$($MODINFO -F version $KMOD_ZFS)"
    if [ "$loaded_vers" != "$mod_vers" ]
    then
        log_note "Wrong zfs.ko loaded: $loaded_vers but expecting $mod_vers; trying again"
        sleep 1
        log_must $ZFS_SH -u
    else
        break
    fi
done

log_must zpool import $TESTPOOL

log_pass "ZFS modules unload after RW->RO conversion and pool export"
