# Values, raw storage and memory views

[`core::mem`](../stdlib/core/mem.lani) provides 11 source functions and access
to six compiler intrinsics. Its value helpers allocate nothing. Its raw-view
helpers describe borrowed storage; they do not allocate, initialize or free it.
The concrete layout described below is the current **x86_64 Linux** layout,
not a C ABI or a target-independent serialization format.

## Source helpers

`MemoryCapability` aliases `bool`.
`VALUE_HELPERS_REQUIRE_RUNTIME` and `VALUE_HELPERS_REQUIRE_ALLOCATOR` are false.
`value_helpers_require_runtime()` and `value_helpers_require_allocator()`
return those constants; `value_helpers_are_runtime_free()` returns true.
These describe the value-helper bodies, not the expressions supplied as their
arguments or a dynamic test of target support.

| Function | Contract |
| --- | --- |
| `identity<T>(value) -> T` | Return the value |
| `first<T>(left, right) -> T` | Return the left value |
| `second<T>(left, right) -> T` | Return the right value |
| `select<T>(condition, when_true, when_false) -> T` | Return the selected value |
| `typed_slice_from_raw_parts<T>(data, length) -> [T]` | Assert nonnegative length, then construct the type's canonical raw view |
| `size_of<T>() -> usize` | Absolute byte stride of the type's canonical raw view |
| `typed_slice_from_storage<T>(storage, length) -> [T]` | Construct a raw view anchored within `length` storage slots starting at the allocation base |
| `typed_prefix_from_storage<T>(storage, capacity, length) -> [T]` | Construct the first `length` elements at the same addresses as a capacity-sized storage view |

The four value helpers have no trait bound, arithmetic, validation, deep clone,
move or destructor behavior. Ordinary value copying applies. A fixed array or
record gets its own outer value storage; references, strings, slices and
manually owned handles inside it copy shallowly. Copying an owned collection
handle does not create another allocation or another valid owner. Keep one
active owner and follow that type's explicit release contract.

These are ordinary functions with **eager arguments**. Both arguments of
`first`/`second`, and both value arguments of `select`, are evaluated before
entering the helper. The condition does not suppress a failing, allocating or
effectful expression in an unselected argument. Use control flow when only one
expression should execute. No unused resource is automatically destroyed.
Copy cost can depend on the number of words in `T`; returning a fixed array is
not necessarily constant work. The scalar tests include negative zero and NaN
classification; they do not establish an exhaustive floating-payload model.

## Compiler intrinsic spellings

The following calls have compiler implementations rather than Lanius bodies.
They are separate from the 11 source helpers and from the host allocator:

| Spelling | Result and role |
| --- | --- |
| `core::mem::i32_array_data_ptr(array)` | `ptr` to the array place's logical element zero; the retained direct mutation tests use packed i32 arrays |
| `core::mem::i32_slice_data_ptr(view)` | `ptr` copied from a slice descriptor's data component; does not return its count or stride |
| `core::mem::string_data_ptr(text)` | `ptr` to the string's borrowed byte data, not its descriptor |
| `core::mem::i32_slice_from_raw_parts(data, length)` | Canonical packed `[i32]` raw view |
| `slice_from_raw_parts(data, length)` | Contextually typed `[T]` raw view; the complete receiving type determines `T` |
| `core::mem::slice_stride(view)` | `isize` signed byte stride stored in that particular slice descriptor |

The unqualified `slice_from_raw_parts` spelling is used in the source helpers
and the direct typed-intrinsic fixture. It does not infer an element type from
the pointer's contents. Prefer `typed_slice_from_raw_parts<T>` for an explicit
element type and its nonnegative-length assertion. The legacy `i32_` names do
not make pointer extraction a type conversion or repack the backing.

The compiler's intrinsic table is in
[`params.rs`](../crates/laniusc-compiler/src/type_checker/params.rs), with result
identities in
[`intrinsic_result.slang`](../shaders/type_checker/calls/intrinsic_result.slang).
The raw constructors check pointer/integer argument categories during type
checking; this does not establish runtime pointer validity. A direct intrinsic
does not supply the source wrapper's assertion or a recoverable error result.
Use nonnegative `i32` element counts. Do not rely on admission of another
integer type to preserve a count outside that domain.

An extracted pointer retains neither allocation ownership nor descriptor
metadata. Extracting a pointer and rebuilding a raw view can therefore lose
the original stride. Keeping the original view preserves it. For strings, keep
the known byte length separately; `string_data_ptr` supplies no length and no
NUL-termination guarantee. String/literal backing is borrowed readable data,
not permission to mutate it. No intrinsic returns a pointer that outlives its
backing place.

## Native values and slice strides

A native slice stores three components: data, logical element count and signed
byte stride. Indexing first checks the logical index, then addresses element
`i` using `data + i * stride`. The data component is the address of that
element's first logical value word, which need not be its lowest address.
Compound value words descend in memory. This representation is recorded in
[`native_value_layout.slang`](../shaders/native_value_layout.slang) and
[`storage_layout.slang`](../shaders/codegen/lir/x86/storage_layout.slang).

An array borrowed as a slice retains its **actual backing stride**. Checked
element type alone does not select that stride:

| Backing used to create a slice | Signed stride |
| --- | ---: |
| Packed local i32 array | +4 |
| Native scalar array, including native u8 arrays | -8 |
| Native compound array with `W` words per element | `-8 * W` |
| Zero-sized element array | 0 |

For example, the same `[i32]` function can receive a packed local array with
stride +4 or an inline record array field with stride -8. The same `[u8]`
function can receive packed bytes with stride +1 or a native u8 array with
stride -8. Native byte elements occupy word slots; a raw byte view accesses
individual bytes. Forwarding, returning or copying a slice descriptor preserves
its count and stride and aliases the same elements. It does not copy those
elements. See the [array-view storage decision](array-view-storage-decision.md)
and [borrowed slice operations](stdlib-slice-views.md).

### Canonical raw layout and `size_of`

Raw constructors cannot recover how an arbitrary pointer was produced. The
native lowering assigns them the following conventions:

| Raw element type `T` | Raw byte stride | `size_of<T>()` |
| --- | ---: | ---: |
| `i32` | +4 | 4 |
| `u8` | +1 | 1 |
| Zero-sized type | 0 | 0 |
| Any other supported concrete type with `W` native words | `-8 * W` | `8 * W` |

`size_of<T>()` constructs a zero-length null raw-view probe and takes the
absolute stride. It performs no element access or allocation. It is an ordinary
runtime-returned value from the instantiated function body, **not a constant
expression**. It is useful for raw slot allocation, not a way to discover the
size or layout of a particular existing array place.

The focused size fixture asserts `u32` and `bool` are 8 bytes in raw storage,
a two-i32 record is 16, `[i32; 3]` as one raw element is 24, `str` is 16,
`[i32]` is 24, and an empty record is 0. The native layouts of other supported
scalar values also use a word slot. A `str` slot holds a descriptor, not an
inline copy of its text; a slice slot holds its three-component descriptor.
The fixed-array size assertion does not establish arbitrary raw nested-array
reads/writes or every compound layout.

Thus `size_of<i32>() == 4` does **not** imply every `[i32]` has stride 4.
Likewise `size_of<[i32; 3]>() == 24` does not make an ordinary packed local
three-i32 array occupy 24 contiguous data bytes. Do not reinterpret a native
word array as packed bytes, or rebuild a native-backed i32 view from its data
pointer with the packed raw constructor. Borrow or retain the original slice
when its layout is already correct.

## First-element pointer versus allocation base

`typed_slice_from_raw_parts<T>(data, length)` uses **data as given** for logical
element zero. For packed i32/u8 this is the lowest element address. For other
nonzero-sized native values, later elements and their remaining words descend
from it. It is not generally the base returned by an allocator.

The caller must establish nonnegative length, the type's alignment and complete
layout, initialized elements when reading, and live backing for every addressed
word/byte. The wrapper checks only length with `assert(length >= 0)`; it cannot
check addresses or their allocation. It creates no owner and performs no copy.
A zero-length null view is used internally for layout queries and is not
dereferenced. That is not permission to dereference null for nonempty data.

### Two two-word records

Let `P` be `struct P { x: i32, y: i32 }`, and let `B` be the base of a live
32-byte allocation aligned to 8. Its two native raw slots are 16 bytes each:

| Logical field | Native word-slot address |
| --- | --- |
| `values[0].x` | `B + 24` |
| `values[0].y` | `B + 16` |
| `values[1].x` | `B + 8` |
| `values[1].y` | `B` |

The raw data pointer is `B + 24` and stride is -16. `x` and `y` are i32 values
in eight-byte native slots; the table does not promise a portable representation
for unused slot bits. It is not C's adjacent four-byte-field layout.

This address table follows the current lowered field word offsets and negative
word displacements. The existing `core_mem_generic_slice.lani` fixture uses
the corresponding 32-byte two-field-record allocation and `base + 24` data
pointer, writes both records and checks their fields. It is source/layout and
fixture evidence, not a newly executed address-dump test. Release `B` with its
matching allocation size/alignment; never release the interior `B + 24` view
pointer as if it owned the allocation.

## Storage-base and capacity-anchored views

`typed_slice_from_storage<T>(storage, length)` accepts the **lowest storage
address**, with room for `length * size_of<T>()` bytes. Its source assertion
rejects negative length. The documented storage contract requires alignment
8, which serves the supported native layouts.

For a positive raw stride, zero stride, or length zero, it uses `storage`
directly. For negative stride and positive length it computes
`data = storage + size_of<T>() * length - 8`, then constructs that many raw
elements. The final `-8` selects the first logical word at the top, not the
lowest byte of the first element's multiword slot.

The storage count anchors the addresses. For the two-record example,
`typed_slice_from_storage<P>(B, 2)` starts at `B + 24`, but calling it with
length 1 starts at `B + 8`, which was the second element of the two-slot view.
Using the current initialized length in place of reserved capacity would
silently select different elements as that length changes.

Use `typed_prefix_from_storage<T>(storage, capacity, length)` for a collection's
initialized prefix. It asserts `0 <= length <= capacity` (which also excludes
a negative capacity). For a nonempty negative-stride prefix it skips
`size_of<T>() * (capacity - length)` bytes before constructing the shorter
storage view. This preserves the full capacity-sized view's element-zero
address. In the example, the capacity-2 prefix of length 1 starts at `B + 24`,
and aliases `full[0]`, not `full[1]`.

A zero-length prefix takes the empty fast path: its data pointer is the supplied
storage base, not necessarily the full view's element-zero pointer. Its stride
still describes the raw type, and it has no readable element. Do not use empty
view pointer equality to infer where a nonempty prefix would start.

Neither storage helper allocates, reserves, checks initialization nor verifies
backing. Before calling, validate signed counts before converting to `usize`,
check required byte multiplication and every pointer adjustment for overflow,
and establish the whole capacity's live storage. The helpers do not return an
overflow/bounds `Result`; arithmetic must not wrap into a smaller valid-looking
region. Alignment, exclusive ownership for eventual release and matching
allocator size remain caller obligations. A checked collection such as
[`alloc::vec`](stdlib-vec.md) establishes these invariants for its own storage.

## Zero-sized values, bounds and lifetime

An empty record and supported zero-word arrays occupy no element bytes. Their
raw stride and `size_of` are zero; different valid indices need not have
different data addresses. Logical count and bounds still apply: a view of
three empty records has three values, while an empty view has none. Reads or
writes outside the logical count trap before any element access. Computing a
zero-sized argument can still have observable effects; zero storage does not
make its expression unevaluated.

The owned-vector fixture exercises nonempty zero-sized storage without an
allocation. Do not call the low-level allocator with size zero and infer a
resource from its result: its separate native contract rejects zero allocation
sizes. Empty/null metadata probes and zero-sized collection storage do not
make arbitrary null, stale or misaligned raw pointers safe for other types.

Views and extracted pointers borrow their backing. Returning a local array's
address or storing a view after the array dies is invalid. Destroying or
relocating an owner invalidates every pointer and descriptor into the old
storage. Shared live aliases observe mutations, so prevent conflicting access;
there is no compiler-enforced lifetime, exclusive-borrow or synchronization
proof supplied by these helpers. Copying a descriptor never extends backing
lifetime, and copying a manual owner never arranges automatic move/drop.

Negative lengths in the checked wrappers and invalid prefix relationships
reach source assertions. The retained native negative-length test observes
SIGILL; ordinary out-of-range slice indexing observes exit 101. An overstated
raw count can pass that logical indexing check and access memory outside its
real allocation: no physical extent has been recovered from the pointer.
Do not treat either trap convention as a general invalid-pointer detector or
as rollback for earlier effects.

## Allocation, evidence and remaining dependencies

Allocation and release belong to `alloc::allocator`, with sole-owner and
matching size/alignment requirements. Its full-width native pointer transport
does not establish layout or lifetime correctness. See
[raw allocator contracts](stdlib-raw-host-width.md). `core::mem` provides no
general C-layout `sizeof`/`alignof`, arbitrary reinterpretation guarantee,
automatic destructor or host binding for a missing intrinsic. A known concrete
type is required before a raw view's stride can be published. Unsupported or
unclosed layouts must not be replaced by null/empty placeholder implementations.

This guide audits existing sources and test assertions; **no fresh GPU or native
run is claimed**. The tests below compile production code and execute x86_64
ELFs on their supported native hosts:

| Existing test/fixture | Evidence represented |
| --- | --- |
| [`stdlib_mem_execution.rs`](../tests/stdlib_mem_execution.rs) | All 11 source-helper call sites; metadata/value assertions; i32 array/slice pointer aliasing; literal byte reads; direct contextual constructor; negative-length SIGILL and past-end exit 101 |
| `core_mem_size_of.lani` in that driver | Exact size/stride assertions above; generic instantiations; packed i32/u8 allocation-backed buffers; record storage guards and capacity-anchored prefix aliases, including empty prefixes |
| `core_mem_generic_slice.lani` in that driver | Packed i32 mutation, descending u32 slots, two-field records at base+24, aliases and zero-length pointer retention |
| [`stdlib_mem_generic_execution.rs`](../tests/stdlib_mem_generic_execution.rs), `mem_generic_values.lani` | Generic scalar/string helper results, unsigned extrema, negative zero and NaN classification, exact string output |
| [`compiler_generic_types_execution.rs`](../tests/compiler_generic_types_execution.rs) | Independent outer array/record copies, borrowed descriptor aliases, compound returns, pointer helpers, zero-sized effects/bounds; ordinary/generic/imported argument capture before later effects |
| `slice_strides_preserve_mixed_backing_across_calls_and_value_copies` and `slice_stride_compositions.lani` | Packed/native i32 backing through the same function, register/stack arguments, returns, Option/record/array descriptor copies and mutation aliases; exact `native`/`packed` output |
| [`codegen_array_slice_fields.rs`](../tests/codegen_array_slice_fields.rs) | Array-to-slice record fields preserve count/stride/aliases; packed and native fields, nested arrays and zero-sized elements; rejection of unrelated nominal/scalar/array-extent types |
| [`codegen_x86.rs`](../tests/codegen_x86.rs), raw-u8-view and memory-intrinsic tests | Individual string bytes, raw bytes over packed i32 memory, byte mutation canaries, native u8 arrays through the same slice operation and nested pointer intrinsic calls |
| [`stdlib_alloc_vec_execution.rs`](../tests/stdlib_alloc_vec_execution.rs), zero-sized storage test | Nonempty zero-sized vector operations and destruction with no mmap/munmap calls; exercises storage-prefix helpers through an owner |

The source-call inventory alone does not prove runtime behavior. The table's
raw string/fixed-array **size** cases do not prove all raw string/fixed-array
storage constructions, every nesting/enum layout, every pointer-extraction
expression, or valid raw FFI with another language. The direct constructor
fixtures do not establish safe negative or oversized intrinsic counts; use the
checked helper and its documented count domain. Invalid storage-prefix branch
assertions follow source guards rather than a separately enumerated native
test matrix in the focused memory driver.

Wasm has separate intrinsic lowering and memory layout; native word widths,
descending storage, allocator behavior and the address table above must not be
projected onto it. Other targets and object/FFI boundaries require their own
layout and execution evidence. Generic and descriptor composition checkpoints
are recorded in [compiler generic types](compiler-generic-types.md) and the
[array-view decision](array-view-storage-decision.md); they are not proof that
every syntactically expressible raw layout is supported.
