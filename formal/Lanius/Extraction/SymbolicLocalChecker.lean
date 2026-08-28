import Lanius.Extraction.CompleteChecker
import Lanius.SymbolicCore

namespace Lanius.Extraction.SymbolicLocalChecker

open Lanius
open Lanius.Core
open Lanius.Extraction
open Lanius.SymbolicCore
open Lanius.ScopeGraph

/-!
The complete checker supplies a checked scoped Surface view and the numeric
Core proposal. This module derives a convenience view for older proofs from
that accepted pair; it does not rebuild or reinterpret source scoping.
-/

def localIdentity (unit functionDeclaration declaration : SurfaceNodeId)
    (scope : List ScopeId) (name : SpelledName) : LocalIdentity := {
  functionDeclaration := ⟨unit, functionDeclaration⟩
  declaration := ⟨unit, declaration⟩
  scope
  name := name.text
}

def checkedScopePath? (graph : Graph) (scope : ScopeId) : Option (List ScopeId) :=
  (enclosingPath? graph scope).map List.reverse

def requireChild? (graph : Graph) (parent child : ScopeId) : Option Unit := do
  let childScope ← graph.scope? child
  if childScope.parent == some parent then some () else none

def deriveParameterBindings (unit functionDeclaration : SurfaceNodeId)
    (scope : List ScopeId) :
    List SurfaceParameter → List (Nat × CoreTy) →
      Option (List LocalBinding)
  | [], [] => some []
  | source :: sourceTail, (coreId, coreType) :: coreTail => do
      let tail ← deriveParameterBindings unit functionDeclaration scope
        sourceTail coreTail
      pure ({
        identity := localIdentity unit functionDeclaration source.id scope source.name
        coreId
        type := CoreDecode.ty coreType
        kind := .parameter
      } :: tail)
  | _, _ => none

structure StatementView where
  /-- Stable identity of the source statement represented by this row. -/
  sourceNode : SurfaceNodeId
  /-- Checked lexical scope at the entry to the source statement. -/
  lexicalScope : ScopeId
  /-- The Core fragment that implements this source statement.  For a `let`,
      this necessarily includes its binder-owned continuation. -/
  coreStatement : Stmt
  /-- The Core continuation beginning at this source statement.  Structural
      free-local analysis over this field gives the live frame at entry. -/
  coreContinuation : Stmt
deriving Repr

structure StatementDerivation where
  bindings : List LocalBinding
  statements : List StatementView

def StatementDerivation.append
    (left right : StatementDerivation) : StatementDerivation := {
  bindings := left.bindings ++ right.bindings
  statements := left.statements ++ right.statements
}

mutual
  /-- Traverse the checked source statements and accepted Core body together.
      This is the single derivation point for both local bindings and the
      source-statement/Core-fragment correspondence. -/
  def deriveStatements? (unit functionDeclaration : SurfaceNodeId)
      (graph : Graph) (scope : ScopeId) :
      List SurfaceStmt → CoreStmt → Option StatementDerivation
    | [], ⟨_, .skip⟩ => some ⟨[], []⟩
    | ⟨sourceNode, _, .expression _⟩ :: sourceTail,
        coreContinuation@(⟨_, .sequence
          coreStatement@(⟨_, .expression _⟩) coreTail⟩) => do
        let tail ← deriveStatements? unit functionDeclaration graph scope
          sourceTail coreTail
        pure {
          tail with
          statements := {
            sourceNode
            lexicalScope := scope
            coreStatement := CoreDecode.statement coreStatement
            coreContinuation := CoreDecode.statement coreContinuation
          } :: tail.statements
        }
    | ⟨declaration, _, .let_local name _ (some _)⟩ :: sourceTail,
        coreContinuation@(⟨_, .let_local coreId coreType _ coreBody⟩) => do
        let child := ScopeId.afterLocal declaration
        let _ ← requireChild? graph scope child
        let bindingScope ← checkedScopePath? graph child
        let tail ← deriveStatements? unit functionDeclaration graph child
          sourceTail coreBody
        pure ({
          bindings := {
            identity := localIdentity unit functionDeclaration declaration
              bindingScope name
            coreId
            type := CoreDecode.ty coreType
            kind := .local
          } :: tail.bindings
          statements := {
            sourceNode := declaration
            lexicalScope := scope
            coreStatement := CoreDecode.statement coreContinuation
            coreContinuation := CoreDecode.statement coreContinuation
          } :: tail.statements
        })
    | ⟨declaration, _, .let_local name _ none⟩ :: sourceTail,
        coreContinuation@(⟨_, .let_uninitialized coreId coreType coreBody⟩) => do
        let child := ScopeId.afterLocal declaration
        let _ ← requireChild? graph scope child
        let bindingScope ← checkedScopePath? graph child
        let tail ← deriveStatements? unit functionDeclaration graph child
          sourceTail coreBody
        pure ({
          bindings := {
            identity := localIdentity unit functionDeclaration declaration
              bindingScope name
            coreId
            type := CoreDecode.ty coreType
            kind := .local
          } :: tail.bindings
          statements := {
            sourceNode := declaration
            lexicalScope := scope
            coreStatement := CoreDecode.statement coreContinuation
            coreContinuation := CoreDecode.statement coreContinuation
          } :: tail.statements
        })
    | ⟨sourceNode, _, .return_value _⟩ :: sourceTail,
        coreContinuation@(⟨_, .sequence
          coreStatement@(⟨_, .return_value _⟩) coreTail⟩) => do
        let tail ← deriveStatements? unit functionDeclaration graph scope
          sourceTail coreTail
        pure {
          tail with
          statements := {
            sourceNode
            lexicalScope := scope
            coreStatement := CoreDecode.statement coreStatement
            coreContinuation := CoreDecode.statement coreContinuation
          } :: tail.statements
        }
    | ⟨declaration, _, .if_then_else _ sourceThen sourceElse⟩ :: sourceTail,
        coreContinuation@(⟨_, .sequence
          coreStatement@(⟨_, .if_then_else _ coreThen coreElse⟩) coreTail⟩) => do
        let thenScope := ScopeId.thenBody declaration
        let elseScope := ScopeId.elseBody declaration
        let _ ← requireChild? graph scope thenScope
        let _ ← requireChild? graph scope elseScope
        let thenDerived ← deriveStatements? unit functionDeclaration
          graph thenScope sourceThen coreThen
        let elseDerived ← deriveStatements? unit functionDeclaration
          graph elseScope sourceElse coreElse
        let tailDerived ← deriveStatements? unit functionDeclaration
          graph scope sourceTail coreTail
        let nested := thenDerived.append (elseDerived.append tailDerived)
        pure {
          bindings := nested.bindings
          statements := {
            sourceNode := declaration
            lexicalScope := scope
            coreStatement := CoreDecode.statement coreStatement
            coreContinuation := CoreDecode.statement coreContinuation
          } :: nested.statements
        }
    | ⟨declaration, _, .while_loop _ sourceBody⟩ :: sourceTail,
        coreContinuation@(⟨_, .sequence
          coreStatement@(⟨_, .while_loop _ coreBody⟩) coreTail⟩) => do
        let bodyScope := ScopeId.loopBody declaration
        let _ ← requireChild? graph scope bodyScope
        let bodyDerived ← deriveStatements? unit functionDeclaration
          graph bodyScope sourceBody coreBody
        let tailDerived ← deriveStatements? unit functionDeclaration
          graph scope sourceTail coreTail
        let nested := bodyDerived.append tailDerived
        pure {
          bindings := nested.bindings
          statements := {
            sourceNode := declaration
            lexicalScope := scope
            coreStatement := CoreDecode.statement coreStatement
            coreContinuation := CoreDecode.statement coreContinuation
          } :: nested.statements
        }
    | ⟨declaration, _, .block sourceBody⟩ :: sourceTail,
        coreContinuation@(⟨_, .sequence coreBody coreTail⟩) => do
        let bodyScope := ScopeId.blockBody declaration
        let _ ← requireChild? graph scope bodyScope
        let bodyDerived ← deriveStatements? unit functionDeclaration
          graph bodyScope sourceBody coreBody
        let tailDerived ← deriveStatements? unit functionDeclaration
          graph scope sourceTail coreTail
        let nested := bodyDerived.append tailDerived
        pure {
          bindings := nested.bindings
          statements := {
            sourceNode := declaration
            lexicalScope := scope
            coreStatement := CoreDecode.statement coreBody
            coreContinuation := CoreDecode.statement coreContinuation
          } :: nested.statements
        }
    | ⟨sourceNode, _, .break_loop⟩ :: sourceTail,
        coreContinuation@(⟨_, .sequence
          coreStatement@(⟨_, .break_loop⟩) coreTail⟩) => do
        let tail ← deriveStatements? unit functionDeclaration graph scope
          sourceTail coreTail
        pure {
          tail with
          statements := {
            sourceNode
            lexicalScope := scope
            coreStatement := CoreDecode.statement coreStatement
            coreContinuation := CoreDecode.statement coreContinuation
          } :: tail.statements
        }
    | ⟨sourceNode, _, .continue_loop⟩ :: sourceTail,
        coreContinuation@(⟨_, .sequence
          coreStatement@(⟨_, .continue_loop⟩) coreTail⟩) => do
        let tail ← deriveStatements? unit functionDeclaration graph scope
          sourceTail coreTail
        pure {
          tail with
          statements := {
            sourceNode
            lexicalScope := scope
            coreStatement := CoreDecode.statement coreStatement
            coreContinuation := CoreDecode.statement coreContinuation
          } :: tail.statements
        }
    | _, _ => none
end

def buildView? (core : Function) (bindings : List LocalBinding) :
    Option FunctionView :=
  let layout : LocalLayout := ⟨bindings⟩
  if layoutWellFormed : layout.wellFormed = true then
    if layoutCovers : layout.covers core = true then
      if coreWellScoped : core.wellScoped = true then
        some {
          core
          locals := layout
          layoutWellFormed
          layoutCoversCore := layoutCovers
          coreWellScoped
        }
      else none
    else none
  else none

structure DerivedFunction where
  sourceUnit : Nat
  /-- The checked source function is stored with its Core view so consumers
      cannot accidentally resolve a use against an unrelated scope graph. -/
  source : ScopedSurface.CheckedFunction
  view : FunctionView
  /-- Checked source-statement/Core-fragment rows.  Source identities are
      unique, making statement lookup unambiguous. -/
  statements : List StatementView
  statementsUnique : (statements.map (fun statement => statement.sourceNode)).Nodup

def DerivedFunction.sourceDeclaration (derived : DerivedFunction) :
    SurfaceNodeId :=
  derived.source.sourceDeclaration

def DerivedFunction.sourceName (derived : DerivedFunction) : String :=
  derived.source.source.name.text

def DerivedFunction.rootScope (derived : DerivedFunction) : ScopeId :=
  ScopeId.functionBody derived.sourceDeclaration

def DerivedFunction.rootScopePath? (derived : DerivedFunction) :
    Option (List ScopeId) :=
  checkedScopePath? derived.source.graph derived.rootScope

/-- The checked Core bindings introduced by source parameters, in source
    declaration order.  Consumers should use this declaration-backed domain
    instead of reconstructing the parameter range from numeric Core IDs. -/
def DerivedFunction.parameterBindings (derived : DerivedFunction) :
    List LocalBinding :=
  derived.view.locals.bindings.filter fun binding =>
    binding.kind == .parameter

def DerivedFunction.parameterCoreIds (derived : DerivedFunction) :
    List VarId :=
  derived.parameterBindings.map (·.coreId)

/-- Resolve a source parameter spelling through its declaration identity, then
    translate that declaration through the checked Core layout.  The spelling
    is only a source lookup convenience; the returned reference is tied to the
    declaration, not to a numeric Core slot. -/
def DerivedFunction.parameterReferenceNamed? (derived : DerivedFunction)
    (name : String) : Option (LocalRef derived.view.locals) := do
  let parameter ← derived.source.source.parameters.find? (fun candidate =>
    candidate.name.text == name)
  derived.view.locals.referenceForDeclaration?
    ⟨derived.sourceUnit, parameter.id⟩

/-- Totalize a globally unique source-local lookup only after the checked
    symbolic layout proves that the spelling identifies one declaration.
    This is intended for proof resources retained beyond their last program
    use; statement-local clients should prefer the lexical frame APIs below. -/
def DerivedFunction.checkedUniqueBindingNamed
    (derived : DerivedFunction) (name : String)
    (found : (derived.view.locals.uniqueReferenceNamed? name).isSome) :
    LocalBinding :=
  (derived.view.locals.uniqueReferenceNamed? name).get found |>.binding

/-- Mechanically translate a located source use into the Core local selected
    for its proved lexical declaration. Global references return `none`. -/
def DerivedFunction.referenceAtUse? (derived : DerivedFunction)
    (useNode : SurfaceNodeId) :
    Option (LocalRef derived.view.locals) := do
  let use ← derived.source.uses.find? (fun candidate =>
    candidate.reference.node == useNode)
  let declaration ← use.localDeclaration?
  if declaration.unit == derived.sourceUnit then pure () else failure
  derived.view.locals.referenceForDeclaration? declaration

/-- Structural free-local requirements for a statement at a checked lexical
    scope.  This is the proof-facing separation-frame domain: it contains one
    row per live declaration with read/write modes joined across occurrences. -/
def DerivedFunction.liveBindingsAt? (derived : DerivedFunction)
    (scope : ScopeId) (statement : Stmt) :
    Option (List (LocalBinding × AccessMode)) := do
  let path ← checkedScopePath? derived.source.graph scope
  pure (derived.view.locals.freeBindingsAt path statement)

def DerivedFunction.rootLiveBindings? (derived : DerivedFunction)
    (statement : Stmt) : Option LocalAccessFrame :=
  derived.liveBindingsAt? derived.rootScope statement

def DerivedFunction.checkedRootLiveFrame
    (derived : DerivedFunction) (statement : Stmt)
    (found : (derived.rootLiveBindings? statement).isSome) :
    LocalAccessFrame :=
  (derived.rootLiveBindings? statement).get found

def DerivedFunction.statementAt? (derived : DerivedFunction)
    (sourceNode : SurfaceNodeId) : Option StatementView :=
  derived.statements.find? (fun statement => statement.sourceNode == sourceNode)

/-- Find the unique checked source statement whose lowering fragment is the
    requested Core statement.  Returning `none` for zero or multiple matches
    prevents a proof from silently attaching itself to the wrong occurrence
    of repeated syntax. -/
def DerivedFunction.statementForCore? (derived : DerivedFunction)
    (coreStatement : Stmt) : Option StatementView :=
  match derived.statements.filter (fun statement =>
      statement.coreStatement == coreStatement) with
  | [statement] => some statement
  | _ => none

/-- Live source declarations immediately before a checked source statement.
    Both the lexical scope and Core continuation come from the mechanically
    checked source/Core correspondence. -/
def DerivedFunction.liveBindingsBefore? (derived : DerivedFunction)
    (sourceNode : SurfaceNodeId) : Option LocalAccessFrame := do
  let statement ← derived.statementAt? sourceNode
  derived.liveBindingsAt? statement.lexicalScope statement.coreContinuation

def DerivedFunction.liveBindingsBeforeCore? (derived : DerivedFunction)
    (coreStatement : Stmt) : Option LocalAccessFrame := do
  let statement ← derived.statementForCore? coreStatement
  derived.liveBindingsAt? statement.lexicalScope statement.coreContinuation

/-- Source declarations accessed by one checked Core statement, excluding
    declarations used only by its continuation.  This is distinct from the
    live-at-entry frame above and is the right domain for statement-local
    read/write ownership. -/
def DerivedFunction.accessBindingsForCore? (derived : DerivedFunction)
    (coreStatement : Stmt) : Option LocalAccessFrame := do
  let statement ← derived.statementForCore? coreStatement
  derived.liveBindingsAt? statement.lexicalScope statement.coreStatement

/-- Totalize a uniquely matched checked access frame only with explicit proof
    that source/Core correspondence found exactly one statement. -/
def DerivedFunction.checkedAccessFrameForCore
    (derived : DerivedFunction) (coreStatement : Stmt)
    (found : (derived.accessBindingsForCore? coreStatement).isSome) :
    LocalAccessFrame :=
  (derived.accessBindingsForCore? coreStatement).get found

/-- Checked live-at-entry counterpart of `checkedAccessFrameForCore`. -/
def DerivedFunction.checkedLiveFrameBeforeCore
    (derived : DerivedFunction) (coreStatement : Stmt)
    (found : (derived.liveBindingsBeforeCore? coreStatement).isSome) :
    LocalAccessFrame :=
  (derived.liveBindingsBeforeCore? coreStatement).get found

def deriveFunction? (unit : Nat) (source : ScopedSurface.CheckedFunction)
    (wire : CoreFunction) : Option DerivedFunction := do
  let root := ScopeId.functionBody source.sourceDeclaration
  let rootPath ← checkedScopePath? source.graph root
  let parameterBindings ← deriveParameterBindings unit
    source.sourceDeclaration rootPath source.source.parameters wire.parameters
  let coreBody ← wire.body
  let body ← deriveStatements? unit source.sourceDeclaration
    source.graph root source.source.body coreBody
  let view ← buildView? (CoreDecode.function wire)
    (parameterBindings ++ body.bindings)
  if statementsUnique :
      (body.statements.map (fun statement => statement.sourceNode)).Nodup then
    pure {
      sourceUnit := unit
      source
      view
      statements := body.statements
      statementsUnique
    }
  else none

def deriveFunctions? (unit : Nat) :
    List ScopedSurface.CheckedFunction → List CoreFunction →
      Option (List DerivedFunction)
  | [], [] => some []
  | source :: sourceTail, core :: coreTail => do
      let head ← deriveFunction? unit source core
      let tail ← deriveFunctions? unit sourceTail coreTail
      pure (head :: tail)
  | _, _ => none

def deriveArtifact? (artifact : Artifact)
    (surface : ScopedSurface.CheckedArtifact artifact) :
    Option (List DerivedFunction) := do
  let core ← artifact.core_program
  deriveFunctions? surface.unit surface.functions core.functions

/-- One accepted boundary gives consumers both the complete source-to-Core
    certificate and its checked symbolic-local view. -/
structure CheckedArtifact (artifact : Artifact)
    (surface : ScopedSurface.CheckedArtifact artifact) where
  complete : CompleteChecker.CheckedArtifact artifact surface
  functions : List DerivedFunction
  derived : deriveArtifact? artifact surface = some functions

/-- Extend an existing complete source-to-Core certificate with the symbolic
    local-binding view.  Proof pipelines use this operation to compose checked
    stages without accepting or recomputing an independent earlier result. -/
def extendCheckedArtifact? (artifact : Artifact)
    (surface : ScopedSurface.CheckedArtifact artifact)
    (complete : CompleteChecker.CheckedArtifact artifact surface) :
    Option (CheckedArtifact artifact surface) :=
  match derived : deriveArtifact? artifact surface with
  | none => none
  | some functions => some ⟨complete, functions, derived⟩

def checkArtifact? (artifact : Artifact) :
    Option (Sigma fun surface : ScopedSurface.CheckedArtifact artifact =>
      CheckedArtifact artifact surface) := do
  let complete ← CompleteChecker.checkArtifact? artifact
  let checked ← extendCheckedArtifact? artifact complete.1 complete.2
  pure ⟨complete.1, checked⟩

end Lanius.Extraction.SymbolicLocalChecker
