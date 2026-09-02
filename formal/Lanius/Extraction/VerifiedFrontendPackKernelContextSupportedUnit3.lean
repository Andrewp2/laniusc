import Lanius.Extraction.VerifiedFrontendPackKernelDecodedUnit3
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
theorem verifiedFrontendToken_context_items_supported_kernel :
    ArtifactContextChecker.supportedSingleModuleItems
      (verifiedFrontendTokenDecodedSurfaceKernel.items.filter fun item =>
        match item with
        | .importPath _ => false
        | _ => true) = true := by
  with_unfolding_all rfl
end Lanius.Extraction
