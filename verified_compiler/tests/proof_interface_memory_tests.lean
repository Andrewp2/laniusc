import Lanius.Semantics.Representation

namespace ProofInterfaceMemoryTests

open Lanius Lanius.Memory Lanius.Semantics

-- An initially owned table remains readable after its actual selected borrow.
theorem shapeAfterBorrow {heap : Heap} {pointer : Address} {block : Block}
    (found : heap.containingBlock? pointer = some block) :
    (Rep.block pointer (blockShape block)).holds (heap.borrowBlock block.base) := by
  apply (Rep.block pointer (blockShape block)).frame ⟨block, found, rfl⟩
    (HeapFrame.borrowBlock (fun _ _ impossible _ => False.elim impossible))
    (Footprint.Subset.refl _)

theorem notOwnedAfterBorrow {heap : Heap} {pointer : Address} {block : Block}
    (found : heap.containingBlock? pointer = some block) :
    ¬(Rep.owned pointer true).holds (heap.borrowBlock block.base) := by
  rintro ⟨current, located, owned⟩
  have same := Option.some.inj (located.symm.trans (Heap.containingBlock?_borrowSelected found))
  have impossible : false = true := by simpa only [same] using owned
  cases impossible

-- A rule claiming to frame owned=true across that borrow would be unsound.
theorem noOwnedFrame {heap : Heap} {pointer : Address} {block : Block}
    (found : heap.containingBlock? pointer = some block) (owned : block.owned = true) :
    ¬HeapFrame (Rep.owned pointer true).footprint heap (heap.borrowBlock block.base) := by
  intro effect
  exact notOwnedAfterBorrow found ((Rep.owned pointer true).frame
    ⟨block, found, owned⟩ effect (Footprint.Subset.refl _))

theorem borrowedSurvivesRepeat {heap : Heap} {pointer : Address} {block : Block}
    (found : heap.containingBlock? pointer = some block) :
    (Rep.owned pointer false).holds ((heap.borrowBlock block.base).borrowBlock block.base) := by
  simpa only using Rep.borrowed (Heap.containingBlock?_borrowSelected found)

private def byteHeap (byte : UInt8) : Heap := {
  blocks := [{ base := 8, size := 1, alignment := 1, bytes := [byte] }]
  nextAddress := 9 }

theorem actualOverlappingWrite :
    (byteHeap 7).storeByte 8 0 9 = .ok (byteHeap 9) := by rfl

theorem oldBytesReadable : (byteHeap 7).loadBytes 8 1 = .ok [7] := by rfl

theorem writeInvalidatesBytes : (byteHeap 9).loadBytes 8 1 ≠ .ok [7] := by
  intro retained
  have same : ([9] : List UInt8) = [7] := Except.ok.inj retained
  have different : ([9] : List UInt8) ≠ [7] := by decide
  exact different same

-- Overlapping writes cannot obtain the effect needed to reuse a representation.
theorem noOverlappingByteFrame :
    ¬HeapFrame ⟨fun address => address = 8, fun _ => False, fun _ => False⟩
      (byteHeap 7) (byteHeap 9) := by
  intro effect
  have retained := effect.bytes 8 0 7 rfl (show (byteHeap 7).loadByte 8 0 = .ok 7 by rfl)
  have same : (9 : UInt8) = 7 := Except.ok.inj retained
  exact (by decide : (9 : UInt8) ≠ 7) same

#print axioms shapeAfterBorrow
#print axioms noOwnedFrame
#print axioms borrowedSurvivesRepeat
#print axioms actualOverlappingWrite
#print axioms noOverlappingByteFrame

end ProofInterfaceMemoryTests
