# M5: a generator against hand-written iterators

Three programs sum the squares of the odd numbers below 200000000 (the
checksum wraps at 64 bits):

- `src/iter_gen.lani` pulls them from a `gen fn`, which elaborates to a
  machine (docs/state-machines-design.md, M5).
- `src/iter_adapters.lani` pulls them through `core::iter`'s `filter` and
  `map` over a counting `Iterator`, as the standard library's adapters are
  written today.
- `src/iter_hand.lani` pulls them from one hand-written struct whose `next`
  fuses the count, the filter and the square.

Built with

    laniusc --stdlib-root stdlib --emit x86_64 SRC.lani -o bin/NAME

and timed with `../machines_m0/run_bench.py bin 5 iter_gen iter_hand iter_adapters`
on the laptop (`machine_info.json`). `results.tsv` holds the times.

| Program | Min (s) |
|---|---|
| `iter_adapters` (`core::iter` filter and map) | 9.895 |
| `iter_gen` (`gen fn`) | 3.899 |
| `iter_hand` (one fused `next`) | 1.086 |

The generator is 2.5 times faster than the adapter chain it replaces and
3.6 times slower than the fused loop.

## Where the generator's time goes

The backend keeps every temporary in a stack slot, so time follows the
instructions each item runs. `src/lowering/` holds the generator's
elaboration written out by hand (`a`), then with one layer removed at a time
(3 runs each):

| Variant | Min (s) |
|---|---|
| `a`: as elaborated, `next` calls `step`, `step` calls the state's handler, the handler matches the event | 3.869 |
| `b`: `next` matches the state itself | 3.545 |
| `c`: and the handlers have no event match | 3.199 |
| `d`: and the handlers' code is inlined into `next` | 2.965 |
| `e`: and the yield's locals are fields, the state a plain tag | 2.620 |
| `h`: one `next` with no state at all, locals loaded and stored back | 1.695 |

Lowering changes recover at most `a` to `e`, 1.5 times. The rest is the
backend: `h` and `iter_hand` do the same work and differ by 1.6 times in how
their locals move through stack slots.
