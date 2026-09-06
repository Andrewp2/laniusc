import Lanius.Extraction.KernelReduction

/-! A certificate tactic must reject false goals even when elaborator-side
definitional equality is deliberately skipped. -/
namespace Lanius.Extraction.KernelReductionTests

-- No decidable equality instance: the kernel checks constructor equality.
inductive Tree where
  | leaf : Nat → Tree
  | branch : Tree → Tree → Tree

private def tree : Tree := .branch (.leaf (2 + 3)) (.leaf 7)

theorem tree_exact : tree = .branch (.leaf 5) (.leaf 7) := by kernel_rfl

private def sameTree (left right : Tree) : Prop := left = right
example : sameTree tree (.branch (.leaf 5) (.leaf 7)) := by kernel_rfl

example : (List.range 8).length = 8 := by
  let count := 8
  have : (List.range count).length = count := by kernel_rfl
  exact this

example : True := by
  fail_if_success have : tree = .branch (.leaf 6) (.leaf 7) := by kernel_rfl
  fail_if_success have : (1 : Nat) = 2 := by kernel_rfl
  fail_if_success kernel_rfl
  trivial

example (n : Nat) : n = n := by
  fail_if_success kernel_rfl
  rfl

end Lanius.Extraction.KernelReductionTests
