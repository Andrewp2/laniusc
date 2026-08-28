import Lanius.Extraction.ArtifactContextChecker
import Lanius.Extraction.ArtifactPackContextChecker
import Lanius.Extraction.ResolutionEvidenceChecker
import Lanius.Extraction.SurfaceDecode

namespace Lanius.Extraction.GlobalResolutionEvidenceChecker

open Lanius
open Lanius.Extraction
open Lanius.Extraction.ScopedSurface
open Lanius.Extraction.ResolutionEvidenceChecker
open Lanius.Extraction.SurfaceElaborationChecker
open Lanius.ScopeGraph

/-!
The lexical checker proves when lookup must leave the function. This checker
then invokes the existing proof-producing module/global resolver and connects
its selected symbol back to the located declaration named by the artifact row.

This first entry point covers one source unit. The same relation is reusable
for packs once their checked module IDs are threaded through `ScopedSurface`.
-/

def itemMatchesSymbol (symbol : Names.Symbol) (item : SurfaceItem) : Bool :=
  match symbol.lookupNamespace, item.value with
  | .value, .function function => function.name.text == symbol.name
  | .value, .constant name _ _ _ => name.text == symbol.name
  | .type, .structure declaration => declaration.name.text == symbol.name
  | .type, .type_alias name _ _ => name.text == symbol.name
  | _, _ => false

def itemsForSymbol (surface : SurfaceFile) (symbol : Names.Symbol) :
    List SurfaceItem :=
  surface.value.items.filter (itemMatchesSymbol symbol)

inductive CheckedUseGlobalEvidence
    (artifact : Artifact) (context : SurfaceElaboration.Context)
    (surface : SurfaceFile) (graph : Graph) (use : CheckedUse graph) where
  | lexical
      (checked : CheckedReference graph use.reference)
      (outcome : use.resolution = .local checked)
  | global
      (noLocal : resolve? graph use.reference = none)
      (outcome : use.resolution = .global noLocal)
      (path : Surface.Path)
      (pathDecoded :
        decodeSurfacePath (artifact.tokens.length + 1) use.sourcePath = some path)
      (resolved : ResolvedLocalGlobal context use.reference.lookupNamespace
        path)
      (declaration : SurfaceItem)
      (uniqueDeclaration : itemsForSymbol surface resolved.symbol = [declaration])
      (row : ResolutionEvidence)
      (uniqueRow : rowsForUse artifact use.reference.node = [row])
      (sameUnit : row.declaration_unit = context.currentModule)
      (sameNode : row.declaration_node = declaration.id)

def checkUse? (artifact : Artifact) (context : SurfaceElaboration.Context)
    (surface : SurfaceFile) (use : CheckedUse graph) :
    Option (CheckedUseGlobalEvidence artifact context surface graph use) :=
  match outcome : use.resolution with
  | .local checked => some (.lexical checked outcome)
  | .global noLocal => do
      match pathDecoded :
          decodeSurfacePath (artifact.tokens.length + 1) use.sourcePath with
      | none => none
      | some path => do
          let resolved ← resolveGlobal? context use.reference.lookupNamespace path
          match uniqueDeclaration : itemsForSymbol surface resolved.symbol with
          | [declaration] =>
              match uniqueRow : rowsForUse artifact use.reference.node with
              | [row] =>
                  if sameUnit : row.declaration_unit = context.currentModule then
                    if sameNode : row.declaration_node = declaration.id then
                      some (.global noLocal outcome path pathDecoded resolved
                        declaration uniqueDeclaration row uniqueRow sameUnit sameNode)
                    else none
                  else none
              | _ => none
          | _ => none

def checkUses? (artifact : Artifact) (context : SurfaceElaboration.Context)
    (surface : SurfaceFile) (graph : Graph) :
    (uses : List (CheckedUse graph)) →
      Option (List (Sigma fun use =>
        CheckedUseGlobalEvidence artifact context surface graph use))
  | [] => some []
  | use :: tail => do
      let head ← checkUse? artifact context surface use
      let rest ← checkUses? artifact context surface graph tail
      pure (⟨use, head⟩ :: rest)

def checkFunctions? (artifact : Artifact) (context : SurfaceElaboration.Context)
    (surface : SurfaceFile) :
    (functions : List CheckedFunction) →
      Option (List (Sigma fun function : CheckedFunction => List (Sigma fun use =>
        CheckedUseGlobalEvidence artifact context surface function.graph use)))
  | [] => some []
  | function :: tail => do
      let uses ← checkUses? artifact context surface function.graph function.uses
      let rest ← checkFunctions? artifact context surface tail
      pure (⟨function, uses⟩ :: rest)

structure CheckedModuleUseGlobalEvidence
    (artifact : Artifact) (context : SurfaceElaboration.Context)
    (surface : SurfaceFile) (use : ModuleUse) where
  path : Surface.Path
  pathDecoded :
    decodeSurfacePath (artifact.tokens.length + 1) use.sourcePath = some path
  resolved : ResolvedLocalGlobal context (referenceNamespace use.target) path
  declaration : SurfaceItem
  uniqueDeclaration : itemsForSymbol surface resolved.symbol = [declaration]
  row : ResolutionEvidence
  uniqueRow : rowsForUse artifact use.node = [row]
  sameUnit : row.declaration_unit = context.currentModule
  sameNode : row.declaration_node = declaration.id

def checkModuleUse? (artifact : Artifact) (context : SurfaceElaboration.Context)
    (surface : SurfaceFile) (use : ModuleUse) :
    Option (CheckedModuleUseGlobalEvidence artifact context surface use) := do
  match pathDecoded :
      decodeSurfacePath (artifact.tokens.length + 1) use.sourcePath with
  | none => none
  | some path => do
      let resolved ← resolveGlobal? context (referenceNamespace use.target) path
      match uniqueDeclaration : itemsForSymbol surface resolved.symbol with
      | [declaration] =>
          match uniqueRow : rowsForUse artifact use.node with
          | [row] =>
              if sameUnit : row.declaration_unit = context.currentModule then
                if sameNode : row.declaration_node = declaration.id then
                  some ⟨path, pathDecoded, resolved, declaration,
                    uniqueDeclaration, row, uniqueRow, sameUnit, sameNode⟩
                else none
              else none
          | _ => none
      | _ => none

def checkModuleUses? (artifact : Artifact)
    (context : SurfaceElaboration.Context) (surface : SurfaceFile) :
    (uses : List ModuleUse) → Option (List (Sigma fun use =>
      CheckedModuleUseGlobalEvidence artifact context surface use))
  | [] => some []
  | use :: tail => do
      let head ← checkModuleUse? artifact context surface use
      let rest ← checkModuleUses? artifact context surface tail
      pure (⟨use, head⟩ :: rest)

structure CheckedSingleArtifact (artifact : Artifact)
    (surface : ScopedSurface.CheckedArtifact artifact) where
  program : ArtifactContextChecker.CheckedArtifactProgram artifact
  lexical : CheckedArtifactEvidence artifact surface
  functions : List (Sigma fun function : CheckedFunction => List (Sigma fun use =>
    CheckedUseGlobalEvidence artifact program.checked.context surface.source
      function.graph use))
  functionsAccepted :
    checkFunctions? artifact program.checked.context surface.source
      surface.functions = some functions
  moduleUses : List (Sigma fun use =>
    CheckedModuleUseGlobalEvidence artifact program.checked.context
      surface.source use)
  moduleUsesAccepted :
    checkModuleUses? artifact program.checked.context surface.source
      surface.moduleUses = some moduleUses

def extendCheckedSurface? (artifact : Artifact)
    (surface : ScopedSurface.CheckedArtifact artifact) :
    Option (CheckedSingleArtifact artifact surface) := do
  let program ← ArtifactContextChecker.checkArtifactProgram? artifact
  -- Both views are independently tied to `artifact`; no decoded syntax is
  -- accepted as an authority for the located declaration identity.
  let lexical ← ResolutionEvidenceChecker.checkArtifact? artifact surface
  match functionsAccepted : checkFunctions? artifact program.checked.context
      surface.source surface.functions with
  | none => none
  | some functions =>
      match moduleUsesAccepted : checkModuleUses? artifact
          program.checked.context surface.source surface.moduleUses with
      | none => none
      | some moduleUses => some ⟨program, lexical, functions,
          functionsAccepted, moduleUses, moduleUsesAccepted⟩

def checkSingleArtifact? (artifact : Artifact) :
    Option (Sigma fun surface : ScopedSurface.CheckedArtifact artifact =>
      CheckedSingleArtifact artifact surface) := do
  let surface ← ScopedSurface.checkArtifact? artifact
  let checked ← extendCheckedSurface? artifact surface
  pure ⟨surface, checked⟩

/-! ## Dependency-ready source packs -/

def surfaceForModule? (pack : ArtifactPack) (moduleId : ModuleId) :
    Option SurfaceFile := do
  let artifact ← pack.units[moduleId]?
  artifact.surface

inductive CheckedPackUseGlobalEvidence
    (pack : ArtifactPack) (artifact : Artifact)
    (context : SurfaceElaboration.Context)
    (graph : Graph) (use : CheckedUse graph) where
  | lexical
      (checked : CheckedReference graph use.reference)
      (outcome : use.resolution = .local checked)
  | global
      (noLocal : resolve? graph use.reference = none)
      (outcome : use.resolution = .global noLocal)
      (path : Surface.Path)
      (pathDecoded :
        decodeSurfacePath (artifact.tokens.length + 1) use.sourcePath = some path)
      (resolved : ResolvedLocalGlobal context use.reference.lookupNamespace
        path)
      (declarationSurface : SurfaceFile)
      (surfaceFound :
        surfaceForModule? pack resolved.symbol.moduleId = some declarationSurface)
      (declaration : SurfaceItem)
      (uniqueDeclaration :
        itemsForSymbol declarationSurface resolved.symbol = [declaration])
      (row : ResolutionEvidence)
      (uniqueRow : rowsForUse artifact use.reference.node = [row])
      (sameUnit : row.declaration_unit = resolved.symbol.moduleId)
      (sameNode : row.declaration_node = declaration.id)

def checkPackUse? (pack : ArtifactPack) (artifact : Artifact)
    (context : SurfaceElaboration.Context) (use : CheckedUse graph) :
    Option (CheckedPackUseGlobalEvidence pack artifact context graph use) :=
  match outcome : use.resolution with
  | .local checked => some (.lexical checked outcome)
  | .global noLocal => do
      match pathDecoded :
          decodeSurfacePath (artifact.tokens.length + 1) use.sourcePath with
      | none => none
      | some path => do
          let resolved ← resolveGlobal? context use.reference.lookupNamespace path
          match surfaceFound : surfaceForModule? pack resolved.symbol.moduleId with
          | none => none
          | some declarationSurface =>
              match uniqueDeclaration :
                  itemsForSymbol declarationSurface resolved.symbol with
              | [declaration] =>
                  match uniqueRow : rowsForUse artifact use.reference.node with
                  | [row] =>
                      if sameUnit : row.declaration_unit = resolved.symbol.moduleId then
                        if sameNode : row.declaration_node = declaration.id then
                          some (.global noLocal outcome path pathDecoded resolved
                            declarationSurface surfaceFound declaration
                            uniqueDeclaration row uniqueRow sameUnit sameNode)
                        else none
                      else none
                  | _ => none
              | _ => none

def checkPackUses? (pack : ArtifactPack) (artifact : Artifact)
    (context : SurfaceElaboration.Context) (graph : Graph) :
    (uses : List (CheckedUse graph)) →
      Option (List (Sigma fun use =>
        CheckedPackUseGlobalEvidence pack artifact context graph use))
  | [] => some []
  | use :: tail => do
      let head ← checkPackUse? pack artifact context use
      let rest ← checkPackUses? pack artifact context graph tail
      pure (⟨use, head⟩ :: rest)

def checkPackFunctions? (pack : ArtifactPack) (artifact : Artifact)
    (context : SurfaceElaboration.Context) :
    (functions : List CheckedFunction) →
      Option (List (Sigma fun function : CheckedFunction =>
        List (Sigma fun use => CheckedPackUseGlobalEvidence pack artifact
          context function.graph use)))
  | [] => some []
  | function :: tail => do
      let uses ←
        checkPackUses? pack artifact context function.graph function.uses
      let rest ← checkPackFunctions? pack artifact context tail
      pure (⟨function, uses⟩ :: rest)

structure CheckedPackModuleUseGlobalEvidence
    (pack : ArtifactPack) (artifact : Artifact)
    (context : SurfaceElaboration.Context) (use : ModuleUse) where
  path : Surface.Path
  pathDecoded :
    decodeSurfacePath (artifact.tokens.length + 1) use.sourcePath = some path
  resolved : ResolvedLocalGlobal context (referenceNamespace use.target) path
  declarationSurface : SurfaceFile
  surfaceFound :
    surfaceForModule? pack resolved.symbol.moduleId = some declarationSurface
  declaration : SurfaceItem
  uniqueDeclaration :
    itemsForSymbol declarationSurface resolved.symbol = [declaration]
  row : ResolutionEvidence
  uniqueRow : rowsForUse artifact use.node = [row]
  sameUnit : row.declaration_unit = resolved.symbol.moduleId
  sameNode : row.declaration_node = declaration.id

def checkPackModuleUse? (pack : ArtifactPack) (artifact : Artifact)
    (context : SurfaceElaboration.Context) (use : ModuleUse) :
    Option (CheckedPackModuleUseGlobalEvidence pack artifact context use) := do
  match pathDecoded :
      decodeSurfacePath (artifact.tokens.length + 1) use.sourcePath with
  | none => none
  | some path => do
      let resolved ← resolveGlobal? context (referenceNamespace use.target) path
      match surfaceFound : surfaceForModule? pack resolved.symbol.moduleId with
      | none => none
      | some declarationSurface =>
          match uniqueDeclaration :
              itemsForSymbol declarationSurface resolved.symbol with
          | [declaration] =>
              match uniqueRow : rowsForUse artifact use.node with
              | [row] =>
                  if sameUnit : row.declaration_unit = resolved.symbol.moduleId then
                    if sameNode : row.declaration_node = declaration.id then
                      some ⟨path, pathDecoded, resolved, declarationSurface,
                        surfaceFound, declaration, uniqueDeclaration, row,
                        uniqueRow, sameUnit, sameNode⟩
                    else none
                  else none
              | _ => none
          | _ => none

def checkPackModuleUses? (pack : ArtifactPack) (artifact : Artifact)
    (context : SurfaceElaboration.Context) :
    (uses : List ModuleUse) →
      Option (List (Sigma fun use =>
        CheckedPackModuleUseGlobalEvidence pack artifact context use))
  | [] => some []
  | use :: tail => do
      let head ← checkPackModuleUse? pack artifact context use
      let rest ← checkPackModuleUses? pack artifact context tail
      pure (⟨use, head⟩ :: rest)

/-- All resolution evidence retained for one source-pack unit.  The evidence is
    indexed by the checked located Surface program, so a consumer can recover
    the exact local or cross-module declaration selected for every use. -/
structure CheckedPackUnit (pack : ArtifactPack)
    (context : SurfaceElaboration.Context) (moduleId : ModuleId)
    (artifact : Artifact) where
  surface : ScopedSurface.CheckedArtifact artifact
  lexical : ResolutionEvidenceChecker.CheckedArtifactEvidence artifact surface
  functions : List (Sigma fun function : CheckedFunction =>
    List (Sigma fun use => CheckedPackUseGlobalEvidence pack artifact
      (context.forModule moduleId) function.graph use))
  functionsAccepted :
    checkPackFunctions? pack artifact (context.forModule moduleId)
      surface.functions = some functions
  moduleUses : List (Sigma fun use =>
    CheckedPackModuleUseGlobalEvidence pack artifact
      (context.forModule moduleId) use)
  moduleUsesAccepted :
    checkPackModuleUses? pack artifact (context.forModule moduleId)
      surface.moduleUses = some moduleUses

/-- A dependency-ready pack retains one checked resolution witness for every
    input unit, in the same module order as the artifact list. -/
inductive CheckedPackUnits (pack : ArtifactPack)
    (context : SurfaceElaboration.Context) : Nat → List Artifact → Type where
  | nil (moduleId : Nat) : CheckedPackUnits pack context moduleId []
  | cons
      (head : CheckedPackUnit pack context moduleId artifact)
      (tail : CheckedPackUnits pack context (moduleId + 1) artifacts) :
      CheckedPackUnits pack context moduleId (artifact :: artifacts)

def checkPackUnitsFrom? (pack : ArtifactPack)
    (context : SurfaceElaboration.Context) :
    (moduleId : Nat) → (artifacts : List Artifact) →
      Option (CheckedPackUnits pack context moduleId artifacts)
  | moduleId, [] => some (.nil moduleId)
  | moduleId, artifact :: tail => do
      let scopedSurface ← ScopedSurface.checkArtifactInUnit? moduleId artifact
      let lexical ←
        ResolutionEvidenceChecker.checkArtifact? artifact scopedSurface
      match functionsAccepted : checkPackFunctions? pack artifact
          (context.forModule moduleId) scopedSurface.functions with
      | none => none
      | some functions =>
          match moduleUsesAccepted : checkPackModuleUses? pack artifact
              (context.forModule moduleId) scopedSurface.moduleUses with
          | none => none
          | some moduleUses => do
              let rest ←
                checkPackUnitsFrom? pack context (moduleId + 1) tail
              pure (.cons {
                surface := scopedSurface
                lexical := lexical
                functions := functions
                functionsAccepted := functionsAccepted
                moduleUses := moduleUses
                moduleUsesAccepted := moduleUsesAccepted
              } rest)

structure CheckedPackResolution (pack : ArtifactPack)
    (context : SurfaceElaboration.Context) where
  units : CheckedPackUnits pack context 0 pack.units

def checkPackResolution? (pack : ArtifactPack)
    (context : SurfaceElaboration.Context) :
    Option (CheckedPackResolution pack context) := do
  let units ← checkPackUnitsFrom? pack context 0 pack.units
  pure ⟨units⟩

end Lanius.Extraction.GlobalResolutionEvidenceChecker
