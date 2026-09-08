import Lanius.Core
import Lanius.Semantics.CellRenaming.Permutation

namespace Lanius.Semantics.CellRenaming
open Lanius.Core

/-! Cell identities occur in references and slices, including those nested in
aggregate values. Native byte addresses and global type IDs do not change. -/
mutual
  def value (rename : CellId → CellId) : Value → Value
    | .array entries => .array (values rename entries)
    | .structure id entries => .structure id (values rename entries)
    | .enumeration id variant entries => .enumeration id variant (values rename entries)
    | .slice type cell path start length => .slice type (rename cell) path start length
    | .reference type cell path => .reference type (rename cell) path
    | other => other
  def values (rename : CellId → CellId) : List Value → List Value
    | [] => []
    | first :: rest => value rename first :: values rename rest
end

theorem values_eq_map (rename : CellId → CellId) (entries : List Value) :
    values rename entries = entries.map (value rename) := by
  induction entries <;> simp_all [values]

mutual
  theorem value_leftInverse (outer inner : CellId → CellId)
      (inverse : Function.LeftInverse outer inner) (entry : Value) :
      value outer (value inner entry) = entry := by
    have inverseEq : ∀ cell, outer (inner cell) = cell := inverse
    cases entry <;> simp only [value, values_leftInverse outer inner inverse, inverseEq]
  theorem values_leftInverse (outer inner : CellId → CellId)
      (inverse : Function.LeftInverse outer inner) (entries : List Value) :
      values outer (values inner entries) = entries := by
    cases entries <;> simp only [values, value_leftInverse outer inner inverse,
      values_leftInverse outer inner inverse]
end

theorem value_injective (rename : Permutation boundary) : Function.Injective (value rename.forward) := by
  intro left right same
  have recovered := congrArg (value rename.backward) same
  simpa only [value_leftInverse _ _ rename.leftInverse] using recovered

end Lanius.Semantics.CellRenaming
