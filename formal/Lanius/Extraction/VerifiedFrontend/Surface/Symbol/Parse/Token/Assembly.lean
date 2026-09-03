import Lanius.Extraction.VerifiedFrontend.Surface.Symbol.Parse.Token.Header
import Lanius.Extraction.VerifiedFrontend.Surface.Symbol.Parse.Token.Raw
import Lanius.Extraction.VerifiedFrontend.Surface.Symbol.Parse.Token.Canonical
namespace Lanius.Extraction
theorem verifiedFrontendSymbol_token_trace_checked_kernel :
    checkTokenArtifact verifiedFrontendSymbolArtifact = true :=
  checkTokenArtifact_of_trace_phases
    verifiedFrontendSymbol_token_header_trace_checked_kernel
    verifiedFrontendSymbol_token_raw_trace_checked_kernel
    verifiedFrontendSymbol_token_canonical_trace_checked_kernel
end Lanius.Extraction
