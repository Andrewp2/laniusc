# Generic Option extraction in a Pair constructor

The first full iterator-comparison admission stopped before producing an ELF:
`LNC0006` at `core::iter` line 512, on `first.unwrap()` inside the generic
`Pair<T,U>` initializer in `eq_by`. The diagnostic reported an unknown type
where generic 35 was expected. The terminal receipt is
`target/stdlib-work/iterator-comparison-admission-first.log`: zero passed,
one failed, 2.60 seconds. This is a source-composition observation, not a claim
that all generic Option methods or Pair constructors fail.

The production correction introduces typed T/U locals using explicit free
`core::option::unwrap<T/U>` before the Pair constructors in `eq_by` and
`partial_cmp_by`, and before the comparator call in `cmp_by`. The public
signatures, bounds, left/right pull order and short circuits are unchanged.
The same production admission then passed one native test in 6.48 seconds.
That acceptance covers the typed full module. The separate smaller probes
below also reproduce the distinction; no compiler root cause is established.

## Smaller direct/control pair

Both files import the actual production `core::option` and `core::pair`.
They call one generic Option<T>/Option<U>-to-Pair<T,U> function at i32/u64,
then return distinct nonzero statuses for incorrect first/second values.
Success means native exit zero with no output.

- `direct.lani` retains method `unwrap()` expressions inside the initializer.
- `typed.lani` changes only extraction to typed explicit free-function locals.

Root ran both probes through the ordinary compiler CLI and production stdlib:

| Probe | Terminal result | Receipt under `target/stdlib-work/` |
| --- | --- | --- |
| `direct.lani` | Compile exit 1 before ELF; `LNC0006` at line 7:60, `first.unwrap()` has unknown type where generic parameter 0 is expected | `iterator-comparison-pair-direct-cli.log` |
| `typed.lani` | Compile exit 0 with an empty log; emitted native program exits 0 with empty stdout and stderr | `iterator-comparison-pair-typed-cli.log`, `iterator-comparison-pair-typed-native.stdout`, `iterator-comparison-pair-typed-native.stderr` |

The two typed-native output files each contain zero bytes. These are positive
source/control probes, not tests that accept a compiler rejection as successful
library behavior. A future compiler repair should allow the direct form too.
The control changes both extraction spelling and intermediate bindings; these
two observations do not isolate which compiler phase or source detail causes
the rejection. No shadow stdlib or alternative compiler roots are used.

The exact commands below were run from the repository root. The compiler binary
was already built. Both compilations and the typed native process terminated;
no pending process is part of these receipts.

```sh
timeout --kill-after=2s 100s flock -w 95 target/stdlib-work/library-gpu.lock \
  target/stdlib-build/debug/laniusc --stdlib-root stdlib --emit x86_64 \
  tests/fixtures/stdlib_compiler_state/iterator_comparison_pair/direct.lani \
  -o target/stdlib-work/iterator-comparison-pair-direct \
  > target/stdlib-work/iterator-comparison-pair-direct-cli.log 2>&1
timeout --kill-after=2s 100s flock -w 95 target/stdlib-work/library-gpu.lock \
  target/stdlib-build/debug/laniusc --stdlib-root stdlib --emit x86_64 \
  tests/fixtures/stdlib_compiler_state/iterator_comparison_pair/typed.lani \
  -o target/stdlib-work/iterator-comparison-pair-typed \
  > target/stdlib-work/iterator-comparison-pair-typed-cli.log 2>&1
timeout --kill-after=2s 10s target/stdlib-work/iterator-comparison-pair-typed \
  > target/stdlib-work/iterator-comparison-pair-typed-native.stdout \
  2> target/stdlib-work/iterator-comparison-pair-typed-native.stderr
```

## Exact original-module reconstruction

`restore-initial.patch` reconstructs the original failed `stdlib/core/iter.lani`
from the frozen typed production source. Its three hunks reverse only the
typed extraction edits. Apply it to a separate copy of the actual stdlib tree;
do not overwrite the working production source or substitute simplified APIs.

| Source | SHA-256 |
| --- | --- |
| Frozen typed production input | `0efff466fc31a96918d9cd55ad69d4073586803608b35bc1d5a7d743a4ba6211` |
| Reconstructed original failed module | `58364304080e0b2b58347d3480a1ed0eba51c5e3f6d9e20ee7f2c801a604ab57` |
| `direct.lani` | `27fc7398e2eead1153c32556fa1c38acf82af6d0c0419751919a84bb6476a0eb` |
| `typed.lani` | `c2c24df9ea4510b6e483c980e45e45fff4ae5702bc66c7f64141a2bffb249e08` |
| `restore-initial.patch` | `967ae8b15c2c68bedc1e09a2291431fc037912e0c07fd8c2b4986d699feafa9a` |

The original is also captured in
`target/stdlib-work/iterator-comparison-initial-failure/core-iter.lani`.
The patch preserves that exact content without committing a second complete
iterator implementation. Production and both classified probes remain frozen.
No compiler, ABI, runtime, proof or comparison contract change is implied.
