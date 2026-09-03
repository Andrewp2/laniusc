import Lanius.Extraction.Evidence.WitnessQuote

open Lean

namespace Lanius.Extraction

set_option maxRecDepth 500000

def verifiedFrontendCanonicalTokensEvidenceTypeTree :=
  artifact_pack_unit_evidence_type_tree%
    (include_str ".." / ".." / ".." / ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/canonical_tokens.lani", 64

end Lanius.Extraction
