# Retained instance discovery

`RetainedDiscovery` is the GPU producer of `ProjectionInputs` and the original
objects' deferred-use routes. Its inputs are the committed build store. The host
allocates and submits work, reads counts and failures, and retries capacity
requests. It never supplies an instance list, selects a callee, or reads an
environment to construct a route.

The current implementation admits direct free-function calls. Relevant method
routes and trait predicates return a rejection until the discovery-wave solver
producer supplies their evidence. Unsupported calls never disappear and never
trigger source replay in this API.

## Discovery

Every call in an ordinary callable (an empty composed binder) is a root. A generic
callee's normalized closed ENV is validated by retained substitution, including
bindings unused by its body. The exact instance key is `(DeclId, ENV TermId)`;
hash collisions use full-key comparison. A root has depth one. Each following
wave expands the new instances, substitutes their retained call environments and
inserts or reuses the resulting callee instances. An existing instance adds no
depth; creating a new instance beyond depth 64 fails.

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
keys. Frontier placement uses O(F log F) work. Host count readbacks between waves
and sorting's dispatch overhead remain optimization work.

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
