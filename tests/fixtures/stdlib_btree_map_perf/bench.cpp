// std::map on bench.lani's workload (g++ -O2). Same keys and phases.
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <map>

static const int N = 1 << 20;
static const uint64_t SPREAD = 11400714819323198485ull;

static uint64_t now() {
    return std::chrono::duration_cast<std::chrono::nanoseconds>(
        std::chrono::steady_clock::now().time_since_epoch()).count();
}

template <typename K, typename Key, typename Miss>
static void phases(const char *label, Key key, Miss miss) {
    std::map<K, K> table;
    uint64_t t = now();
    for (int i = 0; i < N; i++) if (!table.emplace(key(i), (K)i).second) abort();
    printf("%s insert %llu\n", label, (unsigned long long)(now() - t));
    t = now(); uint64_t sum = 0;
    for (int i = 0; i < N; i++) sum += (uint64_t)table.at(key(i));
    printf("%s hit %llu\n", label, (unsigned long long)(now() - t));
    if (sum != (uint64_t)N * (N - 1) / 2) abort();
    t = now(); sum = 0;
    for (int i = 0; i < N; i++) sum += (uint64_t)table.at(key((int)(((uint64_t)i * 40503u) % N)));
    printf("%s scattered %llu\n", label, (unsigned long long)(now() - t));
    if (sum != (uint64_t)N * (N - 1) / 2) abort();
    if (sizeof(K) == 4) {
        t = now(); sum = 0;
        for (int i = 0; i < N; i++) sum += (uint64_t)table.at((K)i);
        printf("%s sorted %llu\n", label, (unsigned long long)(now() - t));
        if (sum != (uint64_t)N * (N - 1) / 2) abort();
    }
    t = now(); int found = 0;
    for (int i = 0; i < N; i++) found += table.count(miss(i));
    printf("%s miss %llu\n", label, (unsigned long long)(now() - t));
    if (found) abort();
    t = now(); sum = 0; found = 0;
    for (const auto &item : table) { sum += (uint64_t)item.second; found++; }
    printf("%s iterate %llu\n", label, (unsigned long long)(now() - t));
    if (found != N || sum != (uint64_t)N * (N - 1) / 2) abort();
    t = now();
    for (int i = 0; i < N; i += 2) if (table.erase(key(i)) != 1) abort();
    printf("%s remove_half %llu\n", label, (unsigned long long)(now() - t));
    t = now(); found = 0;
    for (int i = 0; i < N; i++) found += table.count(key(i));
    printf("%s half_hit %llu\n", label, (unsigned long long)(now() - t));
    if (found != N / 2) abort();
    t = now();
    for (int i = 1; i < N; i += 2) if (table.erase(key(i)) != 1) abort();
    printf("%s remove_rest %llu\n", label, (unsigned long long)(now() - t));
    if (!table.empty()) abort();
}

int main() {
    phases<uint64_t>("u64", [](int i) { return ((uint64_t)i + 1) * SPREAD; },
                     [](int i) { return ((uint64_t)i + N + 1) * SPREAD; });
    phases<int32_t>("i32", [](int i) { return (int32_t)(((uint64_t)i * 2654435761u) % N); },
                    [](int i) { return (int32_t)(i + N); });
    return 0;
}
