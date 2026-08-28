import Lanius.Extraction.ArtifactQuote
import Lanius.Extraction.CompleteChecker

open Lean

namespace Lanius.Extraction

set_option maxRecDepth 100000

def verifiedFrontendLexerArtifact : Artifact :=
  artifact_pack_unit%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/lexer.lani"

def verifiedFrontendTokenScanArtifact : Artifact :=
  artifact_pack_unit%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/token_scan.lani"

def verifiedFrontendDigitsArtifact : Artifact :=
  artifact_pack_unit%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/digits.lani"

def verifiedFrontendTokenArtifact : Artifact :=
  artifact_pack_unit%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/token.lani"

def verifiedFrontendCanonicalTokensArtifact : Artifact :=
  artifact_pack_unit%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/canonical_tokens.lani"

def verifiedFrontendDecimalArtifact : Artifact :=
  artifact_pack_unit%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/decimal.lani"

def verifiedFrontendNumberArtifact : Artifact :=
  artifact_pack_unit%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/number.lani"

def verifiedFrontendSymbolArtifact : Artifact :=
  artifact_pack_unit%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/symbol.lani"

def verifiedFrontendRawLexerArtifact : Artifact :=
  artifact_pack_unit%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/raw_lexer.lani"

/-- The authoritative frontend pack is assembled from the same named unit
    values consumed by unit-level implementation proofs. -/
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
  "lexer.lani",
  "token_scan.lani",
  "digits.lani",
  "token.lani",
  "canonical_tokens.lani",
  "decimal.lani",
  "number.lani",
  "symbol.lani",
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

/-- Both the ordered file set and every byte are tracked by Lean, so changing a
    verified frontend source without regenerating the pack invalidates this
    theorem. -/
theorem verifiedFrontendPack_tracks_sources :
    verifiedFrontendExtractedSources.map (·.path) =
        verifiedFrontendSourcePaths.map
          ("verified_compiler/src/verified/" ++ ·) ∧
      verifiedFrontendExtractedSources.map (·.bytes) =
        verifiedFrontendSourceTexts.map sourceTextBytes := by
  native_decide

theorem verifiedFrontendPack_completely_checked :
    (CompleteChecker.checkPack? verifiedFrontendPack).isSome = true := by
  native_decide

/-- The complete multi-unit frontend certificate.  All later pack views are
    projections of this one accepted value. -/
def verifiedFrontendPackChecked :
    CompleteChecker.CheckedPack verifiedFrontendPack :=
  (CompleteChecker.checkPack? verifiedFrontendPack).get
    verifiedFrontendPack_completely_checked

end Lanius.Extraction
