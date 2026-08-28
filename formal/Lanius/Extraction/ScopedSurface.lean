import Lanius.Extraction.Artifact
import Lanius.Elaboration
import Lanius.ScopeGraph

namespace Lanius.Extraction.ScopedSurface

open Lanius
open Lanius.Extraction
open Lanius.ScopeGraph

/-!
Construction of lexical scope graphs from the source-located Surface tree.

This phase runs before type checking and Core local allocation. It classifies
each source reference as either a checked lexical reference or a reference
that must be resolved by the module/global phase. The original located path is
retained so qualified names and generic arguments are never reconstructed from
the lexical lookup key.
-/

structure PendingReference where
  reference : Reference
  sourcePath : SurfacePath

structure BuildState where
  scopes : List Scope := []
  references : List PendingReference := []

abbrev BuildM := StateT BuildState Option

def addScope (scope : Scope) : BuildM Unit :=
  modify fun state => { state with scopes := state.scopes ++ [scope] }

def addReference (reference : PendingReference) : BuildM Unit :=
  modify fun state => {
    state with references := state.references ++ [reference]
  }

def referenceFromPath? (lookupNamespace : Names.LookupNamespace)
    (path : SurfacePath) : Option Names.Reference :=
  match (path.value.segments.map (fun segment => segment.name.text)).reverse with
  | [] => none
  | name :: reversedModule =>
      match reversedModule.reverse with
      | [] => some (.unqualified lookupNamespace name)
      | modulePath => some (.qualified lookupNamespace modulePath name)

def addPathReference (unit : Nat) (scope : ScopeId)
    (lookupNamespace : Names.LookupNamespace) (useNode : SurfaceNodeId)
    (path : SurfacePath) : BuildM Unit := do
  let target ← referenceFromPath? lookupNamespace path
  addReference {
    reference := { unit, node := useNode, scope, target }
    sourcePath := path
  }

def isBuiltinTypePath (path : SurfacePath) : Bool :=
  match path.value.segments with
  | [segment] =>
      segment.arguments.isEmpty &&
        (Elaboration.builtinScalar? segment.name.text).isSome
  | _ => false

mutual
  def collectTypeReferences
      (fuel : Nat) (unit : Nat) (scope : ScopeId)
      (type : SurfaceTypeExpr) : BuildM Unit := do
    if fuel = 0 then failure else
    let fuel := fuel - 1
    match type.value with
    | .path path =>
        unless isBuiltinTypePath path do
          addPathReference unit scope .type type.id path
        collectPathArgumentReferences fuel unit scope path.value.segments
    | .array element _ => collectTypeReferences fuel unit scope element
    | .slice element => collectTypeReferences fuel unit scope element
    | .reference referent => collectTypeReferences fuel unit scope referent

  def collectPathArgumentReferences
      (fuel : Nat) (unit : Nat) (scope : ScopeId) :
      List SurfacePathSegment → BuildM Unit
    | [] => pure ()
    | segment :: tail => do
        if fuel = 0 then failure else
        let fuel := fuel - 1
        collectTypeListReferences fuel unit scope segment.arguments
        collectPathArgumentReferences fuel unit scope tail

  def collectTypeListReferences
      (fuel : Nat) (unit : Nat) (scope : ScopeId) :
      List SurfaceTypeExpr → BuildM Unit
    | [] => pure ()
    | head :: tail => do
        if fuel = 0 then failure else
        let fuel := fuel - 1
        collectTypeReferences fuel unit scope head
        collectTypeListReferences fuel unit scope tail
end

mutual
  def collectExprReferences
      (fuel : Nat) (unit : Nat) (scope : ScopeId)
      (expression : SurfaceExpr) : BuildM Unit := do
    if fuel = 0 then failure else
    let fuel := fuel - 1
    match expression.value with
    | .literal _ => pure ()
    | .path path =>
        addPathReference unit scope .value expression.id path
        collectPathArgumentReferences fuel unit scope path.value.segments
    | .array elements => collectExprListReferences fuel unit scope elements
    | .struct_value path fields =>
        addPathReference unit scope .type expression.id path
        collectPathArgumentReferences fuel unit scope path.value.segments
        collectFieldReferences fuel unit scope fields
    | .unary _ operand => collectExprReferences fuel unit scope operand
    | .binary _ left right =>
        collectExprReferences fuel unit scope left
        collectExprReferences fuel unit scope right
    | .assign _ place value =>
        collectExprReferences fuel unit scope place
        collectExprReferences fuel unit scope value
    | .call callee arguments =>
        collectExprReferences fuel unit scope callee
        collectExprListReferences fuel unit scope arguments
    | .index base index =>
        collectExprReferences fuel unit scope base
        collectExprReferences fuel unit scope index
    | .member base _ => collectExprReferences fuel unit scope base

  def collectExprListReferences
      (fuel : Nat) (unit : Nat) (scope : ScopeId) :
      List SurfaceExpr → BuildM Unit
    | [] => pure ()
    | head :: tail => do
        if fuel = 0 then failure else
        let fuel := fuel - 1
        collectExprReferences fuel unit scope head
        collectExprListReferences fuel unit scope tail

  def collectFieldReferences
      (fuel : Nat) (unit : Nat) (scope : ScopeId) :
      List SurfaceStructFieldValue → BuildM Unit
    | [] => pure ()
    | head :: tail => do
        if fuel = 0 then failure else
        let fuel := fuel - 1
        collectExprReferences fuel unit scope head.value
        collectFieldReferences fuel unit scope tail
end

def collectOptionalExprReferences
    (fuel : Nat) (unit : Nat) (scope : ScopeId) : Option SurfaceExpr → BuildM Unit
  | none => pure ()
  | some expression => collectExprReferences fuel unit scope expression

mutual
  def buildStatements
      (fuel : Nat) (unit : Nat) (scope : ScopeId) :
      List SurfaceStmt → BuildM Unit
    | [] => pure ()
    | statement :: tail => do
        if fuel = 0 then failure else
        let fuel := fuel - 1
        match statement.value with
        | .let_local name typeAnnotation initializer =>
            -- A declaration is not visible in its own initializer.
            match typeAnnotation with
            | none => pure ()
            | some type => collectTypeReferences fuel unit scope type
            collectOptionalExprReferences fuel unit scope initializer
            let child := ScopeId.afterLocal statement.id
            addScope {
              id := child
              parent := some scope
              declarations := [{
                id := ⟨unit, statement.id⟩
                lookupNamespace := .value
                name := name.text
              }]
            }
            buildStatements fuel unit child tail
        | .return_value value =>
            collectOptionalExprReferences fuel unit scope value
            buildStatements fuel unit scope tail
        | .if_then_else condition thenBody elseBody =>
            collectExprReferences fuel unit scope condition
            let thenScope := ScopeId.thenBody statement.id
            let elseScope := ScopeId.elseBody statement.id
            addScope ⟨thenScope, some scope, []⟩
            buildStatements fuel unit thenScope thenBody
            addScope ⟨elseScope, some scope, []⟩
            buildStatements fuel unit elseScope elseBody
            buildStatements fuel unit scope tail
        | .while_loop condition body =>
            collectExprReferences fuel unit scope condition
            let bodyScope := ScopeId.loopBody statement.id
            addScope ⟨bodyScope, some scope, []⟩
            buildStatements fuel unit bodyScope body
            buildStatements fuel unit scope tail
        | .block body =>
            let bodyScope := ScopeId.blockBody statement.id
            addScope ⟨bodyScope, some scope, []⟩
            buildStatements fuel unit bodyScope body
            buildStatements fuel unit scope tail
        | .expression expression =>
            collectExprReferences fuel unit scope expression
            buildStatements fuel unit scope tail
        | .break_loop | .continue_loop =>
            buildStatements fuel unit scope tail
end

def parameterDeclaration (unit : Nat) (parameter : SurfaceParameter) : Declaration := {
  id := ⟨unit, parameter.id⟩
  lookupNamespace := .value
  name := parameter.name.text
}

structure BuiltFunction where
  sourceDeclaration : SurfaceNodeId
  source : SurfaceFunction
  graph : Graph
  references : List PendingReference

def buildFunction
    (unit declaration : Nat) (source : SurfaceFunction) : Option BuiltFunction := do
  let root := ScopeId.functionBody declaration
  let initial : BuildState := {
    scopes := [{
      id := root
      parent := none
      declarations := source.parameters.map (parameterDeclaration unit)
    }]
  }
  let (_, final) ← buildStatements (declaration + 1) unit root source.body initial
  pure {
    sourceDeclaration := declaration
    source
    graph := ⟨final.scopes⟩
    references := final.references
  }

inductive ResolutionOutcome (graph : Graph) (reference : Reference) where
  | local (checked : CheckedReference graph reference)
  | global (noLocal : resolve? graph reference = none)

structure CheckedUse (graph : Graph) where
  reference : Reference
  sourcePath : SurfacePath
  resolution : ResolutionOutcome graph reference

def classifyReference (graph : Graph) (pending : PendingReference) : CheckedUse graph :=
  match accepted : resolve? graph pending.reference with
  | none => ⟨pending.reference, pending.sourcePath, .global accepted⟩
  | some (declaration, path) =>
      ⟨pending.reference, pending.sourcePath,
        .local ⟨declaration, path, accepted⟩⟩

def classifyReferences (graph : Graph) :
    List PendingReference → List (CheckedUse graph)
  | [] => []
  | head :: tail => classifyReference graph head :: classifyReferences graph tail

/-- Checked source view consumed by global resolution and type elaboration. -/
structure CheckedFunction where
  sourceDeclaration : SurfaceNodeId
  source : SurfaceFunction
  graph : Graph
  graphWellFormed : graph.wellFormed = true
  uses : List (CheckedUse graph)

def checkFunction?
    (unit declaration : Nat) (source : SurfaceFunction) : Option CheckedFunction := do
  let built ← buildFunction unit declaration source
  if graphWellFormed : built.graph.wellFormed = true then
    some {
      sourceDeclaration := declaration
      source
      graph := built.graph
      graphWellFormed
      uses := classifyReferences built.graph built.references
    }
  else none

def CheckedFunction.erase (checked : CheckedFunction) : SurfaceFunction :=
  checked.source

@[simp] theorem CheckedFunction.erase_source (checked : CheckedFunction) :
    checked.erase = checked.source := rfl

def CheckedUse.localDeclaration? (use : CheckedUse graph) : Option DeclarationId :=
  match use.resolution with
  | .local checked => some checked.declaration.id
  | .global _ => none

def CheckedFunction.localDeclarationNode? (checked : CheckedFunction)
    (useNode : SurfaceNodeId) : Option SurfaceNodeId := do
  let use ← checked.uses.find? (fun candidate => candidate.reference.node == useNode)
  pure (← use.localDeclaration?).node

def collectFunctions : List SurfaceItem → List (SurfaceNodeId × SurfaceFunction)
  | [] => []
  | ⟨declaration, _, .function function⟩ :: tail =>
      (declaration, function) :: collectFunctions tail
  | _ :: tail => collectFunctions tail

def checkFunctions? (unit : Nat) :
    List (SurfaceNodeId × SurfaceFunction) → Option (List CheckedFunction)
  | [] => some []
  | (declaration, function) :: tail => do
      let head ← checkFunction? unit declaration function
      let rest ← checkFunctions? unit tail
      pure (head :: rest)

/-! Declaration signatures live at module scope, not inside any function
    scope. Keeping them separate prevents later proofs from granting parameter
    or local visibility where the language does not. -/

structure ModuleUse where
  unit : Nat
  node : SurfaceNodeId
  target : Names.Reference
  sourcePath : SurfacePath

abbrev ModuleBuildM := StateT (List ModuleUse) Option

def addModulePathReference (unit : Nat) (useNode : SurfaceNodeId)
    (path : SurfacePath) : ModuleBuildM Unit := do
  let target ← referenceFromPath? .type path
  modify fun uses => uses ++ [{ unit, node := useNode, target, sourcePath := path }]

mutual
  def collectModuleTypeReferences
      (fuel : Nat) (unit : Nat) (type : SurfaceTypeExpr) : ModuleBuildM Unit := do
    if fuel = 0 then failure else
    let fuel := fuel - 1
    match type.value with
    | .path path =>
        unless isBuiltinTypePath path do
          addModulePathReference unit type.id path
        collectModulePathArguments fuel unit path.value.segments
    | .array element _ => collectModuleTypeReferences fuel unit element
    | .slice element => collectModuleTypeReferences fuel unit element
    | .reference referent => collectModuleTypeReferences fuel unit referent

  def collectModulePathArguments (fuel : Nat) (unit : Nat) :
      List SurfacePathSegment → ModuleBuildM Unit
    | [] => pure ()
    | segment :: tail => do
        if fuel = 0 then failure else
        let fuel := fuel - 1
        collectModuleTypeList fuel unit segment.arguments
        collectModulePathArguments fuel unit tail

  def collectModuleTypeList (fuel : Nat) (unit : Nat) :
      List SurfaceTypeExpr → ModuleBuildM Unit
    | [] => pure ()
    | head :: tail => do
        if fuel = 0 then failure else
        let fuel := fuel - 1
        collectModuleTypeReferences fuel unit head
        collectModuleTypeList fuel unit tail
end

def collectParameterTypeReferences (fuel : Nat) (unit : Nat) :
    List SurfaceParameter → ModuleBuildM Unit
  | [] => pure ()
  | head :: tail => do
      if fuel = 0 then failure else
      let fuel := fuel - 1
      collectModuleTypeReferences fuel unit head.type_expression
      collectParameterTypeReferences fuel unit tail

def collectFieldTypeReferences (fuel : Nat) (unit : Nat) :
    List SurfaceStructField → ModuleBuildM Unit
  | [] => pure ()
  | head :: tail => do
      if fuel = 0 then failure else
      let fuel := fuel - 1
      collectModuleTypeReferences fuel unit head.type_expression
      collectFieldTypeReferences fuel unit tail

def collectModuleItemReferences (fuel : Nat) (unit : Nat) :
    List SurfaceItem → ModuleBuildM Unit
  | [] => pure ()
  | item :: tail => do
      if fuel = 0 then failure else
      let fuel := fuel - 1
      match item.value with
      | .function function =>
          collectParameterTypeReferences fuel unit function.parameters
          match function.return_type with
          | none => pure ()
          | some type => collectModuleTypeReferences fuel unit type
      | .constant _ _ type _ => collectModuleTypeReferences fuel unit type
      | .type_alias _ _ target => collectModuleTypeReferences fuel unit target
      | .structure declaration =>
          collectFieldTypeReferences fuel unit declaration.fields
      | .module _ | .import_path _ => pure ()
      collectModuleItemReferences fuel unit tail

def collectModuleUses? (fuel unit : Nat) (items : List SurfaceItem) :
    Option (List ModuleUse) := do
  let (_, uses) ← collectModuleItemReferences fuel unit items []
  pure uses

structure CheckedArtifact (artifact : Artifact) where
  unit : Nat
  source : SurfaceFile
  sourceFound : artifact.surface = some source
  functions : List CheckedFunction
  functionsChecked :
    checkFunctions? unit (collectFunctions source.value.items) = some functions
  moduleUses : List ModuleUse
  moduleUsesCollected :
    collectModuleUses? (source.id + 1) unit source.value.items = some moduleUses

def checkArtifactInUnit? (unit : Nat) (artifact : Artifact) :
    Option (CheckedArtifact artifact) := do
  match sourceFound : artifact.surface with
  | none => none
  | some source =>
      match functionsChecked :
          checkFunctions? unit (collectFunctions source.value.items) with
      | none => none
      | some functions =>
          match moduleUsesCollected :
              collectModuleUses? (source.id + 1) unit source.value.items with
          | none => none
          | some moduleUses => some ⟨unit, source, sourceFound, functions,
              functionsChecked, moduleUses, moduleUsesCollected⟩

def checkArtifact? (artifact : Artifact) : Option (CheckedArtifact artifact) :=
  checkArtifactInUnit? 0 artifact

end Lanius.Extraction.ScopedSurface
