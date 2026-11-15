# Retained instance discovery

`RetainedDiscovery` is the GPU producer of `ProjectionInputs` and the original
objects' deferred-use routes. Its inputs are the committed build store. The host
allocates and submits work, reads counts and failures, and retries capacity
requests. It never supplies an instance list, selects a callee, or reads an
environment to construct a route.

The implementation admits free-function and implementation-method calls.
Bounded calls and required-member calls need `run_with_traits` and a current
GPU solver publication. Each wave solves the instances' closed predicates;
required-member edges consume those concrete proofs. Unsupported calls never disappear and never
trigger source replay in this API.

## Discovery

Every call in an ordinary callable (an empty composed binder) is a root. A generic
callee's normalized closed ENV is validated by retained substitution, including
bindings unused by its body. The exact instance key is `(DeclId, ENV TermId)`;
hash collisions use full-key comparison. A root has depth one. Each following
wave expands the new instances, substitutes their retained call environments and
inserts or reuses the resulting callee instances. An existing instance adds no
depth; creating a new instance beyond depth 64 fails.

A wave needs few host round trips. The scan's last lane writes the
workgroup count of the request pass, so requests follow the scan in one
submit; after an edge overflow the request pass has no workgroups. The
publish pass then records in status word 12 whether a request failure or
an overflow happened. Resolution records into the substitution's first
batch submit (`run_then`). It does nothing unless that run's publication
committed, or when status word 12 is set, so the host still reports the
first failure or grows exactly as it did when it read the status between
these passes. The substitution counts, the discovery status and the store
counters come back in one readback. A wave without closed predicates
therefore costs one readback, and a wave with them adds the closed
producer, solver and method-route readbacks. Settings: 134 to 106 readbacks
per build, discovery about 96 to 36 ms in a back-to-back A/B.

The roots follow the same path: the root request pass, the publish pass
and resolution need no status readback between them. The closed
publication's receipt (its route header) is copied on the GPU into
`dg_receipt` in the wave's scan submit and comes back with the
resolution readback; the host checks it before any growth or failure of
that wave, and before the method routes size their tables from its proof
node count. The bound-route pass `06_bound_routes` and the publish pass
record into each method-route batch. They do nothing unless `mr_state`
word 0 is 2 and `MR_PENDING` is clear, so the routes' state, the
discovery status and the store counters come back in one readback. Term
ranking takes the term count from the last status readback and does not
read the status after the sort. Settings: 90 to 81 readbacks per build,
with the same executable. Discovery takes the store's counters from the
catalog's publication-status readback, the retention export reads its
two counter blocks together, and the original-call symbol pass
(`native_calls.rs`) returns its status and both symbol columns in one
readback: 77 per build.

In a wave with closed proofs, the first method-route batch also records
into resolution's first submit, after `01_resolve` and the publish pass,
followed by the bound routes and another publish pass. The host does not
yet know the request count or the proof node count: the batch copies
`sb_counts` word `REQUESTS` and receipt word 24 (admitted proof node
rows) from `dg_receipt` into every route config on the GPU, and sizes
lanes and tables by the request capacity and by the proof arena's words
divided by 8 (a node row is 8 words). Selection checks that the
substitution run is current, so a run that did not publish selects
nothing, and `06_bound_routes` also requires that resolution left status
12 clear. The routes' state comes back with the resolution readback.
The host uses it when that readback came from the first batch and the
routes finished without overflow; otherwise it runs the routes again as
before. A wave with closed predicates then costs three readbacks: the
producer, the solver and resolution. Settings: 74 per build.

A parallel prefix scan assigns each frontier instance a range of use edges.
Request production and result consumption use one lane per edge or request;
no lane walks a function's call list. The interner may allocate unpublished
candidate records under contention. They are tombstoned and omitted from
subsequent waves and output.

Instance, edge and request overflow publish nothing. The host grows the reported
capacity and repeats discovery. Successfully interned substitution terms remain
valid build terms. No frontend job is repeated by discovery.

## Deterministic native identity

After the instance set closes, closed stored terms are sorted by height and then
by their complete key: kind, declaration identity or scalar words, and previously
ranked children. Scalars retain their fixed codes. Each comparison visits only
the record's bounded argument list; it does not recursively walk a term graph.
Instances are then sorted by declaration identity and ENV rank. Neither hashes
nor allocation-order TermIds decide the final instance rank.

The implementation uses bitonic sorts within each height and over the instance
set. Work is O(sum N_h log² N_h + I log² I), with bounded-arity comparisons. It
currently ranks all closed store terms, not just terms reachable from instance
keys. Frontier placement uses O(F log F) work. The sort steps with j < 256
stay inside one 512-key block, so one workgroup runs them in shared memory
with the same compare-exchange network as the global steps. A stage k then
costs one dispatch per global step (j ≥ 512) plus one, and a sort of at most
512 keys is one dispatch. Settings (term heights of 3260, 3139, 323 and 12
keys, 3138 instance slots) records 28 term-sort and 10 instance-sort
dispatches instead of 217 and 78.

## Publication

`DiscoveryPublication.inputs` contains two uint4 records per instance and one
route per instance use, in the existing projection format. No instance is marked
as the program entry: the original object retains `main`.

`root_routes` is indexed by the global retained-use ordinal. A root route contains
`(library, unit/namespace, local/rank, generation)`. Non-root slots are zero.
`root_readiness` contains `(generation, READY_ROUTES, instances, retained uses)`.
The original-call ABI check must certify its ABI flag before native finalization.
Projection independently checks each instance call's signature and layout before
it lowers any batch. All consumers must validate the generation and store READY.

A failed discovery returns a code, retained-use ordinal, instance index and detail.
It publishes no usable readiness record. This API is not yet the default compiler
path and does not by itself remove replay from normal compilation.

## Bounded direct calls

`run_with_traits` binds the retained solver publication without reading semantic
rows. The GPU checks its epoch, arena, serial, generation, status, and source-store
extent (uses, declarations, directory entries, trait records, committed jobs).
A later export invalidates it even within the same build; adding substitution
terms does not. Each bounded call needs a use-map entry with exactly its callee's
applicable predicate count and successful proof routes. Original roots require
closed proofs; calls inside generic templates may use the caller's declared
assumptions. This is parametric proof reuse: every root discharges its bounds,
and every template call proves the next callee's bounds under its own.

The source proof gate authorizes a direct callee. Discovery also solves every
instance's predicates under its closed environment, without assumptions.
Discovery sets projection readiness bit 4 only after these gates succeed.
Projection requires that bit for bounded templates and validates
each BOUND row's predicate link before omitting its source-only syntax.

`retained_discovery_requires_current_proofs_for_bounded_calls` rejects missing
admission, missing per-use proof status (including a forwarding template), and a
publication predating another committed job. A fresh publication succeeds.

## Bound-member routes

`MethodRoutes` matches a required-member use to the caller's accepted predicate
by exact symbolic subject and trait arguments. It reads that predicate's closed
solver route, finds the required symbol in the implementation's sorted method
table, and converts the selected implementation bindings to retained terms.
No host code reads proof rows or constructs an environment.

Proof conversion uses one lane per reached proof node and bounded-arity child
reads. Marking and bottom-up translation are fixed-point loops. Each round
sets a changed flag, and a round after one without change skips its work.
Three flags rotate by round modulo 3, so a round clears the next round's
flag without racing its own readers. The environment and finish passes run
only after the last recorded round of both loops changed nothing. Otherwise
they set `MR_PENDING`, and the host records twice as many further rounds in
the next batch. The first batch has 8 rounds of each loop, and the bound is
65 of each, where the environment pass runs regardless, as before. The
settings app converges in the first batch: 23 dispatches and one readback
per wave instead of 135. A lane per call interns the complete
implementation-method ENV, using exact parameter identities for inherited
impl bindings. Capacity overflow rolls back newly interned terms and retries
after growing the store.

Discovery inserts the selected `(method DeclId, closed ENV)` into the same
instance table as direct calls. `ProjectionInputs` carries that target alongside
each route. Projection checks the selected target's receiver, arguments, result
and layout before any native lowering. Required-member calls from original
nongeneric bodies are not admitted through this route; concrete method calls
there use their frontend-selected implementation.
