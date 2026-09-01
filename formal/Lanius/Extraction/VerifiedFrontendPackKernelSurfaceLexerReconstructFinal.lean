import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructFastCell0

namespace Lanius.Extraction

set_option maxRecDepth 100000

theorem reconstructFile_step
    {artifact : Artifact} {fuel root itemsNode : Nat}
    {start finish : SurfaceNodeId} {items : List SurfaceItem}
    (productionFound : artifactProduction? artifact root = some 0)
    (itemsChildFound : artifactChildNode? artifact root 0 = some itemsNode)
    (itemsFound : (reconstructItems fuel artifact itemsNode).run start =
      some (items, finish)) :
    (reconstructFile (fuel + 1) artifact root).run start = some ({
      id := finish
      parse_node := root
      value := { items }
    }, finish + 1) := by
  unfold reconstructFile artifactExpectProduction
  simp [productionFound, itemsChildFound, itemsFound, freshSurfaceNodeId]

theorem verifiedFrontendLexer_root_production_kernel :
    artifactProduction? verifiedFrontendLexerArtifact 6990 = some 0 := by
  unfold artifactProduction?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 29 (by omega)]
  rfl

theorem verifiedFrontendLexer_root_items_child_kernel :
    artifactChildNode? verifiedFrontendLexerArtifact 6990 0 = some 6989 := by
  unfold artifactChildNode?
  rw [verifiedFrontendLexer_artifactNode_spine_kernel 29 (by omega)]
  rfl

def verifiedFrontendLexerReconstructedKernel : SurfaceFile := {
      id := 1107
      parse_node := 6990
      value := { items := verifiedFrontendLexerProposedItemsKernel }
    }

theorem verifiedFrontendLexer_proposed_id_kernel :
    verifiedFrontendLexerProposedKernel.id = 1107 := by rfl

theorem verifiedFrontendLexer_proposed_parse_node_kernel :
    verifiedFrontendLexerProposedKernel.parse_node = 6990 := by rfl

theorem verifiedFrontendLexer_proposed_items_kernel :
    verifiedFrontendLexerProposedKernel.value.items =
      verifiedFrontendLexerProposedItemsKernel := by rfl

theorem verifiedFrontendLexer_proposed_eq_reconstructed_kernel :
    verifiedFrontendLexerProposedKernel =
      verifiedFrontendLexerReconstructedKernel := by
  cases proposed : verifiedFrontendLexerProposedKernel with
  | mk id parseNode value =>
      cases value with
      | mk items =>
          simp only [proposed] at
            verifiedFrontendLexer_proposed_id_kernel
            verifiedFrontendLexer_proposed_parse_node_kernel
            verifiedFrontendLexer_proposed_items_kernel
          subst id
          subst parseNode
          subst items
          rfl

theorem verifiedFrontendLexer_reconstruct_file_kernel :
    (reconstructFile 6992 verifiedFrontendLexerArtifact 6990).run 0 =
      some (verifiedFrontendLexerReconstructedKernel, 1108) := by
  unfold verifiedFrontendLexerReconstructedKernel
  exact reconstructFile_step
    verifiedFrontendLexer_root_production_kernel
    verifiedFrontendLexer_root_items_child_kernel
    verifiedFrontendLexer_reconstruct_items_fast0_kernel

theorem verifiedFrontendLexer_parse_root_value_kernel :
    verifiedFrontendLexerArtifact.parse_root = some 6990 := by
  rfl

theorem verifiedFrontendLexer_parse_nodes_length_kernel :
    verifiedFrontendLexerArtifact.parse_nodes.length = 6991 := by
  simp [verifiedFrontendLexerArtifact, verifiedFrontendLexerNodeChunks,
    verifiedFrontendLexerParseNodes0_length,
    verifiedFrontendLexerParseNodes1_length,
    verifiedFrontendLexerParseNodes2_length,
    verifiedFrontendLexerParseNodes3_length,
    verifiedFrontendLexerParseNodes4_length,
    verifiedFrontendLexerParseNodes5_length,
    verifiedFrontendLexerParseNodes6_length]

theorem verifiedFrontendLexer_reconstructed_kernel :
    reconstructArtifactSurface verifiedFrontendLexerArtifact =
      some verifiedFrontendLexerReconstructedKernel := by
  unfold reconstructArtifactSurface
  rw [verifiedFrontendLexer_parse_root_value_kernel]
  rw [verifiedFrontendLexer_parse_nodes_length_kernel]
  simp [verifiedFrontendLexer_reconstruct_file_kernel]

end Lanius.Extraction
