import Lanius.Extraction.VerifiedFrontend.Surface.CanonicalTokens.Raw.Data
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
theorem verifiedFrontendCanonicalTokens_raw_tokens_split_kernel :
    verifiedFrontendCanonicalTokensDecodedRawTokens =
      verifiedFrontendCanonicalTokensDecodedRawTokens.take 500 ++
      ((verifiedFrontendCanonicalTokensDecodedRawTokens.drop 500).take 500 ++
      ((verifiedFrontendCanonicalTokensDecodedRawTokens.drop 1000).take 500 ++
      ((verifiedFrontendCanonicalTokensDecodedRawTokens.drop 1500).take 500 ++
      ((verifiedFrontendCanonicalTokensDecodedRawTokens.drop 2000).take 500 ++
        (verifiedFrontendCanonicalTokensDecodedRawTokens.drop 2500).take 38)))) := by
  with_unfolding_all rfl
end Lanius.Extraction
