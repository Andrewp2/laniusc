import Lanius.Semantics.Relocation.Views
import Lanius.Semantics.Relocation.Outcome

namespace Lanius.Semantics.Relocation

open Lanius.Core

theorem mapI32ArrayView (symbols : Core.Relocation.Symbols) (before : State)
    (root : CellId) (path : List ValueProjection) (entries : List Value) :
    Semantics.mapI32ArrayView (state symbols before) root path (Core.Relocation.values symbols entries) =
      outcome symbols (Core.Relocation.value symbols) (Semantics.mapI32ArrayView before root path entries) := by
  unfold Semantics.mapI32ArrayView
  have lookup : (state symbols before).i32ArrayView? root path = before.i32ArrayView? root path := rfl
  rw [lookup]
  cases before.i32ArrayView? root path with
  | some view =>
      simp only [syncToHeap]
      cases syncI32ViewsToHeap before <;> rfl
  | none =>
      simp only [encodeI32Array]
      cases Semantics.encodeI32Array entries with
      | error reason => rfl
      | ok bytes =>
          have heap : (state symbols before).heap = before.heap := rfl
          simp only [heap, Core.Relocation.values_eq_map, List.length_map]
          cases before.heap.mapBorrowed bytes 4 <;> rfl

theorem mapI32SliceDataPtr (symbols : Core.Relocation.Symbols) (before : State)
    (root : CellId) (path : List ValueProjection) (start length : Nat) :
    Semantics.mapI32SliceDataPtr (state symbols before) root path start length =
      outcome symbols (Core.Relocation.value symbols)
        (Semantics.mapI32SliceDataPtr before root path start length) := by
  simp only [Semantics.mapI32SliceDataPtr, readCellProjection]
  cases Semantics.readCellProjection before root path with
  | error reason => rfl
  | ok v =>
      cases v <;> simp only [Except.map, Core.Relocation.value]
      all_goals try rfl
      rename_i entries
      simp only [Core.Relocation.values_eq_map, List.length_map]
      split
      · rw [← Core.Relocation.values_eq_map, mapI32ArrayView]
        cases Semantics.mapI32ArrayView before root path entries with
        | done v next => cases v <;> rfl
        | _ => rfl
      · rfl

theorem mapStringDataPtr (symbols : Core.Relocation.Symbols) (before : State) (v : String) :
    Semantics.mapStringDataPtr (state symbols before) v =
      outcome symbols (Core.Relocation.value symbols) (Semantics.mapStringDataPtr before v) := by
  unfold Semantics.mapStringDataPtr
  have heap : (state symbols before).heap = before.heap := rfl
  rw [heap]
  cases before.heap.mapBorrowed (World.utf8Bytes v) 4 <;> rfl

theorem mapRawI32Slice (symbols : Core.Relocation.Symbols) (before : State)
    (address : Address) (length : Int) :
    Semantics.mapRawI32Slice (state symbols before) address length =
      outcome symbols (Core.Relocation.value symbols) (Semantics.mapRawI32Slice before address length) := by
  unfold Semantics.mapRawI32Slice
  split
  · rfl
  · have heap : (state symbols before).heap = before.heap := rfl
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
            have unchanged := decodeI32Array symbols length.toNat bytes
            cases decoded : Semantics.decodeI32Array length.toNat bytes with
            | error reason => rfl
            | ok entries =>
                simp only [decoded, Except.map, Except.ok.injEq] at unchanged
                simp only [Core.Relocation.values_eq_map] at unchanged
                simp [State.allocateTemporary, outcome, state, cell,
                  Core.Relocation.value, Core.Relocation.ty, unchanged]

end Lanius.Semantics.Relocation
