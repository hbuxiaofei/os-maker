#!/usr/bin/env bash

cd $(dirname $0)

TOP_DIR="${PWD}"
MOD_CODE_DIR="${TOP_DIR}/.mod-code"

NR_CPU=`grep -c ^processor /proc/cpuinfo 2>/dev/null`

VAR_CROSS_COMPILE="aarch64-none-linux-gnu-"

pushd ${MOD_CODE_DIR}/busybox

    [ ! -d _install ] && \
        make CROSS_COMPILE=${VAR_CROSS_COMPILE} -j $NR_CPU && \
        make install CROSS_COMPILE=${VAR_CROSS_COMPILE}

    [ -d rootfs ] && rm -rf rootfs
    [ -e rootfs.gz ] && rm -rf rootfs.gz
    mkdir rootfs

    cp -rf _install/* rootfs/

popd


pushd ${MOD_CODE_DIR}/busybox/rootfs

    mkdir -p {boot,lib64,etc/init.d,dev,proc,sys,tmp}
    cp -a /dev/{null,console,tty,tty1,tty2,tty3,tty4} dev/
    rm -f linuxrc
    cat > etc/inittab <<EOF
::sysinit:/etc/init.d/rcS
ttyS0::respawn:-/bin/sh
tty1::respawn:-/bin/sh
tty2::askfirst:-/bin/sh
tty3::askfirst:-/bin/sh
EOF

    cat > etc/fstab <<EOF
proc      /proc    proc      defaults    0        0
tmpfs     /tmp     tmpfs     defaults    0        0
sysfs     /sys     sysfs     defaults    0        0
EOF

    cat > init <<EOF
#!/bin/busybox sh
exec /sbin/init
EOF

    chmod a+x init

    cat > etc/init.d/rcS <<EOF
mount -a
mkdir /dev/pts
mount -t devpts devpts /dev/pts
if [ -e /dev/mmcblk0p1 ]; then
    mount /dev/mmcblk0p1 /boot
elif [ -e /dev/mmcblk1p1 ]; then
    mount /dev/mmcblk1p1 /boot
fi
# echo /sbin/mdev > /proc/sys/kernel/hotplug
/sbin/mdev -s
# /usr/sbin/depmod -a
echo -e "\n\t\tWelcome to Cute Linux !\n"
EOF
    chmod a+x etc/init.d/rcS

    find . -print0 | cpio --null -ov --format=newc | gzip -9 > ../rootfs.gz

popd