# Bounded archive extraction program

`sample_programs/library/unpack.lani` is a real content-only TAR/ZIP extractor
over [archive preparation](extended-archive-source.md) and
[the materializer](extended-archive-extraction.md).
The four initial native CLI groups pass: 69 process invocations in 10.64s,
covering real trees 7, arguments 27, bounds 30 and reporting 5. The Rust driver
build passed separately in 1.23s. A focused fifth input-fault group also passes
directly against the same retained executable: 1 calibration plus 4 reached
injections. The total is 74 process invocations with overlapping controls.
The first compiler admission stopped before runtime at a fixture import-scope
error (`core::io::Error`); the defining module imports are corrected and the
subsequent source admission compiled successfully before those native groups.

## Invocation

```sh
unpack --format tar --root existing-output -- archive.tar
unpack --format zip --root existing-output --input-bytes 1048576 -- archive.zip
unpack --help
```

`--format`, `--root` and the literal `--` separator are required. Exactly one
archive operand follows the separator. Every option occurs once and takes a
separate value; short flags and `--name=value` are rejected. Numbers are unsigned
ASCII decimal with checked u64 overflow. i32 capacities are checked before
conversion. Standalone `--help` and argument rejection precede input allocation
and filesystem opens. The bounded argument snapshot allows 128 arguments and
262144 selected bytes, excluding their trailing NULs.

The output root must exist. Both root and input use no-follow, CLOEXEC,
nonblocking opens. Nonblocking input prevents a FIFO open from waiting before
its metadata can reject it. The input must provide regular-file TYPE metadata;
directories, FIFOs and symlinks are rejected. No stdin or device input is
supported.

All input is copied under a finite byte/read allowance and its file descriptor
is closed before namespace mutation. Read attempts include EINTR and an EOF
probe. An input exactly filling its byte cap must pass a separate one-byte EOF
probe. Interrupted calls never obtain an unlimited helper retry. The full
copied input stays immutable and alive through preparation, execution,
diagnostics and recovery-name copying.

## Limits

Values below are decimal. Zero is accepted by the CLI syntax and has the
underlying module's bounded failure meaning; it never means unlimited.

| Flag | Default | Meaning |
| --- | ---: | --- |
| `--input-bytes` | 67108864 | Maximum immutable input capacity; exact-full inputs require another one-byte EOF read |
| `--input-reads` | 131072 | All input read attempts, including EINTR and the final EOF probe |
| `--entries` | 4096 | Archive entries admitted before execution |
| `--nodes` | 8192 | Canonical namespace nodes, including implied directories |
| `--depth` | 64 | Maximum canonical depth in both preparation and execution |
| `--path-bytes` | 4095 | Canonical bytes per path, at most 4095 |
| `--component-bytes` | 255 | Bytes per component, at most 255 |
| `--path-storage-bytes` | 16777216 | Total stored canonical-path capacity |
| `--entry-bytes` | 16777216 | Bytes per entry; also the ZIP decode-output bound |
| `--decoded-bytes` | 134217728 | Total declared decoded bytes |
| `--plan-work` | 134217728 | Namespace admission work units |
| `--zip-work` | 16777216 | ZIP metadata parse work units |
| `--metadata-work` | 16777216 | Complete-admission metadata work units |
| `--source-owned-bytes` | 33554432 | Prepared namespace/member requested-owned cap |
| `--run-owned-bytes` | 67108864 | Run requested-owned cap, including Prepared and one decoded ZIP payload |
| `--program-owned-bytes` | 268435456 | Whole-program requested-owned envelope described below |
| `--host-calls` | 1048576 | Run's conservative charged host-operation allowance |
| `--cleanup-calls` | 1048576 | Run's reserved cleanup-operation allowance |
| `--write-calls` | 1048576 | Actual file write attempts, including EINTR |
| `--sync-calls` | 1048576 | File/directory sync attempts, including explicit recovery |
| `--entropy-calls` | 1048576 | Nonblocking OS entropy calls, including EINTR/short progress |
| `--name-attempts` | 262144 | Temporary-name attempts |
| `--steps` | 16777216 | Materializer state/walk work steps |
| `--report-bytes` | 67108864 | Cumulative confirmed output bytes, including error reports |
| `--report-writes` | 131072 | Output write attempts, including EINTR/short progress |

The whole-program envelope is a conservative bound on requested source-owned
bytes, excluding executable pages, stack, kernel rounding and host runtime
internals:

```text
input capacity
+ exact argument storage bytes
+ argument View-vector capacity * sizeof(View<u8>)
+ 16384-byte report buffer
+ max(source-owned cap, run-owned cap)
```

Run's cap already includes Prepared and a current ZIP payload, so Source is
not counted twice. The 256MiB default accommodates the selected defaults.
Reservation arithmetic and Source reservation validation happen before input
opens. Work/call limits do not impose a wall-clock deadline on filesystem calls.

## Publication and cleanup

Extraction applies the admitted content profile, not archived ownership,
permissions or timestamps. New directories request 0700 and files 0600, subject
to host permission rules. Unsupported links and special-file metadata are
rejected by preparation. Both formats must pass complete metadata/path
admission before output mutation; ZIP payload integrity is checked as each
entry is decoded.

Files publish with atomic `NoReplace`. Existing destinations are not
overwritten. The namespace must remain cooperative and stable; descriptor
anchoring does not secure names against hostile concurrent writers. An
execution failure can leave earlier published files and directories. There is
no archive-wide directory transaction, rollback or implicit continuation.

The program executes Run once. After failure it preserves the original exit
status, even when recovery succeeds. It makes at most one explicit retry of a
Published-but-unsynced current directory, then performs explicit cleanup. If an
unremoved temporary name remains, it asks Run to keep that name and copies its
37-byte component into caller-owned storage with `take_kept_name`. A keep can
succeed before its subsequent cleanup reports an error; the program inspects
current status and transfers that duty in either case. One final cleanup is
available if resources remain. Successful recovery never resumes the archive.

Unreleased native owners are reported; `destroyed=1` is emitted only when
Run's fallible destroy succeeds. Closing a descriptor is never blindly retried.
A retained kept name is an explicit application recovery duty, not a successful
publication claim. Inspect its canonical parent and component from the recovery
row. A report failure can obscure that row; the process still returns nonzero.

## Reports and exits

Reports are ASCII rows of unique `key=value` fields. Paths and recovery
components appear only as lowercase hexadecimal bytes. Node rows carry the
plan's index, originating ordinal, kind (1=file/2=directory), explicit/implied
status, and canonical path. `status_available=0` means reservation failed
before that status existed; it does not assert that the node was untouched.

Current/node receipts distinguish NotPublished=0, Published=1 and Unconfirmed=2;
file and directory sync; retained name/fd authority; confirmed write prefixes;
rename attempts; and separate file-close, unlink and directory-close errors.
Execution and cleanup failures have separate rows. The execution current row
precedes explicit recovery; final node/current rows reflect later facts. Caller
root close and Run root close are reported separately.

The report buffer is reserved before effects. Each line is bounded to 16384
bytes; each physical write requests at most 1024 bytes. Both confirmed output
bytes and attempted writes have explicit caps. EINTR consumes a write attempt;
zero, excessive counts and other errors fail reporting. SIGPIPE is ignored so a
closed output pipe becomes a counted write failure and explicit cleanup can
finish. Failed reporting never replaces an existing primary nonzero status.

| Exit | Meaning |
| ---: | --- |
| 0 | Extraction, cleanup and reporting completed |
| 2 | Usage, input byte/read limit, or archive metadata/namespace admission failure |
| 3 | Input/root I/O, missing TYPE metadata or nonregular input |
| 4 | Argument/input/report allocation or preparation allocation failure |
| 5 | Run execution failure; partial output is possible |
| 6 | Cleanup failure after otherwise successful extraction |
| 7 | Reporting failed after otherwise successful extraction |

I/O diagnostics preserve native errno; -1 denotes another typed I/O error,
-2 invalid count, -3 allocation, -4 rejected input type/missing TYPE metadata,
-5 exhausted input read allowance and -6 input beyond byte allowance.
Source causes 1..8 name its direct validation/limit/allocation cases;100 plus
Plan's documented ErrorKind index identifies namespace admission failures
(112=allocation). Profile/TAR/ZIP families are 200/300/400. Run's direct causes
are 1..19 in its declared order, I/O is 1000+the I/O code, ZIP 2000 and Atomic 3000.
Stages follow Run's declared order starting at 1. Atomic failures include their
stage (starting at 1), direct I/O code, confirmed prefix and receipt.
These diagnostic codes describe this CLI, not a binary serialization API.

## Verification scope

Focused groups are defined in
[the executable fixture guide](../tests/fixtures/extended/unpack/README.md).
They use independent public-format archive builders and actual destination-tree
observations, plus exact verified raw-ELF source allocation/free sites and
descriptor generations. The program compiles through the GPU compiler to a
native x86_64 Linux executable; its filesystem work does not execute inside
GPU kernels.

The accepted finite profile is native x86_64 Linux on the test host. Initial
logs are `target/stdlib-work/archive-unpack-groups-first.log` (4/4 tests),
`archive-unpack-driver-build.log` and `archive-unpack-import-retry-compile.log`.
The initial import-only failure is retained in `archive-unpack-first-compile.log`.
Source SHA256 is `90bfb36d56ca7fe269c9f4b315757e14e0b94e3fecc8f9a2fd990f0514bde145`.
The independent read-only review at that source freeze found no blocking issue.

The accepted fifth group adds one normal calibration and four reached read injections:
EINTR recovery, EINTR consuming the last permitted attempt, EIO, and a synthetic
returned count above the 1024-byte native request. It binds each injection to
the normal trace's archive-fd generation, metadata-before-read order, call
ordinal, actual instruction pointer and requested count; it never injects
close into the real CLI. A synthetic positive count is invalid-adapter-count
evidence, not actual bytes read. These cases are not included in the initial 69.
The receipt is `target/stdlib-work/archive-unpack-input-faults-first.log` using
retained `/tmp/laniusc_unpack_program_339456_0`, ELF SHA256
`6599f840ce7030d80a1913c628329668e4c86f59f61366bfd08cf54d2838b22a`.
The updated Rust driver compiled in the shared 1.26s
`archive-materializer-and-unpack-drivers-build.log`; the fifth group was run
through Python directly, without another GPU compile or a fifth libtest claim.
The oracle's 35 CPU controls and 142 literal byte-length checks also pass.

### One bounded runtime observation

The separate `observe.py` tool ran the same retained accepted ELF once,
without tracing or compilation. An independent ZIP contained 273 entries:
16 explicit directories, 256 binary files of 128 bytes each, and one
2,097,152-byte repeated-pattern DEFLATE payload. The archive was 71,261 bytes;
decoded file content totaled 2,129,920 bytes. Exact tree, content, modes,
per-node publication/sync facts and successful cleanup were validated.

The invocation took **1.653438 seconds** on the test host. Its timer included
process startup, input reading, extraction, file/directory sync, cleanup and
report output. Archive generation, compilation and independent validation were
outside the interval. This single observation establishes no comparison,
throughput distribution or compiler-performance result, and is separate from
the 74 finite campaign invocations.

Requested caps included input 1MiB, entries 512, nodes 1024, path storage 256KiB,
Source 4MiB, Run 16MiB and whole-program 32MiB. All 25 explicit caps are recorded
in the [fixture guide](../tests/fixtures/extended/unpack/README.md) and retained
`request.txt`. Run reported 2,304 writes, 546 syncs, 4 peak owned descriptors and
2,811,129 requested-owned accounting bytes. That last figure includes its
Prepared/current ZIP allowance; it is not whole-program heap peak or RSS.
The observation itself does not add a traced resource-ledger receipt.

Receipt: `target/stdlib-work/archive-unpack-observation-first.log`.
Evidence: `/tmp/unpack-observation-5cqwou2x/observation.txt`, alongside the input,
output tree, command, caps and captured diagnostics. Archive SHA256:
`92f1ab43f84b53de36a9fdb495ad93bdb7dc55d98592785f434c9cc55420e1ba`.

No arbitrary filesystem/power-loss safety, hostile namespace security,
metadata restoration or other target support is claimed. Direct materializer
fault acceptance remains pending its fixture corrections. Detailed materializer
and Atomic failure campaigns are tracked separately; these CLI receipts do not
establish their fault coverage.
