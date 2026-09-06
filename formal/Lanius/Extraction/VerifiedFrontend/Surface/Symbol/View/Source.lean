import Lanius.Extraction.KernelReduction
import Lanius.Extraction.VerifiedFrontend.Artifact.Symbol.Cache.Assembly
import Lanius.Extraction.VerifiedFrontend.Artifact.Symbol.Artifact

namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
theorem verifiedFrontendSymbol_source_tree_well_formed_kernel :
    verifiedFrontendSymbolSourceByteTree.WellFormed 64 := by
  apply Lanius.Data.SeqTree.wellFormed_sound
  kernel_rfl
end Lanius.Extraction

namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
theorem verifiedFrontendSymbol_source_tree_represents_kernel :
    ∀ source, verifiedFrontendSymbolArtifact.sources[0]? = some source →
      decodeBytes source.bytes = some verifiedFrontendSymbolSourceByteTree.flatten := by
  intro source found
  with_unfolding_all
    injection found with sourceEq
    subst source
    rfl
end Lanius.Extraction
