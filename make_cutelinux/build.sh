#!/bin/bash

set -e

EXEC_NAME="build.sh"
NR_CPU=`grep -c ^processor /proc/cpuinfo`
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
            git clone https://github.com/hbuxiaofei/syslinux.git
        fi
        if [ ! -d busybox ]; then
            git clone https://github.com/mirror/busybox.git -b 1_35_0
        fi
        if [ ! -d kernel ]; then
            git clone https://github.com/hbuxiaofei/linux-2.6.38-study.git kernel
        fi
    popd
}

function make_drivers()
{
    local _install_dir="$1"
    make
    find drivers -name "*.ko" | xargs -i cp --parents {} $_install_dir
    find drivers -name "*-test" | xargs -i cp --parents {} $_install_dir
}

function do_mkcute()
{
    local _iso_name=$1
    local _mod_code_dir=$MOD_CODE_DIR
    local _kernel_version="xxx"

    make_prepare

    pushd $_mod_code_dir/syslinux
        [ ! -e bios/com32/menu/vesamenu.c32 ] && make -j $NR_CPU bios
    popd

    [ ! -e $_mod_code_dir/busybox/.config ] && cp -f busybox.config $_mod_code_dir/busybox/.config
    pushd $_mod_code_dir/busybox
        [ ! -d _install ] && make -j $NR_CPU && make install
    popd

    pushd $_mod_code_dir/busybox
        [ -d rootfs ] && rm -rf rootfs
        [ -e rootfs.gz ] && rm -rf rootfs.gz
        mkdir rootfs
        cp -rf _install/* rootfs/
    popd

    [ ! -e $_mod_code_dir/kernel/.config ] && cp -f kernel.config $_mod_code_dir/kernel/.config
    pushd $_mod_code_dir/kernel
        [ ! -e arch/x86/boot/bzImage ] && LOCALVERSION= make -j $NR_CPU bzImage
    popd

    _kernel_version=$(cat $_mod_code_dir/kernel/include/config/kernel.release 2> /dev/null)

    pushd $_mod_code_dir/busybox/rootfs
        mkdir -p lib/modules/${_kernel_version}/kernel
    popd

    make_drivers "$_mod_code_dir/busybox/rootfs/lib/modules/${_kernel_version}/kernel/"

    pushd $_mod_code_dir/busybox/rootfs
        mkdir -p {etc/init.d,dev,proc,sys,tmp}
        cp -a /dev/{null,console,tty,tty1,tty2,tty3,tty4} dev/
        rm -f linuxrc
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
LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/lib:/usr/lib
export LD_LIBRARY_PATH
mount -a
mkdir /dev/pts
mount -t devpts devpts /dev/pts
echo /sbin/mdev > /proc/sys/kernel/hotplug
/sbin/mdev -s
echo -e "Welcome to Cute Linux"
EOF
        chmod a+x etc/init.d/rcS
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
    append initrd=rootfs.gz vga=792
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

