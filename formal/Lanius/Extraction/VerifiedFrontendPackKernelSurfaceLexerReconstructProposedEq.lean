import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructProposedItems

namespace Lanius.Extraction

set_option maxRecDepth 100000

theorem verifiedFrontendLexer_proposed_eq_reconstructed_kernel :
    verifiedFrontendLexerProposedKernel =
      verifiedFrontendLexerReconstructedKernel := by
  cases proposed : verifiedFrontendLexerProposedKernel with
  | mk id parseNode value =>
      cases value with
      | mk items =>
          have idEq := verifiedFrontendLexer_proposed_id_kernel
          have parseEq := verifiedFrontendLexer_proposed_parse_node_kernel
          have itemsEq := verifiedFrontendLexer_proposed_items_kernel
          simp only [proposed] at idEq parseEq itemsEq
          subst id
          subst parseNode
          subst items
          rfl

end Lanius.Extraction
