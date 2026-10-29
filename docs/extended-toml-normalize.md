# TOML normalization program

`sample_programs/library/toml_normalize.lani` reads TOML **1.1.0** from stdin,
validates it, and writes deterministic TOML preserving the document's types and
values. `--check` performs validation with quiet success. It uses the real
[Lanius TOML parser/encoder](extended-toml.md), without a host parser or JSON
conversion. Its [resumable-output migration](extended-toml-streaming.md) is
accepted through four groups/64 native cases on Linux x86_64 CPU output from
the GPU compiler; historical receipts remain below.

```sh
mkdir -p target/stdlib-work
timeout --kill-after=2s 100s flock -w 95 target/stdlib-work/library-gpu.lock \
  target/stdlib-build/debug/laniusc --stdlib-root stdlib --source-root extended \
  --emit x86_64 sample_programs/library/toml_normalize.lani \
  -o target/stdlib-work/toml-normalize
printf 'name = "example"\n[server]\nport = 8080\n' | \
  timeout 10s target/stdlib-work/toml-normalize
```

Expected stdout is exactly 40 bytes:

```toml
"name"="example"
"server"={"port"=8080}
```

A second example exercises inserted seconds, exact fraction trimming and the
unknown-offset spelling:

```sh
printf 'clock=07:32\noffset=1979-05-27t07:32:00.1200-00:00\n' | \
  timeout 10s target/stdlib-work/toml-normalize
```

Expected stdout is exactly 55 bytes:

```toml
"clock"=07:32:00
"offset"=1979-05-27T07:32:00.12-00:00
```

Both expected outputs include LF after each shown row. These are usage examples;
the executable receipts below come from the focused test selectors, which
compile and run the real program. No separate execution of these shell commands
is claimed.

## Output semantics

Each root member is emitted as a quoted key, `=`, an inline value and LF.
Tables become inline tables, including tables inside arrays. Key and array
order are retained; comments, indentation, quote choices and original number
spelling are discarded. Integers emit in decimal; floats use shortest binary64
round trips with a decimal marker when necessary to preserve floating type.
Negative zero, infinity and NaN signs are retained. TOML NaN has no payload
syntax. Local dates/times remain local, and unknown offset `-00:00` remains
distinct from known UTC. Temporal spellings use canonical `T`/`Z`, include
seconds and trim redundant fractional zeros without rounding away information.
Reprocessing output produces identical bytes.

Input is valid UTF-8. Escaped NUL is a valid string character and is re-escaped
in output; literal NUL in the TOML syntax is invalid. The program supports
TOML 1.1 escape additions, optional seconds, multiline inline tables and their
trailing commas. It appends no extra blank line. An empty document emits no bytes.

## Options and bounds

| Option | Default | Meaning |
| --- | --- | --- |
| `--check` | off | Parse/validate; do not encode or write stdout. |
| `--max-input-bytes N` | 16,777,216 | Whole stdin bound. |
| `--max-output-bytes N` | 67,108,864 | Canonical output bound, checked before stdout. |
| `--max-nodes N` | 1,000,000 | Root, intermediate tables, arrays and values. |
| `--max-depth N` | 128 | Document nesting depth. |
| `--max-string-bytes N` | 16,777,216 | Per decoded key/string/temporal spelling. |
| `--max-number-bytes N` | 1,024 | Numeric source spelling length. |
| `--max-work N` | 1,000,000,000 | Each parser or encoder operation's budget. |
| `--help`, `-h` | off | Usage without reading stdin. |

There are no operands. Values are unsigned decimal digits. Byte/string/number
bounds are capped at 67,108,864, node count at 1,000,000 and depth at 4,096.
Repeated valued options use the last value; invalid earlier options still
reject. Work accepts the full `u64` range. This allows a caller to raise the conservative
floating conversion budget for large numerical configurations. Each finite
float currently reserves one million work units for parsing and one million
for shortest formatting, besides lexical work. The decimal converter has a
768-mantissa-digit ceiling; exceeding it is an explicit number-limit error even
if the byte option is larger. See the engine guide for precise accounting and
native integer/float range policies.

Parsing and reader construction receive separate `max_work` budgets; the option
is not cumulative across the process. Reader construction admits 2W for
preflight and emission, where W counts emitted bytes, nonroot node visits and
fraction scan/trim digits. The earlier normalizer separately measured and then
required 2W + output bytes for staged `encode_into`; this migration deliberately
uses the new [2W policy](extended-toml-streaming.md#work-accounting). Serializer
work excludes allocator/collector work and transport calls.

The argument snapshot allows at most 32 tokens and 8192 raw bytes, excluding
argv[0]. It is destroyed after scalar option parsing, before help or input.
The canonical collector reads through EOF under the configured byte cap and
131,072 actual read attempts. At the exact byte cap, a real one-byte read
admits EOF or consumes and rejects an excess byte. UTF-8 validation and parsing
finish before any payload output. The original input owner is destroyed after
parse returns; the independent Document then owns all encoded values.

| Direct-call budget | Maximum |
| --- | ---: |
| Stdin reads, including EOF/probe/Interrupted | 131,072 |
| Combined Encoding reads and stdout writes through Copier | 262,144 |
| Help writes | 64 |
| Diagnostic writes | 64 |

After complete semantic/output/work preflight, Encoding feeds Copier through
1024-byte stack scratch. No output-sized owner is created. A successful full
transfer takes `2 * ceil(output_bytes / 1024) + 1` direct provider calls when
ordinary reads/writes fill their requests. These include in-memory Encoding
reads, not only stdout syscalls. Read quota includes an extra byte to admit
its real EOF observation. The call allowance admits the CLI's 64 MiB output
cap with retry headroom.

`--check` bypasses encoding, so an output cap of zero permits a nonempty valid
document. Short transfers retain progress; Interrupted consumes a call and
retries; WouldBlock, zero writes and host failures stop. Output failure or
call exhaustion can leave a confirmed prefix. Copier is aborted before the
Document is destroyed, and cleanup precedes diagnostics. There is no flush,
filesystem publication or durability guarantee.

## Status and diagnostics

| Exit | Meaning |
| --- | --- |
| 0 | Valid document successfully written, quiet validation success, or help. |
| 2 | Invalid arguments, malformed UTF-8/TOML, value range, byte/work limit or read/copy/help call exhaustion. |
| 3 | Host I/O error, SIGPIPE-ignore setup failure, or failure to complete a diagnostic. |
| 4 | Allocation failure. |

Errors attempt a stderr diagnostic with stage, TOML error kind where applicable,
and input byte offset where available. Output-stage errors add ` written=N`
before LF, recording confirmed stdout bytes. Copy-call exhaustion selects
`resource-limit stage=output` and status 2; output I/O failure selects
`io-failure stage=output` and status 3. Failure to complete any diagnostic
overrides its primary status with 3. SIGPIPE-ignore setup failure returns 3
silently. No malformed input is replaced or silently truncated. `--help` does
not suppress invalid arguments elsewhere; its unchanged help text is 170 bytes.

## Current execution status

The migrated source is frozen at SHA256
`6ae13b3e83aa594848113c806fb6ca680205ea5c42f8f6a0a05fc76a095bc0d5`.
All four focused groups pass, totaling 64 native process cases:

| Group | Cases | Test time / separate Rust build | Log under `target/stdlib-work` |
| --- | ---: | --- | --- |
| Exact wires and storage | 14 | 7.67 s / 0.19 s | `toml-streaming-app-model.log` |
| Bounds and actual input probes | 8 | 7.62 s / 0.18 s | `toml-streaming-app-limits.log` |
| I/O and cleanup | 40, including 25 reached allocation denials | 7.95 s / 0.19 s | `toml-streaming-app-io.log` |
| Attempt budgets | 2 | 20.75 s / 0.19 s | `toml-streaming-app-budgets.log` |

The [fixture guide](../tests/fixtures/extended_toml_normalize_streaming/README.md)
records source/oracle hashes and exact scope. The model compares complete
wires and normal versus `--check` allocation requests for expanded output.
The limits group observes the actual 4,096-byte input cap and its EOF/excess
probe; it does not rerun the full 64 MiB CLI cap. The I/O baseline is counted
once among its 15 ordinary cases, separately from the 25 reached denials.

The input budget case observes 131,072 interrupted reads and a successful
resource-limit diagnostic. The output budget case confirms 1,024 stdout bytes,
then exhausts 262,144 combined provider calls: two local Encoding reads and
262,142 stdout attempts. It checks all 64 subsequent requests for the exact
diagnostic including `written=1024`. Continuous injection denies those
diagnostic writes, so the observed final status is 3. Successful delivery of
an output-budget diagnostic with status 2 is not claimed.

The observer tracks nine selected syscalls, full mapping addresses/extents and
owner generations. Argv retires before input; the current Document owner set
remains live at every payload write; cleanup finishes before diagnostics and
exit. No allocation occurs after input retirement, and the expanded normal/
check comparison rules out an extra whole-output owner before that boundary.
The zero-input-cap case has no input-owner retirement to observe and emits no
payload.
These finite observations do not establish all host effects, arbitrary parser
allocation schedules, argument-capture host failures, unexecuted help-attempt
exhaustion or same-process application recovery.

The selected existing configurations/TOML 1.1/types/idempotence regression
passes in 7.31 seconds after a 1.13-second Rust build; the selected existing
malformed/resource-before-output group passes in 7.01 seconds after a
0.18-second build. Their logs are `toml-streaming-app-regression.log` and
`toml-streaming-app-errors.log` under the same directory. These selected old
groups are separate from the 64 cases above. The supported evidence target is
Linux x86_64 CPU output from the GPU compiler. Other hosts,
user-program GPU execution, enforced lifetimes and formal proofs remain
separate.

## Historical executable evidence

The following receipts predate borrowed streaming output and the new work/call
budgets. They describe the earlier staged-output source, not acceptance of this
migration.

`tests/extended_toml_normalize_execution.rs` covers real nested configuration,
all value types, TOML 1.1 additions, canonical byte idempotence, independent Python
`tomllib` comparison for shared 1.0 syntax, exact/failed limits, invalid arguments,
UTF-8 read boundaries and returned diagnostics. Every observed allocation is
denied in turn; read/write errors, short/zero/interrupted writes, failed stderr,
`/dev/full` and late malformed input leave no traced mappings live.

A 1,200-worker configuration contains 100,299 input bytes and emits 100,315
canonical bytes. An observed native run took 233 ms including process/file
setup and I/O, excluding compilation. The typed and idempotent result was
checked; this is not a performance comparison with a host parser.

Verified target: native **x86_64 Linux**, emitted by GPU compilation. No other
native target or user-program GPU execution is claimed.
