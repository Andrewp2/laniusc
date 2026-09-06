import Lanius.Extraction.Reconstruction.Checked
import Lanius.Extraction.KernelReduction

namespace Lanius.Extraction.Reconstruction.Tests

private def node (production : Nat) (children : List ParseChild := []) : ParseNode := {
  production, children, nonterminal := 0, position_start := 0, position_end := 0
}

private def artifact (nodes : List ParseNode) (root : Option Nat) : Artifact := {
  schema_version := schemaVersion, sources := [], tokens := [], semantic_token_kinds := [],
  parse_nodes := nodes, parse_root := root, surface := none, resolutions := [],
  types := [], core_program := none, lowering := []
}

private def emptyFile := artifact [node 2, node 0 [.node 0]] (some 1)

private def expected : SurfaceFile := { id := 0, parse_node := 1, value := { items := [] } }

-- A linked computation and its transported certificate return the same AST.
private theorem linked : checkedWithAccess emptyFile = some expected := by kernel_rfl

private def view : ArtifactView emptyFile :=
  ArtifactCache.ofMatches (cache := ArtifactCache.ofArtifact emptyFile) (by kernel_rfl)
example : checkedView emptyFile view = some expected := by kernel_rfl
example (artifact : Artifact) (view : ArtifactView artifact) :
    checkedView artifact view = @checkedWithAccess (ArtifactAccess.ofView view) artifact :=
  checkedView_eq view

example : reconstructArtifactSurfaceWithAccess emptyFile = some expected :=
  checkedWithAccess_sound (fun _ => rfl) linked

-- Selection uses the declared ID, not whichever forest root comes first.
example : checkedWithAccess (artifact [node 2, node 0 [.node 0], node 2] (some 1)) =
    some expected := by kernel_rfl

example : checkedWithAccess (artifact emptyFile.parse_nodes none) = none := by kernel_rfl
example : checkedWithAccess (artifact emptyFile.parse_nodes (some 99)) = none := by kernel_rfl
example : checkedWithAccess (artifact [] (some 0)) = none := by kernel_rfl

-- Linked trees are not grammar certificates: bad production/child kind fails.
example : checkedWithAccess (artifact [node 2, node 1 [.node 0]] (some 1)) = none := by kernel_rfl
example : checkedWithAccess (artifact [node 0 [.token 0]] (some 0)) = none := by kernel_rfl
example : checkedWithAccess (artifact [node 0 [.node 9]] (some 0)) = none := by kernel_rfl

-- Full functional agreement includes arbitrary counters and exhausted fuel.
example (fuel state : Nat) (ref : ParseTree.Checked emptyFile.parse_nodes) :
    (reconstructFile fuel emptyFile ref).run state =
      (reconstructFile fuel emptyFile ref.val.id).run state :=
  congrFun (file_eq (ParseReference.checked_agrees emptyFile (fun _ => rfl)) fuel ref).symm state

example (ref : ParseTree.Checked emptyFile.parse_nodes) (state : Nat) :
    (reconstructItems 0 emptyFile ref).run state = none := rfl

#print axioms checkedView_sound
#print axioms checkedView_eq

end Lanius.Extraction.Reconstruction.Tests
