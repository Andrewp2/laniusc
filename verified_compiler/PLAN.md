# Self-hosted extraction and verified x86 compilation

## September 18: reduce lexer proof bookkeeping

Across ten batches, **4,606 production lines** were removed and 134 test lines were added: **4,472 fewer lines overall**. The earlier keyword cleanup still deletes `KeywordWorldSemantics.lean` without a shim and retains exact cell-first, recovered-command, and cell-0 contracts.

Cleanup12's four proof files fall 6,133→5,968 lines (−165): `ScanOne/Execution` −55, `Lexer/Calls` −32, `Number/Evaluation` −20, and `DigitRunEvaluation` −58. `SeqTree` and `Surface` add 11 and 6 shared production lines, so six production files fall 6,706→6,558 (−148). `Quotation` adds 46 test-source lines across six new theorem cases (47 added, 1 removed); the seven-file net is **−102 lines**.

The 119 existing public theorem statements in the four proof files and 12 existing generic rules are unchanged; one lemma was added. No new axiom, native proof call, or resource limit was added. The old full `CheckedCalls` inventory still inherits 11 native-computation facts plus the standard three, so no full-compiler native-free claim is made. Fresh shared-import checks took 3.06s, 2.31s, 2.27s, and 1.58s; these are proof checks, not runtime-performance measurements or whole-compiler timing.

The three-unit Surface acceptance for Host, TokenScan, and ByteIO passed fresh in 64.46s; it does not certify the whole 18-unit pack. Current unit8 only checked the ArtifactView cache with a full cache in 21.81s, not a Surface certificate. Range-equality support now carries well-formedness and exact-size facts to avoid recursion-limit pressure; full-cache profiling still spends 11.71s of 22.67s in `parseNodesRepresent`, not the 3s goal. The lexer dependency build and 100-declaration standard-only audit passed; the wider FrontendLink target timed out at the strict 119s limit while rebuilding unchanged parser closure (exit 124), so no full connected-build success is claimed.

The fresh source gate still has the known `FunctionalViewCoverage:36` artifact source-byte mismatch. Source binding and full closure remain open; the new five-function canonical implementation uses `Host.MemoryFrame`, while old contracts require exact `HeapFrame`, so the old theorem cannot transfer unchanged. The 5× proof-size target and broader milestone remain incomplete.

Cleanup13's seven proof files still remove 91 production lines, but the
balanced quotation promotion adds 68 lines of shared support (`ArtifactCacheQuote`
173→241); `Surface` remains 237 lines and `Quotation` grows 102→169 test lines.
Thus this cleanup is −23 production lines, +67 test lines, and +44 overall.
Across 11 batches: −4,629 production, +201 test, net −4,428 lines. The 78
retained public theorem statements and strict standard-only core/new-API audits
remain green; no new resource or trust dependency was added.

Private runtime judgments shorten statements; existing `Env`, `Int`, and `Option`
rules replace bookkeeping, and both `maxRecDepth 200000` overrides were removed.

The connected `Quotation` build passed 11 jobs in 2.09s; the narrow `CallTrust`
build passed 389 jobs in 24.08s, with no whole-`FrontendLink` claim. The
cache-only proper runner fell from 17.47s to 10.28s, while its emitted `.olean`
grew from 5,119,696 to 13,758,688 bytes (2.69×); a 9.84s `shareCommon` scratch
variant was larger still and was not promoted. These are certificate
generation/checking wall times, not compiled Lanius execution or proof-authoring
measurements; no isolated kernel-only timing claim is made. The three-unit
production Surface recipe passed in 48.34s. The full-unit8 Surface acceptance
also passed in 59.77s with current-source equality, the first complete unit8
Surface certificate; its phases were proposal 1.811s, cache 5.302s, typed
tokens 6.450s, fused node validation/reconstruction 25.766s, and origin
witnesses 10.743s. Source→Core/compiler closure remains open.

At the prior Cleanup13 checkpoint, `BlockComment` was about 52.1× its ten-line
source; Cleanup14 reduces the current ratio to 49.3×. The 5× proof-size and 3s
certificate-fast-path goals remain unmet. The old full `CheckedCalls` inventory
still inherits 11 native-computation facts, so no full-compiler native-free
claim is made.

Cleanup14 removes 87 production lines across four proof files: `Calls` −38
(2,606→2,568), `BlockComment` −28 (521→493), `LineComment` −9 (268→259), and
`Number` −12 (1,193→1,181). Shared FunctionalView support adds 24 lines, while
`Reification` adds 102 focused test lines: −63 production, +102 tests, +39
overall. Across 12 batches: −4,692 production, +303 tests, net −4,389 lines.
The 162 old public production statements and nine old test statements remain
unchanged; no trust or option dependency was added. The proof cleanup composes
guarded RHS evaluation and removes duplicate private proof setup.

The connected `CallTrust`+`Reification` graph passed 392 jobs in 13.38s after
an incremental retry following the initial 29.45s `Calls` failure; this is not
a speedup benchmark. The strict 100-declaration standard-only audit passed.
Fresh individual checks took 1.45s (`BlockComment`), 1.35s (`LineComment`),
2.25s (`Number`), and 2.21s (`Reification`); parser `FunctionalView.Scan`
checked fresh in 4.14s with built dependencies. Source→Core/compiler closure,
the native inventory, and the broader milestone remain open.

Cleanup15 retains three production reductions: `Quoted` 1,088→1,056 (−32),
`Lexer/Calls` 2,568→2,553 (−15), and `Number/Calls` 331→311 (−20), for
−67 lines overall, with no shared or test-line growth. The Quoted cleanup adds
only a private `Returns` judgment and reuses existing frame conversion and
parameter-representation rules; all 79 public statements remain unchanged. A
proposed acyclic-evaluator rewrite grew against the original baseline and was
reverted. Across 13 batches, production is −4,759 lines, tests are +303 lines,
and the net is −4,456 lines; no new axioms, native calls, or options were added.
The connected `CallTrust`+`Reification` graph passes 392 jobs incrementally in
16.37s, and the strict 100-declaration audit permits only the standard three
axioms. Fresh import-built checks took 1.72s (`Quoted`), 2.43s (`Lexer/Calls`),
and 1.55s (`Number/Calls`); these are proof checks, not whole-certificate
benchmarks. The unchanged full-unit8 Surface certificate remains 59.77s, not
the 3s goal. The broader 5×, 3s, and source-to-Core closure goals remain open.

Cleanup16 reduces eight proof files 1,836→1,518 lines (−318):
`Number/Calls` −46, the three Decimal files −121, `RawScanOne` −42,
`Symbol` −26, `CanonicalKind` −36, and `CheckedCalls` −47. Shared
`CheckedSimulation` grows 96→159 (+63) and `CallTrust` 124→126 (+2), for
−255 production lines and −253 overall in this batch. The universal
`callPreservesFrame` rule derives callee setup, fresh simulation, restoration,
and post-argument caller/source-binding preservation; it is used at nine sites
across eight files. The keyword singleton projection remains intact, while its
tail reuses the existing `callReturned` rule. All 53 existing public production
statements are unchanged. Across 14 batches, production is −5,014 lines,
tests are +305, and the net is −4,709 lines.

The connected `CallTrust`+`CheckedCalls`+`CanonicalKindContracts` graph passed
418 jobs incrementally in 34.39s; this is not a speedup or whole-compiler
benchmark. Fresh import-built checks took 1.28–1.93s, with the generic rule
checking in 0.8s. The strict 101-declaration audit permits only the standard
three axioms. The old `CheckedCalls` native inventory fell from 11 to 10
facts because only the `isTriviaCall` action-free proof moved to kernel
`decide`; `CanonicalKind` remains at seven, with no added axiom names or
options. The previous full-unit8 Surface result remains 59.77s and was not
rerun. The 5×, 3s, and source-to-Core closure goals remain open; the
`BlockComment` warning remains 493/10 = 49.3×.

## September 17: connect the binary suffix to its Lanius producer

`backend::operation::from_slot` now owns the move-right/reload-left/operation
suffix. Binary expressions and compound assignments call it directly and write
their workspace cursor once, instead of three times. It retains the existing
instruction emitters and failure propagation; there is no compatibility wrapper.
The supported compiler context keeps output and workspace disjoint.

`Lower.Operation.FromSlot.succeeds` proves execution of that actual helper for
ADD, SUB, AND, OR, and XOR, its exact ten-byte output window and return cursor,
caller/storage preservation, and the Core refinement of those same bytes.
Native execution retains following code, memory, non-scratch registers, upper-bit
clearing, and flags. Preconditions are authenticated callees, a bounded frame
slot, and sufficient output storage/capacity. Neither successful emission nor
native correctness is assumed. `rejects` proves sticky initial reservation
failure with no output access, including non-slice output. `write` now also
proves exact partial output and the failure cursor for every instruction-boundary
failure on a valid buffer, including an already-negative cursor. It composes
proved callee contracts rather than interpreting their implementations again.

Fresh checking of the complete, combined proof module takes **2.79 seconds**
with imports built (the integration agent measured 2.72 seconds). The temporary
expression-proof file was merged back into it and deleted, with no import shim.
This is not a speedup over the earlier 2.24-second, narrower proof. The connected
proof/test rebuild takes **12.07 seconds**, and strict transitive audits allow
only `propext`, `Classical.choice`, and `Quot.sound`.

The focused source regression passes **3,559 calls**, 44 selector cases, and
source-shape rejection checks in **4.69 seconds**. Its 825 `from_slot` cases now
compare the total writer model against independent byte prefixes and actual
Core execution. Negative cursors retain their signed value in that comparison.
Automation tests reject wrong callees, results, and unmet preconditions. Runtime
source authentication is not a saved kernel certificate for this concrete
backend embedding. No Lanius code or executable changed in this follow-up, so
the physical native and wider frame suites were not rerun; their prior results
were 7.11 and 4.08 seconds, respectively, with twelve unchanged scalar binaries.

Size warning: the component now has **218 program-specific Lean lines**
(173 lowering and 45 source authentication), versus 174 before, for a seven-line
Lanius helper. That is about **31x**, not the desired 5x. The stronger failure
coverage and shorter public proofs do not establish an overall size reduction.
The composition support also counts: 214 lines for expression rules, automation,
source bridges, and the writer model; 17 for contract mapping/storage framing;
and 111 for callee adapters. These **342 support lines** are separate from the
218, not hidden from the accounting; older dependencies remain additional.
The existing Boolean consumer shrank from 104 to 98 lines. Automation tests grew
by 31 lines and the suffix tests by eight (now 125 and 60 lines respectively).

Six Luna agents worked on bounded helpers, consumers, and tests; an additional
integration agent completed the connected proof after the first integration
attempt failed. This is useful delegation, not evidence that more agents alone
solve the architecture. Do not scale the pattern across recursive branches yet:
the next size target is repeated constant/callee setup and byte-emission
composition, while preserving the current contracts and fast checks.

Current artifacts under `target/verified-compiler` are `from-slot-backend`
(146,565 bytes; GPU bootstrap 2.65 seconds) and `FromSlotBackendExtracted.lean`
(12,625,031 bytes; Lanius extraction 2.20 seconds). SHA-256:
`9e912be6be0e9a83255671f7bcffd84f20d3faf034e59914b5c669d4c5964dd0`
and `ec6bbde10199b7b4468895e1259519e742eac0c2189e779ea07be825fd8735e6`.
Logs use `from-slot-`. The executable is still an unverified bootstrap.

This closes a source-to-machine suffix, not the whole BINARY branch: source
capture/allocation, both recursive child contracts, type/resource rejection,
and wrapper restoration remain. Milestone 3, its 3/18 kernel source-to-Surface
acceptance, the raw-view alias mismatch, runtime/ELF preservation, and the full
seven-step goal remain open. No extractor source-closure files changed.

## September 17: native composition for eager binary operands

`Lower.Expression.Binary.continues` proves the native sequence after the left
operand has returned: save its low word, run a proved right operand, move the
right result to ECX, reload the left result into EAX, and execute the arithmetic
instruction. One six-line statement/eight-line proof covers ADD, SUB, AND, OR,
and XOR. It derives Core's result from both original operand values, handles
dirty upper bits, and accepts either architectural auxiliary-flag outcome.
The suffix preserves memory and non-scratch registers; `Finished.frame` retains
the caller's frame and direction flag.

The new 35-line `Machine.Block` rule composes actual decoded machine steps,
instruction-pointer advancement, and the loaded following code. Capture proves
code preservation under an explicit code/temporary separation condition. The
right-child contract preserves RBP and the four saved bytes, **not all memory**;
side effects elsewhere remain allowed. The full child simulation must also
supply its Core-value correspondence and caller-frame/heap relations; this
native continuation does not establish those. Child correctness is an induction
obligation, not an axiom. A kernel-checked literal-right instance discharges it
for every pair of operand bit patterns. The byte definitions reuse the existing
source-emitter encodings rather than introducing another compiler.

The complete native module checks fresh in **1.33 seconds**, with imports built;
the strict transitive audit checks in **1.34 seconds** and allows only standard
Lean axioms. The connected test rebuild took 2.77 seconds. Tests pass 375 pure
and 375 memory-writing sequences; reversed operand preparation and a missing
reload are both detected. The actual-source/native scalar suite passes in
**7.39 seconds**, including those checks, 50 Core/native results, seven matching
expected traps, and 84 malformed transports. It also finds each of the five
proved suffix byte patterns in current compiler output for `nested` and `bits`.
The seven trap diagnostics are expected. Initial elaboration and test-entrypoint
errors were fixed without increasing limits or changing the trust boundary.

Accounting: **139 native binary-proof lines, 35 shared composition lines, and
98 test/integration lines**; no Lanius or compiler executable changed. This is
not a complete source-branch proof/code ratio, and does not establish the 5x
target. It must not be counted as another closed recursive compiler case.
Logs use `binary-` under `target/verified-compiler`.

Next closure obligation: prove that the actual `emit_expression` BINARY branch
uses both child contracts and emits this sequence, including allocator/frame
store, type rejection, output exhaustion, and wrapper restoration; then close
the recursive induction. The native continuation alone does not prove source
execution. Milestone 3, source-to-Surface acceptance (3/18), runtime/ELF
preservation, the raw-view alias mismatch, and the seven-step goal remain open.

## September 17: arithmetic dispatch closes the source-to-machine connection

`Lower.Operation.Arithmetic.succeeds` now proves the actual
`backend::operation::binary` path for ADD, SUB, AND, OR, and XOR: both selector
calls, opcode choice, guarded emission, exact output, termination, caller
framing, and native correctness of the produced window. `rejects` proves that
invalid cursors or short capacity return -1 without touching output; rejected
output need not be a slice. These endpoints assume authenticated source and
ordinary storage/bounds conditions, not successful source or native execution.
Recursive operand compilation is still a separate, open obligation.

The Lanius opcode selection is now a pure table helper, reusing the existing
table proof. Dispatch consumes the emitter's `CellSpec` directly instead of an
execution callback. Its statement shrank from 14 to six lines; success is a
five-line statement/five-line proof, and rejection is four/three. The internal
dispatch proof remains 28 lines. Shared storage/scope rules carry backing-cell
facts through both read-only calls and restore caller locals. `Produces` and
`Output` retain the same exact bytes, frame, and native semantics; caller
migration added no old-signature adapter.

Fresh checking of the complete dispatch module takes **2.32 seconds**, with
imports built, including elaboration and kernel checking. The transitive audit
takes **1.30 seconds** and permits only `propext`, `Classical.choice`, and
`Quot.sound`. The connected proof/test rebuild took 7.87 seconds. Initial
elaboration failures were fixed, not accepted as evidence or bypassed.

Fresh source-bound validation passes 240 dispatcher calls, 22 opcode selections,
four rejected source-shape mutations, 1,050 low-level arithmetic calls, and the
existing comparison/Boolean cases in **3.45 seconds**. The broader frame/source
regression passes in **4.03 seconds** with dependencies built (33.05 seconds
including its dependency rebuild). The current GPU-bootstrap executable also
passed 50 Core/native scalar results, seven expected matching traps, and 84
malformed-transport checks in 6.90 seconds. These IO checks do not create a
saved kernel source certificate.

Full incremental accounting since the preceding emitter checkpoint: **122
program-specific Lean lines, 94 shared storage/scope lines, and 49 test lines**;
Lanius grows by four lines. The selector and arithmetic dispatch prefix occupy
19 physical Lanius lines, excluding the already-proved condition selector and
byte emitter. Thus even the program-specific increment is about 6.4x that
region, or 11.4x including new shared support, before existing dependencies.
This is above the 5x target, not a repository-wide ratio or evidence that the
size problem is solved. Reuse the shared contracts; do not duplicate the
dispatch administration for each operator.

Current backend artifacts are `arithmetic-backend` (147,034 bytes; GPU bootstrap,
3.15 seconds) and `ArithmeticBackendExtracted.lean` (12,642,059 bytes; Lanius
extraction, 3.81 seconds) under `target/verified-compiler`. Their SHA-256 values
are respectively `6e11ecb28c6656c9836f13dadb10979d48316235728c7f5f41c01b5f1a3cfdb4`
and `cd36b60fee7e68b111dfd5edb694a10025a6d3f2fd6fe6178d73835d51a02a58`.
The executable remains unverified. Logs use the `dispatch-` prefix.

This closes arithmetic operation selection/emission, not recursive expression
preservation, the remaining operators, runtime/ELF correctness, or milestone 3.
The extractor's 18-source closure is unchanged; kernel source-to-Surface
acceptance remains **3/18**, and its 53.66-second fresh certificate has not
become a seconds-level check. The raw-view alias mismatch in `MEMORY.md` also
remains unresolved. The seven-step goal is still open.

## September 17: five arithmetic emitters share a source-to-machine proof

`Encode.Arithmetic.succeeds` connects the actual Lanius `x86::encode::binary`
call to the Core result of ADD, SUB, AND, OR, and XOR. Its public statement is
four lines and its proof is two lines. The shared `Produces` contract retains
source-call termination, exact output storage, caller framing, and native
correctness of the same emitted byte window. The theorem assumes authenticated
source syntax and ordinary input/storage bounds, not successful execution.

The new machine operation handles all register pairs, including identical and
extended registers, and arbitrary low-32-bit operands with dirty upper halves.
Arithmetic wraps exactly as Core specifies. The destination high half clears;
other registers and memory remain unchanged. ADD/SUB set arithmetic flags;
logical operations permit either auxiliary-flag value. The native theorem
quantifies over that choice, and direction-flag preservation is proved. This
extends the existing user-mode machine model, with its documented environmental
limits; it is not a proof of the entire physical ISA or runtime.

The first decoder proof enumerated register pairs. It was replaced before
scaling with symbolic ModRM/REX field reasoning. An otherwise identical full
proof using enumeration checks in **8.20 seconds**; the symbolic version checks
in **1.42 seconds**, with shared imports built. The counterfactual is retained
only under `target/verified-compiler/ArithmeticEnumerated.lean`. No native proof
decision, new axiom, resource-limit increase, or certificate cache supplies the
result. The initial machine support build took 1.79 seconds; the connected
arithmetic proof build took 1.97 seconds.

The actual-source regression passes **1,050 arithmetic calls**, covering both
REX extension bits, register aliases, exact-fit/short buffers, negative and
overflow-boundary cursors, nonslice rejected outputs, and caller preservation.
Together with the existing 324 comparison calls, 22 condition selections and
1,120 Boolean calls, the fresh source-bound invocation takes **3.34 seconds**.
This is executable validation of the unchanged backend pack, not a new saved
source-acceptance certificate. Decoder/boundary tests and transitive-axiom
audits pass; the existing Scalar and Boolean proof targets also rebuild.
Early failed checks were proof elaboration and test-diagnostic issues, not
accepted evidence; the first multi-target rebuild took 9.28 seconds and failed,
then the corrected source driver built in 3.9 seconds and arithmetic tests in
0.964 seconds. Logs are `alu-*` in `target/verified-compiler`.

Full growth, including helper definitions: **64 machine-model lines, 145
emission/refinement lines, and 83 test lines: 292 total**. The short wrapper is
not the size of the complete proof. These are deltas on top of the existing
guarded/register-emitter proofs, not evidence of a repository-wide 5x ratio.
No Lanius, Rust, Python, emitted bytes, or source-pack identity changed.

This closes the byte emitter's arithmetic source/native connection. Selection
in `backend::operation::binary`, recursive operand composition, multiply,
division/remainder, and shifts still need their connected compiler proofs.
Do not count this as five complete recursive expression cases. Source-to-Surface
kernel acceptance remains **3/18**; milestone 3, full x86 preservation, the
verified extractor executable, and the seven-step goal remain open. The
53.66-second fresh Surface certificate is unchanged and still needs a faster
proof path.

## September 17: bounded symbol reads and shared spelling indexes

Fresh source-to-Core validation of the same 22-source, 90-function backend
pack takes **0.902 seconds inside the driver**, versus 2.890 seconds at the
preceding checkpoint; the complete profiling invocation takes 2.61 seconds.
The complete source/execution/mutation regression passes in **4.81 seconds**,
versus 6.84 seconds previously. These are executable checks, not kernel
acceptance certificates.

`matchSymbolHead` previously mapped the whole remaining file before matching
symbols of at most three bytes. It now maps only that prefix. Two generic
prefix lemmas prove exactly the same longest-match result, including failure
and tie behavior. The actual-source agreement proof still builds; its
three-byte independence theorem now closes by reflexivity. Token validation
falls from 1,305 ms to 39 ms on the same pack.

Spelling claims reuse `artifactTokenText?` and `ArtifactAccess.indexedFor` from
reconstruction. One lookup-parametric containment routine serves both views
and runtime indexes. Spelling validation falls from 723 ms to 12 ms. Its
equivalence theorem has a two-line statement and four-line proof. The combined
indexed claim checker no longer takes an unused view, and the redundant view
congruence lemma was removed. All internal callers migrated without old-name
wrappers.

The Surface recipe now assembles parse acceptance through the proved public
checker equation, rather than its former runtime implementation. Phase guards
audit retained declarations: an injected invalid token proof stops after the
cache phase with exit 1 in 4.06 seconds and emits no certificate. The refreshed
three-unit kernel certificate passes its strict audit in **53.66 seconds**
with dependencies built; reload/audit takes 1.62 seconds. The pre-change fresh
measurement was 47.79 seconds. **No kernel speedup is established**; do not
scale this cost across the remaining source units. An earlier connected
rebuild/certificate run took 66.41 seconds and is not the fresh timing above.

Focused tests cover 11 symbol boundaries, opaque unused suffixes, and 480
spelling cases across UTF-8, malformed bytes, absent sources, bad spans/files,
missing references, and cycles. All 35 backend mutations still reject. Strict
transitive audits allow only standard Lean axioms. Fresh symbol and Surface
proof-module checks take 1.35 and 2.48 seconds with dependencies built. Shared
rebuilds took 86.17 seconds for the symbol change, 52.41 for the final spelling
support/tests, and 58.59 for the backend regression driver. A preceding spelling
trial stopped at its 45-second bound with a failed view-transport proof; it is
not an accepted result. The direct API migration above resolves that failure.
Measurements are recorded separately in `prefix-*`, `spelling-*`, `scanner-spelling-*`, and
`kernel-surface-reject-final*` under `target/verified-compiler`.

Since the preceding documented checkpoint, net growth is **47 shared implementation/proof lines, 33 test lines, and two
certificate-recipe lines: 82 total**, including helpers and migrated callers.
The existing 231-line recipe covers the same 200-line, three-unit Lanius scope;
this does not repair the older repository-wide proof ratio. No Lanius, Rust,
Python, or backend behavior changed. Source-to-Surface acceptance remains
**3/18**; the closed extractor instance and general x86 preservation are open.

## September 17: source validation indexes once, not at every read

The complete backend source/execution regression now takes **6.84 seconds**,
down from a same-instance **56.75-second** baseline, with shared proof/native
dependencies built. The input is still the same 22-source, 90-function,
12,643,575-byte backend pack used by the Boolean-literal checkpoint below.
Every invocation reads and validates the pack and the current ordered sources;
it does not reuse a previous program's acceptance result.

Profiling separated two costs. Interpreted decoding took 10.74 seconds; loading
the existing native decoder reduces that to about 0.42 seconds. The remaining
native checker still made repeated linear list reads: its canonical cache is
a single leaf, and the execution path was not using the existing array parse
checker. Native phase measurements before and after the indexing changes are:

| Phase | Before | After |
| --- | ---: | ---: |
| Parse-node checking | 4.846 s | 0.053 s |
| Surface reconstruction | 7.134 s | 0.031 s |
| Node-claim checking | 6.266 s | 0.015 s |

The complete source-to-Core profile now takes **2.89 seconds inside main**,
or **4.16 seconds** including loading and elaborating the profiling driver,
versus 42.64/43.95 seconds before. Token validation (1.31 seconds) and spelling
claims (0.72 seconds) now dominate the Surface phase. These are executable
validation measurements, **not saved kernel-certificate timings**.

The implementation reuses the existing array parse checker and the parametric
reconstruction algorithm. `ArtifactAccess.indexedFor_eq` proves that indexed
node, token, and source-range reads equal the list specification for every
artifact, including malformed bytes and missing entries. A kernel-proved
compiler rewrite selects that access implementation for runtime reconstruction.
Node claims share a lookup-parameterized containment routine; their indexed
check is also proved equal to the original checked-view predicate. Two obsolete
view-specific congruence lemmas were removed. Source binding, rejection behavior,
and downstream contracts are retained; no trust assumption was added.

The first reconstruction candidate exposed a Lean specialization problem:
specializing the runtime access instance moved index construction into each
read. Its connected build/run hit the 119-second cutoff and was rejected.
`ArtifactAccess` now prevents that specialization. Generated code constructs
the indexes once before the walk. After this fix, the connected backend
rebuild/run passes in 71.28 seconds; the subsequent no-rebuild invocation is
the 6.84-second result above. A native-library build took 10.78 seconds
separately. These shared builds are not hidden in the fresh validation time.

`lake run check-backend` and `check-self` share the same runner. Lake checks
whether the driver and native checker need rebuilding, then invokes the built
driver through stdin instead of re-elaborating its unchanged main. No import
stub files or cached artifact acceptances are created. `certify` is unchanged.

Verification and accounting:

- All backend execution cases and 35 source mutations still pass. A stale
  source pack is rejected in 1.64 seconds. Physical native comparison remains
  the two frame helpers, not a claim that every Core test executes natively.
- Focused checks cover empty/malformed source bytes, out-of-range node/token
  reads, 48 clipped source ranges, and 15 valid/invalid node claims. Surface
  and x86 transitive-axiom audits pass; the audit rebuild took 46.75 seconds.
- The indexed-read proof module checks fresh in 1.34 seconds with imports
  built. Its theorem statement is two lines and its proof is thirteen lines.
  The node-claim equivalence has a two-line statement and four-line proof.
- Net growth is **43 shared proof/checker lines**, **26 test/audit lines**,
  and **29 Lake runner lines**: **98 total**, including helpers and migrated
  callers. No Lanius implementation changed and no program-specific proof
  family was added. This does not establish a repository-wide 5x ratio.
- The extractor-wide `check-self` attempt stopped at the 119-second limit
  while rebuilding shared frontend dependencies, before running validation.
  It was not retried unchanged. There is no new measured self-validation
  result, and the closed kernel self-certificate remains open.

Evidence is in `target/verified-compiler/validation-*.log` and
`validation-accounting.txt`. Source-to-Surface kernel acceptance remains 3/18;
this work closes no additional source unit or compiler-preservation case.

## September 17: Boolean literal source-to-machine preservation

The actual recursive expression compiler now has proved Boolean-literal
coverage. `Literal.Boolean.from_transport` connects a serialized Core Boolean
to the real source call and the same emitted x86 window. Both `false` and
`true` execute one MOV32 instruction, return the corresponding Core Boolean,
and leave canonical zero/one bits in EAX. Other registers, memory, flags,
the caller frame, and following code are preserved. Syntax/read bounds come
from serialization; source-call termination, exact bytes, workspace updates,
and storage framing come from the shared compiler contract, not an execution
assumption.

The existing integer proof was generalized, not copied. `Scalar32` describes
integer tags or Boolean tags with zero/one payloads. The entry guards, three
transport reads, width helper, immediate emission, and capacity-failure path
now handle both kinds. Existing execution automation closes the finite guards.
`Literal.compiles` uses `Context.Call` and retains exact integer output plus its
byte window. Its signed-only wrapper proof was removed; all callers use the
shared rule. The Boolean native proof reuses the existing MOV32 execution
proof. The source-to-native statement is five lines with a five-line proof;
the serialized endpoint is six lines with a one-expression proof.

`Literal.Boolean.rejects_capacity` proves the actual failure protocol: INPUT
advances by three, CODE becomes -1, output stays unchanged, TOP and caller
storage survive, and the wrapper still returns Boolean kind 2. It does not
mistake that result kind for successful code generation. General malformed
transport rejection and recursive compiler preservation remain open.

Verification and accounting:

- The original signed-literal contract is recovered verbatim in a disposable
  **51-line** audit. It and both Boolean endpoints use only standard Lean
  axioms; checking takes **1.37 seconds**. Existing signed native, indexed and
  raw-slice endpoints keep their statements and rebuild successfully.
- Fresh Boolean proof module: **1.28 seconds** with imports built (an earlier
  concurrent check took 1.52). Existing signed preservation checks in **1.47
  seconds**, versus a same-session baseline of 1.60. These are module checks,
  not whole-compiler timings or a claimed sustained speedup.
- Connected proof/source-test rebuild: **18.79 seconds**; the final rebuild
  after adding focused tests and audit entries took **14.81 seconds**. Strict
  transitive-axiom audits pass.
- Fresh extraction of the current 22-source backend closure takes **2.14
  seconds**. The authenticated-source regression then passes **48 successful
  integer/Boolean literal calls and 120 short-capacity calls**, plus the
  existing frame/index/storage regressions, in **58.10 seconds**. It checks
  exact buffers and caller state. This is a slow combined source-validation
  and executable-regression path, not a seconds-level certificate result.
  Physical native comparison in that suite remains the two frame helpers;
  Boolean machine behavior is established by the kernel-checked theorem.
- Net growth: **51 production Lean lines and 13 test lines**, counting all
  helper and caller changes. The new Boolean module is 87 lines; the common
  literal module shrinks from 97 to 45. No Lanius implementation changed.
  The overall proof-to-source ratio is still above the target; this does not
  justify copying the old large proof pattern into more cases.

Evidence: `boolean-*.log`, `boolean-accounting.txt`, and
`BooleanRegression.lean` under `target/verified-compiler/`. The freshly emitted
`BooleanBackendExtracted.lean` is 12,643,575 bytes, SHA-256
`a9635979827aa79d3c6b8564fe256c757728a5d39a147c90512973ad93c23081`.
It is an untrusted proposal used by the regression, not a saved kernel source
certificate. Milestone 3's source-to-Surface acceptance remains 3/18; the closed
self-instance, general x86 preservation, and milestones 5–7 remain unfinished.

## September 17: shorter expression-call contracts, with unchanged guarantees

Initialized scalar and pointer locals now use `Expression.Context`: one
description of the invocation, separate memory/resource invariants, and an
`Emits` contract built on `CellSpec`. It still proves termination of the actual
source call, exact output bytes, workspace updates, and preservation of caller
locals, other cells, the external world, raw heap, and registered views.
Lexical lookup, frame-table representation, syntax, and capacity remain proved
preconditions; neither compiler nor native execution is assumed.

`Local.Preservation.compiles` shrinks from a 36-line statement and seven-line
proof to six and one. The pointer theorem uses five and one. Both serialized
syntax endpoints reuse one transport lemma. `Emits.refines` uses the retained
byte equality to attach native correctness to the actual output window; the
two old case-specific window proofs were removed. Raw-slice callers use the
new API directly, with no old-signature wrappers. Argument construction moved
from the literal emitter to its state module so the shared contract does not
depend on a completed expression-case proof.

Verification, with shared imports already built:

- Fresh local preservation module: **1.27 seconds**, versus **7.41 seconds**
  in the before measurement (an earlier after run was 1.21 seconds). This is
  module elaboration/checking and import loading, not a whole-compiler result
  or a phase-by-phase kernel profile.
- A disposable migration audit copies all five original public theorem
  statements and derives them from the new API: **1.99 seconds**, standard
  Lean axioms only. No required outcome was dropped to shorten the interface.
- The affected connected proof graph, strict axiom audits, and source-test
  modules rebuilt in **23.41 seconds**, including the moved shared definition.
  The unchanged Lanius executables and runtime suites were not rerun.

Physical-line accounting includes every new helper and caller change:
**69 fewer production Lean lines**, four fewer test lines, **73 fewer total**.
The new shared contract costs 79 lines and local input contracts 45; those are
included. The 263-line one-off old-contract audit is an ignored build artifact,
not a production dependency. Evidence is in `target/verified-compiler/` under
`contracts-*.log` and `ContractsRegression.lean`.

The follow-up removes duplicated implementation proofs underneath these
interfaces. `Literal.Ready.enterCall` replaces ten copies of parameter
allocation and buffer-preservation reasoning. `Wrapper.body` and `Wrapper.call`
now retain any proved predicate of the emitted buffer, rather than only its
byte window. This lets successful literals, capacity failure, and missing-local
rejection use the same actual wrapper execution proof. Their wrapper proof
bodies shrink from **53/53/45 lines to 16/16/15**, with their statements unchanged.
The shared `finish_eq` rule handles restoring an already retained TOP.

This follow-up removes **165 production Lean lines**, including shared helpers,
and adds one axiom-audit entry: **164 fewer total**, or **237 fewer across both
September 17 changes**. Thirty-eight existing theorem statements are unchanged.
Both old wrapper contracts are recovered from the generalized rule by ordinary
kernel checking in **1.58 seconds**; all five original local contracts still
check in **2.06 seconds**, using standard Lean axioms only.

Fresh checks with dependencies built: shared wrapper **1.43 seconds**, local
emission **1.60 seconds** versus **1.57 seconds** before (no claimed speedup).
The connected rebuild and strict audits pass in **20.39 seconds** after focused
dependency builds. Exact-output facts are carried through, not re-executed or
reconstructed. No Lanius implementation changed; runtime suites were not rerun.
Evidence: `entry-*.log`, `entry-signatures.txt`, and the 78-line disposable
`EntryRegression.lean` under `target/verified-compiler/`.

The next cleanup shortens theorem statements as well as their proofs.
`Context.Result` describes exact buffer contents and retained output facts;
`Context.Call` adds total source execution and memory framing through `CellSpec`.
`Wrapper.body` and `Wrapper.call` now consume this full emitter contract, with
statements of **10 and five lines**, down from **27 and 30**. The local emitter's
statement drops from **34 lines to five**; the local wrapper proof drops from
22 lines to six. Literal success, capacity failure, missing-local rejection,
and raw-slice compilation migrate directly and keep their theorem statements.
No old-signature wrapper remains in production.

The shared context retains the actual `active` argument as a Core value.
Only local lookup requires a natural binding count; its `Binding` now carries
that count and the argument equality. This avoids imposing a new input-type
restriction on the shared wrapper or on literal cases.

This change removes **45 production Lean lines**, including the larger shared
contract and caller changes; test line count is unchanged. Twenty-seven existing
theorem statements are unchanged. All five original public local contracts
still check (**2.37 seconds**). A separate **62-line** migration audit recovers
the original local-emitter contract, including its lack of an explicit TOP
premise, in **1.42 seconds**. Both audits use only standard Lean axioms.
The internal wrapper premise has changed from a pointwise ready-state callback
to a total emitter contract; the historical `EntryRegression.lean` is not the
current migration gate.

Fresh module checks, with dependencies built: wrapper **1.44 seconds**, local
emission **1.61 seconds**, local preservation **1.33 seconds**. The same-session
wrapper baseline was 1.91 seconds, but the earlier 1.43-second measurement
shows no basis for claiming a sustained speedup. The connected proof and
source-test modules rebuilt in **16.63 seconds**, with strict transitive-axiom
audits passing; the final audit-only rebuild took **2.30 seconds**. No runtime
suite was rerun because the Lanius implementation and source checker did not
change. Evidence: `compact-*.log`, `compact-accounting.txt`, the updated
`ContractsRegression.lean`, and `CompactRegression.lean` in
`target/verified-compiler/`. This is proof-interface progress, not additional
compiler-case coverage or a whole-compiler checking result.

This removes repeated call-boundary obligations, not the remaining proof-size
problem: the broader local-expression proof stack still exceeds 1,000 lines.
The remaining per-case state and dispatch interfaces should reuse these
invariants without assuming successful execution. No additional
compiler case or milestone is claimed complete. Source-to-Surface remains
3/18; the closed self-instance, raw-slice semantic decision, full backend
preservation, and the seven-step goal remain open.

## September 16: actual comparison emission carries native correctness

The comparison path of `backend::operation::binary` is now source-checked and
proved. `Lower.Operation.write` executes the selector and both emitters from
their existing contracts. It proves exact eight-byte output, or the exact
two-/five-byte prefix left when the next instruction does not fit. Initial
reservation failure returns -1 without requiring a valid output slice.
Both contracts preserve existing caller storage outside the output, caller
locals, the external world, raw heap, and registered views. Fresh parameter
cells remain permitted by the shared call contract.

The successful call's postcondition also carries `Condition.NativeRefines`
for that exact output window: three decoded instructions produce Core's
Boolean result for all six i32 comparisons and all operand bit patterns,
preserving memory and other registers and advancing RIP by eight bytes.
This is part of the same source-call contract, not an unrelated reference
compiler theorem. Storage/capacity bounds and loading the emitted code remain
explicit assumptions; no callee or machine execution is assumed.

The Lanius comparison path now nests CMP directly inside the Boolean call,
removing an unnecessary temporary scope without changing emitted code or
partial-failure behavior. The exploratory scope-closing helper was discarded;
`Extraction.Source.Call` is unchanged. A one-use branch theorem and redundant
local facts were removed. Shared `CellSpec.withFact` retains an established
semantic property alongside the output postcondition without rerunning a call.

Verification with shared Lean imports built:

- Fresh comparison proof module: **2.49 seconds**; strict transitive-axiom
  audit: **1.49 seconds**, standard Lean axioms only. The earlier version
  checked in 2.02 seconds; this is not a claimed checking-time improvement.
- Exact seven-source validation covers **324** comparison calls, **22**
  selector cases, and **1,120** Boolean emissions in **8.46 seconds**. Negative source checks
  reject a changed callee, reversed operands, and a changed constant.
- The GPU compiler bootstrapped the updated Lanius backend in **2.95 seconds**.
  The candidate passed **50** Core/native scalar results, **7** matching
  arithmetic traps, **84** malformed rejections, and **12** frame protocols in
  **7.53 seconds**; **83** value results, three descriptor transports, and
  **112** malformed rejections passed in **9.22 seconds**.
- That candidate is installed at `target/verified-compiler/lanius-backend`.
  Its whole-extractor ELF is byte-identical to the previous output. This
  remains a bootstrapped executable, not a verified whole compiler.
- The connected backend and compact-output checks rebuilt in **14.04 seconds**
  after the focused dependencies. The final proof-only cleanup rebuilt the
  comparison, audit, and source-test modules in **5.50 seconds**. Neither is a
  cold build or closed self-certificate check.

Physical-line accounting: source authentication and comparison proofs total
**188 Lean lines** (51 + 137), down from 200 before removing the one-use helper
and adding the stronger postcondition. The existing selector module grows by
three lines and shared call infrastructure by ten. Relative to the preceding
selector checkpoint, that is **201 production Lean lines**, **34 test lines**,
and one additional physical Lanius line, for **236 total code lines**. Existing
selector, Boolean, CMP, and machine foundations are retained dependencies.
The matched comparison-specific scope, including the selector change, is
191 lines for the seven-line Lanius path, roughly **27x**, still well above
the 5x target. Do not duplicate this amount of scope/argument glue for arithmetic
operations; reusable composition still needs improvement.

Evidence: `target/verified-compiler/operation-*.log` and
`OperationExtracted.lean`. This closes the comparison helper's implementation
and output-to-machine connection, not the arithmetic tail or recursive
expression compiler. Source-to-Surface remains 3/18. The closed self-instance,
raw-slice semantic choice, full backend preservation, and seven-step goal remain
open.

## September 16: shared selector proof and signed i32 comparison execution

`backend::operation::condition` is source-checked and proved to return the
correct condition code for every Core binary operation, including -1 for
non-comparisons. `Source.Table` authenticates the complete branch chain and
actual constant values, then proves first-match execution once. The existing
argument-register mapper now uses that same proof; its duplicated induction
and checker were removed, and callers were migrated directly.

The machine model now decodes CMP32 as well as CMP64, following
[Intel's CMP specification, 3-153–3-154](https://www.intel.com/content/dam/www/public/us/en/documents/manuals/64-ia-32-architectures-software-developer-vol-2a-manual.pdf).
Subtraction flags are width-parametric. The signed-ordering proof handles
overflow rather than assuming it cannot occur. `Lower.Condition.native_steps`
connects the loaded CMP EAX,ECX; SETcc AL; MOVZX EAX,AL window to Core's result
for all six comparisons and every i32 bit pattern. It derives three decoded
steps, advances RIP by eight bytes, and preserves memory and other registers.
Upper register bits are arbitrary. `Encode.Guarded.compare32_step` connects
the existing source emitter's exact output contract to the new instruction;
decoding is proved for all 256 register pairs.

Verification with shared imports built:

- Fresh selector/Core/native proof module: **1.76 seconds**; shared signed-flag
  proof: **1.21 seconds**. Strict comparison audit: **1.62 seconds**, standard
  Lean axioms only, including an inhabited signed-overflow execution example.
- Exact seven-source validation: **22** selector cases and **1,120** Boolean
  emissions in **6.99 seconds**; **102** parameter-compiler successes, **288**
  rejections, and **10** ABI mappings in **6.00 seconds**.
- Actual-source native scalar suite: **50** results, **7** matching arithmetic
  traps, **84** malformed-input rejections, and **12** frame protocols in
  **9.15 seconds**. The trap fixtures intentionally terminate abnormally.
- Connected backend proof graph rebuilt in **23.88 seconds** after the
  focused dependencies; this is not a cold build or closed self-certificate.

Size accounting uses physical lines: the selector module is **67 Lean lines**
including the Core/native connection, for the **nine-line Lanius selector**
(about 7.4x, still above the 5x target). Shared table infrastructure adds 90
lines, signed comparison foundations 63, and existing ABI proofs lose 59.
Including machine and emitter changes, production code grows by **203 lines**;
tests add **97**, for **300 total**. No Lanius implementation changed. The
shared proofs replace duplication, but their cost is included, not hidden.

Evidence: `target/verified-compiler/{condition-tables-*,cmp32-*}.log` and
`ConditionTablesExtracted.lean`. The next composition boundary is the actual
`backend::operation::binary` implementation and its recursive expression
caller. The selector and machine-window proofs do not prove that enclosing
function yet. Source-to-Surface remains 3/18; the closed self-instance, raw-slice
semantic decision, and the full seven-step goal remain open.

## September 16: Boolean emission composed through native execution

The real `backend::operation::boolean` function is now source-checked and
proved. It composes SETcc and MOVZX directly as a nested call, removing an
unneeded local scope. The proof reuses their existing contracts and argument
evaluation rules; it does not unfold either callee or assume its execution.

`Encode.Boolean.write` covers successful six-byte output and partial output:
when only the first instruction fits, exactly three bytes remain and the call
returns -1. `rejects` covers invalid conditions, negative/sticky cursors, and
insufficient initial capacity without buffer access. The contracts preserve
caller locals, unrelated cells, and heap state. `steps` connects the exact
successful output to two decoded steps producing the condition value in RAX,
preserving other registers, flags, and memory, with arbitrary initial upper bits.
The source checker authenticates the signature, full body, both helper IDs, and
the looked-up RAX constant. Storage and signed-capacity assumptions remain explicit.

Verification, with shared Lean imports built:

- Fresh implementation/decoder-connection proof: **1.65 seconds**.
- Focused strict audit: **1.36 seconds**, standard Lean axioms only.
- Exact six-source validation and **1,120** full/partial/rejected executions:
  **7.81 seconds**, including negative shape checks for changed callees,
  constants, and removal of the first emission.
- GPU bootstrap: **2.69 seconds**. The candidate passed **83** Core/native
  results, three descriptor transports, and **112** malformed rejections in
  **9.77 seconds**. Its whole-extractor ELF is byte-identical to the previous one.
- Connected proof graph: **2.06 seconds** after the focused dependencies were
  rebuilt. This is not a full cold build or a closed self-certificate check.

This adds **136 physical Lean lines** (102 implementation/connection proof,
34 source authentication) for the **five-line Lanius function**, excluding tests
and the existing shared emitters. That roughly 27x ratio still exceeds the 5x
target. The extra obligations include partial-output failure, source identity,
and machine decoding, but their size is not a pattern to duplicate across more
wrappers. The attempted broader proof search was discarded after regressions;
shared execution automation is unchanged from the previous checkpoint.

The tested bootstrap is installed at `target/verified-compiler/lanius-backend`.
Evidence is in `target/verified-compiler/boolean-{emitter-*,nested-*,extractor-emission}.log`;
the exact source pack is `BooleanEmitterExtracted.lean`. The operation selector,
recursive lowering, closed self-instance, and full seven-step goal remain open.
Source-to-Surface coverage is still 3/18; the raw-slice semantic choice is unchanged.

## September 16: reuse call contracts and argument proofs

The direct and guarded register wrappers now use the shared total `CellSpec`
contract and call-frame rules. Compiler callers were migrated directly; there
are no compatibility wrappers. Exact output, termination, rejection, caller
locals, unrelated cells, and heap preservation are retained. Byte-window facts
follow from the existing `Config.emission` theorem and the exact output, rather
than being transported redundantly through each call.

`core_args` composes argument evaluation left to right, including supplied
effectful executions. Local-read automation now handles finite-indexed
parameter facts. `core_eval` and `core_exec` also strip goal metadata: a local
`have` previously made a valid execution goal fail shape recognition. Tests
cover that regression, repeated/reordered pure reads, effectful argument order,
and rejection of missing execution proofs, wrong final states, and false results.

Fresh checks, with shared imports built, compared saved pre-change modules
against the replacements in the same run:

- Direct wrappers: **4.14 → 2.76 seconds**.
- Guarded wrappers: **2.71 → 1.44 seconds**.
- SETcc: **3.16 → 2.97 seconds**; no material speedup claimed.
- All seven original expanded contracts were rederived and strictly audited
  in **1.32 seconds**. Only standard Lean axioms occur transitively.
- The connected backend/byte proof graph passed in **13.49 seconds**. Exact
  source validation and the existing execution suite passed in **25.76 seconds**,
  including 5,198 direct-wrapper and 2,000 SETcc cases. Lanius code is unchanged.

The three proof modules shrink from 513 to 403 physical lines. Shared automation
grows by 22 lines, compiler callers by six, and maintained tests by 41: **82 fewer
production lines, 41 fewer lines including tests**. Counting all three source
descriptions as well gives **567 Lean lines for 38 Lanius lines**, down from 677
(about 15x instead of 18x). This still exceeds the 5x target; the remaining source
descriptions, representation bridges, and composition work need attention before
duplicating this pattern further. The pre-existing shared encoder is excluded
from that matched wrapper scope, not claimed to have disappeared.

Evidence: `target/verified-compiler/wrapper-{final-paired-timings,contract-equivalence,connected-build,source-validation}.log`.
The expanded-contract check and baseline snapshots are disposable artifacts in
that directory, not additional maintained proof modules. Source-to-Surface
coverage remains 3/18; the closed self-instance, general x86 preservation, and
pending raw-slice semantic decision remain open. No milestone is newly complete.

## September 16: SETcc delegates to the proved encoder

`x86::control::set_condition` now guards its condition code and delegates to
the existing register encoder. The duplicate prefix, reservation, and store
implementation is gone; `register_form` is public so the control module can
call it directly. The six-line wrapper retains the original encoding and
failure behavior, including neutral REX and rejection before output access.

`Encode.Condition` proves source-checked success, invalid-condition rejection,
invalid-register rejection, and insufficient-capacity rejection. Success gives
the exact buffer contents and preserves other cells, caller locals, and heap
state. The proved output window decodes to SETcc for all 256 condition/register
pairs and supplies an actual machine step when loaded. The source checker now
authenticates this function's full body, signature, and delegated callee.
The enclosing `backend::operation::boolean` and recursive comparison-lowering
composition are still open; this does not complete milestone 4.

Shared `CheckedInternal.specCell` and `specFrame` rules close call bookkeeping
once. The existing byte-append proof now uses five lines instead of fourteen,
with the same statement. The general call module grew by 40 physical lines;
the byte module shrank by nine. SETcc-specific source descriptions, contracts,
argument proofs, and decoder connections total **144 lines** for a **six-line
Lanius wrapper** (24x, excluding the pre-existing shared encoder). That remains
above the 5x target. Treat argument/source-shape automation as a remaining
infrastructure issue; do not duplicate this amount of glue across new wrappers.
The code has not been compressed or moved into generated per-function shards.

Verification, with shared Lean imports built:

- Fresh SETcc proof module: **2.67 seconds**; focused strict audit: **1.57
  seconds**, with only the standard Lean axioms.
- Exact four-source validation and source-execution suite: **24.94 seconds**,
  including **2,000 SETcc cases** covering all condition/register pairs,
  invalid signed boundaries, exact capacity, and untouched rejection output.
- Fresh GPU-compiled Lanius encoding fixture: **46,018 instructions / 316,713
  bytes** match GNU as, with capacity and frame checks, in **1.86 seconds**.
- Rebuilt Lanius backend: **83 Core/native results**, three descriptor
  transports, and **112 malformed rejections** in **11.27 seconds**. Its
  whole-extractor ELF is byte-identical to the existing executable.
- The connected backend and byte-output proof/test graph rebuilt in **20.51
  seconds**. No command exceeded two minutes; no trust assumptions were added.

The tested backend is installed at `target/verified-compiler/lanius-backend`.
Evidence is in `target/verified-compiler/setcc-*.log`; the fresh emitter source
pack is `SetccEncodingExtracted.lean`. Source-to-Surface coverage is still 3/18,
the raw-slice semantic choice remains pending, and the seven-step goal is open.

## September 16: comparison flags now produce the Core Boolean

`Storage.Pointer.comparison_steps` closes the native result-materialization
gap: the loaded CMP RCX,RAX; SETcc AL; MOVZX EAX,AL sequence takes three decoded
steps and puts the actual Core pointer-equality/inequality result in RAX.
It preserves every other register and memory and advances RIP by nine bytes.
The premises are the loaded bytes, represented operands in RCX/RAX, and an
injective pointer map; native addresses need not equal Core addresses.
The shared materialization rule handles all 16 condition codes and arbitrary
dirty upper register bits. No successful execution is supplied as a premise.

The machine decoder now retains REX presence, including neutral 0x40, so it
does not confuse SPL/BPL/SIL/DIL with legacy high-byte registers. Unsupported
high-byte and memory forms remain rejected. `Encode.Direct.zeroExtend_step`
connects the existing source-checked Lanius MOVZX emitter's output window to
the decoded native instruction for all 256 source/destination combinations.
It reuses the emission contract instead of repeating its source-execution proof.

This adds 151 physical Lean lines across model/proof code: 42 net in the
shared machine model, 62 in the shared sequence module, 25 in the pointer
bridge, and 22 in the MOVZX bridge. Focused tests/audit/integration add 83 lines;
decoder call sites were migrated directly. There are no generated per-program
proofs, source implementation changes, compatibility shims, or added axioms.

Fresh checking of the complete MOVZX emitter proof module takes **4.10 seconds**
with shared imports built. The focused Boolean regression/strict-audit module
checks in **1.34 seconds** with imports built (`boolean-final-audit.log`).
Rebuilding the affected backend proof graph took
17.90 seconds initially and 12.08 seconds after connecting the emitter bridge.
The actual-source native suite passed **83 Core/native results**, three
descriptor transports, and **112 malformed-program rejections** in **9.17
seconds**. It also verifies that the Lanius compiler emits the proved comparison
window. This test is evidence, not a proof of the enclosing emitter.

The SETcc emitter and enclosing comparison-lowering composition remain open,
as do recursive compiler preservation and the full seven-step goal. The pending
raw-slice semantic choice is unchanged; Source-to-Surface coverage remains 3/18.
Evidence is under `target/verified-compiler/boolean-*.log`.

## September 16: isolate certificate costs; discard ineffective batching

The fresh three-unit Surface recipe, with finer phase markers, passed its
strict audit in **46.60 seconds**, peak RSS **3,951,760 KB**, using the saved
encoding and built shared support. Byte-I/O spent 6.16 seconds authenticating
caches, 4.72 checking tokens, 10.15 linking/reconstructing, 1.84 collecting claims
and decoding Surface, 0.90 on spelling coverage, and 5.46 validating origin
witnesses. Final object/acceptance assembly took about 0.03 seconds; its audit
took 0.13 seconds. The long public theorem statements are not the dominant
cost of this certificate. The maintained recipe now records these boundaries.

The pending concurrency experiment finished: enabling asynchronous declarations
took 47.60 seconds; removing intermediate callbacks took 45.06 seconds. These
do not establish a material speedup over the 46.60-second synchronous run.
Lean's `AddDecl.addDeclCore` schedules a kernel check after `env.checked`;
elaboration concurrency does not make these kernel checks independent. The
experimental recipes/artifacts were removed. The `certify` runner retains four
worker threads and a 7,000 MB Lean memory limit to bound resource use, not as a
claimed performance improvement or trust change.

Native shape inspection found 7,574 node visits over 728 byte-I/O node-origin
paths but only 3,386 distinct root/prefix pairs. Parser node origins similarly
use 48,228 visits for 20,633 distinct prefixes. A shared-prefix checker proved
the original pruned-reachability result, including fuel and missing-edge cases,
but consecutive grouping was slower: **5.011 versus 3.184 seconds** for all
byte-I/O node paths on the same saved input, with strict audits. It needs 501
groups for 728 paths; the global sharing opportunity does not translate into
cheap consecutive groups. Sorting with the standard `List.mergeSort` failed
kernel reduction and yielded no timing evidence. All experimental batch code,
proofs, and artifacts were removed. Do not repeat this grouping strategy or
infer a whole-certificate speedup from the potential sharing count.

The retained changes are diagnostic phase markers and the runner's resource
bounds, not additional program-specific proofs. The original Surface artifact
hash below is unchanged. The runner also rejects a false `kernel_rfl` equality
with exit 1 (0.73 seconds); no false certificate was emitted. Source-to-Surface
coverage remains **3/18**, the closed self-instance remains open, and the raw
slice semantic choice below is still pending. The complete goal remains active.

Evidence under `target/verified-compiler`: `detailed-surface-{fresh,phases}.log`,
`surface-async-four-workers.log`, `surface-parallel-fresh.log`,
`origin-sharing.log`, `batch-single-profile.log`, `batch-profile-phases.log`,
`certify-reject-false.log`, and `surface-final-reload.log`.

## September 16: confirmed raw-slice semantic mismatch

Checking the next alias-synchronization boundary found a real counterexample
to general Core/native preservation. Core's `mapRawI32Slice` creates a fresh
array snapshot for every raw mapping; the native backend creates a descriptor
of the existing storage. Assigning through one view then reading through the
other returns different values. The actual source fixture `raw_alias(data, 0)`
returns 999 in Core and 29 in native execution after writing 29 through the raw
view. Native memory changes to `[29, 10, 20, 30, 888]`; Core retains the original
buffer. This was observed directly at native function return, not inferred
solely from a failing assertion.

Three source regressions cover raw-to-original, original-to-raw, and repeated
raw mapping. The existing source-authenticated suite now checks every case
before reporting failure: **9 mismatches, 54 matching results, 41 matching
bounds traps**, in **13.08 seconds** with shared imports and existing bootstrap
executables. Extraction took 0.04 seconds and focused test-support rebuilding
took 2.51 seconds. The test remains red; no mismatch is treated as success.

No semantic or backend implementation change has been made. The user has been
asked whether to correct Core to shared storage (recommended) or preserve its
snapshot behavior in the backend. This changes the meaning of the program
being proved, so the proof must not silently exclude these accepted programs
or replace the source semantics. Shared storage can reuse the registered
backing place; the fresh-only constructor theorem contracts must then be
updated across runtime typing, cell renaming, registry invariants, and native
construction. See `MEMORY.md`. The complete seven-step goal remains open.

Evidence: `raw-alias-extraction.log`, `raw-alias-test-build.log`,
`raw-alias-native.log`, `raw-alias-observation.log`, and
`raw-alias-all-cases.log` under `target/verified-compiler`. Reproduce the full
comparison from the repository root, with a 35-second timeout per command:

```sh
timeout -k 2s 35s target/verified-compiler/lanius-extractor verified_compiler/tests/x86/slices.lani > target/verified-compiler/SlicesAliasExtracted.lean
timeout -k 2s 35s lake -d formal env lean --run formal/Lanius/X86/Tests/Slices.lean target/verified-compiler/lanius-backend target/verified-compiler/SlicesAliasExtracted.lean verified_compiler/tests/x86/slices.lani target/verified-compiler/raw-alias-native
```

## September 16: bounded Core/native writes; reject slower checker experiments

`Storage/Heap/Store.lean` now proves the actual Core bulk store succeeds within
one mapped live allocation and preserves the full native heap correspondence,
pointer map, frontier, and budget. One induction reuses the existing byte-store
proof. Core's i32 bytes equal the modeled MOV32 memory update for every integer.
The connected `store_i32_step` theorem derives a decoded native step from the
loaded disp32 bytes and relates its resulting memory to the actual Core store.
It uses the encoding already proved for the Lanius emitter; it does not assume
either store succeeds. Address/value register preparation and code loading are
explicit premises. Recursive assignment lowering, alias synchronization, native
allocation, and general compiler preservation remain open.

The new shared proof/model code is 92 physical lines, with 70 regression/audit
lines; no per-function family, runtime language, or trust assumption was added.
Focused checks cover arbitrary i32 payloads, Core/native readback, preservation
of another allocation, interior writes, empty end-boundary writes, overflow
rejection, modular native addresses, and a loaded extended-register/SIB MOV
with negative displacement. Fresh checking of the pointer test module and its
strict audit takes **4.47 seconds** with shared dependencies built. The connected
backend proof/audit target passes in **2.27 seconds** with dependencies built.
Rechecking the complete store proof module from source takes **1.32 seconds**
with shared imports built (`lake env lean Lanius/X86/Storage/Heap/Store.lean`
from `formal/`, under a 25-second timeout).
These are development proof checks, not fresh end-user compiler certification.

Three frontend checker experiments were rejected and reverted:

- Retaining original source expressions in the node cache took 55.38 seconds
  for the fresh three-unit recipe; the accepted checkpoint is 47.79 seconds.
  Cache authentication improved, but reconstruction and claims became slower.
- Boolean token-code/span equality took 4.779 versus 4.681 seconds in a paired
  frozen byte-I/O token check.
- Direct Boolean branches in the complete reconstruction plan took 11.395
  versus 10.335 seconds in the paired whole-byte-I/O check.

Temporary probe sources and artifacts were removed; diagnostic logs remain.
The restored plan's focused tests pass in 2.86 seconds. Reloading and strictly
auditing the unchanged Surface certificate passes in 1.35 seconds; this is
reuse, not fresh checking. Its hash remains the one below. Source-to-Surface
coverage remains **3/18**, and the seven-step goal is not complete.

Evidence: `heap-stores-fresh-proof.log`, `heap-stores-tests.log`, `heap-stores-connected-audit.log`,
`retained-cache-fresh.log`, `token-equality-phases.log`,
`boolean-plan-phases.log`, `restored-plan-tests.log`, and
`restored-surface-audit.log` under `target/verified-compiler`.

## September 16: context proofs integrated into the fresh Surface certificate

`Reconstruction/Plan.lean` now consumes ordinary nodes and empty-precedence
contexts in one pass. Ordinary ranges no longer allocate a `take` prefix and
then traverse it for its length and drop it from the original input. Context
pairs are authenticated as they are consumed, retaining the actual child tree.
The general soundness theorem gives the **same complete forest** as the original
grammar-checking linker, and the connected theorem retains the original exact
Surface reconstruction equation. Native plans are hints only; omitted, changed,
reordered, truncated, or ill-typed input cannot be accepted through them.

The first whole-unit plan was slower: 11.401 seconds versus 10.971 for the
unchanged byte-I/O reconstruction, with saved source/cache inputs. Its link-only
diagnostic was also slower, 6.390 versus 5.652 seconds. These measurements
motivated the single-pass implementation rather than adoption of that version.
The corrected paired whole-unit diagnostic takes **9.983 versus 11.321 seconds**;
retaining the original equation adds 0.007 seconds. Its complete invocation,
including proposal, quotation, both checks, and strict audit, takes 23.42 seconds.

The fresh three-unit recipe now uses the proved plan. Proposal, quotation,
cache/token/node/reconstruction/claim checks, strict audit, and output pass in
**47.79 seconds**, compared with **52.34 seconds** for the unchanged recipe
measured immediately beforehand. Peak RSS falls from 4,130,832 to 3,954,364 KB.
Both use the saved encoding and built shared support; neither imports a saved
Surface proof. Earlier 46.29-second measurements remain historical: this is a
modest paired improvement, not an order-of-magnitude gain or a new universal
timing bound. Byte-I/O's fused phase takes 10.353 seconds in the fresh run;
cache authentication, token checking, and claims still cost substantial time.

The updated `SelfSurface.olean` is 5,161,112 bytes, SHA-256
`5119457c68fc4803bdf51c97be5c005cefc8ab50aed1764e657408ddf0c41f41`.
Reload and strict audit pass in **2.02 seconds**, which is reuse, not fresh
verification. The encoding, Core, and lowering artifact hashes are unchanged.
The runner builds the new shared dependency explicitly. The recipe stops at the
first failed phase instead of continuing expensive checks after an error.

Focused checks cover exact reconstruction and source identities, nonzero
counters, fuel exhaustion, valid mixed/ordinary-only plans, oversized ordinary
counts, malformed/truncated/reordered plans, and corruption of every one of the
24 source-node production fields. The connected support/test rebuild passes in
2.98 seconds (the focused test module itself takes 1.4 seconds). Strict audits
allow only `propext`, `Classical.choice`, and `Quot.sound`.

Size accounting, including earlier context work: 467 shared implementation/proof/
proposal lines, 91 regression lines, and 154 profiling lines. The representative
200-line Lanius source scope uses a 215-line certificate recipe and the existing
19-line reload/audit recipe. These counts do not include, or claim to repair,
the older large semantic proof bodies. No per-function proof-file family or new
runtime language was added.

Source-to-Surface acceptance remains **3/18**. All-unit Surface-to-Core lowering
is unchanged; the closed extractor instance and general x86 preservation remain
open. Next work must reduce the remaining connected checking cost before
scaling this pattern across the complete source closure. The seven-step goal
remains active.

Evidence under `target/verified-compiler`: `link-profile{,-phases}.log`,
`planned-single-pass.log`, `surface-plan-{baseline,fresh}{,-phases}.log`,
`plan-single-pass-regressions.log`, and `surface-plan-reload.log`. Reproduce the
whole-unit paired diagnostic with the existing `certify` runner and
`formal/experiments/representation/Planned.lean`; reproduce fresh acceptance
with `verified_compiler/proofs/Surface.lean` as documented in `BOOTSTRAP.md`.

## September 16: shared precedence-context proofs; whole-unit integration remains

`Reconstruction/Contexts.lean` now proves two properties of an empty binary
precedence context: the original grammar validator/linker accepts its generated
nodes under the stated child-type/span bounds, and reconstruction equals the
child's reconstruction with the corresponding fuel budget. The latter is an
equality of complete state transformers, including child failure and exact
Surface identities; successful child execution is not an assumption. A shared
theorem covers the whole ten-level, twenty-node context. Source acceptance still
requires authenticating the proposed nodes against the original artifact.

A connected diagnostic finds 75 such contexts (1,500 nodes) in the actual frozen
byte-I/O unit. With saved source data and authenticated caches, range
authentication plus the shared source-checker proof takes **1.137 seconds**
(1.114 + 0.023), compared with **1.360 seconds** for the existing fused linker
on those contexts and **3.157 seconds** for the original indexed node validator.
Quotation takes 0.442 seconds; the full comparative invocation takes 7.71 seconds,
peak RSS 2,249,520 KB. The preceding run measured 1.030 versus 1.254 seconds.
All three checks pass strict axiom audits. These are
**fragment measurements, not a fresh unit certificate or a whole-compiler
speedup**. The context proof has not yet been integrated into `proofs/Surface.lean`.

The focused regression uses a valid, nonempty boolean-literal derivation. It
checks all 24 grammar nodes, source binding, exact result/parse identity/counter,
fuel exhaustion, and rejection of shifted, altered, reversed, and past-end source
ranges. Fresh focused checking takes **1.47 seconds** with shared imports built;
the context support rebuild takes 1.66 seconds separately. Only standard Lean
axioms are allowed. Maintained growth is 406 physical lines: 253 shared context
implementation/proof lines, 63 regression lines, and a 90-line reproducible
profile in `formal/experiments/representation/Contexts.lean`.

Earlier alternatives were removed. A proved single-dispatch replacement for
expression reconstruction took 11.509 seconds against 10.712 for the original
complete byte-I/O fused check; its comparative invocation passed in 24.17 seconds.
Per-node context authentication took 2.001 seconds before an additional 0.023
seconds for the shared proof, losing to the fused check. A proposed ordered scan
also added cost; its integration probe failed and is not an acceptance timing.
The retained version reuses the existing, proved `SeqTree.rangeEq` operation.
The discarded evaluator and ordered-scan implementations and their artifacts
were removed. Logs remain under `target/verified-compiler`.

The preceding interval experiment also failed its performance gate: full
interval authentication, node checks, and remaining claims took 7.029 seconds
against 6.112 for paths on saved byte-I/O input. Its proved implementation was
removed. Native shape profiling across all 18 units counted 125,835 parse nodes:
51,462 have zero width and 56,689 have only one nonempty child. Removing those
shapes would leave 17,684 nodes, versus 17,537 Surface nodes. This is a size
opportunity, not a proved compression transformation: empty/forwarding grammar
contexts must preserve exact reconstruction, not just accepted strings.

Next: integrate retained context proofs into whole-unit linking/reconstruction,
including source authentication, and measure the fresh connected certificate
before scaling. Source-to-Surface acceptance remains **3/18**; all-unit
Surface-to-Core lowering is unchanged. Saved Surface/lowering artifact hashes
are unchanged. The closed extractor instance, general x86 preservation, and
the seven-step goal remain open.

Evidence: `context-probe-range.log`, `context-probe-phases.log`,
`context-profile-final.log`, `reconstruction-contexts-tests.log`,
`expression-dispatch-final-probe.log`, `interval-probe-tail.log`, and
`origin-profile-compressed-shapes.log`. Reproduce the fragment after building
`Lanius.Extraction.Tests.Contexts` with:

```sh
timeout -k 2s 30s lake -d formal run certify formal/experiments/representation/Contexts.lean target/verified-compiler/ContextProfile.olean
```

## September 16: reconstruction experiments rejected; regression gate repaired

No new Surface unit is certified by this checkpoint. Three paired diagnostics
on the saved byte-I/O input failed to improve the same exact reconstructed
Surface result:

| Experiment | Experimental check | Same-run baseline | Additional work |
| --- | ---: | ---: | ---: |
| Materialized artifact, equality-transported view | 12.51 s | 11.94 s | 3.10 s materialization/authentication |
| Reconstruction fuel 128 instead of 5,130 | 12.94 s | 12.98 s | None |
| Primitive tree projections and proof-free references | 12.64 s | 11.84 s | Generic projection equalities |

All final probes passed their strict axiom audits. Their full invocations took
29.39, 27.46, and 26.09 seconds respectively, using about 4 GiB peak RSS. These
are overlapping computations on saved inputs, **not fresh source checks**.
Earlier artifact-snapshot attempts failed during elaboration and are not
acceptance timings. None of these experimental implementations was adopted;
temporary sources and output modules were removed, with logs retained.

Kernel counters for a separate successful fused check show 222,213 `List.rec`
unfoldings, 157,780 `Bool.casesOn`, and 110,294 `Decidable.casesOn` for 5,129
parse nodes. These are reduction counts, not a CPU-time attribution. The probe
took 13.64 seconds overall. Fuel magnitude and tree accessors are now ruled out
as demonstrated fixes; the existing explicit-recursion and retained-forest
experiments below also remain rejected. Further work should target removal of
repeated validation/reconstruction obligations through retained general proofs,
not extend the unchanged per-node computation across all 18 units.

The focused reconstruction regression module had not been migrated to the
grammar-lookup argument: a fresh check failed at its old `linkFrom` call. The
call now supplies the reference lookup, includes a missing-production rejection
theorem, and strictly audits the fixture and all three soundness theorems instead
of merely printing their axioms. The focused rebuild passes in **1.36 seconds**
(shared imports built), including its existing exhaustive small-forest cases.
This restores the regression gate; it is not a compiler milestone or speedup.
Maintained proof/test growth is seven physical lines; production checker and
saved certificate contents are unchanged.

Logs under `target/verified-compiler`: `surface-snapshot-retarget.log`,
`surface-snapshot-phases.log`, `surface-fuel.log`, `surface-fuel-phases.log`,
`tree-projection.log`, `tree-projection-phases.log`, `surface-counters.log`, and
`validated-tests-restored.log`.

## September 16: complete Surface-to-Core lowering certificate

`proofs/Lowering.lean` now saves the complete original lowering equation for
all 18 frozen Surface units and the same 125-function `Self.Core.program`.
It includes preparation, layouts, constants, function order and bodies, target,
and external-policy acceptance. This is no longer just a typing certificate or
a collection of unconnected module checks. The source-byte-to-Surface binding
still covers only three units; full source acceptance, the closed extractor
instance, and general x86 semantic preservation remain open.

The fresh, single-invocation recipe takes **84.77 seconds**, peak RSS
3,397,912 KB, with shared support and the saved Core candidate available. It
reads/proposes/quotes fresh Surface inputs and recomputes every lowering proof;
it imports no saved lowering subproofs. Phase times are about 8.3 seconds for
input proposal/quotation, 27.3 for preparation materialization and checking,
45.6 for module checks, and 1.3 for composition/final assembly/audit. Reload and
strict audit take 1.54 seconds (1.82 after removing all temporary probes);
that is reuse, not fresh verification. This is
well above the seconds-level fresh-check target. The saved artifact is
2,501,872 bytes; its identity and commands are in `AUDIT.md` and `BOOTSTRAP.md`.

Two sources of repeated work were removed. String inference retains the direct
literal derivation instead of comparing a large UTF-8 string with its own copy.
The actual 8,716-byte grammar literal now checks in 42 ms within a 1.81-second
probe; actual-main lowering checks in 17.95 seconds using saved profiling
inputs, versus its earlier memory-guard failure. Separately, shared composition
lemmas join checked modules and carry the retained result through the original
public lowering operation. Final assembly does not rerun function synthesis.
Applying that connection to the concrete program directly caused excessive
unification; proving the connection once with symbolic inputs avoids it.

The connected two-module regression checks distinct function IDs and the final
whole-program equation, alongside existing behavior and rejection tests.
The fresh focused recheck took 2.39 seconds with shared dependencies built;
the connected rebuild/audit took 6.48 seconds. Shared certificate support
refresh took 38.02 seconds separately. All audited assumptions are standard
Lean axioms only.

Maintained growth since the preceding checkpoint is 311 physical lines:
76 shared synthesis/lowering lines, 38 regression lines, and 197 recipe/reload
lines. No Lanius source, runtime language, axiom, or per-function proof-file
family was added. `SelfCore.olean` is unchanged. Temporary diagnostic sources
and artifacts were removed; their logs remain. Several early composition
probes had elaboration errors, so their failures are not valid composition
benchmarks. A corrected saved-input whole check passed in 66.54 seconds, but
the fresh 84.77-second measurement above is the reproducible acceptance timing.

Logs: `self-lowering-fresh-final.log`, `self-lowering-phases.log`,
`self-lowering-reload.log`, `lowering-stage-boundary-{tests,support}.log`,
`lowering-retained-boundary.log`, and `main-string-retention.log` under
`target/verified-compiler`. Next: connect these exact frozen units to all 18
authenticated Surface reconstructions, retaining checked results at that
boundary too. The seven-step goal remains active.

## September 16: retain statement and function lowering proofs

`CoreSynthesis.stmts` now constructs the existing `StmtsLower` derivation as
it constructs Core. It retains expression, annotation, freshness, branch, loop,
and scope evidence instead of discarding it and checking the complete body
again. `function` assembles the original `CheckedFunctionBody` from that result
and the checked signature, removing another complete body traversal. The
authoritative relations, typing check, source boundary, and unsupported cases
are unchanged. Unit-return and fresh-ID rejection checks remain explicit.

Focused kernel-only tests pass in 1.86 seconds with shared dependencies built.
They include 32 nested scopes checked against the original independent lowering
checker, and rejection of missing integer returns, reused local IDs, and
non-Boolean conditions. The connected rebuild took 16.22 seconds; certificate
support refresh and saved Core reload took 36.34 seconds separately. Strict
audits allow only standard Lean axioms.

A fresh native proposal, full kernel typing check, and kernel equality to the
saved 125-function Core candidate pass in 15.06 seconds, peak RSS 2,655,232 KB.
Native synthesis within that diagnostic took 0.194 seconds. This proves the
proposed Core is unchanged, **not** that its source correspondence is certified.
The maintained `SelfCore.olean` was not replaced.

The actual `hex_nibble` source-to-Core equation checks and passes its axiom audit
in 86 ms inside a 1.69-second invocation using saved profiling inputs. Preparing
those inputs took 16.09 seconds separately. The actual `main` synthesis still
hits the sampled memory guard (27.09 seconds, observed peak about 8.7 GiB).
No full-lowering speedup or additional source-unit certificate is claimed.

The profiling also ruled out a source-directed statement-recursion rewrite;
that production experiment was reverted exactly. Early prefix probes contained
a reserved-keyword elaboration error: their apparent millisecond timings are
invalid and discarded. The corrected, audited probe definition instead took
roughly 7–8 seconds per short prefix, including its computed global context;
the multi-prefix diagnostic hit its 55-second cap. Next: separate global-context
lookup cost from expression-depth/repeated-child inference in `main`, rather
than retrying the entire lowering certificate with larger limits.

Net maintained code growth is 17 physical lines: synthesis loses one line and
regressions add 18. No program-specific execution proof family, Lanius source
change, or new axiom was added. Temporary diagnostic recipes/artifacts were
removed; logs remain under `target/verified-compiler`:
`lowering-retained-statements-{build,tests,support}.log`,
`core-retention-identity.log`, `core-retention-identity-phases.log`,
`lowering-{main,hex}-retained-statements.log`, and `lowering-prefix-valid.log`.
The all-unit Surface certificate, closed extractor instance, general x86
preservation, and seven-step goal remain open.

## September 16: kernel-computable lowering; whole lowering still open

The lowering checker and synthesizer now use structural recursion, including
nested statement lists. `GroundTy.toTy` also uses a structural list traversal,
with a general theorem equating it to the former map. Previously even a tiny
function returning `7` succeeded natively but failed kernel reduction.
`checkInferred` reuses existing lowering evidence for matching types and scalar
path casts. Constant and field candidates are selected by their source identity
before entering the existing authoritative checker.

There is now one successful lowering implementation, shared by the diagnostic
source checker and staged synthesis. `sourceBound_of_lowered` proves that exact
source/Surface acceptance, unit decoding, lowering, and typing equations compose
into the original `SourceBound` checker result. These remain proof obligations,
not trusted inputs or a replacement for the complete source-bound certificate.

Nine existing synthesis regressions now use kernel proofs instead of
`native_decide`. New whole-lowering fixtures check actual return values, global
constants, local shadowing, distinct struct receivers sharing a field name,
field mutation, branch allocation, loops, break/continue, and malformed-input
rejection. Strict audits include both stage-composition theorems and the
source-metadata theorem. The final focused build passes in 1.55 seconds, with
shared dependencies built; only standard Lean axioms are allowed. A separate
kernel equality confirmed that the optimized
synthesizer proposed the identical 125-function Core candidate (22.27 seconds,
including quotation and typing, not a fresh source-to-Core proof).

The maintained full Core typing certificate was refreshed: 15.08 seconds fresh,
including proposals, audit, and output; 4.52 seconds for typing/audit; peak RSS
2,657,700 KB. Reload/audit takes 1.19 seconds and is reuse. Shared-support
refresh and saved Surface/encoding audit took 41.02 seconds separately.
This certificate still proves typing/target, not source correspondence.
`AUDIT.md` records the new artifact hash and size.

Full lowering is **not certified**. Preparation alone checked in 5.95 seconds
inside a 19.90-second diagnostic run. The initial whole attempt hit the
115-second command cap after a shared-support rebuild; observed RSS reached
about 16 GiB.
The proof-reuse attempt was stopped at the subsequent 8-GiB sampling guard
(42.71 seconds; observed peak about 8.8 GiB). Quoting and certifying materialized
declaration tables did not fix the growth (52.72 seconds; about 8.9 GiB), so that
experiment and its generated modules were removed. Neither run is a successful
certificate timing. The profile shows substantial kernel term substitution and
cache work. Next: isolate synthesis versus checking for individual actual
functions, then demonstrate a bounded whole check before scaling further.

Physical-line growth since the preceding typing checkpoint is 184: 85 shared
implementation/proof/quotation lines and 99 regression/import lines. This
includes a 27-line reduction in `CoreSynthesis/Program.lean`; duplicate lowering
implementations were removed. No program-specific execution-proof family,
runtime language code, new axioms, or compatibility shim was added. The overall
5x size target, all-unit Surface certificate, closed extractor instance, and
general x86 preservation remain open.

Logs under `target/verified-compiler`: `lowering-final-regressions.log`,
`lowering-final-support.log`, `self-core-identity.log`,
`self-lowering-{prepare,structural,reuse,retained}.log`, and
`lowering-kernel-profile.log`, `self-core-lowering-final.log`, and
`self-core-lowering-load.log`. Failed experimental recipes are not maintained.

## Earlier September 16: full Core typing certificate

`proofs/Core.lean` now saves `SelfCore.olean`, a kernel-checked typing certificate
for the complete 125-function Core candidate proposed from the current
self-extraction. It also proves the x86-64 target and function count. This is
not yet the source-bound Core certificate: the native proposal's correspondence
to the 18 Lanius files is not kernel evidence. Full Surface acceptance, the
source-to-Core equation, the closed extractor execution/resource certificate,
and general x86 semantic preservation remain open.

The previous full typing attempt was stopped after more than 85 seconds in
typing, with about 20 GiB RSS. `CoreTypingChecker` now recurses structurally and
retains each inferred child's proof instead of inferring that child again.
The same dependent typing judgments are returned. The successful initial probe
took 4.32 seconds for typing/audit; the maintained recipe takes 5.08 seconds for
that phase and **15.84 seconds total**, including native proposal preparation,
quotation, strict transitive-axiom audit, and output, with shared dependencies
built. Peak RSS is 2,661,188 KB. Reload/audit takes 2.16 seconds and is reuse,
not fresh checking. Only the three standard Lean axioms are allowed.

Focused tests cover 64 nested casts, rejection without inspecting opaque unused
suffixes, valid/invalid aggregate and match typing, and array/slice loops. The
connected typing/reification/support build passes in 26.90 seconds, including
dependency rebuilds. Refreshing the runner's native dependencies and reloading
the existing Surface certificate takes 40.50 seconds separately. Neither is
included in the fresh-certificate timing. Existing encoding/Surface data hashes
are unchanged. The runner is now named `certify`, without an old-name alias.

Physical code-line accounting: the checker loses 18 lines; shared Core quotation
adds 29; focused tests and their import add 59; generation/reload recipes add
96; runner and saved Surface/encoding audit changes add three. Net growth is
169 lines, including tests and proposal code, not a new program-specific
execution proof family. The temporary probe is removed. Logs in
`target/verified-compiler`: `core-certificate-support.log`,
`core-certificate-surface-reload.log`, `self-core-final.log`,
`self-core-phases.log`, `self-core-load.log`, and
`core-certificate-encoding-surface-audit.log`. Reproduction commands and the
remaining trust boundary are in `BOOTSTRAP.md`.

## September 16: reuse grammar and root indexes in the concrete certificate

The three-unit Surface recipe now uses the authenticated grammar index when
materializing parse-node metadata. `CompactDecode/Indexed.lean` proves that
this produces exactly the reference artifact for every input, including invalid
production IDs. Root validation also uses the existing indexed-root equivalence
instead of walking the flat node list. Neither change weakens the original
checker result, changes the frozen data, or gives the native proposal authority.

A fresh current baseline takes 51.82 seconds. Grammar indexing alone takes
46.59 and 48.35 seconds; the final recipe, including indexed root validation,
takes 46.29 seconds with shared imports and the saved encoding built. This is
a modest improvement, not an exponential drop: the earlier historical result
was 46.80 seconds. On byte-I/O, table authentication falls from 6.89 to 5.56
seconds and parse-acceptance assembly from 2.47 to 1.01. Fused reconstruction
still takes 11.79 seconds, typed tokens 4.60, and claims validation 6.00 in that
run. Those phases are inside the complete invocation, not standalone checks.

The unchanged saved encoding has SHA-256
`3db499f463e13a0a32af11321bff3cde5508909353eb76a3edc331b57889cb4f`.
The new Surface certificate reloads and passes its strict audit in 1.34 seconds;
reuse is not fresh verification. Surface-view and malformed-root regressions,
including the new all-input equality's transitive audit, pass in 1.35 seconds.
The shared-helper build took 18.60 seconds separately, mostly rebuilding
dependencies affected by the preceding contract change. The first integration
attempt failed code generation because the proof-only artifact helper lacked
`noncomputable`; it is not a successful certificate benchmark.

Growth is 23 physical code/test lines: 18 shared, four in the recipe, and one
test import. The runner registers the shared dependency without adding a line.
No new program-specific execution proof or runtime language code was added.
This still certifies only three of 18 units. Whole-pack Surface/Core, the saved
source-checker/execution certificate, and general x86 preservation remain open.
Logs under `target/verified-compiler`: `self-surface-september16-baseline.log`,
`self-surface-indexed-{final,repeat,root-final,load}.log`,
`indexed-decode-build.log`, and `indexed-artifact-tests.log`.

## September 16: compact total function contracts

`CallContracts/CellSpec.lean` packages finite call execution, the return value,
storage pre/postconditions, permitted cell writes, and caller/heap preservation.
Argument effects end at the contract's initial state. It covers Core cell
operations, not host I/O or raw-heap mutation. `Source/Call.lean` connects this
contract to the actual source-checked function and proves pure-call setup once.

Six contracts now use it: byte success/rejection, digit conversion, and the
hex-byte, word, and byte-array rejection cases. Internal callers use the shared
`.call` rule; the old `callPure` interface is removed. The byte rejection
statement is three lines and its proof three lines. Termination, source identity,
and both memory frames remain required. The three serializer rejection contracts
now also retain their previously discarded raw-heap frame.

The connected byte/hex, word, byte-array, and text checks passed in 12.73 seconds,
including affected dependency rebuilds. A regression theorem derives the whole
old byte rejection statement. Tests also cover effectful argument evaluation
and refusal to omit a required precondition. Transitive axiom audits pass with
only standard Lean axioms. Fresh module checks, with shared imports built, take
2.51 seconds for Byte and 1.24 seconds for Digit; these are not whole-extractor
timings or evidence of a material speedup over the previous checkpoint.

Physical-line accounting from this turn's initial worktree: program proofs and
their callers lose 18 lines; shared infrastructure adds 35; tests add 29. Net
growth is 46 code lines, excluding this note. The byte/digit modules still total
129 lines before source-shape definitions and shared foundations. The overall
5x target, concrete self-certificate, and general x86 preservation remain open.
Logs: `cell-spec-tests.log`, `cell-spec-final-tests.log`, and
`{byte,digit}-cell-spec-fresh.log` under `target/verified-compiler`.

## September 13: compact, finite-execution proofs

`Automation/Execute.lean` now applies structural Core execution rules, reuses
supplied call/store/loop proofs, and discharges scalar arithmetic without
unfolding the whole evaluator. `Source/Call.lean` proves parameter binding and
caller-frame restoration once for pure checked bodies. This uses the existing
finite `Evaluates`/`Executes` relations, not the partial `SemanticWP` judgment.

The production `CheckedByte.reject` proof is three lines; `digit_body` is two.
Byte guards, token/assignment size guards, and node validation use one-line
automation. The byte success proof reuses its existing verified slice-store
step. Byte, digit, hex, word, byte-array, text, token, assignment, and node
proofs keep their pre-existing statements and source connections unchanged.

Compared with the worktree at the start of this change, nine program-specific
modules lose 182 physical lines. The two shared modules add 188 lines; the
regression module and its import add 51. Net code growth is therefore 57 lines,
including tests, not counting this checkpoint. Counts include comments and
blank lines. The complete byte/digit modules still total 134 lines before their
source-shape definitions and shared foundations: the overall 5x size target is
not yet met. This replaces a repeated proof pattern; it does not hide its cost.

With shared imports built, fresh checks take 2.62 seconds for Byte and 1.27
seconds for Digit. Byte's instrumented profile reports 44.4 ms of type checking;
tactic simplification, not kernel checking, dominates its proof work. Profile
categories overlap and must not be summed. Prefer the general pure Boolean rule
before short-circuit fallback to avoid repeated traversal of nested guards.

The connected output regression/axiom suite passes in 29.79 seconds, including
affected dependency rebuilds. It covers the complete serializer call proofs
and rejects nonstandard transitive axioms. New regression checks cover skipped
branches, finite returns, actual signed overflow, and refusal of wrong results
or unsupported infinite-loop claims. Logs are `output-automation-final.log`,
`byte-automation-final.log`, `digit-automation-final.log`, and
`byte-automation-profile-final.log` in `target/verified-compiler`.

This closes the compact-execution automation step, not milestone 3.9. The full
self-certificate and general x86 preservation remain open. No Lanius source,
artifact format, native trust boundary, or existing certificate changed.

## September 13: typed encoding certificate accepted

The complete 18-unit encoding/source-binding certificate now checks in **58.52
seconds**, down from 75.51, with shared imports already built. Peak RSS falls
from 9,830,612 to 6,814,944 KB. The unchanged three-unit Surface recipe passes
against it in **46.80 seconds** versus 47.56, with 4,141,604 KB peak RSS. This
improves the connected workflow without shifting the saved work downstream.
These are fresh certificate checks, not cold shared-infrastructure builds;
neither closes milestone 3.9 or establishes seconds-level whole-pack checking.

`CompactDecode/Bounded.lean` carries scalar bounds in `UInt32`, `TokenKind`, and
`Fin` fields. Generic lemmas prove encodability of those fields once; the
concrete check still establishes collection lengths, assignment counts, and
nonempty units. `Unit.data` maps to the existing representation. The serializer,
public decoder, exact ordered source binding, and Surface acceptance statements
are unchanged. Native conversion rejects out-of-range values and remains only
a proposal. No new axiom or native proof dependency is admitted.

The bounds/decoder phase falls from 37.18 to **21.13 seconds**. Other phases are
6.40 seconds for proposal preparation, 14.26 for quotation, 1.00 for independent
source quotation, and 4.80 for source binding/audit; startup/output account for
the remainder. Quoting a production's `Fin` at its normalized numeric bound
initially made quotation exceed its short probe cutoff. Keeping the symbolic
grammar bound in the constructor type avoids that repeated grammar reduction.

A connected byte-I/O probe proves equality with the old frozen unit, the
existing node-cache equation, and token acceptance. Its complete invocation
takes 23.53 seconds. Bounds fall from 2.31 to 0.95 seconds, while cache
authentication rises from 4.46 to 5.64; this is why the complete downstream
measurement above, rather than the isolated bounds result, determined adoption.
The earlier node-only variant took 72.65 seconds for all 18 units and was
superseded by the all-scalar representation. Temporary probe code was removed.

Focused boundary, malformed-count, public decoder round-trip, and strict
transitive-axiom tests pass in 1.36 seconds with imports built. The first typed
module/test build took 2.36 seconds separately. The new tests are imported by
`Tests.Self`, but that complete closure was not rerun. Growth is **208 code/config
lines**: 135 shared proof/representation lines, 49 tests, 22 net recipe lines,
and two test/runner registration lines. The recipe is now 132 lines. No Lanius,
Rust, Python, Wasm, or new program-specific execution cases were added; the
existing large semantic proof bodies remain above the size target.

Current artifact hashes, reload measurements, and commands are in `AUDIT.md`
and `BOOTSTRAP.md`. Logs are `bounded-{data-tests,final-tests,probe-scalars}.log`,
`self-encoding-bounded{,-reload}.log`, and `self-surface-bounded{,-load}.log`
under `target/verified-compiler`. Next: profile the remaining 21-second collection
check and the representative Surface reconstruction/claims checks before
expanding beyond three units. Whole-pack Surface/Core, the retained original
source-checker equation, concrete execution/resource evidence, and general x86
preservation remain open. Older timings below are checkpoint history.

September 16 follow-up: retaining each node's child-list length in its type did
not improve the complete certificate. A `Vector` representation reduced the
bounds phase to 12.93 seconds but raised quotation to 37.26; total time was
80.02 seconds. A length-indexed inductive list took 64.36 seconds (25.38 quoting,
13.60 bounds). Both passed their proof/axiom checks, but both were removed.
The restored implementation checks all 18 units in 59.54 seconds and reproduces
the accepted `SelfEncoding.olean` hash above. No experimental representation,
test, or recipe code remains. Logs are `self-encoding-{children,indexed-children,
restored}.log` and `children-restored-{tests,surface-audit}.log`. Do not repeat
these approaches on the strength of their isolated bounds timings: quotation
cost is part of verification cost.

Grammar specialization also failed the complete-check performance gate. A
preclassified symbol table took 45.98 seconds and prebuilt per-rule checking
functions took 46.21, versus the accepted 46.29-second Surface result. Both
proved equality with the original checker for all inputs, including malformed
symbols/children/stacks, and passed strict axiom audits. Neither demonstrated
enough improvement to retain its added infrastructure. Their shared code,
tests, API migrations, and generated candidate certificate were removed; the
original interfaces and saved certificate are restored. Logs are
`self-surface-specialized{,-functions}.log`, `specialized-{grammar,functions}-tests.log`,
and `specialization-restored-{tests,audit}.log` under `target/verified-compiler`.

## Current acceptance: whole-extractor trust is kernel-only

Milestone 3.7 is complete. The refreshed `Entry.checkSource` has zero
nonstandard axioms, including `checkExtractorCoreSourcePack` and `checkExecution`.
The actual unit emitter, whole-main execution, and observations are kernel-only
too. Strict audits in `Tests.Provenance`, `Tests.Output`, and `Tests.Self` replace
inherited-assumption allowances. This validates the combined earlier cleanups;
it does not remove another 173 assumptions in this turn. No Lanius implementation
or program-specific semantic proof was added, and the size problem remains open.

The remaining `Entry.Source` dependencies rebuilt in 77.50 seconds; this is
incremental with the frontend/shared imports already built. The strict tests
and self-driver rebuild took 9.16 seconds. The exact current self-instance first
passed executable validation and all regressions in 87.91 seconds, including
37.78 seconds for parser/tree resources and 19.04 seconds for three source-mutation
checks. These IO results are not persisted kernel proofs. Logs are
`entry-source-current-build.log`, `entry-trust-current.log`,
`entry-strict-audit-build.log`, and `self-source-current-validation.log` in
`target/verified-compiler`. The current source/embedding identity and remaining
certificate requirement are recorded in `MILESTONE3.md`.

The CPU profile identified interpreter dispatch, not kernel checking, as the
dominant executable-validation cost. General parser workspace arithmetic had
accidentally imported the concrete parser through four source-execution lemmas.
Their actual contents now live at the source-proof boundary; all declarations
are unchanged and there are no compatibility stubs. The native resource closure
shrinks from 74 local modules / 71.81 MB of generated C to 30 / 16.33 MB.

The same resource checker, compiled natively, takes 1.18 seconds instead of
37.78 seconds (about 32 times faster). The complete identical self-validation
and regression driver takes 44.36 seconds instead of 87.91 seconds. The new
`lake -d formal run check-self` command builds and loads the required native
dependencies; it does not create a kernel certificate or add native proof
assumptions. The native helper build took 19.85 seconds separately. Rebuilding
dependent proofs after the import split hit the 119-second cutoff; the
incremental finish took 62.78 seconds. Neither is a fresh-check speedup.
The final strict audit/dependency guard rebuild passed in 2.94 seconds with
imports built. Logs are `self-source-{current-profiled,lake-native}.log`,
`parser-resource-native-build.log`, `parser-workspace-integration.log`, and
`entry-resource-final-audit.log`. Reproduction is in `BOOTSTRAP.md`.

The workspace move adds four header lines and nine import lines; replacing
the ten-line Lake configuration with its 52-line script adds 42. The strict
audit and dependency-guard edits remove five net test lines. Total code/config
growth is 50 lines, with no new semantic proof cases or Lanius source changes.
This does not resolve the existing program-specific proof-size problem.

### Concrete kernel-certificate investigation

The missing certificate is still `Entry.CheckedSource selfEncoded selfSources`,
with independently bound source bytes and the retained source-checker result.
Direct reduction of the current 7,966,372-byte payload exceeded the elaborator's
recursion limit in 2.80 seconds. A first-word kernel-check command reached its
29-second cutoff. Neither is a successful concrete certificate.

`CompactDecode/RoundTrip.lean` now connects the existing serializer/reader proofs
to the public `decodeCompactArtifactPack?`: all encodable, nonempty packs decode
to their original structured data. The complete new module checks in 1.37
seconds with imports built. Its kernel/native regression tests cover ordered
units, UTF-8 paths, empty files, arbitrary source bytes, and split token kinds;
the strict transitive axiom audit passes in a 1.36-second focused build.

The actual 18-source quotation probe exposed unnecessary native code generation
for proof-only data. `quoteBounded` can now omit code generation while retaining
all kernel declaration checks. Both modes pass exact-value proofs and the
default mode's executable test (1.35 seconds). On the complete self-pack, the
untrusted decode/proposal took 6.55 seconds and proof-only quotation took 16.35
seconds. These are preparation costs, not acceptance of the concrete result.
The subsequent rendered-data/literal equality still hit the 59-second whole
probe cutoff. An isolated kernel equality joining both halves of the same full
8 MB literal also hit 29 seconds. Do not retry this representation by increasing
limits or dividing it into separately reported checks.

This follow-up adds 44 lines of shared round-trip proof, two net quotation-helper
lines, 95 focused test lines, and two test imports: 143 net code lines. It adds
no program-specific semantic proof cases, Lanius source changes, or trust
assumptions. The existing program-specific proof-size problem is unchanged.
Evidence is in `kernel-self-roundtrip-build.log`, `kernel-roundtrip-tests.log`,
`proof-only-quotation-tests.log`, `kernel-self-roundtrip-proof-only.log`, and
`kernel-self-string-join.log` under `target/verified-compiler`.
The connected `Tests.Self` dependency rebuild reached the 119-second cutoff
without reported errors (`kernel-certificate-connected-build.log`). It remains
incomplete; the focused green checks are not a fresh whole-closure build. The
unchanged large-literal proof attempts were not retried with higher limits.

### Saved encoding and source-binding certificate

`proofs/Encoding.lean` now saves `SelfEncoding.olean` for the current 18-source
candidate. Its `encodable`, `decoded`, and `source_bound` theorems authenticate
the complete compact representation and the exact ordered source paths/bytes
read independently from disk. The strict transitive audit finds zero
nonstandard axioms. This is a partial concrete certificate, not the final
`Entry.CheckedSource`: Surface/Core acceptance, the retained source-checker
equation, execution evidence, and self-input resource evidence remain open.

The structured data is the embedding, as in the original quotation workflow.
The bootstrap only proposes it. The public decoder round trip uses its canonical
rendering; there is no kernel theorem equating that rendering to the bootstrap's
8 MB transport literal. No source, syntax, Core, or execution obligation is waived.

The complete fresh invocation, including quotation, proof checking, the axiom
audit, and `.olean` output, passes in **75.51 seconds**, with shared imports built
and 9,830,612 KB peak RSS. The candidate has 106,203 source bytes, 28,286 raw
tokens, 18,446 canonical tokens, and 125,835 parse nodes. Phase measurements:
15.87 seconds for structured quotation, 37.18 for bounds/decoder proof, 1.08
for independent source quotation, and 3.54 for source binding plus final audit.
Preparation, startup, and output account for the remainder. Importing and
auditing the saved certificate takes 0.98 seconds; that is reuse, not a fresh check.

Two failed source-binding routes reached the 119-second cutoff. Retaining
`ByteArray` inputs avoids expanding their natural-byte conversion. Exact
environment-local sharing in proof-only quotation then removes the duplicated
constructor chains that made reflexivity exceed its recursion limit. The
normal executable quotation path is unchanged. Primitive Boolean bounds checks
replace proof-producing numeric decisions, with all-input equivalence proofs.
A per-unit proof-generation experiment lowered memory but slowed bounds checking
from about 37 to 55 seconds; it was removed, not retained as another proof path.

This checkpoint adds 260 net code lines over the preceding checkpoint: 130
shared validation/continuation lines, 12 net quotation-helper lines, 110 lines
of concrete quotation/proof glue, and eight net test lines. It adds no Lanius
source changes or program-specific execution cases. The existing large semantic
proof bodies remain a size problem. Focused quotation/round-trip tests and strict
audits pass in 3.15 seconds with their other imports built. Logs are
`self-encoding-{certificate,phases,load}.log` and `shared-quotation-tests.log` in
`target/verified-compiler`; reproduction is in `BOOTSTRAP.md`.

### Saved representative Surface certificate

`proofs/Surface.lean` saves `SelfSurface.olean` for three units of the frozen
source-bound candidate. Each has an exact `reference_accepted` equation and an
`original_accepted` theorem for `checkSurfaceArtifact? unit.artifact`, plus a
checked source-path equation. No acceptance premise or native proof authority
is substituted for those obligations.

| Unit | Lanius lines | Bytes | Canonical tokens | Parse nodes |
| --- | ---: | ---: | ---: | ---: |
| host | 33 | 1,427 | 234 | 583 |
| token_scan | 45 | 1,037 | 165 | 651 |
| byte_io | 122 | 4,127 | 789 | 5,129 |

The latest complete fresh three-unit invocation takes **47.56 seconds**
(previous repeat: 47.52), down from 53.15, including
proposal generation, kernel checking, strict audits, and output; peak RSS is
4,105,848 KB. It reuses the saved encoding certificate and built shared imports.
The artifact is 5,037,496 bytes, SHA-256
`0bc268f9b8450f415a4b9956533c58a2d9bb76b6572e7f0cda432685d7b8ad46`.
The runner reloads, audits, and writes the load-test artifact in **1.26
seconds**. That is reuse, not a fresh check. The original 18-source encoding
certificate is unchanged; this is not whole-pack Surface or Core acceptance.

The typed-token check now reuses the existing token-row and byte-decoder
lemmas. On a saved host fixture its token phase takes 1.38 seconds versus 1.95
for the original computation. Existing validated reconstruction supplies both
node and reconstruction evidence in one pass. A native build of the existing
compact reader cuts untrusted proposal time from roughly six seconds to below
one; it does not prove anything. Reader native preparation took 0.89 seconds
separately with its other dependencies built.

The recipe authenticates cached tables with exact equations and then uses
those tables directly. The grammar table uses the existing sequence tree and
has an all-index equality theorem, including invalid indices. Node predicates
use primitive Boolean checks, with all-input reference equivalence. Rebuilding
this connected path exposed missing transport cases for generic parameters and
extern functions; both are now proved. That dependency rebuild took 7.50 seconds.
The runner now rebuilds the relevant shared modules before loading a recipe.

Profiling still identifies a scaling problem. The byte-I/O unit takes about
33.55 seconds inside the 47.52-second invocation: 5.16 authenticating tables,
4.54 checking tokens, 12.59 validating/linking/reconstructing nodes, and 6.42
checking claims. A separate token-phase probe attributes 2.94 seconds to the raw
lexer trace and 1.62 to canonical tokens. These are phase measurements, not
standalone fresh-check times.
An earlier standalone version took 42.89 seconds. Retaining unevaluated node
expressions made table authentication faster but shifted cost downstream; that
variant is not the production recipe. No exponential speedup or whole-pack
seconds-level claim is justified.

One 201-line recipe replaces the former 148-line host-only file; no compatibility
stub or per-unit copy remains. The reload/contract test adds 17 lines. Together
these are about 1.1x the 200 Lanius lines in the matching representative scope;
shared helpers are counted separately below, not hidden in that ratio. Existing
large program-specific semantic proof bodies remain unchanged and above target.

The current follow-up adds 327 net code/config lines: 207 for the shared path
checker and its proofs, nine for recipe integration, one runner line, and 110
test lines. The preceding Surface checkpoint added 301, so cumulative growth
across both is 628 lines. No Rust, Python, Wasm, or Lanius source was added.

`Surface/Paths.lean` now checks existing provenance-path proposals and derives
the exact original containment/claims checker result. It checks path lengths,
endpoints, child slots, pruning guards, spelling, and witness counts. Parent
tables only propose paths; they have no proof authority. In particular, ordinary
reachability alone would not establish acceptance of the original pruned search.
This integration passed in 46.72 and 46.59 seconds before the scanner change below.

The numeric scanner's length-based termination encoding forced evaluation of
an unused suffix. Structural recursion removes that cost while preserving the
existing general correctness proof. Focused reductions with 512 and 4,096 unused
bytes fell from 41/226 ms to 20/21 ms. A regression with an opaque suffix checks
this reduction property without relying on timing. The latest whole-certificate
run is 47.52 seconds: this scanner fix has **not** demonstrated a further overall
speedup. The affected shared dependency rebuild took 63.94 seconds separately.

Focused typed-token mutations, opaque-element quotation, tree boundaries,
all-input node equivalence, and strict transitive audits pass. The final node
reference tests take 1.41 seconds; the other focused checks take 1.27 seconds,
with their dependencies built. Logs are `self-surface-{certificate,phases,load}.log`,
`surface-fastpath-tests.log`, `primitive-node-tests.log`, and
`shared-grammar-build.log` under `target/verified-compiler`.
The full `Tests.Self` closure was not rerun at this checkpoint.

The path checker and its mutation/fuel/pruning tests build in 2.36 seconds;
scanner/compact regressions and strict audits pass in 6.08 seconds, including
their affected dependencies. Latest logs are `self-surface-structural-scanner.log`,
`self-surface-paths-load.log`, `surface-paths-tests.log`,
`structural-scanner-tests.log`, `digit-tail-{reduction,structural-reduction,support-build}.log`,
and `unit-token-profile.log` under `target/verified-compiler`.

The word-bounded representation experiment is completed in the current checkpoint
above. Its original plan was to test the compact certificate's fields,
so generic type lemmas can discharge scalar bounds instead of checking each
field again. Measure quotation, proof checking, and downstream consumption
together before adoption. Do not scale the current costs across all 125,835
nodes unchanged. Then connect whole-pack Surface/Core
acceptance to the retained source-checker equation and execution certificate.
Milestone 3.9 and general Lanius-to-x86 preservation remain open; the seven-step
objective is unchanged. Older inventory notes below are historical.

### September 13 reconstruction investigation

The connected byte-I/O diagnostic now separates these overlapping computations:

| Computation | Kernel-check phase |
| --- | ---: |
| Link the forest, without grammar validation | 2.22 s |
| Link and validate grammar nodes | 5.57 s |
| Link and reconstruct exact Surface, without grammar validation | 6.90 s |
| Fused pass, checking only successful return | 10.72 s |
| Fused pass, checking the exact Surface result | 10.75 s |

The complete diagnostic invocation takes 37.06 seconds and 4,037,540 KB peak RSS.
It imports frozen data and authenticated views; it is not a fresh source check.
The near-equal last two phases locate the cost in computation, not final output
comparison. CPU samples show substantial expression-cache lookup, allocation,
and reference-counting work. The pinned [Lean kernel implementation](https://github.com/leanprover/lean4/blob/v4.33.1/src/kernel/type_checker.cpp)
also confirms that closed Boolean reflection reduces the computation in the kernel.

An explicit linking recursor, raw tree references without proof fields, and
proof-producing `cbv` did not demonstrate a speedup. `cbv` hit a nine-second
cutoff on the smaller host unit; that is a failed experiment, not acceptance.
Retaining a quoted, authenticated forest passed the exact three-unit certificate
in 55.68 seconds with 3,020,528 KB peak RSS: lower memory, but no demonstrated
speedup over the 47.52-second baseline. Its all-input bridge and focused fixture
passed too. The slower production trial and its unused helpers/tests were then
removed, not retained as another proof path. A primitive-child probe had code
generation errors; its printed reduction timing is not an accepted benchmark.

`proofs/ProfileSurface.lean` retains the 27-line diagnostic recipe; no new
semantic proof or production helper remains from these experiments. Logs are
`reconstruction-profile.log`, `fused-perf.log`, `recursor-probe.log`,
`raw-tree-probe.log`, `retained-tree-probe.log`, `cbv-probe.log`,
`self-surface-retained-forest.log`, and `reconstruction-restored-build.log`.
The restored shared module and strict Surface tests rebuild in 2.27 seconds.
The restored whole three-unit certificate then passes in 47.56 seconds with
4,105,848 KB peak RSS; its hash and size exactly match the pre-experiment
artifact. Reload and strict audit pass in 1.26 seconds. Logs are
`self-surface-restored.log` and `self-surface-restored-load.log`. No new
transitive assumption or change to the accepted theorem remains.
This turn changes the evidence and next action, not milestone acceptance:
whole-pack Surface/Core, `Entry.CheckedSource`, and general x86 preservation
remain open. The encoding certificate's then-37.18-second bounds phase was the
next target; the subsequent typed-representation result is recorded above.

## September 12 proof-architecture checkpoint

The Lean skill's size warning takes priority over adding more backend cases.
The first reduction keeps the parser state proof's actual source connection
and seven branch-shape statements unchanged. It replaces 681 lines of bespoke
shape checks and proofs with 77 lines using the existing sound matcher,
counting comments and internal blank lines in both sets of sections.
No new automation layer or generated proof files were added. Two unused whole-loop
reifications were removed; the consumed loop-to-Core proofs still derive from
their checked bodies. The complete state module shrank from 8,545 to 7,907 lines.

Fresh checks of that complete module, with imports already built, took 32.33
seconds before and 24.85 seconds after. The profiler's type-checking bucket fell
from 15 to 13.5 seconds; its tactic bucket fell from 10.5 to 7.07 seconds. These
buckets overlap and must not be added. Rebuilding the affected parser dependencies
after the accompanying trust cleanup took 81.79 seconds separately. Logs are
`target/verified-compiler/lean-compact-{before,final,clean-trust}.log`.
The stricter axiom-audit module passed in 2.14 seconds with its imports built
(`lean-compact-audit.log`); that is not the time to recheck the parser proofs.

The audit also exposed and removed ten native-generated assumptions in six
existing constant, function-ID, and negative-sentinel declarations. The checked
state-body, incomplete-branch, scan-miss, terminal-success/full, and cursor-advance
consumers now use only standard Lean axioms. See [milestone 3](MILESTONE3.md) for
the remaining trust boundary. This is a measured reduction, not evidence that
the overall proof-to-code ratio is acceptable: the state module alone is still
larger than the entire 463-line Lanius parser, and its imported proofs add more.
The next architecture work must address repeated semantic/environment bookkeeping
before scaling another family of compiler cases. Milestones 3–7 remain open.

### Semantic proof follow-up

The read-only, effectful, and stateful term-machine wrappers are now transparent
abbreviations. Their fixed `World` type is visible at Lean's restricted rewrite
transparency, so the existing call-free transfer theorem can be applied directly.
Previously, rewriting failed to recognize the same world type behind the wrappers.
The evaluator bodies and theorem statements are unchanged. The existing
`functional_eval` tactic also gained the missing natural-number i32 `≤` rule,
derived from its signed-integer rule.

Nine arithmetic, indexed-read, environment-preservation, and result-projection
proof bodies shrank from 208 lines to 23. The complete state module is now 7,722
lines, down another 185. Shared support grew by ten net lines, including removal
of three now-redundant proof steps; the axiom audit gained five lines. This is
reuse of existing semantic rules, not generated proof expansion or weaker input
conditions. The audited consumers and the new rule use only standard Lean axioms.

A fresh complete state-module check with imports built passed in 22.93 seconds
(`target/verified-compiler/lean-semantic-measured.log`), versus 24.85 before this
follow-up. The profiler's type-checking bucket was 11.6 seconds and its tactic
bucket 8.13 seconds; these overlap. The successful affected dependency/reification
check took 75.89 seconds after diagnostic rebuilds, so it is not a cold-build
measurement. The expanded axiom audit passed in 2.04 seconds with imports built.
The actual recognizer caller path also rebuilt successfully in 26.06 seconds
after removing one newly redundant proof step in the position driver
(`lean-semantic-caller.log`). This is an incremental integration check, not a
fresh measurement of the entire recognizer closure.
This improves a connected example; it does not close the overall size or latency
gap or establish whole-compiler correctness.

### Scoped bindings and call arguments

Eight existing proof bodies now use scope constructors, source-call contracts,
and argument-list automation directly: 578 lines became 156, with every theorem
statement unchanged. The state module shrank from 7,722 to 7,300 lines. Shared
support grew by 33 lines and tests/audits by 14; no Lanius code or generated proof
files were added. The call rule exposes arguments to inference before unfolding
the dispatcher. The evaluator tactic reuses constant-table evidence and separates
list/reference goals from arithmetic side conditions. A symbolic-argument
regression proof and the expanded standard-axiom audit pass.
The module alone is still 15.8 times the entire 463-line Lanius parser; imported
program-specific proofs add more, so this does not meet the overall size target.

This is a size improvement, not a demonstrated overall speedup. The final fresh
state-module check took 26.66 seconds with imports built; a control using the old
proof bodies during this turn took 25.59 seconds. Initial automation variants
took 26.69 and 27.42 seconds. The final profiler reports 13.3 seconds in type
checking and 9.23 in tactic execution; these buckets overlap. Logs are
`target/verified-compiler/lean-scoped-{control,final-measured}.log`.

The combined dependency, audit, and caller rebuild hit the 119-second cutoff
after the state module, its audit, and both loop continuations passed. The final
setup/caller modules did not finish, so integration is not accepted for this
checkpoint. See `lean-scoped-integration.log`. Do not present a retry using those
warmed dependencies as a fresh sub-two-minute check. The full proof-to-code ratio,
connected rebuild cost, and milestones 3.7/3.9 remain open.
The lexer and decimal consumers of the shared tactic also rebuilt successfully
in 14.95 seconds (`lean-scoped-other-consumers.log`); this is an incremental
regression check, not a new whole-frontend performance measurement.

### Reuse child typing evidence

The shared expression reifier composes already-checked child typing witnesses
for casts, operators, calls, struct construction, indexing, and field reads.
It no longer runs `inferExpr` over these subtrees again at the parent.
`ReifiedTerms` now retains list typing evidence, so calls and structs need only
check expected types and arity. The read-only statement reifier also composes
sequence, binding, conditional, and return witnesses; stateful returns reuse
their value witness. Stateful mutation checks still have duplicate work.
The returned views retain both Core typing and an exact source round trip.

The scalar-only change left the shared file's size unchanged. This follow-up
changes the shared reifier from 346 to 373 lines and the stateful reifier from
196 to 194. Tests grow from 120 to 188 lines, adding 34 accepted/rejected
aggregate, index, field, and block cases checked against the independent Core
checker. The generic reifiers and the connected parser consumers pass the
standard-axiom audits. No Lanius source, generated proof files, or program-specific
helper lemmas were added; the state module remains 7,300 lines. The overall
proof-size target is still unmet.

Fresh full state-module checks with imports built measured 26.66 seconds before
scalar proof reuse, 24.37 after it, and 23.18 after this follow-up. The latest
type-checking bucket is 11 seconds and tactic execution 8.55 seconds; these
buckets overlap. This is a modest measured improvement, not seconds-scale
whole-compiler acceptance. See `lean-reification-subtrees-measured.log` under
`target/verified-compiler`.
An experiment materializing the entire dependent reification record took 48.52
seconds and was removed completely; no proof-record cache from it remains.

The latest connected recognizer caller and audits pass in 108.01 seconds after
focused reifier builds; this is an incremental integration check, not a fresh
whole-closure performance claim (`lean-reification-subtrees-connected.log`).
The focused reifier tests and transitive axiom audit pass in 6.04 seconds
(`lean-reification-subtrees-tests.log`). Lexer, decimal, raw-lexer result, and
token-scan consumers pass an incremental rebuild in 5.14 seconds
(`lean-reification-subtrees-consumers.log`). The earlier root cleanup replaced all
nine `native_decide` sites in `Root/Commands.lean` with kernel proofs, preserving
their statements; all nine owners remain in the passing transitive audit.
Milestones 3.7 and 3.9 remain open. The stale whole-extractor assumption inventory
has not been refreshed, and the concrete kernel-only self-instance is still open.

### Ownership-preserving state bindings

`RecognizerStateLoopInvariant.bind_candidate_fields` now retains the existing
ownership witness through each read and temporary binding. It derives local
reads from that witness instead of maintaining a second proof chain. Its body
shrinks from 292 to 116 lines. The parent-entry proof reuses the general
persistent-local separation invariant, leaving only the fresh LHS and cursor
cases separate; its body shrinks from 264 to 234 lines. Both declaration headers
and complete execution/ownership result types are unchanged. No helper framework,
source rewrite, or generated proof code was added.

Two accessor constant-table proofs now use direct kernel equalities, removing
another 26 lines. Three root-selection native-decision sites now use kernel
proofs. The five removed sites have five audited owners; the actual candidate
binding and parent-entry proofs also pass the standard-axiom audit. The former
previously inherited a native assumption from `verifiedParser_accessor_constants`.
The state module is now 7,094 lines, versus the entire 463-line Lanius parser:
15.3 times the source even before counting its imported program-specific proofs.
This checkpoint removes 232 program-specific lines and adds five audit lines;
the overall size target remains unmet.

Fresh complete state-module checking with imports built takes 23.01 seconds,
essentially unchanged from 23.18. Type checking reports 11.3 seconds and tactic
execution 8.44 seconds; these buckets overlap. See `lean-ownership-final-measured.log`.
The connected caller and expanded audit pass in 71.98 seconds after dependency
and diagnostic builds (`lean-ownership-integration.log`); this is not a fresh
whole-closure timing. No trust policy changed. The whole-extractor inventory,
concrete self-instance kernel acceptance, and compiler milestones 3–7 remain open.

### Kernel-only recognizer caller

The actual `executeRecognitionRegion` construction now depends only on
`propext`, `Classical.choice`, and `Quot.sound`, down from 23 inherited native
assumptions. Its grammar, integer-bound, buffer-ownership, and separation
preconditions are unchanged. Its `RecognizerCallExecution` result still carries
the extracted call's evaluation, semantic outcome, workspace growth/artifact,
write footprint, and well-formedness preservation. This closes the native-trust
dependency of that recognizer caller, not the whole extractor or all input domains.

The initial loop is assembled from its checked body. The enclosing continuation
composes that loop with the already-checked position/root command, using the
existing scoped-renaming theorem. New exact source equalities for the loop and
continuation replace the two removed whole-subtree reifications; no source
connection is assumed. The strict metadata audit now includes those equalities
and the actual caller construction. Other remaining decisions in initial-loop,
prediction, terminal-scan, and call-support proofs now use the kernel. Constant
lookups use direct equalities. Across six affected modules, all 26 native-decision
sites are gone; 23 assumptions from these sites reached the caller.

Program-specific code shrinks by 28 lines, including the new source-equality
proofs; the existing audit grows by five lines. The initial-loop module remains
1,524 lines and the state module 7,094, so the overall proof-size problem remains.
A fresh complete initial-loop check takes 3.14 seconds with imports built
(`recognizer-initial-kernel-measured.log`). This is not a whole-parser timing or
a like-for-like speedup against the previous native-based proof. The connected
caller/audit rebuild passes in 15.44 seconds after dependency/debug builds
(`recognizer-kernel-audit.log`). The before/after transitive inventories are
`parser-trust-{before,after}.log` under `target/verified-compiler`.

The whole `Entry.Source` target is still out of date, confirmed without building
it (`entry-source-freshness.log`). Its old 173-assumption inventory cannot be
reported as current. Remaining lexer/extractor trust dependencies and the
concrete self-instance kernel acceptance still block milestone 3 acceptance.

### Kernel-only scanner calls and symbolic byte classification

The complete lexer `framePreservingCallSoundness` and number-scanner
`numberFramePreservingCallSoundness` now use only standard Lean axioms. Their
previous transitive inventories contained 18 and 20 native assumptions,
respectively. The call contracts still connect the extracted bodies to their
success/failure results and frame guarantees. The strict audit now checks all
dependencies of 57 constructors, routes, source projections, and evaluation
lemmas; it no longer exempts inherited assumptions or grants local budgets.
Across the affected modules, 61 native-decision sites were replaced by kernel
proofs; 38 of those assumptions reached these two call constructors.

Exhaustively running the byte predicates for all 256 inputs was the remaining
leaf bottleneck. Five proofs now evaluate an arbitrary byte symbolically. They
materialize only source-checked block data, retain the dialect signature, and
use existing primitive evaluation rules plus one general conditional rule.
The unary views expose arity one while retaining the actual parameter context
and exact source-body check. Conditional proofs pass the unchanged world
explicitly, so later branch proofs need not determine it for earlier goals.
No correctness statement, supported-input domain, or trust policy was weakened.

A fresh complete predicate-module check with imports built fell from 17.27 to
5.66 seconds; the profiler's type-checking bucket fell from 16.4 to 1.27 seconds.
The final tactic bucket is 5.63 seconds; these buckets overlap. Logs are
`scanner-predicates-kernel-enumerated.log` and
`scanner-predicates-final-measured.log` under `target/verified-compiler`.
The connected scanner rebuild after the shared conditional rule passed in
55.78 seconds, separately from focused/debug builds (`scanner-symbolic-connected.log`).
The final compact proofs and 57-declaration audit pass a subsequent incremental
check in 9.64 seconds (`scanner-final-connected.log`). Neither is a fresh
whole-extractor timing.

Program-specific code grows by 13 net lines, including removal of 37 obsolete
proof steps exposed by the earlier evaluator changes. Shared rules grow by 14
lines; the stronger audit shrinks by 75, for 48 fewer total lines. This does not
solve the proof-size problem: the three scanner proof folders alone contain
20,046 lines against 497 lines in the five corresponding Lanius units, about
40 times the source before counting imported program-specific support. The next
architecture work must reduce repeated proof bookkeeping, not expand this ratio.
Whole-extractor trust inventory, concrete kernel self-acceptance, and milestones
3–7 remain open.

### Kernel-only linked raw lexer

`RawLexer.LexInto.Linked.call_evaluates_at` and the frontend's `lex_then_count`
now use only `propext`, `Classical.choice`, and `Quot.sound`. All 12 native
assumptions previously inherited by the linked raw-lexer call are gone. The
contract still executes the actual extracted function at arbitrary distinct
source/output cells, produces the exact token-record prefix, preserves spare
words, and limits writes to the output cell. Success, lexical failure, and
output exhaustion remain covered. Integer bounds, backing storage, ownership,
and valid program linking remain explicit premises; execution success is not
a premise. The existing strict scanner audit now checks 69 declarations,
including the linked call and its frontend result-count consumer.

Symbol agreement now proves that 11 second-byte representatives cover all 256
bytes: both matchers observe only ten nonzero second-byte values. Combined with
the existing two third-byte representatives, this reduces the checked table
from 18,456 to 816 cases without restricting the theorem's input domain. The
table and its representative-equivalence proofs are kernel checked. A fresh
complete `Symbol/CompilerAgreement.lean` check takes 7.38 seconds with imports
built (`symbol-agreement-representatives-final.log`). This is not a speedup
comparison against the previous native-based proof.

Existing scalar-evaluation and scoped-binding rules replace repeated arithmetic
and environment equality chains. `RawLexer/LexInto/Execution.lean` shrinks from
965 to 819 lines, with its public statements unchanged. After minimal repairs
to stale proof steps, the fresh complete module took 1.85 seconds; the final
compact proof takes 1.46 seconds, both with imports built. Logs are
`raw-lexer-execution-before-measured.log` and
`raw-lexer-execution-final-measured.log`. This module was already fast; the
main gain here is a shorter proof and a closed native-trust boundary.

Across the changed program-specific modules, 111 net lines are removed,
including the new symbol-equivalence proofs. Shared infrastructure is unchanged;
the audit gains 14 lines, for 97 fewer total lines. This remains far from the
size target: the five lexer proof folders contain 28,688 lines against 837 in
the seven corresponding Lanius units, about 34 times the source even before
counting imported program-specific support. Counts include comments and blank
lines. No source implementation or generated proof files were added.

The connected linked-lexer, frontend consumer, and strict audit rebuilt in
19.65 seconds after focused/debug builds (`raw-lexer-kernel-connected.log`).
This is an incremental integration result, not a fresh whole-closure check.
The linked call's before/after inventories are `raw-lexer-trust-{before,after}.log`;
the final compacted execution and audit rebuilt in another 7.34 seconds
(`raw-lexer-final-connected.log`), also incremental.
The connected frontend audit below supersedes the next-step note from this
checkpoint. The whole-entry inventory and concrete kernel self-acceptance remain open.

### Kernel-only frontend and faster symbolic metadata

The current `Frontend.CheckedSyntax.call_evaluates`, `call_native`, and
`reject_call`, plus `checkSyntax?` and `checkLinkedSyntax?`, have no nonstandard
axioms. The audit now reaches the actual `extract_syntax` call and source/link
construction, not only isolated lexer/parser components. This establishes the
combined effect of the preceding cleanups; no additional native assumptions
were removed in this checkpoint. `Tests.FrontendLink` now strictly audits six
declarations instead of allowing whatever assumptions the execution theorem
inherits. The separate scanner audit grows from 69 to 73 targets, including
canonicalizer execution and source authentication.

The call retains its existing grammar, representability, storage, separation,
ownership, and argument-evaluation premises. It derives execution, exact stage
and output information, and memory preservation; it does not assume successful
lexing or parsing. Negative-length rejection has its separate weaker domain.
`call_native` is a Core-level memory/typing contract, not an x86 preservation
proof. Concrete self-instance acceptance and whole-extractor trust remain open.

Profiling the complete parser symbolic-data module exposed quadratic uniqueness
checks. `Extraction.Distinct.nodupOn` now checks sorted small keys and retains a
proof of uniqueness. Key collisions use the complete original decision, so
valid source identities and reused scope-local IDs remain accepted. The generic
decision and full `buildView?` acceptance condition are proved equivalent to
their reference specifications. Layout metadata retains the two `Nodup` proofs
directly, rather than a Boolean equality that can repeat the decision during
conversion. The metadata module also disables compiler closed-term hoisting;
its exact source-derivation equality remains kernel checked.

Fresh complete `Parser/Symbolic/Data.lean` checks, with shared imports built:

| Measurement | Before | After |
| --- | ---: | ---: |
| Wall time | 24.07 s | 17.84 s |
| Peak RSS | 4,692,040 KB | 3,210,672 KB |
| Normalization interpretation | 6.83 s | 4.78 s |
| Reported type checking | 10.5 s | 7.79 s |

Profiler buckets overlap; do not add them. Logs are
`parser-symbolic-data-before-measured.log` and
`parser-symbolic-data-evidence-measured.log` in `target/verified-compiler`.
The consumer `Parser.Symbolic` rebuilt in 2.7 s versus 2.6 s previously under
concurrent builds; the saving was not merely shifted into that consumer.
Seventeen seconds still misses the seconds-scale target.

Narrow uniqueness/collision/layout tests and their strict trust audit passed in
2.14 s. The shared type change invalidated hundreds of dependent proof modules;
the connected build hit the 119 s cutoff. Finishing that incremental integration
took 52.87 s, and strengthening its final audit took 1.24 s. Neither is a fresh
whole-closure timing. Logs are `symbolic-distinct-evidence.log`,
`frontend-distinct-{connected,integration,strict-audit}.log`, and the ten-target
transitive inventory `frontend-trust-current.log`.

This change adds 149 shared implementation/proof lines, 68 test/audit lines, and
one program-specific metadata option line. It adds no Lanius code or generated
proof files and does not reduce the existing program-specific proof-size ratio.
The earlier scanner-only lower bound of about 34 times source size still stands.
Milestone 3.7 is now closed through the checked frontend call, not through the
whole extractor. The next trust boundary is the source-bound unit/output/entry
composition. The concrete self-certificate and compiler milestones 3–7 remain open.

## Compiler implementation status

Current execution plans: [Milestone 3](MILESTONE3.md) records extractor proof
completion and open acceptance obligations. [The x86 backend](BACKEND.md) is
the active implementation track. Its engineering does not require first
removing Lean-native trust dependencies; those remain explicit open findings.
The whole-extractor x86 engineering boundary is now closed. The Lanius backend
links all 106 reachable internal functions and nine runtime services, emits
Linux ELF itself, and produces an extractor that self-extracts the 18-source
closure in 2.12 seconds with byte-identical output. Source-to-Core still runs
in Lean; the GPU compiler bootstraps the Lanius backend. The recursive backend,
runtime and ELF preservation proofs remain open. The next work composes those
proofs along this executable path, not another instruction inventory. This
does not accept milestones 3–7 or authorize trusting the bootstrap.
The pointer decision is [native runtime addresses with proof-only block
correspondence](MEMORY.md), not preservation of the interpreter's numerical
allocation layout through runtime translation. Bounded storage and pointer
comparison proofs do not yet establish general address-relocation correctness.
The raw-i32 storage boundary now derives protection, decoding, packed backing,
and a fresh view from actual Core allocation plus the native allocation effect.
Decoded descriptor initialization composes with bounds-checked native indexing.
The actual raw-slice compiler branch now has a complete source-emission proof
for pointer-local/i32-literal operands, including both recursive calls,
interleaved pointer save and length check, and aggregate-result slot lifetime.
`Lower.Expression.Raw.Preservation.compiles` connects those emitted bytes to
the actual Core expression and full native execution, including negative-length
rejection. The complete case retains explicit live-local, exact-backing, and
private-frame separation conditions. General recursive operands, allocator
execution, and whole-compiler composition remain open.
[The memory contract](MEMORY.md) states the exact proved boundary.
The extractor now has a 16 MiB output cap and matching formal bounds because
the expanded backend's singular source pack exceeded the former 8 MiB cap.
The packed workspace size and one-extractor architecture are unchanged.
Work now follows connected compilation cases rather than finishing the entire
instruction-emitter proof inventory first. The first case accepts real Core
functions returning an i32 parameter and now has a complete source-linked
Lanius implementation proof on that domain: selection, ABI mapping, size
selection, reservation, emission, and caller restoration. The selector proof
covers safe reads, both nested loops, termination, and both supported body
forms. `Lower.Parameter.compile_function_certified` constructs the machine
certificate from the actual Core transport and input storage, without assuming
selector execution or running an output validator. Capacity rejection also
has a complete implementation proof for that parameter-return routine.

The public backend now uses one recursive frame-based compiler and links
complete Core call graphs. It supports i32/bool expressions and control flow,
full-width pointer/usize values and casts, constants, nested struct values,
slice descriptors, checked packed-i32 indexing, field/indexed mutation,
aggregate arguments/results, and recursive calls with register/stack arguments.
This expanded implementation is not yet proved
correct. Frame layout, source-bound frame helpers, and decoded spill/reload
have kernel proofs. Whole-value copying now also has a decoded x86 theorem
that preserves represented Core values and the caller's saved frame, using
only standard axioms. Actual-source copy emission agrees with that sequence
on concrete cases; the general Lanius emission proof remains open.
Packed-slice storage now has kernel proofs of nonwrapping in-bounds addresses,
element separation, signed reads, exact backing-array updates, and preservation
of other bytes. The final decoded loads/stores connect to effectful Core
indexing and assignment, including nonzero read offsets and RHS mutations.
Slice stores also preserve the existing caller-frame invariant under explicit
heap/frame separation. The complete decoded bounds/address sequence now
establishes the Core read address or the matching bounds fault. A single
unsigned comparison handles signed-negative and full-width indices on valid
packed storage; MOVSXD and scaled LEA replace the extra negative check and
shift/add sequence. The actual Lanius scaled-address emitter has a general
source-linked exact-byte and capacity-rejection proof, connected to the LEA
machine step. The shared memory emitter now has general source-linked success
and atomic capacity-rejection proofs. The public load/store proofs connect
their actual Lanius calls to decoded 32/64-bit MOV steps for every register/base
choice and signed displacement. The frame-load, word-load, and word-store
wrappers now compose those calls with the actual workspace cursor update,
preserving both arrays and the caller outside their write footprints. The
actual bounds-check helper composes branch emission, its local cursor binding,
and trap emission; loading its output gives the proved branch-or-UD2 behavior
for every condition code. `Lower.Index.Emission.compiles` now composes the
complete actual `backend::index::address` body with the Core address/bounds
contract for both index widths. It covers valid compiler resources and
sufficient output capacity, exact bytes, workspace updates, and caller framing.
The recursive expression/place simulation must still establish its captured
descriptor/index and storage premises. Compiler-capacity rejection remains
separate from the proved runtime bounds-fault behavior.

The decoded prologue/epilogue now compose with an explicit body-execution and
frame-preservation premise. Private slot stores preserve the saved caller
state. The Lanius return routine emits the fixed five-byte epilogue after one
capacity check; its source-linked proof yields the exact bytes and their
machine execution, with atomic rejection when capacity is insufficient.
The general body simulation and actual prologue-emission proof remain open.

A prior exact-source census found 106 reachable internal extractor functions
and nine external runtime functions. The updated whole-call-graph test compiles
103 actual extractor functions. Its scalar/record sampler executes 60 of them
on 480 inputs, plus 20 actual text-output cases, in 27.25 seconds; other buffer-dependent
functions need dedicated execution checks. The actual raw lexer passes 96
Core/native comparisons in 27.36 seconds, including token-buffer writes and
classified failures. These are execution results, not proof-completion
percentages. The actual `backend::compile::indexed` caller now composes
allocation, descriptor saving, a recursive-expression emission hypothesis, and
the proved checked-address routine, including whole-call framing. Exhausted
slots and invalid recursive result kinds have source-linked rejection proofs.
`Indexed.Preservation.compiles` attaches the full emitted window's machine
contract; recursive machine execution remains a separate explicit hypothesis.
The signed-i32 literal wrapper and its composition into the indexed helper now
have source-to-native proofs, including actual transport reads and emission,
with no recursive source or native execution hypothesis for those cases.
Transport-linked corollaries derive signed bounds and input words from Core
serialization. Initialized i32 locals now also have actual wrapper/source/native
preservation, with lexical shadowing and lookup-miss rejection proved. A shared
scalar wrapper rule supplies TOP and caller bookkeeping. The next proof work
covers remaining expression cases and composes memory operations, control flow
and calls. Host services, ELF output and
fresh string-data copies are now implemented; their general preservation
proofs remain open.
Source-to-Core implementation/proofs and general malformed
transport rejection also remain open. Neither the parameter case nor this
program checkpoint completes milestone 4; milestones 3–7 remain unfinished.
Follow these plans instead of the chronological checkpoint notes below.

The user goal is the complete seven-step pipeline below. The old Rust
exporter has been removed; the extraction implementation is in Lanius.
The earlier self-extraction-only goal is superseded by this expanded scope.

All executables and execution tests in this workflow target x86-64 Linux ELF,
including the untrusted GPU bootstrap. Do not use a Wasm fallback. The existing
GPU compiler is bootstrap machinery, not the verified compiler/backend in
Lanius required by milestone 4.

The first native tests exposed missing conditional-call lowering, runtime-length
array indexing, a six-slot argument ABI limit, and an incoherent raw-array
layout. Conditional lowering, direct-call stack arguments, checked fat-slice
access, and coherent packed `i32` arrays now pass focused native execution
tests. The checked-in Lanius syntax extractor builds and runs as a static
x86-64 ELF. It emits one compact logical `ArtifactPack` for the exact 18-file
source closure recorded in `source-closure.txt`. Lean decodes it through fixed
general infrastructure and returns proof-carrying syntax evidence plus an
independently reconstructed, origin-checked Surface program for every unit.
This completes milestone 2. The milestone-3 self-embedding now validates exact
sources, syntax, reconstructed Surface, proof-producing source-to-Core
lowering and whole-program x86 Core typing. A separate extractor-specific
checker links the declared source `main` to a well-formed Core executable
entrypoint and checks its return codes. General Core preservation proves memory
safety for every terminal execution of an entrypoint accepted by that checker.
Ordinary extracted programs need neither that entrypoint nor those return codes.
The extractor now has a complete main-body success/failure I/O refinement proof
on its loading/resource domain, connected to the actual executable entrypoint.
The public `Entry.checkExecution` checker constructs the frontend proof links
and retains the complete execution theorem for consumers. The self-source
driver uses this library result, and a separate proof-producing input-domain
check establishes the loading conditions for the actual self closure.
The language-to-chart completeness theorem now proves that valid input has a
root in a seeded, closed chart. The actual root-search proof retains exhaustive
rejection evidence, and the parser call and frontend preserve it. Establishing
initial seeding from the source loop is complete. Prediction and scanning completeness now
cover every item of every final-workspace input chart, including items
appended during processing and preservation through later positions. Actual
chart-head and position-zero entry discharge the prefix preconditions. The
public parser result and frontend rejection contract retain that guarantee
for the same returned workspace. Matching scans retain their advanced item,
including duplicate insertion; failed matches and capacity failures remain
distinct. Parent traversal and nullable replay now prove their coverage through
the actual source entries and restored callers. Their combined pair invariant
covers all processed states and survives later positions. The position/root
continuation constructs full chart closure from these source-loop guarantees,
the stored position bounds, and language-sound derivations.
`RecognizerCallExecution.success_or_capacity` now proves that declaratively
valid input succeeds or reports capacity exhaustion; it cannot be rejected as
invalid syntax. The frontend retains the same result, and successful calls
expose the actual stored root. No caller assumes chart closure or parser success.
The exact self closure now satisfies source-bound syntax and token-storage
domains. Token bounds reuse the certified spans instead of running the lexer
again. The accepted postorder parse certificates imply the parser's declarative
language, including the split-token lattice. The actual file-loop theorem
`File.Resources.frontend_success_or_resource` combines these facts: on that
domain the frontend can only succeed, exhaust parser capacity, or exhaust tree
resources. The new parser resource domain below excludes capacity failure;
tree resource sufficiency and semantic/output bounds remain for the self closure.
Capacity diagnostics now retain the actual full workspace through every source
parser loop and the frontend return. The public `capacity_exhausted` theorem
proves the returned state count equals the authenticated capacity, supplying
the failure witness used by the resource bound.
The source-connected bound theorem is now proved: every generated state belongs
to any closed candidate chart, so unique source keys bound the returned state
count by the candidate size. `success_of_closed_bound` combines a candidate
strictly below capacity with declarative input syntax to guarantee actual
parser success. Fresh items retain generation from source initialization or
prediction; existing decreasing backpointers establish it for all advances.
The finite candidate checker now validates all four closure rules, including
coverage of its lookup indexes. A Lanius tool calls the existing lexer/parser
to propose charts; Lean checks them against the authenticated token streams.
All 18 self-source candidates are accepted. `checkParserDomain?` retains the
source-only resource domain and `File.Resources.frontend_success_or_tree_resource`
excludes parser capacity as well as lexical/token/syntax failures. Tree depth
and storage sufficiency are the next boundary. A GPU lowering bug found by the
proposer is fixed: host-service IDs no longer index ordinary function return
metadata. The production extractor's output remains byte-identical.
The next tree-resource boundary is now closed as well. Checked potentials on
the same finite charts bound every recognized tree's exact nodes, words, and
depth; no emitted tree or backpointer choice is trusted. All 18 self sources
pass `checkParserTreeDomain?`, which reuses chart closure and accepted lexical
evidence. The frontend postcondition retains the actual depth limit and the
existing materializer's sufficient-resource guarantee.
`File.Resources.frontend_success` now excludes every frontend failure on those
source-only domains. The final integration passed in 66.82 seconds, including
37.364 seconds for parser/tree resources, with shared infrastructure built.
New audits add no assumptions. The existing semantic collector already proves
its buffer sufficient after frontend success; the active next step is complete
output capacity and propagation of success through the whole file/main loop.
The output-capacity boundary is now closed. Tight tree budgets and the raw
lexical evidence already checked by the token checker yield a source-only
full-module bound of 7,899,213 bytes, below the unchanged 8,388,608-byte output
allocation. The exact serializer-size theorem and
`File.Resources.encoding_bound` connect this bound to the actual emitter and
every recognized tree, not a trusted choice of emitted tree. All 18 sources
pass; checking the output domain takes 419 microseconds, and the complete
integration takes 65.63 seconds with shared infrastructure built.
Successful whole-run completeness is now proved as well. The actual file loop
retains success and cumulative cursor bounds, and the complete main proof
reserves enough room for the suffix. The public `CheckedExecution.run_complete`
theorem gives successful extraction above a finite fuel bound from source-only
syntax/resource conditions and the explicit loading domain. The exact 18-file
self world satisfies those conditions; full integration passed in 67.91 seconds
(`completeness-self-source.log`). The new input binding took 15.968 milliseconds
and reran no lexer, parser, or resource analysis. The proof concerns the accepted
Core executable and modeled host, not native x86 machine code.
The broader external failure boundary is now connected. The exact checked
main now has a no-input rejection theorem: argv lengths zero and one return
code 1 before allocation or file access, preserving the external world except
for the argc event. The new public rejection contracts pass standard-axiom-only
audits and six actual-source cases. All 13 allocations now check the raw pointer
before constructing a slice; the redundant post-allocation guard is removed.
The source-linked sequence proof covers exhaustion at every position, and
`CheckedExecution.allocationFailure` proves finite, classified code-3 rejection
through the actual main, with unchanged files, handles, arguments, and output.
Twenty-five focused budgets and four actual-main exhaustion cases pass.
The first requested path now has actual-main rejection proofs outside
`LoadingDomain`: `CheckedExecution.invalidPath` returns 2 for an empty or
oversized path; `CheckedExecution.missingFile` returns 5 for an absent file
with a valid-length path. Both preserve files, handles, and pre-existing output.
The checker retains the proved startup prefix and path buffers, without
assuming file availability or a fresh/representable handle counter.
The later-file connection is now proved as well. `CheckedExecution.laterFailure`
covers any nonempty loadable prefix followed by an invalid/missing path or oversized file,
without assuming that preceding syntax parses or extraction succeeds. An
earlier frontend/encoding failure may return first; otherwise the designated
file returns 2, 5, or 6. The result preserves files, old handles, argv, and stdout.
`checkLaterFailureDomain?` reuses the existing loading checker to establish
the prefix, selected bad path, and handle conditions from external inputs.
`CheckedExecution.oversizedFile` now proves code-6 rejection of an oversized
first file through the actual main, mandatory close, and both diagnostic calls.
The reader handles arbitrary file sizes with one shared initialization/call
proof; overflow consumes exactly capacity plus one bytes without copying the
overflowing chunk. Startup derives its resources without a file-size premise.
The new domain checker needs no syntax or later-file assumptions.
Full integration accepts all 18 self sources in 69.02 seconds
(`host-self-source.log`), retaining successful termination and exact output.
Focused source mutations, UTF-8 boundaries, and missing-file/counter cases pass.
A fresh native self-extraction is byte-identical and takes 1.15 seconds.
The public later-file theorem now includes overflow through the existing loop
induction, mandatory close, and actual diagnostics. `HostDomain.classify`
exhaustively partitions every host-bounded invocation into the loading case or
a proved rejection case. `CheckedExecution.hostSafe` therefore supplies finite
termination and the original soundness/failure contracts without assuming file
availability, file size, valid syntax, or successful earlier execution. This
closes 3.8 on the explicit deterministic host domain; finite allocation
exhaustion retains its separate theorem. Native OS I/O errors and arbitrary
finite-budget successful heaps are not covered by the unified theorem.
The [milestone-3 acceptance audit](AUDIT.md) repaired missing source provenance:
`Entry.CheckedSource` now retains the source-checker's result and whole-run proof
together, and the self-check consumes `Entry.checkSource` without repeating
source parsing or Core synthesis. The audit also distinguishes native IO
self-validation from a concrete kernel-checked self-proof artifact; the latter
is not yet available. Full integration with three new source-mutation cases
passed in 88.78 seconds (19.550 seconds were those negative tests).
Inherited trust cleanup remains open; no weaker trust policy has been approved.
The last fully rebuilt whole-checker inventory has 173 nonstandard assumptions
in 158 declarations for the combined source/execution checker (`source-trust-inventory.log`), down from 207 in 176,
328 in 249, and originally 463 in 264. Total Core equality now has
all-input correctness proofs,
and structural live-local analysis lets parser metadata and grammar-validator
frames pass ordinary kernel checks. Structural term renaming also removes the
state-loop command-comparison dependencies. Their focused audits and the public
checker rebuild pass (107.34 seconds). Actual self-source integration also
passes in 67.28 seconds, retaining the complete execution certificate for all
18 files. Parser/tree resource checking still takes 37.412 seconds; this
checkpoint reduces trust dependencies, not the end-to-end checking cost.
Milestone 3 remains incomplete.
See the
current [milestone ledger](MILESTONE3.md) for theorem names and verification.

## Historical component checkpoints

The following component notes describe earlier boundaries; their outstanding
tasks do not supersede the current milestone ledger.

The derivation reader now has a complete success-path execution proof from
caller buffers and scalar arguments. It executes the input guard, base
initializer, workspace guard, child-count lookup, count and output-capacity
guards, root metadata lookups, header writes, cursor allocation, backpointer
loop, final seed validation, and return of the child count. It derives every
field read, guard, temporary binding, output store, and cursor update. The invariant proves termination
and exact child-record order, preserving the header and trailing capacity.
Fresh cursor allocations supply the non-aliasing conditions; closing their
scopes leaves only output-buffer writes visible to the caller. The complete
record matches `derivationRecordWords` and preserves both surrounding buffer
regions. The complete success-path module checked in 2.18 seconds with shared
dependencies built; its axiom audit found only Lean's standard logical axioms.
The source checker requires exact equality with the entire reader body,
with a statement-equality theorem connecting the checker to the execution
proof. The current self-extraction passed that check in 20.89 seconds.
The complete reader's function-dependency closure is also proved.
The execution proof uses standalone parser symbol coordinates. A checked
reader link now verifies the accessor's program link and exact relocation
of the complete reader body into the current extractor. Execution and
call-boundary transport rules are proved, and the current self-extraction
passed this link check in 20.68 seconds. A runtime constructor connects
the success-path theorem to the checked source's local coordinates.
Caller-state and output-postcondition composition, and the extractor's
full success/failure I/O contract, remain unfinished.
These results do not complete milestone 3 or the x86 backend proof.

The extractor embeds the exact grammar as one hexadecimal string token, decodes
it in Lanius, and uses dynamically allocated native pointer/length slices.
Chunked host I/O replaced the former one-syscall-per-byte bridge. Its output is
one compact hexadecimal string decoded by
`Lanius.Extraction.CompactArtifact`; malformed counts are bounded by the
remaining payload before allocation or iteration. This avoids both the old
121-file generated proof forest and millions of generated Lean constructor
syntax nodes. The process now assembles the entire module before its single
logical stdout write, so pre-write failures cannot expose a partial
certificate. The generated Lean checker then rereads its ordered input paths
and requires the decoded pack's source names and bytes to equal those
independent inputs. It then reconstructs Surface from the accepted parse
artifacts and checks all Surface-origin claims. Closure selection and bootstrap
invocation remain outside the proved Lanius execution semantics, while the
exact execution/output relation and general extractor correctness theorem keep
milestone 3 incomplete.

`Lanius.Extraction.ExtractorContract.Success` now fixes the execution theorem's
target: exact rendered stdout, exact ordered input files, accepted syntax
evidence, preserved source files and arguments, and no leaked file handles.
It intentionally does not require type correctness of the extracted input:
`AcceptedSuccess` adds that obligation only after the typed-Core checker
accepts. A type-error fixture guards this boundary.
The source-bound compact checker also retains independently reconstructed
Surface values with their validity proofs, so subsequent lowering can consume
them without reconstructing a second copy.

The output proof now covers signed-word byte serialization, the complete Core
packing loop (including termination, input preservation, and write footprint),
heap read-after-write, disjoint-view synchronization, and exact stdout for a
successful Core host call. The clearing loop is also proved and establishes
the zeroed-word precondition. A proof-producing structural check locates both
exact loops in the checked source `main`, without copying its body.
`stdout_after_packing` derives the packed buffer and its encoding from the
loop execution. It requires initial ownership, valid registered blocks, and
distinct view addresses; heap well-formedness then supplies non-overlap.
Pointer exposure preserves distinct addresses, while raw-slice construction
requires a fresh address. The enclosing source execution must still establish
these entry conditions and connect the phases in order.
These results do not yet prove the extractor's full execution contract.

The input proof covers the actual Core host read through heap synchronization
and scratch-word refresh. The complete unpacking loop is proved terminating;
it copies exactly the refreshed bytes while preserving earlier chunks, unused
output capacity, and the packed scratch buffer. `unpack_after_read` composes
these proofs, deriving the copied bytes from the file contents rather than
assuming a correct scratch encoding. The enclosing file-reader guards must
still establish its ownership and capacity preconditions. The source checker
links this exact loop to `verified::byte_io::read_file` in the self-embedding.
The read-preservation theorem also derives coherence for other in-range i32
buffers and proves they survive both synchronization passes unchanged. Raw
slice allocation preserves unique backing roots; exposing an existing slice
pointer preserves the registry. The capacity-probe branch is proved to compute
the bounded, positive request size and is linked to the checked source.
The outer reader loop, guard composition, and caller-side handle lifecycle
still need to be composed with these stage proofs.

Frontend proof reuse now has a proof-producing global-ID relocation checker.
Against the current self-embedding, all 18 old lexer functions, 6 token-scan
functions, and 20 parser functions match their relocated definitions; so do
49 constants and 5 structure layouts. Both sides use x86-64 Core. Type IDs use
an invertible permutation, not a non-surjective offset, so pre-existing caller
values can be transported too. This complete source/link check took 19.64 s.

The generic relocation lemmas cover scalar operations, nested assignments,
parameter binding and call state, enum matching, slices, i32 encoding, and
heap/view synchronization. Their focused regressions and axiom audit pass
(1.34 s with dependencies already built); production proofs use only Lean's
standard axioms, not native evaluation as a proof oracle. The full fuel
induction is now proved: `Semantics.Relocation.Execution.evaluates` and
`executes` preserve successful executions of internal modules in the larger
program. This covers expressions, calls, memory operations, statements, and
loops; the internal-call condition is checked with proof-producing evidence.
The complete transport build took 9.38 s. Checking its assumptions against the
three actual frontend modules and exact self-sources took 20.11 s. Its axiom
audit contains only `propext`, `Classical.choice`, and `Quot.sound`.
The merged nine-module frontend has checked name-based cross-module mappings.
`Semantics.Restriction` now proves that removing unreachable functions preserves
successful execution with exactly the same state and result. Its checker
requires every retained function body to call only retained functions, including
calls nested in arguments, mutable places, and loop bounds. Combined with
relocation, `Semantics.Relocation.Link` transports the dependency-closed portion
of an old program into the current program. The self-source check accepted
50 of the old merged frontend's 54 functions and all 92 constants in 21.87 s.
The four historical canonicalization helpers are explicitly excluded; their
replacement is proved separately below. No changed body is assumed equivalent.
Focused closure regressions pass, and the restriction theorems use only
`propext`, `Classical.choice`, and `Quot.sound`. The old pack's source-byte
assertion now covers only its eight unchanged units, not the replaced
canonicalizer. Exact current-source authentication remains in the self checker.

The scanner-model mismatch exposed by rebuilding the old public raw-lexer
contract is repaired. `LexerStreamOffsets.scanOne_eq_scanOneAt` (in the
`Compiler.Lexer` namespace) proves that suffix scanning and absolute-offset
scanning agree for every source and start position. Supporting lemmas cover
identifiers, whitespace, quoted literals, comments, numeric literals, symbols,
and failure offsets. The equivalence proof uses only `propext` and `Quot.sound`.
All eight affected `RawLexer.ScanOne.Execution` proofs now pass; that focused
build took 4.15 s. The initial full public-contract rebuild hit the 29-second
limit, with the old `Symbol.Execution` module taking 19 s.
Profiling traced a substantial part of that cost to 50 native decisions for
constant IDs. The lookup now matches signed-i32 constants directly, avoiding
opaque generic value equality; all 50 decisions use ordinary kernel reduction.
The focused rebuild, including the checked source-structure proof, passed in
11.26 s. No Lanius scanner behavior changed.
The next full-contract attempt exposed `Symbol.CompilerAgreement` at 23 s.
That proof enumerated 24 × 256 × 256 three-byte inputs. A new kernel-checked
equivalence shows that the third byte matters only when it is `=`, reducing
the enumeration to 24 × 256 × 2 without weakening coverage. The agreement
declaration now checks in 4.4 s, and the complete `LexInto.EndToEnd` build
passes in 5.67 s. The reduced finite agreement checks still use the legacy
native-decision mechanism; this is not a claim that the old frontend's entire
trust footprint is kernel-only.

`RawLexer.LexInto.Linked.call_evaluates` now transports the existing complete
raw-lexer call theorem through a checked dependency-closed link. Invocation
preconditions remain in the original state coordinates; the executed call and
result state are explicitly relocated. The exact self-source integration check
now links `verifiedFrontendCore`, the program used by that theorem, rather than
a separately decoded JSON copy. It requires the raw-lexer entrypoint to remain
in the retained set and instantiates the linked call theorem. This check passes
in 24.06 s. Caller-state composition with the canonicalizer, parser contract
instantiation, and the full extractor I/O theorem remain unfinished.

The linked raw-lexer theorem now also returns ownership of the unchanged
source buffer and the exact encoded emitted-token prefix followed by unchanged
spare capacity. `LexInto.run_records_prefix` proves that format directly from
the lexer's three stores per token; it matches the canonicalizer's input
encoding and also covers prefixes emitted before failure. The prefix proof
checked in 0.32 s, and the new ownership/prefix audit contains only standard
Lean axioms. This strengthens the existing theorem rather than adding a weaker
compatibility wrapper. One caller-side limitation remains explicit: the old
raw-lexer model fixes source and record backing cells to 0 and 1. Global-ID
relocation preserves cell addresses, so these results do not yet cover the
extractor's arbitrary buffer allocation layout. That address generalization
must be proved before claiming complete caller-state composition.

`Semantics.CellRenaming` now provides the state-level foundation for that
generalization. A bounded permutation can place two distinct model buffers at
arbitrary distinct existing caller cells, including overlapping placements,
while fixing every future allocation identity. Renaming covers nested slices
and references, local bindings, cells, and registered view roots; native byte
addresses, heap contents, and the host world remain unchanged. Kernel proofs
establish reversibility, cell lookup, state well-formedness, and compatibility
with local-cell and temporary allocation. Focused checks cover all 56 distinct
destination pairs below eight, nested references, native-address preservation,
and round trips. The state module checked in 0.43 s and the tests/audit in
0.46 s, using only standard Lean axioms. The complete evaluation-transport
theorem and its lexer instantiation are not yet proved.

Cell-renaming rules now also cover cell/local reads and writes, nested field
and array assignments, projected reads, parameter binding, caller-local
restoration, scalar operations, and i32 encoding/decoding. Both registered-view
synchronization directions are proved compatible with renamed cell roots while
preserving native addresses and bytes. The synchronization module checked in
0.48 s; the combined focused checks and axiom audit checked in 0.43 s with
dependencies built. All audited new rules use only standard Lean axioms.
Pointer exposure now covers array views, slice pointers, strings, and raw-slice
construction, including fresh-cell allocation and registered roots. Pattern
bindings and execution outcomes also respect cell renaming. Source literals
are proved unchanged, including literals inside aggregates.

The execution induction now carries the allocation boundary through argument
lists, match arms, mutable places, both loop-iteration forms, and every statement
form. These are conditional fuel-step lemmas: they use the smaller-fuel
execution hypothesis, not an axiom asserting full transport. Explicit evaluator
cases keep the place and statement modules at 1.3 s and 1.2 s respectively.
Expression cases now cover internal calls and constants under explicit program
invariance premises, scalar operations (including short-circuiting), aggregate
construction, matches, field/index reads, locals, borrowing, dereferencing, and
assignment. Calls preserve parameter allocation and caller-local restoration;
missing bodies are not silently treated as pure external calls. Separate
counter lemmas prove that writes, view synchronization and pointer exposure
preserve `nextCell`, while raw-slice construction increments it by one. The
call, scalar, aggregate and reference modules checked in 0.72 s, 1.8 s, 1.0 s
and 0.56 s respectively.
All expression cases now pass, including array-to-slice conversion, pointer
exposure, raw memory operations and intrinsics. The complete fuel induction is
closed: `CellRenaming.Execution.evaluates` and `executes` transport successful
execution and preserve the allocation boundary. The assembled expression step
checked in 0.48 s and the final induction in 0.45 s with dependencies built.
These theorems require `ProgramInvariant`: constants and internal function
bodies must be unchanged by cell renaming. A proved structural checker now
establishes this premise for every renaming from one source check. It rejects
embedded runtime references/slices and missing function bodies, while allowing
source operations that create references during execution. The actual
`verifiedFrontendCore` passes this check; the self-embedding/link check also
passes with this evidence.

`RawLexer.LexInto.Linked.call_evaluates_renamed` now composes cell renaming and
symbol relocation for the complete lexer call. It preserves the source buffer
at the renamed source root and the encoded-token prefix plus untouched suffix
at the renamed record root. The module checked in 0.99 s. Its initial
representation remains in model coordinates. A new
`RawLexer.LexInto.Caller.body_executes_at` contract now accepts arbitrary
distinct caller source/record cells and the caller's local-cell layout
directly. It constructs the permutation and inverse representation internally,
derives allocation bounds from ownership and well-formedness, and preserves
the caller-coordinate output representation. Its module checked in 0.99 s.
`Caller.call_evaluates_at` lifts it to a complete call with argument evaluation,
parameter binding, restored caller locals, and the exact token-prefix plus
untouched-suffix buffer postcondition. The self-source check using the caller
body theorem passed in 21.59 s. `Linked.call_evaluates_at` now connects this
caller-coordinate contract to the checked linked program. The body contract
also preserves its store effect through cell renaming; the call uses the
resulting allocation-domain extension to prove well-formedness after restoring
caller locals. It requires well-formedness of the post-argument caller state,
not an assumption that the final state is well-formed. The strengthened linked
module checked in 0.99 s.
Raw-token span validity is now proved for every emitted token, including
lexical-failure and capacity-limited prefixes. The scanner proofs cover numeric
forms, quoted literals, comments, and fixed symbols. `canonicalize_emitted`
uses the lexer's buffer postcondition to invoke the checked canonicalizer,
deriving span and buffer-size preconditions without repeated validation.
The bridge module checked in 0.45 s with dependencies built; its axiom audit
reports only `propext`, `Classical.choice`, and `Quot.sound`.
The two buffer-copy loops now have a shared total execution proof, covering
contiguous raw words and every-third-word token kinds. The invariant preserves
the source, replaces exactly the destination prefix, retains unused capacity,
and bounds i32 cursor arithmetic. A proof-producing matcher accepted both loops
in the current self-embedding: raw local 4 to canonical local 6, and canonical
local 6 to kinds local 8. The complete source/link check passed in 21.76 s.
The loop proof checked in under one second and uses only standard Lean axioms.
Token-record lemmas derive the copied-word and kind-selection relations;
they do not assume a successful read or a correct iteration. Focused tests
reject mismatched read/write cursors, incorrect increments, and wrong strides.
Cursor initialization now derives the loop invariant from caller storage and a
fresh binding. Closing the cursor scope exposes only destination-buffer writes.
`copy_then_canonicalize` composes the loop with the checked canonicalizer call
inside the original cursor scope and binds the returned count for the rest of
the extractor. Canonical capacity may differ from raw capacity; only the copied
prefix must fit. The composed theorem checked in 0.54 s and its audit reports
only standard Lean axioms. The self-source checker also authenticates the
enclosing scope, call arguments, and canonicalizer function identity; it passed
in 20.55 s. Negative tests reject a different cursor or miswired count/buffer.
`copy_kinds` now constructs its memory model and initial invariant directly from
the canonicalizer's buffer, allocates the cursor, executes the kind loop, and
passes the exact kind prefix and count to a continuation in the original scope.
Its first check took 0.46 s. `kind_prefix` converts that output to `I32Prefix`,
which retains physical capacity while describing only the meaningful input.
The new prefix read and frame-preservation rules are kernel-checked.

Parser composition has a concrete remaining contract gap: the old
`RecognizerResources.tokensBacking` and `parserTokensValue` require exactly
the logical token list and its length. The extractor supplies a larger kinds
slice with an untouched suffix. The parser contract must be generalized to
prefix-backed read-only input; the current proof cannot be applied by assuming
away spare capacity. The new prefix rules are a basis, not that generalization.
Inspection confirms `scan_terminal` is the parser's only direct token-array
reader. Its functional-view read helpers now accept explicit storage and are
verified. Their initial check was delayed because rebuilding the legacy parser
artifact exceeded the 29-second command limit before reaching the scan module.
The first build also spent 26 seconds on unrelated lexer artifacts imported
only for `sourceBytes`; that import was removed from the parser program module.
Standalone artifact quotation now caches decoded JSON by exact input text,
matching the existing pack-cache design. Cached/uncached replacement, repeated,
equivalent-encoding, and malformed-input tests pass (test module: 0.87 s).
The parser artifact still exceeded 29 seconds after this change. A bounded
debugger sample subsequently located active work in Lean's LCNF specialization
(`isGround` / `shouldSpecialize`), not kernel checking. Temporary file-backed
timing instrumentation bypassed buffered diagnostics: decoding took about
0.18 seconds, while compiling each 6,474-node parse-table field took about
9 seconds. Literal `include_str` paths alone did not fix the timeout.
Standalone field quotation now bounds constructor expressions with ordinary
auxiliary definitions and batches their compilation. It does not add shard
files or trust assumptions. Kernel equality tests cover empty, short, and
multi-definition nested data; a runtime check also compares compiled data.
An intermediate 512-node, synchronous direct Lean check completed within
29 seconds, with parse-table fields taking roughly 4.3 seconds each. This is
not itself a successful normal build: normal builds, including the batched
variant, still timed out at 29 seconds. Subsequently disabling redundant
closed-term extraction for this generated module cleared the full normal
build in 24.33 seconds (about 2.7 GB peak RSS).
The next check exposed a stale whole-file source claim: the current parser
appends `copy_derivation` to the exact original source. The assertion is now
explicitly `verifiedParserArtifact_tracks_source_prefix`; it does not claim
to validate the appended function. Reuse in the current self-embedding still
requires the exact Core relocation link and full-current-source check.
With closed-term extraction disabled, the parser program module rebuilt in
2.22 seconds. The parser scan proof and its dependencies then rebuilt in
11.84 seconds; the functional-view scan module itself took 3.4 seconds.
This verifies the generalized raw-token and grammar-read helpers, not yet
the full prefix-backed recognizer contract.
`scanTerminal_evaluates_storage` now composes those helpers into the complete
in-bounds scan evaluator for arbitrary unused token storage. The exact-sized
scan theorem specializes it with an empty suffix, avoiding duplicate proofs.
The module checks in 3.7 seconds. Its axiom audit retains the existing
`native_decide` dependencies for signed minus one and parser constants; no
new axiom was added. `scanTerminal_rejects_past_end_storage` now proves
rejection for any storage world using only logical count and position; spare
capacity cannot expose extra tokens. `extractedParserScanTerminalBody_scans_storage`
connects the in-bounds result to actual Core execution, preserving caller
cells and state well-formedness. The module still checks in 3.7 seconds.
`ScanStorageEntry` now derives the world representation and local-environment
assumptions from concrete locals and backing cells. The combined body theorem
covers both branches, and `extractedParserScanTerminalCall_implements_model_storage`
proves the actual call result, caller-cell preservation, restored-state
well-formedness, and preservation of both the grammar and complete token buffer.
`parserScanStorageCallee_entry` now derives the entered-state facts from
caller well-formedness, distinct buffers, and their concrete contents. The
call theorem no longer assumes its own callee invariant. The module checks
in 3.9 seconds. Generalizing persistent recognizer resources and carrying
the suffix through workspace updates and nested loops remain unfinished.
`I32PrefixLocal` now couples a slice local to its physical backing capacity
and logical prefix. Its read and frame-preservation rules check in 0.4 seconds.
`parserRecognizeScanTerminalCall_implements_prefix_model` uses that resource
at the recognizer's exact call expression and returns it preserved, without
exposing a capacity parameter in the statement. The recognizer module passes.
`RecognizerResources` and `RecognizerInvariant` now use `tokenStorage` instead
of separate exact-sized token-local/backing fields. Preservation across local
binding, read-only calls, workspace writes, scoped effects, and both scan paths
has been updated; the recognizer module passes. The downstream soundness build
does not yet pass. The common Functional View world now carries an explicit
physical suffix, and `recognizerWorld_from_invariant` obtains a consistent
world and slice local from the persistent resource (common module: 0.96 s).
Chart clearing now preserves the combined prefix resource. Phase-specific
worlds/environments and setup code still need migration; the whole parser
soundness build is not yet restored.
Prediction migration exposed a missing retained frame fact:
`RecognizerSeededAppendResult` now includes `argumentsEffect`, proving that
argument evaluation preserves existing cells. Its constructor supplies the
already-proved seed effect, and the recognizer module passes. This permits
transport of a chosen physical suffix into the append argument state.
Experimental prediction suffix propagation was not retained: it still
needs the suffix/backing relation carried through configuration and loop
outcome definitions, not a fresh unrelated witness at each step.
`I32PrefixLocal.unused` now names the suffix selected from a resource, with
proofs that backing contents determine it uniquely and that untouched cells
preserve it across reconstructed proofs (module: 0.44 s). The common world
module uses this to prove representation from the named suffix and equality
between workspace-updated worlds built from different before/after invariants.
Both preservation theorems audit to standard Lean axioms only. Phase migration
can therefore use invariant-selected suffixes without adding data fields to
every loop configuration; it remains to apply those equalities in the phases.
The distinct-buffer premise was subsequently removed from the storage entry,
call, and recognizer call-site contracts. When both slices share a cell,
their concrete backing equalities prove that the encoded contents agree;
the read-only world then reduces to a singleton. The generalized contract
therefore retains the old recognizer's aliasing domain rather than imposing
an extra separation assumption. The scan and recognizer modules pass.
The exact current self-source and frontend relocation check also passed again
in 22.21 seconds, including all old parser functions, constants, and layouts.
Composing the preceding guards and lexer call, the following parser,
and full I/O contracts
remain unfinished. The reused lexer proof still
has legacy `native_decide` dependencies; the new generic source and transport
proofs use only standard Lean axioms.
The generic link theorem and actual self-source link check pass independently
(the latter took 20.21 s after using the reusable checker).

The compact ASCII helper now has a kernel-checked proof of its complete Core
body: string exposure, exact raw-word borrowing, decoding, local bindings,
terminating byte comparison, and both return paths. It preserves caller cells,
locals, and the host world. The body proof checked in 0.49 s. The proof exposed
an actual source bug: ordinary strings do not guarantee readable word padding.
Keyword literals now include explicit zero padding, while comparison lengths
exclude it. No memory-model relaxation was needed. Execution tests cover all
keyword spellings, every mismatch position, and the source dispatcher against
the independent lexer table, including keyword prefixes and suffixes. The
updated full self-source check and execution regressions took 19.29 s.

The helper is now composed through keyword dispatch. The general proof covers
rule choices, length branches, the fallback return, and the end-minus-start
initializer. Exact-spelling lookup is proved equivalent to the independent
lexer's keyword classifier, including its handling of non-byte integers.
`Dispatch.Checked.executes` ties that theorem to an actual Core body after
checking its matcher, padding, constants, and complete reference-table
permutation. The updated self-source check accepted all six length groups in
20.85 s. New production proofs use only Lean's standard axioms.

`Kind.result_canonicalKind` connects the callable classifier to the independent
lexer specification. The actual `canonicalize_in_place` source now passes a
proof-producing whole-body check. Its first loop has a total-correctness proof
for filtering and keyword retagging; its second loop has a total-correctness
proof for inclusive-range marking, including empty and singleton streams.
These proofs account for the caller's spare buffer capacity and fresh helper
allocations. They prove each iteration from Core execution rules rather than
assuming an abstract iteration is correct. The loop declarations checked in
0.59 s and 0.65 s respectively; these are incremental proof-build times, not
whole-extractor checking times. Their axiom audit passed without `sorry` or
project-specific axioms. `Compaction.CheckedSource.evaluates_call` now composes
both loops with local initialization, scope cleanup, the return, and the actual
function call. It proves the canonical token count, the encoded output prefix,
and preservation of the rest of the caller's capacity. The function body and
call proof declarations checked in 0.51 s and 0.46 s. Regression execution of
the checked source covers empty input, singleton keywords, all-trivia input,
contiguous and separated range operators, and several spare-capacity sizes.

The old public lexer/parser contracts still need composition in the complete
extractor. Fresh borrowed storage means the new matcher preserves caller cells
and the host world, but not literal heap/view identity; `CellEffect` states
that distinction without claiming raw-memory preservation. No whole extractor
I/O refinement theorem follows from these results alone. Milestone 3 remains
incomplete.

## Milestones and acceptance evidence

1. **Lanius extractor.** Build on the current Lanius lexer/parser. Implement
   derivation materialization, semantic analysis and lowering required by the
   embedding, and serialization in Lanius. Support the complete extractor's
   source closure; reject unsupported inputs explicitly. Differential tests
   against the Rust exporter are useful but are not a correctness proof.
2. **GPU bootstrap.** Compile that source with the existing GPU compiler and
   execute the resulting untrusted program. Host services may supply memory
   and I/O, but must not perform parsing, lowering, or extraction on its behalf.
   Record the source closure, compilation command, and executable identity.
3. **Self-extraction and extractor correctness.** Run the Lanius executable on
   its own source closure, produce the deep Lean embedding, and validate the
   source-to-embedding connection. Then prove the extractor's general
   correctness for supported inputs. An accepted embedding alone does not
   establish that general theorem. Include memory safety, failure behavior,
   and exact input/output semantics in the stated contract.
4. **Verified Lanius x86 backend.** Implement a simple backend in Lanius and
   prove that emitted machine code preserves the input IR semantics. Specify
   instruction encodings, machine state, memory, calling convention, runtime
   boundary, and supported IR. It must support the extractor, not just a toy
   arithmetic example. State any limitations explicitly.
5. **Whole compiler correctness.** Compose the frontend, lowering, and backend
   theorems into a source-to-x86 result. Cover the supported language and the
   whole compiler/extractor source closure; no omitted pass may be silently
   assumed correct. Identify environmental assumptions separately.
6. **Extractor x86 executable.** Run the verified compiler to produce it.
   Establish the connection between the exact executable bytes and the
   compiled program in the correctness theorem. A proof about the compiler
   algorithm does not alone justify an arbitrary bootstrap executable.
7. **Fast trusted extraction.** Provide an explicit trusted extraction boundary
   that relies on the established compiler/extractor correctness. The user
   permits certificates, object-file integration, or explicit extraction
   axioms as appropriate. Keep these assumptions identifiable and separate
   from ordinary kernel-checked theorems; do not disguise trusted results as
   kernel reduction. Bind results to exact source, tool version, and output.
   Measure fresh per-program extraction, emission, loading, and checking with
   only general infrastructure prebuilt. Target a couple of seconds, not
   minutes; cached prior program certificates do not satisfy this target.

## September 6 checkpoint (historical)

- `src/verified/parser.lani` is a workspace-backed Earley recognizer. The
  extractor materializes its retained derivation without reparsing and
  serializes ordered parse nodes.
- All bootstrap artifacts used by this plan are x86-64 Linux ELF executables.
  Historical Wasm recognizer tests are not part of the bootstrap or trust path.
- The former Rust `laniusc-formal-export` extractor has been removed. The
  supported syntax-certificate producer is now `src/extractor.lani`; it does
  not yet emit complete Surface/Core semantics.
- `src/verified/host.lani` is the extractor's deliberately small host boundary.
  It replaces four unrelated general-stdlib files in the proof closure and
  contains only the allocator, filesystem, argument, output, and three raw-view
  operations the extractor calls. Core syntax, typing, executable semantics,
  artifact decoding/checking, and fuel stability now model
  `i32_slice_from_raw_parts`, `i32_slice_data_ptr`, and `string_data_ptr`.
  Connecting those operations through the complete program-elaboration and
  preservation proofs remains part of the extractor execution theorem.
- On September 6, 2026 the current x86 extractor emitted its exact 18-file,
  2,331-line, 105,021-byte closure in 1.22 seconds with about 39 MiB peak
  RSS. With shared Lean infrastructure built, compact decoding plus
  proof-producing exact-source, syntax, reconstructed-Surface, source-to-Core
  lowering and whole-program x86 Core typing took 18.97 seconds
  with about 1.65 GiB peak RSS. A pruned
  postorder-origin lookup avoids rescanning irrelevant parse subtrees. These
  are major representation improvements, but the full-closure check is not yet
  the milestone-7 couple-of-seconds target.
- The self-embedding check with extractor-specific entrypoint analysis and
  ordered count/clear/pack, input-unpacking, and capacity-probe source linkage
  took 19.70 seconds.
  The loop and memory proofs
  depend only on Lean's standard `propext`, `Classical.choice`, and `Quot.sound`;
  they introduce no project-specific axiom or `sorryAx`.
- The focused input/output proof and regression build took 6.42 seconds.
  Input-loop execution tests cover every byte value at every packed-word lane,
  empty input, partial final words, preceding chunks, and unused capacity.
  After the later preservation and capacity-probe additions, the incremental
  focused build took 2.35 seconds. A Core host-call regression covers a partial
  read followed by EOF, preserving an unrelated signed buffer and the unread
  scratch tail. The impacted relational adequacy module also checks.
- File reads reuse the existing scratch slice rather than registering an
  overlapping raw view for every file. The GPU compiler also now uses narrow
  moves for known narrow scalars; unclassified values retain full pointer
  width. This fixes a native failure where an i32 argument carried stale
  stack bytes in its upper half.
- The generic checker accepts both a library without `main` and a program
  returning `42`; extractor-specific entrypoint analysis is separate.
  `writeStdout_exact` and `writeStdout_invalidRange` prove the modeled host
  output boundary. They do not prove that the Lanius packing loop supplies the
  correct bytes, or that native OS writes cannot be short.

## Previous work-sequence checkpoints

Latest parser integration checkpoint (September 7):

- Prediction now uses the invariant-selected physical token suffix throughout
  its FunctionalView execution. Its append proof preserves the backing through
  argument evaluation, and its loop-step proof shows that the suffix is unchanged.
  `Lanius.Extraction.Parser.Recognize.Prediction` builds successfully within the
  29-second command limit (`prediction-selected-suffix.log`).
- Nullable and parent traversal now build with the invariant-selected physical
  suffix (`nullable-world.log`, `parent-world.log`). Their scoped restoration,
  append argument evaluation, and all six loop transitions preserve that suffix.
  Both focused builds finished within the 29-second command limit.
- `TraversalPrefixAudit.lean` checks the traversal theorem dependencies. They
  still inherit legacy `native_decide` axioms from existing parser proofs; this
  migration does not remove that trust boundary or add a new one.
- Setup's resource-preservation code has also been migrated, but its build is
  not yet validated: it depends on the unfinished traversal migration.
- The state scanner call model now accepts a logical token prefix plus arbitrary
  spare capacity, with a full-capacity slice value and a separate logical count.
  Its generalized call theorem builds (`scan-registry-prefix.log`, 2.86s).
  Terminal append results now expose their existing no-write argument effect;
  the recognizer and call-model build passed in 9.07s, and all three traversal
  modules rebuilt together in 17.19s.
- The complete parser integration still needs state/initialization consumers
  and the full extractor composition. The first state-module check hit the
  29-second cutoff; ordinary retries stopped in favor of bounded profiling.
  The first asynchronous profile attributed 4–13s to shape-check declarations.
  A serial profile clarified that expensive concrete-command structural proofs
  contribute to those waits. Replacing native decisions with `rfl` failed and
  was reverted. Generalizing structural proofs over a command instead worked:
  branch decomposition fell from about 4.7s to 0.26s; incomplete and body
  structural proofs now take about 0.58s and 0.46s. These are profiler timings,
  not a complete successful-build benchmark.
  The normal state-module check now terminates within 29s with the outstanding
  token-buffer integration errors (`state-generic-build.log`). Generic branch
  projections retain the same source-derived command and add no trust premise.
  After migrating the state module's scoped token-storage restoration, the
  complete error-reporting build took 27.52s and about 2.46 GiB peak RSS
  (`state-generic-resource-build.log`); the restored-resource errors are gone.
  Subsequent token-world, scanner, append, and parent-return integration removed
  the remaining State.Core errors. Its first error-free attempt hit the cutoff;
  disabling `compiler.extract_closed` allowed the complete module to build in
  28.88s with about 2.58 GiB peak RSS (`state-prefix-no-closed-build.log`).
  This remains far from the desired fast checking time.
  `stateEnvironment`, `positionEnvironment`, `positionStatementEnvironment`,
  and `StateAfterBindingsEnvironment` now carry physical token capacity
  separately from logical count. State.Core rebuilt successfully in 27.88s
  (`state-capacity-environments.log`).
  State.Terminal also builds (`state-terminal-capacity.log`): scanner matching
  and source-local binding preserve the same suffix, and completed miss/append
  outcomes preserve the caller's full-capacity environment.
  State.Nonterminal now builds in 11.68s (`nonterminal-capacity.log`). Its
  prediction/nullable outcomes retain the selected physical suffix, and joining
  a restored physical frame with its functional result now explicitly requires
  equality of the token backing before and after scope restoration. The driver
  caller supplies that equality from the recorded restoration equation.
  State.Driver now builds successfully in 10.66s with about 2.19 GiB peak RSS
  (`state-driver-capacity.log`). Parent, prediction, nullable, and candidate-field
  setup preserve the physical token backing across reads and temporary bindings.
  Completed branches and scope restoration preserve the same capacity in both
  the physical state and functional environment. Explicit suffix equalities
  replace expensive implicit reduction in the combined state-step proof; no
  heartbeat-limit increase was needed. The outer position loop and initialization
  still need integration. This check validates the driver's restored-frame
  composition call, but does not establish the complete extractor theorem.
  Position.Core now builds in 8.15s (`position-capacity.log`). Its activity,
  scoped state execution, and full position loop carry physical capacity through
  normal advancement and early capacity failure. Token-backing preservation
  follows from the real cursor-binding, activity, and scope-closing effects.
  The position-update lemma remains generic in capacity. Root.Commands also
  builds in 2.15s (`root-commands-capacity.log`). Root selection and initialization
  remain to be integrated; these results do not complete milestone 3.
  Root.Selection now builds in 6.30s (`root-selection-capacity.log`). Its
  read-only field/predicate helpers accept an explicit unused suffix; candidate
  executions use the invariant's physical suffix. Cursor updates preserve that
  suffix through the synchronized root loop. Root-head initialization and the
  rejected fallback retain the caller's physical world. Position.Continuation
  now builds in 2.25s (`position-continuation-capacity.log`), including both
  local-counter bindings and the position-to-root connection. Initial.Loop now
  builds in 3.55s (`initial-loop-capacity.log`). Its shared continuation
  environment carries physical capacity separately from logical count. The
  append bridge proves token backing through argument evaluation, and successful
  seeding preserves the same suffix in the successor runtime.
  Initial.Continuation builds in 2.16s (`initial-continuation-capacity.log`),
  Recognize.Setup in 9.43s (`setup-capacity.log`), and Parser.Soundness in 1.52s
  (`parser-soundness-capacity.log`), with shared dependencies already built.
  The parser theorem states that success of a checked `recognize` call implies
  recognition by the declarative grammar. This completes this buffer-capacity
  integration through that soundness theorem, not the extractor's end-to-end
  correctness or the x86 milestones.
  `ParserCapacityAudit.lean` reports only `propext`, `Classical.choice`, and
  `Quot.sound` for `RecognizerCallExecution.success_recognizesInput`. This audits
  the implication from a supplied execution, not construction of that execution;
  inherited `native_decide` in earlier construction proofs remains a separate
  trust consideration.
  The public `parserRecognizeValues`, `parserRecognizeBindings`, and
  `parserRecognizeCallee` now take physical token capacity explicitly, and
  `executeRecognizerCall` propagates it. Previously this public boundary still
  constructed an exact-length slice despite the generalized internal proofs.
  `parserRecognizeCallee_tokenStorage` now derives callee token ownership from
  the caller's prefix-backed storage and well-formed state, using actual call
  parameter binding and cell preservation. Setup and Soundness rebuild together
  in 9.04s (`parser-call-capacity.log`). Grammar/workspace entry resources and the
  extractor's concrete call arguments still need caller-side composition.
  `Parser.Recognize.Caller.parserRecognizeCallee_resources` now constructs all
  `RecognizerResources` from caller-side grammar facts, bounds, and backing
  storage. Dense call-parameter binding supplies all six locals; call effects
  preserve the three backing buffers. The module builds in 1.65s
  (`parser-caller-resources.log`), and its axiom audit reports only `propext`,
  `Classical.choice`, and `Quot.sound`. The remaining entry obligation is
  separation of fresh parameter cells from the mutable workspace, followed by
  composition with the extractor's actual argument evaluation.
  `Separation.CallFrame.enterCall_frame_disjoint_old_cell` now proves that any
  callee local-binding frame is disjoint from a pre-existing caller cell, even
  with shadowed parameter names. It builds in 1.05s (`call-frame.log`) and uses
  only standard Lean axioms. `parserRecognizeCallee_entry` combines this with
  the resource constructor to discharge the full callee-entry obligation from
  caller facts; Caller builds in 1.70s (`parser-caller-resources.log`). Its audit
  also exposes three inherited `native_decide` assumptions from the checked
  parser parameter frame (`verifiedParserRecognizerSymbolic`,
  `verifiedParser_scoped_surface_accepted`, and
  `verifiedParser_symbolic_derivation_accepted`). No new such assumptions were
  added. Concrete extractor argument evaluation and pipeline composition remain.
  Passing State.Core does not establish the complete extractor theorem.
  Milestone 3 and the x86 correctness milestones remain
  incomplete. No new trust assumptions were added for this migration.

- The actual kind-copy/recognizer source region now has a proof-producing
  checker in `BufferCopy/RecognizeSource.lean`. It checks the cursor scope,
  triple-stride reads, single-stride writes, and the destination/count passed
  among the recognizer's six arguments. Focused tests reject wrong cursors,
  buffers, counts, and strides; they build in 1.3s. The self-embedding linkage
  check also verifies the callee is `parser::recognize` and that the copy uses
  the canonicalizer's buffer and returned token count. It passes in 20.47s
  (`recognize-source-link-run.log`). This authenticates source wiring, not
  execution of the whole pipeline. No new axioms were introduced.
  The initial integration build hit its 29s cutoff rebuilding shared proofs.
  Removing unused theorem bindings and the full lexer-correctness import from
  the runtime linkage executable reduced its dependency graph from 369 to 184
  jobs; the next build passed in 2.34s with already-built dependencies. The
  proof-producing relocation checks remain, and the correctness theorems remain
  in their proof modules. This is not a cold-build benchmark.

The complete x86 Core embedding is now synthesized from the checked Surface
values without introducing a second program copy, and it retains indexed
lowering evidence for internal functions plus checked extern construction.
Next prove the extractor I/O contract now exercised by the source-bound
self-pack and prove the Lanius extractor implementation refines
the Lean specification for every supported input, including explicit failure
behavior and memory bounds. Only after that
proof boundary is stable should the x86 backend semantics and implementation be
fixed around the actual IR required to compile the extractor.

Backend design must follow the semantics needed by the resulting extractor;
do not invent an incompatible IR just to obtain an easy backend proof.
No milestone is complete yet merely because this plan exists.

## Historical baseline

On September 5, 2026, `cargo test -j 1 --test verified_parser -- --nocapture`
passed: one GPU-compiled recognizer test, 3.27 s test execution after 25.47 s
incremental build. That historical Wasm route is not used by the current x86
bootstrap and establishes no part of the x86 trust chain.
