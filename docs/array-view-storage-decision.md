# Array view storage decision

**Implemented and verified (2026-10-09).** The user authorized any needed ABI
changes. Both retained array-borrow tests now execute with their original
assertions. All 246 execution/rejection checks pass, with no exclusions; 25
layout, object-format, and resource/lifetime checks and eight interface-export
checks also pass. Evidence is x86_64 Linux ELF emitted by the GPU compiler.
The subsequent body-closure correction passes three focused and 32 affected
regression checks; the preceding full matrix was not rerun. See the
[current checkpoint](compiler-generic-types.md#slice-body-closure-follow-up-2026-10-09).

## Original failure

`repro_ordinary_inline_array_borrow.lani` borrows a record's `[i32; 3]` field
as `[i32]`, mutates the view, and reads through the original field, then mutates
the field and reads through the view. Its generic counterpart forwards the
view through `core::mem::identity`. Both rejected with `LNC0017` in the
2026-10-04 matrix (229 passes and these two failures). The unrelated
native match scheduling and implicit-epilogue relocation defects are fixed. Those
fixes preserve the existing ABI and do not establish the missing alias behavior.

The field addresses descending eight-byte native words. A packed integer
array addresses ascending four-byte elements. Both could become a slice whose
previous runtime value contained only `(data, length)`. After forwarding, the
callee cannot recover the backing storage convention from the checked element
type. `storage_layout.slang` detected this mismatch; `x86/scatter.slang` rejected
the call before publishing an executable. Copying to a temporary would fail
the alias requirements of both tests.

## Implemented contract

An array view is `(data, length, byte_stride)`, with signed stride.
Keep checked type identity separate from storage. A view's index computes
`data + index * byte_stride` after checking the logical bounds. The concrete
element type determines the element's value layout and component widths.
The producer supplies the backing place's stride; no consumer guesses it from
the producer opcode or a scalar type number.

| Backing storage | View data | Stride |
| --- | --- | --- |
| Packed integer array | Address of logical element zero | `+4` |
| Native scalar array | Address of logical element zero | `-8` |
| Native compound array | Address of logical element zero | `-8 * element_words` |
| Zero-sized elements | Existing backing place | `0` |

Forwarding, returning, storing in records/enums, copying, and generic
specialization preserve all three components. Creating a view never copies or
reorders its referent. View element writes and original place writes address
the same bytes. An owned array copy continues to create independent storage.
Nested fixed-array elements retain their concrete value layout; each new view
is constructed from that element's actual place.

`slice_from_raw_parts` publishes its documented backing convention: packed `+4`
for i32 and descending native words for other element layouts. Zero-sized
elements have stride zero. Its receiving context supplies the complete checked
slice type; specialization closes the element layout before construction. Bounds
remain element counts, including zero-sized elements. Invalid layout facts,
unbound element layouts, arithmetic capacity exhaustion, and unsupported raw
backing shapes must fail explicitly. This proposal does not make unchecked raw
pointers safe.

## ABI effect and implementation owners

This changes a slice's native value width from two words to three. It also
changes the derived widths of any record, enum, or array containing a slice.
Slice parameters, returns, stack arguments, field copies, and specialization
layout validation must migrate together. Strings retain their separate
representation. The verified IR schema, extractor, and proofs are outside this
proposal.

`native_value_layout.slang` owns the three component positions and width;
`storage_layout.slang` constructs strides from the backing place. Index loads,
stores, and compound copies share `index_address.slang`; its pure sizing module
is also consumed by byte counting. Index emission belongs to the shared x86
instruction plan. The shader size guard remains enabled at 524,288 bytes.

Semantic parameter/result projection, argument capture, field/element operations,
descriptor copies, declaration homes, target row sizing, byte counting/emission,
and retained layouts use the new width. Native object format version 3 rejects
versions 1 and 2. Rebuild existing native objects before linking them.

## Acceptance requirements and evidence

1. Both retained borrowing tests execute without changing their assertions.
2. Ordinary, local generic, and imported generic calls preserve the original
   place and aliases through reads, writes, copies, returns, and record/enum
   fields, including nested arrays and slices of views.
3. Packed and native backing execute through the same concrete slice function;
   no specialization key depends on the backing's direction or stride.
4. Empty and zero-sized views execute; invalid indexes trap before an access.
5. Complete value copying, existing native argument placement, and mixed
   scalar/string/reference/slice call boundaries remain correct.
6. Resource/reflection/lifetime checks and the full generic execution gate
   pass; unsupported or incompatible layouts reject before ELF publication.
7. The existing 1 MB and 32-parameter performance drivers execute their outputs
   after measurement. Report any speed change and keep the shader size guard.

The complete 246-test gate is partitioned into three disjoint groups of 82,
with no skipped tests. Logs and the binary manifest are
`slice-stride-matrix-{a,b,c}.log` and `slice-stride-matrix-manifest.json` under
`tests/fixtures/stdlib_compiler_state`. `slice-stride-contracts.log` retains 25
passing host checks, including rejection of old object versions;
`slice-stride-export.log` retains eight passing interface-export checks.

`slice_stride_compositions.lani` executes both packed and native backing through
the same slice function, crosses register/stack argument placement, returns
views through local/imported generics, and stores them in Option, records, and
arrays of slices. It verifies mutation aliases and neighboring values and prints
exactly `native` and `packed`. The native-backed bounds test traps with exit 101
for negative and past-end indexes.

`zero_sized_slice_views.lani` executes borrowed and raw zero-sized views,
local/imported forwarding, empty-view copies, observable call effects, and
neighbor checks. Separate read/write tests trap with exit 101 on negative,
past-end, and empty-view indexes. These exposed a body-closure exception for
symbolic slices, which is now removed: a known descriptor width cannot stand
in for a complete generic type. `slice-body-closure-focused.log` has three
passes; `slice-body-closure-controls.log` has 32 affected regression passes.

The existing performance drivers produce correct outputs. The 1 MB compiler
median is 46.696 ms and the 32-parameter median is 414.562 ms, up from the previous
unpaired 37.587 ms and 373.936 ms measurements. Performance preservation is not
established. After the one-shader body-closure correction, the generic driver
measures 384.358 ms with correct output; the 1 MB result above predates that
correction. See [the performance record](stdlib-gpu-performance.md).

An alternative is one canonical physical memory layout plus explicit native
argument/result marshalling. That would also change aggregate layout contracts
and require a wider rewrite of place, field, copy, and object layout handling.
The explicit-stride view is the smaller general change for the two backing
conventions already present.
