# Randomness vector provenance

`random_vectors.txt` was generated on 2026-10-23 with the authors' public-domain
C implementations, compiled with `cc -O2 -std=c11`. C is only the independent
vector-generation reference. The production library and executable fixtures
implement and exercise randomness in Lanius; normal tests need neither C nor
network access.

Sources fetched and SHA-256 digests:

- [Blackman/Vigna xoshiro256++ 1.0](https://prng.di.unimi.it/xoshiro256plusplus.c):
  `c60fa97279fea9da87b0ffa047eccb6f85d66102ce559aaed8bb5a7217809919`
- [Vigna SplitMix64](https://prng.di.unimi.it/splitmix.c):
  `920282fcf60da413d5d823b4049b4962db16816de59d5cc63507d816f2938742`
- Checked-in vector text:
  `6b3da013e26a4fc28c69e33123a3c5ba415afafe527a90aada432470ae56d6c0`

The xoshiro source was retained through the end of `long_jump`, excluding its
later arbitrary-jump implementation and `f2x.c` dependency. SplitMix's `next`
function was renamed `seed_next`; its algorithm was unchanged. The original
public-domain notices were retained in the temporary combined reference source.
Append this driver after those two source bodies to regenerate the data:

```c
#include <stdio.h>
#include <inttypes.h>
static void emit(uint64_t value) { printf(" %" PRIu64, value); }
int main(void) {
    const uint64_t seeds[] = {
        0, 1, 42, UINT64_C(0x8000000000000000),
        UINT64_MAX, UINT64_C(0x123456789abcdef0)
    };
    for (unsigned k = 0; k < 6; k++) {
        x = seeds[k];
        for (int i = 0; i < 4; i++) s[i] = seed_next();
        printf("%" PRIu64, seeds[k]);
        for (int i = 0; i < 4; i++) emit(s[i]);
        for (int i = 0; i < 4; i++) emit(next());
        jump(); emit(next()); emit(next());
        long_jump(); emit(next()); emit(next());
        for (int i = 0; i < 4; i++) emit(s[i]);
        puts("");
    }
    return 0;
}
```

Each line contains 17 unsigned decimal fields: seed, initial four-word state,
four raw outputs, two outputs after jump, two after long_jump, and final
four-word state. The jumps act on the state left by preceding draws. There is
no reset between phases. The Rust model and Lanius mode-5 fixture must both
match these fixed vectors before the larger model comparisons are accepted.
