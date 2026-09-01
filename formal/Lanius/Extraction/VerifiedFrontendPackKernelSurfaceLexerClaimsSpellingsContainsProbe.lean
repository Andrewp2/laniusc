import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerClaimsSpellingChunks
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false
theorem verifiedFrontendLexer_claims_spellings_contains_probe :
    verifiedFrontendLexerSpellingClaimsChunk0.all (fun claim =>
      parseNodeContainsTokenCached verifiedFrontendLexerArtifact
        claim.owner claim.token) = true := by cbv
end Lanius.Extraction
