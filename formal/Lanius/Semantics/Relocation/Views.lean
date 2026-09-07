import Lanius.Semantics.Relocation.Assignment
import Lanius.Semantics.Relocation.Encoding

namespace Lanius.Semantics.Relocation

open Lanius.Core

theorem syncToHeapFrom (symbols : Core.Relocation.Symbols)
    (views : List I32ArrayView) (before : State) :
    syncI32ViewsToHeapFrom views (state symbols before) =
      (syncI32ViewsToHeapFrom views before).map (state symbols) := by
  induction views generalizing before with
  | nil => rfl
  | cons view rest induction =>
      simp only [syncI32ViewsToHeapFrom, readCellProjection]
      cases Semantics.readCellProjection before view.root view.projections with
      | error reason => rfl
      | ok v =>
          cases v <;> simp only [Except.map, Core.Relocation.value]
          all_goals try rfl
          rename_i elements
          simp only [Core.Relocation.values_eq_map, List.length_map]
          split
          · rfl
          · rw [← Core.Relocation.values_eq_map, encodeI32Array]
            cases Semantics.encodeI32Array elements with
            | error reason => rfl
            | ok bytes =>
                simp only []
                change (match before.heap.storeBytes view.address bytes with
                  | .error reason => Except.error reason
                  | .ok heap => syncI32ViewsToHeapFrom rest (state symbols { before with heap })) = _
                cases before.heap.storeBytes view.address bytes with
                | error reason => rfl
                | ok heap => exact induction { before with heap }

theorem syncToHeap (symbols : Core.Relocation.Symbols) (before : State) :
    syncI32ViewsToHeap (state symbols before) =
      (syncI32ViewsToHeap before).map (state symbols) :=
  syncToHeapFrom symbols before.i32ArrayViews before

theorem syncFromHeapFrom (symbols : Core.Relocation.Symbols)
    (views : List I32ArrayView) (before : State) :
    syncI32ViewsFromHeapFrom views (state symbols before) =
      (syncI32ViewsFromHeapFrom views before).map (state symbols) := by
  induction views generalizing before with
  | nil => rfl
  | cons view rest induction =>
      simp only [syncI32ViewsFromHeapFrom]
      have sameHeap : (state symbols before).heap = before.heap := rfl
      rw [sameHeap]
      cases before.heap.loadBytes view.address (view.length * 4) with
      | error reason => rfl
      | ok bytes =>
          simp only []
          have unchanged := decodeI32Array symbols view.length bytes
          cases decoded : Semantics.decodeI32Array view.length bytes with
          | error reason => rfl
          | ok elements =>
              simp only []
              simp only [decoded, Except.map, Except.ok.injEq] at unchanged
              have writes := writeResolvedPlace symbols before
                { root := view.root, projections := view.projections, value := none } (.array elements)
              simp only [resolvedPlace, Option.map, Core.Relocation.value, unchanged] at writes
              rw [writes]
              cases Semantics.writeResolvedPlace before
                { root := view.root, projections := view.projections, value := none } (.array elements) with
              | error reason => rfl
              | ok next => exact induction next

theorem syncFromHeap (symbols : Core.Relocation.Symbols) (before : State) :
    syncI32ViewsFromHeap (state symbols before) =
      (syncI32ViewsFromHeap before).map (state symbols) :=
  syncFromHeapFrom symbols before.i32ArrayViews before

end Lanius.Semantics.Relocation
