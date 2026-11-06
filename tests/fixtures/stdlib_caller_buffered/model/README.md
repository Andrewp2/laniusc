# Buffered stream model

`model.lani` executes public `core::buffered` and `alloc::buffered` operations.
`fixture/wire.lani` is a scheduled Read/Write/Seek endpoint and binary recorder;
it contains no buffering implementation. The Python oracle supplies 48 bounded
histories, each repeated through native descending byte arrays (stride -8),
packed caller storage with an interior View (stride +1), and owning wrappers.
Caller capacities are 1, 3, 4, 5 and 7 bytes. Arguments use both physical layouts.

The expected state uses queued bytes with storage-slot labels and a provider
acknowledgement tape. A separate conservation ledger knows only successful
public transfers, provider receipts, explicit abandonment and the retained byte
sequence. It has no buffer cursors or fill/drain algorithm. Route equivalence
is checked after removing physical offsets/strides and unused scratch bytes.

The 1,455 actions include short reads/writes, transient EOF, ordinary errors
(including ordinary Err(InvalidCount)), malformed successful counts and flush
acknowledgements, state precedence, zero requests, partial drain failure,
handoff, empty and faulted restoration, rejected Parts, and explicit cleanup.
Seek histories cover reader Current reconciliation, arithmetic rejection that
retains unread input, query/positioning errors, malformed positions, writer
flush-before-seek and ordinary versus malformed seek failure. Four deterministic
mixed tails per direction vary capacities and operation ordering. The seed is
`0xb0ffe0261121`.

Every step compares complete result metadata, returned and retained bytes,
Parts metadata, selected backing and all caller guards, complete argument
arrays, all 128 provider bytes, positions, counters, and the ordered provider
event tape including each offered write suffix. Truncation, extra bytes,
nonzero child exit and stderr fail verification. Borrowed storage is checked
even after discard; owned backing is observed only while its owner is live.
Native runners explicitly discard remaining stream/Parts owners at case end.
Allocation lifetime accounting belongs to the separate resource fixture.

Host controls accept two independent initial scratch patterns and reject 16
localized serialized corruptions, four behavioral mutations (lost pending
suffix, fault cleared on restore, ordinary InvalidCount made sticky, and
discard clearing caller bytes), truncation and trailing output. These controls
validate oracle signal, not native correctness.

Acceptance: the GPU compiler produced a Linux x86_64 CPU executable, and the
native model test passed all 144 cases, 1,455 actions and 753 provider calls in
6.13 seconds. The receipt is
`target/stdlib-work/caller-buffered-lang-model-retry.log` (one test passed).
Host controls passed with two positive scratch patterns, 22 rejected
corruptions and 2,672,696 expected output bytes; that receipt is the host-control
test in `target/stdlib-work/caller-buffered-lang-model.log`.

Before native acceptance, the producer's unsupported `else if` syntax was
corrected to nested `else { if ... }` blocks, and the Rust runner supplied the
fixture directory as an explicit source root for `fixture::wire`. The initial
rejection was a test-fixture syntax/setup issue. The retry preserved the
histories, oracle and expected byte stream.

Source SHA-256 values for the accepted native receipt:

| Source | SHA-256 |
| --- | --- |
| `model/oracle.py` | `15807b2d3ca1c3401d04698a2e9e21a24fe0490996bc5e8689332260aaab7a1c` |
| `model/model.lani` | `5ff7385d5bedb94649c12dd9f86d8d7fe9d72edaa6318c00e990477f27769261` |
| `model/fixture/wire.lani` | `256cc90e3a1d3047376f79e5d4cb9376d08640f5df78cc7bfb6ce15ac02d51bc` |
| `tests/stdlib_caller_buffered_model_execution.rs` | `a59f8c5c4c2847d27b96a7c45115aa168d972b60d1f3e49882ebcb0ffdaa0668` |
| `stdlib/core/buffered.lani` | `d21dfc851783d4f69f77834c4e44080662bb07eb090af0990ade4c91adb2150a` |
| `stdlib/alloc/buffered.lani` | `e034d16035b015934df9bb20980bdc1344472c9ea3956f45d4bea4f1fa323eb5` |

The first three paths are relative to `tests/fixtures/stdlib_caller_buffered`;
the remaining paths are relative to the repository root. This finite corpus is
evidence for the explored transitions on this target, not exhaustive
verification or a receipt for other targets.
