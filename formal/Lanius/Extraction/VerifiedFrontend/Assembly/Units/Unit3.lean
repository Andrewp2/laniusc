import Lanius.Extraction.VerifiedFrontend.Context.Materialized.Assembly

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0

theorem verifiedFrontendToken_unit_checked_kernel :
    (ArtifactPackContextChecker.checkUnit? verifiedFrontendPackContextMaterializedKernel
      verifiedFrontendTokenProgramUnitKernel).isSome = true := by
  with_unfolding_all rfl

def verifiedFrontendTokenUnitKernel :=
  (ArtifactPackContextChecker.checkUnit? verifiedFrontendPackContextMaterializedKernel
    verifiedFrontendTokenProgramUnitKernel).get verifiedFrontendToken_unit_checked_kernel

theorem verifiedFrontendTokenUnitKernel_eq :
    ArtifactPackContextChecker.checkUnit? verifiedFrontendPackContextMaterializedKernel
        verifiedFrontendTokenProgramUnitKernel =
      some verifiedFrontendTokenUnitKernel :=
  parseOptionEqSomeGet verifiedFrontendToken_unit_checked_kernel

end Lanius.Extraction
