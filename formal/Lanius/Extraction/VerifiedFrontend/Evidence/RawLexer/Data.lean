import Lanius.Extraction.Evidence.WitnessQuote

open Lean

namespace Lanius.Extraction

set_option maxRecDepth 500000

def verifiedFrontendRawLexerEvidenceTypeTree :=
  artifact_pack_unit_evidence_type_tree%
    (include_str ".." / ".." / ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/raw_lexer.lani", 64

def verifiedFrontendRawLexerEvidenceLoweringTree :=
  artifact_pack_unit_evidence_lowering_tree%
    (include_str ".." / ".." / ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/raw_lexer.lani", 64

def verifiedFrontendRawLexerLoweringTypeRefs :=
  artifact_pack_unit_lowering_type_refs%
    (include_str ".." / ".." / ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/raw_lexer.lani"

def verifiedFrontendRawLexerTypeLoweringRefs :=
  artifact_pack_unit_type_lowering_refs%
    (include_str ".." / ".." / ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/raw_lexer.lani"

def verifiedFrontendRawLexerEvidenceWitnessCache : EvidenceWitnessCache := {
  leafCapacity := 64
  types := verifiedFrontendRawLexerEvidenceTypeTree
  lowering := verifiedFrontendRawLexerEvidenceLoweringTree
  loweringTypeRefs := verifiedFrontendRawLexerLoweringTypeRefs
  typeLoweringRefs := verifiedFrontendRawLexerTypeLoweringRefs
}

end Lanius.Extraction
