#include <stdint.h>

static inline uint64_t read_and_time(volatile uint8_t* addr) {
    uint64_t t0, t1;
    uint8_t val;

    __asm__ volatile(
        "isb\n\t"
        "mrs %0, cntvct_el0\n\t"
        "isb"
        : "=r" (t0)
        :
        : "memory"
    );

    val = *addr;

    __asm__ volatile(
        "eor %0, %1, %1\n\t"
        "add %2, %2, %0\n\t"
        "isb\n\t"
        "mrs %0, cntvct_el0\n\t"
        "isb"
        : "=&r" (t1)
        : "r" (val), "r" (addr)
        : "memory"
    );

    return t1 - t0;
}

static inline void flush_cache_c(void* ptr) {
    __asm__ volatile("dc civac, %0\n\tdsb sy\n\tisb" : : "r" (ptr) : "memory");
}