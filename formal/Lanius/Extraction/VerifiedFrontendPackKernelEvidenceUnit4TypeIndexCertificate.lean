import Lanius.Extraction.VerifiedFrontendPackKernelEvidenceUnit4IndexesData
import Lanius.Extraction.VerifiedFrontendPackKernelEvidenceBase

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0

theorem verifiedFrontendCanonicalTokensTypeNodeIndexDataKernel_eq :
    verifiedFrontendCanonicalTokensTypeNodeIndexDataKernel =
      Std.TreeSet.Raw.ofList
        (verifiedFrontendCanonicalTokensArtifact.types.map (·.surface_node)) := by
  with_unfolding_all rfl

end Lanius.Extraction
