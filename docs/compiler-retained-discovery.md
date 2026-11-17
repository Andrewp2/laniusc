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
node count. The closed solve itself is deferred: the solver records its
first wave submit (the batch admission, two full rounds, three queue
rounds and the finish point)
and returns without its progress readback. The receipt copy also carries
the solver's wave state and batch receipt, so the resolution readback
shows whether the solve finished in that submit. When it did not, the
wave's routes are incomplete: the attempt runs again, and this discovery
reads every later closed solve's progress before its resolution
(`eager_closed`). Settings: 73 to 70 readbacks per build. The bound-route pass `06_bound_routes` and the publish pass
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
It is a block scan in three dispatches (`02_scan` modes 3, 4 and 2): each
256-lane workgroup scans its instances' use counts in shared memory and
writes its total to `dg_scan_blocks`, one workgroup turns the totals into
exclusive prefixes, and the placement pass adds them. The placement writes
the inclusive prefixes to `dg_scan_a`, which the request pass searches. The
Hillis-Steele scan it replaces took one dispatch per power of two of the
frontier width. With the closed producer's block scan, settings records
5346 instead of 5418 dispatches and discovery's host gaps shrink by about
a third.
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

Each resolution submit ends with a level count (`03_term_order` mode 6)
over the store's term capacity, and the counts come back with that
readback. After the last wave nothing interns terms, so ranking takes the
level counts from the last readback when it came from resolution's first
batch and no method routes ran after it; otherwise it counts and reads
them as before. Mode 6 skips a term without a valid height, which mode 1
then reports as before. Discovery's last readback after ranking returns
the status: settings needs 73 readbacks per build.

A native build skips that last readback (`defer_final_status`). The
ranking, instance-order and publish passes write the projection's and the
roots' readiness only when nothing failed, so the projection plan rejects
the inputs of a failed discovery; the build then reads the status
(`final_failure`) and reports discovery's error. Direct callers of `run`
still get the checked outcome.

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

## Chained waves

A wave whose frontier has no closed predicates needs no host decision
before the next wave unless it fails, overflows or inserts instances with
closed predicates. Such waves run as a chain in one submit
(`chain_waves`): the first chain of an attempt records 3 waves, each later
chain twice as many (at most 48). Wave 0 has the host's frontier. Before
each later wave, `05_publish` mode 3 (one lane) places the instances the
previous wave inserted, `(lo, hi, edges)`, in `dg_wave` and logs `(lo,
hi)` at word `4 + 2i`; it leaves the frontier empty when status 12, 3, 10
or 6 shows a failure or overflow, or when status 11 (inserted instances
with closed predicates) differs from `dg_wave` word 3, the count before
the chain. A wave that records its own closed solve (config word 11) takes
new closed predicates itself. Buffer copies then put
`(lo, hi, edges)` into the wave's seven configs, and `dg_indirect` is
cleared, so an empty wave dispatches no requests. The scans of a later
wave run over the instance capacity; the kernels stop at the frontier.

Each wave substitutes its requests in its own run, recorded with
`RetainedSubstitution::record_chained` (run numbers are copied into
`sb_config` in encoder order) and followed by resolution and the publish
pass. Resolution of a chained wave (config word 8 nonzero) whose run did
not publish (not final after its first batch, overflowed, or more
requests than the buffers hold) fails with code 11 in status 10, which
stops the chain. The level count runs once after the last wave. One
readback returns the status words, the store counters, the last run's
status words, the wave log and the level counts. The chain is accepted
only when the last run published, nothing overflowed and nothing failed;
otherwise the attempt runs again without chaining, which grows, retries
substitution batches or reports the failure as before. A chained run that
stopped before its finish step leaves the store's overflow and demand
words cleared, as an unchained run that hits an error does.

Settings: the three waves after the last closed wave cost one readback
instead of three; 44 to 42 round trips per build, the same dispatches and
the same executable. Forcing every chained run to stop after two rounds
reruns each attempt unchained (52 round trips) and still produces the same
executable and passes the retained tests.

## Chained closed waves

Waves with closed predicates chain too (`chain_closed`,
`record_closed_chain`). A chain records `CLOSED_CHAIN_WAVES` (3) closed
waves and then a tail of waves without closed solves, with one status
readback at the end. Each closed wave records its solve before the host
has read the status of the wave before it
(`RetainedTraitPublication::record_chained`):

- Sizes come from capacities: the frontier end is the instance capacity,
  the terms are the term capacity, and the batch uses `closed_bounds` of
  twice the predicated instances the host saw (at least 64).
- `closed/09_plan` (one lane) gates the solve. It reads the frontier from
  `dg_wave` and the discovery status, and runs the solve only when
  discovery has no failure or overflow, the frontier is not empty and the
  wave inserted instances with closed predicates (status 11 differs from
  `dg_wave` word 3). It then writes the indirect workgroups of every
  producer and publication pass. A skipped solve writes zeros and the
  fault word 16, so nothing after it dispatches work.
- `05_publish` mode 4 checks the solve's receipt, copied into
  `dg_receipt`. A solve that ran must have placed its batch and finished,
  or the chain stops with code 12. The mode writes the workgroups of the
  wave's method routes and bound routes (`dg_route_args`,
  `dg_bound_args`): none unless the solve finished. `06_bound_routes`
  stops a chained wave with code 13 when the routes did not finish.
  A stopped solve publishes nothing that a later wave reads.
- The solve submits as it records: the GPU runs its producer and batch
  setup while the host records its rounds. Recording a whole wave (the
  frontier pass, the solve and the resolution) into one encoder and
  submitting it once was tried and was slower. It removed that overlap,
  and the time from the substitution readback to the discovery status
  went from 8.3 to 9.7 ms (medians of 26 builds).

The host checks the end status (`finish_chain`). A capacity failure grows
the capacities and runs the attempt again (`closed_chain_growths`); any
other failure runs the attempt again without chaining
(`closed_chain_fallbacks`). `retained_native_closed_chain_retries_with_grown_capacity`
starts with tiny capacities, grows inside the chain and builds the same
program twice.

Settings: 27 to 24 round trips per build. The span from the proof-wave
readback to the last projection readback is in the table under "Source
publication status".

## Source publication status

The trait catalog's publication status (route header words 8-10) is no
longer read on its own before discovery. The root submit copies the three
words into `dg_receipt`, which is free until the first closed wave, and
they come back with the roots' resolution readback. Discovery notes them in
the publication (`note_status`); a status other than `[1, 0, u32::MAX]`
rejects discovery with code 10 (detail: the first failure) before any
growth or root failure. The native build runs discovery first and then
checks `checked_status`, which returns the noted words or reads them when
discovery stopped before its first readback, so a failed publication is
still reported as the trait diagnostic, before any discovery result. The
publication keeps the store counters its catalog ran with, and discovery
sizes its roots from them while the store has the same generation and
committed exports. Settings: 45 to 44 round trips per build.

The native build's trait solve is deferred (`RetainedTraitOptions::defer_solve`):
nothing reads its progress before discovery. Its publication is valid only
when the solve finished in its first submit and the catalog's fill and
admission held (header words 45 to 47, see the trait catalog guide). The
root submit runs `05_publish` mode 5 after copying the status words. That
mode writes the roots pass's workgroups into `dg_bound_args`: config word
10's workgroups for a valid publication, and none otherwise. So a solve that
did not finish requests no substitution and appends nothing to the store.
The roots readback returns the status. When it is not valid, the native
build checks the traits again with the solver state read back and runs
discovery again (`trait_check_retries`). The projection is recorded after
that readback, so its schema gate (`04_round`) needs no verdict input.
`retained_native_unfinished_deferred_solve_checks_again` forces an
unfinished solve and builds the same program.

Settings, medians of 26 warm profiled builds per version, interleaved
with the baseline in the same session, at load average 3 to 4 with other
agents on the GPU. R is `program_retention.readback`, the readback before
the proof wave, P is `program proof wave progress` and L is the last
`retained_projection.readback`. The executable hash is 115a4d52a2ae77e0
for every version.

| Version | P to L (ms) | R to L (ms) | Round trips | Dispatches |
| --- | --- | --- | --- | --- |
| Baseline (f94c4b01a) | 13.43 | 19.36 | 27 | 3,689 |
| Closed waves chained | 11.17 | 17.34 | 24 | 3,695 |
| Deferred trait solve | no P | 16.66 | 23 | 3,696 |

An earlier session measured the solver's compute passes per run of
dispatches against the same baseline: P to L 14.44 to 14.15 ms, with the
same dispatches and round trips. From the substitution readback to the
discovery status the chain now waits 0.6 to 2.5 ms for the GPU. The three
closed solves take 1.2 to 2.2 ms of GPU time each (116 dispatches, traced),
so the chain is limited by GPU time, not by recording.

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

Proof conversion reads proof nodes with bounded-arity child reads. Marking
(`02_expand`) and bottom-up translation (`03_terms`) are fixed-point loops,
each one dispatch of one 256-lane workgroup. The lanes stride over the proof
nodes, and a workgroup barrier separates levels. Each level sets a changed
flag, and the loop stops at a level whose predecessor changed nothing, or
after 65 levels (proof depth is at most 64), where the environment pass runs
regardless, as before. Three flags rotate by level modulo 3, so a level
clears the next level's flag without racing its own readers. Translation
reads one value buffer and writes the other by level parity, and a level
without change leaves both equal. `MR_PENDING` stays clear. The settings app
records 7 dispatches and one readback per wave (21 before, 135 before
that). A lane per call interns the complete
implementation-method ENV, using exact parameter identities for inherited
impl bindings. Capacity overflow rolls back newly interned terms and retries
after growing the store.

Discovery inserts the selected `(method DeclId, closed ENV)` into the same
instance table as direct calls. `ProjectionInputs` carries that target alongside
each route. Projection checks the selected target's receiver, arguments, result
and layout before any native lowering. Required-member calls from original
nongeneric bodies are not admitted through this route; concrete method calls
there use their frontend-selected implementation.

## Recording

Discovery queues its dispatches and records each run of them as one
compute pass (`flush`), before any other use of the encoder: a copy, a
clear, another module's recording into the same encoder (the substitution
engine, the method routes), the return of a consumer it recorded for the
engine, and `finish`. wgpu-core's `finish` costs about 13 µs per compute
pass: with one pass per dispatch, finishing the ranking encoder took
0.36 ms. Settings: the host gap between the chain readback and the
projection plan readback went from 1.55-1.85 ms to 1.18-1.34 ms.

## Buffers across warm builds

A warm build creates no bind group in discovery, method routes, the
retained catalog, closed waves or native calls. Their buffers persist in
the daemon, and buffers whose size follows the term count grow by powers of
two, so a build whose term count grew a little binds the same buffers and
reuses the cached bind groups. The method-route view binds its whole route
arena, since the route header bounds every read. Discovery keeps the
published projection inputs, root routes and requests while their capacities
are unchanged; every attempt clears them before use. `dg_instances` and
`dg_edges` keep their exact size, because the kernels read their capacity
from the buffer length and it must match the projection inputs.

In the settings census, a late warm job created 364 bind groups before
this change (all stages) and 2 after, none of them in these stages.
