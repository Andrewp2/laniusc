#include <stdint.h>
#include <string.h>

/* Independent C-compiler oracle for the Linux x86-64 scalar ABI. */
_Static_assert(sizeof(float) == 4 && sizeof(double) == 8, "IEEE scalar widths");
_Static_assert(sizeof(void *) == 8, "LP64 pointer width");

uint32_t fp_c_bits32(float value) { uint32_t bits; memcpy(&bits, &value, 4); return bits; }
uint64_t fp_c_bits64(double value) { uint64_t bits; memcpy(&bits, &value, 8); return bits; }
float fp_c_from32(uint32_t bits) { float value; memcpy(&value, &bits, 4); return value; }
double fp_c_from64(uint64_t bits) { double value; memcpy(&value, &bits, 8); return value; }
float fp_c_echo32(float value) { return value; }
double fp_c_echo64(double value) { return value; }
float fp_c_add32(float a, float b) { return a + b; }
double fp_c_add64(double a, double b) { return a + b; }

void *fp_c_pointer(uint32_t index) {
    return (void *)(uintptr_t)(index == 0 ? UINT64_C(0x1234567887654321) : UINT64_C(0x2345678998765432));
}

/* Here INTEGER spills before any SSE register is consumed. */
uint32_t fp_c_gpr_first(uint64_t a, uint64_t b, uint64_t c, uint64_t d,
                        uint64_t e, uint64_t f, uint64_t g, float s, double t) {
    uint32_t mismatch = 0;
    const uint64_t received[] = {a,b,c,d,e,f,g};
    const uint64_t expected[] = {11,23,37,53,71,89,107};
    for (unsigned index = 0; index < 7; ++index) {
        if (received[index] != expected[index]) mismatch |= UINT32_C(1) << index;
    }
    if (fp_c_bits32(s) != UINT32_C(0x3fa00000)) mismatch |= UINT32_C(1) << 7;
    if (fp_c_bits64(t) != UINT64_C(0xc004000000000000)) mismatch |= UINT32_C(1) << 8;
    return mismatch;
}

/* SSE spills at argument 12; INTEGER registers still serve 13, 15 and 17.
 * After 17, the remaining stack slots interleave the two classes in source
 * order. Every value is distinct, including signed/high-bit scalar words. */
uint32_t fp_c_mixed32(
    float a01,
    double a02,
    int32_t a03,
    float a04,
    uint64_t a05,
    double a06,
    void * a07,
    float a08,
    double a09,
    float a10,
    double a11,
    float a12,
    int64_t a13,
    double a14,
    uintptr_t a15,
    float a16,
    intptr_t a17,
    double a18,
    uint32_t a19,
    float a20,
    void * a21,
    double a22,
    int32_t a23,
    float a24,
    uint64_t a25,
    double a26,
    uintptr_t a27,
    float a28,
    intptr_t a29,
    double a30,
    uint32_t a31,
    float a32
) {
    uint32_t mismatch = 0;
    if (fp_c_bits32(a01) != UINT32_C(0x3fa00000)) mismatch |= UINT32_C(1) << 0;
    if (fp_c_bits64(a02) != UINT64_C(0xc004000000000000)) mismatch |= UINT32_C(1) << 1;
    if (a03 != -INT32_C(0x75bcd15)) mismatch |= UINT32_C(1) << 2;
    if (fp_c_bits32(a04) != UINT32_C(0x80000000)) mismatch |= UINT32_C(1) << 3;
    if (a05 != UINT64_C(0xfedcba9876543210)) mismatch |= UINT32_C(1) << 4;
    if (fp_c_bits64(a06) != UINT64_C(0x7ff8123456789abc)) mismatch |= UINT32_C(1) << 5;
    if (a07 != (void *)(uintptr_t)UINT64_C(0x1234567887654321)) mismatch |= UINT32_C(1) << 6;
    if (fp_c_bits32(a08) != UINT32_C(0x1)) mismatch |= UINT32_C(1) << 7;
    if (fp_c_bits64(a09) != UINT64_C(0xfff0000000000000)) mismatch |= UINT32_C(1) << 8;
    if (fp_c_bits32(a10) != UINT32_C(0x7f800000)) mismatch |= UINT32_C(1) << 9;
    if (fp_c_bits64(a11) != UINT64_C(0x8000000000000001)) mismatch |= UINT32_C(1) << 10;
    if (fp_c_bits32(a12) != UINT32_C(0x7fc12345)) mismatch |= UINT32_C(1) << 11;
    if (a13 != -INT64_C(0x123456789abcde)) mismatch |= UINT32_C(1) << 12;
    if (fp_c_bits64(a14) != UINT64_C(0x1)) mismatch |= UINT32_C(1) << 13;
    if (a15 != UINT64_C(0xaabbccddeeff0011)) mismatch |= UINT32_C(1) << 14;
    if (fp_c_bits32(a16) != UINT32_C(0xc0200000)) mismatch |= UINT32_C(1) << 15;
    if (a17 != -INT64_C(0x23456789abcdef)) mismatch |= UINT32_C(1) << 16;
    if (fp_c_bits64(a18) != UINT64_C(0x3ff8000000000000)) mismatch |= UINT32_C(1) << 17;
    if (a19 != UINT32_C(0xe2345678)) mismatch |= UINT32_C(1) << 18;
    if (fp_c_bits32(a20) != UINT32_C(0x7fffff)) mismatch |= UINT32_C(1) << 19;
    if (a21 != (void *)(uintptr_t)UINT64_C(0x2345678998765432)) mismatch |= UINT32_C(1) << 20;
    if (fp_c_bits64(a22) != UINT64_C(0x7ff0123456789abc)) mismatch |= UINT32_C(1) << 21;
    if (a23 != -INT32_C(0x6553f10b)) mismatch |= UINT32_C(1) << 22;
    if (fp_c_bits32(a24) != UINT32_C(0xffc54321)) mismatch |= UINT32_C(1) << 23;
    if (a25 != UINT64_C(0x923456789abcdef0)) mismatch |= UINT32_C(1) << 24;
    if (fp_c_bits64(a26) != UINT64_C(0x8000000000000000)) mismatch |= UINT32_C(1) << 25;
    if (a27 != UINT64_C(0xbbccddeeff001122)) mismatch |= UINT32_C(1) << 26;
    if (fp_c_bits32(a28) != UINT32_C(0xff800000)) mismatch |= UINT32_C(1) << 27;
    if (a29 != -INT64_C(0x3456789abcdef0)) mismatch |= UINT32_C(1) << 28;
    if (fp_c_bits64(a30) != UINT64_C(0xfffffffffffff)) mismatch |= UINT32_C(1) << 29;
    if (a31 != UINT32_C(0xfffffffe)) mismatch |= UINT32_C(1) << 30;
    if (fp_c_bits32(a32) != UINT32_C(0x7f812345)) mismatch |= UINT32_C(1) << 31;
    return mismatch;
}
