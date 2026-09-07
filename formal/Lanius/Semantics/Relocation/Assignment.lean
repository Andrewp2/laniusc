import Lanius.Semantics.Relocation.State

namespace Lanius.Semantics.Relocation

open Lanius.Core

theorem setValue (symbols : Core.Relocation.Symbols) (entries : List Value)
    (index : Nat) (replacement : Value) :
    Semantics.setValue (entries.map (Core.Relocation.value symbols)) index
        (Core.Relocation.value symbols replacement) =
      (Semantics.setValue entries index replacement).map (Core.Relocation.value symbols) := by
  induction entries generalizing index with
  | nil => cases index <;> rfl
  | cons first rest induction =>
      cases index with
      | zero => rfl
      | succ index => simp only [Semantics.setValue, List.map_cons, induction]

theorem replaceProjectedValue (symbols : Core.Relocation.Symbols)
    (original replacement : Value) (path : List ValueProjection) :
    Semantics.replaceProjectedValue (Core.Relocation.value symbols original) path
        (Core.Relocation.value symbols replacement) =
      (Semantics.replaceProjectedValue original path replacement).map (Core.Relocation.value symbols) := by
  induction path generalizing original with
  | nil => rfl
  | cons projection rest induction =>
      cases projection <;> cases original <;>
        simp only [Core.Relocation.value, Semantics.replaceProjectedValue,
          Core.Relocation.values_eq_map, List.getElem?_map]
      all_goals try rfl
      case field.structure field id fields =>
        cases found : fields[field]? with
        | none => rfl
        | some old =>
            simp only [Option.map, induction]
            cases Semantics.replaceProjectedValue old rest replacement <;>
              simp [Except.map, Core.Relocation.value, Core.Relocation.values_eq_map, setValue]
      case index.array index elements =>
        cases found : elements[index]? with
        | none => rfl
        | some old =>
            simp only [Option.map, induction]
            cases Semantics.replaceProjectedValue old rest replacement <;>
              simp [Except.map, Core.Relocation.value, Core.Relocation.values_eq_map, setValue]

def resolvedPlace (symbols : Core.Relocation.Symbols) (place : ResolvedPlace) : ResolvedPlace :=
  { place with value := place.value.map (Core.Relocation.value symbols) }

theorem writeResolvedPlace (symbols : Core.Relocation.Symbols) (before : State)
    (place : ResolvedPlace) (replacement : Value) :
    Semantics.writeResolvedPlace (state symbols before) (resolvedPlace symbols place)
        (Core.Relocation.value symbols replacement) =
      (Semantics.writeResolvedPlace before place replacement).map (state symbols) := by
  cases place with
  | mk root projections value =>
      cases projections with
      | nil =>
          simp only [Semantics.writeResolvedPlace, resolvedPlace, assignCell]
          cases before.assignCell root replacement <;> rfl
      | cons projection rest =>
          simp only [Semantics.writeResolvedPlace, resolvedPlace, cellEntry]
          cases before.cellEntry? root with
          | none => rfl
          | some entry =>
              cases entry with
              | mk id value =>
                  cases value with
                  | none => rfl
                  | some original =>
                      simp only [Option.map, cell, replaceProjectedValue]
                      cases Semantics.replaceProjectedValue original (projection :: rest) replacement with
                      | error reason => rfl
                      | ok updated =>
                          simp only [Except.map, assignCell]
                          cases before.assignCell root updated <;> rfl

end Lanius.Semantics.Relocation
