
#
# -kernel bzImage  : 指定内核路径
# -initrd file     : 指定initramdisk路径
# -append nokaslr  : 指定内核参数nokaslr, 禁止内核地址随机化, 否则gdb打断点找不到地址
# -serial stdio    : 开启窗口
# -vnc :0          : 开启vnc监听0端口
# -s               : -gdb tcp::1234的缩写, 开启一个gdbserver, 可以通过TCP端口1234连接
# -S               : 启动后立即暂停
# --monitor stdio  : 开启qmp交互
#


# 同步本地 /tmp 目录到远程 (rsync端口号默认 873)
# rsync -av /tmp rsync://127.0.0.1/share

/usr/libexec/qemu-kvm \
    --enable-kvm \
    -smp 2 \
    -m 512 \
    -boot d \
    -cdrom out.iso \
    -device e1000,netdev=network0 \
    -netdev user,id=network0,hostfwd=tcp::23-:23,hostfwd=tcp::873-:873 \
    -monitor telnet:0.0.0.0:4321,server,nowait \
    -vnc :0 \
    -chardev stdio,id=char0,signal=off \
    -serial chardev:char0

exit 0

/usr/libexec/qemu-kvm \
    --enable-kvm \
    -smp 2 \
    -m 512 \
    -kernel .mod-code/kernel/arch/x86_64/boot/bzImage \
    -initrd .mod-code/busybox/rootfs.gz \
    -append "nokaslr console=ttyS0" \
    -device e1000,netdev=network0 \
    -netdev user,id=network0,hostfwd=tcp::23-:23,hostfwd=tcp::873-:873 \
    -monitor telnet:0.0.0.0:4321,server,nowait \
    -vnc :0 \
    -chardev stdio,id=char0,signal=off \
    -serial chardev:char0

exit 0
