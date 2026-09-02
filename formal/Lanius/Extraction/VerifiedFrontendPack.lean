import Lanius.Extraction.VerifiedFrontendUnitLexer
import Lanius.Extraction.VerifiedFrontendUnitTokenScan
import Lanius.Extraction.VerifiedFrontendUnitDigits
import Lanius.Extraction.VerifiedFrontendUnitToken
import Lanius.Extraction.VerifiedFrontendUnitCanonicalTokens
import Lanius.Extraction.VerifiedFrontendUnitDecimal
import Lanius.Extraction.VerifiedFrontendUnitNumber
import Lanius.Extraction.VerifiedFrontendUnitSymbol
import Lanius.Extraction.VerifiedFrontendUnitRawLexer

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

def verifiedFrontendSourceTexts : List String := [
  include_str ".." / ".." / ".." / "verified_compiler" / "src" /
    "verified" / "lexer.lani",
  include_str ".." / ".." / ".." / "verified_compiler" / "src" /
    "verified" / "token_scan.lani",
  include_str ".." / ".." / ".." / "verified_compiler" / "src" /
    "verified" / "digits.lani",
  include_str ".." / ".." / ".." / "verified_compiler" / "src" /
    "verified" / "token.lani",
  include_str ".." / ".." / ".." / "verified_compiler" / "src" /
    "verified" / "canonical_tokens.lani",
  include_str ".." / ".." / ".." / "verified_compiler" / "src" /
    "verified" / "decimal.lani",
  include_str ".." / ".." / ".." / "verified_compiler" / "src" /
    "verified" / "number.lani",
  include_str ".." / ".." / ".." / "verified_compiler" / "src" /
    "verified" / "symbol.lani",
  include_str ".." / ".." / ".." / "verified_compiler" / "src" /
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

theorem verifiedFrontendPack_tracks_sources :
    verifiedFrontendExtractedSources.map (·.path) =
        verifiedFrontendSourcePaths.map
          ("verified_compiler/src/verified/" ++ ·) ∧
      verifiedFrontendExtractedSources.map (·.bytes) =
        verifiedFrontendSourceTexts.map sourceTextBytes := by
  native_decide

end Lanius.Extraction
