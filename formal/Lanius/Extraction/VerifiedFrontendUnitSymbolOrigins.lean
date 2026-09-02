import Lanius.Extraction.SurfaceOriginQuote
namespace Lanius.Extraction
set_option maxRecDepth 100000
def verifiedFrontendSymbolOrigins : SurfaceOrigins :=
  artifact_pack_unit_surface_origins% (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/symbol.lani"
end Lanius.Extraction
