import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerClaimsQuoted
import Lanius.Extraction.ArtifactCacheQuote

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

def verifiedFrontendLexerTokenTree : ChunkTree Token :=
  artifact_pack_unit_token_tree%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/lexer.lani", 32

def verifiedFrontendLexerSourceByteTree : ChunkTree (Fin 256) :=
  artifact_pack_unit_source_byte_tree%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/lexer.lani", 0, 32

theorem verifiedFrontendLexer_token_tree_well_formed_kernel :
    verifiedFrontendLexerTokenTree.WellFormed := by
  cbv

theorem verifiedFrontendLexer_token_tree_kernel :
    verifiedFrontendLexerTokenTree.flatten =
      verifiedFrontendLexerArtifact.tokens := by
  cbv

theorem verifiedFrontendLexer_source_byte_tree_well_formed_kernel :
    verifiedFrontendLexerSourceByteTree.WellFormed := by
  cbv

theorem verifiedFrontendLexer_source_byte_tree_kernel :
    ∀ source, verifiedFrontendLexerArtifact.sources[0]? = some source →
      decodeBytes source.bytes =
        some verifiedFrontendLexerSourceByteTree.flatten := by
  intro source found
  cbv at found ⊢
  injection found with sourceEq
  subst source
  rfl

def verifiedFrontendLexerSpellingClaimValidFast
    (claim : SpellingClaim) : Bool :=
  tokenTextWithTrees? verifiedFrontendLexerArtifact
      verifiedFrontendLexerTokenTree verifiedFrontendLexerSourceByteTree
      claim.token = some claim.text &&
    parseNodeContainsTokenCached verifiedFrontendLexerArtifact
      claim.owner claim.token

theorem verifiedFrontendLexerSpellingClaimValidFast_eq
    (claim : SpellingClaim) :
    verifiedFrontendLexerSpellingClaimValidFast claim =
      spellingClaimValidCached verifiedFrontendLexerArtifact claim := by
  unfold verifiedFrontendLexerSpellingClaimValidFast spellingClaimValidCached
  rw [tokenTextWithTrees_eq
    verifiedFrontendLexer_token_tree_well_formed_kernel
    verifiedFrontendLexer_token_tree_kernel
    verifiedFrontendLexer_source_byte_tree_well_formed_kernel
    verifiedFrontendLexer_source_byte_tree_kernel]

theorem verifiedFrontendLexerSpellingClaimValidFast_sound
    (claim : SpellingClaim)
    (accepted : verifiedFrontendLexerSpellingClaimValidFast claim = true) :
    spellingClaimValidCached verifiedFrontendLexerArtifact claim = true := by
  rw [← verifiedFrontendLexerSpellingClaimValidFast_eq]
  exact accepted

end Lanius.Extraction

