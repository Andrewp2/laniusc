# Checked storage layouts

`core::layout` describes byte-storage sizes, alignment and composition using
checked integer arithmetic. It allocates no storage, constructs/dereferences
no pointer and does not infer a Lanius type's native layout. Direct/model tests,
selected arena regressions and the real program pass. This
[increment](library-layout-plan.md) is accepted on the finite profile below.
The full library goal remains open.

## Values and validation

```text
MAX_SIZE: usize = 9223372036854775807
Layout { size: usize, alignment: usize }
ArrayLayout { layout: Layout, stride: usize }
ExtendedLayout { layout: Layout, offset: usize }
Error = InvalidAlignment | SizeOverflow
```

The current profile has 64-bit `usize`/`isize`. Alignment must be a nonzero
power of two. A Layout is valid when rounding its size up to that alignment
does not exceed `MAX_SIZE` (2^63−1). Its stored size need not be aligned.
Zero size is valid even at alignment 2^63; any positive size at that alignment
overflows the permitted rounded extent. A valid huge description does not
promise that backing can be obtained.

Public fields can be forged or mutated, so every operation revalidates its
supplied Layout values. Within one value, invalid alignment precedes size
overflow. `extend` validates the complete left value before the right;
`align_to` validates its input before the requested alignment. Thus a left
size error wins over a right alignment error. Checked padding, addition and
multiplication reject before executing an overflowing expression. Errors
leave inputs unchanged and do not trap, allocate or call the host.

## Eight free functions

All fallible results use `core::result::Result<output, Error>`; `is_valid`
returns bool. There is no duplicate method facade.

| Function | Output and contract |
| --- | --- |
| `from_size_align(size, alignment)` | Validated `Layout`, retaining the unpadded size |
| `validate(layout)` | Revalidated, unchanged `Layout` |
| `is_valid(layout)` | Whether the complete invariant holds |
| `padding_for(offset, alignment)` | Minimum padding to the next alignment multiple; invalid alignment precedes rounded-offset overflow, including offset already above `MAX_SIZE` |
| `pad_to_align(layout)` | `Layout` with trailing padding added, retaining alignment |
| `align_to(layout, alignment)` | `Layout` with the greater alignment and unchanged size; revalidates the result |
| `array(element, count)` | `ArrayLayout`: padded element stride times count, including padding after the last element |
| `extend(left, right)` | `ExtendedLayout`: right offset is left.size rounded to right.alignment; size is offset + right.size, alignment is the maximum, with no implicit final padding |

Offsets, sizes, alignments, strides and counts are `usize`. Array validates
the element even for count zero; the zero-count result retains its alignment
and stride. Zero stride permits every `usize` count. Extend validates the
complete composed result before publication; a representable addition alone
does not establish that the rounded result fits.

For example, an element `{ size: 3, alignment: 4 }` stays size 3 after
validation. Its two-element array has stride 4 and size 8. Extending it with
`{ size: 1, alignment: 2 }` gives offset 4 and size 5 at alignment 4;
calling `pad_to_align` afterward gives size 8. These are explicit byte
descriptions, not native record/array layout predictions.

## Arena and allocator boundary

The [arena](stdlib-arena.md) migration replaces its relative chunk
offset padding calculation with `padding_for`. Its existing 8-aligned payload
base, live-state checks, chunk/capacity limits and typed-storage contract stay
separate. Relative offset padding does not establish an arbitrary base
pointer's alignment.

The native allocator accepts alignments 1, 2, 4 and 8 and rejects zero-size
requests. Arena retains its separate zero-size policy: an aligned dangling
block, no backing access or chunk consumption. Neither allocator gains
over-alignment support from a valid Layout. Native typed storage still uses
the [memory contract](stdlib-memory.md); this increment does not complete
general layout/manual-owner consolidation or migrate protected `std::vec`.

## Evidence and targets

| Accepted scope | Receipt under `target/stdlib-work/` |
| --- | --- |
| All eight APIs, literal boundaries/precedence, trace permits only process entry/exit | One test/4.68s, `layout-direct-first.log` |
| Independent arbitrary-precision model: 18,878 cases, all eight APIs, direct/mutated inputs | One test/5.46s, `layout-model-first.log` |
| Selected arena alignment/stability/errors, typed storage and zero/empty requests | Three tests/11.98s, four filtered, `layout-arena-regressions.log` |
| [Record-storage program](stdlib-layout-records.md), model20/CLI28/I/O10 cases | Three tests/7.32s, `layout-records-first.log` |

The program's 58 cases include actual byte readback through 65,536 records,
three reached allocation denials with matched releases, arena release before
stdout and actual closed-pipe/output failures. The
[library model](../tests/fixtures/stdlib_foundation/layout_model/README.md)
uses seed `0x1a90a0261031`, checking values, errors and operand preservation.
Earlier arena receipts retain their scope; no whole arena-suite rerun is
implied. Production is layout `d6e30272…`
and arena `3e6f7b3a…`; [direct fixtures](../tests/fixtures/stdlib_foundation/layout/README.md)
own exact source identities. The admitted target is native Linux x86_64 CPU
output from the GPU compiler. Other pointer widths, direct GPU execution and
formal proofs are unverified. No compiler dependency, ABI or native service
is introduced; allocator over-alignment, lifetimes and native layout inference
remain separate work.

The invariant and composition design refer to the official
[Rust Layout contract](https://doc.rust-lang.org/alloc/alloc/struct.Layout.html).
Lanius explicitly revalidates public fields and rounded offsets. Its array
contract always includes trailing stride padding; the contract above defines
that choice independently of Rust's repeat variants.
