#!/usr/bin/env bash

# https://github.com/neovim/neovim/releases/download
__download_neovim()
{
    local version="v0.9.5"
    local neovim_name="nvim-linux64"
    local neovim_tarball="${neovim_name}.tar.gz"
    local neovim_url="https://github.com/neovim/neovim/releases/download/${version}/${neovim_tarball}"
    if [ -e "$neovim_tarball" ]; then
        return 0
    fi

    if command -v mwget >/dev/null 2>&1; then
        mwget -n 10 $neovim_url
    else
        if command -v wget >/dev/null 2>&1; then
            wget $neovim_url
        else
            echo "wget: command not found"
            return 1
        fi
    fi

    if [ $? -ne 0 ] || [ ! -e "$neovim_tarball" ]; then
        echo "get stable neovim error"
        return 1
    fi
}
__check_neovim_conflict()
{
    local neovim_name="nvim-linux64"
    local neovim_tarball="${neovim_name}.tar.gz"
    local tempfile=$(mktemp -t temp.XXXXXX)
    local _line=""
    local _ok="false"
    local is_conflict=0
    if [ ! -e "$neovim_tarball" ]; then
        echo "$neovim_tarball not found"
        rm -f $tempfile
        return 1
    fi

    tar -tf $neovim_tarball > $tempfile
    if [ $? -ne 0 ]; then
        echo "$neovim_tarball decompression failed"
        rm -f $tempfile
        return 1
    fi

    sed -i "s#^${neovim_name}#/usr#g" $tempfile
    sed -i '/.*\/$/d' $tempfile

    while read _line; do
        if [ -n "$_line" ] && [ -e "$_line" ] ; then
            echo -e "\033[33m- [Warn] file $_line conflict\033[0m"
            is_conflict=1
        fi

        if [ x"$_line" == x"/usr/bin/nvim" ]; then
            _ok="true"
        fi
    done  < $tempfile

    rm -f $tempfile

    if [ x"$_ok" != x"true" ]; then
        echo "$neovim_tarball seems not be complete"
        return 1
    fi

    return $is_conflict
}

install_neovim() {
    local exename="nvim"
    local neovim_name="nvim-linux64"
    local neovim_tarball="${neovim_name}.tar.gz"

    if command -v ${exename} >/dev/null 2>&1; then
        return 0
    fi
    __download_neovim || return 1
    __check_neovim_conflict || return 1
    tar -xf $neovim_tarball --strip-components 1 -C /usr/ || return 1
}

if [ -d /etc/yum.repos.d ]; then
    if [ -d /etc/yum.repos.d.bak ]; then
        rm -rf /etc/yum.repos.d
    else
        mv /etc/yum.repos.d /etc/yum.repos.d.bak
    fi
fi

mkdir -p /etc/yum.repos.d
pushd /etc/yum.repos.d
    curl  https://mirrors.aliyun.com/repo/Centos-7.repo > CentOS-Base.repo

    # sed -e 's|^mirrorlist=|#mirrorlist=|g' \
    #         -e 's|^#baseurl=http://mirror.centos.org|baseurl=https://mirrors.tuna.tsinghua.edu.cn|g' \
    #         -i.bak \
    #         /etc/yum.repos.d/CentOS-*.repo

    yum clean all
    yum makecache
popd


systemctl stop firewalld
systemctl mask firewalld

setenforce 0
sed -ri 's/SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config

## core
yum install -y vim
yum install -y wget
yum install -y lrzsz
yum install -y unzip
yum install -y net-tools
yum install -y git
yum install -y gcc
yum install -y gcc-c++
yum install -y cmake
yum install -y make
yum install -y bash-completion
yum install -y ctags cscope
yum install -y telnet

## fish
yum install -y pcre2-devel

## iso
yum install -y mkisofs
yum install -y genisoimage
yum install -y isomd5sum

## kernel
yum install -y bison bc
yum install -y ncurses-devel
yum install -y elfutils-libelf-devel
yum install -y openssh-devel openssl-devel libgcrypt-devel

## busybox
yum install -y glibc-static

## syslinux
yum install -y libuuid-devel
yum install -y nasm
yum install -y glibc-devel.i686

## libvirt qemu
yum install -y qemu-kvm
# yum install -y libvirt

## python3
yum install python3
yum install python3-devel

## neovim
install_neovim
