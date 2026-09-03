import Lanius.Extraction.VerifiedFrontend.Surface.RawLexer.Parse.Nodes.Assembly

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0

theorem verifiedFrontendRawLexerParseValidTraceKernel :
    ParseArtifactValid verifiedFrontendRawLexerArtifact :=
  verifiedFrontendRawLexerParseValidChunkKernel

end Lanius.Extraction
