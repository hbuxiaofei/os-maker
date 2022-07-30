CONFIG_MODULE_SIG = n
TARGET_MODULE := fibdrv

obj-m := $(TARGET_MODULE).o
ccflags-y := -std=gnu99 -Wno-declaration-after-statement

SUBPATH=drivers/char/$(TARGET_MODULE)
PWD := $(shell pwd)

KDIR ?= $(subst $(SUBPATH),.mod-code/kernel,$(PWD))

all: module $(TARGET_MODULE)-test

module:
	$(MAKE) -C $(KDIR) M=$(PWD) modules

$(TARGET_MODULE)-test: $(TARGET_MODULE)-test.c
	$(CC) -static -o $@ $^

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean
	rm -rf $(TARGET_MODULE)-test
