#define _POSIX_C_SOURCE 200809L
#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>

/* These are ABI probes, not a runtime or a replacement system library. */
_Static_assert(sizeof(void *) == 8, "the probes require LP64");
_Static_assert(sizeof(int32_t) == 4, "the probes require a 32-bit int32_t");
_Static_assert(sizeof(intptr_t) == 8, "the probes require a 64-bit intptr_t");

static unsigned char buffer[32];
static int initialized;

__attribute__((constructor)) static void initialize_probe(void) {
    initialized = 0x1357;
}

int32_t probe_constructor(void) { return initialized; }

int32_t probe_i32(int32_t value) { return value == INT32_MIN + 37 ? -1700000011 : 0; }
uint32_t probe_u32(uint32_t value) { return value == UINT32_C(0xf1234567) ? UINT32_C(0xe2345678) : 0; }
int64_t probe_i64(int64_t value) { return value == -INT64_C(0x123456789abcde) ? -INT64_C(0x23456789abcdef) : 0; }
uint64_t probe_u64(uint64_t value) { return value ^ UINT64_C(0x923456789abcdef0); }
intptr_t probe_isize(intptr_t value) { return value == -INT64_C(0x3456789abcdef) ? -INT64_C(0x456789abcdef0) : 0; }
uintptr_t probe_usize(uintptr_t value) { return value == UINT64_C(0xfedcba9876543210) ? UINT64_C(0xabcdef0123456789) : 0; }

/* The opaque pointer is compared and transported, never dereferenced. */
void *probe_pointer(void) { return (void *)(uintptr_t)UINT64_C(0x1234567887654321); }
void *probe_pointer_echo(void *value) { return value; }
uint64_t probe_pointer_bits(void *value) { return (uintptr_t)value; }
void *probe_null(void) { return NULL; }
int32_t probe_is_null(void *value) { return value == NULL; }
void *probe_buffer(void) { return buffer; }

void probe_fill(void *destination, uintptr_t count, uint32_t seed) {
    unsigned char *bytes = destination;
    for (uintptr_t index = 0; index < count; ++index) {
        bytes[index] = (unsigned char)(seed + index * 17);
    }
}

uint64_t probe_args6(uint64_t a, uint64_t b, uint64_t c, uint64_t d, uint64_t e, uint64_t f) {
    return 2*a + 3*b + 5*c + 7*d + 11*e + 13*f;
}

uint64_t probe_args7(uint64_t a, uint64_t b, uint64_t c, uint64_t d, uint64_t e, uint64_t f, uint64_t g) {
    return 2*a + 3*b + 5*c + 7*d + 11*e + 13*f + 17*g;
}

uint64_t probe_args8(uint64_t a, uint64_t b, uint64_t c, uint64_t d, uint64_t e, uint64_t f, uint64_t g, uint64_t h) {
    return 2*a + 3*b + 5*c + 7*d + 11*e + 13*f + 17*g + 19*h;
}

uint64_t probe_args9(uint64_t a, uint64_t b, uint64_t c, uint64_t d, uint64_t e, uint64_t f, uint64_t g, uint64_t h, uint64_t i) {
    return 2*a + 3*b + 5*c + 7*d + 11*e + 13*f + 17*g + 19*h + 23*i;
}

uint64_t probe_seed(uint32_t index) { return UINT64_C(0x100000001) + index * 29; }
int32_t probe_imported(int32_t value) { return value * 7 - 11; }

uintptr_t probe_environment_length(void) {
    const char *value = getenv("LANIUS_NATIVE_C_TEST");
    return value == NULL ? 0 : strlen(value);
}

/* Distinct values at every position catch register/stack ordering and width errors. */
void *probe_pointer_at(uint32_t index) {
    static const uintptr_t values[] = {
        UINT64_C(0x1234567887654321),
        UINT64_C(0x2345678998765432),
        UINT64_C(0x3456789aa9876543),
        UINT64_C(0x456789abba987654)
    };
    return index < 4 ? (void *)values[index] : NULL;
}

uint32_t probe_args31(
    int32_t a01,
    uint32_t a02,
    int64_t a03,
    uint64_t a04,
    intptr_t a05,
    uintptr_t a06,
    void * a07,
    int32_t a08,
    uint32_t a09,
    int64_t a10,
    uint64_t a11,
    intptr_t a12,
    uintptr_t a13,
    void * a14,
    int32_t a15,
    uint32_t a16,
    int64_t a17,
    uint64_t a18,
    intptr_t a19,
    uintptr_t a20,
    void * a21,
    int32_t a22,
    uint32_t a23,
    int64_t a24,
    uint64_t a25,
    intptr_t a26,
    uintptr_t a27,
    void * a28,
    int32_t a29,
    uint32_t a30,
    int64_t a31
) {
    uint32_t mismatch = 0;
    if (a01 != -INT32_C(0x7fffffd1)) mismatch |= UINT32_C(1) << 0;
    if (a02 != UINT32_C(0xf1234567)) mismatch |= UINT32_C(1) << 1;
    if (a03 != -INT64_C(0x123456789abcde)) mismatch |= UINT32_C(1) << 2;
    if (a04 != UINT64_C(0x923456789abcdef0)) mismatch |= UINT32_C(1) << 3;
    if (a05 != -INT64_C(0x3456789abcdef)) mismatch |= UINT32_C(1) << 4;
    if (a06 != UINT64_C(0xfedcba9876543210)) mismatch |= UINT32_C(1) << 5;
    if (a07 != (void *)(uintptr_t)UINT64_C(0x1234567887654321)) mismatch |= UINT32_C(1) << 6;
    if (a08 != -INT32_C(0x75bcd15)) mismatch |= UINT32_C(1) << 7;
    if (a09 != UINT32_C(0x80000001)) mismatch |= UINT32_C(1) << 8;
    if (a10 != -INT64_C(0x23456789abcdef)) mismatch |= UINT32_C(1) << 9;
    if (a11 != UINT64_C(0xa3456789abcdef01)) mismatch |= UINT32_C(1) << 10;
    if (a12 != -INT64_C(0x456789abcdef0)) mismatch |= UINT32_C(1) << 11;
    if (a13 != UINT64_C(0xedcba9876543210f)) mismatch |= UINT32_C(1) << 12;
    if (a14 != (void *)(uintptr_t)UINT64_C(0x2345678998765432)) mismatch |= UINT32_C(1) << 13;
    if (a15 != -INT32_C(0x7735940b)) mismatch |= UINT32_C(1) << 14;
    if (a16 != UINT32_C(0xdeadbeef)) mismatch |= UINT32_C(1) << 15;
    if (a17 != -INT64_C(0x3456789abcdef0)) mismatch |= UINT32_C(1) << 16;
    if (a18 != UINT64_C(0xb456789abcdef012)) mismatch |= UINT32_C(1) << 17;
    if (a19 != -INT64_C(0x56789abcdef01)) mismatch |= UINT32_C(1) << 18;
    if (a20 != UINT64_C(0xdcba9876543210fe)) mismatch |= UINT32_C(1) << 19;
    if (a21 != (void *)(uintptr_t)UINT64_C(0x3456789aa9876543)) mismatch |= UINT32_C(1) << 20;
    if (a22 != -INT32_C(0x6553f10d)) mismatch |= UINT32_C(1) << 21;
    if (a23 != UINT32_C(0xc001d00d)) mismatch |= UINT32_C(1) << 22;
    if (a24 != -INT64_C(0x456789abcdef01)) mismatch |= UINT32_C(1) << 23;
    if (a25 != UINT64_C(0xc56789abcdef0123)) mismatch |= UINT32_C(1) << 24;
    if (a26 != -INT64_C(0x6789abcdef012)) mismatch |= UINT32_C(1) << 25;
    if (a27 != UINT64_C(0xcba9876543210fed)) mismatch |= UINT32_C(1) << 26;
    if (a28 != (void *)(uintptr_t)UINT64_C(0x456789abba987654)) mismatch |= UINT32_C(1) << 27;
    if (a29 != -INT32_C(0x53724e11)) mismatch |= UINT32_C(1) << 28;
    if (a30 != UINT32_C(0xfffffffe)) mismatch |= UINT32_C(1) << 29;
    if (a31 != -INT64_C(0x56789abcdef012)) mismatch |= UINT32_C(1) << 30;
    return mismatch;
}

uint32_t probe_args32(
    int32_t a01,
    uint32_t a02,
    int64_t a03,
    uint64_t a04,
    intptr_t a05,
    uintptr_t a06,
    void * a07,
    int32_t a08,
    uint32_t a09,
    int64_t a10,
    uint64_t a11,
    intptr_t a12,
    uintptr_t a13,
    void * a14,
    int32_t a15,
    uint32_t a16,
    int64_t a17,
    uint64_t a18,
    intptr_t a19,
    uintptr_t a20,
    void * a21,
    int32_t a22,
    uint32_t a23,
    int64_t a24,
    uint64_t a25,
    intptr_t a26,
    uintptr_t a27,
    void * a28,
    int32_t a29,
    uint32_t a30,
    int64_t a31,
    uint64_t a32
) {
    uint32_t mismatch = probe_args31(
        a01,
        a02,
        a03,
        a04,
        a05,
        a06,
        a07,
        a08,
        a09,
        a10,
        a11,
        a12,
        a13,
        a14,
        a15,
        a16,
        a17,
        a18,
        a19,
        a20,
        a21,
        a22,
        a23,
        a24,
        a25,
        a26,
        a27,
        a28,
        a29,
        a30,
        a31
    );
    if (a32 != UINT64_C(0xd6789abcdef01234)) mismatch |= UINT32_C(1) << 31;
    return mismatch;
}
