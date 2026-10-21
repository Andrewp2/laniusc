import SelfCore
import Lanius.Core.Bindings
import Lanius.Extraction.OutputPacking.Read
import Lanius.Semantics.ExpressionProof
import Lanius.Semantics.RawStore

namespace ByteIoReadProof

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics Lanius.Extraction.OutputPacking

private def reader := Extracted.«verified::byte_io».Functions.«read_file».core

/-- One actual copy step, including its computed destination and exact native
    write. Arbitrary source words may include sign bits. Readability derives
    store success; only this slot's bytes change. -/
theorem actualCopyByte (total position : Nat) (fits : total + position < 2 ^ 31)
    (inputInside : position < words * 4) (outputInside : total + position < capacity)
    (packed : state.local? (reader.argumentId 3) = some (.rawSlice (.scalar (.signed .i32)) address words))
    (output : state.local? (reader.argumentId 1) = some (.rawSlice (.scalar (.signed .i32)) destination capacity))
    (index : state.local? (reader.bindingId 6) = some (.signed .i32 position))
    (cursor : state.local? (reader.bindingId 1) = some (.signed .i32 total))
    (inputReadable : state.heap.Readable address (words * 4))
    (outputReadable : state.heap.Readable destination (capacity * 4))
    (unique : HeapBlockBasesUnique state.heap) (noViews : state.i32ArrayViews = [])
    (byte : state.heap.loadByte address position = .ok value) :
    ∃ heap, RunsExpr extractedProgram state (reader.effectExpression 1) .unit { state with heap } ∧
      BytesWrite state.heap heap (destination + (total + position) * 4) (i32Bytes value.toNat) := by
  have positionFits : position < 2 ^ 31 := by omega
  refine RunsExpr.assignRawI32 (before := state) (indexed := state) (ready := state) output ?_ outputInside
    (outputReadable.subrange (by omega)) unique noViews ?_
  · exact .ofStable (threshold := 2) (by core_expr) rfl
  · obtain ⟨word, loaded, selected⟩ := readableByte (program := extractedProgram) inputReadable inputInside
    have same : (byteAt word ⟨position % 4, Nat.mod_lt _ (by decide)⟩).toNat = value.toNat :=
      congrArg UInt8.toNat (Except.ok.inj (selected.symm.trans byte))
    rw [← same]
    apply RunsExpr.ofStable (locals := rfl)
    apply readByteExpression (readFuel := 3) (shiftFuel := 3) (maskFuel := 1)
      word ⟨position % 4, Nat.mod_lt _ (by decide)⟩ rfl
    · apply StableExpr.rawSliceRead (sourceFuel := 1) (indexFuel := 2) (position := position / 4)
      · core_expr
      · core_expr
      · exact loaded
    · core_expr
    · core_expr

#print axioms actualCopyByte

end ByteIoReadProof
