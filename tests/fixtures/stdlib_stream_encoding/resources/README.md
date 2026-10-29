# Stream encoding resource gates

Driver: `tests/stdlib_stream_encoding_resources_execution.rs`.
Contract: `docs/library-stream-encoding-plan.md`.

All three resource gates have accepted native receipts across the initial
invocation and the corrected narrow copy retry.

## Native receipts

Root ran the three selectors in
`target/stdlib-work/stream-encoding-resources.log`: two passed and one failed
in 11.61 seconds, after a 1.77-second Rust build.

- Borrowed JSON passed both text sizes: 798,832 total output bytes, no output
  allocation, and 24 exact allocations/releases including setup and cleanup.
- Owned JSON passed the baseline and both reached denials: `mmap` 13 at
  output site 0 and `mmap` 23 at output site 10. Each failure preserved the
  eight original backing owners and recovered all 786,488 output bytes in the
  same process. The denial/recovery runs observed 23 and 33 exact allocations
  and matching releases, respectively.
- Copy did not execute in that run. Compilation rejected `copy.lani:13` with
  `LNC0021` because its trait impl visibility did not match public
  `core::io::Read`. The only producer correction marks the Read/Write impls
  and their methods public. The byte, ownership, failure and trace contracts
  are unchanged.

The corrected copy selector passed 1/1 in 6.64 seconds after a 0.19-second
Rust build, recorded in
`target/stdlib-work/stream-encoding-copy-resources-revised.log`. Both payload
sizes (4,096 and 262,144 bytes) passed with 4,093-byte scratch, the complete
4,076-byte retained suffix, ten pure phases, and six exact allocations with
six explicit exact releases. Only this selector was rerun; the accepted JSON
producer and driver were unchanged.

The rejected copy producer was
`7991394cc261e295bb7453e790e821dc7f0c24c62a9ee24030a4989c528b5db8`.
Driver and JSON producer hashes remain unchanged from the accepted JSON run.

## Selected observations

### Copy owners and retained pending bytes

Selector:
`resumable_copy_retains_real_owner_storage_and_pending_bytes`

`copy.lani` uses 4,096-byte and 262,144-byte binary payloads. Each run owns
three real allocations: source and sink each have seven guard bytes, and
4,105 bytes back a 4,093-byte scratch subview with five leading and seven
trailing guards. The source and sink are actual typed providers containing
their allocation owners; the sink has enough capacity before copying starts.

Five pure phases per size cover admission and a paused read, a 17-byte short
write followed by `Host(5)`, complete observation of the retained 4,076-byte
suffix, zero-new-input-quota recovery, full drain through actual EOF, source
preservation and provider reuse after the local copier retires. The error
acknowledges no bytes, and the retry drains pending bytes before another read.
The fixture checks confirmed counters, direct call counts, full pending
contents, original source bytes, sink bytes and every guard. The host driver
also compares both complete source and sink outputs to an independent formula.

Exactly three caller allocations per size are expected, with extents
`count + 7`, `4105`, `count + 7`. Only explicit final caller cleanup may release
them. There is no allocation-failure campaign for the allocation-free copier.

### Borrowed JSON output

Selector:
`json_encoder_borrows_live_document_without_output_allocation`

Mode 0 of `json.lani` builds a nine-node document with a 4,096-byte or
262,144-byte text value, a preserved number spelling, booleans, null, nested
containers and owned object keys. The text repeats a valid UTF-8 pattern
containing quote, backslash, NUL, control escapes, an accented scalar and an
emoji. The original text and number owners coexist with the document's
independent copies.

The fixture checks length admission, invalid/zero reads, early retirement,
forked positions, fixed 4,093-byte output chunks and fused EOF. Every emitted
byte is checked against a separately defined wire pattern and then published
for independent host comparison. Output is 12,344 and 786,488 bytes,
respectively. Document traversal verifies every node's kind and relationships,
all keys and value bytes, booleans, empty-container state and unchanged original
owners. No whole-output owner is created.

The final setup has eight live allocations: two text owners, two ten-byte
number owners, seven- and four-byte keys, node storage and scratch. Current
node storage is derived from source: `Node` has fourteen native words,
`core::mem` assigns eight bytes per scalar record word, and nine inserted
nodes grow `Vec` capacity to sixteen, giving `16 * 14 * 8 = 1792` bytes.
`String` contains only its three-word `Vec<u8>` owner. The fixed scratch owner
is 4,105 bytes at both text sizes.

### Owned encode allocation failures

Selector:
`json_owned_encode_reached_allocation_failures_release_only_temporary_output`

Mode 1 establishes a successful baseline on the 262,144-byte document.
The driver selects the first allocation and final growth allocation reached
inside the marked `encode` call. Each mode-2 run denies exactly that baseline
`mmap` ordinal with `ENOMEM`, verifies the complete normalized allocation/free
prefix before denial, and requires every temporary output allocation to be
released before the error returns. The original eight backing owners remain
live and their complete values are checked again.

The same process retries without another injected failure. The recovered
786,488-byte output must be exact. It stays live after document, original
strings and scratch are explicitly destroyed; every output byte is checked
again before final output cleanup. These are two focused output-adapter
failure boundaries, not a repeated parser allocation campaign.

## Trace admission and finite scope

All executables must be ELF x86-64 and pass the shared complete jump validator
before native execution. Full `strace` observation admits only launch, the
single initial mode read where applicable, protocol markers, selected
allocation/free operations, checked stdout writes and successful final exit.
No host call is allowed inside a pure phase. Allocations retain full 64-bit
addresses and exact extents; overlap, unknown or duplicate release, incorrect
release extent and source-owner release by `encode` are rejected. Every
allocation must retire before the explicit cycle-completion marker. Process
exit is not used as evidence of cleanup.

The target scope is Linux x86-64 CPU programs produced by the GPU compiler.
Each native invocation has an 18-second timeout; the owned-output selector
uses one baseline plus two reached-denial/recovery invocations. No user-program
GPU execution, automatic lifetime enforcement, formal proof, nonconforming
provider replay or exhaustive allocation-site coverage is claimed.

## Frozen producer hashes

- Driver:
  `266549fa92ae9b5ddbbd10e6415d357203acf82a5fb0fb9c4de882baa7970dff`
- `copy.lani`:
  `2a93684231965aeb1008b49108f39b29cc77a7c314e007da77b39f047db5df1e`
- `json.lani`:
  `1abe7845d581bb717dbeae4a51f7d35afc5695904769b068f535d3c755a71f5f`
