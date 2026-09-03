import Lanius.Extraction.VerifiedFrontend.Context.Materialized.Assembly

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0

theorem verifiedFrontendDecimal_unit_checked_kernel :
    (ArtifactPackContextChecker.checkUnit? verifiedFrontendPackContextMaterializedKernel
      verifiedFrontendDecimalProgramUnitKernel).isSome = true := by
  with_unfolding_all rfl

def verifiedFrontendDecimalUnitKernel :=
  (ArtifactPackContextChecker.checkUnit? verifiedFrontendPackContextMaterializedKernel
    verifiedFrontendDecimalProgramUnitKernel).get verifiedFrontendDecimal_unit_checked_kernel

theorem verifiedFrontendDecimalUnitKernel_eq :
    ArtifactPackContextChecker.checkUnit? verifiedFrontendPackContextMaterializedKernel
        verifiedFrontendDecimalProgramUnitKernel =
      some verifiedFrontendDecimalUnitKernel :=
  parseOptionEqSomeGet verifiedFrontendDecimal_unit_checked_kernel

end Lanius.Extraction
