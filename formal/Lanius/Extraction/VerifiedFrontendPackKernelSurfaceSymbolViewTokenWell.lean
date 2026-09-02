import Lanius.Extraction.VerifiedFrontendUnitSymbolCache
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
theorem verifiedFrontendSymbol_token_tree_well_formed_kernel :
    verifiedFrontendSymbolTokenTree.WellFormed 64 := by
  apply Lanius.Data.SeqTree.wellFormed_sound
  with_unfolding_all rfl
end Lanius.Extraction
