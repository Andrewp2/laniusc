# Response files and owned arguments

Status: implemented with focused executable acceptance on native Linux x86_64.
The complete standard and extended library goal remains open.

Response files are an optional preprocessing step for the existing
[option parser](extended-cli.md) and [command parser](extended-cli-commands.md).
Their decoded argument views use the same input contract as host argv. Neither
parser gains a second interpretation of options or `--`.

| Module | Owns |
| --- | --- |
| `ext::response` | Pure byte grammar, measurement, caller-buffer decoding and decoded-to-raw byte mapping |
| `ext::cli_response` | Generic provider-driven expansion, stable owned argument storage and source diagnostics |
| `ext::cli_response_files` | Explicit native file loading through a borrowed directory descriptor |

## File syntax

Space, tab, CR and LF separate arguments. Matching single/double quotes group
bytes; adjacent quoted and bare pieces concatenate. Empty quoted arguments
are retained. Backslash quotes the next byte inside or outside quotes, including
literal newlines. NUL, a trailing backslash and an unfinished quote are errors
with raw byte offsets. Non-UTF-8 bytes are preserved. `#`, `$`, `*` and `~`
are ordinary bytes. There is no comment, environment, wildcard or BOM processing.

This is an explicitly strict Lanius format. The
[contract plan](library-response-files-plan.md#purpose-and-source-context)
records its established source precedents and deliberate differences.
Original argv entries are already separate tokens and are never quote-decoded.

After decoding, `@path` expands a file in place, depth first. `@` alone is
literal. `@@text` emits `@text` without expanding it again. Quoting or escaping
an @ does not prevent expansion; use the doubled form. `@-` names the file `-`.
Expansion applies to all tokens, including required option values and tokens
after `--`; the option parser interprets the resulting arguments afterward.

## Pure caller-buffer operations

`response::measure(input)` returns the decoded byte and token counts.
`tokenize_into(input, bytes, spans)` checks complete syntax, both logical output
ranges and both capacities before writing. Every error preserves both output
stores. Success writes only the measured prefixes, adds no NUL and preserves
tails and outside-view bytes. A Span records raw start/length separately from
decoded start/length. All offsets are logical, independent of backing starts
or signed element strides.

`raw_offset(token, decoded_byte)` requires exactly one token without surrounding
separators. It maps each decoded byte to the actual raw byte after quote/escape
removal. The endpoint, including an empty quoted token, maps to the raw token's
end. Input and output stores must be disjoint, with valid physical backing;
logical checks cannot prove backing or enforce lifetimes.

## Expansion ownership and errors

Create one `Expansion` with `cli_response::empty()` and call its generic
`prepare(arguments, provider, limits)`. The provider implements
`Provider<H>::load(path, maximum_bytes) -> Result<Vec<u8>,H>`, transferring an
independent content owner on success and its error on failure. There are no
host calls in the expansion module itself.
The provider must not retain a borrowed request path; returned owner/error
storage that outlives the call must be independent of expansion backing.

Preparation validates all initial argv descriptors, limits, bytes and NULs
before invoking a provider. It copies argv and retains successfully captured
source paths, raw contents, decoded tokens and inclusion records. It publishes
`arguments()` and output `origin(index)` only after complete success. On failure
the captured diagnostics remain alive in the Expansion; an OOM does not promise
that uncaptured inputs will be materialized. Returned provider errors belong
to the caller independently of expansion storage.

Preparation is one-shot. Another call returns InvalidState and preserves the
existing state. `destroy()` releases expansion storage and resets the owner;
it invalidates all borrowed views. Copies alias one manual owner. Keep one
active owner and do not reenter it or mutate borrowed storage during operations.

An Origin uses source -1 and an original argument index for argv, or a
zero-based response source ID and argument -1 for a file. Its start/length
describe a raw span. Source records retain path bytes and the including origin.
`locate(parser_location, maximum_work)` translates an expanded argument index
and decoded byte offset by replaying the canonical tokenizer over retained
storage, including removed `@@` prefixes. Real bytes produce a one-byte raw
origin; endpoints produce length zero. Adding decoded offsets to raw starts
would give incorrect answers across quotes and escapes.

## Resource limits

Limits separately bound final argument count/bytes, every decoded token's byte
length, all tokens including directives/empty values, individual and aggregate
source bytes, file requests, nesting, path bytes and abstract engine work.
Aggregate source bytes include argv and repeated file occurrences. Zero is a
real zero limit. Default values and exact work charges are in the
[plan](library-response-files-plan.md#expansion-paths-and-limits).

Before each provider call, the byte grant is the minimum of the per-file cap,
remaining source allowance and raw-processing work allowance. An oversized
successful provider result is destroyed and rejected as ProviderContract.
Provider failures are propagated unchanged, so a native ByteLimit can describe
a smaller remaining grant. Files are loaded completely before their children
are visited. An explicit frame stack and finite limits terminate cycles; no
file-identity cycle detector is supplied. Storage bounds follow the retained
byte/count limits and Vec capacity growth, without an exact heap/RSS cap.

## Native file provider

`cli_response_files::files(directory_fd, maximum_calls, follow_symlinks)` borrows
one stable base directory descriptor. All relative includes, including nested
ones, use that same base; ordinary argument paths are unchanged. Absolute names
retain ordinary host semantics. AT_FDCWD requires the caller to keep cwd stable.
The provider never owns or closes the base descriptor.

Each load opens read-only with close-on-exec, nonblocking and no-controlling-
terminal flags, optionally forbids following the final symlink, checks the
opened descriptor is a regular file, then reads and closes it. It owns at most
one transient descriptor. Lookup is ordinary filesystem lookup, without a
confinement promise.

Every actual open, metadata, read and close attempt consumes a call credit.
Opening requires at least four remaining credits and reserves one for close.
Interrupted reads consume another credit before retrying; open, metadata and
close do not retry. Reads use at most4096 bytes and check actual EOF, consuming
at most one probe byte beyond a byte cap. Metadata length never substitutes for
EOF. A load error preserves its primary phase/cause and a simultaneous close
error separately. A close failure after successful reading is primary. Linux
close retirement is once-only even on error. Call limits bound attempts, not
filesystem wall time.

The current descriptor adapter transfers at most1024 bytes per read. These
ordinary short reads consume separate credits; request size does not predict
the exact call count for a file.

## Current executable evidence

The public tokenizer smoke compiles and exits zero, covering strict syntax,
spans, nonzero starts, a real negative-stride view, mapping and unchanged output
on capacity failures. Under full syscall tracing with every mmap configured
to fail, its trace contains only launch and final raw exit; no allocation or
other host call is attempted. This is not OOM-recovery evidence.

Receipts are `target/stdlib-work/response-public-smoke-compile-first.log` and
`response-public-smoke-no-host.{trace,log}`. Pure source is `a997585c...`, smoke
source `67404fe8...`, retained ELF `9f07ecb8...`. This establishes native Linux
x86_64 CPU execution emitted by the GPU compiler, with no user-program GPU or
other host claim.

The direct owned-expansion public smoke also compiles and exits zero with
empty output. It exercises a nominal generic provider error, two nested files,
literal @@ and empty tokens, copied snapshots, raw-offset mapping, both actual
CLI parsers, repeated preparation and retained provider-failure diagnostics.
Source is `35b6ee83...`, smoke `6399cf85...`, retained ELF `a434ae37...`;
receipts are `response-expansion-smoke-{compile,native}-first.log` under
`target/stdlib-work/`.

Both registered portable tests pass together in 8.93s after a separate 3.37s
test-profile build (`response-semantics-first.log`). The native model processes
96 records: 17 grammar, ten syntax and 69 expansion/limit cases. Separate pure
contracts check preflight, output canaries, exact mappings and real signed
strides. The retained pure contract also passes full tracing with mmap denial;
only launch and exit are observed (`response-contracts-no-host.{trace,log}`).
See the [fixture guide](../tests/fixtures/extended/cli_response/README.md) for
exact sources, oracle limits, independent reviews and retained ELF hashes.

The native provider's public smoke compiles and exits zero after a fixture
correction: its original fixed read-count assertion ignored the existing
1024-byte stream cap. Actual read contents, close and release succeeded before
that assertion trapped. The corrected fixture observes the first call count
and checks exact subsequent zero-cap/nonregular deltas; production was unchanged.
Provider source is `461037b8...`, smoke `07abd146...`, ELF `65855384...`.
Accepted receipts are `response-files-smoke-{compile,native}-read-count-retry.log`;
the original compile, trap and diagnostic trace remain separate records.

| Integration gate | Accepted finite scope | Receipt under `target/stdlib-work/` |
| --- | --- | --- |
| Real native file provider | 39 direct cases cover borrowed/fixed-base descriptors, file admission, byte caps, call budgets and injected I/O/close failures | `response-files-provider-native-first.log` |
| Resource and owned-error campaigns | 31 direct cases: two healthy baselines plus 29 individually reached allocation failures, with live acknowledged owner checks | `response-files-resources-native-first.log` |
| [Migrated KV application](extended-kv.md#current-application-receipts) | 55 direct cases, including all 18 source-allocation denials from its nested-help baseline, a post-database-open OOM and published-unsynced outcome | `response-kv-native-artifact-retry.log` |
| Registered native/KV drivers | Combined `--no-run` build passes in 2.09s, separately from direct oracle execution | `response-resource-kv-drivers-build-first.log` |

The two native groups total 70 group cases with overlapping setup, not two
passing Rust libtests. Their [fixture guide](../tests/fixtures/extended/cli_response/files_README.md)
owns exact source/ELF identities, phase-specific full-syscall admission,
allocation-site/prefix binding, live map/fd generations and pre-exit cleanup.
The owned provider error remains live after Expansion destruction, then is
explicitly released. Test-injected skipped close errors retain a physical fd
until a separately marked fixture repair; this is not claimed as a successful
library close. The 39 CPU oracle controls are separate from runtime.

The application retains Expansion through command execution and destroys it
on success and error. It permits explicit response reads before CLI validation
while preserving ordinary argv no-file-access failures and preventing premature
database effects. Its first response attempt reached ten cases before an
artifact-name bug stopped the harness before launching case eleven. The
corrected 55-case receipt repeats those cases; they are not added again.
Earlier 130-case hierarchy application receipts retain their older source
scope. The Store/publication bodies are unchanged by this preprocessing step.

A separate [complete test-source capture](../tests/fixtures/stdlib_compiler_state/response_none_match/README.md)
records LNC0005 at visible names in two match compositions. Both smaller
controls execute, so there is no demonstrated general None/wildcard restriction.
Consolidating duplicate payload extraction admits the active native fixture
with its assertions intact. No responsible compiler pass is established, and
no compiler or production library implementation was changed for that capture.

Supported runtime evidence remains native Linux x86_64 CPU output from the GPU
compiler. Other hosts and user-program GPU execution remain unverified. Shell
completion and broader application validation remain on the library roadmap.
