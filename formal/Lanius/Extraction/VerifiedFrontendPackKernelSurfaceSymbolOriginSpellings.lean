import Lanius.Extraction.VerifiedFrontendUnitSymbolOrigins
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceSymbolView
import Lanius.Extraction.KernelSurfacePhases
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendSymbol_origin_spellings_checked_kernel :
    spellingOriginPathsValid verifiedFrontendSymbolArtifact verifiedFrontendSymbolView
      (verifiedFrontendSymbolOrigins).claims.spellings (verifiedFrontendSymbolOrigins).spellingPaths = true := by
  with_unfolding_all rfl
end Lanius.Extraction
