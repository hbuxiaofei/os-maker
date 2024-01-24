setenv bootcmd "fatload mmc 0:1 0x40200000 Image;fatload mmc 0:1 0x4fa00000 sun50i-h616-orangepi-zero3.dtb;booti 0x40200000 - 0x4fa00000"

setenv bootargs "console=ttyS0,115200"

setenv bootargs "${bootargs} root=/dev/mmcblk1p2 rw"

echo ">>> Boot script loaded from ${devtype} ${devnum}"

dtoverlay=sun50i-h616-ph-i2c3
dtdebug=1

# setenv load_addr "0x45000000"
# if load ${devtype} ${devnum} ${load_addr} ${bootdir}/overlays/sun50i-h616-ph-i2c3.dtbo; then
#     fdt apply ${load_addr}
# fi

boot
