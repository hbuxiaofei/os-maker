#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <linux/types.h>

#include "wiringPi.h"

#define	BLOCK_SIZE		(4*1024)

sunxi_gpio_info sunxi_gpio_info_t;



static int *pinToGpio;
static int *physToGpio;
int (*ORANGEPI_PIN_MASK)[32];

int pinToGpio_ZERO_2[64] =
{
	229, 228, 73, 226, 227,  70,  75,
	 69,  72, 79,  78, 231, 232,  71,
	230, 233, 74,  65, 272, 262, 234,
	224, 225,

	// Padding:
	-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, 				  	 // ... 31
	-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,   // ... 47
	-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,           // ... 63
};


int physToGpio_ZERO_2[64] =
{
	 -1,	      // 0
	 -1,  -1,     // 1, 2
	229,  -1,
	228,  -1,
	 73, 226,
	 -1, 227,
	 70,  75,
	 69,  -1,
	 72,  79,
	 -1,  78,
	231,  -1,
	232,  71,
	230, 233,
	 -1,  74,     // 25, 26
	 65, 224,     // 27
	272, 225,     // 29
	262,  -1,     // 31
	234,  -1,     // 33

	-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,   // ... 49
	-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,   // ... 63
};

static int ORANGEPI_PIN_MASK_ZERO_2[12][32] =  //[BANK]  [INDEX]
{
	{-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,},//PA
	{-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,},//PB
	{-1, 1,-1,-1,-1, 5, 6, 7, 8, 9,10,11,-1,-1,14,15,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,},//PC
	{-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,},//PD
	{-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,},//PE
	{-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,},//PF
	{-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,},//PG
	{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9,10,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,},//PH
	{-1,-1,-1,-1,-1,-1, 6,-1,-1,-1,-1,-1,-1,-1,-1,-1,16,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,},//PI
	{-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,},//PJ
	{-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,},//PK
	{-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,},//PE
};

unsigned int readR(unsigned int addr)
{
    unsigned int val = 0;
    unsigned int mmap_base;
    unsigned int mmap_seek;

    val = 0;
    mmap_base = (addr & 0xfffff000);
    mmap_seek = ((addr - mmap_base) >> 2);
    if(mmap_base == SUNXI_PWM_BASE) {
        val = *(sunxi_gpio_info_t.pwm + mmap_seek);
        return val;
    }

    if (addr >= sunxi_gpio_info_t.r_gpio_base_addr)
        val = *(sunxi_gpio_info_t.r_gpio + mmap_seek);
    else
        val = *(sunxi_gpio_info_t.gpio + mmap_seek);

    return val;

}

/*
 * Wirte value to register helper
 */
void writeR(unsigned int val, unsigned int addr)
{
	unsigned int mmap_base;
    unsigned int mmap_seek;

    mmap_base = (addr & 0xfffff000);
    mmap_seek = ((addr - mmap_base) >> 2);
    if (mmap_base == SUNXI_PWM_BASE) {
        *(sunxi_gpio_info_t.pwm + mmap_seek) = val;
        return;
    }

    if (addr >= sunxi_gpio_info_t.r_gpio_base_addr)
        *(sunxi_gpio_info_t.r_gpio + mmap_seek) = val;
    else
        *(sunxi_gpio_info_t.gpio + mmap_seek) = val;
}

int OrangePi_get_gpio_mode(int pin)
{
	unsigned int regval = 0;
    unsigned int bank   = pin >> 5;
    unsigned int index  = pin - (bank << 5);
    int offset = ((index - ((index >> 3) << 3)) << 2);
    unsigned int phyaddr = 0;
    unsigned char mode = -1;

	if (bank == 11)
		phyaddr = sunxi_gpio_info_t.r_gpio_base_addr + sunxi_gpio_info_t.r_gpio_base_offset + ((index >> 3) << 2);
	else
		phyaddr = sunxi_gpio_info_t.gpio_base_addr + sunxi_gpio_info_t.gpio_base_offset + (bank * 36) + ((index >> 3) << 2);

	/* Ignore unused gpio */
	if (ORANGEPI_PIN_MASK[bank][index] != -1) {
		regval = readR(phyaddr);
		mode = (regval >> offset) & 7;
	}

	return mode;
}

/*
 * OrangePi Digital Read
 */
int OrangePi_digitalRead(int pin)
{
    int bank = pin >> 5;
    int index = pin - (bank << 5);
    int val;
    unsigned int phyaddr = 0;


    if (bank == 11) {
        phyaddr = sunxi_gpio_info_t.r_gpio_base_addr + sunxi_gpio_info_t.r_gpio_base_offset + 0x10;
    } else {
        phyaddr = sunxi_gpio_info_t.gpio_base_addr + sunxi_gpio_info_t.gpio_base_offset + (bank * 36) + 0x10;
    }


    if (ORANGEPI_PIN_MASK[bank][index] != -1) {
        val = readR(phyaddr);

        val = val >> index;

        val &= 1;

        fprintf(stderr, "Read reg val: 0x%#x, bank:%d, index:%d\n", val, bank, index);

        return val;
    }

    return 0;
}


/*
 * OrangePi Digital write
 */
int OrangePi_digitalWrite(int pin, int value)
{
	unsigned int bank   = pin >> 5;
	unsigned int index  = pin - (bank << 5);
	unsigned int phyaddr = 0;
	unsigned int regval = 0;

    if (bank == 11) {
        phyaddr = sunxi_gpio_info_t.r_gpio_base_addr + sunxi_gpio_info_t.r_gpio_base_offset + 0x10;
    } else {
        phyaddr = sunxi_gpio_info_t.gpio_base_addr + sunxi_gpio_info_t.gpio_base_offset + (bank * 36) + 0x10;
    }

    /* Ignore unused gpio */
    if (ORANGEPI_PIN_MASK[bank][index] != -1) {
        regval = readR(phyaddr);

        if (0 == value) {
            regval &= ~(1 << index);
            writeR(regval, phyaddr);
            regval = readR(phyaddr);
        } else {
            regval |= (1 << index);
            writeR(regval, phyaddr);
            regval = readR(phyaddr);
        }

    } else {
        fprintf(stderr, "Pin mode failed!\n");
        return -1;
    }
    return 0;
}

/*
 * digitalWrite:
 *	Set an output bit
 *********************************************************************************
 */
int digitalWrite (int pin, int value)
{
    int ret;

    if ((pin & PI_GPIO_MASK) == 0) {
        pin = pinToGpio[pin];

        if (-1 == pin) {
            fprintf(stderr, "[%s:L%d] the pin:%d is invaild,please check it over!\n",
                    __func__,  __LINE__, pin);

            return -1;
        }
        OrangePi_digitalWrite(pin, value);

    } else {

        return -1;
    }


    return 0;
}


/*
 * digitalRead:
 *	Read the value of a given Pin, returning HIGH or LOW
 *********************************************************************************
 */
int digitalRead (int pin)
{
	if ((pin & PI_GPIO_MASK) == 0) {
        pin = pinToGpio[pin];

		if (pin == -1) {
			fprintf(stderr, "[%s %d]Pin %d is invalid, please check it over!\n", __func__, __LINE__, pin);
			return LOW;
		}

		return OrangePi_digitalRead(pin);
	}

    return -1;

}


/*
 * getAlt:
 *	Returns the ALT bits for a given port. Only really of-use
 *	for the gpio readall command (I think)
 *********************************************************************************
 */
int getAlt (int pin)
{
	int alt;

	pin &= 63;

	pin = pinToGpio[pin];

	alt = OrangePi_get_gpio_mode(pin);

	return alt;
}

int physPinToGpio (int physPin)
{
    return physToGpio [physPin & 63] ;
}

void set_soc_info(void)
{
    sunxi_gpio_info_t.gpio_base_addr = H6_GPIO_BASE_ADDR;
    sunxi_gpio_info_t.r_gpio_base_addr = H6_R_GPIO_BASE_ADDR;
    sunxi_gpio_info_t.gpio_base_offset = 0x0;
    sunxi_gpio_info_t.r_gpio_base_offset = 0x0;
    sunxi_gpio_info_t.pwm_base_addr = H6_PWM_BASE;
}

int wiringPiSetup (void)
{
    int fd;

    pinToGpio =  pinToGpio_ZERO_2;
    physToGpio = physToGpio_ZERO_2;
    ORANGEPI_PIN_MASK = ORANGEPI_PIN_MASK_ZERO_2;

    set_soc_info();

    if ((fd = open ("/dev/mem", O_RDWR | O_SYNC | O_CLOEXEC)) < 0) {
        fprintf(stderr, "error on open /dev/mem\n");
        return -1;
    }

    sunxi_gpio_info_t.gpio = (uint32_t *)mmap(0, BLOCK_SIZE, PROT_READ | PROT_WRITE,
            MAP_SHARED, fd, sunxi_gpio_info_t.gpio_base_addr);

    if ((int32_t)(unsigned long)sunxi_gpio_info_t.gpio == -1) {
        fprintf(stderr, "error on mmap gpio\n");
        goto error;
    }

    sunxi_gpio_info_t.r_gpio = (uint32_t *)mmap(0, BLOCK_SIZE, PROT_READ | PROT_WRITE,
            MAP_SHARED, fd, sunxi_gpio_info_t.r_gpio_base_addr);

    if ((int32_t)(unsigned long)sunxi_gpio_info_t.r_gpio == -1) {
        fprintf(stderr, "error on mmap r_gpio\n");
        goto error;
    }



error:
    close(fd);
    return -1;
}

/*
 * Set GPIO Mode
 */
int OrangePi_set_gpio_mode(int pin, int mode)
{
    unsigned int regval = 0;
    unsigned int bank   = pin >> 5;
    unsigned int index  = pin - (bank << 5);
    unsigned int phyaddr = 0;
    int offset;

    offset = ((index - ((index >> 3) << 3)) << 2);

    if (bank == 11)
        phyaddr = sunxi_gpio_info_t.r_gpio_base_addr + sunxi_gpio_info_t.r_gpio_base_offset + ((index >> 3) << 2);
    else
        phyaddr = sunxi_gpio_info_t.gpio_base_addr + sunxi_gpio_info_t.gpio_base_offset + (bank * 36) + ((index >> 3) << 2);

    if (ORANGEPI_PIN_MASK[bank][index] != -1) {
        regval = readR(phyaddr);

        /* Set Input */
        if (INPUT == mode) {
            regval &= ~(7 << offset);
            writeR(regval, phyaddr);
            regval = readR(phyaddr);
        } else if(OUTPUT == mode) {
            /* Set Output */
            regval &= ~(7 << offset);
            regval |=  (1 << offset);
            writeR(regval, phyaddr);
            regval = readR(phyaddr);
        }

    } else {
        fprintf(stderr, "Pin mode failed!\n");
        return -1;
    }

    return 0;
}

/*
 * pinMode:
 *	Sets the mode of a pin to be input, output or PWM output
 *********************************************************************************
 */
int pinMode (int pin, int mode)
{
    if ((pin & PI_GPIO_MASK) == 0) {
        pin = pinToGpio[pin];

        if (-1 == pin) {
            fprintf(stderr, "[%s:L%d] the pin:%d is invaild,please check it over!\n",
                    __func__,  __LINE__, pin);
            return -1;
        }

        if (mode == INPUT) {
            OrangePi_set_gpio_mode(pin, INPUT);
        }
        else if (mode == OUTPUT) {
            OrangePi_set_gpio_mode(pin, OUTPUT);
        } else {
            return -2;
        }

        return 0;
    }

    return -1;
}




