// rdtsc.c  读取rdtsc程序
// gcc rdtsc.c

#include <stdio.h>
#include <stdint.h>
#include <unistd.h>

static inline uint64_t rdtsc_x86_64(void)
{
#if defined(__x86_64__)
    uint32_t low, high;
    asm volatile("rdtsc" : "=a"(low), "=d"(high));
    return ((uint64_t)low) | ((uint64_t)high << 32);
#else
    retrurn get_tick_count();
#endif
}

int main()
{
    uint64_t ret = 0;
    ret = rdtsc_x86_64();
    printf("%llu\n", ret);
}


