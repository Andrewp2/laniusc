import Lanius.Extraction.ArtifactContextChecker
import Lanius.Extraction.ArtifactQuote
import Lanius.Extraction.CoreTypingChecker
import Lanius.Extraction.EvidenceStructureChecker

open Lean

namespace Lanius.Extraction

set_option maxRecDepth 100000

def sourceBytes (source : String) : List Nat :=
  source.toUTF8.toList.map UInt8.toNat

def verifiedLexerArtifact : Artifact :=
  artifact% (include_str "Artifacts" / "lexer.json")

def verifiedLexerSource : String :=
  include_str ".." / ".." / ".." / "verified_compiler" / "src" /
    "verified" / "lexer.lani"

theorem verifiedLexerArtifact_tracks_source :
    verifiedLexerArtifact.sources.map (·.bytes) = [sourceBytes verifiedLexerSource] := by
  native_decide

theorem verifiedLexerArtifact_evidence_checked :
    checkEvidenceStructure verifiedLexerArtifact = true := by
  native_decide

theorem verifiedLexerArtifact_core_well_typed :
    CoreTyping.checkCoreArtifactTyping verifiedLexerArtifact = true := by
  native_decide

def verifiedTokenArtifact : Artifact :=
  artifact% (include_str "Artifacts" / "token.json")

def verifiedTokenSource : String :=
  include_str ".." / ".." / ".." / "verified_compiler" / "src" /
    "verified" / "token.lani"

theorem verifiedTokenArtifact_tracks_source :
    verifiedTokenArtifact.sources.map (·.bytes) = [sourceBytes verifiedTokenSource] := by
  native_decide

theorem verifiedTokenArtifact_evidence_checked :
    checkEvidenceStructure verifiedTokenArtifact = true := by
  native_decide

theorem verifiedTokenArtifact_core_well_typed :
    CoreTyping.checkCoreArtifactTyping verifiedTokenArtifact = true := by
  native_decide

def verifiedTokenScanArtifact : Artifact :=
  artifact% (include_str "Artifacts" / "token_scan.json")

def verifiedTokenScanSource : String :=
  include_str ".." / ".." / ".." / "verified_compiler" / "src" /
    "verified" / "token_scan.lani"

theorem verifiedTokenScanArtifact_tracks_source :
    verifiedTokenScanArtifact.sources.map (·.bytes) =
      [sourceBytes verifiedTokenScanSource] := by
  native_decide

theorem verifiedTokenScanArtifact_evidence_checked :
    checkEvidenceStructure verifiedTokenScanArtifact = true := by
  native_decide

theorem verifiedTokenScanArtifact_core_well_typed :
    CoreTyping.checkCoreArtifactTyping verifiedTokenScanArtifact = true := by
  native_decide

theorem verifiedTokenScanArtifact_whole_program_semantically_checked :
    (ArtifactContextChecker.checkArtifactProgram?
      verifiedTokenScanArtifact).isSome = true := by
  native_decide

end Lanius.Extraction
