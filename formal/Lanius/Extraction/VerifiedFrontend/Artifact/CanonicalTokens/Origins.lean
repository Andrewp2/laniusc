import Lanius.Extraction.SurfaceOriginQuote
namespace Lanius.Extraction
set_option maxRecDepth 500000
def verifiedFrontendCanonicalTokensOrigins : SurfaceOrigins :=
  artifact_pack_unit_surface_origins% (include_str ".." / ".." / ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/canonical_tokens.lani"
end Lanius.Extraction
