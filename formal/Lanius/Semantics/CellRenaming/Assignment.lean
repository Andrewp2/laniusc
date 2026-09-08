import Lanius.Semantics.CellRenaming.Access

namespace Lanius.Semantics.CellRenaming

open Lanius.Core

theorem setValue (rename : Permutation boundary) (entries : List Value)
    (index : Nat) (replacement : Value) :
    Semantics.setValue (entries.map (value rename.forward)) index
        (value rename.forward replacement) =
      (Semantics.setValue entries index replacement).map (value rename.forward) := by
  induction entries generalizing index with
  | nil => cases index <;> rfl
  | cons first rest induction =>
      cases index with
      | zero => rfl
      | succ index => simp only [Semantics.setValue, List.map_cons, induction]

theorem replaceProjectedValue (rename : Permutation boundary)
    (original replacement : Value) (path : List ValueProjection) :
    Semantics.replaceProjectedValue (value rename.forward original) path
        (value rename.forward replacement) =
      (Semantics.replaceProjectedValue original path replacement).map (value rename.forward) := by
  induction path generalizing original with
  | nil => rfl
  | cons projection rest induction =>
      cases projection <;> cases original <;>
        simp only [value, Semantics.replaceProjectedValue,
          values_eq_map, List.getElem?_map]
      all_goals try rfl
      case field.structure field id fields =>
        cases found : fields[field]? with
        | none => rfl
        | some old =>
            simp only [Option.map, induction]
            cases Semantics.replaceProjectedValue old rest replacement <;>
              simp [Except.map, value, values_eq_map, setValue]
      case index.array index elements =>
        cases found : elements[index]? with
        | none => rfl
        | some old =>
            simp only [Option.map, induction]
            cases Semantics.replaceProjectedValue old rest replacement <;>
              simp [Except.map, value, values_eq_map, setValue]

def resolvedPlace (rename : Permutation boundary) (place : ResolvedPlace) : ResolvedPlace :=
  { place with root := rename.forward place.root, value := place.value.map (value rename.forward) }

theorem writeResolvedPlace (rename : Permutation boundary) (before : State)
    (place : ResolvedPlace) (replacement : Value) :
    Semantics.writeResolvedPlace (state rename.forward before) (resolvedPlace rename place)
        (value rename.forward replacement) =
      (Semantics.writeResolvedPlace before place replacement).map (state rename.forward) := by
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

theorem projectedValue (rename : Permutation boundary) (v : Value) (path : List ValueProjection) :
    Semantics.projectedValue (value rename.forward v) path =
      (Semantics.projectedValue v path).map (value rename.forward) := by
  induction path generalizing v with
  | nil => rfl
  | cons projection rest induction =>
      cases projection <;> cases v <;>
        simp only [value, Semantics.projectedValue,
          values_eq_map, List.getElem?_map, Except.map]
      all_goals first
        | rfl
        | split <;> simp_all
      all_goals
        rename_i selected
        obtain ⟨original, found, rfl⟩ := selected
        simp only [found]
        exact induction original

theorem readCellProjection (rename : Permutation boundary) (before : State)
    (id : CellId) (path : List ValueProjection) :
    Semantics.readCellProjection (state rename.forward before) (rename.forward id) path =
      (Semantics.readCellProjection before id path).map (value rename.forward) := by
  simp only [Semantics.readCellProjection, cellEntry]
  cases before.cellEntry? id with
  | none => rfl
  | some entry =>
      cases entry with
      | mk id value => cases value <;> simp [cell, projectedValue, Except.map]

end Lanius.Semantics.CellRenaming
