import Lanius.Extraction.Reconstruction.Validated
import Lanius.Extraction.KernelReduction

namespace Lanius.Extraction.Reconstruction.Validated.Tests
private def view : ParseArtifactView Artifact.empty := {
  artifactView := ArtifactCache.ofMatches (cache := {
    leafCapacity := 8, parseNodes := .leaf [], tokens := .leaf [], primarySourceBytes := .leaf []
  }) (by kernel_rfl)
  leafCapacity := 8, semanticKinds := .leaf []
  semanticKindsWellFormed := Nat.zero_le 8
  semanticKindsRepresent := rfl
}
private def grammar : Grammar := {
  n_kinds := 1, n_nonterminals := 1, start_nonterminal := 0,
  split_token_kind := 0, split_component_kind := 0,
  canonical_kinds := [0], productions := [⟨0, []⟩, ⟨0, [1]⟩, ⟨0, [1, 1]⟩]
}
private def leaf : ParseNode := ⟨0, 0, 0, 0, []⟩
private def parent (children : List ParseChild) : ParseNode :=
  ⟨1, 0, 0, 0, children⟩
private def pair (children : List ParseChild) : ParseNode :=
  ⟨2, 0, 0, 0, children⟩
private def check (nodes : List ParseNode) :=
  (linkFrom grammar view 0 nodes []).map (List.map ParseTree.id)
private def reference (nodes : List ParseNode) :=
  if ParsePostorder.check grammar view 0 nodes [] then
    (ParseTree.link nodes).map (List.map ParseTree.id)
  else none
private def casesPass : Bool :=
  check [] == some [] &&
  check [leaf, leaf] == some [1, 0] &&
  check [leaf, parent [.node 0]] == some [1] &&
  check [leaf, leaf, pair [.node 0, .node 1]] == some [2] &&
  check [leaf, leaf, pair [.node 1, .node 0]] == none &&
  check [leaf, pair [.node 0, .node 0]] == none &&
  check [parent [.node 1], leaf] == none &&
  check [leaf, parent [.token 0]] == none &&
  ([{ leaf with production := 9 }, { leaf with nonterminal := 1 },
    { leaf with position_start := 1 }, { leaf with position_end := 1 }]).all
      (fun node => check [node] == none)
example : casesPass = true := by kernel_rfl
#guard casesPass

private def listsUpTo (values : List α) : Nat → List (List α)
  | 0 => [[]]
  | n + 1 => [] :: values.flatMap (fun value => (listsUpTo values n).map (value :: ·))
-- Explore acceptance/rejection against the existing validation-plus-linking
-- composition. Exact returned-forest identity on success is proved generally.
#guard (listsUpTo [leaf, parent [], parent [.node 0], parent [.node 1],
    parent [.node 2], parent [.token 0], pair [.node 0, .node 1],
    pair [.node 1, .node 0], pair [.node 0, .node 0],
    { leaf with production := 9 }, { leaf with position_end := 1 }] 3).all
    (fun nodes => check nodes == reference nodes)
#print axioms linkFrom_linked
#print axioms linkFrom_nodes
#print axioms checkedView_sound
end Lanius.Extraction.Reconstruction.Validated.Tests
