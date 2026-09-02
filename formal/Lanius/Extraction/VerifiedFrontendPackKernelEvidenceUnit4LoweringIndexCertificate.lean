import Lanius.Extraction.VerifiedFrontendPackKernelEvidenceUnit4IndexesData
import Lanius.Extraction.VerifiedFrontendPackKernelEvidenceBase

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0

theorem verifiedFrontendCanonicalTokensLoweringNodeIndexDataKernel_eq :
    verifiedFrontendCanonicalTokensLoweringNodeIndexDataKernel =
      Std.TreeSet.Raw.ofList
        (verifiedFrontendCanonicalTokensArtifact.lowering.map (·.surface_node)) := by
  with_unfolding_all rfl

end Lanius.Extraction
