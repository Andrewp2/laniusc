import Lanius.Extraction.VerifiedFrontendUnitSymbol
import Lanius.Extraction.VerifiedFrontendUnitCacheBase
namespace Lanius.Extraction
set_option maxRecDepth 100000
def verifiedFrontendSymbolParseNodeTree5 : Lanius.Data.SeqTree ParseNode :=
  artifact_pack_unit_parse_node_tree_range%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/symbol.lani", 5152, 1030, 64
end Lanius.Extraction
