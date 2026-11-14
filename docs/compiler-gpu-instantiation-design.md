# GPU instantiation: proposed implementation boundaries

This draft specifies the replacement path. It is not an implementation receipt.
The measurements, prototype history and remaining coverage gaps are in
[GPU generic instantiation](compiler-gpu-instantiation.md). The draft needs a
code audit of discovery inputs outside the settings workload before its
interfaces are frozen.

The host supplies input bytes, allocations, transfers and submissions. Shaders
own declaration identity, type substitution, implementation selection, instance
discovery, layout, row projection and publication. Every build reconstructs all
semantic state. Retained capacities and pipelines are not compiled-result caches.

## 1. Separate logical identity from physical storage

The following are distinct typed handles, even if an initial implementation
stores each as a u32. No token number is a program type or instance identity.

| Handle | Identity and use |
| --- | --- |
| `DeclId` | GPU map of `(library, frontend unit, declaration namespace, local identity)`. Namespaces distinguish callables, nominal types, traits and implementations. Public interface indexes and private local identities keep their existing meaning. |
| `ParamId` | `(declaring owner DeclId, type/constant domain, source ordinal)`. An inherited parameter retains its original owner. A slot is only a position in one environment's parameter map. |
| `SymTermId` | Immutable symbolic term over exact `ParamId` leaves, named declarations and typed constants. Shared terms are equal only after comparing complete records and child identities. |
| `TypeId` | An exactly interned **closed** type/constant term in the build store. A named type includes its declaration and complete ordered lexical/application arguments. |
| `InstanceId` | `(callable DeclId, closed environment TypeId)`. Environment domains, parameter order and constant value/type identity are explicit. Native widths and transient proof IDs are not part of this key. |
| `UseId` | A template's callable-use ordinal. An instantiated use is `(InstanceId, UseId)`; an ordinary use is qualified by its frontend unit. Calls and address-taking must both be inventoried. |

The canonical store in a frontend job remains job-local. At retention, shaders
translate its leaves and nominal identities into these build handles before
another job reuses the storage. There is no global relocation of every source
token. A build declaration key need not be numerically identical under a
different frontend partition; all references within either build must resolve
consistently, and partitioning must preserve program behavior.

The implementation solver keeps its current graph representation initially.
GPU adapters translate closed build terms into solver terms and intern returned
implementation bindings into the build store. Solver roots are not canonical
identities. Translation work is proportional to the reachable term graph; it
must not be described as one constant-cost operation per call or wave.

Atomic insertion order must not determine output order. Final instance ranking
uses declaration keys and structural environment order. Structural type ranks
can be computed bottom-up over the type DAG. Hashes may accelerate sorting and
lookup, but collisions require exact comparison, never rejection or replay.

## 2. A unit exports two different kinds of retained data

**Discovery data** contains declarations, binder maps, nominal field/variant
schemas, callable contracts, callable uses, obligations and symbolic term DAGs.
It contains the semantic dependencies needed to resolve each use. It does not
contain executable statement order merely because the original HIR did.

**Body segments** contain immutable HIR and side tables for projection. References
inside a definition are relative to that definition. External declarations,
symbolic terms and source files use build handles. Strings have segment-owned
byte ranges. A directory maps a declaration to its segment and ranges.

Retention is a GPU count/scan/scatter operation. It copies live ranges, not
whole token-capacity buffers. Every exported field is either local to the
segment or explicitly externalized. Keeping an arbitrary outside HIR/token
index, as the current same-job copy code does, is invalid across units.

The retained set includes file functions, impl methods, trait-provided bodies,
and nested definitions with lexical parameters. Nested definitions get their
own declaration identity and an explicit map of inherited parameters. Runtime
captures must already be represented by the existing closure elaboration.
An inner slot zero must never capture an outer or trait slot zero accidentally.

Ordinary functions can lower during their unit job. Their generic calls and
generic function references emit deferred GPU link records keyed by ordinary
`UseId`; final routes are resolved after discovery. This avoids retaining all
ordinary HIR until the final unit. Those objects remain unpublished until the
program admission and routing checks finish.

## 3. Discovery consumes semantic dependencies

A callable use records its diagnostic span and one of:

- a resolved declaration with its symbolic environment;
- a required trait member, trait arguments, receiver term and receiver plan;
- an explicitly described deferred route supported by the current language.

Each environment/result dependency is an immutable semantic term or projection
with named inputs. The initial operations are parameter substitution, nominal
application, existing supported constant terms, signature instantiation and
implementation-member routing. A deferred signature result names the selected
callee and its environment, not an instruction to re-run type inference over
source text. A new projection operation needs an actual supported source case
and a GPU producer/consumer contract.

The frontend must normalize bound-member signature types into the enclosing
binder before retention. For `F: Mapper<T,U>`, the result of `F.apply` is the
bound's `U`, even if the trait and enclosing function use different parameter
slots. The confirmed `enter_mapper` defect violates this requirement. Fixing it
does not require choosing a concrete implementation.

Discovery must not assume a single fixed-size call record is sufficient. A use
may reference a variable-size semantic dependency DAG. Its readiness is defined
by those inputs. The GPU schedules ready term, obligation and routing tasks;
one lane must not walk an entire function's call list. Count/scan operations
flatten `(frontier instance, use)` and variable-length term/argument work.

This is the boundary to audit for constant generics, trait-provided methods,
nested definitions, constructors, function references and dependent method
results. The audit must show that their existing semantic inputs can be
exported. One settings counter cannot prove this contract for the language.
If a case needs another semantic dependency, export that dependency; it does
not automatically require every executable body to stay resident.

## 4. One owner for implementation selection and obligations

After all units export their catalog rows, the GPU admits the combined catalog
and checks coherence. The program trait solver owns concrete implementation
selection. Discovery produces hard obligations and consumes selected member
declarations and implementation environments from its evidence.

Template checking retains symbolic assumption contexts. Closed instances need
concrete obligations; they do not acquire proof merely by inheriting an integer
evidence slot. Retain the current context-scoped proof memo initially. Sharing
closed proofs across contexts is a later optimization, with separate admission
of closedness, catalog identity and source authority. Repeated in-progress goals
remain dependency edges and must not count as successful proofs.

The GPU checks callee bounds, exact environment domains, selected member
contracts, receiver adjustment and complete layouts before publication. Replay
transport/provenance checks may disappear only when their source-authority
obligations have moved to the retained-template boundary. The current soft
obligation demotion to replay has no role in the new path.

## 5. Discovery waves, depth and capacity

Root uses come from the ordinary emitted callable inventory. A wave expands a
frontier of newly discovered instances. It substitutes use inputs, resolves
required semantic dependencies, submits obligations, obtains routes and inserts
new exact instance keys. Pending facts stay in that wave until ready. Memory
chunks do not increment semantic instantiation depth.

Depth is proposed as minimum distance from a root instance (root depth one).
Insertion/reuse must resolve existing keys before reporting a depth violation.
The baseline replay probes support the 64-level boundary for finite chains,
mutual recursion and a shortcut to an existing instance. GPU-selected-copy and
cross-unit depth behavior still need acceptance tests. Growing polymorphic
recursion must retain LNC0073 and its source call, including when a type graph
work limit is encountered before the nominal depth boundary.

The host may record batches of waves in advance. GPU-produced indirect counts
make empty work inert. Solver rounds and dependent semantic terms still impose
real sequential work; both their span and idle dispatch cost must be measured.

Each arena publishes demand and capacity status without writing outside its
allocation. A capacity failure cannot authorize partial output or a speculative
language diagnostic. The host grows storage and replays GPU work from immutable
retained inputs. Capacity is distinct from language limits and traversal guards;
replay packet limits must not become whole-program limits.

## 6. Physical cloning and bounded lowering

After discovery, GPU scans assign disjoint row, token and side-table ranges to
instances in a lowering batch. Projection substitutes symbolic facts and computes
layout before LIR sizing. The existing lowering algorithms consume the concrete
rows. Instances do not share mutable local, place or schedule identities.

Instance lowering has its own capacities and local type-row namespace. It does
not use the original job's spare quarter of token capacity. Cross-batch calls
name the final instance symbol, never another batch's virtual token.

Use a reserved instance symbol namespace, qualified by the definition's library
and deterministic instance rank. Frontend units cannot allocate that namespace.
The GPU link stage resolves ordinary deferred uses and instance relocations to
these symbols. A trait default body uses the selected implementation's subject
and trait arguments while retaining the default declaration's identity.

Bodies may be transferred to opaque host-backed storage for the current build
and streamed by segment for projection. The GPU determines batch membership
and routes; the host transfers bytes. Discovery data and canonical identities
must remain available independently of body placement. Their actual memory
budget is still unmeasured; the settings source-ratio estimate is not an upper
bound. A device buffer limit must not be turned into a source-size restriction.
Forced-small-budget tests must exercise segment transfer and lowering batches
before claiming large-program support.

## 7. Publication and implementation gates

One GPU status reduction permits publication only after all required work has
finished, no capacity or semantic failure remains, every emitted callable use
has an admitted target, and every by-value type and call ABI is complete.
Diagnostics retain unit-qualified source locations. Deterministic error choice
requires a defined lexicographic reduction; discovery thread order is not one.

Implementation proceeds through complete interfaces, without per-instance
admission/rejection fallback:

1. Repair and validate symbolic binder ownership; audit discovery dependencies
   for the source forms listed in section 3.
2. Export two units into retained segments and semantic data, then overwrite
   both frontend workspaces. Reconstruct a foreign body and its types correctly.
3. Run GPU discovery/selection with two environments, a cross-unit generic
   chain, private nominal/extern references and a failing concrete obligation.
4. Clone and lower the complete instance graph, resolve ordinary root uses,
   and execute with the source-copy builder unavailable.
5. Force growth, body transfer and multiple lowering batches; validate finite
   and growing recursion, diagnostics, hash collisions and repeated builds.
6. Cover the existing supported language suites, delete source replay and
   selective rejection machinery, then measure full settings rebuilds.

The first cross-unit execution fixture is the existing
`native_large_pack_spills_originals_and_generic_replays_and_writes_atomically`
test. Extend coverage with foreign equal-width/different-layout types and a
private nominal inside a foreign generic body. Padding above the unit limit
tests partitioning; it does not test a large live template working set.

A new implementation may emit different bytes from the replay implementation.
Required comparisons are program behavior, admitted semantic facts and source
diagnostics, plus deterministic bytes across identical builds of the new path.
The timing target remains about 160 ms for a full warm settings rebuild; this
architecture alone is not evidence that the target will be met.
