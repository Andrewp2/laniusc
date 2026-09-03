import Lanius.Extraction.VerifiedFrontend.Surface.Token.Parse.ChunkAssembly

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0

theorem verifiedFrontendTokenParseValidTraceKernel :
    ParseArtifactValid verifiedFrontendTokenArtifact :=
  verifiedFrontendTokenParseValidChunkKernel

end Lanius.Extraction
