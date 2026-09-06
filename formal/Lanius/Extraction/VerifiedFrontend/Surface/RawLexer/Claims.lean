import Lanius.Extraction.VerifiedFrontend.Surface.RawLexer.Reconstruction
import Lanius.Extraction.VerifiedFrontend.Artifact.RawLexer.Origins
import Lanius.Extraction.KernelSurfacePhases

namespace Lanius.Extraction

set_option maxRecDepth 500000
set_option maxHeartbeats 0

def verifiedFrontendRawLexerClaimsKernel : SurfaceClaims :=
  verifiedFrontendRawLexerOrigins.claims

theorem verifiedFrontendRawLexer_claims_found_kernel :
    collectSurfaceClaimsFrom verifiedFrontendRawLexerArtifact
      verifiedFrontendRawLexerReconstructedKernel = some verifiedFrontendRawLexerClaimsKernel := by
  kernel_rfl

theorem verifiedFrontendRawLexer_claims_equal_kernel :
    verifiedFrontendRawLexerOrigins.claims = verifiedFrontendRawLexerClaimsKernel := rfl

end Lanius.Extraction
