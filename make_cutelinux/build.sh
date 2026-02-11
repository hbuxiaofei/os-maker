#!/bin/bash

set -e

EXEC_NAME="build.sh"
IN_ARGS=`getopt -o ho: --long help,out: -n 'build.sh' -- "$@"`
GETOPT_RET=$?

function do_usage()
{
    cat <<EOF
Usage: $EXEC_NAME <command> [args...]
  command:
    prepare     Prepare for making iso
    mkiso       Only make a Cute Linux iso
  args:
    -h, --help  Show this help message
    -o, --out   Out iso name
Example:
  $EXEC_NAME prepare
  $EXEC_NAME mkiso --out=iso
EOF
}

if [ $GETOPT_RET != 0 ]; then
    echo "Terminating..."
    do_usage
    exit 1
fi

eval set -- "${IN_ARGS}"

ARGS_EXP=""
ARG_OUT_ISO="out.iso"

while true; do
    case "$1" in
        -h|--help)
            do_usage
            exit 0
            ;;
        -o|--out)
            ARG_OUT_ISO="$(echo $2 | sed 's/^=//')"
            echo "[Info] Out iso file: ARG_OUT_ISO=$ARG_OUT_ISO"
            shift 2
            ;;
        --)
            shift 1
            break
            ;;
        *)
            echo "[Err] Internal error!"
            exit 1
            ;;
    esac
done
ARGS_EXP="$@"
echo "[Info] Auto package args: ARGS_EXP=$ARGS_EXP"

cd $(dirname $0)
ISO_BASE_DIR="${PWD}/iso-base"
MOD_CODE_DIR="${PWD}/.mod-code"

function make_prepare()
{
    local _mod_code_dir=$MOD_CODE_DIR

    if [ ! -d $_mod_code_dir ]; then
        mkdir -p $_mod_code_dir
    fi

    pushd $_mod_code_dir
        if [ ! -d syslinux ]; then
            git clone https://github.com/hbuxiaofei/syslinux.git -b centos7
        fi
        if [ ! -d busybox ]; then
            git clone https://github.com/mirror/busybox.git -b 1_35_0
        fi
        if [ ! -d kernel ]; then
            git clone https://github.com/hbuxiaofei/linux-2.6.38-study.git -b 3.10 kernel
        fi
    popd
}

function make_drivers()
{
    local _kernel_dir="$1"
    local _install_dir="${_kernel_dir}/kernel/"
    make all-drivers
    find drivers -name "*.ko" | xargs -i cp --parents {} $_install_dir
    find drivers -name "*-test" | xargs -i cp --parents {} $_install_dir

    pushd $_mod_code_dir/kernel
        find drivers -name "virtio.ko" | xargs -i cp --parents {} $_install_dir
        find drivers -name "virtio_pci.ko" | xargs -i cp --parents {} $_install_dir
        find drivers -name "virtio_ring.ko" | xargs -i cp --parents {} $_install_dir
        find drivers -name "virtio_scsi.ko" | xargs -i cp --parents {} $_install_dir
        find drivers -name "virtio_blk.ko" | xargs -i cp --parents {} $_install_dir
        find drivers -name "e1000.ko" | xargs -i cp --parents {} $_install_dir
    popd

    pushd $_mod_code_dir/kernel
       [ -e modules.builtin ] && cp -f modules.builtin ${_kernel_dir}/
       [ -e modules.order ] && cp -f modules.order ${_kernel_dir}/
       [ -e Module.symvers ] && cp -f Module.symvers ${_kernel_dir}/
       [ -e System.map ] && cp -f System.map ${_kernel_dir}/
     popd
}

function make_tools()
{
    local _install_dir="$1/"
    make all-tools
    find tools -name "*.bin" | xargs -i cp --parents {} $_install_dir
    find tools -name "*-test.sh" | xargs -i cp --parents {} $_install_dir
}

function install_bin()
{
    local _rootfs_dir=$1
    pushd $_rootfs_dir
        while read _bin; do
            [ -z "$_bin" ] && continue
            if [ ! -e "$_bin" ]; then
                echo "[Warn] file $_bin not found" >&2
                continue
            fi
            _bin_dir="${_bin%/*}"
            _bin_dir="${_bin_dir#*/}"
            [ -z "$_bin_dir" ] && continue
            [ ! -d "$_bin_dir" ] && mkdir -p $_bin_dir
            cp -f ${_bin} ${_bin_dir}/
        done << EOF
/lib64/ld-linux-x86-64.so.2
/lib64/libc.so.6
/lib64/libm.so.6
/lib64/libresolv.so.2
/lib64/libtinfo.so.5
/lib64/libdl.so.2
/lib64/libblkid.so.1
/lib64/libmount.so.1
/lib64/libuuid.so.1
/lib64/libselinux.so.1
/lib64/libudev.so.1
/lib64/libpcre.so.1
/lib64/librt.so.1
/lib64/libcap.so.2
/lib64/libdw.so.1
/lib64/libgcc_s.so.1
/lib64/libpthread.so.0
/lib64/libattr.so.1
/lib64/libelf.so.1
/lib64/libz.so.1
/lib64/liblzma.so.5
/lib64/libbz2.so.1
/lib64/libpci.so.3
/lib64/libkmod.so.2
/lib64/libutil.so.1
/lib64/libbfd-2.27-44.base.el7.so
/lib64/libopcodes-2.27-44.base.el7.so
/lib64/libpopt.so.0
/lib64/libgmp.so.10
/lib64/libmpfr.so.4
/lib64/libmpc.so.3
/lib64/libacl.so.1
/lib64/libsmartcols.so.1
/usr/lib64/libmagic.so.1
/usr/lib64/libdl.so.2

/sbin/lspci
/usr/sbin/depmod
/bin/ldd
/bin/lsblk
/bin/bash
/usr/bin/file
/usr/bin/rsync
/usr/bin/dmesg
/usr/bin/lscpu

/usr/share/misc/magic
/usr/share/misc/magic.mgc
EOF
    popd
}

function do_mkcute()
{
    local _iso_name=$1
    local _mod_code_dir=$MOD_CODE_DIR
    local _kernel_version="xxx"
    local _need_build_kernel=0

    make_prepare

    pushd $_mod_code_dir/syslinux
        [ ! -e bios/com32/menu/vesamenu.c32 ] && make -j $(nproc) bios
    popd

    [ ! -e $_mod_code_dir/busybox/.config ] && cp -f busybox.config $_mod_code_dir/busybox/.config
    pushd $_mod_code_dir/busybox
        [ ! -d _install ] && make -j $(nproc) && make install
    popd

    pushd $_mod_code_dir/busybox
        [ -d rootfs ] && rm -rf rootfs
        [ -e rootfs.gz ] && rm -rf rootfs.gz
        mkdir rootfs
        cp -rf _install/* rootfs/
    popd

    [ ! -e $_mod_code_dir/kernel/.config ] && cp -f kernel3.10.config $_mod_code_dir/kernel/.config
    pushd $_mod_code_dir/kernel
        [ ! -e vmlinux ] && _need_build_kernel=1
        [ ! -e modules.order ] && _need_build_kernel=1
        [ ! -e arch/x86/boot/bzImage ] && _need_build_kernel=1
        if [ ${_need_build_kernel} -eq 1 ]; then
            LOCALVERSION= make -j $(nproc) vmlinux
            LOCALVERSION= make -j $(nproc) modules
            LOCALVERSION= make -j $(nproc) bzImage
        fi
    popd

    _kernel_version=$(cat $_mod_code_dir/kernel/include/config/kernel.release 2> /dev/null)

    pushd $_mod_code_dir/busybox/rootfs
        mkdir -p lib/modules/${_kernel_version}/kernel
    popd

    install_bin "$_mod_code_dir/busybox/rootfs"

    make_drivers "$_mod_code_dir/busybox/rootfs/lib/modules/${_kernel_version}"

    make_tools "$_mod_code_dir/busybox/rootfs/usr/sbin"

    pushd $_mod_code_dir/busybox/rootfs
        mkdir -p {etc/init.d,etc/rcS.d,etc/network,dev,proc,sys,tmp,mnt}
        mkdir -p usr/share/udhcpc
        cp $_mod_code_dir/busybox/examples/udhcp/simple.script usr/share/udhcpc/default.script
        chmod +x usr/share/udhcpc/default.script
        cp -a /dev/{null,console,tty,tty1,tty2,tty3,tty4} dev/
        rm -f linuxrc
        cat > etc/inittab <<EOF
::sysinit:/etc/init.d/rcS
ttyS0::respawn:-/bin/sh
tty1::respawn:-/bin/sh
tty2::askfirst:-/bin/bash
tty3::askfirst:-/bin/bash
EOF
        cat > etc/passwd <<EOF
root::0:0:root:/:/bin/sh
EOF
        cat > etc/fstab <<EOF
proc      /proc    proc      defaults    0        0
tmpfs     /tmp     tmpfs     defaults    0        0
sysfs     /sys     sysfs     defaults    0        0
EOF
        cat > etc/rsyncd.conf <<EOF
uid = 0
gid = 0
port = 873
fake super = yes
[share]
    path = /tmp
    read only = no
    comment = rsync share
EOF
        cat > etc/network/interfaces <<EOF
auto eth0
iface eth0 inet dhcp
EOF
        cat > init <<EOF
#!/bin/busybox sh
exec /sbin/init
EOF
        chmod a+x init
        cat > etc/init.d/rcS <<EOF
LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/lib:/usr/lib
export LD_LIBRARY_PATH
mount -a
mkdir /dev/pts
mount -t devpts devpts /dev/pts
echo /sbin/mdev > /proc/sys/kernel/hotplug
/sbin/mdev -s
/usr/bin/clear
/usr/sbin/depmod -a
modprobe e1000
udhcpc
telnetd
rsync --daemon
exec /etc/init.d/rc S
echo -e "\n\t\tWelcome to Cute Linux !\n"
EOF
        chmod a+x etc/init.d/rcS
        cat > etc/init.d/rc <<EOF
#!/bin/sh
scriptname="\$0"
runlevel=\$RUNLEVEL
[ "\$1" != "" ] && runlevel=\$1
if [ "\$runlevel" = "" ]; then
    echo "Usage: \$scriptname <runlevel>" >&2
    exit 1
fi
if [ -d /etc/rc\$runlevel.d ]; then
    for s in /etc/rc\$runlevel.d/S*; do
        /bin/sh \$s
    done
fi
EOF
        chmod a+x etc/init.d/rc
        cat > etc/rcS.d/S30custom <<EOF
#!/bin/sh

ln -sf /usr/bin/dmesg /bin/dmesg

EOF
        find . -print0 | cpio --null -ov --format=newc | gzip -9 > ../rootfs.gz
    popd

    [ -d linux-iso ] && rm -rf linux-iso
    mkdir linux-iso

    cp $_mod_code_dir/busybox/rootfs.gz linux-iso/

    # echo "default vmlinuz initrd=rootfs.gz" > linux-iso/isolinux.cfg
    cat > linux-iso/isolinux.cfg <<EOF
default vesamenu.c32
timeout 50
menu clear
label Cute Linux
    kernel bzImage
    append initrd=rootfs.gz quiet splash nokaslr console=ttyS0
EOF

    cp $_mod_code_dir/kernel/arch/x86/boot/bzImage linux-iso/
    cp $_mod_code_dir/busybox/rootfs.gz linux-iso/

    cp $_mod_code_dir/syslinux/bios/core/isolinux.bin linux-iso/
    cp $_mod_code_dir/syslinux/bios/com32/menu/vesamenu.c32 linux-iso/
    cp $_mod_code_dir/syslinux/bios/com32/elflink/ldlinux/ldlinux.c32 linux-iso/
    cp $_mod_code_dir/syslinux/bios/com32/lib/libcom32.c32 linux-iso/
    cp $_mod_code_dir/syslinux/bios/com32/libutil/libutil.c32 linux-iso/

    [ -e $_iso_name ] && rm -f $_iso_name
    pushd linux-iso
        # xorriso -as mkisofs -o ../$_iso_name -b isolinux.bin -c boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table ./
        mkisofs -R -b isolinux.bin -no-emul-boot -boot-load-size 4 -boot-info-table -o ../$_iso_name ./
    popd

    implantisomd5 $_iso_name
}

if [ "X$ARGS_EXP" == "Xprepare" ]; then
    make_prepare
elif [ "X$ARGS_EXP" == "Xmkiso" ]; then
    do_mkcute "$ARG_OUT_ISO"
else
    echo "[Err] Args unknown: $ARGS_EXP"
    do_usage
fi

