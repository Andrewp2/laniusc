import Lanius.Extraction.VerifiedFrontendPackKernelContextMaterialized

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0

theorem verifiedFrontendSymbol_unit_checked_kernel :
    (ArtifactPackContextChecker.checkUnit? verifiedFrontendPackContextMaterializedKernel
      verifiedFrontendSymbolProgramUnitKernel).isSome = true := by
  with_unfolding_all rfl

def verifiedFrontendSymbolUnitKernel :=
  (ArtifactPackContextChecker.checkUnit? verifiedFrontendPackContextMaterializedKernel
    verifiedFrontendSymbolProgramUnitKernel).get verifiedFrontendSymbol_unit_checked_kernel

theorem verifiedFrontendSymbolUnitKernel_eq :
    ArtifactPackContextChecker.checkUnit? verifiedFrontendPackContextMaterializedKernel
        verifiedFrontendSymbolProgramUnitKernel =
      some verifiedFrontendSymbolUnitKernel :=
  parseOptionEqSomeGet verifiedFrontendSymbol_unit_checked_kernel

end Lanius.Extraction
