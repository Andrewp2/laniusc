import Lanius.Extraction.Reconstruction.Validated
namespace Lanius.Extraction.Representation
open Reconstruction.Validated
theorem step (grammar : Grammar) (view : ParseArtifactView artifact)
    (id : Nat) (value : ParseNode) (rest : List ParseNode)
    (stack : List ParseTree) (children : List (Option ParseTree))
    (tail forest : List ParseTree)
    (consumed : ParseTree.consumeChildren value.children stack = some (children, tail))
    (valid : ParsePostorder.node grammar view id value
      (children.filterMap fun child => child.map fun tree => (tree.id, tree.value)) = true)
    (next : linkFrom grammar view (id + 1) rest (.node id value children :: tail) = some forest) :
    linkFrom grammar view id (value :: rest) stack = some forest := by
  simpa [linkFrom, consumed, valid] using next

def finish (grammar : Grammar) (view : ParseArtifactView artifact)
    (forest : List ParseTree)
    (accepted : linkFrom grammar view 0 artifact.parse_nodes [] = some forest) : Option SurfaceFile :=
  letI := ArtifactAccess.ofView view.artifactView
  do
    let checked := forest.attach.map fun tree =>
      (⟨tree.val, ParseTree.link_sound artifact.parse_nodes forest
        (linkFrom_linked grammar view 0 artifact.parse_nodes [] forest accepted)
        tree.val tree.property⟩ : ParseTree.Checked artifact.parse_nodes)
    let rootId ← artifact.parse_root
    let root ← checked.find? (fun tree => tree.val.id == rootId)
    let (surface, _) ← (reconstructFile (view.artifactView.nodeCount + 1) artifact root).run 0
    pure surface

theorem finish_eq (grammar : Grammar) (view : ParseArtifactView artifact)
    (forest : List ParseTree)
    (accepted : linkFrom grammar view 0 artifact.parse_nodes [] = some forest) :
    checkedView grammar view = finish grammar view forest accepted := by
  unfold checkedView checkedForest finish
  split
  · rename_i absent
    rw [accepted] at absent
    contradiction
  · rename_i result found
    have same : result = forest := Option.some.inj (found.symm.trans accepted)
    subst result
    rfl
end Lanius.Extraction.Representation

