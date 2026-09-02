import Lanius.Extraction.VerifiedFrontendPackKernelContextMaterialized

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0

theorem verifiedFrontendLexer_unit_checked_kernel :
    (ArtifactPackContextChecker.checkUnit? verifiedFrontendPackContextMaterializedKernel
      verifiedFrontendLexerProgramUnitKernel).isSome = true := by
  with_unfolding_all rfl

def verifiedFrontendLexerUnitKernel :=
  (ArtifactPackContextChecker.checkUnit? verifiedFrontendPackContextMaterializedKernel
    verifiedFrontendLexerProgramUnitKernel).get verifiedFrontendLexer_unit_checked_kernel

theorem verifiedFrontendLexerUnitKernel_eq :
    ArtifactPackContextChecker.checkUnit? verifiedFrontendPackContextMaterializedKernel
        verifiedFrontendLexerProgramUnitKernel =
      some verifiedFrontendLexerUnitKernel :=
  parseOptionEqSomeGet verifiedFrontendLexer_unit_checked_kernel

end Lanius.Extraction
