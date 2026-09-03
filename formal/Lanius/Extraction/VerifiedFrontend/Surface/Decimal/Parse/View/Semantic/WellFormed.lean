import Lanius.Extraction.VerifiedFrontend.Artifact.Decimal.Cache.Semantic
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendDecimal_semantic_tree_well_formed_kernel :
    verifiedFrontendDecimalSemanticKindTree.WellFormed 64 := by
  apply Lanius.Data.SeqTree.wellFormed_sound
  with_unfolding_all rfl
end Lanius.Extraction
