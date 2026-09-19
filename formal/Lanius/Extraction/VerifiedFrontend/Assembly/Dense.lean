import Lanius.Extraction.VerifiedFrontend.Assembly.Wire
import Lanius.Extraction.VerifiedFrontend.Evidence.Coverage

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0

theorem verifiedFrontendPack_dense_checked_kernel :
    coreNodeIdsDense verifiedFrontendPackWireKernel = true := by
  change ((coreProgramNodeIds verifiedFrontendPackWireKernel).mergeSort ==
    List.range (coreProgramNodeIds verifiedFrontendPackWireKernel).length) = true
  have coverage := verifiedFrontendPack_lowering_covers_core_kernel
  change ((CompleteChecker.packLoweringCoreNodeIds verifiedFrontendPack).mergeSort ==
    List.range (coreProgramNodeIds verifiedFrontendPackWireKernel).length) = true at coverage
  simpa only [show CompleteChecker.packLoweringCoreNodeIds verifiedFrontendPack =
    coreProgramNodeIds verifiedFrontendPackWireKernel by rfl] using coverage

end Lanius.Extraction
