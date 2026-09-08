import Lanius.Semantics.CellRenaming.Assignment
import Lanius.Semantics.CellRenaming.Encoding

namespace Lanius.Semantics.CellRenaming

open Lanius.Core

theorem syncToHeapFrom (rename : Permutation boundary)
    (views : List I32ArrayView) (before : State) :
    syncI32ViewsToHeapFrom (views.map (fun view : I32ArrayView => { view with root := rename.forward view.root })) (state rename.forward before) =
      (syncI32ViewsToHeapFrom views before).map (state rename.forward) := by
  induction views generalizing before with
  | nil => rfl
  | cons view rest induction =>
      simp only [List.map_cons, syncI32ViewsToHeapFrom, readCellProjection]
      cases Semantics.readCellProjection before view.root view.projections with
      | error reason => rfl
      | ok v =>
          cases v <;> simp only [Except.map, value]
          all_goals try rfl
          rename_i elements
          simp only [values_eq_map, List.length_map]
          split
          · rfl
          · rw [← values_eq_map, encodeI32Array]
            cases Semantics.encodeI32Array elements with
            | error reason => rfl
            | ok bytes =>
                simp only []
                change (match before.heap.storeBytes view.address bytes with
                  | .error reason => Except.error reason
                  | .ok heap => syncI32ViewsToHeapFrom (rest.map (fun view : I32ArrayView => { view with root := rename.forward view.root })) (state rename.forward { before with heap })) = _
                cases before.heap.storeBytes view.address bytes with
                | error reason => rfl
                | ok heap => exact induction { before with heap }

theorem syncToHeap (rename : Permutation boundary) (before : State) :
    syncI32ViewsToHeap (state rename.forward before) =
      (syncI32ViewsToHeap before).map (state rename.forward) :=
  syncToHeapFrom rename before.i32ArrayViews before

theorem syncFromHeapFrom (rename : Permutation boundary)
    (views : List I32ArrayView) (before : State) :
    syncI32ViewsFromHeapFrom (views.map (fun view : I32ArrayView => { view with root := rename.forward view.root })) (state rename.forward before) =
      (syncI32ViewsFromHeapFrom views before).map (state rename.forward) := by
  induction views generalizing before with
  | nil => rfl
  | cons view rest induction =>
      simp only [List.map_cons, syncI32ViewsFromHeapFrom]
      have sameHeap : (state rename.forward before).heap = before.heap := rfl
      rw [sameHeap]
      cases before.heap.loadBytes view.address (view.length * 4) with
      | error reason => rfl
      | ok bytes =>
          simp only []
          have unchanged := decodeI32Array rename.forward view.length bytes
          cases decoded : Semantics.decodeI32Array view.length bytes with
          | error reason => rfl
          | ok elements =>
              simp only []
              simp only [decoded, Except.map, Except.ok.injEq] at unchanged
              have writes := writeResolvedPlace rename before
                { root := view.root, projections := view.projections, value := none } (.array elements)
              simp only [resolvedPlace, Option.map, value, unchanged] at writes
              rw [writes]
              cases Semantics.writeResolvedPlace before
                { root := view.root, projections := view.projections, value := none } (.array elements) with
              | error reason => rfl
              | ok next => exact induction next

theorem syncFromHeap (rename : Permutation boundary) (before : State) :
    syncI32ViewsFromHeap (state rename.forward before) =
      (syncI32ViewsFromHeap before).map (state rename.forward) :=
  syncFromHeapFrom rename before.i32ArrayViews before

end Lanius.Semantics.CellRenaming
