# Wasm memory layout

Wasm uses the native value layout that x86_64 uses
(`shaders/native_value_layout.slang`). Layout is decided once. Only the
target's scalar widths differ. The Wasm backend has no private aggregate model.

## Per-target layout

| | x86_64 | wasm32 |
| --- | --- | --- |
| Word | 8 bytes, descending: word k at `addr - 8k` | same |
| Pointer / `usize` / `isize` | 8 bytes | 4 bytes, in the low half of its word |
| `i64` | 8 bytes | 8 bytes (`i64.load`/`i64.store`) |
| Slice / array view | 3 words: data, length, byte stride | same |
| `str` | 2 words: data, length | same |
| Aggregate value | address of word 0 | i32 address of word 0 |

Wasm keeps 8-byte words even though its pointers are 4 bytes. That way:

- `size_of`, field offsets and array strides agree across targets;
- the layout producer (`semantic_lir_layout_word_offset`) and the x86 output
  stay exactly as they were;
- `i64` fields need no second layout.

The strides are the ones in
[array-view-storage-decision.md](array-view-storage-decision.md):

- packed i32 storage: `+4`
- native words: `-8 * element_words`
- byte views (string bytes, `slice_from_raw_parts` over `u8`): `(ptr, len, 1)`

## Linear memory

```
0                     string/data segment
align16(data_len)     shadow stack, 1 MiB (grows down)
stack top             __heap_base: heap / host allocations above
```

- Global 0 is the mutable shadow-stack pointer. It starts at the stack top.
- Global 1 is the immutable `__heap_base`, which equals the stack top. It is
  exported next to `main` and `memory`.
- The initial memory size is `ceil(stack_top / 65536)` pages. It used to be a
  fixed 16384 pages.
- Hosts start allocating at `__heap_base` and grow memory on demand
  (`tests/common/mod.rs`, `tools/run_typical_lanius_matrix.py`).

## Frames

Any row whose value lives in memory owns a frame slot of its layout's words.
That covers:

- an address-taken local or parameter home (the header `ADDRESS` row);
- an aggregate constructor, copy, or call result;
- an argument view.

How slots are placed:

1. `frame_words.slang` writes each scheduled row's word count.
2. One exclusive scan over the schedule numbers every slot.
3. `frame_bounds.slang` records each slot's word 0 and each function's
   `(start, end)` word range.
4. A slot's byte offset from the frame base is `8 * (word - start)`.
5. The frame size is `align16(8 * (end - start))`.

At run time:

- **Prologue** (function's first row): `sp -= frame`. It then fills
  parameter homes. Scalars are stored. A `str` is stored as two words.
  Aggregates and slices are copied with `memory.copy`.
- **Epilogue**: `sp += frame`, before every `return` and after the last row.

Inside the body, `global.get 0` is the frame base. Recursion works because
every activation has its own frame.

## Lowering

LIR rows translate nearly 1:1:

- `PLACE_LOAD` and `PLACE_STORE` become typed loads and stores at the slot or
  pointer.
- `FIELD_ADDRESS` and `INDEX_ADDRESS` are address arithmetic. Indexing is
  bounds-checked against the array or descriptor length (`unreachable` on failure).
- Aggregate copies are `memory.copy`. Zero-filled aggregates are `memory.fill`.
- `[v; n]` stores one element, then doubles the filled range.

Count and scatter replay the same plan (`wasm_plan_rows` in
`codegen/lir/wasm/common.slang`), so the two passes cannot disagree on row
counts.

## Array call ABI

- A `[T]` or `[T; N]` argument to a Lanius call crosses as the address of a
  3-word descriptor.
- A fixed-array value gets a view built in three extra words of its row's
  slot.
- A fixed-array parameter loads the descriptor's data word in the prologue,
  so its body sees the array itself.
- Slice parameters keep the descriptor.
- Host and intrinsic calls take their arguments unchanged.
