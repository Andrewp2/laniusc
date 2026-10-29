# Native endian memory and effect gates

These fixtures complement the primary native-endian contracts and independent
byte model. Their focus is storage admission, exact-bit transport, observable
effects and a bounded large input.

## Explored storage and bounds

`contracts.lani` exercises all 24 additions on three real byte layouts:

- A single owned `alloc::vec::Vec<u8>` allocation of 64 bytes.
- A native fixed byte array with negative element stride.
- Packed bytes starting one byte after an aligned storage base.

Both byte orders use nonzero offsets and exact logical fits. One fixed record
has high-bit unsigned values, negative signed values and signaling NaN payloads;
its bytes are checked against independent big/little-endian literals. Float
payloads also pass through a generic function, a struct and a generic enum,
then are written into separate guarded fields without floating arithmetic.

Seven invalid schedules cover negative length, negative offset, extreme
offset, insufficient remaining bytes, per-type width minus one, empty input
and maximal length/offset. Each calls all 24 APIs on null zero-length backing
and all three real layouts: **672 rejected API calls**. Null backing must not
be accessed; rejected reads preserve the exact fallback, including signaling
NaN bits. Every false write on real backing is followed immediately by a check
of all 64 sentinel bytes. The eight-byte width-minus-one cases detect a partial
first-word write before rejection.

Three `P/p` phases surround these operations. The driver traces every syscall
and rejects any host call inside a phase. Outside them, it admits only launch,
the single byte-backing mapping, explicit markers, its one matching release and
process exit. Repeated logical destruction must not issue a second release.

## Bounded scale

`scale.lani` stores **32,768 records** in one 1,179,650-byte Vec. Every record
selects 34 payload bytes plus two guard bytes, with additional outer guards.
Alternating records use opposite byte orders. Each performs six full-width
writes and six reads: **196,608 writes and 196,608 reads**, over 1,114,112
selected payload bytes. Integer/float bit results and each record's guards are
checked; the host independently checks the emitted operation counts.

The loop uses fixed-size scalar work rather than another input-sized buffer.
Its single traced phase makes no host call, allocation or release; the only
mapping is the existing byte owner, released once afterward. This finite
roundtrip/effect witness complements the independent literal/model checks; it
is not a standalone serializer-correctness or universal memory proof.

## Accepted execution and identities

Both registered tests passed in **7.73 seconds**. Receipt:
`target/stdlib-work/native-endian-memory-first.log`. Instrumented whole-process
durations were 4 ms for contracts and 122 ms for scale; these include process
work and are not kernel-only timings or cross-compiler speed ratios.

The accepted target is native Linux x86_64 executable output from the GPU
compiler. Device execution, other targets and formal verification are unclaimed.
Valid physical backing and its lifetime remain caller obligations.

Accepted SHA-256 identities (driver before later formatting-only changes):

| Source | SHA-256 |
| --- | --- |
| `stdlib/core/endian.lani` | `3f00b73670d1b388bd3a91efd01bd02077f7b116efdd945dd13a8bb4e165cb3a` |
| `contracts.lani` | `c09577f0aac2ba124800db7ca0a0ce94f2cbfb41697dfef42d38178f11108810` |
| `scale.lani` | `fa35e929642dd1699d490fee0ad9e92e24595ea76087c83e1765c6b142ab9856` |
| `tests/stdlib_native_endian_memory_execution.rs` | `4dc00ad4d9ba503566e19ca53fc566d8b24d4c57af75c9d1efe5c398831fb2a0` |

After execution, only trailing blank lines were removed from `contracts.lani`
and `scale.lani`. Their committed hashes are respectively
`3b6700eb0b0afc5484498de53aedbe35596a51b8cb5b42f317ac6ace441583e5` and
`f1e6755271b5239f423ffbf9af8e3024b0bff943b7ae527e5180cea946299963`.

Run this focused target from the repository root under the shared compiler
lock, with a command limit below two minutes:

```sh
timeout --kill-after=2s 100s flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
  env CARGO_TARGET_DIR=target/stdlib-build cargo test \
  --test stdlib_native_endian_memory_execution -- --test-threads=1 --nocapture
```
