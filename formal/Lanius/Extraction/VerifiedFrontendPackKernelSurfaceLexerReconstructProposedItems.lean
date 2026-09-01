import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructProposedParse

namespace Lanius.Extraction

set_option maxRecDepth 100000

theorem verifiedFrontendLexer_proposed_items_kernel :
    verifiedFrontendLexerProposedKernel.value.items =
      verifiedFrontendLexerProposedItemsKernel := by rfl

end Lanius.Extraction
