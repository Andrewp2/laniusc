import Lanius.Extraction.VerifiedFrontendPackKernelContextTarget
import Lanius.Extraction.VerifiedFrontendPackKernelContextHeaders
import Lanius.Extraction.VerifiedFrontendPackKernelContextImports

namespace Lanius.Extraction

def verifiedFrontendPackContextNamesKernel : Lanius.Names.Environment := {
  modules := verifiedFrontendPackDecodedUnitsKernel.map (fun unit => unit.module)
  symbols := verifiedFrontendPackContextHeadersKernel.symbols
  imports := verifiedFrontendPackContextImportsKernel
}

end Lanius.Extraction
