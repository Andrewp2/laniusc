import Lanius.Semantics.Capacity.Value

namespace Lanius.Semantics.Capacity
open Lanius.Core

theorem setValue (config : Config) (entries : List Value) (index : Nat) (replacement : Value) :
    Semantics.setValue (values config entries) index (value config replacement) =
      values config (Semantics.setValue entries index replacement) := by
  induction entries generalizing index with
  | nil => cases index <;> rfl
  | cons first rest ih => cases index <;> simp only [Semantics.setValue, values, ih]

theorem setValue_append (entries tail : List Value) (index : Nat) (replacement : Value)
    (inside : index < entries.length) :
    Semantics.setValue (entries ++ tail) index replacement =
      Semantics.setValue entries index replacement ++ tail := by
  induction entries generalizing index with
  | nil => simp at inside
  | cons first rest ih =>
    cases index with
    | zero => rfl
    | succ index =>
      simp only [List.cons_append, Semantics.setValue, ih index (Nat.lt_of_succ_lt_succ inside)]

theorem setValue_closed (config : Config) (entries : List Value) (index : Nat) (replacement : Value)
    (original : closeds config entries = true) (replaced : closed config replacement = true) :
    closeds config (Semantics.setValue entries index replacement) = true := by
  induction entries generalizing index with
  | nil => cases index <;> rfl
  | cons first rest ih =>
    have parts : closed config first = true ∧ closeds config rest = true := by
      simpa only [closeds, Bool.and_eq_true] using original
    cases index <;> simp only [Semantics.setValue, closeds, replaced, parts.1, parts.2, ih _ parts.2, Bool.and_self]

theorem projectedValue (config : Config) (original : Value) (path : List ValueProjection) :
    Semantics.projectedValue (value config original) path =
      (Semantics.projectedValue original path).map (value config) := by
  induction path generalizing original with
  | nil => rfl
  | cons projection rest ih =>
    cases projection <;> cases original <;>
      simp only [value, Semantics.projectedValue, values_getElem?]
    all_goals try rfl
    case field.structure field id fields =>
      cases found : fields[field]? <;> simp only [Option.map, Except.map, ih]
    case index.array index elements =>
      cases found : elements[index]? <;> simp only [Option.map, Except.map, ih]

theorem projectedValue_closed (config : Config) (original : Value) (path : List ValueProjection)
    (originalClosed : closed config original = true)
    (selected : Semantics.projectedValue original path = .ok result) : closed config result = true := by
  induction path generalizing original with
  | nil => cases selected; exact originalClosed
  | cons projection rest ih =>
    cases projection <;> cases original <;> simp only [Semantics.projectedValue] at selected
    all_goals try contradiction
    all_goals
      split at selected
      · contradiction
      · rename_i entries index entry found
        exact ih entry ((closeds_iff config entries).mp originalClosed entry (List.mem_of_getElem? found)) selected

theorem replaceProjectedValue (config : Config) (original replacement : Value) (path : List ValueProjection) :
    Semantics.replaceProjectedValue (value config original) path (value config replacement) =
      (Semantics.replaceProjectedValue original path replacement).map (value config) := by
  induction path generalizing original with
  | nil => rfl
  | cons projection rest ih =>
    cases projection <;> cases original <;>
      simp only [value, Semantics.replaceProjectedValue, values_getElem?]
    all_goals try rfl
    case field.structure field id fields =>
      cases found : fields[field]? with
      | none => rfl
      | some old =>
        simp only [Option.map, ih]
        cases Semantics.replaceProjectedValue old rest replacement <;> simp [Except.map, value, setValue]
    case index.array index elements =>
      cases found : elements[index]? with
      | none => rfl
      | some old =>
        simp only [Option.map, ih]
        cases Semantics.replaceProjectedValue old rest replacement <;> simp [Except.map, value, setValue]

theorem replaceProjectedValue_closed (config : Config) (original replacement : Value) (path : List ValueProjection)
    (originalClosed : closed config original = true) (replacementClosed : closed config replacement = true)
    (replaced : Semantics.replaceProjectedValue original path replacement = .ok result) : closed config result = true := by
  induction path generalizing original result with
  | nil => cases replaced; exact replacementClosed
  | cons projection rest ih =>
    cases projection <;> cases original <;> simp only [Semantics.replaceProjectedValue] at replaced
    all_goals try contradiction
    all_goals
      split at replaced
      · contradiction
      · rename_i entries index entry found
        have entryClosed := (closeds_iff config entries).mp originalClosed entry (List.mem_of_getElem? found)
        split at replaced
        · rename_i updated computed
          cases replaced
          exact setValue_closed config entries _ updated originalClosed (ih entry entryClosed computed)
        · contradiction

/-- Appending capacity changes only the top-level array. Every successful
nonempty projection still reads the old prefix. -/
theorem projectedValue_append (config : Config) (entries : List Value) (projection : ValueProjection)
    (rest : List ValueProjection) (selected : Semantics.projectedValue (.array entries) (projection :: rest) = .ok result) :
    Semantics.projectedValue (.array (values config entries ++ config.tail)) (projection :: rest) = .ok (value config result) := by
  cases projection with
  | field => contradiction
  | index index =>
    simp only [Semantics.projectedValue] at selected ⊢
    cases found : entries[index]? with
    | none => simp [found] at selected
    | some entry =>
      have inside := (List.getElem?_eq_some_iff.mp found).1
      rw [List.getElem?_append_left (by simpa using inside), values_getElem?, found]
      simpa only [Option.map_some, projectedValue, found, Except.map] using congrArg (Except.map (value config)) selected

theorem replaceProjectedValue_append (config : Config) (entries : List Value) (projection : ValueProjection)
    (rest : List ValueProjection) (replacement result : Value)
    (replaced : Semantics.replaceProjectedValue (.array entries) (projection :: rest) replacement = .ok result) :
    ∃ updated, result = .array updated ∧
      Semantics.replaceProjectedValue (.array (values config entries ++ config.tail))
        (projection :: rest) (value config replacement) = .ok (.array (values config updated ++ config.tail)) := by
  cases projection with
  | field => contradiction
  | index index =>
    simp only [Semantics.replaceProjectedValue] at replaced ⊢
    cases found : entries[index]? with
    | none => simp [found] at replaced
    | some entry =>
      have inside := (List.getElem?_eq_some_iff.mp found).1
      rw [List.getElem?_append_left (by simpa using inside), values_getElem?, found]
      simp only [found] at replaced
      cases computed : Semantics.replaceProjectedValue entry rest replacement with
      | error reason => simp [computed] at replaced
      | ok updated =>
        simp only [computed, Except.ok.injEq] at replaced
        subst result
        refine ⟨_, rfl, ?_⟩
        simp only [Option.map_some, replaceProjectedValue, computed, Except.map]
        rw [setValue_append _ _ _ _ (by simpa using inside), setValue]

end Lanius.Semantics.Capacity
