import Lanius.Extraction.VerifiedFrontend.Evidence.Units
import Lanius.Extraction.VerifiedFrontend.Assembly.Wire

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0

theorem verifiedFrontendPack_lowering_covers_core_kernel :
      CompleteChecker.packLoweringCoversCore
        verifiedFrontendPack verifiedFrontendPackWireKernel = true := by
    change ((CompleteChecker.packLoweringCoreNodeIds verifiedFrontendPack).mergeSort ==
      List.range (coreProgramNodeIds verifiedFrontendPackWireKernel).length) = true
    have lowering_range :
        CompleteChecker.packLoweringCoreNodeIds verifiedFrontendPack =
          List.range (coreProgramNodeIds verifiedFrontendPackWireKernel).length := by
      unfold verifiedFrontendPackWireKernel
      rfl
    rw [lowering_range]
    rw [List.mergeSort_of_pairwise]
    · rfl
    · simpa only [decide_eq_true_eq] using
        (List.pairwise_le_range
          (n := (coreProgramNodeIds verifiedFrontendPackWireKernel).length))

end Lanius.Extraction
