import Lanius.Extraction.VerifiedFrontendUnitSymbolOrigins
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceSymbolView
import Lanius.Extraction.KernelSurfacePhases
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendSymbol_coverage_checked_kernel :
    spellingCoverageValid verifiedFrontendSymbolArtifact (verifiedFrontendSymbolOrigins).claims = true := by
  with_unfolding_all rfl
end Lanius.Extraction
