# Direct Unix stream contracts

Pair admission and the corrected direct-contract gate passed in separate runs
recorded below. Root owns compiler, Cargo and subprocess runs.

The first selector executes `admission.lani`: one real AF_UNIX stream pair,
binary bytes in both directions, nonzero byte-view offsets, surrounding
sentinels and one explicit close per owner. Repeated close has no host call.
Named independent peers and fault/effect schedules are separate.

`contracts.lani` has four finite scenarios:

- 2,053-byte pattern transfers through the real 1,024-byte staging boundary,
  both directions and actual byte layouts, nonzero starts and complete
  sentinel checks. Generic Read/Write loops allow at most sixteen calls.
- Cloning, actual descriptor CLOEXEC checks, shared nonblocking/shutdown state,
  pair-endpoint flag independence, take/adoption and one cleanup authority.
- Readiness, initial deadline operations, zero-length requests, logical
  rejection over inaccessible backing, EOF and both half-close directions.
  Closed wrappers check the public method errors, including zero I/O.
- One same-process pathname listener/client/accepted child, exercising
  bind/listen/connect/accept and independent child nonblocking selection.
  Closing leaves the pathname for the driver to observe and clean up.

The admission source remains unchanged. The first broader compile stopped at
a generic `write(...).unwrap()` result chain before native execution. Explicit
typed Result locals retain the generic Read/Write calls and all assertions;
the corrected broader gate passed. A socket-free reduction and control
are retained in [generic_result_chain](generic_result_chain/README.md), with
ignored positive-success compiler follow-up tests in the driver.

The driver requires genuine x86_64 ELF and shared jump checks. It checks atomic
AF_UNIX/SOCK_STREAM/CLOEXEC acquisition, matches acquired descriptors to
explicit closes and rejects allocation or implicit pathname-removal calls.
Evidence is scoped to Linux x86_64 CPU output from the GPU compiler; device
execution, other filesystem/kernel profiles and formal correctness are
unclaimed.

## Executed receipts

| Accepted gate | Actual scope | Result | Log under `target/stdlib-work/` |
| --- | --- | --- | --- |
| Pair admission | One native process, one pair, both directions and owner cleanup | 1 passed, 7.30s | `unix-stream-admission-first.log` |
| Direct contracts | One native process, all four scenarios above and generic Read/Write with typed Result locals | 1 passed, 8.11s; 3 other tests filtered | `unix-stream-direct-final.log` |

Both processes passed descriptor-lifetime and no-allocation/path-removal trace
checks. These are separate receipts, without a combined rerun claim.

The initial direct compile in `unix-stream-direct-first.log` failed with
`LNC0027` before native execution. Its full source is retained only at
`target/stdlib-work/unix-stream-direct-first-contracts.lani`. No production or
compiler change was needed for the typed-local contract fixture to execute.

The explicit ignored compiler-follow-up pair is **dependency evidence, not a
passing gate**: `unix-stream-generic-result-chain-control.log` reported one
failed chained-form test and one passed native typed-local control in 4.67s,
with overall command status 101. The chain failed at `chained.lani:14` with
`LNC0027`; both follow-ups remain ignored and continue to expect successful
compilation and execution. See the reduction guide for the exact boundary.

Retained Lanius SHA-256 identities:

| Source | Hash |
| --- | --- |
| `admission.lani` | `e508397ec51a0d3d192150ad2aa5f387685ecf40bc533ec4653efa9e375f6c7a` |
| Corrected `contracts.lani` | `217d2c638eb9855d5b12681a5d237e9e5770d3f7f1aa0b6ee5ed9681befabe83` |
| Failed full source under `target/` | `ecd6240bf4912ed16ea128dcc3c2993108037a101dab911724389377fe4e5fd3` |
| `stdlib/std/socket.lani` | `44f6739da9be0aa5d28c97dee2c905bca157e237df91c34a0ee6790909c06ccb` |

Accepted gate selectors:

```text
cargo test --test stdlib_unix_stream_execution unix_socketpair_admits_bidirectional_binary_bytes_and_owned_close -- --exact
cargo test --test stdlib_unix_stream_execution unix_stream_direct_contracts_cover_staging_flags_transfer_and_half_close -- --exact
```
