import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceDecimalParseChunkAssembly

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0

theorem verifiedFrontendDecimalParseValidTraceKernel :
    ParseArtifactValid verifiedFrontendDecimalArtifact :=
  verifiedFrontendDecimalParseValidChunkKernel

end Lanius.Extraction
