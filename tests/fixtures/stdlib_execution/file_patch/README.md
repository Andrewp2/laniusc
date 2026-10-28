# Positional file patch application fixture

The oracle creates real binary files and independently computes preserved
prefix + replacement + suffix. All success and failure cases check exact
resulting bytes. Sparse cases above 4 GiB check sentinel windows, untouched
holes, unchanged logical length and bounded allocated blocks, without reading
or materializing the huge hole. Native commands and evidence are per case.

| Group | Cases | Coverage |
| --- | ---: | --- |
| model | 24 | Nonzero ranges, every byte, 1023/1024/1025/4096-byte boundaries, unchanged replacements, uppercase hex, leading-zero positions, Unicode/non-UTF8 paths, followed final symlink, seeded byte models and three high sparse/hole patches |
| preservation | 6 | First/last mismatches, empty/at-end/partially read EOF and the largest valid nonempty positional start |
| cli | 35 | Arity/help, strict offset/hex/path bounds and nonempty equal lengths before any open |
| io | 17 | Positional retries/failures, confirmed write prefix, open/close errors, primary mismatch on close error, finite EINTR budgets, missing/directory/FIFO host errors, help/signal failures and two reached CLI-allocation denials |

The four groups contain 82 native cases. Each trace requires no lseek and no
shared-cursor payload read/write. Positional
requests must use the exact advancing offset and at most 1024 bytes. Every
write must follow the complete expected read. After successful open, exactly
one close is attempted, including mismatch and I/O failure paths. Normal valid
arguments require exactly the two CLI snapshot allocations; all observed
successful mappings must match explicit same-address/same-size releases.
The positional operation and payload use no extra allocation.

Write failure is intentionally not rollback: the second-chunk EIO case must
leave exactly the first confirmed 1024 replacement bytes and preserve the
remainder. No positive return count is fabricated. Injected close EIO observes
one attempted close/no retry; because strace skips that injected syscall, it
does not establish that the kernel executed a close before process exit.
These finite observations are not leak, lifetime, atomicity, concurrency or
crash-durability proofs. Access restrictions and maximum supported file sizes
remain host/filesystem policy.

```sh
python3 -B tests/fixtures/stdlib_execution/file_patch/oracle.py controls
python3 -B tests/fixtures/stdlib_execution/file_patch/oracle.py model PATH_TO_ELF
python3 -B tests/fixtures/stdlib_execution/file_patch/oracle.py preservation PATH_TO_ELF
python3 -B tests/fixtures/stdlib_execution/file_patch/oracle.py cli PATH_TO_ELF
python3 -B tests/fixtures/stdlib_execution/file_patch/oracle.py io PATH_TO_ELF
```

Every child has a 15-second deadline and every registered group an 85-second
deadline. Commands, stdout, stderr, status and syscall traces are retained.
The oracle contains no production-library implementation and imports no
production model.

## Acceptance

All four groups passed: **82 native Linux x86_64 cases** across two receipts,
using the same application and oracle. The driver used the GPU compiler and
the shared strict ELF checker before CPU execution.

- Model 24 passed in 7.18 seconds; the other three tests were filtered.
  Receipt: `target/stdlib-work/positional-io-file-patch-model-first.log`.
- CLI 35, preservation 6 and I/O 17 passed in 7.57 seconds; the model test
  was filtered. Receipt:
  `target/stdlib-work/positional-io-file-patch-boundaries.log`.

Evidence directories:

- Model: `/tmp/file-patch-model-6o4bv68n`.
- CLI: `/tmp/file-patch-cli-evyl3tz3`.
- Preservation: `/tmp/file-patch-preservation-uxp628zx`.
- I/O: `/tmp/file-patch-io-ojbhxuo7`.

Executed application SHA-256:
`13eb71092f9a8595f0e4b4d313da0dc3d6f0eedf9b0b843887f3bb305b6d92e3`.
Oracle SHA-256:
`62cc1c6fc6199429bc6da4428e21818f072c53998d7d791a28431470bcaade17`.
Preformat executed driver SHA-256:
`902c566aa652f23ef2054a64635aa03666b2d8a51d2bdbdfccdf7c03bb30ce38`.
This driver identity describes the receipts before any final whitespace
formatting.

The I/O group contains 12 injected-fault processes and 42 reached injected
error results: two 16-attempt EINTR budgets and ten single errors, including
the two CLI allocation denials. Its other five processes cover the normal
baseline, missing file, directory, FIFO and closed help output. All observed
successful mappings matched explicit releases. The second-write EIO case
retained exactly 1024 replacement bytes; mismatch and read failures retained
the original file. Injected close failures establish attempts and primary
error policy, not that the skipped close executed in the kernel.

These receipts cover finite actual-file behavior and selected faults. They
do not establish atomic compare-and-swap, concurrency safety, crash durability,
leak freedom, device-side execution, formal verification or exhaustive fault
coverage. Oracle syntax was checked separately; pure control execution is
not included in these native case counts.
