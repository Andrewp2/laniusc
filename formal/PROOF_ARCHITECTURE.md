# Verified compiler proof architecture

Status: active, incomplete. This file describes the current proof boundary,
not the history of the proof reset.

**Design update, 2026-09-27:** Read the
[compiler working notes](../verified_compiler/NOTES.md) before extending the
extraction architecture. The agreed target trusts the verified Lanius
typechecker and extractor rather than reconstructing typing proofs for each
emitted program. The notes distinguish that target from the unfinished proofs
and the per-program checking mechanisms described below.

## What the proof is meant to establish

The public result must be one connected implication about an actual compiler
certificate:

```text
the certificate checker accepts exact source files and exact ELF bytes
  -> the reconstructed Surface program is the program described by those files
  -> the authenticated Core program is a well-typed lowering of that Surface program
  -> the ELF function spans implement that Core program
  -> execution from the ELF entry refines execution of the selected Core entrypoint
```

This is partial correctness of a successful compiler result. Compiler
termination, helpful diagnostics, and acceptance of every valid Lanius program
are separate completeness properties. They must not be smuggled into the
semantic-preservation theorem, and semantic preservation must not be weakened
to a claim that bytes merely decode.

The certificate payload may be produced by an untrusted executable. No
decoded source tree, Core program, function span, or machine byte is trusted:
the Lean checker reconstructs or authenticates each one. A native build of
that checker is a performance optimization; the kernel-checked soundness
theorem remains the trust boundary.

## Current connected spine

`Compiler.EndToEndCheck.check` currently composes these concrete boundaries:

1. `Extraction.CertificateBoundary` decodes certificate version 3.
   `CertificateRoundTrip` proves the actual encoder/decoder round trip under
   explicit UTF-8, count, signed-word, and span representability bounds;
   `CertificateBoundaryBridge` then recovers the exact encoded fields from an
   accepted round trip.
2. `FrontendBoundary` checks exact source identity, lexer evidence, grammar
   derivations, Surface reconstruction, declarations, and imports.
3. `CoreBoundary` and `CertificateLoweringCheck` authenticate a typed Core
   program and reconstruct `ProgramLowering` evidence from the same source
   pack, catalog, imports, declaration rows, and aliases.
4. `X86.Transport` authenticates the canonical Core transport consumed by the
   Lanius backend.
5. `CertificateImageCheck` and `ImageCheck` derive ordered function slices
   from the certificate-owned ELF and prove that those exact slices are loaded
   by an ELF image.
6. `ProgramCheck` applies `FunctionCheck` to every Core function and connects
   the selected zero-argument entrypoint to its authenticated machine bytes.
   The accepted backend fragment includes literal and parameter returns, the
   checked two-function direct-call path, and one authoritative structural
   path from recursive scalar expressions through next-completing statements,
   a terminal return, the real function epilogue, and the uniform program
   preservation theorem.  Supported recursive expressions include i32 and
   boolean literals, i32 positive/negate, boolean logical-not, and nested i32
   add/subtract/bitwise and/or/xor.  The old expression-only and
   literal-binary whole-function preservation branches have been removed.
7. `ELFExecutionCheck` derives the startup rel32 target and selected entry
   slice from the certificate, executes the authenticated startup path, hands
   the reached state to `ProgramCheck`, and composes the uniform returned state
   with the authenticated return-to-syscall suffix. Runtime callers provide
   only mapped-image, initial-RIP, compiler-state correspondence, and one
   body-indexed image/stack-separation fact.  The bridge derives the ordinary
   text/stack condition and every direct-call layout obligation from that
   checker-owned layout.

The v3 checker accepts the current generated return-42 certificate and the
monomorphic type-alias regression. Cached certificate checking is around
hundredths of a second; full compact self-extraction checking is around one
second in the native checker. These timings are evidence about authentication
cost, not substitutes for soundness.

The actual Lanius compiler's `--certificate` path also passes that checker.
The focused two-function regression carries 34 canonical transport words, a
529-byte x86 ELF image, and two ordered function spans, so the connected path
is not relying on empty backend fields.  Both the one- and two-function
certificates also pass `ELFExecutionCheck`, authenticating the startup jump and
selected entry slice consumed by the public startup-to-exit theorem.  The
executable that generated those bytes is still the bootstrap build; acceptance
authenticates this output but does not yet prove universal generator
correctness.

Constants are checked against their declared type through `ExprChecks` rather
than inferred with the unannotated integer default. Literal elaboration's
bounds also supply Core value typing through one shared lemma. The direct
source checker authenticates i32, bool, string, usize, and null-pointer literal
initializers; computed initializers remain unsupported. Independent same-typed
value mutations are rejected. Generated constant typing and shared lookup
proofs now compose into `extractedVerifiedProgram` alongside supported function
proofs, without rerunning the whole-program checker.

A fresh nominal-structure/type-alias regression now passes source lowering,
x86 execution, v3 certificate generation, and the independent Lean checker.
This is connected evidence for that lowering path, not yet the general
emitter-correctness theorem.

The shared Lanius lowering API now returns only a semantic `ir::program::Program`.
Its program pipeline and function-catalog assembly have no transport-output
mode or buffer. The compiler's explicit certificate branch owns serialization;
the extractor does not import the Core wire writers. The representative direct
Lean output and the two-function certificate remain byte-identical across this
boundary change, and their existing checkers accept them. This is an ownership
cleanup, not a new semantic-preservation theorem or a relaxation of checking.

The Lanius extractor self-extracts its import closure directly to a
Lean `Core.Program` by default. Its `--lean-checked` mode additionally emits
typed frontend evidence: the independent checker authenticates the source,
lexer, grammar, and Surface tree. `Compiler.DirectCoreCheck` joins that
checked frontend to the directly emitted Lean program and entrypoint, then
checks the exact `ProgramLowering`. It accepts a two-source cross-unit call and rejects a
different program or entrypoint. No Core transport certificate is involved in
this direct extraction path. The shared native IR retains source identifier
spans and module paths, so actual public Lean declarations use names such as
`Extracted.«app::main».Types.Choice` and `Extracted.«app::main».Functions.main`
without reparsing source. Type and function namespaces remain distinct, and
Lean keywords and generated auxiliary names cannot collide with source names.
Constructor notation such as `.Some 7` resolves through owner-scoped typed
metadata; nested match expressions retain their grouping. Importers can use
these declarations and instances in ordinary Lean proofs.
Bodies use source-shaped typed notation that
erases to the same `Core.Stmt`. Every defined function in the current
self-extraction uses this notation, including bodies above the former
256-node cutoff. Each body is normalized once into an ordinary checked
definition, shared by execution and proof checking. Generated structural
typing proofs cover the supported proof shapes; the notation alone is not
a proof of source-to-Core correctness.
Local binding descriptions are also shared before normalization, so repeated
uses do not re-elaborate their types and `Code` instances. Explicit signature
variables enter the same lexical scope; computed signatures still use ordinary
typed elaboration. A fixed-input comparison reduced the fresh self-module check
from 67.01 to 61.72 seconds, with byte-identical Core data and unchanged proof
obligations. This does not yet meet the full-check performance target.
The body-definition helper also uses Lean's let-expanding closure operation
to avoid an extra meta-level dependency check. Kernel validation remains on,
and generic/captured-variable tests cover the closure boundary. The current
fixed self-module checks in 60.82 seconds with identical Core and compiled
artifact size; this is not a large performance gain. Disabling asynchronous
elaboration exceeded the 110-second experiment cap and is not used.
Native lowering now builds the global callable/variant name index once for
all units, while the allocation index retains every enum declaration in
source order. Name resolution still checks full spellings, module identity,
imports, privacy, and ambiguity. Rejecting wrong module prefixes before import
lookup reduced generation from 25.35 to 21.85 seconds on identical input;
indexing enum candidates later reduced it from 21.51 to 20.34 seconds on another
fixed input. Both changes preserved every emitted Lean byte. Sharing the name
index saved about 11 MB of peak memory but did not demonstrate a speedup.
The exact emitted program and entrypoint now also
yield `Execution.ExecutableWellFormed` through a reusable selection theorem,
rather than duplicating the entrypoint proof for direct emission. The same
two-source program evaluates to 7 in
Lean and exits with status 7 when the normal Lanius compiler emits x86 from
the shared IR; both modes reject the same invalid expression fixture. The
focused regression rebuilds both Lanius executables from current source by
default before testing them. This is a connected representative check, not a
universal compiler theorem. The source-to-Core checker covers the monomorphic
subset supported by `ProgramLoweringCheck`. It now accepts and relates enum
declarations with checked variant payloads, including an enum in a different
module from a scalar `main`; it does not yet accept the extractor's enum-heavy
function bodies. The x86 end-to-end checker retains a separate no-enum
restriction.
`CoreBoundary` now pairs each source enum with its Core declaration and checks
every ordered variant payload against the source; catalog IDs follow the
Lanius allocator's semantic ordering, so nested variant names do not shift
function IDs. This is proof-producing and rejects a mismatched payload in a
representative direct-Lean fixture. Context synthesis now populates enum
nominal instances and variant-constructor tables from the checked catalog
and Core rows. Enum payloads are checked in their owning module's context;
the two-module regression has same-named but different `Payload` structures
and confirms that the auxiliary enum resolves to its own structure while a
Core row referring to the main module's `Payload` is rejected. That fixture
also passes the direct source-to-Core checker, reusing the enum-shape proof
already produced at the Core boundary.
`ProgramLoweringCheck` still rejects many enum bodies: its body checker
supports only a limited expression fragment. The shared
named-type checker now grounds monomorphic enum types and aliases as well as
struct types; annotated locals use that checker for all supported Core types.
Bare monomorphic nullary variants are now related through resolved source
names and checked variant rows. A direct-Lean fixture with an annotated enum
local passes the complete source-to-Core check; changing its Core body to the
other valid variant is rejected at body agreement, not Core typing. Binary
checking grounds both inferred operand types and reuses the general Core
typing checker, so a direct-Lean fixture with enum equality and inequality
also passes the complete source-to-Core check and its normal x86 executable
exits with the expected status 0. A non-generic payload-bearing constructor
call is also source-to-Core checked; a same-type wrong payload is rejected,
and a program that constructs a payload value returns 0 in both
Lean and x86. The body checker now relates match arms with wildcard, boolean,
i32 literal, and non-generic enum patterns, including payload binders, to the same source
relation. Connected nullary and payload-match fixtures reject a same-type
changed arm and return 7 in both Lean and x86. Other pattern and expression
forms remain unsupported, so the enum-heavy extractor is
not yet source-to-Core checked. A general theorem
that the extractor emits a valid artifact for every supported input remains open.

The frontend proof path now also has a structured-input entrypoint:
`SyntaxCheck.checkTypedSourcePack`, `FrontendCheck.checkTyped`, and
`FrontendBoundary.checkTyped` accept a Lean `ArtifactPack` directly and reuse
the existing lexer, parse, Surface, source-pack, catalog, and import checks.
The focused regression accepts a real frontend pack and rejects a wrong schema
and a malformed token for both one- and two-source programs. The extractor's
`--lean-checked` mode now emits that structured pack and the Core program in
one Lean module; the checker validates the emitted frontend against source
bytes and rejects a different source. `DirectCoreCheck.checkTyped` now joins
that same generated module to the source through a common `CoreInput`. The
direct source-to-Core suite now uses this typed path exclusively; no integer
artifact is generated or read by those tests. The separate compact frontend
still uses the same declaration, typing, lowering, and entrypoint checkers for
the existing certificate-based backend proof. The checked two-source program evaluates to 7 in Lean
and its x86 executable exits 7. A wrong entrypoint and a different but
well-typed return body are rejected. With shared Lean infrastructure built,
the 12.4 KB two-source module's source-to-Core check takes about 1.2 seconds.
Ordinary extractor output is Core-only Lean; `--lean-checked` adds the typed
frontend for bootstrap validation. The separate compiler `--certificate` mode
remains live for the existing certificate-based backend proof. The typed frontend
adds about 67 MB to a self-extracted module because the grammar derivation has
roughly 1.05 million parse nodes. A per-unit scan found no repeated
production/nonterminal/span headers, so subtree interning is not an obvious
size reduction. The generated self-module did not finish checking within a
105-second diagnostic limit. This is a bootstrap validation mode, not the
fast per-program proof path. Completing the migration requires an extractor
correctness theorem that removes this repeated derivation from normal output.

`verified_compiler/tests/direct_self_typing_check.sh` reproduces direct Lean
emission for the current extractor closure, checks the generated
module, and runs the independent Core typing checker on `extractedProgram`.
This confirms that the self-emitted Core is well typed; it does not prove that
the source-to-Core lowering is correct for that full closure. On the current
bootstrap build, the latest September 27 fresh run took 107.98 seconds: 21 seconds
for self-emission, 82 seconds for module checking, and 0.885 seconds for
independent typing, plus setup. It contains 1,153 source-shaped defined functions,
nine runtime imports, and 1,127 emitted function-typing proofs. Constant references
no longer prevent a body proof. The remaining 26 defined bodies and runtime
imports still lack generated proofs. This does not meet the
seconds-scale full-check target. Profiling identifies elaboration and artifact
serialization as substantial costs alongside kernel checking; body lowering
still dominates generation. The representative enum let/match takes 0.02
seconds to generate and 0.75 seconds to check freshly, with shared infrastructure
built. See `../verified_compiler/VERIFICATION.md` for measurement conditions,
controlled comparisons, and rejected performance experiments.

## Remaining semantic gaps

The project is not yet a verified compiler. In particular:

The full `lake build Lanius` facade currently has two known failures. The
legacy `Lexer.Artifact` quotes `lexer.json`, whose embedded source predates the
current enum-based lexer, so its exact-source provenance theorem correctly
fails. `Compiler.ELFExecutionBridge` also needs literal-callee evidence for a
direct-call preservation constructor, while the current authenticated direct
mode can contain a body callee. Neither failure is bypassed by the direct
source-to-Core checker; its focused target and connected tests pass separately.

- `FunctionCheck` is still a small backend fragment.  Its recursive
  expression/statement path is now authoritative, but local reads and writes,
  calls inside general expressions, conditionals, loops, heap operations, and
  aggregate values still need to be added through a shared state relation.
  Adding one top-level checker case per whole program shape remains explicitly
  out of scope.
- The actual ELF startup CALL and rel32 JMP, constructor-independent entrypoint
  result, return instruction, and exit-register load are now one theorem. Its
  image/stack separation is indexed by the authenticated body shape and the
  structural checker exports recursive-expression allocation depth.  General
  locals, control flow, and deeper calls are not yet in that accepted shape.
- Multi-source lowering exists at the source/Core boundaries, but the current
  Lanius orchestration still needs one concrete multi-unit path through body
  lowering, transport, code generation, and certificate checking.
- The extractor and compiler are written in Lanius and both currently pass
  production x86 source checking in a few seconds, but their own successful
  executions have not yet been connected to general emission-correctness
  theorems.  The native extractor's Core phase is now consumed directly by the
  certificate/lowering checker, while generated deep artifacts used for
  function-level Lanius proofs remain untrusted inputs. Self-extraction is the
  required bootstrap regression, not by itself a universal proof.
- Runtime services, heap representation, calls, loops, control flow, and
  aggregate values need one shared Core/machine state relation. Without that
  relation, isolated instruction traces cannot compose into whole-program
  semantic preservation.

## Backend proof shape

The backend must be proved structurally, at the same granularity as the Core
syntax and the Lanius emitter:

```text
value representation + frame invariant
  -> expression lowering theorem (structural recursion)
  -> statement lowering theorem (structural recursion / CFG invariant)
  -> call and function-frame theorem
  -> all-functions/program theorem
  -> ELF startup and observable-result theorem
```

Each layer consumes exact decoded instruction chunks and proves their effect in
the existing x86 machine semantics. Literal, scalar-operation, frame-slot,
call, and control-flow lemmas are reusable leaves of this proof; they are not
parallel end-to-end proof systems.

The structural checker should consume the authenticated function span from
left to right. Its expression result carries the remaining bytes, represented
value, and updated frame state; its statement result additionally carries the
control-flow outcome. The public theorem quantifies over one dynamic frame and
image/stack-separation invariant derived from the checked frame size. A fixed
two-slot or forty-byte stack window is sufficient for the current scalar
regressions but is not the invariant for the general backend.

All accepted function cases should project to one public refinement contract:
the authenticated Core body executes to a return outcome, and the machine
executes to the matching ABI return state (result representation, return RIP,
restored stack, and framed memory effect). Constructor-specific trace details
stay private. This uniform result is what the ELF startup/exit theorem
consumes; the exit proof must not split again on every `FunctionCheck` case.

Certificate version 3 already authenticates Core transport and exact function
spans. Prefer recursively consuming those exact spans before extending the
certificate format. Add instruction/chunk annotations only if measurement
shows that reconstructing boundaries is materially expensive or makes the
proof interface substantially larger; any such annotations remain untrusted
and must be checked against both Core and bytes.

The certificate may carry instruction boundaries, frame layouts, relocation
targets, and control-flow annotations so that the checker does not rediscover
work already performed during compilation. Those annotations are untrusted
and cheaply checked. They should be emitted by the Lanius compiler/extractor
in the same traversal that emits code.

## Extractor proof shape

The direct extractor's correctness argument should follow its actual pipeline:

```text
source bytes
  -> lexer/parser and reconstructed Surface
  -> shared semantic typed IR
  -> source-shaped Lean declarations
  -> Lean Core interpretation
```

The remaining contracts must connect source lowering to the shared IR and
Lean emission to that IR's meaning, then compose the two. Core typing alone
does not establish either equality. The printer contract must cover every
supported body and declaration, including names, references, and scoping;
unsupported or malformed inputs must fail explicitly.

Each source function has one named declaration. A `mutual functions` block
supports forward and recursive calls through a temporary name-to-ID index
read from those declarations' headers; there are no separate reference
declarations. The printer resolves IDs through the shared function catalog;
it neither reparses source nor renumbers semantic functions. The connected
namespace test checks these names against exact source lowering and matching
Lean/x86 execution.

Normal Lean output now uses a proof-free representation. The Lanius frontend
checks source typing and the emitter prints ordinary Core syntax through
readable Surface notation. Expressions have only phantom source-type labels
for resolving names and literal representations. Their stored syntax has no
scope or signature index and no per-node typing proof. Calls accept ordinary
argument lists without comparing them to a callee's parameter types.

References carry resolved IDs, not authenticated lookups into a second
signature table. Each native nominal type carries one `lanius_type` annotation
with its kind and resolved IR ID. Its constructors supply field labels and
positions; separate record/enum metadata instances and copied field tables
are unnecessary. Constants are ordinary Core values.
Functions assemble directly into `extractedProgram : Core.Program`; there is
no generated `extractedVerifiedProgram` or automatic `ProgramWellTyped`
theorem. The shared intrinsic library is not imported by normal output.

The function notation constructs Core nodes directly, rather than expanding
into nested polymorphic builder calls for ordinary Lean elaboration. Labels
exist only while resolving source names. A public function retains its name
and one Core declaration; linking projects those declarations without a
second conversion pass over their bodies. Native runtime declarations use the
same Core function representation.

Closed `mutual functions` declarations use Lean's nonrecursive admission API
after their bodies have become data with no free variables or metavariables.
Temporary header locals preserve forward-name resolution; the emitted call IDs
do not create Lean recursion. The kernel, compiler, documentation, and source
information remain active. Generic, attributed, module-system, or genuinely
dependent definitions continue through Lean's general definition machinery.
This is shared elaborator work, not generated proof evidence or deferred checking.

Defined-function parameters now bind source names directly to resolved IDs,
for example `arguments := [value := 72]`. The notation reads labels from the
existing function signature and builds the Core parameter list directly. It
does not elaborate a dependent `Vars` value or require generated Lean `Var`
bindings around the body. Captured IDs and computed/generic signatures remain
supported. Runtime imports still use the small `Function.external` helper.

This implements the representation part of the decision in
[the compiler notes](../verified_compiler/NOTES.md). It does not complete the
general typechecker or extractor proof and adds no new axioms. Until those
proofs and the execution/import boundary are connected, trust in the current
extractor is provisional. Proofs about the emitted program alone are distinct
from proofs that the source program has the same behavior.

The direct-parameter checkpoint contained 996 functions and 673 constants from
80 source units. On September 28, that checkpoint emitted in
9.77 seconds and checked/wrote one fresh Lean module in 18.29 seconds.
The previous builder representation took 35.58 seconds; the earlier intrinsic
representation took 87.27 seconds. Shared infrastructure was built beforehand;
no cached program declarations or split checks were used. This remains slower
than the seconds-scale goal.

That checkpoint's profile records 6.06 seconds of elaboration, 1.47 seconds of typeclass
inference, 2.23 seconds of interpretation, 926 ms of kernel checking,
about 6.1 seconds of Lean compilation, and 3.61 seconds of artifact writing.
These overlapping categories are not additive wall-clock phases. The optional
self-typing regression audit passed in 432 ms. The full diagnostic script,
including source-closure setup, took 33.87 seconds. Shared constant resolution
now filters unrelated module owners before name checks and only searches
imports when no local value matches. On an identical frozen input, generation
fell from 17.24 to 11.70 seconds and emitted byte-identical Lean.

The parser now caches grammar actions and uses a collision-checked state index,
while retaining its insertion-ordered chart queue and first derivation. Its
separate fixed-input comparison measured 11.62 versus 10.53 seconds and emitted
byte-identical Lean. The shared workspace grows from 64 to 96 MiB to preserve
state capacity. Exhaustive short-token and ambiguity/capacity regressions pass;
this does not establish a correctness theorem for the revised implementation.

Direct parameter binders removed 2,524 lines of generated scaffolding on the
fixed input and checked in 17.89 seconds, versus the preceding 19.92-second
check. The complete evaluated Core snapshot remained byte-identical, including
all 997 functions and 673 constants. Current self-extraction has one fewer
function because the old parameter-printing helper was deleted.

Constant lookup now uses the module declaration spans that shared lowering
already checked, avoiding unrelated allocation rows without adding an index.
The fixed-input comparison improved generation from 11.58 to 9.38 seconds with
byte-identical output. That checkpoint's full fresh run measured 9.76 seconds for
emission, 23.21 seconds for Lean checking/artifact writing, and 39.97 seconds
overall, including setup and the separate 468 ms typing audit. The unchanged
previous program also checked more slowly in this session: a paired comparison
measured 24.71 seconds before and 24.22 after. No Lean admission improvement is
claimed for this native lookup change. See the compiler notes for the discarded
Lean experiments and the subsequent native-executable checkpoint.

Native declarations now own constructor and field metadata. The notation reads
their names, payload labels, and ordinals from Lean's declaration information;
record constructor binders use the source field names. The obsolete per-member
instances and APIs were removed, without adding a compatibility table or
reconstructing Lanius typing. A fixed-input comparison preserves the complete
Core program and removes 1,395 instances and 3,301 generated lines. Fresh Lean
admission takes 19.33 seconds versus 22.34 before this change.

That checkpoint's self-module contains 992 functions and 673 constants; four obsolete
printer functions were deleted. Fresh generation takes 7.75 seconds, Lean
checking/artifact writing 19.21 seconds, and the full diagnostic script 33.50
seconds. The optional typing audit takes 341 ms. The few-second target remains
open. These current-source measurements are separate from the fixed-input
comparison; they do not establish a native generation speedup.

The linking step removes the separate emitted Core nominal-type tables. A small
`link` notation reads the same native declarations used by body name resolution
and constructs their Core declarations once. Explicit type lists preserve all
IDs, field/variant order, and unused declarations. Shared label-reading code
lives in `Surface/Labels.lean`; the old Lanius type-table printers were removed.
The actual emitted program preserves the complete fixed-input Core snapshot.
This is a representation cleanup, not a general correctness proof or a clear
performance improvement. Current-source self-extraction covers 989 functions
and 673 constants: 8.47 seconds to emit, 19.25 seconds to check/write, and 34.27
seconds for the full diagnostic script. The few-second target remains open.

The subsequent native parser change indexes completion and nullable-replay
searches while retaining chart insertion order and exact action comparisons.
Fixed-input generation uses 15.2% fewer user instructions and takes 7.77 versus
6.70 seconds, with byte-identical Lean. The fresh 990-function, 674-constant
self-module emits in 7.51 seconds and checks/writes in 14.37 seconds; the
complete diagnostic takes 27.42 seconds.
No Lean compilation change was retained, so this is not a controlled Lean-side
speedup. The parser uses 120 MiB of scratch instead of 96 MiB to preserve its
prior state capacity. Focused parser and connected Lean/x86 checks pass, but
they do not establish general correctness of the optimized implementation.

A fixed-program comparison preserved the complete evaluated Core data
byte-for-byte. The current generated program definition has no axiom
dependencies. This describes the data definition and regression evidence,
not a general correctness proof of the extractor or compiler.

`verified_compiler/tests/direct_emission_check.sh` checks expected execution
in Lean and x86 for fourteen fixtures, including `Some(7)`. Twelve fixtures also
pass the independent exact-source checker. Two raw-slice/memory fixtures are
outside that checker's supported fragment; their coverage is execution and
structural checking. Same-typed field/initializer substitutions and seven
constant mutations remain rejected by the independent source checker.

Typing rejection tests now run at the Lanius boundary: wrong call arguments,
arity, return types, unknown locals, and wrong enum payloads fail in both
extraction modes and the x86 compiler. Lean Surface tests check representation,
binding identity, and execution, not a second implementation of source typing.

The migration exposed missing definite-return validation in Lanius: non-unit
functions could reach the end, and the old Lean representation was catching
that later. Shared IR validation now rejects missing returns, one-sided returns,
and loop-only returns. Unit fallthrough and valid branch/loop continuations
remain accepted. The fixture gate covers ten malformed-source cases in both
extraction modes and x86. The separate runtime-import gate also passed, including
six same-signature service substitutions under forged policies.

The existing source checker independently authenticates lexer and grammar
evidence and reconstructed Surface. Small `--lean-checked` examples use that
checker to establish exact source-to-Core agreement. Emitting a full parser
derivation for every normal extraction is not the intended fast path, and
integer transport is not part of direct Lean emission. The separate legacy
backend certificate still has its own format contracts; it must not dictate
the extractor's representation.

## Size and performance gates

The current tree has roughly 46,000 production Lean lines plus 2,700 focused
test lines for roughly 14,000 Lanius lines under `verified_compiler/src`--about
3.3 production proof lines per implementation line. This is within the broad
five-times-source target, but only if the remaining proof reuses the current
infrastructure. Moving repeated program traces into a "shared" file does not
make them reusable.

For every connected increment:

- the public theorem states a semantic phase contract, not evaluator
  bookkeeping;
- program-specific proof code stays near five times the relevant source and
  should normally be much smaller;
- a focused changed-module check should take seconds;
- cached whole-facade checking should take seconds;
- no individual development command runs for more than two minutes; use a
  shorter timeout to leave room for cleanup;
- normal per-program certificate generation and checking must not replay the
  compiler or kernel-reduce a large extracted execution.

## Unit of proof coverage

Every function reachable on the trusted compiler/extractor path needs
transitive semantic coverage, but it does not need its own public theorem.
Pure selectors and short encoders should reduce through shared rules; related
helpers should be covered by one parameterized phase invariant; orchestration
functions should compose the phase theorems.  Named, function-specific proofs
are reserved for real semantic boundaries or algorithms with distinct
invariants.  This distinction is essential to cover the implementation without
returning to hundreds of repetitive program traces.

## Acceptance rules

- Prove the actual reconstructed Core and exact emitted ELF bytes, never a
  look-alike example.
- A proof module is not progress until its evidence is consumed by the
  authoritative certificate checker or is clearly reusable infrastructure on
  that path.
- Do not accept a callee postcondition, machine result, successful execution,
  relocation target, or memory fact as an unexplained premise when it is the
  property being proved.
- Group unavoidable representation and separation facts behind one reusable
  state/layout invariant; do not expose lists of instruction-local premises in
  public theorems.
- Reject unsupported source or machine forms explicitly. Never obtain a
  shorter proof by silently broadening the theorem beyond what the checker
  authenticates.
- Use no `sorry`, `admit`, custom axioms, `native_decide`, or `unsafe` proof
  shortcuts.
- Keep the compiler and extractor implementation in Lanius and the native
  target x86-64. Bootstrap tooling may compile Lanius, but it is not a second
  implementation of the compiler.

## Next gates

The certificate-checker work above describes available bootstrap validation,
not a requirement to regenerate typing evidence for every normal extraction.
The earlier next-step list predated the trusted-tool decision. The remaining
contracts now follow the actual implementation:

1. Connect the Lanius frontend and lowering implementation to source semantics
   and shared-IR typing. Keep malformed/unsupported input rejection explicit.
2. Prove that the Lanius printer and Lean notation preserve that IR's meaning,
   including names, declaration identities, field order, and binding scope.
   An emitted program being well typed does not discharge this contract.
3. Connect the Lanius x86 emitter to the machine semantics for its supported
   fragment, including the runtime services used by the extractor. Compose
   this with source lowering; executable comparisons alone are insufficient.
4. Establish the checked self-embedding and native bootstrap connection for
   those actual implementations, not just abstract algorithms or validators.
5. Specify the trusted execution/import mechanism that ties a tool invocation
   to its exact input and output. State the assumptions explicitly; do not add
   silent axioms or put per-program typing reconstruction back into admission.

Fresh per-program emission and Lean admission must also meet the seconds-scale
performance target with shared infrastructure already built. These obligations
remain open; the working direct pipeline and passing fixtures are progress,
not completion of the general compiler/extractor proof.
