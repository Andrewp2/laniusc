# Temporary directories, links and descriptor permissions

Status: implemented after `39e41327`, with all 13 selected executable tests
accepted across separate native commands. This completes the selected
filesystem increment. The complete standard and extended library goal remains
open.

## Boundary and authority

Extend `std::file_ops` through the existing checked `std::linux` syscall
boundary. Add `std::temp_dir` as a manual directory/name owner and a real
`mktemp_dir` application. Production code remains Lanius. No compiler, ABI,
extractor, proof, Rust/Python library implementation or new cryptography belongs
to this increment. Root serializes compiler and native gates under
`target/stdlib-work/library-gpu.lock`; every command stays below two minutes.

The Linux man-pages define [linkat](https://man7.org/linux/man-pages/man2/link.2.html),
[symlinkat](https://man7.org/linux/man-pages/man2/symlink.2.html),
[readlinkat](https://man7.org/linux/man-pages/man2/readlink.2.html),
[mkdirat](https://man7.org/linux/man-pages/man2/mkdir.2.html) and
[fchmod](https://man7.org/linux/man-pages/man2/fchmod.2.html).
Direct x86_64 syscall numbers and flags must agree with installed Linux headers.
There is no libc fallback or ambient umask modification. All initial execution
claims require native Linux x86_64 evidence, not merely GPU compilation.

## Checked primitives

- `hard_link_at(old_fd, old_path, new_fd, new_path, follow:bool)` stages both
  complete paths before one `linkat` call. False links a symlink inode itself;
  true follows the final source symlink. It never replaces an existing name.
- `symlink_at(target, new_fd, new_path)` stages target bytes and new path before
  one `symlinkat` call. Relative/dangling targets are permitted; they are not
  resolved during creation. No link-target normalization or containment claim.
- `read_link_at_into(fd,path,destination:View<u8>) -> Result<LinkRead,io::Error>`
  stages the path and receives into 4,096 packed stack bytes. The request is
  `min(destination.length+1,4096)`, formed without signed overflow. A successful
  syscall result must be within that request. Copy at most destination.length;
  report `LinkRead { copied:i32, complete:bool }`, where complete requires a
  result shorter than the requested buffer. A full probe is explicitly
  incomplete even when every returned byte fits. Empty destinations still make
  a one-byte probe. No terminator or invented total target length is returned.
  Preflight/syscall/invalid-count errors leave the destination unchanged.
- Current-directory convenience wrappers share those exact implementations.
- `set_permissions(file:&File,mode:u32)` checks mode 0..4095, obtains a live
  descriptor and makes one fchmod call. File type bits reject. Host permission
  and filesystem rules remain authoritative; callers can inspect metadata.
- `set_permissions_at(fd,path,mode)` checks mode before path staging and makes
  one three-argument raw Linux fchmodat call (268). It follows the final symlink;
  no flag or emulated no-follow policy is offered. `set_permissions_path`
  supplies AT_FDCWD. These allow permission changes without first opening the
  target for reading, including after a caller closed a mode-zero file.

All use existing byte Path/logical-range/4,095-byte path validation, real
physical backing as a precondition, existing I/O errors and no allocation or
implicit retry. Destination views support native stride and nonzero starts.
Path/destination overlap is valid because the complete path is staged first.
General *at paths retain Linux absolute-path and intermediate-symlink behavior;
they are not leaf-only namespace capabilities.

## Temporary directory ownership

The TempFile owner is the behavioral precedent, not an instruction to refactor
its already accepted implementation. TempDir has a distinct child-directory
lifecycle: exclusive mkdir first, ownership recorded immediately, then child
open with directory/no-follow/close-on-exec options. An open failure must retain
the created name and parent anchor for cleanup. The child is requested with
mode 0700; umask/default ACL/parent inheritance remain host behavior.

The public surface is `empty`, `default_limits`, `TempDir.borrow/state/stats`,
`create_in(parent,limits)`, `parent()`, `directory()`, `name()`,
`owns_temporary_name()`, `close_directory()`, `keep()`, `cleanup()/destroy()`,
`last_cleanup()` and `last_failure()`. Construction validates finite name and
entropy call limits, reserves a 37-byte name, duplicates a live directory
parent with close-on-exec, checks directory metadata/unsupported O_PATH, and
uses fresh 16-byte OS entropy plus `.tmp-`/32 hex digits. Retry only EEXIST,
with exact attempts/collision/entropy accounting and bounded exhaustion.

One active owner controls both descriptors, name allocation and removal duty.
Borrowed Files may not be closed/taken/replaced by callers. Parent renames and
caller-parent closure do not invalidate the duplicate anchor. The namespace
must be stable/cooperative. A name can be replaced by another actor between
mkdir/open/removal; no hostile-namespace security guarantee follows.

Cleanup first attempts removal of only its own empty directory name, with both
descriptors still live. ENOENT disarms removal as already absent. ENOTEMPTY and
other removal errors retain name backing, child and parent descriptors, and
removal duty for recovery. The caller can remove owned children through the
child descriptor or explicitly keep the directory, then retry. An earlier
explicit `close_directory()` naturally leaves only the parent/name for recovery.
No recursive deletion, symlink traversal or silent abandonment. Final cleanup
closes the child and parent once and releases name storage. Close errors retire their
descriptor and are reported; they are never retried. Keep disarms removal
without allocation/I/O, retains borrowed name information until cleanup, and
does not transfer an extra descriptor owner. Repeated cleanup is inert.
First failure and per-attempt cleanup are separate diagnostics. Invalid active
recreation preserves the existing resources and prior failure.

## Verification and real use

Native primitive fixtures and a host filesystem oracle must compare actual
inodes/link counts, symlink bytes, complete/truncated buffers, mode bits,
nonzero/strided outputs, path preflight atomicity and one-call errno behavior.
Include exact-fit, empty output, long/binary targets, symlink-source policy,
collision/nonreplacement, anchored relative paths and closed descriptors.

TempDir fixtures must observe real owner state, 0700 under an explicit test
umask, child operations, caller-parent closure/rename, empty cleanup, retained
nonempty cleanup, keep, close failures and recovery. Inject reached allocation,
entropy, duplicate/stat/flags, mkdir/open/unlink/close failures with instruction/
syscall provenance and exact owner cleanup. A skipped strace close is logical
retirement evidence, not physical close success. Do not infer an operation from
an injection that was not reached.

`mktemp_dir PARENT` creates and keeps an empty directory and prints its generated
basename. Argument/output failures clean the still-owned name; a write can
publish a prefix already accepted by the OS. Native application tests inspect
the resulting directory and explicitly remove it in their temporary fixture.
No production action runs outside bounded test-owned temporary roots.

Each owner freezes its APIs/source before root's serialized native acceptance.
Update guides, inventory and generated references with actual receipts after
those gates. Compiler limitations get small preserved reproductions; they are
not an invitation to modify compiler implementation in this increment.

## Implementation checkpoint

The selected implementations are written. Independent source reviews found no
material issue in FileOps/TempDir under their stated contracts. The application
review found that help output could run before SIGPIPE handling; its author
moved the checked policy setup before all allocation/output, with failure
returning without a write. These are source reviews, not runtime or test-oracle
acceptance. Executable results are recorded separately below.

| Frozen production source | SHA-256 |
| --- | --- |
| `stdlib/std/file_ops.lani` | `21269e340801c09396a133a43ea5f5391307a59de861476605a140f953530ab6` |
| `stdlib/std/temp_dir.lani` | `56898b00479c5051db959b5f05069b7435c337be0b96cfe47c997adaf2c994b6` |
| `sample_programs/library/mktemp_dir.lani` | `118f9a78f53bdab02ad0ed014d226f2c4ba3560124da18eef5b25639160ab4b9` |

## Compiler dependency and equivalent production form

The first application gates failed before ELF emission. The original FileOps
guard `received<0 || received>(requested as i64)` is parsed as a generic
application. A [ten-line import-free reproduction and executable control](../tests/fixtures/stdlib_compiler_state/filesystem_imports/README.md)
is retained. Widening the request into a local before the comparison admits
the complete module and preserves its API, syscall, error order and validation
before destination mutation. Independent review reversed that single hunk to
recover the original source hash. The larger failing import's host fallback
labelled an unrelated Iterator bound; it did not identify the causal construct.
No compiler repair is included.

## Current finite runtime evidence

These receipts use code emitted by the GPU compiler and executed as native
Linux x86_64 CPU programs. They do not supply GPU-kernel filesystem services.
Logs are under `target/stdlib-work/`.

| Surface | Accepted scope | Receipt |
| --- | --- | --- |
| FileOps | Links 28, readlink 19, permissions 12 and preflights 45 process cases; fault group 35 in a separate retry | `filesystem-links-native-first.log`: four pass, one fail in a mixed 6.67s invocation. `filesystem-links-faults-small-poke-retry.log`: fault-only pass, 6.36s. |
| `mktemp_dir` | Four tests: arguments 13, normal creation 5, allocation 4 and host/output/cleanup faults 26 process invocations | `filesystem-mktemp-behavior-local-guard.log`: two pass, 7.64s; `filesystem-mktemp-faults-first.log`: two pass, 7.32s. |
| TempDir | Ownership/recovery 9, creation faults 8, cleanup faults 10 and admission/entropy 19 process cases | `filesystem-temp-dir-native-first.log`: owner passes in a mixed 6.88s invocation with three harness failures. `filesystem-temp-dir-callback-retry.log`: creation/cleanup pass in a mixed 7.66s invocation with one admission harness failure. `filesystem-temp-dir-single-entropy-rule-retry.log`: admission-only pass, 6.07s. |

The first FileOps campaign completed 34 fault cases, then strace rejected its
4,096-byte poke argument before launching the final child. The corrected case
injects the same full count with a 16-byte supplied prefix, requiring exact
count/completeness, that prefix and unchanged outer guards. It leaves the
unprovided copied interior unconstrained. Real 4,095-byte, exact-fit, stride
and alias cases retain full-backing comparisons. The final accepted five group
scopes contain 139 process cases, not the cumulative number of executions
across failed and repeated campaigns.

TempDir's initial three failed groups stopped because injection expectation
assembly overwrote a callback with a dictionary. Correcting that helper
preserved the callback and all semantic/provenance checks. Creation and cleanup
then passed, while the admission group detected strace replacing its first
entropy-injection rule with a second rule for the same syscall. The final
collision fixture forces only its first draw to select an existing file,
directory or symlink; subsequent real OS entropy bytes are bound to actual
candidate names. Every preceding mkdir must return EEXIST, the final distinct
name must succeed, and exact measured counters must fit the finite limits.
Duplicate syscall-injection options now reject before launch. The reached-fault
checker, ownership, cleanup and instruction-provenance assertions remain intact.
Independent reviews reversed each harness correction to recover its previous
reviewed source. Production, probe and Rust driver did not change for either
retry. The four accepted TempDir groups contain 46 process cases, not all
executions across repeated campaigns. Mixed invocation times are not isolated
timings for their passing groups.

The application passes all four tests, including its baseline and all three
reached allocation failures, 26 host/output/cleanup cases and real EPIPE on
closed help/creation output pipes. FileOps passes all five groups and TempDir
all four. Together these are 13 selected Rust tests with 233 accepted group-case
scopes across separate commands, including baselines and repeated setup. They
do not establish 233 independent properties or count cumulative executions.
CPU controls (FileOps 40, TempDir 45 and application 16) validate test machinery
separately; they are not native library executions.

The host profile is Linux x86_64, kernel `7.0.0-38-generic`, with ext4 under
`/tmp`. No compiler IR, ABI, extractor, proof or runtime source is changed.
The initial parser source form remains an explicitly listed dependency.
Manual lifetime/backing preconditions, stable cooperative namespaces,
nonrecursive cleanup, host permission policy and broader target dependencies
remain as documented in the individual guides. The remaining-work audit in the
[roadmap](library-roadmap.md#remaining-work-beyond-atomic-files) retains the full
uncompleted goal.
