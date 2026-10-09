import Lanius.Extraction.WriterFrame
import Lanius.Semantics.MutableLocal
import Lanius.Semantics.ScalarAssignment
import Lanius.Semantics.ProofFacts
import Lanius.Semantics.NaturalArithmetic

namespace Lanius.Extraction

open Lanius.Core Lanius.Semantics

variable {base before current ready : State} {id oldId : VarId} {cell : CellId} {value : Value}
variable {scope : List (VarId × CellId)}
variable {control : VarId} {controlCell : CellId} {replacement : Value}

/-- A printer's fresh cursor cell and accumulated output. The frame is anchored
    before binding that cell, so updating it does not mutate caller cells. -/
structure WriterCursor (base current : State) (id : VarId) (cell : CellId) (address position : Nat)
    (bytes : List UInt8) (scope : List (VarId × CellId) := []) : Prop where
  frame : WriterFrame base current address bytes
  fresh : base.nextCell ≤ cell
  slot : current.cellId? id = some cell
  value : current.local? id = some (.signed .i32 (position + bytes.length : Nat))
  locals : current.locals = scope ++ (id, cell) :: base.locals

attribute [core_local_rule] WriterCursor.value

theorem WriterFrame.bindLocal (frame : WriterFrame base current address bytes)
    (id : VarId) (value : Value) : WriterFrame base (current.bindLocal id value) address bytes :=
  ⟨frame.output, frame.cells.trans (FreshCellFrame.bindLocal current id value), frame.world, frame.views⟩

theorem WriterCursor.start (frame : WriterFrame base current address bytes)
    (formed : base.CellsWellFormed) (locals : current.locals = base.locals) (id : VarId) :
    WriterCursor base (current.bindLocal id (.signed .i32 (position + bytes.length : Nat)))
      id current.nextCell address position bytes :=
  ⟨frame.bindLocal id _, frame.cells.choose_spec.2.1,
    State.bindLocal_cellId current id _, State.bindLocal_local? current (frame.afterFormed formed) id _,
    by simpa only [State.bindLocal, State.bindCell, List.nil_append] using congrArg ((id, current.nextCell) :: ·) locals⟩

/-- Start before any output is written, allocating only the fresh cursor. -/
theorem WriterCursor.begin {position address : Nat}
    (formed : base.CellsWellFormed) (unique : Memory.HeapBlockBasesUnique base.heap)
    (id : VarId) :
    WriterCursor base (base.bindLocal id (.signed .i32 (position : Nat))) id base.nextCell address position [] :=
  WriterCursor.start ⟨.write (Memory.BytesWrite.refl unique), (CallerFrame.refl formed).cells, rfl, rfl⟩ formed rfl id

@[core_local_rule] theorem WriterCursor.localFound
    (cursor : WriterCursor base current id cell address position bytes (scope := scope))
    (different : id ≠ oldId) (found : base.local? oldId = some value) :
    (scope.find? (fun binding => binding.1 == oldId)) = none → current.local? oldId = some value := by
  intro unshadowed
  exact cursor.frame.cells.localFoundAt
    (by simp [State.cellId?, cursor.locals, List.find?_append, unshadowed, different]) value found

/-- Reader calls retain the cursor and accumulated output while adding their
    own temporary cells. The explicit lexical prefix does not change. -/
theorem WriterCursor.afterPure
    (cursor : WriterCursor base before id cell address position bytes (scope := scope))
    (pure : PureFrame before ready) :
    WriterCursor base ready id cell address position bytes (scope := scope) :=
  ⟨⟨by simpa only [pure.heap] using cursor.frame.output,
      cursor.frame.cells.trans pure.cells, pure.world.trans cursor.frame.world,
      pure.views.trans cursor.frame.views⟩,
    cursor.fresh, by simpa only [State.cellId?, pure.locals] using cursor.slot,
    pure.localFound cursor.value, pure.locals.trans cursor.locals⟩

/-- Writing and reader calls retain every lexical slot while a cursor stays
    in the same scope. Control values may change; their cell IDs do not. -/
theorem WriterCursor.slotsEq
    (current : WriterCursor base after id cell address position bytes (scope := scope))
    (previous : WriterCursor base before id cell oldAddress oldPosition oldBytes (scope := scope)) :
    after.cellId? key = before.cellId? key := by
  simp only [State.cellId?, current.locals, previous.locals]

/-- Leaving a temporary scope changes only the lookup table. The caller must
    retain the same cursor cell; its current value and output stay checked. -/
theorem WriterCursor.restoreScope
    (cursor : WriterCursor base current id cell address position bytes (scope := inner))
    (locals : caller.locals = scope ++ (id, cell) :: base.locals)
    (slot : caller.cellId? id = some cell) :
    WriterCursor base (restoreLocals caller current) id cell address position bytes (scope := scope) := by
  refine ⟨cursor.frame.restoreLocals caller, cursor.fresh, slot, ?_, locals⟩
  change (caller.cellId? id).bind current.cell? = _
  simpa only [State.local?, cursor.slot, slot] using cursor.value

/-- A fresh read-only index local can sit above the mutable output cursor. -/
theorem WriterCursor.bindLocal
    (cursor : WriterCursor base current id cell address position bytes (scope := scope))
    (formed : base.CellsWellFormed) (newId : VarId) (newValue : Value) (different : id ≠ newId) :
    WriterCursor base (current.bindLocal newId newValue) id cell address position bytes
      (scope := (newId, current.nextCell) :: scope) :=
  ⟨cursor.frame.bindLocal newId newValue, cursor.fresh,
    (State.bindLocal_cellId_of_ne current id newId (Ne.symm different) newValue).trans cursor.slot,
    State.bindLocal_local?_of_ne current (cursor.frame.afterFormed formed) id newId _ newValue (Ne.symm different) cursor.value,
    by simpa only [State.bindLocal, State.bindCell, List.cons_append] using congrArg ((newId, current.nextCell) :: ·) cursor.locals⟩

/-- Updating another fresh control cell preserves output and the cursor.
    The assignment's existence is discharged by the execution rules below. -/
theorem WriterCursor.afterControlAssignment
    (cursor : WriterCursor base before id cell address position bytes (scope := scope))
    (formed : base.CellsWellFormed) (slot : before.cellId? control = some controlCell)
    (fresh : base.nextCell ≤ controlCell) (different : controlCell ≠ cell)
    (assigned : before.assignLocal control replacement = some after) :
    WriterCursor base after id cell address position bytes (scope := scope) ∧
      after.local? control = some replacement ∧
      (∀ localId value, before.local? localId = some value → before.cellId? localId ≠ some controlCell →
        after.local? localId = some value) := by
  have assignedCell := assignLocal_assignCell _ _ _ slot assigned
  have effect := assignCell_effect assignedCell
  refine ⟨⟨⟨by simpa only [effect.heap] using cursor.frame.output,
    cursor.frame.cells.assignCellFresh formed _ _ fresh assignedCell,
    effect.world.trans cursor.frame.world, effect.views.trans cursor.frame.views⟩,
    cursor.fresh, by simpa only [State.cellId?, effect.locals] using cursor.slot,
    assignCell_preserves_other_local_of_cellId _ _ _ assignedCell cursor.value
      (by rw [cursor.slot]; simpa using different.symm),
    effect.locals.trans cursor.locals⟩,
    assignLocal_finds_assigned _ _ _ slot assigned, ?_⟩
  intro localId value found separated
  exact assignCell_preserves_other_local_of_cellId _ _ _ assignedCell found separated

/-- A native-navigation call may allocate parameter cells, then store its
    result in a fresh loop control. Caller cells and output stay framed. -/
theorem WriterCursor.assignControl
    (cursor : WriterCursor base before id cell address position bytes (scope := scope))
    (formed : base.CellsWellFormed) (slot : before.cellId? control = some controlCell)
    (found : before.local? control = some (.signed .i32 previous))
    (fresh : base.nextCell ≤ controlCell) (different : controlCell ≠ cell)
    (read : RunsExpr program before expression (.signed .i32 next) ready) (pure : PureFrame before ready) :
    ∃ after, RunsExpr program before (.assign .set (.local control) expression) .unit after ∧
      WriterCursor base after id cell address position bytes (scope := scope) ∧
      after.local? control = some (.signed .i32 next) ∧
      (∀ localId value, before.local? localId = some value → before.cellId? localId ≠ some controlCell →
        after.local? localId = some value) := by
  obtain ⟨after, run, assigned, _⟩ := RunsExpr.assignI32After slot found read
  have slotReady : ready.cellId? control = some controlCell := by
    simpa only [State.cellId?, pure.locals] using slot
  obtain ⟨nextCursor, updated, retained⟩ := (cursor.afterPure pure).afterControlAssignment
    formed slotReady fresh different assigned
  exact ⟨after, run, nextCursor, updated, fun localId value found separated =>
    retained localId value (pure.localFound found) (by simpa only [State.cellId?, pure.locals] using separated)⟩

/-- Increment a fresh ordinal without reconstructing its assignment frame. -/
theorem WriterCursor.incrementControl
    (cursor : WriterCursor base before id cell address position bytes (scope := scope))
    (formed : base.CellsWellFormed) (slot : before.cellId? control = some controlCell)
    (found : before.local? control = some (.signed .i32 (index : Nat)))
    (fresh : base.nextCell ≤ controlCell) (different : controlCell ≠ cell) (fits : index + 1 < 2 ^ 31) :
    ∃ after, RunsExpr program before (.assign .add (.local control) (.value (.signed .i32 1))) .unit after ∧
      WriterCursor base after id cell address position bytes (scope := scope) ∧
      after.local? control = some (.signed .i32 (index + 1 : Nat)) ∧
      (∀ localId value, before.local? localId = some value → before.cellId? localId ≠ some controlCell →
        after.local? localId = some value) := by
  obtain ⟨after, run, assigned, _⟩ := RunsExpr.assignI32
    (op := .add) (replacement := (index + 1 : Nat)) slot found (.ofStable .value rfl) (by
      simpa only [evalAssignValue, assignOpBinary?, Int.natCast_add, Int.natCast_one] using
        eval_i32_addNat program.target index 1 fits)
  obtain ⟨nextCursor, updated, retained⟩ := cursor.afterControlAssignment formed slot fresh different assigned
  exact ⟨after, run, nextCursor, updated, retained⟩

/-- A proved writer call followed by storing its returned cursor. The store's
    existence, retained output, fresh-cell frame, and new cursor are derived. -/
theorem WriterCursor.advanceKeeping (cursor : WriterCursor base before id cell address position front (scope := scope))
    (formed : base.CellsWellFormed)
    (right : RunsExpr program before expression (.signed .i32 (position + (front ++ suffix).length : Nat)) ready)
    (written : WriterFrame before ready (address + front.length) suffix) :
    ∃ after, RunsExpr program before (.assign .set (.local id) expression) .unit after ∧
      WriterCursor base after id cell address position (front ++ suffix) (scope := scope) ∧
      (∀ localId value, before.local? localId = some value → before.cellId? localId ≠ some cell →
        after.local? localId = some value) := by
  obtain ⟨after, run, assigned, effect⟩ := RunsExpr.assignI32After cursor.slot cursor.value right
  have slot : ready.cellId? id = some cell := by
    simpa only [State.cellId?, right.choose_spec.2] using cursor.slot
  have cells := (cursor.frame.cells.trans written.cells).assignCellFresh formed _ _ cursor.fresh
    (assignLocal_assignCell _ _ _ slot assigned)
  refine ⟨after, run, ⟨⟨by simpa only [effect.heap] using cursor.frame.output.append written.output,
      cells, effect.world.trans (written.world.trans cursor.frame.world),
      effect.views.trans (written.views.trans cursor.frame.views)⟩,
    cursor.fresh, by simpa only [State.cellId?, effect.locals] using slot,
    assignLocal_finds_assigned _ _ _ slot assigned,
    effect.locals.trans (right.choose_spec.2.trans cursor.locals)⟩, ?_⟩
  intro localId value found different
  apply assignCell_preserves_other_local_of_cellId localId cell _
    (assignLocal_assignCell _ _ _ slot assigned)
  · exact written.cells.localFound right.choose_spec.2 localId value found
  · simpa only [State.cellId?, right.choose_spec.2] using different

/-- The simple cursor result is a projection of the same framed update. -/
theorem WriterCursor.advance (cursor : WriterCursor base before id cell address position front (scope := scope))
    (formed : base.CellsWellFormed)
    (right : RunsExpr program before expression (.signed .i32 (position + (front ++ suffix).length : Nat)) ready)
    (written : WriterFrame before ready (address + front.length) suffix) :
    ∃ after, RunsExpr program before (.assign .set (.local id) expression) .unit after ∧
      WriterCursor base after id cell address position (front ++ suffix) (scope := scope) := by
  obtain ⟨after, run, next, _⟩ := cursor.advanceKeeping formed right written
  exact ⟨after, run, next⟩

/-- Compose pure argument reads, a checked writer call, and its cursor store.
    Cursor arithmetic is checked once rather than by rewriting execution proofs. -/
theorem WriterCursor.advanceArgumentsKeeping (cursor : WriterCursor base before id cell address position front (scope := scope))
    (formed : base.CellsWellFormed)
    (call : ∃ ready, RunsExpr program before (.call functionId (values.map Expr.value))
      (.signed .i32 next) ready ∧ WriterFrame before ready (address + front.length) suffix)
    (arguments : RunsExprs program before expressions values before)
    (positionIs : next = (position + (front ++ suffix).length : Nat)) :
    ∃ after, RunsExpr program before (.assign .set (.local id) (.call functionId expressions)) .unit after ∧
      WriterCursor base after id cell address position (front ++ suffix) (scope := scope) ∧
      (∀ localId value, before.local? localId = some value → before.cellId? localId ≠ some cell →
        after.local? localId = some value) := by
  obtain ⟨ready, run, frame⟩ := call
  rw [positionIs] at run
  exact cursor.advanceKeeping formed (RunsExpr.callArguments arguments run) frame

theorem WriterCursor.advanceArguments (cursor : WriterCursor base before id cell address position front (scope := scope))
    (formed : base.CellsWellFormed)
    (call : ∃ ready, RunsExpr program before (.call functionId (values.map Expr.value))
      (.signed .i32 next) ready ∧ WriterFrame before ready (address + front.length) suffix)
    (arguments : RunsExprs program before expressions values before)
    (positionIs : next = (position + (front ++ suffix).length : Nat)) :
    ∃ after, RunsExpr program before (.assign .set (.local id) (.call functionId expressions)) .unit after ∧
      WriterCursor base after id cell address position (front ++ suffix) (scope := scope) := by
  obtain ⟨ready, run, frame⟩ := call
  rw [positionIs] at run
  exact cursor.advance formed (RunsExpr.callArguments arguments run) frame

/-- A conditional writer may read metadata and allocate guard-call cells.
    The false branch does not run the writer; either branch retains the live
    cursor scope and every other local's value. Writer success is discharged
    by the caller's checked contract, not inferred by this composition rule. -/
theorem WriterCursor.branchArguments (cursor : WriterCursor base before id cell address position front (scope := scope))
    {conditionExpr : Expr} (formed : base.CellsWellFormed) (truth : Bool)
    (condition : ∃ ready, RunsExpr program before conditionExpr (.boolean truth) ready ∧ PureFrame before ready)
    (write : truth = true → ∀ ready, PureFrame before ready → ∃ printed,
      RunsExpr program ready (.call functionId (values.map Expr.value))
        (.signed .i32 (position + (front ++ suffix).length : Nat)) printed ∧
        WriterFrame ready printed (address + front.length) suffix)
    (arguments : ∀ ready, PureFrame before ready → RunsExprs program ready expressions values ready) :
    ∃ after, RunsStmt program before (.ifThenElse conditionExpr
      (.sequence (.expression (.assign .set (.local id) (.call functionId expressions))) .skip) .skip) .next after ∧
      WriterCursor base after id cell address position (front ++ if truth then suffix else []) (scope := scope) ∧
      (∀ key value, before.local? key = some value → before.cellId? key ≠ some cell → after.local? key = some value) := by
  obtain ⟨ready, guardRun, pure⟩ := condition
  cases truth with
  | false =>
      exact ⟨ready, .ifThenElseFalse guardRun (.skip _ _),
        by simpa using cursor.afterPure pure, fun _ _ found _ => pure.localFound found⟩
  | true =>
      obtain ⟨after, written, next, kept⟩ := (cursor.afterPure pure).advanceArgumentsKeeping formed
        (write rfl ready pure) (arguments ready pure) rfl
      exact ⟨after, .ifThenElseTrue guardRun (.sequenceNext (.expression written) (.skip _ _)), next,
        fun key value found separate => kept key value (pure.localFound found)
          (by simpa only [State.cellId?, pure.locals] using separate)⟩

/-- Finishing a cursor chain uses the returned writer value without mutating
    the cursor again. The accumulated caller/input frame includes both writes. -/
theorem WriterCursor.finishArguments (cursor : WriterCursor base before id cell address position front (scope := scope))
    (call : ∃ after, RunsExpr program before (.call functionId (values.map Expr.value))
      (.signed .i32 next) after ∧ WriterFrame before after (address + front.length) suffix)
    (arguments : RunsExprs program before expressions values before)
    (positionIs : next = (position + (front ++ suffix).length : Nat)) :
    ∃ after, RunsStmt program before (.returnValue (some (.call functionId expressions)))
      (.returned (some (.signed .i32 (position + (front ++ suffix).length : Nat)))) after ∧
      WriterFrame base after address (front ++ suffix) := by
  obtain ⟨after, run, frame⟩ := call
  rw [positionIs] at run
  exact ⟨after, .returnValue (RunsExpr.callArguments arguments run), cursor.frame.append frame⟩

end Lanius.Extraction
