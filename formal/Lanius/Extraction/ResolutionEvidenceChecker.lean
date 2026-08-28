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
      (uniqueRow : rowsForUse artifact use.reference.node = [row])
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
      (uniqueRow : rowsForUse artifact use.reference.node = [row])
      (sameNamespace :
        row.namespace_tag = namespaceWire use.reference.lookupNamespace)
      (samePath : row.scope_path = wirePath path)

def checkUse? (artifact : Artifact) (use : CheckedUse graph) :
    Option (CheckedUseEvidence artifact graph use) :=
  match uniqueRow : rowsForUse artifact use.reference.node with
  | [row] =>
      match outcome : use.resolution with
      | .local checked =>
          if sameDeclarationUnit :
              row.declaration_unit = checked.declaration.id.unit then
            if sameDeclarationNode :
                row.declaration_node = checked.declaration.id.node then
              if sameNamespace :
                  row.namespace_tag = namespaceWire use.reference.lookupNamespace then
                if samePath : row.scope_path = wirePath checked.path then
                  some (.local checked outcome row uniqueRow sameDeclarationUnit
                    sameDeclarationNode sameNamespace samePath)
                else none
              else none
            else none
          else none
      | .global noLocal =>
          match pathFound : enclosingPath? graph use.reference.scope with
          | none => none
          | some path =>
              if sameNamespace :
                  row.namespace_tag = namespaceWire use.reference.lookupNamespace then
                if samePath : row.scope_path = wirePath path then
                  some (.global noLocal outcome path pathFound row uniqueRow
                    sameNamespace samePath)
                else none
              else none
  | _ => none

def checkUses? (artifact : Artifact) (graph : Graph) :
    (uses : List (CheckedUse graph)) →
      Option (List (Sigma fun use => CheckedUseEvidence artifact graph use))
  | [] => some []
  | use :: tail => do
      let head ← checkUse? artifact use
      let rest ← checkUses? artifact graph tail
      pure (⟨use, head⟩ :: rest)

structure CheckedFunctionEvidence
    (artifact : Artifact) (function : CheckedFunction) where
  uses : List (Sigma fun use => CheckedUseEvidence artifact function.graph use)
  accepted : checkUses? artifact function.graph function.uses = some uses

def checkFunction? (artifact : Artifact) (function : CheckedFunction) :
    Option (CheckedFunctionEvidence artifact function) :=
  match accepted : checkUses? artifact function.graph function.uses with
  | none => none
  | some uses => some ⟨uses, accepted⟩

def checkFunctions? (artifact : Artifact) :
    (functions : List CheckedFunction) →
      Option (List (Sigma fun function => CheckedFunctionEvidence artifact function))
  | [] => some []
  | function :: tail => do
      let head ← checkFunction? artifact function
      let rest ← checkFunctions? artifact tail
      pure (⟨function, head⟩ :: rest)

structure CheckedModuleUseEvidence
    (artifact : Artifact) (use : ModuleUse) where
  row : ResolutionEvidence
  uniqueRow : rowsForUse artifact use.node = [row]
  sameNamespace :
    row.namespace_tag = namespaceWire (referenceNamespace use.target)
  moduleScope : row.scope_path = []

def checkModuleUse? (artifact : Artifact) (use : ModuleUse) :
    Option (CheckedModuleUseEvidence artifact use) :=
  match uniqueRow : rowsForUse artifact use.node with
  | [row] =>
      if sameNamespace :
          row.namespace_tag = namespaceWire (referenceNamespace use.target) then
        if moduleScope : row.scope_path = [] then
          some ⟨row, uniqueRow, sameNamespace, moduleScope⟩
        else none
      else none
  | _ => none

def checkModuleUses? (artifact : Artifact) :
    (uses : List ModuleUse) →
      Option (List (Sigma fun use => CheckedModuleUseEvidence artifact use))
  | [] => some []
  | use :: tail => do
      let head ← checkModuleUse? artifact use
      let rest ← checkModuleUses? artifact tail
      pure (⟨use, head⟩ :: rest)

structure CheckedArtifactEvidence
    (artifact : Artifact) (surface : CheckedArtifact artifact) where
  functions :
    List (Sigma fun function => CheckedFunctionEvidence artifact function)
  functionsAccepted : checkFunctions? artifact surface.functions = some functions
  moduleUses :
    List (Sigma fun use => CheckedModuleUseEvidence artifact use)
  moduleUsesAccepted :
    checkModuleUses? artifact surface.moduleUses = some moduleUses

def checkArtifact? (artifact : Artifact) (surface : CheckedArtifact artifact) :
    Option (CheckedArtifactEvidence artifact surface) :=
  match functionsAccepted : checkFunctions? artifact surface.functions with
  | none => none
  | some functions =>
      match moduleUsesAccepted : checkModuleUses? artifact surface.moduleUses with
      | none => none
      | some moduleUses => some ⟨functions, functionsAccepted, moduleUses,
          moduleUsesAccepted⟩

end Lanius.Extraction.ResolutionEvidenceChecker
