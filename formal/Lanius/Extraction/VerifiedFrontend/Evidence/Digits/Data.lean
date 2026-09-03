import Lanius.Extraction.Evidence.WitnessQuote

open Lean

namespace Lanius.Extraction

set_option maxRecDepth 500000

def verifiedFrontendDigitsEvidenceTypeTree :=
  artifact_pack_unit_evidence_type_tree%
    (include_str ".." / ".." / ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/digits.lani", 64

def verifiedFrontendDigitsEvidenceLoweringTree :=
  artifact_pack_unit_evidence_lowering_tree%
    (include_str ".." / ".." / ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/digits.lani", 64

def verifiedFrontendDigitsLoweringTypeRefs :=
  artifact_pack_unit_lowering_type_refs%
    (include_str ".." / ".." / ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/digits.lani"

def verifiedFrontendDigitsTypeLoweringRefs :=
  artifact_pack_unit_type_lowering_refs%
    (include_str ".." / ".." / ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/digits.lani"

def verifiedFrontendDigitsEvidenceWitnessCache : EvidenceWitnessCache := {
  leafCapacity := 64
  types := verifiedFrontendDigitsEvidenceTypeTree
  lowering := verifiedFrontendDigitsEvidenceLoweringTree
  loweringTypeRefs := verifiedFrontendDigitsLoweringTypeRefs
  typeLoweringRefs := verifiedFrontendDigitsTypeLoweringRefs
}

end Lanius.Extraction
