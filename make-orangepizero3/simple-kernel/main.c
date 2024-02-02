
typedef unsigned long long      virtual_addr_t;

#define uint32_t unsigned int
#define u32_t unsigned int

// 定义Orange Pi Zero2的GPIO寄存器地址
#define GPIO_BASE       0x0300b000  // 根据具体硬件配置调整

// GPIO寄存器偏移量
#define GPIO_DATA_OFFSET    0x02
#define GPIO_DIR_OFFSET     0x04

// GPIO寄存器的指针
volatile uint32_t* gpio_data_reg = (uint32_t*)(GPIO_BASE + GPIO_DATA_OFFSET);
volatile uint32_t* gpio_dir_reg = (uint32_t*)(GPIO_BASE + GPIO_DIR_OFFSET);

// 定义LED连接的GPIO引脚号
#define LED_PIN     13  // 根据实际硬件连接调整

// 初始化GPIO配置
void init_gpio() {
    // 设置LED引脚为输出
    *gpio_dir_reg |= (1 << LED_PIN);
}

// 打开LED
void turn_on_led() {
    *gpio_data_reg |= (1 << LED_PIN);
}

// 关闭LED
void turn_off_led() {
    *gpio_data_reg &= ~(1 << LED_PIN);
}

void delay(uint32_t sec) {
    // 获取当前 CPU 主频
    // uint32_t cpu_freq = 1500000000;  // 假设CPU主频为1.5GHz
    uint32_t cpu_freq = 3000000;  // 假设CPU主频为1.5GHz

    // 计算需要循环的次数
    uint32_t loop_count = cpu_freq * sec;  // 1秒钟的循环次数

    // 执行延时循环
    for (uint32_t i = 0; i < loop_count; ++i) {
        // 空操作，仅用于占用时间
        __asm__("nop");
    }
}

static inline __attribute__((__always_inline__)) u32_t read32(virtual_addr_t addr)
{
    return (*((volatile u32_t *)(addr)));
}

static inline __attribute__((__always_inline__)) void write32(virtual_addr_t addr, u32_t value)
{
    *((volatile u32_t *)(addr)) = value;
}

#define clrbits_le32(addr, clear) \
    write32(((virtual_addr_t)(addr)), read32(((virtual_addr_t)(addr))) & ~(clear))

#define setbits_le32(addr, set) \
    write32(((virtual_addr_t)(addr)), read32(((virtual_addr_t)(addr))) | (set))



int main() {
    // 初始化GPIO
    // init_gpio();

    while (1) {
        // 打开LED
        // turn_on_led();
        setbits_le32(0x0300B058, (1 << 12));

        // 延时
        delay(1);

        clrbits_le32(0x0300B058, (1 << 12));

        // 关闭LED
        // turn_off_led();
        // clrbits_le32(0x0300B058, (1 << 12));

        // 延时
        delay(1);
    }

    return 0;
}

