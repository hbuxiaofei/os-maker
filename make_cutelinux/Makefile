KDIR := $(shell pwd)/.mod-code/kernel
MAKE := make -j 8

all:
	make -C drivers
	# $(MAKE) -C $(KDIR) M=drivers/virtio modules
	# $(MAKE) -C $(KDIR) M=drivers/scsi modules
	# $(MAKE) -C $(KDIR) M=drivers/block modules

clean:
	make -C drivers clean
	make -C $(KDIR) M=drivers/virtio clean
	make -C $(KDIR) M=drivers/scsi clean
	make -C $(KDIR) M=drivers/block clean

export KDIR
