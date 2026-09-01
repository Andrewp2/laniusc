import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructExactItems24

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendLexer_reconstruct_item25_exact_kernel :
    (reconstructItem 6966 verifiedFrontendLexerArtifact 6118).run 931 =
      some (verifiedFrontendLexerProposedItem25Kernel, 963) := by
  cbv

theorem verifiedFrontendLexer_reconstruct_item26_exact_kernel :
    (reconstructItem 6965 verifiedFrontendLexerArtifact 6417).run 963 =
      some (verifiedFrontendLexerProposedItem26Kernel, 1017) := by
  cbv

theorem verifiedFrontendLexer_reconstruct_item27_exact_kernel :
    (reconstructItem 6964 verifiedFrontendLexerArtifact 6960).run 1017 =
      some (verifiedFrontendLexerProposedItem27Kernel, 1107) := by
  cbv

end Lanius.Extraction

