#!/bin/bash

cd ${0%/*}

zpool list -H -o name |
	while read poolname
	do
		echo "hostname=$(hostname) pool=$poolname:"
		zpool status $poolname
		./zdb --allocation-scanner $poolname
	done
