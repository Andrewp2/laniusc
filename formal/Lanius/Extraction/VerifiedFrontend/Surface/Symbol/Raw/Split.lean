import Lanius.Extraction.VerifiedFrontend.Surface.Symbol.Raw.Data
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
theorem verifiedFrontendSymbol_raw_tokens_split_kernel :
    verifiedFrontendSymbolDecodedRawTokens =
      verifiedFrontendSymbolDecodedRawTokens.take 500 ++
      ((verifiedFrontendSymbolDecodedRawTokens.drop 500).take 500 ++
      ((verifiedFrontendSymbolDecodedRawTokens.drop 1000).take 500 ++
        (verifiedFrontendSymbolDecodedRawTokens.drop 1500).take 317)) := by
  with_unfolding_all rfl
end Lanius.Extraction
