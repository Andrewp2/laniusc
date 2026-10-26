# Filesystem link and permission execution fixtures

Status: all five groups passed GPU compilation followed by native Linux x86_64
execution through the separate receipts below. Production code is the actual
`std::file_ops` library. Python is only test transport and an independent host
filesystem oracle; these filesystem operations do not execute on GPU kernels.

## Finite groups

The new Rust driver is `tests/stdlib_filesystem_links_execution.rs`. Each group
compiles the same real Lanius probe, then invokes one bounded Python group:

| Exact Rust filter | Python group | Accepted native case scope |
| --- | --- | ---: |
| `hard_links_and_symlinks_preserve_inode_policy_and_never_replace` | `links` | 28 |
| `readlink_reports_exact_completeness_with_strided_alias_outputs` | `readlink` | 19 |
| `descriptor_and_path_permissions_preserve_open_file_state` | `permissions` | 12 |
| `link_and_permission_preflights_preserve_destinations_without_syscalls` | `bounds` | 45 |
| `reached_link_and_permission_faults_are_one_attempt_and_atomic` | `faults` | 35 |

These counts total 139 cases across the five accepted group scopes. They are
not cumulative process executions: the first 34 fault cases were repeated.
Acceptance is recorded below.
Run groups independently, in table order, with root's normal compiler
lock. An individual native case has an eight-second deadline, a Python group
has 75 seconds, and the Rust oracle wrapper has 85 seconds. Keep every outer
command below 100 seconds. No broad filesystem/runtime suite is required by
these new boundaries.

The host oracle compares real device/inode identities and link counts, checks
that existing files/directories/symlinks are never replaced, and distinguishes
linking the source symlink inode from following its final target. It inspects
relative, dangling and arbitrary non-NUL target bytes directly with `readlink`.
Descriptor-relative cases rename both anchored parents and change the child's
current directory; current-directory wrappers have their own direct cases.

Readlink cases cover empty, exact-fit and truncated output, 4,095-byte targets,
packed and actual native strided backing, nonzero starts and path/destination
aliasing. Every result serializes the full 4,104-byte backing so guards, suffix
bytes and error atomicity are observable. The host computes expected copied
bytes and completeness from the target and public request bound, not by
reimplementing library staging. A synthetic syscall return of 4,096 plus a
16-byte poke checks the full-probe/incomplete boundary: copied must be 4,096,
complete must be false, the supplied 16-byte prefix must arrive and all bytes
outside the copied destination must remain unchanged. The unprovided copied
interior is deliberately unconstrained. This does not claim a 4,096-byte kernel
data write, depend on zero-initialized scratch, or establish that this filesystem
stores a 4,096-byte symlink target. Real 4,095-byte and all other real readlink
cases still compare the entire destination backing exactly.

Permission cases inspect descriptor and path modes, including mode zero and
special bits, and confirm path permissions follow the final symlink. Real
`/proc` fdinfo before/after plus library queries check offset, status flags and
close-on-exec flags. Parent-owned read descriptors allow content comparisons
even after mode zero; they are never inherited by the child. Kernel ownership,
ACL, filesystem and mount policy remain authoritative.

## Effects and failure evidence

The probe is allocation-free. Three stdout/ACK checkpoints permit inspection:

1. Three actual descriptor owners are live and bound to host inodes.
2. The operation has completed, full destination bytes are visible, and its
   remaining descriptors can still be inspected independently.
3. Every descriptor has been explicitly closed before process exit.

The `C`/`c` markers enclose only the primitive. Its phase must contain exactly
one expected syscall, or zero syscalls for a preflight rejection. Complete
paths, fd selectors, link-follow flag, mode and readlink request are checked;
there is no accepted fallback, allocation or retry. The final `P`/`p` phase
closes remaining owners once. Closed-owner cleanup must not close a reused fd.

Path bounds, embedded NUL, invalid View metadata, permission mode-before-path
and readlink destination-before-path precedence require zero effect calls.
Injected EIO/EINTR/EAGAIN/ENOSYS and invalid success counts must hit the actual
baseline syscall instruction and ordinal with unchanged input arguments.
Readlink's output pointer is ASLR-dependent and is pretty-printed differently
on errno; its verified thunk, input fd/path and request remain exact. Error
destinations and skipped filesystem operations must remain unchanged.

The oracle imports the existing TempFile raw allocator verifier and archive
source live-map ledger unchanged. Its outer parser accounts for new link/mode
calls explicitly; only mmap/munmap lines enter the reused source-map parser.
Both verified 0x22/full-width and historical 0x62 profiles remain supported.
Every target syscall post-IP must also belong to the exact 32-byte six-word
Linux syscall thunk, whose syscall instruction boundary is independently
decoded with objdump. Merely being somewhere in an executable LOAD is not
sufficient target provenance.

## Current checks and requirements

The separate CPU control command is:

```sh
python3 -B tests/fixtures/stdlib_execution/filesystem_links/oracle.py controls
```

It currently passes 40 finite controls: 17 reused source-map/trace controls
and 23 local argument, fd-selector, mode, syscall-IP, guard and error-output
controls. The seven new short-poke controls require correct counts, completeness,
supplied bytes and outer guards while accepting arbitrary unprovided interior
bytes. These execute no Lanius native program. Literal lengths, Python AST and
the Rust driver formatting are checked separately.

Native gates require Linux x86_64, strace with syscall injection and
`poke_exit`, objdump, `/proc`, Python 3 and a writable test filesystem supporting
hard links, symlinks and the tested mode bits/4,095-byte targets. No unsupported
filesystem behavior is converted into a passing case. Evidence directories are
retained under `/tmp/filesystem-links-GROUP-*`; all effects are confined to
their test-owned `work` roots. No other target or hostile namespace guarantee
follows from this finite profile.

## Current native receipts

| Accepted scope | Result | Invocation time | Log under `target/stdlib-work/` |
| --- | --- | ---: | --- |
| Links 28, readlink 19, permissions 12, bounds 45 | All four groups passed; 104 cases. Fault group in the same invocation stopped at its last launch. | 6.67 s, complete mixed invocation | `filesystem-links-native-first.log` |
| Faults 35 | Complete fault-only retry passed. | 6.36 s | `filesystem-links-faults-small-poke-retry.log` |

`target/stdlib-work/filesystem-links-native-first.log` passed four groups:
links 28, readlink 19, permissions 12 and bounds 45, totaling 104 native cases.
The complete mixed invocation took 6.67 seconds and also included the fault
group failure; this is not an isolated duration for the four accepted groups.

The fault group completed its first 34 native cases, then installed strace
rejected the final case's 4,096-byte `poke_exit` argument before launching the
child. The failure evidence is
`/tmp/filesystem-links-faults-n88q_pv0/34-read-full-probe-incomplete/stderr.bin`;
there was no syscall trace for that launch. This was a test-tool input failure,
not a product result or accepted full fault-group receipt. The corrected oracle
uses only the 16-byte known prefix described above. Root's fault-only retry
then passed all 35 cases in 6.36 seconds. Probe, Rust driver and production
behavior were unchanged by this oracle correction. The first four groups were
not rerun, and the repeated first 34 fault cases are not added to the 139-case
accepted scope as new cases.

Earlier source admission encountered the
[minimal parser cast/guard limitation](../../stdlib_compiler_state/filesystem_imports/README.md).
The original ambiguous count guard was replaced by an equivalent widened i64
local before these native receipts. The larger import fallback's `core::iter`
label was not the cause; the standalone reproduction fails without imports.
No compiler repair or unrelated inference change is claimed.

## Saved source checkpoint

These SHA-256 values identify the current accepted frozen checkpoint. The
oracle hash includes the separately accepted short-poke correction.

| File | SHA-256 |
| --- | --- |
| `stdlib/std/file_ops.lani` | `21269e340801c09396a133a43ea5f5391307a59de861476605a140f953530ab6` |
| `tests/stdlib_filesystem_links_execution.rs` | `c7c9147758048a00b3a208ef37a8e316579fb8d792815b1daf6d0db6bc78e5ad` |
| `probe.lani` | `0ae3b31afe60a2e53c2a5930e7a2d32c6211aa0d0628961614e4518e7c3876c0` |
| `oracle.py` | `b36e33e3ad3d62172ebf9bd16f0d9065f6c3edcd2ac706d13afb6b739483b9c4` |

The first mixed receipt used oracle `c156cbb97045487cefc0d71655f576e8ac4e5d71f5ea3fc077756a696d7a65a7`.
The source-owner's initial FileOps hash `46dbefa1be4e4478d30136e230edd152a92b3903e3f0fc56119a751bd871744f`
preceded the root-reviewed equivalent local guard/cast source-shape adjustment;
the native receipt uses the current production hash above. No compiler repair
is claimed by either test-tool or source-shape correction.
