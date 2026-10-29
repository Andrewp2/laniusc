# Streaming inflate resource evidence

These Linux x86-64 fixtures execute the Lanius streaming decoder and the actual
owned `ext::compression::decode` API. The Rust driver requires ELF64 x86-64
output and applies the shared native jump validation before execution.

## Fixed workspace and reuse

`stream.lani` allocates two guarded caller-owned workspaces once: 32,769 bytes
and 708 `i32` entries. The decoder borrows only the first 32,768 bytes and 707
entries. The measured total is **35,601 bytes**, including both guard tails.
Input and output use fixed 4,096-byte stack buffers.

Each process decodes eight streams with the same owner: raw DEFLATE, zlib,
concatenated gzip, checksum failure, successful reset after failure, malformed
DEFLATE, empty gzip, and a large gzip stream. The two processes end with 2 MiB
and 4 MiB outputs respectively. Python zlib independently produces and checks
valid streams; the oracle compares every output byte and terminal counters,
including provisional output before the checksum failure. Repeated terminal
calls and reset state are checked, and guard tails remain unchanged.

Markers delimit allocation, borrowed construction, reset, streaming, and
destruction. The syscall ledger requires exactly the two setup mappings and
their exact address/extent releases. This resource trace filters to `read`,
`write`, `mmap`, `munmap`, `mremap`, and `brk`. Among those traced calls,
borrowed construction and reset have none; streaming contains read/write only,
with no allocation or release. The separate [direct decoder full-trace gates](../inflate_stream/README.md)
establish the stronger absence of intervening host effects for their workloads.
This tests fixed workspace across these workloads, rather than claiming a
general proof about every possible execution.

## Reached owned allocation failures

`owned.lani` calls the production owned decoder with a successful gzip stream,
a checksum failure, and invalid zlib FCHECK bytes `78 00`. Three successful
baseline *processes* identify each reached `mmap` ordinal. Every such allocation
is faulted separately, and its complete argument prefix must match the baseline.
The injected call must be reached, no later allocation may occur, and the result
must report allocation failure without output. At the return marker, an error
retains no mapping; success retains only the returned output owner. Destruction
must release that owner too.

The borrowed constructor allocates nothing, so construction OOM evidence comes
from the actual owned API. The malformed-header case explicitly exercises
private workspace allocation before header validation.

## Accepted execution

The root runner accepted both focused tests:

| Group | Native processes | Result | Log | Evidence directory |
| --- | ---: | --- | --- | --- |
| Fixed workspace | 2, containing 16 streams | 1 test passed in 7.51 s; peak 35,601 bytes in both runs | `target/stdlib-work/inflate-stream-resources-fixed.log` | `/tmp/inflate-stream-resources-stream-i_2b6e4e` |
| Owned allocation failures | 31: 3 baselines + 28 reached OOM injections | 1 test passed in 6.39 s | `target/stdlib-work/inflate-stream-resources-owned.log` | `/tmp/inflate-stream-resources-owned-4v4s5wyf` |

These are **33 native processes**, without counting Python controls or compiler
invocations as native fixture cases. Selectors in
`tests/stdlib_inflate_stream_resource_execution.rs` are
`resumable_inflate_reuses_fixed_workspace_across_formats_errors_and_megabyte_streams`
and
`owned_inflate_reached_workspace_and_output_allocation_failures_release_all_private_owners`.
Each Python subprocess is bounded, and the driver bounds each oracle group at
85 seconds. Run `python3 -B oracle.py controls` for independent host-only fixture
and ledger checks. `native_compare.py` is a separate parent-owned performance
comparison; its results are not included in these correctness counts.
