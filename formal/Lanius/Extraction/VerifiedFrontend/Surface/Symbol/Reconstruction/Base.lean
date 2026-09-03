import Lanius.Extraction.VerifiedFrontend.Surface.Symbol.Parse.Trace
import Lanius.Extraction.SurfaceReconstruct
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendSymbol_proposed_present_kernel : verifiedFrontendSymbolArtifact.surface.isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendSymbolProposedKernel : SurfaceFile :=
  verifiedFrontendSymbolArtifact.surface.get verifiedFrontendSymbol_proposed_present_kernel
theorem verifiedFrontendSymbol_proposed_found_kernel :
    verifiedFrontendSymbolArtifact.surface = some verifiedFrontendSymbolProposedKernel :=
  parseOptionEqSomeGet verifiedFrontendSymbol_proposed_present_kernel
end Lanius.Extraction
