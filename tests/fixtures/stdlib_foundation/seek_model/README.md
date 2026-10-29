# Portable Seek arithmetic and cursor model

This fixture checks the portable `core::io` Seek contract through independent
arbitrary-integer arithmetic, a Seek-only scripted provider and materialized
SliceReader/SliceWriter byte states. Production remains Lanius. Python and the
binary adapter are test infrastructure only.

## Independent observations

The `offset_position` reference computes the mathematical sum of a u64 base
and signed i64 offset with unbounded integers, then checks membership in
`0..=u64::MAX`. It does not reproduce unsigned magnitude conversion or
subtraction/addition overflow guards. Inputs cover the full 64-bit domain,
including i64::MIN, exact zero/u64::MAX outcomes and their rejected neighbors.

The Seek-only provider scripts returned positions/errors independently of
actual provider position effects. Every `stream_position` must dispatch one
`Current(0)`; every `rewind` one `Start(0)`. The reference checks cumulative
call transcripts, unchanged full-width payloads, every Error variant, signed
Host payloads, exact-zero rewind acknowledgements and subsequent operations
after failure. Interrupted is propagated without retry. An error or malformed
acknowledgement can follow an observed provider effect; no rollback is assumed.

Reader/writer sequences independently calculate each target from its origin,
admit it to the bounded cursor interval and update materialized byte arrays
only for actual Read/Write operations. They compare every result, cursor,
length, position()/remaining() observation and both complete 32-byte backings
after each action. All three origins, position/rewind helpers, short and empty
transfers, rejected spans, failed seek followed by transfer, and explicit
forged-state recovery are exercised. Native descending and packed ascending
data/auxiliary byte backings appear in all four combinations.

Forged-state cases include negative lengths/cursors, cursor beyond length and
extreme i32 fields. Huge positive logical lengths are used only for seek and
inspection, which must not access backing bytes. Before a subsequent transfer,
the fixture explicitly restores a physically backed length and valid cursor.
The model does not infer validity of backing from a successful seek.

## Finite corpus

There are **17,620 cases**, seed `0x5eeca0261031`:

| Family | Cases | Actions |
| --- | ---: | ---: |
| Full-width offset arithmetic | 8,791 | 8,791 arithmetic calls |
| Seek-only provider dispatch and effects | 197 | 1,576 |
| SliceReader state sequences | 4,316 | 34,528 |
| SliceWriter state sequences | 4,316 | 34,528 |

Arithmetic combines boundary grids, all 64 power neighborhoods, exact
mathematical admission edges and 3,000 seeded input pairs plus edge-derived
pairs, deduplicated before execution. The reference classifies 7,303 accepted
and 1,488 rejected sums. Every non-arithmetic case has eight actions. Memory
cases cover small cursor/origin grids, explicit forged fields and invalid
transfer spans, plus 250 seeded sequences across both reader/writer types and
four backing combinations. These are finite reference classifications.

CPU controls pass literal MIN/MAX arithmetic, interrupted dispatch with prior
effects, malformed rewind acknowledgement, signed Host error preservation,
failed-target cursor preservation, read-after-seek bytes and forged-state
recovery. Seven deliberately corrupted arithmetic, call, effect, Host, cursor,
backing and written-byte observations are rejected.

## Protocol and acceptance

Each input packet is 40 little-endian u64 words: an eight-word header and up
to eight four-word actions. Signed fields retain their complete bit patterns.
Output begins with family, backing policy and case identity. Arithmetic emits
its result and original operands. Provider cases emit result, actual position,
call count and cumulative origin/argument records after each helper. Memory
cases emit result, cursor/length/inspection values and both complete backings
after each action. The oracle checks exact framing and prints the complete
case and seed on mismatch.

The native gate passed on its first attempt: **1 registered test in 5.01s**,
reporting **17,620 cases / 4 families / 4 memory backing combinations** at seed
`0x5eeca0261031` from the native process. The receipt is
`target/stdlib-work/seek-model-first.log`. Exact result, provider-effect,
cursor and complete byte-state comparisons execute, beyond compilation.

The registered Rust test is
`independent_seek_models_match_full_width_positions_dispatch_and_byte_state`
in `stdlib_seek_model_execution`. It checks executable ELF admission before
publication and uses shared strict x86 jump validation, one batched native
process, an 85-second outer timeout and a 70-second child timeout. Accepted
scope is finite native Linux x86_64 CPU output from the GPU compiler. File and
allocating buffered Seek behavior have separate gates. No direct GPU-device,
arbitrary-target, automatic ownership or formal verification claim is made.

Frozen tested identities (SHA256):

| Source | SHA256 |
| --- | --- |
| `stdlib/core/io.lani` | `16f3f761235ed7e3e0cde154e5a45555d55f09fa69e94507b2744c41227def31` |
| `model.lani` | `15a7ae3e167c901d10462290670abb1a9d348821371c470f53b0c773cba4a0d2` |
| `oracle.py` | `b6e6ed622b266531596455ce47048efa156e67dcf0a8de9ee6797848a69df164` |

```sh
python3 -B tests/fixtures/stdlib_foundation/seek_model/oracle.py controls
cargo test --test stdlib_seek_model_execution independent_seek_models_match_full_width_positions_dispatch_and_byte_state -- --nocapture
```
