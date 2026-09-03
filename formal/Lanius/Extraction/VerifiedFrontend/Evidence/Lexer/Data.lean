import Lanius.Extraction.Evidence.WitnessQuote

open Lean

namespace Lanius.Extraction

set_option maxRecDepth 500000

def verifiedFrontendLexerEvidenceTypeTree :=
  artifact_pack_unit_evidence_type_tree%
    (include_str ".." / ".." / ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/lexer.lani", 64

def verifiedFrontendLexerEvidenceLoweringTree :=
  artifact_pack_unit_evidence_lowering_tree%
    (include_str ".." / ".." / ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/lexer.lani", 64

def verifiedFrontendLexerLoweringTypeRefs :=
  artifact_pack_unit_lowering_type_refs%
    (include_str ".." / ".." / ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/lexer.lani"

def verifiedFrontendLexerTypeLoweringRefs :=
  artifact_pack_unit_type_lowering_refs%
    (include_str ".." / ".." / ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/lexer.lani"

def verifiedFrontendLexerEvidenceWitnessCache : EvidenceWitnessCache := {
  leafCapacity := 64
  types := verifiedFrontendLexerEvidenceTypeTree
  lowering := verifiedFrontendLexerEvidenceLoweringTree
  loweringTypeRefs := verifiedFrontendLexerLoweringTypeRefs
  typeLoweringRefs := verifiedFrontendLexerTypeLoweringRefs
}

end Lanius.Extraction
