# Complete archive metadata admission

`ext::archive_source` compiled and passed four focused native groups: 120
process-case invocations, including eight reached source allocation failures.
The tested profile is x86_64 Linux, kernel `7.0.0-38-generic`, with guard/evidence
directories under ext4 `/tmp`. These are combined metadata-owner receipts;
filesystem extraction and unpack-program acceptance are separate.

[`ext::archive_source`](../extended/ext/archive_source.lani) admits a complete
ustar or classic ZIP archive into one sealed
[`archive_plan::Plan`](extended-archive-plan.md) plus an ordered member table.
The format parsers and [content-only profile](extended-archive-profile.md) retain
their own responsibilities. The adapter does not create files or directories,
open a destination, restore metadata, or decode ZIP payloads.

## API and ownership

```text
default_limits() -> Limits
reservation_bytes(limits) -> Result<u64, Error>
from_tar(input: View<u8>, limits) -> Result<Prepared, Error>
from_zip(input: View<u8>, limits) -> Result<Prepared, Error>
```

`Prepared` is a manual owner. Use `borrow`, `is_live`, `plan`, `len`, `member`,
`decoded_total`, `metadata_units` and `reserved_bytes` while it is live. Call
`destroy` explicitly on every successful owner, including after later consumer
failure. Repeated destruction is inert. After destruction, `len` and reservation
are zero, member lookup returns `None`, and the plan is inactive and empty.
The decoded-total and metadata counters are historical scalars, not liveness
indicators.

Keep the entire immutable archive backing alive through admission and every
consumer. `Member` and `Payload` are shallow borrows, not independent owners.
`Payload::Tar` holds a borrowed data view; `Payload::Zip` holds a borrowed ZIP
entry. The plan owns copied canonical destination paths. Views obtained from
the prepared owner must not outlive that owner. Preserve a raw input view's
start and signed byte stride; no packed, zero-offset input requirement is
introduced by this API.

The member table is in archive order. Each member stores its final plan-node
index, file/directory kind and payload. An implied directory can be coalesced
with one later explicit directory, so an earlier child's parent node can acquire
the later directory entry's explicit ordinal. It is not a duplicate directory
creation instruction. Negative and out-of-range member indices return `None`.

## What success certifies

For TAR, admission consumes the reader through `None`, including the complete
two-record footer and permitted zero trailing padding. It joins prefix/name
through the canonical TAR API and classifies only regular files and directories.
A directory size hint does not contribute decoded bytes or authorize data.

For ZIP, admission first completes the canonical structural parse, including
local/central agreement, before allocating the prepared owner. It then validates
every creator-dependent type/attribute profile and both extra-field sets. The
raw canonical name is the destination authority; allowed Unicode alternative
name metadata is validated and ignored.

Both adapters finish path/type/duplicate/ancestor checks for the entire archive
and seal the namespace before returning success. A later bad entry disposes all
staged tables. No partial `Prepared` is returned. These checks describe a content
extraction profile; no permissions, ownership, timestamps, links, devices, ACLs
or extended attributes are applied.

**ZIP metadata admission does not verify payload integrity.** A ZIP can have
consistent declared CRC/length fields and damaged compressed or stored bytes.
Consumers must call the canonical `zip::extract` and check its result before
publication, including for a directory with zero declared decoded bytes. The
source owner does not claim to bound the later DEFLATE engine's aggregate work.

## Limits and failure behavior

`Limits` contains the namespace planner limits and these independent adapter
limits:

| Field | Meaning |
| --- | --- |
| `max_archive` | Maximum borrowed archive byte length. |
| `max_entry` | Maximum declared decoded bytes for one member. |
| `max_total` | Maximum aggregate declared decoded bytes. |
| `zip_work` | Structural ZIP parser work; independent of profile/planner work. |
| `metadata_work` | Adapter profile charge: TAR `2*path_bytes+1`; ZIP `4*(central_extra_bytes+local_extra_bytes)+name_bytes+1` per member. |
| `max_owned_bytes` | Full reserved requested bytes for Plan and Member capacities. |

The reservation is:

```text
max_nodes * sizeof<Node>() + max_stored_path_bytes
    + max_entries * sizeof<i32>() + max_entries * sizeof<Member>()
```

It charges configured capacities even for an empty archive. A reservation over
`max_owned_bytes` fails before source allocation. This is a logical requested
heap bound, not RSS or rounded mapped pages. It excludes the borrowed input,
test transport, a future extraction `Run`, later decoded ZIP owners, and native
runtime heap. The current implementation reserves the three planner vectors
then the member vector; allocation failure releases earlier reservations.

`Error` preserves a `Cause` and an ordinal. `Bounds`, `InvalidLimits`,
`ArchiveLimit`, `OwnedLimit`, `AllocationFailed`, and the independent
`EntryLimit`, `TotalLimit`, `MetadataLimit` are explicit. `Plan`, `Profile`,
`Tar` and `Zip` retain their underlying error. Ordinal `-1` denotes failure
before a particular member, such as input/preflight, ZIP structural parsing,
or initial allocation. Later TAR/profile/plan failures identify the current
archive ordinal; a seal failure uses the admitted entry count.

Logical view bounds are checked before indexing. The caller remains responsible
for providing valid live backing storage for the declared view. Signed byte
stride and a nonzero start do not weaken that requirement. This module performs
no host service or silent no-op fallback.

## Focused execution gates

The new [Lanius probe](../tests/fixtures/extended/archive_source/probe.lani),
[independent oracle](../tests/fixtures/extended/archive_source/oracle.py) and
[Rust driver](../tests/extended_archive_source_execution.rs) passed four finite
native groups:

- TAR: packed/nonzero/strided raw binary views, prefix joining, implied/explicit
  directory coalescing, later footer/header/path/type/duplicate/conflict errors.
- ZIP: independent `zipfile` and raw metadata archives, stored/DEFLATE payloads,
  creator/type/extras/path failures, later central disagreement, and metadata
  success followed by actual payload CRC rejection.
- Limits: exact/over byte, entry, total, metadata, planner, owned-reservation and
  structural ZIP-work limits, invalid logical views, empty zero capacities and
  no-allocation preflight failures.
- Allocation cleanup: baseline-derived reached allocation positions, exact
  request/site prefix matching, and release of every earlier owner on failure.

The oracle pauses after admission and again after explicit destruction. It
checks verified runtime mapping sites, live requested bytes, `/proc` mappings,
descriptor ownership and host inactivity before permitting exit. Process exit
cannot satisfy an owner-cleanup assertion. Independent Python archive builders
and raw metadata are test fixtures; no Python/Rust library implementation is
added to the product.

## Current execution receipts

`target/stdlib-work/archive-source-groups-first.log` records four Rust tests
passing in **8.09s**, sharing one compiled probe ELF:

| Group | Process-case invocations | Retained evidence directory |
| --- | ---: | --- |
| TAR | 26 | `/tmp/lanius-archive-source-tar-e4nc0olq` |
| ZIP | 26 | `/tmp/lanius-archive-source-zip-5znnpg17` |
| Limits/preflight | 58 | `/tmp/lanius-archive-source-limits-zjaemfiv` |
| Allocation cleanup | 10 | `/tmp/lanius-archive-source-allocations-hzcdmqqf` |

The 120 invocations include repeated baselines and boundary contexts, rather
than 120 disjoint scenarios. Allocation coverage is two baselines plus all four
reached Plan/Member allocation failures for each format. Each injection binds
the baseline's exact runtime site, requested length, native call ordinal and
preceding allocation prefix; all earlier owners are released before exit.

The independent expected namespace uses raw full-prefix identities and explicit
entry manifests; it does not duplicate the planner's table-scan/work algorithm.
Python `tarfile`/`zipfile` verify independent archive construction. Exact and
one-below planner-work gates use the successful public counter while still
checking the independently expected namespace. The adapter's documented metadata
charge is checked separately. TAR/ZIP cases include packed starts 0 and 7 and
native start 3 with actual signed stride **-8**. Payload checks compare exact
binary bytes; CRC-negative ZIP cases require successful metadata admission and
a later real `zip::extract` error, including a zero-length directory.

The fixture bounds input to 32,760 borrowed bytes (4,090 in its strided layout)
and individual decoded payload reports to 4,096 bytes. Ordinary limits reserve
8 members, 16 nodes and 1,024 path bytes. This ELF reports `sizeof<Node>()=72`
and `sizeof<Member>()=320`, giving **4,768 requested source bytes** for those
capacities; the native mappings use the verified full-width profile. Empty
zero-capacity and exact/one-below owned budgets are separately covered. These
finite inputs do not test every default-limit-sized archive or bound later
DEFLATE CPU/native heap.

Accepted SHA-256 identities:

```text
archive_source.lani ebfa8538249da60fca3f66ae8e46028ebfc3646495a4ddd315c34a80e5d3878e
probe.lani          aae5d3307e54cfdd1cbdc40656e61b7df054fdcdf77afe487c282b6295d3422f
probe ELF           762e8cec55c6ccb74fc2343cdc74062bb18bfa77a11eb5bd002b3dbb92a8b923
```

The CPU-only oracle/ledger controls pass **24** finite checks, including 17
live-ledger/prefix controls. `archive-source-driver-build.log` separately records
Rust `--no-run` admission in 1.24s; runtime acceptance comes from the four-group
receipt above. Compilation uses the existing GPU compiler to produce native
x86_64 code. These receipts do not establish GPU-kernel execution of this API
or performance ratios.

Three earlier CLI attempts failed before native execution: the fixture's
`Option<...>=` was lexed as `>=` (`archive-source-probe-first-compile.log`);
the production allocation annotation named an unimported `alloc::vec::Error`
(`archive-source-probe-spacing-retry-compile.log`); and the fixture called the
unimported sibling `core::slice::view`
(`archive-source-probe-allocation-inference-compile.log`). Spacing, the inferred
`with_capacity<Member>` initializer and an exact `view` item import corrected
those admission errors before the passing gate. The public API/layout stayed
unchanged; no compiler change or runtime assertion relaxation was needed.

For a previously compiled probe, each command is bounded below two minutes:

```sh
timeout --kill-after=2s 85s python3 -B tests/fixtures/extended/archive_source/oracle.py tar /absolute/path/to/probe
timeout --kill-after=2s 85s python3 -B tests/fixtures/extended/archive_source/oracle.py zip /absolute/path/to/probe
timeout --kill-after=2s 85s python3 -B tests/fixtures/extended/archive_source/oracle.py limits /absolute/path/to/probe
timeout --kill-after=2s 85s python3 -B tests/fixtures/extended/archive_source/oracle.py allocations /absolute/path/to/probe
```

Filesystem publication remains a separate consumer described in the
[bounded extraction plan](library-archive-extraction-plan.md); this receipt does
not accept it.
