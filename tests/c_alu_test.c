#include <stdint.h>

static inline void test_pass(void) {
    __asm__ volatile(".word 0x00A00013");
    for (;;) { }
}

static inline void test_fail(void) {
    __asm__ volatile(".word 0x00F00013");
    for (;;) { }
}

int main(void) {
    volatile uint32_t a = 0x12345678u;
    volatile uint32_t b = 0x0000000Fu;
    volatile uint32_t result = a & b;

    if (result == 0x00000008u) {
        test_pass();
    } else {
        test_fail();
    }

    return 0;
}