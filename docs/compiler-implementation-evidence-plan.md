# Portable implementation evidence

**Status: native caller evidence and sibling-method emission verified (2026-10-11).**
The latest [sibling-method checkpoint](compiler-generic-types.md#generic-sibling-method-emission-2026-10-11)
passes 29 distinct checks: eleven native integration tests, two library GPU tests,
and sixteen host tests. It verifies selected-body emission, ordinary-helper
retention, and workspace reset. The preceding native caller-evidence checkpoint
passes 20 checks, and the catalog/batch checkpoint passes 24. General generics
remain unfinished; the remaining boundaries are listed below.

The call-graph prerequisite now retains symbolic type/constant leaves with exact
caller binder identity, independently of native layout. Its checkpoint passes
32 selected checks and records one preexisting borrowed-enum failure. It does
not yet retain selected implementation proofs. See
[retained call graphs](compiler-generic-types.md#retained-symbolic-call-graphs-2026-10-10).
The later [borrowed-enum checkpoint](compiler-generic-types.md#borrowed-enum-matching-and-imported-structural-types-2026-10-10)
resolves that failure and passes 19 selected checks; it does not change the
outstanding implementation-selection boundary.

## Owned definition and caller snapshots

The next prerequisite now retains definition-owned predicates, concrete
implementations, full operand graphs, accepted method bindings, and one shared
binder table for public and private owners. Public aliases come from the real
exporter. Private rows belong to the immutable checked unit. Exact enclosing
owner links are distinct from each call's actual enclosing function.

Concrete replay reuses the template contract `Arc` and reads fresh call facts.
It does not rebuild definition contracts from substituted bodies or read stale
exporter scope maps. Predicate-only and zero-call generic units retain contracts;
current-job feature flags prevent previous workspace contents from becoming
facts for an empty job.

All 16 selected snapshot, library, and native checks pass. Evidence is recorded in
`tests/fixtures/stdlib_compiler_state/caller-contract-snapshots/verification.json`.
Batching removes most of the first implementation's synchronization cost; the
trait workload retains a measured 10.2% overhead against its preserved baseline.
See the [checkpoint](compiler-generic-types.md#owned-definition-and-caller-contracts-2026-10-10)
and [performance evidence](stdlib-gpu-performance.md#owned-definition-and-caller-contracts-2026-10-10).
This supplies inputs to the solver; it does not select an implementation or satisfy
a bound.

## Shared graph capability

The parameter-identity hash/equality interface now passes 18 focused library and
native checks, including a direct physical GPU probe. Adapters receive original
owned parameter references, and substitution clears the callee environment over
the complete replacement subtree. Nominal operand capacity is independent of
graph node count. Existing source adapters keep their current environment policy.

The packed program adapter, bounded admission, catalog, selection, and explicit
replay proof validation have the executable checkpoints below. Complete callable retention
now passes 25 focused checks: ordinary callers, executable public/private methods,
and exact method-to-implementation links survive workspace reuse. Trait requirement
owners remain distinct from executable callables. Call pruning preserves the exact
retained owner inventory. See the
[ownership checkpoint](compiler-generic-types.md#complete-callable-ownership-2026-10-10).
See the [graph checkpoint](compiler-generic-types.md#parameter-identity-in-shared-graph-operations-2026-10-10).

## Program catalog admission: executable checkpoint (2026-10-11)

The packed catalog, host packet ownership, and GPU catalog dispatcher now pass
eight executable tests on the physical GPU and six host packet tests. GPU tests
cover nested array lengths, retained-unit deduplication, cross-unit coherence,
public/private method targets, malformed unused rows, ownership relationships,
header rejection, the 64-frame boundary, reachable cycles, and exact lexical
parameter visibility. The host tests exercise storage, provenance, and fresh
receipts with scripted results; they do not establish GPU selection.

All 22 catalog shader artifacts pass external SPIR-V validation. Complete ordered
row admission now establishes structural facts once; later checked graph readers
reuse those facts while preserving contextual scope, cycle, depth, work, domain,
substitution, and closure checks. Bootstrap owner/node validation remains full.
This responsibility split reduced implementation-admission pipeline preparation
from exceeding 90 seconds to 12.044 seconds. Index construction took 15.385 seconds
and coherence took 84.016 seconds. These are cold pipeline preparation measurements,
not program compilation throughput. The coherence preparation cost was high at that snapshot.

Bring-up also exposed a Slang 2026.2 defect: consuming the previous value from
`InterlockedExchange` emits an undefined SPIR-V ID at `-O0`; the minimal example
crashes Slang at `-O1`. Catalog insertion now uses a bounded compare-and-swap
loop. Failure publication uses a single compare-and-swap owned by the diagnostic
writer. The corrected artifacts validate and all selected catalog tests pass.
The reproduction, measured attempts, frozen source hashes, and 14-check result
are retained in `tests/fixtures/stdlib_compiler_state/program-catalog-admission/`;
`verification.json` identifies the completed checkpoint.


## Batch selection and replay: executable checkpoint (2026-10-11)

Seven physical GPU batch tests, nine GPU catalog tests, and eight host scheduling
tests pass against one preserved source snapshot and binary. The complete record
is `tests/fixtures/stdlib_compiler_state/program-batch-selection/verification.json`.
All 41 catalog/batch shader artifacts also pass SPIR-V validation.

The tests select the caller's nested length-three implementation instead of the
provider's length-two implementation, reject missing or wrong inner types, forward
symbolic hypotheses, and retain two distinct replay occurrences. They also reject
changed unused bindings, changed retained witnesses, authentic evidence for a
different goal, and unused malformed roots. Empty submissions require fresh
receipts. The added directory test rejects malformed widths, counts, capacities,
physical bounds, and overlaps, including unused tables, and verifies valid recovery.

The earlier 90-second preparation failures are resolved for these stages. One
shared candidate comparison brought selection preparation under 21 seconds;
checked input projections brought context preparation under 6 seconds. Complete
directory validation remains at initialization, each read independently proves
logical membership and physical safety, and concurrent receipt publication still
uses CAS ownership. These timings describe pipeline preparation at the recorded
snapshots, not a whole-compiler speedup.

The GPU executes selection and explicit replay-context checks in this checkpoint.
Native execution was verified in the later checkpoint below.

## Native caller evidence: executable checkpoint (2026-10-11)

The original caller-supplied implementation reproduction now compiles and executes
with exit zero. Eight native tests cover imported bounds, nested forwarding at
two types and array lengths, repeated calls, bodies already available for reuse,
missing-bound rejection with the correct source label, and existing method,
constant, and alias behavior. One physical GPU retention test checks two source
files, UTF-8 byte offsets, exact call associations, and workspace replacement.
Eleven host tests check occurrence ownership, publication, source paths, storage
moves, and diagnostics. Host receipt tests script GPU results; they do not
independently establish implementation selection.

One session freezes the complete retained program before body reuse or native
symbol filtering. Every original call is checked. A validated replay request owns
the exact template, selected callable, complete environment, and evidence. The
frontend obtains all replay inputs from that request. Its private pending object
is released only after the matching request checks the fresh call inventory.
Ordinary frontend paths remain strict, and each recording resets the replay mode.

Call token byte spans and ordered source paths are retained before GPU workspace
reuse. A missing implementation maps to LNC0008 only when the entire saved span
belongs to the exact saved file; malformed spans never receive a guessed label.
Path-backed cache fallbacks include diagnostic paths in their identity.

Evidence is in `tests/fixtures/stdlib_compiler_state/program-native-replay/`.
The native/performance and library test binaries have separate recorded source
snapshots: the only intervening compiler-source edits added test assertions.
All four changed shader artifacts pass external SPIR-V validation. The existing
performance harness measured +7.8% on the trait workload and +7.4% on the ordinary
32-parameter program; see [measurements](stdlib-gpu-performance.md#native-caller-evidence-2026-10-11).

Remaining boundaries:

- Replaying a method can substitute shared impl parameters in sibling scratch
  data. The later sibling-method checkpoint prevents publishing those bodies
  and restores only their admitted original template facts after checking native
  definitions and complete call ownership. Ordinary helpers keep exact checks.
- Generic implementations with prerequisites, generic trait methods, method
  where clauses, and direct constant trait operands remain unsupported.
- Persisted object-only generic replay and the immediate executable path do not
  consume this retained program session; their frontend checking remains strict.
- These tests execute x86_64 Linux output produced by the physical GPU compiler.
  They do not establish user-program GPU execution or general generic scaling.

## Contract addressed by native forwarding

Previously, a caller could validate its implementation of an imported trait,
then lose that evidence when the generic body was compiled in its own unit.
The retained baseline reproduction rejects with `LNC0008` during body replay;
the native checkpoint above executes it successfully. Exported callable
predicates describe what the body requires. Selected evidence records the
implementation that satisfies those requirements.

The accepted invariant is: a checked obligation retains the exact selected
implementation, its complete type/constant substitutions, its required-method
bindings, and any prerequisite evidence. Those identities survive dependency
page replacement and pass explicitly into body compilation. Hashes only narrow
lookup; full identity and structural comparison decide equality. Source
concatenation is not part of this design.

## Current records

Reuse the existing canonical type graph, including constant operands. Give each
implementation a stable identity `(library_id, unit_id, implementation_index)`.
Assign the local index by deterministic compaction of accepted implementations.
Do not persist an implementation's HIR node or lookup bucket as its identity.

An implementation record contains 14 words:

| Fields | Contract |
| --- | --- |
| `module`, `visibility` | Defining module and language visibility |
| `trait_library`, `trait_unit`, `trait_declaration` | Stable defining trait identity |
| `subject_type` | Complete, nonconstant subject root |
| `first_argument`, `argument_count` | Ordered type/constant operand roots |
| `first_member`, `member_count` | Generic header and implementation callable contracts |
| `first_prerequisite`, `prerequisite_count` | Predicates owned by this implementation |
| `first_method_binding`, `method_binding_count` | Complete validated method bindings |

Each method binding contains six words:

```text
implementation_index
required_method_symbol
implementation_method_member
target_library
target_unit
target_symbol
```

The implementation supplies the required method's trait identity. The method
symbol identifies its exact required contract; the member identifies the
implementation callable's signature and lexical scope. The target triple names
native code or an explicitly supported body template. A private required method
must remain in the binding set when its implementation is externally usable.

Validation must establish complete generic scopes, trait arity and operand
domains, exact ownership of argument/prerequisite/binding ranges, and exactly one
binding for every required method. Receiver mode, arity, substituted parameter
and result types, visibility, and generic requirements must agree. Unresolved
identities and incomplete graphs reject. Trait paths obey name resolution and
visibility; implementation selection uses the program catalog. Existing
source-pack tests select public implementations through qualified trait paths
without importing the implementation's module. Dependency-page membership is a
storage fact, not the definition of the program catalog. See
`formal/SEMANTIC_DECISIONS.md` for the catalog and unique-resolution contract.

## Contract owners and migration

Use a tagged `u32 owner_ref` for member and predicate ownership: a clear high bit
names a declaration; a set high bit names an implementation. Reserve
`0xffffffff` as invalid and reject indices outside the chosen tag domain. Keep
method scope symbols in their separate field and domain. Central helpers must
validate, decode, and rebase each owner kind.

This replaces member and predicate `owner_declaration`; declaration parent
ownership keeps that field and its original meaning.
Implementations can target scalars, arrays, references, or imported declarations,
so their parameters cannot borrow an arbitrary local nominal owner. Generic
leaves and symbolic array lengths continue to refer to exact shared member
records. Source order remains independent of type/constant binding slots.

This is a schema migration, requiring a new version and rebuilt artifacts.
Update host validation, batching, GPU readers/writers, method lookup, and replay
ownership together. Existing consumers index the declaration table directly;
every such use must branch on owner kind. Rebase the owner payload in its own
table and preserve the tag. Associated callable receiver checks must use the
implementation's full subject graph when the owner is an implementation.

## Authoritative producers

Paths below are relative to `shaders/` unless otherwise stated.

| Evidence | Producer |
| --- | --- |
| Accepted implementation header | `type_checker/predicates/01_collect_impls.slang`, `collect_common.slang::validate_trait_impl_node` |
| Subject and ordered operands | Checked references from `compact_hir_semantic_facts[impl].method_impl_receiver_type`, `predicate_trait_impl_trait_type_node`, `predicate_bound_arg_count`, and canonical argument access |
| Trait identity | `trait_reference_identity`; local declarations translated through public declaration compaction |
| Generic header and prerequisites | `compact_generic_param_ranges/params`, canonical binding slots, and `compact_predicates` with exact implementation ownership |
| Method correspondence | `01f_emit_method_validation_rows`, `01f1_emit_method_param_validation_rows`, and `01f2_validate_imported_methods` |
| Final acceptance | Method statuses, `predicate_method_validation_first_error_row`, and successful overall checking |
| Module and visibility | Source-file module map and `trait_impl_header_is_public` |

Imported method validation now retains the required method's portable symbol
while its defining page is active. Local validation translates its checked peer
to the same required-method symbol domain. The retained resource survives through
export, and failed validation clears it. No page-local member row is persisted.

Header status zero alone does not prove an implementation valid. Duplicate-key
validation reports diagnostics without changing `predicate_status`; export must
also require successful final validation and complete method checks.

Native callable identity already has the form `(library, unit, symbol)`.
`codegen/lir/semantic/function_scatter.slang` selects the symbol;
`function_method.slang` supplies public implementation method symbols; x86 object
definitions and relocations preserve the triple. Public implementation methods
use the `0x80000000` symbol namespace, while private callables use the existing
`0x40000000` namespace. Consumers treat these as opaque symbols. The authoritative
producer in `callable_identity.slang` is shared by interface export, native
definitions, and local call selection. Private implementations retain their
private native target separately from the interface method's lexical scope symbol.

## Verified first checkpoint

Concrete, validated public implementations now export complete method bindings
and empty generic/prerequisite ranges. Private required bindings and full
compound subjects/operands are retained; unsupported cases reject explicitly.
Tests verify binary round trips, malformed records, stable identities, rebasing,
dependency-page replacement, and native target agreement with object definitions.
The native program executes copies, aliases, empty values, enum payloads, and
public/private methods. The 79 selected checks and investigation history are in
`tests/fixtures/stdlib_compiler_state/implementation-evidence-export/`.

This checkpoint establishes portable evidence records. It does **not** finish
caller evidence forwarding. A following checkpoint must select an implementation
at the call, retain its substitutions and prerequisite evidence, and install that
evidence during imported body replay. Native tests must then execute the retained
caller-implementation reproduction and reject missing or ambiguous evidence.

## Caller selection and replay: integration in progress

The following contracts describe the intended complete path; the checkpoint
above states which parts have executable evidence. The retained failing case is
`tests/fixtures/stdlib_compiler_state/trait-type-graphs/imported-caller-impl.lani`.
Its provider requires `Rel<Cell<[U;N]>>`; the caller supplies the length-three
implementation, but provider replay currently searches only its original local
implementation index and reports `LNC0008`.

Retain one proof per accepted `(call, predicate)` obligation. A proof contains the
complete instantiated subject and ordered operands, plus either the selected
implementation identity or the exact enclosing callable predicate being
forwarded. Selected implementation evidence carries substitutions, required
method bindings, and prerequisite proofs. Concrete implementations use empty
substitution/prerequisite ranges at the first checkpoint. The host copies
GPU-selected facts from retained immutable artifacts; it does not perform trait
selection or type equality.

The GPU must count and compact local and imported callable obligations after
inference, materialize required graphs while their defining pages are active,
and compare complete graphs against the checked program catalog. A hash chooses
candidates only. Accumulate a stable candidate identity across all pages before
finalizing uniqueness; repeated copies of the same identity are one candidate.
Reject distinct matches regardless of page order. Preserve catalog-wide
selection after trait-name resolution; do not add an import-only implementation
filter. Complete-program overlap rejection remains required when separately
compiled catalog fragments are combined.

Accepted evidence owns its graphs and bindings before scratch reuse. Pass it as
a separate immutable input to `CheckedBodySpecialization`, validate it against
each specialized bound in `03_validate_body_obligations.slang`, and forward the
selected proof through nested generic calls. Include normalized evidence in
specialization identity until complete catalog coherence is established.
Neither caller source concatenation nor replacement of the provider's original
dependency snapshot supplies this contract.

Private local contracts need their own real, retained identity domain. They
cannot borrow nonexistent exported indices. Preserve local/private behavior
through a unit-owned contract table tied to its immutable compilation snapshot;
public definitions normalize through their actual export mapping. Private
nominal types and callable predicates require the same ownership discipline.
The initial public cross-unit path may require exported identities, but must not
invalidate existing private local checks.

The program gate must visit retained calls independently of native undefined
symbols. Check all obligations and catalog coherence before the existing-body
shortcut, including tag-only bodies and symbolic forwarding. Source-unit checks
that cannot yet see the catalog need an explicit pending-obligation state and a
mandatory program-level consumer; absence of a local match must not become
success. Preserve immediate malformed-contract and local-ambiguity failures.

The program's unit map must reject conflicting immutable snapshots with the same
numeric unit identity before building the catalog. An owned implementation and
its real public alias are one candidate; two distinct implementations with equal
keys remain a coherence error. Provider caches remain independent of the caller's
catalog, while retained selection and evidence caches belong to that catalog.

Enable obligation storage for local predicates, imported callable predicates,
or replay evidence. A call such as `keep(false)` may have no local generic syntax.
Count graph nodes, edges, operand roots, and bindings separately; 32 independent
compound operands must not accidentally share one root's 64-node limit. Keep
absent-contract jobs on bounded minimum storage with cleared state.

Acceptance includes the original caller program, nested forwarding, wrong inner
types/lengths/trait units, 32 distinct operands, missing and ambiguous evidence,
duplicate pages, page replacement, compiler reuse, and bound checks even when a
native body is reused. Invocation through generic trait bounds is a separate
language/runtime boundary from retaining required-method contracts.

## Program graph and context contracts

The next implementation uses one GPU graph comparator. Host packing copies
accepted graphs and interns exact fixed identity tuples; it does not compare
recursive types, select implementations, or satisfy obligations. Public and
private identity tags remain distinct, and private keys retain their immutable
snapshot owner. Temporary GPU atoms must decode back to retained identities.

Parameter substitution must receive the original owned parameter reference.
Converting it to a slot before looking up an environment can capture another
binder's slot-zero parameter. Add an identity-aware scoped-graph capability;
existing source adapters may implement it through their validated slot lookup,
while the catalog adapter looks up exact parameter identity. Apply a substitution
once: its replacement already belongs to caller scope.

Nominal nodes, operand edges, roots, and environments have separate capacities.
A nominal application with one node and 32 scalar operands is valid; its arity
must not be limited by node count. Current supported nominal applications have a
32-operand semantic limit. That limit does not constrain callable environments,
which have independent 32-slot type and constant domains. Each graph root has
its own traversal depth bound. Invalid graphs, exhausted traversal budgets, and
unsupported depth must produce failure, never an implementation-not-found result.

Definitions and call occurrences have different lifetimes:

- The frozen catalog owns original definition contracts and implementation
  identities. Concrete body replay never adds a second definition catalog.
- A call context owns its definition snapshot, selected lexical owner, body
  environment, and supplied evidence. Different replays can use the same source
  HIR, so `(unit, call_hir)` alone is not a call-occurrence identity.
- Caller-assumption evidence names the exact offered predicate and its context.
  Supplied concrete evidence applies only to the selected lexical body owner.
- Canonical specialization keys contain normalized goals, substitutions, and
  retained implementation witnesses. Transient context, atom, and batch indices
  must not prevent equivalent or recursive calls from reusing a body.

Retained batch input rows are immutable for the life of a GPU packet. The GPU
binds the input arena read-only. `ensure_retained_inputs_unchanged` in
`program_evidence/dispatch/mod.rs` refuses, before any upload, a submission that
rewrites a retained row, moves a table without copying its rows, or overlaps two
tables. A refused submission poisons the packet, so it is never checked again.
Indexes built from retained rows therefore stay valid without being cleared.
In particular, an assumption row indexed by kernel 15 (output tables 8 and 9)
keeps its admission and hash for the rest of the batch lifecycle. Proof work
selection and assumption-proof admission compare against that index hash
instead of admitting the predicate again (`pps_assumption_equals_goal`).
`gpu_batch_refuses_rewritten_retained_assumption_row` covers the refusal.

Implementation hashing and owner/assumption indexes narrow candidates. Full GPU
structural comparison determines equality. Collision chains need an explicit
work bound and an explicit exhaustion failure, with no unbounded scan fallback.
These are design contracts until the program-level gate and replay consumer are
implemented and exercised by the retained caller-implementation reproduction.

## Deferred work

- The cross-unit implementation solver, selected evidence packets, and explicit
  body replay forwarding.
- Blanket/generic implementations, prerequisite solving, and cycle handling.
- Generic trait methods and method `where` clauses.
- Ordered constant trait operands still rejected by the current checker.
- Default-method selection, overlap/specialization rules, negative implementations,
  and associated types/constants.
- Private type identities needed by exported evidence, and generic replay of
  private implementation callables through the current public-method lookup.

These remain compiler dependencies until their runtime behavior is implemented
and tested. See [current semantic contracts](compiler-semantic-contracts.md).
