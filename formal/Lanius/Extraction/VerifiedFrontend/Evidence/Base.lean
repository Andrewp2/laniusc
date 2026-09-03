import Lanius.Extraction.VerifiedFrontend.Assembly.Semantics
import Lanius.Extraction.CompleteChecker

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0

def verifiedFrontendPackSurfaceNodeCountsKernel : List Nat :=
  [1108, 124, 368, 419, 1610, 505, 399, 1000, 903]

theorem verifiedFrontendPackSurfaceNodeCountsKernel_eq :
    verifiedFrontendPackSurfaceDataKernel.nodeCounts =
      verifiedFrontendPackSurfaceNodeCountsKernel := by
  with_unfolding_all rfl

end Lanius.Extraction
