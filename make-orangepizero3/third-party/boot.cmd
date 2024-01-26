setenv bootcmd "fatload mmc 0:1 0x40200000 Image;fatload mmc 0:1 0x4fa00000 sun50i-h616-orangepi-zero3.dtb;booti 0x40200000 - 0x4fa00000"

setenv bootargs "console=ttyS0,115200"

setenv bootargs "${bootargs} root=/dev/mmcblk1p2 rw"

boot
