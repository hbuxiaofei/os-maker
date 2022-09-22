
# gdb vmlinux
# 或者
# gdb vmlinux --tui
#
# (gdb) target remote:1234
# (gdb) hb start_kernel      // 设置硬件断点, 注意需要用 hb
# (gdb) info b
# (gdb) c
#
# gdb可以直接添加command
# gdb vmlinux -ex="target remote:1234" -ex="hb start_kernel"
#

 /opt/gdb_7_6/bin/gdb .mod-code/kernel/vmlinux \
    -ex="target remote:1234" \
    -ex="hb start_kernel"
