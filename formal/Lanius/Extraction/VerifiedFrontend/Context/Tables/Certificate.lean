import Lanius.Extraction.VerifiedFrontend.Context.Tables.Assembly

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0

theorem verifiedFrontendPackContextNamesLiteralKernel_eq :
    verifiedFrontendPackContextNamesLiteralKernel =
      verifiedFrontendPackContextNamesKernel := by
  with_unfolding_all rfl

end Lanius.Extraction
