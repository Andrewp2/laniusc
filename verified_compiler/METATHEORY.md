# Metatheory obligations

Goal: complete the shared language foundations and connect them to correctness
of the actual Lanius extractor/compiler, through x86. This ledger tracks proof
obligations, not percentages or theorem counts. An abstract checker or a narrow
example is not evidence that the actual compiler is correct for all supported
inputs. Define those inputs independently of successful execution.

## Existing execution foundations

`formal/Lanius/Semantics/Fuel.lean`, `LexicalFrame.lean` and `Allocation.lean`
prove fuel independence, unique completed observations, lexical restoration and
fresh-cell inventory preservation for all seven evaluator entry points. These
include traps and modeled exits. They do not prove value typing, memory safety
or termination. Reuse these laws; do not reconstruct them in each function.

Control-flow composition and total-loop rules exist in `Stable.lean`,
`StmtList.lean`, `CallRun.lean`, `ScopedEffect.lean` and `TotalWhile.lean`.
Their existence does not close every compiler algorithm's contract.

## Required ledger

“Partial” means a real restricted law exists, not that the remaining obligation
can be assumed. “Open” means the general requested result is not established.
Paths below are relative to `formal/Lanius/` unless stated otherwise.

| # | Obligation | Current evidence and remaining gate |
|---|---|---|
| 1 | Unified runtime-state typing | Partial: declared cells and live native array targets share the accessibility invariant. `Typing/Native/Mapping.lean` bundles it with the allocation frontier and unique registration keys as storage readiness, preserved by typed cell effects, pointer exposure and modeled reads. Full locals, recursively stored references, layout/lifetime and whole-state preservation remain open. |
| 2 | Binding/context laws | Partial: `Typing/Bindings.lean`, `Pattern.lean`, `Parameters.lean` under `Semantics/` cover initialized bindings and shadowing; connect to declared storage and scope restoration. |
| 3 | Operator/cast preservation | Partial: scalar/arithmetic execution rules and operator result-type uniqueness exist; close general evaluator preservation and specified numeric failures. |
| 4 | Aggregate preservation | Partial: `Semantics/Typing/Projection.lean` covers arbitrary nested struct/array cell paths; `Projection/Identity.lean` proves exact write-back identity. `Projection/Frame.lean` now proves that updates retain independent nested reads, and that typed i32-array leaves either coincide or are independent. Cover enum operations and general native storage. |
| 5 | Place-resolution soundness | Partial: local root assignment resolves before RHS effects and retains destination liveness through the evaluator's identity law. The independently accepted write-place foundation derives raw whole-element/field SET execution across distinct index/RHS states, using captured descriptors and post-RHS storage, with exact read-back/store frames and both access modes' fuel/lexical/inventory laws. The accepted count-store and catalog/collateral caller migration is installed; the real catalog-store CLI checked all 27 connected bodies fresh against authenticated current foundations. Nested places, general typing preservation and source/backend correspondence remain open. |
| 6 | Initialization safety | Partial: full local assignment now initializes declared slots without assuming an old initialized value; derive general read preconditions from control flow. |
| 7 | Reference validity | Partial: `Semantics/Typing/Target.lean` and `Reference.lean` derive live typed reads, survive cell writes/allocation frames, and connect local borrowing/dereference to execution. General place construction and validity of recursively stored references remain open. |
| 8 | Slice validity | Partial: `Semantics/Typing/Slice.lean` proves typed cell slices and indexing after operand effects. Native mapping derives readable cell/raw pointers. The actual allocator and raw constructor now establish scratch validity from numeric size/budget bounds on the no-registration route; the actual read declaration consumes it. General raw layout/lifetime and temporary storage remain open. |
| 9 | Heap-operation laws | Partial: allocation, borrow, read/write and byte-write frontier laws. Fresh i32 allocation retains arbitrary old readable ranges and unique block bases without reducing backing bytes. `Memory/Footprint.lean` composes byte-write permission sets, preserves outside valid/invalid reads and allocation metadata, and feeds the actual whole reader call. Shared frames retain storage readiness and old slice validity; the actual scratch setup derives its storage premises without assuming allocation succeeded. Relevant reallocation/deallocation and general invariant composition remain open. |
| 10 | Native representation | Partial: `NativeLayout.lean`, native snapshots/stores and byte codecs. `Semantics/Native/Codec.lean` and `Typing/Native/Array.lean` now prove both exact i32-array codec roundtrips: typed values to bytes and back, and exact-length bytes to values and back. Close general value/layout fidelity for the supported x86 subset. |
| 11 | Cell/heap coherence | Partial: flush/refresh, arbitrary nested first exposure, canonical pointer/read composition and exact stdout cell framing. Actual no-registration scratch allocation/construction now derives the descriptor premises for modeled reads. Allocation with live registrations, general construction/mutation, raw/temporary lifetime/ownership/regions and the global invariant remain open. |
| 12 | Whole-evaluator preservation | Open: mutual expression/statement/function result and state typing, with legitimate host contracts and map extension. |
| 13 | Safety/error classification | Partial: typed live views and readable storage rule out synchronization traps. The complete actual reader body/call derives total execution, error-or-bounded-count returns, valid buffers, caller preservation and an outside-both-buffers heap frame on the raw/no-registration domain. Readable capacity-fitting files now have an exact whole-call bytes/tail/count/cursor/trace theorem. Negative capacity and null scratch have separate early-rejection proofs without readable-buffer assumptions. Exact whole-file overflow/I/O-error observations and general bounds/division/resource/host classification remain open. |
| 14 | Compact contracts | Partial: the independently accepted `LocalEnv`/`EnvStmt` interface replaces fresh-cell and lexical-scope bookkeeping in both actual lower_owned and the complete reader. `HeapFrame`/`Rep` distinguish byte contents, read-shape and ownership with proved locality. Public inputs contain no assumed execution or output. Actual algorithm and legacy native-representation adapters remain substantial; the near-5x size target is not met. See the October 9 checkpoint below. |
| 15 | Sound composition | Partial: pure/effect/call/match/sequence rules; consolidate remaining control flow, traps and exits when consumers require them. |
| 16 | Separation/ownership/frame rules | Partial: `Memory/`, `NativeReadFrame.lean`, `ScopedEffect.lean` and `Typing/Projection/Frame.lean` cover heap frames and independently updated aggregate branches. Native refresh consumes the nested frame law. The actual whole reader preserves every read outside the union of scratch/output ranges, including an allocated gap between them, together with allocation metadata. Permissions are not the convex hull and do not impose new language alias restrictions. Establish compositional ownership assertions and full lifetime/heap-operation composition. |
| 17 | Loops/recursion | Partial: `TotalWhile.lean`, structural compiler inference induction and actual reader termination. Native `kind`/`child`/`definitely_returns` now have accepted total-execution contracts on independent physical statement trees, including discharged recursion, exact results, rejection and caller frames. The reader's tracked loop composes fitting-file contents, tail, cursor and read count through the actual call; EOF/errors/overflow still terminate. Native lowering/builder provenance, exact reader overflow/error refinements and other compiler contracts remain open. |
| 18 | Data-structure contracts | Partial: independently accepted catalog allocation/copy/build/store/append and initializer contracts derive contents, frames, termination, rejection and sufficient-resource success. The accepted natural-body producer1179 connects original Void/Bool/decimal/negative/MIN syntax to Core/native meaning in both annotation modes. The October 9 accepted actual lower_owned1180 theorem now composes it over ordered selected rows, retaining earlier insertions and protected original inputs/signatures; safe failure and resource-sufficient success are proved. Unit/program callers, general functions, source/extractor/typechecker correspondence and other structures remain open. |
| 19 | Invariant automation | Partial: `core_formed` propagates proved allocation facts; `core_lookup` shares checked table lookup facts across branches; `core_local` handles closed multiple-binding exclusions, and `core_scalar` reuses unsigned-cast laws. Syntax-aware binding selection and supplied-frame priority now close the actual constructor failure/normal-stage consumer without inferring binding data from cell predicates: binding reductions fell from 348,889 to 21, and the stage checked in 3.14s. These shared rules and their opaque-state regressions are accepted and installed with construction. They do not establish general preservation automation, which remains open. |
| 20 | Actual typechecker soundness | Open: the proof-producing `Typing/Check.lean` is a model checker; general correctness of the Lanius implementation remains distinct. |
| 21 | Resolution/linking | Partial: `Compiler/` contains model checks and boundaries; prove the actual implementation and discharge callers' premises. |
| 22 | Observations/refinement | Partial: outcomes/world and backend boundaries exist. The actual public file-reader call now derives exact whole-file expanded bytes, unchanged output tail, count, cursor and read trace for readable files fitting capacity. This is the modeled full-prefix file service, not an OS/x86 syscall theorem. Close remaining error/overflow observations, one source/IR/x86 relation and the runtime bridge. |
| 23 | Lowering-pass composition | Partial: `Compiler/ProgramLowering.lean` and boundaries; close actual passes rather than assume accepted correspondence. |
| 24 | x86 simulation | Partial: `X86/` machine/encoding laws and checked fragments; close supported instruction emission, representations, calls and runtime bridge. |
| 25 | Actual direct-Lean extraction | Open: normal emission uses shared IR and no second typing tree; general extractor correctness and the proved trusted-output boundary remain open. |
| 26 | End-to-end correctness | Open: compose the actual tool theorems through executable x86; existing conditional/checked-fragment boundaries are not this result. |

## Dependency order and consumers

1. Close declared storage, target validity and native coherence. Consumers:
   dereference/index/assignment preservation and the compiler's memory contracts.
2. Build compact contracts and separation/frame composition alongside that work.
   Demonstrate each substantial abstraction on existing compiler proofs before
   scaling it. Measure written statements, proof terms and connected checking.
3. Compose general preservation and actual typechecking/resolution contracts;
   close compiler algorithms using the compact interface and loop/recursion rules.
4. Close extraction and lowering, x86 simulation and their end-to-end composition.

Termination concerns specified compiler algorithms, not every Lanius program.
Normal checking must not execute the compiler again or emit a second typing tree.

## Optional theory decisions

These are provisional deferrals, not completed proofs. Revisit when a consumer
requires one; record that consumer and the resulting scope.

| Topic | Decision and reason |
|---|---|
| Divergence | Defer general coinductive traces until the desired backend refinement needs nontermination; keep divergence distinct from finite-fuel exhaustion. |
| Small-step/evaluator correspondence | Reuse the current evaluator for completed-execution proofs; add small-step theory only if it materially simplifies machine simulation. |
| Contextual equivalence/logical relations | Defer the general library; start with the observation/refinement relation required by concrete passes. |
| Renaming/substitution | Add laws for actual transformations as needed, not a lambda-calculus library unrelated to current bindings. |
| Typechecker completeness | Soundness is required for trusted output; completeness becomes required if rejecting valid inputs is part of a claimed contract. |
| Cost semantics | Measure checking/emission now; formal complexity bounds are not prerequisites for functional correctness. |
| Borrow theory | Prove actual memory/aliasing rules; do not silently add Rust's exclusive-borrow restrictions to Lanius. |

## Evidence requirements

Each completed milestone records the theorem and actual code connection, input
domain, success/failure/termination scope, transitive assumptions, focused checks,
fresh checking times with cache conditions and matching proof/implementation size.
Standard Lean logical axioms are allowed; no `sorry`, new trust axioms, native
proof shortcuts or raised limits. Commands have a two-minute ceiling; splitting
one slow artifact does not establish a speedup. The project-specific acceptance
gate is also 120 seconds for a complete fresh connected check, including setup,
audit and cleanup; seconds remain the target. All other proof gates are unchanged.
General extraction, preservation,
x86 simulation and end-to-end correctness must remain open here until proved.

## October 9: shared proof interface and complete restricted caller

Independent [ACCEPT](../tmp/proof-interface-20261008/candidate-review-1/receipt.md)
covers `IRBodyOwnedProof.actualOwnedLowering` over actual Core1180, plus the
replacement complete reader contracts `ByteIoReadInterface.Function.call` and
`File.call`. Both use the same local-environment/scope and heap-representation
interface over the existing Core execution relation. The lowerer composes the
proved natural-body producer rather than assuming its result. Independent inputs,
finite execution, success, safe failure and caller-required frames are retained.

The new reader family replaces the old `ByteIoReadProof.ReadStep`, `Outer`,
`Total`, `Function` and `File` modules; raw-read and inner-copy foundations remain.
Older sections below document their historical names and checks, not additional
current proof paths. Exact installation is complete; the same canonical-only
49-body destination check passes in 67.87s with matching hashes and clean shutdown.

Fresh independent checking took 68.99s for 49 current/unaccepted bodies, with 187
exact accepted foundations cached, standard axioms and complete process cleanup.
Reader-specific code falls from 1,132 to 1,004 physical lines; new shared code adds
1,079. The lowerer-specific family is 2,858 lines. The complete non-Core pair
closure is 44,482 lines. This is useful composition, not a 5x-size result or a
comparative whole-check speedup. See [current notes](NOTES.md) and
[full costs](../tmp/proof-interface-20261008/check/candidate-handoff/accounting.md).

The admitted Core still needs its source/extractor correspondence proof. General
compiler bodies, the unit/program callers, x86 and the executable trust boundary
remain open. Do not count this restricted result as whole-compiler correctness.

## October 5: native return-analysis execution

`verified_compiler/tests/direct_ir_returns.lean` proves the actual current
admitted Core classifier, rather than a Lean-native replacement. Its independent
physical relation covers all nine native statement forms; the child walker and
return classifier terminate, preserve the caller frame and yield exact results.
The Boolean answer is equivalent to `Typing.DefinitelyReturns`. Bad indices and
every signed child ordinal are covered; concrete byte-backed true/false inputs
establish non-vacuity. No recursive-call answer or successful validator is assumed.

Independent ACCEPT: seven full bodies checked fresh in 28.02 s; exact destination
check: 40.66 s. Only disclosed unchanged foundations and operational program data
were cached. All frozen inputs matched. The 302-line proof plus the conservative
32-line shared-call charge totals 334 lines for 68 matching source lines (4.91x);
native fixtures add 43. Public axioms are the standard three. This is a completed
component, not whole typechecker, extraction, x86 or end-to-end correctness.

The next connection must derive statement provenance from actual lowering and
catalog copy/build. Builder readiness permits non-statement roots; it cannot
replace that proof. The subsequent current-program instantiation is now accepted:
all11 complete compiler-specific bodies and their audit checked fresh in78.15 s,
with the separately accepted generic library cached. The two import changes are
integrated, and all destination sources match that single SelfCore snapshot.
This closes the mismatched-program composition issue, not validator, lowering,
extraction or x86 correctness. Default `.lake` artifact bytes are not the same
accepted warm-library snapshot. Evidence is in `verified_compiler/NOTES.md` and
the frozen return-analysis/current-program packets.

## October 5: small sound Core vcgen scope rules

`Semantics/VCGen.lean` now supplies registered specifications for actual Core
local scopes, evaluated Boolean branches and expression statements. They derive
combined finite execution from independently proved subruns and preserve their
effects, restored locals and arbitrary completion. New fixtures use an effectful
initializer and guard, early return past an arbitrary suffix and a continuing
expression write; no Lean-native replacement program is being substituted.

Independent ACCEPT checked both complete source bodies in6.01 s with20 unchanged,
authenticated semantic foundations cached; all13 axiom reports are standard.
Exact sources are integrated. New cost is31 production,43 fixture and35 mechanical
support lines, with four obsolete support rows retained historically. These rules
remain charged to the actual validator trial. Its complete positive/negative
contract and builder consumers, and the general preservation/extraction/x86
obligations, are still open. No new evaluator, loop framework or trust was added.

## October 5: exact fitting-file observations through the actual call (previous implementation)

`ByteIoReadProof.File.call` proves the complete actual call's expanded i32-byte
contents, untouched output tail, returned count, file cursor and exact read
trace. Its domain is independently specified readable file/handle contents,
the initial unread suffix fitting capacity, a nonnull scratch pointer and the
existing raw-buffer/caller facts. Execution, loaded chunks, EOF, output and
termination are derived. Existing `Total.Result` memory/caller guarantees
remain part of this stronger result.

`Total.runTracked` and `declarationTracked` generalize the existing execution
proof with a heap/world observation invariant. The fitting-file consumer proves
its step callback from `ReadStep.Result`, rather than assuming correct output.
The ordinary safety contracts specialize this same loop without file-readiness
requirements, so modeled errors and overflow remain covered. Pointer/parameter
contexts, entry guards, scopes and actual invocation have shared bridges; the
content theorem does not duplicate their local-state bookkeeping.

`World.FileCursor.read` derives the exact file prefix and cursor update from
independent lookups/readability, without a hidden unique-handle-ID assumption.
`Memory.BufferPrefix` retains a written prefix and original tail within output
storage while other buffers change. Scratch framing and accepted byte-write
append compose through this relation; it does not reexecute the reader or build
an emitted proof/typing tree. Continuing reads either consume a full 65,536-byte
chunk or reach the file end. Thus the trace contains exactly
`ceil(unreadLength / 65536) + 1` reads, including the final EOF read.

The final 3,039-line artifact freshly checks all 21 complete source bodies in
17.09 s. Other foundations and unchanged byte-identical program admission are
cached, not bundled proofs. Shared cursor/prefix checks take 0.16/0.36 s, tracked
loop/declaration 1.42 s, shared actual body/call entry 1.97 s, whole-file body/call
2.21 s and final fixtures 3.57 s. All 1,096 existing executions still pass;
36 cursor tests add duplicate IDs, zero requests, EOF and past-EOF cases.
`readsActualFile` proves an inhabited allocated-buffer actual call's exact
six-byte expansion, first untouched output byte, cursor and two-read trace.
Six chunk-count boundary formulas check by ordinary reduction. Tests supplement
the general theorem. All sources/bundle match; audits show standard logical
axioms only. Source-boundary checking/fresh self-emission matches admission in
6.66 s (79 extractor, 107 compiler, 116 combined units).

Reader-only production totals 1,132 physical lines for the same 38-line function,
about 30x before imported host/allocator contracts. This is still above target.
The extension adds 375 production lines: 272 actual (tracked total +41, shared
entry +16, content consumer 215) and 103 shared (cursor 50, prefix 53). Fixtures
grow 44 lines and the gate three. Stronger scope is not compression or a measured
speedup. Reuse this same progress invariant for remaining error/overflow
observations; do not scale another routine bookkeeping or parallel-loop pattern.

This theorem is for the deterministic modeled full-prefix read service, not
native OS reads (which may be short or fail) or an x86 runtime simulation.
Exact whole-file overflow/I/O-error observations, the real driver's input
premises, general preservation/extraction and native/x86/end-to-end correctness
remain open. All 26 items stay tracked. No compiler source, format, trust or
limits changed. Gate syntax was checked, not full fresh admission/mutations.
Evidence under `target/verified-compiler/binary`: `ReadFile.lean/.olean`,
`ReadFileSource.lean` and `read-file-*.log`/`read-tracked-total.log`.

## October 5: whole-reader outside-buffer frame (previous checkpoint)

`Memory.HeapWritesOn` composes proved byte-only effects within a permission set.
It retains all outside byte reads, including failed reads, all old readable
ranges, unique block bases and allocation frontier/budget/layout metadata.
`BytesWrite.footprint` and `FileReadResult.footprint` derive this frame from the
existing exact effects; neither reexecutes a read/store nor assumes success.

`ReadStep.Result.footprint` frames the union of the scratch request and output
range. The existing `Total.Invariant` carries that frame through the same
decreasing-capacity loop, initializer, function body and public call. No second
loop execution proof, emitted proof tree, checker or new trust boundary exists.
Its public `Total.Result` now guarantees no writes outside both buffers and no
allocation changes. This includes EOF, modeled I/O errors and overflow; negative
capacity/null scratch retain their separate early-rejection proofs.

All 1,096 executions still pass and now check the frame and heap metadata.
The inhabited allocation fixture places real sentinel storage in the gap
between the two buffers. `retainsOutsideStorage` proves its exact bytes survive
the actual call, together with a failed null read, frontier and budget. A convex
hull permission would not suffice to prove the sentinel result.

The final 2,617-line artifact freshly checks all 18 complete source bodies in
15.03 s. Other foundations and unchanged byte-identical program admission are
cached, not bundled proofs. Shared footprint checking takes 0.54 s and host
contracts 1.59 s; actual loop/declaration 1.20 s, function/call 1.75 s and final
fixtures 2.91 s. Sources/bundle match and audits show standard logical axioms
only. Fresh source-boundary checking/self-emission matches admission in 6.72 s
(79 extractor, 107 compiler, 116 combined units). Timings are measurements,
not a same-scope speedup claim. No compiler source, emission, trust or limits changed.

Reader-only proofs total 860 physical lines (48 + 115 + 232 + 132 + 207 + 126)
against the same 38-line function, about 23x before imported host/allocator
contracts. This remains above target. Production grows 108 lines over the
previous checkpoint: 41 actual and 67 shared (new footprint 50, host +17);
fixtures grow 29 lines, and the gate's line count does not change. The stronger
scope is not compression. Reuse one invariant and the existing chunk effects
for file refinement; do not add another parallel loop or reconstruct bindings.

Exact whole-file bytes/cursor/trace, driver's allocation premises, general
preservation/extraction, native syscall/x86 simulation and end-to-end correctness
remain open. All 26 obligations remain tracked. Gate syntax was checked, not
the complete fresh admission/mutation sequence. Evidence under
`target/verified-compiler/binary`: `ReadFootprint.lean/.olean`,
`ReadFootprintSource.lean` and `read-footprint-*.log`.

## October 5: complete modeled reader execution and actual call (previous checkpoint)

`ByteIoReadProof.Total.run` closes total execution of the actual outer loop.
Its invariant contains the fresh total counter, capacity bound, valid scratch
and output ranges, unique heap blocks and the no-registration condition.
Caller bindings are persistent facts, not repeated dynamic invariant fields.
Each continuing read has a positive chunk and strictly decreases remaining
capacity. Every other read returns; neither an execution oracle, read success,
termination nor correct output is assumed. `Total.declaration` connects the
actual zero initializer, complete loop, lexical scope and unreachable tail.

`ByteIoReadProof.Function.run` derives the pointer initializer and both entry
guards from caller parameters. `Function.call` binds the actual arguments,
executes the actual body and restores the caller's locals while retaining its
exact cell prefix. Its input is independent buffer geometry/storage, bounds,
separation, well-formed cells, unique heap blocks and no registered views;
there are no supplied argument locals, internal pointer/counter bindings,
loaded chunks or successful execution. Negative capacity returns before any
buffer access. Null scratch has a separate pure rejection contract that needs
neither readable buffers nor an output argument; a concrete empty-heap fixture
proves that rejection domain is inhabited.

These are **total-execution and safety/return-classification contracts**, not
the completed file-content contract. The final result retains buffer validity,
unique heap blocks, caller cells and an error or bounded count. It does not yet
compose per-chunk bytes/cursor effects into an exact whole-file observation or
an outside-both-buffers heap frame. General preservation, extractor correctness,
native syscall simulation and x86/end-to-end composition remain open.

Fresh i32 allocation now preserves arbitrary old readable ranges and unique
block bases through constructor-specific rules. Native view mapping consumes
the readable-range frame. The concrete call's 65,536-byte scratch domain uses
these rules without reducing its backing-byte list or raising limits.

The final 2,481-line artifact checks all 17 complete source bodies fresh in
19.92 s. Other foundations, including rebuilt allocation/native mapping, and
unchanged byte-identical matched program admission are cached; no bundled
proof is cached. The final actual loop/declaration takes 2.28 s, function/call
2.47 s and new fixtures 3.29 s. Shared allocation rebuilding takes 0.42 s and
native mapping 1.38 s; focused allocation/native-view regressions take 0.87 s
and 1.45 s. All 1,096 new executions pass: 546 declaration states, 546 actual
calls and four early rejections. They cover EOF, I/O errors, overflow, exact
small-file byte expansion/cursors/traces and caller scope/cell preservation,
including a shadowed total. Tests supplement, not replace, the open refinement.
All bundled bodies and artifact text match current sources. Transitive audits
show only standard logical axioms. Current source-boundary checking and fresh
self-emission match admission in 8.27 s (79 extractor, 107 compiler and 116
combined units). No compiler source, emission format, trust setting or resource
limit changed.

Reader-only modules total 819 physical lines (48 + 113 + 200 + 132 + 201 + 125)
against the 38-line `byte_io.lani:14–51` function, about 22x, before imported
actual host/allocator contracts. This remains above the 5x target. Relative to
the previous outer-body checkpoint, production grows 339 lines: 326 actual and
13 shared (allocation +15, native mapping -2). New fixtures add 159 lines and
the gate eight. Coverage expands; this is not a same-scope compression claim.
Keep reusing the public geometry/result and counter/frame boundaries; do not
repeat this entry-state bookkeeping in the remaining content refinement.

The gate includes the new declarations/call/fixtures. Its shell syntax was
checked, not the full fresh admission/mutation sequence. Evidence under
`target/verified-compiler`: `binary/OuterTotalCall.lean/.olean`,
`OuterTotalSource.lean` and `outer-total-*.log`/`outer-function-check.log`.

## October 5: actual outer read body (previous checkpoint)

`ByteIoReadProof.Outer.iteration` proves total execution of the actual complete
outer body, from independently specified buffer/caller facts and the retained
counter. It derives the 65,536-byte request or remaining-capacity-plus-one
request, the assignment, usize conversion and every read-entry premise. It
then consumes `ReadStep.run` for the host read, guards, copy/update and scope.
The result retains the exact file/cursor/heap effects and caller counter.
Neither a request, read success, loaded chunk, execution nor output is assumed.
This is one iteration, not termination of the complete outer loop.

`ReadStep.Result` now separates observable parameters from temporary bindings.
Its proved prepend/scope laws allow reuse through setup and lexical restoration;
this is an internal proof contract, not a second emitted IR or typing tree.
The existing fixture migrates directly. Lookup automation discharges closed
multiple-binding exclusions, and scalar automation consumes the existing cast
law with independently proved bounds. The actual body uses both. Negative
fixtures reject overwritten names and wrong values; existing arithmetic/cast,
state/lookup and fuel-rejection fixtures also pass.

The final 2,007-line artifact freshly checks all 14 complete source bodies in
12.83 s. Other foundations, including the freshly rebuilt automation, and
byte-identical matched program admission are cached; no bundled proof is cached.
The actual outer body takes 1.85 s. Shared automation rebuilding takes 4.02 s,
its focused regressions 1.73 s. The new 179 outer-body executions take 1.32 s
and cover both request branches, capacities 0/65,535/65,536/65,537, EOF, errors,
overflow, byte expansion, cursor updates and restoration of shadowed locals.
Prior count/chunk/guard fixtures also pass. All source bodies and bundle text
match current files; audits show only standard logical axioms. Fresh source
boundary checking and self-emission match admission in 7.60 s (79 extractor,
107 compiler and 116 combined source units). No trust settings or limits changed.

Reader modules total 493 physical lines (48 + 113 + 200 + 132) for the 25-line
`byte_io.lani:24–48` block, about 20x, still above target. This checkpoint adds
155 production lines: 153 actual and two shared automation lines. Fixtures grow
by 99 lines and the gate by six. Coverage expands; this is not a same-scope
compression claim. Stop repeating explicit entry-state bookkeeping: improve
invariant/context composition before scaling to more functions.

Caller-derived loop entry, capacity decrease, the complete outer loop and exact
whole-file/call relation remain open, as do preservation, general extraction,
native syscall simulation and x86/end-to-end correctness. The gate includes
the new body and fixtures; only its shell syntax, not the full admission/mutation
sequence, was additionally checked. Evidence: `binary/OuterIteration.lean/.olean`,
`OuterIterationSource.lean` and `outer-iteration-*.log` under
`target/verified-compiler`. No compiler source or emission format changed.

## October 4: actual host-read/count declaration (previous implementation)

`ByteIoReadProof.ReadStep.run` derives total execution of the actual count
declaration, including its host read, all guards, copy/update and lexical scope.
`Result` retains the exact file result, caller-cell/counter frame and views.
Invalid handles return -1; EOF returns the old total; overflow returns -2
without copying; positive fitting reads write the exact i32-expanded bytes and
advance the total. Overflow still consumes the read bytes and advances the file
cursor: the contract does not pretend that returning -2 undoes the host read.
No successful read, count, loaded chunk, execution or output is an input premise.

Entry conditions remain independent storage/binding/numeric facts: readable
disjoint raw buffers, unique heap blocks, no registered views, representable
capacity/request, total within capacity, and the retained fresh counter identity.
The outer request setup must derive these conditions from its own caller.
The theorem specifies the modeled file service, not native syscalls or x86.

The registered-view read and new raw route share `FileReadResult.perform`.
Raw contracts retain the entire cell/local/view state without creating an empty
typing context. Their redundant unnamed byte-frame witness was removed: the
exact file result already supplies the payload frame or error heap identity.
Read and copy boundaries share `Loop.Buffers`; `CountedLocal.restoreScoped`
handles returning scopes without manufacturing an assignment. The complete
declaration makes three unused standalone guard theorems redundant; they were
removed without aliases. Execution fixtures still cover malformed guard inputs.

Reader modules total 340 physical lines (48 + 113 + 179) for the 19-line
`byte_io.lani:30–48` block, about 18x. The actual host-declaration module is
122 lines, including 14 added for the raw route. Shared host/counter modules
are 335/139 lines. Relative to the last published checkpoint, production grows
177 lines (136 actual, 41 shared) and fixtures 104; the gate does not grow.
Coverage has expanded, so this is not a same-scope compression comparison.
The ratio remains above target: reuse this complete boundary for the outer
algorithm rather than repeat host, binding and return bookkeeping.

The final 1,764-line artifact freshly checks all 12 source bodies in 8.75 s.
It includes host/counter/query/prefix foundations, actual allocation/read/copy
contracts and their fixtures; only other foundations and byte-identical matched
program admission are cached. The actual declaration alone takes 3.85 s and
host metadata 1.14 s. Registered-view/host/counter regression rebuilding takes
3.02 s. All 12 bodies and the bundle text match current files. Fresh source-graph
checking and self-emission match the 79-source admission in 7.80 s. Audits show
only standard logical axioms; no limits or trust settings changed.

Fixtures exercise 324 complete read/count states with varying file lengths,
offsets and destination cursors, plus invalid handles, unreadable handles and
missing files. They check completion, complete output/scratch bytes, file cursor,
host trace, total and scope restoration. A proved instance derives six actual
file bytes, exact output words, retained scratch, total seven and file cursor
six. The earlier 45 complete chunk and eight malformed-return cases also pass.
These fixtures supplement, not replace, the general declaration theorem.

Outer request/remaining setup, decreasing capacity, whole-call restoration and
the exact whole-file relation remain open, as do preservation, general extractor
correctness, native syscall simulation and x86/end-to-end correctness. The full
admission/mutation gate was not run; its shell syntax passes. Evidence:
`binary/ReadCount.lean/.olean`, `ReadCountSource.lean` and `read-count-*.log` under
`target/verified-compiler`. No compiler source or emission format changed.

## October 4: actual scoped chunk and read-count branches (previous checkpoint)

`ByteIoReadProof.Loop.chunk` now proves the actual index declaration, inner
loop, `total += count` and lexical restoration together. It retains exact output
bytes and all outside reads, restores the enclosing counter with its new total,
and preserves caller cells/world/views. `ReadStep.{ioFailure,eof,overflow,copy}`
proves the real post-read continuation: invalid/oversized counts return -1,
EOF returns the old total, capacity overflow returns -2, and positive bounded
counts enter that chunk. Returning guards leave the entire state unchanged.
Their ordering is part of the proof, not an assumed classification.

The existing `CountedLocal.assignScoped` now accepts an arbitrary proved
state-preserving RHS. Literal users were migrated directly, and `stepWith`
reuses it instead of repeating cell assignment and scope restoration. The
shared counter module shrinks from 150 to 132 physical lines. The existing
syntax-query module grows by 16 lines to select actual binding statements,
including their initializer/continuation; this is not a second program tree.
All selected statements still require their complete execution proof.

Actual assignment/loop/count modules total 218 lines (48 + 109 + 61) against
the 18-line source block `byte_io.lani:31–48`, about 12x. Coverage has expanded,
so this is not a same-scope compression comparison with the prior loop ratio.
Production growth for this checkpoint is 89 lines: 91 actual, -18 shared counter
and +16 syntax query. Fixtures grow by 70 and the allocation gate by three.
Proof size remains above the target; reuse these contracts rather than repeat
their entry-state bookkeeping throughout outer-loop branches.

The final 698-line artifact freshly checks all eight source bodies in 3.60 s,
including the counter/query foundations, actual contracts and fixtures. Only
other foundations and byte-identical matched program admission are cached.
Standalone actual loop/chunk checking takes 1.78 s; count-branch contracts
1.71 s. The counter/loop fixture rebuild takes 2.57 s. The final 1,783-line
writer regression checks 13 complete bodies fresh in 23.97 s; this is broader
regression coverage, not a claimed whole-tool speedup. All 17 distinct source
bodies and both bundle texts match. Audits show only standard logical axioms.

Fixtures now execute all 45 fitting count/cursor pairs through the complete
actual scoped chunk, plus eight I/O/EOF/overflow/precedence cases. The concrete
proof instance also checks the accepted read-count continuation. A generic
computed-counter fixture preserves a shadowed caller binding across temporary
scope. Fresh extraction of the current 79-source closure is byte-identical to
the admitted program; source graph checking and emission/comparison take 7.06 s.
The gate includes the new count contracts; shell syntax passes, but the full
fresh admission/mutation sequence was not rerun.

The upstream read and request/remaining setup must still establish the count,
loaded-byte, buffer and fresh-cell premises. The outer loop's capacity decrease,
whole-call restoration and exact file/output relation remain open. So do general
preservation, extraction correctness, the native syscall bridge and x86/end-to-end
correctness. No compiler source, emission format, proof limits or trust policy
changed. Evidence: `binary/ReadStep.lean/.olean`, `ReadStepWriters.lean/.olean`,
`ReadStepSource.lean`, `read-step-*.log` and `copy-chunk-*.log` under
`target/verified-compiler`.

## October 4: actual inner copy loop (previous checkpoint)

`ByteIoReadProof.Loop.run` proves total correctness of the actual inner
`byte_io.read_file` loop. Starting with index zero and independently specified
loop-entry buffers/bindings, it expands every packed input byte to its native
i32 output word, reaches the input count and preserves memory outside the
output prefix. It retains caller cells, other local bindings, world and views.
The contract derives execution and termination; neither is a premise. It covers
empty input, signed packed words and nonzero output cursors.

This reuses the existing counter/prefix framework. `OutputState` now accepts an
item-to-byte-chunk encoder; text and hex writers use singleton encodings and the
reader uses the four-byte i32 encoding. `BytesWrite.append` composes arbitrary
chunks, `ByteWrite.asBytes` supplies singleton chunks, and the existing `snoc`
rule is derived from them. Existing consumers were migrated, not wrapped behind
an obsolete interface. The source buffer remains unchanged because the loop
input requires disjoint source/destination ranges; this is not a language-wide
exclusive-borrow restriction.

The actual copy and loop modules total 127 physical lines (48 + 79) against the
eight-line source block at `byte_io.lani:40–47`, about 16x. The loop alone adds
79 lines and its separate fixture 58. Shared `OutputLoop` is 74 lines and
`Memory/Store` 370; these costs are not hidden from total growth. Text migration
adds four lines (397 to 401); the hex writer also uses the generalized interface.
The ratio is still above the roughly 5x target. Improve reusable composition
before repeating the explicit entry-state setup through the outer algorithm.

The final 264-line connected artifact freshly checks all four source bodies in
2.68 s. It reuses other built foundations and unchanged matched `SelfCore`
program admission, not any of the four bundled proofs. Standalone actual-loop
checking takes 1.68 s. Shared foundation rebuilding takes 2.27 s; focused memory
regressions take 3.59 s. The final 1,491-line writer regression artifact checks
ten complete source bodies fresh in 26.10 s, covering the migrated text/hex
contracts and existing byte/decimal/cursor users. That broader regression cost
is not a performance improvement or a whole-tool check. All current source and
bundle texts match, and theorem audits show only standard logical axioms.

A proved concrete loop instance crosses a packed-word boundary with sign-bit
lanes, a partial final word and nonzero output cursor. Deterministic execution
fixtures cover all 45 count/cursor pairs fitting an eight-word output, including
empty and full output, and check the entire destination, original source and
terminal counter. The allocation gate includes the new loop and fixture; shell
syntax passes, but its full fresh admission/mutation sequence was not rerun.

The actual enclosing initializer, scopes, capacity guards, host reads and
`total += count` still need composition. The outer loop can potentially use
remaining capacity as a decreasing measure: continuing iterations have positive
counts within the remaining space, while EOF/errors/overflow return. That is
an implementation-derived next step, not an established termination theorem.
Caller-derived entry conditions, general preservation, extraction correctness,
native syscall simulation, x86 and end-to-end correctness remain open.

Evidence under `target/verified-compiler/binary`: `CopyLoop.lean/.olean`,
`CopyLoopWriters.lean/.olean` and `copy-loop-*.log`. No Lanius source, emission
format, proof limits or trust policy changed.

## October 4: actual computed-index copy (previous checkpoint)

`ByteIoReadProof.actualCopyByte` now proves the actual reader assignment, not
just its RHS. Generalized existing raw-store rules derive the computed index,
native store and exact byte frame; operand computations must preserve state.
The actual proof covers arbitrary packed bytes, including sign-bit lanes,
with no assumed evaluation/store success. It retains the full non-heap state.
The unused separate actual-RHS contract was folded into this complete step.
Whole copy/read loops, caller-derived bindings/ranges, effectful raw-place
preservation and the native runtime bridge remain open.

The actual module is 48 physical lines, shared store module 119 and separate
copy fixtures 58. Against the four-line assignment the actual module is about
12x, still above the target; the loop must reuse its contract, not replicate
its setup. A proved concrete instance inhabits all preconditions with a nonzero
cursor and negative packed word. Execution fixtures cover every lane, neighboring
nonzero slots and destination bounds traps.

Fresh actual checking: 1.73 s; focused proof/execution fixtures: 1.42 s.
The final 1,658-line store/consumer bundle checks all 15 current source bodies
fresh in 30.44 s. The 1,249-line writer regression bundle checks eight bodies
fresh in 20.80 s. Both reuse other built foundations and unchanged matched
program admission, not their bundled proofs. These broader times are regression
costs, not a claimed speedup; seconds-scale connected checking remains a target.
All 21 distinct bodies and bundle texts match current sources, and audits show
only standard logical axioms. The allocation gate includes the new fixture;
shell syntax passes, but its full admission/mutation sequence was not rerun.

Evidence under `target/verified-compiler/binary`: `IndexedStores.lean/.olean`,
`IndexedWriter.lean/.olean` and `indexed-*.log`. No compiler implementation,
emission format, proof limits or trust policy changed.

## October 4 checkpoint

Cell-target/reference/slice rules and generalized root assignment are checked.
Their actual evaluator consumers cover borrowing, array conversion, dereference,
indexing, initialization and RHS mutation. The shared assignment rule also feeds
`Extraction/WriterCursor.lean` and the actual self-extracted output-writer proof.
Native views, raw storage and whole-body preservation are not closed by this.

New target/reference/slice modules total 229 lines; typed list slicing adds
16 helper lines. Separate target fixtures add 141 lines, and the existing store
fixture grows from 160 to 198 lines. Existing assignment rules were generalized,
not retained alongside an obsolete typed wrapper. The actual frame lookup lemma
was moved from `ReadOnlySlice.lean` to `Frame.lean`, without forwarding modules.

Fresh library checks with built imports take 0.99–1.17 s; the target fixture
checks in 1.11 s and the store fixture in 1.16 s. A connected regression build
including the moved shared-frame dependency takes 11.18 s; the later focused
assignment build takes 1.26 s with its other dependencies already built.

The actual writer dependency closure is freshly checked in one 1,063-line
generated test bundle in 24.63 s. Only byte-identical `SelfCore` admission is
reused: fresh extraction and source-boundary checks take 7.25 s and match that
program. None of the writer contract sources is reused as a cached proof.
The low-overhead profile passes in 25.12 s and reports 12.9 s tactic execution,
8.35 s simplification and 1.68 s type checking. These cumulative asynchronous
measurements are not a partition of wall time. This is still too slow, not a
performance improvement; investigate the concrete simplification paths before
scaling this compiler-proof pattern. Audits show only standard logical axioms.

Evidence: `target/verified-compiler/binary/target-validity-*.log`, with fresh
source/checking logs, `AssignmentWriter.lean` and its checked `.olean`.

## October 4: native synchronization and shared lookup

`Semantics/Typing/Native/{Array,View}.lean` derive typed i32 encoding at the
four-byte stride, typed decoding of arbitrary bytes, and successful cell-to-heap
and heap-to-cell synchronization. The shared accessibility invariant requires
typed declared cells, initialized correctly typed view targets, readable native
ranges and unique heap block bases. It does not require unchanged old cell values
or assume encoding, heap access or synchronization succeeded.

Existing-view reuse and first local-array exposure execute through the actual
evaluator. First exposure requires an independently specified allocation
frontier and derives fresh borrowed storage while retaining old views, including
for empty arrays. This is still not a global layout/ownership/coherence theorem:
accessibility permits overlapping ranges and repeated target registrations.
Byte fidelity, consistency between registrations, lifetime and the complete
runtime-state invariant remain required work.

`Semantics/HostCall.lean` composes native refresh with actual host effects.
Its file-read and stdout rules derive the modeled service's execution from
readable storage; invalid handles may return -1. The actual self-extracted
`verified::host` declarations instantiate those rules in
`verified_compiler/tests/direct_host_views.lean`. These are not proofs of the
native syscall bridge, callers' complete algorithms or general extraction.

The native library adds 234 physical lines; the host module is 124 including
its existing no-view rule. The shared target's live-local read adds 12. Fixtures are separate: 176 native lines
and 41 lines for the actual declaration instantiations. Existing cell, heap,
execution and target foundations remain dependencies. Contents live under
`Typing/Native/`, without forwarding files at the old temporary paths.

A fresh connected check of all five new/changed native sources, fixtures and
actual declaration contracts passes in one 586-line bundle in 2.90 s. It reuses
shared foundations and byte-identical `SelfCore` admission, not those bundled
proofs. Checking just the actual declaration contracts with built shared imports
takes 1.41 s. Focused regression builds cover native, target, host allocation and
lookup rules. Arbitrary signed words and file environments, aliases, fresh empty
views, signed extrema and malformed storage are covered. Only standard logical
axioms appear; no proof limits or trust shortcuts changed.

The separate 1,063-line writer bundle now checks in 18.93 s instead of 24.63 s,
with the same byte/text/decimal/cursor claims and cached program admission only.
Lookup traverses existing chunks, retains first-match semantics, and shares
checked facts across asynchronous proof branches. Decimal guard simplification
no longer repeatedly rewrites the entire context. The low-overhead profile takes
19.62 s: simplification 6.85 s, tactics 13.1 s, type checking 1.26 s and imports
0.602 s. These cumulative asynchronous counters overlap. The improvement is
about 23%, not an order-of-magnitude result; the writer remains above the target.

Evidence: `target/verified-compiler/binary/native-view-{final-build,connected-check}.log`,
`native-host-actual-check.log`, `NativeViews.lean` and its `.olean`,
`writer-shared-lookup-check.log`, and `writer-optimized-profile.log`.

## October 4: exact native bytes and readonly host framing

The i32 codecs now recover complete values/bytes, not just type and length.
Both array roundtrips follow by induction from the shared scalar codec. The
value roundtrip requires representable typed i32 elements: encoding an arbitrary
mathematical integer deliberately truncates it. Exact-length native byte ranges
decode and re-encode without changing a byte.

`Semantics/Typing/Native/View.lean` separates accessibility from byte coherence.
Its existing flush induction now also proves a byte frame and establishes
coherence when registered ranges are pairwise disjoint. This does not forbid
aliased locals/references sharing one canonical registration.
`Native/Coherence.lean` proves that flushing a coherent state changes nothing,
and that refreshing it changes nothing when physical cell IDs are unique.
The existing evaluator-wide inventory theorem already preserves that uniqueness
from a bounded, unique initial inventory; this is not a duplicate inventory proof.

The strengthened stdout rule derives flush, actual modeled host execution and
refresh. Its result updates only heap/world: all cells, aliases, lexical locals,
the allocation frontier and registered views remain exactly the original ones.
Output equals the requested range of the flushed heap. The actual self-extracted
stdout declaration instantiates the rule in `tests/direct_host_views.lean`.
No host success, synchronization success or expected output is an input premise.
The syscall bridge and complete callers' storage invariants remain separate gates.

Two existing scalar codec proofs moved from extractor packing modules into
`Semantics/Native/Codec.lean`; consumers use their real shared contents, not
compatibility aliases or forwarding files. Shared codec/array/projection/view/
coherence/host sources total 713 physical lines, including old rules, imports,
comments and audits. Native fixtures are 258 lines; actual host-declaration
contracts are 57. These are separate from existing store/heap/evaluator foundations,
not a proof-to-source ratio for the whole compiler.

One fresh connected 1,037-line bundle checks all eight current sources in 6.08 s.
Only shared foundations and byte-identical `SelfCore` admission are reused; none
of the bundled proofs is cached. Actual host contracts with shared imports built
check in 1.56 s. Focused native/host/packing/store regressions pass in 1.68 s with
other dependencies built. The unchanged 1,063-line writer artifact also passes
after codec relocation in 21.45 s; this is a regression check, not another claimed
speedup over the previous 18.93 s run. All audited contracts use only standard
logical axioms, with no changed proof limits or trust shortcuts.

Fixtures include arbitrary signed words, exact output bytes, nested projections,
out-of-range truncation, duplicate physical IDs, and a typed readable overlapping
registration that flushes successfully but breaks byte coherence. Strong contracts
reuse the shared rule directly rather than constructing a deeply nested proof
term by unpacking and repacking it. No kernel recursion limit was raised.

Item 11 stays partial. Refreshing new host bytes into mutually independent targets,
fresh-view coherence preservation, region/target consistency, lifetime/ownership,
whole-evaluator preservation, actual extraction and x86 composition remain open.

Evidence under `target/verified-compiler/binary`: `NativeCoherence.lean/.olean`,
`native-coherence-connected-check.log`, `native-coherence-final-build.log`,
`native-host-actual-coherence-check.log` and `writer-codec-relocation-check.log`.

## October 4: coherence after host writes and fresh local views

`Typing/Projection/Frame.lean` proves that updating one struct/array branch
retains reads from independent branches at arbitrary depth. The typed writer
now retains its already-proved reconstruction result so consumers can apply
that frame without reconstructing the update. A second shared law proves that
typed i32-array leaves from one declared root either coincide or are independent.

`Typing/Native/View.lean` adds one registration per canonical root/path as a
separate invariant. Typed accessible targets plus that invariant derive pairwise
target independence; aliased locals/references remain allowed. The existing
refresh induction now establishes byte coherence after arbitrary readable
host-written bytes, including separate arrays nested inside one shared cell.
Native ranges need not be disjoint for refresh because it reads one fixed heap.
The existing fresh-local-array rule also preserves prior coherence and unique
registrations, using the actual missing-registration guard and allocation frontier.

The modeled file-read rule and the actual self-extracted read declaration in
`tests/direct_host_views.lean` retain the stronger coherence result. Invalid file
handles are still permitted. The nested fixture derives the registration premise
for two arrays inside an aliased struct and permits arbitrary bytes, handles and
file worlds. A negative fixture shows duplicate target registrations can refresh
successfully yet remain incoherent. Successful execution is not a theorem premise.
These rules do not prove the native syscall bridge or complete file-reader callers.

One fresh 1,225-line connected artifact checks all eight current frame/native/
host/fixture/actual-declaration sources in 4.56 s. It reuses built shared
foundations, including the strengthened cell/store bridge, and byte-identical
`SelfCore` admission; none of the eight bundled proof sources is cached. The
bundle was compared with those sources. Actual host contracts alone check in
1.56 s with built imports. Focused native, nested-projection, declared-store,
host and writer-cursor regressions pass in 6.48 s including dependent rebuilds.
No whole-compiler speedup follows from timings of this smaller component.

The measured shared codec/array/projection/view/coherence/host set is now 960
physical lines, up from 713 (+247). Native fixtures are 357 lines, the existing
projection fixture is 116, and actual host contracts are 58. Cell/store/evaluator/
heap foundations are additional dependencies; these library counts are not a
whole-compiler proof-to-source ratio. Audits contain only standard logical axioms,
with no raised proof limits, native shortcuts or added trust.

Item 11 remains partial. Next: compose registration, region/allocation and target
invariants through construction and mutation, then discharge the real callers'
premises. Raw/temporary paths, lifetime/ownership, whole-evaluator preservation,
actual extraction and source-to-x86 composition remain open.

Evidence under `target/verified-compiler/binary`: `NativeRefresh.lean/.olean`,
`native-refresh-connected-check.log`, `native-refresh-final-regression.log`,
`native-nested-host-build.log` and `native-read-actual-coherence-check.log`.

## October 4: pointer exposure and read composition

`Typing/Native/Mapping.lean` replaces the two local-only mapping rules with a
shared first-registration proof for arbitrary typed nested array paths, a
both-branch mapper, and small evaluator rules for array and slice pointers.
`I32ViewsReady` bundles accessible typed storage, the allocation frontier and
unique registration keys. Mapping preserves readiness, supplies the exact readable
byte range, and retains prior coherence when present. Sub-slices offset the
canonical whole-array pointer; raw descriptors retain their existing pointer.
Neither this predicate nor readable raw storage asserts full ownership/lifetime.

Flush now retains its proved allocation-frontier preservation result. The existing
`BytesWrite.below` proof moved intact from `Memory/Output.lean` to `Memory/Store.lean`;
there is no alias or forwarding module. A shared typed cell-effect rule supplies
native target/store preservation and replaces the duplicated refresh setup.

The source audit confirmed the extractor uses `i32SliceDataPtr`, usually on raw
scratch buffers created by allocation/from-raw-parts, rather than `i32ArrayDataPtr`.
`RunsExpr.readSlice` therefore handles both cell and raw descriptors, after
operand effects, and derives the requested byte range from descriptor validity
and bounds. The actual self-extracted read declaration instantiates this rule in
`tests/direct_host_views.lean`; its ordinary contract also preserves readiness.
Host/synchronization success is derived, with invalid handles still allowed.
The descriptor's construction/validity and the operand's execution remain caller
obligations: this is not a proof of the complete `byte_io.read_file` function.

Fixtures cover pointer reuse, first exposure of a nested sibling, new and existing
registrations through a nonzero-offset sub-slice, raw scratch descriptors, arbitrary
bytes/worlds/handles, aliases and empty views. Existing rejection/counterexample
properties remain intact. No Lanius source, emitted representation or trust policy
changed, and no typing-proof tree or per-program validator was added.

One fresh 1,525-line connected artifact checks all nine current frame/native/
mapping/host/fixture/actual-declaration sources in 3.80 s. Shared foundations,
including the relocated byte-write law, and the previously matched `SelfCore`
admission are built; none of these nine proof sources is cached. The artifact was
compared with the current sources. Actual host contracts check in 1.43 s with
shared imports built; final focused native/store/host/output/writer-cursor
regressions pass in 3.84 s including dependent rebuilds. These are component costs,
not whole-compiler timings or an apples-to-apples speedup over the smaller bundle.

The same measured shared source set now includes `Mapping.lean` and totals 1,163
physical lines, up from 960 (+203). Native fixtures are 436 (+79), the existing
projection fixture is 116, and actual declaration instantiations are 76 (+18).
Existing evaluator/store/heap foundations remain dependencies; these counts are
not a whole-compiler proof ratio. Audits use only standard Lean logical axioms.

Next concrete gate: derive raw scratch validity/readiness from the actual allocator
and descriptor-construction calls, then prove the byte-I/O loop's data and
termination contract. General region/lifetime composition, whole-evaluator
preservation, actual extraction and end-to-end x86 correctness remain open.

Evidence under `target/verified-compiler/binary`: `NativePointers.lean/.olean`,
`native-pointer-connected-check.log`, `native-slice-final-regression.log` and
`native-slice-actual-check.log`.

## October 4: actual scratch allocation and read composition

The existing actual allocator/constructor contracts now feed `actualScratch`
in `tests/direct_ir_allocation.lean`. Positive representable sizes and numeric
budget capacity derive the readable raw descriptor, storage readiness and old
heap-read frame. `readScratch` in `tests/direct_host_views.lean` consumes those
facts at the actual read declaration; it assumes neither a readable destination
nor a successful allocation/constructor/host read. The no-registration route is
explicit. This does not prove the complete driver or byte-I/O loop.

Shared fresh-cell/heap-read framing retains readiness and old slice validity.
The generic indexed scalar-read proof moved into the native codec without an
alias. Shared growth is 37 physical lines; program connections add 65 and
fixtures add 38. The matching contract sections alone are 208 lines for 22 source
lines, above the 5x target even before common host-file plumbing. Use existing
call composition to reduce repeated setup before scaling the loop proof.

All three actual proof/fixture sources check fresh in one 439-line artifact in
3.22 s, with shared foundations and unchanged previously matched program
admission built. The bundle matches current sources. Focused regressions pass
in 1.86 s and actual fixtures in 1.40 s. Audits use only standard logical axioms.
Fixtures cover old raw storage, finite-budget exhaustion, malformed size guards,
arbitrary file worlds/handles and bounded requests, including zero requests.

Items 8, 9 and 11 stay partial: live-registration allocation, general raw lifetime
and ownership, global preservation and actual caller/loop composition remain.
Extraction, x86 simulation and end-to-end correctness are still open. The full
26-item goal remains active. Evidence: `binary/ScratchRead.lean/.olean` and
`scratch-*.log` under `target/verified-compiler`.

After migrating three old qualified references, the existing child-walker and
type-cache contracts and their dependency bodies also check fresh together in
one 1,347-line artifact in 28.50 s. This broader regression is not a speedup or
newly closed obligation. Evidence: `CodecConsumers.lean/.olean` and
`scratch-codec-consumers-check.log` in the same directory.

## October 4: share allocator call and scope bookkeeping

`RunsExpr.callStores` specializes the existing proved call/postcondition rule
for heap, world and registered-view observations. Its body contract still proves
actual execution and a fresh-cell frame. `RunsExpr.allocatedI32Slice` composes
effectful arguments with the existing allocation/protection law; it derives the
constructor result rather than assuming construction succeeded. The actual
allocator and raw-slice wrapper now use these rules and existing `MemoryEffect`
scope restoration. Redundant explicit locals equalities are removed from these
two contracts: consumers obtain the same equality from `RunsExpr` itself.

Allocation proof source shrinks by 32 physical lines; its builder consumer grows
by one line, and the fixture's tuple adjustment adds no lines. The shared rules,
import and axiom audits add 39 lines, so these production changes total +8, not
a net repository-size reduction. The matching contract sections from the prior
checkpoint shrink from 208 to 176 lines against the same 22 source lines,
roughly 8x rather than 9.5x. This remains above the 5x target; common host plumbing,
shared foundations and fixtures are additional costs.

All three current allocation/host/fixture source bodies check fresh in one
404-line bundle in 3.38 s. It reuses only built shared foundations and unchanged,
previously matched program admission, not any bundled proof. A second fresh
1,751-line bundle checks the full source dependency closure through the actual
builder call in 28.02 s. Both bundles match current source contents. The latter
is a regression check, not a new performance improvement or closed compiler
obligation. The focused shared rebuild takes 12.97 s; actual allocation contracts
alone take 2.93 s. Audits report only standard logical axioms.

No Lanius implementation, output format, proof limit or trust boundary changed.
The next algorithm gate is exact host-read data/cursor effects and their use by
the actual byte-I/O copy/termination proof. Storage/global preservation, general
extraction, x86 simulation and end-to-end correctness remain open. The full
26-item goal stays active. Evidence under `target/verified-compiler/binary`:
`ScratchRead.lean/.olean`, `AllocationBuilder.lean/.olean` and `compact-call-*.log`.

## October 4: exact read effects and actual packed-byte decoding

The existing read rules now return `ReadEffect`/`PointerReadEffect`, including
the real synchronization boundary, invalid-handle result, exact byte-write frame,
returned count and modeled file-world update. No duplicate weaker interface is
retained. Shared projection rules select a proved pointer boundary by execution
determinism and eliminate flushing on the no-registration route. `FileReadResult`
preserves readability and proves that requests below 2^31 return -1 or a signed
count between zero and the request. Actual scratch composition retains these
effects, its allocation-world change and full scratch readability after reading.

`OutputPacking/Read.lean` derives an indexed word and its selected byte from any
readable packed range. `tests/direct_byte_io_read.lean` applies it to the actual
`byte_io.read_file` copy RHS, including arithmetic sign extension. The word need
not be zero or positive. This proves the read expression, not its destination
write, index increment, loops or whole call. Its byte/readability/binding premises
remain to be discharged by that enclosing loop; the read contract supplies data
and storage facts, but the full composition is not yet proved.

All eight current shared/actual/fixture bodies check fresh in one 1,320-line
bundle in 5.26 s. Only other shared foundations and unchanged previously matched
`SelfCore` admission are built; none of the bundled proofs is cached. Source
comparison passes. Focused shared/native regressions take 3.39 s; the actual copy
contract alone takes 1.78 s. Audits show only standard logical axioms. Actual
fixtures cover arbitrary file bytes/offsets, zero requests, EOF, invalid handles,
exact cursor/data effects and bounded signed returns. The positive allocation
gate includes the new copy proof; shell syntax passes, but the complete fresh
admission/mutation script was not rerun here.

Shared production growth is 100 physical lines; actual allocation/host contracts
grow by eight and the new copy module adds 40, for +148 production lines. Fixtures
grow by 67 and the gate by three. The previous matching allocation/descriptor/read
scope is now 183 versus 22 source lines. The whole copy contract module is 40
lines for a RHS spanning four source lines: about 10x, above the 5x target. Common
host plumbing and shared foundations remain additional costs. Improve the
composition interface before multiplying this setup throughout the loop proof.

Next: computed-index raw-store composition, the actual copy-loop invariant and
termination, then outer file-cursor progress and capacity/error branches. Full
storage/evaluator preservation, general extractor correctness, x86 simulation
and end-to-end correctness remain open; all 26 goal items remain in scope.
Evidence: `binary/ReadEffects.lean/.olean` and `read-effect-{all-connected-check,
foundation-build,copy-check}.log` under `target/verified-compiler`.
