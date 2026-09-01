import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructGroup5

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendLexer_reconstruct_items_end_kernel :
    (reconstructItems 6963 verifiedFrontendLexerArtifact 6961).run 1107 =
      some ([], 1107) := by
  cbv

theorem verifiedFrontendLexer_items_node27_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6962 = some 1 := by
  cbv

theorem verifiedFrontendLexer_items_node27_item_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6962 0 = some 6960 := by
  cbv

theorem verifiedFrontendLexer_items_node27_rest_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6962 1 = some 6961 := by
  cbv

theorem verifiedFrontendLexer_reconstruct_items27_kernel :
    (reconstructItems 6964 verifiedFrontendLexerArtifact 6962).run 1017 =
      some ([verifiedFrontendLexerProposedItem27Kernel], 1107) := by
  rw [reconstructItems]
  simp [verifiedFrontendLexer_items_node27_production_kernel,
    verifiedFrontendLexer_items_node27_item_kernel,
    verifiedFrontendLexer_items_node27_rest_kernel,
    verifiedFrontendLexer_reconstruct_item27_kernel,
    verifiedFrontendLexer_reconstruct_items_end_kernel]

end Lanius.Extraction
