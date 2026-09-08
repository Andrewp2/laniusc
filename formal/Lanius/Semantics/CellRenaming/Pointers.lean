import Lanius.Semantics.CellRenaming.Views
import Lanius.Semantics.CellRenaming.Outcome

namespace Lanius.Semantics.CellRenaming
open Lanius.Core

/-- Registry lookup follows the renamed language root while retaining its
existing native address and projection path. -/
theorem arrayView (rename : Permutation boundary) (before : State)
    (root : CellId) (path : List ValueProjection) :
    (state rename.forward before).i32ArrayView? (rename.forward root) path =
      (before.i32ArrayView? root path).map
        (fun view : I32ArrayView => { view with root := rename.forward view.root }) := by
  have roots : ∀ id, (rename.forward id = rename.forward root) ↔ id = root :=
    fun _ => ⟨fun same => rename.injective same, congrArg rename.forward⟩
  simp [State.i32ArrayView?, state, List.find?_map, Function.comp_def, roots]

theorem mapI32ArrayView (rename : Permutation boundary) (before : State)
    (root : CellId) (path : List ValueProjection) (entries : List Value) :
    Semantics.mapI32ArrayView (state rename.forward before) (rename.forward root) path
        (values rename.forward entries) =
      outcome rename.forward (value rename.forward) (Semantics.mapI32ArrayView before root path entries) := by
  unfold Semantics.mapI32ArrayView
  rw [arrayView]
  cases before.i32ArrayView? root path with
  | some view =>
      simp only [Option.map, syncToHeap]
      cases syncI32ViewsToHeap before <;> rfl
  | none =>
      simp only [Option.map, encodeI32Array]
      cases Semantics.encodeI32Array entries with
      | error reason => rfl
      | ok bytes =>
          have heap : (state rename.forward before).heap = before.heap := rfl
          simp only [heap, values_eq_map, List.length_map]
          cases before.heap.mapBorrowed bytes 4 <;> simp [state, outcome, value]

theorem mapI32SliceDataPtr (rename : Permutation boundary) (before : State)
    (root : CellId) (path : List ValueProjection) (start length : Nat) :
    Semantics.mapI32SliceDataPtr (state rename.forward before) (rename.forward root) path start length =
      outcome rename.forward (value rename.forward)
        (Semantics.mapI32SliceDataPtr before root path start length) := by
  simp only [Semantics.mapI32SliceDataPtr, readCellProjection]
  cases Semantics.readCellProjection before root path with
  | error reason => rfl
  | ok entry =>
      cases entry <;> simp only [Except.map, value]
      all_goals try rfl
      rename_i entries
      simp only [values_eq_map, List.length_map]
      split
      · rw [← values_eq_map, mapI32ArrayView]
        cases Semantics.mapI32ArrayView before root path entries with
        | done entry next => cases entry <;> rfl
        | _ => rfl
      · rfl

theorem mapStringDataPtr (rename : CellId → CellId) (before : State) (text : String) :
    Semantics.mapStringDataPtr (state rename before) text =
      outcome rename (value rename) (Semantics.mapStringDataPtr before text) := by
  unfold Semantics.mapStringDataPtr
  have heap : (state rename before).heap = before.heap := rfl
  rw [heap]
  cases before.heap.mapBorrowed (World.utf8Bytes text) 4 <;> rfl

theorem mapRawI32Slice (rename : Permutation boundary) (before : State)
    (ready : boundary ≤ before.nextCell) (address : Address) (length : Int) :
    Semantics.mapRawI32Slice (state rename.forward before) address length =
      outcome rename.forward (value rename.forward) (Semantics.mapRawI32Slice before address length) := by
  unfold Semantics.mapRawI32Slice
  split
  · rfl
  · have heap : (state rename.forward before).heap = before.heap := rfl
    rw [heap]
    simp only []
    cases before.heap.protectAsBorrowed address (length.toNat * 4) 4 with
    | error reason => rfl
    | ok protectedHeap =>
        simp only []
        cases protectedHeap.loadBytes address (length.toNat * 4) with
        | error reason => rfl
        | ok bytes =>
            simp only []
            have unchanged := decodeI32Array rename.forward length.toNat bytes
            cases decoded : Semantics.decodeI32Array length.toNat bytes with
            | error reason => rfl
            | ok entries =>
                simp only [decoded, Except.map, Except.ok.injEq] at unchanged
                simp only [values_eq_map] at unchanged
                simp [State.allocateTemporary, outcome, state, cell, value,
                  rename.fresh before.nextCell ready, values_eq_map, unchanged]

end Lanius.Semantics.CellRenaming
