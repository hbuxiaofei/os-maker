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

TOP_DIR="${PWD}"
MOD_CODE_DIR="${TOP_DIR}/.mod-code"

VAR_CROSS_NAME="${G_CROSS_NAME}"
VAR_CROSS_COMPILE="${G_CROSS_NAME}-"
VAR_CROSS_DIR=${G_CROSS_DIR}
VAR_CROSS_BIN="${VAR_CROSS_DIR}/bin"
VAR_PLAT="sun50i_h616"
VAR_PLAT_FULLNAME="sun50i-h616-orangepi-zero3"

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

        if [ ! -d lrzsz ]; then
            git clone https://github.com/hbuxiaofei/lrzsz.git -b master
        fi

        if [ ! -d i2c-tools ]; then
            git clone git@github.com:mozilla-b2g/i2c-tools.git
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
            exit 1
        fi

        if [ ! -d u-boot ]; then
            echo "[Err] u-boot not found"
            exit 1
        fi

        if [ ! -d kernel ]; then
            echo "[Err] kernel not found"
            exit 1
        fi

        if [ ! -d busybox ]; then
            echo "[Err] busybox not found"
            exit 1
        fi

        if [ ! -d lrzsz ]; then
            echo "[Err] lrzsz not found"
            exit 1
        fi

        if [ ! -d i2c-tools ]; then
            echo "[Err] i2c-tools not found"
            exit 1
        fi
    popd
}

compile_code()
{
    local _top_dir=$TOP_DIR
    local _code_dir=$MOD_CODE_DIR
    local _compiler_name="$VAR_CROSS_NAME"
    local _compiler_prefix="$VAR_CROSS_COMPILE"
    local _plat="$VAR_PLAT"
    local _plt_fllname="$VAR_PLAT_FULLNAME"

    pushd $_code_dir
        pushd arm-trusted-firmware
            [ ! -e build/${_plat}/debug/bl31.bin ] && \
               make CROSS_COMPILE="$_compiler_prefix" PLAT="$_plat" DEBUG=1 bl31 -j ${NR_CPU}
        popd

        # make ARCH=arm CROSS_COMPILE=aarch64-none-linux-gnu- orangepi_zero3_defconfig
        [ ! -e u-boot/.config ] && cp -f ${_top_dir}/uboot.config u-boot/.config
        pushd u-boot
            [ ! -e u-boot-sunxi-with-spl.bin ] && \
               make ARCH=arm CROSS_COMPILE="$_compiler_prefix" BL31=../arm-trusted-firmware/build/${_plat}/debug/bl31.bin -j ${NR_CPU}
        popd

	    # orangepi-build/external/config/kernel/linux-6.1-sun50iw9-next.config
        # make ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu- menuconfig
        [ ! -e kernel/.config ] && cp -f ${_top_dir}/kernel.config kernel/.config
        pushd kernel
            if [ -e "${_top_dir}/${_plt_fllname}.dts" ]; then
                if ! cmp -s ${_top_dir}/${_plt_fllname}.dts arch/arm64/boot/dts/allwinner/${_plt_fllname}.dts; then
                   cp -f ${_top_dir}/${_plt_fllname}.dts arch/arm64/boot/dts/allwinner/${_plt_fllname}.dts
                fi
            fi

            [ ! -e arch/arm64/boot/Image ] && \
                make ARCH=arm64 CROSS_COMPILE="$_compiler_prefix" Image -j ${NR_CPU}

            [ ! -e arch/arm64/boot/dts/allwinner/${_plt_fllname}.dtb ] && \
                make ARCH=arm64 CROSS_COMPILE="$_compiler_prefix" dtbs -j ${NR_CPU}

            [ ! -e Module.symvers ] && \
                make ARCH=arm64 CROSS_COMPILE="$_compiler_prefix" modules -j ${NR_CPU}
        popd

        pushd lrzsz
            [ ! -e Makefile ] && ./configure --host=${_compiler_name}
            [ ! -e src/lrz ] && make CC=${_compiler_name}-gcc -j ${NR_CPU}
        popd

        pushd i2c-tools
            [ ! -e lib/libi2c.so.0 ] && make CC=${_compiler_name}-gcc AR=${_compiler_name}-ar -j ${NR_CPU}
        popd

    popd

    [ ! -e ${_code_dir}/busybox/.config ] && cp -f ${_top_dir}/busybox.config  ${_code_dir}/busybox/.config
    bash busybox-build.sh
}

compile_out()
{
    local _out_dir="${TOP_DIR}/out"
    local _code_dir=$MOD_CODE_DIR
    local _plt_fllname="$VAR_PLAT_FULLNAME"
    local _ins_usr_bin="${_out_dir}/rootfs/usr/bin"
    local _ins_lib64="${_out_dir}/rootfs/lib64"
    local _ins_module="${_out_dir}/rootfs/lib/modules/6.1.31+/kernel"

    [ -e ${_out_dir} ] && rm -rf ${_out_dir}
    mkdir -p ${_out_dir}/u-boot
    mkdir -p ${_out_dir}/boot
    mkdir -p ${_out_dir}/boot/overlays
    mkdir -p ${_ins_usr_bin}
    mkdir -p ${_ins_lib64}
    mkdir -p ${_ins_module}

    pushd ${_code_dir}
        cp -f u-boot/u-boot-sunxi-with-spl.bin ${_out_dir}/u-boot/
        cp -f kernel/Module.symvers ${_out_dir}/boot/
        cp -f kernel/arch/arm64/boot/Image ${_out_dir}/boot/
        cp -f kernel/arch/arm64/boot/dts/allwinner/${_plt_fllname}.dtb ${_out_dir}/boot/
        cp -f kernel/arch/arm64/boot/dts/allwinner/overlay/sun50i-h616-ph-i2c3.dtbo ${_out_dir}/boot/overlays/
        cp -f busybox/busybox.gz ${_out_dir}/

        cp -f lrzsz/src/lrz ${_ins_usr_bin}/
        cp -f lrzsz/src/lsz ${_ins_usr_bin}/

        cp -f i2c-tools/lib/libi2c.so.0 ${_ins_lib64}/
        cp -f i2c-tools/tools/i2cdetect ${_ins_usr_bin}/
        cp -f i2c-tools/tools/i2cdump ${_ins_usr_bin}/
        cp -f i2c-tools/tools/i2cset ${_ins_usr_bin}/
        cp -f i2c-tools/tools/i2cget ${_ins_usr_bin}/
    popd

    pushd ${_code_dir}/kernel
        find fs -name nls_iso8859-1.ko | xargs -i cp -f --parents {} ${_ins_module}
    popd

    mkimage -A arm64 -T kernel -C none -O linux -n "Linux kernel" \
        -a 0x40200000 -e 0x40200000  \
        -d ${_out_dir}/boot/Image ${_out_dir}/boot/uImage

    cp -f boot.cmd ${_out_dir}/boot/
    mkimage -A arm64 -T script -C none -d ${_out_dir}/boot/boot.cmd ${_out_dir}/boot/boot.scr
}

do_compile()
{
    compile_check

    compile_code

    compile_out
}

if [ "X$ARGS_EXP" == "Xprepare" ]; then
    do_prepare
elif [ "X$ARGS_EXP" == "Xcompile" ]; then
    do_compile
else
    echo "[Err] Args unknown: $ARGS_EXP"
    do_usage
fi

