import Lanius.Extraction.VerifiedFrontend.Surface.TokenScan.Parse.ChunkAssembly

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0

theorem verifiedFrontendTokenScanParseValidTraceKernel :
    ParseArtifactValid verifiedFrontendTokenScanArtifact :=
  verifiedFrontendTokenScanParseValidChunkKernel

end Lanius.Extraction
