import Lanius.Extraction.VerifiedFrontendPackKernelContextNames
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
theorem verifiedFrontendPack_context_module_names_present_kernel :
    (SurfaceElaborationChecker.modulesUniquePaths?
      verifiedFrontendPackContextNamesKernel).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendPackContextModuleNamesEvidenceKernel :=
  (SurfaceElaborationChecker.modulesUniquePaths?
    verifiedFrontendPackContextNamesKernel).get
      verifiedFrontendPack_context_module_names_present_kernel
end Lanius.Extraction
