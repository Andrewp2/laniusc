import Lanius.Typing
import Lanius.Semantics

namespace Lanius.Semantics

open Lanius.Core Lanius.Typing

/-- The interpreter's list update is the standard length-preserving update. -/
theorem setValue_eq_set (values : List Value) (index : Nat) (replacement : Value) :
    setValue values index replacement = values.set index replacement := by
  induction values generalizing index with
  | nil => rfl
  | cons value values ih => cases index <;> simp [setValue, List.set, ih]

end Lanius.Semantics

namespace Lanius.Typing

open Lanius.Core Lanius.Semantics

theorem ValuesHaveTypes.drop (typed : ValuesHaveTypes program values types) (count : Nat) :
    ValuesHaveTypes program (values.drop count) (types.drop count) := by
  induction count generalizing values types with
  | zero => exact typed
  | succ count ih => cases typed with
    | nil => exact .nil
    | cons head tail => exact ih tail

theorem ValuesHaveTypes.take (typed : ValuesHaveTypes program values types) (count : Nat) :
    ValuesHaveTypes program (values.take count) (types.take count) := by
  induction count generalizing values types with
  | zero => exact .nil
  | succ count ih => cases typed with
    | nil => exact .nil
    | cons head tail => exact .cons head (ih tail)

theorem ValuesHaveTypes.get {index : Nat} (typed : ValuesHaveTypes program values types)
    (found : types[index]? = some type) :
    ∃ value, values[index]? = some value ∧ ValueHasType program value type := by
  induction index generalizing values types with
  | zero =>
    cases typed with
    | nil => simp at found
    | cons head tail =>
      simp only [List.getElem?_cons_zero, Option.some.injEq] at found
      subst type
      exact ⟨_, rfl, head⟩
  | succ index ih =>
    cases typed with
    | nil => simp at found
    | cons head tail => exact ih tail (by simpa using found)

theorem ValuesHaveTypes.set {index : Nat} (typed : ValuesHaveTypes program values types)
    (found : types[index]? = some type) (replacementTyped : ValueHasType program replacement type) :
    ValuesHaveTypes program (setValue values index replacement) types := by
  induction index generalizing values types with
  | zero =>
    cases typed with
    | nil => simp at found
    | cons head tail =>
      simp only [List.getElem?_cons_zero, Option.some.injEq] at found
      subst type
      exact .cons replacementTyped tail
  | succ index ih =>
    cases typed with
    | nil => simp at found
    | cons head tail => exact .cons head (ih tail (by simpa using found))

end Lanius.Typing
