# `core::result::Result<T, E>`

`Result<T, E>` stores either a successful `Ok(T)` payload or a failed `Err(E)`
payload. `Ok(false)`, `Ok(0)`, and `Ok("")` are successful values. An error may
also be zero, false, or an empty borrowed view. The discriminant determines
the active variant independently of its payload.

The complete source module imports on x86_64 Linux. All twenty public functions
and methods have executable coverage for the tested instances below. Generic
free and receiver payload functions specialize the tested scalar arguments,
including strings. Compound extraction also executes for the record, slice, and fixed-array
instances listed in the [compiler checkpoint](compiler-generic-types.md).

Receiver methods take `self` by value. This follows Lanius copy semantics:
the caller keeps its enum, owned payloads copy, and borrowed payloads keep their
aliases. The receiver correction and its current executable checkpoint are
recorded in [compiler generics](compiler-generic-types.md).

## Executable operations

| Operation | Behavior |
| --- | --- |
| `Ok(value)`, `Err(error)` | Construct an annotated `Result<T, E>` with one active payload. |
| `is_ok(value)`, `is_err(value)` | Generic free predicates that inspect the discriminant. |
| `value.is_ok()`, `value.is_err()` | Generic value-receiver predicates. |
| `unwrap_or<T, E>` and `value.unwrap_or(fallback)` | Return the successful value or the explicit fallback. Never panics. |
| `unwrap_err_or<T, E>` and `value.unwrap_err_or(fallback)` | Return the failed payload or the explicit error fallback for success. Never panics. |
| `or<T, E>` and `value.or(fallback)` | Preserve a successful left input; otherwise return the fallback Result. Two failures select the fallback error. |
| `and<T, E>` and `value.and(next)` | Return the next Result after success; otherwise preserve the first error. |
| `contains_i32`, `contains_bool`, `contains_u32`, `contains_u8` | Compare the successful scalar payload. An `Err` returns false. |
| `contains_err_i32`, `contains_err_bool`, `contains_err_u32`, `contains_err_u8` | Compare the failed scalar payload. An `Ok` returns false. |
| Concrete `match` | Recover the complete active payload, with explicit behavior in both branches. |
| Function arguments and returns | Preserve the tested Result layouts. Generic free and value-receiver fallback extractors also execute for `Result<Pair, [i32]>` and `Result<[i32], bool>`. |

All predicates and membership helpers preserve their inputs and allocate no
storage. They never read the inactive payload. Ordinary calls reject a wrong
concrete scalar type with `LNC0006`; integer widths share identities as
described below.

The scalar fixture executes `Result<i32, bool>`, `Result<bool, i32>`,
`Result<u32, u32>`, and `Result<u8, u8>`, including signed extrema, unsigned
high-bit values, zero, and false. It also constructs, tests, and matches
`Result<Pair, Quad>` with independently sized caller-local records. Every
field survives extraction from its respective variant.

Generic payload-function tests execute i32/bool in both orders, u32/bool,
f32/char in both orders, and str/bool in both orders. They check both branches,
signed and unsigned extrema, false and zero, negative zero, Unicode and NUL,
empty string success, and which of two distinct string errors each combinator
preserves. Strings retain their pointer and length through generic extraction.

The receiver matrix executes those seven ordered environments plus str/str
and u32/u32. For each environment it checks two distinct success payloads and
two distinct error payloads, all 16 pairs for both combinators, both fallback
extractors, and input preservation. Empty string success and empty string
error remain distinct from each other. Wrong success and error argument types
are rejected independently; the receiver binds both generic slots.

Descriptor coverage includes `Result<[i32], str>` and `Result<str, [i32]>`.
Strings retain their contents and length; slices retain their pointer and
runtime length. An empty success or error view iterates zero times. Mutation
through a recovered slice changes its caller-owned backing. Bounds remain
active: indexing past a populated view or into an empty view exits with status
101. Bind slice-valued match results and loop iterables to typed locals.

Array payload tests execute `Result<[i32; 3], [i32; 2]>` and
`Result<[str; 2], [f32; 2]>`. Free and value-receiver fallback extractors preserve
complete success and error arrays, caller-provided fallbacks, independent
storage, both string descriptor words, and negative zero.

The compiler checkpoint also executes `Result<[Pair], [Pair]>` with populated
and empty record slices. Free and receiver fallback extraction preserve actual
runtime lengths and storage aliases. Composed generic arguments retain both
checked payload types, and empty extracted views retain native bounds traps.

## Target and limits

The GPU-resident compiler emits the tested x86_64 Linux programs. User-program
GPU execution is not established.

- The four free payload functions and four receiver payload methods execute
  for the scalar instantiations listed above on the resident native entry-root
  path. Record and slice fallback extraction has additional executable
  coverage. General nested layouts and methods with their own generic
  parameters remain unverified. Unsupported bodies must fail explicitly.
- Specialization retains sources and checked environments in memory; durable
  object-only linking does not persist them. The scheduler limits each build
  to 32 type arguments and 64 retained structural type nodes per body,
  256 distinct bodies, and 64 MiB of
  specialized native text. Exceeding a scheduling limit reports `LNC0017`.
- Signed integer widths share a compiler type identity, as do unsigned
  widths. Membership helpers do not narrow values or enforce distinct u8/u32
  types. Use explicit narrowing helpers when conversion is required.
- Unsuffixed high-bit unsigned constructor values need typed unsigned locals.
- Implied local record field applications have executable compiler coverage.
  Implied enum/imported field applications, element shapes beyond the tested
  records/strings/fixed arrays, arbitrary imported record layouts,
  and native i64/u64 payloads remain outside this tested set. The
  [compiler checkpoint](compiler-generic-types.md) records current execution
  evidence and the remaining generic compiler work.
- Borrowed payload storage belongs to the caller and must remain alive. A
  Result does not extend its lifetime or acquire ownership of it.

## Executable verification

`tests/stdlib_result_generic_execution.rs` exercises the actual stdlib through
`--stdlib-root`. Together with `tests/stdlib_result_methods_execution.rs`, it
covers all twenty functions and methods, both
variants, payload preservation, concrete returns, descriptor aliasing, empty
views, native bounds failures, rejected scalar types, and inconsistent slice
type arguments. Generic slice extraction now executes both branches and checks
the recovered views' lengths and aliases.

The receiver suite adds all state pairs,
NaN and negative zero in either payload, exact Unicode string output, and
rejection of inconsistent success/error arguments and result types.
The descriptor fixture also checks concrete i32
membership when the other payload is a borrowed slice; a mismatched successful
scalar remains a checking error.

[`result_reading_total.lani`](../sample_programs/result_reading_total.lani)
combines Result, slice iteration, range validation, saturating integer addition,
and stdio. Valid readings return `Ok(20)`; an invalid reading returns `Err(-2)`.
It uses both value-receiver fallback methods, and its executable test checks stdout
`20\n-2\n`.

Run the focused suite with:

```sh
CARGO_INCREMENTAL=0 CARGO_PROFILE_RELEASE_DEBUG=0 \
CARGO_TARGET_DIR="$PWD/target/stdlib-perf/build" \
timeout 110s cargo test --locked --release \
  --test stdlib_result_generic_execution \
  --test stdlib_result_methods_execution -- --test-threads=1
```

The retained suite log is
`tests/fixtures/stdlib_compiler_state/result-generic-receiver-tests.log`.
The broad foundation gate and performance comparison remain earlier checkpoints.
