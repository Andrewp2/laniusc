import Lanius.Extraction.VerifiedFrontend.Surface.Symbol.Parse.Nodes.Assembly

namespace Lanius.Extraction

theorem verifiedFrontendSymbolParseValidTraceKernel :
    ParseArtifactValid verifiedFrontendSymbolArtifact :=
  verifiedFrontendSymbolParseValidChunkKernel

end Lanius.Extraction
