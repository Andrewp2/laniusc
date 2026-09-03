import Lanius.Extraction.SurfaceOriginQuote
namespace Lanius.Extraction
set_option maxRecDepth 100000
def verifiedFrontendTokenOrigins : SurfaceOrigins :=
  artifact_pack_unit_surface_origins% (include_str ".." / ".." / ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/token.lani"
end Lanius.Extraction
