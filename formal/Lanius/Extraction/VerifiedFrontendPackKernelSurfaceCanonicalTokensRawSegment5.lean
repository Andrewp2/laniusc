import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceCanonicalTokensRawData
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
theorem verifiedFrontendCanonicalTokens_raw_segment_5_kernel :
    scanRawTokenSegment
      (verifiedFrontendCanonicalTokensDecodedSource.drop 6128) 6128
      ((verifiedFrontendCanonicalTokensDecodedRawTokens.drop 2500).take 38) =
      some (verifiedFrontendCanonicalTokensDecodedSource.drop 6268,
        6268) := by
  with_unfolding_all rfl
end Lanius.Extraction
