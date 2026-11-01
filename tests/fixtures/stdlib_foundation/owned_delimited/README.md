# Bounded owned delimiter and line direct contracts

All four registered tests are accepted across three separate commands:

| Receipt under `target/stdlib-work/` | Accepted scope | Time |
| --- | --- | --- |
| `owned-delimited-admission-first.log` | One generic admission test and native process | 6.67s |
| `owned-delimited-direct-first.log` | One capability-bound test with two marked LNC0008 rejections; this command also had two pre-native fixture failures | 7.72s for the mixed batch |
| `owned-delimited-direct-retry.log` | Two corrected native runtime tests; admission and capability-bound tests filtered | 8.82s |

The admission followed a 37.40s driver build caused by the selected target
directory. Root ran compiler, Cargo and native commands; fixture authors
performed static review only. Independent model, resource, guarded-backing and
application gates have separate receipts.

The first broader batch (`owned-delimited-direct-first.log`, 7.72s) passed the
two-fixture capability-bound gate. Its two runtime fixtures stopped before
execution with LNC0005 on payload wildcard patterns followed by fallback arms.
The existing [minimal reproduction](../repro_payload_wildcard.lani) and
[dependency ledger](../../../../docs/library-dependencies.md) describe this
compiler limitation. The fixtures now bind those payloads and use typed match
locals, preserving all behavior and expectations. Both corrected native runtime
gates passed on the next attempt; the original mixed batch was not green.

The admission uses a BufRead-only provider through generic functions for both
public collectors, including a nested Result/Option return. One coalesced fill
can contain later records: the binary NUL record, valid LF text and malformed
LF text are consumed separately. Exact bytes, provider calls and positions,
retained malformed text, empty EOF at a zero byte cap, and repeated cleanup
are asserted. Successful and failed records retain their historical progress
after cleanup.

`contracts.lani` contains six finite scenario functions. They cover binary NUL,
native descending and packed ascending bytes through nested/nonzero-start
Views, exact included-delimiter caps, observed EOF at exact caps, and unconsumed
overlong suffixes. Literal fill/consume traces and positions distinguish the
copied prefix from confirmed consumption. Fill Interrupted is retried; consume
Interrupted is terminal. Native errors and all three invalid successful consume
counts retain their staged bytes. Invalid metadata after earlier progress wins
over exhausted byte/call allowances. The script deliberately leaves its state
unchanged for invalid counts; it makes no public broken-provider rollback claim.

UTF-8 cases split Euro and emoji scalars across fills, preserve NUL and CRLF,
distinguish empty EOF from LF-only text, and retain malformed terminal text with
its exact byte offset and ending. Source errors, limits and rejected consume
take precedence over malformed incomplete text. Returned String storage and
capacity survive explicit transfer into a Vec, and returned record owners stay
usable after the actual buffered provider is discarded.

`bounds.lani` uses inaccessible backing to assert descriptor validation before
EOF, byte limits, consume budget or any backing read. Negative limits and zero
call quotas cause no provider calls; valid empty EOF needs one fill even with a
zero byte cap. Final nonempty fills at a byte/call cap are not scanned, copied,
allocated or consumed. The u64::MAX call allowance is configuration admission
followed by one actual EOF observation, not an exhaustive 2^64-call execution.
Two negative fixtures require LNC0008 at the marked collector call: implementing
Read alone does not provide BufRead.

The native harness checks x86_64 ELF and shared jump boundaries, traces every
syscall, permits only process entry/exit and matched owner mmap/munmap, and
requires no live allocations at exit. The separate bounds gate permits no
allocation at all. All three accepted native processes satisfied these checks.

Accepted fixture and production source hashes:

| Source | SHA-256 |
| --- | --- |
| `admission.lani` | `ed8d097eee8601102c77e0692cf444da65e984e09e3a93a827dc43ff6318c5e9` |
| `contracts.lani` | `4cf92a23ba944774c5aefd1a91c1941d4abf2eee0dbc32606e9bdb2c0b247799` |
| `bounds.lani` | `4b79443eefe831aec971c2c02fb35dd3ee2ae0dcc5b97558a6f7936ba871afa8` |
| `negative_read_until.lani` | `4f2cb5d8a55eb7b2390b96c7141df2da750f94873acb117546e6b7765fde3ff9` |
| `negative_read_line.lani` | `fffc7734108fc83bc6885f7913712972b5212fa8b736dd66dfffb77f55b495e1` |
| `stdlib/alloc/io.lani` | `9eeb63f40cc582d192afa43e5b2e65ffa209bbfc63d6893a3f0af155377b7392` |

```text
cargo test --test stdlib_owned_delimited_execution owned_delimited_bufread_only_generic_records_execute_admission -- --exact
cargo test --test stdlib_owned_delimited_execution owned_delimited_executes_scripted_records_progress_limits_and_terminal_text -- --exact
cargo test --test stdlib_owned_delimited_execution owned_delimited_rejects_unreadable_descriptors_and_limits_without_allocation -- --exact
cargo test --test stdlib_owned_delimited_execution owned_delimited_collectors_require_bufread_not_sequential_read -- --exact
```

The accepted target is native Linux x86_64 CPU execution of output
from the GPU compiler. GPU device execution, other targets, automatic owner
cleanup and formal verification require separate evidence.
