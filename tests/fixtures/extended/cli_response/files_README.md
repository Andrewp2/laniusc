# Response-file native provider and owner gates

Status: both direct native groups pass: provider39 and resources31, totaling
70 overlapping group cases with 29 individually reached allocation denials.
Thirty-nine focused Python-only controls pass separately. These are not two
passing registered Rust libtests.
The public contract is [response files](../../../../docs/library-response-files-plan.md).

## Scope and entry points

The two registered filters in `tests/extended_cli_response_files_execution.rs`
compile actual public modules; they contain no Rust library implementation:

- `native_response_provider_files_and_call_failures_execute`
- `response_expansion_native_and_owned_error_resources_execute`

The Python oracle can reuse retained emitted executables without recompilation:

```sh
python3 -B tests/fixtures/extended/cli_response/files_oracle.py provider FILES_ELF
python3 -B tests/fixtures/extended/cli_response/files_oracle.py resources FILES_ELF OWNERS_ELF
python3 -B tests/fixtures/extended/cli_response/files_oracle.py controls
```

Root serializes compiler/native commands, each below two minutes. A process
case has an eight-second deadline; a complete group has 75 seconds and the
registered Python driver has 85 seconds. Compilation is separate from these
oracle deadlines. Evidence directories survive success and failure. Every case
retains its command, binary request, full syscall trace and captured output;
failures additionally retain partial reports, stderr and the native exit code.

## Real provider cases

`files_probe.lani` calls the actual `Provider<cli_response_files::Error>`.
Its accepted provider group has 39 process invocations, including the healthy
fault calibration and repeated setup. These are not 39 independent properties.

- Binary and empty regular files, a real short read, exact byte caps and the
  actual one-byte EOF/overflow probe. Existing Descriptor reads can reduce a
  provider chunk to 1,024 native bytes; small files here need five calls and
  an empty file needs four. The oracle checks actual requests/results.
- The minimum four-credit admission, the reserved close credit and cumulative
  budgets across two loads on one provider.
- Raw non-UTF-8 paths, a renamed directory anchor, changed cwd, AT_FDCWD,
  absent/directory/FIFO inputs, symlink follow/no-follow and a dangling symlink.
  NONBLOCK and descriptor metadata are checked before any content read.
- Negative/overflowing logical ranges, NUL, empty/overlong paths, a negative
  byte cap, constructor rejection and native EBADF from a closed borrowed base.
- Individually reached open/metadata/read errors, charged read EINTR with
  recovery and exhaustion, invalid metadata/read results, close EIO/EINTR and
  a primary read EIO plus a separate close EIO.

Fault ordinals come from an actual healthy trace. Every injected call must be
reached; post-IP, scope, descriptor, request shape and preceding relevant
requests must match its calibration. Read pointers are not cross-process
identities. Injected positive counts skip a read; the invalid-count cases make
no physical-read or short-read claim. The short-read case uses actual file data.

The base directory is created/opened by the native child, without inherited
test descriptors. Provider phases may not close or duplicate it. A live report
checks the physical fd set before caller cleanup; the caller closes it once.
The test does not treat strace's injected close error as physical release:
that injection skips the syscall. The report first proves the library returned
its typed primary/secondary error, then an ACK permits one raw close in a
separate Q/q repair phase for the same fd generation. This is test cleanup,
not a production close retry or evidence that real Linux close retains a fd.

## Expansion and independent returned errors

The resource group first uses actual `Expansion` plus `Files`. A response file
`nested/top` includes `child`; only the base directory's `child` has the right
content. This checks fixed-base nesting rather than including-file-relative
lookup. Successful expanded bytes are checked exactly. The same native probe
is rerun at every source-allocation attempt reached by that baseline.

`files_owners.lani` uses the actual generic Expansion with one small scripted
provider. The first call transfers an owned `held @bad` byte vector; the next
returns a distinct Vec-backed `failure` error. Its three live ACK checkpoints
hold both owners, destroy Expansion while the returned error remains readable,
then destroy the error. Exactly that seven-byte error mapping remains at the
middle checkpoint; no source mapping or acquired fd may remain before exit.
Provider/engine allocation failures are typed, partial argv is never published,
and every successfully captured expansion owner is explicitly released.

Every source-allocation position reached by the two resource baselines is
denied separately. The exact mmap post-IP, requested size/flags and complete
allocation request prefix bind each denial; no fixed allocation count is
assumed. All 29 baseline-reached positions across the two programs are denied
individually. Together with the two healthy baselines, the resource group has
31 process cases. These baselines and repeated campaigns overlap and must not
be added as distinct API coverage or distinct source-code allocation sites.

## Shared authority and observation

The unchanged `kv_publication/source_ledger.py` supplies full syscall trace
admission, exact launch/final-exit normalization and verified raw ELF sites.
The unchanged `archive_source/ledger.py` supplies live full-width source-map
accounting. The unchanged trusted TempFile source ledger independently checks
the final release sequence. No named-symbol fallback, lowered-pointer shortcut
or reinterpretation of mmap flags is introduced.

This fixture adds only explicit launch validation for ACK prefixes (which have
no exit), phase/fd-generation bookkeeping and independent expected file bytes.
Unknown full-trace events, extra launches/exits, wrong source sites/sizes,
borrowed-base closes, unbound faults, missing repairs and leaked owners reject.
The 39 CPU controls mutate those boundaries; they execute no compiler or native
Lanius. They are separate from actual runtime gates.

The accepted finite target is native Linux x86_64 CPU output from the GPU
compiler. No other-host, user-GPU, hostile-namespace containment, arbitrary
filesystem timing, kernel-memory or RSS guarantee follows. These cases
do not force a kernel metadata response with a missing STATX_TYPE mask.

## Current finite receipts

`response-files-probe-compile-single-match.log` records successful compiler
admission of probe SHA-256
`f8a564cb2152291f870e1fa8718227769d0591f3ecdadaf26285826b8e1ccd36`.
The emitted native ELF is
`81b3998977e5231132424f54f47a2d1509c78deeba28dc18fa23fcb6bc309d25`.
`response-files-provider-native-first.log` records the first actual provider
group, passing all 39 cases with full-trace, reached-fault, physical
skipped-close repair, source/fd and live ACK checks. Evidence is retained under
`/tmp/response-files-provider-qad6xo3q`. Both logs are in `target/stdlib-work/`.
No earlier probe compile reached native execution.

`response-files-owners-compile-borrow-methods.log` records successful admission
of owning-error probe SHA-256
`5b28229c5a50d293ad86b0ff68b89f0f7c41428c61cffb6f57bf4e021ccc7a59`.
Its native ELF is
`996fd7a8c2e449b644f04b8072005a5590fefe3254ebd6bfc824f403097dfaa5`.
`response-files-resources-native-first.log` records all 31 resource cases and
29 reached OOMs against the two retained executables, with evidence under
`/tmp/response-files-native-resources-klvyij8q` and
`/tmp/response-files-owned-errors-dpymg37g`. All two-/three-ACK source/fd
checkpoints, held error lifetime, explicit pre-exit cleanup, full phase
admission and exact reached-injection bindings pass. No successful earlier
native group is added again. Provider39 plus resources31 totals 70 group
invocations, including overlapping baselines and setup.

The final oracle is SHA-256
`a47276543bc6c6005e986a8da03512148415658151187e320f06ec300d6b52ca`;
the registered driver is
`413b7ab2023010aad738ee4b4d3cf32042d68c2fb3db929c1bb893f8c5dfdf69`.
Independent review closed the phase-admission, fd, statx-input binding and
nonpublication checks before these runtime receipts; shared helpers remain
unchanged.

The registered provider/resource and KV drivers have combined `--no-run`
admission in 2.09s (`response-resource-kv-drivers-build-first.log`), separately
from native behavior. Both receipts are direct retained-ELF Python oracle
runs, not two passing registered Rust libtests. The full library goal remains
open.

## Admission history

The first probe compile stopped before native execution at `vec::new`:
`response-files-probe-compile-first.log` reports LNC0027. A module import does
not create a Rust-style leaf namespace alias. Both fixture probes now use
canonical `alloc::vec::new`; no production/compiler change was needed.
An earlier static API audit likewise replaced a nonexistent FileOps rename
wrapper with the actual `rename_at` operation before admission.

The qualified retry also stopped before execution: LNC0005 at the fixture's
module-qualified None constructor, recorded in
`response-files-probe-compile-qualified.log`. Both probes were then updated to
individual Option/Some/None item imports and constructors. Those import edits
alone did not resolve the full fixture shape, as the next attempts show; no
general compiler cause is inferred from the diagnostic location.

The item-import retry still rejected the None match arm with LNC0005 in
`response-files-probe-compile-item-imports.log`. The source and typed-local
control are preserved separately under
`tests/fixtures/stdlib_compiler_state/response_none_match/`. The preserved full
typed-absent variant also failed, now at its wildcard local; the active retry is
recorded in `response-files-probe-compile-typed-absent.log`. Tiny i32 Some/None
controls compiled and executed, so these failures do not establish a general
None-constructor restriction.

The direct-transfer retry also rejected its literal-false wildcard
(`response-files-probe-compile-direct-transfer.log`); an empty constructor is
therefore not necessary for the observed full-probe failure. Active probes now
decompose failure.cause only once. Provider-arm helpers record or transfer the
payload and return the existing numeric diagnostic code, alongside the other
numeric arms. The owning-error helper transfers the actual returned Vec through
a caller-owned Holder into the existing held owner. Failure metadata,
runtime/publication assertions and the ACK protocol are unchanged. No compiler
implementation work or general cause claim is part of these fixture changes.

The first owning-error probe compile stopped before execution at a unary
`&provider` expression (`response-files-owners-compile-first.log`, LNC0016).
Lanius callers use explicit borrow methods rather than Rust unary borrowing.
The fixture now supplies Script/Holder borrow methods and uses those at both
calls; this is a fixture grammar correction with no compiler dependency claim.

Before the first native gate, independent review strengthened the local ledger
to authorize every call by action phase. Provider L/E actions admit only
openat/statx/read/close and source memory operations; setup, cleanup, protocol
I/O and owned-error actions have separate finite sets. The controls reject
KV-admitted unlink/rename/mkdir/fsync calls in provider actions, writes during
expansion, descriptor mutation during the base check and file I/O by the
scripted provider. Native Expansion failures also assert all public publication
accessors are absent, and the oracle requires its ready flag to remain false.
