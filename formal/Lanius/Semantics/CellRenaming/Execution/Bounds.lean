import Lanius.Semantics.CellRenaming.Pointers
import Std.Tactic

namespace Lanius.Semantics.CellRenaming.Execution
open Lanius.Core

theorem assignCell_nextCell (before after : State) (id : CellId) (entry : Value)
    (assigned : before.assignCell id entry = some after) : after.nextCell = before.nextCell := by
  unfold State.assignCell at assigned
  split at assigned
  · cases assigned; rfl
  · contradiction

theorem writePlace_nextCell (before after : State) (place : ResolvedPlace) (entry : Value)
    (written : Semantics.writeResolvedPlace before place entry = .ok after) :
    after.nextCell = before.nextCell := by
  unfold Semantics.writeResolvedPlace at written
  repeat' first | contradiction | split at written
  all_goals grind only [assignCell_nextCell]

theorem syncToHeapFrom_nextCell (views : List I32ArrayView) (before after : State)
    (synchronized : syncI32ViewsToHeapFrom views before = .ok after) :
    after.nextCell = before.nextCell := by
  induction views generalizing before after with
  | nil => cases synchronized; rfl
  | cons view rest induction =>
      simp only [syncI32ViewsToHeapFrom] at synchronized
      repeat' first | contradiction | split at synchronized
      have same := induction _ _ synchronized
      exact same

theorem syncFromHeapFrom_nextCell (views : List I32ArrayView) (before after : State)
    (synchronized : syncI32ViewsFromHeapFrom views before = .ok after) :
    after.nextCell = before.nextCell := by
  induction views generalizing before after with
  | nil => cases synchronized; rfl
  | cons view rest induction =>
      simp only [syncI32ViewsFromHeapFrom] at synchronized
      repeat' first | contradiction | split at synchronized
      have next := induction _ _ synchronized
      grind only [writePlace_nextCell]

theorem syncToHeap_nextCell (before after : State)
    (synchronized : syncI32ViewsToHeap before = .ok after) : after.nextCell = before.nextCell :=
  syncToHeapFrom_nextCell before.i32ArrayViews before after synchronized

theorem syncFromHeap_nextCell (before after : State)
    (synchronized : syncI32ViewsFromHeap before = .ok after) : after.nextCell = before.nextCell :=
  syncFromHeapFrom_nextCell before.i32ArrayViews before after synchronized

theorem arrayView_nextCell (before after : State) (root : CellId)
    (path : List ValueProjection) (entries : List Value) (result : Value)
    (mapped : Semantics.mapI32ArrayView before root path entries = .done result after) :
    after.nextCell = before.nextCell := by
  unfold Semantics.mapI32ArrayView at mapped
  repeat' first | contradiction | split at mapped
  all_goals grind only [syncToHeap_nextCell]

theorem slicePointer_nextCell (before after : State) (root : CellId)
    (path : List ValueProjection) (start length : Nat) (result : Value)
    (mapped : Semantics.mapI32SliceDataPtr before root path start length = .done result after) :
    after.nextCell = before.nextCell := by
  unfold Semantics.mapI32SliceDataPtr at mapped
  repeat' first | contradiction | split at mapped
  all_goals grind only [arrayView_nextCell]

theorem stringPointer_nextCell (before after : State) (bytes : String) (result : Value)
    (mapped : Semantics.mapStringDataPtr before bytes = .done result after) :
    after.nextCell = before.nextCell := by
  unfold Semantics.mapStringDataPtr at mapped
  repeat' first | contradiction | split at mapped
  all_goals cases mapped; rfl

theorem rawSlice_nextCell (before after : State) (address : Address) (length : Int) (result : Value)
    (mapped : Semantics.mapRawI32Slice before address length = .done result after) :
    after.nextCell = before.nextCell + 1 := by
  simp only [Semantics.mapRawI32Slice, State.allocateTemporary] at mapped
  repeat' first | contradiction | split at mapped
  all_goals cases mapped; rfl

end Lanius.Semantics.CellRenaming.Execution
