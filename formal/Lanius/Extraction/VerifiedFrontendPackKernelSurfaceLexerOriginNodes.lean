import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerOriginNodes0
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerOriginNodes1
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerOriginNodes2
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerOriginNodes3

namespace Lanius.Extraction

set_option maxRecDepth 100000

theorem verifiedFrontendLexer_node_origin_trace_checked_kernel :
    nodeOriginPathsValid verifiedFrontendLexerArtifact verifiedFrontendLexerView
      verifiedFrontendLexerOrigins.claims.nodes
      verifiedFrontendLexerOrigins.nodePaths = true := by
  let claims0 := verifiedFrontendLexerOrigins.claims.nodes.take 277
  let claims1 := (verifiedFrontendLexerOrigins.claims.nodes.drop 277).take 277
  let claims2 := (verifiedFrontendLexerOrigins.claims.nodes.drop 554).take 277
  let claims3 := verifiedFrontendLexerOrigins.claims.nodes.drop 831
  let paths0 := verifiedFrontendLexerOrigins.nodePaths.take 277
  let paths1 := (verifiedFrontendLexerOrigins.nodePaths.drop 277).take 277
  let paths2 := (verifiedFrontendLexerOrigins.nodePaths.drop 554).take 277
  let paths3 := verifiedFrontendLexerOrigins.nodePaths.drop 831
  have claimsSplit : verifiedFrontendLexerOrigins.claims.nodes =
      claims0 ++ (claims1 ++ (claims2 ++ claims3)) := by
    with_unfolding_all rfl
  have pathsSplit : verifiedFrontendLexerOrigins.nodePaths =
      paths0 ++ (paths1 ++ (paths2 ++ paths3)) := by
    with_unfolding_all rfl
  rw [claimsSplit, pathsSplit]
  rw [nodeOriginPathsValid_append _ _ claims0 _ paths0 _
    (by with_unfolding_all rfl)]
  rw [nodeOriginPathsValid_append _ _ claims1 _ paths1 _
    (by with_unfolding_all rfl)]
  rw [nodeOriginPathsValid_append _ _ claims2 _ paths2 _
    (by with_unfolding_all rfl)]
  simpa [claims0, claims1, claims2, claims3, paths0, paths1, paths2, paths3,
    verifiedFrontendLexer_node_origins_0_checked_kernel,
    verifiedFrontendLexer_node_origins_1_checked_kernel,
    verifiedFrontendLexer_node_origins_2_checked_kernel] using
      verifiedFrontendLexer_node_origins_3_checked_kernel

end Lanius.Extraction
