import Lanius.Extraction.VerifiedFrontend.Surface.Symbol.Raw.Data
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
theorem verifiedFrontendSymbol_raw_segment_0_kernel :
    scanRawTokenSegment (verifiedFrontendSymbolDecodedSource.drop 0) 0
      ((verifiedFrontendSymbolDecodedRawTokens.drop 0).take 500) =
      some (verifiedFrontendSymbolDecodedSource.drop 1686, 1686) := by
  with_unfolding_all rfl
end Lanius.Extraction
