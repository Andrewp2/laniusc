import Lanius.Extraction.VerifiedFrontend.Context.Materialized.Assembly

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0

theorem verifiedFrontendNumber_unit_checked_kernel :
    (ArtifactPackContextChecker.checkUnit? verifiedFrontendPackContextMaterializedKernel
      verifiedFrontendNumberProgramUnitKernel).isSome = true := by
  with_unfolding_all rfl

def verifiedFrontendNumberUnitKernel :=
  (ArtifactPackContextChecker.checkUnit? verifiedFrontendPackContextMaterializedKernel
    verifiedFrontendNumberProgramUnitKernel).get verifiedFrontendNumber_unit_checked_kernel

theorem verifiedFrontendNumberUnitKernel_eq :
    ArtifactPackContextChecker.checkUnit? verifiedFrontendPackContextMaterializedKernel
        verifiedFrontendNumberProgramUnitKernel =
      some verifiedFrontendNumberUnitKernel :=
  parseOptionEqSomeGet verifiedFrontendNumber_unit_checked_kernel

end Lanius.Extraction
