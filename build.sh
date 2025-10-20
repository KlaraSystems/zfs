#!/bin/bash

MYDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

function getParam {
	name=$1
	currentValue=$2
	defaultValue=$3
	# If already set, return it
	if [[ -n $currentValue ]]; then
		echo "$currentValue"
		return
	fi
	# If not set, prompt for it
	read -r -p "$name [$defaultValue]: " newValue
	if [[ -z $newValue ]]; then
		echo "$defaultValue"
		return
	else
		echo "$newValue"
		return
	fi
}

ZFS_CLONE_URL=$(getParam "ZFS_CLONE_URL" "${ZFS_CLONE_URL}" "https://github.com/KlaraSystems/zfs.git")
ZFS_CLONE_BRANCH=$(getParam "ZFS_CLONE_BRANCH" "${ZFS_CLONE_BRANCH}" "i-2.3.4-scd-tool")
SCD_BUILD_VERSION=$(getParam "SCD_BUILD_VERSION" "${SCD_BUILD_VERSION}" $(date -u +%Y%m%d%H%M%S))

echo
echo "============================================================"
echo "URL:      $ZFS_CLONE_URL"
echo "Branch:   $ZFS_CLONE_BRANCH"
echo "Version:  $SCD_BUILD_VERSION"
echo "============================================================"
echo

set -e
set -x

# Create a workspace
WORKSPACE="/tmp/zfsbuild"
if [[ -d $WORKSPACE ]]; then
	rm -rf $WORKSPACE
fi
mkdir -p $WORKSPACE
mkdir -p $WORKSPACE/dist

# Clone the repo and checkout the branch
cd $WORKSPACE
git clone ${ZFS_CLONE_URL} zfs
cd zfs
git checkout ${ZFS_CLONE_BRANCH}

# Build the components
git clean -fdx
sh autogen.sh
./configure --enable-debug --enable-debuginfo --with-config=user
make

#-----------------------------------------------------------------------------
# At this point, on the build system we have a temporary `zdb` wrapper script 
# in the current directory, and a `zdb` binary in the `.libs/` directory. The 
# wrapper script is designed to manipulate the rpath in the binary to make it 
# usable on the build system. We will disregard that and manipulate the rpath 
# ourselves using the `chrpath` command. The `zdb` binary depends on some 
# zfs-specific shared libs (like libnvpair, libzpool, etc) and some 
# external/system libs (like libuuid, libudev, etc). We can safely assume 
# that the external libs will already be present on the target system. But 
# the zfs libs on the target are likely to be from an older version whereas 
# we want to use the newer libs that we have just built. So we'll package the 
# `zdb` binary plus the zfs-specific libs in a standalone directory, and set 
# the rpath in the binary to '$ORIGIN' which tells the linker to look for 
# libs in its own directory first.
#-----------------------------------------------------------------------------

distSuffix=$(rpm -E '%dist') # Value will be .el8 or .el9 depending on platform
distName="zfs-scd-${SCD_BUILD_VERSION}${distSuffix}"

# Create a target directory for the portable distribution
mkdir -p $WORKSPACE/dist/${distName}

# Create a libs subdirectory
mkdir -p $WORKSPACE/dist/${distName}/libs

# Copy the built zdb binary to it
cp .libs/zdb $WORKSPACE/dist/${distName}/libs/

# Copy all the zfs shared libs to it
cp -a .libs/lib*.so* $WORKSPACE/dist/${distName}/libs/

# Patch the zdb binary by changing its rpath to $ORIGIN i.e. its own directory
chrpath -r '$ORIGIN' $WORKSPACE/dist/${distName}/libs/zdb

# The 'scd' wrapper script provided by Klara scans all pools,
# but on vSnap servers we want to ignore any cloud pools and 
# only scan the local pool. We also want to run the scan as a 
# background task and collect the output in a file. We use our
# own wrapper script for all that. Copy it to the target dir.
cp $MYDIR/zfs-scd.sh $WORKSPACE/dist/${distName}/

# Create a tar.gz archive of the distribution.
cd $WORKSPACE/dist
tar -czvf ${distName}.tar.gz ${distName}/

set +e
set +x

echo "============================================================"
echo "Output: $WORKSPACE/dist/${distName}.tar.gz"
echo "============================================================"

