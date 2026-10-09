import Lanius.Memory.Output
import Lanius.Semantics.NativeReadFrame

namespace Lanius.Semantics

open Lanius.Memory

/-- A read-only heap fragment, separated from a mutable output buffer.
    This is a memory frame, not another syntax or typing representation. -/
structure ReadOnlyMemory (reference actual : Heap) (address capacity : Nat) : Prop where
  reads : HeapReads reference actual
  outside : ∀ pointer offset byte, reference.loadByte pointer offset = .ok byte →
    pointer + offset < address ∨ address + capacity ≤ pointer + offset

/-- A contained interval write retains the same protected read-only fragment. -/
theorem ReadOnlyMemory.afterRegionWrite (frame : ReadOnlyMemory reference before address capacity)
    (write : HeapRegionWrite before after destination size)
    (lower : address ≤ destination) (upper : destination + size ≤ address + capacity) :
    ReadOnlyMemory reference after address capacity := by
  refine ⟨frame.reads.afterWrites write.footprint ?_, frame.outside⟩
  intro pointer offset byte read
  have apart := frame.outside _ _ _ read
  dsimp only [Lanius.Address] at *; omega

/-- Block separation establishes the frame once, rather than proving a new
    byte-range lemma for each native record, enum, or slice read. -/
theorem ReadOnlyMemory.ofBlocks (reads : HeapReads reference actual)
    (separate : ∀ block ∈ reference.blocks,
      block.base + block.size ≤ address ∨ address + capacity ≤ block.base) :
    ReadOnlyMemory reference actual address capacity := by
  refine ⟨reads, ?_⟩
  intro pointer offset byte read
  obtain ⟨block, found, _⟩ := Heap.loadByte_ok_iff.mp read
  have member := List.mem_of_find?_eq_some found
  have contains := List.find?_some found
  change (block.live && decide (block.base ≤ pointer + offset) &&
    decide (pointer + offset < block.base + block.size)) = true at contains
  simp only [Bool.and_eq_true, decide_eq_true_eq] at contains
  have lower := contains.1.2
  have upper := contains.2
  rcases separate block member with left | right
  · exact Or.inl (by dsimp only [Address] at *; omega)
  · exact Or.inr (by dsimp only [Address] at *; omega)

/-- A checked writer preserves the fragment even when the output was
    allocated before the IR and when printing borrows fresh string storage. -/
theorem ReadOnlyMemory.afterOutput (frame : ReadOnlyMemory reference before address capacity)
    (effect : OutputEffect before after destination bytes)
    (lower : address ≤ destination) (upper : destination + bytes.length ≤ address + capacity) :
    ReadOnlyMemory reference after address capacity := by
  refine ⟨?_, frame.outside⟩
  intro pointer offset byte read
  apply effect.outside (frame.reads _ _ _ read)
  rcases frame.outside _ _ _ read with left | right
  · exact Or.inl (by omega)
  · exact Or.inr (by omega)

end Lanius.Semantics
