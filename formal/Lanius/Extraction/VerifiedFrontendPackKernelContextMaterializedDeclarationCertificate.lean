import Lanius.Extraction.VerifiedFrontendPackKernelContextTablesStructsCertificate

namespace Lanius.Extraction

theorem verifiedFrontendPackDeclarationContextMaterializedKernel_eq :
    verifiedFrontendPackDeclarationContextMaterializedKernel =
      verifiedFrontendPackDeclarationContextKernel := by
  have fields := congrArg (fun details => details.fields)
    verifiedFrontendPackContextStructDetailsMaterializedKernel_eq
  have constructors := congrArg (fun details => details.constructors)
    verifiedFrontendPackContextStructDetailsMaterializedKernel_eq
  change verifiedFrontendPackContextTablesLiteralKernel.fields =
    verifiedFrontendPackContextStructDetailsKernel.fields at fields
  change verifiedFrontendPackContextTablesLiteralKernel.structConstructors =
    verifiedFrontendPackContextStructDetailsKernel.constructors at constructors
  unfold verifiedFrontendPackDeclarationContextMaterializedKernel
    verifiedFrontendPackDeclarationContextKernel
  rw [verifiedFrontendPackTypeContextMaterializedKernel_eq]
  rw [fields, constructors]

end Lanius.Extraction
