import Lanius.Extraction.SurfaceReconstruct

namespace Lanius.Extraction

theorem reconstructItems_cons_of [ArtifactAccess]
    {fuel : Nat} {artifact : Artifact} {nodeId itemNode restNode : ParseNodeId}
    {start middle finish : SurfaceNodeId} {item : SurfaceItem}
    {items : List SurfaceItem}
    (productionFound : artifactProduction? artifact nodeId = some 1)
    (itemChildFound : artifactChildNode? artifact nodeId 0 = some itemNode)
    (restChildFound : artifactChildNode? artifact nodeId 1 = some restNode)
    (itemFound : (reconstructItem fuel artifact itemNode).run start =
      some (item, middle))
    (restFound : (reconstructItems fuel artifact restNode).run middle =
      some (items, finish)) :
    (reconstructItems (fuel + 1) artifact nodeId).run start =
      some (item :: items, finish) := by
  rw [reconstructItems]
  simp [productionFound, itemChildFound, restChildFound, itemFound, restFound]

theorem reconstructFile_of [ArtifactAccess]
    {fuel : Nat} {artifact : Artifact} {root itemsNode : ParseNodeId}
    {start finish : SurfaceNodeId} {items : List SurfaceItem}
    (productionFound : artifactProduction? artifact root = some 0)
    (itemsChildFound : artifactChildNode? artifact root 0 = some itemsNode)
    (itemsFound : (reconstructItems fuel artifact itemsNode).run start =
      some (items, finish)) :
    (reconstructFile fuel artifact root).run start = some ({
      id := finish
      parse_node := root
      value := { items }
    }, finish + 1) := by
  unfold reconstructFile artifactExpectProduction
  simp [productionFound, itemsChildFound, itemsFound, freshSurfaceNodeId]

end Lanius.Extraction
