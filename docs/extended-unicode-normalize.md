# Unicode normalization

`ext::unicode_normalize` implements Unicode 17.0.0 NFC, NFD, NFKC and NFKD
over counted UTF-8 `core::text::Text`. The engine allocates no storage and
never writes any output bytes when it returns an error. Callers supply
`core::slice::View<u32>` scratch and `core::slice::View<u8>` output.

The definitions come from [Unicode 17 chapter 3, sections 3.11 and
3.12](https://www.unicode.org/versions/Unicode17.0.0/core-spec/chapter-3/)
and [UAX #15 revision 57](https://www.unicode.org/reports/tr15/tr15-57.html).
Canonical ordering preserves the relative order of equal combining classes.
Composition respects blocking and the complete `Full_Composition_Exclusion`
property. Hangul decomposition and composition use the specified arithmetic.
Noncharacters, private-use values, unassigned scalars, and embedded NUL are
valid input. The engine rejects malformed UTF-8, including surrogates,
overlong encodings, truncated sequences and values above U+10FFFF.

## API

```lanius
pub enum Form { Nfc, Nfd, Nfkc, Nfkd }
pub enum Error {
    Bounds, InvalidUtf8(i32), SizeOverflow,
    ScratchCapacity(i32), OutputCapacity(i32), WorkLimit(u64)
}
pub struct Normalized {
    bytes: i32, scalars: i32, scratch: i32, work: u64
}

scratch_len(input: Text, form: Form, work_limit: u64) -> Result<i32, Error>
measure(input: Text, form: Form, scratch: View<u32>, work_limit: u64)
    -> Result<Normalized, Error>
normalize_into(input: Text, form: Form, output: View<u8>,
    scratch: View<u32>, work_limit: u64) -> Result<Normalized, Error>
is_normalized(input: Text, form: Form, scratch: View<u32>, work_limit: u64)
    -> Result<bool, Error>
maximum_decomposition_length(form: Form) -> i32
maximum_decomposition_depth(form: Form) -> i32
```

The names above abbreviate `core::text::Text`, `core::slice::View`, and
`core::result::Result`. Sizes and indices use `i32`, as these types do.

`scratch_len` returns the exact number of scalars in the full decomposition
before composition. It needs no output or scratch. `measure` fills scratch
with the normalized scalar sequence and returns the exact UTF-8 output size.
`normalize_into` performs the same computation, checks the exact output
capacity, and writes the UTF-8 prefix. It appends no terminator. `bytes` and
`scalars` describe the normalized output; `scratch` records the exact full
decomposition capacity required even when composition shortens the result.

An owning caller can first call `scratch_len`, allocate that many `u32`
elements, call `measure`, allocate exactly `bytes` output elements, and then
call `normalize_into`. Each call has its own budget and independently checks
its input. A caller with existing reusable buffers can call `normalize_into`
directly. `is_normalized` computes the requested form and compares the exact
result; a `Quick_Check=Maybe` value does not bypass composition checks.

## Storage and failure contracts

The selected input, scratch, and output storage must be disjoint, physically
backed for their claimed ranges, and alive for the entire call. Keep input
bytes immutable throughout the call. These are caller preconditions because
Lanius does not enforce borrowed lifetimes or discover physical slice lengths.
Native arrays and raw views retain their own element strides.

Every entry point validates logical range metadata. The engine also validates
the UTF-8 boundary, including a `Text` record fabricated without its checked
constructor. `InvalidUtf8` identifies the sequence's starting byte relative
to the selected input range. Negative ranges and an overflowing start plus
length return `Bounds`; a physically unbacked claim can trap and violates
the caller preconditions.

`ScratchCapacity(required)` and `OutputCapacity(required)` report exact
required sizes. `SizeOverflow` reports a count outside the `i32` range.
`WorkLimit(used)` reports consumed work at the failed charge. Output metadata
is checked first, then input and scratch metadata, then the validation/count
pass, scratch capacity, normalization work, and output capacity. Work
exhaustion can therefore precede a later capacity or encoding error.

All returned errors preserve the entire output storage, including the selected
range, its tail, and neighboring guards. Success changes only the normalized
output prefix. Scratch is workspace and may change on success or failure.
The count pass returns insufficient scratch capacity before writing scratch.

## Work and space bounds

Every call accepts an explicit `u64` work budget. The count pass charges one
unit per input scalar. The normalization pass charges one unit per decoded
input scalar, one per decomposed scalar emitted, one per ordering iteration,
one per ordering comparison, and one per composition iteration. Final sizing
charges one plus the UTF-8 width per normalized scalar; those width units
reserve the later output write or comparison. Consequently, `measure` and
`normalize_into` consume the same work for the same input and form. An empty
input succeeds with a zero budget and empty views. These units are a stable
description of this engine's accounting, rather than a CPU cycle estimate.

Static table searches have fixed bounds determined by Unicode 17 table sizes.
Canonical ordering uses stable insertion sorting and can take quadratic work
on a hostile combining run. Every comparison consumes budget, so a finite
caller budget bounds that work. Scratch holds the full decomposition; there
is no input-length assumption that normalized UTF-8 must fit in the original
byte count.

The generator verifies the decomposition graph has no cycles and fully expands
it into static tables. Runtime normalization performs no recursion and needs
no recursion stack or runtime depth limit. The derived Unicode 17 maxima are
4 scalars and depth 3 for canonical decomposition, and 18 scalars and depth 3
for compatibility decomposition. The public maximum functions report these
derived values; exact sizing uses the actual selected input.

Calls normalize complete input sequences. They do not insert CGJ or otherwise
change text to the Stream-Safe Text Format. The API exposes no resumable
streaming state: normalizing chunks independently can lose composition and
ordering context across their boundary.

## Data and verification

`tools/unicode17/generate_normalization.py` translates the official archived
Unicode 17 `UnicodeData.txt`, `DerivedNormalizationProps.txt`, and
`CompositionExclusions.txt` into `extended/ext/unicode_normalize_data.lani`.
It verifies the vendored compressed and original SHA-256 hashes against
`data/unicode/17.0.0/manifest.json`. Provenance and the Unicode V3 license live
beside those files. The generator uses no host Unicode database or normalizer.
The generated tables contain printable ASCII hexadecimal records read
directly from static string storage. No lookup creates a large local array,
allocates, or initializes the table at runtime.

```sh
timeout --kill-after=2s 100s python3 tools/unicode17/generate_normalization.py --check
timeout --kill-after=2s 100s env \
  CARGO_TARGET_DIR=/home/andrew-peterson/code/laniusc/target/stdlib-build \
  CARGO_INCREMENTAL=0 CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 \
  cargo test --test extended_unicode_normalize_execution
```

The native x86_64 Linux tests execute every Unicode 17 `NormalizationTest.txt`
row's twenty prescribed transformations. They also check every valid scalar
absent from Part 1, with NUL separators preventing cross-scalar interactions.
The column relationships exercise idempotence and canonical/compatibility
equivalence. Further checks cover every UCD decomposition, every Hangul
syllable, deterministic generated combining sequences, stable equal classes,
composition exclusions, blocked pairs, and `is_normalized` results against an
independent test-only UCD model.

Contract tests cover exact sizing, exact and exhausted budgets, hostile
combining runs, short scratch/output storage, malformed UTF-8 and metadata,
native and raw storage strides, output guards, and empty input. A separate
native run traces `mmap` and `munmap` while injecting allocation failures;
normalization succeeds with no allocation calls. Verification compiles Lanius
through the GPU compiler and executes the resulting native binaries; it does
not execute normalization as a GPU kernel.
