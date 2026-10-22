import Lanius.Semantics.Stable
import Lanius.Semantics.StmtList
import Lanius.Memory.BorrowRange
import Lanius.Memory.Allocation

namespace Lanius.Semantics

open Lanius.Core Lanius.Memory

/-- Normalize a native nominal-slice index using proved layout and address
    arithmetic. This selects a slot, without decoding its contents. -/
theorem rawSliceElementAddress_of_layout
    (nominal : (match element with | .structure _ | .enumeration _ => true | _ => false) = true)
    (layout : NativeLayout.valueWords? program element = some words) (width : 0 < words)
    (room : (index * words + words - 1) * 8 ≤ pointer)
    (address : pointer - (index * words + words - 1) * 8 = base) :
    rawSliceElementAddress? program element pointer index = .ok base := by
  cases element <;> simp at nominal
  all_goals simp [rawSliceElementAddress?, layout, NativeLayout.elementBase?, NativeLayout.wordBytes,
    Nat.ne_of_gt width, Nat.not_lt_of_ge room, address] <;> rfl

/-- A nonempty typed view needs its full backward byte range inside one live
    allocation. Constructing it does not copy or decode elements, and leaves
    the state as it was. -/
theorem mapRawNominalSlice_of_block (count : Nat) (positive : 0 < count)
    (nominal : (match element with | .structure _ | .enumeration _ => true | _ => false) = true)
    (layout : NativeLayout.valueWords? program element = some words) (width : 0 < words)
    (room : count * words * NativeLayout.wordBytes ≤ address + NativeLayout.wordBytes)
    (found : state.heap.containingBlock? (address + NativeLayout.wordBytes - count * words * NativeLayout.wordBytes) = some block)
    (aligned : (address + NativeLayout.wordBytes - count * words * NativeLayout.wordBytes) % NativeLayout.wordBytes = 0)
    (alignment : NativeLayout.wordBytes ≤ block.alignment)
    (bounds : address + NativeLayout.wordBytes ≤ block.base + block.size) :
    mapRawNominalSlice program state element address count = .done (.rawSlice element address count) state := by
  have checked := Heap.checkRange_of_block (size := count * words * NativeLayout.wordBytes) found
    (Nat.mul_pos (Nat.mul_pos positive width) (by decide)) aligned (by decide) alignment (by omega)
  have nonnegative : ¬((count : Int) < 0) := Int.not_lt_of_ge (Int.natCast_nonneg count)
  cases element <;> simp at nominal
  all_goals simp [mapRawNominalSlice, nonnegative, layout, Nat.ne_of_gt width,
    Nat.ne_of_gt positive, Int.toNat_natCast, Nat.not_lt_of_ge room, checked]

/-- Construct a raw slice from its allocation metadata, without assuming a
    successful constructor or copying/decoding the backing bytes. -/
theorem mapRawI32Slice_of_block (length : Nat) (positive : 0 < length)
    (found : state.heap.containingBlock? address = some block) (aligned : address % 4 = 0)
    (alignment : 4 ≤ block.alignment) (bounds : address + length * 4 ≤ block.base + block.size) :
    mapRawI32Slice state address (length : Int) =
      .done (.rawSlice (.scalar (.signed .i32)) address length) state := by
  have checked := Heap.checkRange_of_block (size := length * 4) found (by omega) aligned (by decide)
    alignment bounds
  simp [mapRawI32Slice, Int.natCast_nonneg length, Nat.ne_of_gt positive, checked]

theorem mapRawI32Slice_empty (state : State) (address : Lanius.Address) :
    mapRawI32Slice state address 0 = .done (.rawSlice (.scalar (.signed .i32)) address 0) state := by
  simp [mapRawI32Slice]

theorem StableExpr.rawSliceDataPtr
    (run : StableExpr threshold program before expression
      (.rawSlice (.scalar (.signed .i32)) address length) after) :
    StableExpr (threshold + 1) program before (.i32SliceDataPtr expression)
      (.pointer address) after := by
  intro fuel enough
  have evaluated := run (fuel - 1) (by omega)
  rw [show fuel = (fuel - 1).succ by omega, evalExpr.eq_def]
  simp only [evaluated]

theorem mapRawI32Slice_stringStorage
    (heapIs : state.heap = heap.borrowedI32 (stringStorage input))
    (below : HeapBlocksBelowNext heap) :
    mapRawI32Slice state heap.borrowedAddress (((World.utf8Bytes input).length + 3) / 4 : Nat) =
      .done (.rawSlice (.scalar (.signed .i32)) heap.borrowedAddress
        (((World.utf8Bytes input).length + 3) / 4)) state := by
  by_cases zero : ((World.utf8Bytes input).length + 3) / 4 = 0
  · rw [zero]; exact mapRawI32Slice_empty state _
  have size := stringStorage_length input
  have found := Heap.borrowedI32_containing (bytes := stringStorage input) (index := 0) below
    (by rw [size]; exact Nat.mul_pos (Nat.pos_of_ne_zero zero) (by decide))
  rw [Nat.add_zero, ← heapIs] at found
  exact mapRawI32Slice_of_block _ (by omega) found heap.borrowedAddress_aligned (Nat.le_refl _)
    (by simp only [size]; exact Nat.le_refl _)

theorem RunsExpr.stringDataPtr
    (source : RunsExpr program before expression (.string value) after) :
    RunsExpr program before (.stringDataPtr expression) (.pointer after.heap.borrowedAddress)
      { after with heap := after.heap.borrowedI32 (stringStorage value) } := by
  obtain ⟨threshold, run, locals⟩ := source
  refine ⟨threshold + 1, ?_, locals⟩
  intro fuel enough
  rw [show fuel = (fuel - 1).succ by omega, evalExpr.eq_def]
  simp only [run (fuel - 1) (by omega), mapStringDataPtr, Heap.mapBorrowed_i32]

theorem RunsExpr.rawSliceFromParts
    (pointerRun : RunsExpr program before pointer (.pointer address) middle)
    (lengthRun : RunsExpr program middle length (.signed .i32 count) afterLength)
    (construct : mapRawI32Slice afterLength address count = .done value after)
    (locals : after.locals = afterLength.locals) :
    RunsExpr program before (.i32SliceFromRawParts pointer length) value after := by
  obtain ⟨pointerFuel, pointerRun, pointerLocals⟩ := pointerRun
  obtain ⟨lengthFuel, lengthRun, lengthLocals⟩ := lengthRun
  refine ⟨max pointerFuel lengthFuel + 1, ?_, locals.trans (lengthLocals.trans pointerLocals)⟩
  intro fuel enough
  rw [show fuel = (fuel - 1).succ by omega, evalExpr.eq_def]
  simp only [pointerRun (fuel - 1) (by omega), lengthRun (fuel - 1) (by omega), construct]

/-- Raw construction directly from a fresh allocation, after both argument
    effects. The view leaves the allocation, and its owner, as they were. -/
theorem RunsExpr.allocatedI32Slice {words : Nat}
    (pointer : RunsExpr program before pointerExpression (.pointer heap.borrowedAddress) middle)
    (length : RunsExpr program middle lengthExpression (.signed .i32 words) ready)
    (allocated : ready.heap = heap.allocatedI32 words budget)
    (positive : 0 < words) (below : HeapBlocksBelowNext heap) :
    RunsExpr program before (.i32SliceFromRawParts pointerExpression lengthExpression)
      (.rawSlice (.scalar (.signed .i32)) heap.borrowedAddress words) ready := by
  apply RunsExpr.rawSliceFromParts (after := ready) pointer length ?_ rfl
  simp only [mapRawI32Slice, Int.not_lt_of_ge (Int.natCast_nonneg words), ↓reduceIte,
    show (words : Int) ≠ 0 by omega, Int.toNat_natCast, allocated, Heap.allocatedI32_checkRange below positive]

theorem RunsExpr.nominalSliceFromParts
    (pointerRun : RunsExpr program before pointer (.pointer address) middle)
    (lengthRun : RunsExpr program middle length (.signed .i32 count) afterLength)
    (construct : mapRawNominalSlice program afterLength element address count = .done value after)
    (locals : after.locals = afterLength.locals) :
    RunsExpr program before (.typedSliceFromRawParts element pointer length) value after := by
  obtain ⟨pointerFuel, pointerRun, pointerLocals⟩ := pointerRun
  obtain ⟨lengthFuel, lengthRun, lengthLocals⟩ := lengthRun
  refine ⟨max pointerFuel lengthFuel + 1, ?_, locals.trans (lengthLocals.trans pointerLocals)⟩
  intro fuel enough
  rw [show fuel = (fuel - 1).succ by omega, evalExpr.eq_def]
  simp only [pointerRun (fuel - 1) (by omega), lengthRun (fuel - 1) (by omega), construct]

#print axioms RunsExpr.allocatedI32Slice

end Lanius.Semantics
