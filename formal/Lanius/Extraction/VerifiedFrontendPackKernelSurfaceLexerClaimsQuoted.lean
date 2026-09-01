import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerClaimsBase
import Lanius.Extraction.ArtifactClaimsQuote

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

def verifiedFrontendLexerClaimsQuoted : SurfaceClaims :=
  artifact_pack_unit_surface_claims%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/lexer.lani"

theorem verifiedFrontendLexerClaimsKernel_eq_quoted :
    verifiedFrontendLexerClaimsKernel = verifiedFrontendLexerClaimsQuoted := by
  cbv

end Lanius.Extraction
