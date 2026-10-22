import Lanius.Semantics.Assignment
import Lanius.Semantics.StmtList
import Lanius.Semantics.NativeStore

namespace Lanius.Semantics

open Lanius Lanius.Core Lanius.Memory

private theorem rawPlace {before indexed : State}
    (source : before.local? sourceId = some (.rawSlice element address length))
    (index : StableExpr indexFuel program before indexExpression (.signed .i32 (Int.ofNat position)) indexed)
    (bound : position < length)
    (location : rawSliceElementAddress? program element address position = .ok base) :
    ∃ root, ∀ fuel, max 1 indexFuel + 1 ≤ fuel →
      evalPlace fuel program before .address (.index (.local sourceId) indexExpression) =
        .done { root := root
                projections := []
                value := none
                raw := some (element, base) } indexed := by
  cases cell : before.cellId? sourceId with
  | none => simp [State.local?, cell] at source
  | some root =>
    have entry := cellEntry_of_local before sourceId root _ cell source
    refine ⟨root, ?_⟩
    intro fuel enough
    rw [show fuel = (fuel - 1).succ by omega, evalPlace.eq_def]
    dsimp only
    rw [show fuel - 1 = (fuel - 2).succ by omega, evalPlace.eq_def]
    simp only [cell, entry, index (fuel - 2 + 1) (by omega)]
    have nonnegative : ¬((position : Int) < 0) := Int.not_lt_of_ge (Int.natCast_nonneg position)
    simp [integerIndex, Int.ofNat_eq_natCast, nonnegative, bound,
      location]

/-- The descriptor is captured before the index. The RHS runs afterward,
    and the native store uses its resulting state without registered views. -/
theorem StableExpr.assignRaw {before indexed ready : State} {value : Value}
    (source : before.local? sourceId = some (.rawSlice element address length))
    (index : StableExpr indexFuel program before indexExpression (.signed .i32 (Int.ofNat position)) indexed)
    (bound : position < length)
    (location : rawSliceElementAddress? program element address position = .ok base)
    (noViews : ready.i32ArrayViews = [])
    (right : StableExpr threshold program indexed expression value ready)
    (stored : writeNativeValue NativeLayout.maxDepth program ready ready.heap element base value = .ok heap) :
    StableExpr (max (max 1 indexFuel + 1) threshold + 1) program before
      (.assign .set (.index (.local sourceId) indexExpression) expression)
      .unit { ready with heap } := by
  obtain ⟨root, place⟩ := rawPlace (program := program) source index bound location
  intro fuel enough
  have placeRun := place (fuel - 1) (by omega)
  have rightRun := right (fuel - 1) (by omega)
  rw [show fuel = (fuel - 1).succ by omega, evalExpr.eq_def]
  dsimp only
  rw [placeRun]
  dsimp only
  rw [rightRun]
  simp [evalAssignValue, assignOpBinary?, writeResolvedPlaceNative, stored,
    ResolvedPlace.viewFreeRootWrite, syncI32ViewsFromHeap, noViews]
  rfl

/-- Scalar stores retain their exact byte effect from the post-RHS heap. -/
theorem StableExpr.assignRawI32 {before indexed ready : State} {value : Int}
    (source : before.local? sourceId = some (.rawSlice (.scalar (.signed .i32)) address length))
    (index : StableExpr indexFuel program before indexExpression (.signed .i32 (Int.ofNat position)) indexed)
    (bound : position < length)
    (noViews : ready.i32ArrayViews = [])
    (right : StableExpr threshold program indexed expression (.signed .i32 value) ready)
    (stored : ready.heap.storeBytes (address + position * 4) (i32Bytes value) = .ok heap) :
    StableExpr (max (max 1 indexFuel + 1) threshold + 1) program before
      (.assign .set (.index (.local sourceId) indexExpression) expression)
      .unit { ready with heap } := by
  exact StableExpr.assignRaw source index bound rfl noViews right stored

/-- Writable post-RHS storage and a value codec derive the captured-address
    assignment, its read-back value, and the final store's memory frame. -/
theorem RunsExpr.assignRawNative {before indexed ready : State} {value : Value}
    (source : before.local? sourceId = some (.rawSlice element address length))
    (index : RunsExpr program before indexExpression (.signed .i32 (Int.ofNat position)) indexed)
    (bound : position < length)
    (location : rawSliceElementAddress? program element address position = .ok base)
    (codec : NativeStoreSpec NativeLayout.maxDepth program element value size)
    (room : size ≤ base + 8) (readable : ready.heap.Readable (base + 8 - size) size)
    (unique : HeapBlockBasesUnique ready.heap)
    (noViews : ready.i32ArrayViews = []) (right : RunsExpr program indexed expression value ready) :
    ∃ heap, RunsExpr program before (.assign .set (.index (.local sourceId) indexExpression) expression)
      .unit { ready with heap } ∧ NativeSnapshot NativeLayout.maxDepth program heap element base value size ∧
      HeapRegionWrite ready.heap heap (base + 8 - size) size := by
  obtain ⟨heap, stored, read, effect⟩ := codec ready ready.heap base room readable unique
  exact ⟨heap, .ofStable (StableExpr.assignRaw source index.choose_spec.1 bound location noViews
    right.choose_spec.1 stored) (right.choose_spec.2.trans index.choose_spec.2), read, effect⟩

/-- The final scalar write preserves every nonheap field of the RHS state,
    while preceding index/RHS effects remain part of the full execution. -/
theorem RunsExpr.assignRawI32 {before indexed ready : State} {value : Int}
    (source : before.local? sourceId = some (.rawSlice (.scalar (.signed .i32)) address length))
    (index : RunsExpr program before indexExpression (.signed .i32 (Int.ofNat position)) indexed)
    (bound : position < length) (readable : ready.heap.Readable (address + position * 4) 4)
    (unique : HeapBlockBasesUnique ready.heap) (noViews : ready.i32ArrayViews = [])
    (right : RunsExpr program indexed expression (.signed .i32 value) ready) :
    ∃ heap, RunsExpr program before (.assign .set (.index (.local sourceId) indexExpression) expression)
      .unit { ready with heap } ∧ BytesWrite ready.heap heap (address + position * 4) (i32Bytes value) := by
  obtain ⟨heap, stored, written⟩ := Heap.storeBytes_of_readable (i32Bytes value) unique
    (by simpa only [Heap.Readable, i32Bytes, List.length_map, List.length_range] using readable)
  exact ⟨heap, .ofStable (StableExpr.assignRawI32 source index.choose_spec.1 bound noViews
    right.choose_spec.1 stored) (right.choose_spec.2.trans index.choose_spec.2), written⟩

#print axioms RunsExpr.assignRawI32
#print axioms RunsExpr.assignRawNative

end Lanius.Semantics
