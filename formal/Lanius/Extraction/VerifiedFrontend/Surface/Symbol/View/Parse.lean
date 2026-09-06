import Lanius.Extraction.KernelReduction
import Lanius.Extraction.VerifiedFrontend.Artifact.Symbol.Cache.Assembly
import Lanius.Extraction.VerifiedFrontend.Artifact.Symbol.Artifact

namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
theorem verifiedFrontendSymbol_parse_tree_well_formed_kernel :
    verifiedFrontendSymbolParseNodeTree.WellFormed 64 := by
  apply Lanius.Data.SeqTree.wellFormed_sound
  kernel_rfl
end Lanius.Extraction

namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
theorem verifiedFrontendSymbol_parse_tree_represents_kernel :
    verifiedFrontendSymbolParseNodeTree.Represents verifiedFrontendSymbolArtifact.parse_nodes := by
  rfl
end Lanius.Extraction
