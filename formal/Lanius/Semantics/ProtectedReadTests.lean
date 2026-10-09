import Lanius.Semantics.ReadOnlyMemory

open Lanius.Memory Lanius.Semantics

example (reads : HeapReads reference before)
    (first : HeapRegionWrite before middle left 4) (second : HeapRegionWrite middle after right 4)
    (order : left = 0 ∧ right = 8 ∨ left = 8 ∧ right = 0)
    (gap : ∀ p o b, reference.loadByte p o = .ok b → 4 ≤ p + o ∧ p + o < 8) :
    HeapReads reference after := by
  apply reads.afterWrites (allowed := fun location =>
    (left ≤ location ∧ location < left + 4) ∨ (right ≤ location ∧ location < right + 4))
    ((first.footprint.weaken fun _ h => Or.inl h).trans
      (second.footprint.weaken fun _ h => Or.inr h))
  intro pointer offset byte read
  have := gap pointer offset byte read
  dsimp only [Lanius.Address] at *; omega

example (reads : HeapReads reference before) (write : HeapRegionWrite before after address 0) :
    HeapReads reference after :=
  reads.afterWrites write.footprint (by intro p o b read; dsimp only [Lanius.Address]; omega)

example (frame : ReadOnlyMemory reference before address capacity)
    (write : HeapRegionWrite before after address capacity) :
    ReadOnlyMemory reference after address capacity :=
  frame.afterRegionWrite write (Nat.le_refl _) (Nat.le_refl _)

private def singleByte (value : UInt8) : Heap :=
  { blocks := [{ base := 4, size := 1, alignment := 1, bytes := [value] }], nextAddress := 5 }

example : (singleByte 1).storeByte 4 0 2 = .ok (singleByte 2) ∧
    ¬HeapReads (singleByte 1) (singleByte 2) := by
  constructor
  · rfl
  · intro reads
    exact (by decide : (2 : UInt8) ≠ 1) (Except.ok.inj (reads 4 0 1 (by rfl)))

#print axioms HeapRegionWrite.footprint
#print axioms HeapReads.afterWrites
#print axioms ReadOnlyMemory.afterRegionWrite
