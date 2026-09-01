import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerClaimsSpellingChunks
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false
theorem verifiedFrontendLexer_claims_spellings_text_probe :
    verifiedFrontendLexerSpellingClaimsChunk0.all (fun claim =>
      tokenTextWithUniformChunks? verifiedFrontendLexerArtifact
          128 verifiedFrontendLexerTokenCache
          287 verifiedFrontendLexerSourceByteCache
          claim.token = some claim.text) = true := by cbv
end Lanius.Extraction
