import Lanius.Extraction.VerifiedFrontend.Context.Tables.Certificate

namespace Lanius.Extraction

theorem verifiedFrontendPackContextNamesLiteralModulesUniqueKernel :
    Lanius.Names.ModulesHaveUniquePaths
      verifiedFrontendPackContextNamesLiteralKernel := by
  rw [verifiedFrontendPackContextNamesLiteralKernel_eq]
  exact verifiedFrontendPackContextModuleNamesUniqueKernel

theorem verifiedFrontendPackContextNamesLiteralSymbolsUniqueKernel :
    Lanius.Names.SymbolsAreUnique
      verifiedFrontendPackContextNamesLiteralKernel := by
  rw [verifiedFrontendPackContextNamesLiteralKernel_eq]
  exact verifiedFrontendPackContextSymbolNamesUniqueKernel

/-- Materialized type-context phase. -/
def verifiedFrontendPackTypeContextMaterializedKernel :
    Lanius.SurfaceElaboration.Context := {
  target := .x86_64
  names := verifiedFrontendPackContextNamesLiteralKernel
  modulesHaveUniquePaths :=
    some ⟨verifiedFrontendPackContextNamesLiteralModulesUniqueKernel⟩
  symbolsAreUnique :=
    some ⟨verifiedFrontendPackContextNamesLiteralSymbolsUniqueKernel⟩
  currentModule := 0
  monomorphization := ArtifactContextChecker.monomorphizationFrom
    verifiedFrontendPackContextTablesLiteralKernel.nominalInstances
  nominalSchemes := verifiedFrontendPackContextTablesLiteralKernel.nominalSchemes
  nominalInstances := verifiedFrontendPackContextTablesLiteralKernel.nominalInstances
  typeAliases := verifiedFrontendPackContextTablesLiteralKernel.typeAliases
}

/-- Materialized declaration-context phase. -/
def verifiedFrontendPackDeclarationContextMaterializedKernel :
    Lanius.SurfaceElaboration.Context := {
  verifiedFrontendPackTypeContextMaterializedKernel with
  fields := verifiedFrontendPackContextTablesLiteralKernel.fields
  structConstructors :=
    verifiedFrontendPackContextTablesLiteralKernel.structConstructors
}

/-- Materialized constant-context phase. -/
def verifiedFrontendPackConstantContextMaterializedKernel :
    Lanius.SurfaceElaboration.Context := {
  verifiedFrontendPackDeclarationContextMaterializedKernel with
  constants := verifiedFrontendPackContextTablesLiteralKernel.constants
}

/-- Computational view of the certified final context. All finite tables are
materialized, while proof fields remain opaque certificates. -/
def verifiedFrontendPackContextMaterializedKernel :
    Lanius.SurfaceElaboration.Context := {
  verifiedFrontendPackConstantContextMaterializedKernel with
  functions := verifiedFrontendPackContextTablesLiteralKernel.functions
  functionInstances :=
    verifiedFrontendPackContextTablesLiteralKernel.functionInstances
}

end Lanius.Extraction
