# Real unpack CLI fixture

Status: the four initial groups passed 69 process invocations in 10.64s
(`target/stdlib-work/archive-unpack-groups-first.log`): bounds30, reporting5,
arguments27 and trees7. The Rust driver build passed in 1.23s
(`archive-unpack-driver-build.log`). The fifth input-fault group passed directly
against the same retained executable: 1 calibration plus 4 reached injections
(`archive-unpack-input-faults-first.log`), with no new GPU compile. The updated
Rust driver compiled in the shared 1.26s
`archive-materializer-and-unpack-drivers-build.log`; that fifth libtest was
not executed. The first source admission failed at missing defining-module import
`core::io::Error` (LNC0007), before native behavior; the module imports have been
corrected and the import retry compiled successfully
(`archive-unpack-import-retry-compile.log`). That compiler failure
(`archive-unpack-first-compile.log`) is not a runtime failure or a passing test.
Accepted source SHA256:
`90bfb36d56ca7fe269c9f4b315757e14e0b94e3fecc8f9a2fd990f0514bde145`.
The independent read-only source/test review found no blocking issue.
The retained ELF was `/tmp/laniusc_unpack_program_339456_0`, SHA256
`6599f840ce7030d80a1913c628329668e4c86f59f61366bfd08cf54d2838b22a`.

The Rust driver compiles `sample_programs/library/unpack.lani` with the GPU
compiler, then launches its native x86_64 Linux executable. These are real
filesystem programs, not type-only checks or GPU-kernel filesystem operations.

## Finite groups

| Group | Process invocations | Assertions |
| --- | ---: | --- |
| `tree` | 7 | Both formats: binary/empty files, explicit/implied directories, empty archives, arbitrary byte names; exact tree/content/modes, hex reports, input close before mutation, NoReplace with earlier partial publication and later entries untouched |
| `arguments` | 27 | Standalone help lists every limit; exact required flags/separator/operand; unknown, duplicate, attached, signed, malformed and overflowing values; argument count/byte caps; nonblocking no-follow input rejects symlink/FIFO/directory; root symlink/absence/non-directory |
| `bounds` | 30 | Exact byte/read budget including EOF probe; overflow read and exhausted attempts; preparation entries/nodes/depth/path/component/storage/entry/total/work/owned bounds; Run owned/host/cleanup/steps/sync/entropy/name limits; zero write budget's created-and-cleaned temporary; full admission rejects traversal/duplicate/file-parent conflict before effects |
| `report` | 5 | Zero output bytes/writes and an actually closed pipe return 7 after real publication; existing execution failure 5 survives reporting failure; raw byte/newline path appears only as canonical hex |
| `input_faults` | 5 | One normal traced calibration plus four reached input-read injections: EINTR recovery, EINTR exhausts the read allowance, EIO and over-request invalid returned count; archive descriptor/generation/IP/ordinal/count binding, metadata-before-read, exact typed diagnostics, no output mutation on failure and explicit cleanup |

The accepted 69 count includes overlapping controls, not 69 independent
behavioral properties. The additional 5 comprises 1 calibration and 4 injected
cases, for 74 accepted process invocations. Runtime counts are printed only after
every assertion in a group has completed. No broader fault campaign or
power-loss/network-filesystem claim is implied.

## Independent observations and resource authority

The oracle reuses the existing independent archive_source TAR/ZIP fixture
builders read-only. Python tarfile/zipfile and explicit public ZIP records
produce inputs; the actual extracted namespace, file bytes and modes are
observed independently. Reports are parsed as bounded ASCII unique-key rows;
raw paths are compared via hexadecimal decoding. They cannot inject newline
or key syntax.

The trusted TempFile raw-ELF verifier admits exact known allocation/free runtime
profiles, including historical 0x62 and current full-width 0x22 flags, and binds
every source mapping to its verified post-syscall instruction address and
requested length. Every mapping release must match the original request.
The CLI wrapper passes only actual mmap/munmap events into that unchanged
verifier, avoiding interpretation of ordinary stderr diagnostics as phase
markers. All traced mapping lines are preserved; unknown raw-image sites are
not ignored.

A small marker-free FD-generation checker records real openat and fcntl
duplication, requires an owned source for each duplicate, rejects duplicate/
unowned closes and fd reuse while owned, and requires successful explicit
close of every acquired descriptor. No injected skipped-close cases are used
here. Successful extraction also proves the single input descriptor closed
before output namespace operations. Final trace ownership checks observe
explicit release syscalls; they do not credit implicit OS process teardown.
There is no process-held ACK checkpoint in this CLI fixture.

A closed-pipe case suppresses strace's signal-event lines while checking actual
EPIPE, exit 7 and complete resource release. It does not suppress a failed
process status or assert signal timing.

## CPU controls and invocations

The current 35 CPU controls pass, covering independent builder decoding, strict
ASCII/report framing, malformed diagnostics, decimal range vectors, exact
142 source-literal byte lengths, the full limit-name surface, and descriptor
generation mutations, causal metadata/read selection and rejection of mismatched
or unreached input-injection signatures. These controls do not execute Lanius.

```sh
python3 -B tests/fixtures/extended/unpack/oracle.py controls
python3 -B tests/fixtures/extended/unpack/oracle.py tree /absolute/unpack
python3 -B tests/fixtures/extended/unpack/oracle.py arguments /absolute/unpack
python3 -B tests/fixtures/extended/unpack/oracle.py bounds /absolute/unpack
python3 -B tests/fixtures/extended/unpack/oracle.py report /absolute/unpack
python3 -B tests/fixtures/extended/unpack/oracle.py input_faults /absolute/unpack
```

Each child has a 15-second timeout; a group has an 80-second Rust wrapper timeout.
Root serializes compiler/native gates and keeps each outer command under two
minutes. Exact Rust filters:

```text
unpack_real_tar_zip_trees_raw_paths_and_no_replace_partial_publication
unpack_exact_arguments_help_and_nonregular_inputs_precede_effects
unpack_bounded_input_admission_and_run_limits_preserve_namespace
unpack_bounded_reporting_preserves_publication_and_primary_failure
unpack_reached_input_interrupt_error_and_invalid_count_preserve_ownership
```

On a failure, /tmp/unpack-GROUP-* retains the exact command, input archive,
destination tree, stdout/stderr/status, syscall trace and failure explanation.
Successful cases are removed only after the full group passes.

## Separate bounded runtime observation

`observe.py` passed once against the same accepted retained ELF, without another
compile or strace. This is separate from the 74 finite campaign invocations.
It is not counted as a 75th campaign case or a compiler-speed result.

| Observation | Value |
| --- | ---: |
| ZIP entries | 273: 16 explicit directories and 257 files |
| Small binary files | 256, each 128 bytes |
| Repeated-pattern DEFLATE payload | 2,097,152 bytes |
| ZIP input | 71,261 bytes |
| Total decoded file bytes | 2,129,920 bytes |
| One untraced invocation elapsed | 1.653438 seconds |
| Reported writes / syncs | 2,304 / 546 |
| Reported peak owned descriptors | 4 |
| Run requested-owned accounting | 2,811,129 bytes, including Prepared/current ZIP allowance |

The timer includes process startup, input reads, extraction, file/directory
sync, cleanup and report output. Compilation, archive construction and
independent validation are excluded. Exact tree, bytes, modes and every file's
publication/sync receipt were validated. One host/filesystem sample establishes
no comparison or throughput distribution. Run's accounting is not a whole-
program heap/RSS measurement; this untraced sample adds no allocation/FD-ledger
claim. Direct Run fault acceptance remains pending separate fixture corrections.

Every CLI cap was explicit:

```text
--input-bytes 1048576 --input-reads 2048
--entries 512 --nodes 1024 --depth 8
--path-bytes 255 --component-bytes 64 --path-storage-bytes 262144
--entry-bytes 2097152 --decoded-bytes 4194304
--plan-work 16777216 --zip-work 16777216 --metadata-work 16777216
--source-owned-bytes 4194304 --run-owned-bytes 16777216
--program-owned-bytes 33554432
--host-calls 131072 --cleanup-calls 4096
--write-calls 8192 --sync-calls 4096 --entropy-calls 2048
--name-attempts 1024 --steps 262144
--report-bytes 1048576 --report-writes 4096
```

The child timeout was 45 seconds, with an outer 60-second tool bound. The script
checks the retained ELF SHA before execution; it preserves the request, archive,
output tree and full result at `/tmp/unpack-observation-5cqwou2x`. The accepted
log is `target/stdlib-work/archive-unpack-observation-first.log`; archive SHA256
is `92f1ab43f84b53de36a9fdb495ad93bdb7dc55d98592785f434c9cc55420e1ba`.
Its CPU-only fixture control independently decoded all 273 ZIP entries and
validated the explicit cap surface before the native observation.

```sh
python3 -B tests/fixtures/extended/unpack/observe.py controls
timeout 60s python3 -B tests/fixtures/extended/unpack/observe.py /tmp/laniusc_unpack_program_339456_0
```
