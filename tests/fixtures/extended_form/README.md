# Ordered form direct contracts

The format, API and borrowing contract are frozen in
[`docs/library-form-plan.md`](../../../docs/library-form-plan.md).
These fixtures exercise the production `ext::form` and `ext::form_owned`
modules. The independent oracle, live-owner allocation failures and
`form_select` application have separate drivers and receipts.

## Registered groups

`tests/extended_form_execution.rs` registers four executable groups:

- `form_borrowed_owned_and_generic_read_execute_tiny_admission`:
  selected borrowed input, ordered duplicate fields, original offsets,
  forgiving single-pass decoding, independent owned parse, append and generic
  Read with exact canonical output and real EOF.
- `form_ordered_pairs_binary_components_strides_and_allowed_aliases_execute`:
  empty segments, empty names and values, missing and repeated equals signs,
  literal leading question mark and semicolon, malformed percent, binary NUL,
  lowercase escapes and decoding once. Exact pair spans and decoded bytes,
  copied/fused cursors and all input/output guards are checked on actual
  negative and positive byte strides. A literal expected wire covers all 256
  byte values. Same-start/same-stride forward decoding and backward encoding
  execute in place on both layouts; bytes outside the written prefix remain
  unchanged. Other overlaps are not exercised or admitted.
- `form_preflight_limits_source_metadata_and_read_state_execute`:
  limit ordering and exact boundaries, metadata before unreadable backing,
  unchanged failed component destinations and exact required capacity. Both
  whole-form source representations validate later invalid fields before
  accessing earlier component bytes. Packed ranges reorder and share bytes,
  retain selected offsets, and ignore descriptors outside their selected span.
  Complete output, remaining counts, copied progress inside a percent escape,
  invalid calls, zero-length requests, real EOF and permanent exhaustion are
  checked with generic Read and both destination strides.
- `form_owned_iteration_text_uri_and_stream_composition_execute`:
  source mutation after owned parse proves independent decoded storage;
  generic Iterator/ExactSizeIterator consumers check exact remaining counts,
  forked positions, duplicate order and binary values. Invalid metadata,
  component/total/pair caps and output caps preserve contents. Clear retains
  capacity, destroy retires both buffers, and the original owner is reused.
  A returned ASCII String survives Form clear/destroy. Checked Text projections
  report relative UTF-8 errors and retain a decoded BOM. An existing URI query
  view composes with borrowed/owned form parsing. Encoding then Copier uses
  a selected three-byte scratch span and one provider call per step, checking
  complete bytes, guards, both cumulative counters and observed EOF.

The API introduces no generic callback protocol. Existing Read and iterator
capabilities are exercised by positive generic consumers; this suite does not
add redundant capability-rejection fixtures for those existing protocols.

## Execution profile

Each fixture compiles through the GPU compiler to a Linux x86_64 CPU program,
passes strict ELF/shared in-function jump checks, and executes with a 15-second
child bound. Full syscall traces admit only a successful launch/exit and
bounded successful mmap/munmap lifetimes. Full-width addresses and requested
lengths must match, every allocation must be released, and stdout/stderr must
be empty. The two borrowed-only fixtures admit zero allocations and no other
host effects. Allocation bounds for the owned fixtures constrain finite work
without making vector growth policy a public promise.

Null-backed views appear only on paths required to reject metadata/limits
before access, or with zero selected length. These checks do not validate
physical backing for callers. Huge successful inputs or u64 size overflow are
not simulated by forged spans. Manual lifetime discipline is respected; the
suite does not establish automatic lifetime checking, arbitrary overlapping
storage, panic cleanup, other targets, user-program GPU execution or formal
verification. Selected reached allocation failures are tested separately.

Root alone runs compiler/Cargo/native commands under the shared library lock,
with every outer command bounded to 100 seconds. This fixture owner performs
only source preparation and bounded host checks. Literal byte-length
annotations were independently checked before freeze.

## Receipts

- Tiny admission passed 1/1 in 7.03 seconds, with a separate Rust build of
  1.87 seconds, exit 0 and the complete host-effect/allocation ledger.
  Log: `target/stdlib-work/form-admission.log`. Tested sources: admission
  `3abd9f30...`, driver `f68aeef7...`, borrowed module `0b7ce72e...` and owned
  module `4b638c41...`.
- The remaining run finished with 2 passed and 1 failed in 10.57 seconds
  (separate Rust build 0.18 seconds). Contracts and preflight executed with
  complete no-host-effects traces. Owned failed compilation with LNC0016 at
  line 17:267 because five generic typed assignments lacked a space between
  the closing `>` and `=`. This run supplies no owned-fixture runtime claim.
  Log: `target/stdlib-work/form-direct.log`.
- The owned fixture was corrected by adding only those five spaces; its
  expectations and all other source remained unchanged. Its focused native
  retry passed 1/1 in 8.49 seconds (separate Rust build 0.20 seconds), exit 0,
  with the complete host-effect/allocation ledger. Log:
  `target/stdlib-work/form-owned-direct-revised.log`. Corrected source:
  `eb0e8132...`.
- Independent source review accepted all four fixtures and the driver,
  including actual strides, aliases, metadata precedence, complete outputs,
  owner lifetimes and real EOF. This review is distinct from runtime evidence.
- All four registered groups are accepted across these receipts. The two
  borrowed-only groups performed no allocation or other host work; both owned
  groups released every observed mapping. No source change or native rerun
  followed acceptance.

## Frozen sources

| Source | SHA-256 |
| --- | --- |
| `tests/extended_form_execution.rs` | `f68aeef761c3d368496cefd780ddb24fb59bff19c69740ae4ee26e8da7e992b8` |
| `admission.lani` | `3abd9f301d34a6225e50d40ba163a5f403413882e64aee87f5cca4ba0f91eaf4` |
| `contracts.lani` | `ddf379a8abd02acff5d6e153102315730f4c219885109084fbb28b1d4458923d` |
| `preflight.lani` | `781b319659a25c71e4045aa36c2a6eb46b3e6b46bb61e3bde3bf325d0a6f1665` |
| `owned.lani` | `eb0e81322fd0876c9d8e9e22bb4c9a885099a018c3310905d39bb7d8e268d5ad` |
