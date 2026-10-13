# `core::option::Option<T>`

`Option<T>` represents presence independently of the payload. `Some(false)`,
`Some(0)`, and `Some("")` are present values. `None()` constructs absence;
`None` is the corresponding match pattern. The type does not allocate or own
storage referenced by its payload.

```lanius
import core::option;

struct Pair { first: i32, second: i32 }

fn pair_or(value: core::option::Option<Pair>, fallback: Pair) -> Pair {
    return match (value) {
        core::option::Some(inner) -> inner,
        core::option::None -> fallback,
    };
}
```

Receiver methods take `self` by value. This follows Lanius copy semantics:
the caller keeps its enum, owned payloads copy, and borrowed payloads keep their
aliases. The receiver correction and its current executable checkpoint are
recorded in [compiler generics](compiler-generic-types.md).

## Executable operations

| Operation | Supported behavior |
| --- | --- |
| `Some(value)`, `None()` | Construct the documented concrete instances below. Annotate the receiving local with `Option<T>`. |
| `value.is_some()`, `value.is_none()` | Generic value-receiver tag predicates. They preserve the receiver and never read an inactive payload. |
| `core::option::is_some(value)`, `core::option::is_none(value)` | Generic free tag predicates. |
| `unwrap_or<T>`, `or<T>`, `and<T>`, `xor<T>` and their value-receiver methods | Shared generic Lanius bodies execute for the tested bool, i32, u32, f32, char, and str instantiations on the resident native path. |
| Generic `unwrap_or` with compound payloads | Free and value-receiver forms execute with caller-local records, `Cell<Pair>`, borrowed `[i32]` views, and the tested fixed-array payloads, preserving complete values, independent copies, and descriptor aliases. |
| Concrete `match` | Recover complete scalar, string, fixed-record, or tested scalar-slice payloads. The `None` branch supplies explicit failure or fallback behavior. |
| Function arguments and returns | Pass and return the tested concrete instances. Generic value functions also preserve nested `Option<Option<Pair>>` values. |
| `contains_i32`, `contains_u32`, `contains_u8` | Compare the present scalar; absence returns false. |
| Concrete `contains` methods | Equality executes for bool, i32, u32, f32, and char. The unsigned implementation also executes for tested u8 values; integer-width identity is limited as described below. |
| `Option<bool>::ok_or` | Returns `ResultBool`, preserving the present bool or using the supplied error for absence. |
| `ok`, `err` | Convert the concrete `ResultBool` representation to `Option<bool>`. |

The tested imported payloads are `bool`, `u8`, `u32`, `i32`, `f32`, `char`, `str`, and
caller-local fixed structs. Structs may nest other such structs and include
string or borrowed `[i32]` descriptors. String contents and lengths survive
construction, extraction, and concrete fallback functions. Borrowed slice
storage remains owned by the caller and must stay alive; extraction preserves
aliasing and the native indexing bounds.

Fixed-array fallback extraction also executes for `Option<[i32; 3]>` and
`Option<[str; 2]>`. Returned arrays have independent storage. String array
elements retain both descriptor words, including Unicode and empty strings.
The compiler checkpoint includes a generic record with an inline fixed i32
array field; monomorphic array-containing record constructors remain limited
as described below.

Direct `Option<[i32]>`, `Option<[u32]>`, `Option<[u8]>`, `Option<[bool]>`, and
`Option<[f32]>` payloads also execute. `Some(empty_view)` remains present and
iterates zero times. A concrete match returns the complete pointer/length
descriptor; mutation through the recovered view reaches the original backing
storage. Passing a view to a function preserves its actual runtime length,
including zero, independently of the descriptor's two-word storage width.
Bind slice-valued match-arm results to typed locals before the match; the
tested result projection uses those checked references.

## Scalar payload behavior

All scalar payload methods take a value receiver and preserve both inputs.
Lanius copies the enum; reference and slice payloads retain their aliases.
The generic free operations have the same selection behavior and preserve inputs.
`unwrap_or` returns the stored value for `Some` and the explicit fallback for
`None`. `or` prefers the left present value; `and` returns the right option
when the left is present; `xor` returns the sole present input and returns
`None` when both or neither are present. Stored zero, NUL, and false are present.
No scalar payload method allocates or panics.

`Option<f32>::contains` uses IEEE equality: NaN does not equal itself, while
positive and negative zero compare equal. Extraction and combinators retain
NaN and the sign of negative zero.

## Target and limitations

Execution is supported by the GPU-resident compiler emitting x86_64 Linux ELF.
This does not establish a user-program GPU target.

- Imported free and receiver payload bodies specialize with the six tested
  scalar identities above, including the two-word string representation.
  Compound extraction and generic value forwarding have the additional
  executable coverage in the [compiler checkpoint](compiler-generic-types.md).
  Methods with their own generic parameters and constant arguments still
  need compiler support. Calling
  another receiver method from a symbolic local impl body is also unsupported;
  the shared Option bodies inspect tags directly. Concrete matches remain
  available as listed above. A used
  unresolved template reports `LNC0017`, "referenced function has no native
  definition"; no guessed payload body is linked.
- Specialization uses retained source and checked call environments during
  a resident entry-root build. Durable object-only linking does not retain
  this context. The current scheduler accepts at most 32 type arguments and
  64 retained structural type nodes per body, 256 distinct bodies, and 64 MiB
  of specialized native text per build;
  exceeding a scheduler limit reports `LNC0017`.
- The compiler gives all signed integer widths one type identity and all
  unsigned widths another. Separate `Option<u8>` and `Option<u32>` method
  definitions collide, so the unsigned methods use one implementation.
  Its u8 tests use values in 0..255; these methods do not perform narrowing
  or enforce a distinct u8 argument type. Likewise, i32 methods provide no
  i8/i16 narrowing policy. Use the explicit numeric narrowing helpers when
  conversion is required. The compiler dependency and minimal reproduction
  are listed as dependencies 57 and 86 in the foundation audit.
- Imported constructors reject empty, cyclic, and monomorphic
  fixed-array-containing caller-local struct layouts with `LNC0006`. Their rejection prevents an
  unsupported payload copy from silently producing a value.
- Scoped nested declaration fields execute with their enclosing generic
  environments. The compiler creates implied applications for the tested local
  record fields. `Option<[Pair]>` extraction also preserves populated
  and empty views, runtime lengths, aliases, and bounds. The arrays listed
  above, `Option<Cell<Pair>>`, and `Option<Option<Pair>>` have focused execution
  coverage. Implied enum/imported field applications, untested element shapes,
  and payload structs from other imported modules still need compiler work or
  executable evidence; see the [compiler checkpoint](compiler-generic-types.md).
- Native full-width integer behavior remains a separate compiler dependency;
  this document makes no `Option<i64>` or `Option<u64>` runtime claim.
- Concrete record returns have executable coverage for the listed fixtures and
  sample. Layout completion uses the active imported interface page; arbitrary
  packs spanning several interface pages have not been verified for this case.
- Direct string-valued record fields execute as imported stdio arguments in
  the compiler checkpoint's descriptor-record fixtures.
- Named concrete i32, u32, u8, bool, and f32 slice locals and parameters can
  be iterated. The slice test also iterates an i32 view recovered from an
  Option record. Bind a projected field to a typed slice local first; direct
  field/call iterable expressions are unsupported. Unconditional return from
  a loop body remains an SSA dependency; conditional return executes.

No general `unwrap`, mutation, or replacement API is exposed here. The former
by-value replacement stub was removed.

## Focused verification

`tests/stdlib_option_generic_payload_execution.rs` executes all four generic
free operations through the actual stdlib for all six listed scalar identities.
It checks Some/None branches, extrema, false and zero, NaN, negative zero,
Unicode and NUL, empty string presence, input preservation, and exact string
stdout. It also executes the shared receiver bodies for strings, checks all
16 input pairs for each combinator, rejects bool fallbacks and mismatched
Option arguments, and runs the exact minimal string-crash reproduction.

The current receiver checkpoint passes all **25 tests** across that suite,
`stdlib_option_bool_execution`, and `stdlib_option_scalar_execution`. The
log is `tests/fixtures/stdlib_compiler_state/option-generic-receiver-complete-tests.log`.
Two native specialization tests additionally exercise distinct free and
receiver definitions in one program, preserve cached call identities, and
clear the substitution packet before the next ordinary compilation. Their
log is `option-receiver-retained-native-tests.log` in the same directory.
The adjacent template, generic memory, and Result suites pass all 17 tests in
`option-receiver-adjacent-runtime-tests.log`. Three checker graph tests and two
retained call-environment tests also pass, in
`option-receiver-checker-graph-tests.log` and
`option-receiver-retained-environment-tests.log`.
The later generic-slice checkpoint passes all seven foundation tests and its
139 executable source entries. Its log is
`generic-slice-foundation-complete-tests.log` in the same directory.
The checkpoints below record earlier changes. The
[compiler checkpoint](compiler-generic-types.md) records later execution and
performance evidence.

`tests/stdlib_generic_predicates_execution.rs` compiles the actual stdlib,
executes both tags and generic predicate methods, recovers multiword payloads,
checks descriptors, and rejects unsupported layouts and unrelated nominal
types. `tests/stdlib_option_bool_execution.rs` covers the bool methods and
conversions, including all three states and all nine state pairs.

Compiler reproductions and the supported foundation are listed in
[`stdlib-foundation.md`](stdlib-foundation.md), dependencies 1 and 76 onward.
An earlier focused imported checkpoint passed six tests, including scalar extrema,
floating payload fallbacks, empty strings, a native slice bounds trap, nominal
type rejection, and unsupported-layout diagnostics.
The bool suite passed all 18 tests. One additional symbolic-payload check
confirms that unsupported generic reads and offsets still fail with `LNC0017`.
These 25 checks preceded the direct-slice changes; the broad foundation gate
and performance benchmarks were not repeated. Logs are retained in
`tests/fixtures/stdlib_compiler_state/option-final-focused-tests.log`,
`option-final-bool-tests.log`, and `option-symbolic-payload-test.log`.

[`optional_reading_summary.lani`](../sample_programs/optional_reading_summary.lani)
combines `Option<Summary>`, slice reads, range validation, and saturating integer
addition. It checks the absent empty-input result and prints `4` and `20` for
the four valid readings.

`tests/stdlib_option_slice_execution.rs` passes five focused tests through the
actual stdlib. They execute both variants, all five listed slice element types,
empty presence, borrowed mutation, populated and empty bounds traps (exit 101),
concrete function returns, and wrong-element-type rejection. Its real program,
[`optional_slice_window.lani`](../sample_programs/optional_slice_window.lani),
combines memory, Option, ranges, and saturating arithmetic. Empty and invalid
input return `None`; valid input returns the original borrowed view and prints
`4` and `20`. The current slice-iteration suite also passes five tests, including
runtime lengths 0, 1, 2, 3, and 7 through direct and forwarding calls, fixed-array
scalar and record iteration, and the Option-record summary program.
Logs are `tests/fixtures/stdlib_compiler_state/option-direct-slice-tests.log`
and `slice-iteration-tests.log`. The scalar matrix was then strengthened to
return both `Some` and `None` through concrete functions for all five element
types; that focused check passes in `option-slice-return-scalar-matrix.log`.
Six imported scalar/record checks and six selected bool regressions also pass
after the slice changes, in `option-slice-adjacent-predicates.log` and
`option-slice-adjacent-bool.log`. These are native x86_64 Linux executions through
the GPU compiler. A user-program GPU target and a fresh performance comparison
are not covered by these runs.

`tests/stdlib_option_scalar_execution.rs` passes four focused tests. The
scalar matrix executes every new payload method for i32, u32, u8, f32, and char,
checking all 16 state pairs for each combinator, both signed extrema, unsigned
high-bit and maximum values, zero, NUL, finite floats, fallback values, and
input preservation. The float test checks NaN membership and preservation and
negative zero extraction. Wrong bool and unrelated Option payload arguments
produce `LNC0006`.

[`first_valid_reading.lani`](../sample_programs/first_valid_reading.lani)
combines ranges, slice iteration, optional scalar returns, fallback selection,
and saturating arithmetic. It prefers a valid primary reading, then a backup,
then an explicit default; stored zero takes precedence over the backup. Its
runtime test checks stdout `-2\n5\n`. The scalar suite log is
`tests/fixtures/stdlib_compiler_state/option-scalar-method-tests.log`.
The existing bool API fixture and direct slice-payload fixture also execute
after these additions, in `option-scalar-adjacent-bool.log` and
`option-scalar-adjacent-slice.log`. Earlier broad-gate and performance results
remain earlier checkpoints.

After native template deferral, the scalar method suite still passes all four
tests. The bool API fixture, direct Option-slice fixture, empty generic Vec API,
and used symbolic-payload rejection also pass. Logs are
`tests/fixtures/stdlib_compiler_state/template-adjacent-*.log` and
`template-used-payload-rejection.log`. Four Option-slice checks also pass after
the Result descriptor-argument fix, including wrong-element-type rejection
and bounds failures, in `result-slice-adjacent-option.log`. These focused checks
do not replace the earlier broad gate or performance comparison.
