import Lanius.Extraction.VerifiedFrontendPackKernelContextMaterialized

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendCanonicalTokens_unit_checked_kernel :
    (ArtifactPackContextChecker.checkUnit? verifiedFrontendPackContextMaterializedKernel
      verifiedFrontendCanonicalTokensProgramUnitKernel).isSome = true := by
  with_unfolding_all rfl

def verifiedFrontendCanonicalTokensUnitKernel :=
  (ArtifactPackContextChecker.checkUnit? verifiedFrontendPackContextMaterializedKernel
    verifiedFrontendCanonicalTokensProgramUnitKernel).get
      verifiedFrontendCanonicalTokens_unit_checked_kernel

theorem verifiedFrontendCanonicalTokensUnitKernel_eq :
    ArtifactPackContextChecker.checkUnit? verifiedFrontendPackContextMaterializedKernel
        verifiedFrontendCanonicalTokensProgramUnitKernel =
      some verifiedFrontendCanonicalTokensUnitKernel :=
  parseOptionEqSomeGet verifiedFrontendCanonicalTokens_unit_checked_kernel

end Lanius.Extraction
