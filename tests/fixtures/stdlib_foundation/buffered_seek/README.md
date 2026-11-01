# Buffered Seek runtime and effect gates

**Accepted: all three focused gates passed in 9.95 seconds**, receipt
`target/stdlib-work/seek-buffered-factored-peer.log`. These are ordinary enabled
positive tests in `tests/stdlib_buffered_seek_execution.rs`, with strict x86 ELF,
actual native Linux x86_64 execution and complete syscall observation. Production
is `08212669...`; the scripted peer is `365d8062...`.

The accepted run covers three compilations and seven native lifecycles: reader,
writer, nested baseline, and each of four reached constructor allocation denials.
No compiler, runtime, ABI or proof changes were made for this increment.

## Finite runtime coverage

- `reader_seek_reconciles_read_ahead_and_distinguishes_arithmetic_from_provider_failure`:
  nine phases cover all origins, Current query/absolute reconciliation, signed
  boundary arithmetic that preserves unread bytes, query and second-seek errors,
  malformed acknowledgements, fault publication, inactive state and handoff.
- `writer_seek_orders_complete_flush_and_preserves_partial_or_faulted_progress`:
  twelve phases cover exact write/flush/seek order, confirmed partial output,
  Interrupted/WouldBlock/WriteZero, malformed write/flush counts, post-flush seek
  errors and malformed Start acknowledgements. Accepted bytes are not replayed.
- `nested_seek_transfers_real_buffer_authority_and_reaches_each_constructor_denial`:
  four actual buffer owners, nested reader/writer reconciliation, an allocation
  transferred through Parts and explicitly rebuilt, and each constructor mmap
  denied separately. Every denial must be reached and reported as
  AllocationFailed; preceding owners are released with no peer I/O or seek.

The peer records its real scripted calls and memory effects without host
services. The driver traces every syscall and rejects all host calls inside the
22 total baseline `P/p` phases, including allocation, release and close. Actual
buffer releases must match their acquired full
addresses and extents, with every owner retired before `D` and process exit.
This is finite behavior and effect evidence, not a general lifetime or ownership
proof. Keep borrowed inner streams exclusively available and their backing live;
Parts transfer one explicit buffer cleanup authority.

Related receipts using the same production source:

| Run | Result | Test duration | Local receipt |
| --- | --- | --- | --- |
| Reverse-records application | 4 passed; 86 cases | 8.00 s | `target/stdlib-work/seek-app-projection-helpers.log` |
| Selected existing buffered regressions | 4 passed; 1 filtered | 10.57 s | `target/stdlib-work/seek-existing-buffered-regressions.log` |

The existing regressions cover binary copy and its errors, all four constructor
allocation denials, nested copying and reader behavior. The durations include
compilation, native processes and observation; they are not seek benchmarks.
GPU device execution, other native targets and formal verification are unclaimed.

## Preserved source forms and diagnostic controls

Initial block arms in bare match statements were outside the documented current
language profile. Scalar matches then encountered a full-source projection
failure labelled LNC0005 at the fallback expression. Changing payload names or
using typed zero fallbacks did not admit that source. Two private non-generic,
exhaustive enum projection helpers admit the production generic Reader Seek
implementation. The peer uses the same structure and preserves both Current and
End offset payloads. Public generic bounds, query/arithmetic/fault semantics and
all full behavior assertions remain intact.

The failed forms remain historical source dependencies. Current production and
its complete runtime gates work. Local and imported nested-bound controls, and
both literal/typed-zero controls, execute successfully; the earlier diagnostic
at an unrelated Iterator bound does not establish a general generic restriction.
The responsible compiler pass remains unestablished. No compiler repair or
concrete stream specialization is claimed.

Compact chronology (all failures below occurred before native execution):

| Preserved stage | Result and duration | Receipt under `target/stdlib-work/` |
| --- | --- | --- |
| Original full buffered gates | 0 passed, 3 failed; 3.19 s | `seek-buffered-first.log` |
| Existing reader / application model against that source | Each 0 passed, 1 failed; 2.91 s / 2.64 s | `seek-existing-buffered-control.log` / `seek-app-model-first.log` |
| Import plus local nested/flat controls | 2 passed, 1 failed; 3.98 s | `seek-dependency-controls-first.log` |
| Imported nested/flat controls | 2 passed; 4.05 s; 3 filtered | `seek-imported-dependency-controls-first.log` |
| Exact baseline / Reader-only / Writer-only module isolation | 2 passed, 1 failed; 8.59 s; 5 filtered; only Reader-only failed | `seek-module-snapshot-isolation-first.log` |
| Scalar-arm full gates / import-only | 0 passed, 3 failed; 3.07 s / 0 passed, 1 failed; 2.90 s | `seek-buffered-scalar-match-retry.log` / `seek-buffered-import-scalar-retry.log` |
| Literal/typed-zero minimal controls | 2 passed; 4.86 s; 8 filtered | `seek-wildcard-literal-controls-first.log` |
| Unique-binder import | 0 passed, 1 failed; 2.67 s; 9 filtered | `seek-buffered-import-unique-binders.log` |
| Typed-zero import | 0 passed, 1 failed; 2.91 s; 9 filtered | `seek-buffered-import-typed-zero.log` |
| Production private projections, import-only | 1 passed; 6.01 s; 9 filtered | `seek-buffered-import-projection-helpers.log` |
| Complete gates before peer factoring | 0 passed, 3 failed; 4.98 s; peer projection only | `seek-buffered-projection-helpers.log` |
| Production and peer private projections | **3 passed; 9.95 s** | `seek-buffered-factored-peer.log` |

`tests/stdlib_seek_dependency_execution.rs` retains ten explicitly ignored
**positive** diagnostic probes. Each requires compile and bounded native exit
zero with empty output; a rejected historical source remains a failed test.
They are not green tests asserting compiler bugs, and are not the enabled full
behavior gates above. Run selected probes explicitly with `--ignored`.

The three module-isolation probes copy the actual stdlib tree byte-for-byte and
override only the complete `alloc/buffered.lani` snapshot. Baseline is the exact
module from git HEAD `017b9c052480cd840c0e3948f6fe6378c9d1b8dd`. The driver asserts
that deleting the exact added Seek blocks from stored `full_failed.lani`
reconstructs baseline and each paired one-implementation source. Existing bodies
and every other copied stdlib file stay unchanged. Historical replay is
independent of corrected live production; there are no fake replacement APIs.

## Source identities

Accepted SHA-256 identities:

| Source | SHA-256 |
| --- | --- |
| `stdlib/alloc/buffered.lani` | `08212669340df04f8a6d61d1e17a8af13c7c1d730e01b30ec1f662e3fd302834` |
| `fixture/peer.lani` | `365d80627633b45a88bc173e8ab4c2175d2eb872b54bcf60a91a5afcf2deeac0` |
| `reader.lani` | `957657227775ef0fb8190ca55081c078e1cd6177a9b0aa2192004a625ef5494e` |
| `writer.lani` | `9f1a07045e49c176e6300b4112ec5b0db587a92292d7fc71525ad9ff21ddcf19` |
| `nesting.lani` | `5b0f5dff82d2b27c8b06ad82b1f11c649733624d7b86fe1680f9389dc10bae43` |
| `tests/stdlib_buffered_seek_execution.rs` | `6045e51e00416387546195d61971436c80fa72eaa36f283a1abc574321893676` |

Retained historical sources in `admission_snapshots/`:

| Artifact | SHA-256 |
| --- | --- |
| `full_failed.lani` | `08adf326c59455d3d227ea4e759f5c6e7f2408e750c9375b69520576e77fb34b` |
| `baseline.lani` | `025394873442bfe8b50254db4a4d50273a22a825cde83ff381578b2be0bd269d` |
| `reader_only.lani` | `b9cf1dfd2e4b2a56cd06ce3989a36b048b25b49eb92feb134398ff031f3acb93` |
| `writer_only.lani` | `5aa7f420ff726012d78ca0c7d0c80e841b2116f60c8839820119434e5a2e2397` |
| `peer_failed.lani` | `587ba88bbba731ff0aa4b5a8a5e8e1ce67710dc5be1469b1a8131104f89c12dc` |
| `scalar_failed.lani` | `29de2ee8db9db2bfb5c34a3813edaa599277d3e5323e46a2de1d5969cd543d4c` |
| `peer_scalar_failed.lani` | `9656c0d90139cbcceb6a4f7afb80ce8fef6ca42abd034cfdcf629186d1563f7e` |
| `unique_binders.patch` over `scalar_failed.lani` (source `5a9b162c...`) | `bf13b4c99e53dba0ce119f9c56294f5f65a33273857d641abba18b5dbc0b99c5` |
| `typed_zero.patch` over `scalar_failed.lani` (source `4c4a7a34...`) | `8e15fad7797f08fb0263907cb64b77d327c8297fdfe9f9b834a65967b50b6460` |

Reproduce the accepted gate from the repository root with serialized compiler
access and a command limit below two minutes:

```sh
timeout --kill-after=2s 100s flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
  env CARGO_TARGET_DIR=target/stdlib-build cargo test \
  --test stdlib_buffered_seek_execution -- --test-threads=1 --nocapture
```

For historical module isolation, select `--test stdlib_seek_dependency_execution
snapshot_ -- --ignored --test-threads=1 --nocapture` under the same wrapper. Its
Reader-only rejection is retained evidence, not an active failure of accepted
production or a claim that all nested generic bounds fail.
