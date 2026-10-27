# Cursor allocation migration

All five current application tests pass native x86_64 Linux execution. They
retain the 124-input classifier model in both CLI modes plus exact boundaries,
malformed input/limits/nonpublication, scripted production I/O helpers, all
reached application OOMs in both modes, and the 4,096-token counts observation.

| Current accepted scope | Tests | Elapsed | Receipt under `target/stdlib-work/` |
| --- | ---: | ---: | --- |
| Grammar model/boundaries, malformed/admission/nonpublication, scripted production I/O | 3 | 13.63s | `lex-scan-workspace-behavior-io-first.log` |
| Reached OOM/native I/O faults and resource observation | 2 | 16.66s | `lex-scan-workspace-faults-cost-first.log` |

These are separate invocations. The accepted production app source SHA256 is
`7454037c6cbdd7f46227611c5b4a317b57ec9e168c525233e1971465f05ea10c`.

The trace gates now pass every raw image through
`../lexer/resources.py`, which reuses the unchanged TempFile verifier and
archive Source full-width mapping ledger. Source instruction provenance,
runtime flags, complete requested lengths, and exact releases are mandatory.
The local Rust parser supplies secondary application descriptor/count summaries;
it cannot admit an unverified allocation.

OOM binding compares native instruction addresses and every allocation argument
through the reached injected position. No fixed allocation floor/distribution
or per-rule scratch count remains. Only a uniquely baseline-derived eager
temporary Frame setup after a sticky code-allocation failure may continue:
its exact allocation/free episode must match that baseline's source instruction
and request, then release immediately.
No other error-path allocation is accepted. The prior `oom17-witness.md` remains
historical evidence rather than a current ordinal or layout assertion.

Ordinary application rule descriptors must close successfully. The separate
injected-close EIO control checks a single logical retirement and exact error
propagation: strace skips that physical close, so this case does not claim a
natural Linux close failure or physical descriptor release. Application OOM
cases inject only allocation failure and require successful descriptor closes.
Both spans and counts passed all **30** reached application ENOMEM positions,
with exact injection binding, empty stdout and complete source release. This
is one fault at a time at successful-baseline positions, not simultaneous
faults or new allocations reached only during error propagation.

The accepted native I/O controls also cover reached read/write EINTR,
read/write/close EIO, a confirmed publication prefix, `/dev/full` and closed
stdin. They retain exact syscall/ordinal/errno checks and never treat an
unreached injection as evidence.

The current 4,096-token counts gate reports exact output and **32 verified
source mmap requests**, **8,895 cumulative requested bytes**, **6,868 peak live
requested bytes**, balanced explicit releases and **79.624585ms traced
correctness/cost harness wall time including setup and verification**.

The clock starts before temporary rules/input/trace setup, and ends after child
execution, trace reading, output checks and verified Python ledger validation.
The application executable had already been compiled by the earlier OOM test
in that combined invocation. This measures neither compiler speed nor isolated application
process time. Allocation totals cover whole-program verified source owners,
not just scanning, rounded kernel pages or RSS.

The older 36,887-request/10.278540515-second receipt remains historical and is
not a freshly rerun baseline. No timing ratio, controlled performance comparison,
throughput result or timing threshold follows from these observations.
