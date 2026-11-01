# Binary sampler execution fixture

This independent test-only model uses Python bytes slicing in the specified
order: optional reverse, offset, stride, then count. It compares exact stdout,
exit status and diagnostics; binary output is never decoded as text.

| Group | Cases | Coverage |
| --- | ---: | --- |
| model | 37 | Empty and one-byte input, all 256 byte values, NUL/high bytes, ordinary and reversed compositions, zero count, offsets at/past end, u64 maximum parameters, exact 1 MiB input, wide offsets and 15 seeded models |
| limits | 3 | Input one byte above 1 MiB, including count zero and a huge offset; no stdout prefix |
| cli | 39 | Invalid grammar/overflow/zero step, unknown options/operands, every duplicate policy including help/clusters, argument caps, both help forms, help input bypass, attached/equals forms and a bare terminator |
| io | 16 | Directory stdin, real closed stdout, empty-output behavior, closed help output, native multi-transfer baseline, eight reached single syscall faults, read/write interruption caps and actual WouldBlock stdin |

The I/O group traces one 4097-byte baseline and selected faulty executions
using `strace`. It checks that targeted read/write calls use the same descriptor
and requested count as the baseline, and that an allocation denial reaches the
selected mmap with identical arguments. Empty CLI arguments allocate no
argument owner: the first mmap follows a successful stdin read, and the last
occurs after EOF and before stdout. These two points exercise input allocation
and exact-size output reservation respectively. This is a small reached-fault
check, with no custom ownership checker, exhaustive allocation campaign or
leak claim.

Single faults cover read/write EINTR, read EIO, write EIO after one actual
1024-byte stdout write, a zero-byte write, input/output ENOMEM, and SIGPIPE setup
EIO. Positive byte-transfer results are never fabricated. Persistent EINTR
checks the actual 4096-attempt read/write limits; failed diagnostic writes also
spend their separate eight-attempt budget. The real native baseline confirms
five stdout writes of 1024, 1024, 1024, 1024 and 1 bytes. Empty selection on a
closed reader succeeds because it performs no stdout write.

```sh
python3 -B tests/fixtures/stdlib_execution/sample_bytes/oracle.py controls
python3 -B tests/fixtures/stdlib_execution/sample_bytes/oracle.py model PATH_TO_ELF
python3 -B tests/fixtures/stdlib_execution/sample_bytes/oracle.py limits PATH_TO_ELF
python3 -B tests/fixtures/stdlib_execution/sample_bytes/oracle.py cli PATH_TO_ELF
python3 -B tests/fixtures/stdlib_execution/sample_bytes/oracle.py io PATH_TO_ELF
```

Each native child has a 20-second timeout. The registered Rust driver has an
85-second group timeout and uses the shared strict ELF checker on its emitted
executable. Each case retains input, command, output, stderr and exit evidence;
traced cases additionally retain the syscall log. The final line identifies
the evidence directory and executed case count. Eight CPU-only controls cover
hand-computed byte selections, full-width slicing, literal lengths, trace
parsing and the non-I/O case counts. They are separate from native acceptance.

## Acceptance

The registered Rust driver compiled the application through the GPU compiler,
passed the shared strict ELF checker and passed all four tests on 2026-10-28.
These are 95 finite native Linux x86_64 cases: model 37, limits 3, CLI 39 and
I/O 16. Runtime took 9.44 seconds and Cargo build took 1.70 seconds. Both are
recorded in `target/stdlib-work/sample-bytes-runtime-first.log`.

Accepted evidence directories:

- Model: `/tmp/sample-bytes-model-s8tfmb4c`.
- Limits: `/tmp/sample-bytes-limits-0hmwt3q5`.
- CLI: `/tmp/sample-bytes-cli-urlxjxfx`.
- I/O: `/tmp/sample-bytes-io-zz6pp3oe`.

Reproduce the registered driver with a warm local build and configured GPU:

```sh
timeout 100s env CARGO_TARGET_DIR=target/stdlib-build cargo test --test stdlib_sample_bytes_execution -- --nocapture --test-threads=1
```

The GPU compiler emits the native executable; the application itself runs on
the CPU and performs native stdin/stdout I/O. This fixture does not establish
device-side GPU execution, leak freedom, arbitrary iterator correctness or
formal verification. The application source and oracle were unchanged during
the accepted run; no separately retained direct-run executable is claimed.

Executed source SHA-256:
`f2dc47389be7c22f32e23ae790dfb2bd2055619127023ae6952cd160a75b81b2`.
Oracle SHA-256:
`3303757c39451c5646de9dfb9c842b151c5897a1a5c83e35f72cc64de8c3da27`.
