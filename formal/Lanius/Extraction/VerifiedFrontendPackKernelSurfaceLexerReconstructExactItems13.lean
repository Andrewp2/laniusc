import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructExactItems0

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendLexer_reconstruct_item13_exact_kernel :
    (reconstructItem 6978 verifiedFrontendLexerArtifact 1905).run 157 =
      some (verifiedFrontendLexerProposedItem13Kernel, 309) := by
  cbv

end Lanius.Extraction

