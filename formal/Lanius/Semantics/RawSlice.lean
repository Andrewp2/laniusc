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

/-- A nonempty typed view borrows its full backward byte range inside the
    actual allocation. Ownership transfer does not copy or decode elements. -/
theorem mapRawNominalSlice_of_block (count : Nat) (positive : 0 < count)
    (nominal : (match element with | .structure _ | .enumeration _ => true | _ => false) = true)
    (layout : NativeLayout.valueWords? program element = some words) (width : 0 < words)
    (room : count * words * NativeLayout.wordBytes ≤ address + NativeLayout.wordBytes)
    (found : state.heap.containingBlock? (address + NativeLayout.wordBytes - count * words * NativeLayout.wordBytes) = some block)
    (aligned : (address + NativeLayout.wordBytes - count * words * NativeLayout.wordBytes) % NativeLayout.wordBytes = 0)
    (alignment : NativeLayout.wordBytes ≤ block.alignment)
    (bounds : address + NativeLayout.wordBytes ≤ block.base + block.size)
    (unique : HeapBlockBasesUnique state.heap) :
    mapRawNominalSlice program state element address count = .done (.rawSlice element address count)
      { state with heap := state.heap.borrowBlock block.base } := by
  have borrowed := Heap.protectRangeAsBorrowed_of_block (size := count * words * NativeLayout.wordBytes) found
    (Nat.mul_pos (Nat.mul_pos positive width) (by decide)) aligned (by decide) alignment (by omega) unique
  have nonnegative : ¬((count : Int) < 0) := Int.not_lt_of_ge (Int.natCast_nonneg count)
  cases element <;> simp at nominal
  all_goals simp [mapRawNominalSlice, nonnegative, layout, Nat.ne_of_gt width,
    Nat.ne_of_gt positive, Int.toNat_natCast, Nat.not_lt_of_ge room, borrowed]

/-- Construct a raw slice from its allocation metadata, without assuming a
    successful constructor or copying/decoding the backing bytes. -/
theorem mapRawI32Slice_of_block (length : Nat) (positive : 0 < length)
    (found : state.heap.block? address = some block) (live : block.live = true)
    (size : block.size = length * 4) (alignment : block.alignment = 4) :
    mapRawI32Slice state address (length : Int) =
      .done (.rawSlice (.scalar (.signed .i32)) address length)
        { state with heap := { state.heap with
          blocks := replaceBlock state.heap.blocks { block with owned := false } } } := by
  simp [mapRawI32Slice, Int.natCast_nonneg length, Nat.ne_of_gt positive,
    Heap.protectAsBorrowed, found, live, size, alignment]

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

/-- Borrowing storage that is already protected does not rewrite the heap. -/
theorem mapRawI32Slice_of_borrowed (length : Nat)
    (found : state.heap.block? address = some block) (live : block.live = true)
    (size : block.size = length * 4) (alignment : block.alignment = 4)
    (owned : block.owned = false) (unique : HeapBlockBasesUnique state.heap) :
    mapRawI32Slice state address (length : Int) =
      .done (.rawSlice (.scalar (.signed .i32)) address length) state := by
  by_cases zero : length = 0
  · subst length; exact mapRawI32Slice_empty state address
  have replacement : { block with owned := false } = block := by cases block; simp_all
  have unchanged := replaceBlock_self state.heap.blocks block (fun other member same =>
    unique other member block (List.mem_of_find?_eq_some found) same)
  simpa only [replacement, unchanged] using mapRawI32Slice_of_block length (by omega) found live size alignment

theorem mapRawI32Slice_stringStorage
    (heapIs : state.heap = heap.borrowedI32 (stringStorage input))
    (below : HeapBlocksBelowNext heap) (unique : HeapBlockBasesUnique heap) :
    mapRawI32Slice state heap.borrowedAddress (((World.utf8Bytes input).length + 3) / 4 : Nat) =
      .done (.rawSlice (.scalar (.signed .i32)) heap.borrowedAddress
        (((World.utf8Bytes input).length + 3) / 4)) state := by
  apply mapRawI32Slice_of_borrowed (block := {
    base := heap.borrowedAddress, size := (stringStorage input).length,
    alignment := 4, bytes := stringStorage input, owned := false })
  · rw [heapIs]; exact Heap.borrowedI32_block below _
  · rfl
  · exact stringStorage_length input
  · rfl
  · rfl
  · rw [heapIs]; exact Heap.borrowedI32_unique below unique

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
    effects. Protection changes ownership, not bytes or allocation budget. -/
theorem RunsExpr.allocatedI32Slice {words : Nat}
    (pointer : RunsExpr program before pointerExpression (.pointer heap.borrowedAddress) middle)
    (length : RunsExpr program middle lengthExpression (.signed .i32 words) ready)
    (allocated : ready.heap = heap.allocatedI32 words budget)
    (positive : 0 < words) (below : HeapBlocksBelowNext heap) :
    RunsExpr program before (.i32SliceFromRawParts pointerExpression lengthExpression)
      (.rawSlice (.scalar (.signed .i32)) heap.borrowedAddress words)
      { ready with heap := heap.appendI32 (List.replicate (words * 4) 0) false budget } := by
  apply RunsExpr.rawSliceFromParts
    (after := { ready with heap := heap.appendI32 (List.replicate (words * 4) 0) false budget }) pointer length ?_ rfl
  simp only [mapRawI32Slice, Int.not_lt_of_ge (Int.natCast_nonneg words), ↓reduceIte,
    show (words : Int) ≠ 0 by omega, Int.toNat_natCast, allocated, Heap.allocatedI32_protect below]

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
