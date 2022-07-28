#!/bin/bash

set -e

EXEC_NAME="build.sh"
IN_ARGS=`getopt -o hi:o: --long help,iso:,out: -n 'build.sh' -- "$@"`
GETOPT_RET=$?

function do_usage()
{
    cat <<EOF
Usage: $EXEC_NAME <command> [args...]
  command:
    base        Prepare base iso
    mkiso       Only make iso from iso base directory
    mkcute      Only make cute iso from iso base directory
  args:
    -h, --help  Show this help message
    -i, --iso   Input iso file, using for making base
    -o, --out   Out iso name
Example:
  $EXEC_NAME mkiso
  $EXEC_NAME base --iso=input.iso
  $EXEC_NAME mkiso --out=iso
  $EXEC_NAME mkcute --out=iso
EOF
}

if [ $GETOPT_RET != 0 ]; then
    echo "Terminating..."
    do_usage
    exit 1
fi

eval set -- "${IN_ARGS}"

ARGS_EXP=""
ARG_INPUT_ISO="input.iso"
ARG_OUT_ISO="out.iso"

while true; do
    case "$1" in
        -h|--help)
            do_usage
            exit 0
            ;;
        -i|--iso)
            ARG_INPUT_ISO="$(echo $2 | sed 's/^=//')"
            echo "[Info] In iso file: ARG_INPUT_ISO=$ARG_INPUT_ISO"
            shift 2
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

function make_iso_base()
{
    local _input_iso=$1
    local _cdrom_dir="/mnt/iso-base"
    local _iso_base_dir=$ISO_BASE_DIR

    if [ ! -f $_input_iso ]; then
        echo "[Err] In iso is not exist..."
        exit 1
    fi

    [ -d $_iso_base_dir ] && rm -rf $_iso_base_dir
    mkdir -p $_iso_base_dir

    [ -d $_cdrom_dir ] && rm -rf $_cdrom_dir
    mkdir -p $_cdrom_dir

    mount -o loop $_input_iso $_cdrom_dir

    pushd $_cdrom_dir
    tar -cvf /tmp/iso-base.tar .
    popd
    umount $_cdrom_dir
    tar -xvf /tmp/iso-base.tar -C $_iso_base_dir
    rm -rf /tmp/iso-base.tar
    rm -rf $_cdrom_dir
}

function do_mkisofs()
{
    local _iso_name=$1
    local _iso_dir=$2
    local _product_name=""

    /bin/bash iso/build.sh "$_iso_dir"

    # CentOS-7-x86_64-Minimal-2009.iso
    # 07b94e6b1a0b0260b94c83d6bb76b26bf7a310dc78d7a9c7432809fb9bc6194a
    _product_name="CentOS 7 x86_64"

    [ -e "$_iso_name" ] && rm -rf $_iso_name

    genisoimage -U -r -v -T -J -joliet-long -V "$_product_name" \
        -volset "$_product_name" -A "$_product_name" \
        -b isolinux/isolinux.bin -c isolinux/boot.cat\
        -no-emul-boot -boot-load-size 4 -boot-info-table -eltorito-alt-boot \
        -e images/efiboot.img -no-emul-boot -o "$_iso_name" "$_iso_dir"

    [ -d "$_iso_dir" ] && rm -rf $_iso_dir

    implantisomd5 $_iso_name
}

function do_mkcute()
{
    local _iso_name=$1
    local _iso_base_dir=$ISO_BASE_DIR

    if [ ! -d busybox ]; then
        git clone https://github.com/mirror/busybox.git -b 1_35_0
    fi

    [ ! -e busybox/.config ] && cp -f busybox.config busybox/.config
    pushd busybox
        [ ! -d _install ] && make install
        [ -d rootfs ] && rm -rf rootfs
        [ -e rootfs.gz ] && rm -rf rootfs.gz
        mkdir rootfs
        cp -rf _install/* rootfs/
        pushd rootfs
            mkdir -p {etc/init.d,dev,proc,sys}
            cp -a /dev/{null,console,tty,tty1,tty2,tty3,tty4} dev/
            rm -f linuxrc
            cat > init <<EOF
#!/bin/busybox sh
mount -t proc none /proc
mount -t sysfs none /sys
exec /sbin/init
EOF
            chmod a+x init
            cat > etc/init.d/rcS <<EOF
echo -e "Welcome to Cute Linux"
EOF
            chmod a+x etc/init.d/rcS
            find . -print0 | cpio --null -ov --format=newc | gzip -9 > ../rootfs.gz
        popd
    popd
    [ -d linux-iso ] && rm -rf linux-iso
    mkdir linux-iso

    cp busybox/rootfs.gz linux-iso/
    cp $_iso_base_dir/isolinux/isolinux.bin linux-iso/
    cp $_iso_base_dir/isolinux/vesamenu.c32 linux-iso/
    cp $_iso_base_dir/isolinux/vmlinuz linux-iso/
    # echo "default vmlinuz initrd=rootfs.gz" > linux-iso/isolinux.cfg
    cat > linux-iso/isolinux.cfg <<EOF
default vesamenu.c32
timeout 50
label Cute Linux
    kernel vmlinuz
    append initrd=rootfs.gz
EOF

    [ -e $_iso_name ] && rm -f $_iso_name
    pushd linux-iso
        # xorriso -as mkisofs -o ../$_iso_name -b isolinux.bin -c boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table ./
        mkisofs -R -b isolinux.bin -no-emul-boot -boot-load-size 4 -boot-info-table -o ../$_iso_name ./
    popd
}

if [ "X$ARGS_EXP" == "Xbase" ]; then
    make_iso_base "$ARG_INPUT_ISO"
elif [ "X$ARGS_EXP" == "Xmkiso" ]; then
    do_mkisofs "$ARG_OUT_ISO" "$ISO_BASE_DIR"
elif [ "X$ARGS_EXP" == "Xmkcute" ]; then
    do_mkcute "$ARG_OUT_ISO"
else
    echo "[Err] Args unknown: $ARGS_EXP"
    do_usage
fi
