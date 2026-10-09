import direct_output_byte
import direct_packed_words
import Lanius.Extraction.OutputPacking.Read
import Lanius.Semantics.LoopRun
import Lanius.Semantics.RawSlice
import Lanius.Semantics.CountedLocal
import Lanius.Core.Bindings
import Lanius.Extraction.OutputLoop

namespace OutputTextProof

open Lanius Lanius.Core Lanius.Semantics Lanius.Extraction Lanius.Extraction.OutputPacking

private def source := Extracted.«verified::lean_output».Functions.«text».core
private def outputId := source.argumentId 0
private def capacityId := source.argumentId 1
private def positionId := source.argumentId 2
private def inputId := source.argumentId 3
private def lengthId := source.argumentId 4
private def wordsId := source.bindingId 0
private def indexId := source.bindingId 1
private def valueId := source.bindingId 2

private def actualBody : Stmt :=
  Extracted.«verified::lean_output».Functions.«text».core.body.getD .skip

private def actualGuard : Expr :=
  match actualBody with
  | .sequence (.ifThenElse condition _ _) _ => condition
  | _ => .value (.boolean true)

def textCall (output : Value) (capacity position : Int) (input : String) (length : Int) : Expr :=
  .call Extracted.«verified::lean_output».Functions.«text».core.id
    ([output, .signed .i32 capacity, .signed .i32 position, .string input,
      .signed .i32 length].map Expr.value)

/-- Invalid ranges return before constructing or accessing either buffer.
    Even an invalid output pointer is permitted on this rejection path. -/
theorem actualCall_rejects (output : Value) (capacity position : Int) (input : String) (length : Int)
    (formed : state.CellsWellFormed) (fits : capacity < 2 ^ 31)
    (bad : length < 0 ∨ position < 0 ∨ position > capacity ∨ length > capacity - position) :
    ∃ after, RunsExpr extractedProgram state (textCall output capacity position input length)
      (.signed .i32 (-1)) after ∧ PureFrame state after := by
  let bindings : List (VarId × Value) := [(outputId, output), (capacityId, .signed .i32 capacity),
    (positionId, .signed .i32 position), (inputId, .string input), (lengthId, .signed .i32 length)]
  let callee := ({ state with locals := [] }).bindLocals bindings
  have calleeFormed : callee.CellsWellFormed := formed.bindLocals bindings
  apply RunsExpr.callUnchanged (bindings := bindings)
    (values := [output, .signed .i32 capacity, .signed .i32 position, .string input, .signed .i32 length])
    (by core_lookup) rfl rfl formed
  have guardRun : StableExpr 5 extractedProgram callee actualGuard (.boolean true) callee := by
    by_cases early : length < 0 ∨ position < 0 ∨ position > capacity
    · apply StableExpr.weaken
      · apply StableExpr.logicalOrTrue
        core_guard_step
      · decide
    · have subtraction := eval_i32_subNonneg extractedProgram.target capacity position (by omega) (by omega)
      core_guard
  core_stmt

#print axioms actualCall_rejects

-- An empty heap and zero-length raw descriptor need no validity proof when
-- the guard rejects. The skipped capacity subtraction would overflow i32.
example : ∃ after, RunsExpr extractedProgram {}
      (textCall (.rawSlice (.scalar (.signed .i32)) 0 0) (-2147483648) 2147483647 "" 1)
      (.signed .i32 (-1)) after ∧ PureFrame {} after :=
  actualCall_rejects _ _ _ _ _ (by simp [State.CellsWellFormed]) (by decide) (by decide)

private def loop? : Stmt → Option (Expr × Stmt)
  | .sequence first second => loop? first <|> loop? second
  | .letLocal _ _ _ body => loop? body
  | .whileLoop condition body => some (condition, body)
  | _ => none

private def actualLoop : Expr × Stmt :=
  (loop? actualBody).getD
    (.value (.boolean true), .skip)

private def actualRead : Expr :=
  match actualLoop.2 with
  | .letLocal _ _ expression _ => expression
  | _ => .value .unit

/-- The actual text loop reads the selected byte from packed input, including
    sign-bit lanes. This is a read contract, not yet the whole text call. -/
theorem actualRead_byte (word : BitVec 32) (index : Nat)
    (representable : index < 2 ^ 31) (inside : index / 4 < words)
    (source : state.local? wordsId = some (.rawSlice (.scalar (.signed .i32)) address words))
    (position : state.local? indexId = some (.signed .i32 index))
    (contents : state.heap.loadBytes (address + index / 4 * 4) 4 = .ok (i32Bytes word.toInt)) :
    StableExpr 5 extractedProgram state actualRead
      (.signed .i32 (byteAt word ⟨index % 4, Nat.mod_lt _ (by decide)⟩).toNat) state := by
  apply readByteExpression (readFuel := 3) (shiftFuel := 3) (maskFuel := 1)
    word ⟨index % 4, Nat.mod_lt _ (by decide)⟩ rfl
  · apply StableExpr.rawSliceRead (sourceFuel := 1) (indexFuel := 2) (position := index / 4)
    · core_expr
    · core_expr
    · exact readRawSliceIndex_i32Bytes extractedProgram state inside contents
  · core_expr
  · core_expr

#print axioms actualRead_byte

private structure Context (base : State) where
  address : Nat
  words : Nat
  capacity : Nat
  position : Nat
  inputAddress : Nat
  inputWords : Nat
  capacityFits : capacity < 2 ^ 31
  storage : capacity ≤ words * 4
  output : base.local? outputId = some (.rawSlice (.scalar (.signed .i32)) address words)
  limit : base.local? capacityId = some (.signed .i32 capacity)
  start : base.local? positionId = some (.signed .i32 position)
  input : base.local? wordsId = some (.rawSlice (.scalar (.signed .i32)) inputAddress inputWords)
  formed : base.CellsWellFormed

private def actualCall : Expr :=
  match actualLoop.2 with
  | .letLocal _ _ _ (.sequence (.expression call) _) => call
  | _ => .value .unit

private theorem iteration {inputWord : BitVec 32} {index : Nat}
    (context : Context base) (frame : CountedLocal base state indexId index)
    (available : context.position + index < context.capacity)
    (sourceBound : index / 4 < context.inputWords)
    (sourceWord : state.heap.loadBytes (context.inputAddress + index / 4 * 4) 4 =
      .ok (i32Bytes inputWord.toInt))
    (outputReadable : state.heap.Readable (context.address + (context.position + index) / 4 * 4) 4)
    (noViews : state.i32ArrayViews = []) (unique : Memory.HeapBlockBasesUnique state.heap) :
    ∃ after, RunsStmt extractedProgram state actualLoop.2 .next after ∧
      Memory.ByteWrite state.heap after.heap (context.address + (context.position + index))
        (UInt8.ofBitVec (byteAt inputWord ⟨index % 4, Nat.mod_lt _ (by decide)⟩)) ∧
      CountedLocal base after indexId (index + 1 : Nat) ∧ after.world = state.world ∧
      after.i32ArrayViews = state.i32ArrayViews := by
  core_facts [context, frame]
  have indexFits : index + 1 < 2 ^ 31 := by omega
  let byte := byteAt inputWord ⟨index % 4, Nat.mod_lt _ (by decide)⟩
  let ready := state.bindLocal valueId (.signed .i32 byte.toNat)
  have readRun := actualRead_byte inputWord index (by omega) sourceBound
    (by core_local) (by core_local) sourceWord
  obtain ⟨middle, call, effect, cells, world, views⟩ := OutputByteProof.actualCall_writes
    (state := ready)
    { address := context.address, words := context.words, capacity := context.capacity,
      cursor := context.position + index, capacityFits := context.capacityFits,
      available, storage := context.storage, readable := outputReadable }
    ⟨byte.toNat, byte.isLt⟩ (by core_formed) noViews unique
  have callRun : RunsExpr extractedProgram ready actualCall
      (.signed .i32 (context.position + index + 1 : Nat)) middle := by
    core_run
  obtain ⟨after, bodyRun, nextFrame, heap, nextWorld, nextViews⟩ :=
    CountedLocal.step (type := .scalar (.signed .i32)) frame context.formed (by decide)
      indexFits (.ofStable readRun rfl) callRun cells
  refine ⟨after, bodyRun, ?_, nextFrame, ?_, ?_⟩
  · simpa only [heap, ready, State.bindLocal, State.bindCell, UInt8.ofNat, UInt8.ofBitVec,
      BitVec.ofNat_toNat, BitVec.setWidth_eq] using effect
  · exact nextWorld.trans world
  · exact nextViews.trans views

private def CopyState (context : Context base) (bytes : List UInt8) (state : State) (index : Nat) :=
  OutputState base state indexId index context.address context.position context.words bytes (fun byte => [byte])

/-- Total correctness of the actual copying loop, from prepared raw buffers.
    String-view allocation and the outer entry guard are separate obligations. -/
private theorem copyLoop (context : Context base) (bytes : List UInt8)
    (lengthLocal : base.local? lengthId = some (.signed .i32 bytes.length))
    (space : context.position + bytes.length ≤ context.capacity)
    (sourceSize : bytes.length ≤ context.inputWords * 4)
    (separate : context.address + context.words * 4 ≤ context.inputAddress ∨
      context.inputAddress + context.inputWords * 4 ≤ context.address)
    (outputReadable : base.heap.Readable context.address (context.words * 4))
    (inputReadable : base.heap.Readable context.inputAddress (context.inputWords * 4))
    (inputBytes : base.heap.loadBytes context.inputAddress bytes.length = .ok bytes)
    (noViews : base.i32ArrayViews = []) (unique : Memory.HeapBlockBasesUnique base.heap) :
    ∃ after, RunsStmt extractedProgram (base.bindLocal indexId (.signed .i32 0))
      (.whileLoop actualLoop.1 actualLoop.2) .next after ∧ CopyState context bytes after bytes.length := by
  apply OutputState.run (limit := bytes.length) (position := context.position)
    (items := bytes) (encode := fun byte => [byte])
    (OutputState.start context.formed outputReadable unique)
  · intro state current
    core_facts [context, current]
    exact ⟨state, .whileFalse (by core_run), current⟩
  · intro index state inside current
    have available : context.position + index < context.capacity := by omega
    have sourceBound : index / 4 < context.inputWords := by omega
    have outputSize := context.storage
    obtain ⟨inputWord, sourceWord⟩ := readableWord
      ((current.written.readable inputReadable).subrange
        (start := index / 4 * 4) (length := 4) (by omega))
    have outputWord := current.readable.subrange
      (start := (context.position + index) / 4 * 4) (length := 4) (by omega)
    obtain ⟨after, bodyRun, effect, frame, world, views⟩ := iteration context current.toCountedLocal
      available sourceBound sourceWord outputWord (current.views.trans noViews) current.written.unique
    have selected := Memory.Heap.loadBytes_get sourceWord
      (i32Bytes_at inputWord ⟨index % 4, Nat.mod_lt _ (by decide)⟩)
    have selectedAt := Memory.Heap.loadByte_alias selected
      (show context.inputAddress + index = context.inputAddress + index / 4 * 4 + index % 4 by omega)
    have preserved := current.written.loadBytes_disjoint inputBytes (by
      simp only [List.flatMap_singleton']
      dsimp only [Lanius.Address] at *
      have prefixLength : (bytes.take index).length ≤ bytes.length := by
        simp only [List.length_take]; omega
      rcases separate with left | right
      · exact Or.inl (by omega)
      · exact Or.inr (by omega))
    have original := Memory.Heap.loadBytes_get preserved (List.getElem?_eq_getElem inside)
    have byteEq := Except.ok.inj (selectedAt.symm.trans original)
    have wrote : Memory.ByteWrite state.heap after.heap
        (context.address + context.position + index) bytes[index] := by
      simpa only [Nat.add_assoc, byteEq] using effect
    core_facts [context, current]
    exact ⟨after, by core_run, bodyRun,
      current.advance inside (by
        simpa only [List.flatMap_singleton', List.length_take, Nat.min_eq_left (Nat.le_of_lt inside)]
          using wrote.asBytes) frame world views⟩

#print axioms copyLoop

/-- The public copying domain: readable packed output and enough byte space.
    No string allocation, raw-slice construction, or loop success is assumed. -/
structure TextBuffer (state : State) (input : String) where
  address : Nat
  words : Nat
  capacity : Nat
  position : Nat
  capacityFits : capacity < 2 ^ 31
  space : position + (World.utf8Bytes input).length ≤ capacity
  storage : capacity ≤ words * 4
  readable : state.heap.Readable address (words * 4)

/-- Total correctness of the actual public `text` call, including its string
    storage, packed-word calculation, raw descriptor, copying loop and return.
    The heap gains fresh borrowed string storage; only the output bytes change
    in that extended heap, and the caller's cells/world/views are framed. -/
theorem actualCall_copies (buffer : TextBuffer state input)
    (formed : state.CellsWellFormed) (noViews : state.i32ArrayViews = [])
    (below : Memory.HeapBlocksBelowNext state.heap)
    (unique : Memory.HeapBlockBasesUnique state.heap) :
    ∃ after, RunsExpr extractedProgram state
        (textCall (.rawSlice (.scalar (.signed .i32)) buffer.address buffer.words)
          buffer.capacity buffer.position input (World.utf8Bytes input).length)
        (.signed .i32 (buffer.position + (World.utf8Bytes input).length : Nat)) after ∧
      Memory.BytesWrite (state.heap.borrowedI32 (stringStorage input)) after.heap
        (buffer.address + buffer.position) (World.utf8Bytes input) ∧
      FreshCellFrame state after ∧ after.world = state.world ∧
      after.i32ArrayViews = state.i32ArrayViews := by
  let bytes := World.utf8Bytes input
  let count := bytes.length
  let words := (count + 3) / 4
  let output := Value.rawSlice (.scalar (.signed .i32)) buffer.address buffer.words
  let bindings : List (VarId × Value) := [(outputId, output), (capacityId, .signed .i32 buffer.capacity),
    (positionId, .signed .i32 buffer.position), (inputId, .string input), (lengthId, .signed .i32 count)]
  let callee := ({ state with locals := [] }).bindLocals bindings
  have calleeFormed : callee.CellsWellFormed := formed.bindLocals bindings
  have capacityFits := buffer.capacityFits
  have space : buffer.position + count ≤ buffer.capacity := buffer.space
  have countFits : count < 2 ^ 31 := by omega
  let mapped := { callee with heap := callee.heap.borrowedI32 (stringStorage input) }
  have pointerRun : RunsExpr extractedProgram callee (.stringDataPtr (.local inputId))
      (.pointer state.heap.borrowedAddress) mapped :=
    RunsExpr.stringDataPtr (value := input) (after := callee) (by core_run)
  obtain ⟨packed, packing, packingFrame⟩ := PackedWordsProof.actualCall
    (state := mapped) (count : Int) (by omega) calleeFormed
  have packingRun : RunsExpr extractedProgram mapped
      (.call Extracted.«verified::host».Functions.«packed_words».core.id [.local lengthId])
      (.signed .i32 words) packed := by
    simp only [PackedWordsProof.packedCall, if_neg (by omega : ¬ (count : Int) < 0),
      Int.toNat_natCast] at packing
    core_run
  have packedHeap : packed.heap = state.heap.borrowedI32 (stringStorage input) := packingFrame.heap
  have constructed : mapRawI32Slice packed state.heap.borrowedAddress (words : Int) =
      .done (.rawSlice (.scalar (.signed .i32)) state.heap.borrowedAddress words) packed :=
    mapRawI32Slice_stringStorage packedHeap below unique
  have initializer := RunsExpr.rawSliceFromParts pointerRun packingRun constructed rfl
  let base := packed.bindLocal wordsId
    (.rawSlice (.scalar (.signed .i32)) state.heap.borrowedAddress words)
  have packedFormed := packingFrame.afterFormed
  let context : Context base := {
    address := buffer.address, words := buffer.words, capacity := buffer.capacity,
    position := buffer.position, inputAddress := state.heap.borrowedAddress, inputWords := words,
    capacityFits, storage := buffer.storage, output := by core_local,
    limit := by core_local, start := by core_local, input := by core_local,
    formed := packedFormed.bindLocal _ _ }
  have baseHeap : base.heap = state.heap.borrowedI32 (stringStorage input) := packedHeap
  have outputReadable : base.heap.Readable buffer.address (buffer.words * 4) := by
    rw [baseHeap]
    intro index bound
    obtain ⟨byte, read⟩ := buffer.readable index bound
    exact ⟨byte, Memory.Heap.borrowedI32_oldRead read⟩
  have inputAll : base.heap.loadBytes state.heap.borrowedAddress (words * 4) =
      .ok (stringStorage input) := by
    rw [baseHeap]
    have full :=
      Memory.Heap.borrowedI32_loadBytes below (stringStorage input) (stringStorage input).length
    rw [List.take_length] at full
    simpa only [stringStorage_length, words, count, bytes] using full
  have inputBytes : base.heap.loadBytes state.heap.borrowedAddress count = .ok bytes := by
    rw [baseHeap]
    simpa only [count, bytes, stringStorage_content] using
      Memory.Heap.borrowedI32_loadBytes below (stringStorage input) count
  have separate : buffer.address + buffer.words * 4 ≤ state.heap.borrowedAddress ∨
      state.heap.borrowedAddress + words * 4 ≤ buffer.address := by
    by_cases empty : buffer.words * 4 = 0
    · have lengthZero : count = 0 := by have := buffer.storage; omega
      have wordZero : words = 0 := by simp [words, lengthZero]
      simpa only [empty, wordZero, Nat.zero_mul, Nat.add_zero] using
        (Nat.le_total buffer.address state.heap.borrowedAddress)
    · exact Or.inl (Nat.le_trans (buffer.readable.belowNext (Nat.pos_of_ne_zero empty) below)
        state.heap.borrowedAddress_ge)
  obtain ⟨finished, loopRun, copied⟩ := copyLoop context bytes (by core_local)
    space (by change bytes.length ≤ words * 4; dsimp only [words, count]; omega)
    separate outputReadable (Memory.Heap.Readable.of_loadBytes inputAll)
    inputBytes (packingFrame.views.trans noViews) (by
      rw [baseHeap]
      exact Memory.Heap.borrowedI32_unique below unique)
  core_facts [context, copied]
  have returnRun : RunsExpr extractedProgram finished (.binary .add (.local positionId) (.local lengthId))
      (.signed .i32 (buffer.position + count : Nat)) finished := by
    exact .ofStable (StableExpr.binary (leftFuel := 1) (rightFuel := 1)
      (by core_expr) (by core_expr) (by decide)
      (eval_i32_addNat _ buffer.position count (by omega))) rfl
  let completed := restoreLocals packed (restoreLocals base finished)
  have guardRun : StableExpr 5 extractedProgram callee actualGuard (.boolean false) callee := by
    core_guard
  have bodyRun : RunsStmt extractedProgram callee actualBody
      (.returned (some (.signed .i32 (buffer.position + count : Nat)))) completed := by
    apply RunsStmt.sequenceNext
    · core_stmt
    · apply RunsStmt.letLocal
      · exact initializer
      · apply RunsStmt.letLocal
        · core_run
        · core_stmt
  have callRun := RunsExpr.call (program := extractedProgram)
    (functionId := Extracted.«verified::lean_output».Functions.«text».core.id)
    («function» := Extracted.«verified::lean_output».Functions.«text».core)
    (by core_lookup) rfl (RunsExprs.values
    [output, .signed .i32 buffer.capacity, .signed .i32 buffer.position,
      .string input, .signed .i32 count]) (show bindParameters
        Extracted.«verified::lean_output».Functions.«text».core.parameters _ = some bindings from rfl) bodyRun
  have calleeCells : FreshCellFrame state callee := FreshCellFrame.bindLocals state bindings
  have mappedCells : FreshCellFrame callee mapped := by exact ⟨[], by simp [mapped], Nat.le_refl _, by simp⟩
  have allCells := (((calleeCells.trans mappedCells).trans packingFrame.cells).trans
    (FreshCellFrame.bindLocal packed wordsId _)).trans copied.cells
  refine ⟨restoreLocals state completed, callRun, ?_, ?_, ?_, ?_⟩
  · simpa only [restoreLocals, completed, ← baseHeap, List.take_length, List.flatMap_singleton'] using copied.written
  · exact allCells.restoreLocals
  · exact copied.world.trans packingFrame.world
  · exact copied.views.trans packingFrame.views

#print axioms actualCall_copies

-- The public domain is inhabited: nonzero preexisting output, an unaligned
-- cursor, multiple packed words, UTF-8/NUL, and a neighboring canary.
private def sample : State :=
  ({ heap := { blocks := [
      { base := 4, size := 12, alignment := 4, bytes := [11, 22, 33, 44, 55, 66, 77, 88, 99, 11, 22, 33] },
      { base := 32, size := 8, alignment := 4, bytes := [65, 0, 195, 169, 90, 0, 0, 0] }], nextAddress := 41 } } : State).bindLocals
    [(outputId, .rawSlice (.scalar (.signed .i32)) 4 3), (capacityId, .signed .i32 12),
      (positionId, .signed .i32 3), (wordsId, .rawSlice (.scalar (.signed .i32)) 32 2), (lengthId, .signed .i32 5)]

example : ∃ after, RunsExpr extractedProgram sample
      (textCall (.rawSlice (.scalar (.signed .i32)) 4 3) 12 3 "A\x00éZ" 5) (.signed .i32 8) after ∧
    after.heap.loadByte 4 3 = .ok 65 ∧ after.heap.loadByte 4 7 = .ok 90 ∧
    after.heap.loadByte 4 0 = .ok 11 ∧ after.heap.loadByte 4 8 = .ok 99 ∧
    after.heap.loadByte 32 3 = .ok 169 ∧
    after.local? wordsId = some (.rawSlice (.scalar (.signed .i32)) 32 2) := by
  obtain ⟨after, run, effect, cells, _, _⟩ := actualCall_copies (state := sample) (input := "A\x00éZ")
    { address := 4, words := 3, capacity := 12, position := 3,
      capacityFits := by decide, space := by decide, storage := by decide,
      readable := Memory.Heap.Readable.of_loadBytes (by rfl) }
    (by simp [State.CellsWellFormed, sample, State.bindLocals, State.bindLocal, State.bindCell])
    rfl (by simp [Memory.HeapBlocksBelowNext, sample, State.bindLocals, State.bindLocal, State.bindCell])
    (by simp [Memory.HeapBlockBasesUnique, sample, State.bindLocals, State.bindLocal, State.bindCell])
  refine ⟨after, run, ?_, ?_, ?_, ?_, ?_, cells.localFound run.choose_spec.2 wordsId _ rfl⟩
  all_goals rw [effect.reads]
  · rfl
  · rfl
  · exact Memory.Heap.borrowedI32_oldRead (bytes := stringStorage "A\x00éZ")
      (show sample.heap.loadByte 4 0 = .ok 11 from rfl)
  · exact Memory.Heap.borrowedI32_oldRead (bytes := stringStorage "A\x00éZ")
      (show sample.heap.loadByte 4 8 = .ok 99 from rfl)
  · exact Memory.Heap.borrowedI32_oldRead (bytes := stringStorage "A\x00éZ")
      (show sample.heap.loadByte 32 3 = .ok 169 from rfl)

-- Empty input still executes the public setup and return. No output storage
-- is accessed, and the original caller cells remain well formed.
example : ∃ after, RunsExpr extractedProgram {}
      (textCall (.rawSlice (.scalar (.signed .i32)) 0 0) 0 0 "" 0) (.signed .i32 0) after ∧
    after.CellsWellFormed := by
  obtain ⟨after, run, _, cells, _, _⟩ := actualCall_copies (state := {}) (input := "")
    { address := 0, words := 0, capacity := 0, position := 0,
      capacityFits := by decide, space := by decide, storage := by decide, readable := by
        intro index bound; omega }
    (by simp [State.CellsWellFormed]) rfl (by simp [Memory.HeapBlocksBelowNext])
    (by simp [Memory.HeapBlockBasesUnique])
  exact ⟨after, run, cells.after_cellsWellFormed (by simp [State.CellsWellFormed])⟩

end OutputTextProof
