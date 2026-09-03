import Lanius.Extraction.VerifiedFrontend.Context.Tables.Certificate

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0

theorem verifiedFrontendPackContextTablesLiteralKernel_headers_eq :
    (verifiedFrontendPackContextTablesLiteralKernel.nominalSchemes,
      verifiedFrontendPackContextTablesLiteralKernel.nominalInstances,
      verifiedFrontendPackContextTablesLiteralKernel.typeAliases) =
    (verifiedFrontendPackContextExplicitKernel.nominalSchemes,
      verifiedFrontendPackContextExplicitKernel.nominalInstances,
      verifiedFrontendPackContextExplicitKernel.typeAliases) := by
  with_unfolding_all rfl

end Lanius.Extraction
