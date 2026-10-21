import SelfOutputByte
import Lanius.Extraction.WriterFrame

namespace OutputSignedProof

open Lanius Lanius.Core Lanius.Semantics Lanius.Extraction OutputNaturalProof

private def source := Extracted.«verified::lean_syntax».Functions.«signed».core

def bytes (value : Int) : List UInt8 :=
  if value < 0 then [45] ++ OutputNaturalProof.bytes (decimalWidth (-value).toNat) (-value).toNat
  else OutputNaturalProof.bytes (decimalWidth value.toNat) value.toNat

def signedCall (output : Value) (capacity position value : Int) : Expr :=
  .call source.id ([output, .signed .i32 capacity, .signed .i32 position, .signed .i32 value].map Expr.value)

attribute [local core_local_rule] FreshCellFrame.localFound

/-- The actual signed writer terminates for every canonical i32, emits its
    decimal spelling, and preserves caller cells and all old memory outside
    the output. Its minimum-value branch may allocate fresh string storage. -/
theorem actualCall_formats (buffer : Buffer state) (value : Int)
    (canonical : -2147483648 ≤ value ∧ value < 2147483648)
    (room : buffer.position + (bytes value).length ≤ buffer.capacity)
    (formed : state.CellsWellFormed) (noViews : state.i32ArrayViews = [])
    (below : Memory.HeapBlocksBelowNext state.heap) (unique : Memory.HeapBlockBasesUnique state.heap) :
    ∃ after, RunsExpr extractedProgram state
        (signedCall (.rawSlice (.scalar (.signed .i32)) buffer.address buffer.words)
          buffer.capacity buffer.position value)
        (.signed .i32 (buffer.position + (bytes value).length : Nat)) after ∧
      WriterFrame state after (buffer.address + buffer.position) (bytes value) := by
  core_call_framed Lanius.Extraction.RunsExpr.callWriter source as callee
  have subtractMax : StableExpr 2 extractedProgram callee
      (.binary .subtract (.value (.signed .i32 0))
        (.constant Extracted.«verified::host».Constants.«I32_MAX».core.id)) (.signed .i32 (-2147483647)) callee := by
    apply StableExpr.binary (leftFuel := 1) (rightFuel := 1) <;> first | core_expr_step | decide | rfl
  have minimumValue : StableExpr 3 extractedProgram callee
      (.binary .subtract (.binary .subtract (.value (.signed .i32 0))
        (.constant Extracted.«verified::host».Constants.«I32_MAX».core.id)) (.value (.signed .i32 1)))
      (.signed .i32 (-2147483648)) callee := by
    apply StableExpr.binary (rightFuel := 1) subtractMax StableExpr.value <;> first | decide | rfl
  by_cases minimum : value = -2147483648
  · subst value
    rw [show bytes (-2147483648) = World.utf8Bytes "-2147483648" by decide]
    have minimumRoom : buffer.position + (World.utf8Bytes "-2147483648").length ≤ buffer.capacity :=
      by simpa only [show bytes (-2147483648) = World.utf8Bytes "-2147483648" by decide] using room
    let text : OutputTextProof.TextBuffer callee "-2147483648" := {
      address := buffer.address, words := buffer.words, capacity := buffer.capacity, position := buffer.position,
      capacityFits := buffer.fits, space := minimumRoom, storage := buffer.storage, readable := buffer.readable }
    obtain ⟨after, run, written, cells, world, views⟩ := OutputTextProof.actualCall_copies text
      (by core_formed) noViews below unique
    refine ⟨after, ?_, ⟨.borrow _ below written, cells, world, views⟩⟩
    apply RunsStmt.sequenceCompleted
    · apply RunsStmt.ifThenElseTrue (conditionAfter := callee)
      · core_run
      · core_stmt
    · simp
  · by_cases negative : value < 0
    · simp only [bytes, if_pos negative, List.length_append,
        List.length_singleton, OutputNaturalProof.bytes_length]
      have magnitude : ((-value).toNat : Int) = -value := Int.toNat_of_nonneg (by omega)
      have magnitudeFits : (-value).toNat < 2 ^ 31 := by omega
      have space : buffer.position + 1 + decimalWidth (-value).toNat ≤ buffer.capacity := by
        simpa only [bytes, if_pos negative, List.length_append,
          List.length_singleton, OutputNaturalProof.bytes_length, Nat.add_assoc] using room
      have available : buffer.position < buffer.capacity := by omega
      let byte : OutputByteProof.ByteBuffer callee := {
        address := buffer.address, words := buffer.words, capacity := buffer.capacity, cursor := buffer.position,
        capacityFits := buffer.fits, available := available, storage := buffer.storage,
        readable := buffer.readable.subrange (by have storage := buffer.storage; omega) }
      obtain ⟨ready, byteRun, written, cells, world, views⟩ := OutputByteProof.actualCall_writes byte ⟨45, by decide⟩
        (by core_formed) noViews unique
      have first : WriterFrame callee ready (buffer.address + buffer.position) [45] :=
        ⟨.write (by simpa [byte, show UInt8.ofNat 45 = (45 : UInt8) by decide] using
          (Memory.BytesWrite.refl (heap := callee.heap) unique).snoc written), cells, world, views⟩
      let base := ready.bindLocal (source.bindingId 0) (.signed .i32 (buffer.position + 1 : Nat))
      have readyFormed := first.afterFormed (by core_formed)
      have locals := byteRun.choose_spec.2
      let nextBuffer : Buffer base := { buffer with
        position := buffer.position + 1
        readable := first.output.readable buffer.readable }
      obtain ⟨after, naturalRun, output, nextCells, nextWorld, nextViews⟩ :=
        OutputNaturalProof.actualCall_formats nextBuffer (-value).toNat (readyFormed.bindLocal _ _)
          magnitudeFits space (views.trans noViews) first.output.unique
      have naturalResult := naturalRun
      simp only [naturalCall, nextBuffer, magnitude] at naturalResult
      have subtraction := eval_i32_subNonneg extractedProgram.target 0 value (by omega) (by omega)
      simp only [Int.zero_sub] at subtraction
      core_facts [buffer]
      have initial : RunsExpr extractedProgram callee
          (.call Extracted.«verified::lean_output».Functions.«byte».core.id
            [.local (source.argumentId 0), .local (source.argumentId 1), .local (source.argumentId 2),
             .constant Extracted.«verified::ascii».Constants.«MINUS».core.id])
          (.signed .i32 (buffer.position + 1 : Nat)) ready := by core_run
      have body : RunsStmt extractedProgram base
          (.returnValue (some (.call Extracted.«verified::lean_output».Functions.«natural».core.id
            [.local (source.argumentId 0), .local (source.argumentId 1), .local (source.bindingId 0),
             .binary .subtract (.value (.signed .i32 0)) (.local (source.argumentId 3))])))
          (.returned (some (.signed .i32 (buffer.position + 1 + decimalWidth (-value).toNat : Nat)))) after := by
        core_stmt
      have second : WriterFrame base after (buffer.address + buffer.position + 1)
          (OutputNaturalProof.bytes (decimalWidth (-value).toNat) (-value).toNat) :=
        ⟨.write (by simpa only [nextBuffer, Nat.add_assoc] using output), nextCells, nextWorld, nextViews⟩
      obtain ⟨finished, scopeRun, frame⟩ := Lanius.Extraction.RunsStmt.letWriter initial first (by core_formed) body second
      have scopedResult := scopeRun
      simp only [Nat.add_assoc] at scopedResult
      refine ⟨finished, ?_, ?_⟩
      · core_stmt
      · simpa only [bytes, if_pos negative] using frame
    · simp only [bytes, if_neg negative, OutputNaturalProof.bytes_length]
      have magnitude : (value.toNat : Int) = value := Int.toNat_of_nonneg (by omega)
      have fits : value.toNat < 2 ^ 31 := by omega
      have space : buffer.position + decimalWidth value.toNat ≤ buffer.capacity := by
        simpa only [bytes, if_neg negative, OutputNaturalProof.bytes_length] using room
      let input : Buffer callee := { buffer with readable := buffer.readable }
      obtain ⟨after, run, written, cells, world, views⟩ := OutputNaturalProof.actualCall_formats input value.toNat
        (by core_formed) fits space noViews unique
      have result := run
      simp only [naturalCall, input, magnitude] at result
      exact ⟨after, by core_stmt, ⟨.write written, cells, world, views⟩⟩

#print axioms actualCall_formats

-- The contract covers all canonical values, not merely hand-picked runs.
-- The byte before the unaligned destination, a neighboring allocation, and
-- a shadowed caller binding are preserved even in the borrowed-string branch.
private def sample : State :=
  ({ heap := { blocks := [
      { base := 4, size := 12, alignment := 4, bytes := List.replicate 12 255 },
      { base := 20, size := 1, alignment := 1, bytes := [77] }], nextAddress := 21 } } : State).bindLocal
    (source.argumentId 0) (.signed .i32 91)

private def sampleBuffer : Buffer sample := {
  address := 4, words := 3, capacity := 12, position := 1,
  fits := by decide, storage := by decide,
  readable := Memory.Heap.Readable.of_loadBytes (bytes := List.replicate 12 255) rfl }

example (value : Int) (canonical : -2147483648 ≤ value ∧ value < 2147483648) :
    ∃ after, RunsExpr extractedProgram sample (signedCall (.rawSlice (.scalar (.signed .i32)) 4 3) 12 1 value)
      (.signed .i32 (1 + (bytes value).length : Nat)) after ∧
      after.heap.loadBytes 5 (bytes value).length = .ok (bytes value) ∧
      after.local? (source.argumentId 0) = some (.signed .i32 91) ∧
      after.heap.loadByte 4 0 = .ok 255 ∧ after.heap.loadByte 20 0 = .ok 77 := by
  have length : (bytes value).length ≤ 11 := by
    by_cases minimum : value = -2147483648
    · subst value; decide
    · by_cases negative : value < 0
      · have magnitude : ((-value).toNat : Int) = -value := Int.toNat_of_nonneg (by omega)
        have width := (decimalWidth_spec (-value).toNat (by omega)).2.1
        simp only [bytes, if_pos negative, List.length_append,
          List.length_singleton, OutputNaturalProof.bytes_length]; omega
      · have magnitude : (value.toNat : Int) = value := Int.toNat_of_nonneg (by omega)
        have width := (decimalWidth_spec value.toNat (by omega)).2.1
        simp only [bytes, if_neg negative, OutputNaturalProof.bytes_length]; omega
  obtain ⟨after, run, frame⟩ := actualCall_formats sampleBuffer value canonical (by change 1 + _ ≤ 12; omega)
    (by simp [sample, State.CellsWellFormed, State.bindLocal, State.bindCell]) rfl
    (by simp [sample, Memory.HeapBlocksBelowNext, State.bindLocal, State.bindCell])
    (by simp [sample, Memory.HeapBlockBasesUnique, State.bindLocal, State.bindCell])
  exact ⟨after, run, frame.output.loadBytes (sampleBuffer.readable.subrange (by change 1 + _ ≤ 12; omega)),
    frame.cells.localFound run.choose_spec.2 _ _ rfl,
    frame.output.outside rfl (Or.inl (by decide)), frame.output.outside rfl (Or.inr (by change 5 + _ ≤ 20; omega))⟩

example : bytes (-2147483648) = World.utf8Bytes "-2147483648" := by decide
example : bytes (-1) = World.utf8Bytes "-1" := by decide
example : bytes 0 = World.utf8Bytes "0" := by decide
example : bytes 2147483647 = World.utf8Bytes "2147483647" := by decide

end OutputSignedProof
