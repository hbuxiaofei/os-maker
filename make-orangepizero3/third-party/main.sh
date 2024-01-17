#!/bin/bash

set -e

EXEC_NAME="main.sh"
NR_CPU=`grep -c ^processor /proc/cpuinfo 2>/dev/null`
IN_ARGS=`getopt -o h --long help -n 'main.sh' -- "$@"`
GETOPT_RET=$?

function do_usage()
{
    cat <<EOF
Usage: $EXEC_NAME <command> [args...]
  command:
    prepare     Prepare source code
    compile     Compile all
  args:
    -h, --help  Show this help message
Example:
  $EXEC_NAME prepare
  $EXEC_NAME compile
EOF
}

if [ $GETOPT_RET != 0 ]; then
    echo "Terminating..."
    do_usage
    exit 1
fi

eval set -- "${IN_ARGS}"

ARGS_EXP=""

while true; do
    case "$1" in
        -h|--help)
            do_usage
            exit 0
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

MOD_CODE_DIR="${PWD}/.mod-code"
VAR_CROSS_COMPILE="aarch64-none-linux-gnu-"
VAR_CROSS_BIN="/usr/local/bin/gcc-arm-11.2-2022.02-x86_64-aarch64-none-linux-gnu/bin"
VAR_PLAT="sun50i_h616"
VAR_PLAT_FULLNAME="sun50i-h616-orangepi-zero3"

PATH=$PATH:${VAR_CROSS_BIN}
PATH=$PATH:${MOD_CODE_DIR}/u-boot/tools
export PATH

function do_prepare()
{
    local _mod_code_dir=$MOD_CODE_DIR

    if [ ! -d $_mod_code_dir ]; then
    	mkdir -p $_mod_code_dir
    fi

    pushd $_mod_code_dir
        if [ ! -d arm-trusted-firmware ]; then
            git clone https://github.com/hbuxiaofei/arm-trusted-firmware.git -b orangepi-zero3
        fi

        if [ ! -d u-boot ]; then
            git clone https://github.com/hbuxiaofei/u-boot.git -b v2021.07-sunxi
        fi

        if [ ! -d kernel ]; then
            git clone https://github.com/hbuxiaofei/linux-2.6.38-study.git -b orange-pi-6.1-sun50iw9 kernel
        fi

        if [ ! -d busybox ]; then
            git clone https://github.com/mirror/busybox.git -b 1_35_0
        fi
    popd
}

compile_check()
{
    local _mod_code_dir=$MOD_CODE_DIR
    local _cross_bin=$VAR_CROSS_BIN

    if [ ! -d $_cross_bin ]; then
        echo "[Err] cross compile bin not found: $_cross_bin"
        return 1
    fi

    if [ ! -d $_mod_code_dir ]; then
        echo "[Err] mode code directory not found"
        return 1
    fi

    pushd $_mod_code_dir
        if [ ! -d arm-trusted-firmware ]; then
            echo "[Err] arm-trusted-firmware not found"
            return 1
        fi

        if [ ! -d u-boot ]; then
            echo "[Err] u-boot not found"
            return 1
        fi

        if [ ! -d kernel ]; then
            echo "[Err] kernel not found"
            return 1
        fi

        if [ ! -d busybox ]; then
            echo "[Err] busybox not found"
            return 1
        fi
        return 0
    popd
}

compile_code()
{
    local _code_dir=$MOD_CODE_DIR
    local _compiler_prefix="$VAR_CROSS_COMPILE"
    local _plat="$VAR_PLAT"
    local _plt_fllname="$VAR_PLAT_FULLNAME"

    pushd $_code_dir
        pushd arm-trusted-firmware
            [ ! -e build/${_plat}/debug/bl31.bin ] && \
               make CROSS_COMPILE="$_compiler_prefix" PLAT="$_plat" DEBUG=1 bl31 -j ${NR_CPU}
        popd

        # make ARCH=arm CROSS_COMPILE=aarch64-none-linux-gnu- orangepi_zero3_defconfig
        [ ! -e u-boot/.config ] && cp -f uboot.config u-boot/.config
        pushd u-boot
            [ ! -e u-boot-sunxi-with-spl.bin ] && \
               make ARCH=arm CROSS_COMPILE="$_compiler_prefix" BL31=../arm-trusted-firmware/build/${_plat}/debug/bl31.bin -j ${NR_CPU}
        popd

	# orangepi-build/external/config/kernel/linux-6.1-sun50iw9-next.config
	# make ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu- menuconfig
        [ ! -e kernel/.config ] && cp -f kernel.config kernel/.config
        pushd kernel
            [ ! -e arch/arm64/boot/Image ] && \
                make ARCH=arm64 CROSS_COMPILE="$_compiler_prefix" Image -j ${NR_CPU}

            [ ! -e arch/arm64/boot/dts/allwinner/${_plt_fllname}.dtb ] && \
                make ARCH=arm64 CROSS_COMPILE="$_compiler_prefix" dtbs -j ${NR_CPU}
        popd

        [ ! -e busybox/.config ] && cp -f busybox.config busybox/.config
        bash busybox-build.sh

    popd

    return 0
}

compile_gather()
{
    local _gtr_dir="${PWD}/gather"
    local _plt_fllname="$VAR_PLAT_FULLNAME"

    [ -e ${_gtr_dir} ] && rm -rf ${_gtr_dir}
    mkdir -p ${_gtr_dir}/u-boot
    mkdir -p ${_gtr_dir}/boot

    cp -f u-boot/u-boot-sunxi-with-spl.bin ${_gtr_dir}/u-boot/
    cp -f kernel/arch/arm64/boot/Image ${_gtr_dir}/boot/
    cp -f kernel/arch/arm64/boot/dts/allwinner/${_plt_fllname}.dtb ${_gtr_dir}/boot/
    cp -f busybox/rootfs.gz ${_gtr_dir}/

    cp -f boot.cmd ${_gtr_dir}/boot/
    mkimage -C none -A arm -T script -d ${_gtr_dir}/boot/boot.cmd ${_gtr_dir}/boot/boot.scr
}

do_compile()
{
    compile_check
    [ $? != 0 ] && return 1

    compile_code
    [ $? != 0 ] && return 1

    compile_gather
    [ $? != 0 ] && return 1
}

if [ "X$ARGS_EXP" == "Xprepare" ]; then
    do_prepare
elif [ "X$ARGS_EXP" == "Xcompile" ]; then
    do_compile
else
    echo "[Err] Args unknown: $ARGS_EXP"
    do_usage
fi

