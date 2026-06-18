# Lanius Source Standard Library

This directory contains the initial Lanius standard library as plain `.lani`
source files.

For a generated source-level module and declaration inventory, see
[`docs/stdlib/generated/reference.md`](../docs/stdlib/generated/reference.md).
Regenerate and check it with:

```bash
tools/stdlib_inventory.py --output docs/stdlib/generated/reference.md
tools/stdlib_inventory.py --check docs/stdlib/generated/reference.md
```

The full desired standard library surface is tracked in
[STANDARD_LIBRARY_SPEC.md](STANDARD_LIBRARY_SPEC.md). The long-term roadmap is
tracked in [PLAN.md](PLAN.md). Compiler and runtime prerequisites for
implementing those layers are tracked in
[LANGUAGE_REQUIREMENTS.md](LANGUAGE_REQUIREMENTS.md).

These files are not auto-imported by default. The old CPU source import
expander has been removed; `--source-root` can explicitly load leading user
module-path imports and `--stdlib-root stdlib` can explicitly load leading
stdlib module-path imports into the source pack before GPU type-checking. The
same boundary is published in the no-run `laniusc doctor` JSON report for
installers and editor wrappers that need to tell users how stdlib loading works
without scanning sources or creating a GPU device. The
GPU syntax path accepts one leading
`module path;` declaration plus leading `import path;` or `import "path";`
declarations as source metadata. Path imports resolve only against modules
already supplied in the source pack; `--stdlib-root` supplies stdlib files by
path convention and `--source-root` supplies user files by the same convention,
but neither rewrites source or decides declaration visibility.
Quoted imports remain unsupported. Duplicate or non-leading `module`
declarations and non-leading imports remain rejected so they cannot be silently
ignored.
Qualified value paths can pass GPU syntax as HIR evidence. Regular qualified
function calls, qualified extern calls, top-level qualified constants, local or
qualified unit enum variants, and bounded contextual local or qualified generic
enum constructors can type-check when the GPU module/import resolver resolves
the path to a matching declaration. Bounded module-qualified generic calls such as
`core::option::unwrap_or(value, fallback)` can type-check when the return type is
inferred from scalar literal or annotated local arguments through GPU type-ref
metadata. General qualified value paths, non-constructor symbolic generic enum
returns, methods, and broader generic callees remain rejected.

Terminology in this README is intentionally narrow: `type-checks`, `frontend
evidence`, and `source seed` mean the current frontend can accept explicitly
supplied source-pack inputs. `Contract metadata` means public descriptors or
probes for a currently blocked service. Those labels do not imply auto-imports,
package loading, runtime service binding, native/WASM lowering, or executable
support.

The GPU lexer now has an explicit source-pack upload path for already-supplied
source strings. It concatenates their bytes, uploads `source_file_count`,
`source_file_start`, and `source_file_len`, resets the DFA at GPU-visible file
starts, clamps token starts to file starts after skipped trivia, and writes
per-token `token_file_id` on GPU. The GPU syntax checker uses that sideband to
validate leading `module` and `import` metadata per file. An explicit
source-pack type-check entrypoint records the resident GPU
lexer/parser/type-checker path against source-pack buffers. The rebuilt
foundation follows the paper's name extraction pattern: sort/deduplicate
identifiers into stable ids, build path/module/import/declaration records from
AST/HIR spans, sort module and declaration keys, validate duplicates with
sorted adjacent comparisons, resolve path imports to module ids through a GPU
sorted lookup table, materialize visibility tables, resolve type/value paths,
  and connect narrow HIR consumers for regular/extern qualified function calls,
top-level constants, and unit enum variants. The prior scan-based resolver and the later dense
hash/prefix-scan metadata slice were deleted so neither can be mistaken for the
intended sorted-table design. `--stdlib-root` can load stdlib module-path
imports into the source pack, but this still does not provide package manifests,
user package roots, quoted import loading, general qualified value lookup, or a
full package compiler. The normal compiler now records the LL(1) tree/HIR path.
That path receives the
lexer-produced `token_file_id` sideband, validates it during GPU syntax
checking, and feeds it into LL(1) HIR
ownership metadata. The older direct-HIR helper still mirrors the sideband, but
it is not the semantic path to extend.

Module-form helpers live under `stdlib/core/` and use module names such as
`core::i32::abs`. Explicit source-pack inputs and `--stdlib-root` can
type-check module-qualified helpers, and the current x86 path can execute
bounded direct scalar helper calls, currently including
`core::u8::is_ascii_digit`. The active WASM source-pack execution slice is
narrower: synthetic selected linear scalar helpers, synthetic terminal
`if`/`else` helpers, and resolver-backed scalar constants. Real stdlib enum
predicate helpers, broader primitive helper families, arrays, aggregates,
methods, assertion helpers, and payload enum helpers remain blocked until
rebuilt on the record pipeline. Legacy flat files keep the `lstd_` prefix so
copied or manually concatenated helpers are less likely to collide with
application functions.

The GPU parser now preserves early HIR evidence for module items, import items,
and complete qualified path spans. Those records feed the current GPU
module-key, import-target, declaration, visibility, and path-resolution tables,
but they do not imply that imports were loaded or that general qualified values
were bound to executable backend lowering.

The LL(1) parser tree path additionally emits parser-owned HIR item-field
metadata from production ids and AST ancestry. It records top-level item facts
for modules, imports, consts, functions, extern functions, structs, enums, and
type aliases while excluding impl methods from top-level function declarations.
Bounded scalar type aliases now have semantic effect through a GPU alias
projection pass that consumes those records and the sorted module/type resolver.
Direct generic aliases such as `type Alias<T> = T;`, one-hop generic aliases
such as `type Id<T> = Alias<T>;`, and bounded multi-hop scalar alias chains have
GPU type-ref coverage; recursive aliases, deeper generic alias chains,
const-generic alias substitution, and broad alias targets remain unsupported.

Current scope is intentionally small. Module-form seeds below are parser and
source-pack frontend evidence; regular/extern qualified calls, top-level
constants, bounded scalar aliases, and local or qualified unit enum variants
can type-check through the current resolver when their declaring modules are
explicitly supplied or loaded through `--stdlib-root`. Flat compatibility seeds
without module headers can still type-check directly. None of this implies a
full package system, general qualified value lookup, runtime services, or
backend lowering:

- `core/i32.lani` has module-form integer constants, including numeric
  `BITS` and `BYTES` metadata, and helpers built from supported arithmetic and
  comparison operators, including source-level `saturating_abs` and
  `saturating_abs_diff` seeds plus nonzero, parity, and exclusive-range
  predicates plus nonnegative/nonpositive sign-bound predicates.
  `core::i32::saturating_abs_diff`, `core::i32::is_nonzero`,
  `core::i32::is_even`, `core::i32::is_odd`, and
  `core::i32::between_exclusive`, `core::i32::is_nonnegative`, and
  `core::i32::is_nonpositive` can type-check through `--stdlib-root` from an
  importing caller as frontend evidence only. `core::i32::checked_add`
  returns `core::option::Option<i32>` for source-level overflow-aware addition
  and type-checks through `--stdlib-root`; this is not yet executable backend
  coverage.
- `core/u8.lani`, `core/u32.lani`, and `core/i64.lani` seed additional integer
  helper modules in the same primitive-helper family as `core/i32`; they include
  numeric `BITS` and `BYTES` metadata plus `is_nonzero` and parity predicates
  plus `between_exclusive` for strict range checks that type-check through
  `--stdlib-root` as frontend evidence only. `core/i64` also exposes
  source-level `saturating_abs` for the minimum-value edge case and
  `checked_abs`, `checked_add`, and `checked_sub` helpers returning
  `core::option::Option<i64>` for overflow-aware signed arithmetic.
  `core/u8` adds byte-oriented ASCII
  helpers, including range classification, control-byte and punctuation
  predicates, graphic and printable predicates, hex-digit value conversion, and
  case-normalization helpers plus case-insensitive equality for ASCII bytes.
  It also includes `abs_diff` for unsigned byte distance plus `checked_add`,
  which returns `core::option::Option<u8>` for source-level overflow-aware byte
  addition.
  These helpers type-check through `--stdlib-root` as frontend evidence only.
  `core/u32` also includes source-level
  `checked_add`, `checked_sub`, `saturating_add`, `saturating_sub`,
  `saturating_mul`, `checked_next_power_of_two`, `abs_diff`, and
  `is_multiple_of` seeds.
  `core::u32::is_multiple_of(value, divisor)` returns false for a zero divisor
  and otherwise checks whether `value` divides evenly by `divisor`.
  `core::u32::checked_add` and
  `core::u32::checked_sub` return `core::option::Option<u32>` for
  source-level overflow-aware arithmetic, and
  `core::u32::checked_next_power_of_two(value)` returns
  `core::option::Some(1)` for `0` and `1`,
  `core::option::Some(power)` when the next power of two is representable, and
  `core::option::None` above the highest representable `u32` power of two.
  `core::u32::saturating_mul` provides source-level saturating unsigned
  multiplication. These helpers type-check through `--stdlib-root`; this is
  not yet executable backend coverage.
- `core/f32.lani` seeds a small floating-point helper module using currently
  parseable float literals, comparisons, and arithmetic. Its sign and zero
  predicates `core::f32::is_negative`, `core::f32::is_positive`,
  `core::f32::is_zero`, `core::f32::is_nonzero`, and
  `core::f32::signum`, plus the exclusive-range predicate
  `core::f32::between_exclusive` and inclusive-range predicate
  `core::f32::between_inclusive`, type-check through `--stdlib-root` from an
  importing caller as frontend evidence only.
- `core/char.lani` seeds ASCII classification helpers using currently parseable
  char literals and boolean expressions, including digit, alphabetic,
  alphanumeric, word-character, hexadecimal-digit, whitespace, punctuation,
  graphic, and printable predicates, plus case-insensitive equality for ASCII
  letters. `core::char::is_ascii_word(value)` is a source-level classifier for
  ASCII alphanumeric characters plus `_`; it type-checks through
  `--stdlib-root` as frontend evidence only and does not imply backend
  execution. `core::char` ASCII classification and case-insensitive equality
  helpers can type-check through `--stdlib-root` from an importing caller as
  frontend evidence only. Backend execution remains limited to the active
  narrow slices.
- `core/bool.lani` has module-form boolean combinators, equality/inequality,
  conversions, and bounded `i32` selection helpers built on the current bool
  expression surface, including `true` and `false` literals.
  `core/bool.lani` can type-check as an explicitly supplied source-pack seed or
  through `--stdlib-root`, including `core::bool::ne`,
  `core::bool::select_i32`, and the terminal-branch
  `core::bool::choose_i32`. Selected synthetic bool-shaped helper bodies have
  WASM source-pack execution coverage, but real `core::bool` module execution
  is still not an active backend claim. `test/assert.lani` is
  frontend/type-check evidence only; assertion-helper WASM execution remains
  ignored.
- `core/mem.lani` has no-runtime generic value helpers such as
  `core::mem::identity`, `core::mem::first`, `core::mem::second`, and
  `core::mem::select`. The module is ordinary Lanius source and type-checks
  through `--stdlib-root` from an importing caller with both imported-name and
  qualified calls at multiple concrete call-site substitutions. Its raw-memory
  service contract exposes `raw_memory_contract_metadata_is_available()` and
  `raw_memory_host_abi_is_contract_only()` so callers can distinguish
  descriptor metadata from executable allocation/runtime support. It is a
  frontend/type-check stdlib seed only; it does not imply a move, borrow,
  destructor, layout, or allocation model.
- `core/array_i32_4.lani` has module-form fixed-size `[i32; 4]` helper seeds
  for length, first/last element access, lookup, counting, min/max, sum, copy,
  fill, and reverse. It is still a concrete stopgap for helpers that need a
  known length value, but the flat and module-form seed files now type-check on
  the GPU. They rely on bounded concrete i32 array signatures, HIR-backed array
  returns, HIR index expressions, while/if control typing, and compound scalar
  assignments. Array-helper WASM execution is not an active claim right now:
  the legacy full-source-pack array execution tests are ignored until rebuilt
  on the record pipeline. Broader array helper lowering, loops, and
  array-valued backend lowering are still not implemented.
- `core/array_i32.lani` has early const-generic `[i32; N]` helpers such as
  `first()` and `get_unchecked()`. The full module-form seed can pass GPU
  source-pack type checking as module metadata, while direct fixtures still
  validate named array lengths in frontend type checking for concrete `i32`
  elements. A bounded GPU slice now accepts generic array/slice declarations
  and indexed element returns such as
  `fn first<T, const N: usize>(values: [T; N]) -> T { return values[0]; }`,
  plus `ArrayVec<T, const N: usize>` field declarations. Bounded direct
  generic array/slice calls can infer an element return `T` from one
  declaration-backed actual array or slice argument, and local generic array
  annotations can feed indexed element returns. Bounded generic identifier
  array returns such as returning a `[T; N]` parameter from a `[T; N]` function
  now type-check through GPU type-instance records, and an annotated local can
  receive a bounded generic array-valued call result when the actual argument
  declaration has the same concrete array instance. The same bounded check now
  covers returning that array-valued call from a function with the matching
  array return type. Full const evaluation, slice ABI, broader array-valued
  calls, and array-valued backend lowering are still missing.
- Generic function declarations, generic type annotations, and simple generic
  function-call substitution now have GPU type-check coverage for direct calls
  inferred from arguments, including generic forwarding from one generic
  function to another and nested direct helper calls such as `keep(keep(7))`.
  Full monomorphization and backend specialization are separate work.
- `core/option.lani` and `core/result.lani` have declaration seeds for the
  generic core sum types. They now type-check as explicitly supplied source-pack
  seeds through GPU generic enum constructor returns and bounded match payload
  typing. `core/ordering.lani` has the non-generic `Ordering` enum plus
  `compare_i32`, `compare_i64`, `compare_u32`, `compare_u8`, `reverse`,
  `then`, `to_i32`, and predicate helpers such as
  `is_less_or_equal`, `is_greater_or_equal`, and `is_not_equal`; the full
  module-form seed type-checks when supplied explicitly with an app module or
  through `--stdlib-root`, including local returns such as `return Less;` in
  comparison helpers, ordering rank conversion to `-1`/`0`/`1`, and qualified
  app uses such as `core::ordering::Less`. These ordering helpers are
  frontend/source-level evidence only; they do not imply executable enum
  lowering.
  Bounded GPU generic enum constructor
  payload substitution now works for annotated concrete locals such as
  `Maybe<i32> = Some(1)` and `Result<i32, bool>` constructors.
  The same bounded validator now works through resolver arrays for local and
  qualified source-pack constructors such as `Some(1)` and
  `core::maybe::Some(1)` in annotated concrete local contexts. Symbolic generic
  constructor returns such as
  `fn wrap<T>(value: T) -> Option<T> { return Some(value); }` now type-check
  through return-ref metadata. Bounded stdlib-shaped match typing now covers
  arms such as `Some(inner) -> inner` and `None -> fallback` through HIR match
  spans and type-instance payload substitution. Bounded module-qualified generic
  calls such as `core::option::is_some(value)`,
  `core::option::unwrap_or(value, fallback)`, `core::result::is_ok(value)`, and
  `core::result::unwrap_or(value, 3)` now type-check in an explicitly supplied
  source pack. The concrete scalar helpers
  `core::option::contains_i32(value, expected)`,
  `core::option::contains_u32(value, expected)`,
  `core::option::contains_u8(value, expected)`, and
  `core::result::contains_i32(value, expected)` plus
  `core::result::contains_err_i32(value, expected)` can type-check through
  `--stdlib-root` from an importing caller as frontend evidence only. The
  same-type option combinator `core::option::xor(left, right)` can
  type-check in an explicitly supplied source pack as frontend evidence only.
  `core::option::ok_or(value, error)` now type-checks as a bounded
  `Option<T>` to `Result<T, E>` helper by resolving module-qualified
  `core::result::{Ok, Err}` constructors inside match arms. The reverse
  source-level conversions `core::option::ok(result)` and
  `core::option::err(result)` type-check as bounded `Result<T, E>` to
  `Option<T>` / `Option<E>` helpers through the same explicit source-pack
  enum-match path.
  Backend
  execution for tag-only predicates such as
  `core::option::is_some(value)` / `core::result::is_ok(value)` is not an
  active WASM claim; the guarded execution test is ignored and the retired
  enum-match module emitter is no longer loaded until enum/match lowering is
  rebuilt on record-driven passes. Payload projection helpers such
  as `unwrap_or`, `contains_i32`, and `contains_err_i32` remain blocked until
  backend lowering consumes parser-owned call/constructor argument records and
  typed payload value records instead of token-shaped call syntax.
  Package/import loading,
  exhaustive match semantics,
  non-constructor symbolic generic returns, full monomorphization, and general
  enum layout remain unsupported.
- `core/cmp.lani` has declaration seeds for generic `Eq<T>` and `Ord<T>`
  traits plus bounded `i32` trait impls. `core/hash.lani` similarly seeds a
  generic `Hash<T>` trait and an `i32` impl. These seed files now type-check
  together in the GPU source-pack path, including trait impl header resolution,
  required-method presence validation, required-method parameter-count
  validation, and bounded structural parameter and return signature validation
  for scalar/path, reference, array/slice, and generic-instance type forms, with
  trait generic arguments substituted from the impl header. `where` clauses now
  have bounded GPU semantic coverage for direct calls whose generic trait
  obligation can be proven by exactly one concrete one- or two-argument impl row;
  missing and ambiguous candidates reject. General trait solving, method lookup
  through traits, dictionaries, associated items,
  const-generic argument substitution in trait signatures, and backend lowering
  are not implemented yet.
- `core/range.lani` has declaration seeds for `Range<T>`,
  `RangeInclusive<T>`, `RangeFrom<T>`, `RangeTo<T>`, and `RangeFull`, plus
  source-level `i32` helpers for exclusive and inclusive construction,
  endpoints, emptiness, and containment. It also has bounded `Range<i32>` and
  `RangeInclusive<i32>` impl method declarations using value, explicit-type,
  and reference receiver forms. These exercise generic struct declaration,
  receiver, member-access, and `for` syntax in parser/source-shape coverage.
  `self`, `self: Type`, and `&self` receiver forms now parse through the GPU
  frontend, direct `self.field` access type-checks for those receiver spellings
  in direct concrete `Range<i32>` impl fixtures, and concrete inherent method
  calls type-check for direct single-file receivers. The module-form seed now
  type-checks in an explicit source pack, including qualified calls such as
  `core::range::range_i32(1, 4)`, qualified `core::range::Range<i32>`
  annotations, and bounded `Range<i32>` / `RangeInclusive<i32>` method calls on
  annotated receivers through parser/HIR-derived method declaration, call, and
  argument-list records.
  Aggregate and method execution is not an active WASM claim right now: the
  legacy execution tests are ignored until rebuilt on the record pipeline. The
  current useful evidence here is frontend/type-check metadata, not executable
  `core::range` helper lowering.
  `&self` does not yet imply a general reference or borrow model. General range
  operators, slicing integration, trait/generic method lookup, private/public
  method visibility enforcement, full monomorphization, and general backend
  representation are not implemented yet.
- `core/slice.lani` has source-level `[i32]` view helpers such as
  `first_i32`, `get_or_i32`, `contains_i32`, and `sum_i32`. Direct `[i32]`
  slice parameter/indexing fixtures have GPU type-check coverage, but the full
  `core/slice.lani` file is still a source seed rather than an accepted stdlib
  module seed. Slice runtime metadata, borrowing, mutation views, and backend
  representation are not implemented yet.
- `core/panic.lani` declares source-level `panic()` and `unreachable()`
  runtime-boundary helpers. It also exposes a frontend/type-check panic-hook
  service contract:
  `PANIC_HOOK_RUNTIME_ABI_VERSION`, `PANIC_HOOK_SERVICE_ID`,
  `PANIC_HOOK_SERVICE_STATUS_UNAVAILABLE`,
  `PANIC_HOOK_HAS_RUNTIME_BINDING`, and helpers such as
  `panic_hook_runtime_abi_version()`, `panic_hook_service_is_known()`,
  `panic_hook_contract_metadata_is_available()`,
  `panic_hook_is_blocked()`, `panic_hook_requires_runtime_binding()`,
  `panic_hook_host_abi_is_contract_only()`, and
  `panic_hook_is_contract_only()`. Public gates
  `panic_is_executable()`, `panic_is_blocked()`,
  `panic_requires_runtime_binding()`, `unreachable_is_executable()`,
  `unreachable_is_blocked()`, and
  `unreachable_requires_runtime_binding()` keep the raw extern declarations
  fail-closed. These mirror the unbound
  `core::runtime::SERVICE_PANIC_HOOK_ID` boundary without installing a hook or
  making panic reporting executable. The module-form seed now type-checks as
  an explicitly supplied source-pack seed and through `--stdlib-root`, but the
  extern declarations remain non-executable until a runtime/linker binding
  exists. Assertion-helper execution still needs HIR-driven WASM lowering for
  resolver-selected void helpers with typed assertion expression statements and
  void returns. Rich panic payloads, formatting, hooks, unwinding, source
  locations, executable traps, and runtime/linker hook binding are not
  implemented yet.
- `core/target.lani` has a public `Capability = bool` alias plus source-level
  target capability constants and helpers intended to become paths such as
  `core::target::has_filesystem()` and `core::target::is_wasm()`. The
  module-form seed can type-check as an explicitly supplied source-pack seed and
  through normal `--stdlib-root` loading, including caller-visible imported and
  qualified alias, constant, and helper uses. It exposes conservative target
  probes for panic hooks, aggregate host services, process/environment services,
  `core::target::has_runtime_services()`,
  `core::target::runtime_services_are_blocked()`, and
  `core::target::is_freestanding()`. These are static conservative defaults
  for the active executable compiler slice:
  runtime-backed services such as allocation, filesystem, stdio, clocks,
  panic hooks, networking, aggregate host services, threads, secure RNG, GPU
  host services, process, environment, and test harness are reported as
  unavailable until a real runtime/linker contract exists. Real target
  configuration, compile-time capability evaluation, and backend execution are
  still missing.
- `core/runtime.lani` exposes a self-contained conservative runtime capability
  subset with constants and query helpers such as
  `core::runtime::HAS_PANIC_HOOK` and `core::runtime::has_panic_hook()`. These
  all report unavailable services in the active compiler slice and can
  type-check through normal `--stdlib-root` loading. The file also exposes a
  small numeric descriptor surface: `RUNTIME_ABI_METADATA_VERSION`,
  `RUNTIME_ABI_VERSION`, plus stable `SERVICE_*_ID` constants for allocator,
  filesystem, stdio, clock, network, panic-hook, aggregate host-service,
  threads, secure RNG, GPU host-service, process, environment, and test-harness
  bindings. This is a frontend contract surface only; it does not make
  allocator, filesystem, stdio, clock, panic hooks, network, process,
  environment, or test harness APIs executable.
  `runtime_abi_metadata_version()`, `RUNTIME_SERVICE_COUNT`,
  `FIRST_RUNTIME_SERVICE_ID`, `LAST_RUNTIME_SERVICE_ID`,
  `runtime_service_count()`, `first_runtime_service_id()`,
  `last_runtime_service_id()`, and
  `service_id_in_descriptor_range(id)` expose the bounded descriptor inventory
  for tooling without binding any service.
  `is_known_service(id)` classifies stable descriptor ids,
  `service_descriptor_is_known(id)` is the same predicate under a name intended
  for diagnostics and external tools,
  `runtime_abi_version_for_service(id)` returns
  `RUNTIME_ABI_VERSION` for known service descriptors and
  `UNKNOWN_RUNTIME_ABI_VERSION` for unknown ids, and `has_service(id)` maps
  known ids to the current conservative capability constants, which are all
  false for runtime-backed services today. `service_has_runtime_binding(id)` is
  the externally named alias for that executable-binding probe.
  `service_status(id)` returns a
  stable numeric `RuntimeServiceStatus`: `SERVICE_STATUS_UNKNOWN` for unknown
  ids, `SERVICE_STATUS_UNAVAILABLE` for recognized-but-unbound services, and
  `SERVICE_STATUS_AVAILABLE` only when a future capability becomes true.
  `service_is_unknown(id)`, `service_is_unavailable(id)`, and
  `service_is_available(id)` are descriptor-only predicates over that status;
  `service_is_unbound(id)` is the public diagnostic spelling for the
  recognized-but-unbound case. They do not bind or execute any host service.
  `service_is_known_but_unbound(id)` is the stricter source-level predicate for
  that exact boundary: it is true only for recognized service descriptors whose
  current runtime binding is unavailable.
  `runtime_bound_api_is_executable(id)` is the API-level form of the same
  predicate: it is false for current runtime-backed stdlib APIs whose required
  service is recognized but unbound. `runtime_bound_api_is_blocked(id)` is the
  fail-closed companion: it remains true for both recognized-but-unbound services
  and unknown service ids. `runtime_bound_api_is_known_but_unbound(id)` exposes
  the stricter recognized-but-unbound check for runtime-bound API metadata.
  `service_is_fail_closed(id)` is the same fail-closed
  query named from the service-descriptor side, and `service_is_blocked(id)` is
  the module-style spelling for callers that check a descriptor before using a
  runtime-backed API.
  `service_is_contract_only(id)` and
  `service_requires_runtime_binding(id)` are descriptor-only diagnostic helpers:
  they return true only for known service descriptors whose current capability
  is false, so tools can distinguish "recognized but unbound" from "unknown
  service id" without assuming any runtime service exists.
  `runtime_bound_api_requires_runtime_binding(id)` is the API-facing spelling
  of that same known-service runtime-binding requirement; it is an alias for
  `runtime_bound_api_requires_binding(id)` and still returns false for unknown
  service ids.
  `service_binding_diagnostic_is_lnc0038(id)` is a source-level bridge to the
  public diagnostic class used by tools for that recognized-but-unbound
  condition. The current aggregate runtime signal is also explicit:
  `HAS_RUNTIME_SERVICES` and
  `has_runtime_services()` are false, while
  `runtime_services_are_contract_only()` and
  `runtime_services_are_blocked()` are true, until a linker/runtime binding can
  make runtime-backed services executable. The current descriptor
  inventory covers allocator, filesystem, stdio, clock, network, panic-hook,
  aggregate host services, threads, secure RNG, GPU host services, process,
  environment, and test harness; all runtime-backed capability constants are
  false in this slice.
  Source-pack artifact descriptors can carry these ids in
  `required_runtime_service_ids` together with
  `required_runtime_abi_version = RUNTIME_ABI_VERSION`, and also persist flat
  `required_runtime_services` rows containing the service id, ABI version, and
  current service status. `core::runtime` now names that flat-row schema with
  `RUNTIME_SERVICE_REQUIREMENT_FIELD_COUNT` plus stable field ordinals for the
  service id, required ABI version, and service status. It also exposes
  `runtime_service_requirement_row_is_contract_only(id, abi, status)`,
  `runtime_service_requirement_row_is_valid(id, abi, status)`, and
  `runtime_service_requirement_row_is_fail_closed(id, abi, status)` as
  source-level guards for requirement rows. Only recognized, active-ABI,
  known-unbound rows are valid; unknown service ids, unsupported ABI versions,
  executable status claims, and unknown status claims all fail closed before a
  caller treats a row as descriptor metadata.
  `runtime_service_requirement_status_is_declared(status)` and
  `runtime_service_requirement_status_is_fail_closed(status)` let row readers
  keep existing row-focused names, while
  `runtime_service_status_is_unknown(status)`,
  `runtime_service_status_is_unavailable(status)`,
  `runtime_service_status_is_available(status)`,
  `runtime_service_status_is_contract_only(status)`,
  `runtime_service_status_is_declared(status)`, and
  `runtime_service_status_is_fail_closed(status)` expose the same checks for
  raw `RuntimeServiceStatus` values before a caller has a full requirement row;
  invalid, unknown, and unavailable statuses all fail closed.
  Runtime-bound descriptors must also persist a
  `runtime_abi` metadata object with the metadata format version, ABI version,
  service count, and first/last service-id bounds. Descriptor validation treats
  each public `core::runtime` service id as a recognized contract id. The public
  descriptor builder writes service ids and service rows in ascending canonical
  order, and validation rejects non-canonical persisted service-id lists, rows
  that do not match the id list, orphan `runtime_abi` metadata without required
  service ids, missing or incoherent runtime ABI metadata, or runtime ABI
  inventory values that diverge from this stdlib contract. Any
  runtime-bound descriptor must pin that ABI version, keep service rows at
  `SERVICE_STATUS_UNAVAILABLE`, stay contract-only, and reject emitted
  target-byte records until a linker/runtime binding exists.
  `LNC0038` is the public diagnostic class for this runtime-service boundary:
  future stdlib or host-service calls should use it when a known service
  descriptor is still contract-only instead of reporting a backend-specific
  failure. `laniusc diagnostics explain LNC0038` includes a structured
  `runtime_service_boundaries` array for all known service descriptors, with
  each row naming the module path, service id, status probe, binding probe,
  current `known-unbound` status, and `executable = false`. The same
  explanation also includes `runtime_bound_apis`, a structured table of the
  currently declared runtime-bound stdlib extern APIs such as
  `std::io::print_i32`, with their owning service module paths, capability
  constants, service-level probes, `service_current_status` and
  `service_executable`, and API-level executable and runtime-binding probes.
  Every row remains `known-unbound` and `executable = false`.
  Link execution summaries use the same ABI-pinned service-id shape before they
  produce partial-link or linked-output artifact descriptors, so persisted link
  plans cannot imply a runtime service without also naming the expected runtime
  ABI.
  `alloc::*` and `std::*` extern declarations remain source-level ABI
  declarations until a runtime/linker gate rejects or binds them explicitly.

Runtime capability status in the active compiler slice:

| Service descriptor | Current capability | Production requirement |
| --- | --- | --- |
| `SERVICE_ALLOCATOR_ID` | `HAS_ALLOCATOR = false` | Allocator ABI binding, ownership/drop model, executable lowering |
| `SERVICE_FILESYSTEM_ID` | `HAS_FILESYSTEM = false` | Path/string ABI, host filesystem binding, error model |
| `SERVICE_STDIO_ID` | `HAS_STDIO = false` | Host I/O binding, writer/string or byte-slice ABI |
| `SERVICE_CLOCK_ID` | `HAS_CLOCK = false` | Time representation, host clock/sleep binding |
| `SERVICE_NETWORK_ID` | `HAS_NETWORK = false` | Socket/address ABI, DNS and host network binding |
| `SERVICE_PANIC_HOOK_ID` | `HAS_PANIC_HOOK = false` | Panic payloads, source locations, runtime hook binding |
| `SERVICE_HOST_SERVICES_ID` | `HAS_HOST_SERVICES = false` | Link-plan capability gate for all host-backed services |
| `SERVICE_THREADS_ID` | `HAS_THREADS = false` | Thread model, synchronization primitives, host/thread runtime binding |
| `SERVICE_SECURE_RNG_ID` | `HAS_SECURE_RNG = false` | Entropy source, byte-buffer ABI, deterministic test policy |
| `SERVICE_GPU_ID` | `HAS_GPU = false` | Host GPU service ABI, device selection, queue/runtime binding |
| `SERVICE_PROCESS_ID` | `HAS_PROCESS = false` | Process arguments, exit, spawning, child status, host process binding |
| `SERVICE_ENV_ID` | `HAS_ENV = false` | Environment variables, current directory, host environment binding |
| `SERVICE_TEST_HARNESS_ID` | `HAS_TEST_HARNESS = false` | Test discovery, registration, execution, reporting, and harness runtime binding |

- `alloc/allocator.lani` has source-level allocator ABI declarations for
  allocation, growth, deallocation, and allocation failure hooks. It also
  exposes a narrow allocator service contract that reports the
  `SERVICE_ALLOCATOR_ID` descriptor as unavailable and requiring runtime
  binding in the active compiler slice. `ALLOCATOR_RUNTIME_ABI_VERSION`,
  `allocator_service_id()`, `allocator_service_status()`,
  `allocator_contract_metadata_is_available()`,
  `allocator_is_available()`, `allocator_is_blocked()`,
  `allocator_is_known_but_unbound()`,
  `allocator_requires_runtime_binding()`, and
  `allocator_host_abi_is_contract_only()` can type-check through
  `--stdlib-root` from an importing caller alongside `core::runtime`.
  Per-operation gates for `alloc`, `realloc`, `dealloc`, and `alloc_failed`
  expose executable, blocked, known-unbound, and runtime-binding status; every
  executable gate remains false, and every blocked/known-unbound/runtime-binding
  gate remains true until an allocator runtime exists. `AllocatorPointer`,
  `ALLOCATOR_POINTER_UNAVAILABLE`, `allocator_pointer_unavailable()`,
  `allocator_pointer_is_unavailable()`, `allocator_pointer_is_available()`,
  `allocation_result_is_fail_closed()`, `alloc_result_is_fail_closed()`, and
  `realloc_result_is_fail_closed()` provide a source-level null-pointer
  sentinel contract for unbound allocation results without making allocation
  executable. Direct extern signatures can type-check as calls in direct
  single-file fixtures, and bounded source-pack fixtures can type-check
  resolver-backed qualified calls such as `alloc::allocator::alloc(16, 4)` when
  the module is explicitly supplied. No quoted import loading, target runtime
  implementation, native linker integration, heap ownership model, allocator
  runtime, or backend lowering exists yet.
- `std/host.lani` exposes the aggregate host-service descriptor as an
  importable contract-only module. `HOST_SERVICES_SERVICE_ID` mirrors
  `core::runtime::SERVICE_HOST_SERVICES_ID`, `HOST_SERVICES_HAS_RUNTIME_BINDING`
  is false, and helpers such as
  `host_services_contract_metadata_is_available()`,
  `host_services_are_blocked()`,
  `host_services_require_runtime_binding()`,
  `host_services_requires_runtime_binding()`,
  `host_services_abi_is_contract_only()`,
  `host_services_api_is_executable()`, and
  `host_services_api_requires_runtime_binding()` can type-check through
  `--stdlib-root` from an importing caller alongside `core::runtime`. This file
  deliberately declares no raw host externs; it is a fail-closed descriptor gate
  for future host-backed services, not an executable runtime.
- `std/path.lani` exposes source-level byte classifiers for path separators,
  extension separators, drive separators, Windows drive-letter bytes, NUL
  component boundaries, ASCII control bytes, Windows-reserved component
  punctuation, `.`/`..` lexical component markers, root-separator and Windows
  drive-prefix components, lexically rooted and absolute path headers, Unix
  hidden components, and normal Unix-style and Windows-style relative component
  headers plus relative-component start/continue checks.
  `path_contract_metadata_is_available()` and
  `path_lexical_byte_helpers_are_available()` are pure frontend contracts that
  can type-check through `--stdlib-root`; path allocation and host
  normalization remain explicitly blocked through
  `path_allocation_api_is_blocked()`,
  `path_allocation_api_requires_allocator()`,
  `path_host_normalization_is_blocked()`, and
  `path_host_normalization_requires_runtime_binding()`. The
  `path_allocation_api_is_known_but_unbound()` and
  `path_host_normalization_is_known_but_unbound()` probes distinguish those
  recognized but non-executable path surfaces from unknown APIs. It does not
  allocate, normalize or canonicalize paths, access the filesystem, or bind
  host path services; `path_header_is_lexically_rooted()` and
  `path_header_is_absolute()` classify only the caller-supplied source bytes at
  the front of a path-shaped value. The absolute-header helper accepts Unix `/`
  roots and Windows drive roots such as `C:/` or `C:\`, while rejecting bare
  drive prefixes, Windows drive-relative headers such as `C:name`, and
  Windows root-relative `\name` headers.
- `std/io.lani` has source-level host I/O ABI declarations for stdin,
  stdout, stderr, flushing, and a minimal `print_i32` hook. It also exposes a
  narrow stdio service contract that reports the `SERVICE_STDIO_ID` descriptor
  as unavailable and requiring runtime binding in the active compiler slice.
  It exposes the current runtime ABI version and a local recognized-service
  predicate for that descriptor, matching the other host-service seeds.
  `stdio_output_api_is_executable()`,
  `stdio_output_api_requires_runtime_binding()`,
  `stdio_input_api_is_executable()`, and
  `stdio_input_api_requires_runtime_binding()` expose grouped fail-closed gates
  for the raw stdio extern sets. Per-operation probes such as
  `write_stdout_is_executable()`, `read_stdin_is_executable()`,
  `flush_stdout_is_executable()`, `print_i32_is_executable()`, and their
  `*_requires_runtime_binding()` companions route through those grouped gates.
  `stdio_is_known_but_unbound()`,
  `stdio_output_api_is_known_but_unbound()`,
  `stdio_input_api_is_known_but_unbound()`,
  `write_stdout_is_known_but_unbound()`,
  `write_stderr_is_known_but_unbound()`,
  `read_stdin_is_known_but_unbound()`,
  `flush_stdout_is_known_but_unbound()`,
  `flush_stderr_is_known_but_unbound()`, and
  `print_i32_is_known_but_unbound()` make the recognized-but-unbound stdio
  boundary explicit for source-level tooling. These probes remain
  contract-only until the stdio runtime service is bound. The x86 backend
  rejects direct calls to these extern declarations before producing target
  bytes, so source-pack stdio calls cannot silently compile into invalid native
  stubs.
  These extern signatures and contract helpers can type-check as calls in
  direct single-file fixtures, through `--stdlib-root` from an importing caller,
  and bounded source-pack fixtures can type-check resolver-backed qualified
  calls such as `std::io::flush_stdout()`,
  `std::io::print_i32(code)`, `std::io::print_i32_is_executable()`,
  `std::io::stdio_output_api_is_executable()`,
  `std::io::stdio_input_api_requires_runtime_binding()`,
  `std::io::print_i32_requires_runtime_binding()`, and
  `std::io::stdio_requires_runtime_binding()`
  when the module is explicitly supplied. No quoted import loading, host
  runtime, string/slice ABI, native/backend lowering, or executable stdio
  runtime binding exists yet.
- `std/process.lani` and `std/env.lani` seed source-level host ABI declarations
  for process args, exit codes, environment variables, and current-directory
  access. They also expose
  narrow process and environment service contracts that report the
  `SERVICE_PROCESS_ID` and `SERVICE_ENV_ID` descriptors as unavailable and
  requiring runtime binding in the active compiler slice. Both modules also
  expose the current runtime ABI version for their descriptors and local
  recognized-service predicates, and their contract helpers can type-check
  through `--stdlib-root` from an importing caller alongside `core::runtime`.
  `std/process.lani` additionally exposes public API gates for process
  arguments and exit-code hooks:
  `process_args_is_executable()`,
  `process_args_is_known_but_unbound()`,
  `process_args_requires_runtime_binding()`,
  `process_exit_is_executable()`,
  `process_exit_is_known_but_unbound()`, and
  `process_exit_requires_runtime_binding()` all report the current
  non-executable process-service boundary until a runtime binding exists.
  Per-operation probes such as `argc_is_known_but_unbound()`,
  `arg_len_is_known_but_unbound()`, `arg_read_is_known_but_unbound()`,
  `set_exit_code_is_known_but_unbound()`, and
  `exit_is_known_but_unbound()` expose the same recognized-but-unbound boundary
  without making the raw extern declarations executable.
  The same module exposes pure exit-status contracts:
  `EXIT_SUCCESS`, `EXIT_FAILURE`, `exit_success_code()`,
  `exit_failure_code()`, `exit_code_from_success(success)`,
  `exit_code_is_success(code)`, and `exit_code_is_failure(code)` are ordinary
  source-level helpers and do not imply that `set_exit_code` or `exit` are
  executable.
  `std/env.lani` additionally exposes fail-closed grouped environment-variable
  and current-directory gates:
  `env_is_known_but_unbound()`,
  `environment_variables_api_is_executable()`,
  `environment_variables_api_is_known_but_unbound()`,
  `environment_variables_api_requires_runtime_binding()`,
  `current_dir_api_is_executable()`,
  `current_dir_api_is_known_but_unbound()`,
  `current_dir_api_requires_runtime_binding()`,
  the shared `EnvReadResult` contract with `ENV_READ_UNAVAILABLE`,
  `env_read_unavailable()`, result success/failure classifiers, fail-closed
  result probes for environment-variable and current-directory read surfaces,
  and per-extern executable, blocked, known-but-unbound, and
  runtime-binding probes for `var_len`, `var_read`, `var_count`,
  `var_key_len`, `var_key_read`, `current_dir_len`, and `current_dir_read`.
  Their raw extern declarations can type-check in direct no-module fixtures,
  and the module files can type-check as explicitly supplied source-pack seeds. Stable string,
  byte-slice, error, broader executable capability, and runtime initialization
  models are still missing.
- `std/time.lani` seeds source-level host ABI declarations for clocks and
  sleeping. It also exposes a narrow clock service contract that reports the
  `SERVICE_CLOCK_ID` descriptor as unavailable and requiring runtime binding in
  the active compiler slice. The current runtime ABI version, local
  recognized-service predicate, service-status helper, service availability
  helper, service runtime-binding helper, and public API gate helpers such as
  `clock_is_known_but_unbound()`,
  `clock_read_api_is_executable()`,
  `clock_read_api_is_known_but_unbound()`,
  `clock_read_api_requires_runtime_binding()`,
  `clock_sleep_api_is_executable()`,
  `clock_sleep_api_is_known_but_unbound()`,
  `clock_sleep_api_requires_runtime_binding()`,
  `monotonic_now_ns_is_executable()`,
  `monotonic_now_ns_is_known_but_unbound()`,
  `monotonic_now_ns_requires_runtime_binding()`,
  `system_now_unix_ms_is_executable()`,
  `system_now_unix_ms_is_known_but_unbound()`,
  `system_now_unix_ms_requires_runtime_binding()`,
  `sleep_ms_is_executable()`,
  `sleep_ms_is_known_but_unbound()`, and
  `sleep_ms_requires_runtime_binding()` can
  type-check through `--stdlib-root` from an importing caller alongside
  `core::runtime`. `ClockReadResult` and `ClockSleepResult` name the current
  raw clock-return contracts: non-negative read values are successful
  nanosecond/millisecond timestamps, `CLOCK_READ_UNAVAILABLE` is the
  contract-only unavailable sentinel for clock reads, non-negative sleep values
  are successful sleep statuses, and `CLOCK_SLEEP_UNAVAILABLE` is the
  contract-only unavailable sentinel for sleeping. The
  `clock_read_result_is_fail_closed()` and
  `clock_sleep_result_is_fail_closed()` helpers keep callers from treating
  unbound clock APIs as executable host services. The raw extern declarations
  can type-check in direct
  no-module fixtures, and the module file can type-check as an explicitly
  supplied source-pack seed. Stable time representations, executable clock
  binding, native lowering, and host services remain future work.
- `std/fs.lani` seeds source-level host ABI declarations for basic file
  operations. It also exposes a narrow filesystem service contract that reports
  the `SERVICE_FILESYSTEM_ID` descriptor as unavailable and requiring runtime
  binding in the active compiler slice. The current runtime ABI version, local
  recognized-service predicate, and contract helpers can type-check through
  `--stdlib-root` from an importing caller alongside `core::runtime`. Its raw
  filesystem, file-I/O, and path-mutation gates expose explicit `*_is_blocked()`
  and grouped `*_is_known_but_unbound()` companions so callers can fail closed
  while distinguishing recognized contract-only filesystem APIs from unknown
  runtime services. File I/O declarations additionally expose per-operation
  executable, blocked, known-but-unbound, and runtime-binding gates for
  `open_read`, `open_write`, `open_append`, `close`, `read`, and `write`.
  Path-mutation declarations expose the same per-operation gates for
  `remove_file`, `create_dir`, `remove_dir`, and `rename`; all report
  non-executable, known-but-unbound, and requiring a runtime binding in this
  slice. `FilesystemOperationResult` names the signed result returned by file
  and path-mutation declarations; non-negative values are successful handles,
  byte counts, or zero-status results, while `FILESYSTEM_OPERATION_UNAVAILABLE`
  and `filesystem_operation_is_fail_closed()` provide the current
  contract-only unavailable sentinel for the unbound filesystem service.
  `FileHandle`, `FILE_HANDLE_INVALID`, `file_handle_invalid()`,
  `file_handle_is_valid()`, and `file_handle_is_invalid()` name the
  source-level handle-shaped result contract without making file opening
  executable. The extern declarations can type-check in direct no-module
  fixtures, and the module file can type-check as an explicitly supplied
  source-pack seed.
  Stable path/string/byte-slice representations, handle ownership, concrete
  error types, native lowering, and host services remain future work.
- `std/net.lani` seeds source-level host ABI declarations for basic TCP and UDP
  operations using opaque handles and raw pointer/length buffers. It also
  exposes a narrow network service contract that reports the
  `SERVICE_NETWORK_ID` descriptor as unavailable and requiring runtime binding
  in the active compiler slice. It exposes the current runtime ABI version and
  a local recognized-service predicate for the descriptor.
  `network_contract_metadata_is_available()` is descriptor metadata only, and
  `network_host_abi_is_contract_only()` keeps the raw socket ABI visibly
  non-executable. Its contract helpers can type-check through `--stdlib-root`
  from an importing caller alongside `core::runtime`, including
  known-but-unbound probes for the network service plus TCP and UDP API
  families and operations. TCP declarations expose
  per-operation gates for `tcp_connect`, `tcp_bind`, `tcp_listen`,
  `tcp_accept`, `tcp_close`, `tcp_send`, and `tcp_recv`, and UDP declarations
  expose per-operation gates for `udp_bind`, `udp_send_to`, and
  `udp_recv_from`; all report non-executable and requiring a runtime binding
  in this slice. UDP send/receive use an opaque endpoint descriptor pointer
  plus payload pointer/length so imported public calls stay within the current
  source-pack type-checkable call shape. Its raw extern declarations can
  type-check in direct no-module fixtures, and the module file can type-check
  as an explicitly supplied source-pack seed. Stable socket
  address types, explicit endpoint layouts, DNS, blocking mode, error reporting, executable runtime
  binding, native lowering, and host services remain future work.
- `std/random.lani` seeds source-level secure-RNG host ABI declarations for
  filling caller-provided bytes and returning one `u32`. It reports the
  `SERVICE_SECURE_RNG_ID` descriptor as unavailable, exposes
  `random_contract_metadata_is_available()` as descriptor metadata only, and
  exposes `random_host_abi_is_contract_only()` plus per-operation blocked and
  runtime-binding gates for `fill_secure_bytes` and `secure_u32`.
  `random_is_known_but_unbound()`,
  `secure_rng_api_is_known_but_unbound()`,
  `fill_secure_bytes_is_known_but_unbound()`, and
  `secure_u32_is_known_but_unbound()` distinguish the recognized secure-RNG
  descriptor and APIs from executable entropy support. These helpers can
  type-check through `--stdlib-root` from an importing caller alongside
  `core::runtime`. `RandomOperationResult` names the signed status returned by
  `fill_secure_bytes`; non-negative values are successful byte counts or
  zero-status results, while `RANDOM_OPERATION_UNAVAILABLE` and
  `random_operation_is_fail_closed()` provide the contract-only unavailable
  sentinel. The raw entropy extern declarations remain non-executable until a
  secure entropy runtime binding exists.
- `std/gpu.lani` seeds source-level GPU host-service declarations for buffer
  allocation, buffer I/O, and one-dimensional dispatch. It reports the
  `SERVICE_GPU_ID` descriptor as unavailable, exposes
  `gpu_contract_metadata_is_available()` as descriptor metadata only, and
  exposes `gpu_host_abi_is_contract_only()` plus blocked and runtime-binding
  gates for GPU buffer and dispatch API families. Per-operation probes for
  `buffer_alloc`, `buffer_free`, `buffer_write`, `buffer_read`, and
  `dispatch_1d` route through those grouped gates so callers can fail closed at
  the exact operation they intend to use. `GpuOperationResult`,
  `GPU_OPERATION_UNAVAILABLE`, and `gpu_operation_is_fail_closed(result)` name
  the signed status contract for `buffer_free`, `buffer_write`, `buffer_read`,
  and `dispatch_1d`: non-negative values are success results, and the
  unavailable sentinel is fail-closed while the GPU service remains known but
  unbound. These helpers can type-check through
  `--stdlib-root` from an importing caller alongside `core::runtime`, but the
  raw GPU host-service extern declarations remain non-executable until a GPU
  runtime binding defines resource ownership and dispatch ABI semantics.
- `std/thread.lani` seeds source-level host ABI declarations for spawning,
  joining, yielding, and querying the current thread id. It reports the
  `SERVICE_THREADS_ID` descriptor as unavailable, exposes
  `thread_contract_metadata_is_available()` as descriptor metadata only, and
  exposes `thread_host_abi_is_contract_only()` plus per-operation blocked and
  runtime-binding gates so raw thread extern declarations remain visibly
  non-executable until a thread runtime binding exists.
  `thread_is_known_but_unbound()`,
  `thread_spawn_is_known_but_unbound()`,
  `thread_join_is_known_but_unbound()`,
  `thread_yield_is_known_but_unbound()`, and
  `thread_current_id_is_known_but_unbound()` distinguish the recognized thread
  descriptor and APIs from executable thread support.
  `ThreadOperationResult`, `THREAD_OPERATION_OK`,
  `THREAD_OPERATION_UNAVAILABLE`, and
  `thread_operation_is_fail_closed(result)` name the current signed result
  contract for these unbound calls: non-negative values are successful
  handles/statuses, and the unavailable sentinel is fail-closed while the
  thread service remains known but unbound.
- `test/harness.lani` exposes the test-harness runtime descriptor as
  contract-only source metadata. `TEST_HARNESS_SERVICE_ID` mirrors
  `core::runtime::SERVICE_TEST_HARNESS_ID`, and registration, discovery, and
  execution gates all report blocked/requiring runtime binding until a real
  harness runtime exists. `test_harness_is_known_but_unbound()`,
  `test_registration_is_known_but_unbound()`,
  `test_discovery_is_known_but_unbound()`, and
  `test_execution_is_known_but_unbound()` expose that recognized contract-only
  boundary for diagnostics without implying execution. It also exposes
  source-level `TestHarnessStatus` values for passed, failed, and skipped test
  outcomes plus classifiers such as `test_status_is_known(status)`,
  `test_status_is_success(status)`, and `test_status_is_failure(status)`, so
  test-like code can type-check outcome handling before a real harness exists.
  It declares no raw host externs and does not run tests.
- `test/assert.lani` has source-level assertion helpers built on the current
  `assert(bool)` builtin. It type-checks as an explicitly supplied source-pack
  seed, but assertion-helper WASM execution is not active while the legacy tests
  are ignored. Importing it automatically remains blocked until a real package
  model exists. A real test harness, formatted assertion messages, source
  locations, and panic reporting are not implemented yet.
- `i32.lani`, `bool.lani`, and `array_i32_4.lani` keep the older `lstd_`
  compatibility helpers. The flat `i32.lani` and `bool.lani` seeds type-check
  as direct single-file GPU inputs. The flat `array_i32_4.lani` seed also
  type-checks directly, and `core/array_i32_4.lani` type-checks as an explicit
  source-pack module seed. Const-generic array parameters have limited frontend
  coverage for `[i32; N]`; generic array APIs and backend lowering for
  array-returning helpers are still incomplete. Array-helper WASM execution is
  not active while the legacy full-source-pack tests are ignored.

Import declarations remain explicit metadata: path imports resolve only for
already supplied source-pack modules, and quoted import loading is not
implemented. Leading `module path;` headers can flow through the GPU
module/import resolver. Same-module/source-pack qualified struct/enum type
paths, regular/extern qualified function calls, top-level qualified constants,
local or qualified unit enum variants, and bounded contextual local or qualified
generic enum constructors can type-check through resolver arrays, but general
qualified value paths and symbolic/generic-return enum constructors are still
rejected.
Bounded module-qualified generic calls have source-pack type-check coverage only
for stdlib-shaped scalar/literal argument inference; this is not full
monomorphization or backend specialization.
The old source-level include expander and namespace rewrite were
removed with the CPU prepass. A real module/package model must still be
implemented on the GPU-compatible frontend path before quoted imports,
automatic package loading, or broad `core::*` lookup can be counted as
supported.
