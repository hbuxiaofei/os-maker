typedef struct {
	unsigned int gpio_base_addr;
	unsigned int r_gpio_base_addr;
	unsigned int * gpio;
	unsigned int * r_gpio;
	unsigned int gpio_base_offset;
	unsigned int r_gpio_base_offset;
	unsigned int pwm_base_addr;
	unsigned int * pwm;
	unsigned int pwm_ctrl;
	unsigned int pwm_period;
	unsigned int pwm_clk;		// H616
	unsigned int pwm_en;		// H616
	unsigned int pwm_type;		// type:V1 H3/H6, type:V2 H616
	unsigned int pwm_bit_en; 	// SUNXI_PWM_CH0_EN
	unsigned int pwm_bit_act;	// SUNXI_PWM_CH0_ACT_STA
	unsigned int pwm_bit_sclk;	// SUNXI_PWM_SCLK_CH0_GATING
	unsigned int pwm_bit_mode;	// SUNXI_PWM_CH0_MS_MODE
	unsigned int pwm_bit_pulse;	// SUNXI_PWM_CH0_PUL_START
} sunxi_gpio_info;

#define LOW                      0
#define HIGH                     1

#define INPUT                    0
#define OUTPUT                   1


#define	PI_GPIO_MASK	(0xFFFFFFC0)

#define SUNXI_PWM_BASE     (sunxi_gpio_info_t.pwm_base_addr)

/*********** Allwinner H6 *************/
#define H6_GPIO_BASE_ADDR                       0x0300B000U
#define H6_R_GPIO_BASE_ADDR                     0x07022000U
/*********** Allwinner H6 *************/

#define H6_PWM_BASE                             (0x0300A000)

int physPinToGpio(int physPin);
int wiringPiSetup(void);
int OrangePi_get_gpio_mode(int pin);
int getAlt(int pin);
int digitalRead (int pin);
int digitalWrite (int pin, int value);
int pinMode (int pin, int mode);
