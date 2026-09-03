import Lanius.Extraction.Evidence.WitnessQuote

open Lean

namespace Lanius.Extraction

set_option maxRecDepth 500000

def verifiedFrontendSymbolEvidenceTypeTree :=
  artifact_pack_unit_evidence_type_tree%
    (include_str ".." / ".." / ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/symbol.lani", 64

def verifiedFrontendSymbolEvidenceLoweringTree :=
  artifact_pack_unit_evidence_lowering_tree%
    (include_str ".." / ".." / ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/symbol.lani", 64

def verifiedFrontendSymbolLoweringTypeRefs :=
  artifact_pack_unit_lowering_type_refs%
    (include_str ".." / ".." / ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/symbol.lani"

def verifiedFrontendSymbolTypeLoweringRefs :=
  artifact_pack_unit_type_lowering_refs%
    (include_str ".." / ".." / ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/symbol.lani"

def verifiedFrontendSymbolEvidenceWitnessCache : EvidenceWitnessCache := {
  leafCapacity := 64
  types := verifiedFrontendSymbolEvidenceTypeTree
  lowering := verifiedFrontendSymbolEvidenceLoweringTree
  loweringTypeRefs := verifiedFrontendSymbolLoweringTypeRefs
  typeLoweringRefs := verifiedFrontendSymbolTypeLoweringRefs
}

end Lanius.Extraction
