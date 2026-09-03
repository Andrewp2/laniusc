import Lanius.Extraction.VerifiedFrontend.Surface.Digits.Parse.ChunkAssembly

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0

theorem verifiedFrontendDigitsParseValidTraceKernel :
    ParseArtifactValid verifiedFrontendDigitsArtifact :=
  verifiedFrontendDigitsParseValidChunkKernel

end Lanius.Extraction
