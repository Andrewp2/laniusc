# Compiler semantic contracts

## Borrowed receivers that are not places (2026-10-15)

A `&self` method can be called on a value with no storage of its own, such as
a call result: `make().get()`, `w.twice().get()`, `!make().ok()` or
`absent.or(present).contains(7)`. Lowering treats the receiver as the
initializer of a hidden `let`. Semantic LIR stores the value in a
compiler-generated local, then passes that local's address. Each evaluation
stores again, so a receiver in a loop sees the current value.

- `local_mark` gives the call one local. `local_scatter` keys it by the call
  site's method name token, which is unique to the call and never names a
  declaration.
- `place_mark` gives that token a stable home, sized from the matched receiver
  type.
- `count` appends two rows to the receiver: `PLACE_STORE` into the home, then
  `ADDRESS` of it. The call argument reads the last row.

The predicate is in `codegen/lir/semantic/receiver_temporary.slang`. Names,
fields, indexes and paths still borrow their own storage. Some receivers are
still rejected as before:

- a parenthesized receiver;
- a field or index of a temporary (`make().inner.get()`);
- a receiver that the method dereferences first.

Wasm has no place operations, so it still rejects every borrowed receiver. The
stored copy lives in the function's frame, under the caller-managed lifetime
contract described below. There is no escape check.

## Scalar casts (2026-10-15)

`expr as T` converts one scalar value to another with Rust semantics:

- Integer to integer: a narrower target keeps the low bits; a wider target
  sign-extends a signed source and zero-extends an unsigned one. So an `i32`
  -1 cast to `u32` is 4,294,967,295, 300 cast to `u8` is 44, an `i8` -1 cast
  to `i32` is -1, and a `u8` 255 cast to `i8` is -1.
- Integer to float rounds to nearest. Float to integer truncates toward zero,
  saturates at the target's bounds, and maps NaN to zero. `f32` and `f64`
  convert to each other.
- `bool` to an integer gives 0 or 1. `char` to an integer gives its code point,
  truncated to the target width, and `u8` to `char` gives the character with
  that code point. `bool` and `char` also cast to themselves.
- Anything else is `LNC0072` "invalid cast". That includes casts to `bool`,
  `bool` or `char` to a float, any integer type other than `u8` to `char`,
  and casts from or to a non-scalar type.

A cast binds tighter than every binary operator and looser than unary
operators: `-x as u32` is `(-x) as u32`, and `a * b as u8` is `a * (b as u8)`.
Casts chain from left to right. The target is a type name, optionally
qualified: `u32`, a local alias, or `lib::sizes::Length`. Generic
applications, arrays, references, and a missing target are parse errors.

Deviations from Rust:

- `x as u32 < y` parses as a comparison. Rust rejects it because it reads `<`
  as the start of generic arguments. After a qualified target, as in
  `x as a::b < y`, the `<` can still be taken for a generic application, so
  parenthesize the cast.
- An unsuffixed integer literal is `i32`, so `97 as char` is rejected; Rust
  infers `u8` there. Cast a `u8` value instead.
- An unsuffixed float literal is `f32`, so `1.5 as f64` widens an `f32`.
- There are no pointer, reference, enum-discriminant, or function casts.

The parser builds a cast as HIR binary form 36: the operand on the left and the
target type row on the right. The type checker gives the expression the target
type and checks the source and target pair. Semantic LIR lowers it to `CONVERT`
and records the checked source type. x86_64 emits a dedicated conversion
sequence. The wasm backend does not support `CONVERT` yet. It stops with the
generic `LNC0057` lowering error, not a dedicated diagnostic.

A char literal is always a `char`: `expression_types/00_init.slang` types it
directly, so `'Z' as u8` lowers with a known source type. Integer and float
literals still take their type from context.

A const generic parameter used as a value, such as `N as i32` in
`fn length<const N: usize>`, reads its scalar type from the checked constant.
The type checker writes it to `semantic_expr_scalar_type_by_hir` in the packed
form every other row uses: the scalar id in the high bits (`SCALAR_TYPE_SHIFT`)
and all link bits set. Lowering decodes the high bits. Before 2026-10-15 the id
was written unpacked, so it decoded as unknown and x86_64 rejected the cast
with `LNC0017`.

## Call inference termination (2026-10-15)

Call inference repeats its passes until a round changes nothing. The host reads
two things after each round: the round's change count and the status words. It
stops in four ways:

- **Converged.** The round changed nothing. The final passes then run with
  inference closed.
- **Error recorded.** The check fails whatever later rounds would infer, but
  the final passes report the root error only once inference has finished:
  missing-fact errors (an unknown type, an unresolved call) wait for it, while
  their consequences can be recorded earlier. So inference continues for up to
  `CALL_INFERENCE_ERROR_ROUNDS` (16) rounds after the first recorded error.
  - If it converges within them, the check reports as usual: the
    smallest-token error after the final passes.
  - Otherwise the loop stops, which ends an inference that an error keeps from
    converging. The remaining passes run as usual, but the check reports the
    status words of the round that stopped it, because the later passes ran on
    facts inference never finished, and their errors can be consequences of the
    stop.
- **Depth limit.** This is a language limit, like Rust's `recursion_limit`.
  - Inference may take at most `CALL_INFERENCE_DEPTH_LIMIT` (1024) rounds. A
    chain of dependent calls usually resolves one link per round, so a longer
    chain needs a type annotation to break it.
  - Reaching the limit is LNC0047 GenericInstantiationBoundary detail 17.
  - Programs under the limit always pass, and the worst case is about 15 s
    (1024 rounds of ~15 ms on 740 KB).
- **Change bound.** Inference is monotone, so each fact changes a bounded
  number of times. The changes of all rounds together are therefore at most
  `CALL_INFERENCE_CHANGES_PER_SLOT` (32) per HIR node and token slot, per
  dependency page. A larger total means some producer rewrites facts without
  progress, which is a compiler bug (detail 16).

A producer counts a change only when the fact's value changes. Rows with one
canonical ID are one value. Two producers can publish the same application as
different checked rows: the nested-literal pass its indexed field row, and the
canonical context path the realized row of the ID. Comparing rows there instead
of IDs counted a change every round (`calls/03k3_project_record_contexts`, the
same rule as `calls/03e_materialize_return_types`). Identical reference words
are also one value when a structural comparison cannot walk them, such as an
array element whose type name is unresolved: `calls/03i_materialize_array_literals`
republished such a literal, allocating a row, every round.

## Semantic replay identity, widths, and original recipes (2026-10-11)

A replay seed owns a closed semantic type graph and literal constant arguments.
Native width is an optional witness: missing and known zero are different states.
Width availability does not enter semantic specialization identity or cause
otherwise identical seed nodes to be duplicated. Known conflicting witnesses
reject instead of changing the selected semantic type.

The late GPU layout pass visits active seed rows as well as ordinary source and
generated rows. Replay layout admission validates supplied witnesses and requires
layouts for passed argument roots before native lowering can publish a body.
A reference or slice needs its descriptor width; an opaque referent's value width
is not required merely to pass that descriptor. Missing foreign nominal payloads
remain an explicit boundary when neither a witness nor a usable recipe is present.

Owned replay readback retains the completed GPU widths. The native cache records
that completed vector, not the caller's incomplete input vector, and checks later
known witnesses against it before body reuse. The host does not infer native sizes.
Focused GPU checks cover zero width, a contradictory array witness, recovery in
the same compiler, preserved prior readback, and opaque referents under descriptors.

Original public/private nominal recipes retain ordered record fields and enum
variant payloads as complete symbolic graphs. Their source snapshot, nominal
identity, and exact lexical owner remain explicit, including unused definitions.
Concrete replay reuses the immutable original recipes rather than replacing them
with one specialization's fields.

An immutable recipe sidecar is paired with the exact frozen catalog epoch and
atom inventory. Its payload graphs enter the existing catalog graph admission;
separate GPU phases then admit recipes and ordered groups before freezing the
recipe receipt and nominal-to-recipe map. Both directions of group ownership and
exact lexical parameter ownership are checked. Host serialization supplies no
trusted acceptance bit. Both catalog and recipe receipts must be valid before
program evidence is released; this adds no readback fence.

Build 23's focused GPU test checks valid recipes, stale epoch rejection, a broken
group backlink, a foreign lexical parameter, and valid-catalog recovery. This
proves the admission boundary; consuming an admitted recipe to compute a missing
foreign nominal layout is separate work.

The actual foreign missing-layout consumer and abstract trait-member routing
remain unfinished. The [execution checkpoint](compiler-generic-types.md#semantic-replay-and-native-layout-prerequisites-2026-10-11)
distinguishes host, GPU readback/admission, and native execution evidence.

## Generic methods and exact lexical contracts (2026-10-11)

A direct generic trait implementation method has its own callable identity and
an exact enclosing impl. Its inherited environment composes the impl's type and
constant domains; declaration identity remains separate from substitution slots.
Catalog admission and required-method binding validation accept that inherited
environment and preserve exact signature and native-target correspondence.
Trait methods' own generic headers and own prerequisites remain unsupported.

A method owns its `where` predicates even when it declares no parameters and
those predicates name only enclosing impl parameters. Predicate ownership uses
the canonical callable kind. Parameter lookup still follows parameter-bearing
scopes, preserving lexical shadowing and rejecting wrong parameter domains.
Replay starts owner validation at the exact selected method before visiting its
ancestors, so a headerless method's own predicates are not skipped.

Strict local call checking resolves the checked callee HIR and visits its exact
method-to-impl chain. Tokens index predicate buckets; exact HIR identity decides
ownership. Subjects and operands retain their predicate's lexical roots and use
the original call environment. Counting and selection share the same traversal,
with the existing 32-obligation limit applied to the complete callable contract.
Pending-original/replay deferral and the mandatory native publication gate are
unchanged.

The focused Stage A checkpoint passes eight native execution/rejection tests,
four strict-interface tests, and one host contract test. Strict successes used an
identical-binary cache alias after the normal basename exceeded its initialization
watchdog; the complete provenance is in
`tests/fixtures/stdlib_compiler_state/generic-trait-methods/`. Abstract member
routing through `T: Trait` is still unfinished. See the
[execution checkpoint](compiler-generic-types.md#direct-generic-trait-implementation-methods-2026-10-11).

## Implementation heads, proofs, and native replay (2026-10-11)

Generic implementation lookup uses exact owner, parameter domain, and ordinal
identities over complete structural type graphs. One-way matching keeps goal
parameters rigid. Head-overlap checking permits variables on both sides and
performs an occurs check. A fixed prerequisite check consumes completed bindings;
it cannot restart inference. Explicit depth, pair, occurs, and substitution work
limits distinguish resource exhaustion from malformed input and no match.

The catalog admits complete implementation heads and checks coherence. A proof
frontier selects candidates and constructs prerequisite evidence. Implementation
and assumption proof admission run in separate GPU dispatches over the same
pending wave, followed by edge checking and commit. No admission dispatch itself
publishes authority. Malformed proof kinds or fields leave persistent accepted
prefixes unchanged and poison the failed packet. Catalog shaders bind only their
catalog resources; proof-store resources belong to proof matching/admission.

Source checking retains accepted implementation prerequisites as well as callable
bounds. Parameter lookup returns the declaration token, preserving lexical
shadowing. Named owners use their name token; unnamed implementation owners use
their source start token. A trait implementation's payload contains a dense bound
HIR index, which must never be interpreted as a token key. The full head checker
owns graph and parameter validation; later diagnostic passes preserve its
accepted scalar, parameter, and structural root domain.

Pending original units and privately authorized replay units defer nonintrinsic
call implementation selection after checking the owner, subject, environment,
and complete key. Strict checking, unknown modes, and intrinsic bounds remain
strict. During replay, selected-body calls receive fresh program proofs; ordinary
sibling calls must equal admitted originals. Omitted generic templates recover
original facts only after the native gate proves that their bodies and calls
were not emitted. The selected callable and complete call-owner inventory remain
mandatory. Definition-bound materialization checks also remain mandatory.

The focused native marker, GPU matcher, retained-owner, proof corruption, and
host replay tests are recorded under
`tests/fixtures/stdlib_compiler_state/generic-implementation-proofs/` with exact
per-run snapshots. Those marker tests do not establish trait-method execution;
the later direct-method checkpoint above records that separate evidence. The
remaining limitations are listed in the [execution checkpoint](compiler-generic-types.md).

## Structural method receivers and storage (2026-10-11)

The focused execution tests now pass. Eleven structural receiver tests cover
storage identity, copies, evaluation order, imported selection, empty arrays,
iteration, and bounds failures. Seven additional generic composition and call
chain tests passed during integration. The page-order check verifies ambiguity
and recovery in a reused workspace. Evidence is in
`tests/fixtures/stdlib_compiler_state/structural-native-places/verification.json`.

Method selection retains the original receiver graph. It considers that graph
and each successive reference referent, with the existing 64-level bound. Local
methods and public inherent methods from the current unit's admitted dependency
interfaces contribute to one candidate selection. The shallowest matching level
wins; at that level, a method in the caller's local lexical module takes
precedence. Distinct equally ranked callables are ambiguous, independently of
dependency-page order. A source `use` statement and a dependency interface page
are different inventories. Separately linked units are not implicitly added to
this lookup scope.

Selection finishes before publishing a callable or its signature. The checked
call records the source receiver HIR, dereference count, matched full type,
passing mode, and accepted first-parameter type. Only syntactic `&self` introduces
an additional reference. An explicitly typed first parameter must match the
adjusted receiver as a value. Qualified calls have no implicit receiver.

An empty local method inventory owns no lookup buckets and contributes no
candidates. It cannot read storage left by another workspace occupant. Once
selection reports ambiguity or an invalid adjustment, the later signature pass
preserves that diagnostic. A dotted call's callee is its member leaf; a call in
the receiver expression keeps its own identity and result.

Compact parameters retain full checked type references. Explicit parameters,
implicit value `self`, and implicit `&self` all supply the same contract to
template closure and native parameter layout, including unused parameters.
The callee therefore agrees with the caller on one-word references, three-word
array/slice argument descriptors, and private storage for owned array copies.

A reference to a declaration, field, or indexed element names its actual
storage. Reassignment must be visible through an existing reference. Addressable
declarations receive stable homes before lowering and SSA; reads and writes use
explicit memory operations. By-value receiver adjustment copies the matched
value at receiver evaluation time, before later arguments can mutate storage.
Owned fields copy; reference and slice members retain their backing aliases.
Every one-word reference to a fixed array uses canonical native-word element
layout, including arrays nested in aggregates or reached through a slice.

Runtime value shape follows the checked root type. Bounds on a referenced slice
do not turn the reference itself into a slice descriptor. Passing an array to a
slice parameter preserves its backing storage; passing an owned array captures
a copy. An indexed element of a temporary slice descriptor can borrow that
backing storage without making the descriptor itself addressable.

Inherent methods have explicit implementation owners and full subject graphs;
their owner need not be a nominal declaration. The interface migration changes
the schema and rebuilds consumers together. Trait implementations remain a
separate kind for implementation-evidence selection.

References retain the existing caller-managed lifetime contract: referenced
storage must remain alive while used. This work does not add or claim static
escape checking. Direct borrows of temporary descriptors or owned temporary
arrays, and variant-payload places without an accepted storage recipe, reject
explicitly. A `&self` receiver is the exception: its value is stored first, as
described in "Borrowed receivers that are not places". The focused acceptance programs use valid
storage lifetimes and exercise aliasing, mutation, receiver evaluation order,
structural generic substitution, and imported/local method ranking.

## Borrowed enum values and structural child ownership (2026-10-10)

Checking a borrowed enum match follows reference edges to the complete enum
application. Payload substitution uses that application, including its defining
identity and ordered arguments. The scrutinee keeps its original value type.
Every payload occurrence retains a checked type, including `_`; later payload
offsets depend on the widths of ignored prefix fields. Only named payloads
publish lexical bindings. A reference occupies one native value word; its
aggregate-copy width remains zero.

Native match counting validates the terminal enum and pattern identities once.
Counting and materialization share the row recipe, including address loads,
arm boundaries, payload extraction, the result, and final argument capture.
Owned enums and one-layer references already supply the enum address. Additional
reference layers require pointer loads, but native production of those values
is not established: the retained `impl &Flag` probe rejects with `LNC0021`.
Scalar-reference matching also remains unsupported. Wildcard-only matches need
no dereference.

Structural child edges become final after every dependency page has projected
imported names into persistent checked instances. The existing final
array/slice/reference details pass now runs at that boundary, before argument
compaction and alias normalization. Graph registration and command recording
use the same order. Normalization continues rejecting page-local type roots;
this ordering change adds no dispatch.

Semantic instruction totals exceeding allocated capacity publish a lowering
failure before target output can return. A semantic-capacity-only failure
reports required and available rows through `LNC0057`. Mixed failures preserve
their existing details because the status words can carry another phase's
context. The GPU test checks capacity, overflow, and cleared recovery in one
reused workspace.

## Retained generic call graphs (2026-10-10)

The retained call graph distinguishes semantic identity, closure, and native
readiness. Symbolic type parameters and array lengths retain their exact owning
binder, type/constant domain, and position in the binder's mixed header. The
composed substitution slot is a separate field. Arrays, slices, references, and
nominal arguments retain these leaves even when native widths are unavailable.
Known zero width remains distinct from missing layout.

Public nominal and binder identities use the exporter's actual owner mapping.
Private identities remain source-owned anchors into the retained immutable unit;
they are not fabricated exports. Replay anchors and native widths do not enter
semantic specialization identity. Reusing library/unit numbers with a different
source snapshot does not authorize interpreting those private anchors.

Readback copies accepted GPU facts. Active declaration headers and sparse owner
metadata share the existing call readback batches; the host does not infer types
or select trait implementations. The interface-export graph owns its lexical
scope mapping and declares the retention consumer before allocation, keeping it
alive across native scratch reuse.

Symbolic calls await their enclosing body's concrete instantiation. The newer
semantic-replay contract above permits missing native width in a closed seed;
GPU native-layout completion failures report the `LNC0047` instantiation boundary
with the layout detail. An unrepresentable replay packet still reports `LNC0017`
with the cause. The retained reader's 256-level integrity bound
does not enlarge native replay: its existing packet still permits 32 type and 32
constant slots, 64 total structural nodes, and 2,048 argument edges.

These graphs are a prerequisite for caller implementation evidence. They do not
yet select a program-catalog implementation, retain its proof, or forward that
proof into imported body compilation.

## Portable implementation evidence (2026-10-10)

Schema 12 adds 14-word implementation records, ordered canonical operand roots,
and six-word required-method bindings. Implementation identity is the defining
library/unit plus deterministic exported implementation index. The subject graph
is independent of a nominal declaration, so scalar and structural subjects keep
their complete types. Bindings retain the required trait method and the actual
native target triple, including private callables.

Member and predicate `owner_ref` use a tagged declaration/implementation domain;
declaration parent ownership remains `owner_declaration`. Rebase the payload in
its own table and retain the tag. Implementation method members have kind 8 and
carry their full receiver graph. Their lexical `value_hi` is distinct from a
binding's native target symbol. The shared `callable_identity.slang` producer
keeps export and native definitions consistent. Failed method validation revokes
the retained required-method identity.

The GPU exports complete accepted concrete public implementations or rejects
unrepresentable contracts. The host checks graph closure, ownership/ranges,
method coverage, substituted signatures, and native identity shape. Dependency
pages preserve stable implementation identity while rebasing storage references.
Existing declaration-owned method consumers remain restricted to their member
kind. Empty jobs clear the new totals; optional tables use bounded minimum
storage without predicate features.

The [checkpoint](compiler-generic-types.md#portable-implementation-contracts-2026-10-10)
passes 79 selected checks, including executable public/private method bindings.
Caller selection and imported body forwarding were added in the later
[native checkpoint](compiler-implementation-evidence-plan.md#native-caller-evidence-executable-checkpoint-2026-10-11).
Generic implementation/prerequisite records reject explicitly; host representation
of constant operands does not establish source support for constant trait applications.

## Portable callable predicates (2026-10-10)

Schema 11 adds eight-word predicate records: callable declaration and scope,
subject root, defining trait triple, and an ordered operand range. Operand roots
use the existing canonical type/constant graph. Parameter leaves and symbolic
array lengths name exact member records, so equal slot numbers in unrelated
callables cannot become equal bindings. Persisted records contain no dependency
page rows or path handles. Batch/page packing rebases owner and graph storage
references and retains trait identity.

Export selects accepted public free-function bounds from authoritative checker
facts, seeds each operand independently, and rejects missing or unrepresentable
public contracts. Absent predicate features reserve bounded minimum storage;
indirect scans use the compact predicate count and clear empty totals for reuse.
Method `where` clauses currently reject before export, including inherent
methods. Host representation tests for method scopes do not establish their
source-language or runtime support.

The canonical predicate-owner marker also separates both generic bounds and
trait implementation headers from nominal value collection. Each operand owns
its checked graph; there is no artificial trait value whose expansion counts all
operands together. Local required-method lookup consumes the checked trait
reference directly. Existing graph limits remain unchanged.

The [checkpoint](compiler-generic-types.md#portable-callable-bounds-2026-10-10)
passes 67 selected checks, including native execution and dependency-page reuse.
Callable requirements are portable. Selected implementation evidence and its
forwarding into imported body compilation now have an executable
[native checkpoint](compiler-implementation-evidence-plan.md#native-caller-evidence-executable-checkpoint-2026-10-11).

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
example now compiles and executes. Native body compilation consumes one accepted
replay request, then checks fresh calls before releasing its object. See the
[native checkpoint](compiler-implementation-evidence-plan.md#native-caller-evidence-executable-checkpoint-2026-10-11).
The subsequent [sibling-method checkpoint](compiler-generic-types.md#generic-sibling-method-emission-2026-10-11)
checks native emission before restoring omitted sibling template facts. Blanket
implementations, generic trait methods/where clauses, and ordered constant trait
operands remain open.

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

A resolved local callable publishes its complete result reference under the accepted
call environment. This also applies when a method is found during inference,
after initial signature seeding. Receiver shape does not decide whether a
compound result exists. Closed result graphs reuse their checked reference;
symbolic results are materialized under the declaration-owned environment.
Closure traversal consumes the same structure interface for immutable readers,
private producers, and native layout.

Logical GPU tables expose their declared byte ranges to shaders. A physical
scratch slot may be larger and may serve other resources at different times;
that capacity is not part of the table. Materializing a graph view now creates
a bounded subrange, preserving allocation identity and storage reuse while
making shader `GetDimensions` independent of the slot's other occupants.

This fixes a reproducible sequence failure: compiling imported nested `Option`
values first made a subsequent imported enum alias fail name resolution. The
alias table could expose 524,288 bytes through a 32,768-byte declaration.
Disabling storage coloring, or adding diagnostic reads that changed allocation,
masked the failure. The production correction keeps coloring enabled. Runtime
coverage checks enum payload values and mutations through the borrowed slice.

All 276 selected checks pass: 113 execution/rejection checks, 99 semantic checks,
58 resource/native/page/pass checks, and six parser/feature checks. Execution is
x86_64 Linux ELF emitted by the GPU compiler. The full execution inventory was
not rerun. See the [checkpoint](compiler-generic-types.md#late-method-results-and-logical-buffer-bounds-2026-10-10)
and its performance evidence. Imported trait identity, blanket implementations,
trait method generic headers/where clauses, and the other listed dependencies
remain open. No native ABI or private interface format changes.

## Complete trait predicate types (2026-10-10)

Trait arguments use the ordinary type grammar and canonical ordered argument
roots. Collectors retain checked references for the subject and every argument;
the first two cached argument tokens serve diagnostics only. Declaration graphs
validate nominal arity throughout the graph, so an incomplete nested application
cannot masquerade as a concrete type.

Implementation keys contain trait identity, argument count, and a hash of the
complete subject and ordered argument graphs. A matching hash is followed by
complete scoped equality. Nested nominal identity, element types, array lengths,
reference/slice shape, and argument order all participate. The shared graph
contract permits 32 trait arguments and has a 64-level traversal bound.

Call obligations consume the accepted call environment. Forwarding may use a
matching declared bound owned by the caller; matching parameter slot numbers
alone are insufficient. Selected generic bodies validate their obligations
again after concrete replay, before native emission. This closes the observed
case where an imported generic body silently lost its bound check.

Method contract validation substitutes the implementation's complete trait
arguments into the declaration signature and compares checked parameter and
return types. Equivalent types need not have identical syntax trees. The old
pass pairing nested argument nodes by HIR position is removed. Concrete replay
adds one obligation-validation pass, leaving the total kernel count unchanged.

Host allocation and pass scheduling precede semantic token classification.
The lexer therefore publishes a conservative reference feature: `&` after a
known value-ending token is binary; other positions reserve reference storage.
Semantic parsing also publishes reference syntax. Reference-only declarations
cannot depend on unrelated struct or generic syntax to enable their producers.

Blanket trait implementations and trait methods with their own generic headers
or where clauses remain explicit unsupported cases. Imported trait identity in
a caller-defined implementation remains a reproducing dependency. The later
method-result checkpoint above resolves the unannotated compound result case.
See the [trait checkpoint](compiler-generic-types.md#complete-trait-type-graphs-2026-10-10)
for executable coverage and retained reproductions.

## Bound argument storage (2026-10-10)

Argument claims describe bindings after permitted outer argument conversions.
An explicit slice binding can borrow a compatible array; the argument's actual
type remains an array. The shared conversion check compares complete element
identity and permits no nested aggregate conversion. Explicit bindings are read
at claim publication, after their producer, rather than during early pattern
collection.

The bound parameter also determines capture mode. Imported calls retain that
mode while their declaration page is resident. Enum projection preserves it,
and aggregate lowering stores the full slice descriptor using the existing
view conversion and signed storage stride. Following payload offsets use the
converted value width. Ordinary array arguments still copy by value.

The [bound-slice checkpoint](compiler-generic-types.md#bound-slice-arguments-and-enum-payloads-2026-10-10)
passes 61 selected checks, including real alias mutations and argument evaluation
order. No new kernel, buffer, ABI, or private format is introduced.

## Qualified occurrence replay (2026-10-10)

All anchors of one qualified type occurrence expose the same checked reference.
When an imported alias normalizes to a parameter, replay follows the parameter's
exact declaration identity and selected lexical environment. It updates both
the path head and final segment, so parameter and result consumers cannot read
different specializations. Other lexical owners remain symbolic. The original
public template interface is retained separately from the specialized object.

The [replay checkpoint](compiler-generic-types.md#qualified-alias-body-replay-2026-10-10)
passes 49 selected checks. Its unit regression isolates the previously failing
concrete replay after successful template checking; the runtime program verifies
complete value copies and borrowed aliases. One existing producer changes; no
pass, allocation, ABI, or private format is added.

## Imported member ownership (2026-10-10)

Source scope selects an unambiguous parent before normalization. The normalized
checked type owns member lookup, including when the source parent is an alias
or reexport. Lookup reacquires its stable declaration identity on each resident
dependency page and publishes stable member identity. It reuses the visibility
hash workspace only after visibility consumers finish. Late value metadata
projection preserves normalized type references.

Constructor binding decodes the complete target arguments into the existing
checked binding table. Associated methods consume the complete checked receiver
and keep their own header independent. Scheduling cannot infer an absence of
bindings from an absence of written operands: concrete imported aliases can
supply an entire application. Qualified value paths therefore enable binding
and validation even without angle-bracket syntax.

The [imported member checkpoint](compiler-generic-types.md#imported-alias-members-2026-10-10)
passes 68 selected checks, including native execution and rejection across four
dependency-page layouts. No ABI, interface format, or buffer allocation changes.

## Checked module boundaries (2026-10-10)

An imported alias application retains the alias declaration identity and its
ordered arguments until its target is materialized under that environment.
Each dependency page contributes caller-owned checked references. Only after
all pages contribute does normalization follow nested targets. No retained
target contains a page-local type index.

The public interface serializes complete checked graphs in bounded contiguous
reverse preorder. HIR supplies annotation roots and lexical ownership; it does
not supply the normalized shape. Array, slice, and reference annotations keep
their outer checked node. Exact type and constant declaration tokens map to
portable member identities. Removed syntax reconstruction and root propagation
passes have no fallback path.

Concrete replay and template export have different outputs. Replay emits a
specialized object and checked nested calls while retaining the original public
interface. It does not export its concrete graph as a new generic signature.

The [imported alias checkpoint](compiler-generic-types.md#complete-imported-alias-types-2026-10-10)
passes 58 selected checks, including executable dependency-page permutations,
immutable replay interfaces, and resource/lowering contracts. Export bounds are
64 levels, 32 nominal operands, and the existing HIR-capacity tree budget;
invalid or exhausted graphs reject. No ABI or interface format change in this
checkpoint. Imported alias-qualified member lookup is covered by the follow-up above.

## Normalized constructor binding contracts (2026-10-10)

Parent binding, type normalization, and member lookup are separate producers.
A constructor inherits the normalized enum application, including reordered,
injected, and constant operands. Alias source operands validate the alias's own
header and cannot be rebound as the underlying enum's header. Bare concrete
aliases provide a parent application; an unbound declaration template does not.

One producer publishes checked call bindings in a bounded compact table.
Descriptors identify a reserved range and independent type/constant slot masks.
Readers perform mask/rank lookup and never traverse source HIR or a parent type
graph. Publication precedes inference, reservations survive its repeated rounds,
and each workspace job resets validity and spare tags. Resource graph modes mark
the binding columns as producer outputs. Selected-body replay specializes their
type references along with other accepted references. Constant type edges on
generated nominal nodes use the same exact-declaration substitution as arrays.

The [constructor checkpoint](compiler-generic-types.md#normalized-local-alias-constructors-2026-10-10)
passes 34 runtime/rejection checks and both graph resource/lowering checks.
That checkpoint left imported generic alias materialization open. No ABI or interface format
change; one member-resolution kernel is added and existing bind/replay passes own
the new binding relation.

## Transparent alias and parent identity contracts (2026-10-10)

An alias application denotes its substituted target. Each immediate target uses
that alias's ordered type/constant environment; declaration parameter identity
survives forwarding and body replay. Normalization reads immutable source rows,
then publishes complete checked references before signatures are captured.
Generated arrays participate in constant replay and equality just like source
arrays. Equality compares full checked graphs, including nominal identity and
lexical parameter identity. Source spelling and matching parameter slot numbers
cannot establish equality.

Qualified method resolution consumes the existing stable parent binding.
Imported identity belongs to the path's application, so projecting an imported
method cannot rewrite a same-named local declaration. Local/imported method and
qualified enum controls pass alongside alias execution and rejection checks.

The [alias checkpoint](compiler-generic-types.md#transparent-local-aliases-2026-10-10)
passes 74 focused checks. Fourteen forwarding/equivalence kernels and the old
source-subtree comparison kernel are removed; one normalization kernel replaces
the alias algorithm. Eight subtree scratch buffers are removed. Alias-qualified
members are handled by the follow-up above; imported generic alias substitution
remains open. No ABI/private format change.

## Retained field metadata (2026-10-10)

The [field follow-up](compiler-generic-types.md#retained-record-fields-2026-10-10)
extends the page-lifetime contract to member lookup and native field offsets.
Field names, ordinals, and checked references belong to the retained application.
Consumers do not resolve them again through a mutable dependency page. Known
declaration metadata and individual checked fields remain available before all
layout inputs are complete; the header records layout completion separately.
Unresolved fields defer to closure, while name/type validation stays authoritative.

All 33 selected checks pass. Nine executable comparisons cover ordinary, local
generic, and imported generic extraction across three page layouts, with owned
copy/write checks and six invalid-field/type rejections. Native layout uses the
same retained field references. One bounded field-name buffer is added; no
kernel, private format, or ABI changes.

## Dependency page lifetimes (2026-10-10)

The [dependency-page checkpoint](compiler-generic-types.md#dependency-pages-and-retained-value-layouts-2026-10-10)
passes 85 focused tests, with the three page tests also passing without compute
batching. The contracts are:

1. Canonical declaration and type rows belong to the resident dependency page.
   Stable library/unit/declaration identities and checked caller references
   survive page replacement. Both type and value paths retain stable identities;
   later projection cannot downgrade checked annotations to page-local seeds.
2. Qualified lookup binds the parent type before the member. Local declarations
   shadow imports; source-pack and external imports have the same priority.
   Ambiguity is retained across page order, independent of member availability.
3. Submission flushes deferred dispatches before page storage is reused. Readers
   of callable parameter patterns run on the owning page. Shared row initialization
   and scans stay outside that replay, preserving other pages' results.
4. The page producer substitutes all record fields and enum payloads into checked
   references and publishes persistent group boundaries. Final native layout
   calculation consumes those groups without consulting a dependency page.
   Job initialization owns clearing this storage; index rebuilding does not.

Every layout buffer has an initializer even for modules without applications.
Record field readers bind only the shared payload columns. Complete zero-sized
layouts differ from unresolved layouts; bounded storage rejects exhaustion.
Storage width remains a derived fact and cannot stand in for checked type equality.
No kernel, private interface version, native object format, or slice ABI changes.
Remaining compositions and ordinary-language dependencies are listed in the
linked checkpoint.

## Qualified declarations and source parameter rows (2026-10-10)

The [qualified-variant checkpoint](compiler-generic-types.md#qualified-enum-variants-and-method-parameter-rows-2026-10-10)
passes 107 execution/rejection checks and both compiler contract checks. Declaration
lookup retains all candidates and compares exact parent scope. The resolver owns
whether a path segment denotes an enum; one durable qualifier column carries that
fact to normal nominal projection and callable binding. Constructors and patterns
retain the resolved parent identity. An explicit parent and explicit leaf header
cannot both bind the same constructor.

Source operand identity survives body specialization. The nominal collector can
publish a concrete constant edge without overwriting the source operand's cached
lexical parameter. Final explicit validation therefore compares the original
binding with accepted evidence. Inference reports progress only after checking
that a published type graph is complete.

Parameter existence is independent of a written annotation. Implicit `self`
retains ordinal zero and the callable's parameter range, while the receiver
producer owns its checked type. Dropping that row previously skipped value
argument validation. Scalar, compound, generic, and explicit argument checks now
consume the same complete relation for local methods. Imported controls pass too.

No new kernel is introduced. The private interface, object format, and slice ABI
are unchanged. Alias qualifiers remain open; the page follow-up above covers
cross-page qualifier shadowing.

## Unit values and imported nominal annotations (2026-10-10)

The [unit-value checkpoint](compiler-generic-types.md#imported-and-local-unit-values-2026-10-10)
passes 80 execution/rejection tests, six parser checks, and both compiler
contract checks. Local and imported unit values share one publication owner.
Generic units use the complete receiving context and exact nominal identity;
nongeneric imported units use the existing canonical application materializer
and field expansion. Constant consumption no longer publishes enum value types.
An immutable pattern-use classifier keeps value construction separate from
match binding. Match validation consumes complete scrutinee types rather than
recovering identity from a page-local canonical reference.

Imported type projection owns the zero-operand application for a bare nominal
annotation. Call-result validation continues to require complete type equality;
it needs no alternate comparison for an old annotation representation. Import-only
jobs dispatch the existing unit consumer. There are no new kernels or buffers.
The shared slice-width constant also governs the imported enum layout helper.

The parser owns generic-angle disambiguation. A raw angle pair plus a call/path
tail is insufficient when the pair crosses a statement or enclosing delimiter.
One search over the three existing delimiter hierarchies checks container
identity, including sibling groups with equal depths. Published bracket roles
distinguish array types from array values. These checks use immutable relations;
no lane depends on a sibling lane's new classification.

## Nominal and call environments (2026-10-09)

The latest [record-field inference checkpoint](compiler-generic-types.md#inference-from-record-fields-2026-10-09)
passes 79 distinct execution/rejection tests and both resource/lowering contract
checks. A record literal owns named-field lookup and constraint merging. The
existing scoped/canonical matchers bind complete types and constants into the
same ordered environment used by calls. The shared application materializer
instantiates the full nominal template, preserving required unused parameters.
Records retain their own native construction semantics.

The relevant inference order is parameter contexts, closed-type indexing,
record constraints, shared application materialization, field expansion and
indexing, then field/semantic projection. One extra invocation of the existing
indexer publishes parameter applications before record lookup. Declaration
field patterns provide receiving types only after their parent application is
bound. This prevents symbolic placeholders or default integer types from
overriding an actual nested receiving context. Unknown, duplicate, and missing
fields, incompatible types, and incomplete bindings reject before codegen.
No new kernel or binding buffer is introduced by this follow-up.

The preceding [constructor-signature checkpoint](compiler-generic-types.md#constructor-signatures-and-unit-values-2026-10-09)
passes 70 distinct execution/rejection tests, eight interface-export checks,
five parser checks, and six resource/lowering/serialization checks. Constructors
have callable identities, parent-owned generic headers, full payload parameter
patterns, and complete symbolic nominal results. They use the ordinary call
binder and materializer locally and through imports. The old independent enum
payload validator and imported bare-result inference are removed. Construction
still has its own native call kind; no synthetic function body is introduced.

Bare unit values use the shared receiving-context resolver. Named-value readers
consume declaration or checked use-site references consistently across calls,
arrays, matches, and semantic artifacts. Match patterns retain their distinct
binding owner. Nominal declaration templates preserve every ordered operand,
including unused parameters; missing evidence cannot silently erase one.

The preceding [nominal identity checkpoint](compiler-generic-types.md#nominal-declaration-identity-2026-10-09)
passes seven focused execution/rejection tests, 58 affected runtime controls,
all eight interface-export checks, and both compiler contract checks. Every bare
record or enum declaration owns a zero-argument nominal node in the checked
graph. Type uses, constructors, layout, and specialization preserve that node's
declaration identity. Equal legacy cache codes at different source positions
cannot merge nominal types. Unit-variant arguments consume their published
complete reference. Existing passes and buffers own all of these facts.

The preceding [local-enum checkpoint](compiler-generic-types.md#local-enum-and-nominal-contracts-2026-10-09)
passes six focused execution/rejection tests, 38 affected runtime controls,
twelve parser checks, and both compiler contract checks. Local enum calls obtain
their complete result from the shared receiving-context resolver during the
inference fixed point. Payload validation consumes the accepted call result
after the producer dispatch; it does not recompute context while argument lanes
write expected types. Bare enum results publish a complete checked nominal leaf.

Bare and applied records/enums use the same bounded native layout walker.
Declaration identity selects the nominal kind; scalar cache ranges do not select
it. Member/index/copy consumers and the retained-type reader consume those
checked identities and widths. The host copies GPU facts without inferring a
second layout. Match-array value roles come from immutable brace ownership.

The preceding [composition checkpoint](compiler-generic-types.md#composition-contracts-2026-10-09)
passes five new execution/rejection tests, 35 affected controls, eleven parser
checks, and both compiler contract checks. Structural type delimiters own the
type/value role of nested qualified applications. Imported constructor payloads
use scoped type equality even when a payload is a caller parameter. Calls with
a type-graph return supply their complete accepted reference to argument
inference; native pointer cache codes cannot stand in for typed references.
The recursive borrowed-method example now executes without an intermediate local.

The preceding [assignment-context checkpoint](compiler-generic-types.md#assignment-result-contexts-2026-10-09)
passes three focused execution/rejection tests, 29 affected controls, and both
resource/semantic-lowering contract checks. Assignment destinations now feed
the shared receiving-context relation. The call lane owns imported result
validation; the duplicate statement validator has been removed. The complete
gate below describes the preceding ABI checkpoint.

The ABI checkpoint passes all 246 execution/rejection checks, 25 contract checks,
and eight GPU interface-export checks. Its
[body-closure follow-up](compiler-generic-types.md#slice-body-closure-follow-up-2026-10-09)
passes three new checks and 32 affected regressions; the full matrix was not
rerun. The two original array-borrow tests pass unchanged under the authorized
three-word slice ABI. Explicit dotted methods use the shared ordered call
environment. Native object format version 3 rejects older objects.

Receiving-field lookup and call inference have different owners:

| Operation | Binding owner |
| --- | --- |
| Resolve the expected type of a record field | Its nominal instance, through `ScopedCheckedTypeGraph` |
| Look up a record literal's named fields and merge their evidence | The literal, using shared scoped/canonical type-and-constant matchers |
| Materialize an inferred record application | The shared application materializer and accepted ordered environment |
| Publish parameter applications before record lookup | The existing closed-type indexer, after parameter-context production |
| Infer local/imported return-pattern parameters | The called declaration, independently of provisional argument bindings |
| Materialize an accepted call result | Its checked call environment |
| Own an enum constructor's header and parameter patterns | Its parent enum and typed payload declarations |
| Bind constructor arguments and result constraints | The shared generic callable binder |
| Materialize a constructor result | Its accepted complete call environment |
| Supply a bare generic unit value's type | The shared receiving-context resolver |
| Read a named value's complete type | The shared declaration/use-site reference reader |
| Supply an assignment's expected type | Its complete destination place, including field and index projections |
| Expand result fields and enum payloads | Each resulting nominal instance |
| Lay out bare or applied nominal values | The checked declaration and bounded concrete layout walker |
| Identify a bare nominal | Its declaration-owned zero-argument checked node |
| Retain a bare nominal through generic specialization | Its complete checked identity and native width |

Once substitution returns a caller-side reference, it must not apply the original
environment again. Complete type identity includes scoped parameters, every
ordered type/constant operand, and nominal declaration identity. Storage width
does not determine identity.

A fully substituted caller-side application is validated as a complete graph
and retained directly. It does not need another structural lookup or duplicate
allocation before index publication. Field traversal recognizes an identical
instance immediately and still compares complete structure for distinct instances.

Nominal metadata now publishes the type count and constant positions from one
immutable source-operand owner. Semantic-interface version 9 preserves ordered
domains and complete generic nominal declaration signatures; older interfaces
require rebuilding. The previous checkpoints below remain historical evidence.
Native object format remains 3. Verified IR, extractor, and proofs are unchanged
by this follow-up.

## Consolidation checkpoint (2026-10-04)

Explicit callable integer constants now use the same declaration-owned checked
application environment as types. The parser preserves each ordered operand;
local/imported declarations select its kind and lexical slot. Immutable tagged
operand facts retain integer literals or scoped caller constant references. The
binder keeps 32 type slots and 32 constant slots independent, including interleaved
64-operand headers and separate impl/method domains. Final validation compares
explicit evidence with argument/result constraints before retaining specialization
bindings. Invalid headers reject with `LNC0027`; conflicting lengths reject with
`LNC0006`.

Operand roles remain distinct from type identity. Constant-name operands cannot
become fake checked types or unknown exported types; actual annotations using a
constant name still reject. Export classifies the declaration-reachable type
forest. Scoped lookup uses the producer's logical token capacity, read through the
existing uniform allocation, rather than a reused buffer's physical extent.

Accepted constant operands also publish consumed semantic value dependencies.
This keeps scalar-only constant forwarding dependent on its enclosing generic
body even when its signature contains no array. Explicit operands and ordinary
constant references share late value projection during concrete replay; local,
imported, and reused-workspace runtime controls pass.

The current executable matrix has 229 passes and the same two inline-array borrow
failures across 231 tests, covered once by four commands totaling 126.68 seconds.
Eight parser checks, eight interface export tests, and both layout/resource checks
pass. Two HIR-indexed columns add `8 * hir_rows` bytes; no kernel, dispatch, or
uniform allocation is added at this checkpoint. The grammar appends two productions
without renumbering the previous 290. Private argument records remain twenty bytes;
interface version 7 and twelve-word members, verified IR, extractor/proofs, native
codegen/scheduler, and native ABI are unchanged. The shader guard counts 744
artifacts. No performance benchmark was run.

The broader goal remains unfinished. Tested noninteger constant annotations
reject, but constant annotation types are not yet persisted in the interface.
General constant expressions, additional scoped/type-dependent forms, durable
object-only generic bodies, and the pending array-view ABI contract remain open.
See [current evidence](compiler-generic-types.md).

### Preceding explicit type binding

Explicit callable types now have a checked binding producer. The parser owns
each segment's ordered argument list, and the declaration owns its source-order
header and lexical slots. A canonical applying name token connects the two;
legacy call aliases retain that owner. Local binding consumes only the function
or method's own header. Imported binding retains the same mapping while the
exporting dependency page is resident. Receiver/impl parameters stay separate.

The explicit environment reads complete checked references in the caller's scope
from immutable source facts. Inference consumes these references alongside
ordinary argument, receiver, and expected-result evidence. It may provide literal
context but cannot rewrite a known value or explicit application. Final checks
compare complete references and retain accepted bindings for native specialization,
including unused parameters. Arity and kind errors reject with `LNC0027`; conflicting
types reject with `LNC0006` before executable publication.

Method receiver collection consumes complete checked instance argument rows;
the competing whole-path token reconstruction is removed. Imported qualified
receivers preserve resolved nominal identity before structural matching, then
retain the accepted complete receiver for return and required-slot validation.
Method metadata uses the applying segment while existing argument claims retain
their established call identity.

The executable matrix reports 219 passes and the same two inline-array borrow
failures across 221 tests, split into ten new explicit binding tests (11.25 seconds)
and 211 existing controls (99.44 seconds). Seven parser checks, eight GPU interface
export tests, and both layout/resource checks pass. Local/imported functions and
associated methods execute with the listed complete type forms and up to 32 used
explicit slots. Dotted explicit method syntax remains unverified; explicit constant
grammar/bindings and the pending array-view ABI decision remain open.

One binding kernel reuses the existing indirect dispatch packet. Four private
columns add three words per token row and one word per HIR row; reader aliases
reuse existing owned buffers. The enforced shader guard counts 744 artifacts.
No throughput or allocation benchmark was run. Verified IR, extractor/proofs,
semantic-interface version 7, and native ABI are unchanged. Architecture
consolidation and the overall goal remain unfinished. See
[current evidence](compiler-generic-types.md).

### Preceding segmented applications

The parser now owns each applying segment's argument list. Its private twenty-byte
argument row carries the name token; a weighted scan and ordinal scatter publish
contiguous ranges even when nested arguments interleave in semantic HIR. Receiver
and method headers stay independent. Named type/constructor/receiver collectors
consume the appropriate segment. Nominal ranges and constructor debug projections
retain their supported contracts. Structural angle ownership classifies explicit
call parentheses while ordinary comparisons and shifts retain their roles.

Explicit callable binding was unfinished at this preceding checkpoint. A final
semantic boundary rejected headers with source-labeled `LNC0027`, including
imported calls and arguments on nongeneric functions. Registration and runtime
recording both owned that boundary.
Its twelve-byte dispatch packet is produced from actual parser argument counts;
lexical declaration features cannot justify skipping the check. Empty families
publish zero workgroups. The declaration's ordered kinds/slots must next feed the
same accepted environment as inferred argument, receiver, and result evidence.

The native gate has 210 passes and the same two inline-array borrowing failures
out of 212 tests (102.92 seconds). Seven focused parser checks, eight GPU interface
export tests, and record-layout/resource checks pass. One validation kernel is
added; the enforced shader guard now counts 743 artifacts. No throughput benchmark
was run. Verified IR, extractor/proofs, semantic-interface version 7, and native
ABI are unchanged. Architecture consolidation and the overall goal remain
unfinished. See [current evidence](compiler-generic-types.md).

### Preceding declaration order

Generic declaration order now has an explicit portable owner. Semantic-interface
version 7 retains an ordinal across type and constant parameters in each free,
nominal, impl, or method header. This ordinal is independent of separate binding
slots and member ordering. Export consumes the parser-owned source-order range;
serialization and dependency rebasing preserve it. Validation rejects gaps,
duplicates, and order on ordinary members. Previous version 6 artifacts reject
before record interpretation.

All member readers/writers and capacity calculations use shared twelve-word
layout constants. There is no new kernel or dispatch, and verified IR and native
ABI remain unchanged. Ten interface transport/validation tests, eight GPU export
tests, and the resource/lifetime check pass. The current native gate has 209 passes
and the same two inline-array borrowing failures out of 211 tests (109.03 seconds).
This change has not been benchmarked.

Declaration order completed one prerequisite at that checkpoint. Segment-owned
explicit lists and checked bindings were still missing, and the retained explicit
function probes rejected with `LNC0016`. The current checkpoint above supersedes
those restrictions. Architecture consolidation remains unfinished.

### Preceding declared callable requirements

Declared callable requirements have a shared count view and final validator.
Local counts remain declaration-owned; imported calls retain independent type and
constant counts from checked interface metadata before a dependency page is
replaced. Counts include unused parameters and compose impl/method domains.
Complete argument, receiver, and result environments supply bindings; signature
uses cannot redefine which slots are required. Imported native compilation now
reports missing bindings with source-labeled `LNC0006` during checking.

That gate reports 209 passes and two retained inline-array borrowing
failures out of 211 tests. The new rejection matrix reaches slot 31 independently
in both domains; valid compound/constant method programs and all existing
composition programs still execute. Resource/lifetime validation passes. Counting
uses the existing member scan and call projection, with two private workspace
columns and no new dispatch. Verified IR, interface format, and native ABI are
unchanged. That requirement change has no timing measurements.

Explicit function type/constant applications remain a parser/argument-ownership
dependency. Each path segment must retain its own ordered argument list, and the
declaration must determine parameter kinds before the accepted call environment
is published. Receiver arguments and method arguments need distinct owners.
The retained minimal probes reject with `LNC0016`; this contract is unfinished.

### Preceding method result ownership

Method lookup owns candidate identity and declaration signatures. The shared
call materializer owns accepted receiver environments and complete result
substitution. Local and imported shallow return projectors are removed, along
with the unused argument-hash allocation and dispatch. Seven structural receiver
tests execute, including local/imported 32-parameter records with reversed lexical
slots, nested receiver arguments, full-record returns, independent copies, and
reference/slice aliases. The preceding full gate reports 208 passes and the two
retained inline-array borrowing failures out of 210 tests; resource/lifetime
validation passes. No verified IR schema or native ABI changed.

The latest measured checkpoint is 47.642 ms for the canonical 1 MB compiler preset.
Two runs of the existing 32-parameter generic driver measure 326.879 and
289.685 ms on the same frozen build. The unpaired comparisons do not establish
performance preservation. The profile observes two-round inference convergence;
performance attribution and wider scaling remain unfinished. See
[performance evidence](stdlib-gpu-performance.md).

### Preceding structural receiver consolidation

Method lookup now separates candidate indexing from complete receiver matching.
Nominal owner, arity, and name select a bucket; shared checked constraints decide
applicability, including nested type arguments and array lengths. Equivalent
duplicate patterns match in both directions. Accepted receiver substitutions
publish independent type and constant bindings into the existing call environment
before return materialization and concrete replay. Local matching imports pure
graph functions; dependency-page buffers remain with imported interface readers.

Impl header context consumes completed raw bracket depths. A type-array
semicolon cannot terminate the header, and its length identifier retains a value
role. Qualified applications inside generic arguments retain type roles even
inside a value constructor path, before contextual angle-closer splitting.
Five receiver execution/rejection tests, three focused parser checks, 23 semantic
parser controls, and both resource/lifetime checks pass. The preceding execution gate
was 206 passes and the same two inline-array borrowing failures out of 208 tests.
The current measurements above include these receiver changes.

Nested calls now consume the same complete receiving contexts through argument,
field, array-element, and match-result ownership. Field expectations carry their
receiver scope separately from the declaration owner. Scoped lookup is a pure
graph adapter; checked metadata buffers have one owner. Final imported-pattern
validation consumes complete expression references after inference and preserves
stable library/unit/declaration identity.

Actual return materialization preserves argument evidence and fills missing
bindings from result context. Expected parameter projection can prefer a declared
result constraint, but cannot rewrite an accepted actual result. Otherwise a
forwarded invalid call can feed its own changed result into its caller and never
converge. Provisional result-context mismatches publish nothing; a final invocation
checks them after inference closes. The resource graph records that invocation
and keeps its inputs live through closure.

Native scheduling now uses each producer's completion boundary. Inner expressions
finish before consumers at shared boundaries, with expression-depth ordering for
equal spans. Structured match and short-circuit recipes, assignment effects,
conditions, and range bounds use the same rule. This fixes the nested-match SSA
failure, which also reproduced without generics, and preserves observable sibling
argument order and skipped effects.

Native frame metadata has a pure shared owner in `codegen/lir/x86/frame_layout.slang`.
Byte counting, emission, and relocation placement consume the same implicit
epilogue width, including saved-register restores. The former fixed-width estimate
corrupted the final imported call in a void helper. Both that reduced program and
the original mixed record/string-array program now pass unchanged output assertions.
The resource graph keeps finalized frame metadata live through relocation.

Raw delimiter depth and its minimum hierarchy have one producer before semantic
brace ownership. The brace-owner pass can recover a lost nested header from the
matching condition parentheses. Semantic bracket roles have a separate producer
that consumes completed statement context. Static graph registration and dynamic
recording use the same order. Ordinary prefix owners remain a fast path. This
closes the nested `if`/`while`/match-scrutinee brace ownership gap without adding
buffers, IR schemas, or an ABI change.

Record literals now consume this same receiving-context relation during call
inference. Constructor identity is checked before publishing missing bindings;
field context retains its receiver scope. Expected argument materialization
expands declaration fields and enum payloads under that receiver, then publishes
completed applications to the shared index. This closes both the three fresh
record-literal failures and the missing implied imported field application.
Integer field literals receive their complete expectation while known values
remain actual evidence. Record context, fields, and semantic references publish
in separate dispatches inside convergence, using existing buffers.

Explicit record applications now use the shared named-application owner and
argument-reference collection. Grammar-owned links preserve the complete ordered
value-path argument list, including 32 parameters. Raw angle matching supplies
structural evidence for constructor braces and array type arguments through a
shared value-path helper. An explicit source application's arguments remain
actual evidence even inside a generic body; receiving context only supplies
missing bare-constructor bindings. Replacing explicit applications with expected
instances could silently accept conflicting types or oscillate during inference.
Both defects now have focused executable/rejection coverage.

The preceding execution gate reported 201 passes and two explicit inline-array
borrow failures out of 203 tests. Four explicit-constructor tests, two new parser
tests, all 22 existing semantic token/ownership checks, and both parser and
type-checker resource/lifetime checks pass. The preceding receiving-context and
native controls remain in the gate, including 32 mixed fields, imported nested
identities, aliases, and rejected conflicts. These results establish the tested
compositions; further reference/trait, storage,
parser, and persistence capabilities remain unfinished. Current executable
counts and performance evidence are in
[Executable compiler generics](compiler-generic-types.md).

The GPU compiler now has shared owners for checked type identity, lexical
environments, concrete layout and storage capabilities, and specialization.
Local and imported inherent generic methods use these contracts. The former
imported `Boxed<T>::keep<U>` failure now executes, including compound arguments,
constant lengths, borrowed receivers, and qualified static methods.
Constructor payloads also consume shared complete expression references. Nonempty
array/record literals and the tested finite compositions execute locally and
through imports, including construction inside a generic body.
Expected argument references also contextualize empty/nested empty and unsigned
arrays. Imported match bindings and native enum layout consume complete payload
patterns; declaration expansion includes unused variants.
Scalar integer literals now consume the same context through generic calls,
constructors, and match arms. Declaration result constraints are independent of
provisional actual types; strict generic conflicts are checked after closure.
Unannotated argument inference also gives known values precedence over eligible
integer-literal defaults. Literal provenance stays with the argument-context
producer; the shared environment selector supplies deterministic binding order.
Constant lengths now follow the complete structural pattern at every array
level. Literal and scoped symbolic bindings survive local/imported forwarding,
retention, and concrete replay. The executable matrix includes all 32 constant
slots independently of type slots, and a 33rd slot rejects at its declaration.
Constant parameters also execute as values using their declared types. Exact
lexical identity, tagged bound/symbolic semantic facts, required binding checks,
and function template classification share the same ownership and replay
contracts. Empty array argument shapes supply context independently of element
types, while complete declaration matching still owns accepted bindings.
Annotated bindings and declared returns now publish independent type and tagged
constant result environments, including zero and all 32 constant slots. Local
and imported functions, receiver methods, and associated functions share that
matching contract. Imported method results use the existing callable-return
accessor, which distinguishes direct method patterns from function signatures.
Final result checks consume accepted call-result facts; retention preserves both
domains before workspace reuse without doing host-side inference.

This checkpoint establishes the architecture for the currently supported
capabilities. It does not establish generics over every finite type composition.
Borrowing a multi-element inline i32 array now uses an explicit signed stride;
the user authorized the required ABI changes. Reference escape, additional
constraint contexts, and the dependencies below still need work.

Execution evidence is x86_64 Linux ELF emitted by the GPU compiler and run on the
host. User-program GPU execution and other targets are not established here.
Counts, retained logs, and remaining language/runtime dependencies are in
[Executable compiler generics](compiler-generic-types.md).

## Contract owners

| Responsibility | Shared owner | Consumers and boundary checks |
| --- | --- | --- |
| Raw delimiter structure and semantic roles | `parser/tokens/delimiter_match/01_depth_blocks.slang`, `parser/tokens/delimiter_match/02_build_min_tree.slang`, `parser/tokens/delimiters/04_owner_apply.slang`, `parser/tokens/value_path_type_arguments.slang`, `parser/tokens/bracket/01_kinds.slang` | Matching depths and hierarchy publish before brace ownership; lost condition owners use matching parentheses. Constructor braces and value-path array arguments share complete raw angle evidence. Bracket roles consume statement context in a later dispatch. |
| Ordered source applications | `parser/hir/type/arg/links.slang`, `parser/hir/canonical/type_args/{mark,scatter}.slang`, `type/instances/named_application_owner.slang`, `type/instances/01b_collect_named_instances.slang`, `type/instances/01e_collect_named_arg_refs.slang`, `checked_record_constructor_reference.slang` | List identity and applying name token survive ranking. Weighted scan and ordinal scatter allocate independent contiguous ranges. Constructors/types apply the final segment; associated paths apply the receiver segment. Explicit record actuals survive context and strict validation. |
| Explicit callable binding and admission | `calls/03a0_bind_explicit_applications.slang`, `calls/explicit_dependency_binding.slang`, `calls/explicit_call_environment.slang`, `calls/03a8_validate_explicit_applications.slang`, `semantic/features/01_dispatch_args.slang`, `CallBindGroups`, resident recording | Source order maps only the callable's own header to lexical slots; receiver domains remain separate. Immutable caller-side checked references feed inference and final validation. Arity, unsupported kinds, and conflicting types reject before publication. Dispatch reads actual parser counts, and final retention supplies native specialization. |
| Method receiver applicability | `methods/lookup.slang`, `methods/receiver_graph.slang`, `match/ct_match.slang`, `dependencies/canonical_field_types.slang`, `calls/03e_materialize_return_types.slang` | Indexes select nominal/name candidates. Complete local or canonical patterns decide matches and preserve repeated type/constant leaves. Accepted bindings feed the ordinary call environment; duplicate and ambiguous methods reject explicitly. |
| Checked type identity and structural constraints | `checked_type_graph.slang`, `checked_scoped_types.slang`, `scoped_reference_lookup.slang`, `scoped_type_equality.slang`, `scoped_type_hash.slang`, `calls/argument_pattern_ids.slang`, `match/ct_match.slang`, `dependencies/canonical_field_types.slang` | Argument collection, claim emission, result constraints, and interface decoding consume complete checked references. Canonical-to-checked lookup uses hashes only to select candidates and complete equality to decide. Scalar caches cannot decide generic equality. |
| Expected expression context | `argument_context.slang`, `declared_expression_context.slang`, `calls/03k_project_argument_contexts.slang`, `calls/array_shape_context.slang`, `calls/03k1_project_literal_contexts.slang`, `calls/03k3_project_record_contexts.slang`, `array_literal_expected.slang` | Expressions consume retained complete parameter patterns and declaration/return/field context. Eligible scalar/array integer literals, bare records, and match arms receive context in both inference facts and final semantic types; known values and explicit applications retain their actual types. |
| Lexical parameter identity and substitution | `type/instances/lexical_parameter_lookup.slang`, `match/ct_match.slang`, `calls/checked_constant_environment.slang`, `type_checker/generic_calls.rs`, `compiler/semantic_interface.rs` | Declaration uses, structural length constraints, export/import, required binding checks, retention, and replay preserve exact parameter ownership and separate type/constant domains. |
| Accepted result environments | `calls/contextual_call_environment.slang`, `calls/03a4b_contextual_result_requests.slang`, `dependencies/08a_validate_call_results.slang` | Declaration result matching publishes independent type/constant masks and references. Expected-context readers prefer these facts; argument-only readers preserve actual argument evidence. Final validation compares accepted call results and checks every argument against the closed environment. |
| Constant value facts and body closure | `visible/04_hir_names.slang`, `type/instances/01f_decl_refs.slang`, `semantic/artifact/00b_local_const_references.slang`, `codegen/lir/semantic/function_templates.slang` | Value lookup preserves lexical declaration identity and declared types. Bound values execute; symbolic constant uses keep bodies pending until concrete replay. Mutation and noninteger array lengths reject explicitly. |
| Concrete value layout and native storage capabilities | `concrete_value_layout.slang`, `codegen/lir/semantic/concrete_struct_layout.slang`, `codegen/lir/x86/storage_layout.slang` | Field ranges, copies, address generation, byte counting, and emission consume concrete widths and explicit storage conventions. Incompatible borrowing rejects before ELF publication. |
| Expression completion and effect order | `codegen/lir/semantic/materialize.slang`, parser-owned compact expression forest and match-arm records | Producers finish before consuming calls and effects. Structured control recipes share completion boundaries; sibling effects follow source order. SSA validation remains enabled. |
| Finalized native frame layout | `codegen/lir/x86/frame_layout.slang`, `codegen/lir/x86/location_common.slang` | Byte counting, emission, and relocation placement share frame and result-move widths. The resource graph retains function metadata and saved-register masks through relocation publication. |
| Concrete body identity, scheduling, and reuse | `type_checker/generic_body.rs`, `compiler/gpu_compiler/body_specialization.rs`, `compiler/gpu_compiler/typecheck.rs` | Scheduling uses canonical semantic arguments, checks layout agreement separately, requires declared bindings, and bounds replay/native output. |

Shader paths in the table are relative to `shaders/type_checker/`, except paths
beginning with `parser/` or `codegen/`, which are relative to `shaders/`. Rust paths
are relative to `crates/laniusc-compiler/src/`.

## 1. Checked types own semantic identity

A checked reference describes a scalar, a declaration-scoped parameter, or a
complete structural application. Applications retain nominal identity, every
ordered argument, array lengths, and element/referent types. Source and generated
applications have the same meaning. Imported types preserve stable
library/unit/declaration identity.

Native widths, source positions, and fixed-size caches are representations or
indexes. They cannot establish type equality, invent a binding, or override an
accepted checked reference. Unknown is distinct from unit, zero-sized layout,
and rejected input. Integer-width aliases in the current checked scalar model
remain a language/compiler limitation; this checkpoint does not claim native
full-width integer support.

Argument collection owns argument-to-parameter relations and parameter-use masks.
Collection and claim emission share argument-value projection and structural
pattern matching. Only emission publishes generic claims; conflict validation
compares their complete checked references. The competing shallow nominal/array
claim emitters have been removed. Receiver, argument, and expected-result
constraints feed the same accepted environment.

The same complete pattern walk publishes independent type and constant-use
masks. One argument lane owns both compact claim spans; an argument's constants
are not limited to its outer array dimension. Constant claims have their own
count and index. The former four-slot constant cache is removed. Both claim
counts reset unconditionally at job entry so omitted optional passes cannot
expose a preceding compilation's environment. Array return checking also uses
complete structural equality, including nested symbolic lengths.

Expected parameter projection gives declared result constraints precedence over
provisional argument defaults. Actual-value projection retains argument facts.
Result constraints read immutable local/imported declaration patterns without
substituting provisional type or constant claims into those patterns. Strict claim comparison
and required binding validation run after closure. Expected context can select an
eligible integer literal's type; it cannot change the type of a named value or
relabel floating/Boolean bits. Generic constructor payloads require checked type
identity even when their accepted instance uses a primitive scalar argument.

`checked_call_environment.slang` owns indexed selection by complete callee/slot
identity and stable tie-breaking. Its priority provider receives provenance from
the owning context producer. Expected argument projection ranks eligible direct
integer literals below known values, then publishes context through the existing
expression relation. Ordinary actual-value readers retain stable claim order.
After literal facts settle, every claim must agree with the accepted context and
the other argument claims. The provider does not add HIR buffers to other graph
consumers or weaken complete type equality.

Array dimensions are parser-owned facts even when a literal's element type is
pending. `calls/03k_project_argument_contexts.slang` walks matching
literal/pattern array levels by canonical ID, substitutes the element pattern
once under the accepted environment, and wraps the result in the actual
dimensions. The resulting relation is optional literal
context. It does not replace the declaration pattern or publish accepted claims.
Complete matching still rejects inconsistent dimensions, element types, and
repeated parameters. An empty outer array cannot infer an unknown inner
dimension or element type. Imported array validation also uses the complete
composed call environment instead of comparing shallow source subtrees.

Result constraints which depend on pending expression facts defer diagnostics
during inference. The final dependency-call validation runs with deferral disabled.
Local enum constructors retain their resolved identity and checked result context
while compound payload facts are pending, then revalidate every payload after
closure. Their primitive scalar conversion rules remain separate from complete
reference equality for generic/nominal payloads, including bare nominal references
in the legacy scalar encoding.
An unresolved payload at closure writes an explicit typed diagnostic. Updating
the name-resolution status alone is insufficient because its consumer has
already executed earlier in the pipeline.

Imported methods reserve argument relations before dependency target resolution,
then project their explicit parameter patterns while the dependency page is
active. They join the common matcher. Call-result substitution reads the
declaration-owned return pattern for functions and methods, so an earlier
inference iteration cannot replace the template with another call's result.

Early argument checks consume accepted inference/declaration/field/index facts.
Only record literals have an early semantic artifact producer. Reading other
final expression rows early could consume facts from a previous workspace job;
that path has been removed. Ordinary scalar conversion and transparent alias
normalization remain separate from structural generic matching.

Expected argument context retains complete caller-side references after scoped
substitution. Imported canonical patterns are read on their active declaration
page. The shared declaration/expression relation covers statement, return, field,
and expected argument ownership. Array literal context may propagate through
multiple array layers; match arms inherit their match expression's context. Literal
scalar types are published in a separate dispatch before expression projection;
both inference and final semantic projection consume that same table. Changing
an array's outer type without changing its element facts is insufficient.

Imported match payloads use stable library/unit/declaration identity to select
the parent, materialize the complete variant parameter pattern under the accepted
scrutinee, and retain the resulting reference by binder HIR row. No canonical
type row survives as a caller-side payload reference. Capacity failures are
explicit; unresolved facts defer until strict final validation.

## 2. Environments own substitution

Parameters retain declaration identity. Dense slots encode bindings; a numerical
slot cannot identify a declaration. A method environment places enclosing impl
parameters before its own parameters, independently in the type and constant
domains. Lexical name lookup checks the nearest scope first. Declaration uses,
constant-length nodes, interface normalization, and replay share that lookup.
Substitution applies once: an accepted argument is already in caller scope.

Constant bindings retain either a literal length, including zero, or the exact
caller parameter token. `match/ct_match.slang` owns their structural
comparison and inference rules for local and imported patterns, on canonical
IDs. Literal values
and parameter identities never share an untagged value field. Type and constant
slots have independent 32-parameter limits, enforced when declarations publish
their slots, including unused parameters. Invalid scope and resource exhaustion
remain distinct failures.

Expected-result constants have their own per-call mask and tagged payload
columns in `contextual_call_environment.slang`. Job entry clears the validity
mask; unpublished payload cells are never read. The shared declaration matcher
publishes both type and constant domains only after the complete match succeeds.
Expected-context substitution can read the result environment before the indexed
argument environment. Argument evidence uses its own reader, preserving conflicts
for validation after closure. Final imported result comparison uses the accepted
call-result relation, and pending instances defer while inference is active.

Missing bindings may defer during inference; conflicting bindings reject.
Retention preserves both domains before workspace reuse. Final specialization
requires the complete declared slot sequence, including unused parameters, before
reusing an existing native body. Missing imported unused parameters currently
reject at the specialization gate with `LNC0017`; tested conflicting bindings
reject during checking with `LNC0006`.

Symbolic retained constants are valid bindings while a generic body is pending;
they are incomplete executable arguments. Concrete replay publishes selected
owner values in `type_const_param_value_by_token`. The host copies unique
parameter rows in one bounded readback and retains unresolved rows as parameters.
It does not infer constants from source or array layouts. Scheduling and native
specialization require literals for every declared constant slot, and semantic
body identity includes those values.
Retention reads type and constant context masks together, copies constant rows
only for calls with published bindings, and combines result and argument facts
before resolving unique symbolic parameters. Duplicate accepted facts must agree.

Ordinary value lookup consults the shared lexical parameter owner only after
local/value parameter resolution. A type parameter cannot become a value.
The parser retains a constant's annotation in a private sidecar without changing
`HirGenericParam`. Declaration projection derives its checked type from that
annotation. Bound constant uses publish a value-presence tag; unbound uses
publish a distinct symbolic tag retaining the exact declaration token. Native
function classification requires both complete type layout and complete value
facts. A body containing a symbolic constant stays a template even if its
parameter/result layouts are already concrete. Plain and compound assignments
reject rather than mutating the immutable binding.

Local required-binding rows contain the declared type slots followed by the
independent constant slots. Methods compose their own and impl-owned counts
without rewriting declaration metadata. Final checking requires each slot in
the accepted indexed environment, including unused declarations. Missing local
constants report `LNC0006` at the call; the imported specialization gate retains
its explicit `LNC0017` boundary until those diagnostics move into checking.

### Portable interface

GPU semantic interface version **6** records exact generic member identity.
Nominal/free parameters use the existing unscoped representation. Impl and method
parameters retain their lexical scope in member metadata, and their composed
binding slot is encoded separately. Generic type nodes and symbolic array lengths
reference the exact parameter member. Associated methods retain combined declared
type and constant counts even when a parameter is absent from the signature.

Validation before GPU upload checks parameter member kinds, ownership, unique
method identities, explicit parameter ordinals, method-owned slot suffixes,
requirement bounds, and signature scope agreement. Dependency batching rebases
member references. Nominal/free arity consumers exclude scoped parameters.
Validation indexes scoped members once instead of scanning every member for each
method. Graph access declarations cover the added scope-owner and parameter maps.
Imported associated function resolution follows the same dependency authority
as imported receiver methods; local method-table validation cannot override a
resolved dependency target. Signature and argument validation remain owned by
the dependency passes.
The existing callable-return accessor owns the interface representation:
function exports contain a complete signature; method exports contain the
direct return pattern. Result inference must consume this accessor rather than
reinterpret every export as a function node. Interface version 6 is unchanged
by the result-only constant work.

Version 5 is rejected explicitly. This private compiler interface change does
not change the verified IR record schema or native ABI.

Executable coverage includes local/imported methods, ordinary and generic owners,
owned and borrowed receivers, reordered impl parameters, compound values and
independent copies, static methods, constant lengths, zero lengths, and missing or
conflicting bindings. Trait method generics and method where clauses remain
explicitly restricted. Symbolic constant forwarding and nested constant
inference and value expressions now have executable coverage. Further
expected-result contexts for nested argument/field/array-element calls, explicit
constant argument syntax, and imported missing-binding diagnostics remain unfinished.

## 3. Layout owns addresses and copies

Concrete value layout computes aggregate widths from checked payload references.
Field ranges consume concrete widths. Descriptors are terminal values; known zero
size is complete. Unbound generic value fields remain unresolved instead of being
guessed to occupy one word.

Imported enum payload lookup shares the canonical-to-checked relation used by
application producers and imported fields. Declaration expansion materializes
every variant's patterns under the enum's accepted arguments, including unused
variants. Native layout then sums each variant's complete payload widths and
takes their maximum plus the tag. Zero-sized arrays are valid payloads and do
not erase following values. This does not change native call placement or ABI.

The native storage contract distinguishes descending eight-byte aggregate words,
ascending packed four-byte i32 places, and direct/indirect descriptors. The user
authorized the slice ABI migration on 2026-10-09. The verified implementation
uses `(data, length, signed byte stride)` for every slice, including fields and
generic arguments/results. `native_value_layout.slang` owns its three-word width;
`storage_layout.slang` constructs fixed-array strides. Index loads, stores, and
compound copies share the x86 instruction plan's index address calculation and
preserve logical bounds checks.

Borrowing preserves the original storage and every alias. A descriptor copy
retains its referent and stride; an owned array copy retains independent storage.
Backing layout does not enter semantic type identity or specialization identity.
Native object version 3 requires rebuilding earlier objects. Strings retain
their two-word representation. The verified IR, extractor, and proofs are unchanged.

The earlier two-word baseline rejected the two inline-array borrow cases. Their
unchanged assertions and the broader descriptor checks now pass. Raw typed view
construction obtains its complete slice type from the receiving-context owner;
specialization closes the element layout before lowering publishes its stride.
See [the acceptance record](array-view-storage-decision.md).
Reference escape and further element-layout support still need separate evidence.

## 4. Specialization owns concrete executable bodies

The scheduling key contains stable body identity, every ordered semantic type
argument, and constant values. `generic_body.rs` validates the bounded replay
packet and canonicalizes its postorder structural graph. Nominal identities,
element/referent types, and array lengths remain in the key. Derived widths and
mutable source-local replay indexes are excluded.

Layouts are retained separately. Duplicate semantic nodes with inconsistent
layouts reject; a cache hit with the same semantic identity and different layouts
also rejects. Native specialization reuses the completed symbol for a complete
environment. Tag-only bodies cannot bypass missing declared bindings.

Body constraints must close before native publication. Missing definitions,
unsupported environments, and exhausted arenas terminate with explicit errors.
Parameter and result types require complete closure even when their native
representation has a fixed width. In particular, a symbolic slice descriptor
cannot authorize an unspecialized body: that body may call another generic
whose environment requires the element type. The former slice exception caused
undefined calls through `core::mem::identity` and has been removed.
Current limits include 32 arguments per domain, 64 retained type nodes, 2,048
nominal edges, 256 resident bodies, and 64 MiB of specialized native text.

Source-pack replay and host progress readback remain compilation costs. Reuse of
checked bodies, substitutions, and layouts can be improved within this owner.
The existing 1 MB benchmark measures ordinary corpus compilation; it does not
establish acceptable scaling for increasingly large generic graphs.

## Extension rule and remaining work

New type forms and payload compositions must extend these contract owners and
their consumers together. Avoid per-payload implementations, guessed widths,
scope inference from slot numbers, and silent fallback bodies. Retain a minimal
reproduction, execute accepted programs, verify required rejections, and review
GPU resource access contracts when pass inputs or outputs change.

Assignment projection reads checked declaration/member references and the stable
call-inference snapshot. It does not infer a destination from the RHS or from
the base identifier's type. In particular, a field's type differs from its
containing record's type. Array literal assignment uses this same projection;
there is no separate array-only assignment-context helper. The imported call
lane publishes and validates the environment once, avoiding a second statement
lane that could publish a conflicting expectation.

The next work is remaining constructor and expression constraint closure;
further constant binding contexts; further
reference/trait capabilities; durable object-only generic context; and generic
workload scaling. The detailed list and supported matrix live in
[Executable compiler generics](compiler-generic-types.md). These are unfinished
capabilities under the shared architecture, and the overall arbitrary-type
generics goal remains unfinished.
