import Lanius.Extraction.VerifiedFrontendPackKernelContextMaterializedConstantCertificate
import Lanius.Extraction.ArtifactPackContextPhaseChunks

namespace Lanius.Extraction

def verifiedFrontendPackMaterializedFunctionHeaders
    (offset count : Nat) : ArtifactContextChecker.FunctionHeaders :=
  ⟨(verifiedFrontendPackContextTablesLiteralKernel.functions.drop offset).take count,
    (verifiedFrontendPackContextTablesLiteralKernel.functionInstances.drop offset).take count⟩

end Lanius.Extraction
