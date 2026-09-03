import Lanius.Extraction.VerifiedFrontend.Artifact.CanonicalTokens.Artifact
import Lanius.Extraction.VerifiedFrontend.Artifact.CacheBase
namespace Lanius.Extraction
set_option maxRecDepth 100000
def verifiedFrontendCanonicalTokensParseNodeTree6 : Lanius.Data.SeqTree ParseNode :=
  artifact_pack_unit_parse_node_tree_range%
    (include_str ".." / ".." / ".." / ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/canonical_tokens.lani", 7733, 1289, 64
end Lanius.Extraction
