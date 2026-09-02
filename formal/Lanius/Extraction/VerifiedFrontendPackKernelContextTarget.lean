import Lanius.Extraction.VerifiedFrontendPackKernelContextBase
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false
theorem verifiedFrontendPack_context_target_present_kernel :
    (ArtifactPackContextChecker.commonTarget?
      verifiedFrontendPackDecodedUnitsKernel).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendPackContextTargetKernel :=
  (ArtifactPackContextChecker.commonTarget?
    verifiedFrontendPackDecodedUnitsKernel).get
      verifiedFrontendPack_context_target_present_kernel
theorem verifiedFrontendPack_context_target_found_kernel :
    ArtifactPackContextChecker.commonTarget? verifiedFrontendPackDecodedUnitsKernel =
      some verifiedFrontendPackContextTargetKernel :=
  parseOptionEqSomeGet verifiedFrontendPack_context_target_present_kernel
end Lanius.Extraction
