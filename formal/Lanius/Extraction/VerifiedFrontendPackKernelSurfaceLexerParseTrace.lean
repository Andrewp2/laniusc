import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerView
import Lanius.Extraction.ParseTrace

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0

theorem verifiedFrontendLexerParseValidTraceKernel :
    ParseArtifactValid verifiedFrontendLexerArtifact := by
  parse_artifact_trace verifiedFrontendLexerArtifact, verifiedFrontendLexerView

end Lanius.Extraction
