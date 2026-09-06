import Lanius.Extraction.KernelReduction
import Lanius.Extraction.VerifiedFrontend.Artifact.Decimal.Cache.Semantic

namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendDecimal_semantic_tree_well_formed_kernel :
    verifiedFrontendDecimalSemanticKindTree.WellFormed 64 := by
  apply Lanius.Data.SeqTree.wellFormed_sound
  kernel_rfl
end Lanius.Extraction

namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendDecimal_semantic_tree_represents_kernel :
    verifiedFrontendDecimalSemanticKindTree.Represents verifiedFrontendDecimalArtifact.semantic_token_kinds := by
  kernel_rfl
end Lanius.Extraction

