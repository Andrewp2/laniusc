import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceCanonicalTokensRawData
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
theorem verifiedFrontendCanonicalTokens_raw_segment_2_kernel :
    scanRawTokenSegment
      (verifiedFrontendCanonicalTokensDecodedSource.drop 2372) 2372
      ((verifiedFrontendCanonicalTokensDecodedRawTokens.drop 1000).take 500) =
      some (verifiedFrontendCanonicalTokensDecodedSource.drop 3456,
        3456) := by
  with_unfolding_all rfl
end Lanius.Extraction
