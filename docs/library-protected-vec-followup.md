# Protected vector heap-index follow-up

This is a **static finding**, recorded against baseline
`7aae094fa580ebc77401feb76d582fb8d04bb0c6`. There is no executable reproduction,
runtime acceptance receipt or repair. Protected vector code, compiler code and
proofs are unchanged. This follow-up is separate from stable `alloc::slice`
sorting.

## Capacity and reachable arithmetic

[`std::vec` caps storage at 2147483647 bytes](../stdlib/std/vec.lani#L25),
and its [element-capacity calculation](../stdlib/std/vec.lani#L47) divides that
cap by `size_of<T>()`. On the recorded target,
[`size_of<u8>()` is one byte](../stdlib/core/mem.lani#L60). Thus owner capacity
does not exclude this initialized, lawful-`u8` input, assuming allocation
succeeds:

```text
count = 1073741825 = 2^30 + 1
every item is 0 except items[1073741824] = 1
```

The public [`try_resize`](../stdlib/std/vec.lani#L289) and
[`try_set`](../stdlib/std/vec.lani#L209) can establish that state without forged
length, capacity or backing. The input requires slightly more than 1 GiB;
no such allocation was attempted for this review.

The [first heap-construction call](../stdlib/std/vec.lani#L419) passes
`root = count/2 - 1 = 536870911` to
[`sift_down`](../stdlib/std/vec.lani#L398):

1. Its left child is `1073741823`; the right child is `1073741824`.
2. Their values are 0 and 1, so the lawful unsigned comparison selects the
   right child. The parent is 0, so the swap occurs.
3. [`parent = child`](../stdlib/std/vec.lani#L411) makes `parent = 1073741824`.
4. The [next loop guard](../stdlib/std/vec.lani#L400) forms
   `parent*2+1 = 2147483649`, exceeding `i32::MAX` before it can determine
   that the parent is a leaf.

The recorded [integer semantic reference](../crates/laniusc-compiler/src/codegen/lowering_ir.rs#L11237)
uses wrapping addition/multiplication. The
[x86 binary32 emitter](../shaders/codegen/lir/x86/encoding.slang#L220) emits
32-bit operations. Under those semantics the guard expression becomes
`-2147483647`, which compares less than the positive count; following that
source path would then attempt a negative child index. This is a source-based
prediction, not an observed native trap or a compiler root-cause diagnosis.

For nonzero element sizes of at least two bytes, the byte-capacity bound keeps
all valid indices below the multiplication threshold. Zero-sized `Unit` is
**not** a substitute witness: its lawful equality-only total order cannot
trigger the strict comparison and swap needed to reach the high leaf. The
`u8` witness uses neither an inconsistent comparator nor invalid ownership.

## Narrow next step

Coordinate a small arithmetic/control reduction and the protected vector's
specification obligations before any repair. A child-existence guard evaluated
before doubling is the candidate to assess; this note supplies no repair.
Avoid a huge allocation-based test merely to exercise the arithmetic.

## Recorded source identities

These SHA-256 identities fix the line-linked review scope:

| Source | SHA-256 |
| --- | --- |
| `stdlib/std/vec.lani` | `47ae5b83ff36e9c04dca819ff5bc881be58b32c3c5526b7d0e42b3ab382829fa` |
| `stdlib/core/mem.lani` | `b77a16ddc79cf9f9a1e10a45d1c9f0282addec24af8634f88f835a8877d678b3` |
| `crates/laniusc-compiler/src/codegen/lowering_ir.rs` | `b3d567ec792a16b68f6fc53368336bb3e03638b5daa1ed06f5b2d11273942f3e` |
| `shaders/codegen/lir/x86/encoding.slang` | `2ef287820a423e6fc3bb7e8c55073a953d7388171931a339d1645d4a2244c1f6` |
