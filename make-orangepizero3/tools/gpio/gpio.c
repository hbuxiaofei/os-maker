#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "wiringPi.h"
#include "readall.h"


char *usage = "Usage: gpio -v\n"
              "       gpio -h\n"
              "       gpio [mode/read/write]\n"
              "       gpio readall\n";

/*
 * doMode:
 *	gpio mode pin mode ...
 *********************************************************************************
 */
void doMode (int argc, char *argv [])
{
    int ret = -1;
    int pin ;
    char *mode ;

    if (argc != 4) {
        fprintf(stderr, "Usage: %s mode [pin] [out/in]\n", argv[0]) ;
        exit(1) ;
    }

    pin = atoi(argv[2]);
    mode = argv[3];

    if (strcasecmp (mode, "in")      == 0) ret = pinMode         (pin, INPUT) ;
    else if (strcasecmp (mode, "input")   == 0) ret = pinMode         (pin, INPUT) ;
    else if (strcasecmp (mode, "out")     == 0) ret = pinMode         (pin, OUTPUT) ;
    else if (strcasecmp (mode, "output")  == 0) ret = pinMode         (pin, OUTPUT) ;

    if (ret) {
        fprintf(stderr, "operate mode %d %s error", pin, mode);
    }
}

/*
 * doRead:
 *	Read a pin and return the value
 *********************************************************************************
 */
void doRead (int argc, char *argv [])
{
    int pin, val ;

    if (argc != 3) {
        fprintf (stderr, "Usage: %s read pin\n", argv [0]) ;
        exit (1) ;
    }

    pin = atoi (argv [2]) ;
    val = digitalRead (pin) ;

    printf ("%s\n", val == 0 ? "0" : "1") ;
}

/*
 * doWrite:
 *	gpio write pin value
 *********************************************************************************
 */
static void doWrite (int argc, char *argv [])
{
    int pin, val ;
    int ret = -1;

    if (argc != 4) {
        fprintf (stderr, "Usage: %s write pin value\n", argv [0]) ;
        exit (1) ;
    }

    pin = atoi (argv [2]) ;

    if ((strcasecmp (argv [3], "up") == 0)
            || (strcasecmp (argv [3], "on") == 0)
            || (strcasecmp (argv [3], "1") == 0))
        val = 1 ;
    else if ((strcasecmp (argv [3], "down") == 0)
            || (strcasecmp (argv [3], "off") == 0)
            || (strcasecmp (argv [3], "0") == 0))
        val = 0 ;
    else
        val = atoi (argv [3]) ;

    if (val == 0)
        ret = digitalWrite (pin, LOW) ;
    else
        ret = digitalWrite (pin, HIGH) ;

    if (ret) {
        fprintf(stderr, "write %d %d error\n", pin, val);
    }
}

int main (int argc, char *argv [])
{
    if (argc == 1) {
        fprintf(stderr,
"%s: At your service!\n"
"  Type: gpio -h for full details\n", argv[0]);
        exit(EXIT_FAILURE);
    }


	if (strcasecmp(argv [1], "-h") == 0) {
		printf("%s: %s\n", argv[0], usage);
		exit(EXIT_SUCCESS);
	}

    wiringPiSetup();

    if (strcasecmp(argv[1], "mode") == 0) doMode(argc, argv) ;
    else if (strcasecmp(argv[1], "read") == 0) doRead(argc, argv);
    else if (strcasecmp (argv[1], "write") == 0) doWrite(argc, argv) ;
    else if (strcasecmp(argv[1], "readall") == 0) doReadall();
}
