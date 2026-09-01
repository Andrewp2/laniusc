# Proof architecture for verified compiler code

Status: scanner pilot implemented; kernel-clean checker reduction remains an
engineering follow-up  
Scope: compiler code written in Lanius  
First pilot: `verified::lexer::scan_identifier_end`

Implementation checkpoint (August 31, 2026): the scanner pilot is implemented
end to end. The repository contains the checked-program facade,
signature-indexed values and arguments, exact reification, relational function
contracts, relational primitive-call semantics, structural term/command WP,
successful-Core inversion, and an invariant-aware Core-reflection boundary.
The public identifier and whitespace theorems invert actual successful calls
to functions recovered from the completely checked frontend pack.

`Relational.CoreSuccess` derives a structural successful-execution tree from a
fuelled Core result. `Relational.CoreReflection` reflects that tree through
sequence, scoped locals, assignment, branches, loops, returns, source
representation, and fresh-cell framing. The bridge assumes neither termination
nor determinism. `RelationalSuccessfulCoreRefinement.structuralWhen` transports
the resulting conditional reflection through exact command reification.

The predicate leaves are also structural. The identifier-start, decimal-digit,
identifier-continue, and whitespace contracts are proved directly for their
checked Core terms; identifier-continue includes the actual short-circuit `||`
shape. The public scanner path no longer imports `Lexer.Calls` or uses the
legacy `ReturnsCorrectly.ofFramePreservingModel` adapter. The one retained
`IdentifierEndBootstrap` module is an isolated migration comparison and is not
reachable from either public theorem.

`SemanticWP.Command` now has rules for every command constructor: skip,
sequence, lexical let, local set/update, action, conditional, invariant-based
while, both returns, break, and continue. The generic scanner WP consumes typed
`SpecEntry` contracts and a cursor invariant; the identifier and whitespace
proofs instantiate it without a `CallModel`, whole-loop trace, termination
argument, or physical-frame reasoning.

Optional availability properties are separate in
`Relational.CorrectnessProperties`: `DoesNotTrap`, `Terminates`, and the
three-field `TotalCorrect` bundle do not appear as premises of
`ReturnsCorrectly`. `Lanius.Automation.VCGen` is the stable automation facade,
with source-indexed loop annotations, four bounded simp sets, and diagnostics
for missing specifications, representation facts, and invariants. Generated
lexer handles and loop annotations carry concrete Lanius line/column spans.

Measured checkpoint on the same date:

- a warm focused build of both public scanners completed in 0.13 s with
  131,920 KiB maximum RSS;
- a focused build from an empty Lake cache completed all 115 required jobs in
  3 min 43.71 s with 5,520,924 KiB maximum RSS;
- renaming one harmless local binder in the identifier proof rebuilt only the
  identifier direct proof and public wrapper, not the whitespace proof; that
  rebuild completed in 1.73 s with 1,786,036 KiB maximum RSS;
- generic relational and VCGen infrastructure is 4,698 lines; shared lexer
  relational infrastructure is 2,348 lines; identifier-specific files are 497
  lines and whitespace-specific files are 298 lines;
- source audits find none of the forbidden abstraction vocabulary in either
  `*Direct.lean` file, no authored proof escape in the new slice, no
  `native_decide` in relational/VCGen/scanner proof modules, and no public-path
  import of the retained bootstrap adapter;
- the fast assurance gate records both public axiom sets and allowlists only
  the isolated complete checked-pack native certificate;
- the kernel-clean certificate is split into evidence, semantics, and global
  resolution phases. `decide +kernel` was rejected for this full artifact after
  reaching 27 GiB RSS plus 17 GiB swap; the proof-producing `cbv` build stays
  near 1.7 GiB for evidence while semantics grows to roughly 10 GiB. A bounded
  10 min 27 s run produced no proof failure but did not finish, so this gate is
  implemented but not yet practical CI.

The scanner implementation passes the semantic, abstraction, reuse, and fast
trust criteria below. The kernel-clean trust criterion remains open as an
explicitly measured checker-performance issue rather than being hidden behind
another trusted shortcut.

All Lean declarations below are interface sketches. The pilot must refine their
universe, representation, and indexing parameters against the existing APIs;
an illustrative name in this document is not a second source of truth.

## Decision

Keep Core as the authoritative executable semantics and keep exact artifact
checking and exact FunctionalView reification. Add a relational specification
and weakest-precondition layer over the existing
`FunctionalView.Stateful.Command` syntax.

The public correctness contract for an ordinary compiler function will be
partial correctness:

```text
if the checked Core function returns successfully from a represented state,
then its result and final state satisfy the function's specification.
```

Termination, absence of traps, and constructive execution will be separate,
stronger contracts. They must not be prerequisites for using a function's
partial-correctness specification in a caller proof.

This design has one immediate goal: compiler proofs should state algorithmic
preconditions, postconditions, data-representation predicates, and loop
invariants. They should not reconstruct Core executions or manage physical
locals.

## Why this change is needed

The checked frontend proves real execution of all 74 verified lexer and parser
functions. That result is valuable, but the proof interface is too low-level
for the rest of the compiler.

Today, a successful abstract call is normally turned into an existential Core
execution through `Effectful.CallSoundness` or
`FreshSimulation.FramePreservingCallSoundness`. Composing calls requires
routing by numeric `FunctionId`. Loop proofs commonly construct finite
evaluation traces and then transport them through local-cell allocation,
callee entry, restoration, and separation-logic framing.

Those mechanisms belong in the trusted semantic bridge. They should not be the
normal vocabulary of lexer, parser, lowering, optimizer, or backend proofs.

The current `FunctionalView` work is not discarded. In particular, the design
keeps:

- `Core.Program`, Core typing, and Core execution as authoritative;
- complete checked artifact packages;
- exact recovery of a proof-facing command from the checked Core body;
- `FunctionalView.Stateful.Command` and its scoped functional environment;
- existing Core simulation, separation, call-frame, and loop lemmas as
  implementation material for the generic bridge;
- existing concrete execution theorems as regression oracles during the
  migration.

## Goals

The new interface must provide:

1. A checked-program facade with typed function references and typed argument
   encoding.
2. Relational function specifications over abstract inputs, outputs, and
   state.
3. A structural weakest-precondition calculation for existing FunctionalView
   terms and commands.
4. A relational call rule that consumes a callee specification rather than
   constructing the callee's execution.
5. One generic soundness theorem connecting the WP result for an exactly
   reified command to successful Core execution.
6. Separate optional contracts for no-trap safety and termination.
7. Diagnostics that identify a missing function specification, representation
   fact, or loop invariant at the corresponding Lanius source construct.

## Non-goals

This proposal does not:

- replace Core semantics;
- rewrite all existing FunctionalView syntax;
- migrate the lexer or parser before the pilot passes;
- reorganize the formal module tree before the API stabilizes;
- prove termination of every compiler function in the first phase;
- introduce the backend IR;
- claim that a build-time artifact certificate validates parse results for
  arbitrary future compiler inputs;
- require immediate removal of every existing `native_decide` use.

## Correctness properties

The proof API should name three independent properties.

### Returns correctly

`ReturnsCorrectly` is the default compiler-soundness contract. It quantifies
over an actual successful Core call:

```lean
-- Schematic: names and representation parameters will be refined by the pilot.
def ReturnsCorrectly
    (program : CheckedProgram)
    (function : program.FnRef signature)
    (contract : FnContract program function) : Prop :=
  forall args values abstractBefore concreteBefore value concreteAfter,
    contract.Pre args abstractBefore ->
    contract.ArgsRep args values ->
    Represents abstractBefore concreteBefore ->
    CoreCallEvaluates program.core function values concreteBefore
      value concreteAfter ->
    exists abstractAfter result,
      contract.ResultRep result value /\
      Represents abstractAfter concreteAfter /\
      contract.Post args result abstractBefore abstractAfter /\
      contract.Frame abstractBefore abstractAfter
```

This property prevents a successful compiler execution from silently
producing a wrong result. It does not claim that execution succeeds.

### Does not trap

`DoesNotTrap` states that a represented input satisfying the precondition
cannot reach a Core trap. It is useful for compiler availability and for
proving that internal assumptions are not violated, but callers do not need it
merely to use the postcondition of a successful call.

### Terminates

`Terminates` constructs a successful or explicitly rejected result for every
represented input satisfying the precondition. A total-correctness theorem can
combine all three properties:

```text
TotalCorrect = ReturnsCorrectly + DoesNotTrap + Terminates
```

Existing constructive call-soundness and loop-trace theorems can discharge
`Terminates`; they need not remain the default composition interface.

## Checked-program facade

The repository already has the evidence needed for this package:

- `CompleteChecker.CheckedArtifact` joins the complete source and Core checks;
- `ArtifactPackContextChecker.CheckedArtifactPackSemantics` checks a pack;
- `ArtifactContextChecker.FunctionHeaders` contains typed schemes and concrete
  function instances;
- `FunctionsChecked` connects Surface functions to Core functions.

Do not create a parallel checker. Define a small opaque facade over
`CompleteChecker.CheckedPack` and its existing projections.

```lean
structure CheckedProgram where
  pack : ArtifactPack
  checked : CompleteChecker.CheckedPack pack
  core : Core.Program
  coreFound :
    ArtifactPackChecker.mergeCorePrograms? pack.units = some core

structure FnSignature where
  arguments : List Core.Ty
  result : Core.Ty

structure CheckedProgram.FnRef
    (program : CheckedProgram) (signature : FnSignature) where
  function : Core.Function
  found : program.core.function? function.id = some function
  parameterTypes : function.parameters.map Prod.snd = signature.arguments
  resultType : function.returnType = signature.result
  sourceIdentity : SourceFunctionIdentity
```

The facade should generate references from the checked function-instance
table. A proof author names `LexerFn.scanIdentifierEnd`; numeric IDs remain an
internal projection used only by Core and the generated registry.

Arguments receive a signature-indexed representation:

```lean
-- Schematic.
def DenoteArgs : List Core.Ty -> Type
def encodeArgs : DenoteArgs types -> List Core.Value

theorem decode_encode_args (args : DenoteArgs types) :
    decodeArgs types (encodeArgs args) = some args
```

The pilot may initially wrap existing argument encoders. It must not add a
second handwritten account of function IDs or signatures. A typed function
reference must also carry proof that the body is present; the pilot must not
recover a missing body with a fallback such as `getD .skip`.

## Function contracts and registry

A function contract describes abstract behavior. It does not contain a Core
execution proof and does not expose physical memory cells.

```lean
-- Schematic.
structure FnContract
    (program : CheckedProgram)
    (function : program.FnRef signature) where
  Args : Type
  Result : Type
  AbstractState : Type
  Pre : Args -> AbstractState -> Prop
  Post : Args -> Result -> AbstractState -> AbstractState -> Prop
  ArgsRep : Args -> List Core.Value -> Prop
  ResultRep : Result -> Core.Value -> Prop
  Frame : AbstractState -> AbstractState -> Prop
```

`ReturnsCorrectly program function contract` is proved separately. This keeps
the specification usable without making the specification structure recursive
through its own proof.

A registry contains typed references, contracts, and their proved
`ReturnsCorrectly` theorems. Registration must be source-identity based and
must fail on duplicate or missing functions. The generated registry may use
numeric IDs internally, but `FunctionId` must not occur in an algorithm proof.

```lean
-- Schematic.
structure SpecRegistry (program : CheckedProgram) where
  contract : (function : program.AnyFnRef) ->
    FnContract program function.ref
  sound : (function : program.AnyFnRef) ->
    ReturnsCorrectly program function.ref (contract function)
```

The first implementation does not need heterogeneous global inference. A
generated lookup table plus typed projections is sufficient.

## Weakest-precondition layer

Reuse `FunctionalView.Term` and `FunctionalView.Stateful.Command`. Add a
relational operation specification and a structural WP. Do not change the
existing executable machines during the pilot.

For a command with `arity` scoped locals, use:

```lean
-- Schematic.
abbrev Assertion (World : Type) (arity : Nat) :=
  World -> FunctionalView.Env arity -> Prop

abbrev Postcondition (World : Type) (arity : Nat) :=
  Stateful.Completion -> World -> FunctionalView.Env arity -> Prop

def Command.WP
    (operations : OperationRegistry program registry)
    (command : Stateful.Command signature actions arity)
    (annotations : AnnotationRegistry program command)
    (post : Postcondition World arity) : Assertion World arity
```

`AnnotationRegistry` supplies invariants and source identities for recursive
control constructs. It is generated from the checked artifact plus explicit
proof annotations; the command syntax itself does not need to be rewritten to
store tactic metadata.

The defining equations should follow command structure:

```text
skip:
    post next world environment

sequence first second:
    WP first (fun completion world environment =>
      if completion = next then WP second post world environment
      else post completion world environment)

let value := initializer; body:
    TermWP initializer (fun value world =>
      WP body
        (fun completion world extended =>
          post completion world (Env.pop extended))
        world (Env.push environment value))

set/update local:
    evaluate the term and require the continuation on Env.set

action:
    use the registered relational action specification

if:
    evaluate the condition; require the selected branch

while:
    require a registered invariant; one condition/body step must preserve it;
    condition false establishes the continuation; break exits; return escapes

return/break/continue:
    apply the postcondition to the corresponding Completion
```

`TermWP` must preserve left-to-right argument evaluation and short-circuiting.
For ordinary operations it uses generic Core operation specifications. For a
call it uses the call rule below.

The initial WP is a partial-correctness WP: it constrains every successful
result represented by the semantics. Trap freedom and termination use separate
judgments. The API must not make a failed or diverging execution prove an
arbitrary successful result.

## Relational call rule

The call rule consumes a proved callee contract. It does not evaluate an
abstract `CallModel` and does not construct a callee trace.

For a call to `f` with abstract arguments `args`, initial abstract state
`before`, and continuation `Q`, the rule is:

```text
1. prove f.Pre args before;
2. for every result and final abstract state allowed by f.Post,
   prove Q result finalState;
3. retain every caller resource included in the registered frame.
```

Schematically:

```lean
def callWP
    (entry : registry.Entry function)
    (args : entry.contract.Args)
    (before : entry.contract.AbstractState)
    (post : entry.contract.Result ->
      entry.contract.AbstractState -> Prop) : Prop :=
  entry.contract.Pre args before /\
  forall result after,
    entry.contract.Post args result before after ->
    entry.contract.Frame before after ->
    post result after
```

The generic Core soundness proof inverts the actual Core call execution,
applies `entry.sound`, and feeds the resulting abstract postcondition to the
continuation. No function-ID disequality proof appears at the call site.

Calls without a registered contract must produce one explicit unresolved VC:

```text
missing Lanius specification for verified::lexer::is_identifier_continue
at verified_compiler/src/verified/lexer.lani:<source span>
```

## Generic Core soundness theorem

Exact reification and semantic adequacy remain separate obligations:

```text
exact reification:
    toCoreStmt command = checkedFunction.body

WP soundness:
    WP command post + successful execution of toCoreStmt command
    implies post
```

The target theorem is:

```lean
-- Schematic.
theorem wp_toCore_sound
    (program : CheckedProgram)
    (registry : SpecRegistry program)
    (command : Stateful.Command signature actions arity)
    (hwp : Command.WP registry command post abstractWorld environment)
    (represented : Represents layout abstractWorld environment concreteBefore)
    (executes : Core.Executes program.core concreteBefore
      (Stateful.toCoreStmt actionAdapter layout nextLocal command)
      coreCompletion concreteAfter) :
    exists abstractAfter environmentAfter completion,
      CompletionRep completion coreCompletion /\
      Represents layout abstractAfter environmentAfter concreteAfter /\
      post completion abstractAfter environmentAfter
```

It may be proved directly by structural inversion of the Core execution, or by
introducing a small relational FunctionalView semantics and proving two
lemmas. The pilot should choose the smaller proof. It must not duplicate the
command syntax or replace the existing executable semantics merely to match a
paper architecture.

The call case uses `ReturnsCorrectly` from the registry. The local and action
cases use the existing representation and separation lemmas. All physical-cell
allocation, callee entry, local restoration, and write framing stay inside
this theorem and its generic helpers.

The final function theorem rewrites by exact reification:

```lean
theorem function_returns_correctly ... := by
  intro ... actualCallExecution
  obtain bodyExecution := invert_checked_call actualCallExecution
  rw [functionView_toCore_exactly] at bodyExecution
  exact wp_toCore_sound ... bodyExecution
```

This is the only algorithm-facing use of the Core bridge.

## Loop rules

The partial-correctness loop rule requires an invariant, not a decreasing
measure. For a loop `while condition { body }`, the VCs are:

1. The precondition establishes the invariant.
2. When the invariant holds and the condition is true, normal or `continue`
   completion of the body re-establishes the invariant.
3. When the condition is false, the invariant establishes the loop
   continuation.
4. A `break` completion establishes the loop continuation.
5. A returned completion establishes the enclosing function postcondition.
6. All condition and body operations meet their registered preconditions.

A separate termination rule adds a well-founded variant. Existing
`FunctionalView.Stateful.Loop` and `LoopVerification` drivers remain available
to prove that stronger property.

## Abstract state and framing

Contracts describe logical state. Physical cells and slice encodings live in
representation predicates.

For the lexer pilot, the logical state is read-only source data. For the parser
pilot it will eventually include mathematical grammar, token lattice, chart,
and error position objects.

The frame interface should begin with the region classes already supported by
the current proofs:

```text
immutable source region
immutable grammar region
writable workspace region
writable output region
untouched caller frame
```

Do not introduce a general concurrent separation logic. The initial region
algebra should express only ownership and preservation properties required by
single-threaded compiler semantics. More expressive framing must be justified
by a concrete pilot obligation.

## Pilot: `scan_identifier_end`

### Checked source

The source function initializes `end = start + 1`, advances `end` while it is
in bounds and the next byte satisfies `is_identifier_continue`, then returns
the exclusive end offset.

The pilot must use:

- `Scanners.scanIdentifierEndView`, recovered from the checked artifact;
- `Scanners.scanIdentifierEndView_toCore_exactly`;
- the checked typed reference for `scan_identifier_end`;
- a registered relational specification for `is_identifier_continue`;
- `Lanius.Compiler.Lexer.IdentifierEndSpec` as the algorithmic result.

It must not use the existing concrete execution theorem as a proof premise.
That theorem remains a regression oracle.

### Contract

The abstract arguments are `source : List Byte` and `start : Nat`. The encoded
Core call also carries `source_length`; its representation requires that value
to equal `source.length`.

Precondition:

```text
source.length <= 2^31 - 1
start < source.length
the concrete source slice represents exactly source
the encoded start and source length are signed i32 values
```

The function itself does not need to assume that `source[start]` begins an
identifier. Its operational behavior is defined for every in-bounds `start`;
the caller's classification establishes the stronger lexical fact.

Postcondition for returned `finish`:

```text
IdentifierEndSpec source start finish
start < finish
finish <= source.length
the returned Core value encodes finish as signed i32
the abstract source is unchanged
all caller-visible regions are unchanged
```

`IdentifierEndSpec.functional` then identifies the result with
`scanIdentifierEnd source start` when an exact functional value is wanted.

### Loop invariant

At loop head with cursor `end`:

```text
start + 1 <= end
end <= source.length
end <= 2^31 - 1
every byte in the half-open range source[start + 1 .. end) satisfies
  is_identifier_continue
the source region is unchanged
the local environment represents source, source.length, start, and end
```

The in-bounds and accepted branch proves `end + 1` is representable as i32 and
preserves the invariant. At exit, either `end = source.length` or the byte at
`end` is the first rejected byte. Together with the accepted prefix, this
establishes `IdentifierEndSpec` and maximality.

### Callee specification

The registered `is_identifier_continue` contract states:

```text
Pre:
    the argument is an i32 encoding of one Byte

Post:
    the returned boolean equals Compiler.Lexer.isIdentifierContinue byte
    the abstract and concrete caller-visible worlds are unchanged
```

The scanner proof refers to the typed function handle and this contract. It
does not mention the callee's numeric ID, body, call frame, or execution fuel.

### Required theorem

The pilot is complete when it proves a premise-free theorem equivalent to:

```lean
theorem scanIdentifierEnd_returnsCorrectly :
  ReturnsCorrectly checkedFrontend LexerFn.scanIdentifierEnd
    scanIdentifierEndContract
```

The theorem must quantify over every represented caller state allowed by the
contract, not only the canonical singleton source state used by some existing
execution examples.

## Pilot acceptance criteria

The pilot passes only if all of the following hold.

### Semantic criteria

- The function reference and body come from the completely checked frontend
  artifact.
- Exact reification connects the proof command to that checked body.
- Every successful checked Core call establishes `IdentifierEndSpec`.
- The proof covers arbitrary valid source bytes and every in-bounds start.
- The proof preserves arbitrary caller-owned frame regions.
- The only function-specific logical inputs are the contract, loop invariant,
  and ordinary list/arithmetic facts.
- The existing constructive execution theorem is not imported by the pilot
  proof.

### Abstraction criteria

The algorithm-specific proof file contains no reference to:

```text
CellId
State.local?
enterCall
restoreLocals
bindParameters
ModifiesOnly
CallModel.route
numeric FunctionId literals or disequality proofs
evaluator fuel
Command.Evaluates constructors
Core Executes/Evaluates constructors
```

These names may occur only in the checked-program facade, WP soundness,
reification, representation, or other generic infrastructure.

### Reuse criteria

Without changing the WP, call, frame, or adequacy implementations, apply the
same scanner rule to `scan_whitespace_end`. That second proof should require
only:

- the whitespace predicate contract;
- the whitespace result specification;
- the exact checked function handle and reification theorem.

If the second scanner needs a new evaluator or frame lemma, the abstraction is
still too low.

### Trust criteria

- The pilot introduces no `sorry`, `admit`, authored `axiom`, `unsafe`, or
  `implemented_by` declaration.
- `native_decide` may occur only in an isolated artifact or reification
  certificate module.
- `#print axioms scanIdentifierEnd_returnsCorrectly` is recorded in CI.
- The repository maintains two explicit assurance profiles:
  - a fast profile with an allowlist for isolated `native_decide` certificates;
  - a kernel-clean profile that replaces them with `decide_cbv` or checked
    proof-producing certificates.

### Engineering criteria

- Record focused clean-build and incremental-build times before and after the
  pilot.
- Count handwritten infrastructure separately from handwritten
  function-specific proof.
- Record which files rebuild after a harmless change to a Lanius local name or
  administrative block shape.
- Do not delete or migrate existing proofs until both identifier and whitespace
  scanners pass the new interface.

The decision to continue is based on these measurements. An order-of-magnitude
reduction is a hypothesis, not an acceptance criterion that can be declared in
advance.

## Parser and certificate implications

After the scanner pilot, `append_state` is the stateful pilot. Its public
contract should speak about an abstract chart and three outcomes:

```text
duplicate: the abstract chart is unchanged
inserted:  one valid item is added
full:      no physical record remains
```

The caller must not know that the physical state uses fixed-width records or
linked indices.

Parser certificate checking remains a separate design. The current complete
artifact checker validates the compiler's own extracted source artifact. It
does not validate arbitrary parser output at compiler runtime. Removing the
operational parser from the soundness-critical path requires a verified
checker that runs on every produced token stream or parse derivation, or a
pipeline type that downstream phases can construct only from an accepted
certificate.

A parse-tree checker can establish soundness of accepted trees. Parser
completeness, termination, capacity behavior, and unambiguity remain separate
theorems.

## Automation policy

Prototype the WP decomposition with Lean 4.33's `WP`/`vcgen` interfaces, but
put all use behind `Lanius.Automation.VCGen`. The semantic definitions and
soundness theorems must not depend on tactic implementation details.

Use small, explicit automation sets for the remaining obligations:

```text
lanius_pure
lanius_bounds
lanius_rep
lanius_frames
```

Prefer `grind only [...]` or another bounded discharger over unrestricted
global simplification. Automation should close equations and arithmetic after
the VCG has exposed the correct obligation; it should not discover the program
logic by unfolding the evaluator.

## Migration order

1. Freeze and measure the existing `scan_identifier_end` proof slice.
2. Add the checked-program facade and generated typed handles needed by the
   pilot only.
3. Define relational operation contracts and the structural WP over existing
   FunctionalView syntax.
4. Prove the generic Core soundness theorem for the constructs used by the
   scanner.
5. Register `is_identifier_continue` and prove the identifier scanner
   contract.
6. Instantiate the same infrastructure for `scan_whitespace_end`.
7. Review proof size, rebuild behavior, diagnostics, and axiom dependencies.
8. Only after the review, extend the WP to the constructs required by
   `append_state`.
9. Do not migrate `recognize` or design the backend proof IR until
   `append_state` succeeds at the abstract-chart boundary.

## Open questions resolved by the pilot

The pilot should answer these questions rather than settling them by design
fiat:

- Are the existing `TermHasType` judgments and the Core typing evidence
  retained by stateful reification sufficient, or would intrinsically typed
  expressions materially simplify the user proof?
- Is direct WP-to-Core soundness smaller than introducing a relational
  FunctionalView execution judgment?
- Can Lean 4.33 `vcgen` express our call and frame rules with stable,
  source-oriented diagnostics?
- Is a simple finite region algebra sufficient for arbitrary caller frames?
- Can typed function handles be generated entirely from existing checked
  function instances?
- Can the kernel-clean certificate profile handle the current artifact size at
  acceptable build cost?

## References

- [CompCert manual: semantic preservation and pass composition](https://compcert.org/man/manual001.html)
- [CakeML proof-producing translation of pure and stateful functions](https://cakeml.org/jfp14.pdf)
- [CakeML verified compiler backend](https://cakeml.org/jfp19.pdf)
- [Bedrock2 source semantics and weakest-precondition generator](https://github.com/mit-plv/bedrock2)
- [Aeneas functional translation and Lean backend](https://github.com/AeneasVerif/aeneas)
- [RefinedC and predictable Lithium proof search](https://plv.mpi-sws.org/refinedc/)
- [Lean 4.33 `WP`, `vcgen`, and frame inference](https://lean-lang.org/doc/reference/latest/releases/v4.33.0/)
- [Lean `grind`, `native_decide`, and `decide_cbv`](https://lean-lang.org/doc/reference/latest/Tactic-Proofs/Tactic-Reference/)
- [Coqlex verified lexer generation](https://programming-journal.org/2024/8/3/)
- [Validating LR(1) parsers](https://gallium.inria.fr/~fpottier/publis/jourdan-leroy-pottier-validating-parsers.pdf)
- [Alive2 bounded translation validation](https://web.ist.utl.pt/nuno.lopes/pubs.php?id=alive2-pldi21)
