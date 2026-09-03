import Lanius.Extraction.VerifiedFrontend.Artifact.Symbol.Artifact
import Lanius.Extraction.VerifiedFrontend.Artifact.Cache.Base
namespace Lanius.Extraction
set_option maxRecDepth 100000
def verifiedFrontendSymbolParseNodeTree7 : Lanius.Data.SeqTree ParseNode :=
  artifact_pack_unit_parse_node_tree_range%
    (include_str ".." / ".." / ".." / ".." / ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/symbol.lani", 7213, 1031, 64
end Lanius.Extraction
