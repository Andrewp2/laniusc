# Standard library execution audit and portable foundation

This audit distinguishes runtime evidence from source that merely type-checks.
`laniusc check` exercises the GPU-resident frontend but does not establish that
the target backend can emit or execute a helper. The executable claim below is
limited to native x86_64 output from this worktree.

## Public API inventory

| Public surface | Classification | Evidence and limit |
| --- | --- | --- |
| `core::number_i8` constants and all 26 public functions | Executable on x86_64 | Focused runtime fixture checks signed 8-bit limits, widened arithmetic, wrapping and saturation, multiplication and power overflow, GCD/LCM, division and Euclidean remainder, zero-divisor and `MIN/-1` fallbacks, parity, signs, and power-of-two boundaries. |
| `core::number_i16` constants and all 26 public functions | Executable on x86_64 | Focused runtime fixture checks signed 16-bit limits, widened arithmetic, wrapping and saturation, multiplication and power overflow, GCD/LCM, division and Euclidean remainder, zero-divisor and `MIN/-1` fallbacks, parity, signs, and power-of-two boundaries. |
| `core::number_u16` constants and all 25 public functions | Executable on x86_64 | Focused runtime fixture checks unsigned 16-bit limits, widened saturation and wrapping, multiplication and power overflow, GCD/LCM, zero-divisor fallbacks, parity, and power-of-two and alignment boundaries. |
| `core::number_i32` constants and all 26 public functions | Executable on x86_64 | Focused runtime fixture checks ordinary values, integer extremes, wrapping arithmetic, multiplication and power overflow, signed GCD/LCM, truncating and Euclidean division, failure fallbacks, and power-of-two overflow. |
| `core::number_u32` constants and all 25 public functions | Executable on x86_64 | Runtime fixture checks unsigned extremes, wrapping and saturating arithmetic, GCD/LCM, power overflow, zero-divisor fallbacks, and alignment fallbacks. |
| `core::wide_u64` all 24 public two-word and decimal functions | Executable on x86_64 | The imported runtime fixture calls every function and checks high-bit construction, ordering, wrapping add/subtract/multiply, bitwise operations, shifts across word boundaries, division and remainder, zero-divisor fallbacks, full-width decimal digits and parsing, malformed input, and overflow. A generated native fixture compares arithmetic and shifts against Rust `u64` across eight operand pairs and four values at eight shift counts. The decimal-double program reads and prints full-width values. The representation is two `u32` words; this does not claim native `u64` correctness. |
| `core::wide_i64` all 29 public two-word and decimal functions | Executable on x86_64 | The imported runtime fixture calls every function and checks sign extension, signed bounds, ordering, wrapping and saturating arithmetic, bitwise operations, arithmetic right shifts, signed quotient and remainder, zero-divisor and `MIN/-1` fallbacks, and full-width signed decimal parsing and output. A generated native fixture compares arithmetic and shifts against Rust `i64` across eight operand pairs and four values at eight shift counts. A decimal-double program exercises real input and output, including signed extrema and failure cases. It uses `core::wide_u64` internally and does not claim native `i64` correctness. |
| `core::wide_u64_checked` all 9 public functions and `core::wide_i64_checked` all 11 public functions | Executable on x86_64 | Imported fixtures call every checked and saturating operation with ordinary values, zero, high-bit values, signed extrema, overflow, zero divisors, and `MIN / -1`. Generated native fixtures compare checked arithmetic, powers, and saturation with Rust `u64` and `i64` across eight operand pairs and boundary exponents. The checked-factorial program prints `20!` and rejects `21!` overflow through `OptionWideU64`. These modules use explicit two-word arithmetic, not native 64-bit operators. |
| `core::byte` constants and all 44 public functions | Executable on x86_64 | Focused runtime fixture checks arithmetic overflow, every wrapping-multiplication byte pair, division, GCD/LCM, power overflow, zero divisor, power-of-two overflow, all nibble round trips, ASCII classes, case conversion, and hex conversion fallbacks. |
| `core::bits` all 42 public `i32`, `u32`, `u16`, and `u8` functions | Executable on x86_64 | Runtime fixture checks zero, highest bit, all bits, counts, rotates across word widths, bit reversal, byte swap, endian packing and extraction for every byte value, and out-of-range bit and byte fallbacks. Byte operations run all 256 inputs; halfword operations run boundary values and 256 evenly spaced inputs; signed operations check negative patterns and all 32 one-hot bits. |
| `core::wide_u64_bits` all 12 public two-word bit functions | Executable on x86_64 | The imported runtime fixture calls every function and checks zero, one, high bit, maximum, and mixed byte patterns; zero and one counts; rotations at word and width boundaries and for all counts 0 through 127; bit reversal and byte swap; all eight byte positions in both orders; and caller fallbacks for invalid positions. It uses `WideU64` rather than native `u64`. |
| `core::wide_i64_bits` all 12 public signed two-word bit functions | Executable on x86_64 | The imported runtime fixture calls every function on zero, one, negative one, the signed minimum, and a mixed negative pattern. It checks counts, sign-bit rotations and reversal, byte swapping, bit and byte fallbacks, and rotation round trips for all counts 0 through 127. The signed-bit-report program reads full-width decimal input and prints the population count and unsigned reversal for ordinary, extreme, malformed, and overflowing inputs. The functions operate on `WideI64` bit patterns and do not use native `i64` operations. |
| `core::bitset` all 14 public caller-backed bitset functions | Executable on x86_64 for `[u32]` backing | Runtime fixtures check word counts, bit access and mutation, fill, counts, any/all, first/last set bit, equality, union, and intersection. They cover logical lengths 0 through 65, word boundaries, aliases, invalid lengths and indices, preserved padding and unused words, and a physical backing overclaim that traps. A source scan requires a runtime call for every public function. |
| `core::base64` all 4 public caller-backed encoding functions | Executable on x86_64 for `[u8]` backing | Runtime fixtures check exact size calculation, standard padded Base64 encoding and strict decoding, empty input, all 256 values as the final byte of one-, two-, and three-byte round trips, one- and two-byte padding, same-buffer encode/decode, rejected malformed input and insufficient capacity without output changes, and overstated physical views that trap. A source scan requires a runtime call for every public function. |
| `core::endian` all 12 public caller-backed byte-order functions | Executable on x86_64 for `[u8]` backing | Runtime fixtures check big- and little-endian 16-, 32-, and two-word 64-bit reads and writes, high-bit values, zero, maximum values, invalid logical bounds without writes, and physical backing overclaims that trap. The 16- and 32-bit matrix covers all 256 high-byte values across offsets 0 through 4. The packet-header sample combines byte-order reads with unsigned arithmetic and checks its printed result. A source scan requires a runtime call for every public function. |
| `core::varint` and `core::varint_wide_u64`, all 12 public functions and five status constants | Executable on x86_64 for caller-backed `[u8]` views | Runtime fixtures call every function, check canonical unsigned LEB128 at 32 and two-word 64 bits, round-trip all 256 first-byte values and wide boundary values, distinguish invalid bounds, truncation, overflow, and nonminimal encodings, reject short write capacity without changing storage, and confirm native traps on physical backing overclaims. The frame-sum program uses both codecs and full-width decimal output. No native `u64` behavior is claimed. |
| `core::varint_i32` and `core::varint_wide_i64`, all 12 public functions | Executable on x86_64 for caller-backed `[u8]` views | Runtime fixtures call every ZigZag transform, length, write, read, and value accessor. They check `i32` and two-word signed extrema, negative and positive boundaries, all signed values from -128 through 127, no-write capacity rejection, read error fallbacks, and a signed frame program that prints a full-width negative sum. Reads reuse the corresponding unsigned result statuses and next offsets. No native `i64` behavior is claimed. |
| `core::bool` all 10 public functions | Executable on x86_64 | Focused runtime fixture checks both truth values, conversion, and both selection branches. |
| `core::char` all 16 public functions | Executable on x86_64 | Focused runtime fixture checks ASCII classes, all 26 case pairs, case-insensitive comparison, control and printable boundaries, and unchanged non-ASCII values. |
| `core::utf8` all 25 public codec and backed-view functions | Executable on x86_64 | Native fixtures check ASCII and multibyte encoding/decoding, checked scalar append, scalar counts and lookup, first and last scalar and sequence search, byte/scalar boundary mapping, equality, prefix and suffix matching, lexicographic comparison, empty and truncated views, out-of-byte-range integer codes, malformed sequences, surrogate exclusion, and Unicode maximum. Direct caller-backed `[u8]` helpers validate and count scalars, map scalar and byte boundaries, and read scalars by index across one- through four-byte sequences. They reject malformed input and negative lengths, and native indexing traps on a physical length overclaim. The older general view functions use caller-backed `[i32]` byte codes and do not access string storage. |
| `core::utf8_view` all 12 public byte-view functions | Executable on x86_64 for caller-backed `[u8]` views | Focused native fixtures check complete-view validation, equality, prefix and suffix matches, lexicographic ordering, first and last byte-sequence offsets, first and last Unicode scalar indices, and checked append, insertion, removal, and replacement of Unicode scalars in caller-owned bytes. They cover ASCII and two-, three-, and four-byte encodings, repeated matches, empty views and needles, malformed data, invalid scalars, negative lengths, missing matches, growth and shrinkage, exact-fit and insufficient capacity, and unchanged storage after rejected edits. Separate fixtures confirm physical length and capacity overclaims trap. The source scan requires a runtime call for every public function. |
| `core::decimal` all 20 public functions | Executable on x86_64 | Runtime fixture checks decimal length and every ASCII byte of extrema across 8-, 16-, and 32-bit integers, ordinary values, sign placement, zero, out-of-range fallbacks, incremental and complete ASCII parsing for all six widths, and overflow against each width's limits. `std::io_decimal` and both bounded decimal file readers use the portable scalar helpers. |
| `core::hex` all 14 public functions | Executable on x86_64 | Runtime fixture checks shortest lowercase and uppercase hexadecimal representations of `u8`, `u16`, and `u32`, zero and maximum values, invalid-index fallbacks, mixed-case digit accumulation, complete prefixed and unprefixed parsing, and overflow against each width's limit. The helpers allocate no storage and use no host calls. |
| `core::hex_wide_u64` all 7 public two-word functions | Executable on x86_64 | Runtime fixtures call every function and check shortest lowercase and uppercase hexadecimal bytes for zero, the word boundary, a mixed full-width pattern, and the maximum; invalid-index fallbacks; bounded digit appends and overflow; optional prefixes, mixed case, leading zeros, malformed input, and full-width parse overflow. An overstated physical input view traps. The module uses `WideU64`, not native `u64`. |
| `core::binary` all 11 public functions | Executable on x86_64 | Runtime fixture checks shortest unsigned binary representations across `u8`, `u16`, and `u32`, zero and high-bit values, invalid-index fallbacks, bounded digit accumulation, optional prefixes, malformed and overflowing input, and format/parse round trips for all 256 byte values. The helpers allocate no storage and use no host calls. |
| `core::binary_wide_u64` all 6 public two-word functions | Executable on x86_64 | Runtime fixtures call every function and check zero, the 32-bit word boundary, a sparse high-bit pattern, and the maximum; every digit of a full-width pattern; invalid-index fallbacks; bounded appends and overflow; optional prefixes, leading zeros, malformed input, and full-width parse overflow. An overstated physical input view traps. The module uses `WideU64`, not native `u64`. |
| `core::f32` both public constants and all 17 public functions | Executable on x86_64 for tested finite, infinite, and NaN inputs | Runtime fixtures check `ZERO` and imported `ONE`, classification, sign, comparison, valid and reversed clamp bounds, fallback behavior, and square root for zero, negative, small, ordinary, large, infinite, and NaN inputs. Direct and materialized NaN comparisons follow unordered semantics. |
| `core::array_i32_4` all 14 public functions | Executable on x86_64 | Runtime fixture checks access, search, fallback indices, extrema, saturating sum, and caller-backed copy, fill, and reverse. Invalid destination lengths return false without writing; reverse supports shared source/destination backing. Fixed-array-returning predecessors were removed because they misexecute; see dependency 7. |
| `core::array_u8_4` all 17 public functions | Executable on x86_64 | Runtime fixtures check access, search, extrema, full-range sum, equality, endian conversion, invalid-index fallback, and caller-backed copy, fill, and reverse of four-byte arrays. Reversal works with shared source and destination backing. Short destination lengths return false without writing; an overstated backing view traps on native indexing. |
| Legacy `stdlib/bool.lani` all 9 public functions and `stdlib/i32.lani` all 16 public functions | Executable on x86_64 when included as source | A source-level native fixture checks both boolean values, both selection branches, ordinary and boundary signed arithmetic, wrapping overflow, comparisons, clamp bounds, and power-of-two overflow. The test calls every public function in both files. `abs` requires input above `i32::MIN`; `clamp` requires ordered bounds. |
| Legacy `stdlib/array_i32_4.lani` all 14 public functions | Executable on x86_64 when included as source | A source-level native fixture checks length, access, search, fallback indices, extrema, a representable sum, and caller-backed copy, fill, and reverse. Fixed-array-returning predecessors were removed; see dependency 7. |
| `core::range` free functions for all five i32 and u32 range forms, and methods for `Range`, `RangeInclusive`, `RangeFrom`, and `RangeTo` specialized to i32 or u32 | Executable on x86_64 | Runtime fixtures check endpoints, empty/reversed ranges, touching and overlapping intervals, unbounded membership, and full-range membership, including values across the u32 high bit. The imported u32 method reproducer also checks that same-name i32 and u32 methods select the correct body. There is no `RangeFull` method claim. |
| `core::wide_u64_range` all 19 public free functions and 14 receiver methods | Executable on x86_64 | The imported runtime fixture calls every function and method for half-open, inclusive, from, and to ranges. It checks endpoints and membership across the two-word boundary and unsigned high bit, equal and reversed bounds, touching and overlapping intervals, and zero and maximum values. `full_contains` covers the unbounded full domain as a scalar predicate. Range values store four or two flat `u32` words; imported nested wide aggregates and `RangeFull` forwarding remain compiler dependencies. |
| `core::wide_i64_range` all 19 public free functions and 14 receiver methods | Executable on x86_64 | The imported runtime fixture calls every function and method for half-open, inclusive, from, and to ranges. It checks signed minimum and maximum, negative values in the same high word, the negative-to-zero boundary, equal and reversed bounds, touching and overlapping intervals, and full-domain membership. Range values store flat `u32` endpoint words and compare them in signed two's-complement order; no native `i64` behavior is claimed. |
| `core::range_u8` all 27 public scalar and concrete aggregate functions | Executable on x86_64 | Runtime fixtures call every public function and check half-open, inclusive, from, to, and full byte ranges, including reversed and equal bounds, touching intervals, and the byte maximum. The aggregate forms use `RangeU8`, `RangeInclusiveU8`, `RangeFromU8`, and `RangeToU8`. |
| `core::range_i8` all 27 public scalar and concrete aggregate functions | Executable on x86_64 | Runtime fixtures call every public function and check signed half-open, inclusive, from, to, and full ranges, including negative bounds, `-128`, `127`, touching intervals, and empty or reversed bounds. |
| `core::range_u16` all 27 public scalar and concrete aggregate functions | Executable on x86_64 | Runtime fixtures call every public function and check half-open, inclusive, from, to, and full ranges, including equal or reversed bounds, touching intervals, and the `65535` endpoint. |
| `core::range_i16` all 27 public scalar and concrete aggregate functions | Executable on x86_64 | Runtime fixtures call every public function and check signed half-open, inclusive, from, to, and full ranges, including negative bounds, `-32768`, `32767`, touching intervals, and empty or reversed bounds. |
| `core::range_char` all 27 public scalar and concrete aggregate functions | Executable on x86_64 | A runtime fixture calls every public function and checks half-open, inclusive, from, to, and full character ranges. It uses ASCII and two-, three-, and four-byte Unicode literals to check scalar ordering, equal and reversed bounds, touching intervals, endpoint inclusion, and aggregate forwarding. |
| `core::range_f32` all 27 public scalar and concrete aggregate functions | Executable on x86_64 | A runtime fixture calls every public function and checks finite values, signed zero, both infinities, and NaN. NaN bounds make bounded ranges empty; ordered ranges reject NaN values, while the full-range predicate accepts every `f32`. It checks endpoint inclusion, equal and reversed bounds, touching intervals, and aggregate forwarding. |
| `core::slice` all 37 public i32 view functions | Executable on x86_64 for valid backed views | Runtime fixtures check backed, empty, unsorted, duplicate, and sorted views; sequence comparisons, first and last contiguous subsequence matches, rotations, compaction, checked insertion and append within caller-owned capacity, partition boundaries and preserved contents, first and last binary matches, sorted insertion boundaries, extrema, sum, overlapping and nonoverlapping copies, sorting, and fallback behavior. Sorting also runs all 243 five-element arrays over `{-1, 0, 1}` against independently counted expected groups. Separate fixtures confirm native index trapping on overclaimed physical lengths. |
| `core::slice_u8` all 36 public byte-view functions | Executable on x86_64 for fixed-array-backed views | Runtime fixtures exercise access, swaps, fill, rotation, overlap-safe and nonoverlapping copies, compaction, insertion, sequence comparison and search, unsigned ordering, heapsort, binary search, partitioning, and saturating sum. They cover empty and invalid logical lengths, rejected mutation, zero, and 255. Sorting also runs every five-element sequence over `{0,1,2}` against independently counted groups. A source scan requires a runtime call for every public function. Byte views over string or raw pointer storage remain outside this claim. |
| `core::slice_i8` all 36 public signed-byte-view functions | Executable on x86_64 for fixed-array-backed views | Runtime fixtures call every public function and cover search, mutation, copy, rotation, compaction, insertion, signed ordering, sorting, binary search, partitioning, and left-to-right saturating sum. Cases include `-128`, `127`, empty and invalid logical lengths, every five-element sequence over `{-1,0,1}`, and a native trap on physical length overclaim. |
| `core::slice_i16` all 36 public signed-halfword-view functions | Executable on x86_64 for fixed-array-backed views | Matching fixtures cover every public function, `-32768`, `32767`, signed ordering and binary search, sums clamped after each addition, all 243 small sorting sequences, invalid logical lengths, and a native trap on physical length overclaim. |
| `core::slice_u16` all 36 public unsigned-halfword-view functions | Executable on x86_64 for fixed-array-backed views | Runtime fixtures call every public function and check access, mutation, copy and rotation, compaction, insertion, sequence search, unsigned ordering across `32768`, sort and binary search, partitioning, and sums saturating at `65535`. They cover empty and invalid logical lengths, rejected mutation, and all 243 five-element sequences over `{0,1,2}` for sorting. A separate fixture confirms exit 101 when the claimed length exceeds the physical backing and is indexed. |
| `core::slice_u32` all 36 public unsigned-word-view functions | Executable on x86_64 for fixed-array-backed views | Matching runtime fixtures cover the same operations and failure cases, including unsigned ordering across `2^31` and saturation at `u32::MAX`, plus the exhaustive small-sort fixture. The caller supplies a logical length within the physical backing. A source scan requires a runtime call for every public function. |
| `core::slice_bool` all 35 public boolean-view functions | Executable on x86_64 for fixed-array-backed views | Runtime fixtures call every function and check reads, writes, fill, swap, overlapping and disjoint-range copies, rotation, compaction, insertion and removal, prefix, suffix, and subsequence search, false-before-true comparison, binary bounds and search, partitioning, true counts, `any` and `all`, empty and invalid lengths, and an overclaimed physical length that traps. Sorting and binary search check all 32 five-element Boolean sequences. The boolean checksum sample uses it with numeric and Option helpers. Generic `[T]` operations are withheld because signed element instantiations misexecute; see dependency 41. |
| `core::slice_char` all 35 public character-view functions | Executable on x86_64 for fixed-array-backed views | Runtime fixtures call every function and check access, mutation, overlap-safe and disjoint-range copying, rotation, compaction, insertion, extrema, partitioning, prefix and subsequence matching, equality, Unicode scalar ordering, sorting, bounds, binary search, empty and invalid lengths, and non-ASCII values. They assert the scalar values of two-, three-, and four-byte UTF-8 character literals, including two literals with the same leading byte. Sorting checks all 243 five-element sequences over `{'a', 'z', 'é'}`. An overclaimed physical length traps. The character inventory sample combines it with `core::char`, `core::range`, `core::range_char`, and `core::number_i32`. |
| `core::slice_f32` all 36 public floating-view functions | Executable on x86_64 for fixed-array-backed views | Runtime fixtures call every function and check finite, infinite, and NaN values, IEEE equality and signed zero, left-to-right sums, overlap-safe and disjoint-range copying, rotation, compaction, insertion, prefix and subsequence matching, finite extrema and lexicographic comparison, checked partitioning, invalid bounds, and native trapping on an overclaimed physical length. Finite-only heapsort, extrema, and partitioning check all 243 five-element sequences over `{-1, 0, 1}`; binary bounds and searches cover duplicates, missing values, signed zero, and invalid input. The floating window sample combines it with `core::f32`, `core::range_f32`, and `OptionF32`. |
| `core::mem::{i32_array_data_ptr,i32_slice_data_ptr,string_data_ptr,i32_slice_from_raw_parts}` | Compiler-provided intrinsics; executable on x86_64 for tested backing storage | The source has no null or empty placeholder bodies. A native fixture checks array and slice pointers, view mutation, and a string literal's first byte; existing native tests check bounds trapping. Byte-slice access to string storage remains broken; see dependency 16. |
| `core::mem::{identity,first,second,select}` | Executable on x86_64 for i32 instantiations | Runtime fixture exercises each generic helper and both selector branches, plus `identity<bool>`. Aggregate instantiations are outside this claim. |
| `core::mem` capability metadata, all 10 public functions | Executable on x86_64 Linux | The native metadata fixture calls every function and checks runtime-free value helpers and the unavailable raw-memory host API against `core::runtime`. The unavailable host API is distinct from the four executable compiler-provided intrinsics above. `tests/stdlib_mem_execution.rs` requires a runtime call for all 18 public functions across the metadata and value fixtures. |
| `core::hash` twelve public free functions and two FNV-1a constants | Executable on x86_64 | The runtime fixture checks stable 32-bit bit-pattern hashes for six integer widths, both Boolean values, and ASCII and Unicode characters. The i32, u32, bool, and char functions call local `Hash<T>` implementations; narrow integers widen explicitly. `hash_wide_u64` and `hash_wide_i64` apply FNV-1a to eight little-endian bytes of the two-word representation and check zero, high-bit, maximum, and signed boundary values against exact outputs. The byte extraction masks before narrowing because direct unsigned casts misexecute (dependency 33). The fixture also checks both constants, a one-byte step, known byte-sequence hashes, empty input, binary bytes, and a negative-length fallback. A separate native fixture confirms that overstating the physical byte view traps. The stdin fingerprint sample combines hashing with byte input and hexadecimal output. Direct imported `Hash<T>` calls remain outside the claim. |
| `core::crc32` all 3 public functions and 3 constants | Executable on x86_64 for caller-backed `[u8]` views | The native fixtures check CRC-32/ISO-HDLC on `123456789`, empty input, a one-byte prefix, binary bytes, and every byte value through the streaming interface. Negative logical lengths return the fallback without reading storage; an overstated physical view traps. A source scan requires a runtime call for every public function. |
| `core::option_i32` all 12 public functions and `core::result_i32` all 10 public functions | Executable on x86_64 | `tests/fixtures/stdlib_foundation/option_result_i32.lani` executes constructors, both presence/error states, payload and error predicates, fallbacks, both branches of `or`, `and`, and `xor`, and conversions between the two concrete types. Zero values and negative/extreme payloads distinguish an absent value or error from its stored number. A source scan requires every public function to have a runtime call. Local aggregate forwarding is covered by the executable return suite; see dependency 39. |
| `core::option_u32` all 12 public functions and `core::result_u32` all 10 public functions | Executable on x86_64 | The matching runtime fixture covers every function and both variants with zero, ordinary values, the high bit, and `u32::MAX`. Both the success payload and error code are `u32`; inactive fields are zero. A source scan requires every public function to have a runtime call. See dependency 39 for local return coverage. |
| `core::option_u8` all 12 public functions and `core::result_u8` all 10 public functions | Executable on x86_64 | The byte fixture executes every function with `None`, `Some`, `Ok`, and `Err`, including zero, 128, and 255 payloads. A source scan requires every public function to have a runtime call. See dependency 39 for local return coverage. |
| `core::option_bool` all 12 public functions and `core::result_bool` all 10 public functions | Executable on x86_64 | The runtime fixture calls every function with both boolean values and all presence and success states. It distinguishes `Some(false)`, `Ok(false)`, and `Err(false)` from absence or the opposite variant, and checks conversions, fallbacks, `or`, `and`, and `xor`. A source scan requires a runtime call for every public function. Local aggregate forwarding is covered by the executable return suite; see dependency 39. |
| `core::option_char` all 12 public functions and `core::result_char` all 10 public functions | Executable on x86_64 | The runtime fixture calls every function with both variants, NUL payloads, two distinct characters sharing a UTF-8 leading byte, and two-, three-, and four-byte Unicode scalars. It checks presence and error predicates, fallbacks, `or`, `and`, `xor`, and both conversion directions. Inactive payloads are NUL and must not be read without checking the tag. A source scan requires a runtime call for every public function. |
| `core::option_f32` all 12 public functions and `core::result_f32` all 10 public functions | Executable on x86_64 | The runtime fixture calls every function with ordinary finite values, zero, negative values, and NaN payloads. It checks both variants, conversions, fallbacks, `or`, `and`, `xor`, and IEEE unordered equality for NaN. A source scan requires a runtime call for every public function. Local aggregate forwarding is covered by the executable return suite; see dependency 39. |
| `core::option_i8` all 12 public functions and `core::result_i8` all 10 public functions | Executable on x86_64 | The signed byte fixture executes every function with both variants, zero, `-128`, and `127`, including Option to Result and Result to Option conversions. A source scan requires every public function to have a runtime call. See dependency 39 for local return coverage. |
| `core::option_i16` all 12 public functions and `core::result_i16` all 10 public functions | Executable on x86_64 | The signed halfword fixture executes every function with both variants, zero, `-32768`, and `32767`, including conversions. A source scan requires every public function to have a runtime call. See dependency 39 for local return coverage. |
| `core::option_u16` all 12 public functions and `core::result_u16` all 10 public functions | Executable on x86_64 | The unsigned halfword fixture executes every function with both variants, zero, `32768`, and `65535`, including conversions. A source scan requires every public function to have a runtime call. See dependency 39 for local return coverage. |
| `core::option_wide_u64` and `core::option_wide_i64` all 12 public functions each; `core::result_wide_u64` and `core::result_wide_i64` all 10 public functions each | Executable on x86_64 | Imported runtime fixtures call every function and check both variants, zero, signed or unsigned high-bit values, wide extrema, negative and zero i32 error codes, fallbacks, `or`, `and`, `xor`, and conversions between concrete Option and Result types. Each representation uses a tag and two 32-bit words; an Err stores its i32 code in the low word. These modules do not claim native `i64` or `u64` correctness. |
| `core::i8` all 28 public functions and 4 constants | Executable on x86_64 | The imported module fixture calls every function and reads every constant. It checks signed byte limits, wrapping and saturating overflow, checked results through `OptionI8`, ordinary comparisons and predicates, reversed bounds, and power-of-two overflow. |
| `core::i16` all 28 public functions and 4 constants | Executable on x86_64 | The imported module fixture calls every function and reads every constant. It checks `MIN` and `MAX`, ordinary and overflowing arithmetic, checked results through `OptionI16`, signed predicates, reversed bounds, comparison, and power-of-two overflow. |
| `core::i32` all 28 public functions and 4 constants | Executable on x86_64 | The imported module fixture checks each function's ordinary result and selected edge cases: `MIN` absolute value, checked and saturating overflow, wrapping arithmetic, signed predicates, range boundaries, and power-of-two overflow. Checked results use concrete `OptionI32`. |
| `core::u8` all 37 public functions and 4 constants | Executable on x86_64 | The imported module fixture checks every function, overflow and zero-divisor behavior, wrapping multiplication, ASCII classes and case conversion, and checked results through `OptionU8`. Its multiplication delegates to the tested `core::byte` implementation. |
| `core::u16` all 25 public functions and 4 constants | Executable on x86_64 | The imported module fixture calls every function and reads every constant. It checks ordinary and high-bit values, wrapping and saturating overflow, checked arithmetic through `OptionU16`, reversed bounds, zero divisors, power-of-two overflow, and invalid or overflowing alignment. |
| `core::u32` all 25 public functions and 4 constants | Executable on x86_64 | The imported module fixture checks every function, unsigned high-bit and maximum values, checked and wrapping arithmetic, alignment failures, and power-of-two overflow. Checked results use concrete `OptionU32`. |
| `core::ordering` all 20 public functions and `Ordering` variants | Executable on x86_64 | `tests/stdlib_ordering.rs` and `tests/stdlib_ordering_wide.rs` execute every function and direct qualified and unqualified `Less`, `Equal`, and `Greater` values through the real stdlib root. They cover predicates, reverse, then, all six scalar integer widths, Boolean false-before-true order, Unicode scalar order, unsigned high-bit comparison, and full-width signed and unsigned ordering through the two-word `WideI64` and `WideU64` types. `compare_f32_or` checks finite values, signed zero, infinities, and caller-supplied fallbacks for NaN. The broken primitive `compare_i64` was removed until native i64 literal and comparison lowering works (dependency 11). |
| Generic `core::option`, `core::result`, and `core::i64` as complete imported modules | Contract-only for native execution | Generic enum values fail GPU lowering and native 64-bit comparison/arithmetic are incomplete. Even a direct `core::i64::min(2, 3)` call cannot emit x86 code because importing `core::i64` pulls in generic Option/Result. The former by-value `Option::replace` ignored its input and was removed. Concrete 8-, 16-, and 32-bit Option/Result modules and concrete two-word 64-bit variants execute on x86_64. |
| `core::cmp` all 60 public free functions for six integer widths, `bool`, `char`, `WideU64`, and `WideI64` | Executable on x86_64 | The imported runtime fixture calls every equality and ordering function with equal and unequal values, both directions, signed and two-word extrema, unsigned high-bit values, both Boolean values, and Unicode characters. The `i32`, `u32`, `bool`, and `char` functions execute local trait implementation bodies. Narrow integer functions use scalar operators because their trait keys collide with the corresponding 32-bit type (dependency 57); two-word functions use the executable wide modules because imported nominal trait arguments fail in native emission (dependency 58). Direct imported trait calls remain outside this claim. |
| `core::cmp` trait methods, `core::hash::Hash<T>` trait methods, and `core::array_i32` | Contract-only as complete APIs in this audit | The public free comparison and hashing functions execute, but direct imported trait method calls do not. Generic fixed-array APIs depend on backend support. See dependencies 7, 31, 57, and 58. |
| `core::target` all 18 public functions and 16 constants | Executable x86_64 Linux capability metadata | The native fixture executes every function and reads every constant. It checks the available allocator, filesystem, stdio, clock, secure RNG, process, and environment bindings against `core::runtime`; unbound network, threads, GPU, host services, panic hooks, and test harness remain false. This is a target snapshot, not a live host probe. |
| `core::runtime` all 62 public functions and 40 constants | Executable x86_64 Linux capability metadata | The native fixture executes every function and reads every constant, checking service IDs, ABI fields, available and unavailable services, unknown IDs, status classifiers, and fail-closed requirement rows. These helpers report bindings; they do not implement an unbound service operation. |
| `core::panic` both trap functions, all 19 metadata functions, and 4 constants | Executable on x86_64 Linux for the trap functions and metadata | `tests/stdlib_panic_execution.rs` checks that `panic()` and `unreachable()` terminate with SIGILL, and a runtime fixture checks every metadata result. Panic hooks remain unbound; their availability flags stay false. |
| `alloc::allocator` all 32 public metadata functions and 4 host calls | Executable x86_64 Linux host ABI for valid allocation arguments | The native metadata fixture calls every metadata function, checks available service flags and null/non-null pointer classification against `core::runtime`, and performs a real allocation and release. `tests/stdlib_allocator_metadata_execution.rs` requires a runtime call for each metadata function. Normal allocation, reallocation, and release have x86 tests; the `alloc_failed` host call is tested as terminating with exit status 1. `tests/stdlib_allocator_failure_execution.rs` injects `ENOMEM` into `mmap` and `mremap`: both return null, and failed reallocation leaves the old storage readable and releasable. The API is low-level; callers must pass a valid pointer and matching sizes to `realloc` and `dealloc`. |
| `std::process` all 44 metadata functions, 12 constants, and 4 host calls | Executable on x86_64 Linux | The foundation runtime fixture checks every metadata function and constant, including successful and failed argument results, service availability, and exit status helpers. Native source-pack tests execute `argc`, `arg_len`, and `arg_read` with real process arguments; the process exit sample confirms that `exit(7)` terminates with status 7. This module reports the Linux host binding; GPU device execution is not claimed. |
| `std::env` all 54 public functions, 13 constants, and 6 host calls | Executable on x86_64 Linux | The foundation runtime fixture checks every metadata function and constant and calls `current_dir_len`. Native source-pack tests exercise environment lookup, enumeration, key reads, and current-directory reads with real host state. The focused environment suite checks missing keys, bounded storage, host failure, and allocation failure in `current_dir_len`. GPU device execution is not claimed. |
| `std::io` all 54 public Lanius functions, 12 constants, and 7 host calls | Executable on x86_64 Linux | The foundation runtime fixture checks every metadata function and constant. Existing I/O fixtures execute all six higher-level public functions, including line output, `print_i32`, and synchronous flush semantics. Native tests exercise the seven bound calls with real stdin, stdout, stderr, and file handles, including short writes and host errors. GPU device execution is not claimed. |
| `std::fs` all 67 public Lanius functions, 18 constants, and 14 host calls | Executable on x86_64 Linux | The foundation fixture checks every metadata function and constant. Native tests exercise raw open, append, read, write, close, path mutation, string paths, and decimal reads. Pointer path calls consume their supplied lengths and reject invalid bounds or embedded NUL bytes; decimal reads reject overflow. The file suite covers normal paths, missing paths, and host failures. GPU device execution is not claimed. |
| `std::random` all 28 metadata functions, 8 constants, and 2 host calls | Executable on x86_64 Linux | The foundation fixture executes every metadata function and reads every constant. `fill_secure_bytes` returns a byte count or negative error, including after unrelated host calls (resolved dependency 44). The raw `secure_u32` returns a full-width draw or traps on a short read or host error (resolved dependency 18). GPU device execution is not claimed. |
| `std::time` all 53 public metadata functions and 7 host calls | Mixed: bound calls executable; i64 declarations contract-only | The native metadata fixture calls every public metadata function, checks available and unavailable capabilities, classifies ordinary and failure results, and directly executes all four bound host calls: two 16-byte clock reads, i32 millisecond sleep, and Unix seconds. The broad `clock_read_api_*` and `clock_sleep_api_*` flags now describe their unbound i64 calls, and their fail-closed helpers recognize the unavailable result; separate timespec and i32 sleep flags describe the bound calls. Its i64 result checks cover only small values; full-width i64 behavior remains blocked by dependency 11. `std::time_checked` tests bounded operations and host failures. Consult `laniusc diagnostics runtime-apis` for per-call binding status. |
| `std::args_checked` all 3 public helpers | Executable x86_64 Linux host wrappers | `tests/stdlib_host_execution.rs` runs a Lanius program with nonempty and empty arguments. It checks argument count including the executable, exact byte lengths and bytes, absent/negative indices, sufficient and insufficient capacity, null storage, and capacity above `i32::MAX`. Caller storage avoids allocation. |
| `std::env_checked` all 3 public helpers | Executable x86_64 Linux host wrappers | `tests/stdlib_env_execution.rs` checks exact value and key bytes, missing and invalid indices, capacity and null-storage failures, current-directory bytes and its NUL terminator, and injected `getcwd` failure. Caller storage avoids allocation. |
| `std::time_checked` all 3 public helpers | Executable x86_64 Linux host wrappers | `tests/stdlib_time_execution.rs` checks both 16-byte clock reads, nanosecond bounds, a measured 50 ms sleep, invalid buffers/lengths, negative sleep, injected clock failures, and an interrupted host sleep. Caller storage avoids allocation and i64 scalar results. |
| `std::io::{write_line,println,eprintln,flush_stdout,flush_stderr,print_i32}` | Executable x86_64 host wrappers | `tests/stdlib_host_execution.rs` checks stdout, stderr, empty lines, exact byte counts, invalid handles, synchronous flushes, and signed printing through the real stdlib root. These are separate from the portable core. |
| `std::io_checked` all 5 public helpers | Executable x86_64 Linux host wrappers | `tests/stdlib_io_checked_execution.rs` checks exact stdin, bounded read-to-EOF, stdout, and stderr bytes; empty, exact-fit, and overlong input; invalid storage; EOF after a read prefix; host errors and zero progress; retries after short transfers; and a multi-chunk binary stdin-to-stdout copy. Caller storage avoids allocation. |
| `std::io_byte` all 3 public helpers | Executable x86_64 Linux host wrappers | `tests/stdlib_io_byte_execution.rs` checks scalar reads of ASCII, NUL, and 255, a distinct EOF fallback, checked stdout and stderr bytes, invalid values without writes, and injected read and write errors. `sample_programs/hex_to_decimal.lani` combines it with portable byte and hex helpers. The implementation uses one synchronous host call per byte. |
| `std::io_line` all 3 public helpers | Executable x86_64 Linux host wrappers | `tests/stdlib_io_line_execution.rs` checks multiple LF lines, exact-fit and zero capacities, EOF after a partial line, overlong-line consumption, CR and NUL bytes, stdout and stderr output, invalid codes without output, injected host errors, and native trapping on an overstated backing view. Bytes are stored as integers in caller-owned `[i32]` storage. |
| `std::io_utf8` all 7 public helpers | Executable x86_64 Linux host wrappers | `tests/stdlib_io_utf8_execution.rs` checks one- through four-byte scalar reads and writes, checked output of caller-backed `[i32]` UTF-8 byte-code and ordinary `[u8]` views, the Unicode maximum, distinct EOF and failure fallbacks, malformed and truncated input, invalid values without writes, native bounds trapping before output, and injected read and write errors. It does not access borrowed string storage. |
| `std::io_decimal` all 16 public helpers | Executable x86_64 Linux host wrappers | `tests/stdlib_host_execution.rs` checks signed and unsigned output extrema across 8-, 16-, 32-, and two-word 64-bit integers, exact byte counts, invalid handles, and injected sign and digit write failures for the underlying 32-bit writers. The two-word decimal-double programs also write full-width results through this module. `tests/stdlib_io_decimal_input_execution.rs` checks bounded stdin parsing across the six scalar and both two-word 64-bit types, EOF, whitespace and signs, malformed and overlong input, overflow, and injected read failures. |
| `std::io_hex` all 9 public helpers | Executable x86_64 Linux host wrappers | `tests/stdlib_io_hex_execution.rs` checks exact lowercase and uppercase writes across `u8`, `u16`, and `u32`, counts, invalid handles, injected write failures, bounded stdin parsing with optional prefix and whitespace, malformed and overflowing input, and injected read failures. |
| `std::io_hex_wide_u64` all 3 public two-word helpers | Executable x86_64 Linux host wrappers | The native suite calls every function and checks shortest lowercase and uppercase output, byte counts, invalid handles, full-width stdin values, optional prefixes, surrounding whitespace, malformed and overflowing input, exact and exceeded byte limits, and zero-limit behavior. With Linux `strace`, it also checks first and later short writes, write errors, and injected read failures. |
| `std::io_binary` all 6 public helpers | Executable x86_64 Linux host wrappers | `tests/stdlib_io_binary_execution.rs` checks shortest binary writes across `u8`, `u16`, and `u32`, exact byte counts, invalid handles, injected write failures, bounded stdin parsing with optional prefix and whitespace, malformed and overflowing input, and injected read failures. |
| `std::io_binary_wide_u64` both public two-word helpers | Executable x86_64 Linux host wrappers | The native suite calls both functions and checks shortest zero and full-width binary writes, byte counts, invalid handles, full-width stdin values, optional prefixes, surrounding whitespace, malformed and overflowing input, exact and exceeded byte limits, and zero-limit behavior. With Linux `strace`, it checks first and later short writes, write errors, and injected read failures. |
| `std::file_hex` all 9 public helpers | Executable x86_64 Linux host wrappers with literal paths | `tests/stdlib_file_hex_execution.rs` checks lowercase and uppercase writes, bounded hexadecimal file reads across `u8`, `u16`, and `u32`, whitespace and optional prefixes, malformed and overflowing input, missing and overlong files, and injected read/write/close errors. |
| `std::file_binary` all 6 public helpers | Executable x86_64 Linux host wrappers with literal paths | `tests/stdlib_file_binary_execution.rs` checks shortest binary file writes and bounded reads across `u8`, `u16`, and `u32`, whitespace and optional prefixes, malformed, missing, overlong, and overflowing input, plus injected read/write/close errors. |
| `std::file_binary_wide_u64` both public two-word helpers | Executable x86_64 Linux host wrappers with literal paths | The native fixture calls both functions and checks shortest zero, word-boundary, high-bit, and maximum writes; full-width bounded reads, optional prefix and surrounding whitespace, missing and malformed files, exact and exceeded byte limits, overflow, invalid output paths, and `/dev/full`. With Linux `strace`, it checks short and failing writes plus read and close failures. |
| `std::file` all 25 public helpers | Executable x86_64 Linux host wrappers | `tests/stdlib_file_execution.rs` checks text writes, one-shot, exact, and read-to-end caller-buffer reads, complete handle and path buffer writes, multi-chunk binary copies between files and standard streams, bounded decimal reads and writes across 8-, 16-, 32-, and two-word 64-bit integers, empty and overlong files, invalid buffer sizes, missing paths, injected read/write/close errors, and write failures using `/dev/full`. `copy_distinct_with_buffer` requires distinct underlying files and a valid writable buffer. |
| `std::random_checked` all 6 public helpers | Executable x86_64 Linux host wrappers | `tests/stdlib_random_execution.rs` checks exact caller-buffer filling, zero length and invalid arguments, host errors and zero progress, short-read retries, bounded and inclusive unsigned and signed outputs, forced draws and rejection, full-range failure fallbacks, and secure i32 slice shuffling with preserved contents, a forced swap, and injected failure. The suite also runs a raw fill after a directory read to guard the runtime flags fix, and confirms that the raw scalar traps on host failure and short reads. |
| `std::path` all 17 constants and all 37 public functions | Executable on x86_64 | `tests/stdlib_path_execution.rs` runs ordinary and boundary cases for byte classes, separator kind, component headers, path headers, full caller-backed component bytes, and last-component, extension, and stem byte offsets. The final-component helpers treat slash and backslash as separators, ignore trailing separators, accept non-UTF-8 bytes, and return the supplied fallback for empty or separator-only paths, negative lengths, or embedded NUL. A leading dot alone and a trailing dot do not create an extension. The two-byte header classifiers check only the supplied header when `length > 2`; use `path_component_is_normal_relative_bytes` or `path_component_matches_windows_relative_byte_rules` to inspect every byte. Negative and empty lengths return false in the classifiers; an overstated positive length traps on native indexing if scanning reaches beyond the backing slice. The Windows byte classifier rejects reserved bytes but does not reject reserved device names or trailing spaces/dots. Redundant no-argument functions that failed natively were removed in favor of the tested constants. Allocation and host normalization are unavailable. |
| `std::vec_i32` all 19 public functions and its capacity constant | Executable on x86_64 Linux | `tests/fixtures/stdlib_foundation/vec_i32.lani` checks construction, growth, element access and mutation, bounds, reserve, pop, clear, cloning, and destruction. `tests/stdlib_vec_i32_execution.rs` injects allocation and reallocation failures and checks the vector and prior data stay unchanged. This is a linear-ownership API by convention; source-level moves are not enforced. |
| `std::vec_u32` all 19 public functions and its capacity constant | Executable on x86_64 Linux | The unsigned vector fixture checks construction, growth, access, mutation, bounds, reserve, pop, clear, cloning, destruction, `2^31`, and `u32::MAX`. The allocation-failure suite injects failed initial allocation and reallocation; the real checksum sample combines it with `core::number_u32` and `OptionU32`. Storage uses 32-bit cells and preserves every unsigned bit pattern. Ownership is linear by convention. |
| `std::vec_u8` all 20 public functions and its capacity constant | Executable on x86_64 Linux | The byte vector fixture checks construction, growth, independent cloning, access, mutation, bounds, reserve, pop, clear, destruction, 128, and 255. `data_ptr` exposes its 32-bit byte-code cells for a caller-bounded borrowed view; the fixture checks empty and initialized views. The allocation-failure suite injects failed initial allocation, reallocation, and a clone allocation through the text wrapper; the byte checksum sample combines it with `core::byte` and `OptionU8`. Each byte occupies one 32-bit cell because the raw-slice intrinsic currently accepts i32 cells. Ownership is linear by convention. |
| `std::utf8_vec` all 30 public text helpers | Executable on x86_64 Linux | The runtime fixtures construct and edit text from Unicode scalars, complete caller-backed UTF-8 byte-code views, and ordinary `[u8]` byte views; check independent cloning, multibyte bytes, scalar count and lookup, first and last search, equality, prefixes, suffixes, ordering, byte-offset sequence search, insertion, removal, replacement, splicing, pop, clear, and destruction. Byte-view splicing covers growth, shrinkage, equal-width replacement, and insertion at the end; malformed input and invalid indices leave data unchanged. Injected allocation failures check that failed scalar, byte-code, and `[u8]` edits preserve prior bytes. Storage is a `VecU8` with one 32-bit cell per encoded byte and linear ownership by convention. |
| `std::vec_i8` all 19 public functions and its capacity constant | Executable on x86_64 Linux | The signed byte vector fixture checks construction, growth, access, mutation, bounds, reserve, pop, clear, cloning, destruction, `-128`, and 127. The allocation-failure suite injects failed initial allocation and reallocation; the signed byte sum sample combines it with `core::number_i8` and `OptionI8`. Each signed byte occupies one 32-bit cell, preserving its sign. Ownership is linear by convention. |
| `std::vec_u16` all 19 public functions and its capacity constant | Executable on x86_64 Linux | The unsigned halfword fixture checks construction, growth, access, mutation, bounds, reserve, pop, clear, cloning, destruction, 32768, and 65535. The allocation-failure suite injects failed initial allocation and reallocation; the halfword checksum sample combines it with `core::number_u16` and `OptionU16`. Each halfword occupies one 32-bit cell. Ownership is linear by convention. |
| `std::vec_i16` all 19 public functions and its capacity constant | Executable on x86_64 Linux | The signed halfword fixture checks construction, growth, access, mutation, bounds, reserve, pop, clear, cloning, destruction, `-32768`, and 32767. The allocation-failure suite injects failed initial allocation and reallocation; the signed halfword sum sample combines it with `core::number_i16` and `OptionI16`. Each halfword occupies one 32-bit cell. Ownership is linear by convention. |
| `std::vec_bool` all 19 public functions and its capacity constant | Executable on x86_64 Linux | The boolean fixture checks construction, growth, access, mutation, bounds, reserve, pop, clear, cloning, destruction, and stored `false` distinct from a `true` fallback. The allocation-failure suite injects failed initial allocation and reallocation; the true-count sample combines it with `core::bool` and `OptionBool`. Each boolean occupies one 32-bit cell containing 0 or 1. Ownership is linear by convention. |
| `std::map_i32_i32` all 16 public functions and its entry-limit constant | Executable on x86_64 Linux | A single allocator-backed pair array provides linear lookup, insertion without partial pairs, in-place update, ordered removal, reservation, independent cloning, clearing, capacity release, and destruction. The native fixture calls every function and checks zero and negative keys and values, the signed maximum key, duplicates, missing keys, ordinal bounds, retained and reduced capacity, and clone independence. Injected initial, growth, shrink, and clone allocation failures preserve the original map or return an empty clone. The byte-histogram program combines it with numeric and byte I/O helpers on empty, text, and binary input. Ownership is linear by convention. |
| `std::set_i32` all 19 public functions and its capacity constant | Executable on x86_64 Linux | The native fixture calls every function and checks empty and populated sets, both signed extremes, duplicates, absent items, insertion order, stable removal, invalid ordinals and capacities, independent cloning, clearing, growth, shrinking, subset and disjoint predicates, and ordered union, intersection, difference, and symmetric difference. Injected initial allocation, growth, shrink, clone, and each set-algebra allocation failure preserve ownership and existing items. The set owns one allocation of 32-bit cells; ownership is linear by convention. |
| `std::net` all 64 metadata functions and 6 constants | Executable metadata on x86_64 Linux; 10 host calls unbound | The native fixture calls every metadata function and constant, checks available and unavailable result classification, and confirms network capability flags against `core::runtime`. TCP and UDP calls have no runtime binding. |
| `std::thread` all 32 metadata functions and 6 constants | Executable metadata on x86_64 Linux; 4 host calls unbound | The native fixture calls every metadata function and constant, checks result classification, and confirms that spawn, join, yield, and current-id calls remain unavailable. |
| `std::gpu` all 44 metadata functions and 6 constants | Executable metadata on x86_64 Linux; 5 host calls unbound | The native fixture calls every metadata function and constant, checks result classification, and confirms unavailable buffer and dispatch services. Compiler execution on a GPU does not bind a user-program GPU API. |
| `std::host` all 15 metadata functions and 4 constants | Executable metadata on x86_64 Linux | The native fixture calls every public function and constant and checks its unavailable service report against `core::runtime`. No host operation ABI is declared here. |
| `test::harness` all 31 metadata and status functions and 7 constants | Executable metadata on x86_64 Linux; test execution unbound | The native fixture calls every public function and constant, checks passed, failed, skipped, and unknown statuses, and confirms registration, discovery, and execution remain unavailable. |
| `test::assert` all 8 public helpers | Executable on x86_64 Linux | `tests/stdlib_assert_execution.rs` runs all passing conditions and separately checks that every false condition terminates with SIGILL. The helpers use no allocation or host calls. See dependency 35 for a separate compiler issue with explicit void returns. |
| Generic `std::vec::Vec<T>` associated `new`, `len`, and `is_empty` | Executable on x86_64 for imported `i32` and `bool` empty values | `tests/stdlib_generic_vec_flat_execution.rs` compiles the real `std::vec` through `--stdlib-root` and executes both instantiations, including their methods. There is no generic storage or mutation. The former `push` silently discarded its argument and was removed. See dependencies 4 and 54. |
| Generic `std::vec::new` | Executable on x86_64 for imported `i32` and `bool` empty values | An annotated `Vec<T>` supplies the result type, and the imported constructor runs through `--stdlib-root`. See `tests/stdlib_generic_vec_flat_execution.rs`. |
| Generic `std::vec::{len,is_empty}` | Executable on x86_64 for imported `i32` and `bool` empty values | `repro_vec_generic_free_new.lani` executes both through `--stdlib-root` with both instantiations. `repro_vec_generic_free_direct_argument.lani` also executes direct nested constructor arguments. Generic `Vec<T>` has no storage or mutation; concrete vectors use the allocator service. See dependencies 4 and 54. |

All seven concrete vector modules also implement `truncate(value, new_len)`.
`tests/stdlib_vec_truncate_execution.rs` executes each imported implementation:
valid truncation preserves the prefix and capacity, invalid lengths leave the
vector unchanged, and appending after truncation reuses the allocation.
All seven also implement `try_resize(value, new_len, fill)`: growth fills each
new element, shrinking retains the prefix and allocation, and invalid lengths
or allocation failure leave the original vector unchanged. The imported
runtime fixture checks all seven element types, including signed and unsigned
extremes and `false`; an injected `mremap` failure checks preservation of the
original i32 vector.
Each concrete module also implements `try_shrink_to_fit(value)`. The native
fixture checks that it preserves elements, reaches `capacity == len`, releases
storage for an empty vector, and permits subsequent growth. An injected
`mremap` failure checks that the old allocation, capacity, and elements stay
owned by the returned vector.

For all seven concrete vector types, the allocation-failure suite executes a
successful clone and then injects failure into its allocation. It checks that
the failed clone is empty and that the original vector retains its elements
and ownership. `strace` is required for the injected branch.
The same suite forces growth during middle insertion and batch append and
checks that failed reallocation leaves length, capacity, order, and ownership
unchanged.

The inventory classifies a module as contract-only when it lacks sufficient
runtime evidence as a complete import, even if several bodies contain real
Lanius logic. No declaration is promoted solely because it type-checks.

## Executable subset and behavior

- `core::target` and `core::runtime` describe the currently supported native
  service bindings. The target flags now agree with the runtime inventory for
  the allocator, filesystem, stdio, clock, secure RNG, process, and environment.
  `is_freestanding` is false because those bindings exist.
  `HAS_RUNTIME_SERVICES` remains false because the complete service set is not
  bound; individual availability flags do not claim that every function in a
  host module works. These constants are a compiled target snapshot, not
  probes of the live host.
- `core::number_i8` widens arithmetic to i16 before checking the signed 8-bit
  bounds. Wrapping add, subtract, and multiply reduce modulo 256 and return
  the signed low-byte value. Saturating operations clamp to `MIN` or `MAX`;
  unrepresentable multiplication, powers, GCD, and LCM return the caller's fallback. Division
  and remainder return the fallback for zero or `MIN/-1`. The next positive
  power of two returns zero above 64.
- `core::number_i16` widens arithmetic to i32 before checking the signed
  16-bit bounds. Wrapping add, subtract, and multiply reduce modulo 65,536 and
  return the signed low-half value. Saturating operations clamp to `MIN` or
  `MAX`; `mul_or`, `pow_or`, and unrepresentable GCD/LCM results return the caller's fallback.
  `gcd_or(0, 0, _)` is zero. Division and remainder return the fallback for a
  zero divisor or `MIN/-1`. Euclidean remainder is nonnegative. The next
  positive power of two returns zero above 16,384.
- `core::number_u16` widens sums and products to u32, which can represent the
  product of any two u16 values. Saturating operations clamp at 65,535;
  wrapping operations reduce modulo 65,536. `gcd(0, 0)` is zero. `lcm_or` and
  `pow_or` return the caller's fallback above 65,535. A zero divisor or
  alignment returns the fallback or false as named. The next positive power
  of two returns zero above 32,768, and `align_up_or` returns its fallback
  when rounding would exceed 65,535.
- `core::number_i32` provides saturating arithmetic and wrapping add,
  subtract, and multiply modulo 2^32. `clamp_or` returns its caller-supplied
  fallback when `low > high`; valid inclusive bounds clamp.
  `saturating_mul` clamps an unrepresentable mathematical product to `MIN` or
  `MAX`; `mul_or` returns the caller's fallback for that case. Both check
  overflow before multiplying, including `MIN * -1`. `pow_or` defines `0^0`
  as one, computes powers by squaring, and returns the fallback on overflow.
  `div_or` and `rem_or` return the fallback for a zero divisor or `MIN/-1`.
  `div_euclid_or` and `rem_euclid_or` apply the same failure rule and otherwise
  return a quotient and nonnegative remainder satisfying
  `value = divisor * quotient + remainder`.
  `gcd_or(0, 0, _)` returns zero; if the true GCD is 2,147,483,648, it returns
  the caller's fallback because that magnitude does not fit in `i32`.
  `lcm_or` returns a nonnegative result, zero if either input is zero, or the
  fallback if the LCM exceeds `i32::MAX`.
  `is_multiple_of(_, 0)` is false. `next_power_of_two` returns zero when the
  next positive power would exceed 1,073,741,824.
- `core::number_u32` saturates or wraps as named. `saturating_mul` checks
  overflow with division instead of repeated addition. `is_multiple_of(_, 0)`
  and `is_aligned(_, 0)` are false. `next_power_of_two` returns zero above
  2,147,483,648. Invalid alignment or overflowing `align_up_or` returns the
  caller's fallback. `gcd(0, 0)` is zero; `lcm_or` returns zero if either input
  is zero and the caller's fallback if the LCM exceeds `u32::MAX`.
  `pow_or` also defines `0^0` as one and returns the caller's fallback for a
  power above `u32::MAX`. `div_or` and `rem_or` return the caller's fallback
  for a zero divisor.
  `core::u32::saturating_mul` uses the same constant-time
  source algorithm and runs in its imported module fixture.
- `core::wide_u64` represents an unsigned 64-bit integer explicitly as high
  and low `u32` words. It performs unsigned comparisons, arithmetic modulo
  2^64, bitwise operations, logical shifts, and quotient/remainder without
  native `u64` operations. Shift counts outside 0 through 63 return zero;
  division and remainder by zero return the caller's fallback. Its functions
  allocate no memory and invoke no host service. `decimal_len` counts the
  shortest unsigned decimal representation, and `decimal_byte_at_or` returns
  its ASCII bytes from the most significant digit. Invalid indices return the
  caller fallback. `can_parse_ascii_decimal` accepts exactly a positive
  logical length of ASCII digits from a caller-backed `[i32]` view, including
  leading zeros, and rejects values above 2^64 - 1 before arithmetic wraps.
  `parse_ascii_decimal_or` returns the caller fallback for empty, malformed,
  or overflowing input; call the predicate first when a valid value could
  equal the fallback. An overstated physical view can trap on indexing. The
  imported x86 fixtures
  execute every public function and compare selected values against native
  `u64` results. Native `u64` expressions themselves remain incorrect above
  32 bits; see dependencies 26 and 30.
- `core::wide_i64` uses the same two-word representation in two's complement.
  `from_i32` sign-extends, comparison uses signed order, and arithmetic right
  shifts fill vacated bits with the sign. Addition, subtraction,
  multiplication, and negation wrap modulo 2^64 where named; saturating add
  and subtract clamp to the signed minimum or maximum. Division truncates
  toward zero and remainder has the dividend's sign. A zero divisor or
  `MIN / -1` returns the caller's fallback from either division helper.
  Invalid shift counts return zero. `decimal_len` includes the minus sign,
  and `decimal_byte_at_or` emits the shortest signed ASCII representation;
  invalid indices return the caller fallback. `can_parse_ascii_decimal`
  accepts an optional leading `+` or `-` followed by at least one ASCII
  digit from a positive logical length of caller-backed `[i32]` codes. It
  accepts leading zeros and negative zero, and rejects whitespace, malformed
  input, and values outside the signed 64-bit range. An overstated physical
  view can trap when indexed. `parse_ascii_decimal_or` returns the caller
  fallback for invalid input; call the predicate first when a valid value
  could equal the fallback. These functions use no allocation or host service
  and do not depend on native `i64` arithmetic.
- `core::wide_u64_checked` returns `OptionWideU64` for add, subtract,
  multiply, divide, remainder, and power. Overflow, underflow, and a zero
  divisor return `None`; `checked_pow` defines `0^0` as one. Saturating add
  and multiply return the unsigned maximum on overflow, while saturating
  subtract returns zero on underflow.
- `core::wide_i64_checked` returns `OptionWideI64` for add, subtract, negate,
  absolute value, multiply, divide, remainder, and power. `MIN` negation or
  absolute value, `MIN / -1`, a zero divisor, and unrepresentable arithmetic
  return `None`. Its saturating multiply clamps according to the result sign;
  saturating negate and absolute value map `MIN` to `MAX`. Both checked
  modules allocate no memory and invoke no host service.
- `core::byte` arithmetic saturates or wraps as its function name says.
  `wrapping_mul` computes multiplication modulo 256; the focused fixture
  compares all 65,536 byte pairs with a widened arithmetic reference.
  `is_multiple_of(_, 0)` returns false; `div_or` and `rem_or` return the
  caller's fallback for a zero divisor. `gcd(0, 0)` is zero. `lcm_or` returns
  zero if either input is zero and the fallback if the LCM exceeds 255.
  `pow_or` defines `0^0` as one and returns the fallback on overflow.
  Invalid ASCII hex input returns the
  unchanged fallback from `ascii_hexdigit_value_or`. `clamp_or` returns its
  fallback for reversed bounds. `next_power_of_two` returns zero when the next
  u8 power would exceed 128. `high_nibble` and `low_nibble` split a byte;
  `join_nibbles_or` returns the fallback when either input exceeds 15.
  `ascii_lower_hex_digit_or` and `ascii_upper_hex_digit_or` accept nibbles
  `0..=15` and return the fallback otherwise. Its ASCII whitespace set is
  SP, HT, LF, CR.
- `core::bits` treats `u32` as exactly 32 bits. Zero has 32 leading and
  trailing zeros; rotations reduce their count modulo 32. `bit_at_or_u32`
  returns the caller's fallback for an index of 32 or more. The byte-packing
  helpers accept four `u8` values in big- or little-endian order; extraction
  indices 0 through 3 use the named order and higher indices return the
  caller's fallback.
- The `u8` operations in `core::bits` widen before shifting and return eight
  leading or trailing zeros for zero. Rotation counts reduce modulo eight.
  `bit_at_or_u8` accepts indices 0 through 7 and returns the caller's
  fallback for larger indices.
- The `u16` operations use the same widened arithmetic. Zero has 16 leading
  and trailing zeros, rotations reduce their counts modulo 16, and
  `bit_at_or_u16` accepts indices 0 through 15 before using its fallback.
- The `i32` operations read or rotate the complete two's-complement bit
  pattern through `u32`. `has_single_bit_i32(i32::MIN)` is true because its
  representation has one set bit. Rotations, reversal, and byte swap return
  the resulting bit pattern as `i32`.
- `core::wide_u64_bits` counts and transforms the complete 64-bit pattern in
  two `u32` words. Zero has 64 leading and trailing zeros. Rotation amounts
  reduce modulo 64, including `u32::MAX`. Bit positions 0 through 63 and byte
  positions 0 through 7 are valid; larger positions return the caller's
  fallback. Little-endian byte zero is the least significant byte and
  big-endian byte zero is the most significant byte.
- `core::wide_i64_bits` applies those same rules to the two's-complement bit
  pattern of `WideI64`. In particular, the signed minimum has one set bit,
  and rotations can move that sign bit into or out of the low word.
- `core::bitset` stores bit zero in the least-significant bit of word zero.
  The caller supplies at least `ceil(bit_len / 32)` words. A negative logical
  length returns `false` or the named fallback without touching storage;
  out-of-range bit indices do the same. A nonnegative length that exceeds
  physical backing traps when an out-of-bounds word is accessed. Empty sets
  have no set bits and satisfy `all_or`. Counts and comparisons ignore unused
  high bits in the last word; mutation preserves those bits and any extra
  words. Union and intersection permit the destination to alias an input.
  `sample_programs/bitset_prime_sieve.lani` uses this storage and
  `core::number_i32` to count and sum primes through 100; its executable test
  checks the printed results, 25 and 1060.
- `core::base64` uses the standard `A-Z`, `a-z`, `0-9`, `+`, `/` alphabet with
  required `=` padding. It rejects whitespace, misplaced padding, and nonzero
  unused bits. `encoded_len_or` returns the caller's fallback if the input
  length is negative or the encoded size exceeds `i32::MAX`; `decoded_len_or`
  validates the complete view before returning its size. `encode_into` and
  `decode_into` return `-1` for invalid logical lengths, malformed input, or
  insufficient declared output capacity, leaving output untouched in those
  cases. Both allow input and output to be the same byte array. A length or
  capacity that overstates physical backing can trap on native indexing.
- `core::endian` reads and writes two-, four-, and eight-byte unsigned fields at a
  caller-supplied offset in a logical byte view. Big-endian order places the
  most significant byte first; little-endian order places it last. A negative
  length or offset, or a field that exceeds the logical length, returns the
  supplied read fallback or `false` before touching storage. A logically valid
  field beyond physical backing traps on native indexing. Writes preserve
  every byte outside the field. Eight-byte functions take and return
  `core::wide_u64::WideU64`, avoiding the incomplete native `u64` path.
  `sample_programs/packet_header_sum.lani`
  parses a mixed-endian packet header, sums its payload, and prints `67`.
- `core::varint` and `core::varint_wide_u64` encode canonical unsigned LEB128
  into caller-owned bytes and decode one value from a caller-supplied offset.
  Zero uses one byte; the maxima use five and ten bytes. The write functions
  return the next offset or `-1` for invalid logical bounds or insufficient
  space, and reject those cases before writing. Read results expose `OK`,
  `INVALID_BOUNDS`, `TRUNCATED`, `OVERFLOW`, and `NON_CANONICAL`; failed value
  and next-offset accessors return the caller's fallback. A terminated
  encoding with a zero final group after an earlier group is noncanonical.
  Physical backing overclaims trap when an element is accessed. The wide
  result stores flat scalar words to avoid dependency 56. The codecs are
  portable Lanius source, but executable target evidence is x86_64 only.
  `sample_programs/varint_frame_sum.lani` writes a small frame, decodes it,
  and prints `4294967606`.
- `core::varint_i32` and `core::varint_wide_i64` map signed values to unsigned
  LEB128 with ZigZag encoding: `0 -> 0`, `-1 -> 1`, `1 -> 2`, and the signed
  minimum to the corresponding unsigned maximum. The unsigned readers supply
  the status and next offset. The signed `value_*_or` accessors decode only a
  successful result and otherwise return the caller's fallback. Signed writes
  inherit the unsigned no-write logical rejection and physical-backing trap
  behavior. `sample_programs/varint_signed_frame_sum.lani` decodes three
  signed readings and prints `-4294967321`.
- `core::bool` converts any nonzero i32 to true. Its selector functions return
  the chosen branch value. `core::char` tests ASCII classes; its case-insensitive
  equality and case conversion fold ASCII letters only. `is_ascii_control`
  includes `0..=31` and 127; non-ASCII input is unchanged by conversion.
- `core::utf8` accepts Unicode scalar values in `0..=0x10FFFF` excluding the
  surrogate range. Valid encoded bytes and decoder arguments use `u8`.
  Encoding returns a caller fallback for an invalid scalar or byte index.
  Decoding accepts exactly one to four bytes, ignores unused arguments, and
  returns the caller fallback for malformed, overlong, surrogate, truncated,
  or out-of-range sequences. `codes_are_valid` and `scalar_count_or` scan a
  caller-backed `[i32]` view of byte codes in `0..=255`, reject malformed or
  truncated sequences, and count Unicode scalars. Negative lengths are
  invalid; an empty view is valid with count zero. The count helper returns
  the caller fallback on failure, which can equal a valid count. An overstated
  physical view length may trap on native indexing.
  `bytes_are_valid` and `byte_scalar_count_or` apply the same UTF-8 rules to
  ordinary caller-backed `[u8]` views. They accept empty input, reject negative
  lengths and malformed sequences, and may trap on a physical length overclaim.
  `byte_view_offset_of_scalar_or` and `byte_view_scalar_index_of_byte_or`
  map valid scalar and byte boundaries in these `[u8]` views; the end boundary
  is allowed. `byte_view_scalar_at_or` decodes a selected scalar. All three
  validate the complete view before answering and return the caller fallback
  for invalid UTF-8 or indices.
  `core::utf8_view` compares and searches complete validated `[u8]` views.
  Equality and prefix/suffix checks return false for malformed input;
  ordering returns -1, 0, or 1, or the caller fallback on invalid input.
  Sequence searches return byte offsets; scalar searches return scalar
  indices. First and last empty-sequence searches return zero and the view
  length respectively. Invalid needles and missing matches return the caller
  fallback. `byte_view_append_scalar_or` encodes one valid scalar into a
  validated caller-owned prefix and returns its new length. Invalid UTF-8,
  scalar, length, or logical capacity returns fallback without writing.
  `byte_view_insert_scalar_or` accepts a scalar index from zero through the
  scalar count; removal and replacement require an existing scalar. They
  return the new byte length, or fallback without writing for malformed
  input, an invalid scalar or index, or insufficient logical capacity.
  Removal and shrinking replacement leave bytes above the new length outside
  the logical view.
  All views must physically back their claimed lengths and writable capacity.
  `byte_offset_of_scalar_or` maps scalar indices to byte starts and permits
  the index equal to the scalar count, returning the end offset. The inverse
  `scalar_index_of_byte_or` accepts only byte boundaries, including the end.
  `scalar_at_or` decodes a selected scalar. `index_of_scalar_or` and
  `last_index_of_scalar_or` return the first or last scalar index of a valid
  needle. Each checks the complete backed view first and returns its caller
  fallback for malformed UTF-8, invalid indices or needles, and missing
  scalars. `append_scalar_or` validates the existing byte-code prefix and
  checks scalar validity and remaining capacity before writing any bytes.
  It returns the new byte length, or its caller fallback without writing for
  invalid input. The claimed capacity must fit the physically backed writable
  view; an overclaim may trap. `equal_codes`, `starts_with_codes`, and
  `ends_with_codes` check both complete views and return false if either is
  invalid. `compare_codes_or` compares valid canonical UTF-8 byte sequences
  lexicographically and returns -1, 0, or 1. `index_of_codes_byte_or` and
  `last_index_of_codes_byte_or` search a valid complete view for a valid
  complete sequence, returning byte offsets. An empty needle matches at zero
  for the first search and at the view length for the last. Comparisons and
  searches return the caller fallback on malformed input or a missing match.
  A fallback can equal a valid result. Borrowed `str` storage remains a
  separate compiler dependency below.
- `core::decimal` returns decimal length and the ASCII byte at a zero-based
  index for `u8`, `u16`, `u32`, `i8`, `i16`, and `i32`. The maximum lengths are
  3, 5, 10, 4, 6, and 11 respectively. Signed output includes `-` at index
  zero when negative, including each minimum value without negating it. An
  index outside the representation returns the caller's
  fallback unchanged. It performs no allocation or host I/O.
  `can_append_ascii_digit_u32` rejects non-digits and decimal appends above
  the supplied limit before multiplication. `append_ascii_digit_or_u32` returns
  the caller's fallback on either failure; that fallback can equal a valid
  parsed value, so callers needing a separate success check use the predicate.
  The `parse_ascii_*_or` functions read exactly the given number of ASCII
  codes from a caller-backed `[i32]` view for all six 8-, 16-, and 32-bit
  integer types. Unsigned input accepts one or more digits; signed input also
  accepts one optional leading sign. Neither accepts whitespace or trailing
  characters. Empty, sign-only, malformed, and overflowing input returns the
  caller fallback, which can equal a valid value. Signed minimums and maximums
  parse without overflow; narrow parsers reject values outside their own
  width before casting. An overstated physical view length can trap on native
  indexing.
- `core::hex` returns the shortest unsigned hexadecimal length and lowercase
  or uppercase ASCII byte at a zero-based index for `u8`, `u16`, and `u32`.
  Zero is one digit; out-of-range indices return the caller's fallback. Its
  digit predicate accepts ASCII `0..9`, `a..f`, and `A..F`, and rejects an
  append above a caller-supplied limit before multiplying by 16. The append
  helper returns fallback for malformed or overflowing input, which can equal
  a valid parsed value; call the predicate when success must be separate.
  `parse_ascii_u8_or`, `parse_ascii_u16_or`, and `parse_ascii_u32_or` consume
  exactly the caller-supplied length of a backed `[i32]` view. They accept
  mixed-case digits with an optional `0x` or `0X` prefix, and require at least
  one digit. Empty, prefix-only, malformed, whitespace-containing, or
  overflowing input returns the caller fallback. A valid value can equal that
  fallback. An overstated physical view length can trap on native indexing.
- `core::hex_wide_u64` extends those rules to 64-bit values stored in two
  `u32` words. It formats zero as one digit and values through `2^64-1` as up
  to 16 digits. `can_parse_ascii` distinguishes a valid value equal to the
  caller's fallback from a failed `parse_ascii_or`. Both accept an optional
  `0x` or `0X` prefix and reject whitespace, signs, invalid codes, empty
  digits, and overflow. The caller supplies the logical `[i32]` view length;
  overstating physical backing traps when indexed.
- `core::binary_wide_u64` extends the binary rules to 64-bit values stored
  in two `u32` words. Zero has one digit and the maximum has 64.
  `can_parse_ascii` separates success from a value equal to the caller's
  fallback. Parsing reads exactly the caller's logical `[i32]` length,
  accepts an optional `0b` or `0B` prefix, and rejects empty digits,
  malformed codes, and overflow. An overstated physical backing may trap.
- `core::binary` returns the shortest unsigned binary length and ASCII byte
  at a zero-based index for `u8`, `u16`, and `u32`. Zero is one digit;
  out-of-range indices return fallback. Its digit predicate accepts only
  ASCII `0` and `1` and checks the caller's limit before multiplication by
  two. The append helper returns fallback for malformed or overflowing input;
  that fallback can equal a valid value. The three `parse_ascii_*_or` helpers
  read exactly the supplied length of a backed `[i32]` code view, accept an
  optional `0b` or `0B` prefix followed by at least one digit, and reject
  empty, sign-containing, whitespace-containing, malformed, and overflowing
  input. An overstated physical view length can trap on native indexing.
- `core::f32::clamp_or` returns its caller fallback when bounds are reversed
  or either bound is NaN; `clamp` returns its input unchanged for those invalid
  bounds. Valid bounds clamp inclusively, and a NaN value propagates.
  `min` and `max` return the non-NaN argument when exactly one is NaN; two
  NaNs yield NaN. `signum` and `sqrt` propagate NaN. Predicates treat NaN as
  unordered: it is nonzero, neither positive nor negative, and outside every
  finite interval. `sqrt` returns zero for nonpositive inputs and scales finite
  positive inputs before Newton iteration, including values far above or below
  one. `sqrt_or` returns its caller fallback for negative or NaN inputs and
  otherwise uses `sqrt`, including positive infinity. `is_nan`, `is_infinite`,
  and `is_finite` classify NaN, both infinities, ordinary finite values, and
  signed zero. Imported `core::f32::ONE` has a native runtime case; the constant
  lowering repair is described in dependency 5.
- `core::array_i32_4::sum` folds with saturating addition; overflowing sums
  clamp to the corresponding i32 endpoint at each element. `get_or` and
  `index_of_or` return the caller's fallback for out-of-range or absent values.
  `copy_into`, `fill`, and `reverse_into` write into caller-backed views.
  They return false without writing if the claimed destination length is below
  four. The caller must supply at least four physical elements; overstated
  lengths can trap on indexing. `reverse_into` can use the same source and
  destination backing. The legacy source form has the same destination rules.
- `core::array_u8_4` accepts exactly four `u8` elements. `sum_u32` returns
  their exact sum in `0..=1020`; endian conversion interprets the first array
  element as the most or least significant byte as named. `get_or` and
  `index_of_or` return caller fallbacks for invalid indices or absent bytes.
  `copy_into`, `fill`, and `reverse_into` write four bytes into caller-owned
  storage. They return false before writing for destination lengths below four;
  overclaiming the physical backing can trap. Reversal may share backing.
- `core::option_i32` distinguishes `None` from `Some(0)` with a presence flag;
  `contains` ignores the inactive payload, and `unwrap_or` returns its caller
  fallback only for `None`. `or`, `and`, and `xor` use the ordinary optional
  value truth table and return complete values. `core::result_i32` similarly
  distinguishes `Ok(0)` from `Err(0)` with a success flag. Its `contains` and
  `contains_err` inspect only the active payload, and both unwrap helpers
  return the caller fallback on the opposite variant. `option_i32::ok_or`
  turns `Some` into `Ok` and `None` into the supplied `Err`; its `ok` and
  `err` extract the matching result payload into an option and return `None`
  for the other result variant. Neither module allocates.
- `core::option_u32` and `core::result_u32` use the same explicit presence and
  success flags for unsigned payloads and error codes. `Some(0)`, `Ok(0)`,
  and `Err(0)` remain distinct. All extraction operations either inspect the
  active variant or return a caller fallback. Neither module allocates.
- `core::option_wide_u64`, `core::result_wide_u64`, `core::option_wide_i64`,
  and `core::result_wide_i64` carry full two-word values with a presence or
  success flag. Their Result error type is `i32`; an Err stores its bit pattern
  in the low word and zeroes the high word. Callers must inspect the tag or
  use a fallback accessor before reading a value. `Some(0)`, `Ok(0)`, and
  `Err(0)` are distinct. `ok_or` turns an optional wide value into a Result;
  `ok` extracts a wide value and `err` extracts an `OptionI32` error. Both
  signed and unsigned pairs make no heap allocation and use no host service.
- `core::option_u8`, `core::option_i8`, `core::option_u16`, and
  `core::option_i16` pair with their matching concrete Result modules. A
  success or presence flag distinguishes `Some(0)`, `Ok(0)`, `Err(0)`, and
  absence; inactive payloads are zero, and extraction on the inactive branch
  returns the caller fallback. `core::i8`, `core::i16`, `core::i32`,
  `core::u8`, `core::u16`, and `core::u32` use the corresponding concrete Option modules until
  generic enum lowering works. Their `clamp` functions leave the input
  unchanged when `low > high`. `core::i32::abs(MIN)` returns `MAX`, while
  `checked_abs(MIN)` returns `None`. `core::u32::is_aligned(_, 0)` is false;
  `align_up` and `align_down` return zero for zero alignment, and `align_up`
  returns zero if rounding would overflow. Callers that need an arbitrary
  failure value can use `core::number_u32::{align_up_or,align_down_or}`.
  `core::i8` and `core::i16` follow the same `abs(MIN)` and checked-absence
  rules. Checked add and subtract widen to i32 before testing their own
  bounds. Their wrapping arithmetic reduces modulo 256 or 65,536, and their
  next power helpers return zero above 64 or 16,384 respectively.
  `core::u16` wraps arithmetic modulo 65,536, returns `None` for checked
  overflow or underflow, and returns zero for unrepresentable next powers of
  two or invalid and overflowing alignment. Its widening arithmetic avoids
  overflowing before the bounds check; callers needing a distinct alignment
  failure value can use `core::number_u16::{align_up_or,align_down_or}`.
- `core::option_bool` and `core::result_bool` use separate presence and
  success flags. Stored `false` is distinct from `None`, and both `Ok(false)`
  and `Err(false)` retain their variant. Inactive fields are `false`.
  `unwrap_or` and `unwrap_err_or` return the caller fallback on the inactive
  branch. The Option to Result conversion uses the supplied boolean error;
  `ok` and `err` extract only the matching Result variant. Both modules are
  allocation-free.
- `core::option_f32` and `core::result_f32` use the same explicit variant
  flags for floating-point payloads. `Some(0.0)`, `Ok(0.0)`, and `Err(0.0)`
  remain distinct; inactive fields are zero. `contains` and `contains_err`
  use IEEE equality, so a stored NaN does not compare equal to any expected
  value, including NaN. Presence and success predicates still report the
  active variant, and unwrap helpers preserve a stored NaN. Both modules are
  allocation-free.
- `std::vec_i32`, `std::vec_u32`, `std::vec_u8`, `std::vec_i8`,
  `std::vec_u16`, `std::vec_i16`, and `std::vec_bool` own allocated 32-bit
  cells. The non-i32 modules access those cells through the currently available
  i32 raw-slice intrinsic and encode or decode values on read and write.
  `vec_u32` preserves every bit pattern;
  the narrow numeric modules preserve their full 8-bit or 16-bit range. The
  boolean module stores `false` as zero and `true` as one. All these values
  use four bytes of storage per element. `try_push` doubles capacity when full,
  starting at four elements. On allocation failure it returns the prior vector
  unchanged. Compare the returned length with the prior length to
  detect failure. `try_reserve` grows to the requested absolute capacity;
  compare the returned capacity with the request to detect failure. Invalid
  indices return the caller fallback or `false`, and invalid capacities leave
  the vector unchanged. `try_extend_from_slice` accepts a typed caller-backed
  view and count, grows capacity by the push doubling rule (or to the required
  size when larger), reserves before appending, and increases length by that
  count on success. Zero count changes nothing; negative count,
  capacity overflow, or failed allocation leaves the vector unchanged. For a
  positive count, compare lengths to detect success. The caller must back the
  full count, and the input must not alias the vector's storage because growth
  can move it. An i32 fixture confirms a physical input-length overclaim traps
  on x86. `try_insert` accepts an index from zero through the
  current length; invalid indices or allocation failure return the original
  vector unchanged. `try_remove` accepts an index below the current length;
  invalid indices return the original vector unchanged. Compare lengths to
  detect success. Insertion preserves order and may move the allocation;
  removal preserves order and keeps capacity. `try_pop` on an empty vector
  returns it unchanged; `clear` keeps its allocation. `destroy` releases
  storage. The caller must retain only the newest returned value, must call
  `destroy` once, and must not use aliases or copies after growth or
  destruction. These ownership rules are not yet checked by the language.
  Every concrete vector's `try_clone`
  leaves the source live and returns an independent allocation with capacity
  equal to the initialized length. Both vectors must be destroyed separately.
  An empty source clones without allocation; a nonempty source with an invalid
  raw cell or failed allocation yields an empty zero-capacity vector. Compare
  lengths to detect that failure. The 8-bit, 16-bit, and boolean vectors reject
  malformed raw cells before allocating; i32 and u32 accept every 32-bit cell.
- `std::set_i32` owns 32-bit cells and keeps each distinct item once, in
  insertion order. `try_insert` leaves duplicate items unchanged and grows
  capacity by doubling from four cells. A new item increases length by one on
  success; capacity overflow or allocation failure leaves the set unchanged.
  `try_remove` preserves the order of remaining items and decreases length
  only when the item existed. `at_or` returns the caller fallback for an
  invalid ordinal; use `len` to distinguish a stored equal value. Invalid
  `try_reserve` requests and failed reallocation leave the original set live.
  `try_shrink_to_fit` releases storage when empty, reduces capacity to length
  otherwise, and retains original storage and elements if reallocation fails.
  `try_clone` makes an independent copy or returns an empty zero-capacity set
  on allocation failure. The caller keeps only the newest returned owner and
  destroys each independent set once. These rules are not enforced by the
  language. `is_subset` and `is_disjoint` read their inputs without allocation.
  The four `try_` set-algebra operations return independent allocations,
  retaining left input order and then right input order for new items. They
  compute the full result size and reserve before writing, so failed
  allocation or capacity overflow returns an empty zero-capacity set rather
  than a partial result. An empty result can also be mathematically correct;
  callers expecting a nonempty result can detect failure with `len(result)`.
  The API requires x86_64 Linux allocator bindings.
- `std::map_i32_i32` stores distinct signed keys and signed values as adjacent
  32-bit cells. Insertion and removal preserve the order of remaining keys.
  `try_insert` adds a missing key and leaves an existing one unchanged;
  `try_set` updates only an existing key. A new key increases length by one on
  success, while capacity overflow or allocation failure leaves the map
  unchanged. `get_or` and ordinal access use caller fallbacks for missing
  keys and indices; use `contains_key` or `len` when a stored value could
  equal its fallback. `try_shrink_to_fit` releases empty storage or reduces
  capacity to length. Failed reallocation preserves all entries and the old
  capacity. `try_clone` returns an independent copy or an empty zero-capacity
  map on allocation failure. The caller keeps only the newest returned owner
  and destroys each independent map once. The API requires x86_64 Linux
  allocator bindings.
- `std::utf8_vec` stores canonical UTF-8 in `VecU8`. `try_append_scalar`
  validates the existing complete byte sequence, checks the scalar and
  capacity bound, and reserves storage for every encoded byte before writing.
  An invalid scalar, malformed existing text, capacity overflow, or allocation
  failure returns the original vector unchanged. Compare byte lengths before
  and after the call to detect failure. `try_append_scalars` validates one
  caller-backed scalar view, computes its total encoded size, and reserves
  once; construction runs in time linear in the old and new text lengths.
  `try_clone` validates the complete source text and makes an independent
  allocation, leaving the source live. Malformed text or allocation failure
  returns a new empty vector; a valid empty source clones without allocation.
  A nonempty clone succeeded when its byte length equals the source length.
  `try_append_codes` validates a complete caller-backed UTF-8 byte-code view,
  including that every cell is in `0..=255`, and reserves the full append
  before writing. Negative lengths, malformed input or existing text,
  capacity overflow, and allocation failure return the original vector
  unchanged. A zero-length valid append also returns it unchanged. Compare
  byte lengths to detect a nonempty append failure. Both input views must
  physically back their claimed counts and must not alias the vector
  allocation because growth can move it. `try_append_bytes` accepts a valid
  complete `[u8]` view directly, uses the byte vector's atomic batch append,
  and has the same failure and aliasing behavior. `try_insert_codes` accepts a scalar
  boundary from zero through the scalar count, validates the complete source
  and destination, and reserves all bytes before shifting and inserting. A
  valid zero-length insertion leaves text unchanged. Other invalid inputs and
  allocation failure also leave it unchanged; compare byte lengths for a
  nonempty insert. `try_insert_scalar`
  accepts scalar indices from zero through the scalar count and shifts whole
  encoded sequences after reserving space; invalid inputs or allocation
  failure leave the old vector unchanged. `try_remove_scalar` accepts only
  existing scalar indices, closes the byte gap without allocation, and keeps
  capacity for reuse. `try_remove_scalar_range` accepts a starting scalar
  boundary and a nonnegative count within the remaining scalars. It checks
  the complete text and removes all selected encoded bytes in one pass while
  retaining capacity. Invalid requests and valid zero-count ranges leave
  text unchanged; a nonempty successful removal reduces `byte_len`.
  `try_splice_codes` replaces any count of scalars at a valid scalar boundary
  with a complete caller-backed UTF-8 byte-code view. It covers insertion,
  removal, and replacement in one atomic edit. It checks both complete
  sequences, source byte range, scalar bounds, and final capacity before
  mutation; invalid input or allocation failure leaves the original text
  unchanged. The source must physically back its claimed length and must be
  disjoint from the vector allocation even when no growth is needed, because
  shifting could overwrite aliased cells. A valid empty splice is unchanged.
  `try_splice_bytes` applies these edit and failure rules to ordinary `[u8]`
  input; `try_insert_bytes` inserts it with a zero removal count. Both reject
  malformed source or destination text before changing storage. Native tests
  cover an input-length overclaim and injected reallocation failure.
  For equal-length replacement, inspect the selected text when success must
  be distinguished from failure.
  `try_replace_scalar` accepts only existing scalar
  indices, shifts bytes when the replacement width differs, and reserves
  before a growing edit. An equal-width replacement can succeed without a
  length change; read the selected scalar to distinguish it from failure.
  `try_pop_scalar` removes one complete final scalar.
  Removal and pop leave empty or malformed text unchanged. Read-only
  operations validate complete text, including bytes beyond a requested
  match; malformed inputs return false or the caller fallback. Sequence
  search returns byte offsets, while scalar search returns scalar indices.
  `std::vec_u8::data_ptr` is a borrowed pointer to its initialized 32-bit
  cells. A view built from it must not outlive the owner or survive growth or
  destruction. This is an x86_64 Linux allocation-backed API, separate from
  the allocation-free `core::utf8` codec and from host I/O.
- Half-open ranges exclude `end`; inclusive ranges include it. A reversed or
  empty range contains no values and overlaps no range. `RangeFrom<i32>` includes
  its start, `RangeTo<i32>` excludes its end, and `RangeFull` contains all i32
  values. `RangeTo<i32>` ending at `MIN` contains no i32 value. The u32 free
  functions and methods apply the same endpoint rules over `0..=u32::MAX`. A `RangeTo<u32>`
  ending at zero is empty; an inclusive range ending at `u32::MAX` includes
  that value.
- `core::wide_u64_range` uses the same endpoint rules over the full unsigned
  two-word domain. Half-open ranges exclude their upper endpoint even across
  the high-bit boundary; inclusive ranges include it. Equal half-open and
  reversed ranges contain nothing, and touching half-open ranges do not
  overlap. `RangeFrom` includes its start and `RangeTo` excludes its end.
  `full_contains` accepts every `WideU64` without constructing `RangeFull`.
- `core::wide_i64_range` applies those rules in signed two's-complement order.
  Its full-domain predicate accepts the signed minimum and maximum. A
  half-open range ending at the minimum is empty, while an inclusive range
  may include both extrema.
- `core::range_u8` accepts scalar byte bounds or concrete caller-owned range
  values. Half-open equal or reversed bounds are empty;
  inclusive equal bounds contain one byte and reversed bounds are empty.
  Touching half-open intervals do not overlap, while inclusive intervals
  sharing an endpoint do. `from_contains` includes its start, `to_contains`
  excludes its end, and `full_contains` is true for every `u8` value.
- `core::range_char` applies the same endpoint and overlap rules to Unicode
  scalar values. It provides concrete half-open, inclusive, from, and to
  aggregates and scalar predicates. The full-range predicate accepts every
  valid `char`; it does not construct or iterate character values.
- `core::range_f32` uses IEEE ordering. A NaN bound makes a bounded interval
  empty and unable to overlap. One-sided and bounded intervals never contain
  NaN, while `full_contains` includes NaN because it is unbounded. Signed
  zeros compare equal. Infinite endpoints are allowed: a closed singleton at
  positive infinity contains positive infinity; the corresponding half-open
  interval is empty. These helpers test membership and do not iterate values.
- `core::range_i8` applies the same endpoint rules across
  `-128..=127`. Half-open ranges exclude the upper endpoint even when it is
  `127`; inclusive ranges can contain both extrema. A to-range ending at
  `-128` is empty.
- `core::range_u16` and `core::range_i16` apply these rules across
  `0..=65535` and `-32768..=32767`. The unsigned inclusive range can contain
  `65535`; the signed inclusive range can contain both signed extrema. Each
  small-width module provides concrete half-open, inclusive, from, and to
  aggregates, with constructors, endpoint readers, and predicates. The
  `full_contains` scalar helper covers the full range without an aggregate.
- Slice callers supply `len` because source code cannot read slice metadata
  yet. `len <= 0` is empty for the safe fallback and accumulation helpers.
  `first_i32` traps on an empty view. `get_or_i32` returns the fallback for an
  index outside the supplied length; if the supplied length exceeds the actual
  view and indexing reaches beyond it, native execution traps with exit 101.
  `core::slice_u8`, `core::slice_i8`, `core::slice_i16`, `core::slice_u16`,
  and `core::slice_u32` use the same caller-supplied logical length for fixed
  byte, halfword, or word arrays. `first` traps on an empty physical view;
  `first_or`, `get_or`, and first/last search helpers return their
  fallback for empty, invalid, or absent positions. `set`, `swap`, rotation,
  insertion, append, and copy helpers reject invalid logical bounds without
  mutation. `copy_within` supports overlap; `copy_nonoverlapping_prefix`
  requires separate backing. `insert` and `push` need capacity within the
  physical view, and the caller increments its logical length after success.
  Search, fill, compaction, sort, and reverse treat nonpositive lengths as
  empty. Equality and prefix or suffix checks reject negative lengths.
  `compare_lexicographic` returns -2 for negative lengths; subsequence search
  returns -1 for invalid lengths or no match and treats an empty needle as a
  match at the first or final boundary. Binary search requires sorted input.
  Unsigned `sum` saturates at the element type's maximum. Signed narrow `sum`
  folds from left to right and clamps after each addition, so later negative
  values can lower an earlier saturated total. The physical backing
  must contain at least the claimed length, or native indexing can trap.
  String-backed and arbitrary raw byte views remain outside this claim.
  `core::slice_bool` provides access, mutation, copying, rotation, compaction,
  insertion, search, and sorting for the tested scalar element
  type `bool`. `get_or` returns its caller fallback for a negative
  length or out-of-range index. `set` returns false without writing for those
  invalid bounds. `fill` treats a nonpositive length as empty and returns the
  number of elements written. `swap` rejects invalid indices without writing.
  `copy_within` supports overlap and rejects invalid logical bounds before
  writing. `reverse` treats nonpositive lengths as empty and returns the
  logical length otherwise. `copy_prefix` copies the shorter of the two
  supplied nonnegative logical lengths and returns that count; a negative
  length returns -1 without writing. Its backing views must be distinct or
  start at the same element; other overlap is unsupported.
  `copy_nonoverlapping_range` requires disjoint backing and treats its
  destination length as writable capacity. Rotations accept amounts from zero
  through the logical length. Compaction returns a new length and leaves the
  tail unspecified; insertion and removal require the caller to update its
  logical length after success. Negative compaction lengths return -1 without
  writing. Empty prefixes and suffixes match valid views. Each operation can
  trap when a caller overstates the physical backing length and indexing
  reaches past it. `count_true` returns -1 for a negative length and zero for
  an empty view. `any` returns false for empty or invalid lengths; `all`
  returns true for an empty view and false for an invalid length. Searches
  return the caller's fallback index when absent or invalid. `equal` rejects
  negative or unequal lengths and accepts two empty views. `sort` puts false
  before true, returning false without writing for a negative length.
  Lexicographic comparison uses the same order; empty subsequences match at
  the first or final boundary. Binary bounds and searches validate sortedness
  and return the caller's fallback for an unsorted view. `partition_lt` places
  false values before true values when its pivot is true, returning -1 for a
  negative length without writing. A fallback can
  equal a stored value; callers that need a distinct success indication use
  `set` for mutation or validate the index separately for reading.
  `core::slice_char` operates on caller-backed character views and compares
  Unicode scalar values. It checks logical bounds for access and mutation,
  supports overlap within one view, and requires disjoint or same-start backing
  for prefix copying. `copy_nonoverlapping_range` requires disjoint backing
  and treats the destination length as writable capacity. Rotations accept
  amounts from zero through the logical length. Compaction returns a new
  length and leaves the tail unspecified; successful insertion and removal
  require the caller to update its logical length. A negative length returns
  -1 for compaction and partitioning, without writing. Empty subsequence
  searches return the first or final
  boundary; invalid lengths return false, -1, or the caller's fallback as
  documented by each function. Sort uses in-place heapsort, and binary bounds
  and searches validate that the input is sorted. An overclaimed physical
  length can trap when indexed. A direct fixed-array literal of character
  literals currently fails type checking; typed character variables work
  (dependency 48).
  `core::slice_f32` offers bounded access and mutation, fill, swap, overlap-safe
  in-place copy, disjoint range copy, rotation, reverse, prefix copy,
  compaction, insertion, search, equality, and left-to-right sum
  over caller-backed float views. Invalid indices return a fallback or false;
  a negative length makes `sum_or` return its fallback. Searches and equality
  use IEEE equality: NaN never matches, even against itself, while signed zeros
  compare equal. Thus adjacent NaNs remain distinct during compaction, a NaN
  target is never removed by `retain_not_equal`, and a subsequence containing
  NaN never matches. Empty subsequences match at the first or final boundary.
  Negative compaction lengths return -1 without writing, and rejected
  insertion or range copies leave the view unchanged. `sort_finite` checks
  the entire view first and returns false
  without writing for a negative length, NaN, or infinity. It sorts finite
  values ascending in place; signed zeros can appear in either order.
  `min_finite_or`, `max_finite_or`, and `compare_lexicographic_finite_or`
  inspect the complete logical view and return the caller's fallback for NaN,
  infinity, or invalid lengths; empty extrema also use the fallback.
  `partition_lt_finite_or` validates the finite pivot and entire view before
  writing, then returns the boundary before values at or above the pivot.
  Invalid input leaves the view unchanged and returns its fallback.
  `is_sorted_finite` checks the same finite precondition. Lower and upper bound
  helpers return the first index at least or greater than a finite needle;
  binary search returns the first or last matching index. They validate sorted
  finite input and return the caller's fallback for invalid views or needles.
  Physical backing overclaims can trap when indexed.
  `sum_i32` folds from left to right with saturating i32 addition, so each
  overflow clamps to `MIN` or `MAX` before the next element. Search helpers
  return the first or last matching index as named, or the caller's fallback.
  Empty extrema return the fallback. `is_sorted_i32` accepts equal neighbors;
  `lower_bound_i32` and `upper_bound_i32` require that order and return the
  insertion index before and after equal values respectively, including `len`
  when the insertion point is past the last element. A nonpositive length
  returns zero. `binary_search_first_or_i32` and `binary_search_last_or_i32`
  use the lower and upper bounds respectively, returning the first or last
  match or the caller's fallback. `partition_lt_i32` moves all values below a
  pivot ahead of values at or above it and returns their boundary. It does not
  preserve relative order; a nonpositive length returns zero without mutation.
  `set_i32` and `swap_i32` reject invalid indices without mutation.
  `fill_i32` returns the number of elements written, and `reverse_in_place_i32`
  returns the number of swaps. `copy_within_i32` handles overlap in either
  direction and rejects invalid source or destination bounds before writing.
  `copy_nonoverlapping_prefix_i32` copies the requested source prefix into a
  separate backed view, returns false without writing for negative lengths or
  insufficient destination length, and accepts an empty source. Its source and
  destination element ranges must not overlap in memory.
  `copy_nonoverlapping_range_i32` accepts source and destination offsets plus
  a count. It returns false before writing for a negative or out-of-range
  argument, accepts an empty range at either view's end, and requires the
  copied element ranges to be disjoint. The seven-argument imported call is
  exercised by the runtime fixture and `portable_window_checksum.lani`.
  `starts_with_i32`, `ends_with_i32`, and `equals_i32` compare elements in
  backed views; they treat negative lengths as empty.
  `compare_lexicographic_i32` returns -1, 0, or 1 after comparing the first
  differing element, then the lengths. `index_of_subslice_i32` and
  `last_index_of_subslice_i32` return the first or last contiguous match, or
  -1 when absent. An empty needle matches at index zero for the first search
  and at the logical view length for the last search; negative lengths count
  as empty. All three require valid backed views for any indexed element.
  `rotate_left_i32` and
  `rotate_right_i32` mutate in place and return false without writing unless
  `len >= 0` and `0 <= amount <= len`. Rotating an empty view by zero succeeds.
  `dedup_adjacent_i32` retains one element from each adjacent run;
  `retain_not_equal_i32` removes every matching element while preserving the
  rest in order. Both return the new logical length, or zero without writing
  for a nonpositive length. `remove_at_i32` shifts successors left and returns
  false without writing for an invalid index. After any of these operations,
  elements outside the new logical length are unspecified.
  `insert_i32` shifts a suffix right and writes at an index in `0..=len`;
  `push_i32` appends at `len`. Both require `0 <= len < capacity`, reject invalid
  bounds without writing, and return true when the caller should advance the
  logical length by one. The backed view must contain at least `capacity`
  writable elements; an overstated capacity can trap on native indexing.
  `sort_i32` uses an in-place heapsort in ascending order and returns the
  number of elements sorted, or zero for a nonpositive length. The backing
  array sees these mutations.
- `core::mem` raw-view construction borrows the backing array. The array must
  remain alive for every use of the view. The selected tests use stack-backed
  arrays and no allocator. These four intrinsics are compiler-provided, with
  no Lanius source bodies. Behavior on other targets remains unverified.
- `std::args_checked::argument_count_or` includes the executable at index zero
  and returns the caller fallback if the host reports fewer than one argument.
  `argument_len_or` returns a byte length without the terminating NUL, or the
  fallback for a negative or absent index or host failure. A fallback may
  equal a valid count or length. `read_exact_into` copies the selected argument's
  bytes into caller storage without a terminator. It checks the reported
  length before writing. An empty argument succeeds with a null buffer;
  rejected indices, capacity, and storage leave the buffer untouched. A host
  short read returns false and may leave a copied prefix.
- `std::env_checked::var_read_exact_into` uses a nonempty byte key supplied by
  pointer and length, then copies the value into caller storage without a
  terminator. A missing key, insufficient capacity, or invalid pointer/length
  returns false before writing. An empty value succeeds with a null buffer.
  A host short read returns false and may leave a copied prefix.
- `std::env_checked::var_key_read_exact_into` copies a complete nonempty key
  by index without a terminator. Missing or negative indices and invalid or
  insufficient storage return false before writing. A host short read can
  leave a prefix.
- `std::env_checked::current_dir_read_into` returns the directory path's byte
  count, excluding the trailing NUL written into caller storage on x86 Linux.
  It returns `-1` for invalid storage or capacity and host failure. A failed
  call may leave a prefix in storage.
- `std::time_checked` writes the native 16-byte seconds/nanoseconds timespec
  into caller storage for monotonic or system time. Null or short buffers and
  capacities above `i32::MAX` return false before a host call. Clock errors
  return false; storage contents after such an error are unspecified.
  `sleep_nonnegative_ms` rejects negative durations and returns false if the
  host sleep fails or is interrupted.
- `std::io::write_line` writes text followed by a newline and returns the
  combined byte count. A negative result from either host write is returned
  immediately. A partial text write is reported by its count, and the newline
  is attempted. The combined count saturates at `i32::MAX`. `println` and
  `eprintln` select stdout and stderr respectively.
  The focused host fixture also confirms that `write_i32` writes its decimal
  text and returns status `0`, while `write_byte` and `write_newline` return
  byte counts for the tested writes.
- `std::io_checked::read_exact_stdin` fills exactly the requested number of
  caller-buffer bytes, retrying short reads. EOF, a negative host result,
  zero progress, a null nonempty buffer, or a length above `i32::MAX` returns
  false. A failed read can leave a prefix in caller storage. Zero length
  succeeds without touching the pointer or stdin.
- `std::io_byte::read_stdin_byte_or` returns an integer in `0..=255` for a
  received byte, or the caller's separate EOF and host-error fallbacks. The
  caller should choose fallbacks outside the byte range. It uses a zeroed
  one-word stack cell and the low byte of the x86_64 host read. A result
  other than zero or one byte is treated as an error. `write_stdout_byte` and
  `write_stderr_byte` reject values outside `0..=255` without writing, and
  return false on host failure or a short write. No heap storage is used.
  The hex-to-decimal sample ignores ASCII whitespace, rejects invalid or
  overflowing input, and prints a decimal `u32` followed by a newline.
- `std::io_line::read_stdin_lf_line_into_i32` stores each byte before LF as an
  integer in `0..=255` and returns the count. An empty LF-terminated line
  returns zero; EOF before a byte returns `LINE_EOF` (`-1`), while EOF after
  bytes returns their count. A host failure returns `LINE_HOST_ERROR` (`-2`)
  and can leave a prefix. A negative capacity returns `LINE_INVALID_CAPACITY`
  (`-3`) without reading. An overlong line consumes through LF or EOF,
  preserves its first `capacity` bytes, and returns `LINE_TOO_LONG` (`-4`),
  so the next call starts at the next line. CR is retained, and NUL is a
  normal byte. `write_stdout_lf_line_from_i32` and
  `write_stderr_lf_line_from_i32` validate all codes before output, reject a
  negative length, and append LF even for an empty line. A host failure can
  leave an output prefix. Callers must provide backed views at least as long
  as the stated capacity or length; native indexing traps on an overclaim.
  The implementation uses one synchronous host call per byte.
- `std::io_utf8::read_stdin_scalar_or` returns one Unicode scalar or the
  caller's separate EOF, malformed-input, and host-error fallbacks. Choose
  distinct fallback values above `0x10FFFF` to distinguish all outcomes.
  A malformed sequence consumes the bytes already read, including any
  non-continuation byte; it does not retain an unread byte. A truncated
  sequence returns the malformed fallback, while the next call returns EOF.
  `write_stdout_scalar` and `write_stderr_scalar` reject invalid scalars
  before writing and return false on host failure; a valid encoding can leave
  a written prefix if a later byte write fails. `write_stdout_codes` and
  `write_stderr_codes` first validate the entire caller-backed `[i32]` byte
  view as UTF-8. Invalid sequences, codes outside `0..=255`, or negative
  lengths return false with no output; an empty view succeeds without output.
  Host failure returns false and can leave a written prefix. The stated length
  must not exceed the physical backing view or native indexing may trap.
  `write_stdout_bytes` and `write_stderr_bytes` apply the same validation and
  write behavior to caller-backed `[u8]` views. Their validation finishes
  before the first host write, including when a claimed length traps.
  There is no heap storage or user-program GPU target. Each byte uses one
  synchronous host call.
- `std::io_checked::{write_all_stdout,write_all_stderr}` retry short writes
  until all requested bytes are sent. They return false for invalid pointer
  or length arguments, negative host results, zero progress, or impossible
  host counts. A failed write can leave a visible output prefix. Zero length
  succeeds without touching the pointer or destination stream.
- `std::io_checked::read_to_end_stdin_into_buffer` reads through EOF into
  caller storage and returns the complete byte count, including zero for an
  empty stream. Capacity may be zero with a null pointer. Invalid arguments,
  host errors, impossible counts, and input longer than capacity return `-1`.
  Failure may leave a buffer prefix and consume one byte beyond capacity when
  probing for EOF.
- `std::io_checked::copy_stdin_to_stdout_with_buffer` requires a non-null
  caller buffer with capacity from 1 through `i32::MAX`. It reads until EOF,
  sends each chunk completely, and leaves both streams open. Empty input
  succeeds without output. Invalid storage, host errors, zero-progress writes,
  or impossible host counts return false; failure may leave an output prefix.
- `std::io_decimal::write_u32` writes the complete decimal representation without
  allocating or reading string storage. It uses `core::decimal` for each ASCII
  byte and returns a byte count from 1 to 10,
  the first negative host error, or `-1` if a byte write does not report
  exactly one byte. Failure may leave a decimal prefix on the handle.
- `std::io_decimal::write_i32` writes an optional minus sign followed by the
  full decimal magnitude through `core::decimal`. It returns 1 to 11 bytes,
  the first negative host error, or `-1` if a byte write does not report
  exactly one byte. A failure may leave a sign or decimal prefix. It handles
  `i32::MIN` without signed negation overflow.
- `std::io_decimal::{write_wide_u64,write_wide_i64}` write the complete
  decimal representation of the two-word 64-bit values through their
  portable formatters. They return 1 to 20 bytes, the first negative host
  error, or `-1` for a short write. Failure may leave a prefix. The native
  fixture checks both extrema, byte counts, and invalid handles; both
  decimal-double programs exercise full-width output.
- `std::io_decimal::{write_u8,write_u16,write_i8,write_i16}` widen their
  values and use the corresponding 32-bit writer. They return the complete
  decimal byte count or the first write error, and may leave a prefix on
  failure.
- `std::io_decimal::{read_u32_stdin_or,read_i32_stdin_or}` read through stdin
  EOF into one stack word, accepting surrounding SP, HT, LF, or CR and one
  leading sign (`+` for unsigned; `+` or `-` for signed). Zero `max_bytes`
  returns fallback without reading stdin. Empty, malformed, overlong, or
  overflowing input and host read errors return fallback; that value can
  also be a valid parsed number. Failure may consume an input prefix.
- `std::io_decimal::{read_wide_u64_stdin_or,read_wide_i64_stdin_or}` apply the
  same full-stream syntax and byte limit to the two-word 64-bit types. They
  accept leading zeros, reject values beyond the respective unsigned or
  signed range before multiplication can wrap, and return the supplied
  fallback for invalid input or host failure. They make no heap allocation and
  may consume an input prefix on failure.
- `std::io_decimal::{read_u8_stdin_or,read_u16_stdin_or,read_i8_stdin_or,read_i16_stdin_or}`
  apply the same syntax and byte limit, then reject values outside the narrower
  type with the caller's fallback. They consume the input through the 32-bit
  reader and return the fallback for malformed input or host errors too.
- `std::io_hex` writes the shortest lowercase or uppercase hexadecimal form
  of `u8`, `u16`, or `u32` without allocation. A successful call returns the
  number of bytes written. A negative host error is returned directly; a
  write reporting anything other than one byte returns `-1`. Failure can
  leave a hexadecimal prefix on the handle.
- `std::io_hex::{read_u32_stdin_or,read_u8_stdin_or,read_u16_stdin_or}` read
  all of stdin with a caller-supplied byte limit. They accept ASCII hex digits
  of either case, optional leading `0x` or `0X`, and surrounding SP, HT, LF,
  or CR. A sign, missing digit, embedded whitespace, overflow, input beyond
  the byte limit, or host read failure returns the caller's fallback. Narrow
  readers also reject values outside their type. Zero limit returns fallback
  without reading; other failures may consume an input prefix. The fallback
  can equal a valid parsed value.
- `std::io_hex_wide_u64` applies those write and bounded-read rules to
  `WideU64` values through `core::hex_wide_u64`. Successful writes return 1
  through 16 bytes. Host errors pass through; short writes return `-1` and
  can leave a prefix. The reader returns its caller's two-word fallback for
  malformed input, overflow, excess bytes, or host failure. Zero byte limit
  returns fallback without consuming stdin; other failures may consume a
  prefix. A valid input can equal the fallback.
- `std::io_binary_wide_u64` writes the shortest binary form of a two-word
  `WideU64` in 1 through 64 bytes, and reads bounded stdin with the same
  syntax as `std::io_binary`. Writes pass through negative host errors; a
  short write returns `-1` and may leave a prefix. The reader returns its
  caller fallback for malformed, overflowing, overlong, or failed input. A
  zero byte limit consumes nothing. A valid value may equal the fallback.
- `std::io_binary::{write_u32,write_u16,write_u8}` write the shortest ASCII
  binary representation without allocation. Success returns the byte count.
  A negative host error passes through; a write reporting anything other than
  one byte returns `-1`. Failure may leave a digit prefix on the handle.
- `std::io_binary::{read_u32_stdin_or,read_u16_stdin_or,read_u8_stdin_or}`
  read all stdin with a caller-supplied byte limit. They accept only ASCII
  `0` and `1`, an optional leading `0b` or `0B`, and surrounding SP, HT, LF,
  or CR. A missing digit, sign, embedded whitespace, overflow, input beyond
  the byte limit, or host read failure returns the caller's fallback. Narrow
  readers reject values outside their width. Zero limit returns fallback
  without reading; other failures may consume an input prefix. The fallback
  can equal a valid parsed value.
- Raw `std::fs::{open_read,open_write,open_append,remove_file,create_dir,remove_dir,rename}`
  on x86_64 Linux copy exactly the supplied path bytes into temporary
  NUL-terminated storage before making a syscall. Each path is limited to
  4095 bytes; a longer length returns `-36` (`ENAMETOOLONG`) before reading
  the pointer. A null pointer with nonzero length returns `-14` (`EFAULT`),
  and an embedded NUL returns `-22` (`EINVAL`). Empty paths reach Linux and
  return `-2` (`ENOENT`). Other syscall errors are returned as negative Linux
  errno values. The caller must provide readable storage for the declared
  length. `rename` checks each path independently. The string-based
  `open_read_path` and `open_write_path` use the same bounded runtime calls.
- `std::file::write_text_once` opens or creates a file, truncates it, attempts
  one text write, and attempts to close it even if writing fails. It returns the actual
  byte count on success, including zero for empty text; a negative open,
  write, or close result is passed through. A short write is reported by its
  count and is not retried.
- `std::file::read_once_into_buffer` opens an existing file and makes one read
  into caller storage. It returns the actual byte count, including zero at EOF
  and a short positive count when appropriate. A null buffer, zero capacity,
  or capacity above `i32::MAX` returns `-1` before opening the path. Open,
  read, and close failures return a negative result; close is attempted even
  after read failure. The caller must keep at least `capacity` writable bytes
  alive for the call.
- `std::file::read_exact_into_buffer` reads exactly the requested number of
  bytes into caller storage, retrying short reads. It returns false for invalid
  arguments, missing files, early EOF, read errors, or close errors. A failed
  call can leave a copied prefix in the buffer. Zero length still opens and
  closes the file; it accepts a null buffer and reads no bytes. Extra file
  bytes are not consumed.
- `std::file::read_to_end_into_buffer` reads until EOF and returns the complete
  byte count. It returns `-1` for invalid arguments, missing files, an input
  longer than capacity, or a read or close failure. A failed call may leave a
  prefix in caller storage. A full buffer is followed by a one-byte EOF probe;
  the probe does not write past caller storage. Zero capacity with a null
  buffer accepts only an empty file.
- `std::file::write_all_bytes` requires an open file handle and a buffer valid
  for `len` readable bytes. It retries short writes until all bytes are sent.
  A valid handle with zero length succeeds without reading the pointer.
  Invalid handles, a null nonempty buffer, lengths above `i32::MAX`, host
  failures, or a zero-progress write return false. A failed call may leave a
  written prefix in the file; it does not close the handle.
- `std::file::write_all_bytes_to_path` creates or truncates a path and writes
  all bytes from caller storage, then closes the handle. Invalid buffer or
  length arguments fail before opening and leave an existing file unchanged.
  A null buffer with zero length creates an empty file. Open, write, or close
  failure returns false; a failure after opening can leave a truncated file
  or written prefix.
- `std::file::copy_distinct_with_buffer` copies until EOF using caller storage
  and retries short writes. It returns false for invalid buffer arguments or
  any host failure. The destination can contain a copied prefix on failure.
  Source and destination must refer to different files, even through aliases;
  the current file ABI cannot check that precondition before truncation.
- `std::file::copy_file_to_stdout_with_buffer` opens an existing file, reads
  through EOF using a caller buffer, and sends each chunk completely to stdout.
  `copy_stdin_to_file_with_buffer` creates or truncates its destination and
  copies stdin through the same kind of buffer. Both require a non-null buffer
  and capacity from 1 through `i32::MAX`, attempt to close the file on later
  failure, and return false for invalid arguments or host errors. A failed
  copy may leave a visible output prefix or a truncated destination.
- `std::file::read_i32_decimal_or` reads a complete file of at most
  `max_bytes` bytes. It accepts ASCII digits with an optional leading sign and
  surrounding SP, HT, LF, or CR. Empty input, malformed input, overflow,
  overlong files, host failures, and a zero limit return the caller's fallback.
  A successful parsed value can equal that fallback. The reader uses one-byte
  reads into a stack word and uses `core::decimal` to check magnitude before
  multiplication. It does not depend on the raw host `read_i32` parser.
- `std::file::read_u32_decimal_or` has the same byte limit and whitespace
  rules, accepts an optional leading plus, and rejects a minus. It checks
  overflow through `core::decimal` before each digit. It returns the caller's
  fallback for malformed, empty, overlong, or inaccessible input and read or
  close failures. The fallback can also be a valid parsed value.
- `std::file::{read_wide_u64_decimal_or,read_wide_i64_decimal_or}` apply the
  same complete-file syntax and byte limit to two-word 64-bit values. They
  reject overflow before arithmetic can wrap, accept leading zeros, and
  always close a successfully opened handle. Open, read, or close failure,
  invalid input, and an overlong file return the caller's fallback, which can
  also be a valid parsed value.
- `std::file::write_i32_decimal` creates or truncates a file and writes the
  complete decimal representation of an i32 through `std::io_decimal::write_i32`.
  It returns false for open, write, or close failure and can leave a decimal
  prefix on failure. It handles `i32::MIN` without overflowing during
  negation and does not use the raw host `write_i32` formatter.
- `std::file::write_u32_decimal` writes the full unsigned decimal value and
  closes the file. Open, write, and close failures return false; a failed
  write can leave a decimal prefix.
- `std::file::{write_wide_u64_decimal,write_wide_i64_decimal}` write the
  portable two-word decimal representation and close the file even after a
  write failure. Open, write, or close failure returns false; a truncated
  file or decimal prefix can remain.
- `std::file::{read_u8_decimal_or,read_u16_decimal_or,read_i8_decimal_or,read_i16_decimal_or}`
  use the corresponding bounded 32-bit file reader, then reject values outside
  the narrower type with the caller's fallback. They inherit its syntax,
  open/read/close errors, and byte limit.
- `std::file::{write_u8_decimal,write_u16_decimal,write_i8_decimal,write_i16_decimal}`
  widen without changing the value and use the corresponding complete 32-bit
  file writer. Open, write, and close failure return false; a failure after
  opening may leave a truncated file or decimal prefix.
- `std::file_hex` writers create or truncate a file, write the shortest
  hexadecimal representation through checked byte writes, and close it.
  They return false on open, write, or close failure; failure after opening
  can leave a truncated file or digit prefix. Its bounded readers accept
  surrounding SP, HT, LF, or CR, one optional `0x` or `0X` prefix, and at
  least one digit. Missing, malformed, overlong, or overflowing input and
  read or close errors return the caller's fallback, which may also be a
  valid value. Narrow readers reject values above their type maximum.
- `std::file_binary` writers create or truncate a file, write the shortest
  binary representation through checked byte writes, and close it. They
  return false on open, write, or close failure; failure after opening can
  leave a truncated file or digit prefix. Its bounded readers accept
  surrounding SP, HT, LF, or CR, one optional `0b` or `0B` prefix, and at
  least one digit. Missing, malformed, overlong, or overflowing input and
  read or close errors return the caller's fallback, which can also be a
  valid value. Narrow readers reject values above their type maximum.
- `std::file_binary_wide_u64` applies the binary file rules to two-word
  `WideU64` values. `write` returns false on open, write, or close failure,
  possibly leaving a truncated file or digit prefix. `read_or` accepts at
  most the caller's byte limit, including whitespace and an optional prefix,
  and returns fallback for missing files, malformed or overflowing input,
  excess bytes, and read or close errors. A zero limit reads nothing; a valid
  value may equal fallback.
- `std::random_checked::fill_secure_exact` fills the requested caller-buffer
  length, retrying short reads. Zero length succeeds without touching the
  pointer. Null storage for a nonzero length, a length above `i32::MAX`, a
  host error, or zero progress returns false. A failed call can leave a
  random prefix in caller storage.
- `std::random_checked::secure_u32_or` fills four stack bytes through that
  helper and returns their native-order `u32` bit pattern. Failure returns
  the caller's fallback, which can also be a legitimate random output. Use
  `fill_secure_exact` when success must be distinguishable from that value.
  This wrapper relies on the x86 `core::mem::i32_array_data_ptr` intrinsic.
- `std::random_checked::secure_u32_below_or` uses rejection sampling to draw
  uniformly from `0..bound` without modulo bias. A zero bound or random-host
  failure returns the caller's fallback, which may also be a valid result.
  Bound one returns zero without host access. Larger bounds use the checked
  four-byte fill and may retry rejected words.
- `std::random_checked::{secure_u32_inclusive_or,secure_i32_inclusive_or}`
  draw uniformly from caller-supplied inclusive bounds. Reversed bounds
  return fallback, and singleton bounds return their value, both without host
  access. The complete 32-bit interval uses a direct checked four-byte draw;
  smaller intervals use rejection sampling. Signed intervals are mapped into
  unsigned order by XORing the sign bit before and after the draw. A host
  failure returns fallback, which can also be a valid random result.
- `std::random_checked::shuffle_i32` applies Fisher–Yates to a caller-backed
  i32 view using unbiased secure draws. It returns false without writing for
  a negative length; lengths zero and one succeed without host access. Host
  failure returns false and may leave a partially shuffled permutation. A
  caller-supplied length beyond the actual backing view can trap on indexing.

The checked random helpers report failure if the host call fails. The raw
`secure_u32` returns a full-width draw or traps on a short read or host error.
Use `fill_secure_bytes` or the checked helpers when failure must be recoverable.

The small runnable example is `sample_programs/portable_window_checksum.lani`.
It validates an ASCII marker, copies readings into a separate backed view,
sorts the copy, selects a half-open window from sorted-value boundaries, reads
the view, and accumulates with saturating arithmetic. It prints `96`.

`sample_programs/hex_packet_checksum.lani` validates a fixed byte packet's
header and hexadecimal payload with `core::slice_u8`, `core::range`,
`core::byte`, and `core::number_u32`. It prints the digit checksum `28`.

`sample_programs/path_extension_lowercase.lani` finds the final component of
a caller-backed byte path, ignores its trailing separator, lowercases its
extension using `core::byte`, and writes `txt` through checked byte output.
Its native execution test checks the exact output.

`sample_programs/fnv1a_stdin.lani` hashes every input byte with the portable
FNV-1a step and prints the lowercase hexadecimal result. Its native test checks
text, empty input, and binary bytes. A host read error exits with status 2;
write failures exit with status 3 or 4.

`sample_programs/wide_fingerprint.lani` reads one full-width unsigned decimal
line, compares it with 2^63, and prints the resulting order (-1, 0, or 1)
beside its stable two-word FNV-1a hash. The native test checks zero, values
above 32 bits, the high-bit boundary, the unsigned maximum, malformed and
overflowing input, and empty input.

`sample_programs/halfword_window_total.lani` sorts six unsigned halfword
readings, selects an inclusive value range, checks its first match through
an Option returned by its local search helper and concrete Result helpers,
then accumulates the selected values with
saturation. It combines five portable modules and prints `32786`.

`tests/fixtures/stdlib_foundation/wide_u64_decimal_double.lani` reads one
bounded decimal line, doubles its two-word value modulo 2^64, and prints the
full-width result. Its x86 test checks zero, a value above `u32::MAX`, the
high bit, the unsigned maximum, malformed and overflowing input, empty input,
and an overlong line.

`tests/fixtures/stdlib_foundation/wide_i64_decimal_double.lani` reads one
bounded signed decimal line, doubles its two-word value modulo 2^64, and
prints the signed result. Its x86 test checks zero, negative zero, negative
values, values beyond the 32-bit range, both signed extrema, overflow,
malformed input, empty input, and an overlong line.

`sample_programs/wide_checked_factorial.lani` reads a bounded unsigned count,
computes its factorial through `core::wide_u64_checked::checked_mul`, and
prints the full-width decimal result. Its x86 test checks `0!`, `5!`, and
`20!`, as well as `21!` overflow, malformed input, and an overlong input.

`sample_programs/character_inventory.lani` sorts six Unicode scalar values,
finds an ASCII letter range, and counts its members. It combines five portable
modules and prints `3`.

`sample_programs/floating_window_total.lani` sorts finite readings and searches
them through `core::slice_f32`, sums and checks them against an inclusive
`core::range_f32` interval, clamps them, and carries the result through
`OptionF32`. It prints the matched reading's index, `2`, after verifying the
floating total is `7.0`. Floating-to-integer conversion remains a compiler
dependency; see item 43 below.

`sample_programs/vector_square_sum.lani` uses the allocation-backed vector,
checked push length, bounded indexed reads, saturating arithmetic, and native
integer output. It prints `285` and releases its storage.

`sample_programs/vector_edit_checksum.lani` appends a caller-backed batch,
inserts and removes readings from an ordered i32 vector, checks the resulting
lengths, computes a saturating checksum, carries it through `OptionI32`,
prints `19`, and releases storage.

`sample_programs/vector_byte_checksum.lani` stores bytes in `std::vec_u8`,
checks every push, reads them through a bounded accessor, combines them with
`core::byte` arithmetic, and uses `OptionU8` for its result. It prints `4` and
releases its storage.

`sample_programs/utf8_text_report.lani` validates ordinary UTF-8 bytes,
builds `A¢A¢B` in an owned UTF-8 vector, searches Unicode scalars, writes its encoded bytes, and
prints the scalar count. The native fixture checks exact output
`A¢A¢B5\n` and releases its storage.

`sample_programs/utf8_owned_line.lani` reads one bounded LF line, validates
its UTF-8 byte codes, copies them into an owned text vector, appends a
four-byte smiley, and prints the text with its scalar count. It checks both
allocation-backed appends, releases the vector on every path after creation,
and returns distinct statuses for input, encoding, allocation, and output
failures. The focused native test runs multibyte, empty, malformed, overlong,
and EOF inputs.

`sample_programs/vector_signed_byte_sum.lani` stores signed bytes in
`std::vec_i8`, checks every push, reads them through a bounded accessor,
combines them with `core::number_i8` arithmetic, and uses `OptionI8` for its
result. It prints `1` and releases its storage.

`sample_programs/vector_halfword_checksum.lani` and
`sample_programs/vector_signed_halfword_sum.lani` exercise the unsigned and
signed 16-bit vectors with wrapping arithmetic and the corresponding concrete
Option modules. They print `4` and `1`, respectively, and release storage.

`sample_programs/vector_true_count.lani` stores true and false values in
`std::vec_bool`, counts them through `core::bool`, and checks the result through
`OptionBool`. It prints `2` and releases storage.

`tests/fixtures/stdlib_host/std_utf8_line_count.lani` is a second runnable
program. It reads one LF line into a 16-byte caller-backed view, validates and
counts its Unicode scalars, and prints the count in decimal. The focused x86
test runs ASCII, multibyte, NUL, empty, and unterminated valid lines, plus
malformed UTF-8, overlong input, and EOF failure cases. It returns a distinct
nonzero status for line input, UTF-8, decimal output, and newline output
failures.

`tests/fixtures/stdlib_host/std_utf8_line_append.lani` exercises text
construction across modules. It reads one LF line, validates UTF-8, appends a
four-byte scalar within reserved caller storage, and prints the resulting text
and scalar count. `tests/stdlib_io_utf8_execution.rs` runs it on x86_64 Linux
with multibyte, empty, exact-capacity, malformed, overlong, and EOF input.

## Target support and focused verification

| Target / path | Status |
| --- | --- |
| x86_64 Linux ELF | Executable subset above, checked by `tests/stdlib_foundation_execution.rs`. |
| GPU-resident compiler frontend and x86 codegen | Used to compile each runtime fixture. This is compiler execution on a GPU, not a user-program GPU target. |
| User GPU target / `std::gpu` | No executable user GPU API is exposed. |
| Wasm | Not claimed or required for this foundation. |

Run the focused gate with `cargo test --test stdlib_foundation_execution`.
Run `cargo test --test stdlib_char_array_literal_execution` for direct
Unicode character arrays through imported slice helpers and type rejection.
Run `cargo test --test stdlib_wide_u64_bits_execution` for every public
two-word bit helper, including rotation boundaries and invalid-index fallbacks.
Run `cargo test --test stdlib_hex_wide_u64_execution` for full-width
hexadecimal formatting, bounded parsing, fallbacks, and native bounds trapping.
Run `cargo test --test stdlib_binary_wide_u64_execution` for full-width
binary formatting, bounded parsing, fallbacks, and native bounds trapping.
Run `cargo test --test stdlib_wide_u64_range_execution` for the full-width
unsigned range forms, their receiver methods, and endpoint boundaries.
Run `cargo test --test stdlib_wide_i64_range_execution` for the signed
two-word range forms, methods, negative ordering, and both extrema.
Run `cargo test --test stdlib_wide_i64_bits_execution` for the signed
two-word bit view, including negative patterns and sign-bit rotations.
Run `cargo test --test stdlib_signed_bit_report_program` for a real program
combining signed parsing, bit operations, and decimal output.
Run `cargo test --test stdlib_bitset_execution` for the caller-backed bitset,
including the word-boundary matrix and native bounds trap.
Run `cargo test --test stdlib_base64_execution` for strict caller-backed
Base64 encoding and decoding, all byte values, and native bounds trapping.
Run `cargo test --test stdlib_crc32_execution` for streaming and caller-backed
CRC-32/ISO-HDLC, known vectors, all byte values, and native bounds trapping.
Run `cargo test --test stdlib_wide_u64_execution` for all two-word 64-bit
operations, full-width decimal parsing and output, the decimal-double program,
high-bit edge cases, and generated differential arithmetic cases.
Run `cargo test --test stdlib_wide_i64_execution` for signed two-word 64-bit
operations, full-width signed decimal parsing and output, the decimal-double
program, edge cases, and generated differential arithmetic cases.
Run `cargo test --test stdlib_option_result_wide_u64_execution --test stdlib_option_result_wide_i64_execution` for the concrete two-word optional
and result variants, including every public function and imported aggregate
returns.
Run `cargo test --test stdlib_wide_u64_checked_execution --test stdlib_wide_i64_checked_execution` for the checked and saturating two-word
arithmetic, differential native comparisons, and the checked-factorial
program.
Run `cargo test --test stdlib_endian_execution` for caller-backed endian
fields, a packet-header sample, and native bounds trapping.
Run `cargo test --test stdlib_varint_execution` for caller-backed canonical
varints at both widths, the frame-sum program, and native bounds trapping.
Run `cargo test --test stdlib_varint_signed_execution` for signed ZigZag
round trips, both signed extrema, and the signed frame-sum program.
Run `cargo test --test stdlib_cmp_execution` for local trait method dispatch,
imported `core::cmp` free calls, and `core::hash::hash_i32` through its local
trait implementation.
Run `cargo test --test stdlib_ordering` for imported `Ordering` values and
comparators over six integer widths, Boolean values, Unicode characters, and
f32 values with an explicit NaN fallback.
Run `cargo test --test stdlib_ordering_wide` for the two-word signed and
unsigned 64-bit comparators, including high-bit values and signed extrema.
Run `cargo test --test stdlib_wide_fingerprint_program` for the stdin program
combining wide parsing, ordering, hashing, and checked output.
Run `cargo test --test stdlib_mem_execution` for all public memory helper
functions, including capability metadata, value helpers, and intrinsics.
Run `cargo test --test stdlib_allocator_metadata_execution` for allocator
capability metadata and live pointer classification.
Run `cargo test --test stdlib_generic_vec_flat_execution` for empty generic
vector operations, including imported `--stdlib-root` calls and flat source
packs. Storage and mutation for generic vectors remain unavailable.
Run `cargo test --test stdlib_generic_interface` for exported generic
Option/Result types and associated methods on both plain and generic structs.
Run `cargo test --test stdlib_time_execution` for clock metadata, the four
bound host calls, checked wrappers, and injected host failures.
Run `cargo test --test stdlib_cast_store_execution` for direct indexed byte
casts and the i32 and byte-slice store paths.
The test compiles small Lanius programs through `--stdlib-root`, executes
the native ELFs, checks their exit status, checks the example's stdout, and
checks the slice bounds trap. Each source is also suitable for direct CLI
compilation with `laniusc --stdlib-root stdlib --emit x86_64 -o OUTPUT SOURCE`.
Run `cargo test --test stdlib_allocator_failure_execution` and
`cargo test --test stdlib_vec_i32_execution` for native allocation failures;
fault injection runs when Linux `strace` is available.
Run `cargo test --test stdlib_vec_truncate_execution` for all seven concrete
vectors' prefix preservation, invalid lengths, retained capacity, and reuse.
Run `cargo test --test stdlib_vec_resize_execution` for growth, fill,
shrinkage, invalid lengths, and an injected reallocation failure.
Run `cargo test --test stdlib_vec_shrink_execution` for all seven concrete
vectors' capacity release and an injected shrink reallocation failure.
Run `cargo test --test stdlib_map_i32_i32_execution` for the owned map,
initial, growth, shrink, and clone allocation failures, and the stdin byte
histogram.
Run `cargo test --test stdlib_set_i32_execution` for the owned integer set,
set algebra, and its initial, growth, shrink, clone, and four set-algebra
allocation failures.
Run `cargo test --test stdlib_fs_read_i32_execution` for the raw signed
integer reader's normal values, signed limits, overflow, line boundaries,
empty lines, EOF, and an injected host read error when `strace` is available.
Run `cargo test --test stdlib_io_write_i32_execution` for the raw signed
integer writer's zero and signed-endpoint output, short-write retry,
zero-progress failure, and host error behavior.
Run `cargo test --test stdlib_host_execution` for the separate native I/O
wrappers; its partial-write fault cases run when Linux `strace` is available.
Run `cargo test --test stdlib_io_decimal_input_execution` for bounded decimal
stdin reads; fault injection cases run when Linux `strace` is available.
Run `cargo test --test stdlib_io_hex_execution` for hexadecimal stream input
and output; its host-failure cases run when Linux `strace` is available.
Run `cargo test --test stdlib_io_hex_wide_u64_execution` for full-width
hexadecimal stream input and output, limits, and injected host faults.
Run `cargo test --test stdlib_io_binary_execution` for binary stream input
and output; its host-failure cases run when Linux `strace` is available.
Run `cargo test --test stdlib_io_binary_wide_u64_execution` for full-width
binary stream input and output, limits, and injected host faults.
Run `cargo test --test stdlib_io_checked_execution` for complete caller-buffer
stream operations; fault injection cases run when Linux `strace` is available.
Run `cargo test --test stdlib_io_byte_execution` for scalar binary I/O and the
hex-to-decimal sample; fault injection cases run when Linux `strace` is available.
Run `cargo test --test stdlib_io_line_execution` for bounded LF line I/O;
fault injection cases run when Linux `strace` is available.
Run `cargo test --test stdlib_io_utf8_execution` for scalar UTF-8 stream I/O;
fault injection cases run when Linux `strace` is available.
Run `cargo test --test stdlib_file_execution` for the file wrappers; its
read/write/close fault cases run when Linux `strace` is available.
Run `cargo test --test stdlib_file_hex_execution` for hexadecimal file input
and output; fault cases run when Linux `strace` is available.
Run `cargo test --test stdlib_file_binary_execution` for binary file input
and output; fault cases run when Linux `strace` is available.
Run `cargo test --test stdlib_file_binary_wide_u64_execution` for full-width
binary file I/O, bounds, and injected host failures.
Run `cargo test --test stdlib_path_execution` for the lexical path predicates.
Run `cargo test --test stdlib_utf8_bytes_execution` for direct `[u8]` UTF-8
validation, owned text append, the text-report sample, native bounds trapping,
and injected allocation failure when Linux `strace` is available.
Run `cargo test --test stdlib_random_execution` for the checked random scalar;
the failure injection cases run when Linux `strace` is available.

## Compiler/runtime dependencies and minimal reproductions

These reproductions concern the GPU-based `laniusc` compiler and its target
runtime, chiefly under `crates/laniusc-compiler` and `shaders`. The separate
`verified_compiler` and Lean workstream verifies a Lanius compiler; it is not
the owner of these GPU compiler or x86 runtime fixes. This stdlib worktree
also fixes the imported struct-return relocation path described below.

1. **Generic Option/Result native lowering.** `laniusc check --stdlib-root
   stdlib tests/fixtures/stdlib_foundation/repro_generic_option.lani` succeeds.
   Interface export now resolves `Some(T)`, `Ok(T)`, and `Err(E)` against their
   parent enum parameters; `tests/stdlib_generic_interface.rs` checks the
   exported records from the real modules. Native emission reaches lowering
   but stops with `LNC0017`, unsupported target opcode 8 (alias). The enum
   layout pass requires concrete payload types, while these definitions still
   contain generic `T` and `E`; a fixed one-word assumption would miscompile
   wider instantiations. This blocks executable generic Option/Result modules.
   `repro_i64_min_import.lani` shows a second effect: a call to the ordinary
   scalar helper `core::i64::min(2, 3)` passes GPU `check`, but native emission
   stops with `LNC0017` at the transitively imported generic `Result<T, E>`
   enum. The complete `core::i64` module cannot be treated as executable even
   for small scalar arguments before generic enum lowering is fixed; native
   full-width i64 behavior also needs dependency 11.
   The 8- and 32-bit checked numeric helpers now return concrete Option structs.
   `repro_generic_enum_only.lani` with its three-line `Maybe<T>` dependency
   narrows the failure to generic enum construction: native emission stops in
   GPU lowering before x86 output. The local
   `repro_generic_enum_local_scalar.lani` and
   `repro_generic_enum_local_wide.lani` both pass GPU `check` and both report
   `LNC0017` for native output. Each fixture checks construction and matching
   by returning zero on the expected payload. A reverted layout experiment
   treated every generic payload as one word: the scalar case then exited zero, but
   the two-word `Pair` case compiled and exited one. That representation is
   unsafe; generic enum layout must account for the concrete type argument
   before these APIs can be claimed. The imported scalar reproducer also
   reached an optimizer failure (`LNC0057`) under that experiment, so layout
   alone is not the remaining compiler work.
   `repro_generic_payload_struct_wide.lani` also compiles a two-word `Pair`
   through `Maybe<T>` as a generic struct, but the native ELF exits 1 instead
   of 0. A struct representation is therefore not a safe source-level
   workaround for the generic enum layout failure. The former by-value
   `core::option::replace(value, next)` always returned `Some(next)` without
   changing `value`; it was removed rather than retained as a misleading
   mutation API. A real replacement operation needs a mutable Option receiver
   and executable generic enum behavior.
2. **Imported aggregate results: struct and flat-payload enum returns fixed.**
   `tests/stdlib_imported_aggregate_execution.rs` now compiles and executes
   imported one-, two-, and three-word struct constructors and consumers on
   x86_64. The object relocation pass previously guessed the call instruction
   width and patched its `rel32` field three bytes early, corrupting the
   caller's prologue. It now shares the exact byte count with code emission and
   recognizes imported nominal aggregate results without treating scalar
   results as aggregates. A later `repro_vec_get_empty.lani` showed imported
   scalar calls inheriting an enclosing struct's word count and shifting all
   their arguments by one ABI register; x86 call counting, scattering, and
   stack allocation now use the checked result type to exclude that width.
   Both fixes support the concrete Option/Result and vector modules. The
   enum case now reads imported variant signatures and retains the
   discriminant plus the maximum supported payload width as aggregate
   storage. `tests/fixtures/stdlib_foundation/repro_enum_payload_app.lani`
   executes absent, single-scalar, and two-scalar variants through separate
   library calls, including a three-word return;
   `tests/fixtures/stdlib_foundation/repro_ordering_return.lani` exits 0 and
   `tests/stdlib_imported_aggregate_execution.rs` guards the calling
   convention. The imported `Wrapped::Payload(Pair)` fixture checks a flat
   two-field struct inside an enum variant through a separate-library call.
   Deeper nested aggregate payloads still need exact projected widths before
   they can be claimed. The current `core::ordering` public API executes;
   `compare_i64` was removed until dependency 11 is fixed, and the qualified
   variant issue in dependency 34 has been resolved.
   Concrete small-width range aggregates and their imported constructors,
   readers, and predicates now execute in dedicated fixtures. Adding the same
   functions to generic `core::range` still makes its existing `range_full()`
   return fail x86 lowering with `LNC0017` (no canonical ABI layout); see
   dependency 38. The concrete per-width modules keep that working generic
   module unchanged.
3. **Portable slice construction and metadata.** The four `core::mem` pointer
   and view helpers are compiler-injected intrinsics with no Lanius source
   bodies. X86 lowering passes the backed-view fixture, and an existing Wasm
   byte-write test passes for `i32_array_data_ptr`; no full cross-target
   behavioral claim follows from those checks. A portable slice constructor
   and a way to read slice length are still needed before slice APIs can be
   independent of caller-supplied lengths.
4. **Generic allocation-backed vectors remain blocked.** The old `std::vec`
   silently dropped values in `push`, so that stub was removed. The empty
   generic `Vec<T>` has executable imported associated `new`, `len`, and
   `is_empty` methods with `i32` and `bool` instantiations. Its three free
   constructor also executes through an imported, annotated result. The free
   `len` and `is_empty` functions now infer scalar type arguments from imported
   `Vec<T>` values. `std::vec_i32`,
   `std::vec_u32`, `std::vec_u8`, `std::vec_i8`, `std::vec_u16`, and
   `std::vec_i16`, and `std::vec_bool` have tested storage, growth, mutation, failure, and
   destruction on x86 Linux.
   `tests/fixtures/stdlib_foundation/repro_vec_generic_associated_new.lani`
   compiles and executes through `--stdlib-root`. The free constructor also
   executes when its result has an explicit `Vec<T>` annotation. Imported free
   `len` and `is_empty` infer `T` from `Vec<i32>` or `Vec<bool>` arguments;
   `repro_vec_generic_free_new.lani` executes all three free functions through
   normal imports. All six forms also compile and run in one flat source pack.
   The former vector service metadata also incorrectly reused runtime service
   ID 13, which is the test harness. It was removed: the concrete vectors
   depend on the allocator service, while generic layout is a compiler
   dependency rather than a missing host service.
   A generic collection still needs executable generic value layout and a
   language-level move/borrow rule to enforce ownership rather than relying
   on caller discipline.
5. **Resolved: imported f32 constant lowering.** The GPU compiler now records
   compact HIR float literal bits in its exported constant metadata. The
   original `repro_f32_const.lani` exits 0 instead of 3. The executable
   `tests/stdlib_f32_imported_constants_execution.rs` also checks imported
   negative and computed constants and both signs of zero. The real
   `core::f32::ONE` is covered by `core_f32.lani`.
6. **Resolved: native assertion lowering.** `repro_assert_pass.lani` imports
   `test::assert` and calls each of its eight public functions with passing
   inputs. The x86 compiler now calls a shared runtime assertion routine.
   `tests/stdlib_assert_execution.rs` executes every passing helper and every
   failed condition; failure raises SIGILL instead of returning. The former
   unsupported target LIR opcode 38 is resolved for the assertion intrinsic.
7. **Fixed-array results.** `repro_array_i32_4_return.lani` imports
   `core::array_i32_4::copy` from the isolated
   `repro_array_i32_4_return_root` and accesses its returned array. Native
   emission succeeds, but the minimal ELF exits 1 instead of 0. The real
   `core::array_i32_4` and legacy source library now offer executable
   caller-backed `copy_into`, `fill`, and `reverse_into` in place of the three
   array-returning functions. The imported struct-return repair in dependency
   2 does not cover fixed arrays.
   `repro_local_array_return.lani` shows that a local source-level copy also
   returns wrong values: it passes type checking and emits an ELF, but that
   ELF exits 1 instead of 0. Source inclusion does not avoid the array-return
   compiler bug; the legacy module also removed those functions. The x86
   disassembly shows a layout mismatch: fixed i32 arrays hold packed 32-bit
   elements at increasing addresses, while aggregate return rows copy 64-bit
   words toward decreasing addresses. The subsequent local copy also needs
   the checked array shape to select the right destination layout; a width-only
   special case changes the wrong copy when a literal precedes the call.
8. **Resolved: native numeric module imports.** The `core::{i32,u8,u32}`
   modules now return concrete `OptionI32`, `OptionU8`, and `OptionU32` from
   checked operations, avoiding unsupported generic enum lowering.
   `repro_numeric_powers.lani` and the three full-module fixtures compile
   through the real stdlib root and execute on x86_64. Power-of-two guards
   return zero or false when the next positive power is unrepresentable.
   The byte multiplication helpers now use `core::byte` so overflow cannot
   silently corrupt a saturating or wrapping result.
9. **Resolved: imported stdio metadata return.**
   `tests/fixtures/stdlib_host/repro_std_io_abi.lani` now compiles and exits
   zero through the native path. The foundation runtime fixture executes every
   `std::io` metadata function, and the public wrapper and raw host tests
   exercise the I/O operations.
10. **Resolved in the current compiler: imported no-argument scalar returns.**
    With `--stdlib-root tests/fixtures/stdlib_host/repro_path_no_arg_root`,
    `repro_path_byte_return.lani` and `repro_path_capability_return.lani` now
    compile and execute with exit zero. `tests/stdlib_path_execution.rs` keeps
    executable regression coverage for both imported byte and Boolean returns.
    The redundant public `std::path` functions were removed earlier; its 37
    lexical functions and constants retain their own runtime tests.
11. **Native i64 literal and comparison lowering.**
    `tests/fixtures/stdlib_foundation/repro_i64_compare.lani` compares
    an i64 value of `4,611,686,018,427,387,904` with `1,073,741,824`. Native emission
    succeeds, but the ELF exits 1 because it evaluates the large positive
    value as smaller. Disassembly of this ELF shows a 32-bit immediate
    (`0x12e0be82`) for the large literal and a 32-bit `cmp`, so widening only
    the comparison instruction would leave the input value wrong. A proposed
    portable `number_i64` module was removed
    after this executable check; signed 64-bit numeric APIs cannot be claimed
    working from current native test results. The former
    `core::ordering::compare_i64` also produced the wrong order
    for values above 32 bits and was removed from the executable surface.
12. **Const-generic array indexing.**
    `tests/fixtures/stdlib_foundation/repro_array_i32_generic.lani` calls
    `core::array_i32::first` on a four-element array. Native emission stops
    with `LNC0017` at `values[0]` in the const-generic helper, so the generic
    array module remains contract-only; the concrete `core::array_i32_4`
    scalar functions have separate executable tests. A source-level attempt
    to form a bounded slice from the array pointer needs the length as a
    value. `repro_array_i32_const_value.lani` shows that `N as i32` inside a
    const-generic function fails GPU checking with `LNC0005` (unresolved
    identifier). Fixed arrays also lack a callable `values.len()` method
    (`LNC0027`). Neither route currently gives a safe source-level
    replacement for generic array indexing. For comparison, a temporary
    four-element-only slice length compiled and the reproducer exited 7,
    confirming the pointer and slice intrinsics work for that concrete case;
    that hard-coded length was not retained in the generic API.
13. **Resolved: raw host integer read overflow.** The native
    `std::fs::read_i32(handle, fallback)` parser now accumulates magnitude in
    64 bits and returns the fallback above `i32::MAX` or below `i32::MIN`.
    `tests/stdlib_fs_read_i32_execution.rs` runs the original overflow
    reproduction and checks ordinary positive and negative values, both
    signed endpoints, positive and negative overflow, a long digit sequence,
    a following valid line, empty lines, a sign without digits, EOF, and an
    injected host read error.
14. **Direct slice literals.**
    `tests/fixtures/stdlib_foundation/repro_i32_slice_literal.lani` creates
    `[i32] = [3, 5]` and reads both elements. Native emission succeeds, but
    the ELF exits 101 from a bounds trap on the first read. The same result
    occurred for a `[bool]` literal. A view built from backing array storage
    with `core::mem::i32_slice_from_raw_parts` indexes correctly, so public
    slice APIs remain limited to valid backed views.
15. **Borrowed string length.**
    `tests/fixtures/stdlib_foundation/repro_string_length.lani` calls
    `text.len()` on a `str` value. `laniusc check --stdlib-root stdlib` reports
    `LNC0027`: no method matches this receiver. A borrowed UTF-8 string
    module needs executable length metadata to bound every read.
16. **Byte access to borrowed string storage.**
   `tests/fixtures/stdlib_foundation/repro_u8_string_slice.lani` takes
   `core::mem::string_data_ptr("Az")`, constructs a two-byte `[u8]` view,
   and returns `bytes[1]`. Native emission succeeds, but the ELF exits 245
   instead of the ASCII value 122 for `z`. Thus even with a caller-supplied
   length, byte iteration cannot be claimed executable from this pointer and
   view combination. A second reproduction,
   `repro_u8_array_raw_slice.lani`, constructs a raw byte view over an i32
   stack array containing known little-endian bytes; native execution exits 1
   because `bytes[2]` is not the expected value 65. Both minimal reproductions
   are recorded here for the GPU compiler work.
17. **Integer-to-character cast.**
    `tests/fixtures/stdlib_foundation/repro_u32_to_char.lani` returns a
    `u32` value as `char`. Native compilation reports `LNC0006`: the return
    context expects `char` but still sees `u32`. `core::char` uses explicit
    ASCII mappings for executable case conversion, while general conversion
    from a Unicode scalar to `char` remains a GPU compiler dependency.
    `repro_i32_to_char.lani` shows the same `LNC0006` for an `i32` source;
    that conversion is needed to read a character vector backed by the
    currently available 32-bit raw-slice intrinsic. These reproductions are
    recorded here.
18. **Resolved: raw secure random scalar failure channel.** The x86 runtime
   bytes for `std::random::secure_u32` previously returned `0xFFFFFFFF` when
   the `getrandom` syscall did not return four bytes. That bit pattern is a
   valid random `u32`, so the failure was ambiguous. The runtime binding now
   traps with `ud2` on a short read or host error. The focused native test
   executes a successful draw and injects both `EIO` and a two-byte read,
   checking for SIGILL. Callers needing a recoverable error can use the signed
   status from `fill_secure_bytes` or the Lanius `std::random_checked` wrappers.
19. **Transitive host import loses the native entrypoint.** With
    `--stdlib-root tests/fixtures/stdlib_foundation/repro_transitive_host_root`,
    `repro_transitive_host_direct.lani` emits an x86_64 ELF that exits zero.
    `repro_transitive_host_import.lani` type-checks with the same root, but
    native emission reports `LNC0017: missing main entrypoint` at the
    transitive `std::process` source. It calls the same bound exit operation
    through `test::probe`; the adjacent small sources reproduce the issue.
    `repro_imported_direct_exit.lani` also type-checks but fails native
    emission with the same error when its imported helper declares the host
    exit operation directly. This rules out that Lanius-source workaround and
    blocks a source-level `test::assert` with a terminating failure path.
20. **Resolved: imported non-i32 slice arguments from fixed arrays.** The
    dependency call validator now accepts the same fixed-array-to-slice
    conversion used for local calls, and checks the element type throughout
    the interface type tree. `tests/imported_concrete_method_execution.rs`
    compiles and executes the original `[u8]` and `[u32]` imported-helper
    reproductions and rejects an `[i32]` argument to an imported `[u8]`
    helper. `core::slice_u8` exercises the imported byte-slice path
    across reads and mutations. The raw-view behavior in dependency 16 is a
    separate obstacle.
21. **Resolved: raw signed integer short writes.** The native
    `std::io::write_i32` routine now advances its output pointer by the host
    byte count and retries until the whole decimal representation is written.
    It returns zero only on completion; zero progress returns failure and a
    negative host error remains negative. `tests/stdlib_io_write_i32_execution.rs`
    checks zero, ordinary values, both signed endpoints, and injects a
    one-byte write, zero progress, and `EIO`. The short-write trace contains
    two write syscalls and a successful
    return. `strace` simulates the first byte count without copying that byte,
    so its injected run displays only the remaining `2` of `42`.
22. **Resolved: allocator syscall failures return null.** The native `mmap`
    and `mremap` thunks now convert negative Linux syscall results to a null
    pointer. `tests/stdlib_allocator_failure_execution.rs` compiles both
    reproductions, verifies their normal allocation paths, and injects
    `ENOMEM` into each syscall. Both fault-injected programs exit zero;
    the `mremap` fixture also verifies that the original bytes remain readable
    and the original allocation can be released after failure.
23. **Imported struct literals in native code.** Compile
    `tests/fixtures/stdlib_foundation/repro_imported_struct_literal.lani` with
    `--stdlib-root tests/fixtures/stdlib_foundation/repro_aggregate_root`.
    Native emission stops with `LNC0017`, unsupported target LIR opcode 31 at
    the `core::pair::Pair { ... }` literal. This is a second obstacle to a
    public struct-based collection handle unless construction goes through a
    tested module function instead of an imported struct literal.
24. **Resolved: imported calls with stack arguments.** The x86 backend now
    pushes arguments past the six register words, restores the aligned outgoing
    stack area after imported calls, and keeps object relocation offsets at the
    call site. `tests/stdlib_imported_aggregate_execution.rs` executes
    seven-, eight-, and nine-argument imported calls, plus seven- and
    eight-argument calls with a three-word return and hidden return pointer.
    `core::slice::copy_nonoverlapping_range_i32` uses two backed views and five
    scalar arguments and runs in the native fixture and checksum sample.
25. **Uninitialized array backing for stack buffers.**
    `tests/fixtures/stdlib_foundation/repro_uninitialized_array_data_ptr.lani`
    passes `laniusc check --stdlib-root stdlib`, but `--emit x86_64` stops with
    `LNC0057` when an uninitialized fixed array is passed to
    `core::mem::i32_array_data_ptr`. Array repeat syntax such as `[0; 1024]`
    also fails parsing. A fully enumerated 4096-byte stack array emitted and
    ran in isolation, but repeated source-pack compilation failed parsing its
    closing bracket. Consequently `std::env::current_dir_len` cannot yet
    replace its 4096-byte allocation with stack storage. Its heap allocation
    checks for null and returns `ENV_READ_UNAVAILABLE` on failure; the
    allocation failure is injected in `tests/stdlib_env_execution.rs`.
    Callers can use the tested `std::env_checked::current_dir_read_into` with
    their own buffer.
26. **Unsigned 64-bit arithmetic above the low 32 bits.** Compile
    `tests/fixtures/stdlib_foundation/repro_u64_division.lani` with
    `--stdlib-root stdlib --emit x86_64` and run the ELF. It exits 1 because
    `18446744073709551615 / 2` as `u64` does not equal the correct
    `9223372036854775807`. The smaller
    `tests/fixtures/stdlib_foundation/repro_u64_high_half_add.lani` also exits
    1: adding one to `9223372036854775808` loses the high half. Native x86
    lowering currently uses 32-bit integer operations for these expressions.
    A candidate `core::number_u64` module compiled but failed its executable
    saturating-multiplication case, which relies on division for its overflow
    guard. The candidate was removed rather than publishing arithmetic with
    incorrect high-value behavior. Complete 64-bit arithmetic lowering is a
    compiler dependency before a public u64 numeric module can be claimed.
27. **Resolved: specialized generic range method dispatch for scalar receiver arguments.** Compile
    `tests/fixtures/stdlib_foundation/repro_u32_range_method.lani` with
    `--stdlib-root tests/fixtures/stdlib_foundation/repro_u32_range_method_root`
    and `--emit x86_64`, then run the ELF. It now exits 0; before the fix it
    exited 2 because the imported method call targeted the signed i32 body.
    The GPU semantic interface now records each public method's full receiver
    type, and imported lookup compares scalar generic arguments before
    selecting a target. Ambiguous and unsupported compound receiver arguments
    fail closed. Interface version 5 rejects older artifacts, which must be
    rebuilt. `tests/imported_concrete_method_execution.rs` and the u32 range
    fixture execute this path. Compound generic receiver argument comparison
    remains a compiler dependency for methods specialized to nested types.
28. **Resolved: unsigned arithmetic with a left integer literal.** The GPU
    expression-type pass now inherits a checked u32 type from the right operand
    when the left operand is an unsuffixed integer literal. The original
    `repro_u32_literal_mod.lani` exits 0 instead of 1. The executable
    `tests/stdlib_literal_arithmetic_execution.rs` checks division and
    remainder at `u32::MAX`, a nested right expression, a high-bit bitwise
    result followed by a right shift, wrapped subtraction, and signed
    division/remainder cases. This does not claim general implicit numeric
    coercion for other type combinations.
29. **Resolved: raw filesystem path lengths.** The x86_64 Linux runtime now
    copies exactly each supplied path length, rejects overlong, null, and
    embedded-NUL paths, and then calls the corresponding Linux syscall.
    `tests/fixtures/stdlib_foundation/repro_fs_path_len_ignored.lani` now
    creates `"lanius"`, rather than the full source literal. Three executable
    tests in `tests/stdlib_file_execution.rs` cover every raw path operation,
    string-based opens, paths longer than 255 bytes, and error cases. A
    checked append-to-path wrapper still needs a compiler binding for
    `open_append_path(str)`; only raw `open_append(ptr, len)` is bound.
30. **High-bit unsigned 64-bit operations.** Compile
    `tests/fixtures/stdlib_foundation/repro_u64_bit_ops.lani` with
    `--stdlib-root stdlib --emit x86_64` and run the ELF. It exits 30, a
    four-group failure mask: right shift (2), narrowing cast to `u32` (4),
    addition/subtraction (8), and bitwise OR/AND (16) each contain at least
    one result that disagrees with the expected high-bit result. Its unsigned
    comparison checks (bit 1) pass.
    This is broader than dependency 26's division failure. A complete
    `core::number_u64` cannot claim native correctness while these operations
    fail; fixing one division call in Lanius would leave other wrong results.
    `repro_u64_literal_prefix.lani` narrows an earlier problem: the 11-digit
    literal `10000000000` compares equal to `1000000000`, so its ELF exits 1
    instead of 0. `parse_uint_token` in
    `shaders/parser/hir/literal_values.slang` reads only ten decimal digits
    into one `uint`; the compact HIR literal payload is also one 32-bit word.
    Native 64-bit support needs exact literal representation as well as wide
    arithmetic lowering. The executable `core::wide_u64` and
    `core::wide_i64` modules take explicit 32-bit words and do not make the
    primitive `u64` or `i64` types correct.
31. **Partially resolved: calling comparison trait implementations.**
    `tests/fixtures/stdlib_foundation/repro_cmp_trait_call.lani` imports
    `core::cmp` and calls `core::cmp::Eq<i32>::eq` and
    `core::cmp::Ord<i32>::lt`. `laniusc check --stdlib-root stdlib` rejects the
    first call with `LNC0027` (no resolved function or method signature);
    native emission rejects it with `LNC0005` (unresolved identifier).
    The GPU method table now indexes trait impl bodies, and built-in scalar
    receiver names acquire a method lookup key. Local `i32::eq`, `Box::eq`,
    and `value.describe()` calls execute in `tests/stdlib_cmp_execution.rs`.
    The public `core::cmp` i32, u32, bool, and char free functions call these
    trait bodies inside their defining library and execute through ordinary
    imports. The narrow integer free functions use scalar operators
    (dependency 57). Likewise, the i32, u32, bool, and char `core::hash` entry
    points call their local trait bodies. The separate
    `repro_cmp_receiver_call.lani` passes GPU `check` for an imported
    `i32::eq` call but native emission still reports `LNC0005`. Imported
    `core::hash::Hash<i32>::hash` also fails GPU `check` with `LNC0027` in
    `repro_hash_trait_call.lani`. Imported trait-method export and native
    dependency-call resolution remain before the trait APIs themselves can
    be claimed executable.
32. **Resolved: unordered f32 comparisons.**
    `tests/fixtures/stdlib_foundation/repro_f32_unordered.lani` now exits 2:
    only `nan != nan` is true. Native x86 `UCOMISS` sets parity for unordered
    operands, so comparison results and fused branches now combine their
    ordinary condition with the parity flag. The executable fixtures cover
    direct branches, bool values passed between functions, both operand
    orders, signed zero, and NaN behavior of `core::f32` helpers.
33. **Out-of-range narrow integer casts.**
    `tests/fixtures/stdlib_foundation/repro_signed_narrow_cast.lani` passes
    `laniusc check --stdlib-root stdlib` and emits x86_64 output. It casts
    128 from `i16` to `i8` and 32,768 from `i32` to `i16`, then compares the
    results with -128 and -32,768. Both comparisons fail: the ELF exits 3
    instead of 0. The executable signed wrapping helpers reduce the widened
    result modulo the target width and bring it into the signed range before
    casting. `repro_unsigned_narrow_cast.lani` demonstrates the same issue for
    `u32 as u8` and `u32 as u16`: values 256 and 65,536 retain their full
    native values instead of becoming zero, so the ELF exits 3. The wide hash
    byte extractor masks every shifted word to 0..255 before casting. Direct
    out-of-range signed and unsigned narrowing still need a compiler fix.
34. **Resolved: qualified imported unit enum variants.**
    The original `repro_ordering_variant_import.lani` passed `laniusc check`
    but native compilation reported `LNC0005` at `core::ordering::Less`.
    Dependency projection now matches a payload-free variant against its
    exported parent enum member, retains its ordinal across dependency pages,
    and lowers the path as a tagged enum aggregate. The native fixture checks
    direct `Less`, `Equal`, and `Greater` values, a direct variant call argument,
    ranks, and reversal. A second native fixture executes `None` from an enum
    that also has payload variants;
    a bare imported payload variant remains rejected. Unqualified variant
    names also execute; see resolved dependency 45.
35. **Explicit return in a void helper.**
    `tests/fixtures/stdlib_foundation/repro_void_return.lani` defines an
    unused void helper containing only `return;` alongside a valid `main`.
    Type checking succeeds, but native compilation stops in the GPU SSA
    operand rewrite pass (optimization structure flag 1024, row 0). The
    diagnostic now preserves that failure instead of incorrectly claiming
    that `main` is missing; it still needs a specific compiler diagnostic and
    a lowering fix. `test::assert` omits redundant void returns, so this
    compiler limitation does not affect its executable helpers.
36. **Resolved: imported generic slice parameter from a fixed array.** The
    late GPU dependency-call checker used an argument token to look up a
    generic claim keyed by the callee token. It now carries the callee token
    separately from the argument token used for diagnostics.
    `repro_generic_slice.lani` imports `core::slice_any::get_or<T>` and runs
    with `[u8; 1]` and `[u32; 1]` arguments; the focused execution test also
    confirms that a `[u8]` argument with a `bool` fallback is rejected.
    This verifies generic slice substitution for those scalar cases. The
    concrete `core::slice_bool`, `core::slice_u8`, `core::slice_i8`,
    `core::slice_i16`, `core::slice_u16`, and `core::slice_u32` modules remain the complete
    executable slice APIs in this audit.
37. **Third same-name concrete method specialization.**
    `laniusc check tests/fixtures/stdlib_foundation/repro_third_concrete_method.lani`
    reports `LNC0016` at the third `get` method, claiming that the function
    name is unexpected. The first two `Small<i32>` and `Small<u32>` methods
    parse, and renaming the `Small<i8>` method makes the file compile and run.
    Three same-name methods on unrelated concrete structs also parse, and
    removing `pub` does not change the generic failure.
    This prevents adding the same method names for all small-width generic
    `Range<T>` specializations in `core::range`. The executable modules use
    concrete range types and distinctly named free functions instead.
38. **RangeFull layout after unrelated exports.**
    `repro_range_full_growth.lani` imports the adjacent
    `repro_range_full_growth_root` copy of `core::range` with seven extra
    scalar identity functions. Run it with `--stdlib-root
    tests/fixtures/stdlib_foundation/repro_range_full_growth_root --emit
    x86_64`. The unmodified module and the copy with six extra functions
    compile; seven produce `LNC0017` at the existing `range_full()` call:
    the empty nominal result has no canonical ABI layout (LIR opcode 23).
    This is a native lowering dependency. Adding free functions for more
    `Range<T>` widths to the shared module crosses the same boundary, so the
    small-width aggregate APIs reside in separate modules.
    `repro_wide_range_full_import.lani` is a smaller cross-module case: simply
    importing both `core::range` and `core::wide_u64_range` and calling
    `range_full()` produces `LNC0017` (LIR opcode 23). The executable wide
    range module provides `full_contains` as a scalar predicate instead.
39. **Resolved: local helpers returning imported concrete Option or Result.**
    `repro_option_u16_local_return.lani` previously compiled but segfaulted.
    The type checker now carries the checked width of an imported flat struct
    through a local function return type. x86 lowering marks local calls with
    aggregate results as aggregates and reserves stack homes for imported
    aggregate calls, including calls returned directly from a helper. The
    executable return suite forwards `Some` and `Ok` through local helpers
    for i8, u8, i16, u16, i32, u32, bool, and f32. Separate u16 and f32
    fixtures check `Some`/`None` and `Ok`/`Err` through conditional local
    returns, including two-word register returns and three-word hidden
    structure returns. Generic Option/Result enums still have dependency 1;
    this repair applies to concrete flat structs.
40. **Resolved: inferring a generic element only from an imported slice parameter.**
    `repro_generic_slice_inference.lani` calls `core::slice_any::swap<T>` with
    a `[u8; 2]` array and no separate scalar `T` argument. The GPU claim
    collector now reads the generic child of the imported canonical slice
    type and records the actual array element reference. The reproducer
    compiles and executes on x86. A separate `copy_first<T>` reproducer with
    two imported `[T]` parameters accepts matching byte views and rejects
    a `[u8]` source paired with a `[bool]` destination. This repairs generic
    inference, while dependency 41 still prevents a public all-type slice API.
41. **Signed generic slice element access misexecutes on x86.**
    `repro_generic_slice_signed.lani` imports `get_or<T>` with an `[i32; 3]`
    backing containing 3, 7, and 11. It compiles with the adjacent test root,
    but the ELF exits 2 because index 1 does not return 7. A same-module
    generic function also returns an incorrect value there; the concrete
    `core::slice::get_or_i32` returns 7. A matching `[u32; 3]` generic probe
    returned every element correctly, while `[i16; 3]` also failed at index 1.
    `core::slice_generic<T>` was removed from the main library because an
    accepted signed instantiation silently returned wrong data. Concrete
    signed slices and `core::slice_bool` remain executable. This needs a
    compiler or native-lowering fix before generic slices can be claimed.
42. **Resolved: imported Boolean calls accept comparison expressions.**
    `repro_option_bool_comparison_arg.lani` formerly passed `laniusc check`
    but failed native compilation with `LNC0006`: the imported-call validator
    read the i32 type of the first token in `count == 2` rather than the bool
    result. It now classifies comparison and Boolean expression results after
    following expression wrappers. The reproducer and
    `sample_programs/vector_true_count.lani` compile and execute on x86. A
    separate negative fixture confirms that passing a bare i32 still fails.
43. **Floating-to-integer casts are rejected.**
    `repro_f32_to_i32_cast.lani` assigns `7.0 as i32` to an i32 local.
    `laniusc check --stdlib-root stdlib` reports `LNC0006`, expecting i32 but
    seeing float. The executable floating-window sample checks its f32 total
    and prints a separately computed integer index. The language needs a
    defined checked or saturating conversion rule and compiler support before
    an f32-to-i32 helper can be claimed.
44. **Resolved: raw secure byte fill inherited stale syscall flags.**
    Compile `tests/fixtures/stdlib_foundation/repro_random_fill_flags.lani`
    with `--stdlib-root stdlib --emit x86_64` and run it on Linux. Before the
    fix it exited 1, with `strace` showing
    `getrandom(ptr, 4, 0x100) = -1 EINVAL` after
    `std::env::current_dir_read(ptr, 256)`. The compiler task confirmed no
    file conflict, then the x86 runtime binding in
    `shaders/codegen/lir/x86/runtime_abi.slang` gained a `cdq` after loading
    positive syscall 318. That clears EDX before `syscall`. The reproducer
    now exits 0 and `strace` shows `getrandom(ptr, 4, 0) = 4`. A focused
    native test and the host smoke sample exercise the sequence; the sample
    checks the returned byte count instead of a tautological `secure_u32`
    self-comparison. The raw scalar's separate failure channel is resolved in
    dependency 18.
45. **Resolved: unqualified imported enum variant names.**
    `repro_ordering_variant_unqualified.lani` imports `core::ordering` and
    executes direct `Less`, `Equal`, and `Greater` values, including `Less` as
    a direct call argument. The original native `LNC0005` at `Less` was
    resolved by projecting the imported path's canonical enum type reference
    onto its path head before argument validation and semantic projection.
46. **Resolved: inferred local type from an imported enum value.**
    `repro_ordering_variant_inferred.lani` assigns
    `core::ordering::Greater` to an unannotated local, passes it to
    `core::ordering::is_greater`, and exits zero. A second native fixture
    infers both a unit variant and an imported function's enum result, then
    passes them to a different imported module. An imported struct result also
    executes through an inferred local. The checker copies the stable nominal
    identity onto the local; a negative fixture verifies that an unrelated
    enum parameter still reports `LNC0006`.
47. **Resolved: direct imported payload enum constructors and call arity.**
    `repro_enum_direct_payload_constructor_app.lani` calls the imported
    `helpers::maybe::Some(3)` and `Pair(2, 3)` constructors and executes their
    tagged payloads on x86_64. The GPU semantic projection now lowers a
    concrete imported payload variant as an enum constructor instead of
    emitting an unresolved external function symbol (`LNC0059`). Inferred
    local storage for the same constructor also executes. A call-level
    dependency validator rejects
    missing arguments for both `Some()` and an ordinary imported function, and
    an extra argument to `Some`, with `LNC0027`; GPU `check` reports the same
    arity error for the constructor calls. A Boolean payload reports `LNC0006`,
    and a bare payload variant remains rejected.
48. **Resolved: direct character literals in fixed-array initializers.**
    The GPU array-element checker now identifies a direct character expression
    as `char`. `repro_char_array_literals.lani` initializes `[char; 3]`
    with ASCII and two- and four-byte Unicode literals, reads the values
    directly and through imported `core::slice_char`, and mutates the array.
    The emitted x86_64 ELF exits zero. A separate fixture with an `i32`
    element still reports `LNC0006`. The character inventory sample also
    uses direct literals and prints its expected count. All three run in
    `tests/stdlib_char_array_literal_execution.rs`.
49. **Returned slice values in native code.**
    `tests/fixtures/stdlib_foundation/repro_slice_return.lani` constructs a
    `[i32]` view in a helper and returns it. GPU `check` succeeds, but native
    compilation reports `LNC0017`: the slice result has no canonical x86
    aggregate ABI layout. `std::utf8_vec` uses `std::vec_u8::data_ptr`, which
    returns a scalar pointer, and constructs the borrowed view at its use
    site. This keeps text operations executable without claiming that a
    function can return a slice yet.
50. **Unsigned literals in fixed-array initializers.**
    `tests/fixtures/stdlib_foundation/repro_u32_array_literals.lani`
    declares `[u32; 2] = [65, 4294967295]`. GPU `check` reports `LNC0006` at the
    first integer literal because it infers `i32` despite the array's `u32`
    element annotation. Initializing typed `u32` locals before building the
    array compiles and executes, including indexed access after the source
    local changes; `u32_array_typed_elements.lani` tests this control case.
    The owned-text range-removal fixture also uses typed locals.
    An experimental checker relaxation accepted direct integer literals,
    but the native ELF then exited 2: element 1 did not equal `u32::MAX`.
    Disassembly showed packed 32-bit storage in an intermediate array and an
    8-byte-stride load from its copied result. The relaxation was reverted.
    Contextual element typing and the corresponding native literal materialization
    must both work before this form can be exposed as executable.
51. **Cast directly on a composite expression fails parsing.**
    `tests/fixtures/stdlib_foundation/repro_cast_call_result.lani` applies
    `as i32` to a `u32` function call, and
    `tests/fixtures/stdlib_foundation/repro_cast_arithmetic_result.lani`
    applies it to `(64 - shift)`. GPU `check` reports `LNC0016` at `as` in
    both cases. Assigning the result to a typed `u32` local and casting that
    local works. `core::utf8_view` and `core::wide_u64_bits` use the named-local
    form; their executable fixtures pass without this compiler fix.
52. **Resolved: cast directly into a byte-array slot misexecuted on x86.**
    `tests/fixtures/stdlib_foundation/repro_u8_cast_store.lani` casts an
    `i32` value to `u8` on the right side of two indexed assignments. GPU
    `check` and native compilation succeeded before the fix, but the ELF
    exited 1 because the second byte was not stored. The x86 GPU lowering
    selected packed i32 array storage from the RHS cast's input type. It now
    selects that layout from the checked lvalue element type.
    `tests/stdlib_cast_store_execution.rs` runs the direct and named-local
    forms, a direct fixed-array cast store, an i32 store with a cast RHS, and
    existing i32 and byte-slice fixtures. They all exit 0 on x86_64.
53. **Resolved: i32 millisecond sleep left half of each timespec field uninitialized.**
    `tests/fixtures/stdlib_host/std_time_metadata.lani` calls both clock reads
    and then zero-millisecond sleep after many metadata calls. Before the fix,
    the native ELF exited 11; `strace` showed `nanosleep` receiving a nonzero
    garbage upper half of `tv_nsec` and failing with `EINVAL`. The fixed x86
    runtime writes both `timespec` fields as 64-bit words while preserving the
    block's 55-byte size and every following runtime service offset.
    `tests/stdlib_time_execution.rs` now runs this fixture and the checked
    clock and sleep cases successfully.
54. **Partially resolved: imported generic calls.**
    `tests/fixtures/stdlib_foundation/repro_imported_associated_new.lani`
    calls `core::thing::Thing::new()` through a separate stdlib root and
    checks both returned fields through an imported free function. The native
    executable exits zero in `tests/stdlib_imported_aggregate_execution.rs`.
    Method projection now runs for import-only entries, publishes the
    qualified call at its owner token, and reports the imported aggregate
    return width. The sibling `repro_imported_plain_method.lani` calls the
    imported `value.get()` after a free constructor, and
    `repro_imported_plain_method_inferred.lani` does the same through an
    unannotated binding. Both compile and exit zero in the native executable
    tests. Receiver lookup follows the stable imported identity on the
    annotation or inferred call result, rather than a page-local canonical
    type index. Scalar method returns have zero aggregate result words; the
    specialized imported `RangeFrom<u32>::contains` executable test catches
    a wrong return layout. Imported generic associated calls now resolve their
    concrete receiver arguments directly from the value path. The interface
    exporter ignores expression-owned type arguments, and methods returning
    the same generic nominal type reuse the instantiated receiver argument.
    `repro_vec_generic_associated_new.lani` compiles and executes through
    `--stdlib-root` with both `i32` and `bool` types. The smaller `Bucket<T>`
    fixture also executes static construction and instance access, while a
    negative test rejects an unrelated `Other<T>` result. The free
    `repro_vec_generic_free_new_only.lani` compiles and runs with an annotated
    result. The call-argument claim pipeline now reads generic children from
    imported parameter types, so `repro_vec_generic_free_len_only.lani` and
    the complete `repro_vec_generic_free_new.lani` also execute. All six
    operations execute when supplied in one flat source pack. The direct
    `Vec<i32>::new()` argument in `repro_vec_generic_free_direct_argument.lani`
    also executes: the dependency-call validator reads its scalar generic
    argument from the value-path type instance when no annotation subtree
    exists. This path is limited to a single generic parameter and a scalar
    return.
    The semantic-interface exporter previously omitted both public methods
    on plain `Thing` because it looked for a generic instance binding on the
    receiver. It now resolves plain receivers through the checked module type
    path. `tests/stdlib_generic_interface.rs` confirms that `Thing::new`,
    `Thing::get`, and all three `Vec<T>` methods are exported. Generic vector
    storage and mutation remain compiler and runtime dependencies.
55. **Imported aggregate nested in a returned struct.**
    `tests/fixtures/stdlib_foundation/repro_nested_imported_vec_field.lani`
    puts the imported three-word `VecI32` inside a local `Wrap`, returns the
    wrapper, and reads the vector length. GPU checking and native emission
    succeed, but the ELF exits 1 because the returned empty vector has an
    incorrect length. Passing `wrapped.cells` directly to `len` also fails
    type checking with `LNC0006`. The first `std::map_i32_i32` implementation
    nested a `VecI32` and crashed even on construction and length lookup.
    The executable map stores its pointer, length, and capacity directly and
    uses the bound allocator; it does not rely on nested imported aggregate
    returns. Nested aggregate layout and projection remain compiler work.
56. **Imported return with a nested aggregate and following field.**
    `tests/fixtures/stdlib_foundation/repro_imported_nested_return.lani`
    imports a `Read` struct containing an `i32`, a two-word `Pair`, and a
    following `i32`. GPU checking and native emission succeed, and the ELF
    reads the first three scalar words correctly but exits 4 because the
    trailing field differs from its initializer. Four flat scalar fields in
    the same shape execute correctly in a separate local check. Compile with
    `laniusc --stdlib-root tests/fixtures/stdlib_foundation/repro_imported_nested_return_root --emit x86_64 -o /tmp/repro_nested tests/fixtures/stdlib_foundation/repro_imported_nested_return.lani`
    and run `/tmp/repro_nested` to reproduce the exit status. The wide
    varint decoder uses three flat scalar fields and encodes its successful
    next offset in a private negative state; this gives executable status,
    value, and next-offset accessors without relying on the broken nested
    return layout.
57. **Narrow integer trait implementation keys collide with 32-bit keys.**
    `laniusc check tests/fixtures/stdlib_foundation/repro_cmp_signed_width_trait_impls.lani`
    reports `LNC0021` on `impl Marker<i32> for i32` after an `i8` impl.
    The matching unsigned reproducer reports the same error for `u8` and
    `u32`. The GPU language declaration table currently assigns one type
    code to every signed integer width and another to every unsigned width;
    the exact trait-impl index therefore treats distinct primitive types as
    the same key. A single narrow-width impl succeeds, and `i8` beside `u32`
    succeeds. Widening type identity through the compiler is required before
    `core::cmp` can provide distinct trait impls for every integer width.
    The 60 imported free functions execute and cover all six scalar integer
    widths, Boolean values, Unicode characters, and two-word signed and
    unsigned 64-bit values without claiming those colliding trait impls.
58. **Imported nominal trait argument differs between checking and emission.**
    `repro_imported_nominal_trait_impl.lani` defines a local trait for imported
    `core::wide_u64::WideU64`. `laniusc check --stdlib-root stdlib` succeeds,
    but emitting x86_64 rejects the same impl header with `LNC0021`, saying
    the qualified trait argument type is unknown. An unqualified local alias
    fails with an unsupported trait-argument shape. The source-pack predicate
    collection path does not recover this imported nominal declaration from
    its qualified type argument. The two-word comparison and hash free
    functions remain executable, but nominal `Eq`, `Ord`, and `Hash` impls
    cannot be claimed across this import boundary.

These are GPU compiler and target runtime dependencies, not stdlib
implementations in Rust or Python. Their executable claims require those
components to change and the reproductions above to pass.
