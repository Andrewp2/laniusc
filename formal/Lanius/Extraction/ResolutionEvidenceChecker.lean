import Lanius.Extraction.ScopedSurface

namespace Lanius.Extraction.ResolutionEvidenceChecker

open Lanius
open Lanius.Extraction
open Lanius.Extraction.ScopedSurface
open Lanius.ScopeGraph

/-!
Semantic validation of the untrusted exporter's local-resolution certificate.

The located Surface program is the source of truth. `ScopedSurface` rebuilds
its lexical graph; this module requires the exporter to name the same unique
declaration and the same canonical scope path. Global declaration selection is
checked separately against the module/import environment, but even a global
row must prove that lexical lookup reached the function root first.
-/

def scopeIdentity : ScopeId → LexicalScopeIdentity
  | .functionBody node => ⟨.function_body, node⟩
  | .afterLocal node => ⟨.after_local, node⟩
  | .thenBody node => ⟨.then_body, node⟩
  | .elseBody node => ⟨.else_body, node⟩
  | .loopBody node => ⟨.loop_body, node⟩
  | .blockBody node => ⟨.block_body, node⟩

def wirePath (path : List ScopeId) : List LexicalScopeIdentity :=
  path.map scopeIdentity

def namespaceWire : Names.LookupNamespace → Namespace
  | .type => .type
  | .value => .value
  | .module => .module

def referenceNamespace : Names.Reference → Names.LookupNamespace
  | .unqualified lookupNamespace _ => lookupNamespace
  | .qualified lookupNamespace _ _ => lookupNamespace

def rowsForUse (artifact : Artifact) (node : SurfaceNodeId) :
    List ResolutionEvidence :=
  artifact.resolutions.filter (·.use_node == node)

inductive CheckedUseEvidence
    (artifact : Artifact) (graph : Graph) (use : CheckedUse graph) where
  | local
      (checked : CheckedReference graph use.reference)
      (outcome : use.resolution = .local checked)
      (row : ResolutionEvidence)
      (sameNode : row.use_node = use.reference.node)
      (sameDeclarationUnit :
        row.declaration_unit = checked.declaration.id.unit)
      (sameDeclarationNode :
        row.declaration_node = checked.declaration.id.node)
      (sameNamespace :
        row.namespace_tag = namespaceWire use.reference.lookupNamespace)
      (samePath : row.scope_path = wirePath checked.path)
  | global
      (noLocal : resolve? graph use.reference = none)
      (outcome : use.resolution = .global noLocal)
      (path : List ScopeId)
      (pathFound : enclosingPath? graph use.reference.scope = some path)
      (row : ResolutionEvidence)
      (sameNode : row.use_node = use.reference.node)
      (sameNamespace :
        row.namespace_tag = namespaceWire use.reference.lookupNamespace)
      (samePath : row.scope_path = wirePath path)

structure CheckedFunctionEvidence
    (artifact : Artifact) (function : CheckedFunction) where
  uses : List (Sigma fun use => CheckedUseEvidence artifact function.graph use)

structure CheckedModuleUseEvidence
    (artifact : Artifact) (use : ModuleUse) where
  row : ResolutionEvidence
  sameNode : row.use_node = use.node
  sameNamespace :
    row.namespace_tag = namespaceWire (referenceNamespace use.target)
  moduleScope : row.scope_path = []

def checkUseRow? (artifact : Artifact) (use : CheckedUse graph)
    (row : ResolutionEvidence) :
    Option (CheckedUseEvidence artifact graph use) :=
  match outcome : use.resolution with
  | .local checked =>
      if sameNode : row.use_node = use.reference.node then
        if sameDeclarationUnit :
            row.declaration_unit = checked.declaration.id.unit then
          if sameDeclarationNode :
              row.declaration_node = checked.declaration.id.node then
            if sameNamespace :
                row.namespace_tag = namespaceWire use.reference.lookupNamespace then
              if samePath : row.scope_path = wirePath checked.path then
                some (.local checked outcome row sameNode sameDeclarationUnit
                  sameDeclarationNode sameNamespace samePath)
              else none
            else none
          else none
        else none
      else none
  | .global noLocal =>
      match pathFound : enclosingPath? graph use.reference.scope with
      | none => none
      | some path =>
          if sameNode : row.use_node = use.reference.node then
            if sameNamespace :
                row.namespace_tag = namespaceWire use.reference.lookupNamespace then
              if samePath : row.scope_path = wirePath path then
                some (.global noLocal outcome path pathFound row sameNode
                  sameNamespace samePath)
              else none
            else none
          else none

def checkUsesRows? (artifact : Artifact) (graph : Graph) :
    (uses : List (CheckedUse graph)) → (rows : List ResolutionEvidence) →
      Option ((List (Sigma fun use => CheckedUseEvidence artifact graph use)) ×
        List ResolutionEvidence)
  | [], rows => some ([], rows)
  | use :: tail, row :: rows => do
      let head ← checkUseRow? artifact use row
      let (rest, remaining) ← checkUsesRows? artifact graph tail rows
      pure (⟨use, head⟩ :: rest, remaining)
  | _ :: _, [] => none

def checkFunctionsRows? (artifact : Artifact) :
    (functions : List CheckedFunction) → (rows : List ResolutionEvidence) →
      Option ((List (Sigma fun function => CheckedFunctionEvidence artifact function)) ×
        List ResolutionEvidence)
  | [], rows => some ([], rows)
  | function :: tail, rows => do
      let (uses, remaining) ←
        checkUsesRows? artifact function.graph function.uses rows
      let (rest, finalRows) ← checkFunctionsRows? artifact tail remaining
      pure (⟨function, ⟨uses⟩⟩ :: rest, finalRows)

def checkModuleUseRow? (artifact : Artifact) (use : ModuleUse)
    (row : ResolutionEvidence) :
    Option (CheckedModuleUseEvidence artifact use) :=
  if sameNode : row.use_node = use.node then
    if sameNamespace :
        row.namespace_tag = namespaceWire (referenceNamespace use.target) then
      if moduleScope : row.scope_path = [] then
        some ⟨row, sameNode, sameNamespace, moduleScope⟩
      else none
    else none
  else none

def checkModuleUsesRows? (artifact : Artifact) :
    (uses : List ModuleUse) → (rows : List ResolutionEvidence) →
      Option ((List (Sigma fun use => CheckedModuleUseEvidence artifact use)) ×
        List ResolutionEvidence)
  | [], rows => some ([], rows)
  | use :: tail, row :: rows => do
      let head ← checkModuleUseRow? artifact use row
      let (rest, remaining) ← checkModuleUsesRows? artifact tail rows
      pure (⟨use, head⟩ :: rest, remaining)
  | _ :: _, [] => none

def checkArtifactRows? (artifact : Artifact)
    (surface : CheckedArtifact artifact) :
    Option ((List (Sigma fun use => CheckedModuleUseEvidence artifact use)) ×
      (List (Sigma fun function => CheckedFunctionEvidence artifact function))) := do
  let (moduleUses, remaining) ←
    checkModuleUsesRows? artifact surface.moduleUses artifact.resolutions
  let (functions, finalRows) ←
    checkFunctionsRows? artifact surface.functions remaining
  match finalRows with
  | [] => some (moduleUses, functions)
  | _ => none

structure CheckedArtifactEvidence
    (artifact : Artifact) (surface : CheckedArtifact artifact) where
  functions :
    List (Sigma fun function => CheckedFunctionEvidence artifact function)
  moduleUses :
    List (Sigma fun use => CheckedModuleUseEvidence artifact use)
  accepted : checkArtifactRows? artifact surface = some (moduleUses, functions)

def checkArtifact? (artifact : Artifact) (surface : CheckedArtifact artifact) :
    Option (CheckedArtifactEvidence artifact surface) :=
  match accepted : checkArtifactRows? artifact surface with
  | none => none
  | some (moduleUses, functions) => some ⟨functions, moduleUses, accepted⟩

end Lanius.Extraction.ResolutionEvidenceChecker
