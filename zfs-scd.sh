#!/bin/bash

# This is a wrapper script that launches zdb as a background task
# for spacemap corruption detection.

if [[ $EUID != 0 ]]; then
	echo "Error: This tool must be run as root or via sudo."
	exit 1
fi

MYDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGFILE="$MYDIR/scd-log-$(date +%Y%m%dT%H%M%S).log"

# Scan the local pool only, ignore cloud pools
# vSnap servers have a single local pool named vpool<N>

POOL=$(zpool list -H -o name | grep -E "^vpool" | head -n 1)
if [[ -z $POOL ]]; then
    echo "Error: No pools found."
    exit 1
fi

runScan() {
    echo "Hostname = $(hostname)"
    echo "Pool Status for $POOL: "
    zpool status $POOL
    echo "$(date): BEGIN scan for pool $POOL"
    $MYDIR/libs/zdb --allocation-scanner $POOL
    echo "$(date): END scan for pool $POOL"
}

# Run zdb as a detached background task and capture the output
set -m
runScan >>$LOGFILE 2>&1 &
set +m
pid=$!
disown $pid

echo
echo "Started background task with process ID $pid."
echo "Log file: $LOGFILE."
echo "It is safe to log out of the current session. The background process will continue."
echo "Run 'ps -f $pid' or 'ps -ef | grep allocation-scanner' to check if it is still running."
echo
