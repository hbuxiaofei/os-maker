
SRCS = $(wildcard *.c)
OBJS = $(SRCS:.c=.o)
CFLAGS = -Wall -O2 -ffreestanding -nostdinc -nostdlib

all: kernel.img

start.o: start.S
	aarch64-none-linux-gnu-gcc $(CFLAGS) -c start.S -o start.o

%.o: %.c
	aarch64-none-linux-gnu-gcc $(CFLAGS) -c $< -o $@

kernel.img: start.o $(OBJS)
	aarch64-none-linux-gnu-ld -nostdlib start.o $(OBJS) -T link.ld -o kernel.elf
	aarch64-none-linux-gnu-objcopy -O binary -R .note -R .comment -S kernel.elf kernel.img

uImage: kernel.img
	mkimage -A arm64 -O linux  -T kernel -C none \
		-a 0x40200000 -e 0x40200000 -n "Linux kernel" \
		-d kernel.img \
		uImage

clean:
	rm *.elf *.img *.o uImage
