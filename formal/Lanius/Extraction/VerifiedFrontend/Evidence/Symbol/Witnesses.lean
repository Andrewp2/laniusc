import Lanius.Extraction.VerifiedFrontend.Evidence.Symbol.TypedLoweringWitnesses
import Lanius.Extraction.VerifiedFrontend.Evidence.Symbol.TypeLoweringWitnesses

namespace Lanius.Extraction
theorem verifiedFrontendSymbol_evidence_witnesses_checked_kernel :
    checkEvidenceWitnesses verifiedFrontendSymbolEvidenceWitnessView = true := by
  unfold checkEvidenceWitnesses
  change (checkTypedLoweringWitnesses verifiedFrontendSymbolEvidenceTypeTree
      verifiedFrontendSymbolArtifact.lowering verifiedFrontendSymbolLoweringTypeRefs &&
    checkTypeLoweringWitnesses verifiedFrontendSymbolEvidenceLoweringTree
      verifiedFrontendSymbolArtifact.types verifiedFrontendSymbolTypeLoweringRefs) = true
  simp only [verifiedFrontendSymbol_typed_lowering_witnesses_checked_kernel,
    verifiedFrontendSymbol_type_lowering_witnesses_checked_kernel, Bool.true_and]
end Lanius.Extraction
