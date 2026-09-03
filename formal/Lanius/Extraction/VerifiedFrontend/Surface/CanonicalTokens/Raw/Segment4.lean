import Lanius.Extraction.VerifiedFrontend.Surface.CanonicalTokens.Raw.Data
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
theorem verifiedFrontendCanonicalTokens_raw_segment_4_kernel :
    scanRawTokenSegment
      (verifiedFrontendCanonicalTokensDecodedSource.drop 4521) 4521
      ((verifiedFrontendCanonicalTokensDecodedRawTokens.drop 2000).take 500) =
      some (verifiedFrontendCanonicalTokensDecodedSource.drop 6128,
        6128) := by
  with_unfolding_all rfl
end Lanius.Extraction
