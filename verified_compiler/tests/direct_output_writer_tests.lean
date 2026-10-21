import verified_compiler.tests.direct_output_writer
import Lanius.Semantics.ScalarAssignment

namespace OutputWriterTests

open Lanius Lanius.Core Lanius.Semantics Lanius.Extraction Lanius.Memory

/-- The printer's real `next = byte(..., next, ...)` pattern: write heap bytes,
    then store the returned cursor in its original local cell. -/
theorem computedCursor (buffer : OutputNaturalProof.Buffer state) (value : Fin 256)
    (environment : WriterEnvironment state) (room : buffer.position + 1 ≤ buffer.capacity)
    (cellFound : state.cellId? 17 = some cell)
    (localFound : state.local? 17 = some (.signed .i32 buffer.position)) :
    ∃ after, RunsExpr extractedProgram state
      (.assign .set (.local 17)
        (.call Extracted.«verified::lean_output».Functions.«byte».core.id
          [.value (.rawSlice (.scalar (.signed .i32)) buffer.address buffer.words),
            .value (.signed .i32 buffer.capacity), .local 17, .value (.signed .i32 value.val)])) .unit after ∧
      after.local? 17 = some (.signed .i32 (buffer.position + 1 : Nat)) ∧
      OutputEffect state.heap after.heap (buffer.address + buffer.position) [UInt8.ofNat value.val] := by
  obtain ⟨ready, call, frame⟩ := OutputWriterProof.byte buffer value room environment
  have right : RunsExpr extractedProgram state
      (.call Extracted.«verified::lean_output».Functions.«byte».core.id
        [.value (.rawSlice (.scalar (.signed .i32)) buffer.address buffer.words),
          .value (.signed .i32 buffer.capacity), .local 17, .value (.signed .i32 value.val)])
      (.signed .i32 (buffer.position + 1 : Nat)) ready := by
    apply RunsExpr.callArguments (values := [.rawSlice (.scalar (.signed .i32)) buffer.address buffer.words,
      .signed .i32 buffer.capacity, .signed .i32 buffer.position, .signed .i32 value.val])
    · core_arguments
    · exact call
  obtain ⟨after, run, assigned, effect⟩ := RunsExpr.assignI32After cellFound localFound right
  have cellReady : ready.cellId? 17 = some cell := by simpa only [State.cellId?, right.choose_spec.2] using cellFound
  exact ⟨after, run, assignLocal_finds_assigned _ _ _ cellReady assigned,
    by simpa only [effect.heap] using frame.output⟩

#print axioms computedCursor

end OutputWriterTests
