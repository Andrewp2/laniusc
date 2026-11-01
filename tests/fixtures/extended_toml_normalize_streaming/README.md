# TOML normalizer: borrowed streaming migration

These focused tests exercise the real `sample_programs/library/toml_normalize.lani`
consumer after it moves from a complete output String to borrowed TOML Encoding
and canonical Copier. Production implementations remain Lanius. Python is only
the test oracle and trace observer.

## Cases and selectors

| Selector suffix | Group | Native process cases |
| --- | --- | ---: |
| `streaming_preserves_exact_wires_without_output_storage` | model | 14 |
| `streaming_preflights_limits_and_actual_input_probes` | limits | 8 |
| `cleans_up_all_observed_allocation_and_host_io_failures` | io | 40 (15 + 25 reached allocation denials) |
| `streaming_bounds_attempts_and_reports_confirmed_prefix` | budgets | 2 |

The full Rust names begin `toml_normalize_`; the target is
`extended_toml_normalize_execution`. A is every successful mmap in one actual
modest nested-document baseline, including argv, collector growth and parser
storage. Each allocation is denied once at its observed ordinal. The baseline
is already one of the 15 ordinary I/O cases. Host controls and standalone
examples do not add native cases.

The retained selector
`toml_normalize_executes_real_configs_11_syntax_types_and_idempotence` supplies
selected earlier typed semantic and idempotence coverage. Existing broader
parser and scale selectors remain available; this migration does not require
rerunning their campaigns. The old fault test's fabricated positive write
return is removed: a real first write now establishes the confirmed prefix
before the second write receives EIO.

## Behavioral evidence

Twelve literal complete wires cover empty/comment input, insertion order,
inline nested tables and arrays of tables, canonical control escapes, Unicode,
integer/float distinction and signed zero, TOML 1.1 temporal/escape syntax, and
UTF-8/escape positions across the 1,024-byte copy scratch boundary. The host's
TOML 1.0 parser cross-checks shared syntax only; TOML 1.1 cases use explicit
expected bytes. The selected older regression retains its typed float and
negative-zero comparisons.

A large escape-expanding string runs in normal and `--check` modes. Its exact
complete output is checked. Excluding argv, both modes must issue the same
allocation requests and have the same live document extents at input retirement.
No allocation may occur after that boundary. This comparison detects an added
whole serialized-output owner, including one allocated before the observed
boundary; source review establishes the intended owner roles.

Limits include actual 4,096-byte input acceptance and a real one-byte EOF probe,
plus the next byte rejected by that probe. Exact output capacity and capacity
minus one distinguish successful streaming from rejection before stdout.
Zero-byte input capacity, `--check` output-cap bypass, repeated last-option wins,
and invalid help options before input are retained. The full 64 MiB CLI cap is
not replayed in this focused suite.

I/O cases include interrupted reads/writes, input EIO after a real prefix,
first/second output errors, WouldBlock, zero write, actual closed stdout/help
pipes, SIGPIPE setup failure, failed diagnostics, one owned parse failure and
an exact invalid-UTF-8 offset. Every injected site must be reached, and denied
mmap requests must equal the corresponding successful baseline prefix.

The input-call case observes exactly 131,072 interrupted reads followed by a
successful resource-limit diagnostic. The output-call case confirms a real
1,024-byte stdout prefix, then interrupts all later writes. Two local encoder
reads plus 262,142 stdout attempts consume the 262,144 total provider-call
budget. The observer checks 64 subsequent requests for the exact output-limit
message including `written=1024`. Continuous injection prevents delivery of
that diagnostic, so the observed final status is 3, as required by the existing
diagnostic-failure override. This case does not establish successful delivery
of an output-call-limit status-2 diagnostic. No unsupported finite strace range
above 65,534 or invented positive write count is used.

## Ownership observer and limits

The trace filter contains exactly nine syscall names: read, write, mmap,
munmap, mremap, brk, openat, close and rt_sigaction. It is not an all-host-effect
proof. Full virtual addresses, mapping extents and allocation generations are
tracked. Argv owners must retire before input reads. The collector's current
owner is identified at reads; after EOF its release identifies the live
Document mapping set. That exact set must remain live at every payload write,
including the first, and no allocation is allowed after input retirement.
All mappings must be retired before diagnostics and at exit; standard stream
descriptors are borrowed. The zero-input-cap case has no observable input
allocation/retirement, emits no payload and is scoped accordingly.

Host negative controls reject early input release/publication, document release
before the first or a later write, allocation after input retirement, wrong
release extent, missing release and argv surviving into collection. A valid
control deliberately reuses virtual addresses across argv/input/parser phases.
These controls verify the observer rather than add native evidence.

Coverage is finite and tied to the observed Linux x86_64 CPU binaries generated
by the GPU compiler. It does not establish GPU-device execution, arbitrary
parser-allocation schedules, argument-capture host failures, unexecuted help
attempt exhaustion, formal memory safety, or same-process app recovery.

## Verification status

Host-only corpus and observer controls pass: model 14, limits 8, I/O 15 + A,
budgets 2, and seven rejected lifetime corruptions. No compiler/native command
was run by this fixture's author. The root task ran the following frozen groups
serially; each command remained below 100 seconds:

| Group | Native cases | Result | Test time | Separate Rust build | Log under `target/stdlib-work/` |
| --- | ---: | --- | ---: | ---: | --- |
| model | 14 | 1/1 passed | 7.67 s | 0.19 s | `toml-streaming-app-model.log` |
| limits | 8 | 1/1 passed | 7.62 s | 0.18 s | `toml-streaming-app-limits.log` |
| io | 40, including 25 reached allocation denials | 1/1 passed | 7.95 s | 0.19 s | `toml-streaming-app-io.log` |
| budgets | 2 | 1/1 passed | 20.75 s | 0.19 s | `toml-streaming-app-budgets.log` |

Accepted trace directories:

- `/tmp/toml-normalize-streaming-model-i52nxxv6`
- `/tmp/toml-normalize-streaming-limits-15w5g8bh`
- `/tmp/toml-normalize-streaming-io-n2qphb40`
- `/tmp/toml-normalize-streaming-budgets-uehl18x4`

The retained semantic/idempotence regression separately passed 1/1 in 7.31 s
(build 1.13 s), `toml-streaming-app-regression.log`; the existing malformed-input
and resource-error regression passed 1/1 in 7.01 s (build 0.18 s),
`toml-streaming-app-errors.log`. Neither is included in the new table's process
counts. All four focused groups passed: 64 native process cases, including 25
reached allocation denials. The source, driver and oracle stayed unchanged
through these runs. Independent source and harness review also passed.

Frozen inputs for these receipts:

- App: `6ae13b3e83aa594848113c806fb6ca680205ea5c42f8f6a0a05fc76a095bc0d5`
- Driver: `afd21725281493d667148b50be30424e7515400fba6c471f0fa0d14978b49536`
- Oracle: `3fea9d4121c957fbd9150f9caea5e7f8411aa01694232dfa2e8043409018569a`
