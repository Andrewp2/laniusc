import Lanius.Extraction.VerifiedFrontend.Context.Target
import Lanius.Extraction.VerifiedFrontend.Context.Headers.Assembly
import Lanius.Extraction.VerifiedFrontend.Context.Imports.Assembly

namespace Lanius.Extraction

def verifiedFrontendPackContextNamesKernel : Lanius.Names.Environment := {
  modules := verifiedFrontendPackDecodedUnitsKernel.map (fun unit => unit.module)
  symbols := verifiedFrontendPackContextHeadersKernel.symbols
  imports := verifiedFrontendPackContextImportsKernel
}

end Lanius.Extraction
