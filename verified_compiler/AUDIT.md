# Extractor acceptance audit — September 12, 2026

September 16 lowering acceptance: `SelfLowering.olean` now proves
`Option.map (fun result => result.core) (lowerUnits? units) = some Self.Core.program`
for all 18 frozen Surface units. Preparation, constants, layouts, function
bodies/order, x86 target, and external-policy acceptance are included. The fresh
single-invocation check/output takes 84.77 seconds with shared support and the
saved Core candidate available; peak RSS is 3,397,912 KB. Reload and strict audit
take 1.54 seconds and are reuse. The artifact is 2,501,872 bytes, SHA-256
`24e5a4dabeee5a817aa1335a010b885ec030d4599176aff776ed16bb32ddb0b9`.
Every audited assumption is `propext`, `Classical.choice`, or `Quot.sound`.
Native Surface proposals are not proof authority: this equation authenticates
their lowering, not their source-byte origin. Source-to-Surface acceptance is
still 3/18; complete source acceptance, the closed extractor instance, and
general x86 semantic preservation remain open. See `self-lowering-fresh-final.log`
and `self-lowering-reload.log`. No complete-compiler claim is made.

September 16 Core checkpoint: `SelfCore.olean` certifies typing of the frozen
125-function candidate and its x86-64 target, with standard Lean axioms only.
It is 667,184 bytes, SHA-256
`69fc724b7c0bd2e5c81a45bab541f8ccbf403523bb5b424e0e58ebf1273ccdbb`.
Fresh generation/checking takes 15.08 seconds; reload/audit takes 1.19 seconds.
Its native source-to-Core proposal is not authenticated by this typing theorem.
The complete source-checker equation, extractor instance, and general x86
preservation remain open. `PLAN.md` separates phase and shared-build timings.

Lowering infrastructure now reduces structurally and composes retained stages
into the authoritative source-checker equation. Fresh focused regression and
audit checking takes 2.39 seconds; the connected rebuild takes 6.48 seconds.
No additional source-to-Surface unit is certified. Earlier memory-guard
failures are superseded by the lowering
certificate above. `PLAN.md` records the failed experiments and invalid early
diagnostics separately, without counting them as acceptance evidence.

Current proof acceptance: `Entry.checkSource`, its source validator, and its
execution-proof constructor have zero nonstandard axioms. The whole-main
execution and observation theorems are kernel-only too. Strict source, output,
and self-driver audits now reject inherited-trust exemptions. This closes
milestone 3.7; the former 173-assumption inventory is superseded.

The exact current 18-source instance passes executable validation and all
resource/regression checks in 44.36 seconds with shared proof/native imports
built, down from 87.91 seconds. The same general parser/tree resource checker
takes 1.18 seconds natively instead of 37.78 seconds in the interpreter. No
native computation is used as kernel proof evidence. The
artifact is 7,967,195 bytes, SHA-256
`bc11dd2187755d63eb1ad4f8de4ac547c4e753f44c5142fc15f64113e62a675e`.
This is still an IO result, not a saved kernel declaration of its successful
check. Milestone 3.9 and the general verified Lanius-to-x86 compiler remain open.
See `entry-trust-current.log`, `entry-resource-final-audit.log`, and
`self-source-lake-native.log` in `target/verified-compiler`. The native helper
build took 19.85 seconds separately; the dependent proof rebuild is not included
in the runtime comparison. `BOOTSTRAP.md` records the Lake invocation.

Saved Surface checkpoint: `proofs/Surface.lean` proves the exact reference-checker
result and original-checker acceptance for units 17, 14, and 2 of `SelfEncoding`
(`host`, `token_scan`, and `byte_io`). Their source paths are kernel-checked too.
The September 17 fresh invocation/output takes 53.66 seconds with the saved
encoding and shared imports available; the pre-change measurement was 47.79
seconds. Runtime validation improvements do not establish a kernel speedup.
The single-pass linking plan preserves the exact original forest and
reconstruction, authenticating every proposed context against the original
nodes. Peak RSS is 3,954,216 KB. `SelfSurface.olean` is 5,235,312 bytes, SHA-256
`6a057b33cdc7f09dbbfa1230679768902aa2fa1e073612be4a96e202b3b16da5`.
Its reload, strict audit, and output take 1.62 seconds through the Lake runner;
that is reuse, not fresh verification. Every audited transitive assumption is
`propext`, `Classical.choice`, or `Quot.sound`. No native decoder output is proof
authority. The runner now rebuilds the shared certificate dependencies instead
of silently relying on their existing `.olean` files. This is three of 18 units,
not whole-pack Surface/Core acceptance or closure of milestone 3.9. The earlier
host-only certificate is superseded; its recipe was replaced, not shimmed.
Checked path witnesses now prove acceptance of the original containment search,
including its pruning and fuel requirements. Exact witness-count checks prevent
truncated zipped lists from dropping obligations. Native parent/path proposals
remain untrusted. The structural numeric scanner retains its general correctness
proof and now passes an opaque-unused-suffix reduction regression. These changes
do not extend the certificate beyond its three selected units. The full
`Tests.Self` closure was not rerun; focused path, scanner, compact, and saved
certificate audits passed. See `PLAN.md` for measured costs and size accounting.

Current engineering update: the Lanius backend now produces the whole extractor
as a static x86-64 ELF, including 106 internal functions and nine host services.
The emitted executable self-extracts all 18 sources in 2.12 seconds, producing
the identical 7,967,195-byte artifact. Fresh string-data copies now agree with
Core pointer equality and mutation isolation. Runtime/ELF engineering is no
longer missing; the general recursive compiler/runtime/ELF preservation proof
remains open. Raw-parts lowering still has explicit allocation/lifetime
premises; writing a descriptor does not prove those premises. See the current
checkpoint in `BACKEND.md` for tests, hashes and the native host domain.
The extractor output cap and matching formal bounds have increased from 8 to
16 MiB to accommodate the 8,502,803-byte backend source pack. The packing
workspace is unchanged. This changes the exact bootstrap/self-source identities;
older hashes and timings below are historical evidence, not current acceptance.
The current 22-file, 12,699,327-byte backend pack passed the expanded actual-source
integration in 52.20 seconds. New allocator and indexed-caller composition
proofs cover success under an explicit recursive hypothesis, slot exhaustion,
and invalid-kind propagation. Their source proof audit uses standard axioms;
it does not establish the general recursive compiler theorem.
The full indexed-call machine contract also keeps the recursive machine
hypothesis explicit. The actual signed-i32 literal wrapper now has a complete
source-emission theorem with no recursive/helper execution hypothesis, accepted
against that exact source pack. Both the literal and its use as an indexed
helper operand now connect serialized Core to actual source and native
execution, without recursive execution hypotheses for those cases. Explicit
native storage separation remains required. These are not the general
recursive compiler theorem.
The symbolic parser data gate has fallen from 57 to 27 seconds without moving
the cost into its immediate consumer. The first frame-trust cleanup removed
seven historically reachable native assumption owners and passed its connected
audit. A second family removed 12 additional historically reachable assumptions
and passed its newly invalidated connected closure in 103.12 seconds; no fresh
global count is claimed. A shared bottom-up typing cleanup preserves exact
reification, but did not measurably reduce State.Core's 35-second hotspot.
Those component results are historical. The refreshed whole-extractor checker
and self-instance now pass as described above.

The Lanius extractor has connected source-bound Core execution proofs. The
updated exact 18-file source closure passes source/Core validation and execution
proof construction after the capacity change. Milestone 3 is **not accepted as
kernel-only**: the concrete self-validation executes the checker rather than
producing a standalone kernel-checked self-instance. Its generic proof and
source-checker dependencies no longer contain nonstandard axioms.
The verified Lanius x86 backend and later compiler milestones are not delivered.

The precise missing self-instance artifact is a closed saved
`Entry.CheckedSource selfEncoded selfSources`. `Tests.Self` currently constructs
that value inside IO; neither its generic `.olean` nor compiling the emitted
IO checker certifies the concrete successful result. The certificate must
retain `checkExtractorCoreSourcePack selfEncoded selfSources = .success accepted`,
not just an arbitrary well-typed Core program. Once retained, the existing
`CheckedExecution.correct` supplies the general extractor contract. Loading
and success-domain evidence additionally instantiate successful self-extraction.
The current `SelfCompactRequirements.lean` and `SelfLaniusX86.lean` agree;
the old `SelfCompactExtracted.lean` and its 88.78-second result are historical.
The bootstrap commands now name the current artifact. No fresh kernel-instance
runtime has been measured.
The first direct decoder and transport-literal proof probes did not complete.
The structured-data route now saves `SelfEncoding.olean`: the complete compact
encoding is valid and its exact ordered source paths/bytes match independent
file reads. `encodable`, `decoded`, and `source_bound` have zero nonstandard
axioms. The fresh check and output take 58.52 seconds, down from 75.51, with
shared imports built and 6,814,944 KB peak RSS. The source
binding uses shared quoted byte arrays and a general exact-byte conversion
theorem. Typed scalar fields discharge their bounds through generic proofs;
collection lengths and counts are still checked. Native decoding supplies no
proof evidence. A connected fixture proves exact equality with the previous
frozen data, and the unchanged Surface recipe passes against the new certificate.

This is only the encoding/source-binding part of the self-instance certificate.
It does not certify Surface/Core acceptance, the source-checker equation, or
actual execution. Its canonical rendering is not proved byte-identical to the
bootstrap's transport literal; the quoted structured data is the real embedding.
The full `Entry.CheckedSource` and self-input resource certificate remain open.
The saved partial certificate's SHA-256 is
`3db499f463e13a0a32af11321bff3cde5508909353eb76a3edc331b57889cb4f`;
its size is 35,904,016 bytes. The first reload/audit, including a shared-module
refresh, took 2.77 seconds; the shared-ready repeat took 1.32 seconds
(`self-encoding-bounded-reload.log`). Loading reuses a frozen certificate and
does not certify changed files.
See `PLAN.md` for failed experiments and remaining performance costs.
Independent [backend engineering](BACKEND.md) has since added the Lanius
instruction emitter, word/relocation proofs, and source-linked execution proofs
for nineteen emitter/helper functions. Fixed and relative public emitters are also
connected to instruction decoding; relative emission preserves its target
calculation. The shared register-form emitter has exact-byte success and
no-output-access rejection contracts. This does not close the missing whole-backend
semantic-preservation theorem or the acceptance findings here.

The September 11 scalar checkpoint adds a recursive Lanius compiler for
i32/bool operations, scoped locals, assignments, branches, and nested loops,
including stack arguments. It passes actual-source Core/native tests and
compiles its own two frame-arithmetic helpers identically under Core and the
GPU-built executable. Frame-layout/source-helper and decoded spill/reload
proofs use only standard axioms. The later frame checkpoint adds decoded
setup/teardown composition with an explicit body premise and the actual
Lanius return routine's source-to-byte-to-execution proof. Its shared proof
audit adds no assumptions. The later program checkpoint adds linked calls,
full-width values, shared aggregate storage, and checked slice reads/writes.
At that checkpoint transport accepted 100 of the 106 reachable internal bodies;
complete call closures compiled for 97 functions. The scalar/record sampler executes 60
functions on 480 inputs; a separate buffer test executes the actual raw lexer
on 96 inputs. Decoded whole-value
copying now preserves represented Core values and the saved caller frame,
with standard-axiom-only proofs. Actual-source copy emission matches that
sequence on concrete cases; its general implementation proof remains open.
Packed-slice storage and the final decoded element accesses now have
standard-axiom-only proofs connected to effectful Core indexing/assignment
and caller-frame preservation. The complete decoded guard/address sequence
now establishes the successful Core read address or the matching bounds fault.
The actual Lanius indexed-LEA emitter has general exact-byte, caller-frame,
and capacity-rejection proofs, connected to its machine step. The shared
memory emitter now has general success and atomic capacity-rejection proofs;
public Lanius load/store calls connect to decoded 32/64-bit MOV steps for all
register/base choices and signed displacements. The frame-load, word-load,
and word-store wrappers now have source-to-MOV proofs including their
workspace cursor writes. The actual bounds-check helper now has a composed
source-to-byte-to-branch-or-fault proof for all 16 condition codes. These proofs
and the shared byte-window composition rule use only standard axioms; source
authentication still inherits the existing frontend trust boundary.
The complete `backend::index::address` source body now has a sufficient-capacity
proof connected to Core's valid-address and bounds-fault behavior, with exact
byte output and workspace/caller framing. The parent expression/place compiler
must still establish the captured operands and storage relation; its recursive
simulation and general compiler-capacity rejection remain open. The general
recursive compiler proof, other extractor features, and the source-to-x86
composition remain open; see the
current checkpoint at the top of `BACKEND.md`. This does not change milestone
3's trust findings or turn the bootstrap executable into a verified compiler.

## Requirements and evidence

| Requirement | Current evidence | Limit |
|---|---|---|
| Lanius extractor atop the existing frontend | `src/extractor.lani` and `source-closure.txt`; lexer, parser, tree materialization, semantic-token collection, and compact emission are Lanius | Surface reconstruction and Core synthesis still run in fixed Lean infrastructure |
| GPU bootstrap to x86 | `target/verified-compiler/lanius-extractor` is a static x86-64 ELF; it emits the complete module | The GPU compiler and this executable remain untrusted |
| Singular exact-source embedding | `checkCompactSurfaceArtifactPackSources?` retains decoding, schema, exact ordered paths/bytes, and checked Surface data; the existing embedding still passes | Native execution of this checker is not a saved kernel proof of this concrete input |
| Source-derived Core | `Entry.CheckedSource.produced`, `SourceBound.metadata`, and `CheckedSource.coreUnique` now bind the checked source, preparation, layouts, constants, functions, and actual executable together | Algorithmic provenance is not a semantic preservation theorem for every lowering pass |
| General extractor correctness | `CheckedExecution.hostSafe` gives finite normal execution and all-fuel soundness/failure safety on `HostDomain`; `run_complete` and `succeeds` give success on source-only syntax/resource conditions plus loading conditions | Core semantics and the explicit host model, not machine-code execution |
| Actual self-source instance | `Tests.Self` consumes `Entry.checkSource`, validates all 18 sources/resources, and uses the public contracts | Native checker execution; no standalone `SelfCompact*.olean` self-proof was found |
| Lanius x86 backend and machine-code preservation | The recursive Lanius backend/runtime/ELF emitter produces and runs the whole extractor. The parameter-return case and shared index/memory helpers have source-linked proofs; see `BACKEND.md` | General recursive preservation, malformed-transport rejection, storage/alias/lifetime relations, machine/environment coverage and runtime/ELF proofs remain open |
| Whole compiler through x86 | No composed source-to-machine-code theorem | Milestone 5 remains open |
| Extractor executable produced by the verified compiler | `extractor-lanius-x86` is now produced by the Lanius backend, bootstrapped by the GPU compiler; its self-output matches exactly | Backend proof and Lanius source-to-Core implementation are unfinished, so this executable is still untrusted and milestone 6 remains open |
| Fast trusted extraction | The Lanius-backend-produced executable self-extracts in 2.12 seconds; checking/proving is separate | No verified compiler/extractor trust boundary or fresh few-second proving workflow; milestone 7 remains open |

## Open pointer-semantics mismatch

Source inspection found an obstacle to a general preservation theorem, not
just a missing lemma. `Memory.Heap.allocate` assigns deterministic logical
addresses (the first four-byte, four-aligned allocation starts at 4), while
the Lanius runtime allocator returns OS-provided addresses. `Storage.shape`
currently represents a Core pointer by that same numeric machine word.
This relation does not describe ordinary native allocations.

The Core transport accepts nonzero pointer literals. Allocating four bytes
and comparing the result to `.pointer 4` therefore distinguishes Core from
native allocation whenever the native address differs. Source elaboration
only admits null pointer literals, but Core/source wrapping pointer arithmetic
can expose the same address policy; that arithmetic is not yet supported by
this backend. Pointer-to-integer casts are not currently supported and are
not the cause of this mismatch.

Host ranges need attention too: Core `Heap.loadByte` looks up the block at
`pointer + offset`. A host read can cross adjacent logical allocations, while
separate native allocations need not be adjacent. These counterexamples were
derived from the definitions, not executed as regression tests.

The actual extractor's recorded closure uses allocation, null checks,
slice/string pointer conversions, and host buffer ranges, without pointer
arithmetic or numeric address observations. A fresh injective block-address
mapping is a plausible proof route for that program, provided its view and
single-allocation range invariants are proved. It does not justify arbitrary
accepted-Core correctness. The full-language choice between native allocation
semantics and a runtime logical-address translation layer remains open; no
semantics or accepted-input restriction has been changed to conceal the gap.

## Contract defect repaired during this audit

`CoreSynthesis.Program.CheckedProgram` retained typed Core, checked Surface
data, a prepared context, and function-lowering evidence, but did not retain
equations connecting preparation, structures, and constants to those source
inputs. The implementation computed the intended values; the returned record
alone did not establish that provenance.

`CoreSynthesis/Provenance.lean` now derives the missing relationships from the
successful generic checker equation. The equation binds the entire Core
construction, including constants. `SourceBound.metadata` exposes the Surface,
preparation, and structure-layout equations; `SourceBound.unique` excludes
substituting another accepted program for the same exact inputs.

`Entry/Source.lean` retains the original checker equation, accepted source,
entrypoint, and execution proof in `CheckedSource`. `checkSource` invokes each
existing stage once. The self-check now consumes that combined certificate
directly. This is not another extractor, parser, synthesis pass, or compatibility
workflow. Existing component execution proofs remain reusable for their own
Core-level contracts.

## Trust status and scope findings

1. **Current full inventory: zero nonstandard assumptions.** The rebuilt
   `Entry.checkSource`, including source validation and execution-proof construction,
   now uses only standard Lean axioms. The previous 173 assumptions in 158 owners
   are historical; the successive cleanups are now checked together. The recognizer caller,
   `executeRecognitionRegion`, now uses only `propext`, `Classical.choice`, and
   `Quot.sound`: its 23 prior native assumptions are gone, with its grammar/resource
   preconditions and full execution result unchanged. The strict caller audit
   and its new compositional source equalities pass. The complete lexer and
   number-scanner call constructors now also use only standard Lean axioms,
   down from 18 and 20 native assumptions. Their source-linked execution and
   frame contracts are unchanged. The linked raw-lexer call and its frontend
   result-count consumer are now kernel-only too: the linked call's 12 native
   assumptions are gone, with its complete contract and input domain unchanged.
   The scanner audit checks 73 declarations without local budgets or
   inherited-trust exemptions, including canonicalizer execution and its source
   checker. The complete `Frontend.CheckedSyntax.call_evaluates`, `call_native`,
   and `reject_call`, plus source/link construction, also have no nonstandard
   axioms in the current rebuilt frontend. `Tests.FrontendLink` enforces a strict
   six-target audit rather than inheriting the execution theorem's assumptions.
   Their existing grammar, storage, ownership, and resource domain is unchanged;
   the memory contract is not an x86 preservation theorem. See
   `frontend-trust-current.log` and `frontend-distinct-strict-audit.log`.
   The current whole-extractor inventory is `entry-trust-current.log`; strict
   audits also cover the combined source checker and actual main construction.
   Concrete self-instance acceptance stays open. See `PLAN.md`,
   `parser-trust-{before,after}.log`, `scanner-trust-{before,after}.log`, and
   `raw-lexer-trust-{before,after}.log`.
   The pinned Lean implementation and
   [Lean's validation documentation](https://lean-lang.org/doc/reference/latest/ValidatingProofs/)
   distinguish these native computation results from ordinary kernel reduction.
2. **Concrete native checking is a separate boundary.** The emitted module
   contains an encoded pack and an IO `main`; the self driver also runs in IO.
   Its successful run is useful evidence, but is not a persisted proof term of
   acceptance for the concrete encoded pack and exact source bytes. Removing
   `native_decide` from shared lemmas alone would not establish that stronger
   claim for this workflow. Final kernel-only acceptance must address both.
3. **The host model is explicit and narrower than Linux.** `HostDomain` bounds
   argument/path sizes and handle allocation, requires handle freshness, and
   starts with the ordinary empty unlimited-budget heap. Files may be absent,
   oversized, or invalid syntax. Finite allocation exhaustion has a separate
   theorem. Concurrent file changes, asynchronous read/close errors, short
   stdout writes, and arbitrary finite-budget successful heaps are not covered
   by the unified theorem. The x86/runtime work must expose its environmental
   assumptions rather than silently equate Linux with this model.
4. **No source-to-x86 claim follows yet.** The `core.target = .x86_64` field
   chooses Core scalar/target semantics. It is not an instruction encoding,
   an x86 machine model, or proof of an ELF executable. Source provenance is
   likewise not a replacement for semantic preservation of later compiler passes.

## Verification and artifact identity

- Provenance and combined checker build: 2.04 seconds (`source-provenance.log`).
- Focused self-test build and axiom checks: 2.54 seconds (`provenance-tests.log`).
- Complete source-to-execution trust inventory: 0.94 seconds
  (`source-trust-inventory.log`), 173 assumptions in 158 owners.
- Exact 18-source integration: 88.78 seconds (`provenance-self-source.log`).
  This includes 19.550 seconds for three deliberately corrupted source inputs:
  wrong path, changed bytes, and changed order. All failed at source binding,
  before execution-proof checking. The remaining run time was about 69.23
  seconds; this is not a new few-second validation result.
- Parser/tree resource checking: 37.266 seconds; output bounds: 426 microseconds;
  successful-input binding: 16.710 milliseconds. Shared infrastructure was built.
- Source and native executable were unchanged. The previous fresh extraction
  took 1.15 seconds and was byte-identical; all identities were rechecked during
  this audit. No command exceeded two minutes. `git diff --check` passed.

| Artifact | SHA-256 |
|---|---|
| `src/extractor.lani` | `a27bc4964928bb387a46e4f61271d7721780d3eafad6406a7fecc1facdea82c4` |
| x86 bootstrap | `327f8376d70478ad36e07476662c965c0139f7b15e9b07f2c63532a21c5c75b0` |
| singular embedding | `f6d7a1316a231e86588bc673ae002a1aa115afa6223b9b30c666fe1b751b5270` |
| parser envelopes | `10016296f6b01b675529db80ed39ea000a4af95c3d7a01dfbb70c419e1b6d821` |
| ordered closure list | `079059b1eb54011de70900c1c5a9f7d411a027c7166728a95b55aef461a77bf3` |

## Next acceptance work

The general extractor execution pipeline and exhaustive modeled-host coverage
are connected. Do not add isolated failure cases absent an actual gap in that
domain. Kernel-only acceptance still needs the native-assumption obligation
and a concrete self-certification method; keeping compiler trust would instead
be an explicit change in assurance, not a completed cleanup. The seven-step goal
remains unchanged, including the full Lanius x86 compiler and trusted fast path.
