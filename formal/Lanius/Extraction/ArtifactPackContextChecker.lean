import Lanius.Extraction.ArtifactContextChecker
import Lanius.Extraction.ArtifactPackChecker

namespace Lanius.Extraction.ArtifactPackContextChecker

open Lanius
open Lanius.Core
open Lanius.Extraction
open Lanius.SurfaceElaboration
open Lanius.Extraction.ArtifactContextChecker
open Lanius.Extraction.SurfaceElaborationChecker

abbrev Evidence := CoreTyping.Evidence

def declaredModulePath? (surface : Surface.File) : Option Names.ModulePath :=
  match surface.items with
  | .module path :: _ => Declarations.plainPath? path
  | _ => none

structure ProgramUnit where
  artifact : Artifact
  moduleId : ModuleId
  modulePath : Names.ModulePath
  surface : Surface.File
  surfaceDecoded : decodeReconstructedSurface artifact = some surface
  moduleDeclared : declaredModulePath? surface = some modulePath
  core : Core.Program
  coreDecoded : artifact.core_program.map CoreDecode.program = some core

structure DecodedPackUnits (artifacts : List Artifact) where
  units : List ProgramUnit
  artifactsMatch : units.map (·.artifact) = artifacts

def decodePackUnitsFrom :
    (nextModule : ModuleId) → (artifacts : List Artifact) →
      Option (DecodedPackUnits artifacts)
  | _, [] => some ⟨[], rfl⟩
  | nextModule, artifact :: tail =>
      match surfaceFound : decodeReconstructedSurface artifact with
      | none => none
      | some surface =>
          match moduleFound : declaredModulePath? surface with
          | none => none
          | some modulePath =>
              match coreFound : artifact.core_program.map CoreDecode.program with
              | none => none
              | some core => do
                  let rest ← decodePackUnitsFrom (nextModule + 1) tail
                  pure {
                    units := {
                      artifact
                      moduleId := nextModule
                      modulePath
                      surface
                      surfaceDecoded := surfaceFound
                      moduleDeclared := moduleFound
                      core
                      coreDecoded := coreFound
                    } :: rest.units
                    artifactsMatch := by simp [rest.artifactsMatch]
                  }

def decodePackUnits? (pack : ArtifactPack) : Option (DecodedPackUnits pack.units) :=
  decodePackUnitsFrom 0 pack.units

/-- Decode pack-unit metadata from the exact reconstructed Surface values
already returned by `checkArtifactPack?`. -/
def decodePackUnitsFromCached :
    (nextModule : ModuleId) → (artifacts : List Artifact) →
      ArtifactPackChecker.CheckedUnitSurfaces artifacts →
      Option (DecodedPackUnits artifacts)
  | _, [], .nil => some ⟨[], rfl⟩
  | nextModule, artifact :: tail, .cons checkedSurface checkedTail =>
      match moduleFound : declaredModulePath? checkedSurface.surface with
      | none => none
      | some modulePath =>
          match coreFound : artifact.core_program.map CoreDecode.program with
          | none => none
          | some core => do
              let rest ← decodePackUnitsFromCached (nextModule + 1) tail checkedTail
              pure {
                units := {
                  artifact
                  moduleId := nextModule
                  modulePath
                  surface := checkedSurface.surface
                  surfaceDecoded := by
                    rw [← decodeReconstructedSurfaceView_eq artifact
                      checkedSurface.view]
                    exact checkedSurface.surfaceFound
                  moduleDeclared := moduleFound
                  core
                  coreDecoded := coreFound
                } :: rest.units
                artifactsMatch := by simp [rest.artifactsMatch]
              }

def ProgramUnit.module (unit : ProgramUnit) : Names.Module := {
  id := unit.moduleId
  path := unit.modulePath
}

def findModuleByPathInUnits? (units : List ProgramUnit)
    (path : Names.ModulePath) : Option ModuleId := do
  let unit ← units.find? fun unit => unit.modulePath == path
  pure unit.moduleId

def collectUnitImports (units : List ProgramUnit) (current : ProgramUnit) :
    List Surface.Item → Option (List Names.Import)
  | [] => some []
  | .importPath path :: tail => do
      let importedPath ← Declarations.plainPath? path
      let imported ← findModuleByPathInUnits? units importedPath
      if different : imported ≠ current.moduleId then
        let rest ← collectUnitImports units current tail
        pure ({ importer := current.moduleId, imported } :: rest)
      else none
  | .importString _ :: _ => none
  | _ :: tail => collectUnitImports units current tail

def collectPackImports (units : List ProgramUnit) :
    List ProgramUnit → Option (List Names.Import)
  | [] => some []
  | head :: tail => do
      let unitImports ← collectUnitImports units head head.surface.items
      let rest ← collectPackImports units tail
      pure (unitImports ++ rest)

def commonTarget? : List ProgramUnit → Option Core.Target
  | [] => none
  | head :: tail => do
      if tail.all (fun unit => unit.core.target == head.core.target) then
        some head.core.target
      else none

structure UnitAllocation where
  unit : ProgramUnit
  structureDeclarationStart : Nat
  structureTypeStart : TypeId
  typeAliasDeclarationStart : Nat
  constantDeclarationStart : Nat
  functionDeclarationStart : Nat

def totalStructures (units : List ProgramUnit) : Nat :=
  (units.map fun unit => (collectStructures unit.surface.items).length).sum

def totalTypeAliases (units : List ProgramUnit) : Nat :=
  (units.map fun unit => (collectTypeAliases unit.surface.items).length).sum

def totalConstants (units : List ProgramUnit) : Nat :=
  (units.map fun unit => (collectConstants unit.surface.items).length).sum

def allocateUnitsFrom (typeAliasBase constantBase functionBase : Nat) :
    Nat → Nat → Nat → Nat → List ProgramUnit → List UnitAllocation
  | _, _, _, _, [] => []
  | structureCursor, aliasCursor, constantCursor, functionCursor, head :: tail =>
      let structures := (collectStructures head.surface.items).length
      let aliases := (collectTypeAliases head.surface.items).length
      let constants := (collectConstants head.surface.items).length
      let functions := (collectFunctions head.surface.items).length
      {
        unit := head
        structureDeclarationStart := structureCursor
        structureTypeStart := structureCursor
        typeAliasDeclarationStart := typeAliasBase + aliasCursor
        constantDeclarationStart := constantBase + constantCursor
        functionDeclarationStart := functionBase + functionCursor
      } :: allocateUnitsFrom typeAliasBase constantBase functionBase
        (structureCursor + structures) (aliasCursor + aliases)
        (constantCursor + constants) (functionCursor + functions) tail

def allocateUnits (units : List ProgramUnit) : List UnitAllocation :=
  let typeAliasBase := totalStructures units
  let constantBase := typeAliasBase + totalTypeAliases units
  let functionBase := constantBase + totalConstants units
  allocateUnitsFrom typeAliasBase constantBase functionBase 0 0 0 0 units

structure PackHeaders where
  symbols : List Names.Symbol
  nominalSchemes : List Static.NominalScheme
  nominalInstances : List Static.NominalInstance
  typeAliases : List TypeAliasEntry

def buildPackHeaders : List UnitAllocation → Option PackHeaders
  | [] => some ⟨[], [], [], []⟩
  | allocation :: tail => do
      let structures := collectStructures allocation.unit.surface.items
      let aliases := collectTypeAliases allocation.unit.surface.items
      let constants := collectConstants allocation.unit.surface.items
      let functions := collectFunctions allocation.unit.surface.items
      let nominal ← buildNominalHeaders allocation.unit.moduleId
        allocation.structureDeclarationStart allocation.structureTypeStart
        structures allocation.unit.core.structures
      let aliasHeaders := buildTypeAliasHeaders allocation.unit.moduleId
        allocation.typeAliasDeclarationStart aliases
      let constantSymbols := buildConstantSymbols allocation.unit.moduleId
        allocation.constantDeclarationStart constants
      let functionSymbols := buildFunctionSymbols allocation.unit.moduleId
        allocation.functionDeclarationStart functions
      let rest ← buildPackHeaders tail
      pure {
        symbols := nominal.symbols ++ aliasHeaders.symbols ++
          constantSymbols ++ functionSymbols ++ rest.symbols
        nominalSchemes := nominal.schemes ++ rest.nominalSchemes
        nominalInstances := nominal.instances ++ rest.nominalInstances
        typeAliases := aliasHeaders.entries ++ rest.typeAliases
      }

def buildPackStructDetails (context : Context) :
    List UnitAllocation → Option StructDetails
  | [] => some ⟨[], []⟩
  | allocation :: tail => do
      let unitDetails ← buildStructDetails (context.forModule allocation.unit.moduleId)
        allocation.structureDeclarationStart allocation.structureTypeStart
        (collectStructures allocation.unit.surface.items)
        allocation.unit.core.structures
      let rest ← buildPackStructDetails context tail
      pure ⟨unitDetails.fields ++ rest.fields,
        unitDetails.constructors ++ rest.constructors⟩

def buildPackConstants (context : Context) :
    List UnitAllocation → Option (List ConstantEntry)
  | [] => some []
  | allocation :: tail => do
      let unitConstants ← buildConstantEntries
        (context.forModule allocation.unit.moduleId)
        allocation.constantDeclarationStart
        (collectConstants allocation.unit.surface.items)
        allocation.unit.core.constants
      let rest ← buildPackConstants context tail
      pure (unitConstants ++ rest)

def buildPackFunctions (context : Context) :
    List UnitAllocation → Option FunctionHeaders
  | [] => some ⟨[], []⟩
  | allocation :: tail => do
      let unitFunctions ← buildFunctionHeaders
        (context.forModule allocation.unit.moduleId)
        allocation.functionDeclarationStart
        (collectFunctions allocation.unit.surface.items)
        allocation.unit.core.functions
      let rest ← buildPackFunctions context tail
      pure ⟨unitFunctions.schemes ++ rest.schemes,
        unitFunctions.instances ++ rest.instances⟩

def packItemsSupported (units : List ProgramUnit) : Bool :=
  units.all fun unit => supportedSingleModuleItems
    (unit.surface.items.filter fun item =>
      match item with
      | .importPath _ => false
      | _ => true)

/-- Complete context construction after target, names, and name-integrity
certificates have been established. Keeping this phase behind a named boundary
lets generated pack proofs compose cached certificates without re-expanding the
dependent context record at every later phase. -/
def finishPackContext (typeContext : Context)
    (allocations : List UnitAllocation) : Option Context := do
  let details ← buildPackStructDetails typeContext allocations
  let declarationContext : Context := {
    typeContext with
    fields := details.fields
    structConstructors := details.constructors
  }
  let constants ← buildPackConstants declarationContext allocations
  let constantContext : Context := { declarationContext with constants }
  let functions ← buildPackFunctions constantContext allocations
  pure {
    constantContext with
    functions := functions.schemes
    functionInstances := functions.instances
  }

/-- Enter the post-name phase with explicit integrity certificates. -/
def finishCertifiedPackContext (target : Target) (names : Names.Environment)
    (headers : PackHeaders) (allocations : List UnitAllocation)
    (modulePathsUnique : Evidence (Names.ModulesHaveUniquePaths names))
    (symbolsUnique : Evidence (Names.SymbolsAreUnique names)) : Option Context :=
  finishPackContext {
    target
    names
    modulesHaveUniquePaths := some ⟨modulePathsUnique.proof⟩
    symbolsAreUnique := some ⟨symbolsUnique.proof⟩
    currentModule := 0
    monomorphization := monomorphizationFrom headers.nominalInstances
    nominalSchemes := headers.nominalSchemes
    nominalInstances := headers.nominalInstances
    typeAliases := headers.typeAliases
  } allocations

def buildPackContext? (units : List ProgramUnit) : Option Context := do
  if packItemsSupported units then
    let target ← commonTarget? units
    let allocations := allocateUnits units
    let headers ← buildPackHeaders allocations
    let imports ← collectPackImports units units
    let names : Names.Environment := {
      modules := units.map (·.module)
      symbols := headers.symbols
      imports
    }
    let modulePathsUnique ← modulesUniquePaths? names
    let symbolsUnique ← symbolsUnique? names
    finishCertifiedPackContext target names headers allocations
      modulePathsUnique symbolsUnique
  else none

structure CheckedUnit (context : Context) (unit : ProgramUnit) where
  constants : ConstantsChecked (context.forModule unit.moduleId)
    (collectConstants unit.surface.items) unit.core.constants
  functions : FunctionsChecked (context.forModule unit.moduleId)
    (collectFunctions unit.surface.items) unit.core.functions

inductive UnitsChecked (context : Context) : List ProgramUnit → Prop where
  | nil : UnitsChecked context []
  | cons
      (head : CheckedUnit context unit)
      (tail : UnitsChecked context units) :
      UnitsChecked context (unit :: units)

def checkUnit? (context : Context) (unit : ProgramUnit) :
    Option (Evidence (CheckedUnit context unit)) := do
  let localContext := context.forModule unit.moduleId
  let constants ← ArtifactContextChecker.checkConstants localContext
    (collectConstants unit.surface.items) unit.core.constants
  let functions ← ArtifactContextChecker.checkFunctions localContext
    (collectFunctions unit.surface.items) unit.core.functions
  pure ⟨⟨constants.proof, functions.proof⟩⟩

def checkUnits (context : Context) :
    (units : List ProgramUnit) → Option (Evidence (UnitsChecked context units))
  | [] => some ⟨.nil⟩
  | unit :: tail => do
      let checked ← checkUnit? context unit
      let rest ← checkUnits context tail
      pure ⟨.cons checked.proof rest.proof⟩

theorem checkUnits_cons_of
    (headFound : checkUnit? context unit = some checked)
    (tailFound : checkUnits context units = some tail) :
    checkUnits context (unit :: units) =
      some ⟨UnitsChecked.cons checked.proof tail.proof⟩ := by
  simp only [checkUnits, headFound, tailFound, Option.bind_eq_bind,
    Option.bind_some]
  rfl

structure CheckedArtifactPackSemantics (pack : ArtifactPack) where
  structural : ArtifactPackChecker.CheckedArtifactPack pack
  decoded : DecodedPackUnits pack.units
  context : Context
  unitsChecked : UnitsChecked context decoded.units

def checkArtifactPackSemantics? (pack : ArtifactPack) :
    Option (CheckedArtifactPackSemantics pack) := do
  let structural ← ArtifactPackChecker.checkArtifactPack? pack
  let decoded ← decodePackUnitsFromCached 0 pack.units structural.surfaceData
  let context ← buildPackContext? decoded.units
  let checked ← checkUnits context decoded.units
  pure ⟨structural, decoded, context, checked.proof⟩

end Lanius.Extraction.ArtifactPackContextChecker
