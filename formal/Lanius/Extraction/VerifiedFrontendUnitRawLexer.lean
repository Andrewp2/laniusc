import Lanius.Extraction.ArtifactQuote
open Lean
namespace Lanius.Extraction
set_option maxRecDepth 100000
def verifiedFrontendRawLexerArtifact : Artifact :=
  artifact_pack_unit_full% (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/raw_lexer.lani"
end Lanius.Extraction
