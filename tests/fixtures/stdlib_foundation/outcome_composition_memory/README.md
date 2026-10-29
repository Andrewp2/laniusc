# Outcome composition owner and effect witness

`owners.lani` exercises eager composition with six actual generic owned
records. Each contains one independently allocated String and Vec, plus a
borrowed nonzero byte subview, an exact f64 signaling-NaN payload and a nested
optional flag. The element types include i32, u64, u8 and f32; the f32 Vec
contains a signaling NaN, negative zero and a subnormal bit pattern.

## Finite coverage

Seven phases exercise free functions and methods for:

- Cross-type `Option.and` and `Result.and`.
- `Result.or` with a changed owned error type and distinct same-type success
  owners, so selecting the wrong side cannot pass an identity check.
- Nested Option flatten and nested Result flatten, including inner and outer
  owned error sources.
- Both transpose directions and their inverse compositions, with absent,
  successful and owned-error cases.

Each selected payload retains its original String/Vec backing identity,
contents, lengths and capacity. Caller copies retain their original variants
and payloads, including owners discarded by eager selection. Borrowed views
retain their nonzero starts, actual positive/negative strides and guarded
contents. Float payloads are compared by exact bits, without floating arithmetic.

The six original records retain sole explicit cleanup authority. Results are
shallow aliases and are never treated as additional independent owners. All
alias checks finish before the originals release their twelve actual backings.

The Rust driver traces every syscall. No host call is permitted between each
`P/p` phase pair, including allocation or destruction. It observes twelve
unique setup mappings, requires every one to stay live through all seven
phases, and matches each final release by full address and extent. All owners
must be released before `D`; only process exit follows it. This is finite
owner/effect evidence, not an allocation-failure, lifetime or ownership proof.

## Accepted receipt and corrected fixture assumption

The registered gate
`outcome_composition_keeps_real_owner_identity_and_cleanup_without_phase_host_calls`
passed: **one test in 7.28 seconds**, with six records, twelve actual backings,
seven pure phases and twelve matching explicit releases. Receipt:
`target/stdlib-work/outcome-composition-memory-final.log`. The instrumented
whole-process duration was 12 ms; it is not a composition-kernel benchmark.

The first run trapped on a fixture assertion requiring Vec capacity 3 for
three elements. `Vec::from_view` uses a minimum initial growth capacity of 4;
the original mapping extents confirmed that behavior. The fixture now checks
that capacity equals the original owner's actual capacity and is at least its
length. Identity, contents and exact release-extent checks were retained.
This was a fixture expectation error; no production or compiler fix was needed.
The failed source snapshot is local debug material at
`target/stdlib-work/outcome-owners-failed-first.lani`.

Accepted SHA-256 identities (driver before later formatting-only changes):

| Source | SHA-256 |
| --- | --- |
| `stdlib/core/option.lani` | `8b3cf42862f2c6c0203281d5b2b120124c0df74d1b0c664418f5a6e9f57938ee` |
| `stdlib/core/result.lani` | `1a036786910bdcb2f637a1d5e89d08881c2a2dea758beadc488065f8b23e748b` |
| `owners.lani` | `b634a06a85de13e693c69251766504f7f037f8442692be32ffb956f56e5c9a5e` |
| `tests/stdlib_outcome_composition_memory_execution.rs` | `005d3edf81108cc5bbfeacb116f658f1694452a4997f9c0023028800e581f6fb` |

The accepted target is native Linux x86_64 executable output from the GPU
compiler. GPU device execution, other targets and formal verification remain
unclaimed. Keep borrowed backing live and preserve one cleanup authority per
actual owner.

Reproduce from the repository root with serialized compiler access and a
command limit below two minutes:

```sh
timeout --kill-after=2s 100s flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
  env CARGO_TARGET_DIR=target/stdlib-build cargo test \
  --test stdlib_outcome_composition_memory_execution -- --test-threads=1 --nocapture
```
