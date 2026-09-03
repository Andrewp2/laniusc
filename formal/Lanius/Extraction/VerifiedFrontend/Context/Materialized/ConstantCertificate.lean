import Lanius.Extraction.VerifiedFrontend.Context.Materialized.DeclarationCertificate
import Lanius.Extraction.VerifiedFrontend.Context.Tables.ConstantsCertificate

namespace Lanius.Extraction

theorem verifiedFrontendPackConstantContextMaterializedKernel_eq :
    verifiedFrontendPackConstantContextMaterializedKernel =
      verifiedFrontendPackConstantContextKernel := by
  have constants := verifiedFrontendPackContextTablesLiteralKernel_constants_eq
  change verifiedFrontendPackContextTablesLiteralKernel.constants =
    verifiedFrontendPackContextConstantsKernel at constants
  unfold verifiedFrontendPackConstantContextMaterializedKernel
    verifiedFrontendPackConstantContextKernel
  rw [verifiedFrontendPackDeclarationContextMaterializedKernel_eq]
  rw [constants]

end Lanius.Extraction
