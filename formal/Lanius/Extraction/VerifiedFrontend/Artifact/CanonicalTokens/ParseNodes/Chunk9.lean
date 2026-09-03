import Lanius.Extraction.ArtifactQuote
open Lean
namespace Lanius.Extraction
set_option maxRecDepth 100000
def verifiedFrontendCanonicalTokensParseNodes9 :=
  artifact_pack_unit_parse_nodes% (include_str ".." / ".." / ".." / ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/canonical_tokens.lani", 9000, 1000
end Lanius.Extraction
