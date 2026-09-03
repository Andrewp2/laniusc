import Lanius.Extraction.VerifiedFrontend.Surface.CanonicalTokens.Raw.Data
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
theorem verifiedFrontendCanonicalTokens_raw_segment_3_kernel :
    scanRawTokenSegment
      (verifiedFrontendCanonicalTokensDecodedSource.drop 3456) 3456
      ((verifiedFrontendCanonicalTokensDecodedRawTokens.drop 1500).take 500) =
      some (verifiedFrontendCanonicalTokensDecodedSource.drop 4521,
        4521) := by
  with_unfolding_all rfl
end Lanius.Extraction
