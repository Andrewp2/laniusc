import Lanius.Extraction.ArtifactQuote
import Lanius.Extraction.VerifiedFrontend.Artifact.RawLexer.Cache.Assembly

namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option compiler.extract_closed false

/-- The artifact and its checked lookup view share one quoted parse-node table. -/
def verifiedFrontendRawLexerArtifact : Artifact :=
  artifact_pack_unit_reusing_nodes%
    (include_str ".." / ".." / ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/raw_lexer.lani", verifiedFrontendRawLexerCache.parseNodes.flatten

end Lanius.Extraction
