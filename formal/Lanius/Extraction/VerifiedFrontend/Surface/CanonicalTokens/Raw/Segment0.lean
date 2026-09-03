import Lanius.Extraction.VerifiedFrontend.Surface.CanonicalTokens.Raw.Data
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
theorem verifiedFrontendCanonicalTokens_raw_segment_0_kernel :
    scanRawTokenSegment
      (verifiedFrontendCanonicalTokensDecodedSource.drop 0) 0
      ((verifiedFrontendCanonicalTokensDecodedRawTokens.drop 0).take 500) =
      some (verifiedFrontendCanonicalTokensDecodedSource.drop 1271,
        1271) := by
  with_unfolding_all rfl
end Lanius.Extraction
