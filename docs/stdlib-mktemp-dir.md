# Temporary-directory command

Status: the four focused executable tests pass 48 native process invocations
across separate receipts on Linux x86_64. Baselines and setup calls overlap;
this is not 48 distinct properties or completion of the full library goal.
Production code is
[Lanius](../sample_programs/library/mktemp_dir.lani), using
[`std::temp_dir`](stdlib-temp-directories.md).

```text
mktemp_dir PARENT
mktemp_dir --help
```

The command creates one new empty directory beneath an existing parent, keeps
it and writes its 37-byte `.tmp-` plus lowercase hexadecimal basename followed
by LF to stdout. The caller removes the kept directory when finished. The
command does not print a full path, create the parent or recursively remove
anything. Arguments and parent paths can contain non-UTF-8 bytes.

## Admission and bounds

The owned argument snapshot admits exactly one selected argument, at most
4,095 bytes excluding its trailing NUL; argv[0] is excluded. Empty parents,
unrecognized leading-dash arguments and extra/missing arguments fail before
filesystem or entropy access. Prefix a parent beginning with `-` with `./`.
`--help` alone prints `usage: mktemp_dir PARENT` plus LF without opening a
parent. At process entry a checked SIGPIPE-ignore disposition makes closed
output pipes ordinary write failures, including help and argument diagnostics.
If its installation fails, the command returns 3 without attempting output.

The parent is opened read-only with directory, no-follow, nonblocking and
close-on-exec flags. Linux path resolution remains authoritative: no-follow
rejects a final symlink; intermediate symlinks and absolute paths retain their
ordinary meaning. This is not a namespace-containment interface. The namespace
must remain cooperative and stable throughout creation and cleanup.

The TempDir uses its defaults: at most 32 candidate names and 128 nonblocking
OS-entropy attempts. New directories request mode 0700, filtered by host umask,
ACL and filesystem behavior. Names derive from 16 fresh OS entropy bytes per
candidate; only EEXIST retries creation. There is no custom random fallback.

Application library storage comprises one argument-view entry, at most 4,095
argument bytes and the 37-byte TempDir name owner. Output uses a 38-element
stack array, with no output heap allocation. The parent, its duplicate anchor
and the child give at most three owned descriptors. Each output fragment admits
at most 64 write attempts, counting interruptions and partial progress. Zero or
invalid progress, WouldBlock, other errors and exhaustion fail explicitly.
These logical bounds do not limit kernel/native memory, stack storage, RSS or
the duration of an individual host call.

## Publication and failure

The command closes the child directory and caller parent before writing a name.
TempDir's duplicate parent still anchors removal. It writes the complete
38-byte line while TempDir owns the name, and calls the I/O-free `keep` only
after that output succeeds. Final cleanup releases the duplicate parent and
name allocation. A kept directory is not fsynced; this is not a power-loss
durability promise.

Output failure attempts empty-directory removal. A previously accepted output
prefix cannot be retracted. If removal fails, cleanup retains the name and
anchor; the command makes a best-effort stderr diagnostic containing the
parent-relative recovery name, explicitly keeps it to transfer deletion duty,
then releases remaining resources. It does not retry removal or recurse. If
stderr also fails, recovery-name delivery is not guaranteed; inspect the
supplied parent. A close error retires its descriptor exactly once, without
retry, and is reported as failure. A final anchor-close error occurs after
publication: the complete printed directory remains kept even though exit is
nonzero.

| Exit | Meaning |
| --- | --- |
| 0 | Directory kept and resources released, or help written successfully. |
| 2 | Argument count/byte limit, empty/option-shaped parent or invalid Path. |
| 3 | Signal setup, host/entropy, output or cleanup failure. Partial output or a kept/recovery name may remain. |
| 4 | Argument or TempDir source allocation failure. Secondary cleanup/report errors do not replace this primary code. |

Diagnostics are bounded and best effort. Successful stdout is exactly one
basename line; failure must be determined from the exit status, not from the
presence or absence of text alone.

## Current execution receipts

The accepted source is `mktemp_dir.lani` SHA-256 `118f9a78...`, unchanged from
the reviewed checkpoint, with TempDir `56898b00...` and FileOps `21269e34...`.
The [fixture guide](../tests/fixtures/stdlib_execution/mktemp_dir/README.md)
records their full hashes. Current receipts under `target/stdlib-work/` are:

| Log | Accepted scope |
| --- | --- |
| `filesystem-mktemp-behavior-local-guard.log` | Two tests in 7.64s: normal 5 process cases; arguments 13, including an actual closed-reader help pipe. |
| `filesystem-mktemp-faults-first.log` | Two tests in 7.32s: allocations 4 (one baseline and all three reached source OOM positions); faults 26, including actual EPIPE, entropy/host failures, close retirement and retained-removal duty. |

These are native Linux x86_64 programs emitted by the GPU compiler, tested on
kernel `7.0.0-38-generic` with test-owned roots under ext4 `/tmp`. They establish
no other host or user GPU-kernel support. Sixteen CPU controls are separate
oracle checks. Driver `--no-run` admission passed in 1.14s in
`filesystem-mktemp-driver-first-build.log`; the runtime receipts above establish
behavior independently of that build admission.

The [Rust driver](../tests/stdlib_mktemp_dir_execution.rs) compiles the actual
application once per test process. Its independent
[host oracle](../tests/fixtures/stdlib_execution/mktemp_dir/oracle.py) inspects
real directory types, mode 0700 under an explicit test umask, link count two,
emptiness, distinct creation names and exact output. It covers relative,
absolute, non-UTF-8 and intermediate-symlink parents; final-symlink rejection;
argument/help/exact-byte-boundary admission; every dynamically reached source
allocation; entropy, directory, close, output and retained-cleanup failures.
Actual closed-reader creation and help pipes require noninjected EPIPE and
cleanup, rather than relying only on a synthetic write error.

Source mappings use the existing verified raw-ELF allocation instruction sites
and exact full-width requested sizes. Every scheduled injection must be reached;
allocation faults bind the baseline syscall ordinal, site, arguments and
allocation prefix. The oracle checks explicit release before process exit.
Injected close errors skip the actual kernel close: those cases establish
logical retirement once and separately record the physically open descriptor
until process exit, not successful native closure. All test mutations and
oracle removal remain inside bounded test-owned temporary roots.

The initial two-test invocation failed before ELF emission in 2.56s
(`filesystem-mktemp-behavior-first.log`), so it supplied no runtime evidence.
The larger import composition's `Mapper<T,Option<U>>` diagnostic was a fallback
mislabel. A [standalone cast/guard reproduction](../tests/fixtures/stdlib_compiler_state/filesystem_imports/README.md)
isolated parser ambiguity in a FileOps comparison. Moving the same widening
cast into a local preserves API/error/copy semantics and admits the current
module. The application and TempDir sources were unchanged; no compiler source
change or broad claim about generic bounds follows.
