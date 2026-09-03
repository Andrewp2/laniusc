import Lanius.Extraction.VerifiedFrontend.Context.Tables.Functions.Certificate

namespace Lanius.Extraction

theorem verifiedFrontendPackContextMaterializedKernel_eq :
    verifiedFrontendPackContextMaterializedKernel =
      verifiedFrontendPackContextExplicitKernel := by
  have schemes := congrArg (fun headers => headers.schemes)
    verifiedFrontendPackContextFunctionsMaterializedKernel_eq
  have instances := congrArg (fun headers => headers.instances)
    verifiedFrontendPackContextFunctionsMaterializedKernel_eq
  change verifiedFrontendPackContextTablesLiteralKernel.functions =
    verifiedFrontendPackContextFunctionsKernel.schemes at schemes
  change verifiedFrontendPackContextTablesLiteralKernel.functionInstances =
    verifiedFrontendPackContextFunctionsKernel.instances at instances
  unfold verifiedFrontendPackContextMaterializedKernel
    verifiedFrontendPackContextExplicitKernel
  rw [verifiedFrontendPackConstantContextMaterializedKernel_eq]
  rw [schemes, instances]

end Lanius.Extraction
