import Lanius.Extraction.VerifiedFrontendUnitLexer
import Lanius.Extraction.VerifiedFrontendUnitCacheBase

namespace Lanius.Extraction
set_option maxRecDepth 100000

def verifiedFrontendLexerParseNodeTree : Lanius.Data.SeqTree ParseNode :=
  artifact_pack_unit_parse_node_tree%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/lexer.lani", 64

def verifiedFrontendLexerTokenTree : Lanius.Data.SeqTree Token :=
  artifact_pack_unit_token_tree%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/lexer.lani", 64

def verifiedFrontendLexerSourceByteTree : Lanius.Data.SeqTree (Fin 256) :=
  artifact_pack_unit_source_byte_tree%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/lexer.lani", 0, 64

def verifiedFrontendLexerCache : ArtifactCache := {
  leafCapacity := 64
  parseNodes := verifiedFrontendLexerParseNodeTree
  tokens := verifiedFrontendLexerTokenTree
  primarySourceBytes := verifiedFrontendLexerSourceByteTree
}

end Lanius.Extraction
