import Lanius.Semantics.NativeReadFrame

namespace Lanius.Semantics.NativeReadFrameTests

open Lanius Lanius.Core Lanius.Memory

-- This covers arbitrary recursive native layouts, not just endpoint words.
example (heap : Heap) (loaded : readNativeValue fuel program heap type address = .ok value) :
    readNativeValue fuel program (heap.appendI32 bytes owned budget) type address = .ok value :=
  HeapReads.appendI32.nativeValue loaded

example (reads : HeapReads original before) (below : HeapBlocksBelowNext original)
    (fresh : original.nextAddress ≤ address) (written : BytesWrite before after address bytes)
    (loaded : readNativeValue fuel program original type pointer = .ok value) :
    readNativeValue fuel program after type pointer = .ok value :=
  (reads.writeFresh below fresh written).nativeValue loaded

example (reads : HeapReads original before) (below : HeapBlocksBelowNext original)
    (fresh : original.nextAddress ≤ address) (written : HeapRegionWrite before after address size)
    (loaded : readNativeValue fuel program original type pointer = .ok value) :
    readNativeValue fuel program after type pointer = .ok value :=
  (reads.writeRegionFresh below fresh written).nativeValue loaded

private def old : Heap := {
  blocks := [{ base := 4, size := 4, alignment := 4, bytes := [7, 0, 0, 0] }]
  nextAddress := 8 }
private def changed : Heap := { old with blocks := [{ base := 4, size := 4, alignment := 4, bytes := [0, 0, 0, 0] }] }

-- Preserving successful reads must not quietly permit overwriting old data.
example : ¬HeapReads old changed := by
  intro wrong
  have impossible := wrong 4 0 7 (by rfl)
  change (Except.ok (0 : UInt8) : Except Trap UInt8) = .ok 7 at impossible
  exact (by decide : (0 : UInt8) ≠ 7) (Except.ok.inj impossible)

#print axioms HeapReads.nativeValue
#print axioms HeapReads.writeFresh
#print axioms HeapReads.writeRegionFresh

-- Overwriting an element needs no assumption about its previous value.
example {before after : State} (write : BytesWrite before.heap after.heap (address + index * 4) (i32Bytes (-1)))
    (bound : index < capacity) (room : before.heap.Readable (address + index * 4) 4) :
    readRawSliceIndex program after (.scalar (.signed .i32)) address capacity index = .ok (.signed .i32 (-1)) := by
  simpa only [↓reduceIte] using readRawSliceIndex_i32_afterStore (program := program)
    (before := before) (after := after) (pointer := address) (position := index) (previous := 37)
    (value := -1) write (by decide) bound room (by intro impossible; exact False.elim (impossible rfl))

-- The entire logical table survives writes in either disjoint address order.
example {values : Nat → Int} (write : HeapRegionWrite before.heap after.heap address size)
    (bound : count ≤ capacity) (room : before.heap.Readable pointer (count * 4))
    (separate : pointer + count * 4 ≤ address ∨ address + size ≤ pointer)
    (reads : ∀ index, index < count → readRawSliceIndex program before
      (.scalar (.signed .i32)) pointer capacity index = .ok (.signed .i32 (values index))) :
    ∀ index, index < count → readRawSliceIndex program after
      (.scalar (.signed .i32)) pointer capacity index = .ok (.signed .i32 (values index)) :=
  i32Table_afterRegionWrite write bound room separate reads

#print axioms readRawSliceIndex_i32_afterStore
#print axioms i32Table_afterRegionWrite

end Lanius.Semantics.NativeReadFrameTests
