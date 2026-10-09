import Lanius.Extraction.WriterCursor
import Lanius.Semantics.CallProof
import Lanius.Semantics.PureProof

namespace Lanius.Extraction.WriterCursorTests

open Lanius.Core Lanius.Semantics

private def reader : Function := {
  id := 99, parameters := [(9, .scalar (.signed .i32))], returnType := .scalar (.signed .i32),
  body := some (.returnValue (some (.binary .add (.local 9) (.value (.signed .i32 1))))) }
private def program : Program := { functions := [reader] }

private abbrev Scoped (base current : State) (cell : CellId) (address position : Nat)
    (bytes : List UInt8) (scope : List (VarId × CellId) := []) :=
  WriterCursor base current 20 cell address position bytes (scope := scope)

-- Abbreviated cursor records still supply lookup evidence. No individual
-- cursor-value or preserved-local fact needs to be restated in the proof.
example (cursor : Scoped base current cell address position bytes) :
    RunsExpr program current (.local 20) (.signed .i32 (position + bytes.length : Nat)) current := by
  core_run

example (cursor : Scoped base current cell address position bytes) (caller : base.local? 100 = some value) :
    RunsExpr program current (.local 100) value current := by core_run

example (cursor : Scoped base current cell address position bytes [(40, otherCell)])
    (caller : base.local? 100 = some value) :
    RunsExpr program current (.local 100) value current := by core_run

example (cursor : Scoped base current cell address position bytes [(100, otherCell)])
    (caller : base.local? 100 = some value) : True := by
  fail_if_success
    have shadowed : RunsExpr program current (.local 100) value current := by core_run
  trivial

example (cursor : Scoped base current cell address position bytes) (other : State)
    (different : other.locals ≠ current.locals) : True := by
  fail_if_success
    have wrongState : RunsExpr program other (.local 20)
        (.signed .i32 (position + bytes.length : Nat)) other := by core_run
  trivial

-- A temporary binding can disappear without reverting the cursor's stored
-- value. Restoring a caller that points at another cell must be rejected.
example (cursor : Scoped base current cell address position bytes [(40, temporary)]) (caller : State)
    (locals : caller.locals = (20, cell) :: base.locals)
    (slot : caller.cellId? 20 = some cell) :
    Scoped base (restoreLocals caller current) cell address position bytes :=
  cursor.restoreScope locals slot

example (cursor : Scoped base current cell address position bytes [(40, temporary)]) (caller : State)
    (locals : caller.locals = (20, otherCell) :: base.locals) (different : otherCell ≠ cell) : True := by
  fail_if_success
    have restored : Scoped base (restoreLocals caller current) cell address position bytes :=
      cursor.restoreScope locals (by simp [State.cellId?, locals])
  trivial

/-- The RHS is a real call using the current child, not an injected result.
    Its parameter cell survives, but caller cells and both other controls stay intact. -/
theorem controls (formed : base.CellsWellFormed) (unique : Memory.HeapBlockBasesUnique base.heap)
    (caller : base.local? 100 = some (.signed .i32 42)) :
    ∃ after, RunsStmt program
      (((base.bindLocal 20 (.signed .i32 4)).bindLocal 30 (.signed .i32 1)).bindLocal 40 (.signed .i32 0))
      (.sequence (.expression (.assign .set (.local 30) (.call 99 [.local 30])))
        (.sequence (.expression (.assign .add (.local 40) (.value (.signed .i32 1)))) .skip)) .next after ∧
      WriterCursor base after 20 base.nextCell address 4 []
        (scope := [(40, base.nextCell + 2), (30, base.nextCell + 1)]) ∧
      after.local? 30 = some (.signed .i32 2) ∧ after.local? 40 = some (.signed .i32 1) ∧
      after.local? 100 = some (.signed .i32 42) := by
  let frame : WriterFrame base base address [] :=
    ⟨.write (Memory.BytesWrite.refl unique), (CallerFrame.refl formed).cells, rfl, rfl⟩
  let first := WriterCursor.start (position := 4) frame formed rfl 20
  let second := first.bindLocal formed 30 (.signed .i32 1) (by decide)
  let current := second.bindLocal formed 40 (.signed .i32 0) (by decide)
  let before := ((base.bindLocal 20 (.signed .i32 4)).bindLocal 30 (.signed .i32 1)).bindLocal 40 (.signed .i32 0)
  have cursor : WriterCursor base before 20 base.nextCell address 4 []
      (scope := [(40, base.nextCell + 2), (30, base.nextCell + 1)]) := current
  have beforeFormed := cursor.frame.afterFormed formed
  have child : before.local? 30 = some (.signed .i32 1) := by core_local
  have ordinal : before.local? 40 = some (.signed .i32 0) := by core_local
  have childSlot : before.cellId? 30 = some (base.nextCell + 1) := by simp [State.cellId?, cursor.locals]
  have ordinalSlot : before.cellId? 40 = some (base.nextCell + 2) := by simp [State.cellId?, cursor.locals]
  have read : ∃ ready, RunsExpr program before (.call 99 [.local 30]) (.signed .i32 2) ready ∧ PureFrame before ready := by
    apply RunsExpr.callPureArguments
    · core_arguments
    · core_call_pure reader as callee
      core_pure
  obtain ⟨ready, read, pure⟩ := read
  have freshChild : base.nextCell ≤ base.nextCell + 1 := Nat.le_add_right _ _
  have differentChild : base.nextCell + 1 ≠ base.nextCell := Nat.ne_of_gt (Nat.lt_add_of_pos_right (by decide))
  have freshOrdinal : base.nextCell ≤ base.nextCell + 2 := Nat.le_add_right _ _
  have differentOrdinal : base.nextCell + 2 ≠ base.nextCell := Nat.ne_of_gt (Nat.lt_add_of_pos_right (by decide))
  obtain ⟨middle, childRun, advanced, childNext, kept⟩ := cursor.assignControl
    (control := 30) (controlCell := base.nextCell + 1) formed childSlot child
    freshChild differentChild read pure
  have ordinalKept := kept 40 _ ordinal (by rw [ordinalSlot]; simp)
  obtain ⟨after, ordinalRun, final, ordinalNext, kept⟩ := advanced.incrementControl (program := program) formed
    (control := 40) (controlCell := base.nextCell + 2) (by simp [State.cellId?, advanced.locals]) ordinalKept
    freshOrdinal differentOrdinal (by decide)
  have childKept := kept 30 _ childNext (by simp [State.cellId?, advanced.locals])
  refine ⟨after, by core_stmt, final, childKept, ordinalNext, ?_⟩
  exact final.localFound (by decide) caller (by simp)

-- A control update cannot be used to overwrite the cursor while claiming
-- that its old position and bytes remain valid.
example (cursor : WriterCursor base before 20 cell address position bytes)
    (formed : base.CellsWellFormed) : True := by
  fail_if_success
    have invalid := cursor.assignControl (program := program) formed cursor.slot cursor.value
      cursor.fresh (by omega) (RunsExpr.ofStable StableExpr.value rfl) (PureFrame.refl (cursor.frame.afterFormed formed))
  trivial

private def echo : Function := {
  id := 100, parameters := [(10, .scalar (.signed .i32))], returnType := .scalar (.signed .i32),
  body := some (.returnValue (some (.local 10))) }
private def branchProgram : Program := { functions := [reader, echo] }

/-- Either branch follows a real guard call that allocates parameter cells.
    The optional empty writer is also a real call, not an injected run. -/
theorem optionalBranch (truth : Bool) (formed : base.CellsWellFormed)
    (unique : Memory.HeapBlockBasesUnique base.heap) (caller : base.local? 200 = some value) :
    let before := base.bindLocal 20 (.signed .i32 4)
    ∃ after, RunsStmt branchProgram before (.ifThenElse
      (.binary .equal (.call 99 [.value (.signed .i32 0)]) (.value (.signed .i32 (if truth then 1 else 2))))
      (.sequence (.expression (.assign .set (.local 20) (.call 100 [.local 20]))) .skip) .skip) .next after ∧
      Scoped base after base.nextCell address 4 [] ∧ after.local? 200 = some value := by
  intro before
  have cursor : Scoped base before base.nextCell address 4 [] := WriterCursor.begin formed unique 20
  have beforeFormed := cursor.frame.afterFormed formed
  have condition : ∃ ready, RunsExpr branchProgram before
      (.binary .equal (.call 99 [.value (.signed .i32 0)]) (.value (.signed .i32 (if truth then 1 else 2))))
      (.boolean truth) ready ∧ PureFrame before ready := by
    apply RunsExpr.binaryPure (leftValue := .signed .i32 1)
      (rightValue := .signed .i32 (if truth then 1 else 2))
    · apply RunsExpr.callPureArguments (values := [.signed .i32 0])
      · core_arguments
      · core_call_pure reader as callee
        core_pure
    · intro ready pure
      exact ⟨ready, .ofStable .value rfl, PureFrame.refl pure.afterFormed⟩
    · simp
    · cases truth <;> rfl
  obtain ⟨after, run, next, kept⟩ := cursor.branchArguments formed truth condition
    (values := [.signed .i32 4]) (expressions := [.local 20]) (suffix := [])
    (fun _ ready guardFrame => by
      have readyFormed := guardFrame.afterFormed
      obtain ⟨printed, run, pure⟩ : ∃ printed, RunsExpr branchProgram ready
          (.call 100 [.value (.signed .i32 4)]) (.signed .i32 4) printed ∧ PureFrame ready printed := by
        apply RunsExpr.callPureArguments (values := [.signed .i32 4])
        · core_arguments
        · core_call_pure echo as callee
          core_pure
      exact ⟨printed, run, ⟨by
        simpa only [pure.heap] using Memory.OutputEffect.write (Memory.BytesWrite.refl (cursor.afterPure guardFrame).frame.output.unique),
        pure.cells, pure.world, pure.views⟩⟩)
    (fun ready pure => by
      have found := pure.localFound cursor.value
      core_arguments)
  exact ⟨after, run, by simpa using next, next.localFound (by decide) caller (by simp)⟩

example {base : State} (formed : base.CellsWellFormed) (unique : Memory.HeapBlockBasesUnique base.heap) : True := by
  fail_if_success
    have wrong : Scoped base (base.bindLocal 20 (.signed .i32 4)) (base.nextCell + 1) address 4 [] :=
      WriterCursor.begin formed unique 20
  trivial

-- Slot retention is independent of written bytes but not of lexical scope.
example (current : Scoped base after cell address position bytes scope)
    (previous : Scoped base before cell oldAddress oldPosition oldBytes scope) :
    after.cellId? key = before.cellId? key := current.slotsEq previous

example (current : Scoped base after cell address position bytes [(40, temporary)])
    (previous : Scoped base before cell oldAddress oldPosition oldBytes []) : True := by
  fail_if_success
    have wrong : after.cellId? 40 = before.cellId? 40 := current.slotsEq previous
  trivial

/-- A skipped branch needs no successful call to its nonexistent writer.
    In particular, no capacity for its unprinted suffix is assumed. -/
theorem inactiveWriter (formed : base.CellsWellFormed) (unique : Memory.HeapBlockBasesUnique base.heap) :
    let before := base.bindLocal 20 (.signed .i32 4)
    ∃ after, RunsStmt branchProgram before (.ifThenElse (.value (.boolean false))
      (.sequence (.expression (.assign .set (.local 20) (.call 404 [.local 20]))) .skip) .skip) .next after ∧
      Scoped base after base.nextCell address 4 [] := by
  intro before
  have cursor : Scoped base before base.nextCell address 4 [] := WriterCursor.begin formed unique 20
  obtain ⟨after, run, next, _⟩ := cursor.branchArguments (program := branchProgram) (functionId := 404) formed false
    ⟨before, .ofStable .value rfl, PureFrame.refl (cursor.frame.afterFormed formed)⟩
    (values := [.signed .i32 4]) (expressions := [.local 20]) (suffix := [65])
    (fun impossible _ _ => by cases impossible)
    (fun ready pure => by
      have found := pure.localFound cursor.value
      core_arguments)
  exact ⟨after, run, by simpa using next⟩

#print axioms controls
#print axioms WriterCursor.restoreScope
#print axioms WriterCursor.afterControlAssignment
#print axioms WriterCursor.assignControl
#print axioms WriterCursor.incrementControl
#print axioms WriterCursor.begin
#print axioms WriterCursor.branchArguments
#print axioms optionalBranch
#print axioms inactiveWriter
#print axioms WriterCursor.slotsEq
#print axioms RunsExpr.agree

end Lanius.Extraction.WriterCursorTests
