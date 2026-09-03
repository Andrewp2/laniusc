import Lanius.Extraction.VerifiedFrontend.Context.Base
import Lanius.Extraction.VerifiedFrontend.Context.Supported.Unit0
import Lanius.Extraction.VerifiedFrontend.Context.Supported.Unit1
import Lanius.Extraction.VerifiedFrontend.Context.Supported.Unit2
import Lanius.Extraction.VerifiedFrontend.Context.Supported.Unit3
import Lanius.Extraction.VerifiedFrontend.Context.Supported.Unit4
import Lanius.Extraction.VerifiedFrontend.Context.Supported.Unit5
import Lanius.Extraction.VerifiedFrontend.Context.Supported.Unit6
import Lanius.Extraction.VerifiedFrontend.Context.Supported.Unit7
import Lanius.Extraction.VerifiedFrontend.Context.Supported.Unit8
namespace Lanius.Extraction
set_option maxRecDepth 100000
theorem verifiedFrontendPack_context_supported_kernel :
    ArtifactPackContextChecker.packItemsSupported
      verifiedFrontendPackDecodedUnitsKernel = true := by
  unfold ArtifactPackContextChecker.packItemsSupported
    verifiedFrontendPackDecodedUnitsKernel verifiedFrontendPackDecodedKernel
    verifiedFrontendPackDecodedExplicitKernel
  simp only [verifiedFrontendLexerProgramUnitKernel,
    verifiedFrontendTokenScanProgramUnitKernel,
    verifiedFrontendDigitsProgramUnitKernel,
    verifiedFrontendTokenProgramUnitKernel,
    verifiedFrontendCanonicalTokensProgramUnitKernel,
    verifiedFrontendDecimalProgramUnitKernel,
    verifiedFrontendNumberProgramUnitKernel,
    verifiedFrontendSymbolProgramUnitKernel,
    verifiedFrontendRawLexerProgramUnitKernel, List.all_cons, List.all_nil]
  simp only [Bool.and_eq_true]
  exact ⟨verifiedFrontendLexer_context_items_supported_kernel,
    verifiedFrontendTokenScan_context_items_supported_kernel,
    verifiedFrontendDigits_context_items_supported_kernel,
    verifiedFrontendToken_context_items_supported_kernel,
    verifiedFrontendCanonicalTokens_context_items_supported_kernel,
    verifiedFrontendDecimal_context_items_supported_kernel,
    verifiedFrontendNumber_context_items_supported_kernel,
    verifiedFrontendSymbol_context_items_supported_kernel,
    verifiedFrontendRawLexer_context_items_supported_kernel, trivial⟩
end Lanius.Extraction
