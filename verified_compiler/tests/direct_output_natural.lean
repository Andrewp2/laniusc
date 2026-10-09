import GeneratedDirectCore
import Lanius.Semantics.CallProof
import Lanius.Core.Bindings
import direct_output_byte
import Lanius.Semantics.ScalarAssignment
import Lanius.Semantics.LocalPair
import Lanius.Semantics.LoopRun

namespace OutputNaturalProof

open Lanius Lanius.Core Lanius.Semantics

def naturalCall (output : Value) (capacity position value : Int) : Expr :=
  .call Extracted.«verified::lean_output».Functions.«natural».core.id
    ([output, .signed .i32 capacity, .signed .i32 position, .signed .i32 value].map Expr.value)

def decimalWidth (value : Nat) : Nat :=
  if value < 10 then 1 else if value < 100 then 2 else if value < 1000 then 3
  else if value < 10000 then 4 else if value < 100000 then 5
  else if value < 1000000 then 6 else if value < 10000000 then 7
  else if value < 100000000 then 8 else if value < 1000000000 then 9 else 10

/-- Width is the minimal decimal width, including the one digit needed for zero. -/
theorem decimalWidth_spec (value : Nat) (fits : value < 2 ^ 31) :
    1 ≤ decimalWidth value ∧ decimalWidth value ≤ 10 ∧
      (value = 0 ∨ 10 ^ (decimalWidth value - 1) ≤ value) ∧
      value < 10 ^ decimalWidth value := by
  unfold decimalWidth
  repeat' split
  all_goals simp only [Nat.reduceSub, Nat.reducePow] <;> omega

def widthCall (value : Nat) : Expr :=
  .call Extracted.«verified::lean_output».Functions.«decimal_width».core.id
    [.value (.signed .i32 value)]

theorem actualWidth (value : Nat) (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state (widthCall value)
      (.signed .i32 (decimalWidth value)) after ∧ PureFrame state after := by
  core_call Extracted.«verified::lean_output».Functions.«decimal_width».core
  unfold decimalWidth
  repeat' split
  all_goals core_stmt

/-- Invalid inputs reject before width calculation or any output access.
    Storage validity and successful internal execution are not premises. -/
theorem actualCall_rejects (output : Value) (capacity position value : Int)
    (formed : state.CellsWellFormed)
    (bad : value < 0 ∨ position < 0 ∨ capacity < position) :
    ∃ after, RunsExpr extractedProgram state (naturalCall output capacity position value)
      (.signed .i32 (-1)) after ∧ PureFrame state after := by
  core_call Extracted.«verified::lean_output».Functions.«natural».core
  core_stmt

private def source := Extracted.«verified::lean_output».Functions.«natural».core
private def sized : Expr × Stmt := match source.body.getD .skip with
  | .sequence _ (.letLocal _ _ initializer body) => (initializer, body)
  | _ => (.value .unit, .skip)

/-- Too little space rejects before accessing storage, even after the width
    helper and a temporary local have allocated fresh cells. -/
theorem actualCall_noSpace (output : Value) (capacity position value : Nat)
    (formed : state.CellsWellFormed) (fits : capacity < 2 ^ 31)
    (start : position ≤ capacity) (short : capacity - position < decimalWidth value) :
    ∃ after, RunsExpr extractedProgram state (naturalCall output capacity position value)
      (.signed .i32 (-1)) after ∧ PureFrame state after := by
  core_call_pure source as callee
  obtain ⟨ready, widthRun, pure⟩ := actualWidth (state := callee) value (by core_formed)
  have initial : RunsExpr extractedProgram callee sized.1
      (.signed .i32 (decimalWidth value)) ready := by core_run
  obtain ⟨after, bodyRun, frame⟩ := RunsStmt.letLocalPure
    (id := source.bindingId 0) (type := .scalar (.signed .i32)) initial pure
    (body := sized.2) (completion := .returned (some (.signed .i32 (-1))))
    (by core_facts [pure]; core_stmt) (PureFrame.refl (pure.afterFormed.bindLocal _ _))
  refine ⟨after, ?_, frame⟩
  apply RunsStmt.sequenceNext (second := bodyRun)
  core_stmt

private def remainingId := source.bindingId 1
private def indexId := source.bindingId 2
private def loop : Expr × Stmt := match sized.2 with
  | .sequence _ (.letLocal _ _ _ (.letLocal _ _ _ (.sequence (.whileLoop guard body) _))) => (guard, body)
  | _ => (.value (.boolean true), .skip)
private def parts : Expr × Stmt × Expr := match loop.2 with
  | .sequence (.expression decrement) (.sequence branch (.sequence (.expression quotient) _)) =>
      (decrement, branch, quotient)
  | _ => (.value .unit, .skip, .value .unit)
private def write : Expr := match parts.2.1 with
  | .ifThenElse (.binary .less call _) _ _ => call
  | _ => .value .unit
private def quotient : Expr := match parts.2.2 with
  | .assign _ _ right => right
  | _ => .value .unit

structure Buffer (state : State) where
  address : Nat
  words : Nat
  capacity : Nat
  position : Nat
  fits : capacity < 2 ^ 31
  storage : capacity ≤ words * 4
  readable : state.heap.Readable address (words * 4)

private structure Context (base : State) extends Buffer base where
  formed : base.CellsWellFormed
  output : base.local? (source.argumentId 0) = some (.rawSlice (.scalar (.signed .i32)) address words)
  capacityFound : base.local? (source.argumentId 1) = some (.signed .i32 capacity)
  positionFound : base.local? (source.argumentId 2) = some (.signed .i32 position)

/-- One actual iteration derives decrement, store, and quotient assignment.
    No intermediate execution or successful store is a caller premise. -/
private theorem iteration {number left : Nat} (context : Context base)
    (pair : LocalPair base before remainingId indexId
      (.signed .i32 number) (.signed .i32 (context.position + left + 1 : Nat)))
    (numberFits : number < 2 ^ 31) (space : context.position + left < context.capacity)
    (readable : before.heap.Readable context.address (context.words * 4))
    (noViews : before.i32ArrayViews = []) (unique : Memory.HeapBlockBasesUnique before.heap) :
    ∃ after, RunsStmt extractedProgram before loop.2 .next after ∧
      LocalPair base after remainingId indexId
        (.signed .i32 (number / 10 : Nat)) (.signed .i32 (context.position + left : Nat)) ∧
      Memory.ByteWrite before.heap after.heap (context.address + context.position + left)
        (UInt8.ofNat (48 + number % 10)) ∧
      after.world = before.world ∧ after.i32ArrayViews = before.i32ArrayViews := by
  core_facts [context, pair]
  obtain ⟨lowered, decrement, assigned, decrementEffect⟩ := RunsExpr.assignI32
    (program := extractedProgram) (op := .subtract) (replacement := (context.position + left : Nat))
    pair.secondCell pair.second
    (.ofStable (StableExpr.value (value := .signed .i32 1)) rfl) (by
      simpa [evalAssignValue, assignOpBinary?, Nat.add_assoc] using
        eval_i32_subNat extractedProgram.target (context.position + left + 1) 1 (by omega) (by omega))
  have lowerPair := pair.assignSecond context.formed assigned
  let digit : Fin 256 := ⟨48 + number % 10, by have := Nat.mod_lt number (by decide : 0 < 10); omega⟩
  obtain ⟨written, byteRun, byteEffect, byteCells, byteWorld, byteViews⟩ := OutputByteProof.actualCall_writes
    { address := context.address, words := context.words, capacity := context.capacity,
      cursor := context.position + left, capacityFits := context.fits, available := space,
      storage := context.storage, readable := by
        rw [decrementEffect.heap]
        exact readable.subrange (by have storage := context.storage; omega) }
    digit (lowerPair.cells.after_cellsWellFormed context.formed)
    (decrementEffect.views.trans noViews) (by simpa only [decrementEffect.heap] using unique)
  have writeRun : RunsExpr extractedProgram lowered write
      (.signed .i32 (context.position + left + 1 : Nat)) written := by
    core_facts [context, lowerPair]
    simp only [OutputByteProof.byteCall, List.map_cons, List.map_nil] at byteRun
    core_run
  have writtenPair := lowerPair.transCells byteCells byteRun.choose_spec.2
  obtain ⟨after, quotientRun, quotientAssigned, quotientEffect⟩ := RunsExpr.assignI32
    (program := extractedProgram) (op := .set) writtenPair.firstCell writtenPair.first
    (show RunsExpr extractedProgram written quotient (.signed .i32 (number / 10 : Nat)) written from by
      core_facts [context, writtenPair]; core_run) rfl
  refine ⟨after, ?_, writtenPair.assignFirst context.formed quotientAssigned, ?_,
    quotientEffect.world.trans (byteWorld.trans decrementEffect.world),
    quotientEffect.views.trans (byteViews.trans decrementEffect.views)⟩
  · core_stmt
  · simpa only [quotientEffect.heap, decrementEffect.heap, Nat.add_assoc] using byteEffect

/-- Big-endian positional decimal digits, specified independently of the loop. -/
def bytes (count value : Nat) : List UInt8 :=
  List.ofFn fun index : Fin count => UInt8.ofNat (48 + value / 10 ^ (count - index.val - 1) % 10)

@[simp] theorem bytes_length : (bytes count value).length = count := List.length_ofFn

private theorem bytes_step : bytes (count + 1) value =
    bytes count (value / 10) ++ [UInt8.ofNat (48 + value % 10)] := by
  unfold bytes
  rw [List.ofFn_succ_last]
  simp only [Fin.val_last, Nat.add_sub_cancel_left, Nat.sub_self, Nat.pow_zero, Nat.div_one]
  congr 1
  apply congrArg List.ofFn
  funext index
  simp only [Fin.val_castSucc]
  rw [show count + 1 - index.val - 1 = (count - index.val - 1) + 1 by omega,
    Nat.pow_succ', ← Nat.div_div_eq_div_mul]

private theorem runLoop (context : Context base) (value count : Nat)
    (fits : value < 2 ^ 31) (space : context.position + count ≤ context.capacity)
    (noViews : base.i32ArrayViews = []) (unique : Memory.HeapBlockBasesUnique base.heap) :
    ∃ after, RunsStmt extractedProgram
        ((base.bindLocal remainingId (.signed .i32 value)).bindLocal indexId
          (.signed .i32 (context.position + count : Nat)))
        (.whileLoop loop.1 loop.2) .next after ∧
      Memory.BytesWrite base.heap after.heap (context.address + context.position) (bytes count value) ∧
      (∃ number : Nat, LocalPair base after remainingId indexId
        (.signed .i32 number) (.signed .i32 context.position)) ∧
      after.world = base.world ∧ after.i32ArrayViews = base.i32ArrayViews := by
  let invariant := fun left state => ∃ number suffix,
    LocalPair base state remainingId indexId (.signed .i32 (number : Nat))
      (.signed .i32 (context.position + left : Nat)) ∧
    number < 2 ^ 31 ∧ left ≤ count ∧ bytes count value = bytes left number ++ suffix ∧
    Memory.BytesWrite base.heap state.heap (context.address + context.position + left) suffix ∧
    state.heap.Readable context.address (context.words * 4) ∧
    state.world = base.world ∧ state.i32ArrayViews = base.i32ArrayViews
  apply RunsStmt.whileCount invariant
    (fun state => Memory.BytesWrite base.heap state.heap (context.address + context.position) (bytes count value) ∧
      (∃ number : Nat, LocalPair base state remainingId indexId
        (.signed .i32 number) (.signed .i32 context.position)) ∧
      state.world = base.world ∧ state.i32ArrayViews = base.i32ArrayViews)
  · intro state facts
    obtain ⟨number, suffix, pair, _, _, digits, written, _, world, views⟩ := facts
    simp only [show bytes 0 number = [] from rfl, List.nil_append] at digits
    refine ⟨state, ?_, by simpa only [digits, Nat.add_zero] using written, ⟨number, pair⟩, world, views⟩
    core_facts [context, pair]
    core_run
  · intro left state facts
    obtain ⟨number, suffix, pair, numberFits, smaller, digits, written, readable, world, views⟩ := facts
    obtain ⟨after, run, next, effect, nextWorld, nextViews⟩ := iteration context pair numberFits
      (by omega) readable (views.trans noViews) written.unique
    refine ⟨state, after, .next, ?_, run, Or.inl rfl, number / 10,
      UInt8.ofNat (48 + number % 10) :: suffix, next, ?_, by omega, ?_, ?_,
      effect.readable readable, nextWorld.trans world, nextViews.trans views⟩
    · core_facts [context, pair]; core_run
    · exact Nat.lt_of_le_of_lt (Nat.div_le_self _ _) numberFits
    · simpa only [bytes_step, List.append_assoc, List.singleton_append] using digits
    · exact Memory.BytesWrite.cons (by simpa only [Nat.add_assoc] using written) effect
  · exact ⟨value, [], LocalPair.start context.formed (by decide), fits, Nat.le_refl _,
      (List.append_nil _).symm, Memory.BytesWrite.refl unique, context.readable, rfl, rfl⟩

/-- The actual formatter terminates and writes exactly the minimal-width
    decimal representation. All reads outside that byte range are preserved. -/
theorem actualCall_formats (buffer : Buffer state) (value : Nat)
    (formed : state.CellsWellFormed) (fits : value < 2 ^ 31)
    (room : buffer.position + decimalWidth value ≤ buffer.capacity)
    (noViews : state.i32ArrayViews = []) (unique : Memory.HeapBlockBasesUnique state.heap) :
    ∃ after, RunsExpr extractedProgram state
        (naturalCall (.rawSlice (.scalar (.signed .i32)) buffer.address buffer.words)
          buffer.capacity buffer.position value)
        (.signed .i32 (buffer.position + decimalWidth value : Nat)) after ∧
      Memory.BytesWrite state.heap after.heap (buffer.address + buffer.position) (bytes (decimalWidth value) value) ∧
      FreshCellFrame state after ∧ after.world = state.world ∧ after.i32ArrayViews = state.i32ArrayViews := by
  let arguments : List Value := [.rawSlice (.scalar (.signed .i32)) buffer.address buffer.words,
    .signed .i32 buffer.capacity, .signed .i32 buffer.position, .signed .i32 value]
  let bindings := source.parameters.zip arguments |>.map fun (parameter, value) => (parameter.1, value)
  let callee := ({ state with locals := [] }).bindLocals bindings
  obtain ⟨ready, widthRun, pure⟩ := actualWidth (state := callee) value (formed.bindLocals bindings)
  let base := ready.bindLocal (source.bindingId 0) (.signed .i32 (decimalWidth value))
  let context : Context base := {
    toBuffer := { buffer with readable := by rw [show base.heap = state.heap from pure.heap]; exact buffer.readable },
    formed := pure.afterFormed.bindLocal _ _, output := by core_facts [pure]; core_local,
    capacityFound := by core_facts [pure]; core_local, positionFound := by core_facts [pure]; core_local }
  obtain ⟨finished, loopRun, output, ⟨remaining, finalPair⟩, world, views⟩ := runLoop context value (decimalWidth value)
    fits room ((show base.i32ArrayViews = state.i32ArrayViews from pure.views).trans noViews)
    (by rw [show base.heap = state.heap from pure.heap]; exact unique)
  have initial : RunsExpr extractedProgram callee sized.1 (.signed .i32 (decimalWidth value)) ready := by core_run
  have bodyRun : RunsStmt extractedProgram callee (source.body.getD .skip)
      (.returned (some (.signed .i32 (buffer.position + decimalWidth value : Nat))))
      (restoreLocals callee finished) := by
    have baseFormed := context.formed
    have capacityFound : base.local? (source.argumentId 1) = some (.signed .i32 buffer.capacity) := context.capacityFound
    have positionFound : base.local? (source.argumentId 2) = some (.signed .i32 buffer.position) := context.positionFound
    core_facts [buffer, pure, finalPair]
    apply RunsStmt.sequenceNext (middle := callee)
    · core_stmt
    have restored : restoreLocals ready finished = restoreLocals callee finished := by
      simp only [restoreLocals, pure.locals]
    rw [← restored]
    refine RunsStmt.letLocal (afterInit := ready) (afterBody := restoreLocals base finished) initial ?_
    apply RunsStmt.sequenceNext (middle := base)
    · core_stmt
    refine RunsStmt.letLocal
      (afterInit := base) (value := .signed .i32 value)
      (afterBody := restoreLocals (base.bindLocal remainingId (.signed .i32 value)) finished) ?_ ?_
    · core_run
    refine RunsStmt.letLocal (afterInit := base.bindLocal remainingId (.signed .i32 value))
      (value := .signed .i32 (buffer.position + decimalWidth value : Nat)) (afterBody := finished) ?_ ?_
    · core_run
    apply RunsStmt.sequenceNext loopRun
    core_stmt
  refine ⟨restoreLocals state (restoreLocals callee finished),
    RunsExpr.call (values := arguments) (by core_lookup) rfl (RunsExprs.values arguments) rfl bodyRun,
    ?_, ?_, ?_, ?_⟩
  · change Memory.BytesWrite state.heap finished.heap (buffer.address + buffer.position) (bytes (decimalWidth value) value)
    rw [← show base.heap = state.heap from pure.heap]
    exact output
  · exact ((FreshCellFrame.bindLocals { state with locals := [] } bindings).trans
      (pure.cells.trans ((FreshCellFrame.bindLocal ready _ _).trans finalPair.cells))).restoreLocals
  · exact world.trans pure.world
  · exact views.trans pure.views

#print axioms actualCall_rejects
#print axioms decimalWidth_spec
#print axioms actualWidth
#print axioms actualCall_noSpace
#print axioms iteration
#print axioms runLoop
#print axioms actualCall_formats

-- No allocation is needed even for a non-slice output argument.
example : ∃ after, RunsExpr extractedProgram {}
      (naturalCall .unit 0 0 (-1)) (.signed .i32 (-1)) after ∧ PureFrame {} after :=
  actualCall_rejects _ _ _ _ (by simp [State.CellsWellFormed]) (by decide)

example : ∃ after, RunsExpr extractedProgram {}
      (naturalCall (.rawSlice (.scalar (.signed .i32)) 0 0) 0 0 2147483647)
      (.signed .i32 (-1)) after ∧ PureFrame {} after :=
  actualCall_noSpace _ _ _ _ (by simp [State.CellsWellFormed]) (by decide) (by decide) (by decide)

example : bytes (decimalWidth 0) 0 = [48] := by decide
example : bytes (decimalWidth 2147483647) 2147483647 = [50, 49, 52, 55, 52, 56, 51, 54, 52, 55] := by decide

-- Every supported value fits this unaligned buffer. A shadowed caller local,
-- a neighboring byte, another allocation, and an invalid pointer are retained.
private def sample : State :=
  ({ heap := { blocks := [
      { base := 4, size := 12, alignment := 4, bytes := List.replicate 12 255 },
      { base := 20, size := 1, alignment := 1, bytes := [77] }], nextAddress := 21 } } : State).bindLocal
    (source.argumentId 0) (.signed .i32 91)

private def sampleBuffer : Buffer sample := {
  address := 4, words := 3, capacity := 12, position := 1,
  fits := by decide, storage := by decide,
  readable := Memory.Heap.Readable.of_loadBytes (bytes := List.replicate 12 255) rfl }

example (value : Fin (2 ^ 31)) : ∃ after,
    RunsExpr extractedProgram sample
      (naturalCall (.rawSlice (.scalar (.signed .i32)) 4 3) 12 1 value.val)
      (.signed .i32 (1 + decimalWidth value.val : Nat)) after ∧
    Memory.BytesWrite sample.heap after.heap 5 (bytes (decimalWidth value.val) value.val) ∧
    after.local? (source.argumentId 0) = some (.signed .i32 91) ∧
    after.heap.loadByte 4 0 = .ok 255 ∧ after.heap.loadByte 0 0 = .error .invalidPointer := by
  obtain ⟨after, run, written, cells, _⟩ := actualCall_formats sampleBuffer value.val
    (by simp [sample, State.CellsWellFormed, State.bindLocal, State.bindCell]) value.isLt
    (by have := (decimalWidth_spec value.val value.isLt).2.1; change 1 + decimalWidth value.val ≤ 12; omega)
    rfl (by simp [sample, Memory.HeapBlockBasesUnique, State.bindLocal, State.bindCell])
  exact ⟨after, run, written, cells.localFound run.choose_spec.2 _ _ rfl,
    by rw [written.reads]; rfl, by rw [written.reads]; rfl⟩

end OutputNaturalProof
