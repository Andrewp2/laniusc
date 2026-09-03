import Lanius.Extraction.ArtifactQuote
open Lean
namespace Lanius.Extraction
set_option maxRecDepth 100000
def verifiedFrontendSymbolArtifact : Artifact :=
  artifact_pack_unit_full% (include_str ".." / ".." / ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/symbol.lani"
end Lanius.Extraction
