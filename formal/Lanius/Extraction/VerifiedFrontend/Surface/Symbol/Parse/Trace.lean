import Lanius.Extraction.VerifiedFrontend.Surface.Symbol.Parse.ChunkAssembly

namespace Lanius.Extraction

theorem verifiedFrontendSymbolParseValidTraceKernel :
    ParseArtifactValid verifiedFrontendSymbolArtifact :=
  verifiedFrontendSymbolParseValidChunkKernel

end Lanius.Extraction
