// C side of the one-field record ABI test. Each record has the System V
// class of its field, so it crosses in one integer register or stack slot.
#include <stdint.h>

typedef struct { uint32_t sequence; } rec_cookie;
typedef struct { void *raw; } rec_handle;
typedef struct { int64_t value; } rec_wide;

static uint32_t rec_table[2] = {1234567u, 7654321u};

rec_cookie rec_c_make(uint32_t value) {
    rec_cookie cookie = {value + 1u};
    return cookie;
}

uint32_t rec_c_read(void *unused, rec_cookie cookie, uint32_t add) {
    (void)unused;
    return cookie.sequence + add;
}

// The record is the seventh integer argument, so it is passed on the stack.
uint32_t rec_c_stack(uint64_t a, uint64_t b, uint64_t c, uint64_t d, uint64_t e,
                     uint64_t f, rec_cookie cookie, uint32_t tail) {
    if (a != 1u || b != 2u || c != 3u || d != 4u || e != 5u || f != 6u) return 0u;
    return cookie.sequence * 2u + tail;
}

rec_handle rec_c_handle(uint32_t index) {
    rec_handle handle = {&rec_table[index & 1u]};
    return handle;
}

uint32_t rec_c_handle_value(rec_handle handle) {
    return *(uint32_t *)handle.raw;
}

rec_wide rec_c_wide(int64_t value) {
    rec_wide wide = {value * 2};
    return wide;
}

int64_t rec_c_wide_difference(rec_wide left, rec_wide right) {
    return left.value - right.value;
}
