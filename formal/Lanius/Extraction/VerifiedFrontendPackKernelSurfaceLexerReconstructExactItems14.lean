import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructExactItems13

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendLexer_reconstruct_item14_exact_kernel :
    (reconstructItem 6977 verifiedFrontendLexerArtifact 3692).run 309 =
      some (verifiedFrontendLexerProposedItem14Kernel, 567) := by
  cbv

end Lanius.Extraction

