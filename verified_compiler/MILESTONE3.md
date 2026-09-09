# Milestone 3: finish the extractor correctness proof

This is the execution plan from September 7, 2026 onward. It replaces the
chronological “next work” notes in `PLAN.md`. The seven-step user goal is
unchanged; this document organizes its third milestone, not a smaller substitute.

## Done means

The exact Lanius extractor source has one validated self-embedding, and Lean
proves its general execution contract for supported inputs. The result must
connect the actual checked `main` to the requested files and emitted module.
It must not assume that a component ran correctly, that its output passes a
validator, or that its caller happens to satisfy an internal invariant.

The existing targets in `formal/Lanius/Extraction/ExtractorContract.lean` are:

- `RunSound`: a zero return establishes `Success`, including exact ordered
  sources, a syntax certificate, exact stdout, preserved files/arguments,
  restored file handles, and memory safety.
- `RunFailureSafe`: a nonzero normal return establishes classified failure,
  preserved external inputs, restored handles, and memory safety.
- `RunComplete`: supported inputs terminate successfully with enough fuel.
  Support must describe syntax and concrete resource/host conditions; it must
  not be defined as “the extractor succeeds” or “its output is accepted.”

State initial runtime and host assumptions explicitly. Do not make soundness
vacuous by proving it only for a pre-assumed successful result. Do not classify
traps or fuel exhaustion as deliberate failures. Establish termination/no traps
on the stated domain; distinguish modeled host behavior from native OS behavior.

`AcceptedSuccess` additionally requires the typed-Core checker to accept.
Ill-typed but syntactically valid input need not fail syntax extraction.
The current Lanius producer emits syntax evidence; fixed Lean infrastructure
reconstructs Surface and synthesizes Core. Proving a full compiler implemented
in Lanius remains part of the later compiler milestones.

## How work proceeds

Only one numbered step is active. Finish its exit criteria before implementing
the next. Helper lemmas are subtasks, not completed pipeline boundaries.
Every step's closing report names its theorem, actual-source connection,
remaining external assumptions, focused check, and axiom audit.

Use existing component proofs. First try to derive the next component's
preconditions from its predecessor's result. If evidence was dropped, retain
it at the owning interface; do not reconstruct it from weaker facts or add it
as an unproved caller premise. If a step needs an unexpected new proof family,
update this plan and explain the alternative before pursuing that expansion.

The command limit is now two minutes, updated by the user on September 7.
Prefer short focused checks. On a timeout, optimize the expensive
check before retrying; do not divide one long check into artificial pieces.
Do not run the roughly 21-second source integration check for every local
lemma. Run it when the source/link boundary changes or a step closes.

## Ordered completion ledger

| Step | Boundary that becomes complete | Status |
|---|---|---|
| 1 | Successful recognizer result → callable derivation record reader | Complete; call connection checked and trust assumptions audited |
| 2 | Retained workspace → complete materialized tree | Complete on the stated caller domain; success, resource failures, wrapper rejection, source link, and axiom audit checked |
| 3 | Source buffer → complete `extract_syntax` result | Complete on the stated caller domain; whole public call, all stage failures, negative-length rejection, current-source links, and axiom audit checked |
| 4 | Extracted unit → exact accepted compact unit encoding | Active: collector/emitter calls, decoding bridges, and complete syntax acceptance proved on stated domains; final output-byte connection remains |
| 5 | Ordered files → exact successful `main` output | Open; depends on 4 |
| 6 | Failure/completeness theorems and milestone acceptance audit | Open; depends on 1–5 |

Steps 1–3 are complete. Steps 4–6 remain open, and milestone 3 is not complete.
Completion here records the checked pipeline boundary; the inherited native
proof assumptions still require the final trust cleanup in step 6.

### 1. Recognizer to derivation reader

Existing evidence:

- `VerifiedFrontend/Parser/Recognize/Setup.lean` supplies
  `RecognizerCallExecution`, its concrete call evaluation, final workspace
  encoding, and output-only effect.
- `VerifiedFrontend/Parser/Recognize.lean` proves
  `RecognizerInvariant.backpointersSound` internally.
- `Parser/Derivation/Entry.lean` proves the whole reader success path.
  `Transport.lean` checks whole-body relocation and transports calls;
  `Postcondition.lean` transports exact record contents and the write footprint.

Original gap found in the audit: `RecognizerCallExecution` did not expose
`WorkspaceBackpointersSound` for its `finalWorkspace`. Its `growth` is a
`WorkspaceAppendClosure`, whose append constructor admits arbitrary seeds.
That is storage-growth evidence, not semantic derivation evidence. The reader
required the stronger property as a separate premise. The completed connection
below derives it and ties the returned root/state-count fields to the final
physical workspace.

Ordered subtasks:

1. Retain the semantic workspace/root evidence through the existing successful
   recognizer return path and expose it in its public result.
2. Derive reader call-entry resources, actual arguments, bounds, and name/cell
   separation from that result and caller-owned output storage.
3. Compose the current linked calls and their postconditions.

Step 1.1 checked: `Compiler/ParserRoot.lean` defines `StoredRootParse`,
which retains backpointer soundness and proves that materializing the selected
stored root yields the certified tree. Its constructor checks and its axiom
audit contains only `propext`, `Classical.choice`, and `Quot.sound`.
Root selection carries this certificate through acceptance. The
`outcomeWorkspace` proof now preserves its connection to the final physical
workspace through position, initial, setup, and call scope restoration.
`RecognizerCallExecution.successRoot` in `VerifiedFrontend/Parser/Soundness.lean`
derives the stored root and its membership from the observed zero status.
Its result also equates the returned value with the exact workspace state
count and root index; `RecognizerRootResult.root_lt_stateCount` supplies the
reader's index bound. No separate workspace-soundness premise is introduced.

Verification: the root, position, and initial modules checked; the final
Setup/Soundness build passed in 8.91 seconds with their dependencies cached
(`recognizer-root-result-verified.log`). The focused audit passed in 1.65 seconds
(`recognizer-root-audit.log`). The new public result contract uses only standard
Lean axioms. The full `executeRecognizerCall` still inherits existing
`native_decide` assumptions; this is not a claim of kernel-only end-to-end trust.
That debt remains in step 6. Lanius source and its checked body connection did
not change in this subtask.

Step 1.2 checked: `Parser/Derivation/Caller.lean` constructs the reader's eight
callee bindings and physical entry resources. The source checker now checks
the buffer parameter identities and distinct local names; callers do not
assume them. `CheckedReader.read_recognizer_root` derives the entire standalone
reader-body execution from `RecognizerCallExecution`, an observed zero status,
the original output storage, and explicit capacity/separation bounds. It derives
root membership, backpointer soundness, the state bound, and preserved output
storage. The output theorem states the exact record and untouched prefix/suffix.
The recognizer result also retains preservation of runtime well-formedness.

Verification: `reader-recognizer-entry.log` passed in 8.24 seconds (Caller itself
7.3 seconds). `reader-caller-audit.log` passed in 1.58 seconds; its three new
entry/execution theorems use only standard Lean axioms. The changed source
contract passed the existing complete source-link check in 21.23 seconds
(`reader-names-source-run.log`). This verifies the current source connection,
not the whole extractor's execution contract.

Step 1.3 checked: `Parser/Derivation/Recognition.lean` supplies
`LinkedReader.recognize_then_read`. It constructs `executeRecognizerCall` from
argument evaluation and public entry resources, transports that recognizer call
to the checked extractor, derives the eight reader argument values from the
successful result, and executes the linked reader call. Its result contains the
exact derivation record, retained workspace, untouched output prefix/suffix, and
the output-only write footprint after closing the reader's call scope.

`LinkedReader.call_state` (generalized from `call_root` in 2.1) also supports caller-provided argument expressions,
with their ordinary evaluation proof. It does not require the caller to prove
the reader body executes. Step 2 can use this form at source-local call sites.
The top-level connection uses value-level function invocation; it does not claim
that the surrounding `parse_tree.visit` implementation is already proved.

Step 1 closing checks:

- The final connection build passed in 1.93 seconds; Recognition itself took
  1.2 seconds (`recognizer-reader-entry-calls.log`). These are incremental checks,
  not a whole-frontend or cold-build benchmark.
- The current-source checker and whole-body relocation passed in the 21.23-second
  check above. No Lanius source changed after that check.
- The final axiom audit passed in 1.76 seconds (`recognizer-reader-audit.log`).
  The reader call has only standard Lean axioms. `recognize_then_read` inherits the
  existing recognizer's native assumptions; no new native proof shortcut was added.
- External assumptions are explicit: a checked source/link, grammar and buffer
  entry resources, well-formed initial caller state, observed parser acceptance,
  symbol/dependency closure, separate output storage, and sufficient output capacity.
  The existing `parserRecognizeCallee_entry` constructor derives the entry resources
  from ordinary caller storage and grammar facts. There is no independent root
  membership, semantic-workspace, callee-execution, or final-output premise.

Next numbered boundary: step 2, complete tree materialization.

Verification history during 1.1: the dependency rebuild reached
the 29-second command cutoff before checking Root.Selection. State.Core alone
took 27–28 seconds. Profiling also measured Parent at 11.62 seconds; its cost
is distributed. An attempted literal-matcher simplification in State.Core hit
the cutoff and was reverted. These retries were not performance improvements.
A later profile isolated 2.4 seconds of kernel reduction in
`recognizerSeedSetupCommand_toCore_exactly`. Retaining the checked reification
as an opaque value avoids recomputing that projection: setup's measured kernel
time fell from 4.39 to 1.77 seconds, and its complete focused check from 9.82 to
7.39 seconds. The retained value is type-checked, not an added axiom; its existing
native reification-existence assumption remains visible in the audit. Logs:
`recognizer-setup-kernel-profile.log`, `recognizer-setup-opaque-profile.log`.
These are focused setup timings, not a cold dependency-build benchmark.

Exit: a checked-source theorem starts with ordinary recognizer caller inputs
and derives a successful reader call and exact record for the returned root.
It covers arbitrary valid buffer addresses and preserves the workspace and
unwritten output regions. No independent backpointer-soundness, root-membership,
callee-execution, or correct-output assumption remains. Capacity assumptions
stay explicit. This theorem is the interface consumed in step 2.

### 2. Workspace to complete tree

Source: `src/verified/parse_tree.lani`, especially `visit` and `materialize`.
Reuse step 1 and the logical materialization results in
`formal/Lanius/Compiler/ParserTree.lean`. `Extraction/ParseTree.lean` proves
properties of Lean-side linking; it is not an execution proof of this Lanius code.

Prove recursive child expansion, rewritten child IDs, offsets, postorder IDs
with preorder record storage, and expansion of shared states per occurrence.
Relate the stored tree to the selected root derivation. Carry output/depth
bounds, termination, preserved buffers, and partial-output failure rules.

Ordered subtasks:

1. Generalize the reader call to any stored state, retaining step 1's root
   connection. For a child emitted in a parent record, derive residence,
   production completeness, and a strictly smaller state ID. Exit: the recursive
   call can reuse the checked reader contract without pretending its child
   recognizes the entire input or supplying an independent child-validity premise.
2. Specify and prove the record/offset layout and resource bounds. Account for
   parent records reserved before children, postorder node IDs, token triples,
   rewritten state-child IDs, and repeated occurrences of shared states. Relate
   the layout to the existing canonical parse-tree serialization.
3. Check the exact `visit` source and prove its execution by decreasing stored
   state IDs, using 2.1–2.2 for recursive calls, loop updates, buffer preservation,
   and depth/capacity guards. No assumed successful nested call may remain.
4. Prove `materialize` and the result accessors from ordinary successful parser
   inputs; connect the final record/offset buffers to the certified root tree.
   Close the step with current-source checking, focused execution-proof checks,
   failure-path coverage, and an axiom audit.

The source inspection found that step 1's convenience call theorem accepts a
`RecognizerRootResult`, which is too strong for recursive children. Its existing
body proof already handles arbitrary resident states. Generalize that contract
in place and migrate its consumers; do not duplicate the reader proof.

Step 2.1 checked: `CheckedReader.execute_state` and `LinkedReader.call_state`
now handle any resident state in a sound workspace. The original recognizer/root
connection still checks. The existing child-reference lemmas now retain production
completeness as well as residence and strict ID decrease. `LinkedReader.call_child`
derives those facts from a child emitted by the parent reader and supplies its
linked reader execution, exact record, retained workspace, and write footprint.
Capacity is stated for the actual child; it is not inflated to a worst-case
whole-workspace bound. There are no compatibility aliases or duplicate reader proofs.

Verification: the affected proof chain rebuilt successfully in 28.49 seconds
(`reader-complete-children.log`). The final child-call build passed in 2.77 seconds
(`reader-child-call.log`), and its audit passed in 1.37 seconds
(`reader-child-audit.log`) with only standard Lean axioms. Lanius source and its
link-checking contract were unchanged; this was an internal proof API change.
Neither `visit` nor `materialize` is yet claimed verified.

Step 2.2 checked: `Parser/Tree/Layout.lean` specifies preorder record words and
postorder node IDs/offsets for arbitrary starting cursors. `tree_node_lookup`
proves that every canonical node's offset locates its complete record: production,
span, ordered token/node references, and enough room for the entire child array.
`tree_references` connects counts and root IDs to the existing serializer;
`tree_words_length` gives exact record capacity. `tree_depth_le_nodes` proves a
sufficient recursive-depth bound, with terminals requiring no call frame and
nullable productions requiring one. Repeated subtrees allocate per occurrence.
This is a storage specification and its serialization proof, not a claim that
the Lanius materializer already implements it correctly.

The existing canonical serializer needed explicit compiler-tree type names:
its unqualified `ParseTree` resolved to the extraction-layer linked tree after
an import change. Only those type references changed; serialization is unchanged.
The focused layout/regression build passed in 4.15 seconds with shared dependencies
built (`tree-layout-check.log`). It checked terminal and nullable cases, repeated
children, nonzero cursors, and differing record/ID orders. The four public theorem
audits contain only `propext` and `Quot.sound`. Lanius source was unchanged.
Step 2.3 is now active: check the actual `visit` body, then prove its recursive
execution and its correspondence to the retained workspace's materialized tree.

Step 2.3 progress: `Parser/Tree/Source.lean` checks the entire current `visit`
body, its twelve parameters, recursive and derivation-reader call identities,
all status constants, and the result constructor's signature/body/field order.
The self-embedding/source integration check passed in 22.31 seconds
(`tree-visit-source-run.log`), including the existing frontend links. It found
the current source function at ID 69; that ID is looked up, not hard-coded.

`Parser/Tree/Execution.lean` now proves `CheckedVisit.constructor_call` and
`CheckedVisit.failure_call`. The latter starts with ordinary argument evaluation
and derives the actual source call's depth-limit or initial node-table-full
return. It binds the callee parameters itself, gives the depth guard priority,
and preserves every existing caller cell, heap, world, and view while restoring
caller locals. It does not assume constructor or materializer body execution.
The focused execution/regression build and axiom audit passed in 2.75 seconds
(`tree-visit-failure-check.log`); these proofs use only standard Lean axioms.

Further 2.3 progress: `Parser/Tree/Derivation.lean` proves `children_match` and
`state_child`. They connect every ordered reader reference to the exact child
from `materializeStatePrefix?`, even with different sufficient fuel budgets.
For a state child, the result retains its selected subtree computation,
production completeness, and strict ID decrease. `Parser/Tree/Reader.lean`
uses this in `CheckedVisit.read_children`: an actual linked reader call returns
the exact record and child correspondence from ordinary current-state resources.
The existing inverse type-renaming theorem handles unrelated caller values;
the caller does not assume its runtime has a standalone reader's state shape.
The focused bridge/reader check passed in 2.60 seconds (`tree-reader-match-check.log`).

`CheckedVisit.finish` now executes the shared final-capacity guard, writes the
parent's offset at its postorder ID, and returns the incremented node count and
word cursor. Its only visible write is the selected offset-table cell.
`finish_full` proves the final capacity failure with advanced counters and no
additional buffer write. These checked in 2.77 seconds (`tree-finish-check.log`).

`Parser/Tree/Iteration.lean` proves `CheckedVisit.token_iteration`, covering the
actual slot scope, tag read, nonrecursive branch, and overflow-safe cursor
increment. It preserves the complete record buffer and returns ownership of the
updated cursor. The complete focused execution/audit target passed in 2.55 seconds
(`tree-token-iteration-check.log`). All new audits use only standard Lean axioms.
The Lanius source and source-checking contract did not change, so these local
proof additions did not require repeating the source-integration run.

Further checked 2.3 progress: `Cursor.lean` gives the partial-record invariant,
including framed payload rewriting, exact pending-triple lookup, and append
composition for completed siblings. `Runtime.lean` connects that model to the
actual buffers and three owned cursors. `TreeRuntime.At.token_step` preserves
the complete invariant through the actual terminal iteration; `At.finish`
derives the final canonical record/offset arrays and returned counts from the
empty-pending invariant. Both retain the caller's exact unused storage.

`Resume.lean` proves successful child-result stores and failure propagation
through the result-binding scope. Its continuation is factored directly from
the existing checked source template; there is no second template or alias.
The current-source integration check passed in 23.65 seconds
(`tree-resume-source-run.log`). No Lanius source changed.

`Recursive.lean` proves `TreeRuntime.At.state_step`: given an actual recursive
evaluation with exact append outputs and an output-only effect, it executes
the full state-child iteration and establishes the next loop invariant.
`ChildCall` records that induction obligation; the whole-call theorem below
now constructs it. `At.recursive_arguments` derives all twelve actual
arguments, including the pending state ID read from storage and checked depth
subtraction. The invariant now separates all fixed parameter cells from the
mutable cursors, not just parameters used in the terminal branch.

The focused execution/layout regression and axiom audit passed in 4.20 seconds
(`tree-runtime-audit.log`); Recursive itself took 2.2 seconds. Tests include
nullable/repeated children and prefix/suffix preservation around a later
payload rewrite. The new audited theorems use only `propext`, `Classical.choice`,
and `Quot.sound`; no new native decisions, custom axioms, or proof placeholders
were added. These are incremental component checks, not a whole-extractor
checking-time claim.

The post-reader component is now composed. `Entry.initialize` derives the
runtime invariant from the exact reader record and actual locals 13–15
allocations; `Entry.with_cursors` executes those initializers and hides their
fresh-cell writes on scope exit. `At.loop` processes the complete selected
sibling sequence. It derives prefix capacities from the total bounds and
retains each recursive child's membership in the parent's selected trees,
which is needed for the depth bound. `Entry.children` combines initialization,
the whole loop, and the final offset store into the actual `visitChildren`
execution and exact final arrays. Its `EarlierCalls` premise isolates the
smaller-state induction obligation, shared with the loop rather than duplicated
and discharged by the whole-call theorem below.

`Frame.lean` carries the unchanged workspace and fixed arguments through reader
output writes, cursor setup, and the whole loop footprint. `Caller.lean` derives
all twelve callee parameters from ordinary caller storage (`TreeRuntime.enter`),
checks their binding against the actual source signature, and invokes the
reader directly (`CallEntry.read`). That call derives the post-reader entry,
ambient frame, exact selected children, and strict child-ID bounds.
`CallEntry.body` executes the initial depth/capacity guards, both reader-result
guards, and the real result-binding scope around the supplied reader and child
executions. It is a composition theorem, not yet an unconditional whole-call
correctness theorem by itself.

The combined focused regression/axiom audit passed in 2.81 seconds
(`tree-caller-composition-audit.log`). The new composition theorems use only
standard Lean axioms. No Lanius source changed, no new proof placeholders or
native proof shortcuts were introduced, and the command ceiling was respected.
These timings remain incremental component checks with shared infrastructure
built; they do not establish whole-extractor checking performance.

The decreasing-state induction is now checked. `Call.lean` proves
`CheckedVisit.call_state` for the actual source function call. It constructs
the reader execution, private cursor allocation, complete sibling loop, and
every recursive child call, then restores caller locals. Each recursive call
uses a strictly smaller resident state ID, the exact selected child computation,
its depth bound, and the remaining physical capacities. The conclusion gives
the exact record/offset splices, returned counts, retained workspace, and
output-only cell footprint. Ordinary argument evaluation may have effects;
the resource contract begins after it. No `EarlierCalls`, `ChildCall`, callee
execution, private-local ownership, or ambient-frame premise survives.
The focused whole-call build passed in 5.03 seconds (`tree-whole-call-check.log`),
and its axiom audit passed in 1.85 seconds (`tree-whole-call-audit.log`).

The public success path is also connected. `Materialize.lean` proves
`CheckedMaterialize.call`: a successful recognizer's `RecognizerRootResult`
selects the exact semantic tree, the three actual parser-result accessor calls
supply status/count/root, and the complete `visit` call produces that tree's
record/offset buffers. The theorem derives the materialization computation
from the recognizer result; it does not assume an independently correct tree.
The caller supplies the unchanged encoded workspace, disjoint buffers, exact
capacities, sufficient depth, ordinary argument evaluation, and a well-formed
runtime. These are explicit entry conditions, not presumed stage execution.
The focused materializer call build passed in 2.20 seconds
(`tree-materialize-call-check.log`).

`Source/Projection.lean` checks and proves the shared field-accessor behavior
against current source, for parser and tree result fields. `Root.lean` checks
and proves the complete `tree_root` accessor: nonzero status returns `-1` even
when partial counts are positive; zero status performs the modeled i32
subtraction. `MaterializeSource.lean` checks the public wrapper, its actual
accessor identities/types, and the parser success constant. There is no
historical-artifact ID assumption or duplicate Lanius implementation.

The combined execution/layout regression and axiom audit passed in 1.69 seconds
(`tree-materialize-audit.log`). All new public theorem dependencies are limited
to `propext`, `Classical.choice`, and `Quot.sound`. Lanius source was unchanged;
the current self-embedding passed the expanded materializer/accessor source
check in 22.33 seconds (`tree-materialize-source-run.log`). The final source run,
including the distinct `tree_root` body, passed in 22.11 seconds
(`tree-materialize-complete-source-run.log`).
These are focused incremental timings, not an end-to-end extractor benchmark.

Capacity failure is now proved at the actual reader and `visit` call boundaries.
`Derivation/Entry.lean` factors the existing input/workspace checks into
`Entry.with_checked_count`; the success proof uses that same entry path.
`Derivation/Failure.lean` derives the real count read and both capacity branches,
then closes the complete reader body and linked call (`LinkedReader.call_full`).
It returns `-2` and preserves every existing caller cell. The offset must be
within the supplied buffer, and the retained state/workspace must be valid;
there is no assumed count read, failed execution, or private-local resource.

`Tree/Failure.lean` proves `CheckedVisit.record_full_call`. With positive depth
and initial node room, insufficient record storage causes the actual failed
reader call, the `-2` test, and the result constructor to return
`TREE_OUTPUT_FULL` with the original counters and no existing-cell writes.
This applies equally to a nested invocation whose caller buffers already hold
partial output. The checked reader call took 3.05 seconds
(`reader-full-call-check.log`); the complete `visit` capacity-failure call took
1.88 seconds (`tree-record-full-call-check.log`).

`At.state_entry` now shares the actual slot/tag evaluation between success and
failure. `At.state_failure` closes the entire failed-child iteration without
additional parent stores or sibling increment, preserving the child's returned
status/counts and output changes. It still requires a failed recursive call;
the whole-call induction must construct that premise. This is not yet the
general recursive failure contract. The affected modules checked in 8.64
seconds (`tree-child-failure-check.log`).

The success proofs, new failure proofs, layout regressions, and eight direct
Core capacity-boundary evaluations passed in 1.80 seconds
(`tree-failure-boundary-audit.log`). Boundary cases include zero/short headers,
exact header/triple fits, one word short, and nonzero starting offsets. A trap
or fuel exhaustion cannot count as a successful rejection in these tests.
The audited theorem dependencies remain standard Lean axioms only. No Lanius
source or checked-source shape changed, so the previous 22.11-second source
validation remains applicable; it was not repeated for these proof-only edits.

Current 2.3 components (these are not separate completed pipeline steps):

| Component | Evidence / remaining work |
|---|---|
| Complete source shape and early call failures | Checked |
| Public call entry → actual reader → exact selected children and record | Checked |
| Physical loop invariant, actual cursor initialization, terminal-child iteration | Checked |
| Workspace/fixed-argument frame preservation | Checked |
| Recursive arguments | Checked, including stored state ID and depth arithmetic |
| State-child iteration and invariant transition | Checked; `call_state` constructs `ChildCall` by induction |
| Final offset store / capacity failure | Checked; successful exit now derives exact complete layout |
| Complete sibling loop and post-reader source component | Checked; `call_state` discharges `EarlierCalls` |
| Guard and result-scope composition of the full body | Checked; requires the actual component executions |
| Decreasing-state induction and whole-call theorem | Success and bounded outcomes checked; no recursive-execution premise or sufficient-capacity premise for failures |
| Public `materialize` call and result accessors (2.4) | Success, resource failures, and public bad-input rejection checked |
| Record-capacity failure | Complete reader and `visit` call checked; no failed-execution premise |
| Nested partial-output propagation | Complete loop, recursive call induction, and public wrapper checked |

Step 2 closing result: `Total.lean` proves `CheckedVisit.call_bounded` by
decreasing stored state IDs. `At.loop_outcome` either completes all siblings
or propagates the first failed child, and `Entry.children_outcome` closes
cursor scopes and the final offset-capacity check. Each recursive outcome is
constructed by induction. These proofs need neither enough depth nor room
for the whole tree. The whole-call check passed in 3.65 seconds
(`tree-total-call-check.log`).

`Materialize.lean` now proves `CheckedMaterialize.call_bounded` for the
actual public call. It derives the selected tree, parser projections, visit
arguments, complete visit execution, and caller restoration. Its shared
private wrapper proof also supports the existing sufficient-resource
`CheckedMaterialize.call`; there is no duplicate argument/accessor proof.
The bounded public check passed in 1.98 seconds
(`tree-materialize-bounded-check.log`).

On zero status, returned counts and both serialized arrays are exact, including
the unused suffixes. On status 2 or 3, counters stay within the physical
capacities and do not move backward. Partial writes are confined to the two
output cells; the workspace and other existing cells survive. Failed buffers
are not certified trees, and the failure contract does not assert exact partial
contents. `CellEffect` preserves caller locals, modeled host world, and
well-formed cells; it does not independently assert raw heap/view identity.

External assumptions remain explicit: checked source and reader link, the
recognizer's successful root certificate, its unchanged physical workspace,
well-formed caller state, disjoint output/workspace cells, actual buffer lengths
and nonnegative depth within signed-i32 bounds, and ordinary argument evaluation.
Sufficient tree depth and capacity are required only for guaranteed success.
This is not a contract for arbitrary forged workspaces or mismatched lengths.

`CheckedMaterialize.reject` separately proves that a nonzero parser status
or a negative supplied output length returns `TREE_BAD_INPUT` with zero counts
and no existing-cell writes. The unused workspace/buffer arguments require no
storage premise: the guard short-circuits before they are accessed. The complete
wrapper guard check passed in 2.69 seconds
(`tree-materialize-guard-check.log`).

Closing verification:

- The execution proofs, layout regressions, capacity-boundary tests, and axiom
  audit passed in 1.82 seconds (`tree-materialize-outcome-audit.log`). The new
  loop, recursive call, bounded public call, and rejection theorems depend only
  on `propext`, `Classical.choice`, and `Quot.sound`.
- The exact self-embedding/source check passed in 21.17 seconds
  (`tree-materialization-closing-source.log`). It checks complete visit,
  constructor, wrapper, and accessor bodies, plus the linked reader.
- No Lanius source changed. These are focused incremental timings with shared
  infrastructure built, not whole-extractor verification timings.
- The inherited frontend native-proof debt remains a step-6 obligation.

Next numbered boundary: step 3, the complete `extract_syntax` pipeline.

Exit: the actual linked `materialize` call consumes step 1's successful parser
result and returns a valid complete tree with exact record/offset encoding.
No assumed successful `visit`, correct nested record, or accepted tree remains.

### 3. Source buffer to `extract_syntax`

Source: `src/verified/extraction.lani`.
Reuse `RawLexer/LexInto/Caller.lean` for arbitrary-address lexer calls,
`RawLexer/LexInto/Spans.lean`, `BufferCopy/Canonicalize.lean` for the actual
copy/canonicalizer scope, `BufferCopy/Tokens.lean` for kind encoding, and
`Parser/Recognize/Caller.lean` / `Linked.lean` for recognizer calls.

Connect lexing, raw-word copying, canonicalization, kind copying, recognition,
and step 2 in their actual lexical scopes. Each output must establish the next
call's preconditions, including preservation of buffers used later. Derive
stage/detail/count fields and the input/capacity guards. Do not redo the lexer
or recognizer algorithm proofs.

Ordered subtasks:

1. Preserve the lexer's caller frame and derive the raw-copy/canonicalizer
   entry from the actual lexer result. Retain arbitrary unused raw capacity:
   the source passes `raw_length / 3`, so the buffer need not have a length
   divisible by three.
2. Compose raw copying, canonicalization, kind copying, and recognition in
   their checked source scopes, carrying exact buffers and untouched resources.
3. Feed the recognizer's retained root/workspace into step 2 and derive every
   syntax-result field, including stage failures and partial counts.
4. Close the actual `extract_syntax` function call and run its source,
   execution, failure, and dependency audits.

The entry audit found two restrictions: an existential, unconstrained write
set in `EndToEnd.checkedBody_executes`, and a requirement that
`records.length = 3 * capacity`. The first did not establish preservation
of later pipeline buffers; the second did not cover the source's actual
`raw_length / 3` argument for arbitrary word lengths.

Step 3.1 progress: the capacity restriction is removed through the existing
model bounds, complete body proof, caller-coordinate calls, symbol linking,
and canonicalizer entry. The contract now requires
`3 * capacity ≤ records.length`. The canonicalizer separately requires
the actual backing length to fit i32; this no longer follows from the token
capacity bound when spare words are allowed.
`run_records_spare` proves that every word beyond the declared token
capacity survives every normal outcome. The affected call chain checked in
6.10 seconds (`lexer-spare-capacity-call.log`).

The frame proof reuses `ScanOne.Calls.framePreservingCallSoundness` and the
existing strong expression simulator. The token-result accessor and lexer-result
constructor proofs now retain caller preservation; their ordinary contracts
derive from those stronger proofs. `LexInto.Calls.framePreservingCallSoundness`
combines the actual helper registry. Its affected dependency build passed in
26.79 seconds (`lexer-helper-registry-frame.log`).

The generic action-free simulator could not cover the lexer's three array stores,
so `FunctionalView/Stateful/` now supplies the corresponding resource-framed
rules. `Footprint.lean` proves logical resource membership is invariant.
`ActionFrame.lean` uses the existing expression and slice-store proofs to
bound an actual store's writes by its owned resources. `Frame.lean` carries
that bound plus fresh local cells through the complete command, including
scopes, loops, and early returns. No lexer algorithm was reimplemented.
These generic theorems depend only on standard Lean axioms.

`RawLexer/LexInto/Frame.body_executes` applies the new rule to the existing
complete logical lexer execution and its exact source reification. It removes
the source buffer from the write set using the preserved source contents.
`Frame.call_executes` then derives parameter bindings from ordinary caller
storage, executes the actual call, and hides fresh writes on return. It returns
the exact raw-token prefix and an output-only `CellEffect`; no callee
representation or presumed preservation is a caller premise. The call check
passed in 1.61 seconds (`lexer-framed-call.log`).

The frame now reaches arbitrary caller addresses and the actual linked program.
`Caller.body_executes_at` retains the output-cell/fresh-local footprint through
the existing bounded cell permutation. `Caller.callee_executes` constructs the
parameter state from ordinary owned source/raw buffers. `Caller.call_evaluates_at`
closes the call with an output-only `CellEffect`; it no longer requires a callee
representation. This checked in 2.04 seconds (`lexer-caller-frame.log`).
`Linked.call_evaluates_at` transports the body, then attaches the actual linked
argument evaluation. Its inverse type map handles arbitrary unrelated tagged
caller values internally. The caller supplies neither a model-coordinate state
nor relocated argument expressions. This checked in 1.76 seconds
(`lexer-linked-frame.log`). The two unused, weaker linked-call variants were
removed; their audit sites now use this contract.

`Frontend.lex_then_count` executes the linked lexer and the checked current-source
`lex_token_count` accessor in their two actual local scopes. It derives both local
values, exact emitted buffers, preservation of unrelated storage and slice/scalar
locals, and the output-only effect after scope restoration. Its continuation is
the remaining source body, not an assumed lexer or accessor execution. The proof
checked in 1.84 seconds (`lexer-count-prefix.log`).

`BufferCopy.copy_emitted_then_canonicalize` constructs the copy memory and loop
entry from that emitted-prefix format and ordinary caller resources. It derives
the contiguous word selection and fresh cursor, invokes the existing complete
copy/canonicalizer proof, and retains source/raw buffers plus the exact compacted
canonical buffer. It checked in 1.69 seconds (`lexer-copy-entry.log`) and uses only
standard Lean axioms. Destination capacity need only fit emitted words; unused
raw capacity is neither copied nor interpreted as tokens.

That guarded composition is now checked, as described below. Step 3.1 is complete
on the successful-lexing/sufficient-canonical-storage domain. The whole frontend
step remains open. Early-return classification stays in step 3.3, and closing the
outer input guards/function call stays in step 3.4.

`Frontend/Source.lean` authenticates the exact nested lexer/count bindings and
`raw_length / 3` argument. The current-source checker now checks the accessor,
parameter identities, and the source/raw/count connection to the copy scope.
Four focused matcher tests reject a different accessor input, a shadowed result,
and a wrong divisor, while accepting the correct shape. The combined proof,
boundary-test, source-checker build, and axiom audit passed in 3.01 seconds
(`lexer-copy-source-audit.log`). The concrete lexer and prefix proofs still inherit
legacy native assumptions; no new native decision or correctness axiom was added.
The expanded check of the current self-embedding passed in 21.71 seconds
(`lexer-copy-current-source.log`), including the new lexer/count/copy wiring and
the existing frontend and tree source links. No Lanius source changed. These
remain focused incremental checks, not a whole-extractor verification benchmark.

Step 3.1 closing connection: `Frontend.lex_to_canonical` executes the contiguous
source prefix from the actual `lex_into` arguments through the `token_count`
binding. It derives `raw_length / 3`, the lexer call, result-count accessor,
status accessor and comparison, canonical-capacity division/comparison, raw-word
copy loop, and complete canonicalizer call. Its only continuation premise is
execution of the later source body after canonicalization. It requires no assumed
intermediate call, guard result, loop invariant, or correct output.

The result includes exact raw and canonical counts; preserved source and raw
buffers; the compacted canonical buffer with its unused suffix; preserved
slice/scalar parameter locals for subsequent stages; and a `CellEffect` confined
to raw/canonical storage after closing the lexical scopes. The reusable
`CellEffect.transScoped` rule composes that frame across live local scopes.
`lex_then_count` now returns the exact restored state, not an existential state
with only a cells/locals comparison.

External assumptions are explicit: checked function/source links and accessors,
a bijective type relocation, the checked canonicalizer and zero success constant,
a well-formed caller, separate source/raw/canonical buffers, parameter values
matching actual storage lengths, signed-i32 bounds, logical lexer completion, and
enough canonical words for the emitted triples. This is a success-path contract,
not a claim that every source or capacity succeeds. The failure branches remain
unchanged in the authenticated source and still need their classified-return
proofs in step 3.3. The eight outer input guards are outside this prefix.

`Frontend/Guards.lean` proves the capacity expression for both Boolean outcomes,
then proves the two successful guards with an empty caller-cell frame.
`Frontend/Source.lean` authenticates the entire contiguous prefix, including
guard order, exact parameter/local identities, empty success branches, copy
strides, and canonicalizer arguments. Global function/type IDs come from checked
source linking. Failure branches and the later continuation are retained verbatim.

The complete connection checked in 1.97 seconds
(`frontend-canonicalize-check.log`). Ten direct Core guard evaluations cover zero
counts, zero capacity, one word short, exact fits, one/two spare words, and both
sides of the largest signed-i32 word capacity. Matcher regressions reject the
wrong count, wrong capacity, reordered guards, and a side effect in a success
branch. The full equality-based matcher is exercised as compiled regression code,
not a native correctness axiom. The axiom audit shows only standard axioms for
the guards and no axioms for `transScoped`; the full connection inherits existing
lexer native assumptions. No new native decision, correctness axiom, or Lanius
source change was introduced.

The expanded current-self-embedding check passed in 20.73 seconds
(`frontend-canonicalize-source.log`). It checks this complete source sequence,
both lexer result accessors, the success constant, and the canonicalizer's
keyword/trivia/kind/compaction proofs, alongside the existing parser/tree links.
These are focused incremental timings, not full-extractor verification timings.
The final regression and dependency audit passed in 2.43 seconds
(`frontend-canonicalize-audit.log`), with no proof placeholders in the audited
dependencies. The earlier failed regression builds were test-elaboration issues
(kernel reduction of the proof-producing matcher, then an unspecified test IO
type); the compiled matcher checks and direct Core capacity checks now pass.

Step 3.2 complete: `Frontend.lex_to_recognize` joins the preceding theorem to
the kind-capacity guard, kind-copy loop, actual six-local recognizer call, and
`parsed` binding. Its only execution premise is the later tree/result tail.
It derives the intermediate canonical/kind contents and callee resources; it
does not require a caller-provided loop invariant, recognizer execution, or
successful parse. Logical lexer completion and sufficient canonical/kind storage
remain explicit input-domain conditions. Parser rejection and workspace exhaustion
remain represented by the returned semantic outcome.

`ParserRecognize.recognize_region_at` executes the linked recognizer from the
caller's actual locals and buffers, constructing the inverse symbol coordinates
and parameter resources internally. It retains the outcome, its agreement with
the final logical workspace, workspace growth, exact physical encoding, and a
workspace-only write footprint. `Frontend.canonical_to_recognize` supplies those
inputs from the actual copy result, preserving physical kind capacity separately
from logical token count. The kind guard compares those counts directly; unlike
the canonical-storage guard, it does not divide by three.

The joined result retains raw/canonical counts, the bound parse result, unchanged
source bytes, exact raw/canonical/kind buffers and their unused suffixes, and the
final workspace artifact. Parameter locals remain available for tree construction.
The combined frame confines writes to raw, canonical, kind, and workspace storage
after closing the prefix's lexical scopes; other caller storage is preserved.
The caller still supplies checked module links/accessors/canonicalization helpers,
type permutations, a well-formed state, matching buffer lengths, required buffer
separation, signed-i32 bounds, an encoded well-formed grammar, and workspace layout
facts. No independent valid-root or semantic-workspace premise is introduced.

Source authentication now checks the recognition stage as the immediate
continuation of canonicalization, including exact local identities, capacity
guard, copy stride, six call arguments, and result binding/type. Failure bodies
and the later continuation are retained unchanged. The current self-embedding
passed this expanded check in 22.88 seconds (`frontend-recognition-source.log`).
No Lanius source changed.

Verification: the linked caller theorem checked in 2.17 seconds
(`recognizer-linked-caller.log`), the canonical-to-recognizer connection in 2.06
seconds (`frontend-recognize.log`), and the joined lexer-to-recognizer build in
3.86 seconds (`frontend-pipeline.log`). Nine direct Core evaluations cover zero,
short, exact, spare, and largest signed-i32 kind capacities. Matcher regressions
reject wrong counts/buffers, count shadowing, scalar parse results, triple-capacity
division, and intervening statements, and check that tails are retained.
The focused regressions and dependency audit passed in 3.09 seconds
(`frontend-recognition-audit.log`). The new guard uses only standard Lean axioms;
the full connection inherits the existing lexer/recognizer native decisions.
No new native decision, custom axiom, or proof placeholder was added. These are
incremental checks, not a whole-extractor verification benchmark.

Next active subtask: 3.3, derive the root from the retained recognizer outcome,
feed its workspace into the proved materializer, and derive syntax-result fields
and classified failures. The outer input guards and whole call remain in 3.4.

Step 3.3 progress: the complete post-recognizer tail now has checked execution
contracts for both parser outcomes. `CheckedAfterParse.accepted` derives the
selected root from `RecognizerInitialContinuationOutcome` and its retained
workspace agreement. It executes the real parse-status guard, constructs all nine
materializer arguments from caller locals, calls the proved materializer, binds
the returned tree, and executes the final syntax-result code. The materializer's
bounded-outcome contract covers success, output exhaustion, and depth exhaustion;
the caller does not assume successful tree construction or supply a valid root.

`CheckedFinish.execute` proves the actual stage assignment and seven-field
return in source order. A zero tree status produces extraction stage 0; a nonzero
tree status produces stage 5 while retaining the detail, raw/token counts, node
count, and used words. The returned error position is zero on this branch.
`CheckedResult.call` checks and executes the current seven-parameter constructor,
including field order. The fresh stage/tree locals are scoped out. Exact successful
tree records and offsets, or bounded partial-output counters on failure, survive
result construction through `TreeRuntime.Result.preserved`. Writes remain confined
to the two tree output buffers, and the recognizer workspace remains unchanged.

`CheckedAfterParse.rejected_outcome` derives the parser's result shape and failure
fields from that same retained semantic outcome. Parser rejection or workspace
exhaustion returns extraction stage 4, parser detail 1 or 2, the actual error
position, the existing raw/token counts, and zero tree counts. It executes the
actual guard, repeated status accessor, error-position accessor, and constructor.
This branch requires no tree/workspace storage assumptions and has an empty
caller-cell write footprint. The underlying `reject` theorem also supports any
nonzero parser status with the stated concrete result shape.

The source checker now authenticates the entire post-recognizer tail, including
the parser failure fields, all materializer arguments, tree-result binding, stage
assignment, three tree accessors, and exact result constructor. The current
self-embedding passed in 21.81 seconds (`frontend-tree-source.log`). Negative
checks reject a materializer call using raw count instead of canonical token
count, and a tree-failure assignment using the extraction-success constant.
No Lanius source changed.

Focused Core executions cover tree statuses 0, 2, 3, 1, and -1 with distinct raw,
token, node, and word counts. They check the entire returned value, restored
shadowed locals, and unchanged unrelated array storage; traps or exhausted runs
fail the test. The final execution/dependency audit passed in 2.85 seconds
(`frontend-tree-final-audit.log`). All new tail theorems use only `propext`,
`Classical.choice`, and `Quot.sound`; result preservation uses only `propext`.
No new native decision, custom axiom, or proof placeholder was added. This does
not remove the native assumptions inherited by the earlier lexer/recognizer call.

Step 3.3 composition checked: `Frontend.lex_to_syntax` now joins
`lex_to_recognize` to both post-parser branches. It starts with source bytes,
grammar and buffer resources, and executes the contiguous source from the lexer
invocation through the actual `SyntaxResult` return. There is no continuation,
intermediate-execution, assumed parse result, or independently valid tree premise.
The existing semantic lexer-completion and sufficient canonical/kind-storage
conditions define this theorem's domain; parser rejection, parser workspace
exhaustion, and tree output/depth exhaustion are all included.

The proof derives the nine materializer arguments from preserved caller locals.
It derives equality between the original and final workspace buffer lengths from
their shared layout, and derives untouched tree storage from the prefix frame.
The final contract retains the selected parser outcome/workspace, exact source,
raw/canonical/kind buffers, and the final tree-result contract. Parser failure
leaves both tree output arrays unchanged. Tree failure retains bounded partial
counts without authorizing a certificate. The combined frame permits writes only
to raw, canonical, kind, workspace, tree-record, and tree-offset buffers; all
prefix and result-construction locals are restored.

`syntaxPost.success` proves that observing extraction stage 0 yields the selected
complete-input parse and its exact serialized record/offset buffers, counts, and
unused suffixes. It rules out parser failure and partial tree output as successful
extraction. `syntax_source_sequence` composes the three adjacent checked regions
into the exact lexer-to-return statement inside the current `extract_syntax` body.
This is an occurrence proof, not execution of the outer input guards or public call.

Verification: the joined execution theorem first checked in 2.40 seconds
(`frontend-syntax.log`). The final focused execution/source-interface/dependency
audit passed in 4.50 seconds (`frontend-syntax-audit.log`), including the existing
return-tail regressions. The expanded current self-source check passed in 22.58
seconds (`frontend-syntax-source.log`) and constructed the joined source-occurrence
evidence. No Lanius source changed. The source-joining and success-projection
theorems use only standard Lean axioms. The complete execution theorem inherits
the previously recorded lexer/recognizer native decisions; no new native decision,
custom axiom, or proof placeholder was added. These timings are incremental checks,
not a whole-extractor or cold-build benchmark.

Step 3.3 complete on the stated caller domain: `Frontend.lex_to_return` now
executes the entire contiguous lexer-to-return statement without assuming lexer
success or sufficient canonical/kind capacity. `bodyPost` joins all early errors
with the existing parser/tree contract. The raw-token list is the logical
lexer's emitted prefix, not an assumed complete input parse. No intermediate
execution or continuation premise remains.

`CheckedEarly.lexer_failure`, `canonical_full`, and `kinds_full` execute each
actual guard and seven-field return with an empty caller-cell write set from
the guard point. `lex_to_early_failure` includes the actual lexer/count prefix,
classifies lexical errors versus raw-output exhaustion versus canonical-output
exhaustion, and retains the exact raw prefix and unused suffix. Only raw storage
may change. `lex_to_kinds_failure` includes successful lexing and canonicalization;
it retains both exact buffers and permits only raw/canonical writes. Neither
branch requires later destination storage to exist. The unified theorem accepts
the common caller resources needed by all branches but retains these narrower
failure footprints in its result.

`bodyPost.success` rules out every early failure, parser failure, and partial tree
output when the returned extraction stage is zero. It yields logical lexer
completion, the canonical count, the selected complete-input parse, and exact
tree record/offset contents, counts, and untouched suffixes. The combined frame
still permits only the six mutable frontend buffers and restores caller locals.

`checkEarly?` checks every early return field against the same checked result
constructor as the final tail and retains that constructor equality.
`syntax_source_all` joins those bodies to the adjacent current-source statement.
The expanded current self-source check passed in 21.22 seconds
(`frontend-body-source.log`), including rejection of interchanged canonical/kind
storage failure bodies. No Lanius source changed.

The final focused build passed in 2.61 seconds (`frontend-body-audit.log`). It
includes 43 early-boundary Core executions: lexical errors/raw-output exhaustion
without later locals, zero/exact/insufficient capacities, one/two spare canonical
words, unchanged pre-existing cells, and restored caller scopes. It also reruns
the five existing tree-return executions. Traps, exhausted runs, or missing
returns fail these tests. All three new guard-to-return proofs, source joining,
and the success projection use only standard Lean axioms. Prefix composition
and `lex_to_return` inherit the existing lexer/recognizer native decisions; no
new native decision, custom axiom, or proof placeholder was added. These are
incremental checks, not whole-extractor or cold-build timings.

Substep 3.4 was completed in this order:

1. Check the eight ordered negative-length guards and prove their exact early
   results and empty write set, including first-failing-guard precedence.
2. Derive their success from ordinary nonnegative lengths and compose them with
   `lex_to_return`, retaining the full result and branch-specific frames.
3. Check the public function signature/body, derive its 17 argument bindings,
   and close the actual `extract_syntax` call and caller scopes.

Step 3.4 and step 3 complete on the stated caller domain:
`CheckedSyntax.call_evaluates` proves the actual current `extract_syntax` call.
It derives all 17 parameter bindings from the evaluated argument values and
ordinary caller-owned buffers, passes the eight nonnegative-length guards,
executes `lex_to_return`, and restores the caller. `SyntaxData.Post.closeCall`
retains the selected parser/tree result, exact buffers and counts, and the
narrower early-failure write footprints through that scope restoration.
`bodyPost.success` remains the success projection used by downstream stages.

`SyntaxData.Valid` groups the existing size, grammar, workspace-layout and buffer
separation requirements; it adds no successful-execution or validator-acceptance
premise. `SyntaxData.Owns` describes the actual backing cells. `LinkedSyntax`
groups the static checked component links, symbol identities, and type inverses.
The call theorem derives its own callee state and local/resource predicates.
Argument-expression evaluation is the ordinary call-boundary premise, not a
premise that any frontend component ran correctly.

The separate `CheckedSyntax.reject_call` proves exact negative-length returns
from actual argument values, including first-failing-guard precedence. It needs
no buffer contents, encoded grammar, lexer/parser links, or later scalar values
beyond the first failure. It returns stage 1, the source's detail code, five zero
fields, and an empty caller-cell write footprint. Depth is deliberately not one
of these eight guards. The full computational caller domain still uses the
documented nonnegative depth/resource conditions.

`checkSyntax?` now checks the 17-parameter signature and the entire public body,
not an occurrence somewhere inside it. The current self-source check constructs
`LinkedSyntax` for that checked function and instantiates its public-call theorem
with the current lexer/canonicalizer/parser/reader links and inverse type maps.
It rejects reordered input guards and an extra leading statement, in addition
to the earlier failure-field and materializer-argument mutations.

Verification: `frontend-call-audit.log` passed in 3.11 seconds. It includes all
256 combinations of negative/nonnegative lengths at a real 17-argument Core call,
signed extremes, first-error precedence, absent buffer backings, and restored
caller locals/cells, plus the 48 earlier return/guard executions. The expanded
current self-source check passed in 20.65 seconds (`frontend-call-source.log`).
No Lanius source changed. The new guard and negative-input call proofs use only
standard Lean axioms; the complete computational call inherits the existing
lexer/recognizer native decisions. No new native decision, custom axiom, or proof
placeholder was added. These are incremental proof/source checks, not a full
extractor or cold-build benchmark. The caller frame concerns logical cells,
locals, and the host world; it is not a separate raw-heap/view-identity theorem.

Step 4 is now active. Its first boundary is `semantic_tokens.collect`, consuming
the complete-input tree and exact arrays established here. The whole extractor's
encoding, `main`, failure/completeness composition, and trust cleanup remain open.

The joined theorem's caller domain requires checked source links, type relocation,
a well-formed caller, matching local/buffer lengths, the stated buffer separation,
an encoded well-formed grammar and workspace layout, and signed-i32 size/depth
bounds. These are ordinary caller resources, not assumed component executions.

Earlier frame verification: eight focused boundary tests cover one/two spare words, no complete
row, empty input, output exhaustion, and lexical-error precedence over zero
capacity. They and the call/audit targets passed. The final focused build also
checked the existing raw-lexer coverage consumer in 4.94 seconds
(`lexer-framed-call-audit.log`). The generic frame and spare-word proofs use
only standard axioms; the concrete lexer call still inherits the existing
frontend native decisions. No new native decision or correctness axiom was
added. No Lanius source or checked source shape changed, so the previous
current-source validation remains applicable. These are incremental checks,
not an end-to-end extractor timing.

Exit: one current-source `extract_syntax` call theorem consumes source bytes,
an encoded well-formed grammar, and caller resources, and returns the exact
raw tokens, canonical tokens, and valid materialized tree. It identifies
stage failures and their permitted partial outputs. No separate intermediate
execution premise remains. This is the frontend pipeline completion point.

### 4. Extracted unit to compact encoding

Sources: `semantic_tokens.lani`, `compact_artifact_output.lani`, and the
called `output.lani` helpers. `semantic_tokens.emit` and older Surface/text
exporters are not called by the current `main`; do not prove unused exporters.

First prove `semantic_tokens.collect`: lattice positions, split tokens,
assignments, and child traversal agree with step 3's tree. Then prove the
actual hexadecimal writers and `emit_unit`, including paths, source bytes,
raw/canonical tokens, semantic assignments, and nodes in decoder order.

Reuse the compact decoder/checker specifications. Byte packing for stdout is
already proved, but it does not prove these certificate fields are correct.

Ordered subtasks:

1. Derive the collector's logical record and assignment contract from the same
   selected parse returned by step 3. Retain semantic token kinds in physical
   child triples, cursor spans, postorder references, and unique assignment slots.
2. Check the complete current `collect` body and prove its public call. Derive
   its loop invariants from 4.1 and ordinary caller storage; prove initialization,
   record traversal, assignment stores, final validation, return codes, and frame
   preservation. No assumed successful collector execution may remain.
3. Prove the called hexadecimal writers and complete `emit_unit` execution.
   Derive exact decoding and syntax acceptance, including semantic terminal
   advancement, node productions, origins, spans, and output-capacity failures.

Step 4.1 checked: `SemanticTokens/Records.lean::selected_collection_records`
constructs the logical collector input contract from `MaterializedParse` and
the grammar's 32768-kind encoding bound. It retains the exact tree, not a
separately accepted certificate. The theorem provides:

- One or two semantic uses per physical token, with assignment addresses
  determined by lattice position. Whole uses of the physical split-token kind
  remain distinct from pairs of virtual terminal uses.
- A source-order scan whose permutation is the materialized records' postorder
  terminal walk. Every assignment slot is unique; reordered traversal gives
  the same complete two-word assignment vector and checker-valid packed codes.
- Exact record words, offsets, child kinds, and cursor bounds.
  `tree_visit_child_lookup` proves that each state child points to an earlier
  stored record with the exact start/end span. Empty nodes remain covered.

The earlier `ParserTreeLayout.RecordAt` interface deliberately erases semantic
kinds through `ParseChild`. The new traversal/storage proofs read the stronger
`treeFrom` word layout already returned by step 3. They do not change that
layout, add a second exporter, or assume the erased information. This proof
view is in Lean; no Lanius, Rust, Python, or executable output format changed.

The combined record contract checked in 2.45 seconds
(`semantic-collection-records.log`). The focused tests and axiom audit passed
in 4.53 seconds (`semantic-records-audit.log`). They cover split-half postorder
visitation, whole split tokens, packed-kind boundaries, missing assignments,
and nonzero node/word bases. The audited new results use only `propext`,
`Classical.choice`, and `Quot.sound`; no new native proof assumption was added.

The actual current-source collector also passed 14 Core executions covering
capacity boundaries, malformed token kinds, exact output and untouched suffixes,
input preservation, and restored caller locals. This ran with the existing
full frontend source-link check in 21.82 seconds
(`semantic-collector-source.log`). These executions are tests, not a general
collector theorem. Subsequent changes were proof-only; that source check was
not repeated for each lemma.

Step 4.2 progress: `SemanticTokens/Collect/Source.lean::checkCollect?` now
authenticates the complete current function: ten parameters, every guard,
both child branches, all three loops, final return, and the values of both
child-tag constants. It recovers the global tags from a candidate child body
but requires proof-producing equality with the entire function afterward.
A matching fragment cannot establish the function contract. The source check
exposed and corrected a proof-model mistake about local-ID reuse in branches;
the Lanius source did not change.

`Collect/Initialize.lean::initialize_loop` proves termination of the actual
initialization loop. It fills exactly `2 * token_count` words with `-1`, retains
the spare suffix, and confines writes to the output and cursor cells.
`InitializeEntry.execute` constructs its invariant from caller storage and
derives fresh-cursor separation. `InitializeEntry.continue` composes the real
cursor declaration, initialization, and a continuation, closing the cursor
scope and hiding fresh cursor writes. The continuation still needs its own
execution proof; this is not the full collector call.

`Collect/Guards.lean` proves complete-body rejection before array access for
invalid initial scalar inputs, negative assignment capacity, and insufficient
nonnegative capacity. The public rejection lemmas take scalar values and
numeric conditions, not an assumed guard execution. Grammar/record validation
failures and the function-call wrapper remain separate obligations.

Verification: the complete current-source check and the 14 real collector
executions passed in 22.43 seconds (`semantic-collect-whole-source.log`). The
initialization entry proof checked in 1.64 seconds. The final focused tests
and axiom audit passed in 1.85 seconds (`semantic-collect-entry-audit.log`),
with dependencies cached. Tests cover missing/duplicated/changed function
bodies, child-fragment rejection, scalar guard boundaries with no array locals
present, and 12 initialization cases with empty/exact/spare output capacity and
caller-scope restoration. All new audited proofs use only standard Lean axioms.

Further 4.2 progress: `Collect/Grammar.lean::GrammarData.setup` derives both
grammar header reads, the canonical-table access, and the passing grammar
guard from `EncodesGrammar`, well-formedness, and the existing bounds. Its
continuation retains the exact entered state, so later composition does not
lose unrelated caller resources. `Collect/Record.lean` derives exact header
and child-triple reads from the materializer's stored words, preserving the
distinction between meaningful input and spare physical capacity.

Both child branches now have execution proofs:

- `Collect/NodeChild.lean::node_child_execute` consumes `CollectionRecords`.
  It derives the earlier-node reference and exact nested span, passes every
  guard in the state-child branch, updates only the cursor, and closes its
  temporary scope. Empty spans are included.
- `Collect/TokenChild.lean::token_child_execute` reads the stored semantic
  kind, derives the token/cursor/kind checks from `Use.Valid`, loads the raw
  and canonical kinds, computes the assignment address, writes that slot,
  advances to the parser's recorded finish position, and closes all four
  temporary scopes. `TokenAdvance` covers ordinary tokens, whole split-token
  uses, and both virtual halves. `TokenStore` proves the exact buffer update
  and preservation of every other output word.

These are branch execution proofs, not yet the complete child loop or public
collector call. The token branch still takes the loop's unused-slot fact;
the enclosing loop must derive it from 4.1's uniqueness and its visited-prefix
invariant. Ordinary entry resources, local values, buffer bounds, and output
separation remain explicit. No branch-execution or passing-guard premise is
introduced. The public collector theorem must construct these resources.

Verification: the complete token-branch proof checked in 2.03 seconds
(`semantic-collect-token-child.log`). The final focused test/axiom-audit build
passed in 5.30 seconds (`semantic-collect-child-audit.log`), including rebuilds
of the changed branch modules. Added tests exercise 16 token cases (all four
scan shapes, occupied-slot rejection, exact/spare output capacity, preservation
of the other slot, and restored temporary locals) and six nested-node cases
(empty/nonempty spans and spare record storage). Earlier initialization and
guard tests also passed. Every new audited theorem uses only `propext`,
`Classical.choice`, and `Quot.sound`. No source, emitter, output format, or
source-checker body changed; the earlier complete-source check remains the
source-link evidence and was not repeated for these local lemmas.

Further 4.2 progress: the child loop now composes both branches.
`Collect/Written.lean::written_available` proves that initialization and prior
stores leave each unvisited unique slot at `-1`. The exact buffer history
includes the physical suffix. `ChildMemory.lean` retains input slices, scalar
locals, output contents, and the two loop cursors across lexical bindings and
the bounded write footprint.

`ChildStep.lean::child_step` proves a complete iteration: slot and payload
bindings, nonnegative-payload check, tag dispatch, either checked branch,
child-index increment, and scope restoration. It derives the token branch's
unused-slot premise from uniqueness. `ChildLoop.lean::child_loop` proves
termination by the number of remaining children, including resumed loops and
zero remaining children. The recognized path determines each cursor position
and its final endpoint; no assumed iteration execution remains.

`RecordChildren.lean::record_children_execute` derives that path and uniqueness
from `CollectionRecords`, executes the complete child loop, checks the stored
record endpoint, and increments the outer node index. Its final buffer contains
exactly the writes from the next prefix of the same postorder record list.
It covers the current record body's suffix after the child-cursor declaration,
not yet the complete `nodeBody` or outer record loop.

Entry assumptions still to discharge: `ChildOwned` supplies the physical loop
resources, stable local bindings, and exact prior-record output history;
`ChildMemory` supplies cursor/input separation. The record entry proof must
construct these from caller storage and the fresh local declarations. The node
index's i32 increment bound remains explicit. Initialization already proves
the empty write history, but its resource effect still needs composition with
the record entry. No public collector-call theorem is claimed here.

Verification: the child-loop proof checked in 2.07 seconds
(`semantic-collect-child-loop.log`). The record-children proof and its changed
dependencies rebuilt in 6.08 seconds (`semantic-collect-record-children.log`).
The final focused tests and axiom audit passed in 2.82 seconds
(`semantic-collect-loops-audit.log`). Added tests cover 40 assignment-history
prefixes across four visitation orders and two capacities, plus 16 complete or
resumed record executions. They include the outer split half visited first,
ordinary/whole-split tokens, nested nodes, an empty record, zero remaining
children, spare input/output storage, exact endpoints and indices, and restored
temporary locals. All earlier collector tests passed too. Every new audited
result uses only standard Lean axioms. Lanius source and its complete-body
checker did not change; the earlier actual-source check remains applicable.

Further 4.2 progress: record setup and the entire outer loop are now proved.
`RecordSetup.lean::record_count_guard_pass` derives the actual child-count and
start-position guard from stored record bounds and the recognized span.
`NodeOwned.children` constructs `ChildMemory` and `ChildOwned` from the four
actual fresh declarations. It derives cursor/input separation and stable local
bindings; those are no longer separate premises for the complete record body.

`NodeStep.lean::node_step` proves the entire checked `nodeBody`, including the
offset lookup, both setup guards, child execution, outer index increment, and
closure of all four record scopes. Its caller-visible write footprint contains
only the assignment output and the outer node cursor. `NodeLoop.lean::node_loop`
proves termination of the entire postorder traversal and its exact final write
history, including resumed and already-complete traversals.

`NodeEntry.lean::NodeEntry.execute` derives the outer-loop invariant from
initialized caller storage and the source's fresh `node` declaration. The
caller supplies no record- or child-loop invariant, fresh-cell separation, or
successful iteration premise. The remaining ordinary entry assumptions are
explicit: the selected-tree contract from 4.1, grammar/input/output storage and
scalar values, input/output separation, i32/resource bounds, a well-formed
state, and the initialized assignment buffer. The node scope remains live for
the final-validation phase, just as in the source.

Verification: record setup checked in 2.19 seconds, the complete record body
in 1.72 seconds, the outer loop in 1.88 seconds, and the entry constructor in
1.81 seconds, with their dependencies cached. Logs are
`semantic-collect-record-setup.log`, `semantic-collect-node-step.log`,
`semantic-collect-node-loop.log`, and `semantic-collect-node-entry.log`.
The final focused tests and axiom audit passed in 2.65 seconds
(`semantic-collect-traversal-audit.log`). Six added whole/resumed outer-loop
executions cover the mixed split-token/nested-node tree and an empty record,
with exact/spare output capacity. Each also checks immediate termination after
the last node. Four scoped runs check restoration of the caller's outer cursor
and all other old cells except the output. Earlier collector tests still pass.
All new audited proofs use only standard Lean axioms. Lanius source and its
complete-body checker remain unchanged; this was not a new source-pack check
or a full-extractor timing measurement.

Further 4.2 progress: the entire collector body now has a success theorem.
`Collect/Assignments.lean::written_assignments` proves that the physical stores
produce exactly 4.1's two-word assignment vector plus the untouched output
suffix. It handles arbitrary record visitation order using unique lattice
positions; it does not assume the stored output is accepted. The selected-tree
constructor now retains the per-token validity evidence it already derived,
in `CollectionRecords.validAssignments`, alongside Boolean acceptance.

`Validation.lean::validation_checks` proves the actual whole-token and split-token
guard branches, including their grammar and token reads. `NodeOwned.assignments`
turns completed traversal storage into the validator's input resource.
`ValidationLoop.lean::validation_loop` proves termination of the complete final
loop, including resumed and already-complete states. It preserves every old
cell except its own cursor, so validation cannot change the assignment vector.

`Loops.lean::LoopEntry.execute` joins initialization, traversal, cursor reset,
validation, and the final zero return. Its caller supplies arbitrary output
contents, not an initialized buffer. The proof retains the input resources
through initialization, derives both traversal invariants and validation entry,
and hides both fresh cursors when closing their scopes. The only caller-visible
write is the exact assignment output.

`Body.lean::Entry.execute` includes both initial guards, both grammar metadata
reads, the grammar guard, all three loops, the return, and closure of every
local scope. `CheckedCollect.execute_body` transfers that result to the entire
function body selected by the existing proof-producing source checker. Its
domain is explicit: the selected-tree contract, encoded well-formed grammar,
input/output storage and scalar arguments, input/output separation, sufficient
output capacity, signed-i32 bounds, and a well-formed initial runtime state.
It requires no temporary-local values, loop invariant, successful computation,
or accepted stored-output premise.

Verification: the write-vector bridge and changed record contract checked in
3.70 seconds (`semantic-collect-assignments.log`). The final guard, loop,
three-loop composition, and whole-body checks each took under two seconds with
their dependencies cached (`semantic-collect-validation.log`,
`semantic-collect-validation-loop.log`, `semantic-collect-loops.log`, and
`semantic-collect-body.log`). The final focused tests and axiom audit passed in
3.73 seconds (`semantic-collect-body-audit.log`). New coverage includes every
resume point in valid assignment fixtures, deliberate negative/mismatched
assignments, whole uses of split-token kinds, paired split halves, validation
of actual traversal output, and whole-body execution from arbitrary output
contents. Exact/spare capacity, empty input, output suffixes, and restoration
of pre-existing temporary-local names are checked. All new audited theorems,
including the selected-tree constructor, use only standard Lean axioms.
These are incremental proof/test timings, not full-extractor benchmarks.
Lanius source and the full source checker did not change; the earlier
22.43-second self-source check was not rerun for these proof-only additions.

Step 4.2 checked: `Collect/Call.lean::CheckedCollect.call_evaluates` derives
the callee bindings from caller-owned buffers, executes the complete checked
function, returns the exact assignment vector, and restores caller locals.
Input slice capacities may exceed logical lengths. `short_capacity_call`
proves the public -2 result without accessing any buffer; even non-buffer
argument values are safe on that branch.

`SemanticTokens/Frontend.lean::frontend_result` retains the frontend's exact
selected tree and derives token, record, offset, and signed-i32 bounds from its
postcondition. `FrontendResult.collect` constructs the collector resources and
returns success or capacity rejection, with the exact output in either case.
It does not assume a successful collector run or independently accepted data.

`SemanticTokens/Pipeline.lean::frontend_then_collect` executes the current
frontend call first and supplies the collector call for its successful result.
It derives preserved grammar/output storage from the frontend's write footprint,
uses its returned counts, and composes both effects. Frontend failures remain
explicit. This joins public calls using value arguments; it is not yet a proof
of their surrounding `main` call sites.

Verification: public-call tests and their axiom audit passed in 3.30 seconds
(`semantic-collect-call-audit.log`). The frontend bridge and composition checked
in 2.06 and 1.95 seconds. The final handoff audit passed in 1.97 seconds
(`semantic-collect-pipeline-audit.log`): five new collector/handoff theorems use
only standard Lean axioms; the two-call theorem retains 463 existing
frontend-specific assumptions and adds none. A shared-dependency rebuild took
116.75 seconds, under the two-minute limit; these focused timings are not full
extractor benchmarks. The current-source runner instantiated the combined
theorem with both checked functions and reran 14 collector executions in
21.46 seconds (`semantic-collect-closing-source.log`).

Step 4.3 is active: prove the byte-append primitive and called hexadecimal
writers, then compose `emit_unit` and derive exact decoding and syntax
acceptance. Compact semantic-terminal advancement, origins/spans, the emitter,
and whole syntax acceptance remain open. Step 4 and milestone 3 are not complete.

Step 4.3 progress: the complete current-source `output.byte`, `hex_digit`, and
`hex_byte` calls are now proved. `CompactOutput/Byte.lean::CheckedByte.append`
establishes one exact element write; `reject` covers invalid positions,
exhausted capacity, and invalid bytes without accessing a buffer. Logical
capacity may be smaller than the physical allocation. `Append.lean` joins
the nested digit/append calls, retaining their real argument evaluation order
and fresh parameter allocation.

`CompactOutput/HexByte.lean::CheckedHexByte.write` derives both digit values
from the actual shift/mask expressions, executes both helper calls, and returns
the exact output and cursor. It covers zero, one, or two available slots,
including the retained first digit on partial-output failure and the sticky
-1 cursor. `CheckedHexByte.reject` proves invalid-value rejection even when the
output argument is not a buffer. The domain requires a well-formed runtime,
backing storage, and capacity within both the allocation and signed-i32 range;
it does not assume a nibble result, helper execution, or correct output.
Caller locals and all old cells except the output are preserved. These are
proofs of the existing Lanius functions, not another executable emitter.

Verification: `Tests/CompactOutput.lean` passed in 2.07 seconds with dependencies
cached (`compact-output-audit.log`). Its 1,424 calls cover all 256 bytes across
five capacity/position cases, the ASCII alphabet, byte-store boundaries,
invalid values without buffers, arbitrary initial output, spare storage, and
pre-existing caller local names. Shape mutations test guard removal and
substituted helper IDs. The enforced audit found only standard Lean axioms in
all ten new writer/arithmetic/composition theorems.

The current-source integration check passed in 22.07 seconds
(`compact-output-current-source.log`). It authenticated all three complete
functions and their helper IDs, instantiated the public `hex_byte` theorem,
ran the same 1,424 calls against the self-embedding's actual functions, and
rechecked the frontend/collector link. No Lanius source or output format changed.
These timings do not measure full extractor verification.

Further 4.3 progress: `CompactOutput/Word/Call.lean::Checked.write` now proves
the complete current `hex_u32` call for nonnegative signed-i32 values. It
includes the input guard, both local declarations, all eight iterations,
capacity-error returns, final cursor return, and scope restoration. `success`
proves an exact eight-character interval replacement with leading zeroes,
high-to-low digit order, and preserved prefix/suffix. `reject` proves negative
input rejection without output storage. The writer's name describes its
eight-digit wire field; its Lanius input remains a signed i32, not an arbitrary
unsigned 32-bit value.

`Word/Entry.lean` derives cursor/shift ownership and separation from the actual
declarations. `Word/Loop.lean` derives each iteration, including termination at
shift -4 without executing an invalid shift. The result preserves partial
output at every capacity cutoff. `CompactOutput/Buffer.lean::appendAll_success`
states exact interval replacement independently of loop execution and is
reusable by the remaining serializers. `Separation/LocalCall.lean` handles
assignment of an effectful call result while retaining its destination local;
putting it in a new shared module avoids rebuilding unrelated frontend proofs.
The existing local-store module was left unchanged.

Verification: the public word-call and exact-buffer proofs checked in 2.61
seconds (`compact-word-call.log`). The focused tests and enforced axiom audit
passed in 3.33 seconds (`compact-word-audit.log`): 2,249 calls compare against
the standard library's independent division-based hex formatting, covering
bit patterns, digit boundaries, leading zeroes, every output cutoff, sentinel
and extreme positions, rejection without buffers, and caller-state frames.
All nine audited new theorems use only standard Lean axioms.

The current-source check passed in 22.54 seconds
(`compact-word-current-source.log`). It authenticated the complete word writer
and both helper IDs, instantiated its public-call theorem, ran the same 2,249
calls against the actual self-embedding, and retained the earlier frontend,
collector, and byte-writer checks. No Lanius source or executable format changed.
These are scoped proof/integration timings, not full-extractor verification.

Further supporting work: `CompactOutput/Chunks.lean::appendAll_append` proves
that sequential chunks compose while retaining the first capacity failure.
`appendAll_hexByte` connects the two-call byte writer's output/cursor model to
that sequence model, including failure after either digit. These proofs cover
arbitrary initial buffers and integer cursors. Their enforced standard-axiom
audit passed in 1.74 seconds (`compact-chunks-audit.log`). These are composition
lemmas, not standalone execution proofs. No source or executable changed.

The byte-loop proof now includes `Bytes/Read.lean::read_write`, which derives
the actual indexed input read and `hex_byte` call, and
`Bytes/Step.lean::assign_byte`, which derives the effectful cursor assignment
while preserving the input (including spare storage) and loop counter. The
complete signature/body/helper checker is in `Bytes/Source.lean`. These two
theorems formed the starting point for the whole-call proof recorded below.

The focused byte tests and enforced axiom audit passed in 1.92 seconds
(`compact-bytes-audit.log`). They cover 416 executions with independent hex
formatting, empty input, logical lengths distinct from physical allocation,
every relevant capacity cutoff, negative/extreme cursors, and preserved caller
storage. Source-equality mutation checks reject missing guards, wrong helper
IDs, and extra effects. Both new execution theorems use standard axioms only.
The current-source integration passed in 24.64 seconds
(`compact-bytes-current-source.log`), authenticating the entire `bytes` function
and running the same 416 cases against the self-embedding. No Lanius source,
bootstrap executable, or wire format changed.

The complete byte serializer now has a public-call proof in
`Bytes/Call.lean::Checked.write`. `Bytes/State.lean` preserves the input prefix,
output storage, parameter bindings, and cursor/index ownership across each
iteration. `Bytes/Loop.lean::execute_loop` proves termination over the actual
remaining input suffix and exact partial output on capacity failure.
`Bytes/Entry.lean` derives the invariant from the real local declarations and
executes the length guard, loop, return, and scope closures. Callers supply
ordinary input/output storage and arguments, not loop execution or initialized
temporary locals.

The domain is a logical sequence of bytes below 256, with signed-i32 length and
capacity bounds and separate input/output storage. Physical input capacity may
exceed logical length. `Checked.success` proves exact interval replacement and
cursor advancement by twice the input length, preserving output prefix/suffix.
`Checked.reject` covers negative logical lengths without accessing buffers.
The general write contract also handles empty input and negative initial cursors.
Malformed byte values and aliased buffers are outside its stated input domain.

The focused suite and enforced eleven-theorem standard-axiom audit passed in
4.00 seconds (`compact-bytes-complete-audit.log`), including 418 executions and
source mutation checks. No Lanius source or executable changed. This closes the
byte-loop/public-call obligation on its stated domain, not all of step 4.3.
The current-source check passed in 22.49 seconds
(`compact-bytes-complete-source.log`): it authenticated the complete function
and helper identity, instantiated the public-call theorem for the current
self-embedding, and ran all 418 cases alongside the existing frontend checks.

Shared multi-field support now includes `Word/Assign.lean::assign_word`, which
derives the real word call and cursor assignment from caller expression
evaluations and storage. `Word/Chunks.lean::appendAll_following_word` proves
that an unconditionally executed later word preserves a previous capacity
failure and agrees with flat concatenation. This matches the delayed failure
checks in the token, assignment, and node serializers. The six-theorem enforced
standard-axiom audit passed in 1.66 seconds
(`compact-field-compose-audit.log`); these are shared prerequisites, not proofs
of those enclosing serializers. No source/link boundary changed, so this
focused proof check did not repeat self-extraction or frontend integration.

Assignment field support now proves the real validity guard and `second + 1`
expression in `Assignments/Fields.lean`, including the absent-field sentinel
`-1 → 0`. The upper bound is strict: the guard alone permits signed-i32 maximum,
whose increment would overflow. `Assignments/Domain.lean::field_bounds` derives
the required bound from the collector's `Assignment.Valid` contract and the
existing grammar kind bound of 32,768. `stored_fields` links the two values to
the collector's actual word representation. The four-theorem standard-axiom
audit passed in 2.30 seconds (`compact-assignment-domain.log`). These results
do not alone prove input indexing, the two writes, or the enclosing assignment
loop; they establish its arithmetic/domain handoff without adding an unchecked
no-overflow premise. No Lanius source or executable changed.

`Assignments/Write.lean::write_fields` now derives both consecutive word calls
and assignments to `next`, including the real second-field increment. It
preserves the required parameter locals across the first call and proves exact
combined cursor/output by the flat two-field encoding. The second call still
executes when the first runs out of capacity; its sentinel behavior preserves
that partial result. `Assignments/Source.lean` describes the complete six-argument
function, both indexed reads, guards, loop, and helper identity for source
authentication. Input-index execution, local scope composition, and the whole
loop/public-call proof remain open. The five-theorem standard-axiom audit passed
in 2.38 seconds (`compact-assignment-write-audit.log`).
The current-source integration passed in 23.06 seconds
(`compact-assignment-source.log`), authenticating the complete assignment
serializer's signature/body/helper identity alongside the existing checks.
This authenticates the source model; it does not close the remaining execution
proofs of its input reads and enclosing loop. No Lanius source changed.

`Assignments/Read.lean::stored_pair` now links each indexed pair to the
collector's flattened `Assignment.words` list. `read_pair` proves the actual
multiply/add index expressions and both buffer reads, with signed-i32 address
bounds and arbitrary spare capacity. `initialize_fields` places the second read
after the first local declaration, derives both resulting locals and state
well-formedness, and preserves the same input prefix through both bindings.
The expanded eight-theorem standard-axiom audit passed in 2.50 seconds
(`compact-assignment-read-audit.log`). Iteration composition, field-scope
closure, loop termination, and the public-call theorem remain open. No source
or helper identity changed; the existing source authentication still applies.

`Assignments/Scope.lean::Entry.write` now derives field-local separation,
parameter preservation, the validation guard, and both writes from resources
before the declarations. `Assignments/Failure.lean::Entry.failure` executes the
complete actual iteration when its computed output outcome is full: both
indexed reads, declarations, validation, writes, early return, and scope
closures. It preserves exact partial output, changes only output/cursor cells,
and does not execute the token increment. No iteration execution is assumed.
The ten-theorem standard-axiom audit passed in 1.57 seconds
(`compact-assignment-scope-audit.log`). The successful iteration, loop invariant,
termination, and public call remain open. No source/link identity changed.

`Assignments/Success.lean::Entry.success` now executes the complete successful
iteration on the valid-field domain, including both reads/declarations, the
field guard, both writes, the capacity check, safe counter increment, and scope
closures. Its postcondition retains ownership of the updated cursor and counter,
exact output, and a write set containing only those three cells. The successful
cursor's nonnegativity follows from the computed nonempty encoding, not an
extra caller assumption (`Outcome.lean::appendAll_done_nonnegative`). Together
with `Entry.failure`, both iteration branches are proved. The twelve-theorem
standard-axiom audit passed in 1.68 seconds
(`compact-assignment-iteration-audit.log`). The loop invariant, termination, and
public call still need composition; neither iteration theorem assumes a loop
execution. No Lanius source or source-link identity changed.

`Assignments/State.lean` now supplies the loop invariant and its preservation,
including unchanged logical input and spare capacity, stable parameters,
output length, and cursor/index ownership. `Assignments/Loop.lean::execute_loop`
executes the complete actual loop over the remaining input suffix. It proves
termination, exact flat assignment encoding or exact partial output on capacity
failure, and an exhausted input counter on normal completion. It derives each
iteration from the prior proofs; no loop run or successful output is assumed.
The fifteen-theorem standard-axiom audit passed in 1.65 seconds
(`compact-assignment-loop-audit.log`). The outer function's entry guard, initial
local bindings, final return, and public-call composition remain open. No Lanius
source or helper identity changed.

`Assignments/Guard.lean::entry_guard` now evaluates the actual signed division
and complete entry condition for nonnegative counts/lengths. Its pass/reject
corollaries handle both even lengths and spare trailing words, deriving the
Boolean result from `2 * count ≤ length` or its strict failure. The public
`Assignments/Reject.lean::Checked.short_input` theorem executes the full early
rejection call with arbitrary buffer values, proving no buffer access or
iteration-local allocation and an empty write effect. The nineteen-theorem
standard-axiom audit passed in 3.46 seconds
(`compact-assignment-guard-audit.log`). Normal-entry initialization, final return,
and the general public write contract remain open. No source/link identity changed.

`Assignments/Function.lean::Entry.invariant` now derives the initial loop
resources and fresh-cell separation from the actual declarations.
`Entry.execute` composes the entry guard, both initial locals, complete loop,
final return, and scope closures. `Assignments/Call.lean::Checked.write` exposes
the complete public function with ordinary arguments and backing storage,
proving exact flat encoding (or partial capacity-error output) and an
output-only effect after caller-local restoration. The declared logical input
length and physical allocation are separate; spare input storage is preserved.
The contract's field bounds follow from collector validity as recorded above.
Malformed fields and aliased input/output remain outside this write domain;
the separate public short-input rejection theorem requires no buffer storage.

The focused suite and twenty-two-theorem standard-axiom audit passed in 3.52
seconds (`compact-assignment-complete-audit.log`). Its 840 executions use
independent standard-library fixed-width formatting and cover empty input,
present/absent second fields, odd spare allocation, every output cutoff,
negative/extreme cursors, and caller/input frames. This closes the assignment
serializer's public write proof on its stated domain. No Lanius source changed.
The current-source integration passed in 24.78 seconds
(`compact-assignment-complete-source.log`), authenticating the complete function
and helper identity, instantiating the public write theorem, and running all
840 cases against the self-embedding alongside the earlier frontend checks.

Token serializer work now reuses the frontend's existing `encodeTokens` and
`encoded_row` layout instead of introducing another token representation.
`Tokens/Read.lean::row_index` proves the actual signed `token * 3` expression;
`read_row` proves the actual kind/start/finish index expressions and values,
including arithmetic bounds and independence from arbitrary spare input words.
The two-theorem standard-axiom audit passed in 2.56 seconds
(`compact-token-read-audit.log`). These are read contracts, not a whole token
serializer proof: field validation, lexical declarations, three writes, the
loop, and public-call/source authentication remain to be composed. No Lanius
source changed.

The token field guard now has a standard-axiom proof for ordered spans within
the source, using the actual indexed kind read and local span values
(`Tokens/Fields.lean::fields_valid`). The focused three-theorem audit passed
in 2.53 seconds (`compact-token-fields-audit.log`).
`Tokens/Source.lean` now checks the complete function signature, body, and word
helper identity. The updated audit built in 2.69 seconds; current-source
integration passed in 25.66 seconds (`compact-token-source-link.log`).
This authenticates the token function against the self-embedding, but does not
yet prove its declarations, three writes, loop, or public-call execution.
No Lanius source changed.

The token serializer's complete public write proof is now checked:
`Tokens/Call.lean::Checked.write`. It derives the initial locals, guarded
iteration, exact three-word encoding per token, capacity failure, final return,
and caller restoration. The domain requires ordered spans within an i32-sized
source, representable kind codes, sufficient input prefix, and separate input
and output buffers. Negative cursors and partial output remain covered;
malformed token rejection is not claimed by this write theorem.
The seventeen-theorem standard-axiom audit passed in 3.09 seconds
(`compact-token-call-audit.log`). Current-source integration instantiated the
public theorem against the complete self-embedded function and helper identity
in 24.16 seconds (`compact-token-public-source.log`). This run reuses the
existing execution suites; a token-specific differential execution suite has
not yet been added. No Lanius source changed.

The node serializer's complete public write proof is now checked:
`Nodes/Call.lean::Checked.write`. It derives offset lookup, record/header
declarations and guards, all four header writes, the nested child traversal,
node advancement, capacity failure, final return, and caller restoration.
It reuses the parser's `RecordVisit.Stored` layout and `ChildVisit.Linked`
relations. The domain requires representable nonnegative header fields,
backward node references, bounded token references, sufficient input prefixes,
and an output buffer separate from both input buffers. Negative initial cursors,
empty record lists, spare input capacity, and exact partial output are covered.
The write theorem does not claim rejection of arbitrary malformed records.

The enforced 42-declaration standard-axiom audit passed in 3.39 seconds
(`compact-node-call-audit.log`). Current-source integration passed in
24.79 seconds (`compact-node-public-source.log`), instantiating the public
theorem with the complete self-embedded function, word helper, and checked
child-tag constants. This run reuses the existing execution suites; a
node-specific differential execution suite has not yet been added. No Lanius
source, executable, or output format changed. These are component checks, not
whole-extractor verification timings; inherited frontend trust obligations
remain open.

The pack header's complete public call is now proved by
`CompactOutput/PackHeader.lean::Checked.write`: it emits version 1 and the unit
count, including exact partial-output behavior. Its standard-axiom audit passed
in 2.46 seconds (`compact-pack-header-audit.log`); current-source integration
passed in 25.19 seconds (`compact-pack-header-source.log`).

For `emit_unit`, the complete source sequence and all five helper identities
are checked. `Unit/Word`, `Bytes`, `Tokens`, `Semantic`, and `Nodes` prove the
actual calls (and cursor assignments where present), preserving the other
inputs through the shared `Unit.Memory` frame. `Unit/Entry.initialize_cursor`
now executes the initial path-length word call using the incoming position,
allocates the fresh cursor, and derives that frame while preserving all other
parameters and separate input arrays. No intermediate serializer execution is
assumed by this initializer theorem. The expanded 14-declaration standard-axiom
audit passed in 2.54 seconds (`compact-unit-entry-audit.log`).

The full `emit_unit` composition is now proved. `Unit/Inputs.lean` packages
logical data, storage, scalar bounds, and reference validity without execution
premises. `Inputs.execute_tail` derives the ten calls after cursor allocation
in their actual source order, preserving exact output through capacity failure
and empty serializers. `Inputs.execute` includes the entry guard, first word
call, cursor allocation, full sequence, return, and local-scope closure.
`Unit/Call.lean::Checked.write` lifts this to the checked public call, given
evaluated arguments, their parameter binding, and the input contract in that
bound state. No intermediate call or whole-body execution is assumed.

The domain requires valid byte/token/assignment/node inputs, a nonempty node
list, and output storage separate from input buffers. Output capacity need not
suffice: the theorem gives the exact partial bytes and returned cursor.
It does not claim rejection of every malformed input or decoder acceptance.
The expanded 19-declaration standard-axiom audit passed in 2.51 seconds
(`compact-unit-call-audit.log`). This is a focused incremental component check,
not a full extractor verification time.
Current-source integration passed in 25.28 seconds
(`compact-unit-public-source.log`), checking the complete embedded `emit_unit`,
all five helper identities, and instantiating its public-call theorem. The run
reuses existing execution suites; no unit-specific differential suite was added.
No Lanius source, executable, or wire format changed.

The collector-to-emitter bridge now derives semantic and node input contracts
in `Unit/Collection.lean`. `CollectionRecords.semanticInput` uses the collector's
exact written array, derives assignment length and field bounds from semantic
validity, and retains the unused capacity suffix. `CollectionRecords.nodeInput`
uses the selected parse and materialized arrays to derive production/span
bounds, reference validity, record counts, and storage bounds. Production IDs
are bounded by the recognized grammar; grammar storage establishes the i32
limit. `CollectionRecords.nonempty` derives the unit guard's positive node count
from recognition of the grammar's start nonterminal.

The internal collector result now retains `CollectionRecords`, not just an
assignment list. The pipeline continuation retains the corresponding
`FrontendResult`, returned-count relationships, and the collector-only write
effect as well as the combined frontend effect. This preserves the witnesses
and buffer facts needed for emission; internal callers were updated directly,
without a second compatibility interface. The focused bridge/pipeline audits
passed in 3.06 seconds (`compact-unit-collection-audit.log`). The unit audit now
covers 26 declarations with standard axioms only. The full frontend composition
still carries the same 463 inherited assumptions and adds none.
Current-source integration passed in 25.43 seconds
(`compact-collection-handoff-source.log`) with the strengthened pipeline result.
No source-language code, executable, or wire format changed.

`Unit/Lexical.lean` now derives the raw and canonical token field bounds from
the lexer and both canonicalization passes. Filtering and inclusive-range
retagging preserve byte spans; every token-kind code fits the wire field.
`lexical_storage` extracts the actual source/raw/canonical array prefixes from
successful frontend output. `lexical_storage_after_collection` preserves them
through the collector's separate output-only effect, without rescanning source
or treating spare capacity as logical tokens. `byteInput`, `rawInput`, and
`canonicalInput` construct the corresponding emitter contracts. Byte bounds
come from `Fin 256`, not an added range assumption.

The expanded 36-declaration standard-axiom audit passed in 2.91 seconds
(`compact-unit-lexical-audit.log`). No source, executable, or format changed;
the source-link check was not rerun for these input-contract-only proofs.

The full emitter argument handoff is now assembled in `Unit/Arguments.lean`.
`Emission.values` gives the actual 19-argument order, distinguishing logical
counts from physical capacities. `Storage.inputs` derives the complete bound
parameter state from caller storage and the selected frontend/collection
witnesses. `Storage.of_collection` supplies that storage from the frontend
postcondition and collector effect; `Storage.write` invokes the checked public
emitter without assuming a callee state or independent nonempty-node proof.
Its encoding names the exact path/source bytes, raw/canonical tokens,
assignments, and records retained by the pipeline.

`Unit/Pipeline.lean::collection_then_emit` consumes the proved collector
continuation and composes its real call with the emitter call. It derives the
emitter arguments, retains both executions, and proves exact output plus the
combined frontend/collector/emitter write footprint. The semantic buffer must
fit so collection succeeds; emission capacity may still be insufficient and
the exact partial-output result is retained. This is call composition, not yet
execution of the surrounding main/I/O statements.

The expanded 42-declaration standard-axiom audit passed in 2.97 seconds
(`compact-unit-pipeline-audit.log`). No new nonstandard assumptions were added.
Current-source integration passed in 24.11 seconds
(`compact-unit-pipeline-source.log`), instantiating the new composition with the
actual collector, emitter, and helper identities. No Lanius source, executable,
or format changed. These remain incremental component checks, not a new
whole-extractor timing.

Compact decoding proofs now target the actual reader implementation in
`CompactDecode/Reader.lean`. Its contents were moved out of
`CompactArtifact.lean`; a direct comparison confirmed the reader logic is
unchanged apart from declaration visibility. `CompactArtifact.lean` retains
the artifact/checker logic and public decoding entry point. No duplicate
decoder or compatibility shim was added.

`CompactDecode/Hex.lean` proves single-digit decoding, arbitrary base-16
accumulation, and exact inverses for the two-character byte and eight-character
word encodings, with precise cursor advancement. `CompactDecode/Fields.lean`
composes these into the actual token, semantic-kind, and child-reference
readers. The ten-theorem standard-axiom audit and 1,721 execution checks passed
in 11.94 seconds including newly built dependencies
(`compact-decoder-fields-audit.log`). The execution checks cover all byte
values, word boundaries, nonzero cursors, every field truncation, and several
malformed/empty public pack inputs. They are not a whole-pack inverse proof.
Current self-artifact/source integration passed after the move in 24.05 seconds
(`compact-decoder-reader-source.log`). Lanius code, executables, and wire format
remain unchanged; inherited frontend trust obligations remain open.

Further decoder progress: `CompactDecode/Repeat.lean` proves the actual
`readMany` loop and composition of element reads. `Bytes.lean` proves byte-array
decoding and derives remaining-buffer bounds from encoded bytes. `Nodes.lean`
proves child references, complete nodes, and arbitrary node lists, including
grammar lookup and exact cursor advancement. The node round trip derives its
buffer-space condition rather than requiring a separate premise. `Tokens.lean`
proves raw/canonical token lists and semantic-assignment lists, recovering
`Assignment.code` for both single and packed kinds. Field-range and grammar
conditions remain explicit; these theorems do not claim every record is valid.

The expanded 30-theorem standard-axiom audit and 2,296 execution checks passed
in 3.10 seconds (`compact-decoder-token-lists-audit.log`). Added cases cover
empty/repeated lists, node and semantic-kind boundaries, and every truncation
of the selected list fixtures. No runtime reader, Lanius source, executable,
or wire format changed. This is a focused incremental check, not whole-extractor
verification timing.

The decoder round trip now composes whole units and ordered packs.
`CompactDecode/Path.lean` proves byte-array reconstruction and UTF-8 path
recovery. `Artifact.lean` composes the actual field readers. `Unit.lean` derives
all their reads and bounds from one contiguous encoding, using the existing
field serializers' encodings. `Units.lean::readPack_encoding` composes these
units with the actual pack reader and proves exact end-of-input consumption.
Its explicit conditions are encodable fields, recognized productions, matching
token/assignment counts, nonempty node lists and pack, and an exact input end.
No successful field or unit execution is assumed by this round-trip theorem.
`Pack.lean` also proves wrong-version rejection and framing behavior for empty
packs and trailing bytes.

The 48-theorem standard-axiom audit and 2,818 execution cases passed in 2.85
seconds (`compact-decoder-full-pack-audit.log`). Cases include Unicode paths,
a nonempty artifact with all fields populated, ordered distinct sources,
truncations, wrong versions, and trailing bytes. These are decoder checks,
not syntax-validator acceptance checks or whole-extractor timings.

`CompactDecode/Emission.lean::emission_encoding` now identifies this unit
encoding with `CompactOutput.Unit.Emission.encoding`, the encoding in the
proved Lanius emitter call. The proof covers the two byte-hex representations
and the `Fin 256`/`UInt8` source representation. `emission_decode` applies the
unit round trip to that exact encoding. UTF-8 path-byte agreement and unit
encodability remain explicit premises. The expanded 47-theorem emitter/bridge
standard-axiom audit passed in 2.68 seconds
(`compact-emission-decoder-audit.log`).
Current self-artifact/source integration also passed in 24.11 seconds
(`compact-emission-decoder-source.log`); no runtime source or format changed.

Subsequent 4.3 progress: `CompactDecode/Contracts.lean` derives unit encodability
from frontend/collector storage and capacity bounds. `Buffer.lean` transports
the successful append buffer to `EncodedAt`; `Grammar.lean` derives production
lookups from the recognized tree under the shared-grammar identity. The remaining
byte-backing premise identifies the actual output bytes with the written buffer;
the packing/I/O caller must still supply it. Loaded grammar identity also remains
an explicit caller obligation.

`CompactDecode/Acceptance/Unit.lean::frontend_artifact_accepted` now proves
acceptance by the complete syntax checker. It composes successful frontend
lexing/canonicalization, exact byte/token decoding, semantic-kind acceptance,
every node's production/children/spans/backward references, and root acceptance.
Terminal advancement includes both halves of split tokens and accounts for
postorder collection. Grammar-child identities are derived from tree recognition
and preserved when sibling record arrays are concatenated. No token, node,
root, or whole-checker acceptance is assumed.

This theorem consumes the frontend postcondition, its zero status, the selected
parse/collection, shared parser/decoder grammar identity, and the semantic-kind
bound. It does not prove execution of `main` or native output I/O. The expanded
standard-axiom audit passed in 1.84 seconds
(`frontend-artifact-acceptance-audit.log`). These are incremental proof checks,
not a whole-extractor verification benchmark. Existing frontend trust cleanup
remains in step 6.

The current self-artifact/source-link integration passed in 26.86 seconds
(`frontend-artifact-acceptance-source.log`). It checks the existing source-linked
frontend/collector boundary; it is not an end-to-end instantiation of the new
acceptance theorem with native output bytes. No runtime source or wire format
changed in this work.

`CompactOutput/Unit/Pipeline.lean::collection_then_emit` now includes these
results in the actual collector/emitter call theorem. Its returned collection
determines both the written buffer and the accepted artifact. For a matching
UTF-8 path and shared grammar, it derives encodability and syntax acceptance;
for sufficient output room and bytes matching the written prefix, it derives
exact decoding and the ending cursor. No separate successful emitter execution
or accepted artifact is assumed. The strengthened theorem passed the
standard-axiom audit in 2.08 seconds (`certified-emission-audit.log`).

`CompactDecode/Packing.lean::packing_decode_unit` now connects the physical
packing input to exact unit decoding. It derives the byte-prefix equality from
the packing invariant and emitter buffer contents; it still requires the
packing invariant and the matching output count at that boundary.

Next within 4.3: instantiate that connection in the per-unit/whole-pack flow
and audit the capacity-error cases before closing the boundary. Step 4 and
milestone 3 remain open.

Exit: from step 3's result, `collect` and `emit_unit` produce exactly one unit's
encoding, preserve its inputs, and advance the output cursor by the exact
length. Derive decoding and syntax-validator acceptance from those results;
do not assume acceptance. Include record origin/span validity and capacity errors.

### 5. Ordered files to successful `main`

Sources: `extractor.lani`, `byte_io.lani`, and `host.lani`.
Reuse input chunk/read/unpacking proofs, output clear/packing proofs,
the constructive stdout-tail proof, and the host-call memory rules.

#### Output path: completed components and remaining composition

`OutputPacking/Complete.lean::prepare_and_write` now composes preparation and
the stdout tail into one execution theorem, returning zero and appending the
exact bytes. Its premises describe the entry buffers, registry, local reads,
separation, capacity, and host declaration. It derives both loop executions,
the packed workspace, preserved other arrays and pointer, both synchronization
operations, and the stdout call. No continuation execution is assumed.
The component audit passed in 1.78 seconds (`prepare-and-write-audit.log`).
This is an output-stage theorem, not yet a theorem about all of `main`.

The composition uses these proved components:

- `OutputPacking/Setup.lean::prepare_with_continuation` executes the exact
  `Preparation.statement`: word-count calculation, clear-cursor binding,
  clearing loop, pack-cursor binding, packing loop, and a supplied continuation
  inside those scopes. The continuation remains a premise, receiving the
  completed packing invariant and the loops' memory effects. The theorem now
  carries any continuation world postcondition through all scope restorations.
  The focused proof and axiom audit passed in 3.19 seconds
  (`target/verified-compiler/preparation-world-post-audit.log`).
- `OutputPacking/Stdout.lean::StdoutTail.executes` proves the complete output
  tail: explicit usize cast and binding, pointer/size argument reads,
  synchronization to the heap, stdout, synchronization back, return-count
  check, and return zero. It derives execution and exact world effects from
  pre-tail buffer, registry, local-read, separation, capacity, and host-function
  conditions. Neither synchronization success nor host-call success is a
  premise. This theorem covers root-array views, not arbitrary projections.
- `LoopInvariant.workspace_view` derives the workspace array's contents,
  length, and element types from completed packing and matching view metadata.
  `LoopInvariant.registered_arrays` combines that result with pre-loop arrays
  outside the write set. The caller still supplies the metadata and separation
  conditions and must connect the actual loops' effects.
- `Tests/Self.lean` checks the complete stdout-tail shape in the self-embedding,
  its shared output-length local, and its external stdout service. It
  instantiates the tail theorem for the recovered template; it does not
  discharge the theorem's runtime premises or prove the entire checked `main`.

The latest registry proof and dependency audit passed in 2.75 seconds
(`target/verified-compiler/registry-array-audit.log`). The latest self-source
integration passed in 19.35 seconds (`stdout-theorem-source-link.log`). These
are scoped checks, not timings or evidence for a completed milestone. The new
proof dependencies pass the standard-axiom audit; inherited frontend trust
obligations remain.

`Preparation.checked_stdout_statement` supplies exact equality between the
recovered preparation statement and the composed theorem's template. The self
test checks that equality and instantiates `prepare_and_write` for the checked
program. Runtime entry premises are still open.

Next: connect the output-stage entry resources and byte contents to the
ordered file loop, module framing, and decoding. The initial allocations and
view registrations must establish the registry metadata and separation; the
emission/file-loop proof must establish the output buffer and count.

Allocation support now has two explicit boundaries:

- `Semantics/I32Views/Allocation.lean::evaluatesAllocatedI32Slice_resources`
  constructs a primitive Core allocation and raw-slice mapping from a sufficient
  budget. It establishes full state validity, array storage, a registered view,
  preservation of existing view blocks, and the exact remaining budget.
- `Allocation/Execution.lean::executes` composes primitive allocations under
  one total budget and runs the continuation inside their lexical scopes.
  `Ready` retains each buffer's resources; its projections establish final
  state validity, validity of the whole view registry, and total budget use.

These primitive proofs do **not** yet cover the extractor's actual allocation
calls. Source inspection found that `main` calls the host `.alloc` service,
which synchronizes existing views in both directions and records a host event.
`CallContracts/Host.lean::evaluatesHostAllocation` proves that call boundary
with both synchronization results still explicit. `Allocation/Source.lean`
checks the exact nested host-call representation, allocator identity, byte
sizes, alignments, and element counts for all 13 buffers. It does not replace
the calls with primitive allocations.

The focused host-allocation proof, source matcher tests, and new theorem
dependency audit passed in 2.13 seconds (`allocation-host-audit.log`). The
18-file self-embedding source check passed in 20.36 seconds
(`allocation-source-link.log`), confirming the exact 13-buffer host-call
sequence and its 56,440,332-byte allocation total. This is a source-shape
check, not execution of those allocations or proof of their total success.

The single host initializer is now proved by
`Allocation/Host.lean::hostSlice_exists`. Given a well-formed state, sufficient
budget, valid root-view blocks, and readable i32 arrays of their declared
lengths, it constructs both synchronization passes, the host allocation, and
the raw-slice mapping. Its result includes readable new array storage, the
appended view, full state validity, preservation of existing view blocks,
unchanged local bindings, exact cell-counter growth, exact remaining budget,
and the one added allocation event. Neither synchronization success nor an
intermediate execution is assumed. `hostAllocation_exists` exposes the host
call separately, including its fresh zero-filled block. The new proofs and
dependency audit passed in 2.22 seconds (`host-slice-initializer-audit.log`).

The host sequence now composes in
`Allocation/Sequence.lean::hostSequence_executes`. `Registry` carries state
validity, valid backing blocks, distinct root views, and readable arrays of
the declared lengths. `Registry.allocate` and `Registry.bindLocal` establish
that invariant after every initializer and binding. `HostReady` retains the
new storage at each step and proves aggregate budget use, host events, and
cell-counter growth. No intermediate allocation or synchronization execution
is assumed. The continuation runs inside the scopes with those resources.

`checkAllocator?` recovers proof evidence for the actual allocator declaration,
including parameter binding; `CheckedAllocator.executes` connects it to the
recovered source sequence. The 18-file self-embedding integration passed in
20.26 seconds (`host-allocation-sequence-source-link.log`) with the actual
13-buffer sequence: 56,440,332 bytes, 13 allocation events, and 26 new cells.
The focused proof/dependency audit passed in 2.24 seconds
(`host-sequence-effects-audit.log`); new proofs use only standard Lean axioms.
The integration checks source linkage, not concrete execution of the buffers.

The argument entry now composes with these allocations in
`Entry/Arguments.lean::CheckedArguments.allocate`. It constructs the `argc`
call, binds the result, proves that the `<= 1` guard falls through for a
supported count, and derives the initial allocation registry. Its external
conditions are a well-formed initial state with no registered views, an
argument count between 2 and `2^31 - 1`, sufficient allocation budget, and a
specification for the post-allocation continuation. No initial allocation
registry or successful intermediate execution is assumed separately.

`checkArguments?` checks the exact start of `main` and the `argc` declaration.
The source integration now requires the exact allocation sequence immediately
after that guard; it no longer searches for the allocations elsewhere in the
body. The checked entry/allocation composition passed self-source integration
in 20.55 seconds (`argument-allocation-source-link.log`). Focused matcher
regressions and the proof-dependency audit passed in 2.08 seconds
(`argument-entry-regression-audit.log`), including rejection of a missing
callee and a guard that reads the wrong local.

Pointer support now includes `Allocation.Registry.evaluatesPointer`. For a
local that contains a registered slice, it constructs the actual
`i32SliceDataPtr` evaluation, proves the returned address is non-null, and
retains registry validity, cells, locals, view metadata, cell counter, budget,
and world. The only change is synchronization of heap bytes; it does not
allocate another block. `Registry.synchronize` establishes its synchronization
premise from the registry invariant. The focused proof/dependency audit passed
in 3.69 seconds (`non-null-pointer-audit.log`). This does not yet prove the
whole pointer-guard sequence.

The local-read premise is now derived by `Allocation.HostReady.buffer`:
each buffer remains readable through its binding after the entire allocation
sequence when the buffer names are distinct. The allocation contracts retain
preservation of existing cells outside registered array roots;
`HostReady.preserves_cell`, `preserves_binding`, and `preserves_local` lift
that fact through later allocations and local bindings. `HostReady.pointer`
then constructs the non-null pointer evaluation from allocation history,
without assuming its slice-local read. The source checker now produces
evidence that all allocation bindings are distinct, with positive and
duplicate-binding rejection tests. The focused proof/dependency audit passed
in 2.98 seconds (`allocated-buffer-pointer-audit.log`). Self-source integration
passed in 20.05 seconds (`allocated-buffer-pointer-source-link.log`), including
the distinct-binding evidence for the actual allocation sequence.

`Entry/Pointers.lean::Check.evaluatesFalse` now composes the null-check
expression, including mixed pointer-local reads, slice-pointer queries, and
short-circuit disjunction. Its frame preserves the reads needed by later
operands even when an earlier query synchronizes heap bytes. `Guard.executes`
then skips the return-3 branch and runs the continuation under those resource
facts. The source matcher checks exact expression equality and the complete
return-3 guard; tests reject nonzero comparison constants and inverted
comparisons. The focused proof/dependency audit passed in 2.53 seconds
(`pointer-guard-source-audit.log`). The self-source link passed in 20.67 seconds
(`pointer-guard-source-link.log`), locating the exact guard in the
post-allocation continuation. Guard readiness remains a premise: the
three pointer bindings before it still need to establish that predicate.

Next: compose those pointer bindings with the guard, then grammar
initialization and the file-processing continuation. The rejected
argument-count branch still needs its failure contract. Whole-`main`
execution remains open.

Finish argument/path handling, allocation and slice-view resources, embedded
grammar decoding/identity, the complete file-read loop and close, ordered
multi-file iteration, pack header/module framing, and the final output write.
Supply the grammar and buffer premises left explicit in steps 1–4. Cover
empty files, multiple inputs, and partial final packed words. State host I/O
assumptions rather than assuming native writes cannot be short.

Exit: a theorem about the exact checked `main` establishes `RunSound` and
successful termination on an explicit sufficient-resource domain. The proof
derives `Success.certificate` and exact `renderedModule` stdout from file bytes.
There are no assumed file contents after a read, correct serializer buffers,
successful stage executions, or unproved intermediate ownership conditions.

### 6. Failures, completeness, and acceptance

Component steps must retain failure information as they are built. Here compose
it through `main`: bad arguments, open/read/close errors, allocation failure,
lex/parse errors, tree/depth exhaustion, semantic/encoding errors, and output
failure. Prove the actual `RunFailureSafe` target. Derive a noncircular supported
domain and sufficient fuel for `RunComplete`; prove that the self source closure
is in that domain. Resolve any traps outside that domain explicitly.

Audit the final theorem's complete dependency closure. New reader proofs use
standard Lean axioms, but reused frontend proofs still contain legacy native
decisions. Resolve those reachable trust obligations; local kernel-only audits
do not establish the final theorem's trust footprint. No `sorry`, custom
correctness axioms, or assumed accepted output may close milestone 3.

Exit: all three final contracts are proved for the actual extractor, the exact
self source/embedding linkage is rechecked, and a fresh self-extraction succeeds.
Record theorem names, assumptions, source/artifact identities, axiom inventory,
and scoped timings. Keep bootstrap executable trust separate: verifying the
compiler and producing the verified x86 extractor are milestones 4–6.

## Audit evidence and limits

The initial audit on September 7, 2026 found `RunSound`, `RunFailureSafe`, and
`RunComplete` only in their contract definitions. The work recorded above does
not yet discharge them. Whole-call `parse_tree.visit/materialize` theorems close
step 2; the September 8 `extract_syntax` call theorem now closes step 3 on its
stated caller domain. The collector public call and its frontend connection
now close step 4.2; compact emission and the whole extractor's contracts remain open.

At the initial audit, the whole-reader link test had passed in 20.68 seconds
(`target/verified-compiler/reader-transport-source-run.log`). The record
postcondition build passed in 2.06 seconds (`reader-postcondition.log`).
These are prior successful checks inspected during this audit, not new whole
milestone checks. No broad build or source revalidation was needed for the plan.

The existing bootstrap and embedding identities were reread and still match
`BOOTSTRAP.md`:

- x86 bootstrap: `9608971d94f2cfc2d1622785f0546628c527db5c834e16c9a9ddc63e34977c55`
- self embedding: `ef7858063a60a986a437b999e2da435d70c69baa806929db32591f9261272049`
- ordered closure list: `079059b1eb54011de70900c1c5a9f7d411a027c7166728a95b55aef461a77bf3`

The active implementation action is step 4, as recorded above. The reader,
materializer, and whole frontend call are checked on their stated caller domains;
the whole extractor's contracts remain open.
