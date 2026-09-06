import Lanius.Extraction.KernelReduction
import Lanius.Extraction.VerifiedFrontend.Artifact.Digits.Cache.Semantic

namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendDigits_semantic_tree_well_formed_kernel :
    verifiedFrontendDigitsSemanticKindTree.WellFormed 64 := by
  apply Lanius.Data.SeqTree.wellFormed_sound
  kernel_rfl
end Lanius.Extraction

namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendDigits_semantic_tree_represents_kernel :
    verifiedFrontendDigitsSemanticKindTree.Represents verifiedFrontendDigitsArtifact.semantic_token_kinds := by
  kernel_rfl
end Lanius.Extraction

