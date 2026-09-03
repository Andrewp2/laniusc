import Lanius.Extraction.VerifiedFrontend.Artifact.Symbol.Artifact
import Lanius.Extraction.VerifiedFrontend.Artifact.CacheBase
namespace Lanius.Extraction
set_option maxRecDepth 100000
def verifiedFrontendSymbolSourceByteTree : Lanius.Data.SeqTree (Fin 256) :=
  artifact_pack_unit_source_byte_tree% (include_str ".." / ".." / ".." / ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/symbol.lani", 0, 64
end Lanius.Extraction
