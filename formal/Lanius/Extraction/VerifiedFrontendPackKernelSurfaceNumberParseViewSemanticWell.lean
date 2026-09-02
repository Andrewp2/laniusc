import Lanius.Extraction.VerifiedFrontendUnitNumberCacheSemantic
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendNumber_semantic_tree_well_formed_kernel :
    verifiedFrontendNumberSemanticKindTree.WellFormed 64 := by
  apply Lanius.Data.SeqTree.wellFormed_sound
  with_unfolding_all rfl
end Lanius.Extraction
