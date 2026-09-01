import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructRootProduction

namespace Lanius.Extraction

theorem verifiedFrontendLexer_root_items_child_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6990 0 = some 6989 := by
  unfold artifactChildNode?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 29 (by omega)]
  rfl

end Lanius.Extraction
