import Lanius.Extraction.Evidence.WitnessQuote

open Lean

namespace Lanius.Extraction

set_option maxRecDepth 500000

def verifiedFrontendDecimalEvidenceTypeTree :=
  artifact_pack_unit_evidence_type_tree%
    (include_str ".." / ".." / ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/decimal.lani", 64

def verifiedFrontendDecimalEvidenceLoweringTree :=
  artifact_pack_unit_evidence_lowering_tree%
    (include_str ".." / ".." / ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/decimal.lani", 64

def verifiedFrontendDecimalLoweringTypeRefs :=
  artifact_pack_unit_lowering_type_refs%
    (include_str ".." / ".." / ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/decimal.lani"

def verifiedFrontendDecimalTypeLoweringRefs :=
  artifact_pack_unit_type_lowering_refs%
    (include_str ".." / ".." / ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/decimal.lani"

def verifiedFrontendDecimalEvidenceWitnessCache : EvidenceWitnessCache := {
  leafCapacity := 64
  types := verifiedFrontendDecimalEvidenceTypeTree
  lowering := verifiedFrontendDecimalEvidenceLoweringTree
  loweringTypeRefs := verifiedFrontendDecimalLoweringTypeRefs
  typeLoweringRefs := verifiedFrontendDecimalTypeLoweringRefs
}

end Lanius.Extraction
