# Runtime format strings and owned formatting

`core::format` formats a runtime `core::text::Text` using a typed argument list. It allocates nothing. `alloc::format` returns an independent owned UTF-8 `String` or byte `Vec`. The existing `core::fmt::Formatter` and `Display<T>` remain the lower level compositional interface.

This is a documented subset of the [Python format specification](https://docs.python.org/3/library/string.html#format-specification-mini-language), with the [Rust implicit argument cursor](https://doc.rust-lang.org/std/fmt/#positional-parameters). It does not claim to accept every Rust or Python format string.

## Arguments and entry points

```lanius
pub enum Argument {
    Text(core::text::Text), Signed(i64), Unsigned(u64),
    Bool(bool), Char(char), F32(f32), F64(f64)
}
pub struct Named { name: core::text::Text, value: Argument }
pub struct Limits { max_work: u64, max_output: i32 }

core::format::measure(pattern, positional, named, limits) -> Result<i32, Error>
core::format::format_into(pattern, positional, named, destination, limits) -> Result<i32, Error>
core::format::format_into_staged(pattern, positional, named, destination, staging, limits) -> Result<i32, Error>
alloc::format::format(pattern, positional, named, limits) -> Result<alloc::string::String, Error>
alloc::format::format_bytes(pattern, positional, named, limits) -> Result<alloc::vec::Vec<u8>, Error>
```

Patterns and text values are valid UTF-8 `Text`; argument lists and destinations are `core::slice::View` values. As with other view APIs, claimed backing lengths must be physically backed. Invalid negative or overflowing view metadata returns `Bounds`; overclaiming physical storage is a caller error and can trap. Backing storage must remain alive throughout the call.

Use `Argument::Signed` for signed integers of any width after widening to `i64`, and `Unsigned` after widening to `u64`. F32 retains its own binary precision. `Named` entries must have distinct nonempty ASCII identifier names, including entries unused by the pattern. Invalid names return `InvalidArgument(index)`; duplicates return `DuplicateName(index)` for the later entry. Unused positional values and unused named values are permitted. Repeated references reuse their value.

## Grammar

```text
format      := (literal | "{{" | "}}" | field)*
field       := "{" selector? (":" spec)? "}"
selector    := decimal-index | identifier
identifier  := [A-Za-z_][A-Za-z_0-9]*
spec        := (fill? align)? sign? "#"? "0"? width? ("." precision)? type?
align       := "<" | ">" | "^"
sign        := "+" | "-" | " "
width       := ASCII decimal digits
precision   := ASCII decimal digits
```

A fill is exactly one Unicode scalar followed by an alignment character; braces cannot be fills. Width and precision must fit nonnegative `i32`. There is no whitespace outside the grammar, no nested field, expression, attribute access, indexing operation, conversion (`!r`), dynamic width/precision, grouping, locale, percent, debug, or pointer conversion. Unsupported or contradictory controls fail; they are never silently ignored.

`{}` consumes the next implicit positional argument. Explicit numeric and named selectors leave that cursor unchanged: `"{1} {} {0} {}"` selects `1, 0, 0, 1`. Named fields can occur anywhere. Leading zeros in a numeric selector are permitted. Missing arguments report the opening brace's byte offset.

`{{` and `}}` emit one literal brace. An unmatched brace is an error, even after otherwise valid literal text and fields.

## Type controls

| Argument | Types | Precision | Sign / alternate / zero |
| --- | --- | --- | --- |
| Text, Bool, Char | absent or `s` | maximum Unicode scalars | rejected |
| Signed, Unsigned | absent, `d`, `b`, `o`, `x`, `X` | rejected | numeric sign, radix alternate prefix, sign aware zero padding |
| F32, F64 | absent, `f`, `F`, `e`, `E`, `g`, `G` | see below | numeric sign, decimal alternate form, sign aware zero padding |

Bool renders `true` or `false`; Char renders its UTF-8 scalar. Both follow the text controls, including scalar truncation. Signed radix formatting uses a minus sign and the unsigned magnitude, including `i64::MIN`; it does not format a two's complement bit pattern. Alternate integer prefixes are `0b`, `0o`, `0x`, `0X`; alternate decimal integers are rejected.

A plus sign always emits `+` on nonnegative numbers; a space sign emits one leading space; `-` explicitly selects negative signs only. Zero padding follows the sign and any radix prefix. Combining the zero flag with an explicit fill/alignment is rejected as contradictory. Width includes the sign and prefix.

Text defaults to left alignment and numbers to right alignment. Center alignment puts an odd extra fill on the right. Width counts Unicode scalars, **not UTF-8 bytes, grapheme clusters, or terminal columns**. Text precision cuts only at scalar boundaries; a combining mark is independently counted. Fill may be multibyte, including emoji, and each repetition counts one scalar. Returned sizes and destination capacities always count bytes. Embedded NUL is ordinary text and is preserved.

With no float type and no precision, formatting uses the existing shortest round-trip converter, including its `NaN`, `inf`, `-inf`, and signed zero spelling. An explicit float type defaults to precision 6. Precision without a type selects `f`. Fixed `f` precision counts fractional digits; scientific `e` precision counts fractional digits in a mantissa followed by a signed exponent with at least two digits. General `g` precision counts significant digits (`0` means `1`), chooses scientific notation when the rounded exponent is below -4 or at least the precision, and removes trailing fractional zeros unless alternate is selected.

Exact precision conversion rounds the original binary value to nearest, ties to even. Precision is bounded to 0 through 768; larger values return `InvalidSpec`. Alternate retains a decimal point at zero precision and retains trailing zeros for general form. Alternate without a type or precision is rejected. Explicit lowercase float types render `inf` and `nan`; uppercase types render `INF` and `NAN`. NaN payload/sign bits are not displayed. A requested positive sign still applies. See [exact float precision](stdlib-float-precision.md).

## Atomic output, aliases, and resources

`format_into` validates the complete pattern, argument names and selected value controls, computes the complete byte size, and reserves the work allowance before writing any destination byte. An error leaves the entire destination unchanged, including late parse/type/resource errors and insufficient capacity. On success it writes exactly the returned number of bytes and leaves the suffix untouched. Each numeric field uses bounded stack scratch; output length has no small fixed ceiling.

Commit deterministically repeats the validated render. During `format_into`, the pattern, argument records, name text, and selected Text backing must stay immutable and must be disjoint from destination storage. The language currently cannot enforce those borrow rules. Repeated or overlapping **source** views are permitted. For destination/input aliasing, use `format_into_staged`: staging must be independent of all sources and destination, with sufficient capacity for the whole result. Both capacities and the copy work allowance are checked before staging or destination is touched; the finished staged result is then copied into destination.

`Limits.max_output` is a nonnegative complete output byte limit; the default is `i32::MAX`. `Limits.max_work` is an explicit logical work allowance, default 64,000,000, rather than a wall clock deadline. Each render charges pattern bytes, validated name bytes and compared name bytes, inspected text prefix bytes, and emitted bytes (including padding). Each float occurrence conservatively reserves 1,000,000 additional units for conversion, even for nonfinite values. Named lookup and duplicate checking are linear and quadratic respectively and charge each name comparison. Padding measurement uses checked multiplication and constant time; it does not loop through a huge width.

`measure` and `format_into` each require one render to fit `floor(max_work / 2)`, reserving both preflight and commit. This makes measurement and direct rendering agree about the work gate. Staged rendering additionally reserves the final byte copy. Owned convenience functions conservatively require each render to fit `floor(max_work / 6)`, covering their three render passes, byte initialization, UTF-8 validation, and copying. Allocation latency and arbitrary user `Display` code are outside this logical budget. No stack growth, heap fallback, or shortened successful result occurs when a limit is exceeded.

`Error` distinguishes `Bounds`, `Syntax(offset)`, `MissingArgument(offset)`, `InvalidArgument(index_or_offset)`, `DuplicateName(index)`, `InvalidSpec(offset)`, `TypeMismatch(offset)`, `WorkLimit(offset)`, `OutputLimit(offset)`, `BufferTooSmall(required_bytes)`, and `Float(offset, detail)`. Syntax errors identify the first unexpected byte, or the opening brace for an unterminated field. Invalid controls discovered from an argument report the opening brace; malformed spec syntax identifies its unexpected byte. Text truncation and successful byte counts do not change these UTF-8 byte offsets. `Bounds` and global copy resource failures have no field position (`WorkLimit(0)` for the latter).

## Ownership and custom Display

`alloc::format` performs validation before allocation, returns explicit `Format` or `AllocationFailed` errors, and frees temporary owners on every failure. `format_bytes` uses one allocation for nonempty output. `format` currently copies that byte owner into `alloc::string::String`, using a second allocation; the intermediate is destroyed whether copying succeeds or fails. Empty output allocates nothing. Returned owners are independent of pattern and argument sources and must be destroyed exactly once; shallow owner copies alias the same allocation.

A general `Display<T>` to owned String helper is currently blocked by a compiler dependency and is **not public production API**. Both direct `T::format` and an extra `core::fmt::display` forwarding layer reached LNC0047 for minimal primitive-only consumers, including an explicitly typed Result inspected with a direct match. A larger consumer containing a user-defined Display implementation compiled, so that contextual success is insufficient to establish general support. No concrete payload overloads or compiler changes were introduced. Prototypes, exact diagnostics, passing controls, source hashes, and preparation commands are preserved in [the compiler-state evidence](../tests/fixtures/stdlib_compiler_state/format_result/README.md).

Custom Display remains useful through `core::fmt`: render it into a caller-backed Formatter, borrow its valid completed Text, and use `Argument::Text` in runtime or owned formatting. The production consumer fixture implements Display for `Point` and executes this complete path.

## Verification

`tests/stdlib_format_strings_execution.rs` compiles Lanius consumers into native x86-64 executables. The runtime model compares signed and unsigned extrema, generated integer/float encodings, exact f/e/g precision, nonfinite values, repeated named fields, multibyte fills and scalar truncation with Python's independent formatter. Contract fixtures check complete-output failures, error offsets, resource boundaries, strided subviews, alias staging, outputs larger than local numeric scratch, and custom Display composed through caller-backed Text. Allocation fault injection checks failures of both owned allocations and intermediate cleanup. Core execution is traced under failing allocation syscalls to verify that it allocates nothing.

Verified execution is x86_64 Linux output from the GPU compiler. Other targets
and user GPU kernels have not been verified.
