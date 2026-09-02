import Lanius.Extraction.VerifiedFrontendPackKernelContextTablesCertificate

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0

theorem verifiedFrontendPackContextTablesLiteralKernel_constants_eq :
    verifiedFrontendPackContextTablesLiteralKernel.constants =
      verifiedFrontendPackContextExplicitKernel.constants := by
  with_unfolding_all rfl

end Lanius.Extraction
