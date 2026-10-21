import verified_compiler.tests.direct_source_identifier

namespace EscapedIdentifierProof

open Lanius Lanius.Core Lanius.Semantics Lanius.Extraction Lanius.Memory
open SourceIdentifierProof

private def source := Extracted.«verified::lean_syntax».Functions.«escaped_identifier».core
private def nextId := source.bindingId 0

def bytes (name : Name reference) : List UInt8 := World.utf8Bytes "«" ++ name.bytes ++ World.utf8Bytes "»"
def call (buffer : OutputNaturalProof.Buffer state) (name : Name reference) : Expr :=
  .call source.id ([.rawSlice (.scalar (.signed .i32)) buffer.address buffer.words,
    .signed .i32 buffer.capacity, .signed .i32 buffer.position, name.catalog.value,
    name.referenceValue].map Expr.value)

/-- Escape a name using actual UTF-8 delimiters and the checked catalog/copy
    path. No successful nested lookup or writer call is assumed. -/
theorem actualCall (buffer : OutputNaturalProof.Buffer state) (name : Name reference)
    (memory : ReadOnlyMemory reference state.heap buffer.address (buffer.words * 4))
    (room : buffer.position + (bytes name).length ≤ buffer.capacity) (environment : WriterEnvironment state) :
    ∃ after, RunsExpr extractedProgram state (call buffer name)
      (.signed .i32 (buffer.position + (bytes name).length : Nat)) after ∧
      WriterFrame state after (buffer.address + buffer.position) (bytes name) := by
  have formed := environment.formed
  simp only [bytes, List.length_append] at room
  core_call_framed Lanius.Extraction.RunsExpr.callWriter source as callee
  let input : OutputNaturalProof.Buffer callee := { buffer with readable := buffer.readable }
  let initialEnvironment : WriterEnvironment callee := environment.reheap rfl rfl (by core_formed)
  obtain ⟨first, firstRun, firstFrame⟩ := OutputWriterProof.text input "«" (by dsimp [input]; omega) initialEnvironment
  let bound := first.bindLocal nextId (.signed .i32 (buffer.position + (World.utf8Bytes "«").length : Nat))
  have cursor : WriterCursor callee bound nextId first.nextCell
      (buffer.address + buffer.position) buffer.position (World.utf8Bytes "«") :=
    WriterCursor.start firstFrame (by core_formed) firstRun.choose_spec.2 nextId
  let nextBuffer := input.afterWriter cursor.frame
  have retained := memory.afterOutput cursor.frame.output (by omega) (by have storage := buffer.storage; omega)
  have nameRoom : nextBuffer.position + name.bytes.length ≤ nextBuffer.capacity := by
    dsimp [nextBuffer, OutputNaturalProof.Buffer.afterWriter, input]
    omega
  have nameWriter := SourceIdentifierProof.actualCall nextBuffer name retained nameRoom
    (initialEnvironment.afterWrite cursor.frame)
  obtain ⟨second, sourceRun, nextCursor⟩ := cursor.advanceArguments (by core_formed)
    (expressions := [.local (source.argumentId 0), .local (source.argumentId 1), .local nextId,
      .local (source.argumentId 3), .local (source.argumentId 4)])
    (by simpa only [SourceIdentifierProof.call, nextBuffer, OutputNaturalProof.Buffer.afterWriter, input,
      List.length_append, Nat.add_assoc] using nameWriter)
    (by core_arguments) (by simp only [List.length_append])
  have closing := OutputWriterProof.textAt input nextCursor.frame "»" 2 rfl
    (by simpa only [input, List.length_append, Nat.add_assoc] using room) initialEnvironment
  obtain ⟨after, finish, frame⟩ := nextCursor.finishArguments closing
    (expressions := [.local (source.argumentId 0), .local (source.argumentId 1), .local nextId,
      .value (.string "»"), .value (.signed .i32 2)]) (by core_arguments) rfl
  have tail : ∃ after, RunsStmt extractedProgram bound
      (match source.body with | some (.letLocal _ _ _ tail) => tail | _ => .skip)
      (.returned (some (.signed .i32 (buffer.position + (bytes name).length : Nat)))) after ∧
      WriterFrame callee after (buffer.address + buffer.position) (bytes name) := by
    exact ⟨after, by core_stmt, frame⟩
  obtain ⟨after, tailRun, frame⟩ := tail
  refine ⟨restoreLocals first after, ?_, frame.restoreLocals first⟩
  apply RunsStmt.letLocal
  · apply RunsExpr.callArguments
    · core_arguments
    · exact firstRun
  · exact tailRun

#print axioms actualCall

end EscapedIdentifierProof
