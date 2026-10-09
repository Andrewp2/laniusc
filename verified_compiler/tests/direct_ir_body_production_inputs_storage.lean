import verified_compiler.tests.direct_ir_body_production_inputs
import Lanius.Extraction.OutputPacking.Read

namespace IRBodyProductionInputs

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics

/-- Readable used depth slots supply their arbitrary existing i32 values.
    Neither spare descriptor slots nor particular stale contents are required. -/
theorem originalReadableDepths (room : before.heap.Readable pointer (slots * 4))
    (bound : slots ≤ capacity) :
    ∃ values : Nat → Int32, ∀ index, index < slots →
      readRawSliceIndex extractedProgram before (.scalar (.signed .i32)) pointer capacity index =
        .ok (.signed .i32 (values index).toInt) := by
  classical
  have one (index : Nat) (inside : index < slots) : ∃ value : Int32,
      readRawSliceIndex extractedProgram before (.scalar (.signed .i32)) pointer capacity index =
        .ok (.signed .i32 value.toInt) := by
    obtain ⟨word, loaded⟩ := Extraction.OutputPacking.readableWord
      (room.subrange (start := index * 4) (length := 4) (by omega))
    exact ⟨Int32.ofBitVec word, readRawSliceIndex_i32Bytes extractedProgram before
      (Nat.lt_of_lt_of_le inside bound) loaded⟩
  let values (index : Nat) : Int32 := if inside : index < slots then (one index inside).choose else 0
  refine ⟨values, fun index inside => ?_⟩
  dsimp only [values]
  rw [dif_pos inside]
  exact (one index inside).choose_spec

#print axioms originalReadableDepths

end IRBodyProductionInputs
