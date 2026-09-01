import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructProposedEq
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructExactCell0

namespace Lanius.Extraction

set_option maxRecDepth 100000

theorem reconstructFile_step
    {artifact : Artifact} {fuel root itemsNode : Nat}
    {start finish : SurfaceNodeId} {items : List SurfaceItem}
    (productionFound : artifactProduction? artifact root = some 0)
    (itemsChildFound : artifactChildNode? artifact root 0 = some itemsNode)
    (itemsFound : (reconstructItems (fuel + 1) artifact itemsNode).run start =
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

end Lanius.Extraction
