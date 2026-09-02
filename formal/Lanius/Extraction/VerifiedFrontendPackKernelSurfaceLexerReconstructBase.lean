import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerParseEvidence

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendLexer_proposed_present_kernel :
    verifiedFrontendLexerArtifact.surface.isSome = true := by
  with_unfolding_all rfl

def verifiedFrontendLexerProposedKernel :=
  verifiedFrontendLexerArtifact.surface.get
    verifiedFrontendLexer_proposed_present_kernel

theorem verifiedFrontendLexerProposedKernel_eq :
    verifiedFrontendLexerArtifact.surface =
      some verifiedFrontendLexerProposedKernel := by
  generalize found : verifiedFrontendLexerArtifact.surface = result
  cases result <;> simp_all [verifiedFrontendLexerProposedKernel]

end Lanius.Extraction
