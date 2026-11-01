# Borrowed text owners and Unicode report staging

Driver: `tests/stdlib_text_bidirectional_resources_execution.rs`.
Root owns all compiler and native commands. Both selectors require Linux
x86_64 ELF output and the shared jump validation before execution.

## Live owner traversal

`owners.lani` constructs one live String at a time, with exactly 4,096 and
262,144 reserved bytes. Each repeats a 32-byte valid UTF-8 pattern containing
all four scalar widths, NUL, U+10FFFF, all six ASCII whitespace bytes, LF,
CRLF, empty lines and an ordinary lone CR. Backing uses a normal allocator
owner; there are no large stack arrays.

Four pure phases per size cover constructor setup and early retirement,
cursor copies, complete alternating scalar pulls, complete alternating word
and line pulls, unchanged source contents and fresh cursor reuse. Every scalar
value and original byte index is checked. Every word/line span and all its
bytes are checked against the fixed input pattern. Exhaustion is checked from
both ends. Early-stopped cursors leave most input unread when they retire.

After all cursors retire, the producer verifies the complete original String,
emits every source byte for independent host comparison, and explicitly
destroys the sole owner. The complete syscall ledger rejects any host service
inside pure phases, any allocation after traversal begins, and any release
before the caller's cleanup marker. It binds the one release to the exact live
address and extent. Each owner must be gone before its retirement marker;
process exit is not accepted as cleanup evidence.

Selector:

```text
borrowed_text_cursors_preserve_live_owners_without_resource_effects_at_two_sizes
```

## Canonical report and real output failure

The report test reads `sample_programs/unicode_text_report.lani`, renames only
its `main` entry, and appends `report_harness.lani`. It calls the sample's
actual `report` function; the reporting algorithm is not copied into a fixture.
The original application input capture and error handling remain covered by
root's existing `unicode_report_reads_validates_and_reverses_text` regression.

At both sizes, the harness checks every source byte before and after reporting,
including length, capacity and fresh forward/backward scalar pulls. The host
compares the complete byte/scalar-count header and scalar-reversed output.
Reporting may perform stdout writes of at most 4,096 bytes; allocation,
release and other host work are rejected. The small workload fills the staging
buffer exactly; the large workload crosses it repeatedly.

One EIO is selected from an actual first payload write in the successful
baseline trace. The preceding normalized effect sequence must match. The
sample must return its existing status 3, preserve its source, and allow one
explicit cleanup. A second, larger report then succeeds in the same process.
The host checks the failed report's confirmed header prefix and the complete
second report. No allocation failure is invented for the borrowed API.

Selector:

```text
unicode_report_borrows_unchanged_input_uses_fixed_staging_and_recovers_write_failure
```

## Runtime evidence

Both resource selectors passed in 12.07 seconds. The root-owned receipt is
`target/stdlib-work/text-bidirectional-resources.log`.

The live-owner gate checked both complete source sizes through eight pure
phases, with exactly two allocations and two explicit releases of their exact
live addresses and extents. No construction, traversal or preservation phase
performed a host operation.

The canonical report harness checked complete reversed output, fixed
4,096-byte staging and four source-preservation phases. Reporting allocated
and released no storage. The baseline-derived payload failure reached write
6, returned status 3, preserved and released the first owner, and successfully
reported the second owner in the same process. The host checked the complete
confirmed output prefix and recovery output.

The original application's canonical stdin regression also passed (1/1) in
6.64 seconds after a separate 1.75-second Rust build. Its receipt is
`target/stdlib-work/text-bidirectional-report-stdin.log`; it covers empty,
ASCII, multibyte/NUL and invalid UTF-8 input with complete output and status
checks.
Static checks confirmed unchanged input-capture/error functions, balanced
producer delimiters, clean diffs and removal of the destructive
pop/reversed-String loop. Bounded independent host controls verified the
complete pattern, scalar offsets and values, explicit six-separator word
partitions, LF/CRLF line partitions and fixed staging:

| Source bytes | Scalars | Words | Lines | Payload staging chunks |
| ---: | ---: | ---: | ---: | ---: |
| 4,096 | 2,944 | 1,024 | 512 | 1 |
| 262,144 | 188,416 | 65,536 | 32,768 | 64 |

Host controls validate fixture expectations; they are not executable Lanius
receipts. This is finite native Linux x86_64 CPU scope, not GPU device
execution, language-enforced lifetime safety, formal verification or a
performance benchmark. The wider stdlib goal remains open.
