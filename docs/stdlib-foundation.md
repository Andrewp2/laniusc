# Standard library execution audit and portable foundation

**Latest compiler follow-up (2026-10-11):** body replay now separates closed
semantic identity from optional native-width witnesses. Tested local layouts
complete on the GPU, descriptor forwarding preserves opaque referent identity,
and the body cache retains completed widths. Original field/variant recipes keep
exact owner and snapshot identity; GPU admission rejects malformed recipe
ownership and mismatched recipe epochs. Builds 19, 20, and 23 record 19 passing executions covering
17 distinct tests, with host, GPU readback/admission, and native evidence separated.
The actual foreign missing-layout consumer, abstract trait-member routing, and
the full stdlib acceptance gate remain unfinished. See the
[checkpoint and per-build evidence](compiler-generic-types.md#semantic-replay-and-native-layout-prerequisites-2026-10-11).

**Preceding compiler follow-up (2026-10-11):** direct local and imported generic
trait implementation methods now execute with inherited environments and bounds,
including caller-supplied proofs and compound result copies. Thirteen focused
checks pass: eight native execution/rejection tests, four strict-interface tests,
and one host contract test. Strict successes used the identical module binary
under a cache alias after normal-name initialization timed out. Abstract calls
through `T: Trait`, trait methods' own headers/where clauses, full numeric/constant
support, current performance acceptance, and the full stdlib gate remain open.
This compiler checkpoint does not refresh every stdlib trait API claim below.
See the [execution and evidence limits](compiler-generic-types.md#direct-generic-trait-implementation-methods-2026-10-11).

**Preceding compiler follow-up (2026-10-11):** conditional and blanket marker-trait
implementations now pass the focused native programs, including imported
providers and caller-owned base implementations. Overlap, missing bases, and
recursive prerequisites reject before publication. The current build also
passes 32 direct matcher cases and two owner-retention checks on the physical
GPU. The later checkpoint above adds direct generic trait impl methods; abstract
member routing, complete numeric/constant support, current performance acceptance,
and the full stdlib acceptance gate remain unfinished. See the
[compiler checkpoint](compiler-generic-types.md#conditional-and-blanket-implementations-2026-10-11).

**Preceding compiler follow-up (2026-10-11):** the tested structural method receivers
now execute with correct copies, aliases, argument order, and bounds behavior.
Full checked parameter types also preserve unused receiver widths. The final
eleven-test structural suite passes; seven additional native generic regressions,
two physical-GPU library checks, and three host graph checks passed during
integration. The 1 MB compiler median is 38.474 ms, with all twenty executable
outputs verified. Paired 32-operand/parameter comparisons show 2.6% and 2.4%
overhead. See the [compiler checkpoint](compiler-generic-types.md#structural-receivers-and-native-storage-2026-10-11)
and [performance limits](stdlib-gpu-performance.md#structural-receivers-and-native-storage-2026-10-11).
General trait constraints and primitive-width support remain unfinished. These
results concern x86_64 output from the GPU compiler; user-program GPU execution
is not established, and the full stdlib acceptance gate below predates this work.

**Preceding compiler follow-up (2026-10-10):** local methods discovered during inference
now retain complete compound results without receiver/result annotations. The
shared GPU graph also bounds each shader view to its declared table size; a larger
reused scratch allocation can no longer change that table's apparent capacity.
This resolves the reproduced imported enum-alias failure after prior compilations.
All 276 selected checks pass. Execution evidence is x86_64 Linux ELF emitted by
the GPU compiler; user-program GPU execution is not established.

The existing 1 MB compiler median is 35.031 ms and the 32-parameter median is
354.334 ms. All 21 benchmark output contracts pass. Dispatches and tracked storage
are unchanged; the measurements are sequential observations. See the
[method-result and buffer-boundary checkpoint](compiler-generic-types.md#late-method-results-and-logical-buffer-bounds-2026-10-10)
and [performance report](stdlib-gpu-performance.md#late-method-results-and-logical-buffer-bounds-2026-10-10).
Imported trait identity, blanket implementations, trait method generics/where
clauses, and the other listed generics dependencies remain open. No native ABI or
private interface format change.

**Preceding compiler follow-up (2026-10-10):** trait predicates now compare complete
subject and argument types, including nested aggregates and all 32 argument slots.
Method contracts compare substituted types; imported concrete body replay now
rejects unsatisfied bounds before emission. All 176 selected checks pass.
The canonical 1 MB compiler median is 36.449 ms and the 32-parameter median is
358.767 ms. Dispatches fall by one; tracked storage increases by 27,033,792 bytes
and five allocations. All 21 benchmark output contracts pass. See the
[trait checkpoint](compiler-generic-types.md#complete-trait-type-graphs-2026-10-10)
and [performance report](stdlib-gpu-performance.md#complete-trait-type-graphs-2026-10-10).
Imported trait identity in caller-defined implementations, blanket implementations,
and other listed generics dependencies remain open. The later checkpoint above
resolves the retained unannotated local method-result cases. No ABI or private interface format change in this checkpoint.

**Preceding compiler follow-up (2026-10-10):** explicitly bound slice arguments now
borrow arrays through functions, methods, aliases, and enum constructors. Capture
mode follows the bound parameter; enum payloads store the full descriptor and
preserve following fields. All 61 selected checks pass, including compound and
empty arrays, signed-stride field views, value copies, argument evaluation order,
and type mismatches. The canonical 1 MB compiler median is 36.380 ms and the
32-parameter median is 357.416 ms; dispatch and allocation counts are unchanged.
No ABI change. See the [bound-slice checkpoint](compiler-generic-types.md#bound-slice-arguments-and-enum-payloads-2026-10-10)
and [performance report](stdlib-gpu-performance.md#bound-slice-arguments-and-enum-payloads-2026-10-10).
The broader generics goal remains open.

**Preceding compiler follow-up (2026-10-10):** concrete generic body replay now
specializes both anchors of qualified imported identity aliases. All 49 selected
checks pass, including an executable mixed-value program and unchanged symbolic
public interfaces. The original nested-`>>` program also executes with its
spacing workarounds removed. That checkpoint isolated the explicit generic
array-to-slice boundary addressed above. Performance at that checkpoint:
38.887 ms for the canonical 1 MB workload and 368.493 ms for the 32-parameter
workload; dispatch and allocation counts are unchanged. These are sequential,
unpaired observations. See the [replay checkpoint](compiler-generic-types.md#qualified-alias-body-replay-2026-10-10)
and [performance evidence](stdlib-gpu-performance.md#qualified-alias-body-replay-2026-10-10).
The overall generics goal remains open.

**Preceding compiler follow-up (2026-10-10):** imported alias-qualified constructors
and associated methods consume complete normalized parent types. Reordered,
injected, and constant arguments, reexports, concrete aliases with no written
operands, and 32-operand applications execute. A dispatch bug that skipped
binding checks for concrete imported aliases is fixed. All 68 selected checks
pass, including executable page permutations and invalid argument/scope checks.
Other listed generics limitations remain open. See the
[imported member checkpoint](compiler-generic-types.md#imported-alias-members-2026-10-10).

**Preceding compiler follow-up (2026-10-10):** imported alias types now execute with
complete type and constant substitution, including nested and reexported aliases.
Module interfaces serialize checked graphs, and concrete replay preserves the
template's public interface. All 58 selected checks pass: 45 integration
execution/rejection checks, nine interface checks, two native page/template
checks, and two compiler contracts. That checkpoint left imported alias-qualified
constructors and a nested-`>>` parser case open. See the
[imported alias checkpoint](compiler-generic-types.md#complete-imported-alias-types-2026-10-10).

**Preceding compiler follow-up (2026-10-10):** local alias-qualified enum
constructors inherit their complete normalized parent applications. Reordering,
injected operands, constants, bare/called concrete units, 32-operand applications,
and generic-body forwarding execute. Checked call bindings now use one compact
table; body replay covers both its type references and generated nominal constant
arguments. All 34 selected execution/rejection checks and both resource/lowering
checks pass. That checkpoint left imported generic alias substitution open. See the
[constructor checkpoint](compiler-generic-types.md#normalized-local-alias-constructors-2026-10-10).
The preceding local type-alias checkpoint passed 74 focused checks.

**Preceding follow-up (2026-10-10):** imported record field names and checked types
now survive dependency-page replacement, alongside the retained native layout
inputs. Ordinary, local generic, and imported generic functions execute the same
nested record extraction across flat and split pages, preserving copies and
writes. Unknown fields and wrong payload types reject in each page order. All
33 selected follow-up checks pass. The initial page checkpoint passed 85 checks,
including qualifier scope and nested enum layouts; its three page tests also
passed without compute batching. The full 287-test generic inventory was not repeated.
See the [current compiler checkpoint](compiler-generic-types.md#retained-record-fields-2026-10-10).
The broader goal remains open, including the listed
composition, reference, trait, and persistence contracts. Execution evidence is x86_64 Linux output from the GPU compiler;
user-program GPU execution is not established. The private semantic interface
remains version 9, native objects version 3, and slices use three words. The full
stdlib gate below predates these follow-ups.

**Compiler checkpoint (2026-10-09):** all 246 execution/rejection checks pass,
including both original inline-array borrow cases. Slices carry data, length,
and signed byte stride; local/imported generic calls preserve the original
aliases across packed and native backing. Explicit dotted methods also use the
shared ordered call environment. All 25 contract checks and eight interface-export
checks pass. At that checkpoint the private semantic interface was version 8; native objects must
be rebuilt for object format version 3.
The subsequent body-closure correction passes three focused checks and 32
affected regressions, including zero-sized slice forwarding and bounds. The
246-test full matrix was not rerun after that one-shader correction.
See the [current evidence](compiler-generic-types.md#slice-body-closure-follow-up-2026-10-09).

This audit distinguishes runtime evidence from source that merely type-checks.
`laniusc check` exercises the GPU-resident frontend but does not establish that
the target backend can emit or execute a helper. The executable claim below is
limited to native x86_64 output from this worktree.

The GPU compiler fixes have a [performance report](stdlib-gpu-performance.md),
including current timings, allocation costs, source/shader identities, and
independent executable validation. The observations are unpaired; they do not
establish a causal performance change or the cross-compiler 10x target.
Cold-start performance was not measured under controlled caches.

## Public API inventory

The [current compiler generics checkpoint](compiler-generic-types.md) supersedes
the older scalar-only and missing-local-body restrictions recorded below.
The preceding callable-constant checkpoint reported 229 passes and two explicit
inline-array borrow boundaries across 231 tests. Four disjoint commands covered every test once
in 126.68 seconds combined; eight parser checks, eight interface export tests, and
both layout/resource checks pass. This is executable verification, not a compiler
throughput measurement.
GPU interface export now retains source order across interleaved generic types
and constants independently of
lexical binding slots. At that checkpoint the private semantic-interface format was version 7;
version 6 artifacts must be rebuilt. The parser now retains separate segment-owned
argument ranges. Explicit type headers now execute for tested local/imported
functions and associated methods, including 32 used mixed type slots, independent
receiver/method headers, caller-symbolic types, strings, and reference/slice aliases.
Arity or unsupported argument kinds reject with source-labeled `LNC0027`;
conflicting type evidence rejects with `LNC0006`. Explicit callable integer literals
and scoped caller constant parameters now execute locally and through imports,
including interleaved 32 type/32 constant slots, independent method domains,
zero/high-bit values, and scalar-only forwarding in a reused workspace. Constant
names used as actual type annotations still reject. General constant expressions,
ordinary const-item operands, and broader typed-constant contracts remain
unverified. Dotted explicit methods now execute in the current checkpoint.
The native dominance
failure for nested match arguments and omitted output in mixed record/string-array
programs are fixed;
their original assertions now pass. Shared completion ordering also checks
sibling effects and skipped arms. The original borrow cases now pass under the
explicit-stride storage contract.
Nested matches now execute directly inside `if`/`while` conditions and outer
match scrutinees, with tested generic Option/Result payloads and skipped effects.
Fresh generic record literals passed directly to local/imported enum constructors
or ordinary functions now execute through shared receiving-context propagation.
Expected argument roots expand their implied declaration fields before indexing;
nested imported records also execute without an extra child annotation. The five
new focused checks cover mixed 32-field records, arrays, references, slice
aliases, generic bodies, and conflicts. All seven conflicting-field programs
reject with `LNC0006`; the two historical borrow boundaries also now pass.
Explicit local and qualified imported record constructors now execute through
the same checked application contract, preserving all 32 ordered mixed type
arguments. Their explicit types remain actual evidence; conflicting receiving
types reject rather than replacing those arguments. Four focused compiler
checks, two parser checks, 22 semantic token/ownership controls, and both resource
checks pass. The current checkpoint retains the former parser rejection, false
acceptance, and inference oscillation alongside their final passing results.
Local/imported array and nested record impl receiver patterns now execute through
complete checked matching, with inferred lengths, reference and slice aliases,
owned copies, and explicit rejection of conflicting or ambiguous methods. Five
focused compiler checks, three parser checks, and both resource checks pass.
The generic `core::option` and `core::result` receiver methods now take values
and preserve callers through Lanius copy semantics; older borrowed-receiver
notes below are historical. Reference payloads retain their aliases.
The [checked window sample](../sample_programs/checked_window_checksum.lani)
combines array-valued Option/Result with byte, numeric, range, and slice helpers
and executes on x86_64 Linux. Its focused compiler execution test verifies output,
error/absence paths, and owned-copy behavior.
It now constructs its array payload directly with `Some([18, 42, 24, 30])`.
Local/imported nonempty enum payload literals, including the tested nested arrays
and record arrays, have executable coverage in the compiler generics checkpoint.
Empty/nested empty and unsigned array payloads also execute. Imported enum
layout includes compound patterns in unused variants and preserves zero-sized
payloads next to strings. Scalar integer literal contexts now execute at
local/imported generic calls, constructors, and match arms, including unsigned
high-bit division. Conflicting named values and noninteger literals reject;
the compiler checkpoint records the current gate and remaining dependencies.
Unannotated local/imported calls also infer from known argument types in either
order, including tested scalar, array, and nested-array literal compositions.
Nested constant-length inference and symbolic forwarding also execute locally
and through imports, including all 32 constant slots. Retained symbolic bindings
require concrete replay before native specialization. Conflicting dimensions and
the 33rd parameter report explicit diagnostics; the compiler checkpoint retains
the runtime tests. Constant parameters now execute as values in arithmetic,
loops, and indexing with declared integer types and lexical shadowing. Missing
local bindings, invalid mutation, noninteger lengths, and contradictory literal
shapes reject explicitly. Annotated results and declared returns also infer
constant lengths for local/imported functions, borrowed generic receiver methods,
and associated functions, including zero, all 32 slots, and symbolic replay.
Expected-result contexts for nested argument/field/array-element calls and match
arms now execute in the tested compositions. Further constant binding contexts
and the inline-array storage/alias dependency remain listed in that checkpoint.
Direct generic record fields, scoped nested declaration fields with checked
concrete source applications, the tested compound arrays and borrowed slices,
and Option/Result values carrying record slices now execute. Implied type
instantiation, untested type shapes, and full-width native integers still
require further compiler work.

| Public surface | Classification | Evidence and limit |
| --- | --- | --- |
| `core::number_i8` constants and all 26 public functions | Executable on x86_64 | Focused runtime fixture checks signed 8-bit limits, widened arithmetic, wrapping and saturation, multiplication and power overflow, GCD/LCM, division and Euclidean remainder, zero-divisor and `MIN/-1` fallbacks, parity, signs, and power-of-two boundaries. |
| `core::number_i16` constants and all 26 public functions | Executable on x86_64 | Focused runtime fixture checks signed 16-bit limits, widened arithmetic, wrapping and saturation, multiplication and power overflow, GCD/LCM, division and Euclidean remainder, zero-divisor and `MIN/-1` fallbacks, parity, signs, and power-of-two boundaries. |
| `core::number_u16` constants and all 25 public functions | Executable on x86_64 | Focused runtime fixture checks unsigned 16-bit limits, widened saturation and wrapping, multiplication and power overflow, GCD/LCM, zero-divisor fallbacks, parity, and power-of-two and alignment boundaries. |
| `core::number_i32` constants and all 26 public functions | Executable on x86_64 | Focused runtime fixture checks ordinary values, integer extremes, wrapping arithmetic, multiplication and power overflow, signed GCD/LCM, truncating and Euclidean division, failure fallbacks, and power-of-two overflow. |
| `core::number_u32` constants and all 25 public functions | Executable on x86_64 | Runtime fixture checks unsigned extremes, wrapping and saturating arithmetic, GCD/LCM, power overflow, zero-divisor fallbacks, and alignment fallbacks. |
| `core::narrow` all 24 public 32-bit-to-8/16-bit conversion functions | Executable on x86_64 | The imported fixture calls every signed and unsigned source/target combination in wrapping, checked-fallback, and saturating forms. It checks ordinary values, signed and unsigned boundaries, out-of-range values, negative values, and full-width i32/u32 extremes. The input-driven byte report combines narrowing, byte arithmetic, and decimal I/O. A bare `as` cast truncates; the helpers name the wrapping, checked, and saturating policies and narrow with `as` after normalizing or checking the value. |
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
| `core::char` all 19 public functions | Executable on x86_64 | Focused runtime fixture checks ASCII classes, all 26 case pairs, case-insensitive comparison, control and printable boundaries, and unchanged non-ASCII values. Checked `from_u32` (returning `Option<char>`) and `from_u32_or` accept exactly the Unicode scalar values and reject surrogates and values above U+10FFFF; `is_scalar_value` tests that range. |
| `core::utf8` all 25 public codec and backed-view functions | Executable on x86_64 | Native fixtures check ASCII and multibyte encoding/decoding, checked scalar append, scalar counts and lookup, first and last scalar and sequence search, byte/scalar boundary mapping, equality, prefix and suffix matching, lexicographic comparison, empty and truncated views, out-of-byte-range integer codes, malformed sequences, surrogate exclusion, and Unicode maximum. Direct caller-backed `[u8]` helpers validate and count scalars, map scalar and byte boundaries, and read scalars by index across one- through four-byte sequences. They reject malformed input and negative lengths, and native indexing traps on a physical length overclaim. The older general view functions use caller-backed `[i32]` byte codes and do not access string storage. |
| `core::utf16` all 17 public functions, 5 status constants, and 2 result types | Executable on x86_64 for caller-backed `[u16]` views | The imported runtime fixture calls every function and checks ASCII, NUL, supplementary scalars, Unicode maximum, high and low surrogate boundaries, strict pair decoding, complete-view validation, scalar counts and ordinals, invalid bounds, malformed and truncated pairs, invalid scalar rejection without writes, and short capacity without writes. A second native fixture executes every BMP code point and 3,072 supplementary values, checking surrogate rejection and exact encode/decode round trips across the full high-surrogate range. Result structs distinguish success, bounds, invalid scalar, short input or output, and malformed input; a physical length overclaim traps with exit 101. The stdin UTF-16LE scalar-count program checks empty, ordinary, supplementary, maximal-length, odd-byte, malformed, oversized, and output-failure cases. GPU frontend compilation emits the tested x86 program; user-program GPU execution is not claimed. |
| `core::utf16_bytes` all 19 public functions and 2 result types | Executable on x86_64 for caller-backed `[u8]` views | UTF-16LE and UTF-16BE helpers compose strict scalar conversion with the executable endian module. The imported fixture calls every function and checks exact bytes and scalar values for ASCII, NUL, a supplementary character, and the Unicode maximum; byte offsets, complete-view validation, counts and ordinals, odd and negative lengths, misaligned offsets, lone and malformed surrogates, invalid scalar rejection, and short capacity without writes. An overclaimed physical byte view traps with exit 101. The stdin UTF-16LE scalar-count program uses this byte codec directly and tests real binary input, malformed and oversized input, and output failure. GPU frontend compilation emits the tested x86 program; user-program GPU execution is not claimed. |
| `core::transcode` all 10 public functions and its result type | Executable on x86_64 for caller-backed UTF-8 `[u8]`, UTF-16 `[u16]`, and UTF-16LE/BE `[u8]` views | Imported fixtures execute all four byte-order conversions and both code-unit conversions, all result accessors, exact ASCII, two-, three-, and four-byte sequences, NUL, Unicode maximum, all 128 ASCII bytes for code-unit views, empty input, negative lengths and capacities, malformed or truncated input, odd UTF-16 byte lengths, and short output capacity. Logical failures leave destination storage unchanged, including malformed suffixes after a valid prefix. Physically overclaimed source and destination views trap with exit 101. The bounded stdin summary program combines transcoding, UTF-16 scalar counting, decimal output, and real input and output failure cases. GPU frontend compilation emits the tested x86 program; user-program GPU execution is not claimed. |
| `core::utf8_view` all 12 public byte-view functions | Executable on x86_64 for caller-backed `[u8]` views | Focused native fixtures check complete-view validation, equality, prefix and suffix matches, lexicographic ordering, first and last byte-sequence offsets, first and last Unicode scalar indices, and checked append, insertion, removal, and replacement of Unicode scalars in caller-owned bytes. They cover ASCII and two-, three-, and four-byte encodings, repeated matches, empty views and needles, malformed data, invalid scalars, negative lengths, missing matches, growth and shrinkage, exact-fit and insufficient capacity, and unchanged storage after rejected edits. Separate fixtures confirm physical length and capacity overclaims trap. The source scan requires a runtime call for every public function. |
| `core::decimal` all 20 public functions | Executable on x86_64 | Runtime fixture checks decimal length and every ASCII byte of extrema across 8-, 16-, and 32-bit integers, ordinary values, sign placement, zero, out-of-range fallbacks, incremental and complete ASCII parsing for all six widths, and overflow against each width's limits. `std::io_decimal` and both bounded decimal file readers use the portable scalar helpers. |
| `core::hex` all 14 public functions | Executable on x86_64 | Runtime fixture checks shortest lowercase and uppercase hexadecimal representations of `u8`, `u16`, and `u32`, zero and maximum values, invalid-index fallbacks, mixed-case digit accumulation, complete prefixed and unprefixed parsing, and overflow against each width's limit. The helpers allocate no storage and use no host calls. |
| `core::hex_wide_u64` all 7 public two-word functions | Executable on x86_64 | Runtime fixtures call every function and check shortest lowercase and uppercase hexadecimal bytes for zero, the word boundary, a mixed full-width pattern, and the maximum; invalid-index fallbacks; bounded digit appends and overflow; optional prefixes, mixed case, leading zeros, malformed input, and full-width parse overflow. An overstated physical input view traps. The module uses `WideU64`, not native `u64`. |
| `core::hex_wide_i64` all 5 public signed two-word functions | Executable on x86_64 | Runtime fixtures call every function and check sign-and-magnitude formatting at zero, ordinary positive and negative values, and both signed extrema; shortest lower- and uppercase digits, invalid-index fallbacks, optional signs and prefixes, leading zeros, negative zero, malformed input, and signed overflow in either direction. An overstated physical input view traps. The module uses `WideI64`, not native `i64`. |
| `core::binary` all 11 public functions | Executable on x86_64 | Runtime fixture checks shortest unsigned binary representations across `u8`, `u16`, and `u32`, zero and high-bit values, invalid-index fallbacks, bounded digit accumulation, optional prefixes, malformed and overflowing input, and format/parse round trips for all 256 byte values. The helpers allocate no storage and use no host calls. |
| `core::binary_wide_u64` all 6 public two-word functions | Executable on x86_64 | Runtime fixtures call every function and check zero, the 32-bit word boundary, a sparse high-bit pattern, and the maximum; every digit of a full-width pattern; invalid-index fallbacks; bounded appends and overflow; optional prefixes, leading zeros, malformed input, and full-width parse overflow. An overstated physical input view traps. The module uses `WideU64`, not native `u64`. |
| `core::binary_wide_i64` all 4 public signed two-word functions | Executable on x86_64 | Runtime fixtures call every function and check shortest sign-and-magnitude formatting at zero, ordinary negative values, the word boundary, and both signed extrema; every digit of a negative boundary, invalid-index fallbacks, optional signs and prefixes, leading zeros, negative zero, malformed input, and signed overflow in either direction. An overstated physical input view traps. The module uses `WideI64`, not native `i64`. |
| `core::f32` both public constants and all 17 public functions | Executable on x86_64 for tested finite, infinite, and NaN inputs | Runtime fixtures check `ZERO` and imported `ONE`, classification, sign, comparison, valid and reversed clamp bounds, fallback behavior, and square root for zero, negative, small, ordinary, large, infinite, and NaN inputs. Direct and materialized NaN comparisons follow unordered semantics. |
| `core::array_i32` both public borrowed-view functions | Executable on x86_64 | Fixed arrays of lengths 1, 4, and 7 pass through `[i32]` parameters and execute `first` and `get_unchecked`, including signed extrema. Native bounds checks exit 101 for an empty view, a negative index, or an index past the end. The former const-generic signatures could not emit native indexing; the remaining compiler limitation is recorded in dependency 12. |
| `core::array_i32_4` all 14 public functions | Executable on x86_64 | Runtime fixture checks access, search, fallback indices, extrema, saturating sum, and caller-backed copy, fill, and reverse. Invalid destination lengths return false without writing; reverse supports shared source/destination backing. Fixed-array-returning predecessors were removed because they misexecute; see dependency 7. |
| `core::array_u8_4` all 17 public functions | Executable on x86_64 | Runtime fixtures check access, search, extrema, full-range sum, equality, endian conversion, invalid-index fallback, and caller-backed copy, fill, and reverse of four-byte arrays. Reversal works with shared source and destination backing. Short destination lengths return false without writing; an overstated backing view traps on native indexing. |
| Legacy `stdlib/bool.lani` all 9 public functions and `stdlib/i32.lani` all 16 public functions | Executable on x86_64 when included as source | A source-level native fixture checks both boolean values, both selection branches, ordinary and boundary signed arithmetic, wrapping overflow, comparisons, clamp bounds, and power-of-two overflow. The test calls every public function in both files. `abs` requires input above `i32::MIN`; `clamp` requires ordered bounds. |
| Legacy `stdlib/array_i32_4.lani` all 14 public functions | Executable on x86_64 when included as source | A source-level native fixture checks length, access, search, fallback indices, extrema, a representable sum, and caller-backed copy, fill, and reverse. Fixed-array-returning predecessors were removed; see dependency 7. |
| `core::range` free functions for all five i32 and u32 range forms, and methods for `Range`, `RangeInclusive`, `RangeFrom`, `RangeTo`, and `RangeFull` | Executable on x86_64 | Runtime fixtures check endpoints, empty/reversed ranges, touching and overlapping intervals, unbounded membership, and full-range membership, including values across the u32 high bit. The imported u32 method reproducer also checks that same-name i32 and u32 methods select the correct body. `RangeFull::contains_i32` and `contains_u32` execute through an imported empty receiver at both domain extremes and zero. |
| `core::wide_u64_range` all 19 public free functions and 14 receiver methods | Executable on x86_64 | The imported runtime fixture calls every function and method for half-open, inclusive, from, and to ranges. It checks endpoints and membership across the two-word boundary and unsigned high bit, equal and reversed bounds, touching and overlapping intervals, and zero and maximum values. `full_contains` covers the unbounded full domain as a scalar predicate. Range values store four or two flat `u32` words; imported nested wide aggregates remain compiler dependencies, and `RangeFull` forwarding APIs are not implemented. |
| `core::wide_i64_range` all 19 public free functions and 14 receiver methods | Executable on x86_64 | The imported runtime fixture calls every function and method for half-open, inclusive, from, and to ranges. It checks signed minimum and maximum, negative values in the same high word, the negative-to-zero boundary, equal and reversed bounds, touching and overlapping intervals, and full-domain membership. Range values store flat `u32` endpoint words and compare them in signed two's-complement order; no native `i64` behavior is claimed. |
| `core::range_u8` all 27 public scalar and concrete aggregate functions and 14 receiver methods | Executable on x86_64 | Runtime fixtures call every function and method across half-open, inclusive, from, to, and full byte ranges, including reversed and equal bounds, touching intervals, and the byte maximum. The aggregate forms use `RangeU8`, `RangeInclusiveU8`, `RangeFromU8`, and `RangeToU8`. |
| `core::range_i8` all 27 public scalar and concrete aggregate functions and 14 receiver methods | Executable on x86_64 | Runtime fixtures call every function and method across signed half-open, inclusive, from, to, and full ranges, including negative bounds, `-128`, `127`, touching intervals, and empty or reversed bounds. |
| `core::range_u16` all 27 public scalar and concrete aggregate functions and 14 receiver methods | Executable on x86_64 | Runtime fixtures call every function and method across half-open, inclusive, from, to, and full ranges, including equal or reversed bounds, touching intervals, and the `65535` endpoint. |
| `core::range_i16` all 27 public scalar and concrete aggregate functions and 14 receiver methods | Executable on x86_64 | Runtime fixtures call every function and method across signed half-open, inclusive, from, to, and full ranges, including negative bounds, `-32768`, `32767`, touching intervals, and empty or reversed bounds. |
| `core::range_char` all 27 public scalar and concrete aggregate functions and 14 receiver methods | Executable on x86_64 | A runtime fixture calls every function and method across half-open, inclusive, from, to, and full character ranges. It uses ASCII and two-, three-, and four-byte Unicode literals to check scalar ordering, equal and reversed bounds, touching intervals, endpoint inclusion, and aggregate forwarding. The character-inventory program uses its `contains` method with `core::range`, `core::slice_char`, `core::char`, and `core::number_i32`. |
| `core::range_f32` all 27 public scalar and concrete aggregate functions and 14 receiver methods | Executable on x86_64 | Runtime fixtures call every public function and receiver method with finite values, signed zero, both infinities, and NaN. NaN bounds make bounded ranges empty; ordered ranges reject NaN values, while the full-range predicate accepts every `f32`. They check endpoint inclusion, equal and reversed bounds, touching intervals, aggregate forwarding, and imported floating method returns. The floating window sample uses an inclusive range method. |
| `core::slice` 10 generic access/copy functions and 27 public i32 algorithms | Executable on x86_64 for the documented backed views | The shared generic functions execute for nine tested scalar spellings, including typed i32 raw views, mutation, overlap, NaN, negative zero, and explicit failures; see [the slice guide](stdlib-slice.md). Runtime fixtures check backed, empty, unsorted, duplicate, and sorted views; sequence comparisons, first and last contiguous subsequence matches, rotations, compaction, checked insertion and append within caller-owned capacity, partition boundaries and preserved contents, first and last binary matches, sorted insertion boundaries, extrema, sum, overlapping and nonoverlapping copies, sorting, and fallback behavior. Sorting also runs all 243 five-element arrays over `{-1, 0, 1}` against independently counted expected groups. Separate fixtures confirm native index trapping on overclaimed physical lengths. |
| `core::slice_u8` all 36 public byte-view functions | Executable on x86_64 for fixed-array-backed views | Runtime fixtures exercise access, swaps, fill, rotation, overlap-safe and nonoverlapping copies, compaction, insertion, sequence comparison and search, unsigned ordering, heapsort, binary search, partitioning, and saturating sum. They cover empty and invalid logical lengths, rejected mutation, zero, and 255. Sorting also runs every five-element sequence over `{0,1,2}` against independently counted groups. A source scan requires a runtime call for every public function. Byte views over string or raw pointer storage remain outside this claim. |
| `core::slice_i8` all 36 public signed-byte-view functions | Executable on x86_64 for fixed-array-backed views | Runtime fixtures call every public function and cover search, mutation, copy, rotation, compaction, insertion, signed ordering, sorting, binary search, partitioning, and left-to-right saturating sum. Cases include `-128`, `127`, empty and invalid logical lengths, every five-element sequence over `{-1,0,1}`, and a native trap on physical length overclaim. |
| `core::slice_i16` all 36 public signed-halfword-view functions | Executable on x86_64 for fixed-array-backed views | Matching fixtures cover every public function, `-32768`, `32767`, signed ordering and binary search, sums clamped after each addition, all 243 small sorting sequences, invalid logical lengths, and a native trap on physical length overclaim. |
| `core::slice_u16` all 36 public unsigned-halfword-view functions | Executable on x86_64 for fixed-array-backed views | Runtime fixtures call every public function and check access, mutation, copy and rotation, compaction, insertion, sequence search, unsigned ordering across `32768`, sort and binary search, partitioning, and sums saturating at `65535`. They cover empty and invalid logical lengths, rejected mutation, and all 243 five-element sequences over `{0,1,2}` for sorting. A separate fixture confirms exit 101 when the claimed length exceeds the physical backing and is indexed. |
| `core::slice_u32` all 36 public unsigned-word-view functions | Executable on x86_64 for fixed-array-backed views | Matching runtime fixtures cover the same operations and failure cases, including unsigned ordering across `2^31` and saturation at `u32::MAX`, plus the exhaustive small-sort fixture. The caller supplies a logical length within the physical backing. A source scan requires a runtime call for every public function. |
| `core::u32_cells` all 4 public functions | Executable on x86_64 for caller-backed i32 cells that hold u32 bit patterns | The unsigned vector sort fixture directly calls sort, reverse, lower bound, and upper bound on cells containing zero, one, the unsigned high bit, and the maximum word, and checks all 243 five-cell sequences over three representative unsigned values against independent input counts. The helper also runs through the owned `VecU32` APIs. Search requires nondecreasing unsigned order; invalid physical length claims can trap on native indexing. |
| `core::wide_word_cells` all 4 public paired-cell functions and its length limit | Executable on x86_64 for caller-backed low/high i32 word pairs | Direct native fixtures call sort, reverse, lower bound, and upper bound in signed and unsigned modes. They check both signed extrema, the unsigned high bit, equal high words with different low words, and all 1,024 five-pair sequences over four representative values for each ordering against independent input counts. The owned wide vectors use the same helpers. Search requires nondecreasing input under the selected order; invalid logical lengths return zero, and the native overclaimed-backing fixture exits 101. |
| `core::slice_wide_u64` all 36 public two-word slice functions and its length limit | Executable on x86_64 for caller-backed `[u32]` views | Each element uses adjacent low/high words. The imported runtime fixture calls every function and checks full-width access, mutation, overlap-safe copying, rotation, compaction, insertion, subsequence search, unsigned ordering, heapsort, binary search, partitioning, and wrapping sum. Sorting and extrema run all 243 five-element sequences over zero, `2^32`, and `u64::MAX`. Invalid logical bounds use documented fallbacks or reject mutation; physical backing overclaims exit 101. A five-number median program reads and prints full-width decimal values. Native `u64` behavior and GPU device execution are not claimed. |
| `core::slice_wide_i64` all 36 public two-word slice functions and its length limit | Executable on x86_64 for caller-backed `[u32]` views | Each element retains adjacent low/high two's-complement words. The imported runtime fixture calls every function and checks full-width access, mutation, overlap-safe copying, rotation, compaction, insertion, subsequence search, signed ordering, heapsort, binary search, partitioning, and wrapping sum. Sorting and extrema run all 243 five-element sequences over signed minimum, zero, and maximum, plus an ordinary negative and `2^32` matrix. Invalid logical bounds use documented fallbacks or reject mutation; physical backing overclaims exit 101. A five-number median program parses and prints negative and signed-extreme values. Native `i64` behavior and GPU device execution are not claimed. |
| `core::slice_bool` all 35 public boolean-view functions | Executable on x86_64 for fixed-array-backed views | Runtime fixtures call every function and check reads, writes, fill, swap, overlapping and disjoint-range copies, rotation, compaction, insertion and removal, prefix, suffix, and subsequence search, false-before-true comparison, binary bounds and search, partitioning, true counts, `any` and `all`, empty and invalid lengths, and an overclaimed physical length that traps. Sorting and binary search check all 32 five-element Boolean sequences. The boolean checksum sample uses it with numeric and Option helpers. Generic `[T]` operations are withheld because signed element instantiations misexecute; see dependency 41. |
| `core::slice_char` all 35 public character-view functions | Executable on x86_64 for fixed-array-backed views | Runtime fixtures call every function and check access, mutation, overlap-safe and disjoint-range copying, rotation, compaction, insertion, extrema, partitioning, prefix and subsequence matching, equality, Unicode scalar ordering, sorting, bounds, binary search, empty and invalid lengths, and non-ASCII values. They assert the scalar values of two-, three-, and four-byte UTF-8 character literals, including two literals with the same leading byte. Sorting checks all 243 five-element sequences over `{'a', 'z', 'é'}`. An overclaimed physical length traps. The character inventory sample combines it with `core::char`, `core::range`, `core::range_char`, and `core::number_i32`. |
| `core::slice_f32` all 36 public floating-view functions | Executable on x86_64 for fixed-array-backed views | Runtime fixtures call every function and check finite, infinite, and NaN values, IEEE equality and signed zero, left-to-right sums, overlap-safe and disjoint-range copying, rotation, compaction, insertion, prefix and subsequence matching, finite extrema and lexicographic comparison, checked partitioning, invalid bounds, and native trapping on an overclaimed physical length. Finite-only heapsort, extrema, and partitioning check all 243 five-element sequences over `{-1, 0, 1}`; binary bounds and searches cover duplicates, missing values, signed zero, and invalid input. The floating window sample combines it with `core::f32`, `core::range_f32`, and `OptionF32`. |
| `core::mem::{i32_array_data_ptr,i32_slice_data_ptr,string_data_ptr,i32_slice_from_raw_parts}` | Compiler-provided intrinsics; executable on x86_64 for tested backing storage | The source has no null or empty placeholder bodies. A native fixture checks array and slice pointers, view mutation, and a string literal's first byte; existing native tests check bounds trapping. Byte-slice access to string storage remains broken; see dependency 16. |
| `core::mem::typed_slice_from_raw_parts<T>` | Executable on x86_64 Linux for tested caller-backed `i32`, `u32`, and record slices | The imported runtime fixture checks access, mutation, aliasing, an empty view, and three element types. Separate imported fixtures check that a negative length traps with SIGILL and indexing at the length exits 101. The caller must provide storage in the target's layout, keep it alive, and supply a valid aligned pointer; the constructor cannot validate physical backing. The `u32` and record cases use separately allocated native element slots, not a reinterpretation of a packed `i32` array. |
| `core::mem::{identity,first,second,select}` | Executable on x86_64 for tested scalar and string instantiations on the resident native path | Runtime fixture exercises each helper and both selector branches for `i32`, high-bit `u32`, Unicode `char`, and finite `f32`, plus `identity<bool>`. The new actual-root fixture executes every helper for bool, i32, u32, f32, char, and str, including both selector branches, NaN, negative zero, empty strings, and forwarding through another function. Record body specialization remains unavailable and deferred; dependency 62 records the earlier miscompile, while dependency 92 records the scalar repair. |
| `core::mem` capability metadata, all 10 public functions | Executable on x86_64 Linux | The native metadata fixture calls every function and checks runtime-free value helpers and the unavailable raw-memory host API against `core::runtime`. The unavailable host API is distinct from the four executable compiler-provided intrinsics above. `tests/stdlib_mem_execution.rs` requires a runtime call for all 19 source-defined public functions across its fixtures. |
| `core::hash` twelve public free functions and two FNV-1a constants | Executable on x86_64 | The runtime fixture checks stable 32-bit bit-pattern hashes for six integer widths, both Boolean values, and ASCII and Unicode characters. The i32, u32, bool, and char functions call local `Hash<T>` implementations; narrow integers widen explicitly. `hash_wide_u64` and `hash_wide_i64` apply FNV-1a to eight little-endian bytes of the two-word representation and check zero, high-bit, maximum, and signed boundary values against exact outputs. The byte extraction masks each shifted word before narrowing it. The fixture also checks both constants, a one-byte step, known byte-sequence hashes, empty input, binary bytes, and a negative-length fallback. A separate native fixture confirms that overstating the physical byte view traps. The stdin fingerprint sample combines hashing with byte input and hexadecimal output. Direct imported `Hash<T>` calls remain outside the claim. |
| `core::crc32` all 3 public functions and 3 constants | Executable on x86_64 for caller-backed `[u8]` views | The native fixtures check CRC-32/ISO-HDLC on `123456789`, empty input, a one-byte prefix, binary bytes, and every byte value through the streaming interface. Negative logical lengths return the fallback without reading storage; an overstated physical view traps. A source scan requires a runtime call for every public function. |
| `core::option_i32` all 12 public functions and 8 receiver methods; `core::result_i32` all 10 public functions and 8 receiver methods | Executable on x86_64 | `tests/fixtures/stdlib_foundation/option_result_i32.lani` executes constructors, both presence/error states, payload and error predicates, fallbacks, both branches of `or`, `and`, and `xor`, and conversions between the two concrete types. Zero values and negative/extreme payloads distinguish an absent value or error from its stored number. A source scan requires every public function and receiver method to have a runtime call. The option/result sample chains imported receiver methods and prints `38`. Local aggregate forwarding is covered by the executable return suite; see dependency 39. |
| `core::option_u32` all 12 public functions and 8 receiver methods; `core::result_u32` all 10 public functions and 8 receiver methods | Executable on x86_64 | The matching runtime fixture covers every function and method with both variants, zero, ordinary values, the high bit, and `u32::MAX`. It executes borrowed predicates, fallbacks, aggregate-returning combinators, and Option-to-Result conversion. Both the success payload and error code are `u32`; inactive fields are zero. Source scans require every public function and method to have a runtime call. See dependency 39 for local return coverage. |
| `core::option_ptr` all 12 public functions and `core::result_ptr` all 10 public functions | Executable on x86_64 Linux | The imported fixture calls every function with two distinct live pointers, null as a present or successful payload, absence, negative and zero i32 errors, fallbacks, logical combinators, and conversions in both directions. The input-driven first-byte program passes a pointer result across a helper call, extracts its error through `OptionI32`, and reads real stdin including EOF and binary bytes. A source scan requires a runtime call for each public function. The modules do not allocate or own their pointers; the caller must keep pointed-to storage alive. User-program GPU device behavior is not claimed. |
| `core::option_u8` all 12 public functions and 8 receiver methods; `core::result_u8` all 10 public functions and 8 receiver methods | Executable on x86_64 | The byte fixture executes every function and method with `None`, `Some`, `Ok`, and `Err`, including zero, 128, and 255 payloads. It checks both branches of the aggregate-returning methods and imported method chains. Source scans require every public function and receiver method to have a runtime call. See dependency 39 for local return coverage. |
| `core::option` generic enum, 7 generic free functions, 6 generic receiver methods, 5 concrete free functions, and 6 concrete receiver methods; `core::result_bool` all 10 public functions and 8 receiver methods | Executable on x86_64 for the documented instances | Imported construction and both free and receiver tag predicates execute with bool, u8, u32, i32, f32, char, strings, caller-local fixed structs, and direct slices of the five tested scalar element types. Concrete matches preserve payload words, descriptor lengths, and borrowed aliasing. Shared generic free and receiver bodies provide explicit fallback extraction and the or, and, and xor combinators for bool, i32, u32, f32, char, and str. `flatten` collapses `Option<Option<T>>` for i32 payloads. Concrete contains methods compare five scalar identities; the unsigned implementation also executes tested u8 values. Separate integer-width type identity remains dependency 57. Scalar and string combinator tests execute all 16 state pairs, input preservation, extrema, NaN, negative zero, and empty string presence. Concrete slice-return functions handle absent empty and invalid input. Some(false), Some(0), and Some(empty_view) remain present. The bool methods include conversion to ResultBool. Wrong fallback and combinator payload arguments are rejected, subject to the integer-width limitation. Empty, cyclic, and monomorphic fixed-array-containing imported record layouts are rejected rather than assigned a guessed width. Tested generic records and direct i32/string array fallback payloads now execute; dependency 95 records this checkpoint. General structural substitution remains a dependency. The separate OptionBool type has been removed. See [the Option guide](stdlib-option.md) and dependencies 76, 84, 85, 86, 92, and 93 for supported layouts and restrictions. |
| `core::vec` generic `Vec<T, const N: usize>`, all 19 public functions | Executable on x86_64 for i32, char and `core::pair::Pair<char, i32>` items | A fixed-capacity vector stored inline in a caller-supplied `[T; N]` array, with value semantics: each change returns a new vector, and a failed push, insert, set, remove or swap returns it unchanged. `tests/fixtures/stdlib_foundation/generic_containers.lani` calls every function over all three item types and checks order, bounds, capacity and Option results; a source scan requires a call for every public function. There is no `contains` or `sort`, because bounds on the imported `core::cmp` traits do not dispatch yet (`tests/fixtures/generics_backlog/b02`, `b05`). |
| `core::set` generic `Set<T, const N: usize>`, the `Key` trait with i32, u32, char and bool implementations, and all 12 public functions | Executable on x86_64 for i32 and char items | A fixed-capacity insertion-ordered set over a caller-supplied `[T; N]` array. Equality is equality of `Key::key`, which is exact for the four implemented types. The consumer fixture inserts duplicates, removes items, checks `position_or`, `get`, `at_or`, `clear` and `is_subset` across two capacities, and builds a set of i32 digits. `Key` stands in for `core::cmp::Eq`: a bound dispatches only to a trait in the same module, without arguments, through a `self` member, so user types in other modules cannot implement it yet. |
| `core::pair` generic `Pair<A, B>`, all 5 public functions | Executable on x86_64 for i32 and char fields | Construction, both accessors, `swap`, and `zip` of two Options, including a None side. Pairs are stored in a `core::vec::Vec` in the consumer fixture. |
| `core::option_char` all 12 public functions and 8 receiver methods; `core::result_char` all 10 public functions and 8 receiver methods | Executable on x86_64 | The runtime fixture calls every function and method with both variants, NUL payloads, two distinct characters sharing a UTF-8 leading byte, and two-, three-, and four-byte Unicode scalars. It checks predicates, fallbacks, combinators, and conversions. Inactive payloads are NUL and must not be read without checking the tag. Source scans require runtime calls for every public function and method. |
| `core::option_f32` all 12 public functions and 8 receiver methods; `core::result_f32` all 10 public functions and 8 receiver methods | Executable on x86_64 | The runtime fixture calls every function and method with finite values, zero, negative values, and NaN payloads. It checks both variants, conversions, fallbacks, combinators, and IEEE unordered equality for NaN. Source scans require runtime calls for every public function and method. Local aggregate forwarding is covered by the executable return suite; see dependency 39. |
| `core::option_i8` all 12 public functions and 8 receiver methods; `core::result_i8` all 10 public functions and 8 receiver methods | Executable on x86_64 | The signed byte fixture executes every function and method with both variants, zero, `-128`, and `127`, including conversions, both combinator branches, and imported method chains. Source scans require runtime calls for every public function and method. See dependency 39 for local return coverage. |
| `core::option_i16` all 12 public functions and 8 receiver methods; `core::result_i16` all 10 public functions and 8 receiver methods | Executable on x86_64 | The signed halfword fixture executes every function and method with both variants, zero, `-32768`, and `32767`, including conversions, both combinator branches, and imported method chains. Source scans require runtime calls for every public function and method. See dependency 39 for local return coverage. |
| `core::option_u16` all 12 public functions and 8 receiver methods; `core::result_u16` all 10 public functions and 8 receiver methods | Executable on x86_64 | The unsigned halfword fixture executes every function and method with both variants, zero, `32768`, and `65535`, including conversions, both combinator branches, and imported method chains. Source scans require runtime calls for every public function and method. See dependency 39 for local return coverage. |
| `core::option_wide_u64` and `core::option_wide_i64` all 12 public functions each; `core::result_wide_u64` and `core::result_wide_i64` all 10 public functions each | Executable on x86_64 | Imported runtime fixtures call every function and check both variants, zero, signed or unsigned high-bit values, wide extrema, negative and zero i32 error codes, fallbacks, `or`, `and`, `xor`, and conversions between concrete Option and Result types. Each representation uses a tag and two 32-bit words; an Err stores its i32 code in the low word. These modules do not claim native `i64` or `u64` correctness. |
| `core::i8` all 28 public functions and 4 constants | Executable on x86_64 | The imported module fixture calls every function and reads every constant. It checks signed byte limits, wrapping and saturating overflow, checked results through `OptionI8`, ordinary comparisons and predicates, reversed bounds, and power-of-two overflow. |
| `core::i16` all 28 public functions and 4 constants | Executable on x86_64 | The imported module fixture calls every function and reads every constant. It checks `MIN` and `MAX`, ordinary and overflowing arithmetic, checked results through `OptionI16`, signed predicates, reversed bounds, comparison, and power-of-two overflow. |
| `core::i32` all 28 public functions and 4 constants | Executable on x86_64 | The imported module fixture checks each function's ordinary result and selected edge cases: `MIN` absolute value, checked and saturating overflow, wrapping arithmetic, signed predicates, range boundaries, and power-of-two overflow. Checked results use concrete `OptionI32`. |
| `core::u8` all 37 public functions and 4 constants | Executable on x86_64 | The imported module fixture checks every function, overflow and zero-divisor behavior, wrapping multiplication, ASCII classes and case conversion, and checked results through `OptionU8`. Its multiplication delegates to the tested `core::byte` implementation. |
| `core::u16` all 25 public functions and 4 constants | Executable on x86_64 | The imported module fixture calls every function and reads every constant. It checks ordinary and high-bit values, wrapping and saturating overflow, checked arithmetic through `OptionU16`, reversed bounds, zero divisors, power-of-two overflow, and invalid or overflowing alignment. |
| `core::u32` all 25 public functions and 4 constants | Executable on x86_64 | The imported module fixture checks every function, unsigned high-bit and maximum values, checked and wrapping arithmetic, alignment failures, and power-of-two overflow. Checked results use concrete `OptionU32`. |
| `core::ordering` all 20 public functions and `Ordering` variants | Executable on x86_64 | `tests/stdlib_ordering.rs` and `tests/stdlib_ordering_wide.rs` execute every function and direct qualified and unqualified `Less`, `Equal`, and `Greater` values through the real stdlib root. The imported unit-pattern fixture now executes matches for all three variants through annotated and inferred locals, a typed parameter, and a direct imported function result; negative fixtures reject unrelated enums, scalar scrutinees, unrelated call results, and payload bindings on unit variants. They cover predicates, reverse, then, all six scalar integer widths, Boolean false-before-true order, Unicode scalar order, unsigned high-bit comparison, and full-width signed and unsigned ordering through the two-word `WideI64` and `WideU64` types. `tests/stdlib_char_high_bit_execution.rs` also compares the unsigned character high bit and maximum through ordering, comparison, range, and slice helpers. `compare_f32_or` checks finite values, signed zero, infinities, and caller-supplied fallbacks for NaN. The broken primitive `compare_i64` was removed until native i64 literal and comparison lowering works (dependency 11). |
| `core::result` all twenty source-defined public functions and methods | Executable on x86_64 for the documented instances | The actual module imports with unsupported payload templates deferred. Generic free and receiver unwrap_or/unwrap_err_or/or/and execute for nine tested scalar T/E pairs, including f32, char, and strings in either or both positions. Every pair of two success and two error values is exercised for both receiver combinators, preserving both inputs. Predicates, membership, and concrete matches also execute for independently sized caller-local records, strings, and borrowed i32 slices. Runtime fixtures check concrete returns, descriptor aliasing, and bounds traps. Wrong success and error argument types are rejected independently. See [the Result guide](stdlib-result.md). |
| Generic payload bodies with compound, local, recursive, or durable-only specialization environments | Contract-only for native execution | Imported scalar free bodies and receiver bodies execute as documented above. Unsupported environments still require compiler support. Uninstantiated bodies retain their checked declarations and publish no native definition; a used unresolved template fails explicitly with `LNC0017`. The former by-value Option::replace ignored its input and was removed. Dependencies 1, 92, and 93 distinguish supported specialization from the remaining gaps. |
| Native `core::i64` as a complete module | Contract-only for native execution | Native full-width comparison and arithmetic remain incomplete. The explicitly two-word signed and unsigned modules above provide executable full-width operations. |
| `core::cmp` all 60 public free functions for six integer widths, `bool`, `char`, `WideU64`, and `WideI64` | Executable on x86_64 | The imported runtime fixture calls every equality and ordering function with equal and unequal values, both directions, signed and two-word extrema, unsigned high-bit values, both Boolean values, and Unicode characters. The `i32`, `u32`, `bool`, and `char` functions execute local trait implementation bodies. Narrow integer functions use scalar operators because their trait keys collide with the corresponding 32-bit type (dependency 57); two-word functions use the executable wide modules because imported nominal trait arguments fail in native emission (dependency 58). Direct imported trait calls remain outside this claim. |
| `core::cmp` trait methods and `core::hash::Hash<T>` trait methods | Complete API coverage not refreshed | The public free comparison and hashing functions execute. The later [compiler checkpoint](compiler-generic-types.md#direct-generic-trait-implementation-methods-2026-10-11) establishes focused direct imported generic trait impl methods, but does not rerun these complete stdlib trait APIs. Dependencies 31, 57, and 58 retain the original audit evidence. |
| `core::target` all 18 public functions and 16 constants | Executable x86_64 Linux capability metadata | The native fixture executes every function and reads every constant. It checks the available allocator, filesystem, stdio, clock, secure RNG, process, and environment bindings against `core::runtime`; unbound network, threads, GPU, host services, panic hooks, and test harness remain false. This is a target snapshot, not a live host probe. |
| `core::runtime` all 62 public functions and 40 constants | Executable x86_64 Linux capability metadata | The native fixture executes every function and reads every constant, checking service IDs, ABI fields, available and unavailable services, unknown IDs, status classifiers, and fail-closed requirement rows. These helpers report bindings; they do not implement an unbound service operation. |
| `core::panic` both trap functions, all 19 metadata functions, and 4 constants | Executable on x86_64 Linux for the trap functions and metadata | `tests/stdlib_panic_execution.rs` checks that `panic()` and `unreachable()` terminate with SIGILL, and a runtime fixture checks every metadata result. Panic hooks remain unbound; their availability flags stay false. |
| `alloc::allocator` all 32 public metadata functions and 4 host calls | Executable x86_64 Linux host ABI for valid allocation arguments | The native metadata fixture calls every metadata function, checks available service flags and null/non-null pointer classification against `core::runtime`, and performs a real allocation and release. `tests/stdlib_allocator_metadata_execution.rs` requires a runtime call for each metadata function. Normal allocation, reallocation, and release have x86 tests; the `alloc_failed` host call is tested as terminating with exit status 1. `tests/stdlib_allocator_failure_execution.rs` injects `ENOMEM` into `mmap` and `mremap`: both return null, and failed reallocation leaves the old storage readable and releasable. The API is low-level; callers must pass a valid pointer and matching sizes to `realloc` and `dealloc`. |
| `std::process` all 44 metadata functions, 12 constants, and 4 host calls | Executable on x86_64 Linux | The foundation runtime fixture checks every metadata function and constant, including successful and failed argument results, service availability, and exit status helpers. Native source-pack tests execute `argc`, `arg_len`, and `arg_read` with real process arguments; the process exit sample confirms that `exit(7)` terminates with status 7. An imported helper also executes `exit` through a transitive import and a directly declared host call. This module reports the Linux host binding; GPU device execution is not claimed. |
| `std::env` all 54 public functions, 13 constants, and 6 host calls | Executable on x86_64 Linux | The foundation runtime fixture checks every metadata function and constant and calls `current_dir_len`. Native source-pack tests exercise environment lookup, enumeration, key reads, and current-directory reads with real host state. The focused environment suite checks missing keys, bounded storage, host failure, and allocation failure in `current_dir_len`. GPU device execution is not claimed. |
| `std::io` all 54 public Lanius functions, 12 constants, and 7 host calls | Executable on x86_64 Linux | The foundation runtime fixture checks every metadata function and constant. Existing I/O fixtures execute all six higher-level public functions, including line output, `print_i32`, and synchronous flush semantics. Native tests exercise the seven bound calls with real stdin, stdout, stderr, and file handles, including short writes and host errors. GPU device execution is not claimed. |
| `std::fs` all 67 public Lanius functions, 18 constants, and 14 host calls | Executable on x86_64 Linux | The foundation fixture checks every metadata function and constant. Native tests exercise raw open, append, read, write, close, path mutation, string paths, and decimal reads. Pointer path calls consume their supplied lengths and reject invalid bounds or embedded NUL bytes; decimal reads reject overflow. The file suite covers normal paths, missing paths, and host failures. GPU device execution is not claimed. |
| `std::random` all 28 metadata functions, 8 constants, and 2 host calls | Executable on x86_64 Linux | The foundation fixture executes every metadata function and reads every constant. `fill_secure_bytes` returns a byte count or negative error, including after unrelated host calls (resolved dependency 44). The raw `secure_u32` returns a full-width draw or traps on a short read or host error (resolved dependency 18). GPU device execution is not claimed. |
| `std::time` all 53 public metadata functions and 7 host calls | Mixed: bound calls executable; i64 declarations contract-only | The native metadata fixture calls every public metadata function, checks available and unavailable capabilities, classifies ordinary and failure results, and directly executes all four bound host calls: two 16-byte clock reads, i32 millisecond sleep, and Unix seconds. The broad `clock_read_api_*` and `clock_sleep_api_*` flags now describe their unbound i64 calls, and their fail-closed helpers recognize the unavailable result; separate timespec and i32 sleep flags describe the bound calls. Its i64 result checks cover only small values; full-width i64 behavior remains blocked by dependency 11. `std::time_checked` tests bounded operations and host failures. Consult `laniusc diagnostics runtime-apis` for per-call binding status. |
| `std::args_checked` all 3 public helpers | Executable x86_64 Linux host wrappers | `tests/stdlib_host_execution.rs` runs a Lanius program with nonempty and empty arguments. It checks argument count including the executable, exact byte lengths and bytes, absent/negative indices, sufficient and insufficient capacity, null storage, and capacity above `i32::MAX`. Caller storage avoids allocation. |
| `std::env_checked` all 3 public helpers | Executable x86_64 Linux host wrappers | `tests/stdlib_env_execution.rs` checks exact value and key bytes, missing and invalid indices, capacity and null-storage failures, current-directory bytes and its NUL terminator, and injected `getcwd` failure. Caller storage avoids allocation. |
| `std::time_checked` all 3 public helpers | Executable x86_64 Linux host wrappers | `tests/stdlib_time_execution.rs` checks both 16-byte clock reads, nanosecond bounds, a measured 50 ms sleep, invalid buffers/lengths, negative sleep, injected clock failures, and an interrupted host sleep. Caller storage avoids allocation and i64 scalar results. |
| `std::time_wide` all 5 public helpers | Executable x86_64 Linux host wrappers and two-word seconds decoding | The native suite calls every function, checks synthetic positive seconds above 32 bits and negative seconds, nanosecond boundaries, invalid views and unchanged short-capacity storage, real monotonic and system clock reads, a physical backing overclaim that traps before the host call, and injected failures for both clocks. No native scalar `i64` result or allocation is required. |
| `std::io::{write_line,println,eprintln,flush_stdout,flush_stderr,print_i32}` | Executable x86_64 host wrappers | `tests/stdlib_host_execution.rs` checks stdout, stderr, empty lines, exact byte counts, invalid handles, synchronous flushes, and signed printing through the real stdlib root. These are separate from the portable core. |
| `std::io_checked` all 5 public helpers | Executable x86_64 Linux host wrappers | `tests/stdlib_io_checked_execution.rs` checks exact stdin, bounded read-to-EOF, stdout, and stderr bytes; empty, exact-fit, and overlong input; invalid storage; EOF after a read prefix; host errors and zero progress; retries after short transfers; and a multi-chunk binary stdin-to-stdout copy. Caller storage avoids allocation. |
| `std::io_byte` all 3 public helpers | Executable x86_64 Linux host wrappers | `tests/stdlib_io_byte_execution.rs` checks scalar reads of ASCII, NUL, and 255, a distinct EOF fallback, checked stdout and stderr bytes, invalid values without writes, and injected read and write errors. `sample_programs/hex_to_decimal.lani` combines it with portable byte and hex helpers. The implementation uses one synchronous host call per byte. |
| `std::io_line` all 3 public helpers | Executable x86_64 Linux host wrappers | `tests/stdlib_io_line_execution.rs` checks multiple LF lines, exact-fit and zero capacities, EOF after a partial line, overlong-line consumption, CR and NUL bytes, stdout and stderr output, invalid codes without output, injected host errors, and native trapping on an overstated backing view. Bytes are stored as integers in caller-owned `[i32]` storage. |
| `std::io_utf8` all 7 public helpers | Executable x86_64 Linux host wrappers | `tests/stdlib_io_utf8_execution.rs` checks one- through four-byte scalar reads and writes, checked output of caller-backed `[i32]` UTF-8 byte-code and ordinary `[u8]` views, the Unicode maximum, distinct EOF and failure fallbacks, malformed and truncated input, invalid values without writes, native bounds trapping before output, and injected read and write errors. It does not access borrowed string storage. |
| `std::io_decimal` all 16 public helpers | Executable x86_64 Linux host wrappers | `tests/stdlib_host_execution.rs` checks signed and unsigned output extrema across 8-, 16-, 32-, and two-word 64-bit integers, exact byte counts, invalid handles, and injected sign and digit write failures for the underlying 32-bit writers. The two-word decimal-double programs also write full-width results through this module. `tests/stdlib_io_decimal_input_execution.rs` checks bounded stdin parsing across the six scalar and both two-word 64-bit types, EOF, whitespace and signs, malformed and overlong input, overflow, and injected read failures. |
| `std::io_hex` all 9 public helpers | Executable x86_64 Linux host wrappers | `tests/stdlib_io_hex_execution.rs` checks exact lowercase and uppercase writes across `u8`, `u16`, and `u32`, counts, invalid handles, injected write failures, bounded stdin parsing with optional prefix and whitespace, malformed and overflowing input, and injected read failures. |
| `std::io_hex_wide_u64` all 3 public two-word helpers | Executable x86_64 Linux host wrappers | The native suite calls every function and checks shortest lowercase and uppercase output, byte counts, invalid handles, full-width stdin values, optional prefixes, surrounding whitespace, malformed and overflowing input, exact and exceeded byte limits, and zero-limit behavior. With Linux `strace`, it also checks first and later short writes, write errors, and injected read failures. |
| `std::io_hex_wide_i64` all 3 public signed two-word helpers | Executable x86_64 Linux host wrappers | The native suite calls every function and checks shortest lowercase and uppercase signed output, byte counts, invalid handles, both signed extrema, ordinary negative stdin values, optional signs and prefixes, surrounding whitespace, malformed and overflowing input, exact and exceeded byte limits, and zero-limit behavior. With Linux `strace`, it checks first and later short writes, write errors, and injected read failures. |
| `std::io_binary` all 6 public helpers | Executable x86_64 Linux host wrappers | `tests/stdlib_io_binary_execution.rs` checks shortest binary writes across `u8`, `u16`, and `u32`, exact byte counts, invalid handles, injected write failures, bounded stdin parsing with optional prefix and whitespace, malformed and overflowing input, and injected read failures. |
| `std::io_binary_wide_u64` both public two-word helpers | Executable x86_64 Linux host wrappers | The native suite calls both functions and checks shortest zero and full-width binary writes, byte counts, invalid handles, full-width stdin values, optional prefixes, surrounding whitespace, malformed and overflowing input, exact and exceeded byte limits, and zero-limit behavior. With Linux `strace`, it checks first and later short writes, write errors, and injected read failures. |
| `std::io_binary_wide_i64` both public signed two-word helpers | Executable x86_64 Linux host wrappers | The native suite calls both functions and checks shortest signed zero, ordinary negative, maximum, and minimum writes; exact byte counts and invalid handles; bounded stdin with optional signs and prefixes, whitespace, malformed and overflowing input, exact and exceeded byte limits, and zero-limit behavior. With Linux `strace`, it checks first and later short writes, write errors, and injected read failures. |
| `std::file_hex` all 9 public helpers | Executable x86_64 Linux host wrappers with literal paths | `tests/stdlib_file_hex_execution.rs` checks lowercase and uppercase writes, bounded hexadecimal file reads across `u8`, `u16`, and `u32`, whitespace and optional prefixes, malformed and overflowing input, missing and overlong files, and injected read/write/close errors. |
| `std::file_hex_wide_u64` all 3 public two-word helpers | Executable x86_64 Linux host wrappers with literal paths | The native fixture calls every function and checks lowercase and uppercase output at zero, the word boundary, a mixed full-width pattern, and the maximum; bounded full-width reads, optional prefixes and whitespace, missing and malformed files, exact and exceeded byte limits, overflow, invalid output paths, and `/dev/full`. With Linux `strace`, it checks short and failing writes plus read and close failures. |
| `std::file_hex_wide_i64` all 3 public signed two-word helpers | Executable x86_64 Linux host wrappers with literal paths | The native fixture calls every function and checks shortest lowercase and uppercase output at zero, an ordinary negative value, and both signed extrema; bounded signed reads with optional signs and prefixes, whitespace, malformed and overflowing input, exact and exceeded byte limits, missing files, invalid output paths, and `/dev/full`. With Linux `strace`, it checks short and failing writes plus read and close failures. |
| `std::file_binary` all 6 public helpers | Executable x86_64 Linux host wrappers with literal paths | `tests/stdlib_file_binary_execution.rs` checks shortest binary file writes and bounded reads across `u8`, `u16`, and `u32`, whitespace and optional prefixes, malformed, missing, overlong, and overflowing input, plus injected read/write/close errors. |
| `std::file_binary_wide_u64` both public two-word helpers | Executable x86_64 Linux host wrappers with literal paths | The native fixture calls both functions and checks shortest zero, word-boundary, high-bit, and maximum writes; full-width bounded reads, optional prefix and surrounding whitespace, missing and malformed files, exact and exceeded byte limits, overflow, invalid output paths, and `/dev/full`. With Linux `strace`, it checks short and failing writes plus read and close failures. |
| `std::file_binary_wide_i64` both public signed two-word helpers | Executable x86_64 Linux host wrappers with literal paths | The native fixture calls both functions and checks shortest signed output at zero, an ordinary negative value, the word boundary, and both signed extrema; bounded reads with optional signs and prefixes, whitespace, malformed and overflowing input, exact and exceeded byte limits, missing files, invalid output paths, and `/dev/full`. With Linux `strace`, it checks short and failing writes plus read and close failures. |
| `std::file` all 25 public helpers | Executable x86_64 Linux host wrappers | `tests/stdlib_file_execution.rs` checks text writes, one-shot, exact, and read-to-end caller-buffer reads, complete handle and path buffer writes, multi-chunk binary copies between files and standard streams, bounded decimal reads and writes across 8-, 16-, 32-, and two-word 64-bit integers, empty and overlong files, invalid buffer sizes, missing paths, injected read/write/close errors, and write failures using `/dev/full`. `copy_distinct_with_buffer` requires distinct underlying files and a valid writable buffer. |
| `std::random_checked` all 6 public helpers | Executable x86_64 Linux host wrappers | `tests/stdlib_random_execution.rs` checks exact caller-buffer filling, zero length and invalid arguments, host errors and zero progress, short-read retries, bounded and inclusive unsigned and signed outputs, forced draws and rejection, full-range failure fallbacks, and secure i32 slice shuffling with preserved contents, a forced swap, and injected failure. The suite also runs a raw fill after a directory read to guard the runtime flags fix, and confirms that the raw scalar traps on host failure and short reads. |
| `std::random_wide` all 5 public helpers | Executable x86_64 Linux host wrappers | `tests/stdlib_random_wide_execution.rs` runs all five functions, 64-bit unsigned and signed ranges including singleton, reversed, full-domain, and near-maximum cases, zero and unit bounds, and injected host errors, zero progress, short reads, and rejection. Results use concrete `OptionWideU64` and `OptionWideI64` values. |
| `std::path` all 17 constants and all 38 public functions | Executable on x86_64 | `tests/stdlib_path_execution.rs` runs ordinary and boundary cases for byte classes, separator kind, component headers, path headers, full caller-backed component bytes, and last-component, extension, and stem byte offsets. The final-component helpers treat slash and backslash as separators, ignore trailing separators, accept non-UTF-8 bytes, and return the supplied fallback for empty or separator-only paths, negative lengths, or embedded NUL. A leading dot alone and a trailing dot do not create an extension. The two-byte header classifiers inspect only the supplied header when `length > 2`; the complete-view helpers inspect every byte. The new `path_component_is_windows_portable_utf8` also validates UTF-8 and rejects user-facing Win32 reserved device names, including extension and superscript-digit forms, plus trailing spaces and periods. It does not probe target filesystem limits. The older `path_component_matches_windows_relative_byte_rules` retains its explicitly byte-level behavior, including accepting device names and trailing spaces/dots. Negative and empty lengths return false in these classifiers; an overstated positive length can trap on native indexing. Allocation and host normalization are unavailable. |
| `std::deque_wide_i64` all 20 public functions and its capacity constant | Executable on x86_64 Linux | The owned ring-buffer fixture calls every public function and checks pair-preserving front/back operations, wrapped order, growth, reservation, shrinking, clone independence, invalid bounds, signed minimum, and signed maximum. Six injected `mmap` failures leave prior logical values and ownership intact. The line-oriented recent-values program reads and writes negative full-width decimal values, including both signed extremes, and rejects malformed, overflowing, or underflowing input. Each value occupies two 32-bit cells; no native `i64` or user-program GPU device behavior is claimed. |
| `std::deque_wide_u64` all 20 public functions and its capacity constant | Executable on x86_64 Linux | The owned ring-buffer fixture calls every public function and checks pair-preserving front/back operations, wrapped order, growth, reservation, shrinking, clone independence, invalid bounds, `2^32`, the unsigned high bit, and `u64::MAX`. Six injected `mmap` failures leave prior logical values and ownership intact. The line-oriented recent-values program reads and writes full-width decimal values and rejects malformed or overflowing input. Each value occupies two 32-bit cells; no native `u64` or user-program GPU device behavior is claimed. |
| `std::deque_bool` all 20 public functions and its capacity constant | Executable on x86_64 Linux | The owned ring buffer stores canonical Boolean values as zero or one in 32-bit cells. The imported fixture calls every public function and checks both-end operations, wraparound, growth, reservation, shrinking, cloning, empty access, and invalid bounds. A deterministic 48-operation test compares the deque with a reference after every step. Six injected allocation failures preserve the original owner and values, or return an empty clone. The recent-Boolean-count program combines it with byte classification and stdin, including malformed input. Capacity is limited to 536,870,911 values; ownership is linear by convention. GPU compiler execution emits the tested x86 program; user-program GPU device behavior is not claimed. |
| `std::deque_char` all 20 public functions and its capacity constant | Executable on x86_64 Linux | The imported fixture calls every function and checks both-end operations, wrapped order, growth, reservation, shrinking, clone independence, empty access, invalid bounds, plane-15 code points, and the largest scalar. A second fixture checks ASCII, NUL, two-, three-, and four-byte Unicode scalars through wrapping, cloning, mutation, and shrinking. Six injected `mmap` failures preserve the original owner and logical order, or return an empty clone. The stdin-driven recent-Unicode program checks empty and multibyte input, wraparound, NUL, malformed input, truncated UTF-8, and output failure. Each character occupies one eight-byte `char` slot. Ownership is linear by convention. GPU frontend compilation emits the tested x86 program; user-program GPU execution is not claimed. |
| `std::deque_i16` all 20 public functions and its capacity constant | Executable on x86_64 Linux | The owned ring-buffer fixture calls every public function and checks both-end operations, wraparound, growth, reservation, shrinking, cloning, empty access, invalid bounds, and an exhaustive round trip of all 65,536 signed-halfword values. A 48-operation execution test compares mixed mutations with a reference deque after every step. Six injected allocation failures preserve the original owner and order, or return an empty clone. The recent-values program reads signed decimal lines, prints the last three values, and rejects malformed, overlong, and out-of-range input. Each value occupies one 32-bit backing cell; ownership is linear by convention. The GPU compiler emits the tested x86 program; user-program GPU device behavior is not claimed. |
| `std::deque_i8` all 20 public functions and its capacity constant | Executable on x86_64 Linux | The owned ring-buffer fixture calls every public function and checks both-end operations, wraparound, growth, reservation, shrinking, cloning, empty access, invalid bounds, and all 256 signed-byte values from `-128` through `127`. A 48-operation execution test compares mixed mutations with a reference deque after every step. Six injected allocation failures preserve the original owner and order, or return an empty clone. The recent-values program reads signed decimal lines, prints the last three values, and rejects malformed, overlong, and out-of-range input. Each value occupies one 32-bit backing cell; ownership is linear by convention. The GPU compiler emits the tested x86 program; user-program GPU device behavior is not claimed. |
| `std::deque_u16` all 20 public functions and its capacity constant | Executable on x86_64 Linux | The owned ring-buffer fixture calls every public function and checks both-end operations, wraparound, growth, reservation, shrinking, cloning, empty access, invalid bounds, and an exhaustive round trip of all 65,536 unsigned-halfword values. A 48-operation execution test compares mixed mutations with a reference deque after every step. Six injected allocation failures preserve the original owner and order, including high-bit and maximum values, or return an empty clone. The recent-values program reads unsigned decimal lines, prints the last three values, and rejects malformed, overlong, negative, and out-of-range input. Each value occupies one 32-bit backing cell; ownership is linear by convention. The GPU compiler emits the tested x86 program; user-program GPU device behavior is not claimed. |
| `std::deque_u8` all 20 public functions and its capacity constant | Executable on x86_64 Linux | The owned byte ring-buffer fixture calls every public function and checks both-end operations, wraparound, growth, reservation, shrinking, clone independence, invalid bounds, and all 256 byte values. The stateful fixture checks 48 mixed operations against a reference deque. Six injected allocation failures preserve the original owner and order, or return an empty clone. A binary-input checksum program combines the deque with byte arithmetic, `OptionU8`, and stdin. Each byte occupies one 32-bit backing cell; ownership is linear by convention. GPU compiler execution emits the tested x86 program; user-program GPU device execution is not claimed. |
| `std::deque_u32` all 20 public functions and its capacity constant | Executable on x86_64 Linux | The owned ring-buffer fixture calls every public function and checks both-end operations, wrapped order, growth, reservation, shrinking, clone independence, invalid bounds, `2^31`, and `u32::MAX` through mutation and copying. Six injected `mmap` failures preserve existing data and ownership. The line-oriented recent-values program checks unsigned decimal input, output, full-width values, malformed input, and overflow. Each value occupies one 32-bit cell; ownership is linear by convention. The GPU compiler emits the tested x86 program, with no user-program GPU device claim. |
| `std::deque_i32` all 20 public functions and its capacity constant | Executable on x86_64 Linux | The owned ring-buffer fixture calls every public function and checks both-end pushes and pops, wrapped storage, growth, reservation, shrinking, clone independence, signed extrema, empty and invalid-index behavior, and destruction. Six injected `mmap` failures cover initial allocation, both-end growth, wrapped reservation, cloning, and shrinking; existing contents and ownership remain intact. The line-oriented recent-values program combines the deque with decimal parsing and output and checks normal, extreme, malformed, and overlong input. Ownership is linear by convention. The GPU compiler emits the tested x86 program; no user-program GPU device behavior is claimed. |
| `std::vec_i32` all 25 public functions and its capacity constant | Executable on x86_64 Linux | `tests/fixtures/stdlib_foundation/vec_i32.lani` checks construction, growth, element access and mutation, bounds, reserve, pop, clear, cloning, and destruction. `tests/stdlib_vec_i32_sort_search_execution.rs` executes in-place signed sort and reverse, lower and upper bounds, and first and last binary matches against owned storage, including empty vectors, duplicates, and signed extrema. Searches require nondecreasing input; empty searches return zero or the caller's fallback. Sort returns len, reverse returns swap count, and both preserve capacity. The median program combines these operations with checked decimal input and output. `tests/stdlib_vec_i32_execution.rs` injects allocation and reallocation failures and checks the vector and prior data stay unchanged. This is a linear-ownership API by convention; source-level moves are not enforced. |
| `std::vec_u32` all 25 public functions and its capacity constant | Executable on x86_64 Linux | The unsigned vector fixture checks construction, growth, access, mutation, bounds, reserve, pop, clear, cloning, destruction, `2^31`, and `u32::MAX`. The sort/search fixture checks owned in-place unsigned sort and reverse, lower and upper bounds, first and last matches, empty storage, duplicates, capacity preservation, and high-bit order; search requires sorted input. The signed-bit-pattern backing is ordered through `core::u32_cells`. The input-driven median program checks normal output, signed-bit extremes interpreted as unsigned, and invalid decimal input. The allocation-failure suite injects failed initial allocation and reallocation. Storage uses 32-bit cells and preserves every unsigned bit pattern. Ownership is linear by convention. |
| `std::vec_wide_i64` all 25 public functions and its capacity constant | Executable on x86_64 Linux | The native fixture calls every function and checks pair-preserving growth, access, mutation, insertion, removal, caller-backed batch append, reserve, clone independence, resize, truncation, shrink, clearing, destruction, both signed extrema, the 32-bit boundary, invalid indices and capacities, and a physical input-view overclaim that traps. Injected initial, growth, batch-append, insert, resize, clone, and shrink allocation failures preserve prior values or return an empty clone. The owned ordering fixture checks in-place signed sort and reverse, lower and upper bounds, first and last matches, duplicates, empty storage, both signed extrema, and retained capacity. Search requires sorted input. Signed decimal sum and median-frequency programs use the vector with real input, including full-width values and malformed cases. Each element uses two 32-bit cells; ownership is linear by convention. |
| `std::vec_wide_u64` all 25 public functions and its capacity constant | Executable on x86_64 Linux | The native fixture calls every function and checks pair-preserving growth, access, mutation, insertion, removal, caller-backed batch append, reserve, clone independence, resize, truncation, shrink, clearing, destruction, zero, `2^32`, `2^63`, and `u64::MAX`, invalid indices and capacities, and a physical input-view overclaim that traps. Injected initial, growth, batch-append, insert, resize, clone, and shrink allocation failures preserve prior values or return an empty clone. The owned ordering fixture checks in-place unsigned sort and reverse, lower and upper bounds, first and last matches, duplicates, empty storage, the unsigned high bit, and retained capacity. Search requires sorted input. Unsigned decimal sum and median-frequency programs use the vector with real input, including full-width values and malformed cases. Each element uses two 32-bit cells; ownership is linear by convention. |
| `std::vec_u8` all 26 public functions and its capacity constant | Executable on x86_64 Linux | The byte vector fixture checks construction, growth, independent cloning, access, mutation, bounds, reserve, pop, clear, destruction, 128, and 255. The sort/search fixture checks in-place ascending byte order, reversal, lower and upper bounds, first and last matches, empty and single-element behavior, duplicates, boundary values, and unchanged allocation pointer. Search requires sorted input. Raw writes through `data_ptr` must preserve the 0..255 initialized-cell invariant; the fixture also checks empty and initialized borrowed views. The allocation-failure suite injects failed initial allocation, reallocation, and a clone allocation through the text wrapper; the byte checksum sample combines it with `core::byte` and `OptionU8`. Each byte occupies one 32-bit cell because the raw-slice intrinsic currently accepts i32 cells. Ownership is linear by convention. |
| `std::utf8_vec` all 30 public text helpers | Executable on x86_64 Linux | The runtime fixtures construct and edit text from Unicode scalars, complete caller-backed UTF-8 byte-code views, and ordinary `[u8]` byte views; check independent cloning, multibyte bytes, scalar count and lookup, first and last search, equality, prefixes, suffixes, ordering, byte-offset sequence search, insertion, removal, replacement, splicing, pop, clear, and destruction. Byte-view splicing covers growth, shrinkage, equal-width replacement, and insertion at the end; malformed input and invalid indices leave data unchanged. Injected allocation failures check that failed scalar, byte-code, and `[u8]` edits preserve prior bytes. Storage is a `VecU8` with one 32-bit cell per encoded byte and linear ownership by convention. |
| `std::vec_i8` all 25 public functions and its capacity constant | Executable on x86_64 Linux | The signed byte vector fixture checks construction, growth, access, mutation, bounds, reserve, pop, clear, cloning, destruction, `-128`, and 127. The sort/search fixture executes in-place signed ordering, reversal, lower and upper bounds, first and last matches, empty and single-element behavior, duplicates, signed limits, and capacity preservation. Search requires nondecreasing input; sort returns len and reverse returns swap count. The allocation-failure suite injects failed initial allocation and reallocation; the signed byte sum sample combines it with `core::number_i8` and `OptionI8`. Each signed byte occupies one 32-bit cell, preserving its sign. Ownership is linear by convention. |
| `std::vec_u16` all 25 public functions and its capacity constant | Executable on x86_64 Linux | The unsigned halfword fixture checks construction, growth, access, mutation, bounds, reserve, pop, clear, cloning, destruction, 32768, and 65535. The sort/search fixture executes in-place ordering, reversal, lower and upper bounds, first and last matches, empty and single-element behavior, duplicates, the unsigned high bit, maximum value, and capacity preservation. Search requires nondecreasing input; sort returns len and reverse returns swap count. The allocation-failure suite injects failed initial allocation and reallocation; the halfword checksum sample combines it with `core::number_u16` and `OptionU16`. Each halfword occupies one 32-bit cell. Ownership is linear by convention. |
| `std::vec_char` all 25 public functions and its capacity constant | Executable on x86_64 Linux | Imported runtime fixtures call every function, checking construction, growth, independent cloning, indexed access and mutation, insertion, removal, bulk append, resize, truncation, shrinking, destruction, invalid indices and capacities, Unicode scalars, NUL, and the largest scalar U+10FFFF. Ordering and search use unsigned code-point order; the sort/search fixture checks empty, single-element, duplicate, and maximum-value cases. Seven injected allocation failures cover initial allocation, growth, batch append, insertion, cloning, resize, and shrinking; each retains the prior owner or returns an empty clone. The input-driven `unicode_sort_unique` program reads valid UTF-8 scalars, sorts and deduplicates them, and reports malformed input, size limit, allocation failure, and output failure. Each character occupies one eight-byte slot read and written as `char`, so no integer conversion is involved. Ownership is linear by convention. |
| `std::vec_i16` all 25 public functions and its capacity constant | Executable on x86_64 Linux | The signed halfword fixture checks construction, growth, access, mutation, bounds, reserve, pop, clear, cloning, destruction, `-32768`, and 32767. The sort/search fixture executes in-place signed ordering, reversal, lower and upper bounds, first and last matches, empty and single-element behavior, duplicates, signed limits, and capacity preservation. Search requires nondecreasing input; sort returns len and reverse returns swap count. The allocation-failure suite injects failed initial allocation and reallocation; the signed halfword sum sample combines it with `core::number_i16` and `OptionI16`. Each halfword occupies one 32-bit cell. Ownership is linear by convention. |
| `std::vec_bool` all 25 public functions and its capacity constant | Executable on x86_64 Linux | The boolean fixture checks construction, growth, access, mutation, bounds, reserve, pop, clear, cloning, destruction, and stored `false` distinct from a `true` fallback. The sort/search fixture executes false-before-true ordering, reversal, lower and upper bounds, first and last matches, absent-value fallbacks, empty and single-element vectors, duplicate values, and retained capacity. Searches require sorted input; sort returns len and reverse returns swap count. The allocation-failure suite injects failed initial allocation and reallocation; the true-count sample combines it with `core::bool` and `Option<bool>`. Each boolean occupies one 32-bit cell containing 0 or 1. Ownership is linear by convention. |
| `std::map_i32_i32` all 16 public functions and its entry-limit constant | Executable on x86_64 Linux | A single allocator-backed pair array provides linear lookup, insertion without partial pairs, in-place update, ordered removal, reservation, independent cloning, clearing, capacity release, and destruction. The native fixture calls every function and checks zero and negative keys and values, the signed maximum key, duplicates, missing keys, ordinal bounds, retained and reduced capacity, and clone independence. Injected initial, growth, shrink, and clone allocation failures preserve the original map or return an empty clone. The byte-histogram program combines it with numeric and byte I/O helpers on empty, text, and binary input. Ownership is linear by convention. A deterministic 40-operation execution test checks insertion order, lookup, update, removal, reserve, shrink, clear, clone independence, and invalid bounds against a reference map after every step. |
| `std::map_u32_u32` all 16 public functions and its entry-limit constant | Executable on x86_64 Linux | A single allocator-backed pair array preserves full unsigned key and value bit patterns, including `2^31` and `u32::MAX`. The native fixture calls every function and checks insertion, lookup, in-place update, duplicates, missing keys, insertion order, stable removal, invalid ordinals and capacities, cloning, clearing, growth, and shrinking. Injected initial, growth, shrink, and clone allocation failures preserve prior entries or return an empty clone. A frequency-report program combines the map with numeric and I/O helpers. Ownership is linear by convention. A deterministic 40-operation execution test checks insertion order, lookup, update, removal, reserve, shrink, clear, clone independence, and invalid bounds against a reference map after every step. |
| `std::map_bool_u32` all 10 public functions | Executable on x86_64 Linux | An allocation-free three-word value stores zero, one, or two Boolean keys in insertion order, with full-width `u32` values. The imported fixture calls every function and checks empty and populated lookup, zero distinct from absence, both key orders, replacement without reordering, removal, clearing, invalid ordinals, high-bit and maximum values, and independent value copies. The stdin-driven digit-byte counter combines the map with byte classification and decimal I/O; tests cover empty, text, and binary input and output failure. No capacity, allocator, or destruction service is needed. GPU frontend compilation emits the tested x86 program; user-program GPU execution is not claimed. |
| `std::map_u8_u32` all 12 public caller-backed functions | Executable on x86_64 Linux for eight key words and 256 value words | The dense map uses `std::set_u8` for membership and a caller-owned `u32` value cell for every byte. The imported fixture calls every function and checks all 256 possible keys, zero and `u32::MAX` values, ascending ordinals, missing and duplicate insertions, replacement, present-only updates, removal, clearing, full capacity, and invalid ordinals. Clearing a short physical value view traps with exit 101. The stdin frequency report handles empty, repeated, binary, and every-byte input, including ties and output failure. GPU frontend compilation emits the tested x86 program; user-program GPU execution is not claimed. |
| `std::map_i8_u32` all 12 public caller-backed functions | Executable on x86_64 Linux for eight key words and 256 value words | Signed keys use the -128 through 127 ordering of `std::set_i8` over a shifted byte-keyed dense map. The imported fixture calls every function; checks negative, zero, and positive keys, `u32::MAX` and zero values, duplicate insertions, replacement, present-only updates, removal, invalid ordinals, and clearing; then exercises all 256 keys and values through lookup and signed ordinals. Caller-owned value storage is constructed with `core::mem::typed_slice_from_raw_parts<u32>` and freed after the program. Short physical key and value views both exit 101. The signed-byte frequency program reads real binary input, handles empty input, ties, signed extremes, and all 256 bytes, prints the most frequent signed value and distinct count, and reports output failure. User-program GPU execution is unverified. |
| `std::map_char_u32` all 16 public functions and its entry-limit constant | Executable on x86_64 Linux | The imported fixture calls every function and checks ordered insertion, duplicate keys, lookup, in-place update, stable removal, reservation, clone independence, shrinking, invalid bounds and capacities, high character keys up to U+10FFFF, and `u32::MAX` values. A second fixture checks NUL, Unicode keys, the largest scalar, and zero values. Four injected allocation failures preserve existing entries and ownership, or return an empty clone. The input-driven Unicode frequency report checks empty input, multibyte duplicates, NUL, malformed and truncated UTF-8, and output failure. An entry occupies 16 bytes: a `char` key slot followed by a `u32` value slot. Ownership is linear by convention. GPU frontend compilation emits the tested x86 program; user-program GPU execution is not claimed. |
| `std::map_wide_u64_wide_u64` all 16 public functions and its entry-limit constant | Executable on x86_64 Linux | A single allocator-backed array stores each key and value as two 32-bit words, preserving zero, `2^32`, the unsigned high bit, and `u64::MAX`. The native fixture calls every function and checks insertion, full-width lookup, in-place replacement, duplicates, missing keys, insertion order, stable removal, invalid ordinals and capacities, independent cloning, clearing, growth, and shrinking. Injected initial, growth, shrink, and clone allocation failures preserve prior entries or return an empty clone. The line-oriented frequency program covers duplicate full-width inputs and malformed input. Ownership is linear by convention; no native `u64` behavior is claimed. A deterministic 40-operation execution test checks insertion order, lookup, update, removal, reserve, shrink, clear, clone independence, and invalid bounds against a reference map after every step. |
| `std::map_wide_i64_wide_i64` all 16 public functions and its entry-limit constant | Executable on x86_64 Linux | A single allocator-backed array stores signed two-word keys and values as unchanged two's-complement bit patterns. The native fixture calls every function and checks zero, `2^32`, signed minimum and maximum, full-width lookup, in-place replacement, duplicates, missing keys, insertion order, stable removal, invalid ordinals and capacities, independent cloning, clearing, growth, and shrinking. Injected initial, growth, shrink, and clone allocation failures preserve prior entries or return an empty clone. The line-oriented frequency program covers negative inputs, signed extremes, duplicates, and malformed input. Ownership is linear by convention; no native `i64` behavior is claimed. A deterministic 40-operation execution test checks insertion order, lookup, update, removal, reserve, shrink, clear, clone independence, and invalid bounds against a reference map after every step. |
| `std::set_i32` all 19 public functions and its capacity constant | Executable on x86_64 Linux | The native fixture calls every function and checks empty and populated sets, both signed extremes, duplicates, absent items, insertion order, stable removal, invalid ordinals and capacities, independent cloning, clearing, growth, shrinking, subset and disjoint predicates, and ordered union, intersection, difference, and symmetric difference. Injected initial allocation, growth, shrink, clone, and each set-algebra allocation failure preserve ownership and existing items. The set owns one allocation of 32-bit cells; ownership is linear by convention. A deterministic 32-operation execution test checks two evolving sets against insertion-order references after every mutation, including cloning and invalid capacities, and compares ordered set algebra every fourth step. |
| `std::set_u32` all 19 public functions and its capacity constant | Executable on x86_64 Linux | The native fixture calls every function and checks zero, the unsigned high bit, `u32::MAX`, duplicates, absent items, insertion order, stable removal, invalid ordinals and capacities, independent cloning, clearing, growth, shrinking, subset and disjoint predicates, and all four ordered set-algebra operations. Injected initial allocation, growth, shrink, clone, and set-algebra allocation failures preserve ownership and existing items. A small program deduplicates unsigned readings and prints their wrapping sum. Values use 32-bit cells and preserve every bit pattern; ownership is linear by convention. A deterministic 32-operation execution test checks two evolving sets against insertion-order references after every mutation, including cloning and invalid capacities, and compares ordered set algebra every fourth step. |
| `std::set_bool` all 14 public functions | Executable on x86_64 Linux | An allocation-free three-Boolean value stores at most two distinct elements in insertion order. The imported fixture calls every function and checks construction, membership, length, invalid ordinals with both fallbacks, duplicate insertion, removal, clearing, subset and disjoint predicates, and all four ordered set-algebra operations. It compares membership results for all 25 pairs of the five possible ordered states and checks representative output orders. Values can be copied freely; there is no capacity, allocation failure, or destruction API. |
| `std::set_u8` all 15 public caller-backed functions | Executable on x86_64 Linux for eight-word `[u32]` views | Eight caller-owned words represent all 256 byte values without allocation. The imported runtime fixture calls every function, checks all 256 byte memberships against two independent predicates, cardinalities, ascending ordinals, invalid ordinals, duplicate insertion, missing removal, clearing, filling, subset and disjoint predicates, all four set-algebra writes, and an exact destination alias. A physically short backing traps with exit 101. The stdin distinct-byte program combines this set with byte classification and decimal output, checking empty, repeated, binary, and digit input and output failure. GPU frontend compilation emits the tested x86 program; user-program GPU execution is not claimed. |
| `std::set_i8` all 15 public caller-backed functions | Executable on x86_64 Linux for eight-word `[u32]` views | Signed values map from -128 through 127 onto the same 256-bit storage as `std::set_u8`; ordinals use signed order. The imported fixture calls every public function and checks both signed extremes, zero, duplicates, missing removal, invalid ordinals, all 256 full-set memberships and ordinals, a sparse predicate across all 256 values, filling and clearing, subset and disjoint predicates, all four set-algebra writes, and an exact destination alias. A seven-word physical backing exits 101. The signed-byte frequency program uses its cardinality operation for a real distinct-key count. The set borrows its storage and makes no allocation; user-program GPU execution is unverified. |
| `std::set_char` all 19 public functions and its capacity constant | Executable on x86_64 Linux | The imported fixture calls every public function and checks insertion order, duplicates, stable removal, bounds, reserve, clone independence, shrinking, all four set-algebra operations, plane-15 code points, and the largest scalar. A second fixture checks NUL and two-, three-, and four-byte Unicode scalars through the set-algebra results. Eight injected allocation failures preserve source sets and ownership, or return an empty independent clone/result. A deterministic 32-operation test compares two evolving character sets and ordered algebra with a reference after every step. The input-driven distinct-Unicode program checks empty input, multibyte duplicates, NUL, malformed and truncated UTF-8, and output failure. Each character occupies one eight-byte `char` slot. Ownership is linear by convention. GPU frontend compilation emits the tested x86 program; user-program GPU execution is not claimed. |
| `std::set_wide_u64` all 19 public functions and its capacity constant | Executable on x86_64 Linux | The native fixture calls every function and checks zero, `2^32`, the unsigned high bit, and `u64::MAX`, duplicate and absent values, insertion order, stable removal, invalid ordinals and capacities, independent cloning, clearing, growth, shrinking, subset and disjoint predicates, and all four ordered set-algebra operations. Eight injected allocation failures preserve owned input sets or return empty independent results. The line-oriented distinct-sum program covers duplicates, full-width decimal input, wraparound, and invalid input. Each value occupies two 32-bit cells; ownership is linear by convention. A deterministic 32-operation execution test checks two evolving sets against insertion-order references after every mutation, including cloning and invalid capacities, and compares ordered set algebra every fourth step. |
| `std::set_wide_i64` all 19 public functions and its capacity constant | Executable on x86_64 Linux | The native fixture calls every function and checks zero, `2^32`, the signed minimum and maximum, duplicate and absent values, insertion order, stable removal, invalid ordinals and capacities, independent cloning, clearing, growth, shrinking, subset and disjoint predicates, and all four ordered set-algebra operations. Eight injected allocation failures preserve owned input sets or return empty independent results. The signed distinct-sum program covers ordinary negative values, both signed extrema, duplicates, full-width decimal input, wraparound, and rejected input. Each value occupies two 32-bit cells holding its two's-complement bit pattern; ownership is linear by convention. A deterministic 32-operation execution test checks two evolving sets against insertion-order references after every mutation, including cloning and invalid capacities, and compares ordered set algebra every fourth step. |
| `std::net` all 64 metadata functions and 6 constants | Executable metadata on x86_64 Linux; 10 host calls unbound | The native fixture calls every metadata function and constant, checks available and unavailable result classification, and confirms network capability flags against `core::runtime`. TCP and UDP calls have no runtime binding. |
| `std::thread` all 32 metadata functions and 6 constants | Executable metadata on x86_64 Linux; 4 host calls unbound | The native fixture calls every metadata function and constant, checks result classification, and confirms that spawn, join, yield, and current-id calls remain unavailable. |
| `std::gpu` all 44 metadata functions and 6 constants | Executable metadata on x86_64 Linux; 5 host calls unbound | The native fixture calls every metadata function and constant, checks result classification, and confirms unavailable buffer and dispatch services. Compiler execution on a GPU does not bind a user-program GPU API. |
| `std::host` all 15 metadata functions and 4 constants | Executable metadata on x86_64 Linux | The native fixture calls every public function and constant and checks its unavailable service report against `core::runtime`. No host operation ABI is declared here. |
| `test::harness` all 31 metadata and status functions and 7 constants | Executable metadata on x86_64 Linux; test execution unbound | The native fixture calls every public function and constant, checks passed, failed, skipped, and unknown statuses, and confirms registration, discovery, and execution remain unavailable. |
| `test::assert` all 8 public helpers | Executable on x86_64 Linux | `tests/stdlib_assert_execution.rs` runs all passing conditions and separately checks that every false condition terminates with SIGILL. The helpers use no allocation or host calls. See dependency 35 for a separate compiler issue with explicit void returns. |
| Generic `std::vec::Vec<T>` associated `new`, `len`, and `is_empty` | Executable on x86_64 for imported `i32` and `bool` empty values | `tests/stdlib_generic_vec_flat_execution.rs` compiles the real `std::vec` through `--stdlib-root` and executes both instantiations, including their methods. There is no generic storage or mutation. The former `push` silently discarded its argument and was removed. See dependencies 4 and 54. |
| Generic `std::vec::new` | Executable on x86_64 for imported `i32` and `bool` empty values | An annotated `Vec<T>` supplies the result type, and the imported constructor runs through `--stdlib-root`. See `tests/stdlib_generic_vec_flat_execution.rs`. |
| Generic `std::vec::{len,is_empty}` | Executable on x86_64 for imported `i32` and `bool` empty values | `repro_vec_generic_free_new.lani` executes both through `--stdlib-root` with both instantiations. `repro_vec_generic_free_direct_argument.lani` also executes direct nested constructor arguments. Generic `Vec<T>` has no storage or mutation; concrete vectors use the allocator service. See dependencies 4 and 54. |

The original seven single-cell concrete vector modules also implement `truncate(value, new_len)`.
`tests/stdlib_vec_truncate_execution.rs` executes each imported implementation:
valid truncation preserves the prefix and capacity, invalid lengths leave the
vector unchanged, and appending after truncation reuses the allocation.
Those seven modules also implement `try_resize(value, new_len, fill)`: growth fills each
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

For those seven single-cell concrete vector types, the allocation-failure suite executes a
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
- `core::narrow` gives explicit conversions from i32 and u32 to i8, u8,
  i16, and u16. `*_wrapping` retains the low target-width bits and interprets
  signed results as two's complement. `*_or` returns the caller's fallback
  for an out-of-range value; a valid converted value may equal that fallback.
  `*_saturating` clamps to the target bounds. Each helper normalizes or checks
  the value and then narrows it with `as`.
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
- `core::utf16` uses strict UTF-16 code units in caller-backed `[u16]` views.
  `write_scalar` checks logical capacity before writing either unit and returns
  a status plus the next offset. `decode_next` reports bounds, truncated high
  surrogate, and malformed pairs separately, with a scalar and next offset
  only on success. Complete-view validation, counting, and ordinal lookup
  reject malformed input; ordinal lookup validates the entire view, including
  any suffix after the requested scalar. Negative lengths are invalid and an
  empty view is valid. An overstated physical view may trap on indexing.
- `core::utf16_bytes` uses caller-backed `[u8]` views in either explicit byte
  order, with byte offsets on two-byte boundaries. It does not interpret a
  byte-order mark. `read_next_le` and `read_next_be` report bounds, short input,
  or malformed sequences separately; successful results contain a Unicode
  scalar and the next byte offset. Byte writers reject invalid scalars and
  insufficient logical capacity without writing. Complete-view validation,
  counting, and ordinal lookup reject odd byte lengths and malformed suffixes.
  An overstated physical view can trap when indexed.
- `core::transcode` converts complete UTF-8 byte views to UTF-16 code-unit
  views or UTF-16LE/BE byte views and back. It does not consume or emit a BOM.
  Source and destination must not overlap. A result reports
  success, logical bounds failure, malformed input, or insufficient output
  capacity; successful `read` and `written` counts use each view's element
  type, so the LE/BE variants count bytes. The functions validate and size the
  whole source before writing, so malformed input and short logical capacity
  leave destination storage unchanged. Physical backing overclaims can trap on
  native indexing.
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
- `core::hex_wide_i64` formats a signed two-word integer as an optional
  minus sign followed by the shortest hexadecimal magnitude. The signed
  minimum formats as `-8000000000000000`. Parsing accepts an optional
  leading `+` or `-`, then optional `0x` or `0X`, then at least one hex
  digit. It rejects whitespace, malformed codes, and values beyond the
  selected signed bound. Negative zero yields zero. `can_parse_ascii`
  distinguishes a valid result equal to the caller fallback; overstating the
  physical `[i32]` backing may trap on native indexing.
- `core::binary_wide_i64` formats a signed two-word integer as an optional
  minus sign and the shortest binary magnitude. The signed minimum is a
  minus, one bit, and 63 zero bits. Parsing accepts one optional leading
  `+` or `-`, then optional `0b` or `0B`, then at least one bit. It rejects
  whitespace, malformed codes, and values beyond the selected signed bound.
  Negative zero yields zero. `can_parse_ascii` separates success from a
  value equal to fallback; overstated physical `[i32]` backing may trap.
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
  for the other result variant. Both concrete types expose receiver methods
  for their applicable predicates, fallbacks, combinators, and conversion.
  The receiver methods borrow their values and leave the originals intact.
  Neither module allocates. Run
  `cargo test --test stdlib_option_result_methods_execution` for native
  receiver calls and the sample program.
- `core::option_u32` and `core::result_u32` use the same explicit presence and
  success flags for unsigned payloads and error codes. `Some(0)`, `Ok(0)`,
  and `Err(0)` remain distinct. All extraction operations either inspect the
  active variant or return a caller fallback. Their borrowed receiver methods
  preserve the original value and the full unsigned high bit through
  aggregate returns. Neither module allocates. The same focused receiver
  test covers both the signed and unsigned 32-bit pairs. Chained imported
  receiver calls execute on x86; see resolved dependency 66.
- `core::option_ptr` distinguishes `None` from `Some(null)`;
  `core::result_ptr` distinguishes `Ok(null)` from `Err(0)`. A Result error
  is an `i32`. Their `or`, `and`, and `xor` branches preserve their respective
  tags and payloads; `ok_or` and `ok` convert between pointer Option and
  Result, while `err` extracts an `OptionI32`. These modules do not allocate
  or free pointers, and the caller owns the pointed-to storage.
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
  returns the caller fallback. Their borrowed receiver methods execute for
  both variants, including chained imported calls; a mixed-import fixture
  distinguishes the four narrow method implementations in one program.
  `core::i8`, `core::i16`, `core::i32`,
  `core::u8`, `core::u16`, and `core::u32` use the corresponding concrete Option modules until
  generic Option/Result function specialization works. Their `clamp` functions leave the input
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
- `core::option::Option<T>` has generic free and value-receiver `is_some` and
  `is_none` predicates. Imported construction and concrete matches execute
  for tested scalar payloads, strings, direct scalar slices, and caller-local fixed records,
  including nested records and string/slice descriptors. Bounds and ownership
  remain properties of the payload; wrapping a borrowed view does not extend
  its backing storage's lifetime. See [the Option guide](stdlib-option.md).
  Shared generic free and value-receiver bodies provide `unwrap_or`, `or`,
  `and`, and `xor` for bool, i32, u32, f32, char, and str. They preserve inputs
  and distinguish stored zero, NUL, false, and an empty string from absence.
  Compound payload-body specialization still fails explicitly with `LNC0017`.
- Concrete implementations on that same enum provide `contains` for bool,
  i32, u32, f32, and char. Floating membership follows IEEE equality;
  extraction preserves NaN and negative zero. The unsigned implementation
  also executes for tested u8 values because the compiler currently aliases
  unsigned integer widths. It performs no narrowing and cannot enforce a
  distinct u8 argument type. The signed implementation has the corresponding
  width limitation. Generic trait equality and distinct integer-width type
  identity remain dependencies 31 and 57.
- `core::option::Option<bool>` uses the generic tagged enum with `Some(bool)`
  and `None` variants. There is no separate `OptionBool` type. Its eight
  value-receiver methods preserve the caller's enum. `unwrap_or` returns the explicit
  fallback for `None`; `or`, `and`, and `xor` select variants according to
  presence, independently of the stored bool. `ok_or` returns the existing
  `core::result_bool::ResultBool`, using the supplied bool error for `None`.
  The concrete free `ok` and `err` functions extract that Result representation
  into `Option<bool>`. Stored `false` remains present or successful.
  These APIs allocate no storage and do not panic. Methods with their own
  generic parameters and `Result<T, E>` conversion remain dependencies.
  Direct `ok(result).contains(value)` and `err(result).unwrap_or(fallback)`
  receivers execute, including false payloads and absent results (dependency
  72 is resolved). Their combinator results can be chained into another method.
  The direct method result
  `core::result_bool::contains(option.ok_or(error), value)` executes. Imported
  methods retain concrete parameter types in the imported interface and reject
  wrong scalar and nominal arguments (dependency 70 is resolved for these APIs).
  The generic free Option operations now execute for the documented instances;
  the compiler checkpoint lists the tested compound extraction cases.
- `core::result::Result<T, E>` has generic free and borrowed `is_ok` and
  `is_err` predicates and eight concrete scalar membership helpers. Both
  independently sized record variants and the tested string/slice descriptors
  survive construction and concrete matching. Predicates never read an
  inactive payload; membership returns false for the other variant. Checked
  symbolic bodies remain deferred until a concrete call schedules them.
  The complete module imports and its twenty public APIs have executable
  scalar coverage. See [the Result guide](stdlib-result.md) for the additional
  record and slice extraction cases.
- `core::option_f32` and `core::result_f32` use the same explicit variant
  flags for floating-point payloads. `Some(0.0)`, `Ok(0.0)`, and `Err(0.0)`
  remain distinct; inactive fields are zero. `contains` and `contains_err`
  use IEEE equality, so a stored NaN does not compare equal to any expected
  value, including NaN. Presence and success predicates still report the
  active variant, and unwrap helpers preserve a stored NaN. Both modules are
  allocation-free.
- `std::deque_wide_i64` uses the same paired-cell ring storage and
  ownership rules as `std::deque_wide_u64`. It retains signed values as
  two's-complement bit patterns, including both signed extremes. Bounds,
  allocation failure, clone, and empty-pop behavior match the unsigned deque.
- `std::deque_wide_u64` stores each unsigned two-word value as paired
  low and high 32-bit cells in a circular buffer. Capacity is limited to
  268,435,455 values so byte counts fit i32. Growth, reservation, clone, and
  shrink copy both words in logical order. Invalid ordinals use the supplied
  wide fallback or return `false`; empty pops are unchanged. Allocation
  failure leaves the owner and its values intact, except that a failed clone
  returns an empty independent deque. Retain only the newest returned owner
  and destroy each independent deque once.
- `std::deque_char` stores each character in one eight-byte `char`
  slot. Its maximum capacity is 536,870,911 values. Invalid ordinals return
  the supplied fallback or `false`; empty pops and invalid capacity requests
  leave the owner unchanged. Failed allocation preserves the owner and order;
  a failed nonempty clone returns an independent empty deque. Compare `len`
  after push and `capacity` after reserve to detect failure. Destroy each
  independent owner once.
- `std::deque_bool` stores false as zero and true as one in 32-bit
  backing cells. Its maximum capacity is 536,870,911 elements. Invalid
  ordinals return the supplied fallback or `false`; empty pops and invalid
  capacity requests leave the deque unchanged. Failed allocation preserves
  the original owner and logical order; a failed nonempty clone returns an
  empty independent deque. Compare `len` after push and `capacity` after
  reserve to detect failure, and destroy each independent owner once.
- `std::deque_i16` stores each signed halfword in one 32-bit backing cell.
  Its maximum capacity is 536,870,911 elements. Invalid ordinals return the
  supplied fallback or `false`; empty pops and invalid capacity requests
  leave the owner unchanged. Failed allocation preserves the owner and order;
  a failed nonempty clone returns an independent empty deque. Compare `len`
  after push and `capacity` after reserve to detect failure. Destroy each
  independent owner once.
- `std::deque_i8` stores each signed byte in one 32-bit backing cell.
  Its maximum capacity is 536,870,911 elements. Invalid ordinals return the
  supplied fallback or `false`; empty pops and invalid capacity requests
  leave the owner unchanged. Failed allocation preserves the owner and order;
  a failed nonempty clone returns an independent empty deque. Compare `len`
  after push and `capacity` after reserve to detect failure. Destroy each
  independent owner once.
- `std::deque_u16` stores each unsigned halfword in one 32-bit backing cell.
  Its maximum capacity is 536,870,911 elements. Invalid ordinals return the
  supplied fallback or `false`; empty pops and invalid capacity requests
  leave the owner unchanged. Failed allocation preserves the owner and order;
  a failed nonempty clone returns an independent empty deque. Compare `len`
  after push and `capacity` after reserve to detect failure. Destroy each
  independent owner once.
- `std::deque_u8` stores each byte in one 32-bit backing cell. Its maximum
  capacity is 536,870,911 elements so allocation byte counts fit i32. Invalid
  indices return the supplied fallback or `false`; empty pops and invalid
  capacity requests leave the deque unchanged. Compare `len` after a push and
  `capacity` after reserve to detect allocation failure. A failed nonempty
  clone returns an independent empty deque. Retain only the newest owner and
  destroy each independent deque once.
- `std::deque_u32` uses the same ring-buffer ownership, capacity, bounds,
  and allocation-failure rules as `std::deque_i32`. Its 32-bit backing cells
  preserve all unsigned bit patterns. The executable fixture checks the high
  bit and maximum value after insertion, mutation, clone, and reservation.
- `std::deque_i32` stores i32 values in an owned circular buffer. Push and
  pop at either end are constant time until growth copies elements. Its maximum
  capacity is 536,870,911 elements so four-byte allocation sizes fit i32.
  Invalid indices return the supplied fallback or `false`; empty pops return
  the original deque. Invalid capacity requests and failed allocation leave
  the owner and logical order unchanged. Compare `len` after a push and
  `capacity` after reserve to detect failure. A failed nonempty clone returns
  an empty zero-capacity deque while preserving its source. Shrinking an empty
  deque releases storage. Keep only the newest returned owner and destroy each
  independent deque once; the language does not enforce this ownership rule.
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
  malformed raw cells before allocating; i32, u32, and char accept every 32-bit cell.
- `std::vec_wide_i64` owns one allocation of paired low/high 32-bit
  cells per signed two-word integer. Maximum capacity is `268435455` values
  so every byte count fits signed i32. Operations return the newest vector;
  callers must use only that value and destroy it once. Failed growth, insert,
  resize, reserve, or shrink retains the original length, capacity, elements,
  and allocation. A failed nonempty clone is empty and leaves the source
  owned. `try_extend_from_word_pairs` takes a caller-backed `[i32]` view of
  `2 * count` interleaved low/high words, reserves before writing, and requires
  nonaliasing input; overstating physical backing may trap. Invalid indices
  return fallback or preserve the vector. Compare returned lengths or capacity
  to detect allocation failure.
- `std::vec_wide_u64` has the same eight-byte ownership, bounds, growth,
  clone, and failure contract, but exposes `WideU64` values and preserves all
  unsigned 64-bit bit patterns. Its batch input is the same nonaliasing,
  caller-backed low/high word-pair view. The returned length or capacity
  distinguishes success from allocation failure.
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
- `std::set_char` keeps each distinct character once, in
  insertion order. It has the same bounds, ownership, clone, allocation-failure,
  and ordered set-algebra contract as `std::set_i32`. Each character occupies one
  eight-byte `char` slot. The supported target is x86_64 Linux with
  allocator bindings.
- `std::set_u8` uses exactly eight caller-owned `u32` words. Call `clear` or
  `fill` before the first read. `insert` and `remove` return true only when
  membership changes. `at_or` visits bytes in ascending numeric order and
  returns the caller fallback for an invalid ordinal. Set algebra writes into
  caller-provided destination storage; exact input/destination aliases work,
  while partial overlap is unsupported. `len` and `fill` visit every word, so
  a backing shorter than eight physical words traps; other operations trap if
  they reach a missing word. No allocator or destructor is involved.
- `std::set_u32` has the same ownership, insertion-order, bounds, failure,
  and set-algebra contract for unsigned values. It stores each `u32` as raw
  32-bit bits and preserves values above `i32::MAX`, including `u32::MAX`.
  The supported target is x86_64 Linux with allocator bindings.
- `std::set_wide_u64` has the same ordered-set, ownership, and failure
  contract for two-word unsigned values. Each entry stores low and high
  words in adjacent 32-bit cells. Its maximum capacity is 268,435,455
  entries, so byte-count arithmetic fits signed 32 bits. Invalid ordinals
  return the supplied `WideU64` fallback; failed growth leaves the original
  set live, and failed set algebra returns an empty independent set. The
  supported target is x86_64 Linux with allocator bindings.
- `std::set_wide_i64` follows the same ordered-set, ownership, and failure
  rules for two-word signed values. It stores low and high two's-complement
  words unchanged, including the sign bit. The capacity limit is 268,435,455
  entries; invalid ordinals use the caller fallback. Allocation failure during
  insertion, reservation, or shrinking preserves the original set, while a
  failed clone or set-algebra operation returns an empty independent set.
  Callers distinguish an expected nonempty algebra result from failure with
  `len`. The supported target is x86_64 Linux with allocator bindings.
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
- `std::map_char_u32` has the same ownership, bounds, insertion-order,
  update, and failure contract as `std::map_u32_u32`. Each entry occupies
  16 bytes: a `char` key slot followed by a `u32` value slot.
  The supported target is x86_64 Linux with allocator bindings.
- `std::map_u8_u32` needs eight caller-owned `u32` words for membership and
  256 caller-owned `u32` values. The views must not overlap. Call `clear`
  before the first read; it zeros
  both views. Keys iterate in ascending byte order. `insert` returns true
  only for a new key and preserves an existing value; `put` always writes and
  returns whether its key was new; `set` and `remove` return false without
  writing for a missing key. A missing key or invalid ordinal uses the caller
  fallback. Indexing a missing physical word traps. The map does not allocate.
- `std::map_u32_u32` has the same ownership, bounds, ordering, update, and
  failure contract for unsigned keys and values. Raw 32-bit storage preserves
  all unsigned bit patterns; reads convert the stored cells back to `u32`.
  The supported target is x86_64 Linux with allocator bindings.
- `std::map_wide_u64_wide_u64` stores unsigned two-word keys and values in
  adjacent low/high 32-bit cells. A key match compares both words; updates
  never change key order. Each entry occupies 16 bytes and the maximum is
  134,217,727 entries, keeping byte counts within signed 32-bit arithmetic.
  Invalid ordinals return a caller fallback, and `contains_key` distinguishes
  a missing key when a stored value equals that fallback. Allocation failure
  during insertion, reservation, or shrinking retains the existing map; a
  failed nonempty clone returns an empty independent map. The caller keeps
  only the latest returned owner and destroys each independent map once.
  The supported target is x86_64 Linux with allocator bindings.
- `std::map_wide_i64_wide_i64` follows the same four-cell layout, insertion
  order, ownership, capacity bound, and allocation-failure rules for signed
  two-word keys and values. Equality compares the complete two's-complement
  bit pattern; ordinal and missing-key fallbacks are supplied by the caller.
  Its supported target is x86_64 Linux with allocator bindings.
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
  aggregates, scalar predicates, and receiver methods. The full-range
  predicate accepts every valid `char`; it does not construct or iterate
  character values. Run `cargo test --test stdlib_range_char_methods_execution`
  for the imported receiver methods on x86.
- `core::range_f32` uses IEEE ordering. A NaN bound makes a bounded interval
  empty and unable to overlap. One-sided and bounded intervals never contain
  NaN, while `full_contains` includes NaN because it is unbounded. Signed
  zeros compare equal. Infinite endpoints are allowed: a closed singleton at
  positive infinity contains positive infinity; the corresponding half-open
  interval is empty. The concrete range types expose borrowed receiver methods
  for their endpoints, emptiness, membership, and overlap where applicable.
  These helpers test membership and do not iterate values. Run
  `cargo test --test stdlib_range_f32_methods_execution` for imported receiver
  methods and the floating return regression on x86.
- `core::range_i8` applies the same endpoint rules across
  `-128..=127`. Half-open ranges exclude the upper endpoint even when it is
  `127`; inclusive ranges can contain both extrema. A to-range ending at
  `-128` is empty.
- `core::range_u16` and `core::range_i16` apply these rules across
  `0..=65535` and `-32768..=32767`. The unsigned inclusive range can contain
  `65535`; the signed inclusive range can contain both signed extrema. Each
  small-width integer module provides concrete half-open, inclusive, from, and to
  aggregates, with constructors, endpoint readers, predicates, and receiver
  methods. The `full_contains` scalar helper covers the full range without an
  aggregate. Run `cargo test --test stdlib_narrow_range_methods_execution`
  for their imported x86 receiver-method cases.
- Slice callers supply `len` because source code cannot read slice metadata
  yet. `len <= 0` is empty for the safe fallback and accumulation helpers.
  `first` traps on an empty view. `get_or` returns the fallback for an
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
  `core::slice_wide_u64` uses a caller-owned `[u32]` view with two words per
  logical element. `len` and `capacity` count elements, never words, and are
  limited to 1,073,741,823 so index arithmetic cannot overflow `i32`. All
  checked calls reject invalid logical bounds before writing; an overstated
  physical view traps with exit 101 if indexed. `first` requires at least two
  backing words. Search and extrema compare full unsigned 64-bit values,
  `sort` is in-place heapsort, and `sum` wraps modulo 2^64. The caller must
  advance its logical length after successful `insert` or `push`; copying
  between distinct views requires nonoverlapping backing.
  `core::slice_wide_i64` uses the same two-word backing, element-length limit,
  logical bounds rules, and ownership contract. It preserves both words of
  signed two's-complement values and compares them in signed order. Its
  in-place heapsort and binary search use that order; `sum` wraps modulo 2^64
  and returns the corresponding signed bit pattern. `first` and overstated
  physical backing can exit 101.
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
  `set` and `swap` reject invalid indices without mutation.
  `fill` returns the number of elements written, and `reverse_in_place`
  returns the number of swaps. `copy_within` handles overlap in either
  direction and rejects invalid source or destination bounds before writing.
  `copy_nonoverlapping_prefix` copies the requested source prefix into a
  separate backed view, returns false without writing for negative lengths or
  insufficient destination length, and accepts an empty source. Its source and
  destination element ranges must not overlap in memory.
  `copy_nonoverlapping_range` accepts source and destination offsets plus
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
- `std::time_wide` reads the same native timespec into a caller-backed
  `[i32]` view of at least four words: seconds low, seconds high, nanoseconds
  low, and nanoseconds high. Its decode helpers return two-word signed seconds
  and bounded nanoseconds, accepting negative seconds but rejecting nanos
  outside `[0, 1_000_000_000)`. Invalid logical lengths return false or the
  caller fallback; an overclaimed physical view may trap. A valid decoded
  value may equal fallback. Clock failures return false and callers must
  ignore the resulting buffer; insufficient logical capacity leaves storage
  unchanged. No allocation or native scalar `i64` arithmetic is used.
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
- `std::io_hex_wide_i64` writes shortest sign-and-magnitude hexadecimal
  text for `WideI64` values and reads bounded stdin with the signed syntax
  of `core::hex_wide_i64`. Surrounding SP, HT, LF, and CR are accepted.
  Writes pass through negative host errors; a short write returns `-1` and
  may leave a prefix. Missing digits, malformed or overflowing input, excess
  bytes, and host failures return the caller fallback. A zero byte limit
  consumes nothing, and a valid value may equal fallback.
- `std::io_binary_wide_u64` writes the shortest binary form of a two-word
  `WideU64` in 1 through 64 bytes, and reads bounded stdin with the same
  syntax as `std::io_binary`. Writes pass through negative host errors; a
  short write returns `-1` and may leave a prefix. The reader returns its
  caller fallback for malformed, overflowing, overlong, or failed input. A
  zero byte limit consumes nothing. A valid value may equal the fallback.
- `std::io_binary_wide_i64` writes the shortest signed binary form of a
  two-word `WideI64` in 1 through 65 bytes. It reads bounded stdin with
  surrounding SP, HT, LF, and CR, one optional leading sign, and one
  optional `0b` or `0B` prefix after the sign. Host errors pass through on
  write; a short write returns `-1` and may leave a prefix. Missing digits,
  malformed or overflowing input, excess bytes, and host read failures
  return the caller fallback after possibly consuming a prefix. A zero
  byte limit consumes nothing; a valid value may equal fallback.
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
- `std::file_hex_wide_u64` applies the hexadecimal file rules to
  two-word `WideU64` values. Lowercase and uppercase writes return false on
  open, write, or close failure, possibly leaving a truncated file or digit
  prefix. Bounded reads accept mixed-case digits and an optional `0x` or
  `0X` prefix; missing files, malformed or overflowing input, excess bytes,
  and read or close errors return the caller fallback. A zero limit reads
  nothing, and a valid value may equal fallback.
- `std::file_hex_wide_i64` writes shortest sign-and-magnitude hexadecimal
  text for `WideI64` values, creating or truncating a literal path. Writes
  return false on open, write, or close failure and may leave a truncated
  file or character prefix. Bounded reads accept surrounding SP, HT, LF,
  and CR, one leading plus or minus, and one optional `0x` or `0X` prefix
  after the sign. Missing digits, malformed or overflowing input, excess
  bytes, missing files, and read or close errors return the caller fallback.
  A zero byte limit opens nothing, and a valid value may equal fallback.
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
- `std::file_binary_wide_i64` writes shortest sign-and-magnitude binary
  text for `WideI64`, creating or truncating a literal path. Write failure
  returns false and may leave a truncated file or character prefix. Bounded
  reads accept surrounding SP, HT, LF, and CR, one optional leading plus or
  minus, and one optional `0b` or `0B` prefix after the sign. Missing digits,
  malformed or overflowing input, excess bytes, missing files, and read or
  close errors return fallback. A zero limit opens nothing; a valid value
  may equal fallback.
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

- `std::random_wide::{try_secure_u64,try_secure_i64}` read eight secure
  bytes into native little-endian 32-bit words and return a concrete wide
  `Option`. Host errors and zero progress return `None`; short reads are
  retried. Every 64-bit bit pattern, including zero, is a valid `Some` value.
- `std::random_wide::try_secure_u64_below` draws uniformly from the half-open
  interval `0..bound` using 64-bit rejection sampling. A zero bound returns
  `None`; a unit bound returns `Some(0)` without host access. Host failure
  after a rejected word returns `None`.
- `std::random_wide::{try_secure_u64_inclusive,try_secure_i64_inclusive}` draw
  uniformly from inclusive intervals. Reversed bounds return `None` and
  singleton bounds return their value, both without host access. Full 64-bit
  intervals use one direct secure draw. Signed bounds use sign-bit bias to
  preserve ordering. The helpers allocate no heap storage.

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

`sample_programs/signed_radix_report.lani` reads one bounded signed binary
line, validates it with the portable `core::binary_wide_i64` parser, and
prints its binary, lowercase hexadecimal, and decimal forms through checked
stdout writers. Its native test checks zero, positive and negative values,
both signed extrema, malformed and empty input, and an overlong line.

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
`core::range_f32` interval using a receiver method, clamps them, and carries
the result through `OptionF32`. It prints the matched reading's index, `2`,
after verifying the floating total is `7.0`. Floating-to-integer conversion remains a compiler
dependency; see item 43 below.

`sample_programs/wide_signed_sum.lani` reads bounded signed decimal lines
into `std::vec_wide_i64`, sums them modulo 2^64, and prints the signed
result. Its native test covers empty input, both signed extrema, wrapping,
multiple values, an unterminated final line, malformed and overlong input.

`sample_programs/wide_unsigned_sum.lani` reads bounded unsigned decimal
lines into `std::vec_wide_u64`, sums them modulo 2^64, and prints the
unsigned result. Its native test covers empty input, `u64::MAX + 1`, the
high bit, multiple values, an unterminated final line, malformed, overflowing,
and overlong input.

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
`Option<bool>`. It prints `2` and releases storage.

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
The current combined checkpoint passes all seven foundation tests, including
all 139 source entries and native bounds traps. The generic slice suite also
passes all eight tests. Log:
`tests/fixtures/stdlib_compiler_state/generic-slice-foundation-complete-tests.log`.
This restores the gate after the generic access/copy API migration; see
[the slice guide](stdlib-slice.md) for supported element types and limitations.
A repeated-compilation regression executes the character and halfword examples
through parser workspace growth and shrinkage; dependency 73 is resolved.
Run `cargo test --test stdlib_generic_predicates_execution imported_option_`
for the imported generic Option tags, receiver predicates, full payload
recovery, descriptors, bounds, concrete record returns, summary program, and
unsupported-layout rejection. The earlier focused imported check passed six
tests. The normal and failure behavior is summarized in [the Option guide](stdlib-option.md).
Run `cargo test --test stdlib_option_bool_execution --test stdlib_option_result_methods_execution`
for every concrete bool function and method, state combinations, wrong types,
direct method-result arguments, factory receivers, and the two bool programs.
The Option bool suite passes all 18 enabled tests; dependencies 70 and 74 have
executable regressions. The separate imported factory fixture executes bool and
u8 specializations of the same enum and same method name; wrong method result
types are rejected. A second factory executes four concrete scalar arguments
and a five-word enum value through a direct method receiver.
Run `cargo test --test stdlib_option_slice_execution --test stdlib_slice_iteration_execution`
for the direct Option-slice and iteration suites. Each passes five focused
tests, including the optional-window program, runtime lengths through calls,
native bounds failures, aliasing, and fixed-array scalar and record iteration.
The direct-slice checkpoint and remaining limits are in [the Option guide](stdlib-option.md).
Run `cargo test --test stdlib_option_scalar_execution` for every new concrete
scalar payload method, all 16 state pairs, extrema, NaN, negative zero,
argument rejection, and the reading-selection program. All four tests pass;
the program prints `-2` and `5`. The existing bool and direct slice fixtures
also execute after these methods were added. This checkpoint does not repeat
the broad foundation gate or performance sweep.
Run `cargo test --test stdlib_result_generic_execution` for the actual Result
module, its twelve executable functions and methods, descriptor preservation,
native bounds failures, wrong-type rejection, and the reading-total program.
The program prints `20` and `-2`. Three generic payload functions remain explicit
native failures. The retained log is `result-generic-import-tests.log` under
`tests/fixtures/stdlib_compiler_state/`; target limits are in
[the Result guide](stdlib-result.md).
Run `cargo test --test stdlib_generic_payload_templates_execution` for mixed
libraries containing executable functions and deferred generic payload bodies,
checked fallback types, explicit used-template failures, and qualified generic
scalar returns. Its six-test log is `generic-payload-template-tests.log`.
The retained source and dependency context is checked separately by four
compiler tests selected with `cargo test -p laniusc-compiler --lib template_`.
They execute rebuilt native objects and check cache eviction for source and
interface snapshots. All four pass in `template-context-tests.log`; all eight
cache tests pass in `template-context-cache-tests.log`. These tests establish
retention and replay, not native specialization of a generic payload body.
Run `cargo test --test stdlib_narrow_execution` for all 24 explicit
32-bit narrowing helpers, boundary values, and the input-driven byte report.
Run `cargo test --test stdlib_char_array_literal_execution` for direct
Unicode character arrays through imported slice helpers and type rejection.
Run `cargo test --test stdlib_char_high_bit_execution` for unsigned high-bit
character and `u32` comparisons with a literal on the left, plus imported
ordering, comparison, range, and slice helpers.
Run `cargo test --test stdlib_wide_u64_bits_execution` for every public
two-word bit helper, including rotation boundaries and invalid-index fallbacks.
Run `cargo test --test stdlib_hex_wide_u64_execution` for full-width
hexadecimal formatting, bounded parsing, fallbacks, and native bounds trapping.
Run `cargo test --test stdlib_hex_wide_i64_execution` for signed
full-width hexadecimal formatting, bounded parsing, and native bounds trapping.
Run `cargo test --test stdlib_binary_wide_u64_execution` for full-width
binary formatting, bounded parsing, fallbacks, and native bounds trapping.
Run `cargo test --test stdlib_binary_wide_i64_execution` for signed
full-width binary formatting, bounded parsing, and native bounds trapping.
Run `cargo test --test stdlib_wide_u64_range_execution` for the full-width
unsigned range forms, their receiver methods, and endpoint boundaries.
Run `cargo test --test stdlib_wide_i64_range_execution` for the signed
two-word range forms, methods, negative ordering, and both extrema.
Run `cargo test --test stdlib_wide_i64_bits_execution` for the signed
two-word bit view, including negative patterns and sign-bit rotations.
Run `cargo test --test stdlib_signed_bit_report_program` for a real program
combining signed parsing, bit operations, and decimal output.
Run `cargo test --test stdlib_signed_radix_report_program` for a bounded
signed binary input program that reports three representations.
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
Run `cargo test --test stdlib_option_result_ptr_execution` for every
pointer Option/Result function, null payloads, error codes, and the real-stdin
first-byte program.
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
Run `cargo test --test stdlib_array_i32_view_execution` for both borrowed
array helpers across fixed lengths and native bounds failures.
Run `cargo test --test stdlib_slice_wide_u64_execution` for every two-word
unsigned slice operation, backing traps, exhaustive small sorts, and a median
program.
Run `cargo test --test stdlib_slice_wide_i64_execution` for every signed
two-word slice operation, backing traps, exhaustive signed sorts, and a median
program.
Run `cargo test --test stdlib_allocator_metadata_execution` for allocator
capability metadata and live pointer classification.
Run `cargo test --test stdlib_generic_vec_flat_execution` for empty generic
vector operations, including imported `--stdlib-root` calls and flat source
packs. Storage and mutation for generic vectors remain unavailable.
Run `cargo test --test stdlib_generic_interface` for exported generic
Option/Result types and associated methods on both plain and generic structs.
Run `cargo test --test stdlib_generic_enum_declaration_execution` for an
unused generic declaration, executable local concrete scalar and record
instances, empty-variant padding, and fail-closed imported dependencies.
Run `cargo test --test stdlib_time_execution` for clock metadata, the four
bound host calls, checked wrappers, and injected host failures.
Run `cargo test --test stdlib_time_wide_execution` for two-word clock
seconds, real clocks, invalid views, native bounds trapping, and injected
clock failures.
Run `cargo test --test stdlib_cast_store_execution` for direct indexed byte
casts and the i32 and byte-slice store paths.
The test compiles small Lanius programs through `--stdlib-root`, executes
the native ELFs, checks their exit status, checks the example's stdout, and
checks the slice bounds trap. Each source is also suitable for direct CLI
compilation with `laniusc --stdlib-root stdlib --emit x86_64 -o OUTPUT SOURCE`.
Run `cargo test --test stdlib_allocator_failure_execution` and
`cargo test --test stdlib_vec_i32_execution` for native allocation failures;
fault injection runs when Linux `strace` is available.
Run `cargo test --test stdlib_vec_i32_sort_search_execution` for owned
sorting, search boundaries, and the signed median input program.
Run `cargo test --test stdlib_vec_u32_sort_search_execution` for unsigned
high-bit ordering, owned search boundaries, and the unsigned median program.
Run `cargo test --test stdlib_vec_i8_sort_search_execution` for owned
signed-byte sorting, reversal, and search boundaries.
Run `cargo test --test stdlib_vec_i16_sort_search_execution` for owned
signed-halfword sorting, reversal, and search boundaries.
Run `cargo test --test stdlib_vec_char_execution` for imported character-vector
operations, Unicode and full-width ordering, seven allocation-failure branches,
and the input-driven Unicode sort/deduplicate program. The test compiles through
the GPU-resident frontend and executes native x86_64 output. `strace` is required
for injected allocation failures; the test checks normal paths without it.

Run `cargo test --test stdlib_vec_u16_sort_search_execution` for owned
unsigned-halfword sorting, reversal, and search boundaries.
Run `cargo test --test stdlib_vec_u8_sort_search_execution` for owned
byte sorting, reversal, search boundaries, and unchanged backing pointer.
Run `cargo test --test stdlib_vec_bool_sort_search_execution` for owned
false-before-true sorting, reversal, and search fallbacks.
Run `cargo test --test stdlib_vec_truncate_execution` for all seven concrete
vectors' prefix preservation, invalid lengths, retained capacity, and reuse.
Run `cargo test --test stdlib_vec_resize_execution` for growth, fill,
shrinkage, invalid lengths, and an injected reallocation failure.
Run `cargo test --test stdlib_vec_shrink_execution` for all seven concrete
vectors' capacity release and an injected shrink reallocation failure.
Run `cargo test --test stdlib_vec_wide_i64_execution` for the owned
signed two-word vector, every public operation, backing bounds, and injected
allocation failures. Run `cargo test --test stdlib_wide_signed_sum_program`
for its full-width input and output program.
Run `cargo test --test stdlib_vec_wide_order_execution` for owned
two-word signed and unsigned sorting and searching, exhaustive paired-cell
cases, and full-width median programs with real input.
Run `cargo test --test stdlib_vec_wide_u64_execution` for the owned
unsigned two-word vector, every public operation, backing bounds, and
injected allocation failures. Run `cargo test --test stdlib_wide_unsigned_sum_program`
for its full-width input and output program.
Run `cargo test --test stdlib_deque_stateful_execution` for 48
deterministic mixed operations per deque, checked against a reference deque
after every step for all nine owned deque types.
Run `cargo test --test stdlib_deque_wide_i64_execution` for all
two-word signed deque APIs, six injected allocation failures, and the
signed recent-values program.
Run `cargo test --test stdlib_deque_wide_u64_execution` for all
two-word unsigned deque APIs, six injected allocation failures, and the
full-width recent-values program.
Run `cargo test --test stdlib_deque_char_execution` for every imported
character-deque function, Unicode and full-width storage, six injected
allocation-failure paths, and the input-driven recent-Unicode program. The
GPU-resident frontend compiles these fixtures to executable x86_64 programs;
`strace` is required to exercise the injected failure branches.

Run `cargo test --test stdlib_deque_bool_execution` for every Boolean
deque function, six injected allocation failures, and the recent-Boolean-count
program with real stdin.
Run `cargo test --test stdlib_deque_i16_execution` for every signed-halfword
deque function, all 65,536 values, six injected allocation failures, and the
recent-values program with checked decimal input.
Run `cargo test --test stdlib_deque_i8_execution` for every signed-byte
deque function, all 256 values, six injected allocation failures, and the
recent-values program with checked decimal input.
Run `cargo test --test stdlib_deque_u16_execution` for every unsigned-halfword
deque function, all 65,536 values, six injected allocation failures, and the
recent-values program with checked decimal input.
Run `cargo test --test stdlib_deque_u8_execution` for every byte deque
function, all byte values through wraparound, six injected allocation
failures, and the binary-input checksum program.
Run `cargo test --test stdlib_deque_u32_execution` for the unsigned
deque APIs, high-bit values, six injected allocation failures, and the
recent-values program.
Run `cargo test --test stdlib_deque_i32_execution` for all deque APIs,
wrapped order, six injected allocation failures, and the recent-values program.
Run `cargo test --test stdlib_map_i32_i32_execution` for the owned map,
initial, growth, shrink, and clone allocation failures, and the stdin byte
histogram.
Run `cargo test --test stdlib_map_bool_u32_execution` for all Boolean-keyed
map functions and the input-driven digit-byte counter.
Run `cargo test --test stdlib_map_u8_u32_execution` for all dense byte-map
functions, 256-key behavior, short-backing traps, and the byte-frequency
program with real stdin and output failure.
Run `cargo test --test stdlib_map_char_u32_execution` for all imported
character-keyed map functions, Unicode and full-width storage, four injected
allocation failures, and the stdin-driven Unicode frequency report. The
GPU-resident frontend compiles these fixtures to executable x86_64 programs;
`strace` is required for the injected failure branches.

Run `cargo test --test stdlib_map_u32_u32_execution` for full-width unsigned
keys and values, allocation failures, and the frequency-report program.
Run `cargo test --test stdlib_map_wide_u64_wide_u64_execution` for two-word
keys and values, allocation failures, and the line-oriented frequency report.
Run `cargo test --test stdlib_map_wide_i64_wide_i64_execution` for signed
two-word keys and values, allocation failures, and the frequency report.
Run `cargo test --test stdlib_map_stateful_execution` for a 40-operation
reference comparison on all four owned maps.
Run `cargo test --test stdlib_set_i32_execution` for the owned integer set,
set algebra, and its initial, growth, shrink, clone, and four set-algebra
allocation failures.
Run `cargo test --test stdlib_set_bool_execution` for all Boolean-set
functions and the 25 ordered-state pairs.
Run `cargo test --test stdlib_set_u8_execution` for all caller-backed byte-set
functions, all 256 memberships, short-backing traps, and the distinct-byte
program with real stdin and output failure.
Run `cargo test --test stdlib_set_char_execution` for every character-set
function, Unicode set algebra, eight injected allocation-failure paths, and
the input-driven distinct-Unicode program. The GPU-resident frontend compiles
these fixtures to executable x86_64 programs; `strace` is required for the
injected failure branches.

Run `cargo test --test stdlib_set_u32_execution` for the unsigned set,
its allocation failures, and the unique-unsigned-total program.
Run `cargo test --test stdlib_set_wide_u64_execution` for the two-word
unsigned set, eight allocation failures, and the line-oriented distinct sum.
Run `cargo test --test stdlib_set_stateful_execution` for 32 mixed
operations and ordered algebra comparisons against a reference for all five
owned set types, including `std::set_char`.
Run `cargo test --test stdlib_set_wide_i64_execution` for the signed two-word
set, eight allocation failures, and the signed line-oriented distinct sum.
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
Run `cargo test --test stdlib_io_hex_wide_i64_execution` for signed
full-width hexadecimal streams, limits, and injected host faults.
Run `cargo test --test stdlib_io_binary_execution` for binary stream input
and output; its host-failure cases run when Linux `strace` is available.
Run `cargo test --test stdlib_io_binary_wide_u64_execution` for full-width
binary stream input and output, limits, and injected host faults.
Run `cargo test --test stdlib_io_binary_wide_i64_execution` for signed
full-width binary streams, limits, and injected host faults.
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
Run `cargo test --test stdlib_file_hex_wide_u64_execution` for full-width
hexadecimal file I/O, bounds, and injected host failures.
Run `cargo test --test stdlib_file_hex_wide_i64_execution` for signed
full-width hexadecimal file I/O, bounds, and injected host failures.
Run `cargo test --test stdlib_file_binary_execution` for binary file input
and output; fault cases run when Linux `strace` is available.
Run `cargo test --test stdlib_file_binary_wide_u64_execution` for full-width
binary file I/O, bounds, and injected host failures.
Run `cargo test --test stdlib_file_binary_wide_i64_execution` for signed
full-width binary file I/O, bounds, and injected host failures.
Run `cargo test --test stdlib_path_execution` for lexical path predicates,
including the UTF-8 Windows component checks and reserved-name boundaries.
Run `cargo test --test stdlib_utf8_bytes_execution` for direct `[u8]` UTF-8
validation, owned text append, the text-report sample, native bounds trapping,
and injected allocation failure when Linux `strace` is available.
Run `cargo test --test stdlib_utf16_execution` for strict UTF-16 scalar
conversion across every BMP code point and the full high-surrogate range,
statuses, physical bounds trapping, and the stdin UTF-16LE count program.
Run `cargo test --test stdlib_utf16_bytes_execution` for both byte orders,
status and bounds behavior, and a runtime case for every byte-view helper.
Run `cargo test --test stdlib_transcode_execution` for UTF-8/UTF-16 code-unit
and UTF-16LE/BE byte-view round trips, no-write failures, physical bounds
trapping, and the stdin summary program.
Run `cargo test --test stdlib_random_execution` for the checked random scalar;
the failure injection cases run when Linux `strace` is available.
Run `cargo test --test stdlib_random_wide_execution` for checked two-word
random values and intervals and the runnable range-draw sample; host injection
cases require Linux `strace`.

## Compiler/runtime dependencies and minimal reproductions

These reproductions concern the GPU-based `laniusc` compiler and its target
runtime, chiefly under `crates/laniusc-compiler` and `shaders`. The separate
`verified_compiler` and Lean workstream verifies a Lanius compiler; it is not
the owner of these GPU compiler or x86 runtime fixes. This stdlib worktree
also fixes the imported struct-return relocation path described below.

1. **Partially resolved: generic payload bodies execute with tested scalar
   and compound type arguments on the resident native path.** Imported Option free functions
   `unwrap_or`, `or`, `and`, and `xor` execute for bool, i32, u32, f32, char,
   and str. Actual Result `unwrap_or`, `or`, and `and` execute with the tested
   scalar T/E combinations, including strings in either payload position.
   The four generic memory value helpers also execute with all six scalar
   identities. This includes two-word strings rather than a guessed machine
   word for every T. Dependency 92 records the implementation and current
   executable evidence.

   Generic tag predicates and concrete matches continue to support the
   documented scalar, record, and borrowed-descriptor instances. Uninstantiated
   bodies that read symbolic payloads, return a symbolic T, or copy an aggregate
   of unknown width retain checked declarations and omit native definitions.
   The resident linker schedules concrete bodies from GPU-checked call
   environments and retargets their exact native call symbols. Different type
   arguments receive different definitions; repeated calls reuse one definition.

   Local templates, concrete record/slice extraction, nested enum forwarding,
   and tested fixed-array values now execute. Dependency 95 and the compiler
   checkpoint list their exact cases. Methods with their own generic
   parameters, substitution inside nested declaration fields,
   constant arguments, recursive instantiation, and return-only inference
   remain incomplete. Used unsupported templates report LNC0017. Wrong
   repeated nominal arguments fail checking with LNC0006.

   Source text, dependency interface pages, checked call environments, and
   the private native call-to-HIR column are retained in resident compiled
   units and charged to their cache budget. Active handles preserve them
   through eviction. The version-5 semantic interface does not persist body
   context, so durable object-only linking remains a dependency. Compiler IR
   record formats, the extractor, proofs, and native ABI are unchanged.

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
   functions to generic `core::range` formerly made its existing `range_full()`
   return fail x86 lowering after unrelated interface growth. Dependency 38
   is now resolved for monomorphic empty struct results. The concrete per-width
   modules retain their distinct width-specific method implementations.
3. **Portable slice construction and metadata.** The four `core::mem` pointer
   and view helpers are compiler-injected intrinsics with no Lanius source
   bodies. X86 lowering passes the backed-view fixture, and an existing Wasm
   byte-write test passes for `i32_array_data_ptr`; no full cross-target
   behavioral claim follows from those checks. The compiler also has a direct
   `slice_from_raw_parts` intrinsic for a concrete typed result. The
   source-level `core::mem::typed_slice_from_raw_parts<T>` wrapper now infers
   its element type from an annotated result, and imported x86 fixtures execute
   `i32`, `u32`, and record slices. The former
   `repro_generic_slice_return_context.lani` mismatch is a positive regression
   case now. A way to read slice length is still needed before slice APIs can
   be independent of caller-supplied lengths. User-program GPU behavior and
   general Wasm behavior remain unverified.
4. **Generic allocation-backed vectors remain blocked.** The old `std::vec`
   silently dropped values in `push`, so that stub was removed. The empty
   generic `Vec<T>` has executable imported associated `new`, `len`, and
   `is_empty` methods with `i32` and `bool` instantiations. Its three free
   constructor also executes through an imported, annotated result. The free
   `len` and `is_empty` functions now infer scalar type arguments from imported
   `Vec<T>` values. `std::vec_i32`,
   `std::vec_u32`, `std::vec_u8`, `std::vec_i8`, `std::vec_u16`, and
   `std::vec_i16`, `std::vec_bool`, and `std::vec_char` have tested storage, growth, mutation, failure, and
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
12. **Native const-generic array indexing remains unsupported.**
    `repro_array_i32_const_generic_index.lani` directly indexes a
    `[i32; N]` parameter in a const-generic function. Native emission still
    reports `LNC0017` at `values[0]`. `N as i32` also fails GPU checking with
    `LNC0005` in `repro_array_i32_const_value.lani`; fixed arrays lack a
    callable `values.len()` method (`LNC0027`). The public `core::array_i32`
    helpers now accept borrowed `[i32]` views, which fixed arrays of several
    lengths pass successfully. `tests/stdlib_array_i32_view_execution.rs`
    executes both helpers and confirms native bounds failure for empty and
    invalid indices. Direct const-generic array indexing remains a compiler
    dependency, but this public module no longer relies on it.
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
17. **Resolved: integer-to-character conversion.**
    There is no implicit or `as` conversion from `i32` or `u32` to `char`;
    only `u8 as char` casts into `char`. `core::char::from_u32` returns
    `Option<char>` and `from_u32_or` takes a fallback; both accept exactly the
    Unicode scalar values. `repro_i32_to_char.lani`, `repro_u32_to_char.lani`,
    and `char_conversion_runtime.lani` convert through them across returns,
    calls, locals, fields, enum payloads, and raw cells, and check that
    surrogates and values above U+10FFFF take the fallback. The std character
    containers store `char` values in `char`-typed slots, and the four
    Unicode sample programs convert decoded scalars with `from_u32_or`. This is
    a GPU frontend plus x86 runtime claim; no user-program GPU target execution
    is claimed.
18. **Resolved: raw secure random scalar failure channel.** The x86 runtime
   bytes for `std::random::secure_u32` previously returned `0xFFFFFFFF` when
   the `getrandom` syscall did not return four bytes. That bit pattern is a
   valid random `u32`, so the failure was ambiguous. The runtime binding now
   traps with `ud2` on a short read or host error. The focused native test
   executes a successful draw and injects both `EIO` and a two-byte read,
   checking for SIGILL. Callers needing a recoverable error can use the signed
   status from `fill_secure_bytes` or the Lanius `std::random_checked` wrappers.
19. **Resolved: transitive host imports retain the native entrypoint.** With
    `--stdlib-root tests/fixtures/stdlib_foundation/repro_transitive_host_root`,
    `repro_transitive_host_direct.lani` emits an x86_64 ELF that exits zero.
    `repro_transitive_host_import.lani` now does likewise through `test::probe`
    and its transitive `std::process` import. The earlier missing-main report
    masked the GPU SSA failure on that helper's explicit void return.
    `tests/stdlib_void_return_execution.rs` executes the transitive exit path
    and a directly imported host exit on failure, checking status 0 and 7.
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
    `core::slice::copy_nonoverlapping_range` uses two backed views and five
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
    `repro_hash_trait_call.lani`. The semantic-interface member count and
    scatter passes filter for `METHOD_SIGNATURE_INHERENT_IMPL` in
    `shaders/type_checker/interface/members/00c_method_counts.slang` and
    `02_scatter_hir.slang`; public trait methods have no corresponding
    exported member. The dependency method projector also requires an owning
    exported type declaration for each associated method. Primitive receivers
    such as `i32` have no public nominal type declaration to own one, so
    merely relaxing the inherent-method filter would not supply the missing
    callable identity. Imported trait-method export and native dependency-call
    resolution remain before the trait APIs themselves can be claimed
    executable.
32. **Resolved: unordered f32 comparisons.**
    `tests/fixtures/stdlib_foundation/repro_f32_unordered.lani` now exits 2:
    only `nan != nan` is true. Native x86 `UCOMISS` sets parity for unordered
    operands, so comparison results and fused branches now combine their
    ordinary condition with the parity flag. The executable fixtures cover
    direct branches, bool values passed between functions, both operand
    orders, signed zero, and NaN behavior of `core::f32` helpers.
33. **Resolved: out-of-range narrow integer casts.**
    `tests/fixtures/stdlib_foundation/repro_signed_narrow_cast.lani` casts
    128 from `i16` to `i8` and 32,768 from `i32` to `i16` and expects -128
    and -32,768. `repro_unsigned_narrow_cast.lani` casts 256 and 65,536 from
    `u32` to `u8` and `u16` and expects zero. Both used to exit 3 because
    `as T` was ignored (dependency 51). `as` is now a real operator: a
    narrowing cast keeps the low bits of the target width, and a widening cast
    sign-extends a signed source and zero-extends an unsigned one. Both
    fixtures exit 0 on x86_64. `tests/cast_expression.rs` runs an x86_64
    program with 24 more width, signedness, and `bool` checks. The
    `core::narrow` helpers keep their explicit wrapping, checked-fallback, and
    saturating policies and now narrow with `as`.
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
35. **Resolved: explicit return in a void helper.**
    `tests/fixtures/stdlib_foundation/repro_void_return.lani` defines an
    unused void helper containing only `return;` alongside a valid `main`.
    Native compilation and execution now succeed. The GPU SSA operand-role
    helper recognizes that a void return has no value edge. The executable
    `tests/stdlib_void_return_execution.rs` also calls an imported void helper
    twice and checks the side effect after both an early and a final return.
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
37. **Same-name generic methods collide across signed widths.**
    The smaller `repro_method_signed_width_collision.lani` declares only
    `Small<i8>::get` and `Small<i32>::get`; `laniusc check` rejects the second
    with `LNC0016` and a misleading “expected function name” label. With
    `LANIUS_DEBUG_STAGE_ERRORS=1`, the underlying GPU type checker reports
    `BadHir detail=1`, its duplicate method-key status. The older
    `repro_third_concrete_method.lani` declares `Small<i32>`, `Small<u32>`,
    then `Small<i8>`; it rejects the third method because `i8` collides with
    `i32`, not because it is third. Putting `i8` first moves the rejection to
    the later `i32` method, while renaming one method passes.
    `LANGUAGE_DECL_TAGS` currently assigns the same scalar type code `3` to
    all signed integer widths and `4` to all unsigned widths. The method
    receiver argument hash and exact comparison use those collapsed scalar
    payloads, so distinct width specializations share a lookup key. Raw GPU
    lexing and standalone parsing accept the repro; the type-check method-key
    pass rejects it. The concrete `range_i8`, `range_i16`, `range_u8`, and
    `range_u16` modules now expose and execute same-name receiver methods on
    their distinct concrete range types. Generic `Range<T>` width-specific
    method overloads still need width-preserving method keys.
38. **Resolved: RangeFull layout after unrelated exports.**
    `repro_range_full_growth.lani` imports the adjacent
    `repro_range_full_growth_root` copy of `core::range` with seven extra
    scalar identity functions. Run it with `--stdlib-root
    tests/fixtures/stdlib_foundation/repro_range_full_growth_root --emit
    x86_64`. The unmodified module and the copy with six extra functions
    formerly compiled; seven produced `LNC0017` at the existing `range_full()` call:
    the empty nominal result has no canonical ABI layout (LIR opcode 23).
    A page-local canonical type row escaped into the runtime artifact and its
    external reference tag was truncated to a scalar tag. Rows at or above
    128 were mistaken for aggregate machine type codes. GPU dependency
    projection now proves a monomorphic struct has no fields or generic
    parameters while the complete interface is active. It retains the nominal
    reference for type checking and publishes the existing zero-word unit
    machine representation for the runtime artifact. Unknown aggregate widths
    do not qualify. Compiler IR layouts and the x86 ABI are unchanged.
    `repro_wide_range_full_import.lani` is a smaller cross-module case: simply
    importing both `core::range` and `core::wide_u64_range` and calling
    `range_full()` formerly produced the same diagnostic. Both reproductions
    now execute in `imported_empty_struct_results_execute_without_erasing_nominal_checks`.
    Assigning the empty result to an unrelated struct or to i32 still produces
    `LNC0006`. The wide range module currently provides `full_contains` as a
    scalar predicate; generic empty results and untested forwarding APIs are
    not covered by this repair.
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
    inference; dependency 41 describes the repaired scalar body stride and
    the remaining element-layout limitations.
41. **Resolved for the documented scalar elements: generic slice storage stride.**
    The signed generic get_or reproduction originally loaded eight-byte words
    while its caller stored four-byte i32 elements. Generic indexing and
    iteration are now deferred when their element reference is symbolic, even
    if the function returns only a Boolean or count. Scalar body replay then
    supplies the concrete element type before normal lowering.

    The actual core::slice exposes ten shared generic access/copy functions;
    its remaining 27 algorithms are i32-specific. Runtime tests execute i32,
    u32, bool, f32, char, i8, i16, u8, and u16, including both overlap
    directions, invalid bounds, NaN, negative zero, physical bounds traps,
    and a real program using Option and ranges. No x86 array ABI is changed.
    String, record, nested-view, and native i64/u64 elements remain outside
    this checkpoint. See the slice guide and dependency 94 for raw views and
    local calls.
42. **Resolved: imported Boolean calls accept comparison expressions.**
    `repro_option_bool_comparison_arg.lani` formerly passed `laniusc check`
    but failed native compilation with `LNC0006`: the imported-call validator
    read the i32 type of the first token in `count == 2` rather than the bool
    result. It now classifies comparison and Boolean expression results after
    following expression wrappers. The reproducer and
    `sample_programs/vector_true_count.lani` compile and execute on x86. A
    separate negative fixture confirms that passing a bare i32 still fails.
43. **Resolved: floating-to-integer casts.**
    `repro_f32_to_i32_cast.lani` assigns `7.0 as i32` to an i32 local. It used
    to fail with `LNC0006`, expecting i32 but seeing float. Float-to-integer
    casts now follow Rust: they truncate toward zero, saturate at the target's
    bounds, and map NaN to zero. Integer-to-float casts round to nearest, and
    `f32` and `f64` convert to each other. The fixture exits 0 on x86_64.
    `tests/cast_expression.rs` checks truncation, saturation of `u8`, `i8`,
    `i32`, `i64`, and `u64`, NaN, infinities, and `u32` and `u64` round trips
    through `f64`. The wasm backend does not support conversions yet.
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
51. **Partially resolved: trailing identifiers after an expression.**
    `as` is now a keyword, and `expr as T` is parsed, type-checked, and
    executed (see "Scalar casts" in `docs/compiler-semantic-contracts.md`). A
    cast between unsupported types reports `LNC0072`, and a generic, array, or
    reference target is a parse error. `repro_cast_call_result.lani` and
    `repro_cast_arithmetic_result.lani` put `as` after a call and a grouped
    arithmetic expression. They used to stop with `LNC0016` at `as`; they now
    exit 7 and 0 on x86_64. Before this change, `as T` after a simple name was
    silently ignored. `repro_ignored_postfix_identifier.lani` still shows that
    parser defect for other words. In `let y: i32 = x not_a_cast NotAType;`,
    GPU `check` now reports only `LNC0006` at `x` (u32 where i32 is expected).
    Neither trailing identifier is diagnosed.
    The type checker no longer converts scalars implicitly, so the stdlib's
    older idiom of converting through a typed `let`, `return`, or assignment
    made more than 50 stdlib fixtures fail `check`. About 400 such sites in 55
    modules now use `as`. The `i32` cells of `std::vec_char`, `std::set_char`,
    `std::map_char_u32`, and `std::deque_char` still convert back to `char`
    implicitly. Rust has no `i32 as char`; those modules need a checked
    code-point conversion. Resolved: the four modules now store `char` values
    in `char`-typed slots, and `core::char::from_u32` is the checked
    conversion (item 17).
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

59. **Resolved: lexical locals shadow ambiguous imported values.**
    `tests/fixtures/stdlib_foundation/lexical_shadow_ambiguous_imports.lani`
    imports two modules that each export `zero`, then uses a local and a
    parameter named `zero`. Previously both `laniusc check` and x86 emission
    reported `LNC0005` at the local use. The GPU value-path validator now
    defers a one-segment import ambiguity until lexical name resolution, so
    a local binder can win. Function-scope and module-scope ambiguous imports
    without a local binder still produce `LNC0005`. The native regression
    runs and exits zero.

60. **x86-64 `usize` arithmetic has 32-bit range.**
    `tests/fixtures/stdlib_foundation/repro_usize_x86_pointer_width.lani`
    starts from `u32::MAX`, widens it to `usize`, and adds one. GPU checking
    and native emission succeed, but the x86 executable exits 1 because the
    result is zero after crossing the 32-bit boundary. The language decision in
    `formal/SEMANTIC_DECISIONS.md` specifies a 64-bit `usize` on x86-64.
    This prevents a full-width `OptionUsize` or `ResultUsize` claim even though
    pointer-valued Option/Result operations execute. The GPU compiler must
    preserve pointer-width arithmetic and comparison before those APIs can be
    considered executable across the declared `usize` domain. The builtin
    declaration table currently assigns both `u32` and `usize` scalar type
    code 4, so an x86 instruction selected from that code alone cannot
    distinguish their widths. The fix must retain pointer-width type identity
    through GPU semantic projection, not only change one emitted instruction.

61. **Resolved: literal-left unsigned comparisons.**
    `tests/fixtures/stdlib_foundation/char_high_bit_comparisons.lani` compares
    a Unicode character literal against character values containing the
    unsigned high bit and all bits, and an integer literal against `u32`
    values above the signed maximum. Before the fix, the first literal-left
    `char` and `u32` comparisons exited 4 and 1 respectively in separate
    minimal native reproducers. The GPU semantic LIR lowering now selects
    the right operand's checked unsigned type for these literal-left cases.
    The imported runtime fixture also executes character ordering, comparison,
    range, and slice helpers across the same high-bit boundary.

62. **Imported generic aggregate return layout.**
    `tests/fixtures/stdlib_foundation/repro_imported_generic_aggregate_identity.lani`
    calls the real `core::mem::identity` with a two-field `Pair`. GPU checking
    and native emission succeed, but the ELF exits 1 because the returned
    first field differs from its input. Compile with
    `laniusc --stdlib-root stdlib --emit x86_64 -o /tmp/repro_identity tests/fixtures/stdlib_foundation/repro_imported_generic_aggregate_identity.lani`
    and run `/tmp/repro_identity` to reproduce. The equivalent local generic
    function is rejected at native emission with `LNC0017` because its
    aggregate result has no canonical ABI layout. The scalar instances in
    `core_mem_values.lani` execute; aggregate instances cannot be claimed
    until generic return layout and call lowering agree on the concrete type.

63. **Nested fixed enum returned from a helper.**
    `cargo test --test codegen_x86 x86_executes_nominal_struct_enum_payloads`
    fails in its `nominal_enum_nested_return.lani` subcase: the x86 executable
    exits 1 instead of 0 after `make` returns `Outer::Wrapped(Inner::Number(5),
    7)`. The same failure occurs at clean commit `406f7aa`, before concrete
    generic-enum layout was added. The other four cases in that test reach
    the final subcase. This remains an existing fixed-enum return dependency;
    the concrete generic-enum tests do not establish nested enum return
    correctness.

64. **Nested match as a match-arm result.**
    `repro_imported_generic_payload_nested_match.lani` uses a second `match`
    directly as the result of an imported `Some(inner)` arm. GPU `check`
    reports `LNC0016` at the inner `match`, so this expression form is not
    accepted syntax. Native emission currently reports the less useful
    `LNC0057` instead. This is a syntax and diagnostic dependency, separate
    from the executable flat imported payload patterns above.

65. **Resolved: imported `f32` receiver method returns.**
    `repro_imported_f32_method.lani` imports the tiny adjacent
    `repro_imported_f32_method_root/core/probe.lani` module. Native compilation
    previously succeeded, but its ELF exited 139 at `value.start()` while
    the imported `free_start` and a local receiver method worked. The GPU
    type checker's later local method lookup cleared an already resolved
    imported method's return type because it checked only the local function
    index. It now also checks the imported dependency ID before changing the
    call record. The minimal repro, all 14 `core::range_f32` receiver methods,
    and the floating window sample execute on x86_64. This changes GPU
    semantic resolution, not the x86 call ABI; user-program GPU device
    execution is still unverified.

66. **Resolved: imported aggregate-returning method chains.**
    `repro_imported_method_chain.lani` calls
    `success.or(failure).contains(7)` and a longer `or` chain through the
    real `core::result_u32` import. GPU `check` previously succeeded while
    native source-pack compilation reported `LNC0027` at `contains`.
    The GPU dependency projector now records the imported method result's
    stable type identity, and the method-resolution loop projects imported
    methods after each call-result key pass. The fixture executes those
    chains and `OptionU32::ok_or(...).contains(...)` across two modules on
    x86_64. The option/result sample also executes an i32 chain and prints
    `38`. Method-chain resolution uses the compiler's existing eight-pass
    limit; deeper chains are not claimed. This changes GPU semantic
    resolution, not the x86 ABI or IR.

67. **Resolved: imported associated-method result validation.**
    Imported methods are stored as dependency members. The direct-call result
    validator previously searched only top-level declarations, so it skipped
    a typed assignment from `Other<i32>` to `Bucket<i32>`. It now recognizes
    the method's member identity on the active dependency page and rejects
    the mismatch with `LNC0006`. The negative fixture in
    `tests/stdlib_generic_vec_flat_execution.rs` and the executable imported
    method fixtures cover the rejection and valid calls.

68. **Resolved: concrete generic enum returns.**
    Returning `Maybe<bool>` from a helper previously reached unsupported LIR
    opcode 9 because its symbolic nominal type lost the instantiated payload
    width. GPU semantic projection now preserves the checked concrete type
    reference, substitutes scalar payload arguments, and supplies the checked
    function result width to return materialization. The `Some(false)` identity
    case, all `Option<bool>` combinators, and both bool programs execute. This
    uses the existing IR fields and native calling convention.

69. **Resolved: imported generic member ordinals and enum tags.**
    Interface generic parameters store absolute member identities. Concrete
    instance arguments and call claims use parameter ordinals. GPU consumers
    now resolve the member's ordinal before indexing those relations, including
    slice claim collection and emission. Imported enum tags count variant
    members, excluding generic parameters and methods. Concrete enum layout
    uses instantiated scalar payload widths. The enum regression suite, the
    bool state matrix, generic Vec calls, and the two-view generic slice fixture
    execute; mismatched generic arguments remain rejected.

70. **Resolved: concrete imported associated-method argument signatures.**
    `repro_option_bool_method_wrong_fallback.lani` passes an integer to the bool
    fallback of `unwrap_or`; `repro_option_bool_method_wrong_combinator.lani`
    passes a value of the wrong type to `and`. Both now fail with `LNC0006`.
    Typed Parameter members under the public receiver declaration carry the
    stable method symbol and source parameter ordinal using existing record
    fields. Syntactic self and &self are implicit and omitted; a typed first
    parameter remains explicit for qualified calls and is consumed by dotted
    calls only when its checked type matches the receiver.
    The general dependency validator checks scalar and nominal parameter types,
    including concrete scalar arguments of generic enum instances. Projected
    factory results without an annotation subtree compare their checked type
    argument references. A resolved signature without a parameter record fails
    closed. No bool-specific argument-validation workaround is used.
    Enabled tests execute multi-parameter static, borrowed, and typed receiver
    calls and reject wrong arguments in each position and unrelated nominal
    types. Option/Result method fixtures and the 138-entry foundation gate
    execute. General generic method-body specialization remains dependency 1.

71. **Resolved: imported method result passed as a direct argument.**
    `repro_option_bool_method_argument.lani` passes `present.ok_or(true)` directly
    to `core::result_bool::contains`. The dependency validator previously read
    the receiver token and compared `Option<bool>` with `ResultBool`, reporting
    `LNC0006`. It now reads the projected callee result reference for call
    arguments. The minimal program and complete bool Option/Result fixture
    execute. Passing a method returning `Option<bool>` where `ResultBool` is
    expected still produces a type mismatch.

72. **Resolved: concrete scalar receiver arguments on imported factory results.**
    `repro_option_bool_factory_method.lani` calls
    `core::option::ok(success).contains(false)`. Previous shaders report
    `LNC0027`: the imported result's stable nominal identity survives, but its
    concrete receiver arguments are lost. Call projection now retains concrete
    scalar arguments in the existing local type-instance storage and publishes
    an instance result reference. It copies those values while the exporting
    interface page is resident; receiver lookup no longer needs a page-local
    canonical type index after that slot is reused.

    The enabled runtime regression checks thirty direct-receiver operations
    over false, true, absence, both Result variants, fallbacks, combinators,
    nested factory arguments, and conversion back to Result. A separate
    imported `Maybe<T>` fixture executes bool and u8 factories with same-name
    methods, including false, true, zero, and 255. Both wrong method-result
    scalar types are rejected. A separate `Quad<bool, u8, i32, u32>` factory
    retains all four arguments and executes a checksum over its five-word
    enum value. Switching the same test binary back to the previous shaders
    reproduces `LNC0027` for both the Option receiver and four-argument receiver.

    Projection uses the existing four scalar slots per token. Larger argument
    lists and compound generic arguments retain their canonical references and
    still need structural instance projection. Executable evidence covers
    one-argument bool and u8 instances and the four-argument scalar instance.
    Combining both factory families in one module exposed the separate
    dependency 74, now resolved below. No compiler IR, extraction, proof, or
    native ABI fields change.
    The complete focused check passes 62 tests across the bool Option,
    foundation, generic enum, and generic Vec suites. An interleaved 4 MB
    performance check has median paired change -0.92%; all thirty native
    outputs pass and match the previous version byte for byte. The imported
    bool program's eighty measured entry rebuilds show no increase, and all
    eight final process outputs print `3` and exit zero. Timings and limits
    are retained in `docs/stdlib-gpu-performance.md`.

73. **Resolved: delimiter tree queries after parser workspace shrinkage.**
    `portable_stdlib_helpers_execute_on_x86` reaches `halfword_window_total`
    and reports `LNC0016` at the closing brace of `core/option_u16.lani`.
    The failure repeats when this test runs alone. A fresh CLI compilation of
    that example emits an executable which prints `32786` and exits zero;
    a short daemon sequence also succeeds. The failure therefore does not
    establish that the source is invalid. Reduction found a two-entry public
    compiler API reproduction:

    ```bash
    timeout 110s cargo run --release --example stdlib_compile_sequence -- \
      sample_programs/character_inventory.lani \
      sample_programs/halfword_window_total.lani
    ```

    Before the fix, it failed at the second entry under both the baseline
    c37d38b shaders and the earlier Option shader fixes. The retained parser
    allocated delimiter-tree leaves at index 64 after the larger job. Query
    shaders recomputed index 32 from the smaller current job and searched the
    wrong tree rows. GPU parser parameters now publish the allocated leaf base
    to brace, bracket, and match-pattern queries. Logical token and block bounds
    continue to describe the current source pack. This changes GPU-private
    uniforms; it does not change compiler IR, formal proofs, extraction, or the
    native ABI.

    `stdlib_helpers_execute_after_parser_workspace_shrinks` executes both real
    programs twice through the shared compiler, checking stdout `3` and `32786`
    and zero exit status. Switching back to the previous shaders makes that test
    fail with the original `LNC0016`; the new shaders pass. All seven foundation
    tests, including the combined 138-entry executable gate, pass. Parser
    rejection, feature flags, concrete generic enum execution, and bool Option
    regressions also passed; dependencies 70 and 74 were still open at that
    checkpoint. Dependency 74 is now resolved below.
    The minimal sequence, pre-fix diagnostics, reduction record, and passing
    regression logs are retained under `tests/fixtures/stdlib_compiler_state/`.
    Interleaved 4 MB and 5 MB performance checks give median paired changes
    of +0.50% and -2.72%; all 60 emitted programs execute and match the previous
    native binaries. Earlier sequential comparisons were slower and remain
    recorded in `docs/stdlib-gpu-performance.md`. The interleaved checks do not
    reproduce a material regression; they do not establish identical timing.

74. **Resolved: concrete layout for later generic enums in a module.**
    `repro_factory_mixed_receiver.lani` imports a module containing both
    `Maybe<T>` bool/u8 factories and a `Quad<bool, u8, i32, u32>` factory. Native
    compilation previously reported `LNC0017` at the four-payload `Item`
    constructor, with first unsupported target LIR opcode 30 (`AGGREGATE_ADDR`).
    The isolated Maybe and Quad modules each executed successfully, including
    the Quad checksum of 257. Reduction to
    `repro_generic_enum_mixed_layout.lani` leaves just nine lines: two generic
    enum declarations and one annotated Quad constructor. Removing the first
    unused `Maybe<T>` declaration allowed native compilation. GPU metadata
    readback confirmed that type checking had the correct four arguments and
    five-word layout. The semantic materializer used the call's discriminant
    ordinal within an enum as a global compact-variant row, selecting the first
    enum's owner. It now resolves the constructor's checked enum result
    declaration before finding its concrete layout. No compiler IR fields,
    extraction, proofs, or native ABI change.

    Three enabled runtime regressions execute the nine-line reproduction, the
    combined imported factories, and a later enum with an empty first variant,
    four distinct scalar payloads, and payload/empty values returned through a
    helper. The first enum also executes. Each regression fails with the
    previous shaders and passes with the fix on the same test binary. The
    focused check passes 65 tests across bool Option, foundation, generic enum,
    and generic Vec, including the 138-entry executable gate. An interleaved
    4 MB comparison has median paired change +2.01%; all thirty emitted programs
    pass and match the previous native hashes. Eighty imported entry rebuilds
    have pooled median change -2.55%, with eight final outputs checked. Raw
    results and limits are in `docs/stdlib-gpu-performance.md`. Diagnostics,
    metadata probe, and runtime regression logs are retained under
    `tests/fixtures/stdlib_compiler_state/`.

75. **Resolved: payload comparison in a later match arm.**
    `repro_enum_match_later_payload_arm.lani` is a seven-line fixed-enum
    reproduction: `Empty -> false` precedes `Some(value) -> value == 7`.
    Native compilation reports `LNC0057`; the internal failure is GPU SSA
    validation reason 104. Moving the payload arm first allows the program to
    execute with exit status zero. Reordering the enum declarations does not
    repair it. A two-payload logical expression also fails, including without
    generic types. A temporary GPU metadata probe confirmed the scheduling
    failure: the final compound arm shares its closing token boundary with the
    match. The match's trap, merge, result read, and consuming local store ran
    before the final arm's result store, branch, and closing marker. The
    materializer now schedules the arm closing rows first, then the match
    closing rows, then effects consuming the result. Assignment of a match
    result uses that same completion boundary. SSA validation stays enabled;
    no compiler IR, extraction, proof, or native ABI changes were needed.

    Three enabled runtime regressions cover the original seven-line case,
    compound logical arms with two and four payloads, and match results used
    in locals, direct returns, arithmetic arms, and assignments. Both empty
    and payload variants execute, including matching and nonmatching payloads.
    A false logical operand guards division by zero. All three tests fail with
    SSA reason 104 under the previous shaders and execute under the fix on
    the same binary. The adjacent runtime suites pass 68 tests, including the
    foundation's 138-entry executable gate. These checks use GPU compilation
    and native execution on x86_64 Linux; GPU device execution is not claimed.
    The temporary probe edits were removed; its patch, schedule readback, and
    regression logs remain in `tests/fixtures/stdlib_compiler_state/`.
    An interleaved 5 MB performance comparison has median paired change
    -0.12%; all thirty native outputs pass and match the previous hashes.
    Detailed timing records are in `docs/stdlib-gpu-performance.md`.

76. **Resolved for fixed caller-local structs: imported enum constructors.**
    The eight-line `repro_imported_option_local_nominal.lani` creates a two-word
    local Pair and assigns Some(pair) to imported Option<Pair>. It now compiles
    and executes. Dependency result validation reads the checked local struct
    fields to derive a concrete width, recursing through fixed nested structs
    with cycle, depth, and overflow checks. Nominal identity is retained:
    another same-shape struct is rejected. Empty, cyclic, and
    fixed-array-containing layouts produce `LNC0006` rather than a guessed
    payload width. Payload structs from other imported units, fixed-array,
    and nested generic arguments are outside this support. Direct scalar
    slice payload support was added separately in dependency 84.

    The formerly ignored imported predicate matrix now executes 44 tag checks,
    including the real generic receiver predicates on scalar, Pair, and Quad
    instances. Concrete matches and fallback helpers recover every word of
    Pair, Quad, and nested record payloads. String payloads and string fields
    use their existing two-word pointer/length representation consistently in
    field layout, aggregate initialization, field loads, and match result
    stores. Borrowed slice fields retain access and aliasing. No compiler IR
    records, extractor, proof files, or native ABI formats change.

    Focused runtime checks are in `tests/stdlib_generic_predicates_execution.rs`;
    source fixtures and logs are retained under `tests/fixtures/`. The broad
    foundation gate and performance sweep were not repeated for these changes.

77. **Fixed-array fields in native struct values.**
    `repro_fixed_array_struct_field.lani` is a seven-line program with no
    imports or Option value. It constructs `{ first: i32, values: [i32; 3],
    last: i32 }` and checks each array element. Native compilation succeeds,
    but the executable exits 1 instead of 0. The array field's native copy and
    indexing representation need support. Imported Option constructors reject
    these layouts explicitly with `LNC0006`; scalar, nested fixed-record,
    string, and borrowed slice fields are a separate executable claim.

78. **Resolved for named concrete views: borrowed slice iteration.**
    `repro_borrowed_slice_iteration.lani` formerly emitted an executable that
    silently skipped an ordinary three-element `[i32]` loop. Lowering treated
    the runtime-length marker `0xfffffffe` as a signed constant bound. A private
    slice recipe now captures the view once and reads its actual length before
    entering the loop. Reassigning the source variable during iteration does
    not replace the captured view. Synthetic element loads retain their checked
    scalar type. No IR record, native ABI, or proof changes were made.

    `tests/stdlib_slice_iteration_execution.rs` executes concrete i32, u32, u8,
    bool, and f32 parameter views. Its real-stdlib fixture covers populated,
    empty, and one-element views; signed values; nested loops; conditional
    return, break, and continue; descriptor reassignment; borrowed mutation;
    and a slice recovered from `Option<Readings>`. It combines the Option,
    memory, range, and saturating-number modules. Bind a projected slice to a
    typed local before iterating: direct field/call iterable expressions remain
    unsupported and fail with a source diagnostic. Unconditional return has a
    separate SSA dependency below. Focused logs are retained under
    `tests/fixtures/stdlib_compiler_state/`.

79. **Resolved: reuse of match payload binding names.**
    `repro_option_reused_payload_binding.lani` uses `Some(inner) -> inner` in
    two independent matches within the same function. Checking previously
    rejected the second binding anchor with `LNC0005`. The name-use pass now
    excludes declaration anchors published by the compact declaration table.
    Both recovered values execute correctly. A companion negative case still
    rejects an attempt to use `inner` in the `None` arm; reuse does not expand
    the binding's scope.

80. **Resolved for the tested imported layout: concrete local record Option returns.**
    `repro_imported_option_local_nominal_return.lani` constructs a Pair,
    returns imported `Option<Pair>` through a concrete function, and reads its
    second field. Native lowering previously rejected the call with `LNC0017`,
    opcode 20, because the generic enum instance had no completed return width.
    The imported enum layout helper now accepts checked fixed local struct
    arguments. Semantic projection completes the width after local field types
    resolve, retains the checked call instance, and publishes the complete
    width for function and call lowering. Its canonical interface resource is
    explicitly bound in the private GPU graph. No native ABI format or
    compiler IR record changes were made.

    The minimal return case and `optional_reading_summary.lani` both execute.
    The sample checks present and absent concrete function returns and prints
    `4` and `20`, using slice reads, range validation, and saturating arithmetic.
    The completion path consults the active dependency page. Arbitrary
    multi-page imported packs have not been verified for caller-local payload
    returns. Generic function-body specialization remains dependency 1.
    At that checkpoint, the imported Option checks, bool suite, and
    symbolic-payload rejection check passed 25 tests. These preceded the
    direct-slice changes below. Their three focused logs are
    listed in [the Option guide](stdlib-option.md). Broad GPU suites and
    performance measurements were not repeated.

81. **Unconditional return from a for-loop body fails SSA validation.**
    `repro_slice_iteration_unconditional_return.lani` contains a concrete
    `[i32]` parameter and immediately returns its first loop value. It reaches
    `LNC0057`; the GPU lowering detail reports optimization-structure failure
    with reason 104. The synthetic induction-variable read after the return
    has no reaching definition in its unreachable block, while the SSA read
    resolver and validator require one. This is independent of imported
    generics and Option. Conditional early returns execute in the slice
    integration fixture. The unconditional case requires a consistent policy
    for unreachable reads through SSA construction and validation; disabling
    a validator alone would leave the remaining construction stages unsound.

82. **Resolved: named slice descriptor copies.**
    `let copy: [i32] = original` formerly copied words through the data pointer
    instead of copying the descriptor. An empty source could be dereferenced;
    a populated source could acquire an incorrect length. Native lowering now
    distinguishes a direct named descriptor from an expression yielding a
    pointer to descriptor storage. Direct copies preserve the data pointer and
    length, emit no aggregate-data-copy rows, and do not access the borrowed
    storage. The same path handles descriptor reassignment. The slice fixture
    checks the captured view after reassigning its source and shared-storage
    mutation through an Option payload.

83. **Resolved: scalar induction values in fixed-array loops.**
    `repro_fixed_array_parameter_iteration.lani` and
    `repro_struct_array_iteration.lani` formerly crashed with SIGSEGV. The
    synthetic i32 counter inherited the iterable's aggregate word count, so
    initializing it to zero emitted a copy through a null address. Array and
    slice recipes now retain aggregate widths only for the iterable capture
    and projected element, keeping counters and bounds scalar. Record elements
    retain every payload word. The focused iteration suite executes both
    regressions, checking scalar sum 2 and record sum 102, along with ranges
    and the five tested scalar-slice element types. No IR record or native ABI
    changes were made.

84. **Resolved for tested scalar elements: direct `Option<[T]>` payloads.**
    `repro_option_direct_slice_payload.lani` constructs the actual imported
    generic enum with a borrowed slice rather than a wrapper record. Imported
    layout projection retains the two-word descriptor. Generic claims preserve
    canonical slice references and compare their element types; matching
    publishes a checked slice-result reference and preserves the payload's
    descriptor representation. The bracket matcher also derives the closing
    type-bracket classification from immutable context, removing a same-dispatch
    dependency on the opener's write.

    Five focused tests execute i32, u32, u8, bool, and f32 slice payloads,
    generic free and receiver predicates, both variants, empty presence,
    extraction, aliasing, and native bounds traps. The scalar matrix also
    returns present and absent values through concrete functions for all five
    element types. Wrong constructor element
    types, inconsistent repeated generic T arguments, and mismatched match-arm
    element types still produce `LNC0006`. Slice-valued match-arm results use
    typed locals in these tests. Compound-element slices, fixed-array payloads,
    and nested generic payloads are outside this claim. Generic function-body
    specialization remains dependency 1. No IR record or native ABI changes
    were made; the real programs execute on x86_64 Linux through the GPU compiler.

85. **Resolved: borrowed slice runtime length across calls.**
    `repro_option_slice_loop_return.lani` reduced an incorrect empty-input
    Option return to a plain counting function: the callee received length 2
    for a zero-length view. Call argument lowering replaced the runtime marker
    with the descriptor's aggregate word count. It now retains the runtime
    marker for explicit arguments and receivers; fixed arrays keep their checked
    literal lengths. The obsolete aggregate-width resource binding was removed
    from that private pass. Existing IR records and calling conventions remain
    unchanged.

    `slice_runtime_call_lengths.lani` executes lengths 0, 1, 2, 3, and 7 through
    direct and forwarding functions and checks fixed-array coercion.
    `repro_option_slice_scoped_returns.lani` checks both conditional absence
    returns and a present return. The loop-return reproduction now executes,
    and `optional_slice_window.lani` returns `None` for empty and invalid input,
    preserves the present borrowed view, and prints `4` and `20`. These cases
    are enabled in the five-test Option-slice and five-test iteration suites;
    logs are `option-direct-slice-tests.log` and `slice-iteration-tests.log`
    under `tests/fixtures/stdlib_compiler_state/`. The original failing native
    result is retained in `option-slice-loop-return.log`, and the earlier
    composed-program failure is in `option-direct-slice-return.log`.
    The adjacent six imported scalar/record Option tests and six selected bool
    tests also pass; logs are `option-slice-adjacent-predicates.log` and
    `option-slice-adjacent-bool.log`. The strengthened scalar return matrix
    passes in `option-slice-return-scalar-matrix.log`. Broad GPU suites and
    performance comparisons were not repeated.

86. **Integer-width identity also merges concrete Option method keys.**
    `repro_option_unsigned_width_method_keys.lani` declares one method on
    `Maybe<u32>` and the same name on `Maybe<u8>`. Both bodies return true and
    contain no generic payload access. The lexer and parser accept the module;
    GPU checking reports `BadHir`, detail 1, at the second method. The method-key
    validator identifies it as a duplicate because the language declaration
    table maps both unsigned widths to one scalar identity. This extends the
    trait-key dependency 57 to inherent methods. The current public diagnostic
    misleadingly reports `LNC0016`, "expected function name"; the actual failure
    is duplicate-method validation. Its diagnostic log is
    `option-unsigned-width-method-keys.log`.

    The main Option module therefore uses one unsigned implementation rather
    than two colliding definitions. Executable tests cover u8 values 0, 128, and
    255 and full-width u32 values through the same methods. This supplies the
    payload operations without claiming distinct-width argument checking or
    narrowing. The corresponding signed-width alias remains as well. Correct
    width-specific type identity through checking, interfaces, and lowering is
    still a compiler dependency. The four-test scalar suite, its reading-selection
    program, and the adjacent bool and slice checks are retained in
    `tests/fixtures/stdlib_compiler_state/option-scalar-*.log`.

87. **Resolved for the reproduced layouts: unused generic bodies prevented
    executable library imports.** A library containing a generic payload read
    or generic aggregate return previously reached native emission before a
    caller supplied concrete types. That rejected the entire library even when
    only its working predicates or concrete functions were used. A later scalar
    after an ignored symbolic payload had the same problem because its offset
    depended on the ignored payload's width.

    The private function-template pass now omits native definitions for those
    uninstantiated bodies while retaining checked declarations. It runs after
    layout completion and use marking; function, parameter, and local scans
    compact the remaining executable rows. Fixed-layout generic records such
    as the empty `Vec<T>` remain executable. This changes private GPU scheduling
    and metadata selection, without changing IR record formats or native ABI.

    `repro_deferred_generic_payload_root/core/maybe.lani` contains executable
    generic predicates and a concrete helper alongside three deferred body
    shapes. Its actual imported and flat forms execute. Used local and imported
    templates report `LNC0017`; an imported missing definition includes the
    original library/unit/declaration identity rather than a cache-store error.
    Wrong fallback types still fail checking. The six-test suite is
    `stdlib_generic_payload_templates_execution`; its retained log is
    `generic-payload-template-tests.log`. The original later-offset failure is
    retained in `template-later-offset-before.log`.

    This is a prerequisite for body specialization. It does not retain a new
    checked-body artifact, collect instantiation jobs, substitute body types,
    or emit specialized definitions. Dependency 1 remains open.

88. **Resolved: qualified generic return aliases kept an unresolved type.**
    Dependency projection populated the qualified call's head, leaf, and owner
    aliases, but direct generic result substitution updated only the leaf.
    A concrete wrapper returning the qualified call then read the head's stale
    void type. Substitution now publishes each alias after checking that its
    library/unit/declaration identity matches the resolved callee.

    The template suite executes qualified generic scalar returns for both bool
    values, i32 extrema, and u32 zero, high bit, and maximum. This does not claim
    generic floating or aggregate forwarding. Used qualified payload templates
    now reach the explicit missing-native-definition diagnostic rather than
    an unrelated return-type mismatch.

89. **Resolved: imported generic predicates rejected multiple descriptor
    type arguments.** `repro_result_slice_predicate.lani` constructs a real
    `Result<[i32], str>` but the free `is_ok` call originally failed checking.
    Its symbolic parameter tree contained three rows; the concrete slice added
    an element row. The direct-child fallback only accommodated one generic
    argument. It now validates concrete scalar children and concrete scalar
    slices against each direct generic child. The shared generic claim pipeline
    still checks element identities and repeated slots, and concrete scalar
    children still require their declared types.

    The actual Result suite executes free and borrowed predicates, all eight
    membership helpers, scalar extrema, independently sized records, strings,
    borrowed slices, empty views, concrete returns, aliasing, and bounds traps.
    It rejects mismatched repeated slice types in T and E and a slice supplied
    where a concrete successful i32 is required. Its reading-total program
    prints `20` and `-2`. All seven focused tests pass; the retained log is
    `result-generic-import-tests.log`. The original rejection is in
    `result-slice-predicate-before.log`. Four adjacent Option-slice tests also
    pass in `result-slice-adjacent-option.log`.

    Twelve Result functions and methods execute for these tested layouts.
    `unwrap_or`, `or`, and `and` remain deferred generic payload functions with
    explicit `LNC0017` failures, so the full Result API is incomplete. The
    broad gate and performance comparison were not repeated.

90. **Original compilation context retained for resident generic bodies.**
    `CompiledSourcePackUnit` owns immutable shared snapshots of its ordered
    source strings and dependency interface pages. Exactly those snapshots feed
    checking. Path-backed jobs transfer their loaded allocations into this
    boundary; retaining the context adds no second copy of their source bytes
    or dependency interface records. Cache hits and active handles keep the
    same context. The cache budget includes source storage, page and interface
    storage, and each interface's nested vectors. Oversized units are evicted;
    insertion does not leave an orphan filesystem hint.

    The native source replay regression recompiles ordered UTF-8 source files
    containing a deferred generic body after the caller changes and drops its
    input strings. Both the original and rebuilt programs exit 7. The dependency
    replay regression changes a provider's `i32` result to `bool` under the same
    library/unit/declaration identity. A fresh caller compilation rejects that
    signature; recompiling its retained source and original dependency pages
    still links with the original provider and exits 7. An unrelated page and
    an empty page exercise the original dependency ordering. Cache regressions
    check that large source and dependency snapshots cause eviction while an
    active handle remains valid. Focused results are recorded in
    `tests/fixtures/stdlib_compiler_state/template-context-tests.log`: four
    passed. The complete eight-test cache suite also passes in
    `template-context-cache-tests.log`.
    After the ownership change, all six imported/local generic template tests
    pass in `template-context-import-tests.log`, including the distinct-record
    argument rejection. The actual Result/range/slice/stdio reading-total
    program still prints `20` and `-2`; its focused executable test passes in
    `template-context-stdlib-program.log`.

    This ownership change retains the inputs needed to instantiate a body;
    dependency 91 adds checked call environments separately. It does not
    substitute body types or emit specialized
    definitions. No stdlib API is promoted to executable by retention alone.
    Durable file-backed snapshot storage remains unavailable after cache
    eviction, and dependency 1 stays open. The shader passes, persisted semantic
    interface and object formats, compiler IR, extractor, proofs, and native ABI
    are unchanged by this ownership change. Broad execution and performance
    checks have not been repeated for this checkpoint.

91. **Checked generic call environments retained before workspace reuse.**
    Compiled source units now own immutable snapshots of the GPU checker's
    accepted type arguments. Local free functions retain a source-scoped
    function-start token. Imported free functions retain their canonical
    library/unit/declaration identity; imported methods retain their separate
    persisted member symbol. Each call keeps its own dense HIR identity and
    ordered parameter slots. Repeated T claims collapse only within one call.

    A GPU flag/scan/scatter operation collects callable rows independently of
    explicit argument counts, so receiver-only calls and zero-argument generic
    constructors are included. The retained-resource contract extends the
    required checker table lifetimes through native lowering and readback.
    The reader runs under the resident pipeline lock and copies accepted
    relations; it does not infer types from source or walk a host AST.
    Receiver rows and argument columns are read in batches. Direct generic
    receiver slots are mapped using the exact persisted method signature.
    A concrete `impl Option<bool>` therefore requires no inherited T merely
    because the Option declaration owns a type parameter.

    The two focused native tests compile, link, and run their original
    provider and consumer objects. They check bool, i32, u32, f32, char,
    string, and scalar-slice arguments; distinct calls to one declaration;
    local free calls; repeated T; imported receiver-only predicates; concrete
    bool extraction; and reversed `Result<[i32], str>` / `Result<str, [i32]>`
    parameter ordering. After an unrelated compilation reuses frontend
    storage, the original snapshots remain valid and the program still exits
    zero. The actual `std::vec::new` executes for bool and i32; its two
    zero-argument call records remain incomplete because return-context
    substitutions have not been captured. Private record identities likewise
    remain incomplete instead of receiving a guessed layout.

    Call and receiver vector storage is included in the compiled-unit cache
    budget. Ten cache checks cover eviction and active-handle preservation;
    three compiler-graph checks cover reflected resources and workspace
    lifetimes. Focused logs are `generic-method-environments-tests.log`,
    `generic-call-cache-tests.log`, and `generic-call-graph-tests.log` under
    `tests/fixtures/stdlib_compiler_state/`.
    All six generic-template integration tests and all seven actual Result
    integration tests pass after this change, including explicit unsupported
    call failures, mismatched arguments, descriptor aliasing, bounds traps,
    and the reading-total program's `20\n-2\n` output. Their retained log is
    `generic-call-stdlib-runtime-tests.log`. Four source/dependency replay and
    ownership checks also pass in `generic-call-context-tests.log`.

    This is still a prerequisite for specialization. No new stdlib API is
    promoted by this snapshot. General local method environments, return-only
    inference, constant arguments, nested structural types, and full nominal
    type closure remain unimplemented. Completeness of the captured type
    slots is not a claim of body or constant-argument readiness. Body
    substitution, concrete definition generation, per-call relocation
    retargeting, bounded recursive instantiation, and durable snapshot storage
    remain open in dependency 1. The persisted semantic interface and object
    formats, compiler IR, extractor, proofs, and native ABI are unchanged.
    The snapshot is private host metadata over GPU-checked facts. Fresh
    non-interface jobs do not read it back; cached interface-capable graphs
    can retain the larger workspace capacity. No fresh performance comparison
    is claimed for this change.


92. **Resident scalar body specialization and string return projection.** The
    GPU checker accepts a private bounded substitution packet keyed by the
    original public declaration and its ordered generic slots. Replaying the
    retained source and original dependency pages resolves those uses to
    checked scalar identities. Original cached units remain immutable; ordinary
    jobs upload an empty packet, preventing substitutions leaking between jobs.

    Native object projection supplies the dense call HIR for each undefined
    symbol in a separate resident column. The linker controller joins this
    with the checked call snapshot, schedules missing scalar free-function
    bodies, and allocates unused native unit identities for each instantiation.
    The existing twelve-byte symbol identity and object/IR formats are retained.
    Repeated type environments share a concrete body. Per-build limits are 32
    scalar type arguments per packet, 256 bodies, and 64 MiB of specialized
    text; scheduling limit failures report LNC0017. Replay is uncached and
    recursive specialization is not implemented.

    Direct symbolic T returns are deferred before machine emission. Without
    this step, generic memory helpers happened to work for several integer
    types but used an unresolved machine type for floats and strings. String
    call and return projection now preserves the direct pointer/length slots
    and existing RAX/RDX return convention. Descriptor producers cannot use the
    single-register immediate-return shortcut. This fixes the minimal
    `repro_option_generic_string_payload.lani`, whose length previously
    overwrote the saved frame pointer. Complex specialized emission uses the
    same minimum Slang optimization policy as the main emitter; the size gate
    stays enabled. No new GPU pass or native ABI is introduced.

    The actual-root Option matrix executes all four generic free operations
    for bool, i32, u32, f32, char, and str. It covers both presence branches,
    all i32 combinator state combinations, extrema, zero, false, NaN, negative
    zero, Unicode, NUL, empty presence, input preservation, and exact stdout.
    The four actual memory value helpers execute for those same six identities,
    both selector branches, special float values, and string forwarding through
    another function. All six payload-template integration tests pass. Logs:
    `option-mem-generic-runtime-tests.log` under the compiler-state fixtures.

    All nine actual Result tests pass. They execute all fifteen source-defined
    public functions/methods across their documented cases, scalar body
    functions with i32/bool in both orders, u32/bool, f32/char in both orders,
    and str/bool in both orders. Distinct string errors confirm or selects the
    fallback error and and preserves the first error. Wrong scalar and slice
    relations fail checking; unsupported generic slice extraction fails with
    LNC0017. The reading-total sample now calls generic unwrap_or and prints
    `20\n-2\n`. Three existing memory tests also pass. Log:
    `scalar-string-result-mem-tests.log`.

    Receiver bodies with their own generic parameters, local templates, nominal and slice body arguments,
    nested structural closures, constant arguments, return-only environments,
    recursive instantiation, and durable body storage remain dependencies.
    Supported execution is x86_64 Linux output from the GPU compiler. There is
    no GPU-device execution claim and no new performance measurement.

    Two native specialization checks pass after the string fix, including
    both variants, distinct concrete call environments in one program, and
    clearing the replay packet before the next ordinary job. Two retained
    call-environment tests also pass after scratch reuse. Eleven cache tests
    include the native call-HIR vector's budget charge and active-handle
    preservation. The native reflected-resource test and three checker graph
    tests pass. The specialized pass declares the shared string resources
    retained by minimum optimization. Logs: `scalar-string-body-unit-retry.log`,
    `scalar-body-retained-environment-tests.log`, `scalar-body-cache-tests.log`,
    `scalar-string-native-graph-tests.log`, and `scalar-body-checker-graph-tests.log`.
    The first combined compile/unit-test command reached its 110-second cap;
    its cached retry completed successfully.

    Four existing scalar Option tests and five borrowed-slice Option tests
    pass after the shared return/allocation changes. They include all scalar
    combinator state pairs, IEEE membership, input preservation, concrete
    slice returns, descriptor lengths, bounds traps, wrong-type diagnostics,
    and the scalar-choice real program. Log: `scalar-body-option-regressions.log`.
    The Option payload test additionally runs the exact minimal string-crash
    reproduction. Both it and the complete scalar/string matrix pass in
    `option-generic-string-regression-tests.log`.

93. **Imported scalar receiver bodies and receiver-bound arguments.** The
    resident scheduler now replays an imported generic impl body using its
    existing high-bit native method symbol and the GPU-checked receiver's
    ordered type arguments. Canonical GenericParameter payloads identify
    interface members; host retention resolves their declaration and ordinal
    rather than treating a member index as a generic slot. Factory receivers
    retain either checked type-argument representation.

    Imported method return projection and argument validation bind direct T
    results, direct fallbacks, and nested Option<T> arguments to the receiver.
    Wrong scalar fallbacks and wrong nested payload types report LNC0006.
    The shared Option impl replaces twenty duplicated scalar payload bodies.
    All 25 focused Option tests pass, including all string combinator state
    pairs, exact string output, empty presence, NaN, signed zero, factory
    receivers, and wrong argument diagnostics. Two native specialization
    tests execute distinct free and receiver bodies in one program and verify
    that the next ordinary job receives no stale substitution.

    Logs are `option-generic-receiver-complete-tests.log` and
    `option-receiver-retained-native-tests.log` under the compiler-state
    fixtures. Compiler IR formats, extractor, proofs, and native ABI remain
    unchanged. Methods with their own generic parameters, compound body
    arguments, local templates, recursive instantiation, and durable-only
    body storage remain unsupported. Symbolic impl bodies also cannot call
    another local receiver method during checking; the minimal source is
    `repro_generic_impl_local_method_call.lani`. Option's shared bodies inspect
    the tag directly. No fresh performance comparison is claimed.

    The adjacent template, generic memory, and Result suites pass all 17 tests
    in `option-receiver-adjacent-runtime-tests.log`. Three checker graph tests
    and two retained generic call tests also pass, in
    `option-receiver-checker-graph-tests.log` and
    `option-receiver-retained-environment-tests.log`.

    Result now supplies shared generic receiver unwrap_or, unwrap_err_or, or,
    and and bodies, plus free unwrap_err_or. These five new Lanius APIs use
    the existing scalar specialization path without further compiler edits.
    All twelve focused Result tests pass. The nine-environment receiver
    matrix includes distinct success/error types, str/str, unsigned high-bit
    payloads, all state pairs, input preservation, wrong arguments in either
    generic slot, NaN and signed zero in either payload, and exact string
    output. The reading-total program uses both borrowed fallback methods
    and retains stdout `20\n-2\n`. Log: `result-generic-receiver-tests.log`.

These are GPU compiler and target runtime dependencies, not stdlib
implementations in Rust or Python. Their executable claims require those
components to change and the reproductions above to pass.

94. **Generic slice call arguments and the remaining local-call boundary.**
    Imported scalar argument validation now reads the selected field type for
    a member expression. Previously extent.length was checked as Extent,
    rejecting a valid i32 length. The minimal raw-view reproduction and a
    Boolean-field negative case exercise the repair.

    Both generic array/slice claim paths now retain the element reference for
    [T]. The legacy path previously retained the entire raw slice as T, unlike
    the imported canonical path. This also preserves the distinction from a
    direct T parameter that receives an entire slice.

    The raw-storage suite executes valid reads, writes, fill, and reversal,
    and rejects incompatible element arguments in both copy directions.
    The eight focused slice tests and all seven foundation tests pass in
    generic-slice-foundation-complete-tests.log, including 139 executable
    source entries. Thirty adjacent template, memory, Option, and Result
    checks also pass in generic-slice-adjacent-runtime-tests.log, including
    the local-call boundary reproduction. Temporary tracing was removed.

    Calls to deferred local generic bodies within one combined source pack
    still fail explicitly with LNC0017 before an executable is emitted.
    repro_generic_slice_local_body.lani reproduces this with a three-element
    reversal. The six migrated owned scalar vectors reverse their concrete
    cells directly in Lanius and pass a focused length/capacity/value matrix.
    This avoids introducing broken vector APIs while local body scheduling
    remains a compiler dependency. Generic collections, compound body
    environments, and user-program GPU execution remain unfinished.


95. **Local generic bodies, concrete compound values, and instantiated record fields.**
    The GPU compares full checked type structure and computes native value
    widths. Resident scheduling replays local generic bodies against their
    original checked source references and imported bodies against retained
    concrete environments. Generic records with direct T fields use concrete
    field widths and offsets for construction, projection, mutation, and copy.
    Tested payloads include scalar values, strings, records, borrowed slices,
    fixed arrays, nested enums, and three-level concrete generic records.
    This supersedes dependency 94's missing local-body restriction.

    Packed local i32 arrays are converted at native return and inline-field
    boundaries. Match typing retains complete compound references and checks
    every arm's nominal identity, nested arguments, and array length. Final
    match reads and synthetic loop reads preserve the checked storage type.
    Indexed arguments project the checked element reference for scalar calls
    and generic inference. Ordinary nongeneric trait methods keep their native
    bodies when compiled alongside generic value calls.

    The combined compiler, template, and Result checkpoint passes 42 tests
    (24 + 9 + 9) in generic-record-array-checkpoint.log. These execute emitted
    x86_64 Linux programs and check complete payloads, independent copies,
    aliases, Unicode and empty strings, float signed zero, both variants and
    fallbacks, workspace reuse, and wrong-type diagnostics. Minimal sources
    include repro_generic_record_{scalar_layout,compound_layouts,array_field}.lani,
    repro_option_result_array_{payloads,representations}.lani, and
    repro_generic_array_index_argument.lani under the foundation fixtures.

    General structural substitution inside fields such as Holder<T> containing
    Cell<T>, arbitrary compound-element descriptor transport across imported
    body boundaries, empty values, function/reference values, native full-width
    integer types, const arguments, own-method generics, and durable-only body
    context remain unfinished. The compiler checkpoint lists exact supported
    shapes and target limits. No durable IR format, extractor, formal proof,
    or native calling convention changes were made for this checkpoint.

    The retained 1 MB canonical performance result predates these record,
    match, and argument fixes. No fresh performance claim is made for them.

96. **Scoped declaration fields and complete native descriptor stores.**
    Fields such as Holder<A, B> containing Cell<B> now resolve under the
    enclosing concrete environment, including reordered parameters and nested
    array/slice element types. Symbolic declaration rows remain unchanged.
    Literal fields compare full checked type structure, rejecting wrong nominal
    identities, reordered argument mismatches, and incompatible array lengths
    even when their native widths agree.

    Runtime checks execute three nested-field programs with distinct i32, bool,
    and str environments, deeper record nesting, Option extraction, independent
    value copies, fixed i32/string arrays, populated/empty borrowed views, and
    pointer/length replacement. Native field stores preserve both descriptor
    words, including assigning an empty string, replacing a two-element view
    with a three-element view, and retaining aliases. Complete arrays of Pair
    and string-bearing Text records also execute through imported identity and
    local generic forwarding with independent copies.

    The 43-test compiler/template/Result checkpoint is retained in
    generic-scoped-fields-checkpoint.log. The additional compound-array test
    passes in generic-compound-array-runtime.log. Twenty foundation and adjacent
    tests pass in generic-scoped-fields-foundation-adjacent.log, including 139
    executable source entries; eight native regressions and the deep checker
    pass in generic-scoped-fields-native-regressions.log. All 73 checks pass.

    At this historical checkpoint, general instantiation still needed a checked
    arena for implied applications without concrete source rows. repro_generic_missing_nested_application.lani
    fails explicitly at holder.child with LNC0042, retained in
    generic-missing-nested-application.log. Passing [Pair] as an entire T to an
    imported body fails with LNC0006 at identity(values) in
    repro_generic_compound_slice_value.lani and generic-compound-slice-value.log.
    Claims and retained body environments need the complete descriptor graph.
    These failures describe this historical checkpoint. Entry 97 supersedes
    the compound-slice failure with executable evidence; entry 98 supersedes
    the missing-application failure. The other remaining boundaries in the compiler checkpoint still apply.

    The existing 1 MB performance preset executes and validates all twenty
    generated programs with this checkpoint's shader digest 88fe9f6cd1685780.
    Compiler median is 37.580 ms and wall median is 40.501 ms, 3.67% above the
    preceding unpaired wall result. Results and the runner's post-measurement
    catalogue error are retained under stdlib-gpu-20261001. The shader size
    guard remains enabled. No IR record format, extractor, proof, or native
    calling convention changes were made.

97. **Complete structural argument replay and composed generic values.**
    Checked call environments now retain slices and fixed arrays recursively,
    including nominal element identities and GPU-computed native widths.
    Replayed bodies receive a private checked graph after the source-token
    capacity, preserving source declarations. Imported and local value helpers
    execute with `[Pair]`, `[Text]`, `[[i32; 2]]`, and `[[[i32; 2]; 2]]` as
    an entire `T`. String descriptor pairs, actual runtime lengths, element
    fields, nested indexes, storage aliases, and independent array copies are
    checked by emitted x86_64 Linux programs.

    `Option<[Pair]>` and `Result<[Pair], [Pair]>` preserve both variants and
    their borrowed descriptors through free and receiver fallback extraction,
    including empty present views. Composed generic call arguments retain
    their accepted return types. Seven bounds programs exit with status 101
    and no output; wrong nominal/element/result types and nested array lengths
    report `LNC0006` at the actual invalid call.

    Chained index operands now reference the preceding value. Parser call,
    member, and index spans use immutable grammar positions, and nested bracket
    classification uses immutable token/delimiter context. Parser fixtures
    check names, fields, populated/empty calls, call-returned fields, and types
    nested through 32 fixed-array layers. Three chained indexes directly on a
    generic call result execute in `repro_nested_array_type_syntax.lani`.

    All 85 fresh focused checks pass: 46 compiler/template/Result tests in
    `generic-structural-replay-checkpoint.log`, 20 foundation/memory/Option/slice
    tests in `generic-structural-replay-foundation-adjacent.log` (139 executable
    foundation source entries), and 19 native/parser/deep-checker regressions
    in `generic-structural-replay-native-parser-regressions.log`. The preceding
    three retention/layout/workspace unit checks remain recorded in
    `generic-structural-replay-retention-graph.log`.

    Generics over arbitrary types were unfinished at this checkpoint. The CLI
    rejected the implied `Cell<i32>` in `Holder<i32>` with `LNC0042` at `holder.child`;
    `repro_generic_missing_nested_application.lani` and
    `generic-missing-nested-application.log` retain that minimal dependency.
    Entry 98 adds a GPU type-instantiation arena and indexed lookup for local
    record fields, and executes that former reproduction. Other limits are listed in the [compiler checkpoint](compiler-generic-types.md).
    Specialization currently admits 32 arguments and 64 retained structural
    nodes per body, 256 bodies, and 64 MiB of native text. Unsupported layouts
    fail explicitly.

    The structural graph, composed-call, and parser changes have not been
    benchmarked. Entry 96's 1 MB measurement predates them. The 524,288-byte
    shader guard remains enforced, with a largest artifact of 523,396 bytes.
    IR record formats, the extractor, formal proofs, and the x86 calling
    convention are unchanged.

98. **Compiler-generated type applications and scoped generic field bodies.**
    The GPU creates local record field applications even when their concrete
    types never appear in source annotations. A structural index compares full
    scoped identities, including nominal declarations, ordered arguments,
    element types, and array lengths. Unbound parameters retain their own
    declaration identities; field substitution applies once. Each root expands
    the accepted type DAG once, avoiding exponential traversal of repeated
    argument/field edges. The existing deep imported-type regression passes.

    The former missing-inner-application reproduction now constructs a value
    and executes its reader. The larger generated-application program checks
    i32, bool, str, f32, caller-local records with string fields, fixed arrays,
    nested literal constructors, descriptor words, sentinels, field stores, and
    independent copies. `read_generic<T>(Holder<T>) -> T` executes those payload
    forms. A generic function returning i32 also specializes correctly when its
    field offset depends on T. Unbound declaration fields have no guessed
    one-word layout. Body replay rebuilds type lookup and member references;
    each sibling call retains its own accepted result type and legacy code.
    Canonical nested-literal fields are contiguous per owner, preserving the
    existing HIR record contract.

    Nested wrong scalar and record types report `LNC0006` at the offending
    expression. Unbounded generic expansion reports `LNC0047` with a source
    location and an explicit resource/traversal boundary. Private instantiation
    admits 32 arguments, 64 traversal levels, and 64 generated or expanded nodes
    per root; its arena has at least 64 rows, or one row per source-token
    capacity when larger. Body scheduling retains its existing limits.

    All 91 fresh focused checks pass: 48 compiler/template/Result tests in
    `generic-generated-applications-checkpoint.log`, 20 adjacent tests in
    `generic-generated-applications-foundation-adjacent.log` (including 139
    executable foundation entries), 20 native/parser/deep-checker tests in
    `generic-generated-applications-native-parser-regressions.log`, and three
    retention/layout/workspace tests in `generic-generated-applications-retention-graph.log`.
    Execution is x86_64 Linux ELF emitted by the GPU compiler. User-program GPU
    execution is not established. Remaining enum/imported applications, late
    inferred result types, constructor contexts, and other type shapes are
    listed in the [compiler checkpoint](compiler-generic-types.md).

    This checkpoint has not been benchmarked. Its 727 shader artifacts have
    digest `c9fc48fdf4fb59ce`; semantic scatter is 278,208 bytes and the largest
    artifact is 523,396 bytes. The 524,288-byte guard remains enforced. IR record
    formats, the extractor, formal proofs, and the x86 calling convention are
    unchanged.

99. **Nested record construction in ordinary generic function bodies.**
    `wrap<T>(value: T) -> Holder<T>` now constructs and returns the implied
    `Cell<T>` for i32, bool, str, a caller-local record with a string field,
    and a fixed string array. The minimal constructor reproduction and the
    mixed-type program execute as x86_64 Linux ELF. Their tests check exact
    Unicode/empty-string output, both descriptor words, independent record
    copies, and independent returned-array storage. Mismatched result nominal
    types, array lengths, and array elements report `LNC0006` at the call.

    Deferred generic literals wait for their body environment before native
    field layout is required. Body replay refreshes constructor contexts and
    field expectations. Contextual results compare the full accepted generic
    argument and retain each call's own result through sibling specializations.
    Constructor passes follow parser feature flags, avoiding reads of
    uninitialized field relations in modules without structs. A reused-workspace
    test alternates nested constructors, plain comparisons, generic values,
    and fixed-array returns twice.

    All 92 focused checks pass: 49 compiler/template/Result checks,
    20 foundation/memory/Option/slice checks, 20 native/parser/deep-checker
    checks, and three retained-type/workspace checks. Their logs use the
    `generic-nested-constructors-` prefix under
    `tests/fixtures/stdlib_compiler_state/`. The expanded workspace transition
    also passes in its own log. Generics over arbitrary types remain unfinished;
    the [compiler checkpoint](compiler-generic-types.md) lists outstanding
    enum/imported applications, late inferred types, and native layout limits.

    This checkpoint has not been benchmarked. Its 727 shader artifacts have
    digest `83d91b0f572b5c12`, and the 524,288-byte guard remains enforced.
    User-program GPU execution is not established. IR record formats, the
    extractor, formal proofs, and the x86 calling convention are unchanged.

100. **Nested generic enum payload types.**
     `Batch<T> { Items([T; 2]), Empty }` now executes with i32, bool, str,
     a caller-local record with a string field, and a fixed string array.
     The producer creates applications implied by local enum payloads, and
     constructors and match bindings substitute their complete checked types.
     Indexed match results retain the element type; native enum storage uses
     the accepted instantiated width instead of the symbolic declaration.

     The minimal reproduction and mixed-type program check both variants,
     integer extrema, false values, Unicode/empty-string descriptors, and
     independent returned record/array copies. Negative and upper-bound
     string payload indexes trap with status 101 and no output. Wrong array
     lengths, element types, and record identities report `LNC0006` at the
     argument while preserving the constructor's successful name resolution.

     All 81 fresh focused checks pass: 50 compiler/template/Result checks,
     20 foundation/memory/Option/slice checks (including 139 executable
     foundation source entries), eight native layout checks, and three
     retained-type/workspace checks. Their logs use the `generic-nested-enums-`
     prefix under `tests/fixtures/stdlib_compiler_state/`. The expanded enum
     bounds test also passes in `generic-nested-enum-payload-runtime.log`.
     Generics over arbitrary types remain unfinished; imported applications,
     inferred results, constructor contexts, and other type shapes remain in
     the [compiler checkpoint](compiler-generic-types.md).

     This checkpoint has not been benchmarked. Its 727 shader artifacts have
     digest `5097fb2f5c573fb8`; semantic scatter is 281,784 bytes, and the
     largest artifact is 523,396 bytes. The 524,288-byte guard remains enforced.
     Execution is x86_64 Linux ELF emitted by the GPU compiler. User-program
     GPU execution is not established. IR record formats, the extractor,
     formal proofs, and the x86 calling convention are unchanged.

101. **Generic slices whose elements are borrowed slices.**
     `[[i32]]` and `[[str]]` execute through whole-value generic forwarding,
     imported first/get-or/swap/set operations, and Option/Result extraction.
     The minimal reproductions isolate forwarding, element returns, and swaps.
     A larger program checks both descriptor words, populated and empty views,
     unequal inner lengths, composed calls, descriptor replacement, Unicode,
     empty strings, and aliasing. Invalid logical stores preserve storage;
     five invalid outer/inner indexes trap with status 101 and no output.
     Incompatible nominal element types report `LNC0006` at the call.

     Imported `[T]` parameters bind full element types with variable-size
     canonical subtrees. Indexed slice results retain their descriptor type
     through local copies and stores. Indirect descriptor call arguments keep
     their base address and word selector through operand resolution, using
     the existing native pointer/length protocol.

     All 82 fresh focused checks pass: 51 compiler/template/Result checks,
     20 foundation/memory/Option/slice checks (including 139 executable
     foundation entries), eight native layout checks, and three
     retained-type/workspace checks. Their logs use the `generic-nested-slices-`
     prefix under `tests/fixtures/stdlib_compiler_state/`; the expanded bounds
     and nominal mismatch test also passes in `generic-slice-of-slices-runtime.log`.
     Generics over arbitrary types remain unfinished; the
     [compiler checkpoint](compiler-generic-types.md) lists the remaining work.

     This checkpoint has not been benchmarked. Its 727 shader artifacts have
     digest `0f30af5357d00521`; semantic scatter is 282,660 bytes, and the largest
     artifact is 523,396 bytes. The 524,288-byte guard remains enforced.
     Execution is x86_64 Linux ELF emitted by the GPU compiler. User-program
     GPU execution is not established. IR record formats, the extractor,
     formal proofs, and the x86 calling convention are unchanged.

102. **Generated receiver environments and contextual imported record literals.**
     Local and imported `Five<i32, bool, char, u32, T>` fields preserve all five
     arguments when the concrete inner type is generated by the compiler.
     Private type arenas use physical workspace source capacity rather than
     the current module's token count. Checker, receiver, layout, and host
     retention readers consume complete columnar arguments or all 32 generated
     fallback slots. Projected member results participate in generic claims
     before final semantic artifact publication.

     Imported record constructors retain stable declaration identity. Their
     immutable dependency pages project scalar and direct generic-parameter
     field expectations, declaration ordinals, and native widths. Fields can
     be written in any order. Complete T values can be strings, records, arrays,
     or borrowed slices; contextual array literals validate length and element
     types. Wrong nominal identity and field types report `LNC0006`; missing,
     duplicate, and unknown fields report `LNC0042`.

     The receiver regression executes 12 programs: two minimal reproductions
     and ten mixed payload cases. Every prefix argument and sentinel is checked.
     Record and array mutation preserves independent copies; slice mutation
     preserves aliases. Strings, string arrays, and string-containing records
     check exact Unicode and empty-string output. Reused workspaces alternate
     generated five-argument applications and ordinary jobs twice, including a
     named module followed by anonymous modules. Implicit root module metadata
     is reinitialized instead of retaining stale segment ranges.

     All 99 focused checks pass: 54 compiler/template/Result checks,
     20 foundation/memory/Option/slice checks (including 139 executable
     foundation entries), eight native layout checks, three retained-type/
     workspace checks, and 14 parser/deep-checker checks. Their logs use the
     `generic-generated-receivers-` prefix under
     `tests/fixtures/stdlib_compiler_state/`. Three valid minimal programs
     retain imported-record dependencies: compound declaration fields report
     `LNC0047`, explicit arguments on qualified record literals report
     `LNC0016`, and direct field reads from the importing module report
     `LNC0042`. These are diagnostic evidence, not executable API claims.
     Generics over arbitrary types remain unfinished; the
     [compiler checkpoint](compiler-generic-types.md) lists the remaining work.

     This checkpoint has not been benchmarked. Generic claim emission now
     uses the repository's per-shader minimum Slang optimization policy to
     remain below the artifact guard. Its artifact is 111,384 bytes. The 728
     shader artifacts have digest `cd9dc895599e83f6`; semantic scatter is
     281,836 bytes, and the largest artifact is 523,396 bytes. The 524,288-byte
     guard remains enforced. Execution is x86_64 Linux ELF emitted by the GPU
     compiler. User-program GPU execution is not established. IR record
     formats, the extractor, formal proofs, and the x86 calling convention
     are unchanged.

103. **Imported generic record field reads and writes.**
     Direct fields and generic-body reads now execute for i32, bool, u32, f32,
     char, str, caller-local records, fixed string arrays, and borrowed integer
     slices. Member chains cross local, imported, and caller-local records.
     String, record, array, and slice fields preceding a selected field retain
     their complete native widths. The minimal multiword-prefix reproduction
     reads the fifth field at word offset 11, rather than declaration ordinal 4.

     The checker shares owning-page field lookup across member reads, literal
     contexts, and layouts. A separate GPU pass retains accepted member word
     ranges after width production; native loads and stores consume those
     ranges. Nested literal context crosses imported declarations. Array field
     assignments inherit complete element/length context, scalar field stores
     validate the selected field, and monomorphic record stores compare stable
     declaration identities instead of accepting equal layouts.

     Three emitted programs check direct reads, generic-body reads, multiword
     prefixes, field replacements, independent record/array copies, borrowed
     aliases, and exact Unicode/empty-string output. Nine invalid programs
     report `LNC0042` for unknown fields or `LNC0006` for incompatible field and
     result types at the offending source line. Six runtime array/slice bounds
     programs exit with status 101 and no output. Statically invalid array
     indexes can be rejected before executable emission.

     All 98 fresh focused checks pass: 57 compiler/template/Result checks,
     20 foundation/memory/Option/slice checks (including 139 executable
     foundation entries), 12 native layout checks, six checker checks, and
     three retained-type/workspace checks. Their logs use the
     `generic-imported-fields-` prefix under
     `tests/fixtures/stdlib_compiler_state/`. The direct imported field-read
     dependency from entry 102 is resolved. Compound imported declaration
     fields and explicit type arguments on qualified literals remain minimal
     diagnostic reproductions; the [compiler checkpoint](compiler-generic-types.md)
     lists the broader remaining generic type and expression contexts.

     This checkpoint has not been benchmarked. Its 729 shader artifacts have
     digest `926af4b40ee020ca`; the imported member range pass is 22,740 bytes,
     native width production is 368,512 bytes, semantic scatter is 283,352
     bytes, and the largest artifact is 523,396 bytes. The 524,288-byte guard
     remains enforced. Execution is x86_64 Linux ELF emitted by the GPU
     compiler. User-program GPU execution is not established. IR record
     formats, the extractor, formal proofs, and the x86 calling convention
     are unchanged.

104. **Complete nominal generic graphs and compound return checking.**
     Imported compound declaration fields now execute in the larger mixed
     program, including construction, generic reads, replacement, independent
     copies, and borrowed aliases. Local complete return types use the shared
     substitution producer; reordered generic array returns and tested
     unannotated local results execute.

     Retained nominal applications carry stable declaration identity and all
     ordered type arguments through imported calls and body replay. The private
     graph publishes nested record, enum, array, and slice edges. Checker match
     joins and call argument projection read those same complete references.
     Imported contextual returns use shared scoped matching and reject repeated
     parameter conflicts, including distinct equal-width descriptor types.

     Executable 6-, 16-, and 32-parameter compositions preserve mixed fields,
     sentinels, copies, and aliases. The 32-parameter application also passes
     intact through imported memory identity. The current gates pass 65 distinct
     compiler/template/Result checks cumulatively, 20 adjacent foundation,
     memory, Option, and slice checks (including 139 executable foundation
     entries), and three packet/retention unit checks. Their logs use the
     `generic-nominal-graph-` prefix. The combined gate ran 46 compiler tests;
     the additional negative test passed separately with the new runtime test.

     The existing frozen 1 MB perf corpus passes all 20 emitted-program checks
     at 73.400 ms compiler / 78.147 ms wall median. Two opposite-order control
     pairs also found high absolute times in the matched older compiler; the
     current compiler was faster in both. The real 32-parameter program measures
     246.051 ms median for an entry recompile with warm imports and validates its
     final ELF. These measurements do not establish a general 10x comparison or
     large generic-graph throughput. Details and remaining compiler dependencies
     are in the [compiler checkpoint](compiler-generic-types.md) and
     [performance report](stdlib-gpu-performance.md).

     Generics over arbitrary executable types remain unfinished. Imported
     unannotated returns, result-only binding publication through inference and
     replay, additional ordinary type forms, own method parameters, and const
     parameters still require work. The 732 shader artifacts have digest
     `969718dcfd9ce8a8`; the largest is 523,396 bytes against the enforced
     524,288-byte guard. Runtime evidence is x86_64 Linux ELF emitted by the GPU
     compiler; user-program GPU execution is not established. IR record formats,
     the extractor, formal proofs, and the x86 calling convention are unchanged.

105. **Imported inferred returns and dependent call inference.**
     Imported unannotated array, slice, and nominal results now retain complete
     checked types while their declaration page is active. Shared constraint
     validation publishes result-only bindings without overwriting accepted
     argument bindings. A retention check preserves all 32 ordered parameters
     across workspace reuse.

     A bounded call inference closure publishes complete results before checking
     dependent calls. It compares structural types for progress, retains GPU
     scratch across repeated passes, and rejects unresolved types in a final
     nondeferred pass. A 32-call executable chain checks record/string arrays,
     nested wrappers, independent copies, descriptor replacement, runtime view
     lengths, and borrowed aliases. Wrong elements and array lengths are rejected.

     The current checkpoint passes 92 focused checks: 70 compiler/template/Result,
     20 foundation/memory/Option/slice (including 139 executable foundation source
     entries), and two contextual-retention/GPU-lifetime units. Logs use the
     `generic-inference-closure-` prefix under
     `tests/fixtures/stdlib_compiler_state/`.

     Fresh matched 1 MB controls show average increases of 8.6% and 2.8% in
     opposite orders; the larger difference did not repeat, and unchanged
     performance is not established. The real 32-parameter entry recompile
     measures 265.165 ms median with warm imports and successful ELF validation.
     The [performance report](stdlib-gpu-performance.md) records exact scope.

     Generics over arbitrary executable types remain unfinished. Late inferred
     calls inside concrete body replay, general local result-only constraints,
     additional ordinary type forms, own method parameters, and const parameters
     still need work or evidence. The [compiler checkpoint](compiler-generic-types.md)
     lists the remaining boundaries. Current shader digest is `5b0b8f17178ea693`,
     with 732 artifacts and a 523,396-byte maximum against the enforced
     524,288-byte guard. Runtime evidence is x86_64 Linux ELF emitted by the GPU
     compiler; user-program GPU execution is not established. IR record formats,
     the extractor, formal proofs, and the x86 calling convention are unchanged.

106. **Complete local result constraints and generic-body inference evidence.**
     Local result-only factories now infer complete type arguments recursively
     from their annotated result. This replaces a four-slot scalar cache with
     scoped graph matching over nominal arguments and array/slice elements.
     Bindings publish only after the entire constraint succeeds; accepted
     argument bindings take precedence and repeated parameters must agree.

     Empty factories execute with five and 32 mixed parameters and nested result
     patterns. A retention unit compares every ordered local binding with its
     imported counterpart, then verifies workspace reuse. Local and imported
     inferred call chains inside generic bodies execute for scalars, strings,
     records, fixed string arrays, and borrowed slices, preserving independent
     copies, descriptors, lengths, and aliases. Wrong repeated array lengths,
     nominal identities, and argument/result constraints are rejected.

     The wider gate exposed stale path-segment scan data in anonymous public
     modules. Interface sizing, records, and bytes now publish zero segments
     for the empty root path. All four failing enum cases and named-to-anonymous
     workspace reuse pass.

     The current combined executable gate passes 104 tests; two contextual
     retention and GPU graph lifetime checks also pass, for 106 fresh focused
     checks. Logs use `generic-local-context-` under
     `tests/fixtures/stdlib_compiler_state/`. The preceding foundation gate's
     139 executable source entries were not rerun for this checkpoint.

     Shader digest is `36552debb8404547`, with 732 artifacts and a 523,396-byte
     maximum against the enforced 524,288-byte guard. These latest repairs have
     not been benchmarked; entry 105 records the preceding measured snapshot.
     General generics remain unfinished, including additional type forms,
     structural parameter contexts, own method parameters, and const parameters.
     The [compiler checkpoint](compiler-generic-types.md) lists the current
     contract and remaining work. Runtime evidence is x86_64 Linux ELF emitted
     by the GPU compiler; user-program GPU execution is not established. IR
     record formats, the extractor, formal proofs, and the x86 calling
     convention are unchanged.

107. **Structural parameter inference and dependent value checks.**
     Local and imported parameter patterns now infer complete types recursively,
     including `Cell<Cell<T>>`, `[Cell<T>; 2]`, and a nested application with
     32 ordered parameters. A single argument owns its entire binding span;
     repeated parameters and separate arguments must agree before acceptance.
     Required bindings are validated after call inference closes.

     Completed call results and unannotated lets retain compound instances and
     monomorphic nominal leaves. Concrete leaf returns publish through the same
     result relation. Nested array elements are validated under the accepted
     call environment. Inferred enum payloads publish before final field checks,
     and unannotated nominal assignment checks retain declaration identity.

     The new programs execute scalar, string, record, fixed-array, slice, and
     enum compositions, including independent copies, aliases, Unicode, empty
     strings, and enum payload fields. Repeated-type, array-length, nominal,
     cross-argument, and missing-binding conflicts reject with `LNC0006`.

     The fresh gate passes 108 compiler/stdlib tests and two retained-environment
     and GPU-lifetime checks, for 110 focused checks. Logs use
     `generic-nested-parameter-` under `tests/fixtures/stdlib_compiler_state/`.
     The preceding foundation gate's 139 executable source entries were not
     rerun. Shader digest is `7061ad913cc9d0ac`, with 732 artifacts and a
     523,396-byte maximum against the enforced 524,288-byte guard. This latest
     checkpoint has not been benchmarked.

     General generics remain unfinished. Further expression closure, ordinary
     type forms, method-owned parameters, const parameters, and durable generic
     body context still need work. The [compiler checkpoint](compiler-generic-types.md)
     lists the limits and dependencies. Runtime evidence is x86_64 Linux ELF
     emitted by the GPU compiler; user-program GPU execution is not established.
     IR record formats, the extractor, formal proofs, and the x86 calling
     convention are unchanged.

108. **Complete dependent expression inference.**
     Calls, fields, indexes, and match results now participate in the same
     inference closure. Stable full expression references feed unannotated
     bindings and later generic arguments. Match payloads publish before joins;
     a match compares all complete arm types before accepting its result.
     Arithmetic inherits its checked operand type, including indexed payloads.
     Unresolved callee templates stay pending instead of becoming caller types.

     Five new executable checks cover inferred record fields, temporary return
     indexes, record-valued matches, a twelve-stage chain with independent
     copies, and slice aliases through the same contexts. All 64 compiler tests,
     49 adjacent stdlib tests, and two retained-environment/lifetime checks pass:
     115 focused checks. Logs use `generic-expression-` under
     `tests/fixtures/stdlib_compiler_state/`.

     Shader digest is `96ddfc90abad06ef`, with 733 artifacts and a 523,396-byte
     maximum against the enforced 524,288-byte guard. A fresh real 32-parameter
     entry benchmark measures 248.106 ms median over ten recompiles with warm
     imports; the final ELF passes exact output and exit checks. This unpaired
     run does not establish a speedup or the 10x target. The large corpus was
     not rerun. See [performance](stdlib-gpu-performance.md).

     General generics remain unfinished. Remaining type forms, constructor and
     late replay contexts, method-owned parameters, const parameters, and
     durable generic body context still need work. Direct match expressions in
     call arguments remain a parser reproduction; named match results execute.
     The [compiler checkpoint](compiler-generic-types.md) lists current support
     and explicit limits. Runtime evidence is x86_64 Linux ELF emitted by the
     GPU compiler; user-program GPU execution is not established. This change
     uses private type-checker relations and scheduling; it does not alter IR
     record formats, the extractor, formal proofs, or the x86 calling convention.
