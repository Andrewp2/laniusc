import verified_compiler.tests.direct_byte_io_read

namespace ByteIoReadTests

open Lanius Lanius.Core Lanius.Semantics

private def reader := Extracted.«verified::byte_io».Functions.«read_file».core

private def setup (bytes : List UInt8) (total position : Nat) : State :=
  ({ heap := {
      blocks := [
      { base := 4, size := 4, alignment := 4, bytes, owned := false },
      { base := 8, size := 16, alignment := 4,
        bytes := List.flatten (List.replicate 4 (i32Bytes 11)), owned := false }]
      nextAddress := 24 } } : State)
    |>.bindLocal (reader.argumentId 3) (.rawSlice (.scalar (.signed .i32)) 4 1)
    |>.bindLocal (reader.argumentId 1) (.rawSlice (.scalar (.signed .i32)) 8 4)
    |>.bindLocal (reader.bindingId 1) (.signed .i32 total)
    |>.bindLocal (reader.bindingId 6) (.signed .i32 position)

-- A concrete inhabitant of every copy-contract precondition, not just an
-- evaluator example. The selected packed word is negative and total is nonzero.
theorem copyAtNonzeroCursor : ∃ heap,
    RunsExpr extractedProgram (setup [0, 127, 128, 255] 1 2) (reader.effectExpression 1)
      .unit { setup [0, 127, 128, 255] 1 2 with heap } ∧
    Memory.BytesWrite (setup [0, 127, 128, 255] 1 2).heap heap 20 (i32Bytes 128) := by
  exact ByteIoReadProof.actualCopyByte (state := setup [0, 127, 128, 255] 1 2)
    (words := 1) (capacity := 4) (address := 4) (destination := 8) (value := 128)
    1 2 (by decide) (by decide) (by decide)
    rfl rfl rfl rfl (Memory.Heap.Readable.of_loadBytes rfl) (Memory.Heap.Readable.of_loadBytes rfl)
    (by simp [Memory.HeapBlockBasesUnique, setup, State.bindLocal, State.bindCell]) rfl rfl

#print axioms copyAtNonzeroCursor

-- Exercise every lane (including a negative packed word), nonzero cursors,
-- neighboring nonzero output slots, and the first out-of-bounds destination.
#eval (do
  for bytes in [[0, 127, 128, 255], [255, 128, 127, 0]] do
    for total in List.range 4 do
      for position in List.range 4 do
        let before := setup bytes total position
        match evalExpr 12 extractedProgram before (reader.effectExpression 1) with
        | .done .unit after =>
            unless total + position < 4 do
              throw (IO.userError "out-of-bounds copy unexpectedly succeeded")
            let expected := List.flatten ((List.range 4).map fun slot =>
              i32Bytes (if slot = total + position then (bytes[position]!).toNat else 11))
            let unchanged := match after.heap.loadBytes 8 16, after.heap.loadBytes 4 4 with
              | .ok actual, .ok packed => actual == expected && packed == bytes
              | _, _ => false
            unless unchanged do
              throw (IO.userError "copy changed the wrong slot, lane, or source bytes")
        | .trapped _ _ =>
            unless 4 ≤ total + position do
              throw (IO.userError "valid copy trapped")
        | _ => throw (IO.userError "copy did not finish as a store or bounds trap") : IO Unit)

end ByteIoReadTests
