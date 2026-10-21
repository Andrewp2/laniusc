import Lanius.Semantics.RawStore

namespace Lanius.Semantics

open Lanius Lanius.Core Lanius.Memory

/-- Capture a raw record address before a state-changing index/RHS, then
    write only the selected field using storage in the resulting RHS state. -/
theorem RunsExpr.assignRawFieldNative {before indexed ready : State} {id : TypeId} {value : Value}
    (source : before.local? sourceId = some (.rawSlice (.structure id) address length))
    (index : RunsExpr program before indexExpression (.signed .i32 (Int.ofNat position)) indexed)
    (bound : position < length)
    (location : rawSliceElementAddress? program (.structure id) address position = .ok base)
    (declaration : program.structure? id = some record)
    (fieldType : record.fields[field]? = some type)
    (offset : NativeLayout.structureFieldOffset? program id field = some displacement)
    (codec : NativeStoreSpec NativeLayout.maxDepth program type value size)
    (readable : ready.heap.Readable (base + displacement) size)
    (unique : HeapBlockBasesUnique ready.heap) (noViews : ready.i32ArrayViews = [])
    (right : RunsExpr program indexed expression value ready) :
    ∃ heap, RunsExpr program before
      (.assign .set (.field (.index (.local sourceId) indexExpression) field) expression)
      .unit { ready with heap } ∧
      NativeSnapshot NativeLayout.maxDepth program heap type (base + displacement) value size ∧
      HeapRegionWrite ready.heap heap (base + displacement) size ∧
      writeNativeValue NativeLayout.maxDepth program ready ready.heap type (base + displacement) value = .ok heap := by
  cases cell : before.cellId? sourceId with
  | none => simp [State.local?, cell] at source
  | some root =>
    have entry := cellEntry_of_local before sourceId root _ cell source
    obtain ⟨heap, stored, snapshot, effect⟩ := codec ready ready.heap (base + displacement) readable unique
    obtain ⟨indexFuel, indexRun, indexLocals⟩ := index
    obtain ⟨rightFuel, rightRun, rightLocals⟩ := right
    refine ⟨heap, RunsExpr.ofStable (threshold := max (max 1 indexFuel + 2) rightFuel + 1) ?_
      (rightLocals.trans indexLocals), snapshot, effect, stored⟩
    intro fuel enough
    have indexResult := indexRun (fuel - 4 + 1) (by omega)
    have replacement := rightRun (fuel - 4 + 2 + 1) (by omega)
    have nonnegative : ¬((position : Int) < 0) := Int.not_lt_of_ge (Int.natCast_nonneg position)
    rw [show fuel = (fuel - 1).succ by omega, evalExpr.eq_def]
    dsimp only
    rw [show fuel - 1 = (fuel - 2).succ by omega, evalPlace.eq_def]
    dsimp only
    rw [show fuel - 2 = (fuel - 3).succ by omega, evalPlace.eq_def]
    dsimp only
    rw [show fuel - 3 = (fuel - 4).succ by omega, evalPlace.eq_def]
    simp only [cell, entry, indexResult]
    simp [integerIndex, Int.ofNat_eq_natCast, nonnegative, bound, location,
      declaration, fieldType, offset, replacement, evalAssignValue,
      assignOpBinary?, writeResolvedPlaceNative, stored, ResolvedPlace.viewFreeRootWrite,
      syncI32ViewsFromHeap, noViews]
    rfl

#print axioms RunsExpr.assignRawFieldNative

end Lanius.Semantics
