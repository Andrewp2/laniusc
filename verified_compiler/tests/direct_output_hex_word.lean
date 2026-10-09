import direct_output_byte
import direct_output_cursor
import direct_output_hex
import Lanius.Core.Bindings
import Lanius.Extraction.OutputLoop
import Lanius.Extraction.OutputPacking.Nibble
import Lanius.Semantics.CallerFrame

namespace OutputHexWordProof

open Lanius Lanius.Core Lanius.Semantics Lanius.Extraction Lanius.Extraction.OutputPacking

private def source := Extracted.«verified::lean_output».Functions.«hex_word».core
private def destinationId := source.argumentId 0
private def wordId := source.argumentId 1
private def indexId := source.bindingId 0
private def nibbleId := source.bindingId 1
private def body := source.body.getD .skip
private def loop : Expr × Stmt := match body with
  | .letLocal _ _ _ (.sequence (.whileLoop guard iteration) _) => (guard, iteration)
  | _ => (.value (.boolean true), .skip)
private def read : Expr := match loop.2 with
  | .letLocal _ _ value _ => value
  | _ => .value .unit
private def branch : Stmt := match loop.2 with
  | .letLocal _ _ _ (.sequence first _) => first
  | _ => .skip
private def write : Expr := match branch with
  | .ifThenElse (.binary .less call _) _ _ => call
  | _ => .value .unit

def digit (word : BitVec 32) (index : Fin 8) : BitVec 4 :=
  nibbleAt word ⟨7 - index.val, by omega⟩
def code (word : BitVec 32) (index : Fin 8) : Nat := OutputHexProof.digitCode (digit word index).toNat
def bytes (word : BitVec 32) : List UInt8 := List.ofFn fun index => UInt8.ofNat (code word index)

@[simp] theorem bytes_length : (bytes word).length = 8 := List.length_ofFn

structure Buffer (state : State) where
  address : Nat
  words : Nat
  capacity : Nat
  position : Nat
  fits : capacity < 2 ^ 31
  start : position ≤ capacity
  storage : capacity ≤ words * 4
  readable : state.heap.Readable address (words * 4)

def cursorValue (buffer : Buffer state) : Value :=
  .structure OutputCursorProof.cursorType [
    .rawSlice (.scalar (.signed .i32)) buffer.address buffer.words,
    .signed .i32 buffer.capacity, .signed .i32 buffer.position]

private structure Context (base : State) (word : BitVec 32) where
  buffer : Buffer base
  formed : base.CellsWellFormed
  destination : base.local? destinationId = some (cursorValue buffer)
  value : base.local? wordId = some (.signed .i32 word.toInt)

private theorem readDigit {index : Nat} (context : Context base word)
    (frame : CountedLocal base state indexId index) (inside : index < 8) :
    StableExpr 6 extractedProgram state read (.signed .i32 (digit word ⟨index, inside⟩).toNat) state := by
  core_facts [context, frame]
  apply readNibbleExpression (readFuel := 1) (shiftFuel := 4) (maskFuel := 1)
    word ⟨7 - index, by omega⟩ rfl
  · core_expr
  · core_expr
  · core_expr

private theorem prepareDigit {index : Nat} (context : Context base word)
    (frame : CountedLocal base state indexId index) (inside : index < 8) :
    ∃ prepared, RunsExpr extractedProgram
        (state.bindLocal nibbleId (.signed .i32 (digit word ⟨index, inside⟩).toNat))
        (.call Extracted.«verified::lean_output».Functions.«hex_digit».core.id [.local nibbleId])
        (.signed .i32 (code word ⟨index, inside⟩)) prepared ∧
      PureFrame (state.bindLocal nibbleId (.signed .i32 (digit word ⟨index, inside⟩).toNat)) prepared := by
  core_facts [context, frame]
  obtain ⟨prepared, call, pure⟩ := OutputHexProof.actualCall
    (state := state.bindLocal nibbleId (.signed .i32 (digit word ⟨index, inside⟩).toNat))
    ⟨(digit word ⟨index, inside⟩).toNat, (digit word ⟨index, inside⟩).isLt⟩ (by core_formed)
  refine ⟨prepared, ?_, pure⟩
  core_run

private def arguments : List Expr := match write with
  | .call _ arguments => arguments
  | _ => []
private def values (buffer : Buffer base) (word : BitVec 32) (index : Fin 8) : List Value := [
  .rawSlice (.scalar (.signed .i32)) buffer.address buffer.words, .signed .i32 buffer.capacity,
  .signed .i32 (buffer.position + index.val), .signed .i32 (code word index)]

private theorem writeArguments {index : Nat} (context : Context base word)
    (frame : CountedLocal base state indexId index) (inside : index < 8)
    (fits : context.buffer.position + index < 2 ^ 31) :
    ∃ prepared, RunsExprs extractedProgram
        (state.bindLocal nibbleId (.signed .i32 (digit word ⟨index, inside⟩).toNat))
        arguments (values context.buffer word ⟨index, inside⟩) prepared ∧
      PureFrame (state.bindLocal nibbleId (.signed .i32 (digit word ⟨index, inside⟩).toNat)) prepared := by
  core_facts [context, frame]
  obtain ⟨prepared, digitRun, pure⟩ := prepareDigit context frame inside
  refine ⟨prepared, ?_, pure⟩
  core_arguments

private theorem iteration (context : Context base word)
    (current : OutputState base state indexId index context.buffer.address
      context.buffer.position context.buffer.words (bytes word) (fun byte => [byte]))
    (inside : index < 8) (space : context.buffer.position + index < context.buffer.capacity)
    (noViews : base.i32ArrayViews = []) :
    ∃ after, RunsStmt extractedProgram state loop.2 .next after ∧
      OutputState base after indexId (index + 1) context.buffer.address
        context.buffer.position context.buffer.words (bytes word) (fun byte => [byte]) := by
  core_facts [context, current]
  have fits : context.buffer.position + index < 2 ^ 31 := by omega
  obtain ⟨prepared, argumentsRun, pure⟩ := writeArguments context current.toCountedLocal inside fits
  have preparedViews : prepared.i32ArrayViews = [] := pure.views.trans (current.views.trans noViews)
  let byte : Fin 256 := ⟨code word ⟨index, inside⟩,
    OutputHexProof.digitCode_bound ⟨(digit word ⟨index, inside⟩).toNat,
      (digit word ⟨index, inside⟩).isLt⟩⟩
  obtain ⟨middle, call, effect, cells, world, views⟩ := OutputByteProof.actualCall_writes
    (state := prepared)
    { address := context.buffer.address, words := context.buffer.words,
      capacity := context.buffer.capacity, cursor := context.buffer.position + index,
      capacityFits := context.buffer.fits, available := space, storage := context.buffer.storage,
      readable := by simpa only [pure.heap, State.bindLocal, State.bindCell] using
        (current.readable.subrange (start := (context.buffer.position + index) / 4 * 4)
          (length := 4) (by have storage := context.buffer.storage; omega)) }
    byte pure.afterFormed preparedViews
      (by simpa only [pure.heap, State.bindLocal, State.bindCell] using current.written.unique)
  have callRun : RunsExpr extractedProgram
      (state.bindLocal nibbleId (.signed .i32 (digit word ⟨index, inside⟩).toNat)) write
      (.signed .i32 (context.buffer.position + index + 1 : Nat)) middle := by
    simp only [OutputByteProof.byteCall, List.map_cons, List.map_nil,
      Int.natCast_add] at call
    core_run
  have action : RunsStmt extractedProgram
      (state.bindLocal nibbleId (.signed .i32 (digit word ⟨index, inside⟩).toNat)) branch .next middle := by
    core_stmt
  obtain ⟨after, bodyRun, counter, heap, nextWorld, nextViews⟩ := CountedLocal.stepWith
    (type := .scalar (.signed .i32)) current.toCountedLocal context.formed (by decide) (by omega)
    (.ofStable (readDigit context current.toCountedLocal inside) rfl) action (pure.cells.trans cells)
  have insideBytes : index < (bytes word).length := by simpa only [bytes_length] using inside
  refine ⟨after, bodyRun, current.advance insideBytes ?_ counter
    (nextWorld.trans (world.trans pure.world)) (nextViews.trans (views.trans pure.views))⟩
  have byteEq : UInt8.ofNat byte.val = (bytes word)[index]'insideBytes := by
    exact (List.getElem_ofFn (f := fun index => UInt8.ofNat (code word index))
      (i := index) insideBytes).symm
  simpa only [heap, pure.heap, State.bindLocal, State.bindCell, Nat.add_assoc, byteEq,
    List.flatMap_singleton', List.length_take, Nat.min_eq_left (Nat.le_of_lt insideBytes)] using effect.asBytes

private theorem rejectedIteration (context : Context base word)
    (current : OutputState base state indexId index context.buffer.address
      context.buffer.position context.buffer.words (bytes word) (fun byte => [byte]))
    (inside : index < 8) (full : context.buffer.position + index = context.buffer.capacity) :
    ∃ after, RunsStmt extractedProgram state loop.2 (.returned (some (.signed .i32 (-1)))) after ∧
      OutputState base after indexId index context.buffer.address
        context.buffer.position context.buffer.words (bytes word) (fun byte => [byte]) := by
  core_facts [context, current]
  have fits : context.buffer.position + index < 2 ^ 31 := full ▸ context.buffer.fits
  obtain ⟨prepared, argumentsRun, pure⟩ := writeArguments context current.toCountedLocal inside fits
  obtain ⟨middle, rejected, frame⟩ := OutputByteProof.actualCall_rejects prepared
    (.rawSlice (.scalar (.signed .i32)) context.buffer.address context.buffer.words)
    context.buffer.capacity (context.buffer.position + index) (code word ⟨index, inside⟩)
    pure.afterFormed (by omega)
  have callRun : RunsExpr extractedProgram
      (state.bindLocal nibbleId (.signed .i32 (digit word ⟨index, inside⟩).toNat))
      write (.signed .i32 (-1)) middle := by
    simp only [OutputByteProof.byteCall, List.map_cons, List.map_nil] at rejected
    core_run
  have bodyRun : RunsStmt extractedProgram state loop.2 (.returned (some (.signed .i32 (-1))))
      (restoreLocals state middle) := by
    apply RunsStmt.letLocal (.ofStable (readDigit context current.toCountedLocal inside) rfl)
    core_stmt
  exact ⟨_, bodyRun, current.transPure
    (((CallerFrame.refl (by core_formed)).bindLocal nibbleId _).transPure (pure.trans frame)).restoreLocals⟩

def count (buffer : Buffer state) := min 8 (buffer.capacity - buffer.position)
def result (buffer : Buffer state) : Int :=
  if count buffer = 8 then (buffer.position + 8 : Nat) else -1
def hexCall (buffer : Buffer state) (word : BitVec 32) : Expr :=
  .call source.id [ .value (cursorValue buffer), .value (.signed .i32 word.toInt)]
private def completion (buffer : Buffer state) : Completion :=
  if count buffer = 8 then .next else .returned (some (.signed .i32 (-1)))

private theorem runLoop (context : Context base word)
    (unique : Memory.HeapBlockBasesUnique base.heap) (noViews : base.i32ArrayViews = []) :
    ∃ after, RunsStmt extractedProgram (base.bindLocal indexId (.signed .i32 0))
        (.whileLoop loop.1 loop.2) (completion context.buffer) after ∧
      OutputState base after indexId (count context.buffer) context.buffer.address
        context.buffer.position context.buffer.words (bytes word) (fun byte => [byte]) := by
  apply OutputState.run (limit := count context.buffer) (position := context.buffer.position)
    (items := bytes word) (encode := fun byte => [byte]) (OutputState.start context.formed context.buffer.readable unique)
  · intro state current
    core_facts [context, current]
    by_cases all : count context.buffer = 8
    · refine ⟨state, ?_, current⟩
      simp only [completion, all, ↓reduceIte]
      apply RunsStmt.whileFalse
      core_run
    · have inside : count context.buffer < 8 := by unfold count at *; omega
      have full : context.buffer.position + count context.buffer = context.buffer.capacity := by
        have start := context.buffer.start
        unfold count at *; omega
      obtain ⟨after, run, next⟩ := rejectedIteration context current inside full
      refine ⟨after, ?_, next⟩
      simp only [completion, all, ↓reduceIte]
      apply RunsStmt.whileReturn (middle := state) (iteration := run)
      core_run
  · intro index state inside current
    have inWord : index < 8 := by unfold count at inside; omega
    have space : context.buffer.position + index < context.buffer.capacity := by
      unfold count at inside; omega
    obtain ⟨after, run, next⟩ := iteration context current inWord space noViews
    refine ⟨after, ?_, run, next⟩
    core_facts [context, current]
    core_run

/-- The actual formatter writes the largest available prefix of eight hex
    digits. Insufficient capacity returns -1 after exactly those partial writes. -/
theorem actualCall_formats (buffer : Buffer state) (word : BitVec 32)
    (formed : state.CellsWellFormed) (noViews : state.i32ArrayViews = [])
    (unique : Memory.HeapBlockBasesUnique state.heap) :
    ∃ after, RunsExpr extractedProgram state (hexCall buffer word) (.signed .i32 (result buffer)) after ∧
      Memory.BytesWrite state.heap after.heap (buffer.address + buffer.position)
        ((bytes word).take (count buffer)) ∧
      FreshCellFrame state after ∧ after.world = state.world ∧ after.i32ArrayViews = state.i32ArrayViews := by
  let bindings : List (VarId × Value) :=
    [(destinationId, cursorValue buffer), (wordId, .signed .i32 word.toInt)]
  let callee := ({ state with locals := [] }).bindLocals bindings
  let context : Context callee word := {
    buffer := ⟨buffer.address, buffer.words, buffer.capacity, buffer.position,
      buffer.fits, buffer.start, buffer.storage, buffer.readable⟩,
    formed := formed.bindLocals bindings, destination := by core_local, value := by core_local }
  obtain ⟨finished, loopRun, output⟩ := runLoop context unique noViews
  have bodyRun : RunsStmt extractedProgram callee body
      (.returned (some (.signed .i32 (result buffer)))) (restoreLocals callee finished) := by
    apply RunsStmt.letLocal (.ofStable .value rfl)
    by_cases all : count buffer = 8
    · have fits : buffer.position + 8 < 2 ^ 31 := by
        have start := buffer.start; have bound := buffer.fits
        unfold count at all; omega
      core_facts [context, output]
      simp only [completion, show count context.buffer = count buffer by rfl, all, ↓reduceIte] at loopRun
      simp only [result, all, ↓reduceIte]
      core_stmt
    · simp only [completion, show count context.buffer = count buffer by rfl, all, ↓reduceIte] at loopRun
      simp only [result, all, ↓reduceIte]
      core_stmt
  refine ⟨restoreLocals state (restoreLocals callee finished),
    RunsExpr.call (values := [cursorValue buffer, .signed .i32 word.toInt])
      (by core_lookup) rfl (RunsExprs.values [cursorValue buffer, .signed .i32 word.toInt]) rfl bodyRun,
    ?_, ?_, output.world, output.views⟩
  · change Memory.BytesWrite callee.heap finished.heap (context.buffer.address + context.buffer.position)
      ((bytes word).take (count context.buffer))
    simpa only [List.flatMap_singleton'] using output.written
  · exact ((FreshCellFrame.bindLocals { state with locals := [] } bindings).trans
    output.cells).restoreLocals

#print axioms actualCall_formats

example : bytes (19088743 : BitVec 32) = [48, 49, 50, 51, 52, 53, 54, 55] := by decide
example : bytes (-1 : BitVec 32) = [102, 102, 102, 102, 102, 102, 102, 102] := by decide

-- All nine capacity boundaries instantiate the general contract, with an
-- unaligned cursor and a caller variable shadowed by a function parameter.
private def sample : State :=
  ({ heap := { blocks := [
      { base := 4, size := 12, alignment := 4,
        bytes := [255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255] }], nextAddress := 16 } } : State).bindLocal destinationId (.boolean false)
private def sampleBuffer (capacity : Fin 9) : Buffer sample := {
  address := 4, words := 3, capacity := capacity.val + 1, position := 1,
  fits := by omega, start := by omega, storage := by omega,
  readable := Memory.Heap.Readable.of_loadBytes (by rfl) }

example (capacity : Fin 9) :
    ∃ after, RunsExpr extractedProgram sample (hexCall (sampleBuffer capacity) 19088743)
        (.signed .i32 (if capacity.val = 8 then 9 else -1)) after ∧
      Memory.BytesWrite sample.heap after.heap 5
        ([48, 49, 50, 51, 52, 53, 54, 55].take capacity.val) ∧
      after.local? destinationId = some (.boolean false) := by
  have countEq : count (sampleBuffer capacity) = capacity.val := by
    dsimp only [count, sampleBuffer]; omega
  obtain ⟨after, run, effect, cells, _, _⟩ := actualCall_formats (sampleBuffer capacity) 19088743
    (by simp [State.CellsWellFormed, sample, State.bindLocal, State.bindCell]) rfl
    (by simp [Memory.HeapBlockBasesUnique, sample, State.bindLocal, State.bindCell])
  refine ⟨after, ?_, ?_, cells.localFound run.choose_spec.2 destinationId _ rfl⟩
  · rw [result, countEq] at run
    exact run
  · rw [countEq] at effect
    simpa only [sampleBuffer, show bytes (19088743 : BitVec 32) =
      [48, 49, 50, 51, 52, 53, 54, 55] by decide] using effect

example (word : BitVec 32) : ∃ after, RunsExpr extractedProgram {}
    (hexCall (state := {}) ⟨0, 0, 0, 0, by decide, by decide, by decide, by intro index bound; omega⟩ word)
    (.signed .i32 (-1)) after ∧ Memory.BytesWrite ({} : State).heap after.heap 0 [] := by
  obtain ⟨after, run, effect, _⟩ := actualCall_formats
    (state := {}) ⟨0, 0, 0, 0, by decide, by decide, by decide, by intro index bound; omega⟩ word
    (by simp [State.CellsWellFormed]) rfl (by simp [Memory.HeapBlockBasesUnique])
  exact ⟨after, run, effect⟩

end OutputHexWordProof
