
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

/usr/libexec/qemu-kvm \
    --enable-kvm \
    -smp 2 \
    -m 2048 \
    -kernel linux-iso/bzImage \
    -initrd linux-iso/rootfs.gz \
    -drive file=/var/lib/libvirt/images/disk.qcow2,if=virtio,media=disk,cache=directsync,format=qcow2 \
    -append "nokaslr console=ttyS0" \
    -monitor telnet:0.0.0.0:4321,server,nowait \
    -vnc :0 \
    -serial stdio \
    -s \
    -S


