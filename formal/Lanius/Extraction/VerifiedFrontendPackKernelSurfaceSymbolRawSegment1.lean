import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceSymbolRawData
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
theorem verifiedFrontendSymbol_raw_segment_1_kernel :
    scanRawTokenSegment (verifiedFrontendSymbolDecodedSource.drop 1686) 1686
      ((verifiedFrontendSymbolDecodedRawTokens.drop 500).take 500) =
      some (verifiedFrontendSymbolDecodedSource.drop 3244, 3244) := by
  with_unfolding_all rfl
end Lanius.Extraction
