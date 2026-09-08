import Lanius.Extraction.VerifiedFrontend.Artifact.Lexer.Artifact
import Lanius.Extraction.VerifiedFrontend.Artifact.TokenScan.Artifact
import Lanius.Extraction.VerifiedFrontend.Artifact.Digits.Artifact
import Lanius.Extraction.VerifiedFrontend.Artifact.Token.Artifact
import Lanius.Extraction.VerifiedFrontend.Artifact.CanonicalTokens.Artifact
import Lanius.Extraction.VerifiedFrontend.Artifact.Decimal.Artifact
import Lanius.Extraction.VerifiedFrontend.Artifact.Number.Artifact
import Lanius.Extraction.VerifiedFrontend.Artifact.Symbol.Artifact
import Lanius.Extraction.VerifiedFrontend.Artifact.RawLexer.Artifact

open Lean

namespace Lanius.Extraction

def verifiedFrontendPack : ArtifactPack := {
  schema_version := schemaVersion
  units := [
    verifiedFrontendLexerArtifact,
    verifiedFrontendTokenScanArtifact,
    verifiedFrontendDigitsArtifact,
    verifiedFrontendTokenArtifact,
    verifiedFrontendCanonicalTokensArtifact,
    verifiedFrontendDecimalArtifact,
    verifiedFrontendNumberArtifact,
    verifiedFrontendSymbolArtifact,
    verifiedFrontendRawLexerArtifact
  ]
}

def verifiedFrontendSourcePaths : List String := [
  "lexer.lani", "token_scan.lani", "digits.lani", "token.lani",
  "canonical_tokens.lani", "decimal.lani", "number.lani", "symbol.lani",
  "raw_lexer.lani"
]

/-- Current source text only for unchanged units. The historical canonicalizer
is intentionally excluded; its replacement has a separate source-bound proof. -/
def verifiedFrontendUnchangedSourceTexts : List String := [
  include_str ".." / ".." / ".." / ".." / "verified_compiler" / "src" /
    "verified" / "lexer.lani",
  include_str ".." / ".." / ".." / ".." / "verified_compiler" / "src" /
    "verified" / "token_scan.lani",
  include_str ".." / ".." / ".." / ".." / "verified_compiler" / "src" /
    "verified" / "digits.lani",
  include_str ".." / ".." / ".." / ".." / "verified_compiler" / "src" /
    "verified" / "token.lani",
  include_str ".." / ".." / ".." / ".." / "verified_compiler" / "src" /
    "verified" / "decimal.lani",
  include_str ".." / ".." / ".." / ".." / "verified_compiler" / "src" /
    "verified" / "number.lani",
  include_str ".." / ".." / ".." / ".." / "verified_compiler" / "src" /
    "verified" / "symbol.lani",
  include_str ".." / ".." / ".." / ".." / "verified_compiler" / "src" /
    "verified" / "raw_lexer.lani"
]

def sourceTextBytes (source : String) : List Nat :=
  source.toUTF8.toList.map UInt8.toNat

def verifiedFrontendExtractedSources : List SourceFile :=
  verifiedFrontendPack.units.flatMap (·.sources)

theorem verifiedFrontendPack_lexer_unit :
    verifiedFrontendPack.units[0]? = some verifiedFrontendLexerArtifact := by
  rfl

theorem verifiedFrontendPack_digits_unit :
    verifiedFrontendPack.units[2]? = some verifiedFrontendDigitsArtifact := by
  rfl

theorem verifiedFrontendPack_tracks_unchanged_sources :
    verifiedFrontendExtractedSources.map (·.path) =
        verifiedFrontendSourcePaths.map
          ("verified_compiler/src/verified/" ++ ·) ∧
      (verifiedFrontendExtractedSources.filter
        (fun source => source.path != "verified_compiler/src/verified/canonical_tokens.lani")).map (·.bytes) =
        verifiedFrontendUnchangedSourceTexts.map sourceTextBytes := by
  native_decide

end Lanius.Extraction
