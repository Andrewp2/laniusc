import Lanius.Extraction.ArtifactQuote

open Lean
namespace Lanius.Extraction
set_option maxRecDepth 100000

def verifiedFrontendLexerArtifact : Artifact :=
  artifact_pack_unit_full%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/lexer.lani"

def verifiedFrontendLexerParseNodes0 :=
  artifact_pack_unit_parse_nodes% (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/lexer.lani", 0, 1000
def verifiedFrontendLexerParseNodes1 :=
  artifact_pack_unit_parse_nodes% (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/lexer.lani", 1000, 1000
def verifiedFrontendLexerParseNodes2 :=
  artifact_pack_unit_parse_nodes% (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/lexer.lani", 2000, 1000
def verifiedFrontendLexerParseNodes3 :=
  artifact_pack_unit_parse_nodes% (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/lexer.lani", 3000, 1000
def verifiedFrontendLexerParseNodes4 :=
  artifact_pack_unit_parse_nodes% (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/lexer.lani", 4000, 1000
def verifiedFrontendLexerParseNodes5 :=
  artifact_pack_unit_parse_nodes% (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/lexer.lani", 5000, 1000
def verifiedFrontendLexerParseNodes6 :=
  artifact_pack_unit_parse_nodes% (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/lexer.lani", 6000, 991

end Lanius.Extraction
