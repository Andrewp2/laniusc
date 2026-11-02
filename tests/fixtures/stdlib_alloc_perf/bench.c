// bench.lani's phases on glibc (gcc -O2). `./bench calloc` allocates with
// calloc, which returns zeroed memory as alloc::allocator::alloc does; the
// default uses malloc. realloc is glibc realloc either way.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define PAGE 4096
#define SLOTS 64

static int zeroed;

static uint64_t now(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (uint64_t)t.tv_sec * 1000000000u + (uint64_t)t.tv_nsec;
}

static void *get_block(size_t size) {
    void *p = zeroed ? calloc(1, size) : malloc(size);
    if (!p) abort();
    return p;
}

static uint64_t touch(char *at, long from, long to, uint64_t value) {
    uint64_t sum = 0;
    for (long off = from; off < to; off += PAGE) {
        uint64_t *w = (uint64_t *)(at + (off & ~7L));
        sum += *w;
        *w = value;
    }
    return sum;
}

static uint64_t next(uint64_t seed) { return seed * 6364136223846793005ull + 1442695040888963407ull; }
static long pick_size(uint64_t seed) {
    long base = 1L << (12 + (seed >> 33) % 8);
    return base + (long)((seed >> 41) % (uint64_t)base);
}

static uint64_t fixed(long size) {
    long rounds = 1073741824L / size;
    uint64_t sum = 0;
    for (long k = 0; k < rounds; k++) {
        char *at = get_block(size);
        sum += touch(at, 0, size, 1);
        free(at);
    }
    return sum;
}

static uint64_t mixed(void) {
    char *table[SLOTS] = {0};
    uint64_t sum = 0, seed = 12345;
    for (long k = 0; k < 40000; k++) {
        seed = next(seed);
        int s = (int)((seed >> 20) % 64);
        if (table[s]) {
            free(table[s]);
            table[s] = 0;
        } else {
            long size = pick_size(seed);
            table[s] = get_block(size);
            sum += touch(table[s], 0, size, 1);
        }
    }
    for (int s = 0; s < SLOTS; s++) free(table[s]);
    return sum;
}

static uint64_t grow(long rounds, long step, int doubling, long limit) {
    uint64_t sum = 0;
    for (long r = 0; r < rounds; r++) {
        long size = PAGE;
        char *at = get_block(size);
        sum += touch(at, 0, size, 3);
        while (size < limit) {
            long wanted = doubling ? size * 2 : size + step;
            at = realloc(at, wanted);
            if (!at) abort();
            sum += *(uint64_t *)at + *(uint64_t *)(at + size - 8);
            sum += touch(at, size, wanted, 3);
            size = wanted;
        }
        free(at);
    }
    return sum;
}

int main(int argc, char **argv) {
    zeroed = argc > 1 && strcmp(argv[1], "calloc") == 0;
    const char *labels[5] = {"fixed.4K", "fixed.16K", "fixed.64K", "fixed.256K", "fixed.1M"};
    uint64_t total = 0, t;
    long size = 4096;
    for (int i = 0; i < 5; i++, size *= 4) {
        t = now();
        total += fixed(size);
        printf("%s %llu\n", labels[i], (unsigned long long)(now() - t));
    }
    t = now(); total += mixed(); printf("mixed %llu\n", (unsigned long long)(now() - t));
    t = now(); total += grow(400, 0, 1, 4194304); printf("double %llu\n", (unsigned long long)(now() - t));
    t = now(); total += grow(40, PAGE, 0, 2097152); printf("step %llu\n", (unsigned long long)(now() - t));
    printf("checksum %llu\n", (unsigned long long)total);
    return 0;
}
