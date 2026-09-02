import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceSymbolRawData
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
theorem verifiedFrontendSymbol_raw_segment_3_kernel :
    scanRawTokenSegment (verifiedFrontendSymbolDecodedSource.drop 4767) 4767
      ((verifiedFrontendSymbolDecodedRawTokens.drop 1500).take 317) =
      some (verifiedFrontendSymbolDecodedSource.drop 5564, 5564) := by
  with_unfolding_all rfl
end Lanius.Extraction
