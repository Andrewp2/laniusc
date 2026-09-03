import Lanius.Extraction.Evidence.WitnessQuote

open Lean

namespace Lanius.Extraction

set_option maxRecDepth 500000

def verifiedFrontendNumberEvidenceTypeTree :=
  artifact_pack_unit_evidence_type_tree%
    (include_str ".." / ".." / ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/number.lani", 64

def verifiedFrontendNumberEvidenceLoweringTree :=
  artifact_pack_unit_evidence_lowering_tree%
    (include_str ".." / ".." / ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/number.lani", 64

def verifiedFrontendNumberLoweringTypeRefs :=
  artifact_pack_unit_lowering_type_refs%
    (include_str ".." / ".." / ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/number.lani"

def verifiedFrontendNumberTypeLoweringRefs :=
  artifact_pack_unit_type_lowering_refs%
    (include_str ".." / ".." / ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/number.lani"

def verifiedFrontendNumberEvidenceWitnessCache : EvidenceWitnessCache := {
  leafCapacity := 64
  types := verifiedFrontendNumberEvidenceTypeTree
  lowering := verifiedFrontendNumberEvidenceLoweringTree
  loweringTypeRefs := verifiedFrontendNumberLoweringTypeRefs
  typeLoweringRefs := verifiedFrontendNumberTypeLoweringRefs
}

end Lanius.Extraction
