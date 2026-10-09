# Verification status

Status: active and incomplete. Normal Lean extraction and x86 compilation share
the typed IR. The general tool-correctness proofs and explicit trusted-output
boundary remain unfinished.

Current metatheory ledger: `METATHEORY.md` tracks all 26 requested obligations
and the optional-theory decisions. Cell-backed reference/slice target validity
now supplies successful typed reads and exact slice lengths, survives alias
writes/fresh-cell frames, and connects local borrow/array conversion and
dereference/indexing to the actual evaluator. Access uses the state after
operand effects. Both native synchronization directions now derive success and
retain typed live targets/readability; fresh local-array exposure and existing
view reuse connect to the actual evaluator. Modeled host file reads and stdout
also work with registered views. Both i32-array codecs now roundtrip exact
typed contents/bytes. Flush establishes byte coherence for disjoint registered
ranges; coherent flush is an exact identity, as is coherent refresh with unique
cell IDs. The actual stdout declaration's stronger modeled contract preserves
all cells/aliases, locals, allocation frontier and view registrations exactly.
Refresh now establishes coherence after arbitrary readable host bytes when
root/path registrations are unique. Typed storage derives independence of those
targets, including different arrays nested inside one shared cell. First exposure
now covers arbitrary typed nested array paths and retains prior coherence/unique
registrations. Storage readiness also tracks allocation-frontier bounds and
survives typed cell effects, pointer exposure and modeled reads. The real extractor
uses slice pointers; their cell/raw descriptor rules derive readable requested
subranges after operand effects and compose with its actual read declaration.
Actual scratch allocation/construction now establishes raw descriptor validity
on the no-registration route, from positive representable word counts and
numeric budget capacity. Its modeled read composition consumes that validity,
not an assumed raw readable range. Allocation with live registrations, full
driver/byte-I/O algorithms, region/lifetime/ownership, recursively stored reference
validity and whole-body preservation remain open.

Latest reader checkpoint: the actual public call now proves exact whole-file
expanded bytes, untouched output tail, return count, file cursor and read trace
for independently readable capacity-fitting files with nonnull scratch. It
retains the complete safety/caller/storage result. One tracked loop proof and
shared pointer/parameter/call bridges serve both contracts; the observation
callback is proved from retained read/copy effects, not assumed correct output.

The 21 complete source bodies check fresh together in 17.09 s (3,039 lines),
with other foundations and unchanged matched admission built. Whole-file
body/call checking takes 2.21 s; fixtures 3.57 s. All 1,132 execution tests pass,
with a proved allocated-buffer actual call and ordinary chunk-count boundary
checks. Sources/bundle match and transitive axioms are standard logical axioms.
Current source-boundary checking/self-emission matches admission in 6.66 s.
Reader-only proofs are 1,132 lines against 38 source lines, about 30x before
imported host/allocator contracts, still above target. This is stronger scope,
not compression. Exact whole-file error/overflow refinement, real driver input
premises, general preservation/extraction and native/x86/end-to-end correctness
remain open. The theorem uses the modeled full-prefix file service, not native
OS read guarantees. No source/format/trust/limits changed; the full fresh
admission/mutation gate was not run. See `METATHEORY.md` for evidence.

Previous frame checkpoint: the complete actual outer loop, initializer,
function body and public call now derive total execution from independent
raw-buffer/caller assumptions. Positive reads decrease remaining capacity;
EOF/errors/overflow return. Pointer and parameter bindings are derived, not
caller-supplied. Caller cells/scope, buffer readability and heap uniqueness
survive. The same invariant now preserves all reads outside the union of both
buffers and retains allocation metadata. An actual call proof protects allocated
sentinel bytes in the gap between buffers, not just outside their convex hull.
Negative capacity and null scratch have separate early-rejection
proofs without readable-buffer assumptions, with a concrete empty-heap instance.

The final 18-body connected artifact checks fresh in 15.03 s (2,617 lines),
with other foundations and unchanged byte-identical program admission built,
not bundled proofs. Actual function/call checking takes 1.75 s; final fixtures
2.91 s. All 1,096 declaration/call/error executions pass, including shadowed
caller cells, exact small-file output/cursors/traces, gap storage, failed reads,
allocation metadata and early rejection. Sources/bundle match and
audits show standard logical axioms only. Fresh current self-emission/source
checking matches admission in 6.72 s. Reader-only proofs remain about 23x the
38-line source function, before imported host/allocator contracts, above target.

These contracts establish termination, memory/caller safety, return bounds
and outside-both-buffers framing, not exact whole-file contents/cursors. Those
refinements, the driver's allocation premises, general preservation/extraction,
native syscall/x86 simulation and end-to-end correctness remain open. No
compiler source/emission/trust/limit changed. The full admission/mutation gate
was not run. See `METATHEORY.md` for scope, counts and cache conditions.

Previous outer-body checkpoint: `ByteIoReadProof.Outer.iteration` derives total
execution of one complete actual outer body, including both request branches,
usize conversion and every read-entry premise. It reuses the exact host-read,
guard, copy/update and scope contract. Observable parameters are independent of
temporary bindings, so the result composes without another emitted tree.

All 14 bundled source bodies check fresh in 12.83 s; the actual outer body takes
1.85 s. Other built foundations and byte-identical matched program admission
are reused, not bundled proofs. Shared automation rebuilding takes 4.02 s and
its focused regressions 1.73 s. The 179 new executions cover request boundaries,
EOF/errors/overflow, copied bytes, file cursor, total and shadowed-local scope.
Prior fixtures pass. Current self-emission matches admission in 7.60 s including
source-boundary checks. Sources/bundle match and audits show standard axioms only.
Reader proofs remain about 20x the matching source block, above target; improve
invariant/context composition before scaling. Caller-derived loop entry,
capacity decrease, the complete loop and whole-file/call contract remain open,
alongside preservation, extraction and native syscall/x86/end-to-end correctness.
The full admission/mutation gate was not run. See `METATHEORY.md` for evidence.

Previous host-read checkpoint: `ByteIoReadProof.ReadStep.run` derives total execution
of the actual count declaration, including host read, source-ordered guards,
copy/update and lexical restoration. Exact file results supply counts and bytes,
not assumed read success or loaded chunks. Overflow advances the file cursor
but does not copy; I/O errors/EOF retain the old total. Caller cells/counter,
view registrations and outside output memory are framed. Raw and registered
reads share the byte service; read/copy share buffer facts. Redundant raw-read
witnesses and unused standalone guard contracts were removed without aliases.

Twelve complete source bodies check fresh in 8.75 s; the actual declaration
alone takes 3.85 s with other foundations and matched program admission built.
Fresh current self-emission matches admission (7.80 s including source-graph
checking). Current bodies/bundle match and audits show standard logical axioms
only. A concrete proof and 324 real read/count cases check exact bytes, file
cursor, host trace, total and scope, alongside the earlier fixtures and native
view regressions. Reader modules are still about 18x their matching source block,
above target. Actual outer request setup, caller-derived entry premises,
decreasing capacity, whole-file/call correctness, preservation, extraction and
native syscall/x86/end-to-end correctness remain open. The full admission/mutation
gate was not run. See `METATHEORY.md` for counts and cache conditions.

Previous read-step checkpoint: the actual index initializer, inner copy loop,
computed total update and scope compose, and the actual post-read I/O/EOF/
capacity guards derive their specified outcomes in source order. Returning
branches leave the entire state unchanged; accepted counts retain the exact
output prefix and caller frame. The existing counter rule was generalized and
its duplicated iteration bookkeeping removed, shrinking that module by 18 lines.
Eight complete source bodies check fresh in 3.60 s, with other foundations and
matched program admission built. Fresh current self-emission is byte-identical
to admission (7.06 s including source-graph checking). Thirteen writer bodies
check fresh in 23.97 s as regression coverage. Audits show standard logical
axioms only. The actual proofs are still about 12x their matching source block,
above target. Upstream request/read setup, caller-derived premises, decreasing
outer capacity, exact whole-file behavior and whole-call restoration remain
open, as do preservation, extraction, the native runtime bridge and x86/end-to-end
correctness. Full gate admission/mutation checking was not rerun.

Previous loop checkpoint: `ByteIoReadProof.Loop.run` proves total correctness of
the actual reader's inner copy loop from independently specified entry buffers
and bindings, with index zero. Every packed byte becomes its exact native i32
word, the counter reaches the count and all outside memory/caller cells are
framed. It does not assume execution or output success. The shared prefix rule
now accepts encoded chunks; existing text/hex users are migrated without legacy
wrappers. The four-body connected artifact checks fresh in 2.68 s, with other
foundations and unchanged matched program admission built. The 127 actual proof
lines against the eight-line source block are about 16x, still above the target;
improve composition before scaling outer-loop setup. A concrete proof and all
45 fitting eight-word count/cursor executions pass. Ten full writer bodies
freshly check in 26.10 s as regression coverage, not a claimed speedup. Audits
show only standard logical axioms. Actual initialization/scopes, capacity/error
guards, outer reads and caller-derived entry conditions remain open, as do
general preservation, the runtime bridge and whole-tool correctness.

Previous copy checkpoint: `actualCopyByte` proves the actual reader's complete
computed-index assignment, from readable ranges, numeric bounds and unique heap
blocks. It derives packed-byte decoding and the exact four-byte native write;
all other addresses and the full non-heap state are framed. The unused separate
RHS contract was folded into it. The final actual module checks fresh in 1.73 s
with shared foundations and unchanged matched program admission built. The
48-line module is still about 12x its four-line assignment, above the target;
the enclosing loops must reuse the contract rather than duplicate its setup.
All existing raw-store users were migrated to the generalized state-preserving
index interface, with no compatibility wrappers. Broader consumer/writer
regressions and exact lane/cursor/bounds fixtures pass. The full copy/read loops,
caller-derived invariants, native runtime bridge and tool correctness remain open.

Previous read checkpoint: actual host/scratch contracts now retain exact data,
cursor, count and error effects, with full scratch readability after reading.
The actual `byte_io.read_file` copy RHS returns its selected byte even in a
negative packed word. Destination writes, loop invariants/termination, the
syscall bridge and whole-call/extractor correctness remain open. One fresh
1,320-line bundle checks all eight current shared/actual/fixture bodies in 5.26 s,
with only other foundations and unchanged matched program admission built.
Source comparison and standard-axiom audits pass. Focused regressions take
3.39 s; the actual copy contract alone takes 1.78 s. Production grows by 148
physical lines and fixtures by 67. The 40-line copy module is about 10x its
four-line source RHS, above the 5x target; improve composition before scaling
loop proofs. See the latest ledger/notes for exact scope and evidence.

Previous call-refactor checkpoint: the allocator and raw constructor reuse shared call/store and scoped-memory
rules instead of rebuilding parameter/scope machinery. Their existing local
restoration guarantee comes from the execution relation itself. The three actual
allocation/host/fixture bodies check fresh in one 404-line artifact in 3.38 s,
with shared foundations and previously matched unchanged program admission
built, not cached bundled proofs. Source/bundle comparison passes. The actual
builder's full source dependency closure also checks fresh in a 1,751-line
artifact in 28.02 s; this is a regression, not a speedup. That checkpoint's shared
rebuild takes 12.97 s. The matched allocation/descriptor/read sections shrink
from 208 to 176 physical lines against 22 source lines (~8x), still above the
5x target. Common host-file plumbing and shared foundations add cost. Those
changes remove 32 allocation lines, add one consumer line and 39 shared lines:
production growth is +8, not a net size reduction. Keep reducing repeated
bookkeeping rather than scaling it throughout the remaining loops.
These are modeled-service and self-extracted-body contracts, not syscall,
general extraction or full compiler correctness. See the latest notes for scope.

Local root assignment now uses the evaluator-wide identity law for liveness,
including uninitialized roots and RHS mutation. Its typed composition requires
the proved RHS's resulting typed store; an execution proof alone does not
establish typing. The shorter rule feeds actual writer-cursor proofs, without
weakening their output/frame contracts. Fresh shared proof checks take roughly
one second with built imports. The connected self-extracted writer bundle passes
in 18.93 s, down from 24.63 s, with only byte-identical program admission cached;
it is still above the seconds-scale goal. Lookup now uses existing declaration
chunks and shares kernel-checked lookup facts across proof branches, while guard
simplification avoids repeatedly rewriting the entire context. The new connected
1,525-line frame/native/mapping/host/fixture/actual-host-declaration bundle checks
fresh in 3.80 s with shared foundations and previously matched program admission
built, not cached bundled proofs. Actual declaration contracts alone check in
1.43 s. Focused native, nested-projection, store, host, output and writer-cursor
regressions pass in 3.84 s with dependent rebuilds. The current measured shared
codec/array/projection/view/mapping/coherence/host set is 1,163 physical lines
(+203 from the prior checkpoint); native fixtures are 436, existing projection
fixtures 116 and actual host contracts 76. Additional foundations are not in those
counts. These component checks do not measure the whole compiler proof. The
writer regression after codec relocation passes in 21.45 s; this is not another
performance improvement. These host proofs specify the modeled services, not the native
syscall bridge or general extractor correctness. See the October 4 checkpoints
in `NOTES.md` and `METATHEORY.md` for exact scope and evidence.

Shared semantics metatheory (October 3): `Lanius.Semantics.Fuel` proves that
every completed outcome of all seven mutually recursive evaluator entry points
is unchanged by increasing fuel, including its full state, traps and modeled
host exits. Completed observations are therefore unique across budgets.
`Lanius.Semantics.LexicalFrame` additionally proves that all observed outcomes
retain the caller's lexical bindings, including through native view updates,
scope restoration and host adapters. `Lanius.Semantics.Allocation` proves that
all observed outcomes retain existing cell IDs and append exactly consecutive
fresh IDs. It preserves the allocation frontier invariant, and ID uniqueness
from an initially bounded, unique inventory. Values, native memory and the host
world may change. These laws require no typing or well-formedness premise;
well-formedness is needed only for its preservation consequence.

Single finite execution witnesses now yield stable, lexically framed contracts
without a separate binding-equality premise. The execution contracts also derive
cell well-formedness through `run.cellsWellFormed formedBefore`. The allocation
foundation is 398 lines and checks from source in 15.09 s with built imports;
profiling reports 0.207 s of type checking. Its proof-producing invariant driver
is shared with lexical preservation rather than duplicated. Focused fixtures
cover mutation, recursion, loops, traps, exits and invalid initial states.
The final fixture bundle and ten existing client regression modules pass in
29.01 s, including allocation and client rebuilds with other shared imports built.
Audits show only standard logical axioms. This does not prove value typing,
heap safety, termination of arbitrary programs or compiler simulation.

Typed binding metatheory now connects the actual pattern matcher and parameter
binder to the existing type judgments. Successful nested matches retain every
declared binding's name and type. Typed arguments guarantee parameter-binding
success, including arity agreement. One shared installation rule constructs
the initialized local contexts used by match arms and internal calls, with
the same shadowing order as the runtime. Initialized local reads then evaluate
without a trap and retain their declared type at any positive fuel budget.
Binding installation requires the existing fresh-cell frontier invariant.
This is not whole-body type preservation, match exhaustiveness or a full store
invariant: uninitialized variables and reference/native-view validity remain
separate obligations. Normal emitted programs acquire no second typing tree.

This addition is 188 production-proof lines plus 132 fixture lines. Fresh source
checks take 1.08–1.30 s per proof module with built imports; the connected fixture
checks in 1.18 s. The focused fixture/client build takes 2.38 s, reusing the
existing client checks. Fixtures include real nested match and internal call
execution, arity/variant failures, mixed-type shadowing and invalid states.
Audits use only standard logical axioms. See `Semantics/Typing/` and the
`binary/typing-*-fresh.log` evidence listed in `NOTES.md`.

Aggregate mutation metatheory (October 4): declared struct-field and bounded
array-index paths read successfully with the declared type, at arbitrary
nesting depth. Typed replacement preserves root typing and reads back exactly
the replacement. The actual cell-backed native-aware writer now derives those
results and its existing cell/frame effect from a live initialized typed root;
successful writing is not a premise. Raw heap-backed places and view
synchronization are not covered by this writer-step theorem. A heap/reference-valid
store invariant and whole-body type preservation remain open.

This adds 187 shared proof-library lines plus 110 fixture lines, with no emitted
typing tree or runtime rechecking. Fresh checks take 0.59–1.09 s per proof module
with built imports; the connected fixture checks in 0.94 s. The final focused
build takes 2.38 s, rebuilding the changed proof/fixture modules and reusing
the prior binding tests. A typed nested assignment runs through the actual
evaluator; failures and wrong-type replacement cases keep the theorem's limits
explicit. Audits show only standard logical axioms. Evidence is listed in the
October 4 `NOTES.md` entry.

Declared-cell store preservation now closes the next mutation boundary.
One type per cell identity keeps aliases coherent; initialized contents are
typed and uninitialized slots remain permitted. Fresh allocation extends that
map. Typed cell-backed writes preserve every declared root and read back the
replacement; the only possible primitive-write failure is nested access to an
uninitialized root. A compositional rule for the actual assignment evaluator
also derives success after a proved RHS that retains old cells, with a typed
replacement and empty native views. Unmapped fresh cells, reference/slice target
validity, native storage and whole-body preservation are not thereby proved.

This adds 151 shared-library and 160 fixture lines. Fresh checks take 1.15–1.20 s
per module with built imports; the fresh fixture checks in 1.25 s and the final
focused regression build takes 2.07 s. Tests include real alias writes, allocation
during RHS evaluation, initialization and invalid native-view synchronization.
Audits use only standard logical axioms. No emitted tree, compiler implementation
or compiler-specific contract changed. See the declared-store checkpoint in
`NOTES.md` for assumptions and evidence.

Allocation metatheory now also feeds `core_formed` automatically through proved
expression, statement and argument execution. The actual cache-store proof
drops five manually carried frontier facts; cache reuse and recursive preparation
use the same rule without changing contracts. Heap/value/source-frame obligations
remain explicit. This adds 81 shared-library and 58 fixture lines, with four
lines removed net from compiler proofs: 135 total new Lean lines. Typed binding
and aggregate laws still lack direct compiler-contract consumers.

The connected cache gate passed at the October 4 allocation-reuse checkpoint. It
passes in 83.35 s including setup and 4.34 s fresh self-extraction; fresh
proof/fixture checking takes 74.19 s. Only byte-identical self-program admission
is reused, not producer proof checking. Focused automation/regression fixtures
pass in 1.98 s with built shared imports. No added axioms or raised limits. This
gate was not rerun for the subsequent declared-store library addition.
The bundle remains too slow; an instrumented diagnostic identifies expensive
existing kernel checks but itself hits the normal binary-inference heartbeat
limit. A lower-overhead profile passes in 79.57 s: tactic execution and
simplification dominate its reported component times, but asynchronous and
blocked measurements do not form a wall-time partition. See the allocation-reuse
entry in `NOTES.md` for scope and evidence.

Current source/cache checkpoint (October 3): the actual public inference call
now has a structural-induction proof for accepted literal/unary trees and
mixed I32/Boolean arithmetic, bitwise, comparison and logical trees, at any
depth that fits its represented budget. It derives recursive execution and a
sound resulting cache from native syntax and any sound partially populated
table, including empty, reusable and insufficient-depth entries. Cache writes also
preserve a source fragment separated from both tables. These are tool proofs;
emitted programs carry no cache proof or typing tree. General inference and
extractor correctness remain open.

- `IRRecursiveInferenceProof.actual` closes every recursive child call by
  induction over native/source shape agreement. The independent `classify`
  function operates on the existing source AST and supplies the scalar type
  and minimum budget. A successful compiler run is not an input premise.
  Its resulting `Cache` includes the memory and semantic facts needed by the
  next query, rather than requiring that query to start from empty storage.
- `Fact` retains the exact model-inferred type and its source classification.
  Classification alone did not distinguish handles under an arbitrary
  caller-supplied `Source.ground` interpretation. The exact fact is derived
  during inference, not assumed from successful compiler execution.
- `IRTypeCacheInvariantProof.actualQueryWith` handles hits, empty slots and
  insufficient-depth entries through one rule. The closed recursive theorem
  supplies its inference callback and exact-result argument. The old
  empty-only slot helper was replaced, not retained as a compatibility alias.
- `actualFramed` additionally retains native/source agreement using
  `Updates.reads`, which preserves source bytes across every cache write.
  The caller supplies source/cache separation once, not a read-back proof
  after each write.
- Binary recursion derives both child executions by induction. The right
  child receives the cache left by the first; `Updates.trans` retains both
  sets of justified writes. Read-only source frames are premises of the one
  recursive contract, so nested binary trees can reread syntax after writes.
  The accepted binary subset contains the 16 non-logical integer operators
  and Boolean `&&`, `||`, `==`, `!=`. Integer comparisons can feed Boolean
  parents. `Source.binaryScalar` connects both domains to the existing language
  typing judgment; `actualScalar` proves the actual native decision helper.
  Pointer/nominal binary domains and call/match inference remain open.
- `core_effect` composes proved call effects, local bindings and early-return
  guards. Binary and unary traversal use it after supplying their domain
  facts and callee contracts; no manual intermediate heap/view chains remain.
  Contract lookup filters by callee identity before applying a rule. The
  tactic produces ordinary kernel-checked proofs and adds no trust assumption.
- `prepare` derives the empty-cache precondition and retained source reads
  from the actual clearing call. It needs readable represented cache storage,
  not previously justified source classifications. It does not yet prove
  the enclosing surface extraction or lowering caller.

- `IRUnaryInferenceProof.actualColdAndReuse` derives the actual public query,
  the child's two cache-word writes, the parent's two writes, and a subsequent
  parent hit. It starts from readable native unary/literal nodes and empty or
  insufficient-depth cache entries. No successful child execution, inferred
  type, or inference callback is an assumption of this closed theorem.
- `actualWith` handles unary traversal with a proved child memory effect.
  Warm-child inference specializes the same traversal to a read-only effect.
  `actualStoreWith` composes recursive writes with the parent's store;
  the earlier read-only store contract is its specialization. Both general
  composition lemmas have callback premises, discharged by their closed clients.

- `IRSourceCacheProof.actualFillPreserves` derives the parent's source-classification
  fact from a justified child entry, proves the real unary computation and
  parent cache store, and retains all earlier source facts. It covers all
  three unary operations on accepted operands. Successful inference, the
  parent's type and an intermediate compiler execution are not premises.
- `actualColdPreserves` derives literal and parent classification from their
  source shapes, connects the real four-write query, and preserves the sound
  native table. It does not assume the child is already typed in the cache.
- `IRTypeCacheInvariantProof.Updates.preserves` proves that any finite sequence
  of justified stores preserves the native table and its classification facts.
  Queries may change node and budget while retaining the same cache storage.
  `Updates.trans` composes recursive effects; `Updates.writable` retains the
  parent's storage requirements. These relations are not emitted artifacts.
- `IRTypeCacheResetProof.actualReset` proves the real Lanius clearing loop
  terminates, sets every live code to -1, and leaves memory outside that range
  unchanged. Initial bytes may be stale or corrupt. The zero-count case works
  without reading the pointer. The existing loop moved into the private
  `clear_expression_kinds` helper called by `extract_expression`.
- `IRTypeCacheInvariantProof.actualResetSound` connects that call to an empty
  table while retaining the separate depth table. No prior semantic validity
  or successful reset execution is assumed.
- `actualStoreSound` proves the public query updates its one code/depth pair,
  preserves every other entry and retains their supplied typing facts.
  Inference execution and the new entry's typing fact are explicit premises
  of this composition theorem, not proved by it.
- `actualHitSound` derives the actual cache hit and retrieves its supplied
  typing fact at the requested depth, assuming that relation is monotone.

The table carries readable full code/depth ranges and proves their separation
in either address order. Write/reset execution requires well-formed caller
cells, unique heap-block bases and no legacy array views. The standalone reset
theorem needs only represented bounds and writable/readable code storage,
not a valid initial cache. `Table.Sound` is parameterized by a source-node,
type and depth relation; it does not define correctness as compiler success.
**That relation has not yet been instantiated and proved for the complete
source language and binding scopes.** Empty-table soundness alone says nothing
about a program's typing.

`Source.Meaning` now wraps `SurfaceElaboration.ExprClassifies`, using the existing
source AST, ground types and operator typing rules. The earlier `ExprLowers`
invariant demanded too much of inference: it assigns I32 before parsing and
range-checking integer text. `ClassificationTests.magnitudeCannotLower` proves
that the child magnitude in `-2147483648` cannot lower as positive I32, while
`negativeMinimumLowers` proves the complete expression can lower. Classification
therefore does not imply literal validity. `ExprClassifies.lowerLiteral` requires
the separately checked literal value before deriving real `ExprLowers` evidence.
This corrects the inference contract; it does not replace the required lowering
correctness theorem with a weaker one.

The classification relation covers literals, unary expressions and typed
binary expressions. The closed recursive compiler theorem currently covers
same-I32 binary operands, not general Boolean, pointer or nominal binary typing.
The caller supplies a source view at a fixed scope and native/source shape
agreement. I32, Bool and String meanings are fixed. Existing cache entries must
carry exact model types and source classifications. The theorem preserves those
facts and derives each new entry from source shapes. The real reset establishes
the same invariant without requiring semantic validity of previous entries.
Literal text is arbitrary: neither the native shape relation nor classification
checks spelling or value bounds. Those remain lowering obligations. Source/cache
separation suffices to retain the shape relation after writes. Scope changes,
other expression forms and equality with the emitted body remain unproved.
The named proposition boundary and existing trust policy are retained.

Remaining composition obligations: derive resource and native/source facts at
the outer `extract_expression` call; extend recursion to other binary domains,
calls and matches; preserve source/scope facts through match bindings; then connect
inference to recursive IR lowering. Warm-cache subtrees are now covered for the
literal/unary/integer-binary subset. Rejection and depth exhaustion have runtime
coverage but no closed recursive public-query theorem. Do not describe this as
completed general inference or value validation.

The current focused checkpoint uses the GPU-bootstrapped `extractor-binary`
and `compiler-binary`. Connected cache proofs and fixtures pass in 65.71 s,
plus setup and 4.12 s self-emission, reusing shared libraries and admission of
the byte-identical self-program. This larger scope retains the cases below and
adds 96 binary queries, each followed by a source-free root reuse. It covers
all 16 accepted integer operators, separate/shared leaves, cold caches and
either primed subtree. Ten direct Lean/x86 source fixtures and five invalid
operand fixtures also pass; the Lean fixture bundle checks in 1.51 s.
These are tool-proof and regression timings, not an end-to-end trusted
extractor/compiler proof or a demonstrated proof-writing speed multiplier.
Evidence: `target/verified-compiler/binary/cache-current.log` and
`operand-current.log`.

The preceding GPU bootstraps were `extractor-cache` and `compiler-cache`. Self-emission
took 4.19 s and fresh Lean admission 12.12 s at that unchanged-source checkpoint.
The current cache contracts check in 40.52 s (48.22 s including setup and 3.90 s
self-emission), with shared libraries and admission of the byte-identical
self-program reused. All 390 existing native-memory cases pass: 39 hits,
20 literal fills, 10 whole-table updates, 48 resets, 24 Void/depth failures,
144 unary decisions, 33 warm-child recursive queries and 72 cold-child cases.
The latter cover all three operators, integer/Boolean/string literals,
empty and insufficient-depth entries, minimum and maximum parent depths,
rejection without a parent store, and reuse without readable syntax.
There are 78 additional reset/recursive-source cases through 25-node trees,
with minimum, excess and insufficient budgets, plus 402 source-free entry
reuses. They check every stored type/budget, source bytes and caller state.
Thirty mixed-cache sequences prime a leaf, middle subtree or whole root, then
run the root with reusable or insufficient stored budgets. Excess query budget
makes accidental recomputation observable in retained child-depth entries.
Depth-exhaustion rejection is tested here, not proved by the accepted-tree
theorem.
All audited theorems use only
`propext`, `Classical.choice` and `Quot.sound`.
Before connected integration, the generalized recursive module checked against
hash-verified admitted dependencies in 1.62 s. A larger exploratory fixture set
passed 244 mixed-cache sequences; the final gate retains the 30 focused cases
above, not the redundant cross-product.
The previous source-composition module checked in 1.25 s. These isolated
module timings do not include dependencies or fresh program admission. Shared
classification boundary regressions check in 0.65 s. Earlier effect-rule,
read-frame and call-rule regression evidence remains 1.27/0.88 s.

The preceding connected lowering gate passed against this self-program: 76.11 s
for proofs/fixtures, 85.10 s including setup. It retains the earlier literal,
decimal and writer contracts plus 60 recursive-expression cases. The broader
producer/builder and printer-connection gates still refer to the older
`decimal` checkpoint. The source/cache module is now included in lowering and
full-producer gates, but only the focused cache gate was rerun for this proof
extension; do not report those broader gates as freshly checked.

Five fresh source programs agree in Lean and x86, including mixed-type match
payloads with the same binding name and restoration of an outer binding.
Five invalid programs reject in both extraction modes and shared x86 lowering,
including a Bool payload passed to an I32 parameter. The Lean source-fixture
check takes 1.03 s. These examples are regression tests, not a general binding
scope theorem.

Proof-size accounting: the focused program-specific bundle is 1,845 physical
lines, up 61 from the empty-cache recursion checkpoint's 1,784. The recursive
module is 257 lines (+29), including its source model, native agreement,
initialization, induction and framing. The table invariant is 333 lines (+32); source/cache
composition remains 144 and query definitions 61. Shared classification and
the literal-lowering bridge remain 30 lines. Recursive runtime fixtures are
113 lines (+20). No shared foundation or Lanius implementation grew in this step.
Counts include theorem interfaces, helpers and native representation facts.
Unary inference remains 285 lines, about 4.4x its 65 associated source lines;
that ratio excludes these separately counted dependencies and is not the ratio
for the whole bundle. The store module remains 207 lines and literal inference
138. No implementation lines were added or padded to improve the ratio.
Cache/reset runtime fixtures remain 123/39 lines and operand fixtures are 190;
classification/value regressions remain 42.
Reset is still ~19x its seven implementation lines, above the ~5x target.
Do not copy its remaining loop scaffolding into further functions: reuse the
new rules and investigate a bulk-fill boundary if another such loop is needed.

Evidence under `target/verified-compiler`: `cache-admission.log`,
`cache/warm-connected.log`, `cache/warm-inference.log`, `cache/warm-fixtures.log`,
`cache/general-query-base.log`, and the preceding
`cache/recursive-connected.log`, `cache/recursive-inference.log`,
`cache/recursive-frame-base.log`, `cache/recursive-fixtures.log`,
the preceding `cache/recursive-source.log`, `cache/recursive-source-reuse.log`,
`cache/classification-tests.log`, and the preceding unchanged-source
`cache/source-fixtures.log` and `cache/lowering.log`.
Reproduce the focused checks with:

```sh
timeout -k 5s 105s bash verified_compiler/tests/ir_producer_check.sh \
  target/verified-compiler/extractor-cache cache target/verified-compiler/cache
(cd formal && timeout -k 5s 105s lake --no-cache build +Lanius.SurfaceElaboration.ClassificationTests)
timeout -k 5s 105s bash verified_compiler/tests/operand_check.sh \
  target/verified-compiler/extractor-cache target/verified-compiler/compiler-cache
timeout -k 5s 105s bash verified_compiler/tests/ir_producer_check.sh \
  target/verified-compiler/extractor-cache lowering target/verified-compiler/cache
```

Previous unary-inference checkpoint (October 2): the Lanius implementation now
separates the unary typing decision (`unary_kind`) from traversal. It accepts
Bool for `!` and I32 for unary `+`/`-`, rejects other known types, and preserves
existing failures. The invalid-operator guard remains before child traversal.
The normal extraction and x86 paths share this code.

The source-connected contracts are:

- `IRUnaryInferenceProof.actualDecision`: the actual decision matches a
  constructor-based typing specification for all three unary operators, all
  three expression statuses and every represented TypeRef, including all
  nominal IDs. Its heap and caller frame are unchanged.
- `IRUnaryInferenceProof.actual`: the actual uncached unary query implements
  that rule from readable native syntax and a readable child cache entry. The
  child query is derived, not assumed. Both accepted and rejected child types
  are covered.
- `IRUnaryInferenceProof.actualFillAndReuse`: for an accepted operand and a
  missing parent entry, the public query computes the result, writes exactly
  its type/depth words, and reuses it on the next public query. No successful
  inference or intermediate execution is a premise.

The store/read-back proof moved from the literal module into a shared cache
composition lemma; literal and unary clients both discharge its inference
premise. This is real proof reuse, not a new emitted certificate or trust
assumption. The literal module shrank from 211 to 130 physical lines, the shared
store module has 159, and the expanded unary module has 191. Including all
program-specific type-reference, result, error, guard, hit and store dependencies,
the focused bundle is 827 lines (170 more than the previous checkpoint).
The unary module covers the decoder, 14-line typing decision, traversal branch
and public wrapper; these are roughly 60 source lines (~3.2x for that module,
not the whole dependency bundle). Runtime fixtures are separate: 146 operand
lines and 81 cache lines. No shared automation was added for this extension.

Scope and assumptions: the child cache is already populated and its stored
depth is sufficient. The parent depth is one larger than the queried child
depth. Native syntax/cache slots are readable, query bounds are represented,
and caller cells are well formed. The write theorem additionally needs writable,
nonoverlapping parent cache words, unique heap-block bases and no legacy
cell-backed array views. Its exact-write effect preserves other bytes; callers
must establish separation from protected storage. The read-only inference
theorem does not need those write-specific assumptions.

These contracts do **not** yet prove cache freshness relative to source and
binding scope, cold recursive child inference, general binary typing, recursive
IR semantic preservation, or the complete extractor/backend. The reusable store
callback is currently read-only; cold children require composing their cache
writes with the parent writes. No execution premise may replace that obligation
in a claimed closed recursive theorem.

Validation uses freshly GPU-bootstrapped `extractor-unary` and `compiler-unary`.
Fresh self-emission took 4.06 s and admission 12.23 s. The connected cache gate
passes in 45.29 s (55.01 s including setup), reusing shared libraries and the
byte-identical admitted self-program, while freshly checking the contracts.
It includes 39 cache-hit cases, 20 literal fill/reuse cases, 24 Void/depth cases,
144 unary type/status decisions and 33 public unary-query cases. Successful
queries check exact cache contents and reuse with unreadable source storage;
rejections preserve cache/source bytes and caller state.

Four freshly emitted programs have Lean return-value proofs and matching x86
execution tests: normal Void calls, Choice/match, recursive Boolean expressions,
and scalar unary/record/match expressions. The Lean fixture check takes 0.99 s.
Direct and checked extraction reject four invalid operand programs (exit 30);
x86 compilation rejects them in shared lowering (exit 10). All newly audited
theorems use only `propext`, `Classical.choice` and `Quot.sound`.

The connected lowering gate also passes against the current self-embedding:
75.61 s for proofs/fixtures, 84.95 s including setup. It includes the earlier
literal/decimal/writer contracts and 60 recursive-expression cases alongside
the new cache/unary contracts. This is a general tool-proof check, not a
per-program admission cost. The full producer/builder and printer-connection
gates still refer to the older `decimal` checkpoint; they are not current checks
of `unary`.

Evidence: `unary-admission.log`, `unary/cache-store.log` and
`unary/fixtures.log`, plus `unary/lowering.log`, under
`target/verified-compiler`. Reproduce with:

```sh
timeout -k 5s 105s bash verified_compiler/tests/ir_producer_check.sh \
  target/verified-compiler/extractor-unary cache target/verified-compiler/unary
timeout -k 5s 105s bash verified_compiler/tests/operand_check.sh \
  target/verified-compiler/extractor-unary target/verified-compiler/compiler-unary
timeout -k 5s 105s bash verified_compiler/tests/ir_producer_check.sh \
  target/verified-compiler/extractor-unary lowering target/verified-compiler/unary
```

Previous recursive-operand checkpoint (October 2): shared inference now rejects
Void in unary and binary operand positions. Previously, a child's `Known Void`
result passed through as the parent's type and could be cached. The tested
source programs already failed later; this repairs the internal inference
contract and moves rejection into the shared frontend. Ordinary void-returning
calls still work. Both x86 compilation and Lean extraction use the fix.

`IRExpressionKindProof.actualOperand` proves the actual Lanius helper for every
expression status and TypeRef: valid value types pass through, Known non-value
types become Unsupported, and existing Invalid/Unsupported failures remain
unchanged. The helper is read-only. Existing result construction moved out of
the cache module into this shared result-contract module, without aliases.

`IRUnaryInferenceProof.actualVoid` proves the actual uncached unary query
rejects a cached Void operand for positive, negate and not. It starts with
readable native AST/cache slots and derives the recursive child query, helper
execution and rejection; successful child execution is not a premise. It
requires represented arena bounds, a positive child depth with the parent
budget one larger, a sufficient stored depth, and well-formed caller cells.
The resulting pure frame preserves heap, world, views and caller locals/cells.
No disjointness or unique-block assumption is needed on this read-only path.
This theorem does not establish that the child's cached type matches its source
semantics or current binding scope. General recursive/binary inference, cache
reset/freshness, and the connection to recursive IR semantics remain open.

The two result/unary proof modules contain 167 physical lines including
representation helpers and audit commands, for roughly 52 lines on the covered
Lanius helper/unary-rejection paths (~3.2x). This is a matching-path ratio, not
the size of all reused dependencies. The full focused bundle has 657 lines of
program-specific contracts including existing type-reference, cache and guard
proofs. The new runtime fixture is 75 separate lines. Shared automation now
transports heap reads across proved pure frames and composes skipped helper-call
branches; it neither assumes callee results nor emits per-program evidence.
The caller proof keeps the unary operator symbolic instead of repeating the
same proof three times. It checks within Lean's default heartbeat limit.

Validation uses freshly GPU-bootstrapped `extractor-operand` and
`compiler-operand`. Self-emission took 4.94 s and fresh self-admission 15.71 s.
The connected cache proof/fixture gate takes 33.56 s (43.77 s including setup),
reusing shared libraries and the byte-identical admitted self-program. It
includes 39 cache hits, 20 literal fill/reuse cases and 24 operand/depth cases.
The new cases cover Void on either binary side, all three unary operators,
exhausted child budgets, unchanged source/cache bytes and caller state, and
rejection before output access. They detect the old implementation.

The focused source gate proves that ordinary void calls, Choice/match and
recursive Boolean expressions return the expected values in fresh Lean output
(0.98 s) and tests their x86 execution. Direct/checked extraction rejects both
void-operand fixtures; x86 compilation rejects during shared lowering (exit 10)
instead of later backend validation (exit 11). Shared automation regressions
pass. The audited new theorems use only `propext`, `Classical.choice` and
`Quot.sound`; no `native_decide`, `sorry` or additional axioms were introduced.

The expanded connected lowering gate also passes against this current
self-embedding: 69.87 s for the proofs/fixtures, 77.82 s including setup. It
includes the preceding literal/decimal/writer contracts, 60 recursive-expression
cases, all cache cases and the new operand proof/tests. This is a general tool
proof check, not a per-program admission cost. The full producer/builder and
printer-connection gates still refer to the older `decimal` checkpoint below;
do not report them as freshly checked against `operand`.

Evidence: `operand-admission.log`, `operand/cache.log`, `operand/fixtures.log`
and `operand/pure-read.log`, plus `operand/lowering.log`, under
`target/verified-compiler`. Reproduce with:

```sh
timeout -k 5s 105s bash verified_compiler/tests/ir_producer_check.sh \
  target/verified-compiler/extractor-operand cache target/verified-compiler/operand
timeout -k 5s 105s bash verified_compiler/tests/operand_check.sh
```

Previous inference-cache checkpoint (October 2): the actual Lanius query now has
a connected literal compute/store/reuse proof. `actualFillAndReuse` in
`tests/direct_ir_type_cache_fill.lean` starts with native AST storage and an
empty or insufficient-depth cache entry. It derives the integer, Boolean or
string type, proves the two cache writes, establishes readable cache contents,
and proves a second query returns that type without changing memory. Neither
successful inference nor a successful intermediate call is a premise.

The general hit contract covers every valid primitive and nominal type. Its
decoder theorem covers the full valid nominal-ID ranges, not only sampled IDs.
The cold proof requires represented query bounds, readable source/cache slots,
disjoint cache words, well-formed caller cells, unique heap-block bases and no
legacy cell-backed array views. Its exact two-write effect preserves other
bytes and allocation metadata; a caller must still establish separation from
any protected source/output storage. The cold proof covers literal nodes only.
Recursive inference, cache reset and validity across binding scopes remain open.

The cache gate passes 39 hit cases and 20 empty/insufficient-depth fill/reuse
cases. Reuse tests deliberately supply unreadable source-node storage; misses
start from native AST bytes and check both cache words, neighboring slots,
unchanged AST bytes and caller locals. The fresh connected cache proof/fixture
check takes 34.14 seconds, reusing shared libraries and admission of the
byte-identical `expression` self-program. Shared automation regressions pass
in 4.31 seconds, including their incremental build. All audited cache theorems
use only `propext`, `Classical.choice` and `Quot.sound`.

The two cache contract modules total 282 physical lines, including models and
the read-back bridge; the decoder extension adds 36. That is about 4.7x the
68 source lines for the query, literal branch, decoder and two small helpers.
This is the incremental ratio, not a full dependency-graph ratio: the existing
type-code, context/error and native-memory contracts are reused. Counting the
entire type-reference and context/error modules gives 504 program-specific
lines for this checked bundle, including their unrelated existing contracts.
The cache runtime fixture is 81 separate lines. Shared automation now retains
frames through helper-call branch conditions and accepts local specializations
of proved contracts; it does not interpret helper bodies or assume their results.

No production Lanius or emitted representation changed in this checkpoint.
The producer harness now explicitly rebuilds its pure-proof dependency before
using it. The expanded connected lowering artifact also passes: 81.48 seconds
for its proofs/fixtures, 92.19 seconds for the whole gate. It includes the
earlier integer/negative-literal and 60 recursive-expression cases alongside
the new cache contracts; this is a larger proof scope, not a per-program
emission/admission slowdown. Logs: `expression/cache-fill.log`,
`expression/pure-branches.log`, `expression/lowering-cache.log`.
The cache scope is included in the normal lowering and full producer gates:

```sh
timeout -k 5s 105s bash verified_compiler/tests/ir_producer_check.sh \
  target/verified-compiler/extractor-expression cache target/verified-compiler/expression
```

Previous recursive-lowering checkpoint (October 2): `expression` now owns
type-inference validation. Previously its type query rejected `-true`, but the
lowerer still wrote two IR nodes and returned success. Outer callers normally
checked first; this was a broken internal contract, not evidence that a full
source file was accepted. The entry point now rejects failed inference before
IR writes. Its outer surface wrapper no longer repeats that query. Exhausted
depth also rejects before reading a source node.

`IRExpressionValidationProof.actualBounds` proves termination and a pure
caller/memory frame for every exhausted depth or out-of-range root, even with
unreadable source/output descriptors. The module is 34 lines including context
and call models, for the seven-line entry/guard path (~4.9x). It reuses the
33-line error-contract module, whose existing definitions and proofs moved out
of integer lowering without aliases. The 80-line fixture checks 60 recursive
cases: unary/binary Boolean operations, invalid operands/operators, cold and
warm type caches, depth bounds, annotations, no IR writes on rejection, and
rejection with an invalid output descriptor. It fails against the old embedding.
These tests do not replace the general recursive-lowering proof.

Both Lanius tools were freshly GPU-bootstrapped (`extractor-expression` and
`compiler-expression`). The new self-module checks in 13.74 seconds. The
connected lowering proofs/fixtures check in 48.84 seconds (59.69 seconds for
the gate), reusing shared libraries and admission of the byte-identical current
self-program. All audited theorems use only standard logical axioms. The new
nested Boolean/mutation program returns 37 in Lean and x86; both tools reject
the invalid unary/binary source fixtures. The requested Choice example still
has a fresh termination/return-7/frame proof (1.41 seconds) and an x86 executable
returning 7. These are not general extractor or backend preservation proofs.

Current evidence is under `target/verified-compiler/expression`:
`validation-final.log` (3.12-second focused proof/test check), `old-regression.log`, `self-admission.log`,
`lowering-final.log` and `choice-proof.log`. Reproduce the affected check with:

```sh
timeout -k 5s 105s bash verified_compiler/tests/ir_producer_check.sh \
  target/verified-compiler/extractor-expression lowering target/verified-compiler/expression
```

The full producer/builder and printer-connection gates below last ran against
the preceding `decimal` self-embedding. They have not been rerun against this
new embedding. Cache reuse fails closed on changed inputs; checks also pin the
self-program source in the producer directory and the exact admission cache.
General inference/cache soundness, recursive lowering, printer setup/meaning,
native refinement and the explicit trusted-output boundary remain open.

Previous source-to-Lean checkpoint (October 2): ordinary negative integer
literals now have a connected proof from source digits/token storage through
the actual lowering writes and allocating tree builder to the existing Lean
expression printer. The builder input and printed payload follow from those
writes; neither a prebuilt valid tree nor successful intermediate calls are
premises. The proof covers every readable, valid nonempty span that decodes to
a magnitude below 2147483648, with writable IR storage and allocation budget.
It establishes exact expression text, not yet general semantic preservation.

The final printing contract requires the normal protected native input/output
environment. Constructing that printer environment, lexer/token provenance,
Lean notation semantics and recursive source lowering remain separate
obligations. The signed minimum and failure paths have runtime coverage in
this connected pipeline; their earlier lowering proofs do not yet constitute
a general source-to-printer theorem.

The source-to-tree artifact passes in 86.80 seconds (95.50 seconds for its
gate). The fresh printer and connection check passes in 56.48 seconds (63.81
seconds for its gate), reusing that exact checked producer artifact. A
source/artifact digest guards this test cache; it is not an emitted compiler
certificate or the proposed trusted-output mechanism. Both gates compare
fresh self-output with the admitted self-program. All audited theorems use
only `propext`, `Classical.choice` and `Quot.sound`.

Twenty-seven runtime cases start from source/token bytes and exercise ordinary
negatives, the signed minimum, malformed contents, exact/short output buffers
and exhausted allocation budget. They check exact text and retained input,
IR, endpoint and caller state. The two connection modules add 172 lines,
including their representation bridge; the fixture adds 93. The shared native
write rule now carries heap-frontier validity into allocation. The existing
byte-output proof uses forward scope composition to retain its full contract.
This reuses the decoder, builder and recursive printer proofs rather than
duplicating their execution traces.

Evidence: `decimal/lowered-tree-connected.log`,
`decimal/negative-extraction.log` and `decimal/byte-forward.log` under
`target/verified-compiler`. To recheck that connection against the current
embedding, first run the producer gate with scope `all`, then:

```sh
timeout -k 5s 105s bash verified_compiler/tests/literal_extraction_check.sh \
  target/verified-compiler/extractor-expression target/verified-compiler/expression
```

Earlier integer-lowering checkpoint (October 2): the actual self-emitted
decimal decoder, token-span caller, integer branch of `body_literal.emit` and
negative-literal caller have connected execution proofs. For readable, nonempty,
in-range source spans, they prove radix-10 accumulation, overflow/malformed-content rejection,
termination, exact IR payload, annotation reset, cursor advance and memory
framing. The special magnitude 2147483648 is retained by the decoder for unary
minus but rejected by positive literal lowering. The actual negative caller
writes a unary-negation node and a positive I32 child for ordinary magnitudes;
2147483648 produces one signed-minimum node. Both appends, the child's annotation
write and the surviving node payloads are proved, not assumed. Bad decoder span
bounds reject before any read. Invalid contents reject before touching even an invalid output
descriptor. Token-row provenance and lexical separator placement remain caller
obligations; this is not yet complete frontend correctness.
Success requires writable output storage (two consecutive slots for ordinary
negative literals, one for positive literals or the signed minimum), represented
counts, well-formed caller cells, unique heap-block bases and no legacy cell-backed array views. The native
read/write and host behavior are those of the Core model, not a proved x86 runtime.

The Lanius decoder now uses a typed accumulator plus a cursor instead of four
mutable locals. Shared assignment and scope rules carry the frame through its
helper calls. No new typing tree, JSON, certificate, axiom, native-computation
dependency or increased proof limit was introduced.

The negative caller keeps the existing source-shaped IR. Shared expression
rules retain effects through negation and short-circuit guards. Local-lookup
automation uses a proved fresh-cell frame and an actual execution contract;
execution alone cannot justify preservation. These rules remove handwritten
lookup transport and repeated call syntax from the connected proof.

The connected producer/builder artifact passes in 74.55 seconds (81.96 seconds
for the whole gate). Shared libraries and admission of the byte-identical new
self-program are reused; all selected contracts and fixtures are checked
afresh. Fresh self-admission separately took 13.71 seconds. The new fixtures
cover 11 decoder boundary cases, seven source-to-IR cases and a kernel theorem
connecting actual ASCII 55 and its token row to stored integer 7. The standalone
negative fixture adds nine boundary/rejection cases and a kernel theorem
connecting that same source byte to a stored unary node, integer child and I32
annotation. Shared effect/local regressions pass in 7.50 seconds including
their incremental library build. The standalone Lanius fixture passed before
and after the refactor: 264 decimal roundtrips,
130 single-word inputs, overflow and invalid-span cases. Shared local-pair and
effect checks pass. Audited theorems depend only on `propext`, `Classical.choice`
and `Quot.sound`.

The requested Choice/Some(7)/match program emits readable Lean directly. Its
fresh module checks in 1.03 seconds; a 1.47-second proof establishes termination,
return value 7 and preservation of caller memory. A freshly GPU-bootstrapped
Lanius x86 compiler also produces an ELF that returns 7. This is a representative
execution proof and native test, not the general extractor/backend theorem.

The four decoding/caller proof modules total 627 physical lines, including
models, helpers, representation bridges and the earlier Boolean caller. Their
matched source declarations/functions/branches total 108 lines: about 5.8x.
That positive-decoder checkpoint added 65 shared-rule lines excluding separating blanks; fixtures and
generated data are separate costs. Existing writer/storage contracts are reused
and remain part of the larger proof dependency; this ratio does not describe
the whole compiler.

The negative-caller module adds 234 lines, down from its first 260-line proof,
for the 21-line caller and six-line minimum test: about 8.7x. The new unary-writer
contract and disjoint-slot helper add 23 and 14 lines respectively, in addition
to the reused decoder/storage/annotation contracts. The concrete negative
fixture is 88 lines. This remains above the compactness target: storage-effect
composition is still too manual to copy wholesale into recursive lowering.
Shared effectful-expression/local-lookup rules and their tests are additional
costs, not hidden inside that program-specific ratio.

Evidence is under `target/verified-compiler/decimal`: `negative-final.log`,
`negative-shared.log`, the earlier positive-only `frontend.log`,
`self-admission.log`, `choice-admission.log`, `choice-proof.log` and
`shared-tests.log`. The corresponding full gate for the current embedding is:

```sh
timeout -k 5s 105s bash verified_compiler/tests/ir_producer_check.sh \
  target/verified-compiler/extractor-expression all target/verified-compiler/expression
```

The new executable/cache are explicit here. The older default extractor and
`scoped-expressions` admission were not silently replaced; source mismatches
still fail closed. Strings, recursive expression lowering, malformed token/span
callers, insufficient-output/partial-write paths, catalog correctness, general
extraction preservation/rejection, x86/runtime refinement, verified self-hosting
and the trusted-output boundary remain open.

Earlier frontend-writer checkpoint (October 2): the actual self-emitted
`expression_value`, `expression_call` and `expression_match` functions have
native production contracts. They prove exact event selection/payloads,
annotation reset, cursor advance, termination and memory/caller framing.
Call and match header rejection preserves a pure frame without any storage
premise. Literal dispatch covers every represented i32 and Boolean payload.

`Produces` names this slot contract; shared scope/effect rules compose its
proved heap relation through calls, guards, payload bindings and returns.
`actualAllocateProduceRecord` now consumes it instead of only a store codec.
The closed `allocateLiteralRecord` theorem supplies the actual literal writer,
derives its storage from fresh allocation, records I32/Bool as appropriate,
reads back both results and retains an old canary for arbitrary counts/slots.
`IRLiteralLoweringProof.actualBoolean` then proves the Boolean branch of the
actual `body_literal.emit` caller. It uses the parsed node operator directly,
for either Boolean and every represented token ID, without source/token buffers.
`allocateBooleanLoweringRecord` connects that caller to allocation and its Bool
annotation. Integer/string branches and recursive expression lowering remain open.

The fresh connected producer/builder artifact passes in 44.09 seconds; the
whole gate takes 51.94 seconds. Only shared libraries and admission of the
byte-identical self-program are reused. Current source closure, self-output,
contracts and fixtures are checked afresh. All audited theorems use only
standard logical axioms. There are 120 new Core-evaluator writer/caller cases, alongside
the previous storage/allocation cases. Evidence: `ir-producer/producer-frontend.log`,
`lowering-writer.log` and `scoped-effect-tests.log` under `target/verified-compiler`.

The writer contracts/helpers occupy 107 physical lines for 24 matched Lanius
function lines. The Boolean caller adds 50 for its 9-line source path (header,
operator binding and Boolean branch, not the whole function). Including net
growth of 22 lines in the store interface, this is about 5.4x together.
The 104-line shared effect module, call-tactic changes and fixtures
are additional costs, not hidden proof compression. No production source,
extracted representation, trust dependency or proof limit changed.

These are Core-model contracts, not native x86/runtime refinement. The match
writer checks result kind and positive arm count, but not scrutinee identity
or arity-overflow/tree validity; frontend callers still owe those facts.
Catalog lookup, argument typing, exhaustiveness, recursive source meaning,
complete catalog append, general extraction preservation/rejection, verified
self-hosting and the trusted-output boundary remain open.

Current native-event checkpoint (October 1): all 64 current `Event` variants
have native store/read-back contracts. This includes all eleven aggregate
record layouts, nested TypeRefs, slice-kind enums, scalar payloads and nullary
headers. Fields range independently over represented i32 values and all TypeRefs.
Raw string slices use actual bounded 64-bit pointer/length descriptors, not the
empty surface-syntax Slice type. These are storage contracts: they do not prove
that a referenced function/type exists, that string referents remain valid, or
that an event has its intended source meaning.

Shared `NativeStoreSpec.record` proves the actual indexed field-store loop once
for arbitrary arity and ordered widths, including read-back and memory framing.
`native_store` derives field offsets/widths from actual declaration metadata and
builds kernel-checked applications of that rule. Call and match codecs have
one-line proof bodies; no per-event byte-decoding proof or emitted typing tree
is needed. `NativeStoreSpec.rawSlice` proves exact descriptor copying, with
explicit word-fit bounds and no assumption about successful writes.

`actualAllocateAppendRecord` now accepts any proved event codec, and
`allocateAppendRepresented` discharges that premise for every current event
schema, arbitrary represented counts/positions and valid result annotations.
Its concrete initial heap includes old nonzero storage. The proof executes the
real three initializers and both writers and retains that storage. A kernel
coverage check accounts for every current Event ordinal exactly once; 512
Core-evaluator cases check both slots, mixed fields, signed extremes, nested
enums, maximum-width slice words, annotation reset and neighboring bytes.
Focused shared tests reject malformed arity, nominal identities, undersized
slots, exhausted recursion depth, unsupported slices and truncated descriptors.

The fresh connected producer/builder artifact passes in 40.13 seconds; the
whole gate takes 47.59 seconds. Shared libraries and admission of only the
byte-identical self-program are reused. Self-output/source closure and current
contracts/fixtures are checked afresh. Axiom audits list only `propext`,
`Classical.choice` and `Quot.sound`. Evidence: `ir-producer/producer-aggregate.log`
and `ir-producer/aggregate-shared-tests.log` under `target/verified-compiler`.

The new schema contract/helper module is 127 physical lines for 114 lines of
matched native payload declarations. New shared rules/automation add 314 lines
plus four lines in NativeStore; shared tests add 46 lines. Program fixtures add
90 lines across the new codec tests and extended writer/allocation tests.
The prior allocation/writer function proofs remain around 10x their matched
source size; this checkpoint adds coverage rather than demonstrating compression
of those proofs. Shared foundations, tests and generated data remain real costs.

Frontend production of valid shapes, annotations, catalog references and source
meaning remains open, as do complete catalog append, general extractor
preservation/rejection, native runtime/x86 refinement, verified self-hosting and
the trusted-output boundary. No production source, output format, trust policy,
native-computation dependency or proof limit changed.

Earlier allocation/writer checkpoint (October 1):
`IRRegionAllocationProof.actualOwned` connects the three actual
`body_catalog.append` initializers: byte-count calculation, host allocation,
and region construction. It derives the constructor's storage facts, every
initialized annotation, ownership transfer, termination and preservation of
old memory reads. Inputs are a represented positive count, representable
size/address arithmetic, available budget, well-formed caller cells, heap
frontier/uniqueness invariants and no legacy array views. Successful execution,
precomputed byte counts and valid fresh descriptors are not input assumptions.

`IRRegionPipelineProof.actualAllocateAppendRecord` then derives the writer's
slot from that allocation and connects real append and result-type recording.
It covers every in-range position, signed i32 payload and valid TypeRef, retains
caller cells and all old readable memory, and supplies reusable native snapshots
of the event and annotation. `InitializersRun` names the three proved execution
relations and their bindings; it adds nothing to extracted output. Shared
snapshot, layout and fresh-write rules replace repeated byte-decoding/frame work.

The real size helper's rejection and allocation initializer's exhaustion paths
also check. Tests cover rounded frontiers, exact/insufficient budgets, count
boundaries, zero-size allocation identity, invalid alignment, and 210 complete
allocation/writer cases across capacities 1, 2, 3 and 8. They check every slot,
signed extremes, Void/nominal types, neighboring slots and retained old storage.
The general kernel theorem covers arbitrary counts and positions, not only these
examples. Focused shared-memory and slice tests pass.

The final fresh connected producer/builder artifact checks in 37.98 seconds;
its whole gate takes 45.75 seconds. Shared libraries and admission of only the
byte-identical self-program are reused; current self-output and source closure
are compared, and all producer contracts/fixtures are checked afresh together.
Successful axiom audits list only standard logical axioms. This is not a
whole-goal performance claim.

The two new contract/helper modules are 213 and 114 physical lines, with 140
fixture lines; the shared allocator module and tests are 125 and 39 lines.
Including the existing constructor, append, annotation and TypeRef helpers,
this connected program-specific proof scope is 921 lines for 91 physical lines
of matched source functions/initializers: about 10.1x, still above the 5x target.
Shared foundations, fixtures and generated self-program data are separate costs,
not erased by reuse. Keep reusing the storage contracts rather than copying them.

These results use the Core host-call model. They do not prove native OS allocator
or x86 execution refinement, the whole catalog append (guards, copying, tree
construction and catalog writes), or general frontend/source-meaning closure.
Aggregate event codecs, extractor preservation/rejection, verified self-hosting
and the explicit trusted-output boundary remain open. No production Lanius source,
output representation, trust policy, native-computation dependency or proof limit
changed.

Earlier region-construction checkpoint (October 1): `IRRegionProof.actualRegion`
proves the actual self-emitted `ir::body_events::from_raw_parts` call on positive,
aligned, bounded storage with zero annotation tags. It derives both native
slice descriptors, executes every initialization store and increment, terminates,
transfers ownership, and preserves allocation bytes, caller cells and world/views.
The input describes backing memory; it does not assume successful construction
or valid IR. This covers the fresh-allocation domain, not resetting arbitrary
reused storage. Deriving these memory facts from the actual allocator/caller,
including its runtime refinement, remains open.

`constructAppendRecord` connects real construction, append and type recording
on owned storage with nonzero padding. Its kernel proof covers every signed i32
payload and valid TypeRef, derives each writer's preconditions from the preceding
operation, and preserves neighboring event/annotation bytes. Core-evaluator
tests also cover capacities 1, 2, 3 and 8, all initialized slots, descriptor
addresses, unchanged bytes and ownership transfer. This is not x86 refinement.

Shared proof automation now composes proved loops and returned records in
source order. Contract search matches syntax before comparing states; expression,
argument and statement tactics stay within their own relations. Argument rules
are selected from list syntax, and aggregate rules run before Boolean-guard
search. This avoids unsuccessful proof search expanding unrelated local bindings
or evaluator definitions. It adds no emitted tree and assumes no execution result.
Focused shared tests cover loop/record composition, mismatch rollback and refusal
to invent memory-write or nonterminating-loop contracts.

The fresh region/pipeline artifact passes in 13.78 seconds. The full connected
producer/builder artifact passes in 34.62 seconds, with a 43.82-second whole gate,
including the new proofs and fixtures. The preceding, smaller artifact took
60.55 seconds. These are fresh program-specific checks with shared infrastructure
and admission of the byte-identical self-program reused, not a controlled
benchmark or whole-goal speedup. Successful audits list only standard logical
axioms. No production Lanius code, output format, trust policy or proof limit changed.

The region contract/helper module is 225 physical lines for the 18-line constructor
(about 12.5x), plus 118 fixture lines. The new shared borrow/read and same-byte-store
foundations are 96 and 35 lines; arithmetic, counted-loop and syntax-selection
rules extend existing modules. This still misses the roughly 5x size target.
Reuse and shorten these interfaces rather than copying their setup into each
frontend proof. Remaining event layouts, general frontend/source-meaning closure,
extractor preservation/rejection, runtime/x86 refinement, verified self-hosting
and the explicit trusted-output boundary remain unfinished.

Current result-annotation checkpoint (October 1): the actual self-emitted
`record_result_type` function now has contracts for its write, out-of-bounds
rejection, invalid-type rejection, and annotations-disabled success paths.
The write accepts every valid `TypeRef`, including `Void` and nominal payloads;
it proves read-back, caller-cell preservation, unchanged world/views, and no
byte changes outside its 16-byte slot. Rejected or disabled calls retain a
read-only frame and need no backing buffers. The accepted write needs only
the represented annotation slot, not event storage or an assumed successful
store. `actualValidResult` proves the real type-validation helper separately.

Shared `core_stmt_forward` composes operations using their proved output
states, instead of inferring intermediate states from the final heap. Both
the append and annotation proofs use it. It does not execute the program,
rerun typechecking, or infer unproved write effects. Focused tests cover
consecutive effects, restored local scope, early return and refusal to invent
a memory-write contract. The append module shrank from 143 to 129 lines;
this is a reuse improvement, not a 10x proof-size reduction.

The fresh connected producer/builder/annotation artifact passes in 60.55
seconds; its whole gate takes 67.91 seconds. The annotation-only artifact
passes in 11.27 seconds. These reuse shared infrastructure and admission only
of the byte-identical self-program. Successful axiom audits list only standard
logical axioms. A kernel theorem covers every valid native type and preserves
the neighboring annotation; 144 Core-evaluator cases cover both enable modes,
both slot positions, bounds rejection, nominal-ID boundaries, nonzero padding
and unchanged memory on rejection. These are not x86-refinement proofs.

The new annotation contract/helper module is 122 lines against the ten-line
Lanius function, plus 74 fixture lines and ten lines extending type-validation
proofs. The full contract/helper size still exceeds the roughly 5x target;
the common store and composition rules must absorb future repetition.
Next: close region initialization and the remaining event layouts, then use
these producer contracts to establish frontend shape, annotations, catalog
references and source-to-Core meaning. Those obligations, general extractor
preservation/rejection, runtime/x86 refinement and verified self-hosting remain
open. No production Lanius source, emitted format or trust policy changed.

Current typed-store checkpoint (October 1): `IREventStoreProof.actualAppend`
proves the actual self-emitted `append` call on represented, annotated native
regions. It stores the supplied event, resets that position's annotation to
`Invalid`, advances the cursor once, and preserves caller cells, world state,
allocation metadata and memory outside the two slots. Bounds rejection is
proved independently of storage validity. Event codecs are supplied by proved
shared rules, not assumed successful stores; concrete codecs cover arbitrary
i32 payloads, booleans and null events. Other event payload layouts and the
unannotated success path are not yet closed by this checkpoint.

Shared `NativeStoreSpec` rules derive the write from writable storage and
prove a reusable `NativeSnapshot`. A later disjoint store preserves that
snapshot without another value-decoding proof. These are proof-only memory
contracts, not emitted IR or a second typing tree. Existing represented slot
contents, index/layout bounds, writable separated slots, well-formed caller
cells, unique heap block bases and no legacy array views remain input facts.

Before annotation recording was included, the fresh event-store artifact
checked in 4.62 seconds and its whole gate took 12.03 seconds. The previous
producer/builder artifact checked in 45.30 seconds, with a 53.28-second whole
gate. Shared infrastructure and admission of the unchanged,
byte-identical self-program are reused; no cached producer proof replaces the
new artifact. Successful audits use only standard logical axioms. Physical-
storage fixtures prove arbitrary signed i32 overwrite and unchanged neighboring
slots; Core-evaluator regressions cover signed extremes, booleans, null events,
both positions, nonzero padding and annotation reset. They are not x86
machine-code refinement proofs.

The size target remains unmet here: the program-specific store module is now 129
physical lines for the 11-line append helper, including contracts and codecs.
Shared encoding/store rules are 226 lines; fixtures are 91 lines. The generic
raw-store module is 116 lines after refactoring. Reuse these contracts when
closing annotation recording and additional producers; do not repeat their
memory bookkeeping. Frontend lowering and full compiler correctness remain open.

Current native-builder checkpoint (October 1): `actualCompleteCall` proves that
the actual self-emitted builder creates the unique physical endpoint table for
any represented, well-shaped preorder input within explicit count, capacity and
allocation-budget bounds. It proves the call terminates and retains caller cells
and old event reads. No successful builder call or prevalidated physical table
is an input premise. The loop's rejection result now retains its already-proved
later suffix, so valid inputs can be proved not to reject. The concrete native
leaf/traversal proof reuses the general result instead of reconstructing cases.

The fresh connected builder proof/fixture artifact passes in 43.66 seconds;
the whole gate takes 51.44 seconds. Only admission of the byte-identical
self-program is reused; current self-output and source closure are compared,
and all eight builder-related contracts plus fixtures are freshly checked in
one artifact. Successful audits use only standard logical axioms. This closes
the endpoint-table producer/consumer gap, not the frontend-lowering obligation:
the frontend must still establish shape, annotations and semantic origin for
its event stream. No runtime tree, output representation or trust policy changed.

Current source/body agreement checkpoint (October 1): the reference checker's
accepted result now identifies the actual emitted entrypoint and supplies a
source-lowering witness for every source function's actual emitted body. This
is stronger than proving that an unrelated program is well typed. These shared
theorems reuse existing lowering records; normal output gains no proof tree.

The fresh Choice/Some(7)/match audit passes in 17.88 seconds, including shared
build work. One artifact connects independent source-file bytes, ordinary Lean
output, source/body agreement, and execution returning 7. A same-typed change
to Some(8) is kernel-proved rejected at body lowering, after Core validation.
All successful axiom audits list only standard logical axioms. This proves an
example and reference-checker soundness, not universal Lanius-tool correctness.

The larger nested fixture's source-authentication audit remains unverified:
the connected run reached the 110-second limit, and a syntax-only diagnostic
grew past 12 GB before being stopped. This is upstream of Core body agreement.
The default agreement gate therefore covers Choice; nested source authentication
is an explicit unfinished check, not a passing or cached result. Normal extraction
does not run this bootstrap audit. Module/import decisions and catalog lookup now
reduce in the kernel; proof-only source-byte quotations avoid UTF-8 reconversion
and native data compilation. The separate fresh nested Lean/x86 semantic,
mutation, and malformed-input regression passes in 6.41 seconds.
Next: prove the native producer establishes the
shared lowering/representation facts, rather than adding per-program validation.

Current constructor/match checkpoint (October 1):
`RecursiveExpressionProof.actualTreeWriter` now closes arbitrary finite nesting
of constructors and matches, with Boolean/i32/local leaves and unary/binary
parents. One mutual induction covers expressions, arms, and their child lists.
It derives every recursive writer and atom-classifier obligation; the final
native-input predicate does not assume successful recursive execution. The
contract proves exact text, termination, cursor advancement and caller/input/
runtime framing under explicit native-data, metadata, separation and capacity
facts. Calls, records, fields, slices, strings and casts are not yet part of
this closed printer theorem.

The fresh connected constructor/match gate passes in 104.19 seconds, including
72.46 seconds for one proof artifact and 18.52 seconds for native fixtures.
Only byte-identical admission and expression/builder foundations are reused.
This closes a correctness gap; it is not a checking-speed breakthrough. The
joint recursive model and closure are 198 physical lines. The seven match
modules still total 1,408 lines for the 58-line helper (24.3x), before reused
foundations. Do not copy that bookkeeping into the statement/program proof.

Shared pure-expression rules now compose allocating enum payloads and match
scrutinees while restoring shadowed bindings. Fresh emitted Lean proves
payload preservation for nested constructors, matches in payloads/scrutinees/
arms, and nested name shadowing, with two-line proof bodies. The 101-line proof
module covers the 79-line fixture. Its complete Lean/x86, mutation and malformed-
input gate passes in 8.85 seconds with shared libraries built, using the freshly
GPU-bootstrapped tools from the preceding checkpoint. The original
Choice/Some(7)/match example passes in the same fresh artifact. Successful
audits list only standard logical axioms.

The frontend producer's representation guarantees, general source-to-emitted-
Core preservation and rejection, runtime/x86 refinement, verified self-hosting,
and the explicit trusted-output boundary remain open. Exact printed text and
example/family semantics do not by themselves establish general extractor
correctness. Normal output still has no typing-proof tree or integer certificate;
no production source, trust policy or proof limit changed.

The checkpoints below are historical snapshots, including their theorem names
and coverage limits.

Earlier recursive-constructor checkpoint (October 1):
`RecursiveExpressionProof.actualTreeWriter` closes arbitrary finite constructor
nesting, including unary/binary parents and scalar/local leaves. One induction
supplies the existing printer steps and their payload-list obligations.
`ConstructorPayloadProof.actualCallStep` and `actualExpressionStep` are now
internal composition steps; their child-writer premises are discharged by the
closed theorem, not placed in its native-input predicate. It proves exact text,
successful termination, cursor advancement and caller/input/runtime framing
under explicit native representation, metadata, separation and capacity facts.
It does not prove that the frontend producer establishes those facts, or that
arbitrary emitted programs preserve source semantics. Nested matches remain
outside this closed expression domain.

The connected constructor check passes in 55.86 seconds: fresh proof sources
38.60 seconds, native fixtures 8.02 seconds, with byte-identical self-emission
and checked expression/builder foundations reused. The constructor module is
430 physical lines; the new recursive specification and closure add 106.
Their 536 lines are about 16.2x the 33-line constructor helper, before reused
name/expression/builder foundations. This extends coverage through reuse, but
does not meet the overall 5x compactness target.

`nested_enum_check.sh` also checks fresh ordinary Lean output for the original
Choice/Some(7)/match program and an acyclic nested-enum program. The latter has
general payload-preservation and nullary-branch theorems about the actual emitted
functions, with two-line proof bodies and caller/runtime framing. Its 59-line
proof module covers the 31-line fixture. Both programs execute identically in
Lean and x86; the nested fixture includes negative and signed-i32 boundary
values. A same-typed constant-payload mutation breaks the general theorem.
Wrong nominal payloads are rejected without partial output in ordinary/checked
extraction and x86 compilation. Fresh GPU bootstrap of both Lanius tools takes
5.00 seconds; the complete small semantic/mutation/rejection gate then passes
in 5.58 seconds with shared Lean libraries already built. Fresh bootstrap
self-output is byte-identical to the admitted proof program (6.10 seconds).
These are bootstrap and example/family checks, not a verified executable or
general x86 theorem. Successful axiom audits list only standard logical axioms.
No production Lanius source, emitted representation, trust policy or proof
limit changed.

Latest match-function checkpoint (October 1): `SurfaceMatchProof.actualCall`
proves the actual enclosing helper from an ordinary call, including native
View/header reads, local allocation, both outer-parenthesis modes, scrutinee
classification/printing, the complete arm loop, return, and caller/input/runtime
framing. `actualExpression` closes the normal expression-dispatch route too,
including its fourth, literal `true` argument. Neither theorem assumes the
helper or recursive writers execute successfully. The represented scrutinee
and arm bodies use the existing finite Boolean/i32/local/unary/binary domain;
nested constructors and matches are not included.

The connected match gate passes in 61.72 seconds: fresh match contracts take
32.08 seconds and native fixtures take 17.43 seconds. It includes all 51 match
cases and the existing expression-tree cases. Admission and expression/builder
foundations are reused only for byte-identical sources and self-emission.
The shared dispatch extension was freshly checked in the 89.99-second
expression proof artifact; its broader command was stopped at 110 seconds
during its fixture phase, not counted as a passing full gate. The relevant
expression fixtures pass in the connected match gate. Constructor regression
passes separately in 51.41 seconds. A fresh-admission mutation changing the
match argument from `true` to `false` proves the changed selection and rejects
the required selection without an artifact (17.93 seconds). Successful audits
list only standard logical axioms.

The new match-function module is 458 physical lines, including its native-input
specification, layout/classifier bridges, delimiter helper and dispatch proof.
The seven connected match modules total 1,378 lines against the 58-line source
helper (about 23.8x), before earlier name/expression/builder and shared fallback
foundations. This adds coverage; it is not a compactness breakthrough. Shared
cursor/scope rules now avoid repeated slot reconstruction and do not demand
writer success on an inactive branch. The remaining bookkeeping must not be
copied across the statement/program proofs. Producer facts, general rejection,
nested expression closure, emitted-program semantics, runtime/x86 refinement,
verified self-hosting and the trusted-output boundary remain open. No Lanius
source, output representation, trust policy or proof limit changed.

Latest match-loop checkpoint (October 1): `actualArm` now proves the complete
outer-loop body, including arm metadata, the pattern prefix, native constructor
or wildcard naming, allocation/restoration of the per-arm locals, bindings,
body, and next-arm updates. `actualArms` composes that result for any finite
represented arm list. It proves exact output order, normal termination, the
final arm ordinal, and the final `-1` cursor for a nonempty traversal, with
caller/input/runtime framing. Native data, live outer controls, builder child
chains, capacity and signed-count bounds remain explicit assumptions; no
reader, writer, or whole-loop execution is assumed successful.

The connected gate passes in 36.02 seconds: fresh match proof sources take
20.09 seconds, and 29 native cases take 4.23 seconds. Earlier admission and
expression/builder foundations are reused only for the byte-identical program.
The `<`→`<=` outer-guard mutation admits as fresh data, proves the changed true
guard, and rejects the required false guard without an artifact (19.03 seconds).
All successful audits list only standard logical axioms.

The new arm/outer-loop modules total 338 physical lines. The six connected match
modules total 916 lines, before earlier name/expression/builder foundations,
against the 31-line source loop (about 29.5x). This closes coverage gaps but
does not meet the compactness target. Do not replicate this bookkeeping across
the compiler. The enclosing match wrapper/dispatch, nested constructor/match
bodies, producer facts, emitted-program semantics, runtime/x86 refinement,
verified self-hosting, and the trusted-output boundary remain open. No Lanius
source, output representation, trust policy or proof limit changed.

Latest match-continuation checkpoint (October 1): the actual binding loop now
preserves the outer arm ordinal. `actualBindingsAndTail` connects it to the
actual continuation: arrow, represented expression body, newline, failure
guard, next-arm navigation, and outer-counter increment. It derives recursive
body printing from the existing finite-expression proof, not a successful-call
premise. Exact bytes, termination, cursor advancement, caller/input framing,
and both control updates are checked under explicit native-data, live-scope,
capacity and count-bound assumptions.

The connected gate passes in 31.47 seconds, including fresh match proof sources
(15.84 seconds), byte-identical self-emission, and 19 native cases (2.36 seconds).
Admission and earlier expression/builder foundations are reused only for the
identical program. Changing the actual outer increment to `+2` admits as fresh
data, proves its actual `+2` execution, and rejects the required `+1` theorem
without an artifact (18.99 seconds). Audits list only standard logical axioms.

Shared local-preservation automation replaces repeated intermediate lookup
proofs; the strengthened binding module shrinks 233→218 lines. The new connected
continuation module is 140 lines. Together they are 358 lines for the 17-line
binding/continuation source segment, before earlier metadata/layout and shared
foundations. This adds coverage, not an overall size reduction; the compactness
target remains unmet. Arm-prefix/lexical setup, full outer traversal/dispatch,
nested constructor/match bodies, producer facts, emitted-program semantics,
runtime/x86 refinement, verified self-hosting, and the trusted-output boundary
remain open. No Lanius source, representation, trust policy or proof limit changed.

Latest arm-connection checkpoint (October 1): the real arm event and the
builder's existing result now supply the binding child chain, positive arity,
and overflow-safe count increment. The actual first-child call is checked;
binding traversal returns a node proved to be an expression. The actual
builder rejects negative counts, invalid variant ordinals, wildcard bindings,
and the maximum signed count whose increment overflows. Neither accepted-tree
execution nor rejection execution is assumed.

The connected match gate passes in 14.61 seconds: self-emission 4.19 seconds,
fresh metadata/traversal/arm contracts 4.32 seconds, and 15 native cases
1.85 seconds. Earlier admission and expression/builder proofs are reused only
for the byte-identical program. Inverting the real wildcard count comparison
proves the mutated guard returns false and rejects the required true-guard
theorem after fresh admission (15.45 seconds).
Audits use only standard logical axioms. The new bridge is 133 lines, in
addition to the unchanged 233-line binding module and earlier foundations;
compactness remains below target. Outer local setup, body/arm composition,
and emitted-program semantics are still open. See [NOTES.md](NOTES.md).

Latest traversal checkpoint (October 1): the actual inner match-binding loop
now has a total success contract for any finite represented binding list.
It proves ordered name bytes, cursor/counter advancement, termination at the
remaining body node, restored scope, and caller/input framing. Native reads,
name emission and navigation are derived, not assumed successful. The outer
match printer and its initial-state/producer obligations remain open.

The focused gate passes in 12.32 seconds: fresh byte-identical self-emission
4.15 seconds, new metadata/traversal contracts 3.71 seconds, and eight native
fixtures 1.47 seconds. Admission and expression/builder foundations are reused
only for the exact checked program. The `<`→`<=` mutation fails the actual
empty-loop execution theorem after fresh admission (14.00 seconds total).
Audits use only standard logical axioms. The traversal module is 233 physical
lines for the nine-line Lanius loop, about 25.9x before earlier dependencies;
the compactness target remains unmet. See [NOTES.md](NOTES.md).

Latest proof-maintenance checkpoint (October 1): constructor callers no longer
supply payload arity separately; the theorem derives it from the checked event
classification. Six emitter routes reuse one proved native View/event prefix.
Contract search recognizes reducible invariant aliases without normalizing
execution relations, and callers can expose only direct record facts with
`core_facts 1 [record]`.

The connected expression/name gate passes in 93.78 seconds (72.87 for fresh
proof sources, 10.66 for native fixtures). The constructor gate passes in
43.87 seconds (29.78 for fresh name/constructor contracts, 6.88 for its 24
native fixtures). Both reuse admission and earlier foundations only for the
byte-identical program; these are not fresh full self-check timings. The
constructor module is now 431 lines for 26 Lanius lines, still above the
compactness target. Shared cursor/projection regressions pass through Lake in
8.74 seconds including builds.

Match metadata now has checked execution contracts for the actual header,
arm and binding readers, the validator's binding-ID wrapper, and a native
indexed binding argument. Expression-local events return the invalid binding
ID, rather than being accepted as pattern bindings. The metadata proof sources
check in 1.33 seconds; 23 focused reader cases pass in 0.86 seconds. Their full
gate takes 8.18 seconds including fresh byte-identical self-emission and reused
admission/classification foundations. Audits list only Lean's standard logical
axioms. Changing the actual binding-ID return to `0` admits as fresh data but
fails its execution theorem without a proof artifact (13.88 seconds including
fresh admission). These are reader/framing contracts, not typing validation, complete
match emission, or emitted-program semantics. See [NOTES.md](NOTES.md).

Latest extraction-proof checkpoint (October 1): constructor payload emission
now has checked, terminating execution contracts for the actual helper and
normal expression entry point. Induction derives traversal and recursive
printing for any finite list of represented scalar/local/unary/binary payloads.
The result emits exact ordered bytes and the nominal type annotation, advances
the cursor, and preserves caller/input memory and runtime state. No child
writer success is assumed by the public constructor theorem.

The focused gate passes in 48.33 seconds, including fresh byte-identical
self-emission, fresh name/constructor proofs (32.68 seconds), 24 native-layout
fixtures (8.05 seconds), and the zero-payload boundary proof. Admission,
primitive/builder, and scalar-expression artifacts are reused only for the
exact checked program. The wrong `<`→`<=` loop bound admits as fresh data but
fails the boundary execution proof cleanly in 14.75 seconds without a proof
artifact. Audits use only Lean's standard logical axioms.

Unary and constructor routes share the actual dispatcher prefix; the unary
module shrinks 143→35 lines, while the new shared program-specific module is
153 lines. Shared local/control rules and scope-aware statement automation
remove repeated frame reconstruction and manual final joins. The constructor
module remains 460 lines for 26 Lanius lines (about 17.7x before dependencies),
so the compactness target remains unmet. Its native-read/catalog, scope,
separation, capacity, and environment assumptions are explicit. Nested
constructors/matches, general rejection, producer/typing facts, emitted-program
semantics, runtime/x86 refinement, verified self-hosting, and the trusted-output
boundary are not complete. See [NOTES.md](NOTES.md) for evidence and accounting.

Previous extraction-proof checkpoint (October 1): the named nominal-type route
now has checked execution contracts from `type_identifier`, through the nominal
arm of `named_type_ref`, to the native View-based body helper `type_name`.
It derives the catalog Ref read and reuses the qualified-name proof, yielding
exact bytes, cursor advancement, termination, and caller/input framing.
Bad named type IDs reject before catalog/output backing is accessed, including
when those descriptors and the cursor are invalid.

The focused gate passes in 56.94 seconds: fresh byte-identical self-emission,
fresh connected name proofs (41.48 seconds), and 160 native name fixtures
(7.26 seconds). Admission and primitive writers are reused only for that exact
program. Weakening either the type or source-unit bound from `>=` to `>` admits
as fresh data but fails the actual rejection theorem cleanly, without a proof
artifact (14.87 and 18.63 seconds). Audits use only Lean's standard logical axioms.
The existing connected expression/name regression gate also passes in 108.25
seconds with fresh printer proofs and fixtures, reusing its byte-identical
admission, primitive-writer, and builder foundations.

Shared writer automation commits checked guards and initializers before their
continuations. Native-read matching reuses facts across changed local bindings
only when the program, type, address, length, index, and heap agree. The qualified
name module shrinks 395→357 lines without weakening its contract. Its roughly
11.2x ratio remains above the target; the new type-route module is 119 lines.
These proofs assume valid native name/path data, separated output, capacity,
and the writer environment. Synthetic zero-unit names, other type-reference
arms, lexical validity, producer facts, and emitted Lean semantics remain open.
Constructor payloads and matches/statements are next; the general extractor/
compiler, runtime/x86 refinement, verified self-hosting, and trusted-output
boundary are not complete. See [NOTES.md](NOTES.md) for evidence and accounting.

Previous extraction-proof checkpoint (October 1): actual qualified declaration-name
emission now has a checked total execution contract. It reads native module-path
metadata and source segments, emits the exact qualified name in the type,
function, or constant namespace, advances the cursor, and preserves caller and
input state. Invalid source-unit IDs reject before backing or output access.
Success requires valid native source/name reads, separated output, enough
capacity, and the existing writer environment; lexical validity, name ownership,
and producer facts are not yet derived.

The focused gate passes in 40.86 seconds: fresh byte-identical self-emission,
fresh connected name proofs, and 76 existing plus 42 qualified-name fixtures.
Admission and primitive writers are reused only for that exact program. Weakening
the unit guard from `>=` to `>` admits as data but fails the rejection proof
without a resource failure or proof artifact (19.91 seconds). Audits list only
Lean's standard logical axioms. Neither timing is fresh foundation/admission
checking or a few-second complete compiler proof.

Shared call setup retains checked parameter lookups; local proof search compares
keys and states before lookup results and applies binding rules directly. The
source-copy proof reuses one shared cursor/counter invariant and shrinks by 20
lines. Qualified-name emission itself remains 395 proof lines for 32 Lanius
lines, about 12.3x before shared dependencies. The next task is to reduce its
metadata/framing bookkeeping before extending the pattern to payload traversal.
The named `type_identifier` wrapper, constructors and matches, general rejection,
emitted-program semantics, frontend/lowering producer facts, runtime/x86
refinement, verified self-hosting, and the trusted-output boundary remain open.
See [NOTES.md](NOTES.md) for the precise scope and evidence.

Previous extraction-proof checkpoint (October 1): actual constructor-name lookup
and emission now have checked execution contracts. They derive the type/ordinal
lookup, global variant slot, catalog Ref read, escaped name, and native View
wrapper. Successful named calls terminate, advance the cursor, emit exactly
`.«Some»` (or the selected spelling), and preserve caller/input memory under
explicit native-read, separation, and capacity assumptions. Out-of-range type
IDs reject before output or naming storage is accessed, even when those
descriptors are invalid. Synthetic unnamed catalogs are outside the success
contract.

The connected gate passes in 99.70 seconds, including fresh byte-identical
self-emission, all connected printer proof sources, and 63 expression-tree,
76 identifier, and 44 constructor fixtures. It reuses admission, primitive
writer, and builder proofs only for that exact program. A wrong-slot mutation
admits as data but fails the actual lookup proof without an artifact or resource
exhaustion (18.58 seconds); the earlier wrong-local-ID gate also passes.
Audited transitive axioms remain only Lean's standard logical axioms.

Shared proof search now commits proved initializers and returning guards before
checking their continuation. This fixes the wrong-slot failure's repeated
backtracking without increasing resource limits or weakening contracts. The
constructor module is 213 lines for 35 matching Lanius lines, about 6.1x before
existing shared dependencies; the roughly 5x target remains unmet. This is not
a fresh few-second per-program verification result.

Constructor payload recursion and normal expression routing are not yet proved.
Next are qualified type-name output and payload traversal, then match arms and
statements. General rejection, emitted-program semantic correspondence,
frontend/lowering producer facts, runtime/x86 refinement, verified self-hosting,
and the trusted-output boundary remain open. See [NOTES.md](NOTES.md).

Previous extraction-proof checkpoint (October 1): the closed recursive printing
theorem now covers named local references at arbitrary finite depth alongside
Boolean/i32 literals, all three unary operators, and all 18 binary operators.
It derives the actual local payload read, classifier, atom branch, and normal
expression routing, then reuses the shared catalog/copy/escaping contracts.
The recursive writer carries the existing View's immutable metadata through
navigation and writes; it does not emit another tree or recheck operand typing.

The connected gate passes in 81.91 seconds, including fresh self-emission
(byte-identical to the admitted data), all connected printer proof sources,
63 native-layout expression-tree fixtures, and 76 identifier fixtures. Admission,
primitive writers, and builder proofs are reused only for that exact program.
A wrong-local-ID mutation admits as data but fails the payload execution
contract without a proof artifact or resource failure (13.33 seconds).
Audited transitive axioms remain only Lean's standard logical axioms.

Production proofs grow by 182 physical lines: the local path, immutable scope,
recursive integration, and one shared argument-frame rule. Compactness remains
above the roughly 5x target, and this is not a fresh few-second per-program check.
The theorem proves exact printing, termination, cursor advancement, and framing
under stated native-read/capacity assumptions. It does not establish binding
resolution, operand typing, emitted-program semantics, or producer facts.
Constructor/match and other expression/statement forms, general rejection,
runtime/x86 refinement, verified self-hosting, and the trusted-output boundary
remain open. See [NOTES.md](NOTES.md) for evidence and accounting.

Previous extraction-proof checkpoint (October 1): the shared name-emission path
now has execution contracts for actual symbol-catalog lookup, source-byte
copying, escaped identifiers, and both body-name helpers. Successful calls
terminate, emit exactly the selected name (with `«…»` where required), advance
the cursor, and preserve caller/input memory under explicit native-read and
capacity bounds. Invalid unit references are proved to reject in the catalog
and unescaped writer; other malformed cases are covered by focused tests, not
a general rejection theorem.

The fresh connected name gate passes in 73.28 seconds, including self-extraction,
admission, primitive writer proofs, and 76 native-layout fixtures. Mutating the
actual copied byte to zero still admits as program data but fails the public
writer contract, without a proof artifact or resource failure (60.51 seconds).
The four new production proof modules total 522 lines for 67 physical lines of
Lanius, about 7.8x before shared dependencies; the roughly 5x target remains
unmet. No Lanius source, emitted format, trust policy, or resource limit changed.

These reusable contracts close a prerequisite for local expressions and match
bindings, not their expression/statement routing or semantic preservation.
Constructor/match emission, general rejection, whole-program semantic
correspondence, producer/runtime/x86 proofs, verified self-hosting, and the
trusted-output boundary remain open. See [NOTES.md](NOTES.md) for evidence and
scope accounting.

Previous extraction-proof checkpoint (September 30): the closed recursive
printing theorem covers Boolean/i32 literals, all three unary operators
(`+`, `-`, `!`), and all 18 binary operators through the normal expression
entry point. Negative expressions now use the actual unary-negation route.
One unary execution proof and dispatcher cover the three symbols; induction
derives their recursive child calls. The existing Boolean-only cases follow
from this theorem, so their unused separate corollaries have been removed.

The 88-line induction checks in 0.91 seconds with dependencies built. The
generic unary helper and routing check in 8.06/6.07 seconds. All 49 native-layout
expression fixtures pass, including nested unary operations, negative operands,
mixed arithmetic/comparison trees, and exact/short buffers. The fresh
self-extraction/admission and connected gate passes in 109.08 seconds.
Audited transitive axioms remain only Lean's standard logical axioms. The four
edited production proof files shrink by six lines overall despite the broader
domain. Compactness remains above the roughly 5x target.

This proves exact printing, termination, cursor advancement, and framing under
the stated native-memory/capacity assumptions. It does not prove operand typing
or arithmetic evaluation. Pointer arithmetic, remaining expression/statement
forms, general rejection, whole-program semantic correspondence,
producer/runtime/x86 proofs, verified self-hosting, and the trusted-output
boundary remain open. See [NOTES.md](NOTES.md) for evidence and accounting.

Previous extraction-proof checkpoint (September 30): the closed recursive
printing theorem now covers i32 literals, Boolean literals, unary-not, and all
18 binary operators through the normal expression entry point. The binary
helper and dispatcher are shared across arithmetic, comparison, bitwise,
shift, and logical operations; their execution proofs are not copied per
operator. Scalar `+`/`-` derive the non-pointer route from an existing left
annotation. Other operators need no added annotation premise. The earlier
Boolean-tree domain remains covered.

The 81-line induction checks in 1.03 seconds with dependencies built. Operator
contracts, the generic binary helper, and routing check in 9.64/8.02/5.54
seconds. The full fresh self-extraction/admission and connected gate passes in
101.12 seconds, including 36 expression-tree fixtures and the existing scalar,
unary, and cursor regressions. Audited transitive axioms remain only Lean's
standard logical axioms. The generic binary module grows by seven lines,
251→258; production proof growth including operator specifications and shared
short-circuit rules is 123 lines. Compactness remains above the roughly 5x
target, though the implementation's shared binary path now has a shared proof.

This proves exact printing, termination, cursor advancement, and framing under
the stated native-memory/capacity assumptions. It does not re-prove operand
typing or arithmetic evaluation, nor close whole-program semantic
correspondence. Pointer arithmetic, other unary/expression/statement forms,
general rejection, producer/runtime/x86 proofs, verified self-hosting, and the
trusted-output boundary remain open. See [NOTES.md](NOTES.md) for evidence and
accounting.

Previous proof-maintenance checkpoint (September 30): unary and binary printing
now reuse cursor-relative byte/text contracts. Output effects retain the buffer
and normalize its next position; local lookup automation uses the cursor's
proved value directly. The actual execution contracts, Boolean-tree induction,
memory assumptions, and trust boundary are unchanged.

The edited production proof files shrink by 23 physical lines overall,
including the 42 lines added to shared helpers and automation. The binary/unary
modules shrink from 290/210 to 251/184 lines. Focused checks take 7.95/7.66
seconds with dependencies built. The fresh self-extraction and connected gate
passes in 101.42 seconds, including native fixtures. Overall checking time is
unchanged; this is a modest proof-size reduction, not a new coverage milestone
or a few-second verification result. The binary helper alone remains about
12x its 21-line implementation, before shared dependencies. See
[NOTES.md](NOTES.md) for accounting and remaining obligations.

Previous extraction-proof checkpoint (September 30): the normal expression
entry point now has a closed structural induction for arbitrary finite Boolean
trees using literals, unary-not, `&&`, and `||`. `actualTreeWriter` relates its
specification to the existing physical builder tree and native annotations.
It derives both recursive child calls, including a right child after an
arbitrarily large left subtree, and proves termination, exact bytes, cursor
advancement, and the caller/input frame under explicit capacity and memory
assumptions. No successful-printing or recursive-call correctness premise
remains. Its transitive axioms are only Lean's standard logical axioms.

The 71-line induction module checks in 0.90 seconds with dependencies built.
Fresh self-emission/admission and the full connected gate pass in 101.22
seconds. Checking the same connected contracts together avoids repeated
module loading/serialization; builder cache reuse still requires identical
program data and fresh proof sources. Fourteen new native-layout fixtures
exercise both logical operators, mixed/asymmetric trees, exact capacity,
short buffers, invalid annotations, and retained caller cells and IR reads.
The general induction replaces the unused chain-only proof, without a shim.

This proves a larger expression family, not the whole extractor or compiler.
Other expression/statement forms, general rejection, semantic correspondence
of the emitted Lean program, producer/runtime/x86 proofs, verified self-hosting,
and the trusted-output boundary remain open. Proof compactness is still above
target; the 290-line binary helper must not become a copied pattern for every
operator. See [NOTES.md](NOTES.md) for evidence, assumptions, and size accounting.

Previous extraction-proof checkpoint (September 30): the normal expression
entry point now has a closed induction for arbitrary finite unary-not chains
ending in either Boolean value. `actualChainWriter` describes its domain with
the existing physical IR events and leaf annotation, not successful printing.
It derives every recursive child call and proves termination, exact bytes,
cursor advancement, and the caller/input frame under explicit native-memory
and capacity assumptions. No recursive-call correctness premise remains.

The induction reuses generalized helper/routing steps; the previous
Boolean-child theorems remain proved corollaries. The 53-line recursion module
checks in 0.94 seconds with dependencies built. Fresh self-extraction/admission
and the full connected check pass in 101.64 seconds, within the command limit.
Native regressions exercise depths 0, 1, 2, and 5, including exact capacity,
and retain caller cells plus IR reads. No typing tree, certificate, axiom,
resource-limit increase, or source/compiler rewrite was introduced.

This closes one recursive expression family, not the whole printer. Proof
compactness remains above target. Binary/call/match and statement recursion,
general rejection, whole-printer semantic correspondence, producer/runtime/x86
proofs, verified self-hosting, and the trusted-output boundary remain open.
See [NOTES.md](NOTES.md) for scope accounting and evidence.

Previous extraction-proof checkpoint (September 30): unary-not printing now has
a contract at the normal `surface_expression_output` entry point. The proof
checks the actual non-atom classifier, both operator-name lookups, the selected
unary branch, and the previously proved helper with its Boolean child. It
proves termination, exact text, cursor advancement, and the caller/input frame
for both Boolean values under the existing native-memory and capacity
assumptions. No successful printing, route selection, or child-call correctness
is assumed. Its transitive axioms are only Lean's standard logical axioms.

The fresh self-extraction/check passes in 97.05 seconds, including both unary
contracts and the native-layout regressions. Shared rules now retain read-only
call effects through a falling-through guard and a local initializer before a
writer. Cursor-call composition shortens the helper from 202 to 189 physical
lines, but shared additions and the new dispatcher proof increase total written
code. This is a correctness checkpoint, not a claim that the 5x compactness
target or a net size reduction has been met. General recursive cases,
rejection, whole-printer semantic correspondence, producer/runtime/x86 proofs,
self-hosting, and the trusted-output boundary remain unfinished. See
[NOTES.md](NOTES.md) for verification and accounting.

Previous extraction-proof checkpoint (September 30): the actual unary-not helper
now composes its three prefix writes, the proved Boolean expression dispatcher
on its first child, the mutable cursor updates, and its closing text write.
For either Boolean value it terminates, writes exactly `(!(true))` or
`(!(false))`, returns the next cursor, and retains the caller/input frame under
explicit native-memory and capacity assumptions. It derives child arity from
the existing IR classification; successful printing or recursive-call
correctness is not a premise. The shared fresh-cursor rule retains the heap
effects of each writer while updating only the helper's fresh local cell.

Native-memory regressions additionally run the outer expression dispatcher,
then traverse/read the same tree. That outer unary dispatch is tested, not yet
proved. The helper proof does not cover deeper unary trees, other operators,
general rejection, or whole-printer semantic preservation. Proof compactness
remains above the 5x target; do not multiply this bookkeeping across cases.
See [NOTES.md](NOTES.md) for the bounded fresh check and size accounting.

Previous extraction-proof checkpoint (September 30): boolean and integer leaves
now connect through the actual `surface_expression_output` dispatcher, not just
its atom helper. The integer atom formats every canonical i32; the dispatcher
accepts nonnegative literals and minimum i32, matching the IR convention that
other negatives use unary-negation nodes. Boolean dispatch reads its existing
native Bool annotation and reuses the checked type-reference equality helper.
Neither public expression theorem assumes classifier acceptance or successful
printing. Both prove exact bytes, cursor advancement, termination, and the
writer frame under explicit native-read, capacity, and memory assumptions.

The continuation boundary now carries the readable buffer, protected native
View, and common writer environment across output writes. A connected kernel
proof runs two real boolean writers, deriving the second call's inputs from the
first call's effects. The actual `next = byte(..., next, ...)` pattern also has
a checked regression: its heap write and subsequent local-cursor assignment
both survive composition. These close prerequisites for recursive printing,
not the recursive printers themselves.

Shared rules now compose nested read-only call arguments, writer matches,
locals, returns, and a returning branch after a framed guard. They retain fresh
parameter cells rather than pretending calls leave the entire state unchanged.
The normal emitted representation is unchanged: no second typing tree, new
certificate, axiom, or native-computation shortcut was added.

The fresh scalar/continuation gate passes in 80.52 seconds, including self-extraction,
admission, and writer contracts rechecked against that exact program. Dispatcher
contracts take 5.56 seconds with dependencies built. Native-layout Core fixtures
cover both booleans, zero, ordinary and boundary integers, malformed annotation
rejection, unsupported negative-atom rejection, and traversal/read preservation
after printing. Wrong boolean spelling still admits as data but fails the actual
writer proof without a proof artifact or resource exhaustion (54.95 seconds).

This closes successful boolean/integer leaf dispatch in the formal memory model.
It does not prove all expression/statement cases, general dispatcher rejection,
whole-printer semantic preservation, frontend/lowering representation facts,
native runtime/x86 refinement, verified self-hosting, or the trusted-output
boundary. Those remain open. Compactness is improved by shared composition but
is not yet at the roughly 5x target; see [NOTES.md](NOTES.md) for scope accounting.

Previous extraction-proof checkpoint (September 30): the actual boolean-expression
leaf emitter now reads its value from the built IR and emits the correct Lean
literal. Its checked formatting helper handles both spellings, advances the
cursor, and rejects insufficient space without writing or borrowing storage.
A shared memory frame preserves native IR/context reads across output writes,
including when the output buffer precedes the IR. The builder's consumer view
now retains event and endpoint reads, rather than all old heap bytes.

The leaf contract composes with that consumer view and returns the same tree
for subsequent traversal. It reuses the checked text writer and shared call,
match-scope, and memory-frame rules; it does not emit another tree, certificate,
or typing proof. Core-interpreter regressions build a tree, store it in a
native-layout printer context, print each boolean value, then navigate the same tree.
Wrong boolean spelling still admits as program data but fails the actual-code
correctness contract without a proof artifact or resource failure.

This closes boolean leaf emission and read preservation in the formal memory
model. Other expression/statement cases and whole-printer semantic preservation
remain open, as do frontend/lowering establishment of the representation facts,
native runtime/x86 refinement, verified self-hosting, and the trusted-output
boundary. See [NOTES.md](NOTES.md) for checks, assumptions, and size accounting.

Previous extraction-proof checkpoint (September 30): successful builder output
now feeds the actual traversal contracts directly. The navigation model uses
the builder's endpoint function and native-read facts; its former packed-list
conversion is gone. The complete builder call establishes either rejection
or a `Ready` view of its returned tree. This view is a proof contract, not a
second tree or emitted certificate.

The actual `child_count`, `first_child`, `subtree_end`, and `next_sibling`
contracts compose with that result. Child chains identify the next child and
prove termination after the last child. Reads and caller cells remain framed.
A connected leaf proof starts from original event bytes, builds the tree,
then invokes its navigator. A branching execution fixture checks children of
different subtree sizes. Fresh self-extraction and the connected contracts
pass; wrong first-child code and wrong subtree/sibling code must fail their
public contracts. See [NOTES.md](NOTES.md) for evidence and size accounting.

This closes builder-to-navigation composition in the formal memory model.
Frontend/lowering must still establish the builder's represented-source
facts, and the printer must still prove that its text preserves IR semantics.
Native runtime/x86 refinement and the trusted-output boundary remain open.
The earlier builder compactness warning still applies.

Previous extraction-proof checkpoint (September 30): the complete tree-builder
call now has a total-correctness contract against the actual self-extracted
body. `actualCall` composes the entry guard, allocation and borrowing, counter
initialization, reverse loop, final root check, and return. It covers every
represented natural count; a separate entry contract covers negative counts.
Bounds/size rejection is pure. Allocation failure records the allocator call;
structural rejection identifies a bad node or multiple roots. Successful
results connect the exact returned tree to the physical endpoint words and
preserve old heap reads and caller cells. A concrete full-call proof starts
from original event bytes, with spare capacity, and derives the returned tree
and endpoint 1 without assuming a prepared table or successful validation.

A fresh self-extraction/admission and connected contract/fixture gate passes
in 78.46 seconds with shared infrastructure already built. The new call
contracts check in 4.17 seconds, the loop contracts in 5.39, and fixtures in
1.43. A wrong root guard admits as data but fails the root and complete-call
contracts without a proof artifact or resource failure (60.21 seconds).
The stopped-counter mutation also rejects its iteration/loop contracts (55.51
seconds). A fresh GPU bootstrap takes 2.52 seconds; the connected tree tests,
Lean/x86 enum match returning 7, and three malformed-input rejections pass in
2.98 seconds. All successful audited contracts retain only standard Lean
logical axioms.

This closes the builder proof in the formal memory model. It does not prove
that the frontend establishes its represented-event/read assumptions, that
the native allocator refines that model, or that the whole printer/compiler
is correct. Those obligations and the trusted-output boundary remain open.
The builder-specific files total 703 physical lines for `empty()` plus the
complete builder's 35 source lines (20.1x). The new call file contributes 321
of those lines. Shared scope-composition rules add 36 lines and an aligned
address bound adds six; tests and existing classifier/walker/allocation
dependencies are additional. Compactness is still unresolved. See
[NOTES.md](NOTES.md) for the contract, evidence, and remaining assumptions.

Previous extraction-proof checkpoint (September 30): the actual reverse builder
loop now has a total-correctness contract. Each successful iteration writes its
parent's endpoint and extends the valid suffix; rejection returns `empty()`
with a structural reason. The loop terminates, preserves original event reads
and caller cells, and leaves its signed counter at -1 on completion. Its child
walker inputs are derived from the table and source representation, not from
assumed walker execution or prior validation. The initial table's zero reads
are derived from fresh allocation. Active event count and backing slice length
are distinct, so a capacity-backed event buffer is supported.

A fresh self-extraction/admission and connected builder proof/fixture gate
passes in 61.26 seconds with shared infrastructure built. The builder contracts
check in 4.52 seconds; fixtures take 1.10 seconds. A stopped-counter mutation
admits as data but fails both iteration and loop contracts without a proof
artifact (46.36 seconds for admission, dependency checks, and rejection).
The connected writer proofs also recheck after the shared-counter API change
(37.31 seconds). All successful audited contracts use only standard Lean
logical axioms; no native computation shortcut or new axiom is used.

This closes the reverse-loop obligation, not the whole builder. The entry
guards, allocator/setup, and final root-end check still need composition into
a public builder call contract. Frontend/lowering and whole-printer
correspondence, native runtime/x86 refinement, verified self-hosting, and the
explicit trusted-output boundary remain open. Normal emitted Lean is unchanged.
The builder proof file is 378 physical lines for its currently proved 19-line
source scope (19.9x), including models, selectors, glue, and audits. This is a
compactness hotspot: shared contracts are being reused, but the remaining
mutable-local composition is still too verbose. See [NOTES.md](NOTES.md).

Previous extraction-proof checkpoint (September 30): the builder's storage
contracts now connect to the actual self-extracted allocation wrapper,
raw-slice constructor, and endpoint-store expression. They derive allocation
success or budget exhaustion, invalid-size rejection, caller-cell preservation,
the host-call trace effect, ownership protection without copying, and the exact
endpoint write while preserving all other entries. Concrete heaps exercise
exhaustion, preservation of old storage, and a previously completed child.
The source empty-slice wrapper also has a general pure call contract. Fixing
the interpreter's erroneous rejection of `(null, 0)` makes the actual `empty()`
and zero-count builder calls return normally; those whole-call checks are
executable regressions, not a general builder proof. Nonempty null slices and
all indexing of empty slices still reject.
At this storage checkpoint, native allocator refinement and the reverse-loop
invariant were still open. The latest checkpoint above closes the loop only.

A focused fresh self-extraction/admission check, storage contracts, fixtures,
and three wrong-program mutations pass in 107.48 seconds. Emission takes 4.28,
admission 15.42, the actual-code contracts 3.12, and fixtures 0.99 seconds;
the rest includes setup and three separate mutant admissions/proof attempts.
After the empty-slice fix, the contracts recheck in 3.59 seconds and fixtures
in 1.41 seconds, reusing the identical, previously admitted self-data.
The contract file has 169 physical lines for 11 corresponding source lines
(15.4x), including model, selectors, representation/glue, and axiom audits.
This exceeds the compactness target; the outer proof must consume these
contracts, not repeat their call/heap bookkeeping. Shared foundations and
tests are additional. See [NOTES.md](NOTES.md) for scope and evidence.

Previous extraction-proof checkpoint (September 30): the shared `children_end`
helper now has a call-level total-correctness proof against its actual
self-extracted body. `actualChildrenCorrect` proves that it returns exactly a
bounded, strictly advancing chain of the required child categories, or -1
when no such chain exists. It also preserves caller cells, heap, world, and
array views. Its assumptions describe represented events and physical input
reads, i32 count bounds, and the parent range; they do not assume successful
execution or validator acceptance. The builder must still establish these
input facts from its initialized endpoint suffix.

Classification contracts
cover all 64 event constructors in the self-extracted IR dispatcher. Casts and
match-expression headers complete the previous 62-case coverage. Six general
type-reference helper contracts support them: nominal and nominal-slice code
generation, invalid-tag detection, type-code projection, validity, and equality.
They cover rejected IDs and reserved-range bounds, not just successful examples.
The cast and match contracts prove the returned shape, termination, and caller
frame, including invalid headers and wrapped i32 arity calculation.

This completes structural classification for the represented event families;
it does not validate every arbitrary Core payload. At this child-walker
checkpoint, the actual tree builder's outer-loop invariant and the caller's
derivation of input/storage bounds remained open. Allocation and the single
endpoint store have the contracts above;
they have not yet been composed into a theorem for the complete builder.
Frontend/lowering correspondence, whole-printer preservation, x86/runtime
refinement, verified self-hosting, and the explicit trusted-output boundary also
remain open. Normal output still contains no typing-proof tree or certificate.

The classifier and type-reference files total 400 physical lines, including
models, representation bridges, source accessors, contracts, and axiom audits,
for 220 corresponding Lanius function lines (1.8x). The child-walker file adds
362 physical lines for its 17-line source helper (21.3x), a compactness hotspot.
Together these files are 762 lines for 237 source lines (3.2x); this aggregate
does not erase the walker-specific overhead. Both outer loops must reuse its
contract rather than copy its memory, mutable-local, or scope arguments.
Shared framing, arithmetic,
automation, and their tests are additional and remain part of the connected
proof cost. See [NOTES.md](NOTES.md) for measured checks and regression evidence.

A fresh GPU bootstrap, self-extraction, Lean admission, and all connected
writer, navigation, type-reference, classifier, and child-traversal contracts
pass in 98.53 seconds (952 functions, 667 constants). The freshly checked
child contracts take 8.76 seconds with shared infrastructure built; concrete
heap fixtures take 1.15 seconds and cover an empty chain, a real unary child,
a cyclic endpoint, and an endpoint beyond the region. The earlier wrong
cast/match classifiers admit as data but fail their public contracts without
producing proof artifacts (52.20 seconds for that batch).
Two broken child walkers also admit as data but fail both call-level
correctness contracts without proof artifacts (91.27 seconds for the pair).
The data declaration has no axioms; successful contracts use only standard
Lean logical axioms. These are offline tool-proof checks, not a claim that the
whole extractor is proved or that fresh per-program admission meets its target.

The builder and validator now share one private child-walking loop instead of
duplicating it. The shared total-correctness rule for decreasing loops with
early return is proved and has a general countdown/rejection regression.
The actual child walker is now proved by induction on remaining children,
using the shared loop-step and early-return rules. The reverse-builder
invariant was still open at that checkpoint. Native tree tests include cyclic, negative, and
past-region endpoints. A focused connected gate passes in 2.16 seconds:
tree tests compiled by the Lanius-written x86 compiler, the representative
enum match executing in both Lean and x86, and malformed enum payload,
partial-return, and call-arity rejection without partial output.

Previous extraction-proof checkpoint (September 29): actual IR classification
contracts cover 62 of the 64 event constructors: 45 fixed-arity events,
13 events whose payload does not affect structure, three payload-counted
events, and match-arm headers. They prove the returned kind, arity, and child
rule, termination, and caller-frame preservation. The full child-position
classifier and shape-record constructor also have general contracts.
Match-arm classification covers malformed ordinals, negative binding counts,
wildcards with bindings, and i32 wrapping. A missing arm payload returns an
invalid shape. These are actual self-extracted calls, not substitute models
whose successful execution is assumed.

At that checkpoint, cast events and match-expression headers remained open
because they call the type-reference helpers. Tree construction/validation
loop invariants remain open too: the earlier endpoint assumptions have not
been discharged.
Whole-printer preservation and compiler correctness are therefore incomplete.

Shared matching rules preserve scrutinee effects, choose the first matching
arm, and restore pattern-binding scope. Proved call contracts compose without
reopening callee bodies. Source-constructor notation reuses existing nominal
metadata rather than hand-maintaining numeric tags; it adds no typing tree or
trust bypass. An early-return guard rule avoids repeated failed proof paths.
The classification file is 210 physical lines, including models, representation
glue, regressions, and axiom audits, versus 161 corresponding source-function/
covered-dispatch lines (1.3x). Shared foundations and tests are additional.

Fresh GPU bootstrapping, self-extraction, admission, all connected writer and
navigation contracts, and classification contracts pass in 81.27 seconds.
Emission takes 4.70, admission 15.68, basic writers 31.62, signed printing
4.83, navigation 3.43, and classification 12.08 seconds; the total also includes
bootstrap/setup and a separate 397 ms typing diagnostic. Three wrong classifier
implementations admit as data but fail their public contracts with no proof
artifact (92.48 seconds). Successful contracts use only standard Lean logical
axioms; the self-program data uses none. Production Lanius and normal emitted
Lean are unchanged. See [NOTES.md](NOTES.md) for scope and evidence.

Previous extraction-proof checkpoint (September 29): the actual self-extracted
`ir::body_tree::subtree_end` and `next_sibling` functions now have general
read/rejection contracts. Given the existing endpoint slice's physical bytes,
valid lookups terminate and return the specified endpoint or sibling. Invalid
index ranges return -1 without reading backing storage. Both preserve the
caller frame. A successful sibling advances strictly within its parent and
decreases the count-minus-index traversal measure.

The endpoint bounds and storage facts are explicit input assumptions; they
have not yet been derived from the actual tree builder or validator. These
contracts therefore prepare shared IR traversal for the printer/backend proof,
but do not close tree construction or whole-printer preservation.

Shared read-only statement automation replaces manual scope bookkeeping.
Actual call proof bodies are 3–5 lines; complete navigation proof/glue is 93
physical lines for 13 implementation lines (7.2x), still above the 5x target.
The connected self gate passes in 65.41 seconds, including fresh emission
(4.04), admission (14.20), basic writer proofs (30.88), signed printing (4.16),
navigation (4.31), and setup/typing diagnostics. These are validation timings,
not a speedup claim. Four wrong navigation implementations admit as data but
fail the public contracts without producing proof artifacts (84.59 seconds
for the batch). Successful proofs use only standard Lean logical axioms.
Production Lanius and ordinary emitted Lean are unchanged; no emitted typing
tree, certificate, or new trusted-output shortcut was added. See [NOTES.md](NOTES.md).

Previous extraction-proof checkpoint (September 29): the actual extracted signed
i32 printer now has a successful-formatting contract for every canonical i32,
including -2147483648. It composes the checked byte, natural, and text writers:
exact decimal bytes, termination, next output position, original caller cells,
world, views, and all previously readable memory outside the output. Fresh
borrowed string storage is permitted in the minimum-value branch. This closes
one syntax-atom composition, not the whole printer or source-to-Core proof.

Shared output-effect and call/local-scope rules compose byte writes with fresh
string storage. They are proof infrastructure, not another emitted program,
typing tree, runtime certificate, or trusted-output bypass. Normal emitted
Lean and production Lanius are unchanged. Signed-writer checking takes 4.45
seconds with its dependencies already checked; fresh self-extraction and all
connected writer proofs take 52.41 seconds in the final run (emission 4.09,
admission 12.11, basic writers 26.25, signed printer 4.30, plus setup and a
separate typing diagnostic). An earlier pass took 61.52 seconds; these are
validation timings, not a speedup claim. Successful proofs use only standard
Lean logical axioms.

Signed proof/glue is 115 physical lines for a 13-line Lanius function (8.8x),
above the 5x target. New Lean files total 407 lines: 181 shared foundations,
58 shared regression tests, and 168 signed proof/model/regression lines.
Existing call automation and shell-gate changes are separate. See
[NOTES.md](NOTES.md) for mutation evidence and remaining obligations. Wrong
minimum literals, signs, and magnitudes admit as data but fail the public
contract, without producing a proof artifact.

Previous extraction-proof checkpoint (September 29): the actual extracted decimal
writer now has a total successful-formatting contract. It writes the exact
minimal-width positional decimal bytes, terminates, returns the next cursor,
and preserves caller cells, all other heap reads, allocation metadata, world,
and views. Its domain is nonnegative canonical i32 values, readable packed
output, enough capacity below 2^31, well-formed cells, unique heap block bases,
and no registered views. Internal assignment and store success are derived,
not premises. The earlier invalid-input and insufficient-space rejection
contracts remain checked. All six basic writers now have their stated general
call contracts; this is not a whole-printer or compiler correctness proof.

Shared scalar-assignment and two-local rules handle the mutable remainder and
index without per-iteration evaluator reconstruction. A reverse byte-frame
rule composes the exact output suffix. The mathematical output is defined by
positional powers of ten, independently of the loop. Normal emitted Lean is
unchanged and carries no per-program proof or typing tree.

The decimal proof checks in 12.60 seconds against a fresh writer embedding,
with shared infrastructure already built. Fresh self-extraction and all writer
contracts pass in 60.42 seconds: emission 4.41, admission 15.70, combined writer
contracts 32.88, plus setup and the separate typing diagnostic. The module has
951 functions and 667 constants. Four wrong decimal implementations admit as
data but fail the public formatting contract, with no proof artifact (83.80
seconds). The focused native capacity/digit/canary regression also passes.
Successful contracts use only standard Lean logical axioms. These are
validation timings, not a speedup claim.

Decimal proof/glue is 273 physical lines for 35 implementation lines (7.8x),
excluding module boilerplate and regression examples but including source
accessors, models, helper proofs, and axiom audits. It remains above the 5x
target. Total Lean grows by 465 lines, including shared rules and focused tests.
Whole-printer preservation, general frontend/lowering correctness, complete
x86/runtime refinement, verified self-hosting, and the trusted-output boundary
remain open. See [NOTES.md](NOTES.md) for evidence and exact accounting.

Previous extraction-proof checkpoint (September 29): decimal width calculation
and insufficient-space rejection now have general contracts for the actual
extracted functions. The Lanius writer replaces its counting loop with a
decision tree of at most four comparisons. Lean proves the result is the
minimal decimal width for every nonnegative i32, including zero. The writer
rejects insufficient capacity before touching output storage; it preserves
the caller frame while allowing fresh temporary cells. Successful decimal
output remains unproved, so basic writer completion is still five of six.

Shared call/local-scope rules handle fresh temporary allocation without
repeating call setup. Scalar proof automation no longer tries closed
computation on fixed-result symbolic comparisons with large thresholds.
Focused regressions retain wrong-result rejection and effectful argument order.
The new proof file checks in 9.83 seconds against a fresh writer embedding;
successful proofs use only standard Lean logical axioms.

Fresh self-extraction passes with 951 functions and 667 constants: 58.70
seconds including shared setup, emission, admission, writer contracts, and
the separate typing diagnostic, under concurrent mutation load. Three new
wrong decimal implementations admit as data but fail their public contracts.
The connected Lean/x86 gate passes in 102.31 seconds without concurrent
mutation load. An earlier run hit its 110-second guard. These are validation
results, not a speedup claim. Total Lean grows by 161 lines, including tests;
whole-printer and compiler correctness remain open. See [NOTES.md](NOTES.md).

Previous extraction-proof checkpoint (September 29): shared call automation
derives parameter bindings from the actual declaration, proves their equality
to Core binding, and restores the caller frame. The body proof remains an
explicit obligation. Argument composition retains left-to-right effects and
reuses a supplied call contract. Cursor, byte rejection, hex-digit, and packed
length no longer repeat their parameter-binding lists; hex/text call sites
use the same argument rules without weakening their contracts.

The actual decimal writer now has a general initial-input rejection contract:
negative values, negative positions, or positions past capacity return -1
without output access or caller-state changes beyond fresh parameter cells.
Its proof body is two lines. Decimal digit counting, insufficient-space
rejection after counting, and successful formatting remain unproved; basic
writer completion is still five of six, not six of six.

The fresh 950-function self gate passes in 43.76 seconds under concurrent
mutation load (emission 4.45, admission 13.62, writer contracts 19.52, plus
setup). Nine wrong-output mutations admit as data but fail the relevant public
contracts without proof artifacts. Successful contracts use only standard
Lean logical axioms. No production Lanius or ordinary output format changed.
These are validation timings, not a speedup claim. Existing writer proofs
shrink by 28 lines, but new shared code, rejection coverage, and tests grow
total Lean by 125 lines. Hex/text proofs remain far above the compactness
target. Whole-printer and compiler correctness remain open. See [NOTES.md](NOTES.md).

Latest correctness checkpoint (September 29): the x86 machine model no longer
allows a division instruction through the generic decoded-step rule. That rule
previously bypassed the separate division rule's nonzero-divisor and quotient
range obligations. Division now requires those obligations; ordinary encoding
proofs supply a structural non-division fact. The public division and fault
contracts keep their existing domains and conclusions.

The focused machine/encoding checks pass in 11.59 seconds, including affected
shared builds. Connected program and ELF startup/exit proofs pass in 20.36
seconds. Their axiom audit reports only standard Lean logical axioms. An
isolated copy of the actual relation passes the regression; removing its guard
makes that regression fail without a proof artifact (1.43 seconds together).
There is no production Lanius, emitted Lean, or runtime change. This closes a
machine-model hole, not the whole extractor/compiler proof. See [NOTES.md](NOTES.md).

Latest proof-authoring checkpoint (September 29): the byte writer's success
contract now takes a readable four-byte storage footprint and a `Fin 256`
byte. Callers no longer supply the old packed word or prove an encoding
round-trip. Shared automation projects facts from explicitly supplied records,
transports local lookups through counter frames, and composes scalar guards
with proved effectful calls. Hex formatting and text copying use it without
weakening their public contracts. Text's final arithmetic bound remains explicit.

Fresh standalone writer contracts and the 950-function self gate pass using
only standard Lean logical axioms. The self gate takes 36.26 seconds under
concurrent test load; this is not a speedup claim. Seven admitted-but-wrong hex
and text outputs fail their public contracts without proof artifacts. The
mutation harness checks only each affected writer's dependencies, after an
all-writer batch reached its 110-second guard.

The four changed writer proof files shrink by 31 lines, but the shared
automation adds 59 production lines and its focused tests add 63: total Lean
grows by 91 lines. Hex proof/glue is still about 24 times its source; text is
about 17 times. This improves proof authoring, not the overall compactness
target or compiler-proof completion. No production Lanius changes or new
per-program typing/proof trees were introduced. See [NOTES.md](NOTES.md).

Latest hex-writer checkpoint (September 29): the actual extracted `hex_word`
now has a total call contract for arbitrary 32-bit words and valid packed
output buffers. It writes exactly the available prefix of eight lowercase
hex digits, returning the next cursor on success or -1 after partial output
on capacity failure. It preserves all other reads, allocation metadata, old
cells, caller locals, world, and views. Initial negative/past-capacity cursors
have native regressions, not a general rejection theorem in this contract.

Text copying and numeric formatting now share an exact-prefix state invariant
and loop rule. The text proof derives preservation of its input from the
memory frame instead of carrying another input-state record. Its complete
call contract remains unchanged. Proof accessors derive local IDs from the
actual function, rather than hard-coding token positions shifted by source edits.

Five of six basic output routines have their stated general call contracts;
`natural` remains open. This is not a whole-extractor or compiler proof.
The fresh self gate checks all current writer contracts in the 950-function,
667-constant embedding in 32.52 seconds (emission 4.37, admission 12.34,
contracts 10.14). The connected Lean/x86 gate passes in 79.50 seconds, including
capacity boundaries. Four wrong hex-writer mutations admit as Lean data but
fail the contract without an olean. Successful proofs use only standard Lean
logical axioms. These are validation timings, not a claimed speedup.

Compactness is still unresolved: the hex proof/glue is about 26 times its
11-line implementation, and text remains about 17 times its 21-line source.
Total Lean grows. The next architecture step must shorten the numeric writer's
argument/call/framing composition before scaling this pattern to `natural`.
Whole-printer preservation, frontend/lowering correctness, x86/runtime
refinement, and the explicit trusted-output boundary remain unfinished.
See [NOTES.md](NOTES.md) for the precise domain, evidence, and line accounting.

Previous writer-contract checkpoint (September 29): `cursor` now has a general
call contract for packaging its inputs without changing the caller's memory
or existing variables. `hex_digit` has a general call contract for exact
lowercase ASCII on all sixteen nibble values. Both prove the actual extracted
functions, not separate models of their bodies. They join the existing byte,
text, and host packed-length contracts in the fresh 950-function self-module.
The remaining basic output routines are `natural` and `hex_word`; the latter
has execution regressions, not a general call proof yet.

Shared record rules preserve left-to-right field effects and field projection.
Tests distinguish reading before and after a mutation and reject a wrong
projected result. Contract matching now normalizes metadata and resolved
metavariables before comparing facts, so those tests reuse the proved mutation.
A generic counted-local rule handles temporary scopes, fresh cells, and counter
increments; its shadowing test passes. This removes 41 lines from the text
proof without weakening its full public contract. The text proof/glue is still
about 17.7 times its 21-line implementation, and total Lean grows; compactness
remains unfinished.

The final connected gate passes 29 Lean/x86 fixtures, including all sixteen
hex digits, negative words, unaligned output, and canaries; 22 source audits,
11 trap cases, and malformed-input checks also pass. Its elapsed time is 75.58
seconds. The fresh self gate takes 30.88 seconds, including 4.69 to emit, 12.43
to admit, and 8.21 for the combined contracts. These are validation timings,
not a claimed speedup. All successful contracts use only standard Lean logical
axioms. Whole-printer preservation, frontend/lowering correctness, x86/runtime
refinement, and the explicit trusted-output boundary remain open.
Five wrong-behavior mutations still admit as ordinary Lean data but fail their
relevant contracts: counter increment, string input, final cursor, hex digit,
and swapped cursor fields. None produces a successful proof artifact.
See [NOTES.md](NOTES.md) for domains, mutations, and matching-scope line counts.

Latest full text-call checkpoint (September 29): `actualCall_copies` proves the
actual public `lean_output::text` call in Core semantics, from string storage
and packed-length calculation through raw-slice construction, copying, return,
and caller restoration. It writes exactly the input's UTF-8 bytes, terminates,
and preserves old cells, world, and views. Its domain requires readable packed
output, enough capacity below 2^31, well-formed cells, a valid heap frontier,
unique block bases, and no registered views. It derives the internal operations;
it does not assume they succeed. Empty input and a multiword UTF-8/NUL example
pass, including canaries and restored caller locals. Substituted input or an
incorrect return value admits as data but fails the public contract.

The proof checks in 4.29 seconds against fresh writer output, with shared rules
built. The same byte/packing/text proofs check in the fresh 950-function self
module in 7.62 seconds, using only standard Lean logical axioms. The self gate
takes 33.12 seconds: emission 4.59, admission 12.84, plus proofs and setup.
The connected gate passes 29 Lean/x86 fixtures, 22 source audits, 11 trap cases,
and malformed-source rejection in 71.61 seconds.
No performance improvement is claimed. The text proof/glue is still about
twenty times its 21-line source function, above the compactness target. Shared
framing now transports local lookups across pure calls, but the loop interface
must become smaller before this pattern spreads across the printer. Whole
printer/compiler correctness, x86/runtime refinement, and the explicit trusted
execution/import boundary remain open. See [NOTES.md](NOTES.md) for evidence.

Latest text-entry checkpoint (September 29): the actual host `packed_words`
function now has a general call contract for exact ceiling division throughout
the nonnegative i32 range and rejection of negative inputs. Its old expression
overflowed near the signed limit; the revised source and native limit regression
pass. The full text rejection call is also proved from its input guard, without
buffer-validity or successful-execution assumptions. Shared call framing avoids
repeating parameter and scope bookkeeping. Both new contracts pass in the full
self-extraction with only standard Lean logical axioms, and deliberately wrong
arithmetic/guard mutations fail. The 29-case Lean/x86 gate passes in 74.78 seconds;
22 source audits, 11 traps, and malformed-source checks pass. The new host fixture
is outside the independent source checker's intrinsic fragment. Self-emission
takes 4.01 seconds, Lean admission 13.26, and the combined writer/packing proofs
5.90. The successful text setup and return still need connection to the loop;
the whole printer/compiler proof and compactness target remain unfinished.
See [NOTES.md](NOTES.md) for domain, evidence, and line accounting.

Latest text-writer checkpoint (September 28): the actual extracted copying loop
now has a total-correctness proof for arbitrary supported lengths and byte
contents, composing the byte-writer contract. It proves exact destination bytes
and the memory/caller frame from disjoint readable packed buffers, capacity
bounds, well-formed cells, unique block bases, and no registered views. The
source uses one counter instead of redundant input/output cursors. A multiword
instance covers unaligned output, UTF-8/NUL, and a canary; the corresponding
runtime fixture also checks empty input and rejection. Changed increments or
destinations admit as data but fail the connected proof. Text checks in 1.14
seconds, and byte/text proofs together check in the full self-module in 3.82.
The 28-case integration gate passes in 60.16 seconds. The self gate takes 26.98
seconds, including 4.38 emission and 12.59 admission; no controlled speedup is
claimed. The text call's setup, rejection, return, and wrapper are not yet proved,
and the source-specific proof is about 21 times the loop, above the compactness
target. See [NOTES.md](NOTES.md) for assumptions, accounting, and next work.

Latest proof-architecture checkpoint (September 28): the byte writer's full
success/rejection call contracts now check in the actual 950-function
self-extraction, not only the small fixture, with the same proof source.
Closed lookup proofs go through kernel-checked reflexivity; syntax-directed
proof search avoids unfolding the interpreter while matching contracts.
No new axioms, lookup index, or normal-output typing evidence is introduced.
The contracts take 3.17 seconds standalone and 3.44 in the updated self gate;
the small-fixture check takes 3.29 seconds. Source-specific proof/glue falls
from 214 to 131 lines, still about twelve times the implementation; shared
automation and tests grow, so total Lean does not shrink. All three existing
writer mutations still fail. The self gate passes in 28.35 seconds, including
4.09-second emission and 14.76-second admission; this is not a claimed emission
speedup. The 28-case Lean/x86 gate passes in 68.01 seconds. The raw-storage
premises and general correctness gaps remain.
See [NOTES.md](NOTES.md) for scope, accounting, and evidence.

Latest representation checkpoint (September 28): raw i32 slices now retain
their pointer/length descriptor in Core, matching native records and the x86
constructor. Creating one no longer copies the heap into a backing cell or
registers a redundant array view. The existing exact-block bounds, alignment,
liveness, and borrowing checks remain. Taking the pointer of a slice loaded
from a native record also works; previously this returned 37 in the new x86
regression but trapped in Lean. Both now return 37. Genuine cell-backed array
aliases still synchronize in both directions. A general constructor theorem
derives the result from allocation metadata, and the writer regression uses
it before applying the call contract. Focused constructor/alias checks take
0.86 seconds; the connected alias program checks in 0.67 seconds and writer
contracts in 3.10 seconds. The fresh-output gate passes 28 Lean/x86 cases in
62.00 seconds. General alias coherence, tool correctness, and the trusted-output
boundary remain open; no self-extraction speedup is claimed. See [NOTES.md](NOTES.md).

Latest proof checkpoint (September 28): the actual extracted `lean_output::byte`
now has success and rejection contracts at the function-call boundary. Given
an in-bounds raw output buffer, unique heap block bases, and no registered
cell-backed i32 views, the call writes exactly one byte and returns the next
cursor. It preserves other bytes, raw aliases, allocation metadata, caller
locals and existing cells, and world state; fresh parameter/local cells may
remain. Invalid cursor/value inputs return -1 without accessing the buffer.
Entry arithmetic, the store, return, and call composition are proved, not
assumed successful. Only standard Lean logical axioms are used. The connected
contracts check in about 3.4 seconds with shared infrastructure built.
At that checkpoint the 27-case integration gate passed in 59.18 seconds; incorrect
return, destination, and rejection-bound mutations fail the connected proofs.
Registered-view synchronization and the general implementation/provenance
connection remain open. The source-specific proof is still about 19 times the
eleven-line function, above the compactness target. This is not a general
extractor/compiler theorem or an emission speedup. See [NOTES.md](NOTES.md).

Latest semantics checkpoint (September 28): packed string views now agree with
the native runtime's zero-padded final i32 word. Previously a word view of the
one-byte string `"%"` returned 37 in x86 but trapped with `rawMemoryBounds` in
Lean. The model now gives a fresh string view its rounded storage extent while
preserving logical UTF-8 contents. General prefix/length lemmas check in the
kernel; ordinary raw-block bounds and ownership rules are unchanged. The
27-case connected gate passes, including the extractor's actual `lean_output::text`
function, with 22 source audits, 11 traps, and 16 malformed-source cases.
The focused writer execution proof takes 1.44 seconds. This repairs a concrete
semantic gap; it is not the general runtime/compiler proof or a speedup.
See [NOTES.md](NOTES.md) for the allocation diagnosis that exposed it.

Latest generation checkpoint (September 28): parser insertion no longer returns
unused fields or constructs a completion action before replacing it for an
incomplete state. The parser shrinks by nine lines, with no new cache or change
to its workspace limits. On identical input, generation instructions decrease
by 2.7% in the GPU-built extractor and 2.4% in the Lanius-built one; complete
Lean output is byte-identical. Both builds pass the 25-case connected gate,
source audits, traps, and malformed-input checks. Fresh self-extraction covers
950 functions and 666 constants: 3.99 seconds to emit, 12.04 to check/compile/write,
and 21.75 for the diagnostic. The lower Lean wall time is not a controlled
speedup from this change. General correctness and the performance goal remain
open. See [NOTES.md](NOTES.md), including the native allocation discrepancy.

Latest notation checkpoint (September 28): record construction resolves field
names instead of silently treating initializers as positional. Reordered and
nested proof-side records now match Lanius's declaration-order lowering;
ambiguous names reject, without adding initializer type checking. The focused
regression takes 0.82 seconds, and all 25 connected Lean/x86 cases, 22 source
audits, 11 traps, and malformed-source checks pass. Full self Core is unchanged;
instruction work is effectively unchanged. This closes a readable-notation
correctness gap, not a general compiler theorem or the performance goal.
See [NOTES.md](NOTES.md).

Latest admission checkpoint (September 28): closed source-function definitions
use Lean's nonrecursive declaration API, avoiding irrelevant recursive closure
conversion while retaining kernel checks and compilation. Generic, dependent,
attributed, and module-system definitions keep ordinary elaboration. On identical
input, checking uses 10.2% fewer instructions and the complete evaluated Core
is unchanged; varying wall times do not establish a fixed latency gain. Focused
definition/import tests and the 25-case Lean/x86 gate pass. The fresh self-run
contains 951 functions and 666 constants: 4.60 seconds to emit, 15.80 to
check/compile/write, and 27.73 for the diagnostic including setup and its
optional audit. No general correctness theorem or few-second completion is
claimed. See [NOTES.md](NOTES.md).

Latest representation checkpoint (September 28): each emitted record or enum
has one nominal kind/ID annotation instead of two metadata instances. Native
constructors remain the source of field names and positions. On identical
input, 532 generated declarations disappear and the full evaluated Core is
unchanged. Fresh checking uses 2.3% fewer instructions, without an established
wall-time improvement. Both extractor builds pass 25 Lean/x86 cases, 22 source
audits, 11 traps, and malformed-source rejection; imported generated types
retain their proof and notation support. The current self-run has 951 functions
and 666 constants: 4.68 seconds to emit, 15.43 to check/compile/write, and 27.13
for the diagnostic with setup and its optional audit. No general correctness
theorem, new trust assumption, or few-second completion is claimed. See
[NOTES.md](NOTES.md).

Latest migration checkpoint (September 28): the unused raw Core body printer,
subtree-definition writer, and token-to-byte-array serializer are deleted.
Live operator metadata, slice-layout checks, and UTF-8 validation now have
dedicated owners; no compatibility wrappers remain. The complete import audit
passes with 79 extractor, 107 compiler, and 116 combined units. The GPU and
Lanius-built extractors preserve byte-identical Lean on the unchanged 81-file
input and agree on current self-output. Both pass 25 Lean/x86 cases, 22 source
audits, 11 traps, and malformed-source rejection. The cleanup exposed a GPU
parser bug that paired comparisons across statements as generic arguments;
the boundary fix passes a minimized regression and genuine generic-call checks.
Fresh self-extraction takes 4.87 seconds to emit, 14.66 to check/compile/write,
and 25.52 for the full diagnostic. The smaller implementation contains 952
functions and 666 constants; no reachable source was omitted. These results
do not establish a same-input admission speedup or complete the general
correctness proofs, trust boundary, or few-second target. See [NOTES.md](NOTES.md).

Latest investigation (September 28): pass-level and notation-level profiling
found no single dominant optimizer or field-lookup cost. Two small trials were
rejected; production code is restored and the shared tests pass. No new speedup
is claimed. The detailed measurements and ruled-out approaches are recorded in
[NOTES.md](NOTES.md).

Latest Lean checkpoint (September 28): the shared native constructor-data hook
avoids optional optimizer scans and duplicate optimizer-cache bodies. Kernel
definitions and executable code remain intact. The cache change takes an
identical fresh module from 16.48 to 14.09 seconds in paired runs, with 2.3% fewer
instructions; serialization falls from 2.65 to 1.15 seconds. Complete evaluated
Core matches, and cross-module proofs, interpreted execution, and native
execution pass. The 24-case Lean/x86 gate, 21 source audits, 11 traps, and
malformed-source rejection also pass. The integrated current-source run takes
4.48 seconds to emit, 16.44 to check/compile/write, and 26.96 for the diagnostic
including setup and the optional audit. Wall times vary; this is a modest reduction in work, not
the few-second target or a general correctness theorem. See [NOTES.md](NOTES.md).

Latest generation checkpoint (September 28): qualified function and enum-variant
lookup now reuse the existing shared name index instead of scanning global
declarations. Full spelling, module, import, privacy, and ambiguity checks remain.
On identical frozen input, extraction uses 21.6% fewer instructions in the
GPU-built executable and 22.7% fewer in the Lanius-built one. All four before/after
Lean outputs are byte-identical. Both builds pass 24 Lean/x86 cases, 21 source
audits, 11 traps, and 16 malformed-source cases, plus focused index and visibility
checks. Current self-output is identical between both builds; fresh emission
takes 4.86 seconds, Lean check/compile/write takes 16.19, and the diagnostic takes
26.91 including setup and its optional audit. This is a generation improvement,
not a completed correctness proof or the few-second Lean-admission target.
See [NOTES.md](NOTES.md) for measurements.

Latest semantic checkpoint (September 28): function bodies now accept the
signed-minimum literal `-2147483648`, using the same magnitude parser as
constants. Readable Lean preserves it as one Core literal, and the independent
source checker constructs the existing signed-minimum lowering proof. Ordinary
negation stays unchanged; positive overflow and negative underflow still reject.
Both extractor builds pass twenty-two default Lean/x86 cases, nineteen source
audits, eleven trap cases, and sixteen malformed-source cases. Signed wrapping,
division/remainder boundaries, and short-circuiting over a trapping operand are
covered. Full native/GPU self-output is identical; the preceding frozen output
is unchanged. The fresh self-run takes 5.90 seconds to emit, 16.42 seconds to
check/write, and 28.10 seconds overall. No speedup or general compiler theorem
is claimed. See [NOTES.md](NOTES.md) for the literal-module move and proof scope.

Latest correctness checkpoint (September 28): primitive `Bool`, `String`, and
`Unit` labels now use Lean's root namespace. Previously a source record named
`Bool` with a primitive `bool` field extracted to an accidentally recursive
Lean type; a `String` record had the same defect. The old output could execute
the expected result while describing the wrong field types. Constructor-type
checks reproduce the defect, and the fixed output passes those checks and
independent source agreement. Both extractor builds pass twenty-one default
Lean/x86 cases and eighteen source audits. The full frozen Core is unchanged
outside this regression. Fresh current self-extraction takes 5.80 seconds to
emit, 15.87 seconds to check/write, and 27.36 seconds for the complete diagnostic.
This is a correctness fix, not a claimed speedup or completed general theorem.

Latest validation checkpoint (September 28): the connected fixture gate now
checks the default direct output, rather than substituting `--lean-checked`
output. All twenty default programs and entrypoints are kernel-checked equal
to their checked-mode counterparts, execute as expected in Lean and x86, and
seventeen pass independent source agreement against the default Core data.
Both the GPU-built and Lanius-built extractors pass. A mutation confined to
default output (`Some(7)` to `Some(8)`) is rejected while checked output is
unchanged. This closes a coverage gap, not a compiler bug or general theorem.
The connected gates took 24.28 and 25.66 seconds; these are test-suite times,
not new self-extraction or admission measurements. See [NOTES.md](NOTES.md).

Latest admission checkpoint (September 28): emitted nominal types no longer
generate unused `SizeOf` functions and specification lemmas. The option is
limited to their declaration section; constructors, recursors, and equality
lemmas remain, and later Lean declarations retain normal defaults. Proofs can
derive `SizeOf` explicitly when needed. On identical full input, this removes
1,256 auxiliary declarations and reduces checking instructions from 108.16 to
100.51 billion (7.1%); paired wall times are 18.64 and 16.07 seconds. The complete
evaluated Core is unchanged. Twenty Lean/x86 cases, seventeen source audits,
and focused native-proof-support checks pass. The fresh current self-run has
988 functions and 674 constants: 5.34 seconds to emit, 16.25 seconds to
check/write, and 27.15 seconds including setup and an optional audit.
This remains above the few-second target and closes no general tool theorem.

Latest function checkpoint (September 28): the emitter defines each function
once, and calls use that declaration's name. A `mutual functions` block supports
forward and recursive calls without separate `.ref` declarations. Its temporary
name-to-ID index comes from the existing headers; it contains no bodies or
typing evidence. Ordinary Lean still checks and compiles every definition.
On the frozen 992-function input, all evaluated Core data is unchanged; Lean
source decreases by 223,257 bytes and the artifact by 1,080,616 bytes. Measured
instruction work is roughly unchanged, not a substantial performance win.
The current self-run has 988 functions and 674 constants: 5.90 seconds to emit,
16.47 seconds to check/write, and 28.09 seconds including setup and the optional
audit. Twenty Lean/x86 cases and seventeen source-agreement audits pass. The
few-second target and general tool-correctness proofs remain unfinished.

Latest representation checkpoint (September 28): each named Lean constant now
owns its Core declaration and literal value. The program links those declarations
directly; the separate value table and reference-only API are gone. On identical
source, the complete evaluated Core is unchanged and checking uses 2.2% fewer
instructions, with similar wall time. Twenty Lean/x86 cases, seventeen source
audits, constant-value mutation checks, and the native bootstrap comparison pass.
The fresh self-run contains 990 functions and 674 constants: 6.25 seconds to
emit, 18.07 seconds to check/write, and 31.41 seconds including setup and the
optional audit. This simplifies the representation; it does not meet the
few-second target or complete the tool-correctness proofs.

Latest admission checkpoint (September 28): `lake run checkExtraction -- ...`
builds and loads the native shared notation, then runs ordinary Lean on the
fresh program. On identical input it reduced checking instructions by 5.4%;
paired checks took 14.82 and 14.41 seconds. The complete evaluated Core is
unchanged, and all twenty Lean/x86 cases and seventeen source audits pass.
The latest full self-run took 6.88 seconds to emit, 16.82 seconds to check/write,
and 29.40 seconds including setup and the optional audit. This is a modest
reduction in work, not a large wall-time improvement or the few-second target.
No per-program phase is skipped or deferred. See [NOTES.md](NOTES.md) for the
shared-build metadata correction and the remaining proof obligations.

Latest bootstrap correction (September 28): the GPU compiler now preserves
resolved nominal identities when choosing aggregate layouts, including local
bindings, parameters, and alias chains. A struct/enum legacy type-code collision
had truncated a nested enum from five words to three in the failing extractor.
The minimized regression fails with the old shaders and passes with the fix in
both compilers. The rebuilt tools pass twenty Lean/x86 cases and seventeen
source-agreement audits; full self-extraction is byte-identical to the preceding
checkpoint. This closes the reproduced bootstrap discrepancy, not a general
GPU/compiler correctness proof. No new performance result is claimed.

Latest source-validation checkpoint (September 28): the shared name index now
rejects unused duplicate function/external declarations in a source unit, before
either output is emitted. Previously x86 accepted these programs and extraction
produced duplicate Lean definitions. Twenty Lean/x86 cases and seventeen source
agreement audits pass, including colliding hash keys and same-spelled functions
in different modules. Four new malformed-source fixtures reject in both Lean
output modes and x86. The full self-run covers 992 functions and 674 constants:
5.46 seconds to emit, 15.88 seconds to check/write, and 28.09 seconds including
setup and an optional audit. Added generation work is below 0.001% on unchanged
valid input, whose complete output is preserved. This closes a rejection bug,
not the general correctness proofs or the few-second admission target.

Latest native-code checkpoint (September 28): immediate record-field reads no
longer copy the entire record. Values that must survive later mutation still
get snapshots. On identical input, the Lanius-built extractor uses 47.55 rather
than 67.32 billion instructions (29.4% fewer), taking 6.93 rather than 9.73
seconds in paired runs with byte-identical Lean output. Its ELF shrinks from
3.06 to 2.09 MB. Eighteen Lean/x86 cases, fifteen source-agreement audits,
four arithmetic traps, the uninitialized-field trap, and native workspace
checks pass. The fresh native self-run takes 7.50 seconds to emit, 17.05 seconds
to check/write Lean, and 31.02 seconds including setup and an optional audit.
This does not speed up Lean admission or close the general correctness proofs.
See [NOTES.md](NOTES.md) for snapshot-mutation tests and rejected experiments.

Preceding performance checkpoint (September 28): one typed nominal-candidate
catalog removes repeated declaration-kind scans. On identical input, generation
took 7.05 versus 5.67 seconds for the GPU-built extractor and 11.95 versus 8.42
seconds for the Lanius-built executable, with 21.5% and 23.6% fewer instructions.
All four outputs are byte-identical. The fresh current-source run covers 991
functions and 674 constants: 5.49 seconds to emit, 15.68 seconds to check/write,
and 27.85 seconds for the diagnostic including setup and an optional typing
audit. This is a generation improvement, not a new Lean-stage speedup.
Seventeen Lean/x86 cases, fifteen source-agreement audits, four trap cases,
malformed-source rejection, and the nominal catalog/visibility tests pass.
See [NOTES.md](NOTES.md) for the comparison, rejected experiment, and limits.

Preceding functional checkpoint (September 28): the Lanius-written x86 compiler
produces the full extractor executable, which self-extracts to byte-identical
Lean compared with the GPU-built extractor. Sixteen Lean/x86 cases, fourteen
independent source-agreement audits, four arithmetic-trap cases, malformed-source
rejection, and the large native-workspace regression pass. This is executable
validation, not a general compiler-correctness theorem or a verified bootstrap.
The compiler itself is still built by the GPU compiler.

The native-built extractor's fresh full diagnostic took 18.05 seconds to emit,
21.26 seconds to check/write Lean, and 48.69 seconds overall. A paired generation
comparison on identical inputs measured 7.22 seconds for the GPU-built extractor
and 15.62 seconds for the Lanius-built one, with 50.83 versus 88.08 billion user
instructions. The faster GPU-built extractor remains the default. General
correctness proofs and the few-second target remain unfinished; see [NOTES.md](NOTES.md).

Preceding performance checkpoint: ordered parser action queues reduce native
emission work by 15.2% (60.76 to 51.55 billion user instructions) on identical
input, with byte-identical Lean output; that run took 7.77 versus 6.70 seconds.
The fresh current-source run covers 990 functions and 674 constants:
7.51 seconds to emit, 14.37 seconds to check/write, and 27.42 seconds for the
full diagnostic script. No Lean-stage speedup is claimed from this parser
change. Fourteen Lean/x86 fixtures, twelve source-agreement audits, focused
parser checks, and malformed-source rejection pass with rebuilt binaries.
Parser scratch grows from 96 to 120 MiB to preserve state capacity. General
correctness proofs and the few-second target remain unfinished.

The preceding representation checkpoint: native Lean declarations supply both
body name resolution and the linked Core type declarations. Separate emitted
Core type tables and per-member instances are gone; per-type IDs remain.
The actual printer preserves the complete evaluated Core on identical input.
Current-source self-extraction takes 8.47 seconds to emit and 19.25 seconds to
check/write, or 34.27 seconds for the full diagnostic script. It covers 989
functions and 673 constants; obsolete printer functions were deleted, not
omitted from extraction. Fourteen Lean/x86 execution cases and twelve
exact-source audits pass. The latest linking change simplifies the architecture
but does not establish a speedup. The general correctness proofs and few-second
target remain unfinished.

## Current direct-extraction architecture

Normal extraction now emits readable, proof-free Core program definitions
through the Surface notation. The Lanius extractor and x86 compiler still
share the same typed IR. Lanius checks source argument types, arities, scopes,
returns, literals, and nominal payloads; the emitted Lean does not reconstruct
those judgments.

Surface expressions retain phantom source-type labels for readable notation,
not dependent scope/signature indices or typing evidence. Calls take an
ordinary argument list and reference the function declarations themselves.
The shared notation resolves forward-call IDs from those declarations' headers,
without lookup proofs or a second emitted reference table. Named
constants own ordinary Core declarations; the linked list uses those same
declarations rather than a second value table. There is no emitted signature authentication index,
intrinsic program, second typing tree, or automatic program-typing theorem.
No new axioms or kernel-checking bypasses were introduced.

The shared notation now constructs Core nodes directly, without expanding each
function into nested generic builder calls. Each public function stores its
source name and one Core declaration. Lanius still owns argument and return
type validation; the notation only resolves the labels needed to read names.
Native inductive declarations supply constructor and field information; there
is no separate generated `Constructor` or `Field` instance for each member.
Per-type Core ID instances remain. Private, generic, aliased, mutually recursive,
and reserved-name labels pass focused checks. See [NOTES.md](NOTES.md) for the
fixed-input semantic comparison and fresh-check conditions.
The emitter disables automatic `SizeOf` generation only for these nominal
declarations. Native constructors, induction and equality support are preserved;
`deriving instance SizeOf for SomeType` remains available to a proof that needs
a structural size.
The `link` notation derives Core nominal declarations from those same native
types, preserving IDs, payload order, and unused declarations. Constants and
functions are supplied directly; linking introduces no typing proofs.

On September 27 the full self-module contained 996 functions and 671 constants
from 80 source units. Fresh emission took 18.89 seconds. With shared Lean
infrastructure already built, one fresh module checked and wrote its artifact
in **38.38 seconds**, compared with 87.27 seconds for the prior representation.
The artifact is 46,900,192 bytes. These are full-module measurements, not sums
of cached body checks. Emission also takes longer than desired, and
the fresh Lean check is not yet seconds-scale.

The profile records 22.2 seconds of elaboration, 3.69 seconds of typeclass
inference, 1.62 seconds of interpretation, 1.31 seconds of kernel checking,
about 8.6 seconds of Lean compilation, and 4.55 seconds of artifact writing.
Categories overlap and must not be added as wall-clock phases.

A follow-up removed unused parameter-type lists from function references;
function declarations still retain their full signatures. Its final check took
35.58 seconds. Direct Core construction then reduced the current-source fresh
check to **21.65 seconds**, with emission at **17.57 seconds**. The full script,
including source-closure setup and the separate typing audit, took 45.23 seconds.
The current profile reports 7.53 seconds of elaboration, 1.09 seconds of kernel
checking, about 7.2 seconds of Lean compilation, and 3.52 seconds of artifact
writing. Categories overlap. Shared infrastructure was built beforehand;
the program itself was regenerated and checked as one fresh module.

The native generation follow-up removed repeated constant-resolution work in
shared lowering. On an identical frozen source closure, generation fell from
17.24 to 11.70 seconds with byte-identical Lean output. A fresh run on the updated
sources took **12.25 seconds to generate**, **20.89 seconds to check/write**, and
**39.05 seconds overall**, including setup and the optional 453 ms typing audit.
The module still contains 996 functions and 671 constants. No typing proofs or
new trust assumptions were added. This remains above the few-second target.

The twelve-program gate, ten source-agreement audits, constant-dependency and
mutation checks, and expanded visibility/shadowing gate pass. The latter requires
clean rejection in both extraction modes and x86; a crash is not a passing test.
See `target/verified-compiler/resolution-self.log` for the fresh profile.

The subsequent parser optimization caches grammar actions and indexes duplicate
states while preserving the insertion-ordered chart queue. The latest fresh
self-run took **9.40 seconds to generate**, **19.92 seconds to check/write**, and
**35.21 seconds overall**, including setup and the optional 433 ms typing audit.
It contains 997 functions and 673 constants. The fixed-input comparison measured
11.62 versus 10.53 seconds for generation and produced byte-identical Lean.
The shared parser workspace grows from 64 to 96 MiB to retain its prior state
capacity. These are performance and regression results, not a new parser proof.

The production parser passes an exhaustive 511-input short-token corpus plus
nullable, ambiguity, hash-collision, split-token, and capacity/canary checks.
The twelve-program Lean/x86 gate, ten exact-source audits, and malformed-source
rejections pass with rebuilt binaries. The fresh profile is in
`target/verified-compiler/parser-self.log`; see [NOTES.md](NOTES.md) for the
scratch-memory tradeoff and the unresolved bootstrap aggregate-layout issue.

On September 28, defined-function parameters moved to direct name/ID binders.
The notation takes their labels from the existing function signature and builds
the Core parameter list directly; it no longer elaborates a second dependent
`Vars` list or emits a Lean `Var` binding for every parameter. Captured IDs,
computed/generic signatures, shadowing, and parameter ordering pass focused
tests. Runtime imports retain the existing `Function.external` helper.

The fixed-program Core snapshot is byte-identical across this change, including
all 997 functions and 673 constants. Generated Lean is 2,524 lines shorter and
checks freshly in 17.89 seconds. The latest fresh run on current sources took
**9.77 seconds to emit**, **18.29 seconds to check/write**, and **33.87 seconds
overall**, including setup and the optional 432 ms typing audit. It contains
996 functions and 673 constants because the obsolete printer helper was removed.
The twelve-program Lean/x86 gate, ten source-agreement audits, and malformed
rejections pass. See `target/verified-compiler/direct-parameters-self.log`.
The few-second target and general tool-correctness proofs remain unfinished.

The subsequent constant-lookup change reuses the module declaration spans
already checked by shared lowering. On identical input, generation fell from
11.58 to 9.38 seconds with byte-identical Lean output. The fresh current-source
run passed with 996 functions and 673 constants: **9.76 seconds to emit,
23.21 seconds to check/write, and 39.97 seconds overall**, including setup and
the optional 468 ms typing audit. The higher Lean time also affected the old
program: paired fresh checks in the same session measured 24.71 seconds before
and 24.22 after. This change improves native lookup, not Lean admission.
See `target/verified-compiler/owner-spans-self.log` and [NOTES.md](NOTES.md).

A fixed-program comparison before and after the notation rewrite produced
byte-identical complete Core snapshots. The generated program definition now
has no axiom dependencies. Neither result proves general extractor or compiler
correctness. See [NOTES.md](NOTES.md) for discarded experiments and trust limits.

Validation:

- Twenty emitted programs execute with the expected results in Lean and x86,
  including `Some(7)`, unsigned arithmetic, and string literals. Seventeen also
  pass exact source-to-Core agreement through
  the independent checker. Raw-slice construction and pointer arithmetic are
  outside that checker's current fragment; the three memory fixtures have
  execution checks, not a source-agreement proof.
- Four unsigned arithmetic cases trap as expected in Lean and x86: shifts by
  64 and 2^32, division by zero, and remainder by zero. The Lanius-built extractor
  passes the connected gate and emits the full self-module identically to the
  GPU-built executable. Native workspace tests cover programs exceeding the old
  global event cap, accumulated fixups, capacity rejection, and a memory canary.
  Field-projection tests retain initialization traps and snapshots across
  mutating arguments and index expressions; two snapshot-dropping mutants fail.
- Constant lookup retains exact module ownership, import visibility, local
  shadowing, and ambiguity rejection. Same-named constants in two modules
  resolve correctly when qualified; an unimported candidate is ignored, and
  two imported bare candidates fail in either source-unit order. The constant
  dependency/cycle and seven changed-value mutation checks also pass.
- The connected fixture gate rejects wrong call
  argument types, arities, result types, unknown locals, and wrong enum payloads
  in both extraction modes and in the x86 compiler. It also rejects unused
  duplicate functions/externals, without conflating distinct hash-colliding
  names or same-spelled functions from different modules.
- Constant preservation, seven changed-value mutations, and trapping/range
  rejection passed in 20.72 seconds. Public namespaces and source agreement
  passed separately.
- The optional independent self-typing audit passed (425 ms in the latest
  self-run). This is test evidence, not an emitted theorem or an
  admission requirement.

The typechecker/extractor correctness proofs and explicit trusted-output
import contract are still unfinished. The generated definitions represent a
program about which Lean proofs can be written; they do not by themselves
prove source agreement or x86/compiler correctness. See [NOTES.md](NOTES.md).

The migration exposed missing definite-return validation in Lanius: non-unit
functions could reach the end, and the old Lean representation was catching
that later. Shared IR validation now rejects missing returns, one-sided returns,
and loop-only returns. Unit fallthrough and valid branch/loop continuations
remain accepted. The fixture gate covers fourteen malformed-source cases in both
extraction modes and x86. The separate runtime-import gate also passed, including
six same-signature service substitutions under forged policies.

## Connected proof currently available

For an accepted version-3 certificate, the Lean checker now connects:

1. exact source bytes to checked lexer, grammar, parse, Surface, declaration,
   import, and typing evidence;
2. the reconstructed Surface program to an authenticated typed Core lowering;
3. canonical Core transport, certificate-owned ELF bytes, and exact function
   spans to the currently accepted x86 backend fragment;
4. ELF startup, the selected zero-argument Core entrypoint, its uniform return
   state, and the return-to-syscall suffix.

The actual certificate encoder and decoder have a generic round-trip theorem
under explicit representability bounds. Accepted round trips recover the exact
compact payload, transport words, ELF bytes, and ordered function spans.

The native Lanius compiler's full `--certificate` mode is exercised by a
two-function source and accepted by the same checker with 34 transport words,
529 ELF bytes, and two ordered function spans.  The resulting one- and
two-function artifacts also pass the startup/entry-slice checker used by the
public x86 execution theorem.  This is connected evidence for the real output
path, while the general theorem about the Lanius generator itself remains
open.

The native Lanius extractor now emits Lean Core directly by default from the
semantic IR shared with x86 compilation. `--lean-checked` also emits a typed
frontend artifact that the independent Lean checker validates against source
bytes, lexer traces, grammar derivations, and reconstructed Surface. This
checked path is practical for small connected programs; the full extractor
closure's parser derivation is too large for routine per-program checking.
The compiler's explicit `--certificate` mode still supports the separate
legacy backend proof while its migration remains open.

Shared lowering now returns only `ir::program::Program`: it has no output
buffer, serialization mode, or transport-word result. `lowering/program.lani`
owns the pipeline and `lowering/functions.lani` assembles the function catalog;
their contents moved from the old transport-named files, without wrappers.
Only the compiler's explicit certificate branch invokes the Core serializer.
Normal x86 mode allocates no transport buffer. The extractor's actual import
closure excludes both Core wire writers; its source inventory also no longer
includes the unrelated compact-output and parse-tree modules. Import-graph
checks confirm 89 extractor units, 105 compiler units, and their 116-unit union.

The moved boundary passes function-order and malformed-catalog tests, bundle
storage and body-unit tests, and the public Lean/x86 and constant-rejection
gates. The representative `Some(7)` extraction is byte-identical to the previous
extractor, passes exact source agreement, and returns 7 in Lean and x86. The
two-function certificate is also byte-identical and remains accepted by the
independent checker (30 transport words, 529 ELF bytes, two function spans).
The fresh 89-unit self-check passed in 106.75 seconds: 18 seconds for emission,
84 seconds for the Lean module, and 0.810 seconds for independent Core typing,
plus setup. It contains 1,120 defined functions, nine runtime imports, and 748
constants; generated Lean is 9.28 MB and its compiled artifact is 123.34 MB.
This checks the actual smaller dependency closure, not a fixed-input speedup;
the large-module checking target remains unmet.

Constant lookup evidence is now demand-driven, like function and nominal
lookups. The existing supported-body scan marks constant references, and the
emitter writes each needed lookup once. All constant declarations and their
typing proofs remain. The current self-extraction has 587 constant lookup
lemmas instead of 748: no emitted lookup is unused by the body proofs, and no
used lookup is missing. The focused constant gate passed in 12.27 seconds,
including an unreferenced constant retained in the proof-carrying program and
seven independently changed constant values rejected by the source checker.
The representative `Some(7)` still passes exact source agreement and returns
7 in Lean and x86.

The demand-driven-lookup self pipeline passed in 99.53 seconds: 19 seconds for native
loading/lowering/emission, 76 seconds for the Lean module, and 0.745 seconds
for independent Core typing, plus setup. It covers 1,122 defined functions,
nine runtime imports, and 748 constants. Generated Lean is 9.23 MB and its
compiled artifact is 123.26 MB. Do not infer a large speedup from the earlier
84-second module result: an unchanged input also checked in 76.44 seconds
during the sampling run. The definite improvement is removing 161 unnecessary
lookup obligations without removing any program data or typing coverage.

Phase markers in an otherwise identical native extractor measured 7.84
seconds for loading/frontend work, 12.32 seconds for lowering, and 0.76 seconds
for Lean rendering. Its output matched the uninstrumented extractor byte for
byte. A complete declaration-value profile checked freshly in 79.18 seconds;
its overlapping worker times were 101.13 seconds for function typing proofs,
60.89 seconds for lookups, and 22.64 seconds for source-shaped function bodies.
These are not additive wall-clock phases. Sharing fixed lookup arguments gave
78.15 seconds on the same input, not a convincing improvement. Position-based
lookup and explicit-recursion prototypes did not produce a substantial local
gain; they and the direct-reflexivity experiment remain outside production.
CPU samples resolved leaf symbols but lacked usable Lean caller stacks, so
they do not establish which caller causes the allocation/reduction costs.

The full self-extraction now carries a kernel-checked `ProgramWellTyped`
proof: all 1,129 defined functions and nine runtime imports are covered.
Runtime calls use the existing call rule; each import proves its parameter
and return types match the named host service. The emitter composes the
function proofs through the existing 18 declaration groups and `CheckedList`
lemmas. `extractedTypedProgram` is then `some extractedVerifiedProgram`, not
a fresh execution of the recursive typing checker. The independent checker
still runs as a separate test. This proves typing, not the implementation
semantics of host services or universal compiler correctness.

Closing that gap exposed a scope error in readable emission: a nested block
could extend its local declarations into the following statements. Explicit
nested `do` blocks now preserve both local scope and sequence grouping.
The nested-scope gate passes exact source-to-Core checking and returns 7 in
Lean and x86; the previous extractor fails on the regression. The runtime
gate now also passes exact source-to-Core checking for all nine supported
runtime imports. Explicit ABI/name pairs select the actual service; an
omitted ABI uses the supplied external policy. `ExternalFunctionLowering`
retains the binding proof alongside its existing source, signature, and
typing evidence. The policy is a 44-line shared module, not a separate proof
per imported function. A forged policy cannot override an explicit ABI.

The Lanius shared lowering reads the ABI from the retained parser tree,
decodes it with the existing string-literal decoder, and validates the runtime
signature before either output path runs. This fixes name-only service
selection and the extractor's acceptance of invalid runtime signatures.
No second parser pass or serialized intermediate representation was added.
The source checker also reuses existing literal rules for annotated `usize`
initializers and pointer/null comparisons; null pointers still cannot infer
their type from an unannotated integer expression.

The complete runtime gate passed in 14.90 seconds with shared infrastructure
already built. It checks fresh generated Lean, source agreement, allocator
signature rejection proofs, and x86 execution. Six same-signature service
substitutions fail both with the canonical resolver and with a resolver forged
to agree with the substitution. Unknown ABI/name, wrong ABI, parameter type,
return type, and arity each fail cleanly in default Lean, checked Lean, and
x86 modes. Omitted and escaped ABI spellings pass source agreement and x86
execution. The nested-scope regression passed in 4.75 seconds, and the public
`Some(7)` program still returns 7 in Lean and x86. These are source-binding
and typing checks, not proofs of operating-system service implementations.

Before runtime-binding changes, the fresh self pipeline passed in 105.58
seconds: 19 seconds for native
emission, 82 seconds for the Lean module, and 0.852 seconds for independent
typing, plus setup. It covers 748 constants and 1,132 functions; generated Lean
is 9.79 MB and its compiled artifact is 125.47 MB. The linked program's axioms
are only `propext`, `Classical.choice`, and `Quot.sound`. This closes the typing
coverage gap and fixes scope preservation; it is not a performance speedup.

After runtime binding and signature validation, a fresh self pipeline passed
in 104.36 seconds: 19 seconds for emission, 81 seconds for the Lean module,
and 0.854 seconds for independent typing. All 1,138 emitted functions have
typing proofs; generated Lean is 9.83 MB and its compiled artifact is
125.92 MB. The linked proof still uses only `propext`, `Classical.choice`, and
`Quot.sound`. The small timing difference is not evidence of a speedup.
Large-program checking and the complete backend migration remain open.

Runtime-service contracts no longer import native instruction emission or
wire decoding. `runtime/service.lani` owns the semantic identities and one
signature policy. The implementations moved to `backend/runtime.lani` and
`backend/runtime_record.lani`; internal callers use the new locations directly.
Record validation reuses the shared signature checks. No forwarding modules
or duplicate service policy were added. The extractor's actual import closure
now has 82 units instead of 89 and contains no x86 emitter modules. A new
import-graph check verifies both entrypoint inventories and their 118-unit
union against the checkout; the self-check runs it before emission.

All nine runtime-record signatures pass focused tests, including changed
types, truncated records, negative IDs, and duplicate IDs. The connected
runtime gate passed in 15.82 seconds, including wrong ABI/name/signature
rejection and six same-signature substitutions under forged policies. Ordinary
and checked Lean output and x86 images are byte-identical on the enum and
runtime fixtures. The two-function legacy certificate is also byte-identical.
The `Some(7)` example passes public Lean constructor proofs, exact source
agreement, Lean execution, and x86 execution.

The new self pipeline passed in 100.29 seconds: 17 seconds for emission,
78 seconds for fresh Lean checking, and 0.698 seconds for independent typing,
plus setup. It covers all 1,075 functions (1,066 defined and nine runtime) and
672 constants. Generated Lean is 9.24 MB and its compiled artifact is
119.03 MB. The linked proof still uses only the standard three axioms. This
removes an unnecessary dependency; it is not a fixed-input kernel speedup,
and the seconds-scale large-program check remains unmet.

The GPU bootstrap exposed another comparison-parsing failure in the unchanged
frontend emitter. Reversing its pure comparisons from `a < b` to `b > a`
restored the build without changing GPU code; the output comparisons above
cover both emission modes. A direct bootstrap attempt using the Lanius-written
compiler reached the backend but failed with exit code 11; it is not yet an
alternative bootstrap route for this closure.

Closed arithmetic constant initializers now pass the direct source checker.
`ConstantLowering` retains the initializer's elaborated Core expression and
its evaluation to the emitted value, rather than requiring arithmetic source
syntax to elaborate as a literal. The shared `ConstantEvaluates.evaluates`
theorem connects that evidence to the actual Core evaluator in every caller
state, preserving the state exactly. It uses the existing arithmetic semantics
for wrapping, signed division, and traps; no native-computation axiom was added.
The new semantics module is 59 lines and the expression checker is 80 lines;
the existing constant checker supplies the source/catalog and typing boundary.
There are no new per-program generated proofs or data formats.

The connected arithmetic fixture covers negative literals, signed minimum,
wrapping addition/multiplication, negative division/remainder, and a composed
initializer. Exact source checking and Lean/x86 execution agree, returning 7.
All seven independently changed values are rejected while retaining typing.
Division by zero, signed division overflow, and an out-of-range magnitude fail
cleanly in both Lean modes and x86. Existing literal and multi-unit constant
tests still pass. The affected checker infrastructure rebuilt in 9.58 seconds;
the connected constant suite took 21.70 seconds, including fresh default and
checked Lean output. The backend proof boundary also rebuilds successfully
(8.48 seconds). The semantic theorem and emitted typing proof
use only `propext`, `Classical.choice`, and `Quot.sound`.
Constant-to-constant initializer references still need an acyclic dependency
argument and are rejected by this checker. A signed-minimum literal directly
inside a function body also remains unsupported by the native lowerer; this
fixture uses the supported constant declaration instead.

Further declaration diagnostics on the 1,075-function output measured 10.97
seconds for the type/constant/signature prelude alone. A body-free diagnostic
took 20.82 seconds; it was deliberately not semantics-preserving and is not an
output mode. Disabling closed-term extraction did not improve prelude time.
Deriving field projections from existing record metadata removed 881 generated
field instances in a prototype, but the complete module still took 78.69
seconds, essentially the baseline. The prototype passed full typing after a
payload-inference fix but remains outside production: no checking speedup was
demonstrated.

Further diagnostics did not justify changing production proof structure.
Abstracting the program increased keyword-proof elaboration from 265 to
319 ms, with unchanged kernel time. Sharing Core subtrees also left kernel
time essentially unchanged on the keyword recognizer and expression lowerer.
A diagnostic copy containing the current pre-split program declarations but
no typing or lookup theorems still took 45.41 seconds to check freshly.
This is not an accepted output mode: production retains every typing proof.
It shows that optimizing proof terms alone cannot meet the full-check target.

Representation experiments remain outside production. On the real keyword
recognizer, an intrinsically typed tree with shared typing and return-path
theorems reduced value elaboration from roughly 373 ms to 277 ms, but kernel
checking barely changed (about 55 ms versus 52 ms). Lean proved its erased
body equal to the current implementation. Sharing 3,056 enum uses through
566 payload-position facts checked the full earlier module in 73.92 seconds;
sharing complete constructor signatures took 75.58 seconds. Neither showed
a substantial improvement over the roughly 76-second baseline, so neither
justifies a production representation rewrite.

Generated nominal types and functions are public Lean declarations, not private
ID-prefixed definitions or aliases. Source module paths are single quoted name
components; for example, `Extracted.«app::main».Types.Choice` and
`Extracted.«app::main».Functions.main`. The separate type and function namespaces
preserve Lanius programs that reuse a name. The shared IR retains module-path
token references from the existing parse, without reparsing source.

Calls now use those names too: for example,
`Extracted.«app::namespace».Functions.«theorem» ()`. The `mutual functions`
block resolves forward and mutually recursive calls without reordering
functions or emitting reference-only declarations. One borrowed
function-ID index maps calls to catalog positions during emission; it does not
change Core IDs or copy the IR. Focused checks cover sparse and colliding IDs,
missing IDs, duplicate rejection, and invalid bounds. The connected public-name
gate checks same-named functions in separate modules, nested and recursive calls,
and a function named `ref`, including exact source-to-Core agreement and x86
execution. It passed in 6.39 seconds.

Constants now also use public source names, such as
`Extracted.«app::main».Constants.«SLOT»`, in declarations and function bodies.
The shared IR retains each constant's ID and existing source-token reference;
no reparsing, numbered alias, or new serialized format is involved. The IR
boundary checks that name rows agree with the constant catalog. Focused tests
cover sparse IDs, missing IDs, invalid token references, and allocation bounds.
The standalone `direct_public_constants_check.sh` passed in 12.05 seconds. It
checks same-named constants in separate modules, exact source agreement for
i32/bool/string/usize/null-pointer literal initializers, rejection of six
independently altered but still well-typed values, and matching x86 execution.
Constants are checked against their declared type instead of inferred as
unannotated expressions. A shared lemma reuses literal elaboration's bounds
to prove Core value typing, without a second value check. Focused kernel proofs
cover empty and UTF-8 strings, embedded NUL mismatches, integer bounds, and
non-null pointer rejection. The shared checker still does not authenticate
computed initializers such as arithmetic or negative expressions. The literal
proofs depend only on Lean's standard `propext`, `Classical.choice`, and
`Quot.sound` foundations; no native-computation assumption was added.

Constant declarations and references now also carry generated typing proofs.
Each declaration group's value proofs compose through `CheckedList.flatten`;
uses share one authenticated lookup per constant, reusing the same key-summary
theorem as function calls. A constant-using program can therefore emit
`extractedVerifiedProgram`, instead of falling back solely to `link?` because
its constant table is nonempty. The connected constant gate passed in 12.36
seconds with assertions about the actual proof-carrying program. This proves
typing of those emitted programs, not universal extractor correctness.

Function bodies use `.Some 7` and `.Some value` constructor syntax. Shared
constructor instances resolve the source spelling within its nominal owner to
the same Core tag and typed payload. Ordinary proofs can import the generated
types, functions, and instances. Native Lean constructor names that would
collide with Lean-generated declarations are escaped, such as `«constructor:rec»`;
the function notation still uses the original `.rec` spelling. Nested matches
are parenthesized so operators and following match arms cannot change their
grouping. `direct_public_api_check.sh` checks these cases against exact source
lowering and matching x86 execution.

Reusable IR-shape checks live in `verified/lean_body_shape.lani`; both the
renderer and proof emitter use them directly. Separating these checks from
rendering keeps individual sources within the existing raw-token budget. No
capacity increase, compatibility wrapper, or new trust assumption is involved.

All 1,123 defined functions in the current self-extraction emit source-shaped
typed Lean; the other nine functions are runtime imports. The former 256-node
cutoff no longer forces large bodies into raw Core syntax. The output contains
1,132 direct function-typing proofs and a composed program-typing proof.
Both output modes use the same
body-lowering path. That path builds one allocation-ID index and reuses it for
value validation, field owners, qualified call candidates, and enum patterns.
It rejects duplicate and out-of-range IDs before lowering bodies; lookups still
check declaration kinds and module visibility.

The September 27 constant-proof self-check passed in 107.98 seconds: 21 seconds
for emission, 82 seconds for fresh module checking, and 0.885 seconds for
independent Core typing, plus setup. It covers 93 source units and 752 constants;
the Lean module is 9.62 MB and the compiled artifact is 127.12 MB. This closes
much of the missing typing evidence but increases checking cost from the
preceding 60-second module check. Further proof expansion is held behind a
performance investigation, not treated as a speed improvement.

A synchronous kernel-only replay of the compiled module's 4,755 theorem values
took 21.4 seconds. It checks existing terms in an imported environment, not a
fresh source module, so it is diagnostic rather than an end-user timing. A
large function's proof took 0.90 seconds to elaborate and 0.11 seconds in the
kernel when replayed in that environment. Tracing located most elaboration time
in constructor arguments. Explicit program parameters increased elaboration
to 1.20 seconds; moving field metadata before the operand gave 0.94 seconds.
Neither experiment was adopted. The representative enum still emits in 0.02
seconds, checks freshly in 0.74 seconds, passes exact source agreement, and
returns 7 on x86.

A constructor-directed elaborator was also rejected: native compilation and
direct proof assembly reduced the large proof's elaboration to 0.56 seconds,
but the full fresh module still took 82.13 seconds. No custom elaborator or
plugin was added to the production path. A whole-module profile took 83.64
seconds: parsing used 8.46 seconds and serialization 9.74 seconds; cumulative
parallel-worker totals included 166 seconds of elaboration and 32.3 seconds of
kernel checking. Those worker totals overlap and must not be added to wall
time. A two-worker check exceeded its 110-second cap and is not used. The
next optimization must improve the full pipeline, not just one proof replay.

On September 27, self-extraction with source-named constants passed in 83.87
seconds: 20 seconds for emission, 60 seconds for the fresh Lean module check,
and 0.795 seconds for independent Core typing, plus setup. It emitted 752 named
constants across the same 92 source units. The Lean module is 7.07 MB and its
compiled artifact is 116.87 MB. This completes constant naming, not the
seconds-scale full-check target. The existing public type/function/source/x86
gate also passed in 6.32 seconds.

On September 26, with shared Lean infrastructure built, the representative
`Choice.Some(7)` let/match program generated ordinary Lean in 0.02 seconds and
checked as a fresh module in 0.74 seconds. Its `--lean-checked` module took
1.58 seconds to check and passed exact source-to-Core validation, the public
constructor proof, and matching x86 execution (returning 7). After naming call
references, the full
extractor closure took 84.05 seconds: 19 seconds to generate Lean, 60 seconds
to check the module, and 0.870 seconds for independent Core typing, plus setup.
It contains 92 source units; the generated module is 6.96 MB and its compiled
artifact is 116.46 MB. This run did not overlap another large check. The
preceding pipeline took 87.32 seconds (20 seconds emission, 63 seconds module
checking); these runs use different source revisions and do not establish a
fixed-input speedup from naming calls.

The earlier 99.04-second run overlapped the connected regression suite, so
it is not a controlled baseline for the latest full-check result. A preceding
run before the enum index took 83.85 seconds (21 seconds emission, 58 seconds
module checking). Native generation improved in fixed-input comparisons;
the latest whole-pipeline timings do not establish a further checking speedup.

The earlier cutoff-free check took 90.05 seconds (25 seconds emission,
61 seconds module checking); before removing the cutoff it took 83.87
seconds (24 seconds emission, 55 seconds checking). The broader, public,
source-shaped output is not a demonstrated full-check speedup.

The shared notation now normalizes each elaborated body once and stores it in
an ordinary kernel-checked definition. On the same earlier self-module this
reduced checking from 59.15 to 53.79 seconds and its compiled artifact from
126.06 to 112.96 MB. Profiling showed substantial elaboration and serialization
cost, not just kernel checking. Precompiling the notation took 4.57 seconds of
shared setup but did not improve the fresh check (54.31 seconds), so the normal
path does not require native plugins. No proof assumptions were added.

A later fixed-file comparison on the current 6.68 MB self-module measured
67.01 seconds before sharing local binding descriptions, 62.08 seconds with
shared locals, and 61.72 seconds after also resolving explicit signature
variables directly. The last change reduced typeclass-inference time but
showed little further wall-time benefit. These were fresh checks of the same
Lean input with shared infrastructure already built, not cached program checks.
All three compiled modules evaluate to byte-identical full Core data; the
compiled artifact size remains 116.08 MB. Scope, mutation, generic and computed
signatures, uninitialized locals, and rejected constructor applications pass
focused checks. The connected public-name, nested-match, source-agreement,
and x86-execution gate passes in 5.06 seconds. This is a modest improvement,
not the seconds-scale full-check result still required.

The body-definition helper now expands surrounding Lean `let` bindings when
closing a normalized body. This uses Lean's existing closure operation and
avoids its extra meta-level check for dependency-sensitive abstraction; the
kernel still checks the resulting definition. Generic parameters, dependent
local type aliases, captured variables, shadowing, and mutation pass focused
erasure checks. On the fixed 6.69 MB self-module, a fresh check took 60.82
seconds. Its complete Core value is byte-identical to the preceding module,
passes independent typing, and retains the 116.22 MB compiled artifact size.
This is a small optimization, not a demonstrated large speedup.

Two related experiments were not adopted. Specializing the common lookup
proof arguments once preserved Core but took 61.02 seconds, too close to recent
timings to justify a performance claim. Disabling asynchronous elaboration
did not finish within 110 seconds. A CPU sample of the ordinary fresh check
took 64.15 seconds and showed substantial allocation and reference-counting
work; it does not attribute that work to individual generated declarations.

The body elaborator now exposes separate trace timers. On the fixed 6.96 MB
self-module, their regions totaled 23.36 seconds for typed-term elaboration,
3.16 seconds for normalization, and 0.30 seconds for the checked auxiliary
definition. These are regions within an 87.76-second profiled run, not additive
parts of the ordinary 60-second check. Thus normalization and auxiliary
definition creation are not the main remaining body cost.

A broader custom application elaborator preserved the complete Core value and
passed independent typing, but its 59.41-second fresh check did not establish
a material improvement. It was removed. Constructor syntax now directly uses
the typed variant builder, since the syntax already distinguishes a variant
from a function call; ordinary and polymorphic calls keep the existing
application interface. Focused tests retain rejection of wrong argument types,
arities, result types, and constructor names. The retained simplification
checked in 61.04 seconds, with byte-identical complete Core data and the same
116.46 MB compiled artifact. Independent typing, captured-variable and
intrinsic tests, and the public Lean/source/x86 gate pass. This is a simpler
constructor path and a better profile, not a demonstrated checking speedup.

Suppressing editor metadata inside CLI body elaboration took 60.65 seconds
versus 61.04 seconds on the same input and was removed. No proof checks were
disabled. A diagnostic of the baseline compiled module counted about 0.94
million shared expression nodes in theorem values and 0.54 million in data
definition values, summed per declaration; the largest theorem value had
7,918 nodes. These counts do not include declaration types or compiler IR,
and are not checking times or a proof of good asymptotic behavior.

Indexing had already reduced generation from about 30 seconds to 25–27 seconds;
old and indexed extractors emitted byte-identical Lean for the same source tree.
These checks establish output preservation and Core typing, not a full
source-to-Core correctness proof.

Later September 26 comparisons reduced native generation further. Rejecting
the wrong explicit module before checking its imports reduced generation from
25.35 to 21.85 seconds on identical input. Import and privacy checks still apply.
The global callable/variant name index is now built once and shared across
units. That change reduced peak memory from 212,744 to 201,728 KB but did not
improve time in its comparison (21.00 versus 21.17 seconds).

The allocation index also retains enum declaration rows in source order.
Constructor lookup visits those rows without scanning unrelated declarations;
it still checks ownership, visibility, signatures, and ambiguous names. This
reduced generation from 21.51 to 20.34 seconds on the same current input.
Each comparison produced byte-identical Lean. Focused tests cover index reuse,
sparse IDs, wrong kinds, invalid bounds, local/imported scope, and ambiguous
bare and qualified variants. These are modest measured gains, not a
seconds-scale full-check result.

Uninitialized locals, explicit void returns, and unit-function fallthrough now
have source-shaped output and compositional typing proofs. The corresponding
x86 path accepts void returns and unit fallthrough. A connected fixture checks
both branches of an assigned local, an early return before an infinite loop,
and matching Lean/x86 execution; the source checker rejects an invented zero
initializer. An erasure test confirms that reading an uninitialized local still
traps rather than receiving a fabricated default value.

The connected direct Lean/x86 suite passed in 113.37 seconds. It covers enums,
payload matches, calls, nested fields, mutation, loops, integer operations,
strings, numeric conversions, raw slices, uninitialized locals, and explicit
and implicit unit returns, including source mutations and
malformed-input rejection. That duration is for the suite, not one program.
The separate public-API and nested-match gate also passes. The
focused semantic-IR boundary check also passes, including malformed module
metadata and bodies above the old size cutoff. Focused allocation-index and
alias tests also pass. The full checked frontend
remains too large for routine per-program checking: its earlier 68 MB artifact
did not finish under a 105-second diagnostic cap.

## What remains

This is not yet a proof of the entire compiler or extractor. The principal
open obligations are:

- prove the actual Lanius frontend and shared typed-IR lowering correct for
  their supported source domain, including multi-unit name resolution and
  recursive calls;
- prove the actual Lean printer preserves that IR, including decimal output,
  declaration/body printing, escaping, capacity failure, and termination;
  its five closed basic writer contracts are components, not this theorem;
- establish the emitted Surface notation's correspondence to the intended
  Core data. Normal output must remain proof-free: no second typing tree or
  per-program parser derivation;
- complete the actual Lanius x86 emitter's refinement for all constructs used
  by the extractor/compiler, plus allocator, host-call, and executable-loading
  assumptions. The existing connected checker proves its accepted fragment,
  not general correctness of the Lanius compiler;
- self-extract and produce the extractor's executable through that verified
  x86 path, rather than continuing to rely on the GPU bootstrap executable;
- define the explicit trusted execution/import boundary that lets subsequent
  programs reuse the verified tool without repeating source/type validation.

Integer-certificate emission and checking remain optional bootstrap diagnostics;
they are not the target normal extraction path. See [NOTES.md](NOTES.md) for
current contracts and evidence. The certificate-era design in
`../formal/PROOF_ARCHITECTURE.md` is historical where it conflicts with the
direct-extraction architecture above.
