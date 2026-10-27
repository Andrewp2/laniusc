# Directory-at primitive execution

The probe calls only actual `std::file_ops::create_dir_at` and `remove_dir_at`.
See the [module guide](../../../../docs/stdlib-directory-at.md). All three actual
Rust tests and their native oracle groups pass on the frozen source below.

## Finite groups

| Group | Process cases | Scope |
| --- | ---: | --- |
| `namespace` | 24 | Real create/remove, umask, nested/raw names, existing directory/file/dangling symlink/directory symlink, missing/nonempty entries, bad/non-directory fd, absolute path ignoring invalid fd, held anchor after rename plus cwd change. |
| `bounds` | 19 | Three malformed View cases per primitive, embedded NUL, exact 4,095 native versus 4,096 preflight limits, empty native path, invalid modes, mode-before-path precedence and valid mode endpoints 0/4095. |
| `faults` | 12 | Two successful baselines plus reached EIO, EINTR, EAGAIN, ENOSYS and positive result 1 for each primitive. |

These total 55 process invocations, including the two fault baselines that
repeat namespace coverage. The count is not distinct or exhaustive coverage.

## Accepted receipts

Root ran `tests/stdlib_directory_at_execution.rs`: all three tests passed in
6.51 seconds, with `namespace=24`, `bounds=19` and `faults=12`. Runtime receipt:
`target/stdlib-work/archive-directory-primitives-alias-retry.log`.
The separate shared prerequisite Rust driver build passed in 2.63 seconds:
`target/stdlib-work/archive-prerequisite-drivers-build.log`. A driver build alone
does not establish runtime behavior; the three executed tests do.

The initial gate stopped at source admission with LNC0027, before native
execution: `target/stdlib-work/archive-directory-primitives-first.log`.
The probe incorrectly treated `import std::file_ops;` as a short module alias.
Explicit item imports fixed the fixture; production and its reviewed public
signatures did not change between that admission failure and the passing run.

Accepted source SHA-256:

- `stdlib/std/file_ops.lani`:
  `fa5c5b0b496bf56ce844f2d724506b2a4085aae34252ae7514329dcdd357ba37`
- `tests/fixtures/stdlib_execution/directory_at/probe.lani`:
  `8d1fe4ced934d9154efe850854f5a5013a389b6a887578e9549a4861a58a96d2`

## Protocol and observations

The request is five little-endian u64 words (operation, mode, path length,
logical View selector, parent selector) and exactly 4,096 raw path bytes.
The ready and result frames each contain eight u64 words and require a separate
`!` ACK. The native child opens its own parent; no fd is passed through strace.

Before the first ACK, the oracle checks the actual descriptor identity through
`/proc/<pid>/fd`. For the renamed-anchor case, the host renames that directory
and creates a replacement at its old path. After ACK the child changes cwd to
an unrelated directory, then performs the relative operation using the held fd.
Only the original renamed directory may change.

`C/c` markers surround only the primitive call; `P/p` surround caller-parent
close. Native mutation events must be exactly the selected mkdirat/unlinkat,
with the expected descriptor, raw bytes, mode or AT_REMOVEDIR flag. Preflight
cases permit no native operation in `C/c`; stderr marker writes do not count as
payload or filesystem work. Errors and injections must leave the namespace
and sentinel contents unchanged.

The oracle reuses the verified TempFile runtime/source/fd ledger. Exact runtime
instruction sites identify source allocations for both current full-width
0x22 and historical 0x62 profiles; no source allocation is permitted. Each
successful native open must have one close of its actual fd generation. At the
result checkpoint, only descriptors 0/1/2 may remain before ACK/process exit.
The child must then exit zero with no extra stdout; captured stderr must equal
its traced phase markers.

Fault injection is test-only. It must reach the exact baseline native ordinal,
instruction address, call phase and arguments. EINTR and ENOSYS still get one
attempt with no fallback. Injected positive result 1 skips the kernel operation
and must produce typed InvalidCount; it is not evidence of a physical mutation.
No injected close is used. Failed cases retain request, partial reports, command,
stderr/status, syscall trace and filesystem snapshots where available. Killing a
child is diagnostic recovery and cannot establish acceptance.

## CPU controls and root invocations

Fourteen CPU controls pass for native argument/attempt selection, exclusion of
phase markers, remove-directory flag and report identity. They start no native
child or compiler. Existing shared-ledger receipts retain their own finite scope.

Run each group separately, under two minutes, after compiling the probe:

```sh
timeout --kill-after=2s 70s python3 -B tests/fixtures/stdlib_execution/directory_at/oracle.py namespace PATH_TO_PROBE
timeout --kill-after=2s 70s python3 -B tests/fixtures/stdlib_execution/directory_at/oracle.py bounds PATH_TO_PROBE
timeout --kill-after=2s 70s python3 -B tests/fixtures/stdlib_execution/directory_at/oracle.py faults PATH_TO_PROBE
timeout --kill-after=2s 10s python3 -B tests/fixtures/stdlib_execution/directory_at/oracle.py controls
```

The Rust filters are `directory_at_namespace_and_anchor_semantics_execute`,
`directory_at_preflight_mode_and_path_bounds_execute` and
`directory_at_native_failures_are_exact_and_one_attempt` in
`tests/stdlib_directory_at_execution.rs`. Driver compilation and native
execution are separate receipts.

Initial target: native x86-64 Linux on the tested local filesystem. No GPU-kernel,
archive extraction, hostile-directory or power-loss durability claim follows.
