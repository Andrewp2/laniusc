import verified_compiler.tests.direct_ir_builder_navigation

namespace IRPairNavigationProof

open Lanius Lanius.Core Lanius.Semantics IRBuilderNavigationProof IRChildrenProof IRNavigationProof

/-- Derive the two child positions from the builder's existing chain. The
    right child follows the whole left subtree, not necessarily one node. -/
theorem coordinates (tree : Ready region state) (inside : index < region.count)
    (arity : region.arities index = 2) :
    index + 1 < region.count ∧ index + 1 < (tree.ends (index + 1)).toNat ∧
      (tree.ends (index + 1)).toNat < region.count ∧
      ((tree.ends (index + 1)).toNat : Int) = tree.ends (index + 1) := by
  have children := tree.childrenStart inside
  simp only [Ready.Children, arity] at children
  cases children with
  | cons leftInside _ forward _ rest =>
      cases rest with
      | cons rightInside _ _ _ _ => exact ⟨leftInside, by omega, rightInside, by omega⟩

/-- Both real navigation calls preserve the caller while identifying the
    right child from the left subtree's endpoint. Successful calls are derived. -/
theorem actualPair (tree : Ready region state) (inside : index < region.count)
    (arity : region.arities index = 2) (formed : state.CellsWellFormed) :
    ∃ after, RunsExprs extractedProgram state
      [tree.firstChildCall index, siblingCall tree.value index (index + 1)]
      [.signed .i32 (index + 1 : Nat), .signed .i32 (tree.ends (index + 1))] after ∧
      PureFrame state after := by
  have first := tree.firstChild inside formed
  simp only [Ready.firstIndex, arity, show ¬(2 : Int) ≤ 0 by decide, ↓reduceIte] at first
  obtain ⟨middle, firstRun, firstFrame⟩ := first
  have children := tree.childrenStart inside
  simp only [Ready.Children, arity] at children
  have next := (tree.reheap firstFrame.heap).nextChild (parent := index) (current := index + 1)
    (remaining := 1) (by omega) (by simpa [Ready.Children, Ready.reheap, arity] using children)
    firstFrame.afterFormed
  simp only [show ¬(1 : Nat) = 0 by decide, ↓reduceIte] at next
  obtain ⟨after, nextRun, nextFrame⟩ := next
  exact ⟨after, .cons (by simpa only [Int.natCast_add, Int.natCast_one] using firstRun)
    (.cons nextRun .nil), firstFrame.trans nextFrame⟩

#print axioms coordinates
#print axioms actualPair

end IRPairNavigationProof
