# Bounded byte summary application fixture

The oracle uses independent builtin byte length, sum, minimum, maximum and
endpoints. It does not implement a fold, iterator, quota or batching loop.
Every successful result must be byte-exact fully quoted CRLF CSV, with one
header and one summary row. Empty input has zero count/sum and four empty
byte-stat fields. Reverse mode swaps only the first and last byte.

| Group | Cases | Coverage |
| --- | ---: | --- |
| model | 40 | Empty/singleton/raw binary/invalid UTF-8, every byte, forward/reverse, one-byte batches on small inputs, exact/under/over batch boundaries, maximum batch, exact 4 MiB input and seeded binary data |
| bounds | 1 | One byte over the raw input cap, with no output publication |
| cli | 32 | Batch bounds/grammar, duplicate flags/aliases, unknown options/operands, argument caps, help validation/input bypass and short attached/long equals values |
| io | 14 | Directory stdin, closed data/help stdout, traced baseline, four reached mmap denials, read/write EINTR retries, later read/first write EIO, SIGPIPE setup failure and persistent EINTR read-attempt exhaustion |

The selected allocation faults cover early argument storage, an allocation
after the first successful input read, the first output-stage allocation
after input EOF and a late output allocation. Every ENOMEM must occur at
the selected baseline ordinal with matching mmap arguments, return status 4
and publish no output. Allocation ordering is not a public API.

Each full trace pairs every observed successful mmap with a successful munmap
of the same address and size, and rejects unexpected allocation services.
This finite syscall observation is not a resource checker, exhaustive denial
campaign, lifetime/alias check or proof of leak freedom. Read/write faults
must be reached; retry cases must preserve the independent byte summary.
The later read error requires a positive earlier read and no published CSV.
No positive byte count is fabricated.

Persistent read EINTR uses summary-only strace rather than retaining thousands
of repeated trace lines. It requires 16,384 read calls, all errors, followed by
status 2 and no output. Its allocation releases are not observed by that
summary. Checked-processing overflow and the fold-call cap cannot be reached
under the current valid input/batch bounds and are not claimed as injected
coverage. Library contract tests separately observe per-fold callback/source
effects; this application fixture checks its externally visible summary.

```sh
python3 -B tests/fixtures/stdlib_execution/byte_summary/oracle.py controls
python3 -B tests/fixtures/stdlib_execution/byte_summary/oracle.py model PATH_TO_ELF
python3 -B tests/fixtures/stdlib_execution/byte_summary/oracle.py bounds PATH_TO_ELF
python3 -B tests/fixtures/stdlib_execution/byte_summary/oracle.py cli PATH_TO_ELF
python3 -B tests/fixtures/stdlib_execution/byte_summary/oracle.py io PATH_TO_ELF
```

Each child has a 25-second deadline; each registered group has an 85-second
deadline. Commands, inputs, stdout, stderr, status and optional syscall evidence
are retained per case. The exact input cap uses the ordinary default batch;
batch-one cases remain small. CPU controls check hand summaries, reverse
endpoints, exact-cap arithmetic, group counts and a deliberately missing
release.

## Acceptance

All four groups passed: **87 native Linux x86_64 cases**, with the same
application, oracle and driver across two receipts. The driver used the GPU
compiler and the shared strict ELF checker before CPU execution.

- Model 40 passed in 9.92 seconds; the other three tests were filtered.
  Receipt: `target/stdlib-work/iterator-fold-byte-summary-model.log`.
- CLI 32, bounds 1 and I/O 14 passed in 9.33 seconds; the model test was
  filtered. Receipt:
  `target/stdlib-work/iterator-fold-byte-summary-boundaries.log`.

Evidence directories:

- Model: `/tmp/byte-summary-model-0b9yfhjv`.
- CLI: `/tmp/byte-summary-cli-k2mgamqh`.
- Bounds: `/tmp/byte-summary-bounds-rmn_lwjp`.
- I/O: `/tmp/byte-summary-io-dsoll4va`.

Executed application SHA-256:
`78788a611716d0230e5b7a21e6b68510da9c53266305f1af9cacc39b65ef0fe6`.
Oracle SHA-256:
`6092261549f855022f5eea91ce3737ff6f6a153cd21387294bac4a0099ab6736`.
Driver SHA-256 after whitespace formatting:
`1b058285a4bc6770236d368104ebd29feb609e58c9dda8a5223687c4cdba5899`.
The runtime receipts used driver
`e3d0280f3eea35b0c469a1864d14f57e47600f100c122373564e74c3a3fd499d`;
root applied `rustfmt` afterward without changing behavior or rerunning it.

Nine CPU-only controls also passed. An earlier compilation stopped at mixed
boolean/comparison syntax before runtime; the accepted application adds the
required comparison parentheses without changing the fixture contract.

The I/O receipt reaches all four selected allocation denials, matches observed
successful mappings with explicit releases, and exhausts the 16,384-attempt
read budget under persistent EINTR. These finite observations do not establish
leak freedom or exhaustive allocation-failure coverage. The larger staging
and processing caps are not independently reached by valid summary output.
Device-side execution and formal verification remain outside this receipt.
