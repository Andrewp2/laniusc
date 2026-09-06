import Lanius.Extraction.ParseTree

namespace Lanius.Extraction.ParseTreeTests

private def leaf : ParseNode := {
  production := 0, nonterminal := 0, position_start := 0,
  position_end := 0, children := []
}

private def parent (children : List ParseChild) : ParseNode := { leaf with children }

private def sample : List ParseNode :=
  [leaf, leaf, parent [.node 0, .token 7, .node 1]]

private def childIdAt (index : Nat) : Option Nat := do
  let forest ← ParseTree.checkedForest sample
  let root ← forest.head?
  let child ← root.child? index
  pure child.val.id

example : (ParseTree.link sample).map (List.map ParseTree.id) = some [2] := by
  decide +kernel

example : childIdAt 0 = some 0 := by decide +kernel
example : childIdAt 1 = none := by decide +kernel
example : childIdAt 2 = some 1 := by decide +kernel
example : childIdAt 3 = none := by decide +kernel

-- Empty input and independent roots are valid forests, not successful files.
example : (ParseTree.link []).map List.length = some 0 := by decide +kernel
example : (ParseTree.link [leaf, leaf]).map (List.map ParseTree.id) = some [1, 0] := by
  decide +kernel

-- No future, missing, duplicated, or reordered child reference is guessed.
example : (ParseTree.link [parent [.node 1], leaf]).isNone = true := by
  decide +kernel
example : (ParseTree.link [leaf, parent [.node 9]]).isNone = true := by
  decide +kernel
example : (ParseTree.link [leaf, parent [.node 0, .node 0]]).isNone = true := by
  decide +kernel
example : (ParseTree.link [leaf, leaf, parent [.node 1, .node 0]]).isNone = true := by
  decide +kernel

end Lanius.Extraction.ParseTreeTests
