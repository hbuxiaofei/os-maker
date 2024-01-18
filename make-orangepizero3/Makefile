KDIR := $(shell pwd)/third-party/.mod-code/kernel
export KDIR

VAR_CROSS_COMPILE := $(G_CROSS_NAME)-

CC := $(VAR_CROSS_COMPILE)gcc
CXX := $(VAR_CROSS_COMPILE)g++

LD := $(VAR_CROSS_COMPILE)ld
AS := $(VAR_CROSS_COMPILE)as

AR := $(VAR_CROSS_COMPILE)ar
NM := $(VAR_CROSS_COMPILE)nm
STRIP := $(VAR_CROSS_COMPILE)strip
OBJCOPY := $(VAR_CROSS_COMPILE)objcopy
OBJDUMP := $(VAR_CROSS_COMPILE)objdump

export CC CXX LD AS AR NM STRIP OBJCOPY OBJDUMP


ifeq ($(NR_CPU),)
    NR_CPU := $(shell grep -c ^processor /proc/cpuinfo 2>/dev/null)
    ifeq ($(NR_CPU),)
        NR_CPU := 1
    endif
endif

CROSS_FLAG := ARCH=arm64 CROSS_COMPILE=$(VAR_CROSS_COMPILE)

MAKE := make $(CROSS_FLAG) -j $(NR_CPU)


all: all-drivers all-tools

clean: clean-drivers clean-tools

all-drivers:
	$(MAKE) -C drivers

clean-drivers:
	$(MAKE) -C drivers clean

all-tools:
	$(MAKE) -C tools

clean-tools:
	$(MAKE) -C tools clean


