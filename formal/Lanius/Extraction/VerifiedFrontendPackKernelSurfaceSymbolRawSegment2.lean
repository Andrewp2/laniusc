import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceSymbolRawData
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
theorem verifiedFrontendSymbol_raw_segment_2_kernel :
    scanRawTokenSegment (verifiedFrontendSymbolDecodedSource.drop 3244) 3244
      ((verifiedFrontendSymbolDecodedRawTokens.drop 1000).take 500) =
      some (verifiedFrontendSymbolDecodedSource.drop 4767, 4767) := by
  with_unfolding_all rfl
end Lanius.Extraction
