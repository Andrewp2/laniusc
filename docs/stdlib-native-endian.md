# Fixed-width native numeric byte order

`core::endian` adds 24 concrete functions for native `u64`, signed integers
and IEEE floating-point values, alongside its existing twelve u16/u32/
represented-WideU64 operations. The module now has 36 public functions. The
[fixed contract](library-native-endian-plan.md) defines this increment.
All five new library tests and four application groups pass on the finite
native Linux x86_64 profile below. This selected increment is accepted.
Earlier endian and float receipts retain their
own API/source scope; the whole library goal remains open.

Here native identifies the primitive numeric type. Each operation explicitly
selects big or little endian independently of host byte order.

## Concrete API family

Each row provides two reads returning the same type and two boolean writes:

| Type | Bytes | Read names | Write names |
| --- | ---: | --- | --- |
| `u64` | 8 | `read_u64_be_or`, `read_u64_le_or` | `write_u64_be`, `write_u64_le` |
| `i16` | 2 | `read_i16_be_or`, `read_i16_le_or` | `write_i16_be`, `write_i16_le` |
| `i32` | 4 | `read_i32_be_or`, `read_i32_le_or` | `write_i32_be`, `write_i32_le` |
| `i64` | 8 | `read_i64_be_or`, `read_i64_le_or` | `write_i64_be`, `write_i64_le` |
| `f32` | 4 | `read_f32_be_or`, `read_f32_le_or` | `write_f32_be`, `write_f32_le` |
| `f64` | 8 | `read_f64_be_or`, `read_f64_le_or` | `write_f64_be`, `write_f64_le` |

For each concrete type T above, the signature pattern is:

```text
read_T_be_or(bytes:[u8],len:i32,offset:i32,fallback:T) -> T
read_T_le_or(bytes:[u8],len:i32,offset:i32,fallback:T) -> T
write_T_be(bytes:[u8],len:i32,offset:i32,value:T) -> bool
write_T_le(bytes:[u8],len:i32,offset:i32,value:T) -> bool
```

These are width-specific functions, not a generic codec trait. One-byte
values need no byte-order distinction. Pointer-sized fields do not define a
fixed wire width and have no added family here. Existing
[u16/u32/WideU64 APIs](stdlib-byte-codecs.md#fixed-width-endian-access) retain
their names and contracts. The represented two-word type remains a separate
explicit representation; it is not needed to work around a missing native
integer implementation.

## Logical bounds and physical backing

`len` is the caller's claimed logical byte-element count. `offset` is a
zero-based element index, not a host pointer displacement. For width W,
admission is exactly:

```text
len >= W && offset >= 0 && offset <= len - W
```

The subtraction-based check avoids overflow in `offset + W`. Complete field
admission precedes reads or writes. Rejected reads return the original
fallback, including its float bits; rejected writes return false without
mutating any element. Valid operations select exactly W elements and retain
the byte slice's actual stride. Field offset alignment is unrestricted.
Successful writes return true after writing the complete field; outside
elements remain unchanged. Reads do not mutate backing or advance a cursor.

The descriptor and logical count do not prove physical backing. Keep storage
live, initialized, correctly typed and sufficient for every selected element.
Overclaims may trap during indexing, including after partial physical writes;
they provide no rollback guarantee. Native arrays and packed raw buffers have
different storage layouts, so retain the supplied slice descriptor rather than
assuming contiguous native bytes. See the
[array/view contract](stdlib-foundation.md).

Fallback is a value convention, not a separate validity bit. A valid numeric
result may equal fallback; NaN comparisons are also unsuitable for detecting
an invalid read. Check the logical predicate independently when status is
needed. No Result or parallel checked-View facade is added by this increment.

## Integer and float representations

Big endian puts the most significant byte first; little endian puts it last.
Signed operations preserve the same-width two's-complement pattern, including
negative values and extrema. They do not saturate or reject a high bit as a
numeric overflow. Native u64 packing composes the existing u32 engines; signed
wrappers reuse their unsigned width. The old represented-width engine remains
unchanged.

Float reads decode the unsigned word and use `core::f32::from_bits` or
`core::f64::from_bits`. Writes use the matching `to_bits`. The path performs
no floating arithmetic or numeric float/integer cast. Its contract preserves
both zero signs, normal/subnormal encodings, infinities and every quiet or
signaling NaN sign/payload bit. Invalid-read fallback must preserve those bits
too. This is an exact encoding contract, without a floating exception or
signaling-trap policy.

The [existing float bit-transfer implementation](stdlib-floats.md#values-and-exact-bits)
uses the target's native float/unsigned word storage contract. Correct value
transport through those calls and returns remains a target dependency; the
new wrappers have their own selected direct native evidence below. Earlier
float tests do not establish these new wrappers or another execution target.

Rust's [u64 byte conversions](https://doc.rust-lang.org/std/primitive.u64.html#method.from_be_bytes)
and [float bit conversion](https://doc.rust-lang.org/std/primitive.f64.html#method.from_bits)
are semantic references. Lanius provides caller-backed bytes and fallback /
boolean outcomes using its own implementation.

## Storage, work and application

Each field operation has fixed width at most eight logical byte elements,
constant auxiliary storage, no heap allocation and no host service. Float
bit transfer uses existing stack scratch. No owner is cloned, retired or
transferred, and byte order is selected explicitly rather than inferred from
the machine. Application input/output allocation and I/O budgets are separate.

The bounded [repack_records program](stdlib-repack-records.md) uses the new
family with existing u32 framing. FROM/TO are `le` or `be`; input is
magic `LNR1`, a u32 record count, then that many 32-byte records:

| Record byte offset | Field |
| ---: | --- |
| 0 | `u64` identifier |
| 8 | `i64` timestamp |
| 16 | `i32` channel |
| 20 | `f32` sample |
| 24 | `f64` reading |

The program limits count to 65,536, validates the whole frame and
EOF before output, then reencodes fields in the requested order. Same-order
conversion is byte identity; opposite-order conversion changes only each
field's order, without NaN canonicalization. Stream calls, argument capture,
output attempts and explicit owners retain their own bounds/failure policy.
All four application groups pass with 96 unique process cases, including the
65,536-record frame. Counts with the u32 high bit set are rejected in both
input orders before narrowing. Input/EOF failures publish no output; a later
output error may leave a confirmed prefix. Application evidence and ownership
remain separate from the allocation-free field algorithms.

## Verification and targets

| Accepted gate | Scope | Receipt under `target/stdlib-work/` |
| --- | --- | --- |
| New native contracts, two tests | All 24 additions; 58 literal base vectors in both orders/byte layouts, plus four separate physical-overclaim exits 101 | `native-endian-contracts-final.log`, 8.33s |
| Independent byte/bit model, one test | 16,032 cases: 10,624 admitted and 5,408 rejected, all 24 additions/both orders/two layouts; seed `0xe0d1a0261030` | `native-endian-model-first.log`, 6.96s |
| Memory and backed scale, two tests | 672 rejected-access calls, three real backing layouts, exact fits/NaN transport and 32,768 records with 196,608 writes + 196,608 reads | `native-endian-memory-first.log`, 7.73s |
| Record-repacking model, one test | 27 cases, all four conversion pairs, exact integer/IEEE bytes and a full 65,536-record frame | `native-endian-repack-model-first.log`, 7.80s; three unrelated application groups filtered |
| Record-repacking boundaries, three tests | CLI23 + rejection30 + I/O16; all four application groups total 96 unique process cases | `native-endian-repack-boundaries.log`, 7.62s; model filtered |
| Selected old endian runtime, one test | Seven existing native fixtures, including packet program and traps | `native-endian-existing-family.log`, 8.48s |
| Selected UTF-16 consumer, one test | Two existing native fixtures | `native-endian-utf16-regression.log`, 5.82s |
| Static public-call inventory, one CPU test | All 36 function names appear across the two executing producers | `native-endian-static-inventory.log`, 0.00s; runtime test filtered; bookkeeping only |

The [direct fixture guide](../tests/fixtures/stdlib_foundation/native_endian/README.md)
records signed extrema/high bits, IEEE corners and exact signaling-NaN
fallback bits. Reads compare against literal input bytes; writes independently
check every byte and surrounding sentinel. Both native negative and packed
positive byte strides execute. The direct contract leaves an empty memory-
service trace. Null-backed logical rejections and backed full-field guards
are distinct from physical-overclaim processes, which carry no rollback
promise.

The [independent model](../tests/fixtures/stdlib_foundation/native_endian_model/README.md)
supplies direct read bytes and an independent write word, then compares
read bits and complete encoded buffers separately. Python never constructs
float values. Both signs of all IEEE categories occur in read, write and
invalid-fallback phases; selected NaN payloads remain exact. This finite
model covers values/bounds/bytes, not absence of arbitrary physical reads.

The [memory fixtures](../tests/fixtures/stdlib_foundation/native_endian_memory/README.md)
apply seven invalid schedules to all 24 APIs over null storage and three
real backing layouts: 672 rejected calls. Every rejected write on real
storage immediately checks all 64 sentinel bytes. Exact-fit/nonzero-offset
fields and signaling-NaN transport through selected generic/struct/enum calls
also execute. Trace-all observation forbids every host call inside the three
contract phases and one scale phase. Each fixture's one backing allocation
has an exact address/size release outside those phases.

The backed workload runs 32,768 records, six writes and six reads per record,
with 1,114,112 selected payload bytes in 1,179,650 owned bytes. It complements
the independent model with a bounded roundtrip/effect workload. The observed
4ms contract and 122ms scale times cover each entire instrumented native
lifecycle, including setup, checks and release; they are not isolated codec
throughput or compiler performance ratios.

The first driver build stopped at a missing mutable Rust borrow before any
native attempt. The accepted run changes only that harness argument; Lanius
production and fixture bodies are unchanged. Static public-call inventory is
separate from runtime evidence. The current old-family and UTF-16 regressions
do not expand their historical receipts to the new API surface.

The [application fixture guide](../tests/fixtures/stdlib_execution/repack_records/README.md)
records independent per-field bytes, IEEE patterns kept as integer words and
four selected reached allocation denials with observed mapping releases.
The output-failure case confirms exactly 1024 converted bytes before a later
write error; required-EOF failures publish nothing. Finite interruption
campaigns check the 8192-call budgets; summary traces do not observe owner
release. These receipts are not an exhaustive allocation-failure or lifetime
proof.

Accepted production SHA-256 identities:

| Source | SHA-256 |
| --- | --- |
| `stdlib/core/endian.lani` | `3f00b73670d1b388bd3a91efd01bd02077f7b116efdd945dd13a8bb4e165cb3a` |
| `sample_programs/library/repack_records.lani` | `6c2106c1e6b7c8e8c0ff0e1717443190798779bd86cda56dab54159c3b6c9355` |

These are executed identities. Only the application's trailing blank line was
removed afterward; its committed hash is
`1e4b7b869b41177385461bb9643a9a7d73c62c46abb21f3a3408db872802646f`.

`core::endian` is allocation-free Lanius with no host-order dependency. The selected
execution target is native Linux x86_64 CPU output from the GPU compiler.
Other targets, GPU device execution, automatic lifetime enforcement and formal
proof remain unclaimed. No compiler, runtime ABI or proof change is part of
this increment.
