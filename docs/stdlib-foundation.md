# Standard library execution audit and portable foundation

This audit distinguishes runtime evidence from source that merely type-checks.
`laniusc check` exercises the GPU-resident frontend but does not establish that
the target backend can emit or execute a helper. The executable claim below is
limited to native x86_64 output from this worktree.

## Public API inventory

| Public surface | Classification | Evidence and limit |
| --- | --- | --- |
| `core::number_i32` constants and all 23 public functions | Executable on x86_64 | Focused runtime fixture checks ordinary values, integer extremes, multiplication and power overflow, signed GCD/LCM, truncating and Euclidean division, failure fallbacks, and power-of-two overflow. |
| `core::number_u32` constants and all 25 public functions | Executable on x86_64 | Runtime fixture checks unsigned extremes, wrapping and saturating arithmetic, GCD/LCM, power overflow, zero-divisor fallbacks, and alignment fallbacks. |
| `core::byte` constants and all 44 public functions | Executable on x86_64 | Focused runtime fixture checks arithmetic overflow, every wrapping-multiplication byte pair, division, GCD/LCM, power overflow, zero divisor, power-of-two overflow, all nibble round trips, ASCII classes, case conversion, and hex conversion fallbacks. |
| `core::bits` all 10 public `u32` functions | Executable on x86_64 | Runtime fixture checks zero, highest bit, all bits, counts, rotates across 0 and 32, bit reversal, byte swap, and out-of-range bit fallback. |
| `core::bool` all 10 public functions | Executable on x86_64 | Focused runtime fixture checks both truth values, conversion, and both selection branches. |
| `core::char` all 16 public functions | Executable on x86_64 | Focused runtime fixture checks ASCII classes, all 26 case pairs, case-insensitive comparison, control and printable boundaries, and unchanged non-ASCII values. |
| `core::utf8` all 6 public scalar-codec functions | Executable on x86_64 | Native fixture checks ASCII and multibyte encoding/decoding, length boundaries, malformed sequences, surrogate exclusion, and Unicode maximum. Byte parameters and results use `u8`; it does not access string storage. |
| `core::f32` all 12 public functions | Executable on x86_64 for tested finite inputs | Runtime fixture checks sign, comparison, bounds, and square root for zero, negative, small, ordinary, and large inputs. The imported public constant `ONE` is broken; see dependency 5. |
| `core::array_i32_4` 11 scalar-returning functions | Executable on x86_64 | Runtime fixture checks access, search, fallback indices, extrema, and saturating sum. Its three array-returning functions fail natively; see dependency 7. |
| Legacy `stdlib/i32.lani` power-of-two helpers | Executable on x86_64 | A focused source-level native test checks the highest signed power and the zero overflow sentinel. The legacy file as a whole is not included in this claim. |
| `core::range` free functions for all five range forms and methods for `Range<i32>`, `RangeInclusive<i32>`, `RangeFrom<i32>`, and `RangeTo<i32>` | Executable on x86_64 | Runtime fixtures check endpoints, empty/reversed ranges, touching and overlapping intervals, unbounded membership, and full-range membership. There is no `RangeFull` method claim. |
| `core::slice` all 28 public i32 view functions | Executable on x86_64 for valid backed views | Runtime fixtures check backed, empty, unsorted, duplicate, and sorted views; sequence comparisons, rotations, compaction, search and insertion boundaries, extrema, sum, overlapping copies, sorting, and fallback behavior. A separate fixture confirms native index trapping on an overclaimed length. |
| `core::mem::{i32_array_data_ptr,i32_slice_from_raw_parts}` | Misleading source stubs; executable x86_64 compiler intrinsics | The source bodies return `0` and `[]`; x86 lowers the recognized calls as intrinsics, demonstrated by the slice fixture. Do not use these bodies as evidence for another target. `string_data_ptr` and `i32_slice_data_ptr` have the same placeholder issue and are outside this subset. |
| `core::mem::{identity,first,second,select}` | Executable on x86_64 for i32 instantiations | Runtime fixture exercises each generic helper and both selector branches, plus `identity<bool>`. Aggregate instantiations are outside this claim. |
| `core::hash::hash_i32` | Executable on x86_64 | Runtime fixture checks zero, positive, and negative bit-pattern values. The generic `Hash<T>` trait remains outside the claim. |
| Generic `core::option`, `core::result`, and `core::{i32,i64,u32,u8}` as complete imported modules | Contract-only for native execution | Their Lanius bodies type-check, but generic enum use or import prevents reliable x86 output. The numeric modules import generic `Option` for checked results. A minimal failing program is included below. |
| `core::{cmp,hash,ordering,array_i32}` and legacy root `stdlib/{i32,bool,array_i32_4}.lani` | Contract-only as complete modules in this audit | Individual x86 tests exist for some helpers; no module-wide runtime claim is made here. Generic fixed-array APIs and traits also depend on backend support. |
| `core::{target,runtime,panic}` | Contract-only service metadata | Capability constants are declarations, not live host probes. `core::target` is native-oriented (`IS_NATIVE=true`, `IS_WASM=false`); panic hooks remain unbound. |
| `alloc::allocator` | Executable host ABI, separate from portable core | Its listed allocation externs have compiler bindings and x86 tests, but storage ownership and failure behavior are host/runtime concerns. |
| `std::{io,fs,random,env,process,time}` | Mixed: bound calls executable; remaining declarations contract-only | The compiler binds a specific subset of extern calls on x86; existing `tests/codegen_x86.rs` exercises those calls. An availability flag is not evidence that every declaration in a module works. Consult `laniusc diagnostics runtime-apis` for per-call binding status. |
| `std::io::{write_line,println,eprintln}` | Executable x86_64 host wrappers | `tests/stdlib_host_execution.rs` checks stdout, stderr, empty line, exact byte counts, and invalid handle failure. These are separate from the portable core. |
| `std::file::{write_text_once,read_once_into_buffer,copy_distinct_with_buffer}` | Executable x86_64 Linux host wrappers | `tests/stdlib_file_execution.rs` checks text writes, caller-buffer reads and their bytes, a multi-chunk binary copy, empty files, invalid buffer sizes, missing paths, and write failures using `/dev/full`. `copy_distinct_with_buffer` requires distinct underlying files and a valid writable buffer. |
| `std::path` all 17 constants and 32 lexical helpers | Executable on x86_64 | `tests/stdlib_path_execution.rs` runs ordinary and boundary cases for byte classes, separator kind, component headers, and path headers. Component classifiers supplied only two bytes check the header when `length > 2`; they do not validate later bytes. No-argument value and capability helpers remain blocked by native return lowering; see dependency 10. Allocation and host normalization are unavailable. |
| `std::{net,gpu,thread,host}` and `test::harness` | Contract-only | Their service metadata is available, but user-visible operations have no runtime binding. The compiler's use of a GPU to compile code does not bind `std::gpu`. |
| `test::assert` | Contract-only | Passing assertions hit unsupported target LIR opcode 38 during x86 emission. Reproduction programs are included. |
| `std::vec` | Contract-only after stub removal | The former `Vec<T>::push` returned without storing its argument and was removed. `Vec<T>::new`, `len`, and `is_empty` remain as an empty-value type-checking contract; no storage or mutation is provided. |

The inventory classifies a module as contract-only when it lacks sufficient
runtime evidence as a complete import, even if several bodies contain real
Lanius logic. No declaration is promoted solely because it type-checks.

## Executable subset and behavior

- `core::number_i32` saturates instead of overflowing. `clamp_or` returns its
  caller-supplied fallback when `low > high`; valid inclusive bounds clamp.
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
  source algorithm, but its imported module still lacks a native claim.
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
  returns the caller's fallback for an index of 32 or more.
- `core::bool` converts any nonzero i32 to true. Its selector functions return
  the chosen branch value. `core::char` tests ASCII classes; its case-insensitive
  equality and case conversion fold ASCII letters only. `is_ascii_control`
  includes `0..=31` and 127; non-ASCII input is unchanged by conversion.
- `core::utf8` accepts Unicode scalar values in `0..=0x10FFFF` excluding the
  surrogate range. Valid encoded bytes and decoder arguments use `u8`.
  Encoding returns a caller fallback for an invalid scalar or byte index.
  Decoding accepts exactly one to four bytes, ignores unused arguments, and
  returns the caller fallback for malformed, overlong, surrogate, truncated,
  or out-of-range sequences. It does not yet iterate a `str` or `[u8]` view;
  those storage operations have separate compiler dependencies below.
- `core::f32::sqrt` returns zero for nonpositive inputs and scales finite
  positive inputs before Newton iteration, including values far above or below
  one. The other `f32` functions follow their source definitions; no NaN
  contract is claimed by this gate. Imported `core::f32::ONE` is not usable on
  x86_64 until the constant lowering issue below is fixed.
- `core::array_i32_4::sum` folds with saturating addition; overflowing sums
  clamp to the corresponding i32 endpoint at each element. `get_or` and
  `index_of_or` return the caller's fallback for out-of-range or absent values.
- Half-open ranges exclude `end`; inclusive ranges include it. A reversed or
  empty range contains no values and overlaps no range. `RangeFrom<i32>` includes
  its start, `RangeTo<i32>` excludes its end, and `RangeFull` contains all i32
  values. `RangeTo<i32>` ending at `MIN` contains no i32 value.
- Slice callers supply `len` because source code cannot read slice metadata
  yet. `len <= 0` is empty for the safe fallback and accumulation helpers.
  `first_i32` traps on an empty view. `get_or_i32` returns the fallback for an
  index outside the supplied length; if the supplied length exceeds the actual
  view and indexing reaches beyond it, native execution traps with exit 101.
  `sum_i32` folds from left to right with saturating i32 addition, so each
  overflow clamps to `MIN` or `MAX` before the next element. Search helpers
  return the first or last matching index as named, or the caller's fallback.
  Empty extrema return the fallback. `is_sorted_i32` accepts equal neighbors;
  `lower_bound_i32` and `upper_bound_i32` require that order and return the
  insertion index before and after equal values respectively, including `len`
  when the insertion point is past the last element. A nonpositive length
  returns zero. `binary_search_first_or_i32` uses lower bound and returns the
  first match or its caller's fallback.
  `set_i32` and `swap_i32` reject invalid indices without mutation.
  `fill_i32` returns the number of elements written, and `reverse_in_place_i32`
  returns the number of swaps. `copy_within_i32` handles overlap in either
  direction and rejects invalid source or destination bounds before writing.
  `starts_with_i32`, `ends_with_i32`, and `equals_i32` compare elements in
  backed views; they treat negative lengths as empty. `rotate_left_i32` and
  `rotate_right_i32` mutate in place and return false without writing unless
  `len >= 0` and `0 <= amount <= len`. Rotating an empty view by zero succeeds.
  `dedup_adjacent_i32` retains one element from each adjacent run;
  `retain_not_equal_i32` removes every matching element while preserving the
  rest in order. Both return the new logical length, or zero without writing
  for a nonpositive length. `remove_at_i32` shifts successors left and returns
  false without writing for an invalid index. After any of these operations,
  elements outside the new logical length are unspecified.
  `sort_i32` uses an in-place heapsort in ascending order and returns the
  number of elements sorted, or zero for a nonpositive length. The backing
  array sees these mutations.
- `core::mem` raw-view construction borrows the backing array. The array must
  remain alive for every use of the view. The selected tests use stack-backed
  arrays and no allocator.
- `std::io::write_line` writes text followed by a newline and returns the
  combined byte count. A negative result from either host write is returned
  immediately. A partial text write is reported by its count, and the newline
  is attempted. The combined count saturates at `i32::MAX`. `println` and
  `eprintln` select stdout and stderr respectively.
  The focused host fixture also confirms that `write_i32` writes its decimal
  text and returns status `0`, while `write_byte` and `write_newline` return
  byte counts for the tested writes.
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
- `std::file::copy_distinct_with_buffer` copies until EOF using caller storage
  and retries short writes. It returns false for invalid buffer arguments or
  any host failure. The destination can contain a copied prefix on failure.
  Source and destination must refer to different files, even through aliases;
  the current file ABI cannot check that precondition before truncation.

The small runnable example is `sample_programs/portable_window_checksum.lani`.
It validates an ASCII marker, sorts readings in place, selects a half-open
window from sorted-value boundaries, reads a slice, and accumulates with
saturating arithmetic. It prints `96`.

## Target support and focused verification

| Target / path | Status |
| --- | --- |
| x86_64 Linux ELF | Executable subset above, checked by `tests/stdlib_foundation_execution.rs`. |
| GPU-resident compiler frontend and x86 codegen | Used to compile each runtime fixture. This is compiler execution on a GPU, not a user-program GPU target. |
| User GPU target / `std::gpu` | No executable user GPU API is exposed. |
| Wasm | Not claimed or required for this foundation. |

Run the focused gate with `cargo test --test stdlib_foundation_execution`.
The test compiles seventeen small Lanius programs through `--stdlib-root`, executes
the native ELFs, checks their exit status, checks the example's stdout, and
checks the slice bounds trap. Each source is also suitable for direct CLI
compilation with `laniusc --stdlib-root stdlib --emit x86_64 -o OUTPUT SOURCE`.
Run `cargo test --test stdlib_host_execution` for the separate native I/O
wrappers.
Run `cargo test --test stdlib_file_execution` for the file wrappers.
Run `cargo test --test stdlib_path_execution` for the lexical path predicates.

## Compiler/runtime dependencies and minimal reproductions

1. **Generic Option/Result native lowering.** `laniusc check --stdlib-root
   stdlib tests/fixtures/stdlib_foundation/repro_generic_option.lani` succeeds,
   while native emission stops with `LNC0057` before a useful backend
   diagnostic. A same-file generic enum also reports unsupported target opcode
   8 (`LNC0017`). This blocks the generic Option/Result modules and checked
   numeric helpers that return them.
2. **Imported aggregate result ABI.** Compile
   `tests/fixtures/stdlib_foundation/repro_aggregate_app.lani` with
   `--stdlib-root tests/fixtures/stdlib_foundation/repro_aggregate_root` and
   `--emit x86_64`. The compiler emits an ELF, but running it terminates by
   signal 4 (`SIGILL`) on this host. This blocks a concrete struct-based
   Option/Result workaround and needs a compiler-side fix before such APIs can
   be called executable. The stdlib foundation deliberately contains no
   aggregate-returning workaround.
3. **Portable slice construction and metadata.** The source bodies in
   `core::mem` are placeholders; x86 intrinsic lowering supplies the behavior.
   A real cross-target slice constructor and a way to read slice length are
   needed before the same API can be claimed for another target or made
   independent of caller-supplied lengths.
4. **Allocation-backed vectors.** `std::vec` requires storage, mutation,
   allocation failure, and ownership semantics. Its silent `push` stub is
   removed until those runtime pieces exist; the empty `Vec<T>` contract is
   still type-checkable but not an executable collection.
5. **Imported f32 constant lowering.** With the minimal library in
   `tests/fixtures/stdlib_foundation/repro_f32_const_root`, native emission of
   `repro_f32_const.lani` succeeds, but the ELF exits 3 because imported
   `pub const ONE: f32 = 1.0` compares unequal to `1.0`; the same literal
   compares equal to itself. This prevents a complete `core::f32` module claim.
6. **Native assertion lowering.** `repro_assert_pass.lani` imports
   `test::assert` and calls each of its eight public functions with passing
   inputs. Native emission fails with `LNC0017`, unsupported target LIR opcode
   38. `repro_assert_fail.lani` is the corresponding failure-path input; it
   cannot run until assertions have a native lowering. Type checking alone
   cannot establish that failed assertions terminate execution. A source-level
   fallback using the bound process exit call hits dependency 19.
7. **Imported fixed-array results.** `repro_array_i32_4_return.lani` imports
   `core::array_i32_4::copy` and accesses its returned array. Native emission
   succeeds, but the ELF segfaults (exit 139 under `timeout`). The scalar
   returning functions of the same module do execute. `copy`, `filled`, and
   `reversed` cannot be claimed until the aggregate return ABI is fixed.
8. **Native numeric module imports.** The `core::{i32,u8,u32}` power-of-two
   helpers had overflow loops for values above their highest representable
   power of two. Source guards now return false for `is_power_of_two` and zero
   for `next_power_of_two` in that case. `repro_numeric_powers.lani` exercises
   their boundaries, but importing the complete numeric modules with
   `core::option` still stops native emission at unsupported target LIR opcode
   8. These fixes remain outside the executable claim until the compiler can
   run that fixture through the real stdlib root.
9. **Imported stdio metadata return.**
   `tests/fixtures/stdlib_host/repro_std_io_abi.lani` calls only
   `std::io::stdio_runtime_abi_version()`. Native emission succeeds, but the
   ELF terminates with SIGILL (exit 132 under `timeout`). The working I/O line
   wrappers are tested separately; the stdio metadata functions are not
   claimed executable as a whole.
10. **Imported path no-argument returns.**
    `tests/fixtures/stdlib_host/repro_path_byte_return.lani` calls only
    `std::path::path_unix_separator_byte()`. Native emission succeeds, but the
    ELF segfaults (exit 139 under `timeout`). A separate one-call
    `repro_path_capability_return.lani` for
    `path_contract_metadata_is_available()` terminates with SIGILL (exit 132).
    The 32 parameterized lexical helpers in the same module execute in focused
    fixtures; no-argument byte-valued and capability helpers remain outside
    that claim.
11. **Native i64 comparison.**
    `tests/fixtures/stdlib_foundation/repro_i64_compare.lani` compares
    an i64 value of `4,611,686,018,427,387,904` with `1,073,741,824`. Native emission
    succeeds, but the ELF exits 1 because it evaluates the large positive
    value as smaller. A proposed portable `number_i64` module was removed
    after this executable check; signed 64-bit numeric APIs cannot be claimed
    working from current native test results.
12. **Const-generic array indexing.**
    `tests/fixtures/stdlib_foundation/repro_array_i32_generic.lani` calls
    `core::array_i32::first` on a four-element array. Native emission stops
    with `LNC0017` at `values[0]` in the const-generic helper, so the generic
    array module remains contract-only; the concrete `core::array_i32_4`
    scalar functions have separate executable tests.
13. **Host integer read overflow.** The native host binding for
    `std::fs::read_i32(handle, fallback)` returns a wrapped value for input
    `2147483648` instead of the fallback. Compile
    `tests/fixtures/stdlib_host/repro_fs_read_i32_overflow.lani` with the
    stdlib root, then run the ELF from the repository root with the adjacent
    `overflow_i32.txt` fixture present. It exits 3 instead of 0. A higher-level
    checked integer file reader cannot safely promise overflow fallback until
    the runtime parser reports that failure.
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
    view combination. The compiler task has both minimal reproductions.
17. **Integer-to-character cast.**
    `tests/fixtures/stdlib_foundation/repro_u32_to_char.lani` returns a
    `u32` value as `char`. Native compilation reports `LNC0006`: the return
    context expects `char` but still sees `u32`. `core::char` uses explicit
    ASCII mappings for executable case conversion, while general conversion
    from a Unicode scalar to `char` remains a compiler dependency. This
    reproduction has been sent to the parallel compiler task.
18. **Secure random scalar failure channel.** The x86 runtime bytes for
    `std::random::secure_u32` in
    `shaders/codegen/lir/x86/runtime_abi.slang` return `0xFFFFFFFF` when the
    `getrandom` syscall does not return four bytes. That bit pattern is also a
    valid random `u32`, so callers cannot detect the failure. The bound
    `fill_secure_bytes` operation has a signed status result; a reliable
    scalar random API needs an equally unambiguous failure channel. The
    existing native test demonstrates normal execution, not failure handling.
19. **Transitive host import loses the native entrypoint.** With
    `--stdlib-root tests/fixtures/stdlib_foundation/repro_transitive_host_root`,
    `repro_transitive_host_direct.lani` emits an x86_64 ELF that exits zero.
    `repro_transitive_host_import.lani` type-checks with the same root, but
    native emission reports `LNC0017: missing main entrypoint` at the
    transitive `std::process` source. It calls the same bound exit operation
    through `test::probe`; these four small source files reproduce the issue.
    This blocks a source-level `test::assert` using process exit.

These are compiler/runtime dependencies, not stdlib implementations in Rust or
Python. They should be handled in the parallel compiler task before extending
the executable claim.
