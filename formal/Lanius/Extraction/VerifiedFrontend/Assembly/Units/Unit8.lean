import Lanius.Extraction.VerifiedFrontend.Context.Materialized.Assembly

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0

theorem verifiedFrontendRawLexer_unit_checked_kernel :
    (ArtifactPackContextChecker.checkUnit? verifiedFrontendPackContextMaterializedKernel
      verifiedFrontendRawLexerProgramUnitKernel).isSome = true := by
  with_unfolding_all rfl

def verifiedFrontendRawLexerUnitKernel :=
  (ArtifactPackContextChecker.checkUnit? verifiedFrontendPackContextMaterializedKernel
    verifiedFrontendRawLexerProgramUnitKernel).get verifiedFrontendRawLexer_unit_checked_kernel

theorem verifiedFrontendRawLexerUnitKernel_eq :
    ArtifactPackContextChecker.checkUnit? verifiedFrontendPackContextMaterializedKernel
        verifiedFrontendRawLexerProgramUnitKernel =
      some verifiedFrontendRawLexerUnitKernel :=
  parseOptionEqSomeGet verifiedFrontendRawLexer_unit_checked_kernel

end Lanius.Extraction
