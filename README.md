# ZFS SCD

## Build

We build only the userspace binaries and libraries without any kernel modules.

**Pre-reqs on RHEL 8:**

All pre-reqs are available from the standard repositories.

```
dnf install \
    git wget gcc make cmake autoconf automake libtool \
    libuuid-devel libblkid-devel libudev-devel libtirpc-devel \
    openssl-devel zlib-devel libaio-devel libattr-devel \
    elfutils-libelf-devel python3 python3-devel \
    elfutils chrpath rpm-build
```

**Pre-reqs on RHEL 9:**

One of the pre-req packages (`libtirpc-devel`) needs to be installed from the `codeready-builder` repository which is typically disabled by default on RHEL. You need to enable the repo or download the file manually from Red Hat. Refer to: https://access.redhat.com/solutions/7114696

Then install the rest of pre-reqs:

```
dnf install \
    git wget gcc make cmake autoconf automake libtool \
    libuuid-devel libblkid-devel libudev-devel \
    openssl-devel zlib-devel libaio-devel libattr-devel \
    elfutils-libelf-devel python3 python3-devel \
    elfutils chrpath rpm-build
```

**Run the build:**

Copy the current directory to the build system, and run the build script:

```
./build.sh
```

## Result

Some sample output when extracted on the target system:

```
$ pwd
/home/serveradmin/zfs-scd-20251015203858.el9

$ readelf -d libs/zdb | grep RPATH
 0x000000000000000f (RPATH)              Library rpath: [$ORIGIN]

$ ldd libs/zdb
    linux-vdso.so.1 (0x00007ffc68ffa000)
    libzpool.so.6 => /home/serveradmin/zfs-scd-20251015203858.el9/libs/libzpool.so.6 (0x00007f6681200000)
    libuuid.so.1 => /lib64/libuuid.so.1 (0x00007f6681787000)
    libblkid.so.1 => /lib64/libblkid.so.1 (0x00007f6681750000)
    libudev.so.1 => /lib64/libudev.so.1 (0x00007f66811cf000)
    libz.so.1 => /lib64/libz.so.1 (0x00007f66811b5000)
    libm.so.6 => /lib64/libm.so.6 (0x00007f66810da000)
    libzfs_core.so.3 => /home/serveradmin/zfs-scd-20251015203858.el9/libs/libzfs_core.so.3 (0x00007f668173e000)
    libnvpair.so.3 => /home/serveradmin/zfs-scd-20251015203858.el9/libs/libnvpair.so.3 (0x00007f66810c2000)
    libtirpc.so.3 => /lib64/libtirpc.so.3 (0x00007f6681092000)
    libcrypto.so.3 => /lib64/libcrypto.so.3 (0x00007f6680a00000)
    libc.so.6 => /lib64/libc.so.6 (0x00007f6680600000)
    /lib64/ld-linux-x86-64.so.2 (0x00007f668179a000)
    libgcc_s.so.1 => /lib64/libgcc_s.so.1 (0x00007f6681077000)
    libgssapi_krb5.so.2 => /lib64/libgssapi_krb5.so.2 (0x00007f668101e000)
    libkrb5.so.3 => /lib64/libkrb5.so.3 (0x00007f6680f43000)
    libk5crypto.so.3 => /lib64/libk5crypto.so.3 (0x00007f6680f2a000)
    libcom_err.so.2 => /lib64/libcom_err.so.2 (0x00007f6680f23000)
    libkrb5support.so.0 => /lib64/libkrb5support.so.0 (0x00007f66809ef000)
    libkeyutils.so.1 => /lib64/libkeyutils.so.1 (0x00007f6680f1a000)
    libresolv.so.2 => /lib64/libresolv.so.2 (0x00007f66809db000)
    libselinux.so.1 => /lib64/libselinux.so.1 (0x00007f66809ae000)
    libpcre2-8.so.0 => /lib64/libpcre2-8.so.0 (0x00007f6680912000)
```

