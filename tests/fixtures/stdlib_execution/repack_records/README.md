# Native numeric record conversion fixture

The reference constructs input and expected output independently from abstract
field values. A separate byte-per-field shift/mask encoder uses fixed widths
8/8/4/4/8, with negative signed integers represented at the specified width.
Float payloads remain integer bits throughout: the oracle never creates a
Python float, so signaling NaNs cannot be quieted by host conversion.
Explicit known little/big byte strings also check the model itself; this is
not merely a read/write round-trip comparison.

| Group | Cases | Coverage |
| --- | ---: | --- |
| model | 27 | All four FROM/TO combinations, identities/count 0/singleton, signed extrema/high bits, both zero signs, normal/subnormal/infinity/quiet and signaling NaN payloads, 1024-byte frame boundaries, seeded raw bits and 65536 records |
| rejection | 30 | Header/magic/count/length/EOF/trailing/input-cap errors, high-bit count admission in both orders, later truncation and wrong declared input order, all with empty stdout |
| cli | 23 | Exact lowercase order names, arity/help exclusivity, argument byte caps and input bypass |
| io | 16 | Directory stdin, closed data/help stdout, traced baseline, four reached mmap denials, read/write EINTR, read and required-EOF errors, exact 1024-byte published prefix, signal failure and 8192-call interruption budgets |

The baseline trace requires no mmap after input EOF: conversion reuses the
admitted owned buffer. Four allocation sites cover both CLI snapshot owners
and first/last input growth. Every injected ENOMEM must occur at the selected
baseline ordinal with matching mmap arguments, return status 4 and publish
no output. All successful observed mappings require successful same-address,
same-size releases. This finite observation is not a resource checker,
exhaustive denial campaign, lifetime check or leak-freedom proof.

The second-output-call EIO follows an actual 1024-byte write and must leave
exactly that independently encoded prefix. Read faults, including failure of
the required EOF probe after a complete frame, publish nothing. No successful
transfer count is fabricated. Persistent EINTR tests use compact strace
summaries: 8192 input errors, or 8192 output errors plus one successful stderr
diagnostic call. Those summaries do not observe allocation release.

```sh
python3 -B tests/fixtures/stdlib_execution/repack_records/oracle.py controls
python3 -B tests/fixtures/stdlib_execution/repack_records/oracle.py model PATH_TO_ELF
python3 -B tests/fixtures/stdlib_execution/repack_records/oracle.py rejection PATH_TO_ELF
python3 -B tests/fixtures/stdlib_execution/repack_records/oracle.py cli PATH_TO_ELF
python3 -B tests/fixtures/stdlib_execution/repack_records/oracle.py io PATH_TO_ELF
```

Each native child has a 20-second deadline; each group has an 85-second
deadline. Inputs, commands, stdout, stderr, status and optional syscall
evidence are retained. CPU controls check explicit byte strings, framing,
full-width integers, case counts and a deliberately missing release.

## Acceptance

All four groups passed: **96 native Linux x86_64 cases** across two receipts.
The driver used the GPU compiler and shared strict ELF checker before CPU
execution. The receipt logs and syscall evidence were inspected directly.

- Model 27 passed in 7.80 seconds; the other three tests were filtered.
  Receipt: `target/stdlib-work/native-endian-repack-model-first.log`.
- CLI 23, rejection 30 and I/O 16 passed in 7.62 seconds; the model test was
  filtered. Receipt:
  `target/stdlib-work/native-endian-repack-boundaries.log`.

Evidence directories:

- Model: `/tmp/repack-records-model-bs11ehz7`.
- CLI: `/tmp/repack-records-cli-5gsed9sn`.
- Rejection: `/tmp/repack-records-rejection-20lmhw1w`.
- I/O: `/tmp/repack-records-io-h0v9new5`.

Executed application SHA-256:
`6c2106c1e6b7c8e8c0ff0e1717443190798779bd86cda56dab54159c3b6c9355`.
The committed source differs only by removal of a trailing blank line:
`1e4b7b869b41177385461bb9643a9a7d73c62c46abb21f3a3408db872802646f`.
Oracle SHA-256:
`acab9ead1b8c4087943145fd5e0600c5e3e2db998fe915b8c588bbc6d4fcc0fa`.

Seven CPU controls also passed. Native model evidence includes all four
conversion pairs, explicit IEEE payload cases and the full 65,536-record
frame. Rejection evidence includes header-only high-bit counts `0x80000000`
in both input orders, preventing narrowing before admission from passing.

The I/O group reached four selected allocation denials and matched every
observed successful mapping with an explicit release in its full traces.
It confirmed exactly 1024 converted bytes before the second-write EIO, and
empty output when the required EOF probe failed after the complete input.
Summary traces record 8192 read calls/errors and 8193 write calls with 8192
errors; the remaining write is the successful stderr diagnostic. In total,
ten single-fault traces and two finite interruption campaigns were exercised.

These receipts establish finite bit-exact record behavior and selected fault
handling on the tested target. They do not establish leak freedom, complete
IEEE bit-pattern coverage, device-side execution, formal verification or
exhaustive fault coverage.
