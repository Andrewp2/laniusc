import Lanius.Extraction.VerifiedFrontend.Artifact.Symbol.Cache.Semantic
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
theorem verifiedFrontendSymbol_semantic_tree_well_formed_kernel :
    verifiedFrontendSymbolSemanticKindTree.WellFormed 64 := by
  apply Lanius.Data.SeqTree.wellFormed_sound
  with_unfolding_all rfl
end Lanius.Extraction
