# Borrowed TOML serialization gates

Driver: `tests/extended_toml_streaming_execution.rs`.
Contract: `docs/library-toml-streaming-plan.md`.

All four native groups passed across the focused invocations below.
Independent source/driver review passed at the frozen hashes below, with no
additional runs or edits requested. Root alone runs compiler/native commands. Rust
formatting and host-only controls for literal sizes, escaped bytes and TOML
value preservation passed; those controls do not replace native evidence.

## Admission receipt

`toml_borrowed_encoding_and_atomic_buffer_native_admission` passed 1/1 in
7.27 seconds after a 1.16-second Rust build, recorded in
`target/stdlib-work/toml-streaming-admission.log`. It checked all 34 canonical
bytes, two pure phases, and eleven exact allocations/releases. Native process
time was 0.013950 seconds; compilation was 7.251007 seconds. Production TOML
was `42c8aa81960ea6a8e1ed37faba369c1f23008cf3f9af5fb9baaaf42362951801`.

The admitted driver was
`b8d6a51c7d36730e7ae4d2271f39c42c8a403399315240666775bc90a1616b21`.
Later additions leave the admission selector, producer and shared runner/ledger
unchanged. That admission is not repeated merely for added selectors.

The fixture retires the original parse input, measures the live document,
reads through the canonical Read interface, fills a guarded native byte-array
view directly, and obtains an owned encoding. The final complete output is
checked and published after document destruction, with only its independent
result owner live.

## Initial contract compile failure

The first contract selector failed compilation with LNC0027 in the generic
helper below, before native execution. The run took 4.21 seconds after a
1.23-second Rust build and is recorded in
`target/stdlib-work/toml-streaming-contracts.log`. The fixture omitted an
explicit core::result import and chained `unwrap` on a generic trait result:

```text
fn pull<R>(reader:&R,bytes:[u8],start:i32,count:i32) -> i32
    where R:core::io::Read { return reader.read(bytes,start,count).unwrap(); }
```

The correction adds that import and binds the call to an explicit
`Result<i32,core::io::Error>` before `core::result::unwrap`. These two changes
do not isolate the cause; this remains an unresolved inference/import
dependency, not a demonstrated runtime or serializer defect. The generic Read
bound and all behavior assertions are unchanged. No compiler changes or
additional isolation campaign are part of this increment.

## Reader and atomic caller-buffer contracts

Selector:
`toml_streaming_ranges_work_caps_copied_states_and_atomic_guards_execute`

`toml_streaming_contracts.lani` uses actual descending native byte arrays and
packed ascending destinations, both at nonzero offsets. It copies cursor
positions inside a control escape, two- and four-byte UTF-8 scalars, and a
trimmed temporal fraction. Generic Read calls and single-byte versus bulk
reads must return all expected bytes and exact remaining counts. Invalid
negative/overflowing ranges precede zero or fused EOF handling and preserve
the complete destination and cursor state. Valid zero reads are inert. Whole
destination and guard checks cover both direct caller-buffer layouts.

The public options witness parses `a='` followed by sixteen literal TAB bytes
and a closing quote/newline. Its canonical output has N = 103 bytes and
W = 104 work units: one nonroot node plus 103 emitted bytes. Fresh public parse
options exercise measurement at W - 1/W and reader/owned/caller-buffer
admission at 2W - 1/2W. No document options are mutated after parsing.

Invalid caller metadata precedes semantic/output preflight. Caller capacity
102 rejects before replay-work reservation, leaving all 116 destination bytes
unchanged. A configured output cap 102 paired with work 102 yields WorkLimit
before the cap is reached; work 103 reaches the cap and yields OutputLimit
before charging the next byte. These are generator-order errors, not a claim
that either limit universally wins. Empty live documents emit no bytes and
allocate no output; destroyed documents reject admission. The accepted group
has nine source-owner cycles and ten pure phases, with no output allocation.

The corrected contract selector passed 1/1 in 7.67 seconds after a 0.19-second
Rust build, recorded in `target/stdlib-work/toml-streaming-contracts-rerun.log`.
It observed 54 exact allocations/releases, 0.018629 seconds native process
time and 7.651794 seconds compilation. Only the generic helper import/typing
changed from the failed compile; all behavior checks remained.

## Live document and borrowed storage

Selector:
`toml_borrowed_readers_and_caller_encoding_preserve_live_document_without_allocation`

`toml_streaming_resources.lani`, mode zero, parses real 4,096- and 262,144-byte
payloads containing quotes, backslashes, literal TABs and multibyte Unicode.
The original parse input is destroyed before serialization. The immutable
document also contains an array, Boolean, integer, nested table/string and
local time with a redundant fractional tail.

Every node kind, child/sibling relationship, key, number and temporal spelling,
decoded payload byte, and structured temporal value is rechecked. Early cursor
copies retire without releasing document storage; a fresh reader drains all
bytes through 4,093-byte requests. `encoded_len`, construction, reads and
direct `encode_into` run in phases forbidding every host effect. The caller
supplies a guarded full destination for `encode_into`; this is an explicit
caller allocation, not encoder staging. The reader itself has fixed state.

The two canonical outputs have 5,939 and 376,883 bytes. Both the reader and
caller-buffer paths publish their complete output, for 765,644 compared bytes
and 99 pure phases. Every actual publication retains exactly the sealed
document and caller-owner set. Final explicit cleanup releases them once.

The borrowed selector passed 1/1 in 8.00 seconds after a 0.21-second Rust build,
recorded in `target/stdlib-work/toml-streaming-borrowed.log`. All 765,644 bytes
matched; 54 exact allocations/releases covered setup and final cleanup with
no output allocation during borrowed phases. Native process time was 0.737408
seconds; compilation was 7.257946 seconds.

## Reached owned-output failures

Selector:
`toml_owned_encoding_reached_collector_failures_preserve_document_and_recover`

Resource modes one and two use the large document without caller scratch or
caller output owners. The successful baseline identifies the collector's
initial reservation and final growth reservation. Two separate runs deny
those reached allocations. Each run compares the complete normalized effect
prefix against its baseline, checks partial-output cleanup before Err, and
requires exactly the original document owners to remain live.

Complete document queries and payload bytes survive failure. A fresh borrowed
reader remains admissible, and owned encoding retries against that same
document in the same process. After success the document is destroyed; all
376,883 result bytes are checked and published while the independent result
is the only live allocation, then explicitly destroyed. This is one baseline
plus two selected denial processes, not a parser-wide allocation campaign.
No allocation failures are fabricated for allocation-free borrowed APIs.

The owned selector passed 1/1 in 9.61 seconds after a 0.18-second Rust build,
recorded in `target/stdlib-work/toml-streaming-owned.log`. Its baseline observed
38 exact allocations/releases and took 0.506311 seconds native time. Initial
output reservation `mmap` 29 (site zero) and final growth `mmap` 38 (site nine)
were each denied in separate executions. Both preserved all eight original
document owners and recovered the complete 376,883-byte result. The denial
runs observed 38 and 47 exact successful allocations/releases and took
0.655495 and 0.725988 seconds native time. Compilation took 7.717916 seconds.

Together the four accepted selector identities account for six native
processes: admission, corrected contracts, two-size borrowed execution, and
one owned baseline plus two denial/recovery processes. The initial contract
compile failure produced no native run. Accepted groups were not rerun as
extra evidence.

## Layout, trace and target scope

The ledger tracks full-width addresses and exact requested extents, rejects
overlapping live mappings, unknown/double releases and wrong extents, and
requires no live owner at each explicit retirement marker. Process exit is
not cleanup evidence. Sealed borrowed phases cannot allocate or release;
owned calls cannot release original document backing. Every publication's
live owner set is checked independently of fixture control flow.

Source-derived live document extents are: eight Node entries at eighteen
native words each (8 × 18 × 8 = 1,152 bytes), the payload reservation, exact
bare-key substrings of 7/4/1 bytes, four-byte number and short-string owners,
and the fifteen-byte temporal token. Borrowed mode additionally owns 4,105
scratch bytes and N + 13 caller-output bytes. Exact extents reflect the current
source and native record layout, not page-rounded memory or a promised future
growth schedule. Parse setup effects are tracked and all superseded allocations
must be released; fault selection concerns only marked output construction.

Artifacts must be ELF x86-64 and pass the shared complete jump validator.
Every native process has an eighteen-second bound. Timings include tracing,
setup, checks, publication and cleanup and are reported separately from
compilation; no isolated encoder benchmark or asymptotic claim follows.
Initial support is Linux x86-64 CPU binaries emitted by the GPU compiler.
Device execution, other hosts, enforced borrowing and formal proof need
separate evidence. Valid live immutable document backing and disjoint valid
destinations remain caller preconditions; these tests add no forged-tree
validator. Broad byte/state model and normalizer coverage have separate gates.

## Frozen hashes

- Driver: `cbb099867d2a3d9105ec6ad2d6dbc1c9fc275b55dcde27f1e8746176474ae0d8`
- Admission: `44a0c24764bd5f1af5f69b10d93f19ef9c55897538cc67a76b71ea6c7dfd3c26`
- Contracts: `081b141477aff9fa17ef8365cb555a7ddd32ba7a971044334125e359be5fd443`
- Resources: `db9ae89d1ad0c96407ec4c5f9054c578b5e7522b341632fa1859bea4416d59f5`
