# Milestone 3: finish the extractor correctness proof

September 17 performance checkpoint: executable validation of the complete
22-source backend pack now takes 4.81 seconds, versus 6.84 seconds at the
preceding checkpoint and 56.75 seconds before indexing; source-to-Core
validation accounts for about 0.90 seconds. Bounded symbol matching and indexed
spelling checks are proved equivalent to the previous semantics. These are
IO results, not additional kernel source certificates. The extractor-wide
attempt stopped at the command limit during shared frontend rebuilding, before
validation. Kernel source-to-Surface acceptance remains **3/18**. See `PLAN.md`
for the measured phases, tests, accounting, and remaining work. The refreshed
kernel certificate takes 53.66 seconds, not a demonstrated kernel speedup.

September 16 context integration: the fresh three-unit Surface certificate now
uses a single-pass, kernel-proved linking plan and retains the original exact
checker result. Fresh generation/checking/output takes 47.79 seconds versus a
same-session unchanged baseline of 52.34 seconds. Reload/audit takes 2.02 seconds
and is reuse. This is a modest performance improvement, not another completed
source unit: source-to-Surface acceptance remains **3/18**, and the closed
extractor instance remains open. See the latest `PLAN.md` evidence and size
accounting; older timing checkpoints below are historical.

The complete Surface-to-Core lowering equation is now a saved kernel
certificate for all 18 proposed units and the same 125-function Core program.
Fresh proposal, quotation, lowering, composition, strict audit, and output take
84.77 seconds in one invocation with shared support and the Core candidate
available. Reload/audit takes 1.54 seconds and is reuse, not fresh checking.
The proof covers constants, layouts, target, function bodies/order, and external
policy, not merely Core typing. See the latest `PLAN.md` checkpoint.

This does **not** close 3.1 or 3.9: authenticating those Surface units against
the source bytes still covers only three of 18 units. The complete source
checker equation, closed extractor instance, general compiler preservation,
and seconds-level fresh verification remain open.

Current Core checkpoint: all 125 functions of the proposed x86 Core embedding
now have a saved kernel typing certificate. Fresh generation/checking takes
15.08 seconds with shared dependencies built; typing/audit is 4.52 seconds of
that. This does not authenticate its native source-to-Core proposal. The saved
source-bound Surface certificate still covers three of 18 units; the full
source-checker equation and closed execution/resource instance remain open.
See the current `PLAN.md` checkpoint and `BOOTSTRAP.md` commands.

September 12 acceptance checkpoint: milestone 3.7 is complete. The rebuilt
`Entry.checkSource`, including source validation and execution-proof construction,
has zero nonstandard axioms. Strict audits now forbid inherited-trust exemptions.
The exact current 18-file self-instance passes executable validation, resource
checks, and regressions in 44.36 seconds with shared proof/native imports built,
down from 87.91 seconds. This is an IO result, not a saved kernel certificate;
milestone 3.9 remains open.

Concrete certificate update: `proofs/Encoding.lean` now saves a kernel-checked
encoding and exact source-binding certificate for all 18 sources, with zero
nonstandard axioms. The complete fresh check/output now takes 58.52 seconds,
down from 75.51, with shared imports built. Scalar bounds are retained in the
quoted types instead of recomputed for every field. Loading/audit timings and
the current artifact hash are in `AUDIT.md`; reuse is not a fresh check.
This certifies the quoted structured candidate and its independently read source
bytes, not the bootstrap's transport literal. Surface/Core acceptance, the
source-checker result, and the concrete execution/resource certificate are still
missing. It is progress within 3.9, not closure of the milestone.

`proofs/Surface.lean` now saves original-checker acceptance for three frozen
units: `host`, `token_scan`, and the loop-heavy `byte_io`. One reusable recipe
replaces the former host-only file; no import-only stub remains. The combined
fresh invocation takes 46.29 seconds (September 16 baseline: 51.82),
including proposals, kernel checks, strict audits, and output, with the saved
encoding and shared imports available.
Authenticated grammar/root indexing removes repeated reference lookups without
changing the original-checker result. This is a modest improvement over the
current baseline; the historical measurement was 46.80 seconds.
Loading and auditing that certificate takes 1.34 seconds, which is reuse, not a
fresh check. All three have zero nonstandard axioms. This is three of 18 units;
whole-pack Surface/Core acceptance and the retained source-checker/execution
certificate remain open.

The representative code is 200 Lanius lines, with 205 lines of certificate
recipe and 17 of reload/audit tests. This does not fix the existing large
semantic proof bodies. Typed-token checking reuses decoder lemmas, node
validation and reconstruction share one pass, and the grammar lookup table is
authenticated once. A dependency rebuild also closed missing reconstruction
transport cases for generic parameters and extern functions. The largest unit
still consumes about 31.77 seconds within the combined run, so do not scale this
unchanged to all 125,835 nodes. Checked path witnesses now derive the original
claims-checker result without repeating its containment search. Numeric scanning
also no longer reduces an unused suffix to establish a termination measure;
its general correctness proof still checks, but this change has not demonstrated
a further whole-certificate speedup. `PLAN.md` records shared-helper growth,
focused tests and timings. The September 13 profile ruled out several local
reconstruction changes; all experimental production helpers were removed.
The subsequent typed encoding certificate reduces its bounds phase from 37.18
to 21.13 seconds; the connected Surface check above shows no overall downstream
regression. Its generic scalar lemmas preserve the original decoder/source
contracts. `PLAN.md` records the 208-line total code/config growth and remaining
collection/reconstruction costs. No additional source unit is certified.

The Lanius backend emits the complete extractor ELF; its earlier byte-identical
self-extraction took 2.12 seconds. Source-to-Core remains in Lean, and the
backend/runtime still lacks its general preservation proof. Neither the native
executable nor its fast runtime closes the remaining proof obligations.

This is the execution plan from September 7, 2026 onward. It replaces the
chronological “next work” notes in `PLAN.md`. The seven-step user goal is
unchanged; this document organizes its third milestone, not a smaller substitute.

September 11 capacity update: the expanded backend's singular source pack is
8,502,803 bytes, exceeding the old 8 MiB output cap. The production extractor
now allocates 16 MiB of logical output, and the corresponding source/allocation,
file-loop, output-domain, packing, and stdout bounds have been updated. The
existing 16 MiB packed workspace is sufficient. The new bootstrap self-extracts
the exact 18-source closure. After the subsequent proof cleanups, `Entry.Source`
and the current self-instance both pass. The 77.50-second dependent build is
incremental, not a fresh whole-infrastructure timing. The concrete saved
certificate remains the acceptance gap; this is not closure of milestone 3.

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

Within an implementation track, finish the active step's exit criteria before
starting another. The independent [x86 backend track](BACKEND.md) is now active;
the acceptance findings below remain open, rather than blocking that engineering.
Helper lemmas are subtasks, not completed pipeline boundaries.
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
Do not run the roughly 66-second source integration check for every local
lemma. Run it when the source/link boundary changes or a step closes.

## Ordered completion ledger

### Current milestone breakdown

“Complete” means that the pipeline proof is connected to the actual checked
source on its stated domain. It does not waive the milestone-wide trust and
failure-coverage requirements.

| Part | Deliverable | Status |
|---|---|---|
| 3.1 | One self-extraction, exact source binding, reconstructed embedding, and Core typing | Saved full encoding, Core typing, and 18-unit Surface-to-Core lowering; source-to-Surface acceptance is 3/18, so source-bound closure remains open |
| 3.2 | Parser workspace and backpointers to the complete reconstructed tree | Complete |
| 3.3 | Whole source-buffer-to-frontend execution, including stage failures | Complete on its stated caller domain |
| 3.4 | Extracted unit to exact accepted compact encoding | Complete |
| 3.5 | Actual main, ordered files, exact output, and preserved external inputs | Complete on the current loading/host domain |
| 3.6 | Successful termination from source syntax and sufficient resources, instantiated on the self closure | Complete |
| 3.7 | Remove inherited native-computation trust dependencies | Complete: current `Entry.checkSource` has zero nonstandard axioms, including both constituent checkers |
| 3.8 | Broader failure and host coverage | Complete on the explicit modeled-host domain, with separate allocation-exhaustion coverage |
| 3.9 | Final source/artifact, theorem, trust, and fresh-extraction acceptance audit | Audited with open findings; source provenance repaired, kernel-only acceptance remains open |

The user questioned why 3.7 was a prerequisite. Native decisions extend trust
to Lean's compilation machinery; they are not arbitrary guesses or missing
compiler-correctness theorems. Keeping them is a possible explicit trust-policy
choice, but that choice was not approved. The active whole-extractor checker and
execution constructors now need only standard Lean axioms. The separate concrete
kernel self-certificate remains open; IO validation does not replace it.

### Acceptance evidence and remaining 3.9 work

Current evidence: `entry-source-current-build.log`, `entry-trust-current.log`,
`entry-resource-final-audit.log`, and `self-source-lake-native.log` under
`target/verified-compiler`. The combined checker and whole-main execution have
zero nonstandard assumptions. `Tests.Provenance`, `Tests.Output`, and `Tests.Self`
now enforce that directly. The old 173-assumption inventory is superseded.
The current artifact hash is
`bc11dd2187755d63eb1ad4f8de4ac547c4e753f44c5142fc15f64113e62a675e`;
all ordered source bytes, source-only success resources, and output size
(7,967,195 of 16,777,216 bytes) passed executable validation. Parser/tree resource
checking fell from 37.78 seconds to 1.18 seconds after compiling the same general
checker natively. Profiling had identified interpreter dispatch as the dominant
cost. General workspace arithmetic now lives in `Compiler/Parser/Workspace`;
the actual-source execution lemmas live in `VerifiedFrontend/Parser/Workspace`.
All existing declarations are unchanged, with their contents moved, not re-exported
through compatibility files. This removes an accidental dependency on the
concrete parser from the native helper closure. `lake -d formal run check-self`
reproduces the validation; see `BOOTSTRAP.md` for arguments and build conditions.
Neither native execution nor this dependency split changes the proof trust
boundary. No `Entry.CheckedSource selfEncoded selfSources` has yet been saved
as a kernel-checked declaration. That concrete certificate is the next step.

The concrete-certificate investigation now has a shared, kernel-only
`CompactDecode.decode_renderedPack` theorem, proved by composing the existing
serializer/reader results (1.37-second module check with imports built).
Proof-only quotation of the full current 18-source data takes 16.35 seconds
after a 6.55-second untrusted decode/proposal. The equality to the large emitted
literal remains expensive: the full probe hit 59 seconds, and even an isolated
kernel equality joining both halves of the same payload hit 29 seconds.
Neither probe yielded the required saved certificate. The next step is to
resolve this representation boundary while preserving exact source binding and
the existing source-to-execution contract, not to add another trust exemption.
See the concrete-certificate checkpoint in `PLAN.md` for focused tests and logs.

The following component notes record the preceding cleanup; their open 3.7
and stale-inventory statements are historical, superseded by the checkpoint above.

The rebuilt recognizer caller is now kernel-only: `executeRecognitionRegion`
has only the three standard Lean axioms, with all 23 previously inherited
native assumptions removed. The strict audit checks the actual construction,
not merely a wrapper taking successful execution as a premise. Its explicit
grammar/resource domain and its execution, semantic-outcome, workspace, and
memory-preservation guarantees are unchanged. The initial-loop proof reuses
checked subcommands and retains exact source equalities; its fresh full module
checks in 3.14 seconds with imports built. This closes the recognizer-caller
part of 3.7. The lexer and number-scanner call constructors now also use only
standard Lean axioms, removing their 18 and 20 inherited native assumptions.
The audit checks all transitive dependencies of the scanner declarations, and
symbolic byte evaluation cuts the fresh predicate-module check from 17.27 to
5.66 seconds with imports built. The linked raw lexer and its frontend
result-count consumer are now also kernel-only: all 12 inherited native
assumptions of `RawLexer.LexInto.Linked.call_evaluates_at` are removed, with
execution, failure, exact output, spare-buffer, and frame guarantees unchanged.
The strict scanner audit now covers 73 declarations, including canonicalizer
execution and source authentication. Proven byte representatives replace
the exhaustive symbol tables, and the raw-lexer execution module shrinks from
965 to 819 lines. Its fresh check takes 1.46 seconds with imports built; the
symbol-agreement module takes 7.38 seconds. These are component measurements,
not whole-extractor acceptance times. Other extractor dependencies, the stale
whole-entry build/inventory, and the concrete kernel self-instance still keep
3.7/3.9 open. See `PLAN.md`
for code-size counts and incremental-build timing conditions.

The current connected frontend call and its source/link checkers also have zero
nonstandard axioms. `Tests.FrontendLink` now enforces that directly for six
declarations, including execution, typed-memory preservation, and negative-length
rejection; it no longer permits inherited assumptions from the execution theorem.
The existing grammar/resource domain and full postcondition are unchanged. This
closes 3.7 through `extract_syntax`, not through the enclosing extractor.
Profiling also led to a verified fast uniqueness decision and retained `Nodup`
evidence: the complete symbolic-metadata module now checks in 17.84 s versus
24.07 s with shared imports built. Its source-derivation equality is unchanged.
The dependent frontend integration and strict audits pass, but rebuilding the
invalidated shared closure exceeded 119 s; the later 52.87 s integration finish
is not a fresh-check speedup. `PLAN.md` records timings, size growth, and remaining
performance limits. Whole-entry inventory and concrete self-acceptance remain open.

September 12 parser-state cleanup: ten native-generated assumptions in six
declarations were removed by reusing `wrapSigned_i32_neg_one`, kernel-checking
function IDs, and proving constant-table entries directly. The focused
`Extraction.Tests.Parser.Metadata` audit now requires standard Lean axioms only
for all seven compact source-shape theorems and their state-body,
incomplete-branch, scan-miss, terminal-success/full, and cursor-advance semantic
consumers. It also audits LHS accessor routing. The semantic consumers previously
had a union of nine inherited native assumptions; all nine are gone. Their
statements and source connections are unchanged. No new axioms or Lanius code
were introduced. The affected dependency rebuild and audit passed in 81.79
seconds; a fresh state-module check with imports built took 24.85 seconds,
down from 32.33. See `lean-compact-clean-trust.log` and `lean-compact-final.log`
under `target/verified-compiler`. This does not close 3.7 or refresh the
whole-extractor inventory. The proof-size reduction is recorded in `PLAN.md`.

The subsequent semantic-proof refactor preserves those contracts and extends
the standard-axiom audit to environment preservation, subtraction, indexed reads,
the position-loop condition, and its shared comparison rule. Transparent evaluator
wrappers let these use the existing automation directly. Nine proof bodies shrank
from 208 to 23 lines, and a fresh state-module check fell to 22.93 seconds with
imports built. The full recognizer caller path rebuilt after the change; neither
this refactor nor that build closes the remaining native-trust or self-instance
acceptance obligations.

The scoped-binding/call-argument follow-up removes another 422 lines from eight
proof bodies without changing their statements. The standard-axiom audit passes,
including the shared call rule and source-connected terminal branches. Fresh
state-module checking is still about 26.7 seconds, with no demonstrated overall
speedup. The combined dependency/caller rebuild reached the 119-second cutoff
before the final setup/caller modules finished; its partial success does not
close integration, 3.7, or 3.9. Counts and measurement conditions are in `PLAN.md`.

The reifier now reuses child typing witnesses for scalar operators, casts,
calls, structs, indexing, field reads, and read-only statement composition,
preserving the general typed, exact-source result contract. Fresh state-module
checking measured 24.37 seconds after scalar reuse and 23.18 after the follow-up,
with imports built. The full caller path and transitive audits pass; the latest
incremental integration check took 108.01 seconds. This closes the previous
checkpoint's unfinished rebuild, not milestone acceptance. All nine
native-decision sites in the root command module now have kernel proofs, and
the strict transitive audit covers all nine owners. No statement was weakened.
The whole-extractor inventory and concrete self-instance kernel acceptance
remain outstanding. Size changes and measurement conditions are in `PLAN.md`.

The ownership follow-up removes 232 program-specific proof lines without changing
the candidate-binding or parent-entry contracts. It also replaces the two native
accessor constant-table proofs and the three remaining root-selection native
sites with kernel proofs. All five owners, plus the actual binding and parent-entry
proofs, now pass the standard-axiom audit. Connected caller integration passes;
fresh state-module checking remains about 23 seconds with imports built.
These are local size/trust improvements, not a refreshed whole-extractor inventory
or closure of 3.7/3.9. Exact counts and timing conditions are in `PLAN.md`.

September 12 Decimal cleanup: 29 `native_decide` sites across 27 declarations
now use kernel-checked `decide` proofs. The connected `Extraction.Tests.CallTrust`
audit confirms that the number-scanner call proof no longer inherits native
assumptions from those owners. All 24 routing owners have no locally generated
native assumptions; the three ABI projections use only standard axioms. The
final constructor-routing check passed in 22.05 seconds
(`trust-decimal-constructor-routing.log`). Body simulation, reification, and
the concrete self-validation boundary remain open. This local audit is not a
new whole-extractor assumption count and does not close 3.7.

The [acceptance audit](AUDIT.md) found and repaired missing source provenance
in the returned Core certificate. `Entry.CheckedSource` now retains the exact
source-checker result beside the actual entrypoint and execution proof.
`SourceBound.metadata` derives the Surface/preparation/layout relationships,
and the full construction equation binds constants and functions as well.
`CheckedSource.coreUnique` rules out substituting a different Core for the same
inputs. `Entry.checkSource` runs each existing stage once; the self-check now
consumes that combined result directly. No second parse or synthesis was added.

The new provenance/checker build passed in 2.04 seconds; focused checks in
2.54 seconds. Full integration passed in 88.78 seconds, including 19.550
seconds for wrong-path, changed-byte, and reordered-source rejection tests.
The broader inventory of the combined source/execution checker still has 173
native assumptions in 158 owners. New provenance proofs use standard axioms.
Artifacts and Lanius sources are unchanged. See the audit for exact evidence.

Final kernel-only acceptance has another explicit limitation: the concrete
self-validation currently runs Lean's checker in IO. It is not a standalone
kernel-checked proof artifact for the concrete self-source instance. Clearing
shared `native_decide` dependencies alone would not close that boundary.

The audit records the public contracts, source construction, complete trust
footprint, artifact identities, and actual host/resource assumptions. Do not
add more isolated failure cases without identifying a gap in the exhaustive
host-domain partition below. The inherited native assumptions remain the
separate open 3.7 obligation; passing source integration does not discharge them.
Milestone 3 and the seven-step compiler goal are not complete.

### Completed step: 3.8 — exhaustive modeled-host coverage

`HostDomain.classify` proves that every invocation in the explicit host domain
has no input files, satisfies the existing loading domain, or has a first
invalid/missing/oversized file after a loadable prefix. It neither parses input
nor assumes that any earlier file executes successfully.
`CheckedExecution.hostSafe` combines that exhaustive partition with the actual
main proofs. Its `ExecutionSafe` result retains a finite stable normal return,
no traps at any fuel, and the original `RunSound` and `RunFailureSafe` contracts.
The existing successful-input `RunComplete` theorem remains unchanged.

The assumptions are explicit in `Entry/Domain/Host.lean`: argc is below 2^31,
requested path lengths fit signed i32, all potentially opened handles fit
signed i32, and old handles are below the next fresh handle. File availability,
file size, source syntax, and accepted output are not assumptions. Execution
starts from the ordinary empty, unlimited-budget heap. The separate
`CheckedExecution.allocationFailure` theorem covers finite allocation exhaustion;
the unified theorem does not cover arbitrary finite-budget successful heaps.
The deterministic modeled host has no concurrent file changes, asynchronous
read/close errors, or short stdout writes. This is not a native Linux I/O proof.
Specialized earlier-rejection theorems still work under weaker handle conditions.

The last missing repeated-file case is also connected. `File.Rejection` now
includes oversized files, and `File.Rejection.afterFile` derives all resources
from the real completed iteration. `Files.rejectsAfter` uses the existing
induction for every rejection kind; `Startup.rejectsAfter` and the public
`CheckedExecution.laterFailure` carry it through main. The public domain checker
accounts for the additional handle required to open an oversized file. Earlier
frontend/encoding failures may return first; otherwise overflow returns 6 after
close and the actual diagnostics. No assumed prefix execution was introduced.
`Next.inputNext` now supplies common loading resources without a file-fit premise;
successful callers add that premise directly. No compatibility wrapper remains.

Verification on September 10:

- The changed main/checker proof built in 26.06 seconds. The host partition and
  public execution theorem built in 2.44 seconds. The final affected self-test
  build passed in 6.54 seconds (`host-tests.log`).
- Later-file domains admit 19 worlds and reject 19 false prerequisites. Nine
  interpreted loading loops cover rejection after 1, 3, and 10 preceding files,
  including exact diagnostics and preserved dirty buffers, handles, and stdout.
  The test scales the reader-call capacity to its eight-element buffer; an
  initial mismatched fixture caused a bounds trap and was corrected. The reader,
  close, and diagnostic implementations are unchanged. Twelve native x86 tests
  retain the production capacity and pass in 1.61 seconds (`later-oversize-native.log`).
- The host-only checker admits 19 varied worlds and rejects three invalid handle
  states. The actual-source test instantiates the unified theorem on all 19 and
  on the real self-source world. All new domain/resource/composition proofs use
  standard axioms; the complete source-checker inventory remains 173 inherited
  native assumptions in 158 owners (`host-trust-inventory.log`, 0.85 seconds).
- Full exact-source integration passed in 69.02 seconds (`host-self-source.log`),
  retaining successful extraction and exact output for all 18 sources. Parser/tree
  checking took 38.191 seconds; output bounds 441 microseconds; exact input binding
  16.309 milliseconds. Shared infrastructure was built. This is bootstrap
  validation, not the eventual fast trusted path.
- Fresh x86 self-extraction passed in 1.15 seconds (`host-fresh-extraction.log`)
  and `cmp` found it byte-identical to the singular embedding. The source,
  executable, embedding, envelope payload, and source-list identities are unchanged.
  Every command stayed below two minutes; `git diff --check` passed.

Current SHA-256 identities:

- Lanius entry source: `a27bc4964928bb387a46e4f61271d7721780d3eafad6406a7fecc1facdea82c4`
- x86 bootstrap executable: `327f8376d70478ad36e07476662c965c0139f7b15e9b07f2c63532a21c5c75b0`
- singular embedding: `f6d7a1316a231e86588bc673ae002a1aa115afa6223b9b30c666fe1b751b5270`
- envelope payload: `10016296f6b01b675529db80ed39ea000a4af95c3d7a01dfbb70c419e1b6d821`
- ordered source list: `079059b1eb54011de70900c1c5a9f7d411a027c7166728a95b55aef461a77bf3`

### Earlier 3.8 checkpoints

`CheckedArguments.rejectsNoInputs` proves that the actual argc/guard sequence
returns code 1 when argv has zero or one entries. Its arbitrary continuation
never executes. The source theorem works from a well-formed state with an empty
view registry, without file availability, handle freshness, or allocation-room
premises.

`Entry.Run.call` now supplies the shared actual-entrypoint call connection for
both normal loading and early rejection. `CheckedExecution.noInputs` constructs
a `RejectedExecution` for the accepted executable. It retains finite execution,
classified failure, and memory safety. Its public `terminates`, `observations`,
and `contracts` theorems provide a stable code-1 return above a finite fuel
bound, exclude traps at every fuel, and establish `RunSound`/`RunFailureSafe`.
`noInputs_world` proves that the only external change is the argc call event;
files, handles, outputs, arguments, and other world fields are unchanged.
The successful-input theorem and its loading conditions are unchanged.

Six focused cases cover empty/singleton argv, pre-existing output, files and
handles, collisions, and an unrepresentable future handle counter. The test
also checks that two argv entries enter the continuation and that a modified
guard cannot reuse the exact-source proof. All new rejection/call/contract
proofs pass a standard-axiom-only audit. The first build caught a dependent
rewrite error (103.42 seconds including pending dependency rebuilds); the
corrected focused build passed in 26.45 seconds (`failure-no-inputs-check.log`).

The public checker and self-test build passed in 7.85 seconds
(`failure-self-build.log`). Actual-source integration passed in 68.59 seconds
(`failure-self-source.log`): the exact extractor passed all six rejection cases,
and all 18 sources still satisfy the existing successful-input guarantee.
Parser/tree resources took 37.106 seconds; output bounds 587 microseconds;
exact input binding 16.713 milliseconds. This is not the trusted fast path.
The refreshed whole-checker audit is 173 nonstandard assumptions in 158 owner
declarations (`failure-trust-inventory.log`); the decrease from 207 reflects the
earlier parent/nullable cleanup. The new rejection proof adds none.

#### Allocation exhaustion: complete, including actual-main linkage

The source-order bug is fixed in all 13 allocations. Each buffer now has an
outer slice binding and a short pointer scope: allocate raw bytes, return code
3 if the pointer is null, then construct and assign the slice. The temporary
pointer leaves scope before the next allocation. The old combined null guard
after slice construction is removed, along with its checker and proof code.
There is no fallback accepting the unsafe source form.

`Registry.allocateRaw`, `allocationExhausted`, and `mapRaw` separate raw
allocation from registration and account for both host synchronization passes.
`Step.initializes` establishes valid buffer resources on success;
`Step.rejectsExhaustion` proves a normal code-3 return before slice construction.
The sequence theorem covers failure at any allocation, retaining earlier valid
buffers and skipping the remainder. `HostReady` now records the initialized
buffer after the pointer scope closes, so downstream buffer contracts survive
without retaining pointer temporaries or duplicating initialization proofs.

`CheckedExecution` retains the exact allocation source certificate and derives
its buffer metadata from that certificate. Its public `allocationFailure`
theorem connects the complete sequence to the actual checked `main`. From a
well-formed state with empty locals/views, a representable argc greater than
one, and an insufficient byte budget, it constructs a `RejectedExecution`
with code 3. The existing all-fuel contracts and finite termination theorem
apply. The world changes only by argc and the allocation-call events; files,
handles, arguments, and both output streams are preserved. It assumes neither
file availability nor handle freshness. This is modeled allocation exhaustion,
not arbitrary native OS allocation or I/O faults.

The source change also exposed a missing uninitialized-local case in the
structural execution relation used by entrypoint analysis. `CoreSuccess` now
supports that case with proofs in both directions to the authoritative
evaluator. The prefix and return-composition rules cover the same scope.
Slice validity and the classification of traps are unchanged.

Verification:

- The GPU compiler produced the updated x86-64 ELF in 2.51 seconds. Native
  self-extraction took 1.25 seconds; regenerated parser envelopes took 0.92.
  The canonical `lanius-extractor` executable was rebuilt and is byte-identical.
- Twenty-five small byte budgets exercise first/second allocation failure,
  exact capacity, and excess capacity. Mutations reject missing, changed, or
  late guards, including the old slice-before-check form. A focused rebuild
  and strict axiom audit passed in 1.54 seconds (`allocation-tests.log`).
- The final shared checker/test build passed in 7.45 seconds
  (`allocation-self-build.log`). Earlier rebuilds caught a missing prefix
  constructor and the entrypoint support gap; neither was bypassed.
- Full exact-source integration passed in 66.88 seconds
  (`allocation-self-source.log`). All 18 files retain successful termination
  and exact-output guarantees. The actual main also passed four exhausted
  budgets, including failure after the first buffer was registered, and all
  six no-input cases. Parser/tree resources took 36.588 seconds; the output
  bound is 7,967,185 / 8,388,608 bytes, checked in 434 microseconds. Exact input
  binding took 16.572 milliseconds. This remains bootstrap validation, not the
  trusted fast path.
- All new allocation and public rejection proofs use only standard axioms.
  The whole-checker inventory remains 173 native assumptions in 158 owners
  (`allocation-trust-inventory.log`); 3.7 is still open.

Current artifact SHA-256 values:

- `SelfCompactExtracted.lean`: `f6d7a1316a231e86588bc673ae002a1aa115afa6223b9b30c666fe1b751b5270`
- `self-envelopes.bin`: `10016296f6b01b675529db80ed39ea000a4af95c3d7a01dfbb70c419e1b6d821`
- `source-closure.txt`: `079059b1eb54011de70900c1c5a9f7d411a027c7166728a95b55aef461a77bf3`

#### Invalid first path and missing first file: complete through main

`Files.CheckedSource.reaches` enters the actual file loop. `Files.First`
retains that prefix from the proved startup, and `First.completeReturn` lifts
a first-body rejection through the loop and all enclosing main scopes. The
ordinary file-loading domain is not needed to construct this evidence.
`LoadingSource.pathBuffers` derives the two path buffers and their pointer
from the same executed startup allocations. `CheckedExecution.firstFile`
retains both the prefix and those buffers; it does not assume file availability
or reconstruct an independently supplied intermediate state.

`CheckedExecution.invalidPath` proves that an empty or oversized first path
returns code 2 before argument copying or file opening. It reuses the existing
`Path.Length.Stage.rejects` theorem. The remaining premises are a representable
argc greater than one, selection of the first path, and a path byte count at
most 2,147,483,647. The invalid byte count is zero or at least 1,025.

`Host.File.evaluatesMissing`, `File.Open.Stage.rejectsMissing`, and
`File.Load.Pipeline.rejectsMissing` prove the missing-file branch from the
modeled host through the complete length/copy/unpack/open prefix.
`CheckedExecution.missingFile` connects it to the actual accepted main: a
first path of 1–1,024 UTF-8 bytes absent from the modeled filesystem returns
code 5. No handle bound, handle freshness, file-size condition, or assumption
on later arguments is required. No read or close occurs and no handle is made.

Both public theorems construct `RejectedExecution`, so finite termination,
stable return codes, all-fuel absence of traps, and the existing soundness and
failure-safety contracts follow. They preserve every world field except the
explicit call trace, including pre-existing output. They use the ordinary
empty, unlimited-budget initial heap; the separate allocation-failure theorem
continues to cover insufficient finite budgets.

Focused checks cover ASCII and multibyte paths at both sides of the 1,024-byte
limit, missing guards, changed limits, and changed return codes. Six composed
missing-file runs cover ASCII/UTF-8 paths and handle counters 0, 2,147,483,647,
and 2^80, with an existing negative handle and dirty output. All new proofs
pass standard-axiom-only audits. The final affected build, including the
public checker and self-test, passed in 6.34 seconds (`missing-tests.log`).

Native x86 bootstrap smoke checks returned code 2 for empty, 1,025-byte ASCII,
and 1,026-byte UTF-8 paths, and code 5 for absent 1,024-byte paths and an absent
short path. All produced zero stdout bytes. These are execution tests of the
untrusted bootstrap, not proofs of native x86 correctness.

The final combined path/open integration accepted all 18 exact self sources
in 70.30 seconds (`missing-self-source.log`), retaining successful termination
and exact output. Both new rejection theorems were instantiated on the actual
accepted source, and the six missing-file prefix executions used its checked
host functions. Parser/tree resources took 39.088 seconds; output bounds took
563 microseconds and exact input binding took 17.167 milliseconds. This is
bootstrap validation with shared infrastructure built, not the trusted fast path.
A fresh native self-extraction took 1.23 seconds and was byte-identical to the
singular embedding. The source, native executable, embedding, envelope payload,
and closure identities are unchanged.
The whole-checker inventory remains 173 assumptions in 158 owner declarations
(`missing-trust-inventory.log`); this work does not close 3.7.

#### Invalid or missing paths after a loadable prefix: complete through main

`Path.Rejection` states an external reason to reject a selected argument:
an empty/oversized path or a valid-length path absent from the filesystem.
It contains no assumed execution. The reason remains true when preceding
iterations preserve argv and file contents.

`File.Next.pathBuffers` derives the next path buffers from a completed file's
existing handoff, including any additional registered views. It does not
require that the next file exists. `Files.rejectsAfter` then executes any
nonempty loadable prefix by induction through the actual checked file bodies.
Each iteration either returns its existing frontend/output failure or passes
its buffers and cursors onward. After the prefix, the bad argument takes the
proved code-2/code-5 branch. The theorem does not assume the prefix parses or
extracts successfully.

`Startup.rejectsAfter` derives the first file resources from the existing
startup proof and lifts the loop's return through main's actual lexical scopes.
`Entry.checkExecution` retains the result in `CheckedExecution.rejectsLater`;
`CheckedExecution.laterFailure` exposes a `RejectedExecution`, so the existing
finite-termination and all-fuel contracts apply. Files, original handles, argv,
and stdout are preserved. A preceding frontend failure may write diagnostics
to stderr. The suffix and stdout-emission phases do not execute.

The new `LaterFailureDomain` requires a representable argc, a nonempty prefix
with valid path lengths, available files of at most 65,536 bytes, and enough
representable fresh handles to open that prefix. It imposes no syntax or
successful-run condition on the prefix and no conditions on arguments after
the designated bad path. `checkLaterFailureDomain?` reuses the existing ordered
file-loading checker to produce this proof from world data and the selected
argument index; it neither reparses files nor adds a second extractor.

Eleven accepted domain cases and ten rejected mutations cover repeated paths,
arbitrary prefix syntax, empty source files, UTF-8/oversized paths, missing
prefix files, false rejection claims, index errors, oversized prefix files,
handle collisions, and counter exhaustion. A one-file prefix may consume handle
2,147,483,647 before a missing-file rejection, which itself needs no new handle.
Four small interpreted loading/advance loops check dirty-buffer reuse, exact
stopping cursors, unchanged output and old handles, and absence of tail calls.
The whole frontend/emitter behavior is supplied by the universal loop proof,
not by those smaller fixtures. The boundary executions also run with the
accepted source's host and reader helpers in self integration.

The final affected self-test build passed in 3.04 seconds (`later-tests.log`).
Four native x86 bootstrap runs also returned code 2 or 5 after one or three
real preceding source files, with no stdout, in 0.28 seconds combined. These
are bootstrap execution tests, not native x86 correctness proofs. The new
resource/domain proofs use standard Lean axioms; loop/main composition adds
nothing beyond the existing frontend baseline. The whole-checker inventory
remains 173 assumptions in 158 owners (`later-trust-inventory.log`).

Full source integration passed in 72.05 seconds (`later-self-source.log`).
All 18 exact self sources retain the successful-extraction guarantee, and the
new public rejection theorem is instantiated on all 11 admitted worlds.
Parser/tree resources took 39.707 seconds, output bounds 884 microseconds,
and exact input binding 17.040 milliseconds. Shared infrastructure was already
built; this is bootstrap validation, not the eventual trusted fast path.
The Lanius sources, native executable, singular embedding, envelope payload,
and source-closure identities are unchanged. Every command stayed below two
minutes and `git diff --check` passed.

#### Oversized first file: complete through main, close, and diagnostics

`Input.File.rejectsLoop` proves that every oversized file terminates with
reader result -2 after consuming exactly capacity plus one bytes. It handles
arbitrarily many preceding read chunks. The overflowing chunk is never copied;
earlier copied chunks remain a bounded prefix of the source. The reader's
single initialization and call proofs now cover both fitting and oversized
files. Their shared result retains exact host consumption, buffer contents,
caller storage, and memory safety. Successful callers still obtain all bytes.

`File.Load.Available` separates physical loading resources from the file-size
condition in `File.Load.Input`. `LoadingSource.available` derives those resources
from the same real startup allocations; successful loading adds its size bound.
`Pipeline.prepare` and `Stage.readClose` own the shared path/open and read/close
prefixes. Their former success-only implementations were moved into these
shared proofs, not copied behind compatibility wrappers.

`Diagnostics.Read.Checked.oversized` executes the actual two diagnostic calls
and conditional error-detail expression. It reuses the existing decimal
formatter proof. `Pipeline.rejectsOversized` composes the full path, opening,
read, mandatory close, diagnostics, and code-6 return. `Startup.rejectsOversized`
constructs its input and closes the actual main scopes. `Entry.checkExecution`
authenticates the diagnostic source and retains the resulting theorem.
`CheckedExecution.oversizedFile` exposes a `RejectedExecution`, including finite
termination, all-fuel absence of traps, classified failure, preserved files,
argv, original handles, and stdout. Only stderr and its trace may grow after
the file is closed.

The public domain requires a representable argc, a first path of 1–1,024 UTF-8
bytes selecting an existing file larger than 65,536 bytes, a representable new
handle, and older handles below that counter. It starts with an empty,
unlimited-budget heap. It imposes no syntax condition on the oversized file
and no conditions on later arguments. `checkOversizedFileDomain?` constructs
the domain from world data without parsing or executing the extractor.

Verification:

- Five admitted worlds and nine rejected mutations cover file-size boundaries,
  invalid path byte lengths, missing files, absent arguments, handle collision,
  and the largest representable handle. Four actual-source mutations reject
  removed diagnostics, skipped failure handling, wrong writers, and wrong
  count locals. Three fault-injected reader results test the caller's close,
  diagnostic text, skipped frontend, and dirty-buffer preservation separately
  from the universal reader proof and existing 90 reader boundary executions.
- The final affected self-test build passed in 2.74 seconds
  (`oversize-tests.log`). All new proofs pass standard-axiom-only audits.
  The whole-checker inventory remains 173 native assumptions in 158 owners
  (`oversize-trust-inventory.log`, 0.91 seconds); 3.7 remains open.
- Eight native x86 bootstrap runs passed in 1.12 seconds combined
  (`oversize-native.log`). Files of 65,535 and 65,536 bytes reached frontend
  rejection (28); 65,537 and 131,073 bytes returned 6 with exact overflow
  diagnostics. Each ran both first and after a valid file, with zero stdout.
  The later-file runs are native smoke tests, not a later-file main proof or
  proof of x86 code generation. Binary fixtures are generated by the Lean
  native-test driver; no compiler source is generated.
- Full exact-source integration passed in 67.50 seconds
  (`oversize-self-source.log`), retaining success for all 18 files and
  instantiating the new public rejection theorem on all five admitted worlds.
  Parser/tree resources took 36.958 seconds; output bounds 462 microseconds;
  exact input binding 16.564 milliseconds. This remains bootstrap validation,
  not the trusted fast path.

The Lanius sources, x86 bootstrap executable, singular embedding, envelope
payload, and closure identities are unchanged. No command exceeded two minutes.
Builds caught and corrected type/projection issues and a diagnostic-branch
coverage gap; none was bypassed or replaced with an assumed execution.

The later-file extension and exhaustive host-domain partition are now complete
as recorded above. Final milestone acceptance, inherited trust cleanup,
backend verification, and the trusted fast path remain open.

### Previous checkpoint: inherited trust cleanup

Whole-run successful-input completeness is now connected to the public
executable certificate and instantiated on the actual self-source world.
The remaining milestone-3 acceptance work is broader failure/host coverage
and removal of the inherited nonstandard assumptions. The earlier work order
put trust cleanup first; the current failure-coverage step above supersedes it.
Backend verification and the trusted fast path remain later milestones.

At this checkpoint the fully rebuilt whole-checker inventory contained 207 nonstandard
assumptions in 176 owner declarations (`trust-structural-inventory.log`), down
from the previous 328 in 249 declarations and the original 463 in 264. These
are legacy native decisions, not new hypotheses introduced by the completeness
proof. The combined public-checker build passed in 107.34 seconds
(`trust-restored-checker.log`), including strict source-linked parser metadata
audits. The existing equality-certificate API is unchanged; its implementation
was restored byte-for-byte after an integration run caught a file-path mistake.
New Boolean-equality lawfulness proofs live in `Core/Equality/Lawful.lean`.

The shared infrastructure boundary is now closed for Core structural equality.
Lean's derived equality for nested Value/Pattern/Expr types uses opaque partial
definitions: native execution can compare them, but kernel reduction cannot.
Those instances now use total structural recursion. `Core/Equality/Lawful.lean`
proves that acceptance is equivalent to propositional equality for all inputs, then
derives lawful equality for statements, functions, constants, and programs.
Float literals retain exact bit identity, and every AST field participates.
The implementation replaces the canonical instances; there is no second
consumer-specific equality or correctness axiom. The final Core/equality/test
build passed in 11.44 seconds; 12 closed cases also compute in the kernel and
agree with native execution (`trust-core-structural-equality.log`).

The live-frame issue needed a separate change: move non-recursive dispatch out
of the mutual access-analysis block and use structural recursion for the actual
tree traversals. The general assignment equation is preserved. Six focused
cases cover reads, writes, compound places, match binders, local binders, and
range binders. The actual parser root/caller frames and recognizer-to-extracted
AST equality now pass strict standard-axiom audits, together with the cached
data's exact source-derivation connection. `Symbolic.lean` checks in 2.5 seconds;
the complete focused metadata build took 55.39 seconds
(`trust-single-pass-metadata.log`).

Cold cache construction remains about 51 seconds and produces a 29 MB module.
An object-sharing pass did not reduce it and was removed. Retaining the optional
derivation result avoids a separate success-first API, but did not materially
reduce that timing. The full cold dependent build still exceeds the command
limit in earlier attempts; the combined rebuild above now passes. The grammar
validator now contains no native decisions; its affected build passed in 32.67
seconds, including 13 seconds for the validator itself
(`trust-kernel-validation.log`). Its production, symbol, nonterminal, and listed
production loop frames pass strict standard-axiom audits. Whole-recognizer
reification now also builds without native decisions (3.7 seconds).

The state-loop conversion initially left three failures when comparing renamed
nested commands. The first affected build failed in 82 seconds. Structural
command renaming and command comparison alone did not resolve them (60.99-second
failed build). Making term renaming structural too, with an explicit argument
list traversal, resolved all three. The general term evaluation, command
execution, and Core-correspondence theorems still check; the list traversal is
proved equal to mapping the same renaming function. Focused kernel/native tests
cover nested arguments and lexical binding under an enlarged environment.
`Parser/Recognize/State/Core.lean` now has no native decisions and checks in
48 seconds; the affected build passed in 64.79 seconds
(`trust-structural-state-renaming.log`). The combined public-checker rebuild and
whole-dependency axiom inventory above confirm that these removals reach the
actual extractor theorem. Actual self-source integration now passes in 67.28
seconds (`trust-structural-self-source.log`), after an 8.55-second test build.
All 18 exact sources satisfy the public successful-input domain; the whole-run
theorem, ordered file/output connection, failure classifications, and memory
safety checks remain connected. Parser/tree resource validation took 37.412
seconds. This checkpoint reduces native trust, not that end-to-end runtime.
The largest remaining trust owners are parent replay, nullable replay, lexer
calls, and initialization;
they are next, not a reason to weaken the milestone's acceptance condition.

Measure the replacements and optimize any expensive reduction before repeating
a timed-out build. Audit the complete `Entry.checkExecution` dependency closure,
not just certificate projections. Broader failure/host coverage remains after
trust cleanup; this work does not replace any later compiler milestone.

### Current checkpoint: successful whole-run completeness

`Entry.Startup.executes` now proves a zero return on `SuccessDomain`, in
addition to its existing soundness, failure safety, and finite termination on
`LoadingDomain`. The source-only success domain states syntax and concrete
token/parser/tree/output bounds for the exact ordered requested files. It
contains no premise that a stage succeeds, an output is accepted, or a run
has already occurred. Initial heap and host conditions remain explicit in
the separate loading domain.

`File.Progress` retains frontend success, output sufficiency, and the actual
resulting cursor. `Files.Progress` carries those facts through every requested
file and reserves space for the final suffix. The proof derives successful
suffix emission from that remaining space. Existing source execution proofs
are strengthened directly; there is no second file loop or serializer.
Source-domain definitions and their existing file-resource proofs now live
below the entrypoint checker, without duplicate bodies or forwarding wrappers.

`CheckedExecution.run_complete` exposes the original `RunComplete` contract
for every fuel above a finite bound. `CheckedExecution.succeeds` applies it to
checked loading and successful-input conditions. `Entry.checkExecution`
constructs this stronger certificate from the actual checked source entrypoint.
`CheckedOutputDomain.checkSuccessDomain?` binds the already proved resource
domains to the process's exact source paths and bytes; it performs no lexing,
parsing, or resource analysis again.

The affected source/checker build passed in 5.64 seconds. The self-test build
and audits passed in 4.04 seconds (`completeness-self-build.log`). Full source
integration passed in 67.91 seconds (`completeness-self-source.log`): all 18
inputs satisfy the public successful-input domain, and the actual executable's
`RunComplete` guarantee is instantiated. Parser/tree resources took 37.402
seconds, output bounds 420 microseconds, and input binding 15.968 milliseconds.
Eleven admission cases cover changed bytes, order, missing/repeated requests,
host lookup precedence, and irrelevant host state. The actual file/main/checker
construction adds no assumptions beyond the existing frontend baseline;
the new domain and public contract proofs use only standard Lean axioms.

This closes ledger step 5, not milestone 3. Broader external failure coverage
and inherited trust obligations remain. The proof concerns the Core/host model,
not native x86 execution. The source, executable, and artifacts are unchanged.
The timing assumes shared infrastructure is built and is not the trusted fast
path or evidence that a cold build stays below two minutes.

### Previous checkpoint: source-only output sufficiency

All 18 self-source files now have ordered output bounds. Including the exact
module prefix, 16-byte pack header, and suffix, the proved bound is 7,899,213
bytes against the existing 8,388,608-byte allocation. No allocation, source,
artifact format, or executable changed. The bound happens to equal the current
emitted module's size, but neither that size nor its selected trees are inputs
to the resource proof.

`CompactOutput/Size.lean` proves the exact wire-size algebra for the existing
serializer. For tree records, three times the encoded byte count equals
sixteen times the physical word count plus thirty-two times the node count.
`emission_encoding_size` includes path/source bytes, both token streams,
semantic assignments, and all count fields. `File.Resources.encoding_bound`
applies the result to the actual frontend-selected tree and unit emitter.

The earlier canonical-span raw-token budget overestimated total output by
542,424 bytes and missed capacity by 53,029 bytes. `TokenArtifactValid` now
retains the raw lexical fact already proved by `checkTokenArtifact_sound`
when raw rows are present. The runtime token check is unchanged. Canonical-only
syntax remains supported, but the output-budget checker requires raw evidence
and rejects its absence. It never reruns tokenization.

`CheckedParserTreeStorage` and the ordered `CheckedParserTrees` retain tight
word/node/depth bounds along with their physical-capacity proofs. Root maxima
are numerical proposals; the existing root checker independently validates
them for every possible start production. Internal consumers use the new
records directly, with no old-interface wrapper. `Frontend/Storage/Output.lean`
derives source-only bounds for every recognized tree. `CheckedTreeDomain`
retains this evidence for `checkOutputDomain?`, whose final pass only reads
lengths and sums budgets.

Focused tests cover serializer-size agreement for empty, wide, nested,
split-reference, and UTF-8 fixtures; exact-fit and one-byte-short module
capacities; and missing or forged raw evidence. The new size, resource,
ordered-domain, and actual-emitter proofs use only standard Lean axioms.
The existing 463-assumption frontend baseline is unchanged.

The final self-test build passed in 6.55 seconds (`output-self-build.log`).
Full source integration passed in 65.63 seconds (`output-self-source.log`),
including 36.684 seconds for parser/tree resources and 419 microseconds for
the output domain. This does not demonstrate the eventual trusted fast path.
The executable, singular embedding, envelope payload, and source-list hashes
are unchanged; `git diff --check` passed. No Rust, Python, or Wasm was added.

Broad dependency rebuilds hit the 119-second cutoff. Profiling isolated a
5.85-second kernel check in grammar-validation composition. Named counter-cell
equalities replace broad unfolding of preceding execution records: the
module's serial check fell from 15.80 to 10.18 seconds, kernel time from 7.23
to 1.67 seconds, and peak RSS from 3,524,776 to 1,958,244 KiB. A subsequent
broad rebuild still timed out; cold dependency-chain rebuild performance is
not fixed. The final incremental build is not evidence of a sub-two-minute
cold rebuild.

### Previous checkpoint: tree resources and actual frontend success

All 18 self-source files now satisfy `Entry.TreeDomain` as well as the existing
token, syntax, and parser domains. `File.Resources.frontend_success` proves that
the actual frontend return has stage zero on these source-only conditions.
No successful parser/materializer result is assumed by the caller. This closes
tree resource sufficiency, not whole-extractor successful termination.

`Parser/Tree/Bounds/Cost.lean` gives the exact node, word, and depth algebra for
the existing materializer. A child includes its three-word parent reference;
the root's physical record size is therefore its cost minus three words.
`treeCost_layout` and `forestCost_layout` prove this correspondence.
`BoundedChart.root` bounds every declaratively recognized full-input tree,
including the source-selected root, by induction through scans and completions.

`Bounds/Propose.lean` calculates potentials over the existing finite chart's
dependency graph. It adds no chart items and performs no recognition. Duplicate
items are normalized, missing advances are rejected, and cyclic dependencies
fail. The proposal algorithm is not trusted. `Bounds/Check.lean` independently
checks every transition inequality, every completed item's coverage by its
span/nonterminal summary, and every start-production root bound. A forged
summary cannot omit an expensive alternative derivation. The array-backed
terminal scan now lives in `Compiler/Parser/Scan.lean`, shared directly by the
chart and resource checkers without an import-only wrapper.

`Frontend/Storage/Tree.lean` turns accepted budgets into source-only bounds for
all recognized trees. `CheckedExecution.checkParserTreeDomain?` validates chart
closure once and retains both parser and tree domains, reusing the already
accepted source/token evidence. It uses the existing envelope payload; no
Lanius producer, certificate format, or buffer size changed.

The public frontend postconditions now retain the actual caller's depth limit
and the implication from sufficient resources to zero materializer status.
`CheckedAfterParse.accepted` derives that implication from the existing
materializer success theorem and evaluation determinism. Syntax/body contracts,
frame restoration, capacity transport, and the semantic collector consume the
strengthened interface directly. `syntaxPost.no_tree_failure`,
`bodyPost.no_tree_failure`, and `File.Resources.no_tree_failure` carry the result
to `File.Resources.frontend_success`.

Focused tests cover exact fits, one-word/node/depth shortages, nullable
alternatives, split tokens, reordered/duplicate candidates, missing transitions,
forged summaries, and nullable cycles with arbitrarily deep derivations. The
source-bound integration also rejects wrong token counts, zero resource limits,
invalid productions, and missing/surplus candidates. Pure/resource/domain and
frontend-success audits use only standard Lean axioms. Retaining materializer
success adds no assumptions beyond its existing source proof; this does not
discharge the separate 463-assumption frontend baseline.

The final affected self-test build passed in 7.15 seconds
(`tree-success-self-build.log`). Whole-source integration passed in 66.82
seconds (`tree-success-self-source.log`), with shared infrastructure built,
including 37.364 seconds for the combined parser/tree resource check. This is
one-time validation, not the eventual trusted extraction path. Every command
stayed below two minutes. `git diff --check` passed, and hashes of the original
executable, singular embedding, source list, source contents, and envelope
payload remain unchanged. No Rust, Python, Wasm, or compatibility wrapper was
added.

### Tree resource approach (now completed)

Use resource budgets on the already checked chart items, not the tree emitted
by an untrusted run. Each terminal advance and each possible completion must
fit the next item's budget. Summation bounds nodes and words; maximum child
depth plus one bounds recursion. An induction on declarative tree recognition
will cover the source-selected tree without assuming a particular backpointer
choice or rerunning the recognizer.

1. Prove the resource algebra matches the existing materializer's exact layout,
   and that budgets preserved by chart transitions bound every recognized tree.
2. Compute candidate budgets on the finite chart dependency graph and check
   every transition inequality independently. Cycles or insufficient budgets
   must fail rather than become assumed resource bounds.
3. Retain successful materialization under sufficient resources at the public
   frontend boundary, construct the source-only tree domain, and admit all 18
   self sources. Then move to semantic/output bounds.

A diagnostic of the largest self unit found 162,515 chart items, 53,506 scan/
completion constraints, and no dependency cycle. Its candidate root bounds
are 31,374 nodes, 231,282 words, and depth 198, below the source capacities
65,536 / 1,048,576 / 1,024. Graph processing took 2.28 seconds; the full probe,
including loading the artifacts, took 13.67 seconds. These are feasibility
measurements, not yet accepted tree-resource proofs. No source format or buffer
size change is needed for this approach.

### Previous checkpoint: parser resource domain for all self sources

All 18 self-source files now have checked parser resource certificates.
`Entry.CheckedExecution.checkParserDomain?` consumes the existing source-bound
embedding and retains `ParserDomain sources`. `File.Resources.no_parser_capacity`
excludes capacity failure in the actual frontend call. Together with the syntax
and token-storage domains, `frontend_success_or_tree_resource` reduces its
outcomes to success or tree-resource failure. The next boundary is tree storage
and depth sufficiency, followed by semantic/output bounds. Milestone 3 remains
open, including broader failure coverage and the 463 inherited trust assumptions.

A closed candidate chart bounds the real source parser's state count.
`Compiler.Parser.GeneratedItem` means an
item belongs to every chart satisfying the existing `ChartClosed` rules.
It adds neither a second recognizer nor a new set of grammar rules.
`WorkspaceGenerated.length_le` proves the size bound using the actual
workspace's unique position/key pairs and the candidate's sound chart links.
Candidate state IDs, ordering, and backpointers need not match the source run.

Only fresh backpointer steps needed stronger evidence. Initialization derives
generation from the exact start-production row; prediction derives it from the
actual waiting parent and the selected nonterminal row. The prediction loop
retains that row evidence through its existing scope and append proofs.
`WorkspaceBackpointersSound.generated` then derives generation of every state
by induction on the existing decreasing backpointers. Terminal advances, parent
completion, and nullable replay therefore require no parallel invariant family.

Initial and position returns retain generation for the actual returned
workspace, including capacity failures. The public
`RecognizerCallExecution.states_le_closed` supplies the count bound, and
`success_of_closed_bound` guarantees parser success from declarative syntax
and a closed candidate strictly smaller than the authenticated capacity.
`Frontend.bodyPost.no_parser_capacity_of_closed_bound` carries the same
exclusion to the frontend return. No caller assumes a successful parser run.

`Compiler/Parser/Envelope/Check.lean` checks finite closure with array-backed
grammar/token lookups and balanced item/completion indexes. It validates index
coverage before using the indexes; deleting a completed span cannot hide a
missing completion. `checkWithIndex_closed` proves the four existing closure
rules for arbitrary supplied indexes. Extra entries are safe but count against
capacity; candidate state IDs, order, and backpointers need not match the run.

`verified_compiler/tools/envelope.lani` is an untrusted one-time proposer that
calls the existing Lanius lexer/parser and exports chart coordinates. It does
not implement another recognizer or change the production extractor.
`Tests/Parser/Prepare.lean` packs the existing grammar for its input. The binary
decoder rejects truncation, oversized counts, unknown versions, nonzero
reserved fields, and trailing records. The self-check now requires an envelope
path and retains its source-only domain alongside the whole-executable
certificate. See `BOOTSTRAP.md` for the updated command; no old-call wrapper
or fallback was added.

The proposer initially crashed because GPU lowering treated a host-service ID
as a local function-table index and borrowed an unrelated aggregate result
width. The fix in `shaders/codegen/lir/semantic/materialize.slang` restricts that
lookup to ordinary function calls. Rebuilding the compiler took 10.92 seconds;
the proposer then compiled in 2.98 seconds and exported all charts in 0.97
seconds. A fresh build of the original extractor took 2.54 seconds and its
1.26-second self-extraction reproduced the existing compact module byte-for-byte.
No Rust, Python, or Wasm implementation was added.

The largest envelope, for `parser.lani`, has 162,515 states against capacity
464,305. All 18 passed source-bound checking. Focused tests cover every
required-item deletion, nullable completion, odd split-token positions, forged
indexes, duplicate/reordered candidates, capacity edges, and malformed
transport. A 20,000-item sparse envelope checked in 533 ms. The full affected
self-test build passed in 4.24 seconds (`envelope-self-build.log`), including
standard-axiom audits of the checker and public resource-domain constructors.
New proofs add no assumptions; the existing frontend baseline is not discharged.

Whole-extractor integration passed in 44.32 seconds (`envelope-self-source.log`)
with shared infrastructure built, including 13.97 seconds for the new parser
resource check. This is one-time resource validation, not the eventual
few-second trusted extraction path. Every command stayed below two minutes.
The original executable, singular embedding, source list, and source-content
hashes remain unchanged. The envelope payload SHA-256 is
`242acf6e02c734918c84bd91d9d7b486f32f6943fa5e27bbfdc1d7f81335b0f4`.

### Source-linked parser capacity evidence

Capacity returns now prove that the actual returned parser workspace is full.
`Compiler.Parser.WorkspaceFull` records both the reported state count and the
capacity comparison. `appendLogical.full_workspace` derives this witness from
the failed append. Initial seeding, prediction, parent completion, nullable
replay, terminal scanning, state traversal, and position traversal retain it
through their existing result types. No parser behavior or capacity changed.

The initial and position continuation results no longer discard the workspace
on failure. Their `workspaceAgrees` contracts bind capacity returns to the same
workspace as the physical execution. The public
`RecognizerCallExecution.capacity_result` proves the exact diagnostic fields,
and `capacity_exhausted` combines fullness with the encoded-buffer bound to
prove `finalWorkspace.states.length = workspaceLayout.capacity`.
`Frontend.syntaxPost.capacity_result` and `bodyPost.parser_capacity` preserve
that evidence through the frontend return. Existing frame restoration and
source-buffer expansion preserve the strengthened contract unchanged.

`Tests/Storage/Parser.lean` covers insertion into the final slot, duplicate
insertion at capacity, a missing item at capacity, zero capacity, forged counts,
both public capacity exits, and a wrong-workspace substitution. The tests and
affected whole-extractor dependencies built in 43.96 seconds
(`parser-full-audit.log`). New public/pure theorems use only standard Lean
axioms. The source execution constructors add nothing beyond the inherited
frontend baseline; this does not discharge its 463 nonstandard assumptions.

The final dependent self-test build passed in 2.64 seconds
(`parser-full-self-build.log`). The first attempt exposed one stale tuple
destructuring in the parent-completeness regression; updating it for the new
fullness witness preserved the test's original claim. Exact-source integration
then accepted all 18 files and retained the whole-executable certificate in
25.95 seconds (`parser-full-self-source.log`), with shared infrastructure built.
The executable, singular embedding, ordered closure list, and source-content
hashes are unchanged; `git diff --check` passes. Every command stayed below
two minutes. No Rust, Python, Wasm, or compatibility wrapper was added.

The next obligation remains a non-circular parser resource bound admitting
the actual self closure, followed by tree, semantic, and output bounds. This
checkpoint supplies the evidence needed to contradict capacity failure; it
does not yet provide that bound. A naive bound containing every fresh grammar
production at every token-lattice position is too large: `parser.lani` has
3,889 tokens and capacity for 464,305 states, while that candidate set contains
2,255,910 fresh states alone. A useful bound must restrict reachable states;
counting arbitrary language-sound prefixes is insufficient. These are numeric
inventory results, not measurements of actual parser state usage.

### Certified input syntax and token storage

The actual 18-file self closure now has two source-bound input conditions:
`Entry.TokenDomain` and `Entry.SyntaxDomain`. They are stated in terms of
lexical validity, declarative grammar recognition, and concrete buffer sizes;
neither condition says that the extractor succeeds or accepts its own output.
The existing singular embedding supplies syntax evidence. The only new runtime
check inspects source lengths and already-certified token spans.

`Lexer.rawTokenBudget` subtracts each canonical token's interior bytes from
the source length. Those bytes cannot begin another raw token. The proof follows
the complete raw-lexer trace and shows that trivia removal and kind retagging
cannot increase the retained interior count. This gives a tighter upper bound
than one raw token per source byte, without rerunning the lexer. The checker
requires three words per possible raw token in both the raw and canonical
buffers, plus one kind word per canonical token.

`Frontend.checkUnitsTokenStorage?` consumes the existing checked units and
retains source-only domain evidence for every file. The public
`CheckedExecution.checkTokenDomain?` uses the 65,536-word capacities authenticated
by `File.Syntax.Stage.arguments`. `File.Resources.token_storage` connects those
bounds to the actual loaded bytes and runtime buffer lengths, including dirty
buffers reused for later files. `File.Resources.no_token_failure` excludes
lexer and canonical/kind-storage errors at the source-linked frontend return.

The accepted parse certificates now connect to the parser's separate language
specification. `advanceTerminal.scanTerminal` proves agreement between certified
semantic terminals and the physical-token lattice, including both halves of a
split token and its alternative whole-token interpretation. Earlier-child IDs
in the validated postorder tree supply induction for
`NodesMatchFrom.recognizes`; `RootMatches.recognizes` then covers the full input.
`ParseArtifactValid.recognizes` reuses those proofs and decoded token identities.
It does not run another parser or assume a successful source-parser execution.

`CheckedExecution.syntaxDomain` retains that result for the exact ordered input
sources. `File.Resources.recognizes` connects it to the actual canonical token
stream and checked grammar. Finally,
`File.Resources.frontend_success_or_resource` composes it with the source
parser's completeness theorem. On this input domain the frontend can only
succeed, report parser capacity exhaustion, or report tree-resource exhaustion.
Lexical failure, token-buffer failure, and invalid-syntax rejection are ruled out.

The next boundary is parser and tree resource sufficiency, followed by semantic
collection and output bounds. Those conditions must admit the actual self
closure. Broader host/failure coverage and the 463 inherited frontend assumptions
also remain open. This checkpoint does not close milestone 3 or establish native
x86 execution correctness.

Verification:

- The token-domain build and 31 exact-fit/overflow cases passed in 3.44 seconds.
  Cases cover empty input, long identifiers/literals, trivia, inclusive-range
  retagging, each buffer separately, forged spans, and lexical errors.
- The tree-to-language and frontend composition tests passed in 2.34 seconds.
  They derive recognition from an actual finite nullable/recursive tree and
  cover whole/split terminals, invalid odd-position scans, malformed child
  references, missing split halves, wrong nonterminals, and incomplete roots.
- The final dependent build and both audits passed in 4.44 seconds
  (`frontend-domain-final-build.log`). Every new theorem/checker audited here
  uses only standard Lean axioms. The complete extractor still inherits the
  existing frontend baseline; these local audits do not discharge it.
- Final exact-source integration accepted all 18 files and retained both
  input domains in 25.24 seconds (`frontend-domain-self-source.log`). The new
  numeric token-storage check took 4,608 microseconds inside that run. This
  measures reuse of already checked syntax evidence, not fresh extraction or
  the eventual trusted-extraction path. Shared infrastructure was prebuilt.

New domain modules live under `Entry/Domain/`, language-connection proofs under
`Parse/Language/`, and storage checks under `Frontend/Storage/`. The files contain
the actual proofs and checker implementations; no import-only compatibility
files were left behind. Lanius sources, bootstrap executable, singular embedding,
and ordered-source identities are unchanged.
All four recorded hashes still match, `git diff --check` passes, and every
command stayed below two minutes. No Rust, Python, or Wasm path was added.

### Whole-extractor execution and parser-completeness foundation

The complete `main` execution proof now covers startup, every requested file,
the final suffix, clearing and packing, stdout, and return.
`Entry.Startup.executes` constructs finite fuel on the stated loading/resource
domain. Zero establishes the public `Success` contract, including an accepted
syntax certificate for the exact ordered input files, exact rendered stdout,
preserved inputs, restored file handles, and memory safety. Nonzero returns
establish the public `Failure` contract. Covered errors include file-phase
21/28 and final suffix overflow 25. No successful parse, accepted output,
component execution, or intermediate buffer/resource invariant is assumed.

The output connection uses `Files.History.rendered` to derive decoder acceptance
and the exact module bytes from actual ordered emissions. The text writer and
suffix theorem cover both full writes and partial-output capacity failure.
Suffix failure returns 25 before clearing, packing, or stdout. Final workspace,
pointer, output buffer, and separation come from startup and the file-loop
result; they are not independently supplied to the whole-main theorem.

`Entry.Run.body_typed` derives main-body typing from the accepted entrypoint.
`Entry.Run.evaluates` invokes that exact zero-argument entrypoint and restores
the caller's locals without weakening either public contract.
`Entry.Run.observations` establishes `RunSound` and `RunFailureSafe` for every
fuel bound. There is a finite bound above which every executable run returns
the same value and final state; below it, the only alternative is fuel
exhaustion. Traps and explicit host exits cannot replace the proved result.

`Frontend.checkLinkedSyntax?` constructs the previously assumed `LinkedSyntax`
evidence. It proposes mappings from the embedded frontend pack used by the
existing lexer proofs, then checks dependency closure and exact relocation
against the current Core program. It checks the separate complete canonicalizer
proof and the actual parser/reader link, including helper and result-type
identities. No separate external JSON input is needed. The former standalone
link test no longer contains a second link-construction algorithm; its useful
guard/tail regressions run against the shared checker.

The actual 18-file self-source driver constructs this frontend evidence and
instantiates the whole-executable theorem from an ordinary process world.
Main typing, initial runtime typing, call ABI, and x86 word width are derived.
The remaining input premises describe nonempty bounded argument paths,
available files of at most 65,536 bytes, and representable fresh file handles.
The initial modeled heap is empty with an unlimited allocation budget. This
is a Core/host-model execution result, not yet a native x86 correctness proof.

The complete construction now lives in the library, not in the self-test.
`Entry.checkExecution` consumes the existing `CheckedExtractorCoreSourcePack`
and returns `Except String (CheckedExecution accepted)`. Its result retains
the whole-executable theorem and checked stages for inspection. It performs no
second extraction, source parse, or Core synthesis and imports no test module.
The source-checking and proof-assembly contents were moved from `Tests.Self`;
the test driver now consumes that result and reuses its stages for the existing
execution and mutation regressions. It shrank from 634 to 133 lines, with no
compatibility wrapper or second correctness construction.

The public `CheckedExecution.run_sound`, `run_failureSafe`, and `terminates`
theorems apply to an explicit `LoadingDomain` over an ordinary process world.
`Entry.checkLoadingDomain?` produces that domain evidence from argument paths,
modeled files, byte-size bounds, and fresh handles. It preserves request order
and repeated paths, accepts empty files, and does not parse or require syntax
acceptance. Its 17 boundary cases cover missing inputs/files, UTF-8 path-byte
limits, file-byte limits, invalid syntax as loadable data, and handle
representability/freshness. The actual 18-file self-source world now passes this
domain checker, and all three public theorems are instantiated from its result.
This establishes the self closure's loading domain, not yet the stronger
syntax/resource domain needed to guarantee successful extraction.

The entrypoint bridge uses only standard Lean axioms. The link-construction
audit adds no nonstandard assumptions beyond the existing frontend theorem;
the inherited 463-assumption frontend trust obligation remains. New tests
reject seven mapping/missing-body/changed-body mutations and preserve six
guard/continuation mutations from the former link harness.
The public theorem projections and loading-domain checker use only standard
Lean axioms. Auditing the entire `Entry.checkExecution` construction, not just
its projections, adds no assumptions beyond the same frontend baseline.

The first language-to-chart completeness theorem is now proved in
`Compiler/Parser/Closure.lean`. `ChartClosed.contains_root` derives a complete
start item from `RecognizesInput`, provided the chart is seeded and closed
under prediction, scanning, and completion. Its mutual grammar induction
covers empty productions, recursive nonterminals, and the existing split-token
lattice. It introduces neither another parser implementation nor a definition
of validity based on successful execution. Chart closure must come from the
source loops, not from a new caller assumption. The completed source connection
is described below.

The actual root-loop proof now retains `NoRootIn` on exhaustion. Each source
iteration supplies its failed predicate; the loop composes those facts across
the unvisited suffix. The root entry proves that suffix is the whole final
chart. `RecognizerRootStatementOutcome.rejected` therefore carries proof that
no candidate satisfies the root predicate, and both accepted and rejected
outcomes refer to the actual returned workspace.
`success_of_hasRoot` excludes rejection when the final chart contains a root;
`success_of_closed` connects that result to the declarative grammar theorem
and retains the source-selected `StoredRootParse`.

This evidence survives the concrete parser call and the frontend contract:
`RecognizerCallExecution.rejected_noRoot`, `syntaxPost.rejected_chart`, and
`bodyPost.parser_rejected` expose the exact returned chart and distinguish
syntax rejection from capacity failure. Capacity expansion and scope/frame
preservation retain the witness. No successful result or caller-supplied
absence proof was added to the execution constructors.

Initial seeding is now proved from the source loop. Its invariant records the
exact seeded prefix of the packed start-production row; setup proves that the
whole row equals `productionIdsFor start`. Successful append includes both
new insertion and duplicate detection. `StartSeeded.preserved` carries those
items through workspace growth, and the actual parser call retains them in
every non-capacity result. Frontend rejection therefore carries both
`StartSeeded` and `NoRootIn` for the same returned chart. An empty-input,
empty-start-rule regression excludes rejection from this seeding guarantee
alone, without assuming chart closure.

Prediction now has the same exact-prefix invariant. The source nonterminal
binding proves which semantic row its offset/count select, and
`RecognizerStatePredictionCompletedFrame.seeded` derives every production in
that row on normal completion. Nullable replay retains these seeds, including
when replay exhausts capacity after prediction completed. The synchronized
outcome and restored physical result refer to the same workspace.

`PredictionsComplete` states the prediction clause for one parent item.
The actual nonterminal executor derives it from the selected row; terminal and
finished-item branches discharge it from their source guards. The shared
`RecognizerStateBranchSynchronizedOutcome` and full state-body iteration now
retain it. No caller supplies a predicted chart or an accepted parse.

The state loop now accumulates those results over its entire growing chart.
`Compiler/Parser/Prediction.lean` proves that append-only growth preserves chart
order and the visited prefix. `PredictionsFor.step` extends the certified prefix
by the item just processed; newly appended items remain in the pending suffix.
The existing FunctionalView loop induction retains this evidence in
`RecognizerStateFunctionalResult.predictions`. Normal termination establishes
`ChartPredicted` for the actual final workspace, including newly appended
states. `ChartPredicted.predict` exposes exactly the prediction clause needed
by `ChartClosed`.

Resuming a traversal requires evidence for its already-visited prefix, but
actual callers do not supply that assumption. The source chart-head protocol
establishes an empty visited prefix, or an empty chart when the head is negative.
`RecognizerStateConfig.predictionsReady_of_head` derives this from the checked
head value. The enclosing position scope invokes it and retains `ChartPredicted`
in `RecognizerPositionPostFrame.predicted` after restoring the temporary locals
and advancing the position.

Preservation through later positions is now proved. `ChartsUnchangedBefore`
records equality of every earlier chart, while allowing the state table and
current or later charts to grow. Actual prediction, nullable replay, parent
completion, and terminal scanning establish it on normal completion. The
state-step and complete state-loop results retain and compose that evidence.
Capacity returns remain separate and do not claim completed charts.

`PredictionsBefore.advance` preserves each earlier chart's prediction guarantee
and adds the newly completed chart. The source position-loop induction applies
it after each actual state traversal. `RecognizerPositionFunctionalResult.predictions`
therefore certifies every input position in the final workspace, including the
final position. The actual recognizer starts at zero, so the prior-chart premise
is discharged by the empty prefix, not supplied by an extractor caller.

Root search leaves that workspace unchanged. The position/root continuation
retains its completed prediction prefix, and
`RecognizerCallExecution.predictionsComplete` exposes it for every non-capacity
result. Frontend rejection retains `StartSeeded`, prediction for every input
chart, and `NoRootIn`, all for the same physical workspace. No successful
parse or chart-closure assumption was added.

Scanning now has the same source-to-public-result connection.
`Compiler/Parser/Scanning.lean` states `ScansComplete` for a processed item:
whenever its expected terminal matches, the advanced key is present at the
scanner's returned position. The actual terminal branch derives this key from
successful append, including duplicate detection. A failed match contributes
no advance, and nonterminal or finished-item branches discharge the scan
condition from their checked source guards. Capacity exhaustion does not
claim scan completeness.

`ScansFor.step` accumulates the guarantee over the growing state traversal.
The actual chart-head protocol now proves `processedPrefix_empty_of_head`
once, and both prediction and scanning initialize from that shared fact.
`RecognizerStateFunctionalResult.scans` and `RecognizerPositionPostFrame.scanned`
retain the completed chart result. `ScansBefore.advance` carries it through
later positions using the already-proved earlier-chart stability.

The source position loop starts at zero and constructs
`RecognizerPositionFunctionalResult.scans` for every final-workspace input
chart. Root search retains that workspace, and
`RecognizerCallExecution.scansComplete` exposes the result for every
non-capacity return. The frontend rejection contract now retains scanning as
well as seeding, prediction, and absence of a root, for the exact canonical
token-code stream and physical workspace. The public scan regression obtains
its input-position bound from the matching scan itself, not an extra caller
assumption.

Parent completion now retains its entire visited prefix through the actual
source loop. `ParentsFor.step` includes the current parent and keeps newly
appended parents pending. Normal termination yields `ParentsComplete` for the
origin chart in the actual final workspace. Matching appends include successful
duplicate detection; capacity returns do not claim coverage. The real chart-head
binding discharges the initial prefix condition. `RecognizerStateParentEntry.execute`
retains that result after both temporary source scopes close.

Nullable replay now supplies the other processing order. `NullablesComplete`
requires the waiting parent's advanced key whenever a matching zero-width
child is present. Once one matching append succeeds, the retained key covers
all other matching children, including later additions. Nonmatching iterations
accumulate their visited prefix. `RecognizerNullableFunctionalResult.nullables`
proves coverage through every branch of the actual loop; the real chart-head
entry supplies its initial condition. Prediction composition and restoration
retain the same final workspace in
`RecognizerStateNonterminalSynchronizedExecution.nullables`.

Both scope executors now keep the original FunctionalView result and its
coverage proof together, transporting only the initial-workspace identity.
They no longer reconstruct a second dependent outcome from separately unpacked
fields. The unused parent compatibility wrappers were removed, and the existing
chart-head proofs now live with the source entries rather than being duplicated
in the enclosing driver. No compatibility alias or alternate execution path
was added.

Parser-wide completion is now proved. `CompletionsFor` records processed
parent/child pairs, including parents in earlier origin charts. Its step lemma
preserves old pairs, uses parent replay for the newly processed child, and uses
nullable replay for a newly processed parent of an earlier zero-width child.
Newly appended items stay in the pending suffix. `CompletionStep` obtains both
responsibilities from the actual terminal, nonterminal, and completed-item
source branches.

`RecognizerStateFunctionalResult.completions` accumulates these guarantees
through the entire growing state traversal. The real chart-head entry supplies
the empty-prefix condition. `CompletionsBefore.advance` preserves earlier
charts and adds the completed current chart, so
`RecognizerPositionFunctionalResult.completions` covers every input position
in the final workspace. Position zero discharges the initial premise.

`ChartClosed.of_phases` combines seeding, prediction, scanning, and completion
on that same workspace. Physical encoding bounds every stored position;
existing language-sound derivations prove that each child's origin precedes
or equals its end. These are conclusions of the source invariants, not new
extractor-caller assumptions. The actual position/root continuation constructs
the complete closure proof before returning, and root search preserves it.

`RecognizerCallExecution.success_of_recognizes` now proves that declaratively
valid input succeeds whenever the result is not capacity exhaustion.
`success_or_capacity` states the two alternatives without a non-capacity
premise. `root_of_recognizes` retains the actual selected stored derivation
and exact returned result fields. The source-linked frontend rejection
contract carries closure and absence of a root for the same workspace;
`bodyPost.parser_rejected_invalid` therefore proves that its canonical
token stream is not recognized by the grammar. Syntax rejection can no
longer remain an unexplained failure alternative for valid input.

This closes the parser-completeness obligation, not the extractor's whole
successful-input theorem. Capacity remains a real possible result. The next
resource domain must rule it out and cover token, tree, and output limits,
then be established for the actual self closure. In particular, a conservative
bound that only admits tiny inputs and excludes the extractor's own sources
would not finish this milestone.

Verification of the completed parser boundary:

- Pure phase assembly and span monotonicity checked in 0.93 seconds
  (`parser-chart-closure-model.log`). The new pure lemmas use only standard
  Lean axioms.
- The public parser/frontend regression and assumption-audit build passed
  in 6.74 seconds (`parser-chart-closure-public-audit.log`). It audits the
  actual position/root proof construction as well as its public projections.
  The source construction adds nothing beyond the inherited frontend baseline.
- The remaining dependent whole-extractor build passed in 42.67 seconds
  (`parser-chart-closure-self-build.log`). Exact-source integration accepted
  all 18 files in 25.40 seconds (`parser-chart-closure-self-source.log`),
  retaining the public whole-executable certificate and loading-domain proof.
- A final added regression processes a nullable child before its parent is
  even inserted, preserves the processed prefix across insertion, and closes
  the pair through the parent's own replay. Together with the growing
  `S → A A; A → ε` case, this exercises both outer-loop processing orders.
  Missing-advance cases reject the incomplete chart. The final regression,
  public audit, and dependent self-check build passed in 3.54 seconds
  (`parser-chart-closure-order-audit.log`).

No Lanius source, bootstrap executable, singular embedding, or source-closure
identity changed. All four recorded hashes below still match. Every command
stayed below two minutes, and `git diff --check` passes. These are separate
proof/checking boundaries, not a claim about clean-build time or the eventual
trusted-extraction path. The 463 inherited frontend assumptions remain open.

The new completeness and rejection-projection lemmas use only standard Lean
axioms. Focused cases cover nullable and recursive rules, both halves of a
split token, invalid odd-position scanning, an actual closed empty-input chart,
and a missing-root chart. Prediction cases cover both alternatives of a
nullable/recursive nonterminal, nonzero origins, later capacity failure,
growth in another chart, terminal/finished states, and an omitted alternative.
The growing-chart regression starts with one parent, appends two children,
processes both, and derives chart-wide prediction. It also rejects exhaustion
at the original tail after those children have been appended.
Pure prediction lemmas use only standard Lean axioms. Source invariant and
execution theorems are audited against the existing frontend baseline, since
their types retain its legacy source-data checks.

The new preservation regression carries a completed chart through processing
of a later chart, permits growth in the current chart, and rejects a unique
backward insertion despite preservation of all old states. A public-outcome
regression derives any required child prediction at an arbitrary input
position without a caller-supplied closed chart. The new pure preservation
lemmas and public projections use only standard Lean axioms; the actual
source construction remains within the existing frontend assumption baseline.

Scanning regressions process both halves of one split token and preserve the
first half's completed chart while processing the second. They also cover
duplicate insertion at capacity, missing advanced items, terminal mismatch,
empty and final input positions, invalid odd-position scanning, and
nonterminal/finished states. The scan cases and pure axiom audit passed in
0.94 seconds (`parser-scanning-cases.log`). The actual source branch build
passed in 36.36 seconds, the state driver in 9.64 seconds, and the position
driver in 7.24 seconds. The affected proof chain through `Tests.Self`, including
the public parser/frontend contracts, whole-extractor construction, regression
checks, and axiom audits, passed in 82.40 seconds
(`parser-scanning-self-build.log`). It retains the same 463 inherited
nonstandard frontend assumptions and adds none. A further public-outcome
regression combines seeding and scanning to exclude rejection of a valid
terminal-only split-token input, without assuming full chart closure or parser
success. That regression and the dependent self-check module passed in
2.54 seconds (`parser-scanning-public-cases.log`). The exact 18-file
self-source integration passed in 25.90 seconds (`parser-scanning-source.log`),
retaining the public whole-extractor certificate and the existing source-link
and execution regressions. No Lanius source, executable, or embedding changed.
Every command stayed below two minutes, and `git diff --check` passes. These
are proof/checking timings, not extraction-throughput measurements.

At the parent-completion checkpoint, the source-entry build and growing-chart
regressions passed in 26.75 seconds (`parser-parent-coverage-entry.log`). The
public parser/frontend regression chain and assumption audit passed in
60.39 seconds (`parser-parent-coverage-audit.log`), and the remaining dependent
whole-extractor build passed in 41.47 seconds
(`parser-parent-coverage-self-build.log`). Exact 18-file self-source integration
passed in 25.53 seconds (`parser-parent-coverage-source.log`). The source
construction adds no assumptions beyond the existing frontend baseline.
These are checks of distinct proof boundaries, not a claim that a clean build
of their union takes any one of those times.

Nullable replay's pure regressions cover a child completed before its parent,
nonmatching and unfinished children, wrong nonterminals, nonzero-width children,
duplicate detection at full capacity, missing advances, and later chart growth.
The loop proof passed in 9.94 seconds (`parser-nullable-coverage-loop.log`).
After connecting its real chart-head entry, the restored nonterminal branch
and pure regressions passed in 10.85 seconds
(`parser-nullable-coverage-branch.log`; the regression module itself took
0.887 seconds). The public parser/frontend chain and assumption audit passed
in 60.49 seconds (`parser-nullable-coverage-audit.log`). The remaining dependent
whole-extractor construction passed in 41.77 seconds
(`parser-completion-traversals-self-build.log`). Both completed traversals use
the exact source-linked loops, not a new logical parser. Their new pure lemmas
use only standard Lean axioms; source proofs add nothing beyond the inherited
463-assumption frontend baseline.

Final exact 18-file self-source integration passed in 25.68 seconds
(`parser-completion-traversals-source.log`), retaining the public executable
certificate and source-link/execution regressions. The x86 bootstrap,
singular self-embedding, and source-closure list retain the hashes recorded
below. No Lanius source changed in this traversal-proof checkpoint. Every
command stayed below two minutes, and `git diff --check` passes. These remain
proof/checking timings, not measurements of the final trusted-extraction path.

At the preceding prediction checkpoint, rebuilding the affected chain through `Tests.Self`,
including public parser/frontend contracts and assumption audits, passed in
78.50 seconds (`parser-forward-self-build.log`). The preservation cases and
pure lemma audit passed in 1.04 seconds (`parser-forward-cases.log`).
The complete state traversal checked in 9.54 seconds and the complete position
traversal in 7.24 seconds. These checks establish prediction in the final
workspace, including preservation through later positions, not full chart
closure or successful-input completeness. The exact 18-file self-source
integration passed in 24.90 seconds (`parser-forward-source.log`), retaining
the public whole-extractor certificate and adding no assumptions beyond the
existing frontend baseline. No Lanius source, executable, or embedding
changed. Every command stayed below two minutes, and
`git diff --check` passes. These are proof-build/checking timings, not
extraction-throughput measurements.

At the preceding packaging checkpoint, the public checker module built in 3.94 seconds
(`execution-checker.log`). The affected input-domain/self-test build and audits
passed in 2.34 seconds with shared dependencies built
(`public-execution-domain-audit.log`). Final exact-source integration, using
the public checker and retaining the link/guard regressions, passed in 25.69
seconds (`public-execution-source.log`), down from the previous 33.99-second
driver-local proof construction. These are checking timings,
not extraction-throughput measurements. No Lanius source, bootstrap executable,
or self-embedding changed; no Rust, Python, or Wasm path was added. All commands
stayed below two minutes, and `git diff --check` passes.

Rechecked identities:

- x86 bootstrap: `6163554af500bd57e3c82e4763dad3e2412499ef22146d7d28186bf696ee7c0d`
- singular self-embedding: `8c918c01dab6fccdd2e5ad8ac99002a979286b10c368a9638026070ac3e40328`
- ordered closure list: `079059b1eb54011de70900c1c5a9f7d411a027c7166728a95b55aef461a77bf3`
- ordered source-content digest: `f289195e6e968f2306f5c5d773bbd535bb867ff308bd89df8d3f1e2a056cace9`

Steps 1–4 below remain completed component boundaries. Step 5 is still active:
the whole-extractor theorem proves finite success-or-classified-error execution,
not successful termination for every supported valid input. Parser completeness
now excludes syntax rejection for declaratively valid tokens; resource failures
remain separate. The syntax and token-storage parts of the noncircular input
domain now hold for all self-source files, as recorded above. Next establish
parser, tree, semantic-collection, and output resource bounds that guarantee
success and admit those same files. Then cover failures outside the present
loading domain and resolve the inherited trust obligations. Public whole-extractor proof-checker packaging
is complete for the currently proved loading-domain contract; it is not a
substitute for those remaining correctness obligations.
Milestone 3 and the seven-step goal remain incomplete.

### Previous checkpoints (historical)

These checkpoints record the order of construction. Their “next” and “remains”
statements describe those earlier states, not the current work queue above.

The complete ordered-file loop was proved on its stated
loading/resource domain. `Entry.Files.executes` constructs each actual file
body with `Entry.File.Checked.executes`, rebuilds the next invocation from its
result, and recurses over the remaining requested files. It constructs finite
fuel for either normal loop completion or a classified frontend/output error.
It does not assume any body execution, successful parse, or accepted output.
The last iteration closes the loop without requiring a nonexistent next file.

`Entry.File.certified_output` connects the successful frontend, collector,
emitter guard, and cursor increment to an accepted unit for the exact loaded
path and bytes. Its bounds follow from the actual successful append result.
`Entry.Files.History` retains the ordered accepted units, ordered sources,
cursor, and exact output prefix. `History.emitted` handles the last file;
`History.afterFile` connects the same history to reconstructed next-file
resources. Repeated paths remain repeated entries. The final output allocation
still has 8,388,608 words; unused capacity is not treated as certificate data.

The loop retains runtime typing, caller locals, external inputs, and original
file handles on every covered return. It leaves stdout unchanged on every
branch and stderr unchanged on normal completion. Success retains native
registry validity, representable words, and every original registered view,
while allowing frontend helpers to add borrowed views. The argc local survives
each iteration; its separation from the argument cursor follows from their
different current values. Startup now derives separation from the output
cursor using its fresh allocation, even when argc and the cursor hold the
same integer.

`Pending.sources` connects the ordered request domain and stopping count to
the original `ExtractorContract.requestedSources?`, not a different definition
of the requested program. `History.certificate` constructs the public
`CheckedCompactSyntaxSourcePack` from a completed history and its byte-buffer
relation. Decoder success and syntax acceptance are conclusions. Final output
packing must still supply that byte relation in the composed `main` proof.

The source checker now authenticates the exact argument initialization,
inequality condition, complete file body, and continuation in the current
self-embedding. It also rejects changed initial indices, condition bindings,
comparison operators, and bodies. The integration driver instantiates the
loop theorem at these coordinates, with the existing `LinkedSyntax` evidence
still an explicit parameter. This is not yet a constructed whole-main proof.

New interval-model tests cover empty writes, zero capacity, negative and
beyond-end cursors, partial writes, and untouched tails. Ordered wire tests
cover UTF-8 paths, empty files, and repeated paths; these test encoding and
decoding, not syntax validity of their artificial node fixtures. Syntax
acceptance comes from the execution proof. All new certificate/history/request
lemmas use standard Lean axioms. The actual composed loop retains the same
463 nonstandard frontend assumptions and adds none.

Final verification: the affected build, focused tests, and axiom audit passed
in 2.22 seconds with shared dependencies built
(`target/verified-compiler/files-completion-audit.log`). The final exact-source
integration check passed on all 18 files in 25.98 seconds
(`target/verified-compiler/files-completion-source.log`). The current bootstrap
x86 executable, singular self-embedding, source-closure list, and ordered
source-content hashes are unchanged. No Lanius source edit or re-extraction
was needed; no Rust/Python implementation or Wasm path was added.
`git diff --check` passes. All commands stayed below two minutes. These are
proof/checking timings, not a new extraction-throughput measurement.

Steps 1–4 below have completed component boundaries. Step 5 is active.
Startup is now connected to the complete ordered-file phase.
`Entry.Startup.reaches` derives a reached state from the actual argc,
allocation, pointer, grammar, framing, and header executions. Its result,
`Startup.Ready`, retains allocation history, exact grammar/header storage,
live views, cursor separation, host-world changes, and the main execution
prefix. It does not require the remaining main to return successfully.

`Entry.Files.CheckedSource.resources` constructs the entire first
`File.Resources`, not just the loader input. The selected file supplies the
lexer request; its bounded token count supplies the workspace bounds.
The actual 2,179-word decoded grammar is well formed and has a complete
production index. Every buffer's capacity, current contents, and required
separation follow from the executed allocation history and source bindings.
Working arrays need not still be zeroed. The initial output history follows
from the exact emitted header; no accepted unit is assumed.

`Entry.Startup.runFiles` consumes the result of `Startup.reaches`, derives
loop-entry and body typing from typed main entry, and runs the complete
ordered loop through `CheckedSource.runFromStartup`. It returns finite-fuel
execution and the ordered loop result, tied to startup's actual output cell.
No intermediate startup state, file resource, parser invariant, component
execution, successful parse, or accepted output is independently supplied.
The input domain remains explicit: nonempty bounded paths, available files
of at most 65,536 bytes, sufficient allocation and handle budgets, target
word width, and initial runtime typing. The frontend link remains a separate
proof parameter in the current self-source integration driver.

The actual 18-file self-embedding instantiates this startup-plus-loop
composition. Source mutations reject disconnected source or
grammar inputs, overlapping buffers, changed grammar counts, and incorrect
output/cursor bindings. The loop checker also rejects an argument cursor
that shadows argc and would skip all requested files.

The affected startup, packing, and self-source build and axiom audits passed
in 10.84 seconds (`target/verified-compiler/startup-complete-file-audit.log`).
Startup and resource construction use only standard Lean axioms. The loop
composition adds none beyond the same 463 inherited frontend assumptions.
Exact-source integration passed in 25.65 seconds
(`target/verified-compiler/startup-complete-file-source.log`). The Lanius
source, x86 bootstrap executable, and singular self-embedding hashes are
unchanged. These are checking times, not an extraction-throughput benchmark.
No Rust/Python implementation or Wasm path was added; all commands remained
under two minutes. One launcher stalled before starting Lean and was stopped;
the bounded check then used the already-installed, project-pinned v4.33.1
toolchain directly, avoiding the root directory's floating stable launcher.

The final-output connection has now advanced too. `Files.Result.carriedLocals`
retains live non-array caller values through every successful iteration.
`Result.carriedNonScalar` derives separation of pointers, slices, and strings
from the two signed cursors. Startup retains the exact suffix literal and
its output-capacity bound. `Startup.Ready.bufferAfterFiles` recovers actual
post-loop buffers with their current contents; `suffixAfterFiles` retains the
original suffix text. No array is assumed still to contain allocation zeros.

`Startup.Ready.suffixResources` constructs the suffix call's complete inputs
from the finished loop: the actual output cell and slice, current buffer and
cursor, registry, original literal, and ordered certificate history. It splits
emitted bytes from unused capacity without making that tail certificate data.
It does not assume there is enough remaining room for the suffix.
`Suffix.Stage.executes` proves the real append, cursor assignment, and guard
when that remaining room is sufficient. It appends exactly 677 bytes, excludes
literal padding, and retains the registry and scoped continuation. The full
suffix-overflow branch remains unproved at this boundary.

`CheckedSource.afterLoop` connects normal loop completion to the actual suffix
statement. `Semantics.Prefix.Reaches.completeReturn` closes a returned prefix
through enclosing scopes without executing later statements. `Startup.runFiles`
now returns both facts: success reaches the suffix; a file-phase error yields
an execution of main with the same return and final state except for closed
local mappings. This is not yet the public all-input failure theorem.

The current suffix source is checked against its actual post-loop statement,
framing bindings, and text callee. Nine mutation cases reject changed live
bindings, capacity, callee, and guard. Startup also rejects a cursor which
would shadow the suffix literal. The affected startup, suffix, packing, and
self-source build and audits pass in 9.05 seconds
(`target/verified-compiler/suffix-final-audit.log`). New suffix/resource/scope
proofs use standard Lean axioms; actual frontend execution retains the same
inherited assumptions. Exact-source integration passed on all 18 files in
25.82 seconds (`target/verified-compiler/suffix-final-source.log`), including
the suffix/source mutations and the startup-to-main-return connection.
The source, bootstrap executable, and singular embedding hashes remain
unchanged. `git diff --check` passes; all commands stayed under two minutes.
These are checking timings, not a fresh extraction benchmark.

Next, handle suffix overflow and compose suffix execution with the existing
clearing/packing/stdout theorem. Derive the packing workspace pointer, live
bindings, and exact byte relation from these retained resources. Then apply
the scope-completion rule and close the public main success/failure/completeness
contracts. The frontend-link construction and inherited trust audit also
remain open. Neither milestone 3 nor the seven-step compiler goal is complete.
The older checkpoints below are historical; they do not supersede this one.

Next-iteration checkpoint (September 10): `Entry.File.handoff` derives the
preserved grammar, exact loaded host world, incremented original argument
cell, nonnegative output cursor, and unchanged non-array caller values outside
the two cursor cells. It composes the actual frontend, collector, emitter, and
advance effects. The file-step theorem returns this handoff after closing all
temporary scopes. This does not assert that borrowed views were absent or
that native memory stayed byte-for-byte unchanged.

`Entry.File.Next.inputNext` constructs the next argument/path/open/read input
from that handoff and the file-step's retained registry and views. Pointer and
slice values cannot alias the signed cursor cells; the proof derives this
from their existing values instead of assuming distinct local names imply
distinct cells. Its remaining premises describe the next requested file,
path/file capacities, numeric bounds, and older initial handles. No successful
load or intermediate ownership invariant is assumed.

`Entry.File.Next.frontend` recovers the six working arrays' actual current
contents from registered storage and proves their capacities are unchanged.
It builds the next file's lexer request and derives the workspace layout from
the bounded canonical token count. The grammar stays exact. Neither zeroed
arrays nor a successful parse is assumed. `syntaxReads` preserves all eight
frontend slice arguments. `savedBuffer` and `savedRead` recover the semantic
and output allocations with their current contents, retaining the accumulated
output rather than restoring an old buffer. Cursor and older-handle facts
also survive.

`Entry.File.Resources` groups precisely the ordinary dynamic resources needed
by a file invocation. `Entry.File.Next.rebuild` assembles the complete next
record, including the selected file/index, all loading/frontend/collector/
emitter inputs, capacities, separations, grammar, and cursor values. Runtime
typing is already retained separately by `Entry.File.step`. The source checker
authenticates the reused loading/frontend bindings and instantiates this
resource constructor at the current extractor's actual local coordinates.

The next-resource proof and standard-axiom audit passed in 4.20 seconds
(`file-next-resources.log`). The final affected test/source-check build passed
in 7.11 seconds (`file-next-final-audit.log`). New handoff and reconstruction
proofs use only standard Lean axioms; the composed file step retains the
existing 463 nonstandard frontend assumptions. Focused source-linked execution
coverage loads five files successively into the same buffers, including
long-to-short-to-empty inputs and repeated paths, and checks exact bytes,
argument advancement, caller locals, views, allocation budget, handles, and
the complete host world. Binding mutations must be rejected.
The final exact-source integration check passed on all 18 files in 26.35
seconds (`file-next-final-source.log`), including the assembled resource
constructor's source linkage and those five reused-buffer loads. The GPU-built
x86 executable, singular self-embedding, closure list, and ordered source
content hashes were reread and are unchanged. No Lanius source edit,
re-extraction, Rust/Python addition, or Wasm path was needed. All commands
remained under two minutes. These are proof/checking timings, not a new
extraction-performance measurement.

This closes resource reconstruction between adjacent successful file bodies,
not the ordered-file execution theorem. The loop still needs its ordered
certificate/output-history invariant and termination proof, followed by the
final stdout connection and whole-main success/failure/completeness contracts.

Startup checkpoint (September 9): `Entry.Pointers.executeEntry` composes argc,
argument validation, all buffer allocations, pointer aliases, and the null
guard. It retains allocation history and unchanged local/world facts for the
continuation. `Entry.Grammar.LiteralStage.executes` composes the grammar literal
binding, borrowed string view, source binding, cursor initialization, and full
decoding loop. `checkLiteralData?` checks the actual 2,179-word literal against
the formal parser's `EncodesGrammar` contract, including production indices.
The new proofs pass the standard-axiom audit.

`Entry.initializeGrammar` now composes these prefixes and derives the grammar
destination buffer's typed contents and capacity from the entry allocation
history. Its remaining execution premise starts after grammar initialization.
`Entry.initializeFraming` extends that composition through both framing
literals, the initial `output.text` call, and its success guard. It derives
the output allocation and its preservation across grammar initialization,
then establishes the exact 146-byte Lean module prefix in that buffer. It
retains allocation history, grammar facts, cell effects, and unchanged binding
identities for the continuation. Its remaining execution premise starts at
compact-header output.

`Entry.initializeHeader` extends this to the complete startup: the exact
146-byte Lean prefix followed by the 16-byte compact header. It derives argc
from the host-call entry, proves that count survives allocations and grammar
initialization, and emits version one and the input-file count. The remaining
execution premise starts after the compact-header guard, at ordered-file
initialization. The prefix and header helpers are not assumed to execute
correctly at this boundary.

Startup now also returns `Allocation.Registry` after grammar initialization,
module-prefix emission, and compact-header emission. Borrowed strings retain
their new registered block; typed cell writes retain a separate `HeapFrame`.
The loop/call interfaces carry this evidence through local bindings and scope
closure. `Registry.transport` derives the resulting registry from the original
registry and changed arrays' types and lengths. No new registry is assumed at
the first file operation.

The focused startup audit (`target/verified-compiler/startup-registry-audit.log`)
passes with only standard Lean axioms. The exact-source integration check
(`target/verified-compiler/startup-registry-source.log`) passes on all 18 current
files in 21.27 seconds with shared infrastructure built. These checks establish
source linkage and the composed startup theorem, not the whole-main contract.

Next boundary: the ordered-file phase begins with argument-path length/read,
path unpacking, file open/read/close, and per-unit extraction/emission. Its host
calls synchronize language-level arrays and byte storage. Registry validity
proves both passes can run; it does not prove exact contents survive them.
`Host.evaluatesReadOnly` now derives both passes for heap-preserving services
and retains the registry and non-array local values. `Host.readOnlyPreservesView`
proves exact array preservation separately from disjoint ranges and bounded
i32 values. The next resource obligation is to carry those non-aliasing/range
facts from allocation and startup through file I/O, not assume coherence from
registry validity. The complete constructive `read_file` call proof is now
checked, as recorded below; the enclosing ordered-file phase still needs
composition.

`Entry.Path.Length.Stage.executes` proves the first file-body stage's argument
length call and valid-path guard. `Stage.rejects` proves code-two rejection of
empty or oversized paths on its representable-length domain. Both derive host
synchronization from the input registry. The focused path audit
(`target/verified-compiler/path-audit.log`) uses only standard Lean axioms and
checks UTF-8 lengths, both path-capacity boundaries, unchanged registered buffer
contents, and rejection of changed host declarations or guards. These are
file-body components, not a completed ordered-file loop.

The updated exact-source check (`target/verified-compiler/path-source.log`)
passes in 19.94 seconds on the same 18-file embedding. It checks that the
path-length stage begins the actual file-loop body and reads that loop's
argument cursor, then runs the boundary cases using the checked host service.
The affected frontend, semantic collector, unit serializer, and parser-tree
proof consumers also rebuild successfully (`resource-consumers.log` and
`remaining-resource-consumers.log`). No command exceeded the two-minute limit.

The file-body prefix now extends through argument copying, path unpacking,
and successful file opening. `Entry.Path.Length.Stage.withRead` composes both
path guards and exact argument-byte copying. `Stage.withUnpack` extends it
through zero cursor initialization and the complete unpacking loop.
`Entry.File.prepare` extends that result through the actual open call, handle
binding, and negative-handle guard. Its remaining execution premise begins at
`read_file`. It retains the exact path array, the registered buffers, valid i32
words, the opened world/handle, and preservation of other buffers and locals.
It does not assume a successful host call or an internal unpacking invariant.

The shared input-unpacking proof covers both actual index forms: `index` for
paths and `total + index` for file chunks. Its callers use the new interface
directly. The path stage derives destination storage from the registry and
scratch words from `Host.Copied`. It constructs the fresh cursor's ownership
and transports the registry through the loop. The existing file-unpacking
proof and its boundary checks still pass.

`Host.evaluatesCopy` constructs synchronization, a bounded raw-byte write, and
refresh. Argument and file reads use this same proof. File open/read/close
each have constructive Core-call theorems. `Copied.loadAfterSync` proves that
opening a file reads the exact copied path. `Host.Frame` now retains
`RepresentableViews`: refresh makes every registered word fit signed i32.
Path unpacking preserves that fact. This is separate from range disjointness;
it does not turn registry validity into an assumption of coherent contents.

The focused audit (`target/verified-compiler/file-prepare-audit.log`) passes
with only standard Lean axioms. The combined prefix theorem checks in 0.90
seconds and the focused path tests/audit in 3.3 seconds. Checks cover UTF-8,
all four byte lanes, untouched tails, unrelated buffers, pre-existing handles,
EOF, and source/binding mismatches. A redundant large interpreted-loop test
initially took 27 seconds; smaller lane/tail cases replace it, while the
existing length-boundary and large unpacking tests retain that coverage.

The exact-source check (`target/verified-compiler/file-prepare-source.log`)
passes on the unchanged 18-file self-embedding in 23.52 seconds. It checks the
complete prefix against the actual file-loop body, including the open service,
pointer/length bindings, and handle guard. The existing file-unpacking consumers
also pass (`input-consumers-final.log`). No command exceeded two minutes.

The remaining public premises are valid registered buffers and their local
bindings, capacities, disjoint view ranges, a selected nonempty path of at
most 1,024 UTF-8 bytes, an existing modeled file, and a representable next
handle. Startup already returns the registry. The main-loop composition must
still derive non-aliasing and preserve its caller resources. The ordered-file
loop, per-unit output-byte connection, and whole-main success/failure/completeness
contracts remain open.

`Input.File.Checked.read` now proves the complete authenticated `read_file`
call for fitting files. It executes the capacity guard, pointer synchronization,
pointer guard, request-size constant, capacity-plus-one probe, host reads, count
guards, unpacking at the current destination offset, and total updates. The
outer loop terminates by consuming the remaining file suffix. This covers
multiple chunks and the final EOF read, not just one-chunk test inputs. The
result returns the exact source bytes and count, retains the destination's
unwritten tail, preserves other caller cells and registered buffers, and
restores caller locals and allocation budget. The file handle remains open
with the correct offset: closing it belongs to the enclosing caller.

The public premises describe resources, not successful execution: registered,
disjoint buffers with representable i32 words; sufficient destination capacity;
at least 65,536 bytes of scratch; a readable, fresh appended handle to an
existing modeled file; and a target usize that represents the request bound.
The theorem does not prove native OS behavior. It does not yet cover the full
oversized-input or host-failure call path. The actual overflow guard is proved
and exercised, but that is not a general failure theorem for the whole reader.

The shared unpack initialization now lives in `Input/Unpack/Initialize.lean`,
with its contents moved from the path-specific location. Both path and file
callers import it directly. The generic proof accepts a destination offset;
the path-specific source relation still requires zero offset. No forwarding
module remains. `Host.Effect` supplies an I/O-aware frame: it retains cells,
bindings, views, and budget without incorrectly requiring the host world or
raw byte heap to remain unchanged.

Closing checks for this boundary:

- `Input.File.Checked.read` checks in 0.95 seconds; the complete body in 1.3
  seconds. The outer-loop proof checked in 0.95–2.8 seconds across focused runs.
- `Tests.File` passes 180 complete reader executions covering byte lanes,
  nonzero offsets and offsets past EOF, empty input, exact capacity, overflow,
  untouched tails, another buffer, an older handle, and caller-local restoration.
  Its tests and axiom audit take 1.3 seconds. Every new reader theorem uses only
  `propext`, `Classical.choice`, and `Quot.sound` (`read-file-audit.log`).
- The complete body, signature, and scratch-size constant match the current
  18-file self-embedding. The source-linked reader cases and existing integration
  checks pass in 25.60 seconds (`read-file-source-final.log`). No Lanius source
  or emitted embedding changed at this boundary, and no command exceeded two
  minutes.

`Entry.File.Read.Stage.executes` now also composes the actual caller's
`read_file` call, count binding, mandatory `close`, and read/close success
guard. Its continuation starts at `extract_syntax`, with exact source bytes,
the original handle list, the registry, representable words, and preservation
of all buffers other than source and scratch. It also retains the source
length, view identities, and other non-array local values. The source checker
authenticates both callees, the fixed capacity, the complete guard, and the
bindings that must not be shadowed.

The read/close stage checks in 1.2 seconds and its expanded test/axiom audit
in 1.7 seconds (2.58 seconds for the focused command, `read-close-audit.log`).
The actual caller matches the current embedding and its session regression
passes in the 25.06-second integration run (`read-close-source.log`). An initial
production-sized interpreted fixture spent over 90 seconds synchronizing mostly
unused buffers; it was stopped before two minutes. The replacement uses a small
five-byte session with spare storage and another live buffer. It tests control
flow and preservation, while the universal theorem covers production sizes.
This was a test-workload reduction, not a claim that the interpreter itself
became faster.

Next: derive this stage's resources from `Entry.File.prepare` and connect its
result to the existing frontend and unit-emission proofs. These adjacent
checked stages are not yet one end-to-end ordered-file theorem. Neither this
boundary nor its local kernel-only audit closes milestone 3 or the later
compiler milestones; inherited native proof assumptions remain for the final
trust audit.

That connection exposed a contract mismatch: `Frontend.SyntaxData` and the
raw-lexer call proofs describe a source array whose physical length equals the
input length. The actual caller has a 65,536-element source buffer and passes
the file length separately. Step 3 remains proved on its stated domain, but
its theorem cannot yet be applied to this padded caller buffer.

Before adding a new proof family, check the actual frontend call closure for
operations that can observe or overwrite the extra capacity. If it uses only
explicit indexing, a general buffer-extension execution theorem could retain
the existing tightly sized proofs and preserve the unused tail. The alternative
is to generalize the source-storage contracts throughout the lexer and frontend.
The bounded next steps are: audit the actual syntax and call closure; choose the
smaller sound proof boundary; prove physical/logical length transport; and apply
it to the caller. A syntax audit alone is not a correctness theorem, and no
unproved padding-safety premise counts as closing this connection.

The syntax audit found 83 functions reachable from the actual `extract_syntax`.
Only function 60, the keyword-string matcher, falls outside the proposed
indexing-only fragment: it creates a raw word view of a string. The complete
source check still passed (`buffer-extension-source.log`). The temporary audit
module was removed after collecting this result; no unproved transport API was
left behind. A whole-frontend transport theorem would need additional memory
rules, so that expansion is deferred while composing the existing path/open and
read/close theorems. The physical/logical source-length gap remains explicit.

`Entry.File.Load.Pipeline.executes` now completes that composition. From the
initial registered buffers, argument index, and existing modeled file, it
executes path length/copy/unpack, exact-path open, the complete reader, close,
and their success guards. It constructs the reader's handle and storage
resources from the preceding stage. Its continuation starts at the actual
`extract_syntax` statement with both exact byte arrays, both logical lengths,
the source buffer's original unwritten tail, unchanged unrelated buffers and
locals, and the original handle list. The world records the exact host-call
sequence and next-handle increment.

The path/open interface now retains the path length instead of dropping it.
The source relations reject shadowing of that length by the handle, read
count, or close result. The public resource domain still requires fitting
files, representable registered storage, non-aliasing buffers, a fresh and
representable next handle, and sufficient target/address capacity. Those
conditions must still be derived from startup and preserved by the ordered
file loop; they are not assumptions that any component executed successfully.

The focused composition proof checks in 1.4 seconds. Six composed executions
cover empty, zero-byte-valued, and five-byte high-bit input under ASCII and
UTF-8 paths, with nonzero tails, separate scratch buffers, an older handle,
and exact caller restoration. Nine binding mutations are rejected. The
new load tests and standard-axiom audit check in 1.1 seconds; the updated path
tests check in 3.4 seconds (`file-load-audit.log`, 5.18 seconds overall).
The actual-source pipeline connection and source-linked cases pass on the
unchanged 18-file embedding in 25.09 seconds (`file-load-source.log`).
No command exceeded two minutes and no source re-extraction was required.

Next: connect the loaded source's physical capacity to the frontend's logical
input contract, complete the unit-output connection, and derive/retain these
file-loop resources from startup. The file-loading prefix is complete on its
stated domain; the ordered-file loop and whole-main success/failure/completeness
theorems are still open.

Resource handoff subtask: retain distinct registered addresses in the shared
allocation registry. Heap well-formedness plus distinct addresses yields the
byte-range separation required by file I/O; distinct language-level roots alone
does not. Fresh allocation and string borrowing must establish the fact, and
existing scope/heap-frame transitions must retain it. Strengthening the owning
registry avoids adding another independent non-aliasing assumption to startup.

That subtask is now proved: `Allocation.Registry` retains distinct addresses,
and `Registry.disjoint` / `Registry.apart` derive byte-range separation. Host
allocation proves address freshness from the allocation frontier; borrowed
string views retain the same freshness evidence. Synchronization, refresh,
cell writes, local scopes, and call restoration preserve the strengthened
registry. The file-loading input contract no longer assumes global range
separation or a separate path/source range fact; it derives these from the
registry and distinct buffer roots. Startup already constructs and returns
this registry, so the stronger fact is not delegated to its continuation.

The initial broad consumer rebuild hit the 119-second safety timeout. Two
small helpers had unnecessarily changed foundational memory/view modules and
invalidated existing parser proofs. Their actual contents now live in the
allocation layer; both foundational files are unchanged. No compatibility
wrapper or duplicate helper remains. The focused startup, loading, packing,
path, and compaction checks pass in 20.17 seconds, including their standard-
axiom audits (`address-registry-focused.log`). The load composition checks in
1.5 seconds and its tests in 1.2 seconds. A repeated-address counterexample
confirms that fresh backing roots do not imply fresh raw addresses.
The interrupted broader frontend-consumer rebuild is not counted as passing.
The final exact-source check passes in 23.54 seconds on the unchanged 18-file
self-embedding (`address-registry-source.log`). No command ran beyond two
minutes; the broad rebuild was stopped by its configured timeout. These
changes improve the resource handoff and avoid unnecessary dependency
invalidation, not the runtime of the extractor or the whole-program checker.

The logical-length/physical-capacity handoff is now proved. The earlier frontend
contract used a source backing array exactly as long as the input; `main` instead
passes a 65,536-word slice and a separate logical file length. The public theorem
`Frontend.CheckedSyntax.padded_call_evaluates` now accepts that actual padded
storage and derives its result from the existing lexer/parser proof. Callers
supply ordinary buffer ownership and inputs, not successful frontend execution.

The reusable proof lives in `Semantics/Capacity/`. Its fuel-inductive execution
simulation widens the selected source backing and its reachable slice views,
retains the original tail exactly, and leaves unreachable historical caller
cells alone. Indexed reads/writes, loops, calls, aggregates, and fresh borrowed
word views are covered. A proof-producing fragment checker excludes implicit
slice iteration, array-to-slice conversion, pointer access/synchronization, and
external calls. All 83 functions reachable from the actual `extract_syntax`
pass this checker. Raw-view construction reads the same heap and creates a fresh
semantic cell in both executions; this suffices for execution transport but
does **not** prove preservation of the stronger native-view allocation registry.
That invariant remains a separate composition obligation.

The existing semantic collector now consumes only the grammar ownership it
actually used. `SemanticTokens.padded_frontend_then_collect` reuses that proof;
there is no duplicate collector implementation or compatibility wrapper.
The exact current-source check instantiates both padded public call theorems
and passes in 24.00 seconds (`padded-frontend-source.log`). The 189 small
execution comparisons cover spare tails, nonzero slice starts, indexed source
mutation, nested calls, borrowed string words, loop control, and untouched
historical caller slices (`capacity-tests.log`, 0.65-second test module).
The padded public call and collector proof modules check in about one second
each with dependencies built. Their audit passes in 6.87 seconds and adds no
axioms to the frontend's 463 inherited nonstandard assumptions
(`padded-collector-audit.log`). Those assumptions remain open trust debt, not
newly justified facts. The frontend dependency graph also completed its genuine
rebuild in 50.86 seconds; subsequent focused checks use the resulting artifacts.

`Entry/File/Frontend.lean` derives padded ownership directly from the loaded
file bytes and preserves the other seven buffers through the reader's writes.
`Entry/File/Syntax.lean` evaluates all 17 actual arguments, binds `extracted`,
and composes the full path/open/read/close/frontend prefix. Its only remaining
execution premise starts at the source continuation **after** the frontend
call. The composed proof module checks in 1.3 seconds. The source checker rejects
changed capacity/depth literals and disconnected or shadowed input bindings.
Its full current-source check passes in 23.95 seconds, including 41 binding
mutations and the reader boundary executions (`file-syntax-source.log`); the
focused handoff audit checks in 1.4 seconds (`file-syntax-audit.log`).

The same capacity distinction now reaches the unit emitter: `Emission` has a
separate `sourceCapacity`, and its storage/collector/decoding adapters consume
the padded frontend output directly. Changing that capacity changes only the
passed slice, never the logical byte count or encoding. The existing serializer
was already capacity-aware; no second serializer proof or execution simulation
was needed. Its standard-axiom audit and exact-source instantiation pass
(`padded-emitter-audit.log`, `padded-emitter-source.log`, 24.33 seconds for the
source check).

A second caller mismatch was found at the collector: `main` passes the record
array's capacity, but the proof had required the exact used-word count. The
existing traversal now admits a bounded `recordsLimit` covering the serialized
prefix; bounds checks and state-child reads are proved under that limit. The
public frontend/collector adapter passes the actual physical record capacity.
The old `wordsFit` fact is derived from the limit bounds, not supplied twice.
The collector regression now checks 56 executions across tight, padded,
1,048,576-word and maximum-i32 limits, output capacity failures, malformed
records, split tokens, and caller frames. The updated collector/emitter audits
pass and the actual-source check completes in 24.74 seconds
(`collector-record-limit.log`, `collector-record-limit-source.log`).

`Entry.File.process` composes the file-loading prefix, the padded frontend,
the status accessor/guard, and both node/token accessor bindings in one theorem.
It constructs `FrontendReturn` observations from the reader and frontend proofs;
callers do not supply them. The two remaining execution premises start at the
actual diagnostic body on failure or the actual collector statement on success.
`Results.Stage.dispatch` proves the branch decision and stops before reading
counts on failure. On success it proves both counts and retains every old cell
and non-shadowed local across accessor calls and fresh bindings. The composition
checks in 1.0 seconds and adds no assumptions beyond the frontend baseline
(`file-process-audit.log`). The whole prefix is linked to the actual self-embedding
in 23.25 seconds (`file-process-source.log`). Twelve small accessor/control-flow executions cover
zero/nonzero statuses, distinct count fields, and caller restoration. Diagnostics
and the downstream collector are replaced only in these focused executions;
their production execution is not claimed by these tests.

`Entry.File.process_collect` extends that same prefix through the actual
ten-argument collector and its error guard. It preserves the semantic buffer
from ordinary initial resources, derives the collector's local arguments from
the frontend bindings, and proves the 131,072-word capacity sufficient from
the returned token bound. Callers do not assume collection succeeds. The
remaining success continuation starts at the actual emitter statement.
Shared frontend frame lemmas live in `Frontend/Frame.lean`; the grammar lemma
was moved there, not duplicated or retained behind a wrapper. The new stage
and composition modules check in about 1.3 seconds each. Focused argument,
guard, shadowing, and axiom checks pass (`file-collect-tests.log`), and the
current self-embedding check passes in 23.92 seconds with all 56 collector
execution fixtures (`file-collected-source.log`). No assumptions were added
beyond the existing frontend baseline.

The emitter composition (now part of `Entry.File.step`) extends this boundary through the real 19-argument
emitter, including the nested `raw_count(extracted)` call, `output_length`
assignment, and return-21 guard. The loaded path, frontend prefixes, semantic
assignments, output storage, and every argument local are derived from the
preceding stages. On capacity failure the proof retains the precise partial
buffer and stops before the success continuation; it does not assume the
emitter succeeds. The new execution/storage/reads/composition modules and
standard-axiom audit pass (`file-emit-tests.log`, 1.2-second test module).
The exact-source check passes in 25.38 seconds (`file-emitted-source.log`),
including nested-accessor arguments, cursor mutation, error/success branches,
changed capacities, swapped counts/buffers, and shadowed live bindings.

The file-step interface now retains complete state postconditions and the
actual completion, rather than only a host-world predicate and a completion
chosen before execution. `Scope.Post` closes temporary scopes without losing
buffer, cursor, heap, or view facts. The existing path/reader/frontend/result
proofs now also retain the physical IDs of non-shadowed caller bindings.
`Advance.finishes` uses those IDs to increment the original argument cell and
preserve the output cursor and emitted contents. `Entry.File.step` composes
that final increment directly: its success branch has only a logical
postcondition obligation, no downstream execution premise. Frontend failure
still requires the diagnostic body; emitter failure returns 21 internally.
The old `Emit/Process.lean` contents were moved into `File/Step.lean`, with no
old-path wrapper or import. The complete file-step source check passes in
24.37 seconds (`file-step-source.log`); the step module checks in 1.1 seconds
and its axiom audit passes (`file-step.log`). The interim state/outcome checks
also passed in 24.56/25.68 seconds (`file-state-source.log`,
`file-branch-source.log`). All new frame and increment proofs use only the
standard axioms; the composed step inherits the same frontend baseline.

Native-memory preservation now reaches the complete source tokenization
prefix. `Host.MemoryFrame` retains the original registered views and allocation
budget, and transports both `Allocation.Registry` and signed-word
representability. Fresh string borrowing, matcher calls, keyword dispatch,
both compaction passes, raw-record copying, and parser-kind copying return
these facts through their existing execution contracts. The complete
`Frontend.lex_to_canonical` result includes this frame without an additional
execution or native-registration premise. Lower typed stores now expose their
post-right-hand-side write effect; pure copies and accessors retain their
heap/view frame. Existing callers were updated directly, without legacy
wrappers. The source and self-embedding did not change.

The new canonicalizer regression uses registered native buffers, including
an unrelated buffer with both signed-i32 boundary values. All 24 cases check
the result and untouched capacity, original registrations, distinct new
roots/addresses, unchanged allocation budget, and a complete to-heap/from-heap
round trip for every view. The actual self-embedding check passed in 26.23
seconds (`native-self-source.log`). The dependent file-step and frontend
checks passed in 25.71 seconds (`native-final-tests.log`). A shared-interface
rebuild took 60.32 seconds (`native-boundary.log`); no command exceeded the
two-minute limit. These are validation times, not an extraction-speed gain.

The next parser boundary can reuse Core's existing runtime type-preservation
theorem instead of adding a range proof to every workspace write.
`Host.MemoryFrame.ofRuntime` derives complete registration and representable
words from a typed terminal state and an unchanged heap/view frame.
`Host.checked_evaluation` gets that typed terminal state from the accepted
program's typing proof and an already-proved evaluation. Both use only
standard axioms. The linked recognizer now retains its heap/view frame, and
`canonical_to_recognize`/`lex_to_recognize` compose the native-memory result
conditional on runtime typing at their final state. This is deliberately not
reported as unconditional native preservation for the whole frontend: runtime
typing must still be carried from the real call entry, and the tree/result
tail must retain its memory frame. The updated source-to-recognizer/file-step
build and axiom audits pass (`typed-recognition-tests.log`, 34.41 seconds),
with no assumptions beyond the inherited frontend baseline. The final
unchanged-self-embedding check passes in 25.92 seconds
(`typed-native-self.log`), including all registered-buffer regression cases.

Native-memory preservation now reaches the next-file boundary.
`CellOnly.Region` checks a source statement and its transitive call closure;
its generic execution theorem proves heap/view identity without a separate
range proof at every array write. The full frontend checker retains this
certificate for the parser/tree/result tail. `CheckedSyntax.call_native` and
`padded_call_native` derive the complete native memory frame from ordinary
typed inputs and the already-proved execution. The physical padded buffer is
not confused with the shortened logical array: `ViewLayout` separates native
metadata from cell contents, and terminal runtime typing restores the exact
array lengths and signed-word ranges.

`Host.MemoryTail` carries that evidence through later cell-only work, without
requiring typing at each internal boundary. File loading/frontend, result
accessors, collection, and emission retain it directly in their existing
interfaces. The collector call and emitter assignment have independently
checked cell-only closures, including nested argument calls. `Entry.File.step`
now derives final runtime typing from its typed entry and source-statement
typing proof. Every `.next` result returns a complete `Allocation.Registry`
and representable registered words for the next iteration. It also retains
every original registration as a prefix of the final view list, so the next
file's ordinary buffer-membership preconditions are available. Temporary lexical
scope restoration retains these facts. The final typing witness is also
returned, not discarded. At this checkpoint, frontend-failure diagnostics
remained its only component-execution premise; the September 10 work below
discharges it.

The generic cell-only regression covers 63 recursive/range/while executions
with slice offsets, spare capacity, signed boundary words, and unrelated native
buffers. It rejects allocation, byte/view operations, host calls, and forbidden
operations hidden in transitive callees or untaken branches. The strengthened
file/frontend tests and axiom audits pass (`native-file-tests.log`, 14.80 seconds).
All new generic memory proofs use only standard axioms; the composed file step
adds none beyond the 463 inherited frontend assumptions. The exact 18-file
self-embedding check passes in 26.46 seconds (`native-file-source.log`), linking
the actual collector and emitter memory certificates and typed file-step
theorem. These are validation times, not an extraction-speed improvement.
No Lanius source change or re-extraction was needed for this boundary.

The diagnostic branch's non-fallthrough condition is now checked from its
source by `Source.CheckedStop.not_next`, rather than supplied with the caller's
execution premise. `Results.Stage.checkSupported?` rejects a missing return,
a one-sided conditional return, and a possibly skipped returning loop. The
focused branch checks pass in 4.41 seconds (`diagnostic-stop.log`). This proves
what a normally completing diagnostic branch does, not that all its calls
terminate. `Host.evaluatesStderr` also proves the actual byte service preserves
all registered arrays, stdout, arguments, files, and open handles through both
native synchronization passes. Its 263 byte/wrapping/boundary regression cases
and standard-axiom audit pass in 1.56 seconds (`stderr-tests.log`). This first
checkpoint left the decimal helper and six-call failure-branch execution open;
the September 10 checkpoint below closes them.

Final acceptance rebuilt the affected self-check linkage and validated the
exact 18-file embedding, including the retained original registrations and
actual stderr declaration, in 30.31 seconds total
(`file-boundary-acceptance.log`). The audit explicitly recounts 463 inherited
nonstandard frontend assumptions and no additions from the new composition.
The preceding shared-interface rebuild took 40.04 seconds; every command
remained below the user's two-minute limit. `git diff --check` also passes.

Current artifacts at this checkpoint (read from the workspace, not regenerated):

- GPU-built x86 extractor: `6163554af500bd57e3c82e4763dad3e2412499ef22146d7d28186bf696ee7c0d`.
- Singular self-embedding: `8c918c01dab6fccdd2e5ad8ac99002a979286b10c368a9638026070ac3e40328`.
- Ordered source-content manifest: `f289195e6e968f2306f5c5d773bbd535bb867ff308bd89df8d3f1e2a056cace9`.

The September 10 checkpoint closes frontend diagnostic execution.
`Semantics.Prefix.Reaches` retains executions already established while lexical
scopes remain open. Its typing theorem recovers the actual continuation's
context and runtime store typing from the typed file entry. The path, file
loading, frontend binding, and status guard retain this evidence in their
existing interfaces. `Host.checked_prefix_type` and the existing memory-tail
proof then derive the diagnostic entry's registry and representable words.
No diagnostic run is assumed in order to obtain its own preconditions.

`Diagnostics.Natural.Checked.write` proves the complete existing Lanius
`write_stderr_natural` helper. Negative inputs return immediately. The first
loop grows a positive divisor only while multiplication by ten fits beneath
the input; its decreasing measure is the remaining quotient. The second loop
writes bytes and divides the divisor by ten until it reaches zero. The proof
uses the actual wrapping i32 counter operations and closes both fresh local
scopes. Every old caller cell and registered buffer survives, and the native
allocation budget and view list are unchanged. `Host.StderrOnly` states that
only stderr and its byte-call trace may grow. This uses the current modeled
host service; it does not prove a Linux syscall/runtime refinement. Exact
decimal text is tested but is not needed by `RunFailureSafe`, which deliberately
leaves stderr unconstrained.

`Diagnostics.CheckedFrontend.executes` checks the complete six-call branch,
including each result accessor, call order, caller-local identities, and the
return-28 statement. Argument bounds follow from the original store typing,
not extra field-range premises. `Entry.File.step` now constructs both success
and frontend-failure executions on its stated input domain. Its remaining
callbacks assert logical postconditions; none assumes a component execution.
This does not cover file-loading failures outside that input domain, the
ordered-file loop, or the whole-main contracts.

The original caller-local bindings are now retained from the outer path
scope through the complete file-step result. Together with the final runtime
typing and original-view preservation, this lets the loop use an ordinary
state predicate via `Scope.Post.inScope_iff`, rather than treating a projected
caller state as the real returned state. Reconstructing the complete next
iteration's buffer contents, grammar evidence, input data, and output history
still needs composition.

The focused diagnostic regressions cover 34 integer cases around powers of
ten, zero, negative values, and signed-i32 extremes. They compare text against
Lean's independent integer renderer and check caller cells, the complete host
world, native registrations, and a to-heap/from-heap round trip. The actual
source-linked branch also runs with three distinct six-value inputs and rejects
missing calls, reversed calls, and a changed return code. New diagnostic and
prefix proofs pass the standard-axiom audit. The composed file step retains
exactly the existing 463 nonstandard frontend assumptions; none was added.

The affected self-check build and regressions passed in 7.38 seconds
(`diagnostic-acceptance-build.log`). Exact-source integration passed on the
same 18-file self-embedding in 25.09 seconds (`diagnostic-self-source.log`).
The later caller-scope handoff rebuild passed in 25.77 seconds
(`file-scope-handoff.log`), and its focused scope audit passed in 20.29 seconds
(`file-scope-final.log`). The final file-step/diagnostic dependency audit passed
in 3.63 seconds (`diagnostic-final-audit.log`), again reporting the unchanged
463-assumption frontend baseline. `git diff --check` passes. These are checking
times, not extraction-speed gains.
The x86 executable, self-embedding, and source-content hashes above were reread
and remain unchanged. No Lanius source edit, re-extraction, Rust/Python addition,
or Wasm path was needed. All commands remained under two minutes.

Next: establish the complete next-iteration logical resources, close the
ordered-file loop, connect final output, and prove the whole-main contracts.
Milestone 3 and the full seven-step goal remain open.

`CompactOutput.Text.Checked.append` proves the full text helper call on its
supported capacity and padded-storage domain, including initialization,
packed-byte reads, loop termination, and return. Its effect permits changes
only to the output cell. Negative lengths return before any buffer access.
The proof exposed missing word padding in the extractor's framing literals;
the source now supplies explicit `\0` padding while preserving the emitted
lengths. The refreshed GPU-built x86 extractor self-extracts successfully.

This is not yet a whole-main theorem. Ordered-file execution still needs
composition, along with failure paths and full heap/view invariants.
The existing `RunSound`, `RunFailureSafe`, and `RunComplete`
targets remain open. The older chronological notes below do not supersede this
checkpoint.

| Step | Boundary that becomes complete | Status |
|---|---|---|
| 1 | Successful recognizer result → callable derivation record reader | Complete; call connection checked and trust assumptions audited |
| 2 | Retained workspace → complete materialized tree | Complete on the stated caller domain; success, resource failures, wrapper rejection, source link, and axiom audit checked |
| 3 | Source buffer → complete `extract_syntax` result | Complete on the stated caller domain; whole public call, all stage failures, negative-length rejection, current-source links, and axiom audit checked |
| 4 | Extracted unit → exact accepted compact unit encoding | Complete on the stated domain; actual file-step result returns the accepted unit, exact appended bytes, and successful cursor bounds |
| 5 | Ordered files → exact successful `main` output | Complete on the stated domain: actual executable soundness, covered failure safety, finite termination, and successful-input completeness are packaged and instantiated on the self closure |
| 6 | Failure/completeness theorems and milestone acceptance audit | Active: broader external failure coverage; trust cleanup and final acceptance remain open |

Steps 1–5 are complete on their stated domains. Step 6 and milestone 3 remain open.
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

Current status is recorded at the top of the ordered ledger. Whole-main and
executable-entrypoint success/failure soundness now hold on the loading domain,
and the frontend link is constructed. This step remains active until the
successful-termination domain below is proved. The component notes that follow
record the earlier construction sequence.

Sources: `extractor.lani`, `byte_io.lani`, and `host.lani`.
Reuse input chunk/read/unpacking proofs, output clear/packing proofs,
the constructive stdout-tail proof, and the host-call memory rules.

The next completeness obligation needs a new proof family: the current parser
invariants establish sound states and append-only growth, but do not retain
closure under prediction, scanning, and completion. The work remains inside
step 5 and proceeds in this order:

1. **Done:** prove from the existing declarative token-lattice grammar that a seeded
   chart closed under those operations contains a complete start item for
   every valid input. Include nullable and split-token derivations; do not
   introduce another parser implementation or define validity by execution.
2. **Active:** establish that closure from the actual source-loop invariants,
   retaining failed-append/resource evidence where it is produced. Root-search
   exhaustion, its frontend handoff, and complete initial seeding are proved.
   Prediction and scanning completeness now cover every item in every
   final-workspace input chart, including newly appended items and preservation
   through later positions. Actual chart-head and position-zero entry discharge
   the prefix preconditions; the public parser and frontend retain both results.
   Parent traversal and nullable replay now retain their coverage through the
   actual source entries and restored callers. Next combine those guarantees
   over processed parent/child pairs in the state loop, then preserve them
   through the position loop. Closure must become a conclusion, not a new
   assumed input-domain premise.
3. Combine parser completeness with lexer, tree, and output capacity bounds
   to exclude rejection on the stated syntax/resource domain, then establish
   that domain for the self-source closure.

The alternative of assuming a successful parser run would make the desired
completeness claim circular. The existing execution proofs remain the source
of runtime behavior; the new mathematical argument supplies the missing
language-to-chart direction.

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
`RunComplete` only in their contract definitions. The following audit records
that historical state; the current completion ledger above supersedes it.
Whole-call `parse_tree.visit/materialize` theorems close
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

At that historical checkpoint the active implementation action was step 4. The reader,
materializer, and whole frontend call are checked on their stated caller domains;
the whole extractor's contracts remain open.
