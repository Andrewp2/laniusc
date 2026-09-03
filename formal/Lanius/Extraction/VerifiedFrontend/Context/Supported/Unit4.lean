import Lanius.Extraction.VerifiedFrontend.Decoded.Unit4
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
theorem verifiedFrontendCanonicalTokens_context_items_supported_kernel :
    ArtifactContextChecker.supportedSingleModuleItems
      (verifiedFrontendCanonicalTokensDecodedSurfaceKernel.items.filter fun item =>
        match item with
        | .importPath _ => false
        | _ => true) = true := by
  with_unfolding_all rfl
end Lanius.Extraction
