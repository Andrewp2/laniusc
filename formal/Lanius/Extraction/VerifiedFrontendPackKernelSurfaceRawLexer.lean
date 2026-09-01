import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceSymbol

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendRawLexer_surface_checked_kernel :
    (checkSurfaceArtifactCached? verifiedFrontendRawLexerArtifact).isSome = true := by
  cbv

def verifiedFrontendRawLexerSurfaceKernel :=
  (checkSurfaceArtifactCached? verifiedFrontendRawLexerArtifact).get
    verifiedFrontendRawLexer_surface_checked_kernel

theorem verifiedFrontendRawLexerSurfaceKernel_eq :
    checkSurfaceArtifactCached? verifiedFrontendRawLexerArtifact =
      some verifiedFrontendRawLexerSurfaceKernel := by
  generalize found : checkSurfaceArtifactCached?
    verifiedFrontendRawLexerArtifact = result
  cases result <;> simp_all [verifiedFrontendRawLexerSurfaceKernel]

end Lanius.Extraction
