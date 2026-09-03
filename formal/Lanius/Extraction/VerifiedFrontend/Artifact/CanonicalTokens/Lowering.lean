import Lanius.Extraction.ArtifactQuote
open Lean
namespace Lanius.Extraction
set_option maxRecDepth 500000
def verifiedFrontendCanonicalTokensLowering :=
  artifact_pack_unit_field% (include_str ".." / ".." / ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/canonical_tokens.lani", lowering
end Lanius.Extraction
