import Lanius.Extraction.ArtifactCacheQuote
import Lanius.Extraction.KernelReduction
import Lean.Util.CollectAxioms

namespace Lanius.Extraction.Tests.Quotation

private def values : List Nat := (List.range 300).map (fun n => n * n + 1)

elab "proof_data%" : term => quoteBounded values (compile := false)
elab "runtime_data%" : term => quoteBounded values

elab "shared_data%" : term => do
  let first ← quoteBounded values (compile := false)
  let second ← quoteBounded values (compile := false)
  unless first == second do
    throwError "identical proof quotations did not share checked constructor data"
  return second

elab "different_data%" : term => quoteBounded (values ++ [17]) (compile := false)

noncomputable def proofData : List Nat := proof_data%
noncomputable def sharedData : List Nat := shared_data%
noncomputable def differentData : List Nat := different_data%
def runtimeData : List Nat := runtime_data%

theorem proofData_exact : proofData = values := by decide +kernel
theorem runtimeData_exact : runtimeData = values := by decide +kernel
theorem sharedData_exact : sharedData = values := by decide +kernel
theorem differentData_exact : differentData = values ++ [17] := by decide +kernel

-- Opaque heads cannot be re-decoded; only the list spine is available.
-- This also covers empty, singleton, odd, and cross-leaf table sizes.
opaque retainedHead : Nat := 17
private noncomputable def retained : List (Lanius.Data.SeqTree Nat) := [
  seq_tree% ([] : List Nat), 8,
  seq_tree% [retainedHead], 8,
  seq_tree% (List.replicate 17 retainedHead), 8,
  seq_tree% values, 8]

theorem retained_exact : retained.map (·.flatten) =
    [[], [retainedHead], List.replicate 17 retainedHead, values] := by kernel_rfl

theorem retained_balanced : retained.all (·.wellFormed 8) = true := by decide +kernel

private def emptyTree : Lanius.Data.SeqTree Nat := .leaf []

private def branchTree : Lanius.Data.SeqTree Nat :=
  .branch 4 2 (.leaf [1, 2]) (.leaf [3, 4])

private def malformedTree : Lanius.Data.SeqTree Nat :=
  .branch 3 2 (.leaf [1, 2]) (.leaf [3, 4])

private def checkedEmpty :=
  seq_tree_checked% ([] : List Nat), 2

private def checkedSingleton :=
  seq_tree_checked% [retainedHead], 2

private def checkedLocal (head : Nat) :=
  seq_tree_checked% [head, 2, 3], 1

private def sevenTree :=
  seq_tree_checked% [retainedHead, 2, 3, 4, 5, 6, 7], 2

private def polymorphicTree {α : Type u} (value : α) :=
  seq_tree_checked% [some value, none], 1

theorem checkedEmpty_cases :
    checkedEmpty.val.flatten = [] ∧ checkedEmpty.val.Represents [] := by
  exact ⟨rfl, checkedEmpty.property⟩

theorem checkedSingleton_cases :
    checkedSingleton.val.flatten = [retainedHead] ∧
      checkedSingleton.val.Represents [retainedHead] := by
  exact ⟨rfl, checkedSingleton.property⟩

theorem checkedLocal_cases (head : Nat) :
    (checkedLocal head).val.flatten = [head, 2, 3] ∧
      (checkedLocal head).val.wellFormed 1 = true ∧
      (checkedLocal head).val.Represents [head, 2, 3] := by
  exact ⟨rfl, rfl, (checkedLocal head).property⟩

theorem sevenTree_cases :
    sevenTree.val.flatten = [retainedHead, 2, 3, 4, 5, 6, 7] ∧
      sevenTree.val.wellFormed 2 = true ∧
      sevenTree.val.WellFormed 2 ∧
      sevenTree.val.Represents [retainedHead, 2, 3, 4, 5, 6, 7] := by
  refine ⟨rfl, by decide +kernel, ?_, sevenTree.property⟩
  exact Lanius.Data.SeqTree.wellFormed_sound (by decide)

theorem sevenTree_rejects_bad_sources :
    (¬ sevenTree.val.Represents [retainedHead, 3, 2, 4, 5, 6, 7]) ∧
      (¬ sevenTree.val.Represents [retainedHead, 2, 3, 4, 5, 6, 8]) := by
  constructor
  · intro equal
    change [retainedHead, 2, 3, 4, 5, 6, 7] =
      [retainedHead, 3, 2, 4, 5, 6, 7] at equal
    cases equal
  · intro equal
    change [retainedHead, 2, 3, 4, 5, 6, 7] =
      [retainedHead, 2, 3, 4, 5, 6, 8] at equal
    cases equal

theorem polymorphicTree_cases {α : Type u} (value : α) :
    (polymorphicTree value).val.flatten = [some value, none] ∧
      (polymorphicTree value).val.wellFormed 1 = true ∧
      (polymorphicTree value).val.Represents [some value, none] := by
  exact ⟨rfl, rfl, (polymorphicTree value).property⟩

/- The elaborator rejects a zero leaf capacity before emitting a tree. -/
/--
error: sequence leaf capacity must be positive
-/
#guard_msgs (error, substring := true) in
#check seq_tree_checked% ([] : List Nat), 0

theorem emptyTree_represents : emptyTree.Represents [] := by
  apply Lanius.Data.SeqTree.represents_of_rangeEq (tree := emptyTree) (leafCapacity := 0)
  · simp [emptyTree, Lanius.Data.SeqTree.WellFormed]
  · rfl
  · decide

theorem branchTree_represents : branchTree.Represents [1, 2, 3, 4] := by
  apply Lanius.Data.SeqTree.represents_of_rangeEq (tree := branchTree) (leafCapacity := 2)
  · simp [branchTree, Lanius.Data.SeqTree.WellFormed,
      Lanius.Data.SeqTree.size, Lanius.Data.SeqTree.height]
  · rfl
  · decide

theorem branchTree_rejects_wrong_value :
    branchTree.rangeEq 0 [1, 2, 9, 4] = false := by decide

theorem branchTree_rejects_wrong_order :
    branchTree.rangeEq 0 [1, 3, 2, 4] = false := by decide

theorem branchTree_prefix_requires_size :
    branchTree.rangeEq 0 [1, 2] = true ∧
      branchTree.size ≠ [1, 2].length ∧
      ¬ branchTree.Represents [1, 2] := by
  refine ⟨by decide, by decide, ?_⟩
  simp [branchTree, Lanius.Data.SeqTree.Represents, Lanius.Data.SeqTree.flatten]

theorem malformedTree_rejected :
    malformedTree.wellFormed 2 = false ∧
      malformedTree.rangeEq 0 [1, 2, 3] = true ∧
      malformedTree.size = [1, 2, 3].length ∧
      ¬ malformedTree.Represents [1, 2, 3] := by
  refine ⟨by decide, by decide, rfl, ?_⟩
  simp [malformedTree, Lanius.Data.SeqTree.Represents, Lanius.Data.SeqTree.flatten]

#eval show IO Unit from do
  unless runtimeData == values do
    throw (IO.userError "default quotation no longer supports executable consumers")

run_elab do
  for name in #[``proofData, ``runtimeData, ``proofData_exact, ``runtimeData_exact,
      ``sharedData_exact, ``differentData_exact, ``retained_exact, ``retained_balanced,
      ``checkedEmpty_cases, ``checkedSingleton_cases, ``checkedLocal_cases,
      ``sevenTree_cases, ``sevenTree_rejects_bad_sources,
      ``polymorphicTree_cases,
      ``emptyTree_represents, ``branchTree_represents,
      ``branchTree_rejects_wrong_value, ``branchTree_rejects_wrong_order,
      ``branchTree_prefix_requires_size, ``malformedTree_rejected,
      ``Lanius.Data.SeqTree.represents_of_rangeEq] do
    for assumption in ← Lean.collectAxioms name do
      unless #[``propext, ``Classical.choice, ``Quot.sound].contains assumption do
        throwError "Data quotation {name} uses unexpected axiom {assumption}"

end Lanius.Extraction.Tests.Quotation
