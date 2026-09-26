# Verified compiler proof architecture

Status: active, incomplete. This file describes the current proof boundary,
not the history of the proof reset.

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

A fresh nominal-structure/type-alias regression now passes source lowering,
x86 execution, v3 certificate generation, and the independent Lean checker.
This is connected evidence for that lowering path, not yet the general
emitter-correctness theorem.

The Lanius extractor self-extracts its 88-unit import closure directly to a
Lean `Core.Program` by default. Its `--lean-checked` mode additionally emits
typed frontend evidence: the independent checker authenticates the source,
lexer, grammar, and Surface tree. `Compiler.DirectCoreCheck` joins that
checked frontend to the directly emitted Lean program and entrypoint, then
checks the exact `ProgramLowering`. It accepts a two-source cross-unit call and rejects a
different program or entrypoint. No Core transport certificate is involved in
this direct extraction path. The shared native IR now retains source identifier
spans for types, enum variants, and functions, so Lean declarations can carry
names such as `extractedEnumeration0_Choice` and `extractedFunction0_main`
without reparsing source. These names are metadata: the body is still a
numeric `Core.Stmt`, not the desired source-like, type-indexed Lean IR.
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
emission for the current 88-source extractor closure, checks the generated
module, and runs the independent Core typing checker on `extractedProgram`.
This confirms that the self-emitted Core is well typed; it does not prove that
the source-to-Core lowering is correct for that full closure. On the current
bootstrap build, self-emission took 27 seconds and generated-module checking
21 seconds after source-name retention. Earlier instrumented stage timings
placed roughly 17 seconds
of emission in shared function-body lowering, with first-pass expression type
inference the largest measured substage; the Lean text writer is not the
dominant cost. These timings are diagnostics, not a performance guarantee.

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

Extractor correctness should be factored into format and phase contracts:

```text
source bytes
  -> canonical token evidence
  -> grammar derivation evidence
  -> reconstructed Surface evidence
  -> packed compact bytes
```

The existing checker already proves that accepted evidence denotes the exact
source and reconstructed Surface tree. The remaining generator theorem is
therefore a compositional claim that each Lanius extraction phase emits the
evidence accepted by the corresponding checker. It must reuse the checked
phase formats rather than re-proving the parser through a second semantics.

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
- no individual development command runs for more than 110 seconds;
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

In order:

1. extend the shared structural expression/statement validator with the
   local/call/control-flow state relation used by real compiler functions;
2. pass a real two-unit cross-call certificate through the same end-to-end
   checker;
3. prove the Lanius certificate emitter phases generate evidence accepted by
   the existing v3 decoder and boundaries;
4. make the native Lanius extractor carry the typed Core evidence consumed by
   the checker, eliminating the bootstrap exporter's role in new artifacts;
5. scale the structural validator across the source constructs actually used
   by the compiler and extractor, rejecting unsupported constructs explicitly;
6. self-extract and compile the extractor with the verified x86 path, then
   retain the independently checked self-embedding as the bootstrap anchor.

Completion means the last successful compiler/extractor output is covered by
this one proof spine. It does not mean that several disconnected examples all
have true theorems.
