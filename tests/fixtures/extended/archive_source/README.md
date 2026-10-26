# Archive-source executable admission fixture

Four native groups pass against the real `ext::archive_source`: TAR 26, ZIP 26,
limits 58 and allocation cleanup 10 process-case invocations. The Python side
constructs independent inputs and expected namespaces, verifies payload bytes,
and audits native source ownership. Filesystem extraction is a separate gate.

## Current receipt

`target/stdlib-work/archive-source-groups-first.log` records all four Rust tests
passing in 8.09s with one shared compiled probe. The 120 process invocations
include repeated baselines and boundary contexts; they are not a distinct
coverage count. The allocation group is two baselines plus eight reached source
OOM cases: the three Plan reservations and Member reservation for both formats.
Each failed native allocation matches the baseline's exact post-IP, arguments,
ordinal and preceding allocation prefix. All held owners are checked before
the final ACK and exit.

Retained evidence roots:

```text
TAR         /tmp/lanius-archive-source-tar-e4nc0olq
ZIP         /tmp/lanius-archive-source-zip-5znnpg17
limits      /tmp/lanius-archive-source-limits-zjaemfiv
allocations /tmp/lanius-archive-source-allocations-hzcdmqqf
```

Actual profile: native x86_64 Linux `7.0.0-38-generic`, ext4 under `/tmp`,
`strace` and `/proc`, verified full-width source mappings. The probe ELF reports
Node width 72 and Member width 320. The ordinary 16-node/1,024-path-byte/8-member
caps therefore reserve 4,768 requested bytes. Both formats pass native start 3
with actual byte stride -8, alongside packed starts 0 and 7. Request framing
bounds input to 32,760 bytes (4,090 in the native-strided layout); payload frames
bound one decoded member to 4,096 bytes. This is finite admission/ownership
evidence, not maximum-default-size or aggregate DEFLATE CPU coverage.

```text
SHA-256 archive_source.lani ebfa8538249da60fca3f66ae8e46028ebfc3646495a4ddd315c34a80e5d3878e
SHA-256 probe.lani          aae5d3307e54cfdd1cbdc40656e61b7df054fdcdf77afe487c282b6295d3422f
SHA-256 probe ELF           762e8cec55c6ccb74fc2343cdc74062bb18bfa77a11eb5bd002b3dbb92a8b923
```

`archive-source-driver-build.log` records separate Rust `--no-run` admission in
1.24s. Earlier CLI logs are pre-native admission errors, all corrected before
the passing run: `archive-source-probe-first-compile.log` is fixture `>=`
tokenization; `archive-source-probe-spacing-retry-compile.log` is an unimported
production annotation type, fixed with inferred `with_capacity<Member>`;
`archive-source-probe-allocation-inference-compile.log` is a missing exact
`view` item import in the fixture. No public API/layout or compiler change was
needed. The oracle's runtime assertions remained intact.

## Bounded commands

Reuse one compiled `probe.lani` ELF; run exactly one group per command:

```sh
timeout --kill-after=2s 85s python3 -B tests/fixtures/extended/archive_source/oracle.py tar /absolute/path/to/probe
timeout --kill-after=2s 85s python3 -B tests/fixtures/extended/archive_source/oracle.py zip /absolute/path/to/probe
timeout --kill-after=2s 85s python3 -B tests/fixtures/extended/archive_source/oracle.py limits /absolute/path/to/probe
timeout --kill-after=2s 85s python3 -B tests/fixtures/extended/archive_source/oracle.py allocations /absolute/path/to/probe
timeout --kill-after=2s 20s python3 -B tests/fixtures/extended/archive_source/oracle.py controls
```

CPU controls: 24 pass, including 17 live-ledger/prefix controls. These do not
constitute Lanius runtime acceptance. Each native group has an internal 75-second
deadline, each child phase sequence seven seconds, and the Rust wrapper an
85-second deadline. Each command remains below two minutes. Failures retain the
binary request, emitted prefix, syscall trace, command and stderr in a printed
evidence directory; the outer timeout is not the only diagnostic signal.

Rust filters in `extended_archive_source_execution`:

```text
archive_source_tar_seals_full_metadata_and_preserves_borrowed_binary_payloads
archive_source_zip_separates_metadata_admission_from_payload_integrity
archive_source_limits_preflight_owned_bytes_and_independent_work_budgets
archive_source_reached_allocation_failures_release_staged_owners_before_exit
```

## Probe protocol

Only the test pipe uses this binary format. Request: eighteen little-endian
u64 values, then the archive. Values are format, layout, payload-check flag,
input length, invalid-view selector, and thirteen caps in the order recorded by
`oracle.py::FIELDS`. Layout 0 is packed, 1 starts at byte seven, 2 uses a native
non-unit-stride `u8` array starting at element three. Input and framing backing
are stack allocated. The probe checks that input bytes remain unchanged.

Every output is prefixed by its little-endian u32 body length. Frame 1 contains
twenty u64 header values and the complete successful node/member table. It
reports a raw `getpid`, the signed input stride, exact `sizeof<Node/Member>`,
reservation and public counters. Error frames contain no table. Before ACK `A`,
the oracle checks a successful live owner or complete error-path release.

After the first ACK, requested payload checks call the real `zip::extract` or
read borrowed TAR bytes. The CRC-negative ZIP fixtures deliberately require
metadata success followed by a payload error. The probe destroys the prepared
owner twice, checks the inactive API behavior, and emits frame 3. Before the
second ACK, the oracle requires all source mappings to be released. Exit cleanup
cannot make a leaked owner pass.

`ledger.py` reuses the existing TempFile raw ELF opcode verifier and final source
mapping ledger unchanged. Its focused live-prefix extension preserves exact
post-IP, mmap flags, requested length, pointer and release checks for both
MAP_32BIT and full-width source profiles. It reconstructs stdout from successful
syscall bytes across short writes; one frame need not equal one native write.

The host-free process must own only descriptors 0, 1 and 2 at both checkpoints.
A guard directory's exact names/bytes must remain unchanged, and every traced
call must be allocation/release, stdin/stdout or the explicit getpid. Native
allocation failures are derived from the baseline's reached verified source
mmap calls; each injected prefix and released predecessor is checked.

The reservation assertion covers Plan + Member requested capacity bytes only.
It excludes the borrowed archive, later ZIP decode allocations and future
filesystem run owners. No filesystem extractor, GPU kernel, benchmark ratio,
aggregate DEFLATE-work or general archive-restoration claim follows from this
fixture.
