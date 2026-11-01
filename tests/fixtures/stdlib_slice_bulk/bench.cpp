// bench.lani's phases with the C library (g++ -O2): memcpy, memset,
// std::swap_ranges, memchr, memcmp and vector::insert. The loop phases have
// no C++ counterpart and are omitted. Same 64 MiB in 4 KiB rounds.
#include <algorithm>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <vector>

static const int ROUNDS = 16384, N = 4096;
static std::chrono::steady_clock::time_point start;
static void begin() { start = std::chrono::steady_clock::now(); }
static void report(const char *label) {
    long long ns = std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now() - start).count();
    std::printf("%s\n%lld\n", label, ns);
}

int main() {
    std::vector<uint8_t> a(N), b(N);
    for (int i = 0; i < N; i++) { a[i] = (i * 7 + 1) & 127; b[i] = (i * 7 + 2) & 127; }
    volatile long long check = 0;
    begin();
    for (int r = 0; r < ROUNDS; r++) { std::memcpy(b.data(), a.data(), N); asm volatile("" ::: "memory"); }
    report("u8 copy_from_slice"); check += b[4095];
    begin();
    for (int r = 0; r < ROUNDS; r++) { std::memset(b.data(), r & 255, N); asm volatile("" ::: "memory"); }
    report("u8 fill"); check += b[17];
    begin();
    for (int r = 0; r < ROUNDS; r++) { std::swap_ranges(a.begin(), a.end(), b.begin()); asm volatile("" ::: "memory"); }
    report("u8 swap_with_slice"); check += a[9];
    a[4000] = 255;
    begin();
    for (int r = 0; r < ROUNDS; r++) { const void *p = std::memchr(a.data(), 255, N); check += p ? (const uint8_t *)p - a.data() : -1; asm volatile("" ::: "memory"); }
    report("u8 memchr");
    std::memcpy(b.data(), a.data(), N); b[4090] = 0;
    begin();
    for (int r = 0; r < ROUNDS; r++) { check += std::memcmp(a.data(), b.data(), N) > 0; asm volatile("" ::: "memory"); }
    report("u8 memcmp");
    {
        std::vector<uint8_t> grown;
        begin();
        for (int r = 0; r < ROUNDS; r++) grown.insert(grown.end(), a.begin(), a.end());
        report("u8 extend_from_slice"); check += grown.size() >> 20;
    }
    std::vector<uint64_t> x(512, 3), y(512, 4);
    begin();
    for (int r = 0; r < ROUNDS; r++) { std::memcpy(y.data(), x.data(), 4096); asm volatile("" ::: "memory"); }
    report("u64 copy_from_slice"); check += y[511];
    begin();
    for (int r = 0; r < ROUNDS; r++) { std::fill(y.begin(), y.end(), (uint64_t)r); asm volatile("" ::: "memory"); }
    report("u64 fill"); check += y[5];
    return check == 0;
}
