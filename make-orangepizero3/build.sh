#!/bin/bash

set -e

EXEC_NAME="build.sh"
NR_CPU=`grep -c ^processor /proc/cpuinfo 2>/dev/null`
IN_ARGS=`getopt -o ho:s: --long help,out:,size: -n 'build.sh' -- "$@"`
GETOPT_RET=$?

function do_usage()
{
    cat <<EOF
Usage: $EXEC_NAME <command> [args...]
  command:
    prepare     Prepare source code
    compile     Compile all
    disk        Create disk
    all         Build all by one command
  args:
    -h, --help  Show this help message
    -s, --size  Disk size (M bytes)
    -o, --out   Out disk name
Example:
  $EXEC_NAME prepare
  $EXEC_NAME compile
  $EXEC_NAME disk <--out=disk.img> <--size=500>
  $EXEC_NAME all <--out=disk.img> <--size=500>
EOF
}

if [ $GETOPT_RET != 0 ]; then
    echo "Terminating..."
    do_usage
    exit 1
fi

eval set -- "${IN_ARGS}"

ARGS_EXP=""
ARG_DISK_NAME="orangepi-zero3.img"
ARG_DISK_SIZE=500

while true; do
    case "$1" in
        -h|--help)
            do_usage
            exit 0
            ;;
        -o|--out)
            ARG_DISK_NAME="$(echo $2 | sed 's/^=//')"
            echo "[Info] Out disk name: ARG_DISK_NAME=$ARG_DISK_NAME"
            shift 2
            ;;
        -s|--size)
            ARG_DISK_SIZE="$(echo $2 | sed 's/^=//')"
            echo "[Info] disk size: ARG_DISK_SIZE=$ARG_DISK_SIZE"
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
echo "[Info] args except: ARGS_EXP=$ARGS_EXP"


cd $(dirname $0)

TOP_DIR="${PWD}"

G_CROSS_NAME="aarch64-none-linux-gnu"
export G_CROSS_NAME

G_CROSS_DIR="/usr/local/bin/gcc-arm-11.2-2022.02-x86_64-${G_CROSS_NAME}"
export G_CROSS_DIR

VAR_CROSS_DIR=${G_CROSS_DIR}
VAR_CROSS_BIN="${VAR_CROSS_DIR}/bin"
VAR_CROSS_COMPILE="${G_CROSS_NAME}-"

MOD_CODE_DIR="${TOP_DIR}/third-party/.mod-code"

PATH=$PATH:${VAR_CROSS_BIN}
PATH=$PATH:${MOD_CODE_DIR}/u-boot/tools
export PATH


if [[ "$ARG_DISK_SIZE" =~ ^[0-9]+$ ]]; then
    if [ $ARG_DISK_SIZE -lt 50 ]; then
        echo "[Err] ARG_DISK_SIZE($ARG_DISK_SIZE) is less than 50"
        exit 1
    fi
else
    echo "[Err] ARG_DISK_SIZE($ARG_DISK_SIZE) is not number"
    exit 1
fi

tools_compile()
{
    make all-tools
}

drivers_compile()
{
    make all-drivers
}

do_compile()
{
    drivers_compile
    tools_compile
}

third_install()
{
    local _ins_dir="$1"
    local _out_3rd_usr="${PWD}/third-party/out/rootfs"
    [ -d ${_out_3rd_usr} ] && cp -rf ${_out_3rd_usr}/* ${_ins_dir}/
}

tools_install()
{
    local _ins_dir="$1"
    local _tools_dir="${TOP_DIR}/tools"
    local _ins_usr_bin="${_ins_dir}/usr/bin"

    if [ -d ${_ins_usr_bin} ]; then
        cp -f ${_tools_dir}/ldd ${_ins_usr_bin}/
        cp -f ${_tools_dir}/gpio/gpio ${_ins_usr_bin}/
    fi
}

drivers_install()
{
    local _disk_mnt="$1"
    local _kernel_dir="${MOD_CODE_DIR}/kernel"
    local _install_dir="$_disk_mnt/lib/modules/6.1.31+/kernel"
    if [ -z "${_disk_mnt}" ] || [ ! -d ${_disk_mnt} ]; then
        echo "[Err] disk rootfs($_disk_mnt) missing"
        return 1
    fi
    [ ! -d ${_install_dir} ] && mkdir -p ${_install_dir}
    find drivers -name "*.ko" | xargs -i cp -f --parents {} $_install_dir
    find drivers -name "*-test" | xargs -i cp -f --parents {} $_install_dir
}

do_disk()
{
    local _disk_name="${PWD}/$ARG_DISK_NAME"
    local _disk_mnt="${_disk_name}.mnt"
    local _disk_size="$ARG_DISK_SIZE"
    local _out_3rd="${PWD}/third-party/out"

    local _boot_start=40960                         # 跳过前 20M
    local _boot_end="$(expr ${_disk_size} \* 1024)" # 磁盘一半位置
    [ $_boot_end -gt 204800 ] && _boot_end=204800   # 最大 100M

    local _root_start="$(expr $_boot_end + 1)"

    [ -e ${_disk_name} ] && rm -rf ${_disk_name}
    dd if=/dev/zero of=${_disk_name} bs=1M count=${_disk_size}

    if [ -e ${_out_3rd}/u-boot/u-boot-sunxi-with-spl.bin ]; then
        dd if=${_out_3rd}/u-boot/u-boot-sunxi-with-spl.bin of=${_disk_name} bs=1k seek=8 conv=notrunc
    fi

    fdisk ${_disk_name} << EOF
n
p
1
${_boot_start}
${_boot_end}
w
EOF
    fdisk ${_disk_name} << EOF
n
p
2
${_root_start}

w
EOF

    losetup -d /dev/loop1 || true
    losetup -P /dev/loop1 ${_disk_name}
    fdisk -l /dev/loop1

    [ -d ${_disk_mnt} ] && rm -rf ${_disk_mnt}
    mkdir -p ${_disk_mnt}

    mkfs.fat /dev/loop1p1
    mount /dev/loop1p1 ${_disk_mnt}
    [ -d ${_out_3rd}/boot ] && cp -rf ${_out_3rd}/boot/* ${_disk_mnt}/
    umount /dev/loop1p1

    mkfs.ext4 -F /dev/loop1p2
    mount /dev/loop1p2 ${_disk_mnt}
    if [ -e ${_out_3rd}/busybox.gz ]; then
        cp -rf ${_out_3rd}/busybox.gz ${_disk_mnt}/
        pushd ${_disk_mnt}
            gunzip busybox.gz
            cpio -mdiv < busybox
            rm -f busybox
        popd
    fi
    third_install "${_disk_mnt}"
    tools_install "${_disk_mnt}"
    drivers_install "${_disk_mnt}"

    umount /dev/loop1p2

    [ -d ${_disk_mnt} ] && rm -rf ${_disk_mnt}
    losetup -d /dev/loop1
}

do_all()
{
    bash third-party/main.sh prepare || exit 1
    bash third-party/main.sh compile || exit 1
    do_compile || exit 1
    do_disk || exit 1
}

if [ "X$ARGS_EXP" == "Xprepare" ]; then
    bash third-party/main.sh prepare
elif [ "X$ARGS_EXP" == "Xcompile" ]; then
    bash third-party/main.sh compile && do_compile
elif [ "X$ARGS_EXP" == "Xdisk" ]; then
    do_disk
elif [ "X$ARGS_EXP" == "Xall" ]; then
    do_all
else
    echo "[Err] Args unknown: $ARGS_EXP"
    do_usage
fi

