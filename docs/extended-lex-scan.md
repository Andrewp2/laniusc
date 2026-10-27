# CSV token rules and UTF-8 scanning

`sample_programs/library/lex_scan.lani` reads ordered CSV token rules, compiles
one reusable [`ext::lexer`](extended-lexer.md), and scans all of stdin. It
publishes either byte spans or counts by rule id. CLI parsing, CSV decoding,
matching, counting, formatting and I/O run in Lanius.

The current source uses one eager span-only regex workspace per nonempty lexer
cursor. All five current application tests pass native x86_64 Linux execution,
including matching/admission, scripted I/O, reached OOM/I/O faults and the
4,096-token resource observation. Earlier per-probe receipts remain historical.

Build and run from the repository root:

```sh
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc \
  --stdlib-root stdlib --source-root extended \
  sample_programs/library/lex_scan.lani -o /tmp/lex-scan
printf 'if iffy == 12 λλ\n' | timeout 10s /tmp/lex-scan spans \
  tests/fixtures/extended/lex_scan/example.csv
```

Output:

```csv
id,start,end
10,0,2
90,3,7
40,8,10
30,11,13
20,14,18
```

The `counts` mode emits every non-skip rule in CSV order, including zero counts:

```csv
id,count
10,1
90,1
30,1
40,1
20,1
```

## Rules and selection

The command is `lex-scan spans|counts RULES.csv [OPTIONS]`. Options can appear
between operands. `--help` or `-h` must appear alone; repeated options, unknown
options and extra operands fail. Use `--` before an operand that begins with a
dash. Argument capture allows 32 arguments and 8,192 argument bytes; the rule
path must contain 1..4,095 bytes and no NUL.

The decoded header must be exactly `id,pattern,skip`, followed by 1..64 rows
of exactly three fields. Each id is decimal digits only, within nonnegative
`i32`, and unique by numeric value: `01` and `1` collide. `skip` is exactly `0`
or `1`. No whitespace trimming or extra backslash decoding occurs.

Patterns use the [canonical regex dialect](extended-regex.md). CSV quotes
protect commas and line endings; double a quote inside a quoted CSV field.
Regex backslashes remain literal CSV bytes. For example, `[ \t\r\n]+` reaches
the regex compiler with those three backslash escapes intact. CSV rejects
invalid UTF-8, NUL and its other unsupported control characters. Stdin may
contain NUL when a rule matches it.

At each non-EOF position, the lexer chooses the longest positive byte span
across all rules. Earlier CSV rows win equal lengths. Each pattern itself uses
anchored longest-prefix matching, so `a|ab` can consume all of `ab`. A longer
identifier rule beats the keyword `if` on `iffy`; the keyword wins the equal
length match on `if`. Skip rules consume text without producing a span or
count. An unmatched position or an empty winning match fails; neither silently
advances input. Empty input succeeds without probing even a nullable rule.

Assertions inspect the whole validated input. A later token does not acquire
a new beginning-of-input or word boundary by slicing a suffix. Span endpoints
are half-open UTF-8 **byte offsets**, not character indices. The command does
not print token text or captures.

## Bounds and resource accounting

Numeric option values are unsigned decimal digits. Each option can appear
once, using either `--name N` or `--name=N`.

| Option | Default | Maximum | Meaning |
| --- | ---: | ---: | --- |
| `--max-input` | 1,048,576 | 4,194,304 | Buffered stdin bytes. |
| `--max-tokens` | 100,000 | 1,000,000 | Committed non-skip tokens. |
| `--max-output` | 4,194,304 | 16,777,216 | Complete staged CSV bytes, including the header. |
| `--max-calls` | 1,048,576 | 16,777,216 | Attempted rule searches. |
| `--max-call-work` | 1,048,576 | 16,777,216 | VM work allowance for each attempted rule search; must be positive. |
| `--max-work` | 1,099,511,627,776 | 1,125,899,906,842,624 | Sum of reserved per-search allowances. |

Zero is valid for the other five options. A zero token cap can still accept
all-skip input. Zero input/call/work caps accept empty input. A zero output cap
cannot hold the CSV header.

The rule file is capped at 65,536 raw bytes. CSV decoding admits at most 65
records including the header, three fields per record, 1,024 decoded bytes per
field and 1,035 decoded bytes per record. Each regex has a 1,024-byte pattern,
256-state, 32-depth, 16-capture and 1,000-repeat cap; the compiled lexer has a
16,384-state aggregate cap. The aggregate decoded pattern-byte cap is 65,536.
The application fixes the lexer step cap at 1,000,000, including skips.
Positive progress also bounds committed steps by input bytes.

Every rule is attempted at each selected position, including rules that fail
to match. Each attempt reserves the **entire** `--max-call-work` allowance
before searching. For six rules and two successful steps, exactly 12 attempts
reserve 12 times that allowance. A smaller per-call allowance may admit more
attempts under the aggregate cap, but a VM work-limit failure aborts the scan.
Skipping still charges a step, calls and reserved work. These counters are
limits, not measured CPU instructions or elapsed time.

The library validates input once and reuses its validated descriptor for rule
probes. The app separately validates its buffered stdin before scanning. For
nonempty input, `Lexer.scan` then prepares one owned canonical workspace sized
to the largest actual compiled rule and group zero. Rule probes reuse it and
return plain spans, creating no discarded Match owner. Constructor OOM is an
eager scan failure before any rule call/work charge. Empty input creates no
scratch. Scratch construction/reset, register copying, Unicode operations and
allocation cost lie outside the VM counter. Longest matching can examine text
beyond a winning token and revisit suffixes at later positions. The lexer
creates no allocations during token-returning `next` calls; this whole command
still owns buffered input, staged output and counters, and makes no linear
whole-scan claim.

## Publication, I/O and cleanup

The command compiles every rule, buffers and validates stdin, finishes the scan,
and formats the complete CSV before writing stdout. Invalid input, malformed
rules, scan failures, allocation failures and staging limits publish no stdout.
Counts use a scalar `HashMap<i32,u64>`; separate scalar metadata preserves CSV
order. A skipped rule never appears in counts output.

Publication handles partial writes and advances only by a confirmed positive
count. If a later write fails, stdout can contain that accepted byte prefix.
The command does not replay it. It ignores SIGPIPE so a closed output pipe can
return an I/O failure. No atomicity across the host stdout stream is promised.

Each rule-file or stdin read permits at most 16,384 host calls. Reaching the
byte cap still requires an EOF probe; a further byte fails without entering the
buffer. Stdout and each diagnostic permit at most 65,536 write calls. EINTR
consumes a call before retry; WouldBlock, invalid counts and zero write progress
fail. There is no flush or retry of WouldBlock. The rule file is opened once
and closed once before input scanning; an open or close error fails the command.
A close error takes precedence over a rule read error. These call budgets do
not interrupt a blocking host call; callers needing an elapsed-time bound must
supply an external deadline.

The lexer owns its compiled programs. After compilation, the app releases the
CSV table and borrowed rule descriptors before scanning. The cursor borrows
the lexer and input and owns its workspace; the app ends it before freeing
either owner. Output stores
only formatted numbers, so the input may then be released before publication.
The lexer releases workspace once on EOF, error or cursor destruction; tokens
refer only to input. Independent cursors have independent scratch. All paths
explicitly release their buffers, table, counter map, metadata vector, compiled lexer and argument
snapshot. Copies of owner descriptors remain aliases; none grants a second
cleanup authority or automatic destruction.

| Exit | Meaning |
| --- | --- |
| 0 | Successful CSV publication or standalone help. |
| 2 | Invalid arguments/rules/UTF-8, matching failure, or a configured content/work/staging limit. |
| 3 | Host I/O, read/write-call exhaustion, close or publication failure; also a failed diagnostic write. |
| 4 | Allocation failure, including regex compilation and eager cursor workspace setup. |

Diagnostics use stderr and identify the stage, with zero-based rule and byte
positions when available. A failed diagnostic write changes the exit to 3.

## Current workspace acceptance

All **five** application tests passed GPU compilation and native x86_64 Linux
execution in two separate serialized invocations:

| Current scope | Tests | Elapsed | Receipt under `target/stdlib-work/` |
| --- | ---: | ---: | --- |
| Real grammar model/boundaries, malformed/admission/nonpublication cases, scripted production I/O | 3 | 13.63s | `lex-scan-workspace-behavior-io-first.log` |
| Reached application OOM/native I/O faults and the 4,096-token resource observation | 2 | 16.66s | `lex-scan-workspace-faults-cost-first.log` |

The accepted app source SHA256 is
`7454037c6cbdd7f46227611c5b4a317b57ec9e168c525233e1971465f05ea10c`.
The matching model checks 124 grammar inputs in both spans/counts modes plus
exact longest/tie, Unicode byte-offset, CSV and EOF-budget boundaries. The
other behavioral gates preserve malformed/admission/limit failures with no
premature stdout, and scripted partial progress, EINTR, WouldBlock, zero/invalid
counts and EOF probes against the actual production I/O helpers.

Both one-token modes passed all **30** dynamically reached application mmap
failure positions. Each run binds the injected ordinal to the successful
baseline's native instruction address and exact allocation arguments, then
requires typed allocation failure, no stdout and complete verified source
release. Raw ELF runtime provenance and full-width requested address/length
accounting are mandatory; a local allocation-count summary cannot admit a
source site. Only the uniquely baseline-derived bounded temporary Frame
episode is allowed after a sticky construction failure. The
[workspace migration receipt](../tests/fixtures/extended/lex_scan/workspace-migration.md)
records that scope; the older OOM17 witness does not fix a current ordinal.

The same group passed reached read/write EINTR, read/write/close EIO, confirmed
publication-prefix, `/dev/full` and closed-stdin controls. Ordinary and OOM
paths require successful rule-descriptor closes. The synthetic close-EIO case
checks one logical retirement and exact error propagation: strace skips the
physical close, so it does not establish a natural Linux close failure or
physical descriptor release for that injected case.

### Current resource observation

The counts-mode fixture emitted exactly 4,096 tokens and recorded:

| Verified whole-program source cost | Observed value |
| --- | ---: |
| Source mmap requests | 32 |
| Cumulative requested bytes | 8,895 |
| Peak live requested bytes | 6,868 |
| Explicit source releases | Balanced |
| Traced correctness/cost harness wall time, including setup and verification | 79.624585ms |

This is whole-program verified source allocation, including setup, rule
compilation, input, workspace and output handling. Requested bytes are neither
rounded kernel pages nor RSS, and these totals are not an isolated scan
allocation count. The clock starts before temporary rules/input/trace setup
and ends after child execution, trace reading, output checks and verified
Python ledger validation. The application executable had already been compiled
by the earlier OOM test in that combined invocation; this time does not measure
compilation or isolated application execution.

The historical 36,887-request/10.278540515-second observation below remains a
separate receipt. There was no fresh old-version baseline, controlled timing
comparison or timing-ratio claim. The current observation is a finite
correctness/cost receipt, without a throughput or timing threshold.

## Historical focused acceptance

[`tests/extended_lex_scan_execution.rs`](../tests/extended_lex_scan_execution.rs)
defines five Linux x86_64 groups. The historical receipts below predate the
workspace ownership change. That campaign compiled the real CLI once and one source
fixture that appends scripted readers/writers to the same production helpers.

- An independent character-class oracle checks 124 bounded example-grammar
  inputs in both modes, including concatenations that merge lexemes, Unicode
  byte offsets, rule priority, longest alternatives, CSV quoting and EOF budgets.
- Real-process failures cover short/long CSV rows, strict ids and skip flags,
  invalid text/patterns, full-input assertions, empty matches, every public
  resource knob, argument admission, and absent input files. They require empty
  stdout for failures before publication.
- One-shot ENOMEM injection covers every mmap reached by one-token spans and
  counts baselines. An independent address/size ledger requires exact releases;
  a descriptor ledger requires the rule owner to close once. Injected read/write
  EINTR and EIO, close EIO, `/dev/full`, closed stdin and a confirmed 1,024-byte
  publication prefix exercise host error paths. An injected close error checks
  logical owner retirement; the injected syscall itself does not close the
  kernel descriptor.
- Scripted partial I/O checks EOF probes, exact call budgets, repeated EINTR,
  WouldBlock, zero progress and invalid counts against the actual app helpers.
- A 4,096-token native run requires the exact count and balanced mappings, then
  reports actual mmap requests and traced wall time. This is a finite resource
  observation, not a throughput benchmark or timing threshold.

The first real-app group stopped during GPU source admission after 3.62 seconds,
with `LNC0027` at `read.is_err()` on an unannotated generic Read result:
`target/stdlib-work/lex-scan-real-model-first.log`. No native case ran. The app
now declares its I/O result locals as the existing trait's exact
`Result<i32,core::io::Error>`, matching the canonical I/O helpers. The
[context dependency note](library-context-inference-dependencies.md#generic-byte-writer-return)
retains that failure and the separately verified minimal Read controls: the
untyped reduction rejects at the same result inspection, and the typed control
compiles and exits 0. No compiler cause or repair is claimed.

The earlier serialized GPU compilation and native x86_64 Linux execution had
these separate accepted receipts under `target/stdlib-work/`:

| Groups | Result | Elapsed | Receipt |
| --- | --- | ---: | --- |
| Real CLI model and boundaries | Passed; 124 grammar inputs in both modes, plus priority, longest, CSV and budget boundaries. | 8.40 s | `lex-scan-real-model-explicit-io.log` |
| Admission failures, scripted production I/O, resource observation | All three groups passed. | 14.16 s | `lex-scan-errors-scripted-resource.log` |
| Allocation failures and native I/O faults | Passed; all 30 reached mmap fault positions in each mode, then exact syscall-fault and publication checks. | 8.36 s | `lex-scan-oom-bounded-frame.log` |

The historical resource run counted exactly 4,096 visible tokens, made **36,887 mmap
requests**, and released every mapping. Its captured traced wall time was
**10.278540515 seconds**. The requests include whole-program setup, rule
compilation, scan scratch and output handling. This is an observed finite
cost, not an isolated scan allocation count, throughput claim or timing gate.

The first OOM group run stopped after 7.59 seconds on a harness overassertion:
`lex-scan-oom-native-io.log`. At spans fault 17 the app returned 4, emitted no
stdout and passed both cleanup ledgers, but canonical regex construction made
one frame setup allocation after its sticky code-allocation failure. The
[retained witness](../tests/fixtures/extended/lex_scan/oom17-witness.md)
traces that bounded continuation. The corrected driver keeps the exact request
prefix through each reached injection and accepts only the source-supported
temporary-frame lifetime derived from the successful baseline; it rejects
other post-failure allocations. It still requires one exact injected ENOMEM
event, empty stdout and complete cleanup. The campaign explores one fault per
successful-baseline allocation, not simultaneous faults or a second fault in
an allocation reached only during failure propagation.

The corrected OOM group passed all 30 reached mmap failures in spans and all 30
in counts, followed by the existing read/write EINTR, read/write/close EIO,
confirmed publication-prefix, `/dev/full` and closed-stdin cases. Exact marker
assertions confirm the intended syscall, errno and ordinal for each injected
fault. All five groups therefore have accepted evidence from the three
separate runs above; this does not describe a single combined suite run. The
production app in that historical campaign did not change after its exact I/O
result annotations; only the OOM harness changed for its final group. The
current revision separately adds workspace-error mapping and eager cursor
ownership through the lexer.

CPU checks have audited literal byte lengths and the independent oracle; they
also reject malformed fault markers and unexpected OOM continuations. They
support the native evidence above. The bounded reproduction command is:

```sh
timeout --kill-after=2s 100s env \
  CARGO_TARGET_DIR="$PWD/target/stdlib-build" CARGO_INCREMENTAL=0 \
  CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 \
  cargo test --locked --test extended_lex_scan_execution -- --nocapture --test-threads=1
```

The production source composes portable lexer/CSV/text/container code with
Linux descriptor I/O. The driver is gated to Linux x86_64 and needs `strace` with
syscall injection and `/dev/full`. No other runtime platform is claimed.
