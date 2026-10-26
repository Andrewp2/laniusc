# Executable compiler generics checkpoint

The GPU compiler specializes ordinary Lanius generic bodies using checked
type references and native layouts. `Option<T>` and `Result<T, E>` use this
same mechanism. Execution below is x86_64 Linux ELF emitted by the GPU
compiler; user-program GPU execution is not established.

## Bound-directed generic call inference (2026-10-26)

A call can leave a type parameter that no argument mentions, such as `T` in
`core::iter::enumerate_from<I, T>(source: &I, ...) where I: Iterator<T>`.
The type checker now infers it from the callee's bounds:

- Take a bound `P: Tr<A1..An>` of the callee where `P` is already bound to a
  closed type (by an explicit argument, an argument claim or receiving
  context).
- Count the implementations of `Tr` whose subject matches that type. These
  come from every dependency page and from this unit.
- If exactly one matches, substitute its own parameters into its trait
  arguments; they must come out closed. Then match `A1..An` against them, and
  publish the bindings as the call's context.
- Zero or several matches bind nothing, so the call keeps its existing
  diagnostic (LNC0006 for an unbound parameter).
- No conversion is ever applied. Every slot the call already binds must agree
  with the inferred type; any disagreement drops the whole publication, and a
  contradicting binding is still rejected (LNC0008).

The rule runs in every call-inference round. A binding inferred for one call
can type a `let` that feeds the next call, so chains settle over rounds. For
example, `enumerate_from`, `map` and `try_transfer_up_to` in
`sample_programs/library/index_words.lani` all infer without turbofish.

The kernels are in `shaders/type_checker/calls/`:

| Kernel | Job |
| --- | --- |
| `03l0` | Clears the tables in `bound_tables.slang` each round. |
| `03l1` | Collects implementation and free-function bound rows from each resident dependency page. |
| `03l2` | Collects this unit's implementations of imported traits. |
| `03l3` | Infers, one lane per call. |

Limits of this first version:

- Only calls of imported free functions use the rule. Method calls and calls
  of local generic functions do not.
- The bound's subject must be one of the callee's own type parameters, with
  1 to 7 trait arguments.
- `P`'s binding must be closed, so a call inside a generic body whose `P` is
  still a parameter infers nothing.
- Implementation `where` clauses are not consulted when counting. A clause
  can't add a candidate; it can only make a unique match fail later, when
  program evidence validates the selected implementation.
- An implementation whose header has no canonical ID matches every subject,
  so it can only make a selection ambiguous.
- Implementations of local traits are not collected, since an imported
  callee can't name them.
- If either table overflows (16384 rows), nothing is inferred.

Tests: the `bound_*` fixtures in `tests/fixtures/language/`, run by
`tests/language_ergonomics_execution.rs`.

## `core::mem::size_of<T>()` (2026-10-15, implemented 2026-10-18)

Generic heap-backed containers (the 36 allocating `vec_*`, `set_*`, `map_*`
and `deque_*` modules, backlog b10, now matrix p52) have to size an
allocation for `capacity` elements of `T`, then view it as `[T]`. core::mem
provides `size_of<T>() -> usize` and `typed_slice_from_storage<T>(storage:
ptr, length: i32) -> [T]` for this.

**`size_of<T>()` is the storage size for allocation, not C's `sizeof`.** It
returns the number of bytes one `T` takes in raw storage on this target: the
size of the stride that `core::mem::typed_slice_from_raw_parts<T>` uses. An
alignment of 8 is enough for every `T`.

| `T` | `size_of<T>()` |
| --- | --- |
| `i32` | 4 (packed) |
| `u8` | 1 (packed bytes) |
| zero-sized types | 0 |
| any other `T` | 8 × native words of `T` |

The last row covers `u32`, `i64`, `bool`, `char` and `ptr`, which are all 8
bytes. It also covers records, enums, slices (24), strings (16), and arrays
`[T; N]`, which are 8 × N × words(T). This is not the C or Rust size. It is the
layout raw views use on this target, so it is the right number to allocate
with.

`size_of` is a runtime value. It is not a constant expression, so it cannot be
an array length or a const generic argument. Only the native layout knows the
size, and the type checker runs before the native layout. A call type-checks
with `T` abstract and always has type `usize`. Each instance of the enclosing
body has a concrete `T`, whether it comes from an A2 replay or a D′ copy. A
body that is never instantiated is never lowered, so it never asks for a size.
Making `size_of` a constant expression is a possible later extension, once
the type checker can see native layouts.

A raw view of a type whose words descend needs its element-zero pointer to
start `length * size_of<T>() - 8` bytes above the lowest address of its
storage. The packed i32 and u8 views start at the lowest address. Generic code
cannot tell the two apart, so `typed_slice_from_storage` views `length`
elements stored in `[storage, storage + length * size_of<T>())`, whatever the
direction. Every view of one storage must use the same length to agree on
where element i is. A generic container needs only these calls:

```
let bytes: usize = core::mem::size_of<T>() * (capacity as usize);
let storage: ptr = alloc::allocator::alloc(bytes, 8);
let items: [T] = core::mem::typed_slice_from_storage(storage, capacity);
```

Implementation:
- One intrinsic, `core::mem::slice_stride(view) -> isize` (intrinsic tag 8,
  language symbol 73). It returns a view's signed byte stride, the third word
  of its descriptor: +4, +1, 0, or -8 × words. On x86 the argument's words
  arrive in RDI, RSI and RDX, and the call moves RDX into its result
  (`X86_LIR_OP_INTRINSIC_IDENTITY` with operand a = 2). Wasm reports it
  unsupported.
- `size_of` and `typed_slice_from_storage` are ordinary generic functions in
  core::mem. Each builds an empty raw view with the raw-parts intrinsic,
  `slice_from_raw_parts(0, 0)` into a `[T]` local, and reads its stride. The
  raw view constructor already closes T's layout in every instance
  (materialize, `concrete_type_ref_words`), so no type argument has to reach
  lowering. The stride is an immediate in the instance's code; a call costs a
  few instructions. They call the intrinsic, not the generic
  `typed_slice_from_raw_parts`: a replay of one core::mem body carries its
  generic siblings' calls, and a sibling's call to that generic wrapper has no
  emitted definition (LNC0017).
- A body whose signature and locals are concrete can still pass its own `T`
  on, as `fn bytes<T>() -> i32 { return core::mem::size_of<T>() as i32; }`
  does. It used to be emitted once as a tag-only definition, so the callee was
  never instantiated and the link failed with LNC0017. The checked call record
  now has `symbolic_type_environment`: generic_call_results
  (`semantic/artifact/00c`) sets it when an accepted type argument of the call
  is still open in this run, either a lexical parameter or an instance that
  the closure walker cannot close. It reads the call's contextual arguments
  from `call_context_*` and its explicit ones from the source-owned explicit
  environment (`checked_explicit_environment_argument`), because
  `03a8_validate_explicit_applications` copies the explicit arguments into
  `call_context_*` only after 00c has run. `function_templates` keeps a body
  with such a call as a template, outside a replay and only inside a generic
  environment, so the body's replay requests the callee. A replay ignores the
  flag. Not covered yet: a symbolic environment that comes only from a
  value argument's claim in a body that is otherwise closed, and symbolic
  constant arguments (`f<N>()`).
- Probes: sizes for i32, u8, u32, a record, `[i32; 3]`, `[i32]`, `str`, a
  zero-sized record and bool from one generic body; two-deep generic calls;
  generic push/get buffers over i32, u8 and a record; and a guarded
  three-element view inside five-element storage
  (tests/fixtures/stdlib_foundation/core_mem_size_of.lani).

## Recursive by-value types (2026-10-18)

A struct or enum that contains itself by value has no finite size. Type
checking now rejects it with LNC0006 "type mismatch", labelled "recursive type
has infinite size" at the declaration's name. Rejected cases include:
- `struct Payload { next: Payload }`
- mutual recursion: `struct A { b: B }` with `struct B { a: A }`
- recursion through a fixed array: `struct Outer { inner: [Inner; 2] }` with
  `struct Inner { outer: Outer }`
- `enum Recursive { Stop, Again(Recursive) }`

Before this, `core::option::Option<Payload>` over the first case reached x86
and failed there with LNC0017 "x86 callee function lost its checked aggregate
result layout".

The check is part of the native layout walker,
`type_checker/semantic/artifact/01c_generic_native_words`. It fires when a node
is its own child or a walk returns to its root. It reports GPU type-check status
28 (`RecursiveType`) at the local struct or enum declaration. A slice
(`rest: [Cell]`) or a reference still breaks the cycle.

Gap: only types whose layout is computed are checked. An uninstantiated generic
declaration such as `struct Node<T> { value: T, next: Node<T> }` is still
accepted.

## Canonical type boundary and startup checkpoint (2026-10-11)

Canonical hash, constraint, and match traversal now use a type-only leaf
resolver. Constant operands and array lengths retain their separate complete
checks. A type parameter rejects source and canonical constant replacements;
failure preserves any inference outputs already written. The general resolver
used by materialization retains its constant conversion behavior.

Build 36 succeeds with 850 shaders under the unchanged 524,288-byte limit.
The direct leaf test executes 22 cases on the physical GPU, covering valid
source/canonical replacements, one-step substitution, and malformed domains.
The broader constraint test times out during pipeline creation before dispatch.
Nested identity and the added 63/64-projection terminal cases are not yet
established by execution. Open canonical replacement scope across complete
walkers also remains unverified; leaf admission alone does not prove it.

Earlier partitioned constant-identity runs passed the scoped, depth, and array
constraint groups. The other five groups stopped at pipeline creation. Their
ordered helper calls have since been consolidated without removing assertions;
these changed fixtures still need execution. Production canonical constant
constraints likewise share direct/projected terminal calls and retain the exact
64-visit limit.

The production claims pipeline still exceeds 100 seconds after these changes.
A separate non-inlining SPIR-V simplification experiment also timed out, despite
producing a smaller valid artifact. Neither establishes startup or throughput
acceptance. Recorded builds, failures, and independently hashed source/shader
snapshots are in `tests/fixtures/stdlib_compiler_state/canonical-type-startup/`.
The release loader currently reads shader artifact files, so a binary hash alone
does not identify the executed shaders. Required-member and method-own generic
integration remains separate, unfinished work.

## Typed constant integration checkpoint (2026-10-11)

The combined typed-constant, floating-context, range, and workspace-reuse
changes build successfully. All 840 shader artifacts pass the unchanged
524,288-byte limit. This establishes a buildable integration, not complete
generics or source-program acceptance.

Ten host contract tests and five physical GPU tests pass. They cover complete
typed values and independent array-count projection (4,518 GPU cases), packet
transport, allocation partitions, layout readback, publication-header rejection,
exclusive workspace reuse, and readback recovery after errors and unwinding.
Typed constant matching also passes. The grouped matching/overlap run then
timed out, so it is not recorded as a passing test command.

The isolated overlap test initially exceeded 90 seconds while creating its GPU
pipeline. Sharing its ordered matcher call site preserves all thirteen cases
and assertions; that version passes, with pipeline creation taking 28.9 seconds.
It includes capturing a compound type containing a projected count and revisiting
that binding against the equivalent rigid count. This is a focused startup
result, not a compiler throughput benchmark.

Native source acceptance, the remaining publication and composition checks,
required-member execution, and refreshed performance acceptance remain open.
Two native typed-operands runs timed out during pipeline initialization, before
source execution. The second trace records 374 completed pipelines and two still
being created: `type_checker/calls/03a1_emit_generic_claims` and
`codegen/lir/semantic/aggregate_elements`.
Evidence, failures, and separate build/source/artifact hashes are recorded in
`tests/fixtures/stdlib_compiler_state/typed-constant-build-checkpoint/`.

## Floating payload checkpoint (2026-10-11)

The physical GPU decimal converter passes 841 independent bit/status/bounds
cases. Six native programs execute f32/f64 arithmetic, literal contexts, nested
record/Option/Result/array payloads, imported mixed-width stack arguments, and
portable literal/unary constants. Five explicit float rejection tests and four
integer controls also pass. Neither decimal conversion shader requires Float64.

One Option<f64> fallback context after a generic return still fails to compile;
complete floating payload support is not established. Computed IEEE constants
remain explicitly rejected. Evidence in
`tests/fixtures/stdlib_compiler_state/float-payloads-checkpoint/` records the
passing and failing runs and their separate builds. This checkpoint predates
typed generic constant integration and has no refreshed performance acceptance.

## Reachable instruction ownership (2026-10-11)

The optimizer and native lowering now share the validated CFG reachability
contract. Unreachable instructions contribute no executable access rows, SSA
definitions, aliases, operands, uses, or native instructions. Their source rows
remain available for provenance; reachable uses of unavailable definitions still
reject.

Thirteen native execution checks pass on one recorded build. These include the
four formerly failing direct/named early-return range cases, dead calls and
aggregates after return, two continue controls, the original named range program,
wide and empty/inclusive ranges, endpoint snapshots, and the imported numeric
program. Evidence is in `tests/fixtures/stdlib_compiler_state/range-executable-owners/`.
Full-range break dominance and combined postfix endpoints remain unresolved.
This checkpoint predates float integration and has no refreshed performance or
Wasm runtime acceptance.

## GPU layouts from accepted proof terms (2026-10-11)

The GPU now materializes tested nested record, enum, array, reference, slice, and
zero-sized layouts from admitted symbolic definition recipes. Three physical GPU
tests verify complete semantic graphs and widths, binding with nonconsecutive
source parameter identities, explicit capacity/lexical-ownership failures, and
recovery. Two host planner checks and four GPU lowering controls also pass.
Evidence and per-build source hashes are in
`tests/fixtures/stdlib_compiler_state/proof-term-layouts/`.

The returned type and GPU-computed width grant no call or replay authority.
Connecting this engine to abstract required-member routing remains unfinished.
Its first pipeline creation took 31.843 seconds; the recorded artifact uses the
existing minimum-optimization policy and is 255,704 bytes. No current warm
throughput, cold-start acceptance, or complete-generics claim follows from these
component tests. The earlier prerequisite checkpoint below retains its own
historical evidence and narrower scope.

## Semantic replay and native layout prerequisites (2026-10-11)

Closed semantic arguments can enter body replay before every compound native
width is known. Missing width and known zero remain distinct. The GPU completes
the tested local nominal and array layouts before native publication. References
and slices can pass their descriptors while an opaque referent's width remains
unknown; their complete semantic referent identity is preserved.

The native body cache keeps the completed GPU width vector, so a later
conflicting known witness cannot reuse a body compiled from an unknown input
width. Semantic specialization identity does not depend on width availability.
Public and private nominal definitions also retain their original ordered field
and enum-variant payload graphs, even when no call or predicate uses them. Replay
shares those immutable symbolic recipes with exact unit and owner identity.

The GPU also admits retained nominal recipes against the exact catalog epoch,
nominal owner, ordered payload groups, and lexical parameter identities. Fault
cases reject stale epochs, broken group ownership, and sibling parameters used
outside their scope; a fresh valid catalog recovers. This establishes recipe
admission, while the foreign missing-layout consumer remains unfinished.

Build 19 passed eight selected checks: four host contracts, one GPU replay/layout
readback test, and three native execution tests. Build 20 passed six: two GPU
layout edge checks, two recipe-retention checks, and two native regressions. One
native test repeats across builds. Build 23 adds two host transport checks, one
GPU admission fault/recovery test, and two native controls. Together these are
19 passing executions covering 17 distinct tests. Each run records its own
binary and source snapshot in
`tests/fixtures/stdlib_compiler_state/semantic-replay-layouts/`.
The GPU readback/admission tests are separate from emitted-program execution
and do not establish arbitrary foreign layout materialization.

GPU library tests used recorded per-build hardlinks under the native-test
basename to reuse the previously observed cache condition. No new driver-cache
trace or cold/large-workload performance acceptance is claimed. Applying retained
recipes to an actual foreign nominal with no width witness remains in progress,
as does abstract required-member routing through `T: Trait`. These prerequisites
do not complete general generics or refresh the full stdlib acceptance gate.

## Direct generic trait implementation methods (2026-10-11)

Direct calls to local and imported generic trait implementation methods now
execute. Tested methods inherit type and constant parameters from their impl,
use caller-supplied prerequisite implementations, and preserve compound results
at different array lengths and native layouts. Inherent methods also execute
with their own bounds, enclosing impl bounds, and shadowed parameter names.

Thirteen focused checks pass on the recorded Stage A build: four native execution
tests, four native rejection tests, four strict-interface tests, and one host
contract test. Missing prerequisites and invalid target/visibility contracts
reject explicitly. Strict checking walks the exact method-to-impl owner chain;
it does not rely on native program admission to repair a missing obligation.
Evidence: `tests/fixtures/stdlib_compiler_state/generic-trait-methods/verification.json`.

The ordinary strict-test invocation exceeded its 85-second initialization
watchdog. The four strict checks passed using a hardlink of the identical module
binary under the native test's basename; traces show it opening the native test's
NVIDIA cache leaf. That cache condition and the unresolved startup limit are
recorded with the evidence. These are correctness results, not refreshed cold,
large-workload, or cross-compiler performance acceptance.

Abstract member calls through `T: Trait` are implemented only for the cases in
[bound-member calls](#bound-member-calls-through-t-trait-2026-10-14) below.
Trait methods' own generic headers and own `where` clauses remain unfinished and
still reject explicitly. Direct generic impl methods do not establish broader
required-member routing. Complete primitive widths/floating point, full-width
constant identity and forwarding, durable file-backed native publication, and
the full stdlib acceptance gate also remain open.

## Bound-member calls through `T: Trait` (2026-10-14)

A dotted call whose receiver type is a lexical type parameter `P` (directly or
behind references) now resolves when an accepted predicate `P: Trait` of the
call's enclosing generic scopes declares a member of that name.
`methods/07a_offer_bound_members` joins the published predicate tables: the owner
lookup, the subject's parameter row, the trait reference and the member
contracts. It offers the required member as a local candidate in every method
selection stage, at the receiver's dereference rank. Ordinary ranking, ambiguity
and unresolved-method rejection still apply. Required members publish signature
metadata (name, receiver mode, parameter offset) but no method row, so they never
enter receiver lookup. The early predicate passes now run before scope
resolution, so their tables exist when method selection runs.

The generic body stays a template. Codegen defers a body that has a call whose
receiver parameter is still `P`. A trait's own member is a contract over `Self`
and never becomes a native definition. Body replay substitutes each call's
accepted receiver and parameter types. `methods/09_route_bound_members` then
routes the call to the implementation member of the bounding trait whose closed
receiver pattern equals the concrete receiver. It updates the accepted candidate
and the callee together, so call artifacts read one fact.

Limits:
- Only local traits without arguments. Only dotted calls of `self` and `&self`
  members. Only non-generic local implementations.
- Imported traits and traits with arguments offer no bound member. They keep the
  ordinary unresolved-method rejection.
- A generic implementation (`impl<U> Read for Box<U>`) needs its own call
  environment, which symbolic selection cannot produce. Such calls reject with
  LNC0027 ("no concrete implementation member to route to"). So do imported
  implementations and receivers with no matching implementation.
- Static members and explicitly typed `self` members are invalid candidates.

Evidence:
- Generics-matrix p12 and focused probes now execute. Tested programs: by-value
  `self` with two calls in one body, `&self`, and a scalar `impl Twice for i32`.
  The generic implementation rejects as described above.
- `generic_bound_member_calls_*` in `tests/compiler_generic_types_execution.rs`
  covers these cases.
- Two related programs still time out in the call-inference loop, as
  generics-matrix p04 and p14 do: a `&T` receiver, and two instantiations of one
  bounded function. For p04 the hanging kernel is
  `calls/03e1_expand_application_fields`. A control with two instantiations and
  no trait times out the same way, so this is not a routing failure.

## Conditional and blanket implementations (2026-10-11)

The focused marker-trait programs now execute. Local and imported conditional
implementations prove nested `Cell<T>` and array requirements, including a base
implementation supplied by the caller. A blanket `impl<T> Mark for T` executes
over scalars, arrays, and generic structs. Overlapping heads, missing base proofs,
and recursive prerequisites without a base reject before ELF publication.

The current build passes five native execution/rejection tests, two GPU-backed
owner-retention tests, and one physical-GPU matcher test containing 32 cases.
Earlier runs during this integration passed three GPU proof-packet tests and
eight host replay/publication tests: 19 distinct selected tests in total. The
records identify each run's binary, sources, and shaders; the earlier runs used
different builds. See
`tests/fixtures/stdlib_compiler_state/generic-implementation-proofs/verification.json`.

Accepted implementation bounds retain their exact declaration parameters.
Unnamed implementations use source-token anchors consistently across generic
lookup and arity readers. Replay checks all calls through the same whole-program
selection boundary as original admission; unchanged ordinary siblings must
still equal their previously admitted facts. A later target check no longer
rejects a parameter root already accepted by the full implementation-head check.

The combined matcher test exceeded 100 seconds while creating its GPU pipeline.
Four operation-family pipelines preserve all 32 cases and complete within that
limit; the slowest measured 32.154 seconds for pipeline creation. Production
proof-validation pipelines still have substantial cold costs. Large-workload,
scaling, and cross-compiler performance acceptance have not been refreshed for
this integration; older benchmark results below describe their own snapshots.

The later direct-method checkpoint above adds execution evidence for generic
trait impl methods and inherent method bounds. Abstract trait-member routing,
complete primitive widths and floating-point support, full-width typed constant
identity/forwarding, durable file-backed native publication, and the full stdlib
acceptance gate remain open. Prepared scratch patches are not execution evidence.

## Structural receivers and native storage (2026-10-11)

Local and imported inherent methods now execute on the tested arrays, slices,
references, and nested nominal compositions. Callee parameters retain full
checked types, including unused implicit receivers. This fixes mismatched
argument widths and incorrect array copies. Reference values keep one-word
shape even when their referents carry runtime bounds; borrowed array views
retain their original storage. Nested receiver calls keep distinct callees.

The final structural suite passes all eleven native execution tests. Seven
additional native generic composition/call-chain tests passed during integration,
including local/imported 32-parameter cases. The two physical-GPU library checks
cover parameter records and imported ambiguity across dependency-page orders
and workspace reuse. Three host checks cover graph inputs and resource lifetimes.
The evidence records the exact source/shader version for each run:
`tests/fixtures/stdlib_compiler_state/structural-native-places/verification.json`.

The existing 1 MB workload measured 38.474 ms median compiler time; all twenty
emitted programs produced the expected output. Paired warm comparisons against
the preceding sibling-method checkpoint measured 2.6% overhead for the 32-operand
trait workload and 2.4% for the ordinary 32-parameter program. See the
[performance evidence](stdlib-gpu-performance.md#structural-receivers-and-native-storage-2026-10-11).

General generics remain unfinished: generic trait implementation prerequisites,
generic trait methods and method bounds, full primitive widths, and full-width
constant identity/forwarding still need implementation and execution evidence.
Direct temporary borrows and variant-payload places without a storage recipe
remain explicit boundaries. References still require caller-managed lifetimes;
this checkpoint does not add static escape checking.

## Generic sibling method emission (2026-10-11)

Specializing one method now emits that selected generic body and ordinary local
helpers. Other generic bodies remain templates, including methods that inherit
only constant parameters from their impl. Native eligibility and direct-call
selection share the same complete lexical-parameter classification.

Before a replay object is released, its definitions and native call owners must
belong to permitted callables in the frozen source unit. Ownership is retained
for ordinary imported calls as well as generic calls. Only omitted generic
templates may recover their original call facts; selected facts remain fresh,
and ordinary helpers must retain their original facts exactly.

All 29 focused checks pass: eleven native integration tests, two library tests
using the physical GPU, and sixteen host tests. Native cases include the original
sibling failure, local helpers that call generic functions, ordinary imported
helpers, independent method
parameters, constant-only impls at two array lengths, workspace reuse, and the
preceding caller-evidence cases. Four host fault tests exercise the publication
gate. The workspace-reset check executes both scalar variants through the real
scheduler, then compares the next ordinary object with the original, including
an uncalled generic marker that replay must omit. Evidence is under
`tests/fixtures/stdlib_compiler_state/program-native-replay/sibling-verification.json`.
Both changed shader artifacts pass SPIR-V validation.

An older test manually linked only one specialization while its program needed
two. It failed before reaching its reset assertion; the preserved prior binary
hit the 90-second limit, so an identical historical failure is not established.
The updated test retains its runtime edge cases and strengthens the reset check.

The existing warm performance workloads measured -2.5% for trait operands and
-14.2% for the ordinary 32-parameter program against the preceding checkpoint;
see the [measurement limits](stdlib-gpu-performance.md#selected-generic-body-emission-2026-10-11).

General generics remain unfinished. Generic implementations with prerequisites,
generic trait methods and method bounds, constant trait operands, and structural
reference-target methods still need implementation and executable evidence.
Fresh composition probes verify pointer-containing slices and reproduce the
structural-reference rejection and an ordinary wide-integer literal failure;
see `tests/fixtures/stdlib_compiler_state/generic-completion-audit/README.md`.

## Native caller evidence (2026-10-11)

Imported generic bodies now use implementations selected from the caller's
program. The original failing example, nested forwarding at distinct types and
array lengths, existing body reuse, and missing-bound rejection pass executable
tests. A private replay request ties body compilation to its accepted call;
generated objects remain private until fresh calls pass the program check.

Twenty distinct focused checks pass: eight native execution tests, one physical
GPU retention test, and eleven host ownership/cache/diagnostic tests. Full records
are in `tests/fixtures/stdlib_compiler_state/program-native-replay/`; see the
[contract and remaining limitations](compiler-implementation-evidence-plan.md#native-caller-evidence-executable-checkpoint-2026-10-11).
The existing warm performance workloads measured 7.8% and 7.4% overhead against
the immediately preceding implementation. These measurements do not establish
the 1 MB or cross-compiler performance targets.

The later sibling-method checkpoint above resolves the changed-sibling-facts
rejection from this checkpoint. Generic implementation prerequisites, generic
trait methods, method where clauses, constant trait operands, and broader
type/reference coverage still need implementation and executable evidence.

## Complete callable ownership (2026-10-10)

Checked units now retain every accepted executable function and method, including
nongeneric callers such as `main`. Each callable keeps the native identity emitted
by the shared symbol producer. Methods retain their exact enclosing `impl`, even
when that implementation has no generic parameters. Trait requirements remain
separate from executable bodies. Pruning ordinary imported calls also prunes their
owner rows, preserving an exact call-to-owner inventory.

**All 25 selected checks pass:** 20 library checks and five native integration
tests. They cover ordinary imported callers, public/private methods, nongeneric
implementation parents, workspace reuse after richer units, imported contracts,
and independent type/constant domains. Local and imported references to the same
native generic body now share one specialization key; different units and complete
type/constant environments remain distinct.

The existing performance harness measured 77.310 ms versus 73.505 ms for the
32-operand trait workload (+5.2%), and 265.510 ms versus 262.403 ms for the ordinary
32-parameter program (+1.2%). All eight executable output checks pass. These are
focused warm observations with run-to-run variation; see the
[performance notes](stdlib-gpu-performance.md#complete-callable-ownership-2026-10-10).
Evidence: `tests/fixtures/stdlib_compiler_state/complete-callable-owners/verification.json`.

This checkpoint completed callable ownership for the program catalog. The later
native caller-evidence checkpoint above resolves the imported-body reproduction.

## Parameter identity in shared graph operations (2026-10-10)

Shared scoped hash/equality now pass the original parameter reference to the
adapter before substitution. The replacement keeps its caller scope throughout
the returned subtree. Type and constant parameter domains are validated
independently, including unbound constant leaves. A nominal application permits
32 ordered operands independently of the number of allocated graph nodes.

**All 18 selected checks pass:** four library checks and 14 native integration
tests. A physical GPU probe exercises distinct binders sharing slot zero,
one-time substitution through compound replacements, invalid/wrong-domain
parameters, 32 operands in one node, and 32 independent compound roots. Native
checks cover nested generic types, separate type/constant domains, imported
contracts, method signatures, and rejection of wrong bindings.

The source adapters retain their existing slot and environment policies. This
change supplies an identity-aware interface for the forthcoming owned packet
adapter; it does not make every existing source lookup owner-aware. The existing
walkers retain depth 64 and have no visit budget. The packet consumer still needs
complete admission with explicit per-root work limits.

Evidence: `tests/fixtures/stdlib_compiler_state/parameter-scoped-graphs/verification.json`.
Warm comparisons with the exact previous checkpoint measured 71.322 ms versus
72.397 ms for the trait workload, and 265.803 ms versus 380.246 ms for the ordinary
32-parameter program. All eight benchmark executable checks pass. See the
[measurement limits](stdlib-gpu-performance.md#parameter-identity-in-shared-graph-operations-2026-10-10).
Program catalog selection and proof forwarding remain unfinished.

## Owned definition and caller contracts (2026-10-10)

Checked units now retain complete predicates, concrete implementations, accepted
method bindings, and one binder table for public and private definitions. Public
aliases come from the exporter; private anchors belong to the immutable source
snapshot. Each call retains its actual enclosing function separately from the
generic scope chain. Concrete replay shares the original contract table and
refreshes call facts, preserving definition identity across workspace reuse.

**All 16 selected checks pass:** two new snapshot checks, 12 nearby library
regressions, and two native integration tests. Coverage includes zero-call
contracts, public/private owners, independent parameter domains, 32 parameters,
empty-job workspace reuse, imported private types, and execution after scratch
overwrite. Nested symbolic constants inside nominal trait operands also execute;
eight wrong or unsupported bindings reject. The latter repair recognizes the
already-checked constant role before the type-only diagnostic path.

Evidence is in
`tests/fixtures/stdlib_compiler_state/caller-contract-snapshots/verification.json`.
These checks execute the GPU compiler and emitted x86_64 Linux programs; they
do not establish user-program GPU execution.

Retaining these contracts has a measured cost. Batching reduced the trait-heavy
workload from 163.391 ms initially to 71.651 ms, against a final paired 65.017 ms
baseline (+10.2%). The ordinary 32-parameter comparison ended +3.8% with substantial
baseline drift, so it does not isolate a causal regression. See the
[performance evidence](stdlib-gpu-performance.md#owned-definition-and-caller-contracts-2026-10-10).

**The general goal remains open.** These snapshots supply the missing inputs;
program-wide implementation selection, owned proofs, and validation of those
proofs during imported body replay still need implementation.

## Borrowed enum matching and imported structural types (2026-10-10)

Borrowed concrete and generic enum methods now substitute payload types from
the complete referenced enum application. Reference payloads occupy one native
value word. Ignored payloads retain their checked type, allowing later fields
to use the correct offset even when the ignored value has zero or several words.
The match instruction recipe owns address normalization, arm and payload
positions, and final argument capture together.

An additional import handoff failure is fixed: arrays, slices, and references
now capture their final child types after imported bare nominal names have been
projected into persistent instances. This moves an existing pass and adds no
dispatch. Alias normalization keeps rejecting dependency-page-local roots.

**All 19 selected checks pass:** 11 native integration tests, five library
checks, and three scalar-match controls. They cover local and imported enum
methods, both boolean values and missing variants, arrays and empty values,
copy independence, reference/slice aliases, mutations, argument order, nested
aliases, and compiler workspace reuse. A physical GPU test checks semantic
instruction capacity, overflow, and recovery. Capacity-only failures now report
required and available rows with `LNC0057`; mixed failures keep their existing
details. Evidence is in
`tests/fixtures/stdlib_compiler_state/borrowed-enum-referents/verification.json`.

The earlier retained-call failure in `Maybe<bool>::unwrap_or` is resolved.
The separate `&&Flag` probe rejects at `impl &Flag` with `LNC0021`; nested-reference
production and execution remain unverified. Receiver adjustment needs an
explicit caller-place contract before that path can produce an additional
reference layer. Scalar-reference matching remains unsupported. No new paired
performance result is claimed for this checkpoint.

**The general goal remains open.** Program-catalog implementation selection,
retained proof forwarding, and the remaining trait/generic-method contracts
listed below still need implementation.

## Retained symbolic call graphs (2026-10-10)

Generic call snapshots now preserve symbolic type and constant parameters inside
arrays, slices, references, and nominal applications. Parameters retain exact
binder ownership and mixed-header position separately from substitution slots.
Public types use their real exported identity; private types retain anchors into
the immutable source unit. Semantic closure and native layout availability are
separate checks. Concrete replay reports missing layout or packet capacity as
`LNC0017`, instead of reaching the linker with an unexplained missing body.

**32 selected checks pass:** 26 library checks and six native integration tests.
They cover workspace reuse, distinct caller binders, private records and enums
through imported generic forwarding, zero-sized values, and independent 32-slot
type/constant domains. The Result test now invokes production specialization
before linking. One selected preexisting failure remains: matching the borrowed
receiver in `Maybe<bool>::unwrap_or`. It also fails on the preserved baseline.
The separate borrowed-enum repair is not part of this verified snapshot.

The existing 32-parameter benchmark now measures 358.918 ms against a paired
358.441 ms baseline (+0.13%), with correct executable output. Batching ownership
metadata removed the first implementation's 76 extra readbacks and 10–12%
slowdown. See [the measurements](stdlib-gpu-performance.md#retained-symbolic-call-graphs-2026-10-10)
and `tests/fixtures/stdlib_compiler_state/caller-proof-retention/verification.json`.

**The general goal remains open.** Lossless call snapshots establish a required
input to caller implementation selection. Program-catalog selection, retained
proofs, and forwarding those proofs into imported bodies remain unimplemented.

## Portable implementation contracts (2026-10-10)

Semantic-interface schema 12 exports accepted concrete public trait
implementations. Each record preserves its defining unit and module, complete
subject and ordered operand graphs, and every required method binding. Private
required methods remain part of the contract. Their lexical method identity and
native target identity are separate; interface export and native emission now
share the callable-symbol producer. Old interface artifacts must be rebuilt.

Member and predicate ownership now distinguishes declarations from
implementations. Host validation, binary serialization, dependency batching, and
GPU page packing preserve that distinction. Existing declaration-only method
consumers retain explicit kind checks. Generic implementation evidence and
prerequisites reject explicitly at this checkpoint.

**All 79 selected checks pass:** 20 interface, 46 library/page/resource, and 13
native regression checks. Coverage includes 32 independent compound operands,
scalar/record/enum/array/slice/reference subjects, empty values, malformed
identities and ownership, page order, and workspace reuse. A native test verifies
that each exported public/private method target identifies exactly one emitted
body and then executes the program. Evidence is in
`tests/fixtures/stdlib_compiler_state/implementation-evidence-export/verification.json`.

**The general goal remains open.** These are portable implementation contracts;
the caller still needs to select and retain evidence and pass it into imported
body replay. Generic implementations, prerequisites, method-level `where`,
generic trait methods, and direct constant trait applications remain dependencies.
See the [implementation contract and next boundary](compiler-implementation-evidence-plan.md).

## Portable callable bounds (2026-10-10)

Semantic-interface schema 11 now exports accepted public free-function `where`
bounds. Each predicate retains its defining trait identity, complete subject and
ordered operand graphs, and exact lexical type/constant parameter ownership.
Bound-only types survive export. Binary decoding and dependency-page packing
validate ownership and preserve identities while rebasing storage references.
Old interface artifacts must be rebuilt.

Bounds and trait implementation headers now use their canonical predicate role.
They no longer create an artificial nominal value root that combines all
operands under one value-layout expansion limit. A native test executes 32
independent `Cell<[i32;N]>` operands, including an empty array; changing the final
length rejects. Local and imported method signature validation still passes.

All 67 selected checks pass: 16 interface, 38 library/page/resource, and 13 native
execution tests. Evidence is in
`tests/fixtures/stdlib_compiler_state/callable-predicate-export/verification.json`.
These checks cover full graphs, binary corruption, dependency order, workspace
reuse, and executable behavior; they do not prove all generic programs work. The
[existing performance workloads](stdlib-gpu-performance.md#portable-callable-predicates-2026-10-10)
also pass their output contracts on frozen sources.

**The general goal remains open.** Method-level `where` clauses, including
inherent methods, reject with `LNC0021` before export; their reproduction is
retained. Direct constant trait applications are also unsupported. Imported body
replay still needs the caller's selected implementation evidence. The next
[implementation-evidence contract](compiler-implementation-evidence-plan.md) was
proposed at this checkpoint; the later section above establishes its export.

## Imported trait references and method contracts (2026-10-10)

Imported traits now have checked references that preserve their defining library,
unit, and declaration identity. A local generic bound can use a caller-defined
implementation of an imported trait. Required methods are checked against the
owning dependency page: names, visibility, receiver mode, argument count, and
complete substituted parameter and return types. Qualified and unqualified names
for the same trait match; same-named traits from different units remain distinct.
Page-local rows never become retained trait identities.

Native execution covers arrays, records, references, slices with aliases, empty
values, value copies, private required methods, and all 32 ordered operands.
Malformed method contracts and changed inner types, lengths, or identities reject.
Direct constant-parameter trait applications remain explicitly unsupported;
imported cases now report that limitation instead of accepting a type as a constant.

Two integration corrections were required. A let/return result annotation no
longer leaks into a nested record-literal call argument. Read-only absent-dependency
identities now use immutable empty-page storage, so graph coloring cannot alias
those inputs with writable inference tables.

The initial snapshot passes 170 selected checks. After reducing unnecessary trait
header storage, five native checks and five resource/page/reuse checks pass.
The reuse test trims the exporting workspace, starts with plain imports, grows
for imported traits, and recovers after rejected programs. The two existing
performance workloads produce correct outputs; see [measurements](stdlib-gpu-performance.md#imported-trait-references-and-method-contracts-2026-10-10).
Evidence: `tests/fixtures/stdlib_compiler_state/imported-trait-resolution/verification.json`.

**The general generics goal remains open.** The retained caller-implementation
example now reaches imported body replay and rejects with `LNC0008` because that
body lacks the caller's implementation evidence. The next boundary needs portable
callable bounds, validated implementation records, selected caller evidence, and
explicit forwarding into body compilation. Blanket implementations, generic trait
methods/where clauses, and ordered constant trait operands also remain open.

## Portable trait declaration contracts (2026-10-10)

Semantic interfaces now retain a trait's complete ordered generic header and
required method signatures. Schema version 10 adds a distinct `TraitMethod`
member: return and parameter type graphs, receiver mode, visibility, and
method identity. Trait parameters keep their declaration scope; they are not
flattened into the method's own generic requirements. Private required methods
are retained as part of the public trait contract. This is a private interface
format change; old artifacts must be rebuilt.

Validation rejects incomplete headers, foreign parameter references, malformed
method identities/requirements, orphan parameter records, and members outside
their owner's range. Tests cover mixed type/constant header order, compound
signatures, implicit receivers, void returns, all 32 header operands, malformed
records, and binary round trips. A native program imports a module containing
these contracts and executes generic copies, references, empty arrays, and
slice aliases. All 34 selected interface, native, and regression checks pass.
See `tests/fixtures/stdlib_compiler_state/imported-trait-contract/export-contract-verification.json`.

This earlier export checkpoint did not yet resolve imported trait predicates.
The later checkpoint above establishes imported references and method validation.
Caller evidence for cross-unit body replay remains a separate dependency. The
34 checks here describe the earlier snapshot; they are not additional current
execution coverage.

## Late method results and logical buffer bounds (2026-10-10)

Local methods discovered during inference now publish their complete return type even
when neither the receiver nor the result has an annotation. Early signature
seeding had missed those calls, and the later materializer excluded compound
results on scalar receivers. Both trait and inherent methods now execute through
the accepted result relation. Closed graphs reuse their original reference;
symbolic graphs use the callable's accepted environment. Closure traversal uses
a shared structure interface across checking, materialization, and native layout.

Executable cases cover local/imported call chains, nested arrays and records,
booleans, empty values, enum payloads, Unicode strings, slices, references, value
copies, mutations, and all 32 ordered compound arguments. Conflicting inner
element types, lengths, empty element types, and nominal identities reject with
source-labeled `LNC0006`. Receiver/result annotations and ordinary functions are
retained as controls.

Verification exposed a separate compiler workspace bug. An imported enum alias
passed alone but failed after a program using imported nested `Option` values.
The resource graph supplied the whole reused physical slot as a logical table's
shader binding. Its enlarged `GetDimensions` admitted unrelated scratch storage.
Graph views now bind only the resource's declared byte range, retaining the
same allocation and coloring. A focused binding test checks both typed and
untyped views; a compilation-sequence test checks payload values and slice aliases.
The original failing batch now passes with normal storage reuse enabled.

**276 selected checks pass:** 113 execution/rejection checks (five new), 99
semantic checks, 58 resource/native/page/pass checks, and six parser/feature
checks. The 113 runtime checks include the four method-result tests and the
workspace-growth regression. The full 341-test execution inventory was not rerun.
All execution evidence is x86_64 Linux ELF produced by the GPU compiler.

Evidence: `tests/fixtures/stdlib_compiler_state/method-result-contract/`, including
`final-selection.json`, `final-*.log`, the before/after method probes, the reduced
failing compilation sequence, allocation controls, and the workspace regression.
Temporary shader diagnostics were removed before final verification. An attempted
source-baseline reconstruction was invalid because ten earlier snapshots were
empty; no behavior claim uses that failed reconstruction. Original failure logs
and the successful correction are retained separately.

The [semantic contract](compiler-semantic-contracts.md#late-method-results-and-logical-buffer-bounds-2026-10-10)
and [performance report](stdlib-gpu-performance.md#late-method-results-and-logical-buffer-bounds-2026-10-10)
describe the boundaries. Limits remain 32 ordered nominal operands and 64 levels
of type traversal. Native ABI and private interface formats are unchanged. The
broader [generics goal](#remaining-work) remains open.

## Complete trait type graphs (2026-10-10)

Trait predicates now use the shared checked type graph. Implementation lookup
hashes and compares the complete subject and ordered arguments; it no longer
reduces them to two shallow type codes. Trait arguments use the ordinary type
grammar. Method contracts substitute complete trait arguments and compare the
resulting types independently of source-tree shape. The obsolete nested syntax
comparison pass is removed.

Executable coverage includes nested nominal and array arguments, slices,
references, Unicode strings, empty values, enum payloads, symbolic type/constant
substitution, and all 32 ordered trait arguments. Value arguments retain their
copies and borrowed arguments retain aliases. A caller can forward a parameter
using its own matching declared bound; the forwarding regression covers a
zero-argument marker trait. Wider caller-contract compositions are not thereby
established.

Concrete body replay now checks trait obligations before emission. An imported
call with the wrong nested array length previously produced an executable;
it now rejects with `LNC0008`. Negative execution tests also cover changed inner
nominal identity, array lengths, argument order, the 32nd argument, duplicate
complete implementation keys, unproved caller assumptions, incomplete nested
nominal applications, and mismatching method signatures.

**176 selected checks pass:** 63 integration execution/rejection checks, 99 trait
semantic checks, four parser checks, two lexer/parser feature checks, and eight
resource, native page/template, and pass-selection checks.
Reference-only implementation headers now enable their required storage passes.
Ordinary bitwise `&` expressions do not enable the reference feature. The full
336-test execution inventory was not rerun.

Limits remain explicit: 32 trait arguments and the shared 64-level type-graph
traversal bound; implementation headers must be concrete. Blanket implementations,
trait method generic headers, and method where clauses remain unsupported.
This checkpoint changes neither the native ABI nor the private interface format.

At this checkpoint two retained reproductions failed. A caller-defined
implementation of an imported trait rejects at trait-name resolution
(`imported-caller-impl.lani`), before witness lookup is reached; it remains open.
The unannotated compound method result (`method-signature.lani`) and its inherent
control are resolved by the later method-result checkpoint above. An additional semantic sweep found
an existing test using `receiver: Range` as an implicit receiver rather than
`self` still rejects; its relationship to this checkpoint is not established.

Evidence: `tests/fixtures/stdlib_compiler_state/trait-type-graphs/`, including
`final-{generic,semantic,parser,contracts}.log`, `reference-feature-flags.log`,
`final-selection.json`, `remaining-probes.json`, and the executable/negative
fixtures. See the [semantic contract](compiler-semantic-contracts.md#complete-trait-predicate-types-2026-10-10)
and [performance report](stdlib-gpu-performance.md#complete-trait-type-graphs-2026-10-10).
The overall generics goal remains open.

## Bound slice arguments and enum payloads (2026-10-10)

Explicit bindings such as `keep<[i32]>(array)` now apply the ordinary outer
array-to-slice borrowing conversion. Claim publication consumes the explicit
binding after it is available; the early pattern collector remains independent
of that table. The binding denotes the expected slice while the argument retains
its actual array type. Element types and nested aggregate types must match
exactly. Wrong element types, distinct nominal elements, nested record conversions,
and an array result demanded from a slice result reject with source-labeled
`LNC0006`.

Capture mode comes from the bound parameter. A declaration-side `T` that becomes
a slice borrows the caller's place; it must not first copy that place into a
temporary. This executes through local/imported functions, imported identity
aliases, and methods. The runtime program checks different array lengths, empty
views, zero-sized elements, booleans, records, nested arrays, Unicode strings,
inline array fields, and type/constant parameters inside generic bodies. Ordinary
array value arguments retain independent copies.

Enum constructors preserve the checked passing mode and construct a complete
slice descriptor using the existing aggregate conversion. Payload offsets include
all three descriptor words. Ordinary, structural-generic, explicitly bound,
imported, and concrete-alias constructors preserve mutations in both directions
and the following scalar payload. The ordinary constructor previously emitted
a crashing executable, independently of generics; it now executes correctly.

**61 selected checks pass:** 54 integration execution/rejection checks, five
native page/template checks, and two resource/lowering checks. These include
argument evaluation order, descriptor capture, ordinary value copies, the original
inline-array borrow cases, 32-parameter calls, and qualified alias replay. A
separate generic-body enum probe also executes with both integer and Boolean
elements. The full 329-test integration inventory was not rerun.

No ABI, private format, kernel count, or buffer allocation changes. The native
aggregate pass reads the existing checked passing-mode input; view construction
retains the source place's signed byte stride. An unresolved executable view
length fails before emission. Direct annotated array-to-slice assignment remains
unsupported. Broader dependencies remain under [Remaining work](#remaining-work).

Evidence: `tests/fixtures/stdlib_compiler_state/explicit-slice-borrow/`, including
`final-generic.log`, `final-contracts.log`, `final-selection.json`, the retained
before/after probes, and `compositions.lani`. Performance is in the
[GPU performance report](stdlib-gpu-performance.md#bound-slice-arguments-and-enum-payloads-2026-10-10).

## Qualified alias body replay (2026-10-10)

A generic function whose parameter or result uses an imported identity alias now
specializes the complete qualified occurrence. The symbolic template already
passed checking; concrete replay previously changed the path head while leaving
its final segment symbolic. Parameter and return readers could consequently
observe different types for the same occurrence. The existing replay producer
now publishes the selected reference at both anchors, using exact lexical
parameter identity. The public template interface remains symbolic and unchanged.

**49 selected checks pass:** 33 integration execution/rejection checks, nine
interface checks, five native page/template checks, and two resource/lowering
contract checks. The new program executes integers, booleans, Unicode strings,
arrays, records, references, slices, enum payloads, and empty arrays. It checks
independent copies, preserved aliases, separate type-parameter slots, parameter-
only and return-only aliases, and nested qualified aliases. Conflicting return,
argument, and array-length types reject with source-labeled `LNC0006`. The new
unit regression proves the template passes before concrete replay and that each
replayed public interface equals the original. The full 324-test integration
inventory was not rerun.

The original full adjacent-`>>` program and its spaced counterpart both execute
in the current tree. Its eight spacing workarounds are removed from the runtime
regression. No parser change was made here; the historical rejection's cause
has not been established, and it is no longer listed as a reproducing bug.

At this checkpoint, `keep<[i32]>(array)` rejected with and without aliases.
The subsequent bound-slice checkpoint above implements that call conversion.
Direct annotated array-to-slice assignment still rejects. This checkpoint's
runtime program creates its slice through a `[T]` parameter before forwarding
it through the identity alias; reads and writes preserve the original backing
storage. The original conversion reproductions are retained.

This change adds no pass, buffer, ABI change, or private format change. Evidence:
`tests/fixtures/stdlib_compiler_state/angle-close-probes/`, including
`symbolic-replay-before.log`, `symbolic-replay-final-{generic,interface,contracts}.log`,
and `symbolic-replay-final-selection.json`. The executable program is
`tests/fixtures/stdlib_compiler_state/alias-import-composition/symbolic-identity.lani`.
See the [performance report](stdlib-gpu-performance.md#qualified-alias-body-replay-2026-10-10).
The overall generics goal remains open.

## Imported alias members (2026-10-10)

Imported alias-qualified enum constructors and associated methods consume the
normalized parent type. Member lookup uses its stable declaration identity;
constructor binding uses its complete ordered type and constant arguments.
Reordered and injected operands, local aliases of imported types, reexports,
bare/called empty variants, and 32-operand concrete aliases execute. A caller can
use reexported members without importing the target's defining module.

Qualified method lookup uses the same complete receiver reference. A method's
own arguments remain separate from its receiver's arguments. Invalid receiver
types, array lengths, explicit method arguments, and constructor contexts reject.
Binding and validation also run when a concrete imported alias supplies all its
arguments implicitly: absence of `<...>` syntax no longer skips these checks.

**68 selected checks pass:** 53 integration execution/rejection checks, nine
interface checks, four native page/template checks, and two resource/lowering
contract checks. The new page test executes flat, target-first, target-last, and
empty-interleaved layouts; each rejects conflicting lengths, ambiguous aliases,
and locally shadowed parents. The full 322-test integration inventory was not
rerun. Execution is x86_64 Linux ELF emitted by the GPU compiler.

Three kernels add an index and lookup for enum members and late value metadata
projection. The index reuses the visibility workspace after its consumers finish;
this change adds no buffer allocation. Page-local declaration rows stay within
their page. No ABI or private interface format change in this checkpoint.

The subsequent qualified-alias replay checkpoint above revalidated the original
adjacent-`>>` program. Other items under Remaining work, including trait argument
restrictions, remain open. This checkpoint does not establish arbitrary-type
generics or user-program GPU execution.

Evidence: `tests/fixtures/stdlib_compiler_state/imported-member-final-{generic,interface,contracts}.log`,
`imported-member-final-selection.json`, and `imported-member-plan.json`.
Performance is recorded in the [GPU performance report](stdlib-gpu-performance.md).

## Complete imported alias types (2026-10-10)

Imported aliases substitute their own ordered type and constant arguments into
their complete checked targets. Identity, scalar, array, slice, reference,
reordered record, injected-argument, and nested local/imported aliases execute.
Reexported identity and constant-array aliases retain the same semantics.
Targets are retained before a dependency page is released; normalization runs
after all pages contribute their targets.

Module export now traverses checked types. HIR identifies the exported annotation
roots and lexical owners. It no longer reconstructs alias targets from syntax.
The semantic producer preserves array, slice, and reference roots instead of
recording only their element type. Parameter leaves carry exact declaration
identities, translated to portable member identities. Concrete body replay
retains the original template interface and emits its specialized object without
re-exporting concrete types as generic declarations.

**58 selected checks pass:** 45 integration execution/rejection checks, nine
interface checks, two native page/template checks, and both resource/lowering
contract checks. The page test executes flat, inner-first, outer-first, and
empty-interleaved layouts and rejects wrong lengths in each. The composition
program checks array copies, borrowed slice mutation, reference identity, empty
arrays, and Unicode output. The full 315-test integration inventory was not rerun.

Checked export is bounded to depth 64, 32 operands per nominal application, and
the existing HIR-capacity budget for serialized annotation trees. Exhaustion
rejects explicitly. The private interface remains version 9 and the native ABI
is unchanged in this checkpoint. Rebuild artifacts affected by the old alias
export bugs. Execution evidence remains x86_64 Linux ELF emitted by the GPU
compiler; user-program GPU execution is not established.

**Remaining at that checkpoint:** imported alias-qualified constructors/member lookup and the
retained adjacent-`>>` parser failure. Other limitations listed below, including
trait argument restrictions, remain outside this checkpoint. The overall
generics goal is open.

Evidence: `tests/fixtures/stdlib_compiler_state/checked-export-final-{generic,interface,contracts}.log`
and `checked-export-final-selection.json`. Performance is recorded in the
[GPU performance report](stdlib-gpu-performance.md).

## Normalized local alias constructors (2026-10-10)

A qualified value path binds its parent before member lookup. Local aliases
normalize to complete checked types, then resolve the underlying enum member.
Constructors inherit the normalized target operands. For example,
`Flip<A, B> = Pair<B, A>` supplies the reversed operands; an alias can also inject
operands, preserve constants, or name a concrete unit without written arguments.
Both `Number::None` and `Number::None()` execute when `Number = Choice<i32>`.

The explicit call binder publishes a compact table of checked type and constant
bindings. Inference reads the table by domain and slot, with no source-HIR scan
or parent-graph traversal. Source headers still validate their own arity and
parameter domains. A descriptor and eight binding rows per source-token capacity
bound storage; exhausted storage rejects. Reservations are reused during
inference, and job initialization clears descriptors, counts, and all spare tags.
The table's type references participate in accepted-body specialization.
Constant replay updates generated nominal arguments as well as array lengths,
using exact parameter declaration identities.

**36 selected checks pass:** 34 executable/rejection checks and both resource and
lowering contract checks. They cover reordered and injected operands, symbolic
forwarding, mixed and independent constant domains, 32 injected operands, both
32-slot callable domains, bare/called units, conflicting contexts and headers,
local/imported callable controls, and repeated workspace transitions. The full
303-test generic inventory was not rerun. Outputs are executed x86_64 Linux ELF;
this does not establish user-program GPU execution.

**Remaining at that checkpoint:** imported generic alias substitution. The retained comparison has
six executing direct controls and one executing scalar alias; generic identity,
array, slice, reordered record, and qualified enum aliases reject. Some malformed
local alias headers currently surface as unresolved member diagnostics. The
unrestricted generics goal remains open.

Evidence: `tests/fixtures/stdlib_compiler_state/alias-member-final-{generic,contracts}.log`,
`alias-member-final-selection.json`, and `alias-member-plan.json`. Performance is
recorded separately in [the GPU performance report](stdlib-gpu-performance.md).
No ABI, private interface format, verified IR, or proof changes in this follow-up.

## Transparent local aliases (2026-10-10)

Local aliases now normalize to complete checked types before signature capture.
Each application substitutes its own ordered type and constant environment into
its immediate target. Reordered, omitted, and concrete arguments compose through
alias chains. The normalizer reads immutable source rows and publishes complete
references in a separate dispatch, including generated array and nominal nodes.
Fourteen old forwarding/equivalence kernels are removed.

Aggregate argument equality now compares complete scoped checked graphs. The old
source-subtree comparison kernel and eight scratch buffers are removed. Constant
body replay visits generated arrays using exact parameter declaration identities.
The parser records an alias's direct right-hand-side type, so `const N: usize`
cannot replace `[T; N]` as its target. Associated method lookup consumes stable
parent bindings and keeps imported identity on each path use; a same-named local
declaration cannot acquire imported metadata.

**74 focused checks pass:** 41 generic execution/rejection checks, 25 semantic
checks, six parser checks, and both resource/lowering contract checks. Coverage
includes 64-link reordered/selection chains, all 32 ordered operands, scalars,
arrays, slices, references, records, constants, empty values, body replay, and
workspace reuse. Wrong element types, array lengths, nominal identities, and
lexical parameters reject. The full 297-test generic inventory was not rerun.

The checked graph keeps its 64-level depth bound and 32-operand application
bound. Alias traversal is bounded by source HIR size, independently of graph
depth. Cycles and exhausted storage reject explicitly. Trait argument support
retains its existing scalar and zero-operand nominal leaf restrictions.

The constructor follow-up above supersedes the original local alias-member
failure. Imported generic alias substitution remains open.
No ABI or private format changes in this checkpoint. Evidence is
`tests/fixtures/stdlib_compiler_state/alias-types-manifest.json` and the
[performance report](stdlib-gpu-performance.md).

## Retained record fields (2026-10-10)

Imported record field lookup now consumes retained names, ordinals, and checked
types. Member chains, nested constructor contexts, and native field offsets no
longer consult the active dependency page. The existing payload producer retains
a name hash alongside each field. Known declaration metadata and individually
resolved fields are distinct from complete native layout inputs; a completion
bit preserves that distinction. Unresolved field types wait for closure, while
unknown fields, incompatible types, and exhausted storage still reject.

The new executable comparison covers flat dependencies and both split-page
orders, each through an ordinary function, a local generic function, and an
imported generic function. All nine programs return 42 with empty stdout/stderr,
checking nested field reads/writes, extraction, and independent owned copies.
Every page order also rejects an unknown field and a wrong array element type.
Before the correction, flat cases passed but a split-page generic body rejected
its valid nested field with `LNC0042`.

**33 focused checks pass:** that comparison, the preceding composed enum/page
test, two compiler contract checks, and 29 affected integration tests. They cover
record inference, 32 bindings, constructor conflicts, references, slice bounds,
wide descriptors, unit values, and workspace reuse. The full 287-test generic
inventory was not rerun. This follows the initial 85-check page checkpoint below.

Evidence is `page-fields-{plan,selection,manifest}.json` and
`page-fields-{before,final-focused,final-generic}.log` under
`tests/fixtures/stdlib_compiler_state`. No kernel or ABI changes. One bounded
field-name buffer is added. Measurements are in the
[performance report](stdlib-gpu-performance.md). The general goal remains open;
the page comparison establishes the listed compositions and execution target.

## Dependency pages and retained value layouts (2026-10-10)

Dependency pages are reusable input storage. Checked types, declaration identities,
and native layout inputs must survive replacing a page. This checkpoint repairs
four violations of that contract:

- A qualified variant resolves its parent type before looking up the member.
  A declaration in the owning module shadows imports. Source-pack and external
  imports have equal visibility and can be ambiguous. Stable parent identities
  preserve that result across page order and repeated pages.
- Type paths retain the same library/unit/declaration identity as value paths.
  Projection reacquires the declaration from the resident page. Two obsolete
  page-local declaration buffers are removed. Later call collection preserves
  checked annotation references instead of overwriting them with canonical seeds.
- Deferred compute is flushed before a dependency page is replaced. Parameter
  pattern collection and claim emission read only the callable's owning page;
  initialization and shared prefix scans run once. Single-page scheduling keeps
  its existing dispatch sequence.
- Imported record fields and every enum variant publish retained groups of
  checked payload references, including unconstructed variants. Native width
  calculation consumes these groups without reading a dependency page. Index
  rebuilding preserves them; job initialization clears them even when a module
  has no applications. Incomplete layouts remain invalid, distinct from zero
  words. Arena exhaustion fails explicitly, and newly completed layouts report
  closure progress.

The parser also seeds qualified type paths after enum payload delimiters. Both
payload positions and a path spanning a token-prefix block have full parse checks.

**85 focused tests pass:** 30 generic execution/rejection tests, 33 stdlib enum
tests, 10 module checks, seven parser checks, three dependency-page tests, and
two resource/lowering contract checks. The three page tests also pass with
compute batching disabled. The generic inventory contains 287 tests; this gate
does not repeat the full inventory.

The nested page test compiles and executes an enum containing another imported
enum, arrays, strings, and an unconstructed record alternative. Flat dependencies
and both split-page orders produce exact stdout `αomega`, exit 42, and empty
stderr. Copies, reassignment, and an ordinary by-value function parameter retain
their values. Each ordering rejects boolean payloads in an integer array and
an incorrect string-array length. Qualifier tests cover local shadowing, imported
ambiguity, full qualification, repeated pages, and mixed source-pack membership.

Evidence is `page-manifest.json`, `page-final-selection.json`, and the named
`page-final-*` logs under `tests/fixtures/stdlib_compiler_state`. Before-images,
diagnostic probes, and the initially rejected workspace initialization remain
there. Frozen identities and measurements are in
`benchmark_artifacts/performance/stdlib-gpu-20261010-dependency-pages/`.
See the [performance report](stdlib-gpu-performance.md).

No kernel or ABI is added. Private interface version 9, native object version 3,
and three-word slices are unchanged. At this checkpoint, multi-page record field
access and generic body replay still needed evidence; the follow-up above supplies
it for the listed compositions. The nested-match parser rejection
is retained as `page-layout-nested-match-before.lani`; the successful nested
layout test uses sequential matches. Ordinary string comparison remains a
separate dependency. The broader [generics goal](#remaining-work) remains open.

## Qualified enum variants and method parameter rows (2026-10-10)

Local and imported enum variants retain their parent declaration. `A::Value`
and `B::Value` can coexist; an ambiguous unqualified `Value` rejects. The
existing declaration index retains every row and filters by exact parent scope.
Duplicate validation compares that scope as well. Type-qualified and module-plus-
type-qualified construction and patterns use the resolved enum identity.

Explicit parent applications such as `Packet<T, N, F>::Data(values, flag)`
use the normal nominal projection and ordered callable binder. One per-path
qualifier token records which segment actually denotes the enum; a module prefix
cannot become a type application. Bare and called units accept complete explicit
parent applications. The same application on both parent and variant rejects,
as do wrong families, arities, operand domains, and payload types. This checkpoint
covers 32 type parameters, interleaved type/integer-constant headers, caller-
symbolic forwarding, arrays, strings, zero-length values, and independent copies.
At that checkpoint, alias qualifiers and cross-page qualifier shadowing/ambiguity
were not established. The dependency-page follow-up above covers the latter.

Source constant operands keep their lexical binding after concrete body replay.
The nominal collector may publish a specialized graph edge, but cannot replace
its source operand's cached symbolic parameter with a concrete literal. Final
explicit validation keeps its existing position. Expression inference publishes
progress only for a complete checked graph. Closed nongeneric constructors use
their existing source application without requiring a generic allocation arena;
imported called units retain the enum-construction artifact kind.

A method rejection control exposed a separate pre-existing producer bug:
`hir_callable_parameter` omitted implicit `self` because it has no written type.
That prevented ordinal-zero publication of the method's parameter range, so
argument matching had no rows to validate. Source parameters now retain their
rows and ordinals independently of annotations; receiver checking owns `self`'s
type. The exact preceding compiler sources and all shader payloads reproduced
the failure before this correction. The validator was not weakened or duplicated.

**107 execution/rejection checks pass:** 64 selected generic tests, 10 module
checks, and all 33 stdlib enum tests. Both resource/lowering contract checks pass.
Eight new tests cover qualified ownership/applications and method parameter rows.
The latter executes valid scalar, array, and generic calls and rejects incompatible
arguments for `self` and `&self`, locally and through imports. The generic inventory
contains 286 tests; the full inventory and GPU user-program execution were not run.
All execution evidence here is x86_64 Linux output from the GPU compiler.

Evidence is `variant-ownership-manifest.json` and
`variant-ownership-{generic-final,module-final,enum-final,cpu-final}.log` under
`tests/fixtures/stdlib_compiler_state`. Source, shader, binary, benchmark, and
executable identities are retained in
`benchmark_artifacts/performance/stdlib-gpu-20261010-qualified-variants/`.
The existing workloads measured 37.627 ms for the canonical 1 MB compiler median
and 400.409 ms for the 32-parameter entry; all 21 output checks pass. See the
[performance report](stdlib-gpu-performance.md).

No kernel is added; one u32 qualifier column is added per path-capacity row.
Private interface version 9, native object version 3, and the three-word slice
ABI remain unchanged. The broader [remaining work](#remaining-work) is open.

## Imported and local unit values (2026-10-10)

Bare local and imported unit variants now publish the same complete checked
value type. Generic unit values obtain every type and constant operand from
the shared receiving-context resolver, then validate the exact enum identity.
Nongeneric imported units use the existing application materializer while their
dependency page is resident; field expansion retains their complete payload
layout. Match patterns keep their separate binding owner. The old enum branch
in constant consumption and the page-local bare-scrutinee fallback are removed.
The existing unit consumer also runs for imported-only jobs without local enums.

Bare imported nominal annotations now become zero-operand applications during
dependency projection. The ordinary call-result validator therefore compares
complete checked types on both sides. This fixes the retained imported concrete
two-payload enum return and also executes imported records/enums through generic
forwarding, owned arrays, copies, and matching. The enum layout helper uses the
shared three-word slice constant.

A parser regression exposed by `core::ordering` is fixed at delimiter ownership.
A value-path generic-argument candidate must stay within the same statement and
structural containers. A later comparison or shift cannot supply its closing
angle across those boundaries. One joint traversal of the existing delimiter
hierarchies enforces this rule. An array literal's opening bracket supplies a
value role; only an array type supplies a type role. Comparisons, shifts, explicit
nested applications, and cases spanning token blocks have focused coverage.

**80 execution/rejection tests pass**: 47 selected generic tests and all 33 enum
checks, in 54.61 and 5.98 seconds. Six parser checks pass in 34.19 seconds,
including cold pipeline creation; both resource/lowering checks pass in 0.07
seconds. The generic inventory contains 278 tests; the full matrix was not
repeated. Six new generic tests exercise local/imported unit values, all 32
receiving bindings, constants, arrays, references/slices, owned copies, inferred
nongeneric units, missing or incompatible context, imported nominal annotations,
and comparisons beside explicit generic calls. Two obsolete rejection tests now
execute and inspect constructor payloads. The older bare-unit rejection test
also executes and checks its discriminant.

Evidence is `unit-values-manifest.json` and
`unit-values-{generic-final,enum-final,parser-owner-final,cpu-final}.log` under
`tests/fixtures/stdlib_compiler_state`. Earlier failures and reduced parser cases
remain alongside them. The common unit reader has one call site; its SPV is
373,836 bytes under the unchanged 524,288-byte guard. No new kernel or buffer is
introduced. Private interface version 9, native object version 3, and the
three-word slice ABI are unchanged. Verified IR, extraction, and proofs are
unchanged. Type-qualified variants were still open at this checkpoint; the
qualified-variant follow-up above supersedes that restriction. See the
[performance report](stdlib-gpu-performance.md).

## Inference from record fields (2026-10-09)

Unannotated local and imported record literals now infer complete generic
applications from their named fields. The original
`Have(Cell { value: [41, 43] }, true)` reproduction executes. The literal owns
field lookup and the merge of constraints; the existing scoped and canonical
type matchers own type equality and parameter binding. Accepted fields populate
the existing ordered type/constant environment, and the shared application
materializer creates the result. Records retain their own native construction
semantics. No synthetic function body, kernel, or binding buffer is introduced.

The nominal template retains every declared parameter, including unused ones.
Missing bindings and inconsistent fields reject before code generation, as do
unknown, missing, or duplicate field names. A declaration's symbolic field
pattern cannot act as the receiving type of an unbound literal. Parameter
contexts are published and indexed before field inference chooses literal
types; this preserves unsigned contexts through nested records and arrays.
The existing closed-application indexer runs once more per relevant inference
round to make newly published parameter types available to record lookup.

Four new tests cover local/imported nested records and arrays, reversed field
order, 32 inferred type parameters, constant lengths, caller-symbolic types and
constants, empty payloads, strings, independent owned copies, and preserved
reference/slice aliases. An empty `[T; 0]` field can receive its element type
from another field's evidence. Fourteen invalid local/imported programs check
conflicts, unused parameters, and field shape errors.

**79 distinct execution/rejection tests pass**, comprising those four tests
and 75 affected controls. The three groups take 18.82, 18.07, and 7.11 seconds.
Both resource/lowering contract checks pass in 0.07 seconds. The inventory has
272 runtime tests; the full matrix was not repeated. Evidence is
`record-inference-manifest.json`, `record-inference-gate-{1,2,3}.log`, and
`record-inference-cpu.log` under `tests/fixtures/stdlib_compiler_state`.
Earlier failing probes remain there as historical evidence.

The record-context shader uses the existing minimum-optimization policy for
complex shaders. Its SPV is 188,756 bytes; the 524,288-byte guard remains enforced.
Private interface version 9, native object version 3, and the three-word slice
ABI are unchanged by this follow-up. Verified IR, extraction, and proofs are
unchanged. The broader goal and [remaining work](#remaining-work) remain open;
measurements are recorded in the [performance report](stdlib-gpu-performance.md).

## Constructor signatures and unit values (2026-10-09)

Local and imported enum constructors now use the same generic call contracts as
functions. The variant is the callable identity; its parent enum owns the generic
header. Payload parameters retain complete typed patterns, and the return is the
complete symbolic enum application, including unused parameters and source-ordered
type/constant operands. Explicit arguments, payload inference, receiving context,
and final materialization share the existing binder. The separate enum payload
validator and the imported bare-enum return fallback are removed.

The interface exporter now preserves complete nominal declaration signatures.
Private semantic-interface format **9** requires older interfaces to be rebuilt.
The native object format remains 3 and the three-word slice ABI is unchanged.
Verified IR, extraction, and formal proofs are unchanged.

Unannotated `Value(42)` and imported `Some(42)` now infer executable results.
The runtime checks cover nested records/arrays, owned copies, slice aliases,
zero-sized payloads, generic body replay, 32 inferred type parameters, and
interleaved type/constant headers. Unused parameters still require evidence:
for example, `core::result::Ok(42)` without any way to determine its error type
rejects before code generation. Conflicting payloads also reject with source labels.

Bare generic unit values receive their full application from the shared context
resolver. Declaration, argument, array, match, and semantic-artifact readers now
consume the same named-value type relation. Patterns remain owned by the match
binder. The original `repro_generic_bare_unit_variant.lani` now executes, as do
unit values in record fields, arrays, match results, and ordinary arguments.
The parser also recognizes nominal type arguments in the first enum payload slot;
`Data(Cell<T>)` no longer needs an artificial surrounding array type.

**70 distinct execution/rejection tests pass**, comprising the five new tests
and 65 affected controls. The three groups take 13.79, 7.00, and 25.83 seconds.
All eight interface-export checks pass in 3.16 seconds, five parser controls in
1.22 seconds, and six resource/lowering/serialization checks in 0.07 seconds.
The inventory has 268 runtime tests; the full matrix was not repeated. Evidence
is `constructor-signatures-manifest.json` and
`constructor-signatures-{unit-controls,focused-final,controls-final,export,parser,cpu}.log`
under `tests/fixtures/stdlib_compiler_state`.

At this checkpoint, type-qualified local variants and inference from an
unannotated record literal's own fields still needed work. The field-inference
follow-up above now executes the minimal case retained in
`constructor-signatures-local-probe.log`. Type-qualified local variants remain
unresolved. Imported bare generic unit values were not established until the
unit-value follow-up above. See the
[remaining work](#remaining-work) and [performance report](stdlib-gpu-performance.md).

## Nominal declaration identity (2026-10-09)

A source-position regression exposed an identity collision: the old scalar
caches encoded structs as `4096 + declaration_token` and enums as
`6144 + declaration_token`. Declarations 2,048 tokens apart could therefore
share a code. Generic forwarding then reached an undefined native body; adding
one unrelated token made the same program execute.

**Nongeneric records and enums now own zero-argument nominal nodes in the
checked type graph.** Their declarations publish those nodes during the existing
nominal collection pass. Resolved type uses and constructor results reference
the declaration's node, and native layout traverses that same root. Ordinary
and generic values retain exact declaration identity without decoding a scalar
range. Unit variants also publish their complete checked use-site reference;
argument inference now reads that reference as expression-artifact publication
does. No new kernel, dispatch, or buffer is added by this follow-up.

**Seven focused execution/rejection tests and 58 affected runtime controls
pass** in 8.32 and 26.23 seconds. All eight interface-export checks pass in
2.93 seconds; both compiler contract checks pass in 0.07 seconds. The inventory
has 263 runtime tests; the full matrix was not repeated. The position regression
executes ordinary and generic forwarding at both colliding and adjacent source
positions, including direct unit-variant arguments. Four incompatible enum-to-
record assignments reject with `LNC0006` despite the equal legacy codes.

The expanded compound program also executes imported generic forwarding and
unannotated nested applications introduced inside generic bodies. Owned fixed
array payloads remain independent after copying, borrowed slices retain aliases,
and empty payloads and neighboring sentinels remain intact. Its source is
`generic_bare_nominal_body_closure.lani`.

Evidence under `tests/fixtures/stdlib_compiler_state` is
`nominal-identity-manifest.json`, `nominal-identity-{focused-final,controls-final,export,cpu}.log`,
and the original `nominal-identity-{overlap,separated}.lani` reproductions.
`nominal-identity-position-probes.log` retains the original failure/control pair;
`nominal-imported-closure-probes.log` retains the imported-body checks.
The existing performance tools measure 37.490 ms for the canonical 1 MB workload
and 385.116 ms for the 32-parameter entry; every output program passes validation.
These are unpaired measurements, recorded with frozen inputs in the
[performance report](stdlib-gpu-performance.md).
The broader goal and the [remaining work](#remaining-work) are still open.

## Local enum and nominal contracts (2026-10-09)

Local enum constructors now use the shared complete receiving-context resolver.
The call lane publishes the accepted enum application; payload lanes and the
finalizer consume that published result after the dispatch boundary. The call
consumer participates in the existing inference fixed point, so fields,
assignments, arrays, match results, and arguments can supply context after their
owners become known. Three duplicate let/return-only context readers are removed.
The original `generic_assignment_contexts.lani` now executes in full, including
`Missing()` inside a nested generic record field.

Bare nominal types also use the complete storage contract. The bounded layout
walker handles both nongeneric and applied records/enums, including fixed
arrays, zero-sized values, and borrowed slices. Native consumers resolve the
declaration from checked identity rows instead of assuming a scalar-encoded
nominal is a struct. The retained-type reader copies the same GPU-published enum
identity and word count across generic specialization. It does not reconstruct
layout on the host. Nongeneric enum constructors publish a complete checked
result reference even though they need no application instance.

Match-arm array literals now inherit a value role from the enclosing match
brace; an arrow does not make them function return types. The 32-parameter
composition test executes with its original nested `>>` and array fallback.

**Six focused execution/rejection tests and 38 affected runtime controls pass**
in 4.32 and 16.55 seconds. Twelve parser checks pass in 2.00 seconds; both
compiler contract checks pass in 0.07 seconds. There are 262 registered runtime
tests; the earlier full gate was not repeated. The new compound program checks
bare enums through generic identity calls, nested records, and arrays; owned
copies stay independent, slice mutations retain aliases, empty payloads retain
their type, and neighboring sentinels remain intact. Six incompatible payload
programs reject with `LNC0006`.

The existing shader size guard remains enforced. The array-index artifact now
uses the existing minimum-optimization build policy for complex shaders,
reducing its SPV from 522,440 to 125,064 bytes. The largest artifact is 504,704
bytes, below the 524,288-byte limit. The nominal layout producer has one shared
walker call site; measured pipeline creation in the retained focused trace is
2.714 seconds. No additional kernel or buffer allocation is introduced; enum
inference adds a dispatch of its existing consumer per inference round.

Type-qualified local variants such as `Maybe::Missing()` still reject as an
unresolved module path. At that earlier checkpoint, a generic nullary constructor with no receiving
type rejected late with `LNC0017`. The constructor-signature follow-up now
rejects incomplete bindings before code generation; type-qualified local paths
remain unresolved.

Evidence is `local-enum-context-manifest.json` and
`local-enum-contracts-{focused,controls,parser,cpu}-final.log` under
`tests/fixtures/stdlib_compiler_state`. Executable programs are
`generic_local_enum_contexts.lani` and `generic_bare_nominal_compositions.lani`.
The existing performance tools measure 38.719 ms for the canonical 1 MB workload
and 370.521 ms for the 32-parameter entry, with all emitted outputs verified.
These are unpaired observations; the [performance record](stdlib-gpu-performance.md)
retains source, shader, and binary identities. Verified IR, extractor, and proofs
are unchanged.

## Composition contracts (2026-10-09)

Three failures now use the existing complete-type contracts:

- Qualified applications inside array and slice types inherit the bracket's
  type role. Statement context is intentionally absent inside brackets; that
  absence no longer turns `Option<i32>` into a value application.
- Imported enum constructors accept checked caller parameters such as `T` in
  `fn present<T>(value: T) -> Option<T>`. Payload agreement uses the shared
  scoped type comparison, preserving parameter identity through later
  specialization. Unrelated parameters still reject.
- Argument collection waits for a call's complete checked return when its
  signature has a type-graph origin. The native pointer code for `&Cell<T>`
  cannot become a provisional scalar argument. Direct and nested borrowed
  method calls now execute, including the original recursive `Node<T>` example.

**Five new execution/rejection tests and 35 affected controls pass** in 4.30
and 16.17 seconds. Eleven parser checks pass in 2.40 seconds; both compiler
contract checks pass in 0.07 seconds. There are 257 registered execution tests;
the earlier full gate was not repeated. Runtime checks cover independent owned
copies, slice/reference aliases, recursive reference cycles, empty payloads,
unsigned elements, Option/Result wrappers, and incompatible type rejection.

Only three production shader sources and four SPVs differ from the assignment
checkpoint. Reflection layouts and production Rust sources are unchanged.
The shader size guard remains enforced. The existing performance tools measure
38.247 ms for the canonical 1 MB compiler workload and 389.031 ms for the
32-parameter entry; all emitted outputs were verified. These are unpaired
observations; see the [performance record](stdlib-gpu-performance.md).

At this checkpoint, `generic_assignment_contexts.lani` parsed and passed its
imported generic wrapper, then rejected the nullary local enum constructor
`Missing()` inside a nested generic record field. The failure is retained in
`generic-nullary-constructor-probes.log`. The local-enum follow-up above resolves
it and executes the original whole program.

Evidence is `composition-contract-{focused,controls,cpu}.log`,
`composition-contract-manifest.json`, `parser-composition-parser.log`, and
`generic-{symbolic-constructor,borrow-result}-after.log` under
`tests/fixtures/stdlib_compiler_state`. Executable fixtures are
`generic_qualified_array_elements.lani`,
`generic_imported_constructor_wrappers.lani`, and the unchanged
`generic_recursive_reference_context.lani`.

## Assignment result contexts (2026-10-09)

Generic results now receive the complete type of an assignment destination,
including record fields and indexed elements. The shared resolver projects that
type from accepted declaration/member facts and the preceding call-inference
snapshot. Arrays, record literals, local/imported calls, enum constructors, and
match results use the same receiving-context contract.

The old imported-result assignment validator read the destination's starting
token. For `holder.value`, that selected the type of `holder` and rejected
`holder.value = Some(42)`. That duplicate validator is removed; the call lane
owns its result constraints. The former array-only assignment helper is also
replaced by `assignment_expression_context.slang`. Imported slice result and enum
payload accounting now use `NATIVE_SLICE_WORDS` instead of two stale two-word
constants.

**Three focused tests and 29 affected controls pass** in 2.75 and 13.53 seconds.
The focused tests execute result-only generic calls, constructors and match
results assigned to fields, indexed generic record results, unsigned array
literals, owned copies, and both packed/native slice payloads with aliases and
sentinels. Known incompatible payloads reject with `LNC0006`. Both resource and
semantic-lowering contract checks pass. The inventory has 252 registered tests;
the earlier full gate was not repeated. Evidence is
`assignment-context-{focused-final,controls,contracts}.log` and
`assignment-context-manifest.json` under `tests/fixtures/stdlib_compiler_state`.

The existing benchmark drivers measure 45.824 ms for the canonical 1 MB compiler
workload and 414.383 ms for the 32-parameter entry. All output programs execute
correctly. These are unpaired observations and do not establish performance
preservation. The shader size guard remains enforced; see the
[performance record](stdlib-gpu-performance.md).

Expanded probes also execute unannotated nested generic records/arrays and
ordinary, generic, and mutually recursive pair forwarding. A recursive
`Node<T>` containing `Option<&Node<T>>` executes with a typed intermediate borrow.
At this checkpoint the larger composed assignment fixture rejected during
parsing, and passing `copied.borrow()` directly to generic `walk` rejected
although the typed intermediate executed. The composition checkpoint above
resolves both failures. Both original failing inputs
are retained as `generic_assignment_contexts.lani` and
`generic_recursive_reference_context.lani`. They were not counted as passes at
the assignment checkpoint.
Probe sources and results are retained in `generic-composition-next-probes.log`,
`generic-recursive-type-{probes,reduction}.log`, and
`assignment-context-{compositions,followup-probes}.log`.

## Slice body closure follow-up (2026-10-09)

A focused zero-sized-slice check exposed a general forwarding failure:
`fn view<T>(values: [T]) -> [T] { return core::mem::identity(values); }`
could leave an undefined native body. It also failed for i32 elements. The
body-eligibility pass had exempted symbolic slice types because their descriptor
width was fixed. That exemption allowed a body to call another generic before
its element type was bound.

The exemption is removed. Parameter and result types now use the same complete
type closure as other values. The existing specialization scheduler supplies the
concrete environment. Zero-sized slices execute through ordinary/raw view
construction and local/imported forwarding, preserving side effects and neighboring
values. Reads and writes reject negative, past-end, and empty-view indexes with
exit 101, including when the element occupies no bytes.

**Three focused checks and 32 affected regression checks pass** in 3.22 and
38.27 seconds. The inventory has 249 registered tests. The complete 246-test ABI
gate below predates this follow-up; it was not rerun. Only
`semantic/function_templates.slang`, its SPV, and test sources changed. Shader
reflection layouts and production Rust sources are unchanged, so the preceding
25 host-contract and eight interface-export checks remain applicable.

The existing generic benchmark measures 384.358 ms across ten recompiles after
three warmups and executes its output correctly. This is an unpaired observation;
it does not establish performance preservation. Shader digest is
`5332457d5170a876`; maximum SPV remains 504,704 bytes under the enforced
524,288-byte guard. Evidence is `slice-body-closure-{focused,controls}.log`,
`slice-body-closure-manifest.json`, and `slice-body-closure-checkpoint.json` under
`tests/fixtures/stdlib_compiler_state`. The failing composition and reductions
remain in `slice-stride-zero-runtime.log` and `slice-stride-zero-reduction.log`.

## Slice storage contract (2026-10-09)

The authorized ABI migration is implemented. Every slice carries `(data, length,
signed byte stride)`. Packed i32 arrays use `+4`; native values use
`-8 * element_words`. Borrowing retains the original place. Descriptor copies,
parameters, returns, fields, enum payloads, and slices of slices preserve all
three components. Owned array copies remain independent. Strings remain two
words; earlier native objects must be rebuilt for private object format version 3.

The two retained inline-array borrow tests now pass unchanged. **All 246
execution/rejection checks pass**, with no exclusions, in three disjoint groups
of 82 (33.24, 60.02, and 40.03 seconds). All 25 layout, specialization,
interface/object-format, and resource/lifetime checks and eight GPU
interface-export checks pass. The full gate includes the explicit dotted-method
checks below. Logs are `slice-stride-matrix-{a,b,c}.log`,
`slice-stride-contracts.log`, and `slice-stride-export.log` under
`tests/fixtures/stdlib_compiler_state`; the matrix manifest retains its partition
and binary identity.

`slice_stride_compositions.lani` exercises packed and inline native arrays through
the same concrete function, register/stack arguments, returned views, local and
imported generics, Option payloads, records, and arrays of slices. It checks
aliases and neighboring fields and prints exactly `native\npacked\n`.
Negative and past-end native-backed indexes trap with exit 101. The verified IR,
extractor, and proofs are unchanged. Details and contract owners are in
[the storage decision](array-view-storage-decision.md).

The existing 1 MB and 32-parameter performance drivers also execute their
outputs correctly. Medians are 46.696 ms and 414.562 ms, above the preceding
unpaired 37.587 ms and 373.936 ms measurements. Performance preservation is not
established; see [the performance record](stdlib-gpu-performance.md). The overall
generic goal remains unfinished; [remaining work](#remaining-work) is listed below.

## Explicit dotted methods (2026-10-09)

`receiver.method<T, N>(...)` now uses the same ordered argument records and
checked binder as qualified calls. Binding repeats when inference discovers a
method's receiver, including chained calls. Member application identities use
their own name token; chained calls cannot overwrite each other's shared span
start. Receiver and method parameters keep independent scopes.

Verification: 11 focused parser checks, 30 native execution/rejection checks,
and four token-origin and resource/lifetime checks pass. Runtime cases include
local/imported methods, compound types, constants, symbolic forwarding, chained
unused parameters, and explicit conflicts. Logs are
`explicit-dotted-method-parser-final.log`,
`explicit-dotted-method-final-runtime.log`, and
`explicit-dotted-method-contracts.log` under `tests/fixtures/stdlib_compiler_state`.
These checks are now included in the complete slice-storage checkpoint above.
The older matrix and performance numbers below describe their named baselines.

## Mixed nominal constants: verified baseline (2026-10-09)

**Verified source:** caller-side type references are retained after complete
graph validation, and duplicate field visits stop at the first matching instance.
This optimization passes the execution/rejection gate and performance output
checks. It changes five shader payloads and no reflection layouts.

The optimized baseline had **239 passing checks out of 241 registered tests**. The two
parked inline-array borrow tests were excluded at that checkpoint; they were
not rerun or counted as passes. The 20 focused checks take 65.21 seconds including
cold shader preparation; disjoint groups of 110 and 109 controls take 41.77 and
67.73 seconds. All eight GPU interface-export checks pass in 2.97 seconds. The
preceding 25 interface, specialization, record-layout, and resource/lifetime checks
remain applicable: their Rust sources and shader reflection layouts are unchanged.
Every command stays below two minutes.

Mixed type/constant nominal applications now execute locally and through imports.
Tests cover 32 interleaved operands, records, functions, associated methods,
Option/Result composition, zero lengths, unused constants, owned copies, string
and nested Boolean arrays, reference and slice aliases, and empty payloads.
Equal-width types and different constant values retain distinct identities;
conflicting applications reject before executable publication.

One source-operand lane publishes the full nominal type count, constant-position
mask, and interleaving flag. Callable operands reused as nominal results can no
longer retain a provisional type-only count. The ordered operands survive checked
instances, specialization keys, body replay, and semantic-interface version 8.
Version 7 artifacts require rebuilding.

The older symbolic nested-call regression is also fixed. Expected-field lookup
had used a call-inference graph that deliberately refuses substitution. Local and
imported calls now resolve the receiving field through its nominal owner, then
infer the callee's separate parameters. Executable tests distinguish the record's
type slot 0, the caller's type slot 1, and the callee's type slot 0, while keeping
an unrelated nominal constant 5 separate from caller lengths 0, 2, and 3. Known
Boolean arguments still reject when a receiving generic field requires an integer.
All temporary diagnostic markers have been removed.

Call receiver binding and application field expansion have separate passes.
The semantic layout producer owns local/imported field ranges and widths;
lowering consumes those facts and rejects missing layouts. No verified IR,
extractor, proof, or native ABI change is included.

The existing performance tools measured 37.587 ms for the canonical 1 MB compiler
workload and 373.936 ms for the 32-parameter entry. Before the optimization, these
were 38.062 ms and 406.174 ms. The generic entry remains slower than the earlier
unpaired 289.685–326.879 ms observations; performance preservation is not established.
All 20 canonical output programs and the generic program execute with exact
expected output. See [measurements and provenance](stdlib-gpu-performance.md).

Limits remain 32 type slots and 32 constant slots per callable declaration,
32 total operands per nominal application, and the documented bounded graph and
specialization capacities. These tests establish x86_64 Linux execution from the
GPU compiler, not execution of user programs on a GPU. Arbitrary-type generics
remain unfinished: see [remaining work](#remaining-work), especially the
[array-view storage contract](array-view-storage-decision.md), escaping references,
trait method generics, durable object-only bodies, and multi-page imported layouts.

Evidence under `tests/fixtures/stdlib_compiler_state/`:

- `mixed-nominal-constant-runtime-retain-caller-references.log`: 20 optimized focused passes.
- `mixed-nominal-constant-optimized-controls-{a,b}.log`: 219 remaining optimized passes.
- `mixed-nominal-constant-optimized-manifest.json`: all 241 tests, their partition, and binary identity.
- `mixed-nominal-constant-optimized-export.log`: eight optimized interface-export passes.
- `mixed-nominal-constant-runtime-independent-receiving-scopes.log`: 19 focused passes.
- `mixed-nominal-constant-final-controls-{a,b}.log`: 220 remaining passes.
- `mixed-nominal-constant-final-manifest.json`: the complete 241-test partition and binary identity.
- `mixed-nominal-constant-final-contracts.log`: 25 contract passes.
- `mixed-nominal-constant-final-export.log`: eight interface-export passes.
- `mixed-nominal-constant-runtime-symbolic-{diagnostics,stages,materializer}.log`: diagnosis of the missing local return binding before the fix.

The earlier cold driver-preparation timeouts were not language failures. The
pipeline probe now persists completed preparation after its timing span, allowing
bounded commands to prepare individual expensive shaders. This does not establish
acceptable cold-start latency or replace executable tests.

## Last completed explicit integer constant binding checkpoint (2026-10-04)

The executable matrix reports **229 passes and the same two inline-array
borrowing failures across 231 tests**. Four disjoint commands cover every test
once: eleven constant/workspace checks (14.69 seconds), ten explicit type controls
(10.07 seconds), and two control groups (105 passes in 37.93 seconds; 103 passes
and two failures in 63.99 seconds). Their combined elapsed time is 126.68 seconds.
Each command stays below two minutes. Eight parser checks, all eight GPU interface
export tests, and both layout/resource checks pass. These are verification times,
not compiler throughput measurements. Runtime evidence is x86_64 Linux ELF emitted
by the GPU compiler and executed on the host.

**Explicit callable integer constants now execute in the verified forms.**
Local/imported functions and associated methods accept integer literals and scoped
caller constant parameters alongside complete type arguments. Declaration order
owns the operand kind and lexical slot. Type and constant domains each support 32
slots; a 64-operand interleaved header executes locally and through an import.
Receiver/impl constants and a method's own constants retain separate domains.
Tests cover zero, a high-bit unsigned value, unused parameters, nested array
lengths, independent owned copies, conflicts, and missing/wrong-kind operands.
The reserved value `4294967295` rejects; this is a bounded 32-bit constant domain,
not arbitrary-width constant evaluation.

Two private HIR-indexed columns retain each accepted constant operand's tagged
literal or scoped parameter reference. Immutable readers feed the existing checked
call environment; final validation compares that evidence with argument and result
constraints and retains accepted bindings for specialization. Arity/kind errors
report source-labeled `LNC0027`, and conflicting lengths report `LNC0006` before
ELF publication. Known `bool`, `f32`, `str`, and fixed-array constant parameter
annotations reject with `LNC0006` in the tested forms. The interface does not yet
persist constant parameter annotation types; broader typed-constant and object-only
contracts remain open.

A source operand's role does not manufacture a type reference. A scoped constant
name in an explicit operand bypasses ordinary type-expression checking, while the
same name used as an actual type annotation still rejects with `LNC0007`.
Export path classification consumes the declaration-reachable type forest; body
constant operands cannot become exported unknown types. Scoped operand lookup uses
the producer's logical token capacity through the existing uniform allocation,
so reused physical buffer extents cannot alter the lexical hash lookup.

Scalar-only `relay<N>() -> usize { return length<N>(); }` initially failed native
linking because no signature array exposed its constant dependency. Accepted
constant operands now publish that consumed dependency through the shared semantic
value projection. Ordinary constant references and explicit operands resolve
symbolic parameter values through the same late projection during body replay.
Fresh local/imported calls and repeated generic/plain compilations in one workspace
now execute, including zero. Source operand facts remain immutable. The minimal
reproduction is `repro_explicit_constant_only_forwarding.lani`.

The grammar adds two productions while preserving all 290 previous production
IDs. Argument records remain twenty bytes. The two new private columns add
`8 * hir_rows` bytes; no kernel, dispatch, or uniform allocation is added by this
checkpoint. Verified IR, extractor/proofs, semantic-interface version 7 with
twelve-word members, native codegen, specialization scheduler, and native ABI
are unchanged relative to the preceding checkpoint. The enforced shader guard
reports 744 artifacts, maximum 522,460 bytes, digest `c29c4c43ee7e4d4c`.
Compared with the explicit type binding checkpoint, 26 SPV and 20 reflection
payloads change; the largest x86 emitter is byte-identical. No performance or live
allocation measurement was run.

Evidence under `tests/fixtures/stdlib_compiler_state/`:

- `explicit-constant-arguments-focused-final.log`: ten new constant tests and the strengthened workspace control pass.
- `explicit-constant-arguments-type-controls-final.log`: all ten explicit type controls pass.
- `explicit-constant-arguments-controls-a-final.log`: 105 controls pass.
- `explicit-constant-arguments-controls-b-final.log`: 103 controls pass; the two unchanged inline-array borrow assertions fail with `LNC0017`, native LIR opcode 21.
- `explicit-constant-arguments-parser-final.log`: eight parser checks pass.
- `explicit-constant-arguments-export-final.log`: eight interface export checks pass.
- `explicit-constant-arguments-unit-final.log`: both layout/resource checks pass.
- `explicit-constant-arguments-original-runtime-final.log`: the original literal-argument reproduction emits an ELF that exits zero.
- `explicit-constant-arguments-checkpoint.json`: source, binary, shader, coverage, and log identities.

Intermediate lookup, operand-role, export, and body-replay failures remain in the
earlier logs; the final results above supersede them. The overall generics goal
and architecture consolidation remain unfinished. General constant expressions,
ordinary const-item operands, further typed/scoped constant forms, dotted explicit
methods, durable object-only generic bodies, and the pending array-view ABI
contract remain dependencies. See [Remaining work](#remaining-work).

## Prior explicit type binding checkpoint (2026-10-04)

The executable matrix reports **219 passes and the same two inline-array
borrowing failures across 221 tests**. It ran in two commands: ten new explicit
binding tests pass in 11.25 seconds; the 211 existing controls report 209 passes
and two failures in 99.44 seconds. Their combined elapsed time is 110.69 seconds;
this is not a single full-suite run or a throughput measurement. Seven parser
checks, all eight GPU interface export tests, and both layout/resource checks pass.
Runtime evidence remains x86_64 Linux ELF emitted by the GPU compiler and run on
the host.

**Explicit function and associated-method type arguments now execute in the
verified forms.** Local and imported calls consume the declaration's complete
own header in source order. The binder maps each argument to its lexical type
slot, independently of receiver/impl parameters. It validates arity, kinds, and
the 32-slot domain before publishing the mapping. An immutable reader obtains
each argument's complete checked reference in the caller's scope. This includes
symbolic caller parameters; scalar caches do not decide compound type identity.

Explicit references feed the same inference and substitution contracts as
argument, receiver, and expected-result evidence. They supply integer literal
context and unused parameters without allowing a known value or result annotation
to replace the source application's type. Final validation compares complete
references and retains accepted bindings for native specialization, including
parameters unused in the signature and body. Conflicting type evidence reports
`LNC0006`; malformed arity or unsupported argument kinds report source-labeled
`LNC0027` before ELF publication. A named constant operand declared with another
scalar than its constant parameter (a `u32` constant for a `u64` parameter, an
`f32` constant for an `f64` parameter) is conflicting type evidence and reports
`LNC0006` at the operand; an integer literal operand outside the parameter's
range reports `LNC0069` at the literal.

The tests execute scalars, strings, references, borrowed string slices, nested
nominal/array applications, nested zero-sized arrays, result-only explicit
types, and symbolic forwarding inside a generic body. Both local and imported
`Mine<T0, ..., T31>` programs use all 32 explicit slots with mixed scalar/array
fields, check every field, and mutate copies to verify independent owned storage.
A separate 32-parameter test binds unused parameters. Reference and slice tests
verify mutations through aliases and exact output. Local
`Box<bool>::make<i32>(42)` and imported `Box<bool>::make<[i32; 2]>(values)`
forms keep receiver and method headers distinct. The imported inferred-method
control also executes.

Associated calls now use the final applying name token for method metadata.
Receiver collectors consume the already checked instance argument rows instead
of reconstructing them from a whole path's tokens. Imported qualified receivers
retain their resolved nominal identity before structural matching, and the
accepted complete receiver survives for return substitution and required-slot
validation. The legacy call identity remains valid for existing actual claims.

This adds one binding kernel, reusing the existing twelve-byte indirect dispatch
packet, and four private workspace columns: three words per token row and one
word per HIR row. Shared aliases read existing parser/type buffers. Verified IR,
extractor/proofs, semantic-interface version 7, and native ABI are unchanged.
The guard reports 744 artifacts, maximum 522,460 bytes, digest
`2f16e4bdb9af9789`. Compared with the segmented-application checkpoint, 14 SPV
and 15 reflection payloads change; the largest x86 emitter is byte-identical.
This build has no throughput or allocation measurement.

Evidence under `tests/fixtures/stdlib_compiler_state/`:

- `explicit-call-binding-focused-accepted-receiver-fix.log`: ten new tests pass.
- `explicit-call-binding-existing-controls.log`: 209 passes, two retained failures.
- `explicit-call-binding-parser.log`: seven parser checks pass.
- `explicit-call-binding-export.log`: eight interface export checks pass.
- `explicit-call-binding-unit.log`: both layout/resource checks pass.
- `explicit-call-binding-checkpoint.json`: source, binary, shader, and log identities.

The earlier build/focused logs retain intermediate resource initialization and
receiver ownership failures. The final logs above supersede those results.
`repro_ordinary_string_comparison.lani` independently rejects with `LNC0006`
without generics; its control is retained in
`explicit-call-binding-ordinary-string-control.log`. Explicit string forwarding
is verified through exact stdout, without relying on that unsupported operator.

The overall generics goal and architecture consolidation remain unfinished.
Explicit callable constant grammar/bindings, the pending array-view storage
decision, dotted explicit method syntax, and the other dependencies in
[Remaining work](#remaining-work) remain open. Dotted explicit calls are
unverified; these results establish the listed associated-call forms.

## Prior segmented application checkpoint (2026-10-04)

The native execution gate reports **210 passes and the same two inline-array
borrowing failures out of 212 tests**, in 102.92 seconds. Seven focused parser
checks, all eight GPU interface export tests, and the two record-layout/resource
checks pass. Execution remains x86_64 Linux ELF emitted by the GPU compiler and
run on the host; user-program GPU execution is not established.

Every type argument now retains its applying path segment's name token in the
private parser record. `Wrap<T>::make<U>()` has two independent ranges, including
when a list contains nested applications. A weighted scan allocates each list's
complete contiguous span; ordinal scatter fills it independently of semantic HIR
row order. Canonical validation checks list membership, ordered rows, and the
segment identity. The old nominal type range remains available for type consumers;
whole value paths no longer combine receiver and method headers. Named receiver
collection reads the receiver segment, while type expressions and record
constructors read their final segment. Constructor debug readbacks retain their
original argument lists.

Structural angle ownership also classifies the parentheses after an explicit
callable header. Tests cover comments, qualified paths, scalar/string/array/
reference/slice arguments, 5 and 32 arguments per header, nested `>>`, and ordinary
comparison and shift operators. The private `HirTypeArg` record is now twenty
bytes, and the retained segment range is token-indexed. GPU semantic-interface
version 7 and its twelve-word member format remain unchanged.

**Explicit function and method arguments were not executable at this checkpoint.**
The parser retained them, but the producer mapping declaration order and parameter
kinds into accepted checked bindings was missing. A final semantic boundary gave
source-labeled `LNC0027` instead of silently ignoring the header. Executable
compilation rejected matching/conflicting explicit types, arguments on a nongeneric
function, an associated method with independent receiver/method lists, and an
imported function. The validation operation is registered and recorded before
status readback. Its dispatch consumes the parser's actual argument count, since
lexical declaration flags cannot prove an imported callable has no explicit
arguments. Empty argument families publish zero workgroups.

This adds one small validation kernel and one twelve-byte private dispatch packet;
list packing reuses the existing scan stages. Verified IR, extractor/proofs, and
native ABI are unchanged. The complete generics goal and architecture consolidation
remain unfinished. Explicit constant syntax/binding, inline-array borrowed storage,
and the remaining dependencies below are still open.

Evidence under `tests/fixtures/stdlib_compiler_state/`:

- `segmented-generic-applications-generics-gate.log`: 210 passes, two retained failures.
- `segmented-generic-applications-parser-final.log`: seven parser tests pass.
- `segmented-generic-applications-boundary-dispatch.log`: all five rejection cases pass.
- `segmented-generic-applications-export.log`: eight interface tests pass.
- `segmented-generic-applications-unit.log`: layout and resource checks pass.
- `segmented-generic-applications-checkpoint.json`: source, binary, and shader identities.

The enforced shader guard reports 743 artifacts, maximum 522,460 bytes, digest
`60429062696446f0`. Compared with the preceding ordered-header checkpoint, 23 SPV
and 23 reflection payloads changed, including the new validation kernel. The
largest x86 emitter is byte-identical. No throughput benchmark was run; test-suite
elapsed time does not establish compiler performance preservation.

## Prior ordered parameter checkpoint (2026-10-04)

The native execution gate reports **209 passes and the same two inline-array
borrowing failures out of 211 tests**, in 109.03 seconds. The GPU export suite
passes all eight tests, the interface transport/validation suite passes ten, and
the existing type-checker resource/lifetime check passes. This is x86_64 Linux
execution on the host; user-program GPU execution is not established.

GPU semantic-interface version **7** preserves each generic parameter's source
ordinal in its own lexical header. It is independent of the type/constant binding
slot, flattened member position, and nominal receiver argument position. Export
reads the parser-owned, source-ordered generic parameter range. Free/nominal,
impl, and method headers retain separate owners and independent ordinals. Tests
export 5 and 32 interleaved type parameters and constants, including unused free
parameters and method parameters alongside reversed impl parameters.

Member records now have twelve words. One shared shader layout constant and one
shared Rust layout constant feed all serializers, capacity calculations, identity
writers, and dependency readers. Ordinary members publish an invalid parameter
ordinal. Validation requires complete, unique source ordinals within each lexical
header; malformed order and unexpected ordinary-member ordinals reject. Binary
transport and dependency rebasing preserve order, and version 6 artifacts reject
before their shorter records are interpreted. Verified IR and native ABI are
unchanged. There is no new kernel or dispatch.

This completes the declaration-order prerequisite for explicit applications.
Function type/constant arguments still reject in parsing; path-segment ownership
and publication into the accepted call environment remain unfinished. The existing
whole-path argument relation must not conflate `Wrap<T>::make<U>` lists. The full
generics goal and architecture consolidation are not complete.

Evidence under `tests/fixtures/stdlib_compiler_state/`:

- `ordered-generic-headers-unit.log`: ten transport and validation tests pass.
- `ordered-generic-headers-export-final.log`: eight GPU export tests pass.
- `ordered-generic-headers-resource.log`: one resource/lifetime test passes.
- `ordered-generic-headers-generics-gate.log`: 209 passes and two retained failures.
- `ordered-generic-headers-checkpoint.json`: source, binary, and shader identities.

The initial export process stopped at its 60-second test timeout. A timing-enabled
retry passed in 4.93 seconds; the full export suite subsequently passed within the
unchanged normal timeout in 2.28 seconds. The first timeout was not reproduced;
its original log is retained. No throughput benchmark was run. Of 1,484 prior
SPV/reflection payloads, 26 SPV files and one reflection changed; the largest x86
emitter's SPV is byte-identical. Shader digest is `edc296462ca13666`, with 742
artifacts and maximum 522,460 bytes under the enforced 524,288-byte guard.

## Prior imported requirement checkpoint (2026-10-04)

The complete execution gate reports **209 passes and the two retained
inline-array borrow failures out of 211 tests**, in 107.95 seconds. No other
failures appeared. Execution remains x86_64 Linux ELF emitted by the GPU compiler
and run on the host.

Local and imported calls now share the declared-requirement validator after
inference closes. Imported free functions retain independent type/constant counts
from declaration member metadata; imported methods retain the existing complete
impl/method counts. Signature uses cannot hide an unused parameter. The counts
remain valid after a dependency page is replaced and never overwrite local
owner counts or nominal argument arity.

The existing dependency member scan also counts constants separately from total
arity. Call projection reads those counts in constant time. A shared count view
feeds the existing compact requirement rows and exact binding indexes; no new
kernel or dispatch is introduced. Two private workspace columns add one word per
source-token row and one word per dependency-declaration row. The resource check
verifies initialization, immutable validation reads, producer ownership, distinct
live storage, and lifetime through the final validator. No verified IR schema,
semantic-interface format, or native ABI changed.

Missing imported type/constant bindings now reject during checking with
source-labeled `LNC0006`, including parameters unused in the signature/body,
a missing middle constant, slot 31 in both independent domains, associated calls,
and method parameters alongside an inferred impl parameter. The original
imported missing-method programs retain their rejection assertions and now require
the checker diagnostic and source label. Existing valid compound and constant
method programs still execute; the full gate includes the local/imported
32-parameter value, receiver, and constant compositions.

The retained CLI reproducer previously gave `LNC0006` in `check` and an unlabeled
`LNC0017` during native compilation. Native compilation now gives source-labeled
`LNC0006` too. Evidence under `tests/fixtures/stdlib_compiler_state/`:

- `imported-required-bindings-generics-gate.log`: 209 passes, two retained failures.
- `imported-required-bindings-methods-final.log`: three method tests pass.
- `imported-required-bindings-free-final.log`: eight incomplete imported calls reject.
- `imported-required-bindings-resource-final.log`: one resource/lifetime test passes.
- `imported-required-bindings-compile-before.log` and `*-compile-after.log`: CLI boundary.
- `imported-required-bindings-checkpoint.json`: current source/binary/artifact identities.

Earlier focused/resource logs retain the intermediate initialization failure and
the build command whose exact filter selected zero unit tests; the final resource
log above runs the qualified test and supersedes them. Shader digest is
`f578fa7cda586116`, 742 artifacts, maximum 522,460 bytes under the unchanged
enforced 524,288-byte guard. This requirement change has not been benchmarked;
the figures in the next checkpoint describe the preceding measured build.

### Explicit application dependency

The earlier type and constant probes both rejected with `LNC0016`; their retained
before logs are historical. The segmented-application checkpoint parsed type
headers but rejected them with `LNC0027` until the checked binder existed.
The current checkpoint executes the verified local/imported function and
associated-method type headers. `repro_explicit_method_binding.lani` executes
with exit 42; `repro_explicit_callable_binding.lani` supplies a conflicting known
value and correctly rejects with `LNC0006`. Explicit constant arguments still
lack grammar and checked binding support. Explicit record applications execute.

Version 7 retains declaration order independently of binding slots, and the parser
retains each segment's ordered argument range. Caller-side checked types now
enter the accepted call environment through an immutable source-binding reader.
Own function/method headers remain distinct from inherited impl and nominal
receiver parameters. Arity, kind, conflict, missing-binding, and resource-bound
checks run before executable publication. Constant references and further call
forms still need implementation or executable evidence; arbitrary-type generic
completeness is not established.

## Prior method result ownership checkpoint (2026-10-04)

The complete execution gate reports **208 passes and the two retained
inline-array borrow failures out of 210 tests**, in 100.64 seconds. Seven focused
structural receiver tests and the type-checker resource/lifetime check pass.
Execution is x86_64 Linux ELF emitted by the GPU compiler and run on the host.

Method lookup publishes callable identity and the declaration signature.
Accepted complete receiver bindings and result substitution belong to the shared
call materializer. The competing local and imported positional/name-based return
projectors have been removed. Complete argument rows remain authoritative; the
unused argument-hash buffer, producer kernel, allocation, and dispatch are removed.
No verified IR schema or native ABI changed.

Two new local/imported programs execute `Mine<A0, ..., A31>` methods with a nested
`Cell<T0>` receiver argument and reversed impl parameter declaration order.
They check both endpoint substitutions and every field of a returned record:
unsigned extrema, strings, nested records, fixed arrays, zero-sized arrays,
references, slices, and Booleans. Owned copies remain independent after mutations;
views preserve their original backing aliases. Exact output is
`Ω\nλ\nΩ\nλ\nΩ\nΩ\nΩ\nΩ\n`, with empty stderr and exit zero.

Evidence under `tests/fixtures/stdlib_compiler_state/`:

- `receiver-result-owner-generics-gate.log`: 208 passes, two retained failures.
- `receiver-result-owner-focused.log`: seven receiver tests pass.
- `receiver-result-owner-resource-contract.log`: resource/lifetime check passes.

The unchanged enforced 524,288-byte shader guard records 742 artifacts, maximum
522,460 bytes, digest `68fa380c21cd0c29`. The existing 1 MB preset measures
**47.642 ms compiler / 51.741 ms wall median** across 20 distinct programs. All
source identities, cache/resource facts, and emitted ELFs were validated. The
existing generic 32-parameter driver measures **326.879 ms**, then **289.685 ms**
in a repeat on the same frozen build; both final ELFs pass exact output checks.
These unpaired medians are 7–21% above the preceding generic checkpoint. Canonical
compiler time is 9.1% above its preceding unpaired run. Performance preservation
and causal attribution are not established. An instrumented profile observes
16 inference closures, each converging in two rounds; it does not explain the
timing difference. New local/imported 32-parameter receiver cases measure
517.477/390.165 ms and have no preceding baseline.

Tracked live memory is 1,584,713,263 bytes, up 8,601,648; five raw buffers with
unavailable sizes are excluded. Frozen source/binary identities, the canonical
runner's CLI rebuild transition, all 1,484 SPV/reflection hashes, both generic
runs, and independent validation are retained under
`benchmark_artifacts/performance/stdlib-gpu-20261004-receiver-return-owner/`.
The remaining dependencies below stay in scope; this gate does not establish
arbitrary-type generic completeness.

## Prior structural method receiver checkpoint (2026-10-04)

The complete execution gate reports **206 passes and the two retained
inline-array borrow failures out of 208 tests**, in 99.96 seconds. Local and
imported inherent methods now execute with array and nested record receiver
patterns, including `impl<T> Wrap<[T; 2]>`, `impl<T, const N: usize> Wrap<[T; N]>`,
and `impl<T> Wrap<Cell<T>>`.

Method indexes select candidates by nominal owner, argument count, and name.
Complete checked receiver constraints decide applicability; shallow argument
hashes no longer decide whether a method matches. Duplicate patterns are checked
in both directions, preserving repeated type and constant parameters across
alpha renaming. Conflicting bindings, overlapping matches, and equivalent
duplicate methods reject with `LNC0027` and source labels. The duplicate-method
label describes equivalent receiver patterns rather than reporting a syntax
error. Accepted receiver bindings publish both domains into the existing call
environment before return materialization and concrete body replay.

Impl header context consumes completed raw bracket depths, so `[T; N]` cannot
terminate that context. Array lengths retain their constant-value identifier
role. Qualified applications nested inside generic arguments retain their type
role even inside a constructor value path, including packed `>>` closers.

Five focused execution/rejection tests pass. Their emitted x86_64 Linux programs
check ordinary and generic array receivers, Unicode strings, nested records,
reference aliases, shared slices, independent owned copies, zero-sized arrays,
inferred lengths, and method-level arguments. The local and imported composition
programs each print `Ω\nΩ\nλ\nΩ\n` with empty stderr and exit zero. Three focused
parser checks, all 23 semantic parser controls, and the parser/type-checker
resource and lifetime checks pass. No verified IR schema or native ABI changed.
The enforced 524,288-byte shader guard still records 743 artifacts, maximum
522,460 bytes; the execution build digest is `de3670a04c070cff`.

Evidence is retained under `tests/fixtures/stdlib_compiler_state/` in
`nested-impl-generics-gate.log`, `nested-impl-checked-pattern-final-focused.log`,
`nested-impl-parser-qualified-compositions-focused.log`,
`nested-impl-semantic-token-regressions.log`,
`nested-impl-parser-resource-contract.log`, and
`nested-impl-typecheck-resource-contract.log`. Earlier `nested-impl-*` logs retain
the intermediate failures. This receiver change has not yet been benchmarked;
the performance figures below belong to the preceding checkpoint. Further type
compositions and the dependencies listed below remain in scope.

## Prior explicit record constructor checkpoint (2026-10-04)

The complete execution gate reports **201 passes and the two retained
inline-array borrow failures out of 203 tests**, in 94.52 seconds. Explicit
local and qualified imported record applications now execute, including
`core::five::Five<i32, bool, char, u32, i32> { ... }` and a constructor with
32 ordered mixed type arguments. The preceding receiving-context checks remain
in this gate. The checked-window sample also passes unchanged.

Three shared contracts close the explicit-constructor gap:

1. Raw angle depths and the minimum search hierarchy identify a complete value
   path application before semantic brace and bracket classification. A shared
   value-path helper handles direct array type arguments and nested closing
   `>>` tokens. Constructor braces consume this structural evidence.
2. Grammar-owned argument links retain every argument after a comma in value
   paths. The existing pointer-jump rank and compact scatter publish the complete
   ordered list. Named application collection and argument-reference scatter
   share an owner accessor: type expressions and record constructors apply the
   final path segment; associated value paths apply their receiver segment.
3. An explicit application's checked arguments are actual type evidence,
   including lexical parameters inside a generic body. Receiving context fills
   bare constructors and validates explicit applications without replacing their
   arguments. Field projection and expression context therefore agree on one
   actual source application and reach convergence.

The former false acceptance of `Cell<i32> { value: 1 }` where `Cell<u32>` was
required now rejects with `LNC0006` and a source label. Six negative programs
cover calls, bindings, returns, nested fields, imported identities, and an
incorrect Boolean field. Their assertions were not weakened. The larger
composition initially exposed an inference oscillation; preserving explicit
actual applications closes it rather than imposing an iteration cutoff.

Four focused compiler tests pass. Emitted programs verify imported five-argument
construction; unsigned maximum fields; strings and Unicode output; fixed arrays;
nested local/imported records; independent owned copies; explicit construction
inside a generic body; and Option payloads. A 32-parameter constructor checks
all mixed fields, including empty nested arrays, references, and slice aliases.
The composed program prints `Ω\nΩ\nλ\nΩ\n`; the 32-parameter program prints
four `Ω` lines. Two focused parser tests preserve ordered arguments for 5 and
32 parameters, both local and qualified, and accept separated and packed angle
closers. All 22 existing semantic token/ownership checks pass.

Parser reflection/resource-lifetime checks and the type-checker resource check
both pass. The three raw angle inputs are read-only and survive every consumer.
No new buffer, verified IR schema, or native ABI was introduced. The enforced
524,288-byte shader guard records 743 artifacts, maximum 522,460 bytes.
The current digest is `bf594c3d1d422f3d`; the initial execution build reported
`714ce3a95edfb4a5`. Both were reconstructed from identical artifact bytes: the
builder enumerates cached artifacts before newly compiled ones. Per-artifact
SHA-256 records establish payload identity across the measurements.

The existing 1 MB preset measures **43.660 ms compiler / 46.772 ms wall median**
over 20 distinct programs. All source hashes, cache/resource facts, and emitted
ELFs are independently validated. The existing 32-parameter entry measures
**270.681 ms median** over ten entry recompiles after three warmups and validates
its final ELF. These unpaired medians are 5.6% above and 1.0% below the preceding
runs, respectively; they do not establish causation or a cross-compiler ratio.
Tracked live memory is 1,576,111,615 bytes, excluding five raw buffers with
unavailable sizes. Reports and source/binary/artifact identities are retained in
`benchmark_artifacts/performance/stdlib-gpu-20261004-explicit-records/`.

Evidence under `tests/fixtures/stdlib_compiler_state/`:

- `explicit-record-generics-gate.log`: 201 passes and the two borrow failures.
- `explicit-record-argument-order-focused.log`: four compiler tests pass.
- `explicit-record-argument-order-parser.log`: two parser tests pass.
- `explicit-record-semantic-token-regressions.log` and
  `explicit-record-semantic-ownership-regressions.log`: 19 and three checks pass.
- `explicit-record-parser-resource-contract.log` and
  `explicit-record-typecheck-resource-contract.log`: both resource checks pass.
- Earlier `explicit-record-*` logs retain the original parser rejection,
  false acceptance, oscillation, and incomplete argument list. The final logs
  above supersede those intermediate results.

Runtime evidence remains x86_64 Linux ELF emitted by the GPU compiler and run
on the host. User-program GPU execution is not established. The generics goal
remains active: array view storage/aliasing, further reference/trait capabilities,
explicit constant arguments, durable body context, multi-page layouts,
full-width integers, and wider generic scaling remain unfinished.

## Prior record receiving-context checkpoint (2026-10-04)

The complete executable gate reports **198 passes and two retained inline-array
borrow failures out of 200 tests**, in 94.56 seconds. The three fresh-record
reproductions from the preceding checkpoint now compile and execute:
`repro_call_record_literal_context.lani`,
`repro_local_option_record_literal_context.lani`, and
`repro_generic_option_record_literal_context.lani`.

Record literals consume the shared complete receiving-context relation during
call inference. That relation follows argument, field, array-element, match-arm,
annotated binding, and return ownership. Constructor identity is checked before
publishing context, including the stable identity of imported declarations.
The initial statement-context producer also checks constructor identity, so an
enclosing `Option<Cell<T>>` cannot become the receiving type of its nested `Cell`
literal. Context supplies missing bindings; known values remain actual evidence.
Direct integer field literals consume their scoped field expectation, including
the `u32` maximum `4294967295`.

Expected argument roots now use the existing declaration-expansion service.
It materializes their fields and enum payloads under the accepted receiver
environment before indexing and field projection. Previously an imported
`ImportedEnvelope<str>` root existed without its implied `ImportedCell<str>`
field application, producing `LNC0047`. That composition now executes without
adding a concrete child annotation. The same service handles local/imported
nominal declarations, structural children, and unused enum variants within the
documented 32-argument/64-node bounds.

Five focused tests pass. Their emitted programs verify ordinary and enum
constructor contexts; nested records; unsigned fields; Unicode string arrays;
empty nested arrays; references obtained through the existing borrow method;
slice mutation and original-array aliases; receiving arrays and match arms;
later-argument witnesses; and local/imported construction inside generic bodies.
A `Mine<T0, ..., T31>` receiving context preserves all 32 mixed fields, including
records, arrays, zero-sized arrays, references, and shared slices. Its exact
output is four `Ω` lines. Seven conflicting scalar, known-value, nominal, and
array-length cases reject with `LNC0006` and a source label. No rejection
assertion was weakened. The checked-window sample also passes in the full gate.

The resource/reflection/lifetime check passes and verifies context publication,
field/reference ordering, and participation in inference convergence. The new
record dispatches run only when struct initialization is required. They reuse
existing buffers; no verified IR schema or native ABI changed. Shader digest is
`1eb05daac5b78263`: 743 artifacts, maximum 522,460 bytes, with the unchanged
524,288-byte guard enforced.

The existing 1 MB preset measures **41.354 ms compiler / 44.275 ms wall median**
over 20 distinct programs. All source hashes, cache/resource facts, and emitted
ELFs are independently validated. The 32-parameter entry measures **273.333 ms
median** over ten entry recompiles after three warmups and validates its ELF.
These unpaired medians are 1.0% and 2.4% above the preceding runs; they do not
identify a causal regression or establish a cross-compiler ratio. Tracked live
memory remains 1,583,484,667 bytes, excluding five raw buffers with unavailable
sizes. Reports, source/binary identities, and per-artifact SHA-256 records are
retained in `benchmark_artifacts/performance/stdlib-gpu-20261004-record-contexts/`.

Evidence under `tests/fixtures/stdlib_compiler_state/`:

- `record-context-generics-gate.log`: 198 passes and the two borrow failures.
- `record-context-composition-final-focused.log`: all five focused tests pass.
- `record-context-resource-contract.log`: resource/lifetime ordering passes.
- `record-context-field-closure-focused.log`: intermediate evidence of the
  imported-field fix and two invalid fixture operations, superseded by the final
  focused log. Fixed arrays become slices through calls; direct strings lack
  equality, so output and byte counts check every string field.

Runtime evidence is x86_64 Linux ELF emitted by the GPU compiler and run on the
host. User-program GPU execution is not established. The overall generics goal
remains active: the array storage/alias decision, further reference and trait
capabilities, explicit argument grammar, durable generic bodies, multi-page
layouts, full-width integers, and wider generic scaling remain unfinished.

## Prior structural-header checkpoint (2026-10-04)

The complete executable gate reports **193 passes and two retained inline-array
borrow failures out of 195 tests**, in 93.01 seconds. The two borrow cases rejected
with `LNC0017` under the existing ABI. That gate did not include every known
compiler limitation: three additional record-literal receiving contexts below
reproduced `LNC0006`. The current checkpoint supersedes those three failures.

Nested `match` expressions now execute directly inside `if` and `while`
conditions and inside an outer match scrutinee, including at nonzero enclosing
parenthesis/bracket depth. The former
`repro_match_in_condition_brace_owner.lani` parser rejection now executes.
The generic condition program uses `Option<bool>`, `Option<Cell<bool>>`, and
`Result<bool, i32>` with both branches, changing loop conditions, nested matches
inside an array element, and skipped effects. Its exact output is
`1\n2\n3\n4\n5\n6\n`. The `Cell<bool>` is explicitly typed before being passed
to `Some`; fresh record-literal payload inference remains a separate dependency.

Raw delimiter depths and the existing minimum search hierarchy now publish
before semantic brace ownership. When the prefix owner has been lost to an
inner header, the owner pass recovers the keyword preceding the matching
condition parentheses. Ordinary valid prefix owners retain their fast path.
Bracket-role projection has a separate producer after statement context is
available, preserving its type-array/index/array rules. Both graph registration
and recorded execution use this ordering. This adds one private projection pass
and no buffers or IR/ABI changes.

Two focused parser tests pass, including a header spanning several 256-token
blocks. All 22 existing semantic token tests pass. The parser resource graph
check asserts the producer/consumer ordering and passes. The shader digest is
`fb26a3ca5416983e`: 742 artifacts, maximum 522,460 bytes, with the unchanged
524,288-byte guard enforced. The initial incremental test build reported
`a2dc19b9266420ba`; both digests were independently reconstructed from identical
artifact bytes. The builder hashes cached artifacts before newly compiled ones,
so enumeration order changes its reported digest. Per-artifact SHA-256 records
and `artifact-digest-order-audit.log` retain the byte-identity check; no SPV or
reflection file changed after the initial build. Execution evidence remains
x86_64 Linux ELF run on the host, not user-program GPU execution.

The existing 1 MB preset measures **40.950 ms compiler / 44.045 ms wall median**
over 20 distinct programs; all source hashes, cache/resource facts, and emitted
ELFs are independently validated. The 32-parameter entry measures **266.886 ms
median** over ten entry recompiles after three warmups and validates its ELF.
These are unpaired measurements. The compiler median is 10.6% below and generic
entry median 2.2% above the preceding runs; they do not establish causation or a
cross-compiler ratio. Tracked live memory is 1,583,484,667 bytes, excluding five
raw buffers with unavailable sizes. Details and identities are retained in
`benchmark_artifacts/performance/stdlib-gpu-20261004-structural-headers/`.

### Receiving-context dependency isolated at that checkpoint

All three minimal programs rejected with `LNC0006` at that checkpoint:

- `repro_generic_option_record_literal_context.lani`: imported
  `Option<Cell<bool>> = Some(Cell { value: true })`.
- `repro_local_option_record_literal_context.lani`: the same composition with
  a local generic enum.
- `repro_call_record_literal_context.lani`: an ordinary function accepting
  `Cell<bool>` is called with `Cell { value: true }`.

The imported enum and ordinary-call diagnostics compare the Boolean field
against unresolved generic parameter 0, despite a complete receiving type.
The local enum also reports a type mismatch. The missing context crosses the
record-literal/call boundary; this evidence does not support treating it as an
import-only problem. Directly typing the record first executes in the condition
program above. The current receiving-context checkpoint supersedes this
dependency with a shared fix and executable positive/conflict coverage.
No failing assertions were weakened.

Evidence under `tests/fixtures/stdlib_compiler_state/`:

- `structural-header-generics-gate.log`: 193 passes and two borrow failures.
- `structural-header-parser-focused.log`: two structural header cases pass.
- `structural-header-parser-regressions.log`: 22 token-role cases pass.
- `structural-header-native-final.log`: scalar and generic condition programs execute.
- `structural-header-resource-contract.log`: resource ordering passes.
- `structural-header-*_record_literal_context.log`: the three independent receiving-context rejections.

The overall goal remains active. Further storage, receiving-context, reference,
trait, persistence, explicit constant-argument grammar, and scaling work remains.

## Prior native-contract checkpoint (2026-10-04)

The two native failures from the preceding checkpoint are fixed. The complete
execution gate reports **191 passes and the two retained inline-array borrow
failures out of 193 tests**, in 91.05 seconds. Both borrow cases reject with
`LNC0017`; the [array storage proposal](array-view-storage-decision.md) still
awaits ABI authorization. The checked-window program passes its output, error,
absence, and owned-copy checks.

Relocation placement now consumes the exact implicit epilogue width, including
saved-register restores. The former four-byte estimate patched instruction bytes
after the final imported call and left that call unresolved. The pure
`codegen/lir/x86/frame_layout.slang` module owns frame eligibility, base slots,
and epilogue width for byte counting, emission, and object relocation placement.
The resource graph retains the finalized function and saved-register metadata
through relocation publication. The reduced void function and original mixed
record/string-array copy and mutation program now pass their exact UTF-8 output
assertions without adding explicit returns.

The former nested-match failure also reproduced with a plain integer
`identity(match ...)` argument. Ordinary expression producers now run at their
own completion boundaries. At a shared boundary, inner expressions precede
consumers; equal spans retain expression-depth ordering. Match, short-circuit,
assignment, condition, and range recipes consume those same completion points.
The original generic nested-result program passes SSA validation and executes.
A new effect-order program verifies nested matches through generic calls,
operators, and record fields, left-to-right sibling calls, unselected arms, and
short-circuit skips with exact output `1\n3\n4\n5\n`. It uses the established
`->` syntax for compound match arms; parser restrictions are separate.
The retained unparenthesized record-valued match-call reproduction also compiles
and executes with exact output `Ω\nΩ\n`. A match directly inside an `if`
condition still rejected during parsing at that checkpoint in
`repro_match_in_condition_brace_owner.lani`; the structural-header checkpoint
above supersedes that restriction.

Twenty focused native return/control/I/O checks and eleven resource, reflection,
and specialization checks also pass. Shader digest is `6544f2a90ef57db8`: 741
artifacts, maximum 522,460 bytes, with the unchanged enforced 524,288-byte guard.
No verified IR schema or native ABI changed. Execution evidence is x86_64 Linux
ELF emitted by the GPU compiler and executed on the host; user-program GPU
execution and other targets remain unverified.

The existing 1 MB preset measures **45.818 ms compiler / 48.539 ms wall median**
over 20 distinct programs, all executed and validated. The 32-parameter entry
benchmark measures **261.105 ms median** over ten recompiles after three warmups
and validates its ELF. Compiler time is 4.6% higher and generic entry time 0.2%
higher than the preceding unpaired runs. These comparisons do not isolate a code
regression or establish a cross-compiler ratio; see the
[performance report](stdlib-gpu-performance.md).

Evidence under `tests/fixtures/stdlib_compiler_state/`:

- `native-completion-order-generics-gate.log`: 191 passes and two borrow failures.
- `native-completion-order-effect-order.log`: selected-arm effects and sibling order pass.
- `native-completion-order-control-gate.log`: seventeen focused native controls pass.
- `native-footer-contract-returns.log`: three return/I/O controls pass.
- `native-completion-order-resource-contracts.log`: eleven contract checks pass.
- `mixed-nested-strings-void-show-call-trace.log`: pre-fix missing final call.
- `native-completion-order-match_call_argument_syntax.log`: unparenthesized match calls compile; the emitted ELF was separately executed and checked.
- `native-completion-order-match_in_condition_brace_owner.log`: retained parser rejection.

The overall generics goal remains active. Storage aliases, further reference and
trait capabilities, explicit constant-argument grammar, persisted generic bodies,
additional parser contexts, and wider generic workload scaling remain unfinished.
The accepted declaration/argument/result environments retain their shared owners
and independent 32-slot type and constant domains.

### Prior nested-result checkpoint (2026-10-04)

Expected result types now reach calls nested in arguments, record fields, and
array elements. The shared receiving-context walk also handles match arms,
but its new nested-match program still fails native SSA dominance validation.
Local and imported functions and methods use complete declaration patterns;
symbolic forwarding and all 32 type bindings execute. Record fields retain
their substitution scope explicitly, and checked graph metadata has one buffer
owner. Imported pattern validation runs after complete member/index references
are available and checks stable declaration identity.

Actual call results preserve known argument types, using result constraints for
missing bindings. Giving result expectations precedence here caused an invalid
forwarded slice call to oscillate indefinitely; its existing 25-case rejection
matrix now finishes in 4.94 seconds. Result-context mismatches during inference
publish no facts. A final invocation checks the closed context before native
publication. This restores method lookup through inferred generic call results
without accepting incompatible arguments.

The existing 181-test gate reports **179 passes and two retained borrow
failures** in 87.30 seconds. The nine new nested-result tests report **seven
passes and two failures**. Rechecking the seven prior result-constant tests
alongside them yields 14 passes and two failures in 8.48 seconds. Combined
coverage is 190 tests, with four remaining failures:

| Failure | Current evidence |
| --- | --- |
| Two inline-array borrow cases | Explicit `LNC0017`; the [array storage proposal](array-view-storage-decision.md) awaits ABI authorization. |
| Match arms nested inside array expressions | Type checking succeeds; native SSA dominance rejects with reason 17. |
| Mixed record containing nested string-array enum payloads | The original copy/mutation program exits zero but omits two expected output lines. Its assertion remains failing. A smaller void-function reproduction also omits its last output; adding an explicit return restores it. The underlying lowering defect remains unresolved. |

Plain nested string arrays, the same arrays in generic enum payloads, and reduced
record construction/return/parameter cases execute with exact UTF-8 output and
byte counts. These reductions do not establish correctness of the failing
program. The ten resource/reflection/specialization checks and four focused
parser checks pass. Shader digest is `c1a8b52c1f408f18`: 741 artifacts, maximum
522,460 bytes, with the unchanged enforced 524,288-byte guard. No verified IR
schema or native ABI changed.

Current performance is **43.793 ms compiler / 46.993 ms wall median** for 20
distinct one-megabyte programs, all executed and validated. The 32-parameter
entry benchmark measures **260.563 ms median** over ten recompiles after three
warmups and validates its ELF. These are unpaired measurements; see the
[performance report](stdlib-gpu-performance.md).

Evidence under `tests/fixtures/stdlib_compiler_state/`:

- `nested-result-final-context-existing-gate.log`: 179 passes, two borrow failures.
- `nested-result-final-context-focused.log`: 14 passes, two new native failures.
- `nested-result-final-context-method-and-conflict.log`: inferred method chain and rejection matrix pass.
- `nested-result-final-context-resource-contracts.log`: ten contract checks pass.
- `nested-result-final-context-parser-contracts.log`: four parser checks pass.
- `mixed-nested-strings-void-show-output.log` and `mixed-nested-strings-explicit-return-output.log`: reduced failure and explicit-return control.

The overall generics goal remains active. The two new native defects, storage
alias support, explicit constant-argument grammar, reference/trait capabilities,
persisted generic bodies, and wider workload scaling remain unfinished.
Execution evidence is x86_64 Linux ELF emitted by the GPU compiler and executed
on the host; user-program GPU execution and other targets remain unverified.

### Prior result-only constant checkpoint (2026-10-03)

Annotated local bindings and declared returns now infer constant parameters
from the complete result pattern, alongside type parameters. Result constraints
have an independent tagged 32-slot constant domain; zero is a valid binding.
The declaration matcher reads both domains without substituting provisional
argument facts. Argument/result contradictions and repeated-parameter conflicts
reject with source-labeled `LNC0006` after inference closes.

Local and imported free functions, borrowed generic receiver methods, and
associated functions execute these environments. Imported functions export a
function signature, while imported methods export their return pattern directly.
Both now use the shared callable-return accessor. Final result validation
consumes the accepted call-result relation. Retention batches published masks
and copies only accepted constant rows, resolving unique symbolic caller values
in a bounded readback; the host does not infer bindings.

All **seven new focused tests pass** in 4.25 seconds. They cover zero and
nonzero lengths, nested dimensions, constant-only functions, symbolic forwarding,
impl/method composition, static methods, all 32 constant slots, concrete body
replay, and local/imported conflicts. The method program also checks exact UTF-8
receiver output and its byte count. The workspace-reuse test alternates the new
result-only job with ordinary jobs. The full gate reports **179 passes and the
same 2 inline-array borrow failures** out of 181 tests, in 95.14 seconds. Both
failures explicitly reject with `LNC0017`; the
[array storage proposal](array-view-storage-decision.md) remains awaiting ABI
authorization. The checked-window program passes with exact output `96\n`.

The resource/lifetime check and all eight specialization unit tests pass.
Shader digest is `49ceefb7cccfcae5`: 741 artifacts, maximum 522,460 bytes,
unchanged enforced 524,288-byte guard. No verified IR schema or native ABI
changed. Runtime evidence is x86_64 Linux ELF emitted by the GPU compiler and
executed on the host; user-program GPU execution and other targets remain
unverified.

The existing 1 MB preset measures **56.074 ms compiler / 59.229 ms wall median**
over 20 distinct programs, all executed and validated. The existing 32-parameter
entry benchmark measures **293.330 ms median** over ten recompiles after three
warmups and validates its final ELF. These unpaired measurements are higher than
the preceding checkpoint. Opposite-order paired nongeneric controls put current
and preserved-baseline averages within 1%; concurrent GPU activity was also
observed. The controls use a different corpus and an older baseline, so they do
not resolve the canonical increase or establish general generic scaling. See
[the performance report](stdlib-gpu-performance.md).

Evidence under `tests/fixtures/stdlib_compiler_state/`:

- `result-only-constant-before.log`: the original minimal failure.
- `result-only-constant-focused-final.log`: seven focused tests pass.
- `result-only-constant-execution-gate.log`: 179 passes and two retained borrow failures.
- `result-only-constant-resource-contracts.log`: resource/lifetime check passes.
- `result-only-constant-specialization-contracts.log`: eight specialization tests pass.

The small reproduction is
`tests/fixtures/stdlib_foundation/repro_generic_result_only_constant.lani`.
Expected-result inference for calls nested in arguments, record fields, and
array elements still needs executable coverage and implementation where missing.
Explicit constant-argument grammar, imported missing-binding diagnostics,
storage/alias support, reference/trait capabilities, persisted generic bodies,
and workload scaling also remain unfinished. The overall generics goal is active.

### Prior constant value checkpoint (2026-10-03)

Constant parameters now execute as ordinary values in generic bodies. Lexical
lookup preserves the exact declaration and its annotated type; local and value
parameter shadowing retain priority. Bound constants become semantic values.
Unbound uses remain tagged symbolic facts and keep a function as a template
until concrete replay supplies every declared type and constant binding.
Local calls validate required constant slots, including unused declarations,
with a source-labeled `LNC0006` diagnostic. Assignment to a constant rejects
explicitly (`LNC0016` for parser-rejected assignments, `LNC0068` for checked
compound assignments); mutable local shadows remain valid. Noninteger constant
annotations cannot authorize array lengths.

Array literal syntax now supplies dimensions independently of element types.
The expected-expression producer materializes the complete leaf once, wraps it
in the literal dimensions, and leaves inference and strict validation to the
original declaration pattern. Empty and nested-empty arrays therefore provide
length evidence without guessing missing element types or inner dimensions.
Imported associated functions use dependency target resolution, and imported
array validation consumes the complete composed call environment.

All **ten new focused tests pass**. They execute arithmetic, loops, indexing,
zero lengths, declared integer types, lexical shadowing, local/imported
functions, borrowed methods, associated functions, and nested array literals.
They also verify rejection of missing bindings, invalid value uses, mutation,
noninteger lengths, contradictory dimensions, and unbound element types.
The existing 32-constant test now reads early and late slots in arithmetic and
executes local/imported forwarding. The full gate reports **172 passes and the
same 2 inline-array borrow failures** out of 174 tests, in 96.94 seconds. Both
failures explicitly reject with `LNC0017`; the pending
[array storage proposal](array-view-storage-decision.md) describes the required
alias contract. The checked-window program passes with exact output `96\n`.

The resource/lifetime and parser graph checks, eight specialization unit tests,
and three diagnostic-registry tests all pass. Current shader digest is
`3143f245e4678848`: 741 artifacts, maximum 522,460 bytes, unchanged enforced
524,288-byte guard. No verified IR schema or native ABI changed. Execution is
x86_64 Linux ELF emitted by the GPU compiler and run on the host; user-program
GPU execution and other targets remain unverified.

The existing 1 MB preset measures **41.726 ms compiler / 44.879 ms wall median**
over 20 distinct programs; all 20 ELFs execute with validated output. The
existing 32-parameter entry benchmark measures **285.815 ms median** over ten
entry recompiles after three warmups and validates its final ELF. These are
unpaired measurements. First-run initialization remains a performance concern;
[the performance report](stdlib-gpu-performance.md) records the observations and
measurement limits.

Evidence under `tests/fixtures/stdlib_compiler_state/`:

- `constant-value-focused-final.log`: ten focused tests pass.
- `constant-value-execution-gate.log`: 172 passes and two retained borrow failures.
- `constant-value-typecheck_graph_tracks_operation_workspace_lifetimes-contracts.log`: resource/lifetime check passes.
- `constant-value-frontend_graph_contains_exact_scan_regions-contracts.log`: parser graph check passes.
- `constant-value-type_checker-generic_body-tests-contracts.log`: eight specialization tests pass.
- `constant-value-diagnostic_code_registry_-contracts.log`: three registry tests pass.

The small value-expression reproduction is
`tests/fixtures/stdlib_foundation/repro_generic_constant_value_expression.lani`.
Further result-only and explicit constant-argument contexts, imported
missing-binding diagnostics, storage/alias support, reference/trait capabilities,
persisted generic bodies, and generic workload scaling remain unfinished. The
overall arbitrary-type generics goal is still active.

### Prior constant domain checkpoint (2026-10-03)

Constant array lengths now use complete checked references: either a literal,
including zero, or a declaration-scoped caller parameter. The shared structural
matcher infers lengths at every array level through local and imported calls.
Type and constant bindings have separate 32-slot domains. The complete indexed
claim relation replaces outer-array-only inference and the four-slot constant
cache. Conflicting bindings are validated after inference closes.

Symbolic bindings survive retained calls and generic-body forwarding. During
concrete body replay, the GPU publishes the selected owner's constant values;
retention copies these values in one batched readback. Pending parameters cannot
authorize executable specialization. Both claim counts reset on every job,
including monomorphic jobs which skip generic claim passes. Array return
validation now compares complete structural references rather than immediate
element rows.

All **six focused tests pass**, covering nested dimensions, zero lengths,
Unicode string descriptors, independent owned copies, local/imported forwarding,
all 32 constant slots, seven conflicting calls, and explicit rejection of a
33rd slot. Declaration publication reports the limit at the parameter even
when it is unused. The full execution gate reports **162 passes and the same
2 inline-array borrow failures** out of 164 tests, in 92.34 seconds. Both
failures remain explicit `LNC0017` rejections. The graph/reflection/resource
lifetime check and all eight specialization unit tests pass. The checked-window
program also passes in the full gate with exact output `96\n`.

Checkpoint shader digest: `1e60d9e7da516426` (741 artifacts; largest 522,460 bytes
under the unchanged 524,288-byte guard). No verified IR schema or native ABI
changed. Execution evidence is x86_64 Linux ELF emitted by the GPU compiler
and run on the host; user-program GPU execution and other targets remain
unverified. The arbitrary-type generics goal remains unfinished.

The existing 1 MB preset measures **41.711 ms compiler / 44.831 ms wall median**
over 20 distinct programs, all executed and validated. The existing 32-parameter
entry benchmark measures **284.328 ms median** over ten entry recompiles after
three warmups and validates its final ELF. Both medians exceed the preceding
unpaired measurements; unchanged performance is not established. These runs do
not establish general generic-source scaling or a cross-compiler 10x ratio.
Details are in [the performance report](stdlib-gpu-performance.md).

Checkpoint evidence under `tests/fixtures/stdlib_compiler_state/`:

- `constant-domain-focused-final.log`: all six focused execution/rejection tests pass.
- `constant-domain-execution-gate.log`: 162 passes and the two retained borrow failures.
- `constant-domain-resource-contracts.log`: graph/reflection/resource lifetime check passes.
- `constant-domain-specialization-contracts.log`: eight specialization unit tests pass.

Minimal executable fixtures are `repro_generic_symbolic_length_forwarding.lani`
and `repro_generic_nested_length_inference.lani` under
`tests/fixtures/stdlib_foundation/`. Generated tests exercise 32 dimensions and
the declaration bounds. Constant value expressions, further missing/result-only
binding contexts, storage/alias support, reference/trait capabilities, and
persisted generic bodies remain work listed below.

### Prior argument inference checkpoint (2026-10-03)

Unannotated calls now infer from known argument types in either argument order.
The expected-argument producer supplies literal provenance to the shared indexed
call-environment selector. Eligible integer-literal defaults have lower priority
than known values; literal-only calls retain their default. Actual value readers
retain the stable claim view, and strict validation still compares every claim
after contextual literal facts have settled. No named value is coerced to resolve
a conflict. This adds one existing claim-origin input to argument projection;
other environment consumers acquire no HIR bindings.

Three focused execution/rejection tests pass. Local/imported scalar, whole-array,
array-element, and nested-array calls execute without result annotations. Tests
check unsigned high-bit division, both argument orders, owned-copy preservation,
and twelve conflicting scalar, element-type, and length cases with `LNC0006`.
Numeric inference inside a generic body also executes with independent Boolean,
string, and array type arguments. The earlier unconstrained `T`/integer body
experiment does not establish a compiler bug; the current body fixture uses a
known numeric type.

The execution gate reports **156 passes and 2 known inline-array borrow failures**
out of 158 tests, in 82.55 seconds. Both failures explicitly reject with `LNC0017`.
The current graph/reflection/resource lifetime check passes. The real checked-window
program still produces exact output `96\n`. After the gate, one additional body
execution was added to an existing test; all three focused tests pass afterward
in 3.93 seconds. Compiler code and shaders were unchanged during that addition.
The full gate was not repeated for that extra case.

Final shader digest: `60cb26d5a7d42101` (741 artifacts; largest 522,460 bytes under
the unchanged 524,288-byte guard). No verified IR schema or native ABI changed.
Execution evidence is x86_64 Linux ELF from the GPU compiler. User-program GPU
execution is unverified. The arbitrary-type generics goal remains unfinished.

The existing 1 MB performance preset measures **40.162 ms compiler / 42.941 ms
wall median** over 20 distinct programs, all validated at runtime. The existing
32-parameter entry benchmark measures **268.152 ms median** across ten entry
recompiles after three warmups and validates its final ELF. These are unpaired
measurements; they do not establish a causal speed change, general generic-source
scaling, or a current cross-compiler 10x ratio. Details and identities are in
[the performance report](stdlib-gpu-performance.md).

Current evidence under `tests/fixtures/stdlib_compiler_state/`:

- `literal-argument-inference-before.log`: the original order-dependent scalar rejection.
- `literal-argument-inference-bindings-before.log`: the resource gate catches duplicate bindings in the initial implementation.
- `literal-argument-inference-resources.log`: the final graph/reflection/resource check passes.
- `literal-argument-inference-execution-gate.log`: 156 passes and the two explicit borrow rejections.
- `literal-argument-inference-focused-final.log`: all three focused tests pass, including the additional body execution.

The focused tests execute `repro_generic_literal_argument_inference.lani`,
`repro_generic_array_literal_argument_inference.lani`,
`repro_generic_nested_literal_argument_inference.lani`, and
`repro_generic_literal_argument_inference_body.lani` under
`tests/fixtures/stdlib_foundation/`.

### Prior scalar context checkpoint (2026-10-03)

Scalar integer literal contexts now execute through local/imported generic calls,
enum constructors, and match arms. Expected parameter constraints come from the
immutable declaration pattern independently of provisional argument types. The
shared expression-context relation publishes eligible literal types to both
inference facts and final semantic projection. Generic binding conflicts and
required bindings are validated after inference closes.

The two original reproductions, imported `Some(4294967295)` under `Option<u32>`
and a `0` match arm under an expected `u32`, now execute. High-bit values are
checked with unsigned division, including the absent match branch. Local/imported
direct `T` returns and ordinary unsigned parameters execute, and an unannotated
integer generic call retains its default type. Ten negative cases reject named
type conflicts, floating/Boolean literals, and conflicting repeated parameters
with `LNC0006`. Local generic constructor payloads use checked type identity;
fixed primitive parameters retain their separate conversion rules.

The current execution gate reports **153 passes and 2 known inline-array borrow
failures** out of 155 tests, in 80.61 seconds. Both failures explicitly reject
with `LNC0017`. The current GPU graph/reflection/resource lifetime check passes.
The real checked-window program executes with exact output `96\n`. This is
x86_64 Linux execution from the GPU compiler; user-program GPU execution and
other targets are not established by this checkpoint.

Final shader digest: `487873ee7e66bd30` (741 artifacts; largest 522,460 bytes under
the unchanged 524,288-byte guard). No verified IR schema or native ABI changed.
No performance measurement was repeated for this snapshot; older timings do not
establish its performance. The arbitrary-type generics goal remains unfinished.

Current evidence under `tests/fixtures/stdlib_compiler_state/`:

- `scalar-context-imported-before.log`, `scalar-context-match-before.log`: original scalar-context diagnostics.
- `scalar-context-shared-final.log`: all four focused execution/rejection tests pass before the final publication cleanup.
- `scalar-context-execution-build.log`: build of the current execution gate.
- `scalar-context-final-execution-gate.log`: 153 passes and the two explicit borrow rejections on the final shaders.
- `scalar-context-resources-current.log`: current graph/reflection/resource lifetime check passes.

The original scalar reproductions remain in
`tests/fixtures/stdlib_foundation/repro_imported_unsigned_scalar_literal_context.lani`
and `repro_unsigned_match_literal_context.lani`; the gate executes both.

### Prior expected array and imported layout checkpoint (2026-10-03)

Expected argument types now form a caller-side checked relation shared by local
and imported calls and enum constructors. Array expressions consume that relation
under the accepted type environment. Empty, nested empty, and unsigned array
payloads execute. Integer literal context reaches both inference facts and the
final semantic artifact, preserving values across the unsigned high bit. Named
values and float literals are not relabeled to make a constraint pass.

Imported match bindings retain complete payload patterns while their declaration
page is resident. Native enum layout consumes the same canonical-to-checked lookup
as application creation and imported fields. Declaration expansion visits every
variant, including variants never constructed or destructured in the caller.
This removes the scalar/direct-parameter restriction on imported enum layout.
Zero-sized nested arrays remain complete values, and following string payloads
retain their correct placement.

Six new focused execution/rejection tests pass. They cover local/imported empty
constructor payloads, nested array arguments, unsigned extrema, compound imported
payload patterns, copies, tags, and larger unused variants. Thirteen new conflicting
length, element-type, named-value, and second-parameter cases report `LNC0006`.
The real checked-window program still executes with exact output `96\n`.

The final generic execution gate reports **149 passes and 2 known inline-array
borrow failures** out of 151 tests, in 79.88 seconds. Both failures explicitly
reject with `LNC0017`. The current graph/resource lifetime check also passes.
All six new tests and the checked-window program pass in that final gate.
These are executed x86_64 Linux ELFs emitted by the GPU compiler; user-program
GPU execution and other targets are not established by this checkpoint.

Two further scalar-context failures have minimal reproductions and retained
compiler diagnostics: an imported `Some(4294967295)` under `Option<u32>`, and a
`0` match arm under an expected `u32`. Both currently reject with `LNC0006`.
These are additional remaining work outside the passing array-context cases;
the 151-test gate does not include them. General arbitrary-type generics remain
unfinished, including the storage, constant, reference, trait, and persisted-body
capabilities listed below.

Final shader digest: `23f33e14dc42a5d4` (741 artifacts; largest 522,460 bytes under
the unchanged 524,288-byte guard). The native generic layout shader uses the same
minimum optimization policy as other complex traversal shaders and is 134,052
bytes. No verified IR schema or native ABI changed. No performance measurement
was repeated for this snapshot; older timings do not establish its performance.

Current evidence under `tests/fixtures/stdlib_compiler_state/`:

- `constructor-expected-context-before.log`: the initial empty/unsigned constructor failures.
- `argument-context-imported-patterns.log`: imported match context reaches a native layout failure.
- `argument-context-imported-patterns-final.log`: compound imported constructors and three rejections pass.
- `enum-unused-payloads-before.log`: local control executes; imported unused-variant layout rejects.
- `enum-unused-payloads-final.log`: both local and imported controls execute after declaration expansion.
- `argument-context-final-execution-gate.log`: final 149 passes and two explicit borrow rejections.
- `argument-context-resources-current.log`: current graph/reflection/resource lifetime check passes.
- `scalar-context-imported-before.log`, `scalar-context-match-before.log`: remaining scalar-context diagnostics.

The scalar reproductions are
`repro_imported_unsigned_scalar_literal_context.lani` and
`repro_unsigned_match_literal_context.lani` under `tests/fixtures/stdlib_foundation/`.

### Prior enum literal checkpoint (2026-10-03)

Constructor payload checking now consumes complete accepted expression references
through the shared inference projection. Local constructors accept nonempty array
literals, nested arrays, record literals, and arrays of records. Imported constructors
defer result mismatch diagnostics until inference has closed, so an argument's type
may be published by a later dispatch. Local payloads are revalidated at closure;
pending facts do not authorize native publication. Bare nominal references in the
legacy scalar encoding use reference equality, not scalar conversion rules.

Four focused execution/rejection tests pass. They check integer and Unicode string
arrays, nested arrays, record fields, independent copies, and a generic function
constructing `Packet<[T; 2]>` from `[value, value]`. Seven conflicting length,
element-type, mixed-element, and nominal-identity cases reject with `LNC0006`.
The real checked-window program now directly constructs
`Some([18, 42, 24, 30])` and still executes with output `96\n`.

The current full execution gate reports **143 passes and the same 2 known
inline-array borrow failures** out of 145 tests, in 76.92 seconds. Both retained
failures explicitly reject with `LNC0017`. All six adjacent enum-constructor
diagnostic checks and the current GPU graph/resource lifetime test pass.
The full gate precedes only the final explicit diagnostic for a payload still
unresolved after closure. All four focused tests and six adjacent diagnostic
checks pass afterward; the full gate was not repeated for that diagnostic.
These results establish x86_64 Linux execution from the GPU compiler, not
user-program GPU execution. The overall arbitrary-type generics goal remains active.

Final shader digest: `0ca6847c0d35d60a` (738 artifacts; largest 522,460 bytes under
the unchanged 524,288-byte guard). No IR schema or native ABI changed. The new
constructor validation adds three dispatches when enum syntax is present;
performance was not rerun for this shader snapshot. The 1 MB measurement in the
preceding checkpoint has a different shader digest and is historical evidence.

Current evidence under `tests/fixtures/stdlib_compiler_state/`:

- `enum-literal-context-before.log`: both local/imported literal constructors reject.
- `enum-literal-context-shared.log`: both minimal executable reproductions pass.
- `enum-literal-context-compounds.log`: all four focused tests pass.
- `enum-literal-context-final.log`: all four pass with final unresolved-payload diagnostics.
- `enum-literal-context-execution-gate.log`: 143 pass, two retained borrow failures.
- `enum-literal-context-adjacent-final.log`: six final constructor diagnostic checks pass.
- `enum-literal-context-resources.log`: current graph/resource lifetime check passes.

### Prior architecture consolidation checkpoint (2026-10-03)

The architecture now has shared owners for checked type identity, lexical
environments, concrete layout/storage capabilities, and specialization. The
implementation and extension rules are documented in
[Compiler semantic contracts](compiler-semantic-contracts.md).

Local and imported inherent methods compose impl and method parameters through
the same lexical lookup, structural matcher, retained environments, and replay.
GPU semantic interface **version 6** preserves exact parameter member identity
and combined declared type/constant requirements, including unused parameters.
Export, import, validation, and nominal arity consumers agree on those scopes.
The former imported `Boxed<i32>::keep<U>` reproduction now executes. Imported
compound values, independent copies, borrowed receivers, static calls, literal
constant lengths, zero lengths, and missing/conflicting bindings have focused
execution/rejection coverage. Missing unused imported bindings reject at the
specialization gate with `LNC0017`; tested conflicts reject with `LNC0006`.

Specialization identity is a canonical graph of complete semantic arguments and
constant values. Derived native widths and mutable replay indexes are excluded.
Layouts are checked separately, including on reuse. An already emitted tag-only
body cannot bypass declared binding requirements. Native storage classification,
word displacement, packed i32 stride, and slice compatibility have a shared x86
owner used by scatter, locations, byte counting, and ordinary/specialized emission.

The full execution gate reports **138 passes and 2 known failures** out of 140
tests, in 100.67 seconds. The failures are the retained ordinary and generic
inline-array borrow tests: both reject explicitly with `LNC0017` before ELF
publication. Their descending eight-byte inline storage cannot satisfy ascending
four-byte i32 slice access while preserving aliases. No temporary-copy workaround
or native ABI change was made.

After the final indexed interface-validator change, **all 7 interface tests** and
**all 3 imported-method execution/rejection tests** pass. The adjacent method suite
has **11 passes**, and the identity/interface/resource contract suite has **17
passes**. The full gate precedes only the indexed-validator optimization and the
new real-program test; it was not repeated for those changes.

The additional [checked window program](../sample_programs/checked_window_checksum.lani)
executes and prints `96\n`. It combines `Option<[i32; 4]>`,
`Result<[i32; 4], i32>`, independent owned copies, byte validation, sorting,
binary bounds, `Range<i32>`, slice access, and saturating arithmetic. It checks
the error path and the absent Option fallback. Array payloads are named before
enum construction; direct array-literal enum arguments remain unsupported.
There are now 141 registered execution tests; the new program passes in its
focused run.

Final built/benchmarked shader digest: `eb68683844f2cb2e` (738 artifacts; largest
522,460 bytes under the unchanged 524,288-byte guard). No verified IR schema,
formal proof, extractor, or native ABI changed. Evidence is x86_64 Linux programs
emitted by the GPU compiler; user-program GPU execution is not established.

The existing 1 MB benchmark compiled 20 distinct programs with **41.287 ms compiler
median** and **44.534 ms wall median**. All 20 emitted programs pass exact stdout,
empty stderr, and exit checks; source hashes match the frozen workload, with zero
timed compiled-unit cache hits or new GPU resources. This unpaired measurement
does not establish unchanged performance, generic-graph scaling, or a current
cross-compiler 10x ratio. The arbitrary-type generics goal remains unfinished.

Evidence under `tests/fixtures/stdlib_compiler_state/`:

- `architecture-execution-gate.log`: 138 pass and two known borrow failures.
- `architecture-lexical-focused.log`: seven local/imported execution/rejection cases.
- `architecture-import-final.log`: three final imported-method cases pass.
- `architecture-interface-validated.log`: seven final portable interface tests pass.
- `architecture-adjacent-methods.log`: eleven adjacent method checks pass.
- `architecture-contracts.log`: seventeen identity/interface/resource checks pass.
- `architecture-real-program.log`: the checked window program executes.

Benchmark report, shader metadata, and all 20 runtime validation records are under
`benchmark_artifacts/performance/stdlib-gpu-20261003-contracts/`. The runner writes
its report before the existing catalogue `list.get` postprocessing error;
independent result-schema validation and executable validation pass.

### Prior local lexical environment checkpoint (2026-10-02)

These results precede the portable-interface and specialization consolidation above.

Local inherent methods now compose their impl parameters with their own type and
constant parameters. Shared lexical lookup and slot assignment are used by ordinary
checking, constant declaration identity, and body replay. Enclosing parameters come
first in each separate domain. Declaration-owned counts stay unchanged; callable
requirements and retained specialization environments contain the combined counts.
Missing method type bindings now pass through the same required-slot validation as
free functions. Trait method generics and method where clauses remain restricted.

Four focused execution/rejection tests pass. They cover `impl<T>` with a method
`<U>`, different type combinations at different calls, compound values and independent
copies, reordered impl parameters, borrowed receivers, nested method forwarding,
static methods, constant-only methods, zero-length results, and conflicting or missing
bindings. A constant-only result materialization guard was also corrected to consider
both argument domains. These are executed x86_64 Linux programs emitted by the GPU
compiler, not user-program GPU execution.

The full gate before the final static-method/import probes reports **135 passes and
2 known inline-array borrowing failures** in 75.13 seconds (`78ae901f8661214e`). The
final focused run retains all four passes, including the added static calls, and
finds **one additional failing imported-method reproduction**. All **13 adjacent
method checks** and **3 graph/reflection resource checks** pass. The resource checks
use the existing contract-test binary with the final reflection files; the compiler
integration binaries were rebuilt for this change.

The imported reproduction is intentionally retained as a failing execution test:
`lexical_method_environment_imported_parameters_execute`. Its two source files are
under `tests/fixtures/stdlib_foundation/repro_method_local_import_root/`. Calling
`Boxed<i32>::keep<U>` through an imported receiver rejects with `LNC0047`, generic
instantiation boundary detail 4. The current exporter normalizes generic slots into
the receiver declaration's member segment; the method's extra `U` has no generic
member there. Preserving method ownership across interface export, decoding, and
retention is the next environment dependency. This feature is not claimed to work.
There are now three known failing execution cases: this import and the two array
borrows. The overall compiler-generics goal remains unfinished.

Final shader digest: `88e24df174136530` (738 artifacts; largest 522,464 bytes under
the unchanged 524,288-byte guard). No IR record schema or native ABI changed.
Performance was not rerun; earlier measurements do not establish current performance.

Evidence under `tests/fixtures/stdlib_compiler_state/`:

- `lexical-method-before.log`: original local impl/method example rejects.
- `lexical-method-constants.log`: all four focused cases pass after the constant fix.
- `lexical-method-checkpoint.log`: full gate, 135 pass and two known borrow failures.
- `lexical-method-final-focused.log`: four passes, one imported-method failure.
- `lexical-method-import-boundary.log`: isolated import reproduction and boundary detail.
- `lexical-method-adjacent-final.log`: 13 adjacent method checks pass.
- `lexical-method-resources-final.log`: three resource contracts pass.

### Prior constant environment checkpoint

These results precede the lexical-method checkpoint above.

The environment migration now executes local and imported array-length generics.
The general compiler-generics goal remains unfinished. Ownership rules are in
[Compiler semantic contracts](compiler-semantic-contracts.md).

Checked call environments carry type arguments and constant values in separate
slot domains. Equality, hashing, result constraints, and application materialization
use the same constant lookup. Retained calls preserve those values through workspace
reuse; body replay and specialization keys include them. Constant-only functions
also use this path. Interface decoding translates constant member identities to
constant slots, and dependency batching rebases those member references.

Executable checks cover `keep<T, const N: usize>(values: [T; N]) -> [T; N]`,
distinct lengths in one program, integer/boolean/string elements, inferred results,
zero lengths, a fifth constant parameter, and `Wrapped<[T; N]>` returns. Copies
remain independent after mutation. Local and imported calls execute; conflicting
argument lengths and conflicting result annotations reject with `LNC0006`.
A record-field substitution bug found by the nested return test is also fixed:
once a type argument is bound in caller scope, the record environment is not
applied to it again.

The full x86 execution gate reports **131 passes and the same two known
inline-array borrowing failures**, in 73.79 seconds. Both failures remain explicit
`LNC0017` rejections. All **nine adjacent constant/alias tests pass**, including
`type_checker_accepts_generic_array_calls_beyond_cached_argument_width`, which
failed at the previous checkpoint. Five resource/identity checks pass: three
compiler graph/reflection contracts, specialization-key identity, and dependency
batching of constant member references.

Shader digest: `e3acb0a3baa7a277` (738 artifacts; largest 522,464 bytes under the
unchanged 524,288-byte guard). This migration changes private checker/replay data;
it does not change the IR record schema or native ABI. No new performance run was
made. The last 1 MB timing below predates these changes and does not establish
current performance or generic-graph scaling.

Evidence under `tests/fixtures/stdlib_compiler_state/`:

- `constant-environment-before.log`: the original executable test rejects its call result.
- `constant-environment-identity.log`: four focused execution/rejection tests pass,
  including imported and nested returns; checked environment traces are retained.
- `constant-environment-checkpoint.log`: full execution gate, 131 pass and two known failures.
- `constant-environment-adjacent.log`: all nine adjacent constant/alias checks pass.
- `constant-environment-contracts.log`: all five resource/identity checks pass.

This does not establish arbitrary constant expressions or complete lexical
composition of impl and method parameters. Remaining work is listed below.

### Prior call matching checkpoint

These results precede the constant-environment checkpoint above.

The first migration consolidates call argument projection, structural pattern
matching, and generic claim validation. Collection and emission share one pattern
matcher; direct parameters, nested nominal/array/reference types, local methods,
and imported arguments use its checked references. Separate shallow nominal and
array claim emitters were removed. Claim emission exclusively owns generic claim
rows. Scalar caches remain derived inputs to older scalar consumers, but cannot
establish required generic bindings or decide claim equality. Conflict validation
uses one complete type comparison and no longer schedules a second shallow
comparison of the same arguments.

The retained regression demonstrates a previously accepted invalid program:
a method expecting `Wrapped<[i32; 2]>` accepted `Wrapped<[bool; 2]>` and emitted
an ELF. It now rejects with `LNC0006`; wrong array lengths and nominal identities
also reject. The accepted free-function/method pair executes and preserves owned
copies. Reused-workspace checks exposed and repaired an early read of final
semantic expression records: only record literals have an early artifact producer;
other arguments must use accepted inference/declaration/field/index facts.

The latest full compiler execution gate has **126 passing tests and two known
inline-array borrowing failures** in 83.75 seconds (shader digest
`c5932750ffe80e9b`). The two failures remain explicit `LNC0017` rejections.
A following identity repair makes constant array lengths refer to their parameter
declaration rather than each source occurrence. The no-call reproduction now
compiles and its main executes; a return using distinct `N` and `M` declarations
rejects. This verifies template identity, not execution of constant-specialized
bodies. All three focused call-contract checks and three current resource-contract
checks pass with final digest `cc73f5ad3abd615e` (737 artifacts; largest 522,464 bytes
under the unchanged 524,288-byte guard). The full gate precedes only that constant
identity repair; it was not repeated afterward.

Adjacent constant/alias checks have **eight passes and one remaining failure**:
`type_checker_accepts_generic_array_calls_beyond_cached_argument_width` now reaches
the call but rejects its `[i32; 2]` result annotation. The general application
materializer preserves a symbolic constant length instead of substituting the
call's inferred constant value. Complete constant-value environments remain a
required dependency; no passing claim is made for that API.

The existing canonical 1 MB benchmark measured **38.788 ms compiler median** and
**41.816 ms wall median**. All 20 emitted programs pass exact output/exit checks,
with source hashes verified, zero timed compiled-unit cache hits, and zero new
buffers, bind groups or pipelines. The earlier 45.224 ms measurement is unpaired;
this result does not establish a causal speedup, generic-graph scaling, or a 10x
cross-compiler claim.

Evidence under `tests/fixtures/stdlib_compiler_state/`:

- `semantic-contract-before.log`: accepted wrong method argument; positive case executes.
- `semantic-contract-focused.log`: nine focused execution/rejection checks pass,
  including workspace reuse and nested imported/local generic arguments.
- `semantic-contract-checkpoint.log`: 126 pass, two known borrowing failures.
- `semantic-contract-const-before.log`: an unused constant-array-return body rejects
  even without generic calls, isolating declaration identity from call inference.
- `semantic-contract-final-focused.log`: three call-contract checks pass after
  canonicalizing constant parameter identities.
- `semantic-contract-adjacent.log`: eight pass; constant return substitution remains failing.
- `semantic-contract-graph.log`: three resource/reflection checks pass.

### Prior array-literal checkpoint

The general generics goal remains unfinished. The latest full compiler execution
gate has **124 passing tests and two failing runtime-contract tests**. Both
failures are the existing ordinary/generic inline i32-array borrows, rejected
with `LNC0017`; alias-preserving native array storage is still pending.

Direct array-literal arguments now execute through the shared checked-type
inference mechanism. The former `make(["one", "two λ"])` failure passes. New
runtime checks also cover nested string arrays through imported identity,
record arrays, array literals inside generic bodies, independent owned copies,
reference and slice aliases, scalar arrays, zero-length array elements, and
annotated nested empty literals. Five incompatible-element cases reject with
`LNC0006`. An empty literal without an inferable context rejects before emission,
but its generic-call diagnostic remains `LNC0047` rather than a precise missing
array-element-type error.

Literal inference snapshots first-element references, allocates complete private
array nodes, and validates elements in parallel after inference converges.
Repeated rounds reuse an unchanged literal type. Final semantic projection and
the older array-return validator consume the same accepted references. A return
validator now checks generated symbolic instance IDs against graph capacity,
rather than source-token capacity. These changes preserve the existing IR records
and native calling convention.

Executable nested literals exposed a parser invariant violation: source-order
compaction interleaved inner element rows with outer siblings. The existing
prefix scan now reserves each owner's full element range; ordinal scatter keeps
that range contiguous. This adds no parser dispatch or sorting pass. The retained
parser regression fails before the repair and passes afterward, alongside three
adjacent parser checks. Four compiler resource-contract checks also pass.

Shader digest: `87227182d18aa93b` (737 artifacts; largest 522,464 bytes under the
unchanged 524,288-byte guard). The full compiler gate finished in 69.08 seconds.
The existing canonical 1 MB benchmark measured a 45.224 ms median compiler time
and 48.565 ms median wall time. All 20 emitted ELFs pass exact runtime validation.
The earlier 39.088 ms compiler median is an unpaired historical measurement;
this higher result is a performance concern, not evidence isolating this repair.
See the performance section for measurement limits and retained artifacts.

Evidence under `tests/fixtures/stdlib_compiler_state/`:

- `generic-array-literal-focused.log`: five checks pass, covering runtime values,
  copies, aliases, nested and empty literals, and incompatible element types.
- `generic-array-literal-parser-before.log`: the nested owner's range invariant
  fails before compaction is repaired.
- `generic-array-literal-parser-after.log`: four parser checks pass.
- `generic-array-literal-checkpoint.log`: 124 pass; the two known inline-array
  borrowing tests remain failing and are neither ignored nor weakened.
- `generic-array-literal-graph.log`: four resource-contract checks pass.

### Prior method-convergence checkpoint

The general generics goal remains unfinished. The latest full compiler execution
gate has **119 passing tests and three failing runtime-contract tests**:

- The two existing ordinary/generic inline i32-array borrow tests reject with
  `LNC0017`; consistent alias-preserving native array storage remains pending.
- Passing an array literal directly to a generic parameter still fails inference
  with `LNC0047`. The new executable regression is retained as a failure, and its
  standalone source is `tests/fixtures/stdlib_foundation/repro_generic_array_literal_argument.lani`.

This checkpoint adds executable evidence for complete method environments:

- Local generic methods preserve strings, fixed arrays, records, references,
  independent value copies, and aliases. Nested method calls and reordered impl
  parameters use the impl's lexical parameter bindings.
- Imported reference signatures and fields retain their full referent types.
  Replacing one copied record's reference field preserves the other copy's
  referent. Seven incompatible imported-reference cases reject with `LNC0006`.
- Imported methods on a reference to a five-parameter record execute with string,
  record, fixed-array, slice, and scalar arguments. Returned copies remain
  independent; returned references and slices preserve aliases.
- Chained methods on inferred generic call results execute, including reference
  forwarding and a factory receiving an already typed array. The separate array
  literal failure above does not depend on method syntax.

Method lookup now participates in the existing call-inference convergence loop.
Generated instances use the checked graph's capacity and complete argument
relation. Imported method returns use the general materializer; receiver patterns
produce the same lexical call environment as argument and result constraints.
Declaration-side symbolic return templates cannot masquerade as completed
caller-side receiver bindings. Field references similarly take precedence over
native scalar caches, which cannot distinguish `&T` from an untyped pointer.

A subsequent targeted check exposed an invalid no-import setup: its empty
interface view aliased a writable type table. It now uses a resident, read-only
zero-count header. Four focused method checks pass after that repair, covering
wrong arguments, ambiguous impls, concrete overloads, and the fifth receiver
argument. All **10 adjacent Option/Result execution checks** and **three graph
checks** pass. The latter cover inference lifetimes, dependency bindings, and
native semantic-lowering access contracts. One obsolete graph-test assertion was
moved to the shader that actually consumes the canonical subtree relation.

Shader digest: `b75fb35143144564` (734 artifacts; largest 522,464 bytes under the
unchanged 524,288-byte guard). The full gate precedes only the no-import buffer
repair and graph-test corrections; those have the focused checks above.
Performance has not been remeasured for these reference/method changes.

Evidence under `tests/fixtures/stdlib_compiler_state/`:

- `generic-member-reference-priority-focused.log`: seven field/reference checks
  pass after preserving authoritative field types.
- `generic-method-reference-checkpoint.log`: intermediate 117-pass/two-failure gate.
- `generic-method-receiver-inventory.log`: both new receiver programs fail before
  method-return materialization and convergence are repaired.
- `generic-call-receiver-literal-isolation.log`: method chaining executes while
  the independent array-literal inference reproduction still fails.
- `generic-method-convergence-checkpoint.log`: 119 pass, three retained failures.
- `generic-method-resolution-setup-debug.log`: exact invalid buffer-alias diagnosis.
- `generic-method-resolution-contracts-final.log`: four method-contract checks pass.
- `generic-method-stdlib-checkpoint.log`: all 10 Option/Result checks pass.
- `generic-method-graph-final.log`: all three graph checks pass.

### Prior reference checkpoint

The preceding reference checkpoint had
**110 passing checks and two failing runtime-contract checks**, both the known
inline i32-array borrows described below. The five reference checks added since
the preceding gate all pass, including local/imported generic compositions and
six incompatible-type cases. Shader digest: `33e221ea890c7b12` (734 artifacts;
largest shader 522,464 bytes under the unchanged 524,288-byte guard).

References now retain a distinct node and their complete referent in the private
checked type graph, retained specialization key, and body replay. Native
parameters, fields, and returns carry a pointer word rather than copying the
referent. Ordinary and generic `&self` return tests mutate the original record
after borrowing and observe the mutation through the returned reference.
`Cell<&Item>`, `[&Item; 2]`, and enum reference payloads preserve aliases through
local and imported generic forwarding. Copying their enclosing owned values
keeps independent fields/elements while retaining the shared referent.
Local `&T` parameter/return patterns also execute. Equal-width but distinct
referents, mixed generic bindings, owned/reference mismatches, and integer zero
in a reference context reject with `LNC0006`.

The stricter checker exposed invalid `&self` bodies in `core::option` and
`core::result`: matching or returning `self` there requires an owned enum under
the current language rules. Their methods now take `self` by value. Lanius
copies value arguments, so these calls preserve the caller's enum and keep
reference/slice payload aliases. All **10 adjacent Option/Result tests** pass,
including state-pair matrices, strings, wrong arguments, NaN, and signed zero.
This changes the receiver signatures; the modules and their clients must be
rebuilt together. No compatibility alias or coercion was added.

This checkpoint does not establish every reference operation. Explicit imported
reference-signature materialization remains guarded; method lookup on reference
values, escaping stable cells, and further compositions still need work and
executable evidence. The native array storage decision is also outstanding.
No performance measurement was rerun for this checkpoint; measurements below
belong to their labeled earlier snapshots.

Evidence under `tests/fixtures/stdlib_compiler_state/`:

- `generic-reference-inventory.log`: both original reference programs compile
  but return stale data before the repair.
- `generic-reference-graph-tests.log`: six private retained-graph checks pass;
  these are representation checks, separate from executable evidence.
- `generic-reference-compositions-focused.log`: reference compositions execute;
  the first negative run exposes acceptance of the wrong ordinary referent.
- `generic-reference-contract-focused.log`: all six focused checks pass after
  complete reference-parameter validation and the stdlib receiver correction.
- `generic-reference-checkpoint.log`: 110 pass, two known explicit `LNC0017`
  borrow failures; neither failure is ignored or changed into a success test.
- `generic-reference-stdlib-checkpoint.log`: all 10 adjacent checks pass.

### Preceding compound-return checkpoint

The general generics goal remains unfinished. The preceding compiler gate has
**105 passing checks and two failing runtime-contract checks**. Both failures
are retained tests for borrowing an inline `[i32; 3]` field, through ordinary
and generic calls. They now reject before executable emission with `LNC0017`;
the required alias-preserving behavior is still unimplemented. Shader digest:
`5c5836c7a93b7807` (734 artifacts; largest shader 522,464 bytes under the unchanged
524,288-byte guard).

Nested calls such as `keep(view(values))` now retain the complete ordinary
callee return type before generic inference. The declaration-result projection
previously seeded only named types, leaving array and slice results unavailable
to dependent generic calls. It now seeds every checked compound type. Consumers
still require a closed type graph or a result materialized under the accepted
generic environment; declaration templates are not accepted as concrete values.

Executable checks cover unannotated slice, fixed-array, nested-record, and
zero-sized array returns through local and imported generic calls. They verify
independent value copies, shared slice aliases, Unicode and empty strings, and
rejection of conflicting generic arguments. Unequal nested array dimensions
(`[[str; 3]; 2]`) preserve the inner length across owned and borrowed calls.

The new borrowing reproduction confirms a separate native storage mismatch:
inline i32 arrays descend in eight-byte words, while i32 slices address packed
four-byte elements. Previously both ordinary and generic versions compiled but
exited 1 after reading incorrect elements. Native call lowering now explicitly
rejects an incompatible fixed-array storage address instead of emitting that
program. This is a temporary compiler boundary, not completion of the borrow
contract. Copying to a temporary would break aliases to the original field.
No IR record or native calling-convention change was made.

Evidence for that preceding checkpoint under `tests/fixtures/stdlib_compiler_state/`:

- `generic-compound-return-final-checkpoint.log`: 105 pass, two explicit native
  rejections; the two runtime-contract tests remain failing and are not ignored.
- `generic-nested-array-before.log`: original nested-call inference failures.
- `generic-nested-array-isolated.log`: isolated inference and runtime failures.
- `generic-compound-return-expanded.log`: unannotated compound results execute;
  conflicting generic constraints reject.
- `generic-borrow-boundary-focused.log`: eight checks pass and both unsafe
  borrows reject with `LNC0017` before an artifact is emitted.

The ordinary minimal reproduction is
`tests/fixtures/stdlib_foundation/repro_ordinary_inline_array_borrow.lani`.
Adjacent stdlib checks, reflection checks, and performance measurements below
belong to the preceding checkpoint; they were not rerun for this small change.

### Preceding argument-capture checkpoint

The preceding full compiler gate has
**100 passing checks and zero failures**, plus **49 passing adjacent stdlib
execution checks**. All four semantic/optimizer/target graph reflection checks
pass. Shader digest: `8c5d3cddd7e40d24` (734 artifacts; largest shader 522,464 bytes
under the unchanged 524,288-byte guard).

Caller-side argument capture now has executable evidence:

- Record and fixed-array arguments are captured when their expression finishes,
  before a later argument can mutate their source. Both ordinary and generic
  `first(values, change(values))` preserve the earlier value. Imported generic
  and ordinary functions follow the same contract.
- The checker retains each argument's passing mode while the signature is
  available, including imported signatures, method receivers, and enum payloads.
  Lowering combines that mode with the complete concrete source type. Value,
  slice-backing borrow, and reference borrow remain distinct.
- Slice descriptors capture their pointer and length while retaining shared
  backing storage. A later argument can replace a slice field without changing
  the earlier argument. Mutating the captured slice still reaches its original
  backing array. Copied records preserve this same shallow borrowing behavior
  for nested slice fields while keeping owned fields independent.
- Existing aggregate-copy instructions lower to native word copies or packed
  i32 copies as required. Inline `[i32; N]` fields now pass through ordinary and
  generic value parameters without losing elements. Arrays of strings retain
  their pointer/length argument width, including when followed by a borrowed
  slice. This uses the existing native calling convention and IR records.
- Constructor element ownership still names the original constructor row;
  consumers name its captured value. Deferred templates remain non-executable.
  The 6-, 16-, and 32-parameter mixed composition programs execute successfully.

The preceding fixes remain covered: independent callee parameter storage,
complete nominal return types after field assignment, and recursive comparison
of all ordered nominal arguments through 32 parameters, including rejection of
mismatches beyond the former five-slot boundary.

Logs under `tests/fixtures/stdlib_compiler_state/`:

- `generic-argument-capture-final-checkpoint.log`: 100 pass, zero fail.
- `generic-argument-capture-adjacent-checkpoint.log`: all 49 pass.
- `generic-argument-capture-graph.log`: all four graph reflection checks pass.
- `generic-argument-capture-expanded.log`: seven argument-capture checks pass.
- `generic-argument-capture-expanded-before.log`: descriptor replacement failure
  before its repair; record and imported capture checks already pass.
- `generic-argument-capture-composition-before.log` and `-after.log`: the
  multi-parameter argument-width failure and its successful regression check.

One unresolved stability observation remains: the first intermediate full gate
rejected the contextual nested record-literal case with `LNC0006`. The identical
case passed in isolation, in the focused follow-up, and in the final full gate.
No cause has been established for that isolated rejection; the logs retain it
in `generic-argument-capture-checkpoint.log`. The passing final gate does not
establish that this observation is resolved.

These results establish the tested compositions, not arbitrary generic-body
support or all language type forms. Remaining work is listed below.

## General generics contract and completion plan

For every finite, well-formed type that executes in an ordinary Lanius
function, using that type as a generic argument must preserve the same values,
copy behavior, aliases, bounds behavior, and errors. The initial arity target
is 32 parameters. Five-, six-, sixteen-, and thirty-two-parameter compositions
have executable evidence, including mixed records, arrays, strings, and slices.

The compiler must preserve a complete checked type graph: scalar identity,
stable nominal declaration identity and every ordered argument, nested element
types, array lengths, and lexical identity for symbolic parameters. Native
widths are layout facts; they do not replace the type's structure. Retained
nominal applications now carry every ordered argument through imported calls
and body specialization. Zero-argument named values still use `NativeValue`
leaves with scoped declaration identity and accepted native width.

One recursive substitution mechanism must apply each environment once to
declaration fields, constructors, call parameters, and complete return types.
It must create implied applications, including applications first introduced
by inferred call results. Specialization must close the whole body before
executable lowering. Loads, stores, copies, arguments, and returns must then
consume the accepted concrete layout. Incomplete types and exhausted limits
must produce compilation errors before publishing executable output.

Each stage must cover every type form supported by ordinary functions. A
generic argument is a complete type, including its children, rather than a
choice among supported payload examples. Local and imported functions must
follow the same substitution and specialization contract. Known zero-sized
layouts must be distinguishable from unresolved layouts. A successful generic
call must execute the same operations as its ordinary concrete counterpart;
adding a generic wrapper cannot change the supported value representation.

Completion requires executable generic/concrete comparisons across nested
records, enums, arrays, slices, imported declarations, reordered parameters,
and the other ordinarily executable type forms. Include zero-sized layouts
and full-width scalar identities once their ordinary runtime behavior is
established. Use structural interning, cached substitution/layout, and reuse of
specialized bodies to bound repeated work. Measure the existing large Lanius
performance corpus and representative generic programs at coherent milestones.

### Current work in progress

Concrete body replay now applies the selected lexical environment to every
retained reference column used by accepted expressions, declarations, claims,
contexts, and type-graph edges. The same parameter-reference substitution handles
nested types; it does not choose a scalar/record/array-specific implementation.
Other declarations retain their own symbolic parameters. Layout projection then
uses the complete checked instance, including a valid zero-word result, instead
of falling back to an unresolved generic declaration.

The imported compound-field producer materializes canonical array, slice,
and nominal subtrees under the receiver environment and retains their checked
references before the dependency page expires. Both the minimal imported
array-field reproduction and the larger mixed compound-field program now
execute construction, reads, replacement, independent copies, and aliases.

Local complete return types use the shared substitution producer with the
accepted call environment. The formerly failing reordered `[B; 2]` return
executes, and unannotated local call results retain complete types. Imported
compound returns use shared scoped matching against their contextual result,
including repeated type parameters. Conflicting inferred constraints and
contexts that contradict an accepted argument are rejected with `LNC0006`.
Imported return graphs now materialize while their declaration page is active.
Unannotated array, slice, and nominal results retain their complete checked
types. Contextual constraints publish accepted result-only bindings; a retained
environment check preserves all 32 ordered bindings across workspace reuse.

Call inference runs to a fixed point before required-argument validation.
Dependent calls can consume a preceding inferred compound result without a
source annotation. Progress compares complete types rather than temporary row
numbers or legacy scalar codes. The GPU graph extends scratch lifetimes across
the repeated region, and a final nondeferred pass rejects unresolved types.
A 32-call chain checks records, strings, array copies, and borrowed slice aliases.
This closure currently runs before concrete body replay. Local and imported
inferred call chains inside generic bodies also execute for scalar, string,
record, fixed string-array, and borrowed slice arguments. Late constraints
introduced only by concrete replay still need evidence beyond those cases.

Local annotated results now use complete scoped constraint matching, replacing
the four-slot scalar inference path. The matcher descends through nominal
arguments and array/slice elements, publishes all accepted bindings after the
whole match succeeds, and rejects repeated-parameter conflicts. Empty factories
execute with five and 32 mixed result-only parameters and nested result patterns.
The retention unit compares all 32 local and imported bindings by complete type.

Structural parameter inference now descends through complete local and imported
parameter patterns, including `Cell<Cell<T>>`, `Cell<Many<T0, ..., T31>>`, and
`[Cell<T>; 2]`. Each argument publishes its inferred bindings only after the
whole match succeeds; repeated parameters and separate arguments must agree.
Completed call results take precedence over declaration templates and argument
origin shortcuts. Required bindings are checked after call inference closes.
Unannotated bindings retain both compound instances and monomorphic nominal
leaves. Concrete leaf returns use the same accepted result relation. Array
parameter validation compares nested elements under the accepted call
environment, and inferred enum payload bindings publish before final member
validation. Assignment checks retain the identity of unannotated nominal lets.

The new local and imported compositions execute record and fixed-array copies,
borrowed slice aliases, Unicode and empty strings, enum payload field reads,
repeated parameters, and all 32 ordered parameter bindings. Equal-width nominal
conflicts, different array lengths, incompatible repeated parameters, conflicting
arguments, and truly missing parameters reject with `LNC0006` at the call.

Dependent expression inference now closes member, index, and match results in
the same loop as calls. A stable dense-HIR relation retains complete references
for expressions and unannotated bindings. Match payload bindings publish before
arm joining; a match owner compares every complete arm type before publishing
its result. Nested joins consume the preceding snapshot rather than another
lane's partially written result. Arithmetic follows checked operands, including
indexed payloads, instead of guessing an integer type.

An unresolved callee return template cannot become an accepted caller value.
Only accepted call results or fully closed ordinary compound returns can supply
fallback bindings. Primitive initializers also publish complete references, so
named arguments do not depend on provisional scalar caches. Five new executable
checks cover inferred fields, temporary call-result indexes, record-valued
matches, a twelve-stage field/index/match chain with independent copies, and
borrowed slice aliases through the same expression contexts.

Nominal retention uses stable declaration identities and recursive ordered
arguments. Private replay publishes all 32 argument slots, preserving nested
records, enums, fixed arrays, and borrowed slices. Match joins and call argument
projection read the same complete replay references, including member/index
chains. Equivalent source annotations retain the same nominal declaration
identity; equal-width types with different arguments remain distinct.

The executable 6-, 16-, and 32-parameter composition programs check every mixed
field, sentinels, independent copies, aliases, Unicode, and empty strings.
The 32-parameter program also passes its entire generated nominal application
through imported `core::mem::identity`. The current verification and timings
are recorded below. The general generics contract remains unfinished.

Raw pointer values now use the existing checked scalar path through imported
body replay. Ordinary, local generic, and imported generic forwarding preserve
addresses and aliases. Nested pointer compositions execute record and array
copies, field and element replacement, enum payloads, `Option<ptr>` with a
present null pointer, and `Result<ptr, Cell<ptr>>` with both variants. An ordinary
reproduction exposed address truncation in field and array stores; shared native
word stores now retain all pointer bits without changing the ABI.

Known zero-sized layouts now survive checking, retention, body replay, and
native lowering. Empty records, zero-length arrays, arrays of empty records,
and empty generic records execute through ordinary, local generic, and imported
generic calls. Their composed tests check neighboring fields, Option/Result
tags, enum payload offsets, distinct type identities, side effects, and bounds.
Zero-byte copies and stores still evaluate their operands and execute their
function bodies. Native assertion failure remains SIGILL; invalid indexes
remain exit status 101. Packed scalar slice stores use their actual 32-bit
instruction size while ordinary native word stores preserve full-width pointers.

`repro_unsigned_array_literal_context.lani` records an ordinary nongeneric
literal-context limitation; typed u32 elements remain the input convention for
the compound tests. Explicit arguments on qualified record literals also remain
a parser dependency.

## Verified type shapes

| Type argument or operation | Executable evidence |
| --- | --- |
| Inferred array literals | Nonempty literals passed directly to generic calls, imported identity of nested string literals, literals inside generic bodies, record arrays, scalar arrays, reference/slice aliases, independent copies, zero-length elements and annotated nested empty arrays execute. Heterogeneous scalar, descriptor, nominal and nested-array-length cases reject. |
| `bool`, `i32`, `u32`, `f32`, `char`, `str` | Local and imported value functions; Option/Result scalar operations. Match results preserve float bits, signed zero, Unicode characters, and both words of string descriptors. |
| `ptr` and nested pointer values | Ordinary/local/imported forwarding, selection, generic record construction and extraction, pointer arrays, nested record-array copies, enum payloads, Option/Result branches, field/element stores, and dereferencing live caller-owned storage execute. Present null pointers remain distinct from absent Option values. |
| Known zero-sized values and compositions | Ordinary/local/imported forwarding executes for empty records and zero-length arrays. `Phantom<A, B>`, `Frame<Empty>`, `Frame<[i32; 0]>`, `[Empty; 3]`, `Option<Empty>`, `Result<Empty, i32>`, and an enum with an empty payload preceding a string preserve type identities, neighboring fields, tags, offsets, and body effects. Four invalid empty-element array reads/stores exit 101; ordinary and generic assertion failures both raise SIGILL. |
| Caller-local records | Imported memory helpers and Option extraction preserve each field. Tested records include nested records and string/slice descriptors. |
| Caller-local generic records | `Cell<T>` preserves instantiated field offsets for scalar, string, record, slice, and fixed i32-array fields. Three-level nested cells, `Option<Cell<Pair>>`, independent value copies, and borrowed aliases execute. |
| Scoped generic record fields | `Holder<A, B> { child: Cell<B> }`, `Nest<T> { child: Holder<i32, T> }`, `Cell<[T; 2]>`, and `Cell<[T]>` fields execute with their enclosing type environments. The compiler also creates applications implied by local record fields when no concrete source row exists. Reordered parameters, independent record copies, Option extraction, descriptor replacement, and borrowed aliases are tested. |
| Compiler-generated nested applications | `Holder<i32>`, `Holder<bool>`, `Holder<str>`, `Outer<f32>`, and array holders execute without explicit annotations for their implied inner types. Nested record literals, string-array fields, field stores, and independent copies retain every sentinel and descriptor word. |
| Generic bodies reading nested fields | `read_generic<T>(holder: Holder<T>) -> T` executes for i32, bool, str, a caller-local record with a string field, and a fixed string array. `sentinel<T>(holder: Holder<T>) -> i32` also executes when its field offset depends on T. Returned records and arrays have independent storage. |
| Generic bodies constructing nested records | `wrap<T>(value: T) -> Holder<T>` constructs an implied `Cell<T>` and returns it for i32, bool, str, a caller-local record with a string field, and `[str; 2]`. Sibling calls preserve their distinct result types, both string descriptor words, and independent record/array storage. Wrong nominal results, array lengths, and element types are rejected. |
| Generated applications with more than four arguments | Local `Five<i32, bool, char, u32, T>` fields and imported `core::five::Five<i32, bool, char, u32, T>` fields preserve all five arguments without an explicit concrete inner annotation. Imported receiver methods execute for i32, bool, u32, f32, char, str, a caller-local record with a string field, `[i32; 2]`, `[str; 2]`, and `[i32]`. |
| Imported generic record literals | Contextual literals execute with scalar, parameter, and compound declaration fields, including `items: [T; 2]` and borrowed slices. Fields can be written in any order; complete string, record, array, and slice values retain their native widths. Wrong types, nominal identities, array lengths/elements, missing fields, duplicate fields, and unknown fields are rejected. |
| Imported compound fields and complete local returns | Mixed imported array, slice, and nested nominal fields execute through construction, replacement, generic readers, copies, and aliases. Reordered local generic environments instantiate complete array/slice/nominal returns, including the tested unannotated local results. |
| Imported inferred complete returns | Unannotated array, slice, and nominal returns execute with record/string elements, nested wrappers, independent copies, descriptor replacement, and borrowed aliases. Result-only imported factories retain accepted contextual bindings; the retention unit check covers all 32 parameters. |
| Dependent inferred call arguments | A 32-call chain consumes unannotated complete returns through imported forwarding. Nested wrapper arrays and arrays of borrowed views preserve sentinels, string descriptors, copies, runtime lengths, and aliases. Wrong inferred element types and array lengths are rejected. |
| Dependent expression inference | Unannotated fields, temporary generic-return indexes, and record-valued matches feed later generic calls. A twelve-stage field/index/match chain preserves record and array copies, string descriptors, and sentinels. A composed borrowed-slice case preserves aliases through every context. Arithmetic over indexed enum payloads retains the element type. |
| Inferred calls within generic bodies | Local and imported duplicate/forward chains execute inside a generic body for i32, bool, str, records containing strings, fixed string arrays, and borrowed slices. Independent mutations, complete string descriptors, empty strings, runtime view lengths, and aliases are checked. |
| Local complete result-only inference | Empty factories execute with five and 32 mixed type parameters and nested `Equal<[A; 2], Cell<B>>` result patterns. All 32 retained local bindings equal their imported counterparts. Repeated array-length and nominal-identity conflicts and contexts contradicting an accepted argument report `LNC0006`. |
| Result-only constant inference | Annotated bindings and declared returns execute local/imported factories, borrowed receiver methods, and associated functions with independent type/constant environments. Zero, nested dimensions, symbolic forwarding, all 32 constant slots, and concrete replay execute; argument/result and repeated-slot conflicts report source-labeled `LNC0006`. Nested argument/field/array-element result contexts remain unverified. |
| Structural parameter inference | Local and imported `Cell<Cell<T>>` readers infer scalar, string, record, fixed-array, slice, and enum types. `[Cell<T>; 2]` readers and a 32-parameter nested pattern execute. Unannotated results preserve copies, descriptors, aliases, and enum payload fields; repeated, cross-argument, nominal, array-length, and missing-binding conflicts reject. |
| Complete nominal replay | Imported forwarding and subsequent local body replay preserve `Cell<[str; 2]>`, equal-width reordered argument lists, generic enum values, borrowed slice fields, and `[Cell<[str; 2]>; 2]`. Repeated result constraints reject incompatible scalar or descriptor types. |
| Six-, sixteen-, and thirty-two-parameter composition | Generated inner applications retain every ordered field type. Whole 32-argument nominal values also survive imported identity, including string arrays, records, borrowed views, and independent field mutation. |
| Imported generic record field reads and writes | Direct fields, generic-body reads, and local/imported/local member chains execute for i32, bool, u32, f32, char, str, a caller-local record with a string field, `[str; 2]`, and `[i32]`. Multiword fields preceding the selected field retain their full widths. Scalar, string, record, array, and slice replacement preserve independent value copies and borrowed aliases. |
| Enum values and nested generic enums | Local `Maybe<Maybe<Pair>>` and imported `Option<Option<Pair>>` preserve tags and complete active payloads through value functions. Wrong nested nominal identities are rejected. |
| Local enum payloads containing generic arrays | `Batch<T> { Items([T; 2]), Empty }` executes with i32, bool, str, a caller-local record with a string field, and a fixed string array. Both variants, indexed generic match results, and independent record/array copies work. Wrong lengths, elements, and nominal identities are rejected; negative and upper-bound payload indexes trap with status 101. |
| Borrowed `[i32]` as an entire `T` | Local forwarding, imported memory functions, Option/Result extraction, and receiver fallback methods preserve runtime length and aliases. Empty and populated views retain bounds traps. |
| Compound borrowed slices as an entire `T` | `[Pair]`, `[Text]`, `[[i32; 2]]`, and `[[[i32; 2]; 2]]` execute through imported identity and local generic forwarding. Record fields, string descriptors, runtime lengths, aliases, and nested array elements survive. Three chained indexes also execute directly on a generic call result. |
| Borrowed slices containing borrowed slices | `[[i32]]` and `[[str]]` preserve outer and inner descriptors through whole-value forwarding and element operations. First, get-or, swap, set, Option/Result extraction, empty views, unequal inner lengths, descriptor replacement, and aliases execute. Five invalid outer/inner indexes trap with status 101; incompatible record element identities are rejected. |
| Compound slices inside Option/Result | `Option<[Pair]>` and `Result<[Pair], [Pair]>` execute Some/None and Ok/Err extraction through free and receiver fallback operations. Empty present views remain present, different runtime lengths survive, and recovered views alias their caller-owned storage. Composed arguments such as `unwrap_or(keep(some), fallback)` preserve the complete checked type. |
| `[i32; N]` as an entire `T` | Local and imported identity, forwarding, and selection execute at lengths 1, 2, 3, and 5. Returned arrays have independent storage. Mismatched lengths are rejected. |
| Scalar and string fixed-array elements | Imported identity also preserves bool, u32, f32, char, and str arrays. The checks include high-bit values, signed zero, empty strings, complete descriptors, and independent element replacement. |
| Fixed arrays of records as an entire `T` | Imported identity and local forwarding preserve `[Pair; 2]` and `[Text; 2]`, including every scalar field and both string descriptor words. Element mutation preserves independent input and intermediate copies. |
| Fixed arrays inside Option/Result | Free and receiver fallback extraction preserve `[i32; 3]`, `[i32; 2]`, `[str; 2]`, and `[f32; 2]` payloads. Both variants, fallback arrays, independent copies, Unicode, empty strings, and signed zero execute. |
| Indexed call arguments | Imported scalar functions receive the actual array element. Generic identity preserves indexed i32 and record values, including independent record copies. Wrong scalar element arguments are rejected. |
| `Pair` as the element of `[T]` | Generic first, first-or, get-or, set, swap, reverse, fill, copy-within, and prefix copying execute with a two-field record. Invalid logical bounds preserve storage. |
| `str` as the element of `[T]` | First, get-or, swap, and fill preserve pointer/length pairs, including empty strings and Unicode. |
| Reused compiler workspace | Generated five-argument applications, nested generic constructors, plain comparisons, generic value functions, and plain fixed-array returns execute in alternating cold and warm jobs. A named module followed by an anonymous module does not retain stale module segment metadata. |

The focused suites are `compiler_generic_types_execution`,
`stdlib_generic_payload_templates_execution`, and
`stdlib_result_generic_execution`. Their checkpoints are retained under
`tests/fixtures/stdlib_compiler_state/`. These tests execute emitted programs
and assert exit status, values, aliases, copy behavior, or exact stdout.
The preceding expression checkpoint passes 113 compiler/stdlib tests (64 compiler, 9 template,
1 memory, 18 boolean/enum, 3 Option payload, 9 Result, and 9 slice) in
`generic-expression-compiler-final.log` and
`generic-expression-adjacent-checkpoint.log`. The 32-parameter contextual
retention and GPU graph lifetime checks pass in
`generic-expression-retention-checkpoint.log` and
`generic-expression-lifetimes-checkpoint.log`. Together these are 115 fresh
focused checks, with shader digest `96ddfc90abad06ef`.
The preceding pointer checkpoint passes all 70 compiler checks in
`generic-pointer-compiler-checkpoint.log`, including the five executable pointer
checks and one explicit zero-sized layout boundary check. The shader digest is
`2f57ef9b4a423b87`, with 733 artifacts and a largest artifact of 523,228 bytes;
the 524,288-byte size guard remains enforced. At that pointer checkpoint, the
adjacent suites and performance measurements still belonged to the preceding
expression snapshot.
The preceding zero-layout checkpoint passes 123 compiler/stdlib checks (74 compiler
and the same 49 adjacent checks) in `generic-zero-runtime-checkpoint.log`.
All three checked replay-packet unit tests pass in
`generic-zero-retention-checkpoint.log`, including the distinction between a
complete zero layout and a missing layout. Together these are 126 fresh checks
with shader digest `3979aa9b02a9bb6b`, 733 artifacts, and a largest artifact of
518,612 bytes against the enforced 524,288-byte guard. The two scalar slice
regressions discovered during this change pass in `generic-zero-slice-repair.log`
and in the complete focused gate.
The preceding structural parameter gate's 110 checks remain recorded under
`generic-nested-parameter-`; the local result-constraint gate's 106 checks remain
under `generic-local-context-`.

The preceding inference checkpoint's foundation and adjacent suites pass
20 tests in `generic-inference-closure-foundation.log` and
`generic-inference-closure-adjacent.log`, including 139 executable foundation
source entries. Those foundation entries were not rerun after the local
constraint and anonymous-module repairs. Earlier packet, retained nominal graph,
native/checker, and parser gates remain historical evidence in the
`generic-nominal-graph-`, `generic-imported-fields-`, and
`generic-generated-receivers-` logs.

`repro_generic_generated_five_arguments.lani` and
`repro_generic_generated_receiver_arguments.lani` retain the local and imported
five-argument reproductions. Their runtime test executes 12 programs, including
ten mixed payload cases. Every prefix argument and surrounding sentinel is
checked. Array and record mutation preserves independent copies; slice mutation
preserves borrowed aliases. String, string-array, and string-containing record
cases check exact stdout, including Unicode and empty strings.

`repro_imported_generic_record_field_read.lani` is now executable. The minimal
`repro_imported_generic_record_multiword_prefix.lani` checks a scalar field
after string, record, string-array, and slice fields. The larger
`generic_imported_record_fields.lani` checks mixed instantiations, generic-body
reads, chained fields, replacements, independent copies, aliases, and exact
Unicode/empty-string output. Nine invalid programs report the expected source
location and diagnostic for unknown fields or wrong field/result types.
Six invalid runtime array/slice indexes exit with status 101 and no output.
These checks pass in `generic-imported-fields-runtime.log` and the combined
checkpoint. Statically invalid array indexes can be rejected before emission.

The preceding checkpoint retained two imported-record dependencies in
`generic-generated-receivers-dependencies.log`. The array-field reproduction
now executes as described above. Explicit arguments on a qualified record
literal still report `LNC0016` in
`repro_imported_explicit_generic_record_constructor.lani`; that program remains
a diagnostic reproduction rather than executable API evidence.

`repro_generic_missing_nested_application.lani` is now an executable regression:
it constructs the implied inner type and calls the formerly failing field reader.
`generic_generated_nested_applications.lani` exercises the larger mixed-type
program and checks exact Unicode/empty-string output. Nested scalar and record
payload mismatches are rejected at the offending expression. Unbounded
`Spiral<T> { next: Spiral<[T]> }` expansion reports `LNC0047` with an explicit
instantiation boundary and source location.

`repro_generic_nested_constructor_body.lani` retains the minimal generic-body
constructor regression. `generic_nested_constructor_bodies.lani` checks mixed
scalar, descriptor, record, and fixed-array instantiations with exact stdout
and independent mutation. These pass in `generic-nested-constructor-body-runtime.log`.

`repro_generic_nested_enum_payload.lani` retains the minimal nested enum
payload regression. `generic_nested_enum_payloads.lani` checks mixed scalar,
descriptor, record, and nested-array instantiations with exact stdout and
independent mutation. The same test checks both invalid bounds on a string
payload array. These pass in `generic-nested-enum-payload-runtime.log`.

The three minimal slice reproductions cover forwarding `[[i32]]`, returning
an element whose type is `[i32]`, and swapping those elements.
`generic_slice_of_slice_descriptors.lani` combines imported memory, slice,
Option/Result, and I/O operations over nested integer and string views. Exact
output, complete descriptor words, empty views, aliasing, and descriptor
replacement are checked in `generic-slice-of-slices-runtime.log`, together
with five bounds traps and nested nominal element mismatches.

Seven compound-slice bounds programs exit with native status 101 and no output.
They cover upper and negative record-slice indexes, empty views, Option/Result
extraction, and outer/inner nested-array bounds. Wrong nominal identities,
element types, result types, and nested array lengths are rejected with
`LNC0006` at the offending call, including composed generic arguments.
Parser checks preserve every fixed-array layer through depth 32 and validate
index chains rooted in names, fields, populated/empty calls, and call-returned
fields. Their source-span checks run against the production parser buffers.

## Implementation boundaries

The checker compares concrete type structure, including nominal identity,
recursive arguments, element type, and fixed-array length, including match-arm
results. The GPU computes native payload widths and instantiated record field
offsets. The host retains accepted call environments and source
snapshots, schedules concrete bodies, and links their existing native symbols.
It does not implement library operations or infer a layout from source text.

Retained type arguments carry a complete checked structural graph for slices,
fixed arrays, and nominal applications with all ordered arguments. Nominal
declarations retain their scoped identity and the GPU's accepted native width.
Body replay publishes this graph and its argument edges into a private arena
after the source-token capacity; source declarations remain immutable.
The native width relation uses `INVALID` for an unavailable layout and accepts
zero for a complete empty value. Layout traversal has a separate completion
state, so an empty child still completes and contributes zero to field offsets.
Retention and replay preserve its complete type independently of that width.
Native calls execute zero-sized bodies and preserve argument placement; indexed
empty-element operations keep their physical bounds checks. The compiler omits
only the zero-byte memory operation, after its operands have been evaluated.
A separate GPU producer creates applications implied by local record fields and enum payloads
in another private arena. Source and generated applications use a structural
hash index; complete scoped equality resolves bucket collisions. Unbound
parameters retain their declaration identity, and substitution applies once.
The producer tracks expanded types per root, so repeated argument/field edges
visit the accepted type DAG once instead of generating exponential work.
Checked body replay rebuilds the index, member references, and nested literal
contexts after applying its concrete environment. Constructor passes run only
when the parser reports their feature, so modules without structs never consume
uninitialized constructor relations from a reused workspace. Deferred template
literals have no executable field layout until their body is specialized.
Each call retains its own accepted result reference and legacy type code across
sibling specializations. Contextual nominal results compare complete accepted
argument types, including fixed arrays, before executable emission.

Both private arenas use the workspace's physical source capacity, including
when the current module has fewer tokens. A shared ordered-argument reader
prefers complete columnar rows and reads all 32 slots of a generated fallback
row. Checker claims, receiver projection, native layout, and host retention use
the same arena origin; a generated five-argument instance cannot be mistaken
for a four-slot source row. Generic claims also consume projected member result
references before the final semantic artifact is published.

Imported record literal contexts retain the declaration's stable library,
module, and local identity even when it has no local declaration token.
While its immutable dependency page is active, field projection validates
scalar and direct-parameter declaration fields, required names, duplicates,
and nominal identity. The complete accepted parameter type can itself be a
record, array, string, or slice. Contextual array literals validate length and
element type against the projected field reference. Native imported record
widths use accepted field types, and literal stores follow validated declaration
ordinals rather than written order. The current producer also instantiates
compound canonical subtrees and retains their checked field references.
The mixed compound-field program now has executable runtime evidence.

Imported record field readers share the same owning-page lookup and complete
accepted type projection. A member chain can cross local and imported records;
unknown fields clear the receiver placeholder and report `LNC0042`. A separate
GPU pass retains each accepted imported member's native word offset and count
after native widths are available. Native loads and stores consume those facts
without treating a declaration ordinal as a word offset. This pass runs only
for modules with member expressions and remains separate from the larger width
producer to preserve the shader size guard.

Nested literal context follows imported fields into caller-local record literals.
Array literals assigned to fields inherit the selected field's complete checked
array type, including length and element representation. Scalar assignments
validate the selected field type even when its receiver is an aggregate.
Monomorphic record assignments compare stable declaration identities; equal
field layouts do not permit assigning a different record type.

Local enum constructor and match payload references use the same scoped
substitution as record fields, including nested arrays and nominal types.
Indexed match results project their complete checked element type instead
of reusing the array base's token type. Enum storage uses the accepted
instantiated native width. Unbound nested declaration payloads stay unresolved
until specialization; their widths are never guessed from the outer syntax.
Resolved constructors keep their name resolution when a known payload type
is incompatible and report `LNC0006` at that argument.

Composed calls follow the checker's accepted return-argument relation before
claim matching. Nested index projection follows immutable accepted root
references, including call and member results, rather than another GPU lane's
partially published index. Parser postfix spans and nested bracket kinds are
also derived from immutable grammar/token ownership.

Imported complete return materialization and argument matching use the same
scoped checked graph, including private generated applications. Receiver calls
select the receiver's environment. Result-only contextual bindings publish only
after complete constraint validation; they cannot overwrite an accepted
argument binding. The host retains these accepted GPU facts and controls
inference rounds without inferring types or layouts.

Local result constraints use the same complete graph and scoped equality
contract. A recursive matcher returns ordered bindings for up to 32 parameters;
required-argument validation and retained call capture consume those bindings.
Its constraint input reads argument claims rather than its own result table.

Structural parameter patterns use that recursive matching contract, with one
argument lane owning its complete binding span. A bounded pattern walk counts
used parameters without truncating them to the four-slot scalar cache. It visits
at most 64 unique pattern nodes and 64 traversal levels. Source patterns and
imported canonical patterns publish caller-scoped checked references. Pending
imported return templates remain unresolved until complete materialization;
they cannot become false mismatches during inference. Scalar nominal leaves
remain nominal through call projection, declaration inference, and assignment.

Anonymous source modules publish one empty root path and zero module segments.
Interface sizing, record counts, and byte emission derive that fact from the
job's module count rather than unused scan scratch. Four previously failing
public-enum cases and named-to-anonymous retained workspace reuse pass.

The current call closure uses full GPU sweeps and a progress readback each round.
It is bounded to 64 rounds per HIR node; exhaustion reports `LNC0047` before
emission. This is a correctness mechanism, with a dependent work queue still
needed if larger generic workloads show excessive repeated work.

An imported `[T]` parameter binds its complete element type even when that
type has a larger canonical subtree than the parameter spelling. Existing
generic claims validate repeated uses of T. Indexed slice values retain their
descriptor classification through local copies and stores. Calls through
indirect descriptor storage preserve the base address and word selector,
using the existing native pointer/length protocol for both words.

Programs without generic syntax use direct executable emission. GPU parser
feature facts select this path, including validated cached parser shapes;
ordinary `<` comparisons do not require body specialization. Generic programs
retain the source and checked environment needed for body replay.

Compiler IR record formats, the extractor, formal proofs, and the x86 calling
convention are unchanged. Packed local i32 arrays are converted to and from
the existing native result and inline-field representation at the compiler
boundary. Match results and synthetic loop reads retain their checked storage
type. Ordinary nongeneric trait methods continue to use their native bodies
when a program also contains generic calls.

Declaration fields are compared under their enclosing type environment.
The GPU resolves and creates applications by complete scoped identity;
it never treats equal widths as equal types. Generic declarations keep symbolic
field templates, and checked body replay applies its selected environment only
after ordinary call validation. Literal-field validation compares complete checked references, so
`Cell<i32>` cannot initialize a required `Cell<bool>` even when both layouts
have the same size. Native field stores copy both words of string and slice
descriptors and preserve the existing eight-byte inline field layout.

Generic declaration layouts with an unbound value field stay unresolved;
`T` is no longer guessed to occupy one word. A field read waits for its concrete
receiver layout even when its result is scalar. Nested literals publish fields
in contiguous owner ranges, preserving the existing canonical HIR contract.

## Remaining work

This checkpoint does not yet establish generics over arbitrary types. Further
compiler work includes:

- Resolving the isolated contextual nested record-literal rejection recorded
  above, including its dependence on prior compilations and retained workspace
  state. It has not reproduced in the final gate, but has no established cause.
- Closing late constraints introduced only by concrete generic body replay.
  Inferred local/imported chains inside generic bodies and complete local
  result-only and structural parameter contexts now execute as described above.
  The field/index/match chains above also execute. Additional expression and
  constructor contexts still need closure and executable evidence.
- Extending receiving-context closure beyond the record, call, field, array,
  match-arm, and generic-body compositions verified in the current checkpoint.
  The three original `*_record_literal_context.lani` rejections now execute,
  including local/imported enum constructors and ordinary functions.
- Creating and indexing applications introduced by late body inference when
  their concrete type never appears in a source annotation. The ordinary call
  closure already creates the tested unannotated imported applications.
- Extending expected-type propagation beyond the verified declaration/return,
  call-argument, enum-payload, and nested-array contexts. Empty arrays and unsigned
  array elements now execute in those call/constructor contexts. Empty literals
  without a context still need a more precise missing-element-type diagnostic;
  generic calls currently report the explicit `LNC0047` instantiation boundary.
- Further numeric/expression contexts beyond the verified scalar call/constructor/
  match and nested-array cases. Unannotated local/imported calls now use known
  argument types in either order, including the tested array/nested-array and
  generic-body compositions. Known named values retain their actual types;
  context cannot authorize arbitrary coercion.
- Propagating constructor context through additional arrays of nested generic
  record literals and other expression shapes. Direct nonempty enum payload
  literals now execute for the arrays, records, and generic-body compositions
  listed above. Empty/nested empty and unsigned array payloads now have executable
  evidence. Further record and composed expression contexts remain unfinished.
- Additional slice element shapes beyond the verified scalar, record, string,
  fixed-array, and borrowed integer/string-slice cases above. Inline i32 array
  fields now borrow through the shared stride contract, preserving reads,
  writes, and aliases. This removes the two historical storage rejections.
- Additional pointer-containing slice and constructor contexts beyond the
  executable compositions above, and native full-width integer types. Bare
  record fields containing fixed arrays now execute inside enum payloads,
  arrays, imported generic calls, and inferred body applications in the nominal
  declaration-identity checkpoint.
- Complete reference support beyond the tested local/imported signatures,
  fields, forwarding, and method compositions: further nested referents and
  stable storage for references escaping a local call frame. Array and nested
  record impl receiver patterns now execute in the local/imported compositions
  above; additional reference patterns and imported/chained receiver contexts
  still need executable coverage. Private graph support alone does not establish them.
- Trait method generics and method where clauses. Local/imported inherent methods
  with their own type and constant parameters now compose with enclosing impl
  parameters through the shared environment contract described above.
- Blanket trait implementation environments, complete imported trait identity
  and contract context for caller-defined implementations, and wider compound
  caller-bound forwarding. Complete local trait arguments and concrete-body
  obligation checking are covered by the latest checkpoint above.
- Classify the positional `receiver: Range` control from the broader
  semantic sweep; its intended receiver convention needs to be resolved.
- Further explicit callable forms beyond the verified local/imported function
  and associated/dotted-method type/integer-constant headers. Ordinary string
  comparison also rejects without generics;
  its minimal reproduction is retained separately from successful string forwarding.
- The nested-match expression parser rejection retained in
  `tests/fixtures/stdlib_compiler_state/page-layout-nested-match-before.lani`.
  Sequential matches execute the same nested imported layouts in the page tests.
- Further constant inference and execution: general constant-expression operands,
  ordinary const-item names, further shadowing/type-dependent contexts, and
  broader typed-constant domains. Mixed nominal type/constant applications now
  execute in the current checkpoint. Durable constant parameter annotation types
  for object-only use remain open. Explicit integer
  literals and scoped caller parameters now execute in the listed callable forms.
  Value expressions, nested array
  patterns, annotated binding/declared return contexts, and symbolic forwarding
  now execute through local/imported functions and methods, retention, and body
  specialization, including all 32 constant slots. Expected-result contexts
  nested in arguments, fields, array elements, and match arms also execute in
  the current matrix. Local
  missing declared type and constant slots now reject during checking for local
  and imported calls, including unused parameters, with source-labeled `LNC0006`.
- Persisting generic body context for durable object-only linking.
- Further recursive instantiation beyond the ordinary, generic, and mutually
  recursive pair probes and recursive-reference case above. Retained native
  layouts, record field access, and local/imported generic body replay now execute
  for the nested record/enum compositions and page orders described above.

The current grammar and checked type model contain unit, scalars, arrays,
slices, references, and nominal applications. Tuple and function-value type
forms would require language definitions before they can join this executable
matrix. Every existing type form and its finite compositions remain in scope.

Empty records and `[i32; 0]` now execute through ordinary and generic forwarding.
Six retained reproductions compare ordinary, local generic, and imported calls:
`repro_ordinary_empty_forwarding.lani`, `repro_generic_local_empty_forwarding.lani`,
`repro_generic_imported_empty_forwarding.lani`, and the corresponding
`empty_array_forwarding` fixtures. Historical failing probes remain in
`generic-type-inventory-before.log` and `generic-empty-array-inventory.log`;
the current executable comparisons are in `generic-zero-runtime-checkpoint.log`.
`repro_generic_zero_literal_argument.lani` now executes as part of the direct
record-literal regression checks, including its assertion-failure variant.
Ordinary, local generic, imported generic, and contextual generic record literal
arguments have executable evidence. Constructor inference no longer guesses a
nominal identity from an identifier expression's generic HIR name marker.
Other constructor contexts listed above remain unproven.

Integer-width spellings still share signed or unsigned compiler identities.
The private application arena has at least 64 rows, or one row per source-token
capacity when larger. Declaration environments are bounded to 32 type and 32
constant parameters independently. Instantiation is bounded to 32 arguments
per type node, 64 traversal levels, and 64 generated or expanded nodes per root.
Arena exhaustion and traversal/substitution failures report an explicit compiler
boundary.
The current scheduler bounds resident specialization to 32 type arguments,
64 retained structural graph nodes, and 2,048 nominal argument edges per body,
256 bodies, and 64 MiB of native text. Aggregate parameter copies reject
individual native payloads above 65,535 words before executable emission. The
private scheduling key canonicalizes live semantic graph nodes, excluding derived
layouts and padded arena capacity. Layout facts are validated separately. Replay retains complete structural
graphs and stable declaration identities; it no longer reuses a mutable source
instance row as a substitute for the retained type. Unsupported bodies must
report an explicit error; these limits do not authorize guessed copies or no-op
bodies.

### Next implementation order

1. Close remaining constructor/expression contexts through the same type graph
   and environments. Compare ordinary, local-generic, and imported-generic
   execution for finite type compositions and explicit resource failures.
2. Extend the checked constant domain to the remaining expression and typed
   constant contexts. Explicit integer operands, local/imported impl/method
   composition, annotated and nested result inference, nested length inference,
   symbolic forwarding, retention, and specialization have executable evidence.
   Imported missing-binding diagnostics already reject during source-labeled
   checking. Preserve complete checked references and declaration-owned
   requirements across these consumers.
3. Reuse checked bodies, substitutions, layouts, and complete specializations.
   Measure increasing generic graph sizes alongside the existing large corpus;
   successful emitted programs are part of the performance gate.

## Performance

The earlier 2026-10-03 contract checkpoint uses shader digest `eb68683844f2cb2e`.
The existing `single-file-1mb` preset compiled 20 distinct million-byte programs
in `daemon_warm_workspace` mode. Compiler median was **41.287 ms** and wall median
**44.534 ms**. All 20 emitted programs pass exact output and exit checks, with
matching source hashes, zero timed compiled-unit cache hits, and zero new buffers,
bind groups, or pipelines. Independent result-schema validation passes. The
runner's existing catalogue `list.get` error occurs after the report is saved.
Raw evidence is in `benchmark_artifacts/performance/stdlib-gpu-20261003-contracts/`.
This is an unpaired measurement; the older 38.788 ms result does not provide a
matched regression comparison. Generic-graph scaling and a current cross-compiler
10x comparison remain unmeasured. Earlier measurements below are historical.

The preceding existing `single-file-1mb` preset run compiled 20 distinct programs
with zero timed compiled-unit cache hits and no new timed buffers, bind groups,
or pipelines. Every emitted ELF executed with its exact expected stdout and
zero exit status. Source hashes match the retained frozen corpus. Median
compiler time was 73.400 ms and wall time was 78.147 ms, with shader digest
`969718dcfd9ce8a8`. The older scoped-field run measured 37.580/40.501 ms with
digest `88fe9f6cd1685780`; that is an unpaired historical comparison.

To investigate the increase, two same-session control pairs used the existing
`gpu_compile_bench` on an identical 1,000,134-byte mixed source with seed 20,
three warmups, ten measured full compiles, and executable validation in every
iteration. Matched old host/shaders and current host/shaders ran in opposite
orders. Old average times were 78.495 and 66.562 ms; current times were 63.905
and 60.409 ms. The GPU was shared with other activity (one observation showed
65% utilization before a control). The old compiler also experiences the higher
absolute timings; these controls show no repeatable slowdown on that source.
They use a different corpus and include executable validation in the timed
span, so they do not replace a matched comparison on the canonical corpus.

The real 32-parameter composition program was measured with the existing
`stdlib_gpu_perf` example, three warmups and ten full entry recompiles. Entry
mtime invalidation occurred outside the timed span; imported-unit caches could
remain warm. Its median was 246.051 ms (minimum 209.666, maximum 261.647 ms),
and its final ELF passed exact Unicode/empty-string output and exit checks.
There is no earlier matched timing for that generic checkpoint. These measurements
do not establish performance for large generic graphs or a general 10x claim.

The measured inference checkpoint has shader digest `5b0b8f17178ea693`. Fresh
opposite-order controls compare its matched host/shaders with the preserved
baseline on the same 1,000,134-byte mixed source. Current averages are 69.620
and 68.257 ms, against baseline averages of 64.119 and 66.413 ms: increases of
8.6% and 2.8%. The difference above 5% did not repeat, but these results do not
establish unchanged performance or identify a cause. This nongeneric source
does not exercise the inference loop. Times include executable validation.

That checkpoint's real 32-parameter entry recompile has a 265.165 ms median
(252.001 ms minimum, 273.262 ms maximum), with warm imports and successful
final ELF validation. Its older 246.051 ms median is an unpaired checkpoint,
so the difference cannot isolate the inference changes. Raw current results
and matched binary/shader identities are retained under
`benchmark_artifacts/performance/stdlib-gpu-20261001-inference/`.

The subsequent local result-constraint and anonymous-module repairs have
shader digest `36552debb8404547` and the preceding 106-check correctness gate.
The preceding structural parameter and dependent-consumer repairs have digest
`7061ad913cc9d0ac` and the 110-check gate. Neither intermediate shader set was
benchmarked.

The preceding expression-inference checkpoint, digest `96ddfc90abad06ef`, passes
115 focused checks. A fresh `stdlib_gpu_perf` driver measured the same real
32-parameter program over three warmups and ten entry recompiles with warm
imports: median 248.106 ms, minimum 233.660 ms, average 248.737 ms, maximum
269.007 ms. Its final 66,433-byte ELF passed exact stdout and zero-exit checks.
Raw results, binary/source hashes, and shader metadata are retained under
`benchmark_artifacts/performance/stdlib-gpu-20261001-expressions/`. This is an
unpaired measurement; it does not establish an improvement over the preceding
265.165 ms median. The large canonical corpus and matched controls have not
been rerun for this checkpoint.

The preceding zero-layout checkpoint, digest `3979aa9b02a9bb6b`, passes 126 focused
checks. A fresh `stdlib_gpu_perf` driver measures the same 32-parameter program
over three warmups and ten entry recompiles with warm imports: median 265.524 ms,
minimum 242.884 ms, average 263.156 ms, maximum 280.107 ms. The final 66,433-byte
ELF passes exact stdout, empty stderr, and zero-exit checks. Results and
source/binary identities are retained under
`benchmark_artifacts/performance/stdlib-gpu-20261001-zero-layouts/`.
This is an unpaired measurement; it does not isolate the pointer/zero-layout
changes or establish unchanged performance. Large corpus controls have not been
rerun for this snapshot.

Semantic scatter uses the repository's per-shader minimum Slang optimization
policy. Generic claim emission also uses that policy; default optimization
exceeded the guard after adding projected member references. The 512 KiB
artifact guard remains enforced for all 733 shaders; the largest is 523,396
bytes at the preceding expression checkpoint and 518,612 bytes at the preceding
zero-layout checkpoint, against the 524,288-byte limit.

The earlier nominal benchmark's measurement and executable validation completed.
Its runner then
failed during catalogue generation because it treated an auxiliary JSON list
as a canonical result document. Raw results, the validation records, and that
postprocessing log, control pairs, and generic timing are retained under
`benchmark_artifacts/performance/stdlib-gpu-20261001-nominal/`; the compiler and
emitted-program results above are independent of catalogue generation.

GCC, G++, Rust, and Zig were not rerun. Their older comparisons in the
[performance report](stdlib-gpu-performance.md) do not establish the current
10x target, especially for Zig. TCC was faster in the retained comparisons.


### Body-layout timing (2026-10-02)

The current shader digest `79a0c384042f1c4b` contains 734 artifacts; the largest
is 518,612 bytes and the 524,288-byte guard remains enforced. A freshly built
`stdlib_gpu_perf` driver ran the same 32-parameter composition with three warmups
and ten entry recompiles, keeping imports warm. Median compilation time was
272.382 ms (minimum 263.471, average 272.207, maximum 278.996). The emitted
66,433-byte executable passed exact stdout, empty stderr, and zero-exit checks.
Logs and source/binary hashes are in
`benchmark_artifacts/performance/stdlib-gpu-20261002-body-layouts/`.

The preceding constructor checkpoint measured 250.085 ms for this program.
These are unpaired runs, so the difference does not isolate this patch's cost.
No new large-corpus or cross-compiler speed claim is made for the current code.
The preceding constructor corpus's 20 emitted programs were validated with the
frozen source hashes and expected outputs; records are in
`stdlib-gpu-20261002-constructors/checked/constructors-1mb.validation.txt` under
the performance artifact directory. Those measurements precede the current
body-reference and layout changes.


### Parameter-value and concrete-pattern timing (2026-10-02)

With shader digest `06452b5a23c1e68a`, the rebuilt existing
`stdlib_gpu_perf` driver measured the same 32-parameter mixed program with
three warmups and ten entry recompilations (imports warm). Median compilation
was 296.351 ms (minimum 284.076, average 296.540, maximum 313.358). The emitted
66,971-byte x86_64 ELF executed with the expected stdout, successful status, and
empty stderr. Logs and binary/input/shader hashes are in
`benchmark_artifacts/performance/stdlib-gpu-20261002-parameter-values/`.

The preceding body-layout median was 272.382 ms. These separate runs are not a
paired comparison, so they do not isolate a regression or establish unchanged
performance. A matched large-corpus comparison remains required after the
remaining caller-side value capture and layout corrections. This focused
program does not establish the 10x large-program debug-build target.


### Caller-side argument capture timing (2026-10-02)

Shader digest `8c5d3cddd7e40d24` passes the 100-check compiler gate, 49 adjacent
stdlib execution checks, and four graph reflection checks. The existing
`tools/lanius_perf.py run-lanius --preset single-file-1mb` benchmark ran its
20 canonical programs in `daemon_warm_workspace` mode. Median compiler time
was 39.088 ms and median wall time was 42.209 ms. Every timed sample had zero
compiled-unit cache hits and zero new buffers, bind groups, or pipelines.
Every resulting ELF executed with its expected stdout, empty stderr, and zero
status; all source hashes match the retained frozen corpus. The runner saved
its measurements before the previously recorded catalogue-generation
`list.get` error. That postprocessing failure remains separate from measured
compilation and executable validation.

Two opposite-order control pairs used matched preserved baseline host/shaders
and current host/shaders with the existing `gpu_compile_bench`: identical
1,000,134-byte mixed input, seed 20, three warmups, ten full compiles, and
executable validation in every iteration. Current averages were 51.198 and
52.214 ms; baseline averages were 51.443 and 52.886 ms. These controls show no
slowdown on this input. They include executable validation in the timed span
and use a different corpus from the canonical 20-program benchmark. They do
not establish a general cross-compiler 10x claim or generic-graph scaling.

The rebuilt `stdlib_gpu_perf` driver measured the real 32-parameter mixed
program over three warmups and ten entry recompiles with warm imports. Median
was 250.815 ms (minimum 243.288, average 250.642, maximum 258.119). The emitted
78,746-byte ELF passed exact stdout, empty stderr, and zero-status validation.
Its preceding 296.351 ms result was an unpaired run and does not isolate this
change's compilation cost. Caller capture adds generated copies; eliminating
redundant copies requires preserving the demonstrated evaluation and borrowing
contracts.

Raw results, control input/binary hashes, shader metadata, and all 20 executable
validation records are under
`benchmark_artifacts/performance/stdlib-gpu-20261002-argument-capture/`.

### Array-literal inference timing (2026-10-02)

Shader digest `87227182d18aa93b` passes 124 compiler execution checks; the two
known inline-array borrowing tests remain failures. Four focused parser checks
and four compiler resource-contract checks also pass.

The existing `tools/lanius_perf.py run-lanius --preset single-file-1mb` runner
compiled all 20 canonical programs in `daemon_warm_workspace` mode. Median
compiler time was **45.224 ms**, and median wall time was **48.565 ms**. Every
sample had zero compiled-unit cache hits and zero new buffers, bind groups or
pipelines. Every emitted ELF ran with the generator's exact expected stdout,
empty stderr and exit status zero. Source hashes match the retained frozen corpus.
The runner saved its results before the previously recorded catalogue-generation
`list.get` error; runtime validation was performed separately on all 20 artifacts.

This compiler median is 15.7% higher than the earlier argument-capture
checkpoint's 39.088 ms. These runs were not
paired under the same conditions, and accumulated reference/method changes also
separate them. The result does not establish unchanged performance or isolate a
cause. No generic-graph scaling run or cross-compiler 10x comparison was performed
at this checkpoint. Performance investigation remains part of the unfinished goal.

Raw results, shader metadata and executable validation records are under
`benchmark_artifacts/performance/stdlib-gpu-20261002-array-literals/`.


### Semantic contract consolidation timing (2026-10-02)

Final shader digest `cc73f5ad3abd615e`. The existing `single-file-1mb` preset,
`x86_64` target, and `daemon_warm_workspace` mode compiled 20 distinct programs
(seeds 20–39). Compiler median was **38.788 ms** and wall median **41.816 ms**.
All emitted ELFs produced the generator's exact stdout, empty stderr, and exit 0.
Source SHA-256 values match the workload manifests. Every measured sample reports
zero compiled-unit cache hits and zero new buffers, bind groups, and pipelines.

The runner wrote the complete result before the known catalogue postprocessing
`list.get` failure. Independent result-schema validation passes, and all 20
executables were validated separately. The earlier 45.224 ms and 39.088 ms runs
are unpaired historical measurements. This checkpoint neither isolates a causal
speedup nor establishes generic-graph scaling or a cross-compiler speed ratio.

Raw report, tool log, shader metadata, and runtime validation records:
`benchmark_artifacts/performance/stdlib-gpu-20261002-semantic-contracts/`.
