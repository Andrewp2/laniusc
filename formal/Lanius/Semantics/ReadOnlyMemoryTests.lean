import Lanius.Semantics.ReadOnlyMemory

namespace Lanius.Semantics.ReadOnlyMemoryTests

open Lanius Lanius.Core Lanius.Memory

private def dataBlock : Block := { base := 32, size := 8, alignment := 4, bytes := i32Bytes 7 ++ i32Bytes 8 }
private def reference : Heap := { blocks := [dataBlock], nextAddress := 64 }
private def actual : Heap := { reference with blocks :=
  { base := 16, size := 8, alignment := 4, bytes := List.replicate 8 0 } :: reference.blocks }

-- The output precedes the protected data. An "all old bytes unchanged"
-- contract would incorrectly forbid writing this output buffer.
private theorem included : HeapReads reference actual := by
  intro pointer offset byte read
  obtain ⟨block, found, contents⟩ := Heap.loadByte_ok_iff.mp read
  have member := List.mem_of_find?_eq_some found
  simp only [reference, List.mem_singleton] at member
  subst block
  have inside := List.find?_some found
  change (true && decide (32 ≤ pointer + offset) && decide (pointer + offset < 40)) = true at inside
  simp only [Bool.and_eq_true, decide_eq_true_eq, true_and] at inside
  apply Heap.loadByte_ok_iff.mpr
  refine ⟨dataBlock, ?_, contents⟩
  have past : ¬pointer + offset < 24 := by dsimp only [Address] at *; omega
  simpa only [actual, Heap.containingBlock?, List.find?_cons, past, decide_false,
    Bool.and_false, Bool.false_eq_true, ↓reduceIte] using found

private theorem separated : ReadOnlyMemory reference actual 16 8 :=
  .ofBlocks included (by
    intro block member
    simp only [reference, List.mem_singleton] at member
    subst block
    exact Or.inr (by decide))

-- Both recursive native values and scalar slice reads use the existing
-- native-read theorem, not a new layout or byte-decoding proof per writer.
example (effect : OutputEffect actual after 18 [116, 114, 117, 101]) :
    readNativeValue 64 {} after (.scalar (.signed .i32)) 32 = .ok (.signed .i32 7) :=
  (separated.afterOutput effect (by decide) (by decide)).reads.nativeValue (by rfl)

example (effect : OutputEffect actual after 18 [102, 97, 108, 115, 101]) :
    readRawSliceIndex {} { heap := after } (.scalar (.signed .i32)) 32 2 1 = .ok (.signed .i32 8) :=
  (separated.afterOutput effect (by decide) (by decide)).reads.rawSlice
    (before := { heap := reference }) (by rfl)

-- Overlapping output is not admissible, even if all initial data is readable.
example : ¬ReadOnlyMemory reference actual 32 8 := by
  intro frame
  have outside := frame.outside 32 0 7 (by rfl)
  omega

#print axioms ReadOnlyMemory.afterOutput
#print axioms ReadOnlyMemory.ofBlocks

end Lanius.Semantics.ReadOnlyMemoryTests
