import Lanius.Extraction.VerifiedFrontend.Surface.Number.Parse.Nodes.Assembly

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0

theorem verifiedFrontendNumberParseValidTraceKernel :
    ParseArtifactValid verifiedFrontendNumberArtifact :=
  verifiedFrontendNumberParseValidChunkKernel

end Lanius.Extraction
