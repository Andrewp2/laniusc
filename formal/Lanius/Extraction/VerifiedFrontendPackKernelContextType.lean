import Lanius.Extraction.VerifiedFrontendPackKernelContextNamesCache

namespace Lanius.Extraction

def verifiedFrontendPackTypeContextKernel : Lanius.SurfaceElaboration.Context := {
  target := verifiedFrontendPackContextTargetKernel
  names := verifiedFrontendPackContextNamesKernel
  modulesHaveUniquePaths :=
    some ⟨verifiedFrontendPackContextModuleNamesUniqueKernel⟩
  symbolsAreUnique := some ⟨verifiedFrontendPackContextSymbolNamesUniqueKernel⟩
  currentModule := 0
  monomorphization := ArtifactContextChecker.monomorphizationFrom
    verifiedFrontendPackContextHeadersKernel.nominalInstances
  nominalSchemes := verifiedFrontendPackContextHeadersKernel.nominalSchemes
  nominalInstances := verifiedFrontendPackContextHeadersKernel.nominalInstances
  typeAliases := verifiedFrontendPackContextHeadersKernel.typeAliases
}

theorem verifiedFrontendPackTypeContextKernel_of_evidence
    (moduleNames : SurfaceElaborationChecker.Evidence
      (Lanius.Names.ModulesHaveUniquePaths ({
        modules := verifiedFrontendPackDecodedUnitsKernel.map (fun unit => unit.module)
        symbols := verifiedFrontendPackContextHeadersKernel.symbols
        imports := verifiedFrontendPackContextImportsKernel
      } : Lanius.Names.Environment)))
    (symbolNames : SurfaceElaborationChecker.Evidence
      (Lanius.Names.SymbolsAreUnique ({
        modules := verifiedFrontendPackDecodedUnitsKernel.map (fun unit => unit.module)
        symbols := verifiedFrontendPackContextHeadersKernel.symbols
        imports := verifiedFrontendPackContextImportsKernel
      } : Lanius.Names.Environment))) :
    ({
      target := verifiedFrontendPackContextTargetKernel
      names := ({
        modules := verifiedFrontendPackDecodedUnitsKernel.map (fun unit => unit.module)
        symbols := verifiedFrontendPackContextHeadersKernel.symbols
        imports := verifiedFrontendPackContextImportsKernel
      } : Lanius.Names.Environment)
      modulesHaveUniquePaths := some ⟨moduleNames.proof⟩
      symbolsAreUnique := some ⟨symbolNames.proof⟩
      currentModule := 0
      monomorphization := ArtifactContextChecker.monomorphizationFrom
        verifiedFrontendPackContextHeadersKernel.nominalInstances
      nominalSchemes := verifiedFrontendPackContextHeadersKernel.nominalSchemes
      nominalInstances := verifiedFrontendPackContextHeadersKernel.nominalInstances
      typeAliases := verifiedFrontendPackContextHeadersKernel.typeAliases
    } : Lanius.SurfaceElaboration.Context) =
      verifiedFrontendPackTypeContextKernel := by
  rfl

end Lanius.Extraction
