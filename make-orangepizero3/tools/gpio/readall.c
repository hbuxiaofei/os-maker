#include <stdio.h>
#include <stddef.h>

#include "wiringPi.h"

static int * physToWpi;
static char ** physNames;
static char ** alts;

static int physToWpi_ZERO_2[64] =
{
	-1, 	// 0
	-1, -1, // 1, 2
	 0, -1, // 3, 4
	 1, -1, // 5, 6
	 2,  3, // 7, 8
	-1,  4, // 8, 10
	 5,  6, //11, 12
	 7, -1, //13, 14
	 8,  9, //15, 16
	-1, 10, //17, 18
	11, -1, //19, 20
	12, 13, //21, 22
	14, 15, //23, 24
	-1, 16, //25, 26
	17, 21, //27, 28
	18, 22, //29, 30
	19, -1, //31, 32
	20, -1, //33, 34

	// Padding:
	-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,   // ... 56
	-1,  													  // ... 63
};

static char * physNames_ZERO_2[64] =
{
	NULL,
	"    3.3V", "5V      ",
	"   SDA.3", "5V      ",
	"   SCL.3", "GND     ",
	"     PC9", "TXD.5   ",
	"     GND", "RXD.5   ",
	"     PC6", "PC11    ",
	"     PC5", "GND     ",
	"     PC8", "PC15    ",
	"    3.3V", "PC14    ",
	"  MOSI.1", "GND     ",
	"  MISO.1", "PC7     ",
	"  SCLK.1", "CE.1    ",
	"     GND", "PC10    ",
	"     PC1", "PWM3    ",
	"    PI16", "PWM4    ",
	"     PI6", "        ",
	"    PH10", "        ",
};

static char * alts_common [] =
{
  "IN", "OUT", "ALT2", "ALT3", "ALT4", "ALT5", "ALT6", "OFF"
};



void readallPhys (int physPin)
{
    int pin ;

    if (physPinToGpio (physPin) == -1)
        printf (" |      |    ") ;
    else
        printf (" | %4d | %3d", physPinToGpio (physPin), physToWpi [physPin]) ;

    printf (" | %s", physNames[physPin]);


    if (physToWpi [physPin] == -1) {
        printf (" |        |  ") ;
    } else {
        pin = physToWpi [physPin] ;
        printf (" | %6s", alts[getAlt(pin)]) ;
        printf (" | %d", digitalRead (pin)) ;
    }

    // Pin numbers:
    printf (" | %2d", physPin) ;
    ++physPin ;
    printf (" || %-2d", physPin) ;

    // Same, reversed
    if (physToWpi [physPin] == -1) {
        printf (" |   |       ") ;
    } else {
        pin = physToWpi [physPin] ;

        printf (" | %d", digitalRead (pin)) ;
        printf (" | %-6s", alts [getAlt (pin)]) ;
    }

    printf (" | %-5s", physNames [physPin]) ;
    if (physToWpi     [physPin] == -1)
        printf (" |     |     ") ;
    else
        printf (" | %-3d | %-4d", physToWpi [physPin], physPinToGpio (physPin)) ;

    printf (" |\n") ;
}


void OrangePiReadAll(void)
{
    int pin;

	printf (" +------+-----+----------+--------+---+   H616   +---+--------+----------+-----+------+\n");
	physToWpi =  physToWpi_ZERO_2;
	physNames =  physNames_ZERO_2;
	alts = alts_common;


	printf (" | GPIO | wPi |   Name   |  Mode  | V | Physical | V |  Mode  | Name     | wPi | GPIO |\n");
	printf (" +------+-----+----------+--------+---+----++----+---+--------+----------+-----+------+\n");


    for (pin = 1 ; pin <= 34; pin += 2) {
        readallPhys(pin);
    }

}

void doReadall (void)
{
    OrangePiReadAll();
}
