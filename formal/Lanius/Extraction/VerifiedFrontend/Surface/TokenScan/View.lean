import Lanius.Extraction.VerifiedFrontend.Artifact.TokenScan.Cache.Assembly
import Lanius.Extraction.VerifiedFrontend.Artifact.TokenScan.Cache.Semantic
import Lanius.Extraction.ParseChecker

/-! The authenticated artifact and parse views for TokenScan. -/

/-! Artifact view. -/
namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendTokenScan_cache_checked_kernel :
    verifiedFrontendTokenScanCache.matches
      verifiedFrontendTokenScanArtifact = true := by
  with_unfolding_all rfl
def verifiedFrontendTokenScanView :
    ArtifactView verifiedFrontendTokenScanArtifact := {
  cache := verifiedFrontendTokenScanCache
  parseNodesWellFormed :=
    (verifiedFrontendTokenScanCache.ofMatches
      verifiedFrontendTokenScan_cache_checked_kernel).parseNodesWellFormed
  parseNodesRepresent :=
    (verifiedFrontendTokenScanCache.ofMatches
      verifiedFrontendTokenScan_cache_checked_kernel).parseNodesRepresent
  tokensWellFormed :=
    (verifiedFrontendTokenScanCache.ofMatches
      verifiedFrontendTokenScan_cache_checked_kernel).tokensWellFormed
  tokensRepresent :=
    (verifiedFrontendTokenScanCache.ofMatches
      verifiedFrontendTokenScan_cache_checked_kernel).tokensRepresent
  sourceBytesWellFormed :=
    (verifiedFrontendTokenScanCache.ofMatches
      verifiedFrontendTokenScan_cache_checked_kernel).sourceBytesWellFormed
  sourceBytesRepresent :=
    (verifiedFrontendTokenScanCache.ofMatches
      verifiedFrontendTokenScan_cache_checked_kernel).sourceBytesRepresent
}

end Lanius.Extraction

/-! Semantic-kind tree invariant. -/
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendTokenScan_semantic_tree_well_formed_kernel :
    verifiedFrontendTokenScanSemanticKindTree.WellFormed 64 := by
  apply Lanius.Data.SeqTree.wellFormed_sound
  with_unfolding_all rfl
end Lanius.Extraction

/-! Semantic-kind tree representation. -/
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendTokenScan_semantic_tree_represents_kernel :
    verifiedFrontendTokenScanSemanticKindTree.Represents verifiedFrontendTokenScanArtifact.semantic_token_kinds := by
  with_unfolding_all rfl
end Lanius.Extraction

/-! Parse view. -/
namespace Lanius.Extraction
def verifiedFrontendTokenScanParseView : ParseArtifactView verifiedFrontendTokenScanArtifact := {
  artifactView := verifiedFrontendTokenScanView
  leafCapacity := 64
  semanticKinds := verifiedFrontendTokenScanSemanticKindTree
  semanticKindsWellFormed := verifiedFrontendTokenScan_semantic_tree_well_formed_kernel
  semanticKindsRepresent := verifiedFrontendTokenScan_semantic_tree_represents_kernel
}
end Lanius.Extraction
