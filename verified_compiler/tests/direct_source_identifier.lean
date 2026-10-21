import verified_compiler.tests.direct_symbol_spelling
import verified_compiler.tests.direct_output_writer
import Lanius.Extraction.WriterProof
import Lanius.Extraction.WriterCounter
import Lanius.Semantics.ReadOnlyMemory
import Lanius.Semantics.LoopRun

namespace SourceIdentifierProof

open Lanius Lanius.Core Lanius.Semantics Lanius.Extraction Lanius.Memory SymbolSpellingProof

def source := Extracted.«verified::lean_syntax».Functions.«source_identifier».core
private def outputId := source.argumentId 0
private def capacityId := source.argumentId 1
private def positionId := source.argumentId 2
private def nextId := source.bindingId 2
private def indexId := source.bindingId 3
private def spellingId := source.bindingId 0
private def bytesId := source.bindingId 1

private def loop? : Stmt → Option (Expr × Stmt)
  | .sequence first second => loop? first <|> loop? second
  | .letLocal _ _ _ body => loop? body
  | .whileLoop condition body => some (condition, body)
  | _ => none
private def actualLoop : Expr × Stmt :=
  (loop? (source.body.getD .skip)).getD (.value (.boolean true), .skip)
private def actualWriter : Expr := match actualLoop.2 with
  | .sequence (.expression (.assign .set _ writer)) _ => writer
  | _ => .value .unit
private def copyBody : Stmt := match source.body with
  | some (.letLocal _ _ _ (.sequence _ (.letLocal _ _ _ body))) => body
  | _ => .skip

/-- Prepared native byte span. The catalog contract below supplies its bounds;
    the memory fragment is separated from writable output, not unchanged heap. -/
private structure CopyInput (base : State) extends OutputNaturalProof.Buffer base where
  reference : Heap
  sourceAddress : Nat
  sourceLength : Nat
  start : Nat
  bytes : List UInt8
  sourceFits : start + bytes.length < 2 ^ 31
  outputLocal : base.local? outputId = some (.rawSlice (.scalar (.signed .i32)) address words)
  capacityLocal : base.local? capacityId = some (.signed .i32 capacity)
  positionLocal : base.local? positionId = some (.signed .i32 position)
  bytesLocal : base.local? bytesId = some (.rawSlice (.scalar (.signed .i32)) sourceAddress sourceLength)
  spellingLocal : base.local? spellingId = some
    (spellingValue (.rawSlice (.scalar (.signed .i32)) sourceAddress sourceLength) start bytes.length true)
  memory : ReadOnlyMemory reference base.heap address (words * 4)
  contents : ∀ index (inside : index < bytes.length),
    readRawSliceIndex extractedProgram { heap := reference } (.scalar (.signed .i32))
      sourceAddress sourceLength (start + index) = .ok (.signed .i32 (bytes[index]'inside).toNat)
  space : position + bytes.length ≤ capacity
  environment : WriterEnvironment base

private abbrev CopyState (context : CopyInput base) (current : State) (index : Nat) : Prop :=
  WriterCounter base current nextId indexId (context.address + context.position) context.position
    (context.bytes.take index) index

private theorem iteration (context : CopyInput base) (current : CopyState context state index)
    (inside : index < context.bytes.length) :
    ∃ after, RunsStmt extractedProgram state actualLoop.2 .next after ∧ CopyState context after (index + 1) := by
  have formed := context.environment.formed
  core_facts [context, current]
  have prefixLength : (context.bytes.take index).length = index := by simp [List.length_take, Nat.le_of_lt inside]
  have space := context.space
  have storage := context.storage
  have inputFits := context.sourceFits
  have capacityFits := context.fits
  let buffer := context.toBuffer.afterWriter current.frame
  have reads := (context.memory.afterOutput current.frame.output (by omega) (by simp only [List.length_take]; omega)).reads
  have selected := reads.rawSlice (context.contents index inside)
  have offset := eval_i32_addNat extractedProgram.target context.start index (by omega)
  have first := current.first
  have second := current.second
  have byteBound := context.bytes[index].toNat_lt
  obtain ⟨written, byteRun, writeFrame⟩ := OutputWriterProof.byte buffer
    ⟨context.bytes[index].toNat, byteBound⟩ (by simp only [buffer, OutputNaturalProof.Buffer.afterWriter, prefixLength]; omega)
    (context.environment.afterWrite current.frame)
  have byteCall : RunsExpr extractedProgram state actualWriter
      (.signed .i32 (context.position + (context.bytes.take index ++ [context.bytes[index]]).length : Nat)) written := by
    apply RunsExpr.callArguments
    · core_arguments
    · simpa only [OutputByteProof.byteCall, Extracted.«verified::lean_output».Functions.«byte»,
        buffer, OutputNaturalProof.Buffer.afterWriter, List.length_append, List.length_cons,
        List.length_nil, Nat.add_zero, Nat.zero_add, Nat.add_assoc] using byteRun
  have written : WriterFrame state written
      (context.address + context.position + (context.bytes.take index).length) [context.bytes[index]] := by
    simpa only [buffer, OutputNaturalProof.Buffer.afterWriter, Nat.add_assoc, UInt8.ofNat_toNat] using writeFrame
  obtain ⟨middle, writeCursor, updated⟩ := current.advance formed byteCall written
  obtain ⟨after, increment, advanced⟩ := updated.increment (program := extractedProgram) formed (by omega)
  have cursor := updated.first
  exact ⟨after, by core_stmt, by simpa only [CopyState, List.take_succ_eq_append_getElem inside] using advanced⟩

private theorem copyLoop (context : CopyInput base) :
    ∃ after, RunsStmt extractedProgram
      ((base.bindLocal nextId (.signed .i32 context.position)).bindLocal indexId (.signed .i32 0))
      (.whileLoop actualLoop.1 actualLoop.2) .next after ∧ CopyState context after context.bytes.length := by
  have initial : CopyState context
      ((base.bindLocal nextId (.signed .i32 context.position)).bindLocal indexId (.signed .i32 0)) 0 :=
    by simpa only [CopyState, List.take_zero] using
      WriterCounter.start context.environment.formed context.environment.unique (by decide : nextId ≠ indexId)
  apply RunsStmt.whilePrefix (remaining := context.bytes.length)
    (invariant := fun remaining current => ∃ index, index + remaining = context.bytes.length ∧ CopyState context current index)
  · intro current ⟨index, total, frame⟩
    have same : index = context.bytes.length := by omega
    subst index
    core_facts [context, frame]
    exact ⟨current, .whileFalse (by core_run), frame⟩
  · intro remaining current ⟨index, total, frame⟩
    have inside : index < context.bytes.length := by omega
    core_facts [context, frame]
    obtain ⟨after, body, next⟩ := iteration context frame inside
    exact ⟨current, after, by core_run, body, index + 1, by omega, next⟩
  · exact ⟨0, by omega, initial⟩

private theorem prepared (context : CopyInput base) :
    ∃ after, RunsStmt extractedProgram base copyBody
      (.returned (some (.signed .i32 (context.position + context.bytes.length : Nat)))) after ∧
      WriterFrame base after (context.address + context.position) context.bytes := by
  obtain ⟨after, loopRun, final⟩ := copyLoop context
  have cursor := final.first
  simp only [List.take_length] at cursor
  have written : WriterFrame base after (context.address + context.position) context.bytes := by
    simpa only [List.take_length] using final.frame
  let bound := base.bindLocal nextId (.signed .i32 context.position)
  refine ⟨restoreLocals base (restoreLocals bound after), ?_,
    (written.restoreLocals bound).restoreLocals base⟩
  core_facts [context]
  apply RunsStmt.letLocal
  · core_run
  · apply RunsStmt.letLocal
    · core_run
    · core_stmt

/-- Source spelling retained by the existing catalog, with physical byte reads.
    This is a specification of native inputs, not an emitted certificate. -/
structure Name (reference : Heap) where
  catalog : Catalog
  unit : UnitSpan
  unitIndex : Nat
  tokenIndex : Nat
  start : Nat
  finish : Nat
  valid : ValidSpan catalog unit { heap := reference } unitIndex tokenIndex start finish
  address : Nat
  length : Nat
  bytes : List UInt8
  descriptor : catalog.bytes = .rawSlice (.scalar (.signed .i32)) address length
  byteLength : bytes.length = finish - start
  contents : ∀ index (inside : index < bytes.length),
    readRawSliceIndex extractedProgram { heap := reference } (.scalar (.signed .i32))
      address length (unit.sourceOffset + start + index) = .ok (.signed .i32 (bytes[index]'inside).toNat)

def Name.offset (name : Name reference) : Nat := name.unit.sourceOffset + name.start
def Name.referenceValue (name : Name reference) : Value := SymbolSpellingProof.referenceValue name.unitIndex name.tokenIndex

def call (buffer : OutputNaturalProof.Buffer state) (name : Name reference) : Expr :=
  .call source.id ([.rawSlice (.scalar (.signed .i32)) buffer.address buffer.words,
    .signed .i32 buffer.capacity, .signed .i32 buffer.position, name.catalog.value,
    name.referenceValue].map Expr.value)

/-- Total correctness of actual source-name emission. Lookup, byte copying,
    termination, cursor advancement and caller/input framing are all derived. -/
theorem actualCall (buffer : OutputNaturalProof.Buffer state) (name : Name reference)
    (memory : ReadOnlyMemory reference state.heap buffer.address (buffer.words * 4))
    (room : buffer.position + name.bytes.length ≤ buffer.capacity) (environment : WriterEnvironment state) :
    ∃ after, RunsExpr extractedProgram state (call buffer name)
      (.signed .i32 (buffer.position + name.bytes.length : Nat)) after ∧
      WriterFrame state after (buffer.address + buffer.position) name.bytes := by
  have formed := environment.formed
  core_call_framed Lanius.Extraction.RunsExpr.callWriter source as callee
  have native := name.valid.ofReads (after := callee) memory.reads
  have lookup := actualSpan name.catalog name.unit native (by core_formed)
  have length : (name.finish : Int) - name.start = name.bytes.length := by
    have span := name.valid.span
    have byteLength := name.byteLength
    omega
  rw [length, name.descriptor] at lookup
  apply RunsStmt.letReadWriter
  · apply RunsExpr.callPureArguments
    · core_arguments
    · exact lookup
  · intro ready pure
    let descriptor := Value.rawSlice (.scalar (.signed .i32)) name.address name.length
    let spelling := spellingValue descriptor name.offset name.bytes.length true
    let bound := ready.bindLocal spellingId spelling
    let bytesReady := bound.bindLocal bytesId descriptor
    have currentHeap : bytesReady.heap = state.heap := pure.heap
    let context : CopyInput bytesReady := {
      buffer with
      readable := by rw [currentHeap]; exact buffer.readable
      reference, sourceAddress := name.address, sourceLength := name.length,
      start := name.offset, bytes := name.bytes,
      sourceFits := by
        have range := name.valid.sourceRange
        have fits := name.valid.sourceFits
        have span := name.valid.span
        have byteLength := name.byteLength
        dsimp [Name.offset]
        omega
      outputLocal := by core_local
      capacityLocal := by core_local
      positionLocal := by core_local
      bytesLocal := by core_local
      spellingLocal := by core_local
      memory := by rw [currentHeap]; exact memory
      contents := name.contents
      space := room
      environment := environment.reheap (by exact pure.heap) (by exact pure.views) (by core_formed) }
    have write := prepared context
    apply RunsStmt.guardPureWriter false
    · simp
    · core_run
    · apply RunsStmt.letPureWriter
      · core_run
      · core_formed
      · exact write

/-- Invalid unit references reject before any source or output byte access. -/
theorem actualInvalidUnit (output : Value) (capacity position : Int) (catalog : Catalog) (unit token : Int)
    (bad : unit < 0 ∨ catalog.unitCount ≤ unit) (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state
      (.call source.id ([output, .signed .i32 capacity, .signed .i32 position,
        catalog.value, SymbolSpellingProof.referenceValue unit token].map Expr.value))
      (.signed .i32 (-1)) after ∧ PureFrame state after := by
  core_call_pure source as callee
  have lookup := SymbolSpellingProof.actualInvalidUnit catalog unit token bad (state := callee) (by core_formed)
  core_pure

#print axioms iteration
#print axioms copyLoop
#print axioms actualCall
#print axioms actualInvalidUnit

end SourceIdentifierProof
