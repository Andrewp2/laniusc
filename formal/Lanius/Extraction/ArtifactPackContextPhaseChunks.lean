import Lanius.Extraction.ArtifactPackContextChecker
namespace Lanius.Extraction.ArtifactPackContextChecker
open ArtifactContextChecker
theorem collectPackImports_cons_of
    (units : List ProgramUnit) (head : ProgramUnit) (tail : List ProgramUnit)
    (headImports restImports : List Names.Import)
    (headFound : collectUnitImports units head head.surface.items = some headImports)
    (restFound : collectPackImports units tail = some restImports) :
    collectPackImports units (head :: tail) = some (headImports ++ restImports) := by
  simp only [collectPackImports, headFound, restFound, Option.bind_eq_bind]
  rfl

def PackHeaders.append (head tail : PackHeaders) : PackHeaders := {
  symbols := head.symbols ++ tail.symbols
  nominalSchemes := head.nominalSchemes ++ tail.nominalSchemes
  nominalInstances := head.nominalInstances ++ tail.nominalInstances
  typeAliases := head.typeAliases ++ tail.typeAliases
}

def buildUnitHeaders (allocation : UnitAllocation) : Option PackHeaders := do
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
  pure {
    symbols := nominal.symbols ++ aliasHeaders.symbols ++
      constantSymbols ++ functionSymbols
    nominalSchemes := nominal.schemes
    nominalInstances := nominal.instances
    typeAliases := aliasHeaders.entries
  }

theorem buildPackHeaders_cons_of
    (allocation : UnitAllocation) (tail : List UnitAllocation)
    (headHeaders tailHeaders : PackHeaders)
    (headFound : buildUnitHeaders allocation = some headHeaders)
    (tailFound : buildPackHeaders tail = some tailHeaders) :
    buildPackHeaders (allocation :: tail) =
      some (headHeaders.append tailHeaders) := by
  unfold buildUnitHeaders at headFound
  dsimp only at headFound
  unfold buildPackHeaders
  simp only [tailFound]
  generalize nominalFound :
    buildNominalHeaders allocation.unit.moduleId
      allocation.structureDeclarationStart allocation.structureTypeStart
      (collectStructures allocation.unit.surface.items)
      allocation.unit.core.structures = nominal at headFound ⊢
  cases nominal with
  | none => simp_all
  | some nominal =>
      simp at headFound
      subst headHeaders
      simp [PackHeaders.append, List.append_assoc]

def appendStructDetails
    (head tail : ArtifactContextChecker.StructDetails) :
    ArtifactContextChecker.StructDetails :=
  ⟨head.fields ++ tail.fields, head.constructors ++ tail.constructors⟩

theorem buildPackStructDetails_cons_of
    (context : SurfaceElaboration.Context) (allocation : UnitAllocation)
    (tail : List UnitAllocation)
    (headDetails tailDetails : ArtifactContextChecker.StructDetails)
    (headFound : buildStructDetails
      (context.forModule allocation.unit.moduleId)
      allocation.structureDeclarationStart allocation.structureTypeStart
      (collectStructures allocation.unit.surface.items)
      allocation.unit.core.structures = some headDetails)
    (tailFound : buildPackStructDetails context tail = some tailDetails) :
    buildPackStructDetails context (allocation :: tail) =
      some (appendStructDetails headDetails tailDetails) := by
  simp only [buildPackStructDetails, headFound, tailFound]
  rfl

theorem buildPackConstants_cons_of
    (context : SurfaceElaboration.Context) (allocation : UnitAllocation)
    (tail : List UnitAllocation)
    (headConstants tailConstants : List SurfaceElaboration.ConstantEntry)
    (headFound : buildConstantEntries
      (context.forModule allocation.unit.moduleId)
      allocation.constantDeclarationStart
      (collectConstants allocation.unit.surface.items)
      allocation.unit.core.constants = some headConstants)
    (tailFound : buildPackConstants context tail = some tailConstants) :
    buildPackConstants context (allocation :: tail) =
      some (headConstants ++ tailConstants) := by
  simp only [buildPackConstants, headFound, tailFound]
  rfl

def appendFunctionHeaders
    (head tail : ArtifactContextChecker.FunctionHeaders) :
    ArtifactContextChecker.FunctionHeaders :=
  ⟨head.schemes ++ tail.schemes, head.instances ++ tail.instances⟩

theorem buildPackFunctions_cons_of
    (context : SurfaceElaboration.Context) (allocation : UnitAllocation)
    (tail : List UnitAllocation)
    (headFunctions tailFunctions : ArtifactContextChecker.FunctionHeaders)
    (headFound : buildFunctionHeaders
      (context.forModule allocation.unit.moduleId)
      allocation.functionDeclarationStart
      (collectFunctions allocation.unit.surface.items)
      allocation.unit.core.functions = some headFunctions)
    (tailFound : buildPackFunctions context tail = some tailFunctions) :
    buildPackFunctions context (allocation :: tail) =
      some (appendFunctionHeaders headFunctions tailFunctions) := by
  simp only [buildPackFunctions, headFound, tailFound]
  rfl
end Lanius.Extraction.ArtifactPackContextChecker
