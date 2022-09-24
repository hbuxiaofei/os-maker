KDIR := $(shell pwd)/.mod-code/kernel

ifeq ($(NR_CPU),)
    NR_CPU := $(shell grep -c ^processor /proc/cpuinfo 2>/dev/null)
    ifeq ($(NR_CPU),)
        NR_CPU := 1
    endif
endif

MAKE := make -j $(NR_CPU)

all: all-drivers all-tools

clean: clean-drivers clean-tools

all-drivers:
	$(MAKE) -C drivers
	# $(MAKE) -C $(KDIR) M=drivers/virtio modules
	# $(MAKE) -C $(KDIR) M=drivers/scsi modules
	# $(MAKE) -C $(KDIR) M=drivers/block modules

clean-drivers:
	make -C drivers clean
	make -C $(KDIR) M=drivers/virtio clean
	make -C $(KDIR) M=drivers/scsi clean
	make -C $(KDIR) M=drivers/block clean

all-tools:
	$(MAKE) -C tools

clean-tools:
	make -C tools clean


export KDIR
