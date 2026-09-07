import Lanius.Extraction.CanonicalTokens.Dispatch.Specification

namespace Lanius.Extraction.CanonicalTokens.Dispatch

def Consistent (table : List Row) : Prop :=
  ∀ left ∈ table, ∀ right ∈ table, left.1 = right.1 → left.2 = right.2

theorem Consistent.perm (consistent : Consistent left) (permutation : left.Perm right) :
    Consistent right := by
  intro first firstMember second secondMember same
  exact consistent first (permutation.mem_iff.mpr firstMember)
    second (permutation.mem_iff.mpr secondMember) same

/-- Reordering an unambiguous keyword table does not change lookup. -/
theorem lookup_permutation (query : List Int) (fallback : Int)
    (permutation : left.Perm right) (consistent : Consistent left) :
    lookup query left fallback = lookup query right fallback := by
  induction permutation with
  | nil => rfl
  | cons row permutation ih =>
      have tail : Consistent _ := fun first fm second sm same =>
        consistent first (List.mem_cons_of_mem row fm) second (List.mem_cons_of_mem row sm) same
      simp only [lookup]
      split
      · rfl
      · exact ih tail
  | swap first second rest =>
      by_cases a : query = first.1
      · by_cases b : query = second.1
        · have equal := consistent second (by simp) first (by simp) (b.symm.trans a)
          simp [lookup, a, b, equal]
        · simp_all [lookup]
      · by_cases b : query = second.1 <;> simp_all [lookup]
  | trans first second ihFirst ihSecond =>
      exact (ihFirst consistent).trans (ihSecond (consistent.perm first))

theorem reference_consistent : Consistent referenceRows := by
  unfold Consistent
  decide

def checkReference? (program : Lanius.Core.Program) (groups : List Group) :
    Option (PLift ((rows program groups).Perm referenceRows)) :=
  if same : (rows program groups).Perm referenceRows then some ⟨same⟩ else none

theorem dispatched_reference (program : Lanius.Core.Program) (source : List Int) (start width : Nat)
    (fallback : Lanius.ConstantId) (groups : List Group)
    (valid : ∀ group ∈ groups, ∀ rule ∈ group.rules, ValidRule program group.width rule)
    (reference : (rows program groups).Perm referenceRows)
    (identifier : tag program fallback = 1)
    (capacity : start + width ≤ source.length) :
    dispatched program source start width fallback groups =
      lookup ((source.drop start).take width) referenceRows 1 := by
  rw [dispatched_lookup program source start width fallback groups valid capacity, identifier]
  exact lookup_permutation _ _ reference (reference_consistent.perm reference.symm)

end Lanius.Extraction.CanonicalTokens.Dispatch
