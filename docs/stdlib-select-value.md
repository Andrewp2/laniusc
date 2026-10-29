# Select a signed integer order statistic

`sample_programs/library/select_value.lani` reads signed decimal integers
and prints their zero-based ascending order statistic:

```sh
printf '4 -2 +4\t9\r\n' | select_value 1
```

The example writes `4\n`. The implementation calls public
`core::slice::select_nth_unstable<i64>`; it does not sort locally or provide
a private selection algorithm.

## CLI and token grammar

The CLI is exactly `select_value INDEX`, or a sole `--help` / `-h`.
INDEX uses the existing unsigned decimal parser: ASCII digits only, leading
zeros allowed, in 0..65535. Signs, whitespace, prefixes, empty values and
extra operands are invalid. Capture admits one value and at most 64 bytes,
excluding its terminating NUL. Help bypasses stdin and value allocation.

Input consists of signed decimal i64 tokens. Separators are only ASCII SP,
HT, CR and LF. Leading/trailing/repeated separators are allowed. Each token
is passed to `core::decimal::parse_i64_range`, which accepts optional
plus/minus and leading zeros within the exact i64 range. Bare signs, missing
markers, numeric prefixes, commas, non-ASCII bytes and overflow are invalid.
VT/FF and other whitespace are not separators; they remain invalid token data.
There is no text normalization or alternative numeric parser.

Each token contains at most 64 bytes, including any sign. Input has at most
1048576 raw bytes and 65536 values. A final token needs no trailing separator.
Successful input requires actual EOF, including at the exact byte limit:
a one-byte probe distinguishes EOF from excess input. Any extra byte fails,
even when it is a separator.

Empty/whitespace-only input and INDEX beyond the final value count fail with
no stdout. Duplicate values are retained and occupy separate ranks.

## Public selection and output

After valid CLI parsing, the program pre-reserves one `Vec<i64>` with
capacity 65536. Before every append it checks the value-count limit, so input
never grows that allocation. Token scanning uses a fixed 1024-byte scratch
array and 64-byte token array; it does not retain a separate copy of input.

Only after EOF and all token validation does the program pass the vector's
counted view and INDEX to the public natural-order selection operation.
That operation may permute whole values and returns a borrowed one-element
view at the selected position. The application checks its shape and reads
only its scalar i64 before ending the borrowed lifetime. It makes no stability,
full-sort or exact-permutation assumption.

The scalar is formatted by `core::decimal::format_i64` into a caller-backed
32-byte array, followed by one ASCII LF. Output is canonical decimal, without
a plus sign or leading zeros, at most 21 bytes. The complete line is staged
before stdout. No CLI, allocation, input, token, limit or rank error publishes
a prefix.

## Ownership and attempts

CLI parsing returns a plain command/index rather than a borrowed argument.
The argument snapshot is explicitly destroyed before help output and before
the data vector is allocated. The selected scalar is copied out, then the
vector is destroyed before formatting or stdout. No borrowed selected view
escapes that cleanup. Standard descriptors are borrowed and never closed.

The normal nonempty workflow therefore has two short-lived argument mappings
and one 524288-byte vector mapping on the current native i64 target. No input,
selection or output allocation follows the initial vector reservation.
Help has no value-vector owner.

| Resource | Bound |
| --- | ---: |
| Captured arguments / bytes | 1 / 64 |
| INDEX | 0..65535 |
| Raw input bytes | 1048576 |
| Values / reserved vector capacity | 65536 |
| Token bytes including sign | 64 |
| Caller input scratch | 1024 logical bytes |
| Caller output staging | 32 logical bytes |
| Input attempts, including EOF and Interrupted | 8192 |
| Data/help stdout attempts, including Interrupted | 64 each |
| Diagnostic stderr attempts | 8 |

Every input attempt consumes its quota. Interrupted retries; other host errors
stop. Positive counts are validated before scanning. At the byte cap, only
the one-byte excess/EOF probe is requested. Thus physical input observed is
at most 1048577 bytes including a rejected extra byte. Invalid input may fail
before EOF; successful selection cannot.

Every output attempt consumes its quota and advances only by confirmed
positive counts. Zero, invalid counts, other errors and exhaustion stop.
An output failure may leave a confirmed prefix without replay or rollback.
The attempt bounds do not impose deadlines on blocking host calls.

| Exit | Meaning |
| ---: | --- |
| 0 | Complete selected value line written, or help written |
| 2 | Invalid CLI/input/token/byte/count/attempt bound or rank |
| 3 | Input or argument-capture host error |
| 4 | Argument or value-vector allocation failure |
| 5 | Data/help output or SIGPIPE-policy failure |
| 6 | Unexpected internal count/view/formatting/allocation contract failure |

Errors attempt the exact line `select_value: operation failed\n` using at
most eight stderr write attempts. Diagnostic failure preserves the primary
status. SIGPIPE is ignored before I/O; setup failure returns 5 silently.
Successful runs have no stderr output. Manual cleanup retains the primary
error; no automatic destruction or second cleanup authority is assumed.

## Target and acceptance

### Accepted help-only usability update

Current application source SHA-256:
`58a52db22bbc3abe551ae9dceeac987cc930fe31bc31f966ca2d60141cdb3219`.
Its help is 474 bytes and now says:
`Input is fully validated before output; input errors publish no data.`
Only that help line and its literal byte count changed after the accepted
initial source below; token, selection, I/O and ownership logic are unchanged.
The updated 28-case CLI group passed in one 8.03s registered test, with three
other tests filtered, in
`target/stdlib-work/slice-selection-value-cli-help-final.log`. Evidence is
`/tmp/select-value-cli-x98snvu5`. This run compiled and admitted the current
source for native Linux x86_64 CPU execution through the same GPU-compiler and
strict ELF/jump checks described below.

The current executed help oracle SHA-256 is
`70960c94cb37ad4a000305d4b066bc5fb29b01bebd8d9865d8174ba6744e6115`.
Only its help literal/length expectation changed. This focused rerun reuses
the existing 28 CLI cases; the total remains 101 distinct cases. The original
model/rejection/I/O receipts retain their initially executed identities below
and are not represented as current-source reruns.

### Initial runtime acceptance

All four registered groups on the initial source passed on the first runtime attempt
in one 8.60s run after a 1.80s driver build, totaling 101 unique native cases:

| Accepted group | Cases | Evidence directory |
| --- | ---: | --- |
| Model | 33 | `/tmp/select-value-model-ze7ggy1i` |
| Rejection | 25 | `/tmp/select-value-rejection-e6r9vvbi` |
| CLI | 28 | `/tmp/select-value-cli-yejkskl4` |
| I/O | 15 | `/tmp/select-value-io-9yrpdhlw` |

The receipt is `target/stdlib-work/slice-selection-value-app-first.log`:
four tests passed with no filtered tests. The registered driver compiled
through the GPU compiler, required an actual ELF64 x86-64 executable and
passed the shared strict jump gate before native Linux x86_64 CPU execution,
using existing allocator and Descriptor services. GPU-device execution and
other backends remain unverified.

Initially executed application source SHA-256:
`b942ea043b09159b72b84dda88bc292a6800dfe390723541a1324131fc1c1b42`.
Initially executed oracle SHA-256:
`1373f255add2811cc422a989bba7d99d934ec3c1eb3fbe4846bf4307c5a3ec44`.
Slice implementation SHA-256:
`d77cb28ceb9f6df5e3fa0f752a36409bc4d2ddab1bd35214969fc39614fd13d5`.

The independent test-only oracle splits only the four admitted whitespace
bytes, checks signed-decimal syntax/range, sorts Python integers and selects
the requested rank. It imports no production parser or selection algorithm.
Executed models cover signs/zeros/extrema/duplicates, all admitted whitespace,
final unterminated tokens, 64-byte and read-boundary tokens, all small ranks,
sorted/reversed input, 65536-value ranks, exact input/count caps and seeded
values. Rejections cover empty/out-of-rank input, malformed/range/length/control
and non-ASCII tokens, excessive input/values and later invalid tokens, with
empty stdout. CLI cases include strict INDEX syntax, help input bypass and
64-byte leading-zero INDEX spellings.

Three selected allocation failures reach both argv owners and the one value
reservation, each returning 4 with empty stdout. Complete traces require
successful same-address/same-size releases for observed successful mappings.
They observe argv release before the 524288-byte vector reserve, no allocation
after the first input read, every owner released before data/help stdout, and
no close of borrowed standard descriptors. This finite evidence does not
establish automatic lifetime enforcement or exhaustive allocation schedules.

I/O cases execute directory stdin, closed-reader stdout, input/output EIO,
read/write Interrupted retries, SIGPIPE setup failure and a required-EOF fault
after complete input. Prepublication errors publish nothing; output retries
preserve the exact scalar line, while EIO/EPIPE return 5. Compact summaries
observe 8192 input errors with status 2, or 64 output errors followed by one
successful diagnostic with status 5. Those summaries establish attempt bounds,
not complete mapping-release ledgers; separate complete traces observe selected
cleanup paths. No successful transfer count is fabricated and no partial-output
coverage is claimed for this small-output program.

These application cases establish selected scalar behavior, not the generic
algorithm's full partition/permutation, owner or complexity contract. General
aliasing safety, leak freedom, arbitrary-failure safety, internal-error
injection and formal verification remain outside these finite receipts.

See `tests/fixtures/stdlib_execution/select_value/README.md` for detailed
scope and retained commands, and `tests/stdlib_select_value_execution.rs`
for the registered driver. Whitespace-only driver formatting after these
receipts does not represent a native rerun. With a warm build and configured
GPU, reproduce using:

```sh
timeout --kill-after=2s 100s flock -w 95 target/stdlib-work/library-gpu.lock \
  env CARGO_TARGET_DIR=target/stdlib-build LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=70000 \
  cargo test --test stdlib_select_value_execution -- --nocapture --test-threads=1
```

Production is entirely Lanius and adds no compiler, runtime ABI, proof or host
service. No Rust/Python library implementation, JSON transport or Wasm
dependency is introduced. See the
[slice-selection plan](library-slice-selection-plan.md) for separate public
algorithm contracts, complexity arguments and library acceptance requirements.
