import Lanius.Data.SeqTree
import Lanius.Extraction.KernelReduction

namespace Lanius.Data.SeqTreeTests
private def tree : SeqTree Nat :=
  .branch 4 3 (.branch 2 2 (.leaf [3]) (.leaf [5])) (.leaf [8, 13])

private def agrees : Bool :=
  (List.range 16).all fun index => tree.lookup index == tree.flatten[index]?

-- Kernel reduction and compiled evaluation exercise the same boundary cases:
-- both sides of each branch, leaf ends, and out-of-bounds indices.
example : tree.wellFormed 2 = true := by kernel_rfl
example : agrees = true := by kernel_rfl
#guard agrees

private def emptyAgrees : Bool :=
  (List.range 4).all fun index => (SeqTree.leaf ([] : List Nat)).lookup index == none
example : emptyAgrees = true := by kernel_rfl
#guard emptyAgrees

-- Lookup does not authenticate metadata itself. The validity gate still
-- rejects forged sizes before callers may use lookup_eq_flatten.
private def forged : SeqTree Nat :=
  .branch 4 3 (.branch 999 2 (.leaf [3]) (.leaf [5])) (.leaf [8, 13])
example : forged.wellFormed 2 = false := by kernel_rfl
example : forged.lookup 2 = none := by kernel_rfl
#guard forged.lookup 2 == none

#print axioms SeqTree.lookup_eq_flatten
end Lanius.Data.SeqTreeTests
