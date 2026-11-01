# Signed-token selection application fixture

The independent oracle splits only ASCII SP/HT/CR/LF, validates signed ASCII
decimal i64 tokens, sorts Python integers and prints the zero-based rank.
It imports no production parser or selection algorithm. Optional signs,
leading zeros, negative zero and exact i64 extrema are retained semantically;
VT/FF and non-ASCII whitespace are invalid token bytes.

CLI is exactly `select_value INDEX` or sole `--help`/`-h`. INDEX is unsigned
ASCII decimal 0..65535 with no sign/whitespace and at most 64 bytes. Input is
at most 1 MiB, 65536 values and 64 bytes per token. The full stream, including
actual EOF at the exact byte cap, must validate before any stdout publication.
Empty input and INDEX beyond the final count fail. Successful output is one
signed decimal scalar plus LF, at most 21 bytes.

| Group | Cases | Scope |
| --- | ---: | --- |
| model | 33 | Signed/zero/extreme/duplicate values, all admitted whitespace, final unterminated token, 64-byte tokens, read-boundary tokens, all small ranks, sorted/reversed input, 65536-value ranks, exact input/count caps and seeded values |
| rejection | 25 | Empty/out-of-rank input, malformed/range/length/control/non-ASCII tokens, excessive values/input and invalid later tokens; all with empty stdout |
| cli | 28 | Arity/help exclusivity, strict INDEX syntax/range/overflow/length, preflight no-read behavior and leading-zero/64-byte index tokens |
| io | 15 | Baseline, three reached argv/value allocation denials, actual stdin/closed stdout errors, read/write EINTR, input/required-EOF/output errors, signal failure and read/write attempt bounds |

Normal input has two argv mappings followed by one Vec<i64> reserve for 65536
values. The argv owners are released before the reserve; no allocation follows
the first input read. Every successful mapping in a full trace requires a
successful same-address/same-requested-length release. Any stdout write while
a tracked owner remains live fails the ledger, including help. Borrowed standard
descriptors must not be closed. Selected ENOMEM faults must occur at their
baseline ordinal with matching arguments, return 4 and publish nothing.

Actual directory stdin and closed-reader stdout exercise host failures.
Input/read errors, including failure of the required EOF observation after
complete data, publish nothing. Output EINTR retries to the exact scalar;
EIO/EPIPE return 5. No successful transfer count is fabricated, no output is
split to create a prefix test, and no partial-output coverage is claimed.
The compact interruption summaries require 8192 read errors (status 2) or
64 output errors plus one successful diagnostic (status 5); these summaries
observe attempt limits, not complete mapping-release ledgers. Full traces
separately observe selected cleanup paths. Signal policy failure is silent.

The driver compiles once per libtest process, requires a real little-endian
ELF64 x86-64 executable and applies the shared strict jump gate. The standalone
oracle also rejects non-ELF targets. Native children have 15-second deadlines
and registered groups 85-second deadlines. Inputs, commands, exact output,
status and selected syscall evidence are retained.

```sh
python3 -B tests/fixtures/stdlib_execution/select_value/oracle.py controls
python3 -B tests/fixtures/stdlib_execution/select_value/oracle.py model PATH_TO_ELF
python3 -B tests/fixtures/stdlib_execution/select_value/oracle.py rejection PATH_TO_ELF
python3 -B tests/fixtures/stdlib_execution/select_value/oracle.py cli PATH_TO_ELF
python3 -B tests/fixtures/stdlib_execution/select_value/oracle.py io PATH_TO_ELF
```

## Acceptance

The initial four registered tests passed on the first attempt in 8.60 seconds:
**101 distinct native Linux x86_64 cases**, with no failures or filtered tests.
The GPU compiler produced the strict-admitted ELF64 program; execution was
on the CPU. Receipt: `target/stdlib-work/slice-selection-value-app-first.log`.

| Group | Cases | Evidence |
| --- | ---: | --- |
| model | 33 | `/tmp/select-value-model-ze7ggy1i` |
| rejection | 25 | `/tmp/select-value-rejection-e6r9vvbi` |
| cli | 28 | `/tmp/select-value-cli-yejkskl4` |
| io | 15 | `/tmp/select-value-io-9yrpdhlw` |

Initial executed identities (SHA-256):

- Application: `b942ea043b09159b72b84dda88bc292a6800dfe390723541a1324131fc1c1b42`.
- Oracle: `1373f255add2811cc422a989bba7d99d934ec3c1eb3fbe4846bf4307c5a3ec44`.
- Slice library: `d77cb28ceb9f6df5e3fa0f752a36409bc4d2ddab1bd35214969fc39614fd13d5`.

The inspected baseline explicitly releases both argv mappings before its
single 524288-byte value reserve. It reads 5400 bytes and actual EOF, releases
that reserve, then writes the correct rank-17 result `-1\n`. There is no heap
allocation after the first read and no borrowed descriptor close. The initial
help trace likewise releases both argv owners before publishing its 489 bytes,
without a value allocation.

All three selected ENOMEM sites were reached at mmap ordinals 1, 2 and 3.
Each returns 4 with empty stdout, and full traces match explicit releases for
every successfully obtained mapping. The required-EOF EIO follows all 5400
input bytes but publishes nothing. Read/write EINTR controls produce the exact
three-byte result; actual closed data/help stdout and injected EIO return 5
with no output, while signal policy failure returns 5 silently. These full
traces establish the selected cleanup paths.

Compact summaries separately record 8192 read errors (status 2), or 64 write
errors plus one diagnostic write (status 5, 65 writes total). They establish
attempt bounds, without a complete release ledger. No partial-output behavior
is claimed or induced by changing production writes.

### Final help follow-up

The help line describing storage internals was replaced with:
`Input is fully validated before output; input errors publish no data.`
Only the application help literal/count and oracle help literal/CPU length
check changed; the corpus and data-processing behavior are unchanged.

All 28 CLI cases passed again in 8.03 seconds, one registered test with three
filtered tests. Receipt:
`target/stdlib-work/slice-selection-value-cli-help-final.log`; evidence:
`/tmp/select-value-cli-x98snvu5`. These cases overlap the initial CLI group;
the corpus still contains **101 distinct cases**. Model, rejection and I/O
groups were not rerun for this help edit and retain their initial source scope.

Current help-run identities (SHA-256):

- Application: `58a52db22bbc3abe551ae9dceeac987cc930fe31bc31f966ca2d60141cdb3219`.
- Oracle: `70960c94cb37ad4a000305d4b066bc5fb29b01bebd8d9865d8174ba6744e6115`.

The inspected final help trace releases both argv mappings before writing
exactly 474 bytes; it performs no stdin read or value allocation. The original
489-byte help observations above are historical to the initial receipt.

Eight CPU control families passed before admission, including literal sorted
answers, full-width values, corpus counts, rejected token references and
deliberate missing-release/early-publication violations. GPU device execution,
formal verification, internal-error injection, automatic lifetime guarantees
and exhaustive faults remain unclaimed. Driver hashes are omitted; root applied
whitespace formatting before the final CLI run without changing the corpus.
