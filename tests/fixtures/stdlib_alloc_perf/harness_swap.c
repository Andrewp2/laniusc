// Raw CPU harness for the runtime allocator (docs/runtime-allocator.md): maps
// the assembled alloc array (as --64 shaders/codegen/lir/x86/runtime_raw_width.s;
// objcopy -O binary -j .text.alloc_bytes) and drives alloc/dealloc/realloc with
// 200,000 tagged random operations, raw mode (R15 = a private argc/argv
// vector). The fixed seed is the sequence that hit the 11-01 corruption;
// forced swapping: every PERIOD rounds
// it pages out one live block of at least 1 MiB with MADV_PAGEOUT (choices
// from a second generator, so the allocator sees the same calls as the
// original). On a mismatch it reports the bad bytes, the block's history and
// the page's /proc/self/pagemap flags.
// gcc -O2 -o harness_swap harness_swap.c
// usage: harness_swap alloc.bin DEALLOC REALLOC [period (0 = no pageout)] [seed (0 = original)]
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
#ifndef MADV_PAGEOUT
#define MADV_PAGEOUT 21
#endif
static uint8_t *code; static uint64_t *vec;
static long DEALLOC, REALLOC;
static uint64_t call3(long off, uint64_t a, uint64_t b, uint64_t c, uint64_t d) {
    uint64_t r; void *f = code + off;
    register uint64_t rdi asm("rdi") = a; register uint64_t rsi asm("rsi") = b;
    register uint64_t rdx asm("rdx") = c; register uint64_t rcx asm("rcx") = d;
    // Step over the red zone before pushing: the allocator code uses the stack.
    asm volatile("sub $128, %%rsp\n push %%r15\n mov %[v], %%r15\n call *%[f]\n pop %%r15\n add $128, %%rsp"
        : "=a"(r), "+D"(rdi), "+S"(rsi), "+d"(rdx), "+c"(rcx)
        : [f] "r"(f), [v] "m"(vec) : "r8", "r9", "r10", "r11", "memory", "cc");
    return r;
}
static uint64_t A(uint64_t n, uint64_t al) { return call3(0, n, al, 0, 0); }
static void F(uint64_t p, uint64_t n) { call3(DEALLOC, p, n, 8, 0); }
static uint64_t R(uint64_t p, uint64_t o, uint64_t n) { return call3(REALLOC, p, o, n, 8); }
static uint64_t rng = 88172645463325252ull, rng2 = 0x2545F4914F6CDD1Dull;
static uint64_t nxt(void) { rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17; return rng; }
static uint64_t nxt2(void) { rng2 ^= rng2 << 13; rng2 ^= rng2 >> 7; rng2 ^= rng2 << 17; return rng2; }
#define N 4000
static uint64_t ptrs[N], sizes[N]; static uint8_t tags[N]; static int born[N]; static long pageouts[N];
static int pagemap_fd = -1;
static uint64_t pagemap(uint64_t address) {
    uint64_t entry = 0;
    if (pagemap_fd >= 0) pread(pagemap_fd, &entry, 8, (address / 4096) * 8);
    return entry;
}
static int report(int i, int round) {
    uint8_t *p = (uint8_t *)ptrs[i]; uint64_t first = ~0ull, last = 0, count = 0;
    for (uint64_t k = 0; k < sizes[i]; k++) if (p[k] != tags[i]) { if (first == ~0ull) first = k; last = k; count++; }
    uint64_t page = (uint64_t)(p + first) & ~4095ull, e = pagemap(page);
    printf("corrupt %d at %lu (page offset %#lx) round %d: %lu bad bytes in [%lu, %lu], first %#x want %#x;"
           " block %p size %lu born r%d, paged out %ld times; pagemap %#lx (present %d swapped %d exclusive %d)\n",
           i, first, (unsigned long)((uint64_t)(p + first) & 4095), round, count, first, last, p[first], tags[i],
           (void *)p, sizes[i], born[i], pageouts[i], (unsigned long)e, (int)(e >> 63 & 1), (int)(e >> 62 & 1), (int)(e >> 56 & 1));
    printf("  bytes around:"); for (uint64_t k = first > 8 ? first - 8 : 0; k < first + 8 && k < sizes[i]; k++) printf(" %02x", p[k]); puts("");
    for (int j = 0; j < N; j++) if (ptrs[j] && tags[j] == p[first]) printf("  slot %d has tag %#x (size %lu, born r%d)\n", j, tags[j], sizes[j], born[j]);
    return 2;
}
int main(int argc, char **argv) {
    FILE *f = fopen(argv[1], "rb"); static uint8_t buf[8192]; size_t len = fread(buf, 1, sizeof buf, f); fclose(f);
    DEALLOC = strtol(argv[2], 0, 0); REALLOC = strtol(argv[3], 0, 0);
    long period = argc > 4 ? strtol(argv[4], 0, 0) : 0;
    if (argc > 5 && strtoull(argv[5], 0, 0)) rng ^= strtoull(argv[5], 0, 0) * 0x9E3779B97F4A7C15ull;
    if (argc > 5) rng2 ^= strtoull(argv[5], 0, 0) + getpid();
    pagemap_fd = open("/proc/self/pagemap", O_RDONLY);
    code = mmap(0, 8192, PROT_READ|PROT_WRITE|PROT_EXEC, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0); memcpy(code, buf, len);
    vec = calloc(16, 8); vec[0] = 1; vec[1] = (uint64_t)"prog"; vec[2] = 0;
    vec[3] = (uint64_t)"LANIUS_ALLOCX=mmap"; vec[4] = (uint64_t)"LANIUS_ALLOC=mma"; vec[5] = 0;
    if (A(0, 8) || A(8, 0) || A(8, 3) || A(8, 16) || R(0, 8, 8) || R(1, 0, 8)) { puts("bad invalid"); return 1; }
    long ops = 0, paged = 0, paged_bytes = 0;
    for (int round = 0; round < 200000; round++) {
        if (period && round % period == 0) {
            for (int tries = 0; tries < 64; tries++) {
                int j = nxt2() % N;
                if (!ptrs[j] || sizes[j] < 1048576) continue;
                if (madvise((void *)ptrs[j], sizes[j] & ~4095ull, MADV_PAGEOUT) == 0) { paged++; paged_bytes += sizes[j]; pageouts[j]++; }
                break;
            }
        }
        int i = nxt() % N;
        if (ptrs[i]) {
            uint8_t *p = (uint8_t *)ptrs[i];
            for (uint64_t k = 0; k < sizes[i]; k++) if (p[k] != tags[i]) return report(i, round);
            if (nxt() % 4 == 0) {
                uint64_t n = 1 + nxt() % ((nxt() % 8 == 0) ? (nxt() % 32 == 0 ? 20000000 : 1200000) : 2000);
                uint64_t q = R(ptrs[i], sizes[i], n);
                if (!q) { puts("realloc failed"); return 3; }
                uint8_t *qq = (uint8_t *)q; uint64_t keep = n < sizes[i] ? n : sizes[i];
                for (uint64_t k = 0; k < keep; k++) if (qq[k] != tags[i]) { printf("realloc lost r%d slot %d at %lu\n", round, i, k); return 4; }
                for (uint64_t k = keep; k < n; k++) if (qq[k] != 0) { printf("realloc tail not zero r%d slot %d at %lu\n", round, i, k); return 5; }
                memset(qq, tags[i], n); ptrs[i] = q; sizes[i] = n; born[i] = round; pageouts[i] = 0;
            } else { F(ptrs[i], sizes[i]); ptrs[i] = 0; }
        } else {
            uint64_t n = 1 + nxt() % ((nxt() % 16 == 0) ? (nxt() % 32 == 0 ? 20000000 : 1200000) : 3000);
            uint64_t al = 1ull << (nxt() % 4);
            uint64_t p = A(n, al);
            if (!p || (p & (al - 1))) { puts("alloc failed/misaligned"); return 6; }
            for (uint64_t k = 0; k < n; k++) if (((uint8_t *)p)[k]) { printf("not zero r%d size %lu at %lu\n", round, n, k); return 7; }
            tags[i] = (uint8_t)(1 + nxt() % 255); memset((void *)p, tags[i], n); ptrs[i] = p; sizes[i] = n; born[i] = round; pageouts[i] = 0;
        }
        ops++;
    }
    for (int i = 0; i < N; i++) if (ptrs[i]) { uint8_t *p = (uint8_t *)ptrs[i]; for (uint64_t k = 0; k < sizes[i]; k++) if (p[k] != tags[i]) return report(i, 200000); }
    uint32_t mode = (uint32_t)(vec[0] >> 32);
    printf("ops %ld mode %s pageouts %ld (%ld MiB)\n", ops, mode == 1 ? "direct" : mode ? "pooled" : "undecided", paged, paged_bytes >> 20);
    return mode > 1 ? 0 : 9;
}
