import Lanius.Extraction.VerifiedFrontend.Context.Materialized.Assembly
import Lanius.Extraction.VerifiedFrontend.Context.Tables.HeadersCertificate

namespace Lanius.Extraction

set_option maxRecDepth 100000

private theorem certifiedTypeContext_eq
    (targetLeft targetRight : Lanius.Core.Target)
    (targetEq : targetLeft = targetRight)
    (namesLeft namesRight : Lanius.Names.Environment)
    (namesEq : namesLeft = namesRight)
    (modulesLeft : Lanius.Names.ModulesHaveUniquePaths namesLeft)
    (modulesRight : Lanius.Names.ModulesHaveUniquePaths namesRight)
    (symbolsLeft : Lanius.Names.SymbolsAreUnique namesLeft)
    (symbolsRight : Lanius.Names.SymbolsAreUnique namesRight)
    (schemesLeft schemesRight : List Lanius.Static.NominalScheme)
    (schemesEq : schemesLeft = schemesRight)
    (instancesLeft instancesRight : List Lanius.Static.NominalInstance)
    (instancesEq : instancesLeft = instancesRight)
    (aliasesLeft aliasesRight : List Lanius.SurfaceElaboration.TypeAliasEntry)
    (aliasesEq : aliasesLeft = aliasesRight) :
    ({
      target := targetLeft
      names := namesLeft
      modulesHaveUniquePaths := some ⟨modulesLeft⟩
      symbolsAreUnique := some ⟨symbolsLeft⟩
      currentModule := 0
      monomorphization := ArtifactContextChecker.monomorphizationFrom instancesLeft
      nominalSchemes := schemesLeft
      nominalInstances := instancesLeft
      typeAliases := aliasesLeft
    } : Lanius.SurfaceElaboration.Context) =
    ({
      target := targetRight
      names := namesRight
      modulesHaveUniquePaths := some ⟨modulesRight⟩
      symbolsAreUnique := some ⟨symbolsRight⟩
      currentModule := 0
      monomorphization := ArtifactContextChecker.monomorphizationFrom instancesRight
      nominalSchemes := schemesRight
      nominalInstances := instancesRight
      typeAliases := aliasesRight
    } : Lanius.SurfaceElaboration.Context) := by
  subst targetRight
  subst namesRight
  subst schemesRight
  subst instancesRight
  subst aliasesRight
  rfl

theorem verifiedFrontendPackTypeContextMaterializedKernel_eq :
    verifiedFrontendPackTypeContextMaterializedKernel =
      verifiedFrontendPackTypeContextKernel := by
  have schemes := congrArg (fun value => value.1)
    verifiedFrontendPackContextTablesLiteralKernel_headers_eq
  have instances := congrArg (fun value => value.2.1)
    verifiedFrontendPackContextTablesLiteralKernel_headers_eq
  have aliases := congrArg (fun value => value.2.2)
    verifiedFrontendPackContextTablesLiteralKernel_headers_eq
  unfold verifiedFrontendPackTypeContextMaterializedKernel
    verifiedFrontendPackTypeContextKernel
  apply certifiedTypeContext_eq
  · rfl
  · exact verifiedFrontendPackContextNamesLiteralKernel_eq
  · exact schemes
  · exact instances
  · exact aliases

end Lanius.Extraction
