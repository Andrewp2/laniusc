import Lanius.Semantics.PureProof
import Lanius.Semantics.CallProof

namespace Lanius.Semantics

open Lanius.Core

-- A caller-specific contract need not be registered globally. Argument
-- reads are proved before the contract is reused; its frame is mandatory.
theorem localCallContract (program : Program) (state : State) (id cell : Lanius.VarId)
    (value : Bool) (found : state.local? cell = some (.boolean value))
    (contract : ∃ after, RunsExpr program state (.call id [.value (.boolean value)])
      (.boolean value) after ∧ PureFrame state after) :
    ∃ after, RunsExpr program state (.unary .logicalNot (.call id [.local cell]))
      (.boolean (!value)) after ∧ PureFrame state after := by core_pure_expr

theorem rejectsUnframedCall (program : Program) (state : State) (id cell : Lanius.VarId)
    (value : Bool) (_formed : state.CellsWellFormed) (_found : state.local? cell = some (.boolean value))
    (_unframed : ∃ after, RunsExpr program state (.call id [.value (.boolean value)]) (.boolean value) after) :
    True := by
  fail_if_success
    suffices falsePurity : ∃ after, RunsExpr program state (.call id [.local cell])
        (.boolean value) after ∧ PureFrame state after by trivial
    solve | core_pure_expr
  trivial

#print axioms localCallContract

-- A caller may specialize a proved helper without a global registration.
example (program : Program) (state : State) (id : Lanius.VarId)
    (contract : ∀ state : State, state.CellsWellFormed → ∃ after,
      RunsExpr program state (.call id []) (.boolean true) after ∧ PureFrame state after)
    (formed : state.CellsWellFormed) :
    ∃ after, RunsStmt program state
      (.ifThenElse (.call id [])
        (.letLocal 17 (.scalar .bool) (.value (.boolean false)) (.returnValue (some (.local 17))))
        (.returnValue (some (.value (.boolean true)))))
      (.returned (some (.boolean false))) after ∧ PureFrame state after := by
  have specialized := fun {current : State} (h : current.CellsWellFormed) => contract current h
  clear contract
  core_pure

-- Nested shadowing must restore the pre-existing caller cell, not leak a local.
example (program : Program) (state : State) (formed : state.CellsWellFormed) :
    ∃ after, RunsStmt program state
      (.letLocal 1 (.scalar (.signed .i32)) (.value (.signed .i32 42))
        (.letLocal 1 (.scalar (.signed .i32)) (.value (.signed .i32 7))
          (.returnValue (some (.local 1)))))
      (.returned (some (.signed .i32 7))) after ∧ PureFrame state after := by core_pure

-- An early return skips a trapping tail; fallthrough must execute it.
example (program : Program) (state : State) (formed : state.CellsWellFormed) :
    ∃ after, RunsStmt program state
      (.sequence (.ifThenElse (.value (.boolean true))
        (.returnValue (some (.value (.signed .i32 42)))) .skip)
        (.expression (.binary .divide (.value (.signed .i32 1)) (.value (.signed .i32 0)))))
      (.returned (some (.signed .i32 42))) after ∧ PureFrame state after := by core_pure

example (program : Program) (state : State) (formed : state.CellsWellFormed) :
    ∃ after, RunsStmt program state
      (.sequence .skip (.returnValue (some (.value (.signed .i32 7)))))
      (.returned (some (.signed .i32 7))) after ∧ PureFrame state after := by core_pure

example (program : Program) (state : State) (formed : state.CellsWellFormed) :
    ∃ after, RunsStmt program state
      (.sequence (.ifThenElse (.value (.boolean false))
        (.returnValue (some (.value (.signed .i32 99)))) .skip)
        (.returnValue (some (.value (.signed .i32 7)))))
      (.returned (some (.signed .i32 7))) after ∧ PureFrame state after := by core_pure

-- A guard's true branch may fall through too: it is not automatically a return.
example (program : Program) (state : State) (formed : state.CellsWellFormed) :
    ∃ after, RunsStmt program state
      (.sequence (.ifThenElse (.value (.boolean true)) .skip .skip)
        (.returnValue (some (.value (.signed .i32 7)))))
      (.returned (some (.signed .i32 7))) after ∧ PureFrame state after := by core_pure

example (_program : Program) (state : State) (_formed : state.CellsWellFormed) : True := by
  fail_if_success
    suffices wrongReturn : ∃ after, RunsStmt _program state (.returnValue (some (.value (.signed .i32 1))))
        (.returned (some (.signed .i32 2))) after ∧ PureFrame state after by trivial
    solve | core_pure
  fail_if_success
    suffices skippedTrap : ∃ after, RunsStmt _program state
        (.sequence .skip
          (.expression (.binary .divide (.value (.signed .i32 1)) (.value (.signed .i32 0)))))
        .next after ∧ PureFrame state after by trivial
    solve | core_pure
  trivial

-- This is a successful mutation of an existing caller cell. Supplying its
-- execution proof must not let automation mistake it for a pure statement.
private def before : State := ({} : State).bindLocal 2 (.boolean false)
private def after : State := boundLocalAssigned {} 2 (.boolean false) (.boolean true)
private def mutation : Expr := .assign .set (.local 2) (.value (.boolean true))
theorem rejectsUnframedMutation : True := by
  have changes : RunsExpr {} before mutation .unit after :=
    .ofStable (StableExpr.assignSetBool {} before 2 0 (.boolean false) true after
      rfl rfl rfl rfl) rfl
  fail_if_success
    suffices falsePurity : ∃ completed, RunsStmt {} before (.expression mutation) .next completed ∧
        PureFrame before completed by trivial
    solve | core_pure
  trivial

#print axioms RunsStmt.letPure
#print axioms RunsStmt.branchPure

-- A later wrong return must fail without reconsidering every proved guard
-- and initializer. The same nested prefix must still prove the correct result.
private def guardedLocals : Nat → Stmt
  | 0 => .returnValue (some (.value (.signed .i32 7)))
  | depth + 1 => .letLocal (30 + depth) (.scalar (.signed .i32)) (.value (.signed .i32 depth))
      (.sequence (.ifThenElse (.value (.boolean false))
        (.returnValue (some (.value (.signed .i32 99)))) .skip) (guardedLocals depth))

example (program : Program) (state : State) (formed : state.CellsWellFormed) :
    ∃ after, RunsStmt program state (guardedLocals 4) (.returned (some (.signed .i32 7))) after ∧
      PureFrame state after := by core_pure

example (program : Program) (state : State) (formed : state.CellsWellFormed) : True := by
  fail_if_success
    have wrong : ∃ after, RunsStmt program state (guardedLocals 4) (.returned (some (.signed .i32 8))) after ∧
        PureFrame state after := by core_pure
  trivial

private def echo : Function := {
  id := 99, parameters := [(9, .scalar .bool)], returnType := .scalar .bool,
  body := some (.returnValue (some (.local 9))) }
private def calls : Program := { functions := [echo] }
private def echoCall (value : Bool) : Expr := .call echo.id [.value (.boolean value)]
@[core_pure_rule] private theorem pureEcho (value : Bool) (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr calls state (echoCall value) (.boolean value) after ∧ PureFrame state after := by
  core_call echo
  core_stmt

private def falseCallsOr : Expr :=
  .binary .logicalOr (echoCall false) (.binary .logicalOr (echoCall false) (echoCall false))

theorem falseOrGuardAfterFreshCalls (state : State) (formed : state.CellsWellFormed)
    (found : state.local? 9 = some (.boolean true)) :
    ∃ after, RunsExpr calls state falseCallsOr (.boolean false) after ∧
      PureFrame state after ∧ after.local? 9 = some (.boolean true) := by
  obtain ⟨after, run, frame⟩ : ∃ after, RunsExpr calls state falseCallsOr
      (.boolean false) after ∧ PureFrame state after := by core_pure_guard
  exact ⟨after, run, frame, frame.localFound found⟩

theorem trueOrGuardSkipsMissingCall (state : State) (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr calls state (.binary .logicalOr (echoCall true) (.call 999 []))
      (.boolean true) after ∧ PureFrame state after := by core_pure_guard

example (_state : State) (_formed : _state.CellsWellFormed) : True := by
  fail_if_success
    suffices wrong : ∃ after, RunsExpr calls _state falseCallsOr (.boolean true) after ∧
        PureFrame _state after by trivial
    solve | core_pure_guard
  trivial

example (program : Program) (state : State) (id : Lanius.FunctionId)
    (_formed : state.CellsWellFormed)
    (_unframed : ∃ after, RunsExpr program state (.call id []) (.boolean false) after) : True := by
  fail_if_success
    suffices unsupported : ∃ after, RunsExpr program state
        (.binary .logicalOr (.call id []) (.value (.boolean false))) (.boolean false) after ∧
        PureFrame state after by trivial
    solve | core_pure_guard
  trivial

#print axioms falseOrGuardAfterFreshCalls
#print axioms trueOrGuardSkipsMissingCall

-- Both branches use a framed helper condition, including a nested scope.
-- Its temporary cells must not prevent the branch from reading local values.
example (state : State) (formed : state.CellsWellFormed) (flag : Bool) :
    ∃ after, RunsStmt calls state
      (.ifThenElse (echoCall flag)
        (.letLocal 17 (.scalar (.signed .i32)) (.value (.signed .i32 7))
          (.returnValue (some (.local 17))))
        (.returnValue (some (.value (.signed .i32 9)))))
      (.returned (some (.signed .i32 (if flag then 7 else 9)))) after ∧ PureFrame state after := by
  cases flag <;> core_pure

example (state : State) (formed : state.CellsWellFormed) :
    ∃ after, RunsStmt calls state
      (.letLocal 17 (.scalar .bool) (echoCall true) (.returnValue (some (.local 17))))
      (.returned (some (.boolean true))) after ∧ PureFrame state after := by core_pure

example (state : State) (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr calls state (.unary .logicalNot (echoCall false)) (.boolean true) after ∧
      PureFrame state after := by core_pure_expr

example (state : State) (formed : state.CellsWellFormed) (found : state.local? 17 = some (.boolean true)) :
    ∃ after, RunsStmt calls state
      (.sequence (.ifThenElse (echoCall false) (.returnValue (some (.value (.boolean false)))) .skip)
        (.returnValue (some (.local 17))))
      (.returned (some (.boolean true))) after ∧ PureFrame state after := by core_pure

example (state : State) (formed : state.CellsWellFormed) :
    ∃ after, RunsStmt calls state
      (.sequence (.ifThenElse (echoCall true) (.returnValue (some (.value (.boolean true)))) .skip)
        (.expression (.binary .divide (.value (.signed .i32 1)) (.value (.signed .i32 0)))))
      (.returned (some (.boolean true))) after ∧ PureFrame state after := by core_pure

-- Skip a nontrivial branch after a helper-call guard, then retain the caller's
-- local for the continuation. The first statement allocates call cells.
example (state : State) (formed : state.CellsWellFormed) (found : state.local? 17 = some (.boolean true)) :
    ∃ after, RunsStmt calls state
      (.sequence (.ifThenElse (echoCall false)
        (.letLocal 18 (.scalar .bool) (.value (.boolean false)) (.returnValue (some (.local 18)))) .skip)
        (.returnValue (some (.local 17))))
      (.returned (some (.boolean true))) after ∧ PureFrame state after := by core_pure

#print axioms RunsStmt.sequenceFramedNext

example (state : State) (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr calls state
      (.binary .logicalOr (echoCall true) (.binary .divide (.value (.signed .i32 1)) (.value (.signed .i32 0))))
      (.boolean true) after ∧ PureFrame state after := by core_pure_expr

example (state : State) (formed : state.CellsWellFormed) (value : Bool) :
    ∃ after, RunsExpr calls state (.binary .equal (echoCall value) (echoCall value)) (.boolean true) after ∧
      PureFrame state after := by core_pure_expr

example (_state : State) (_formed : _state.CellsWellFormed) : True := by
  fail_if_success
    suffices wrong : ∃ after, RunsExpr calls _state (.unary .logicalNot (echoCall false))
        (.boolean false) after ∧ PureFrame _state after by trivial
    solve | core_pure_expr
  trivial

private def integerEcho : Function := {
  id := 100, parameters := [(9, .scalar (.signed .i32))], returnType := .scalar (.signed .i32),
  body := some (.returnValue (some (.local 9))) }
private def integerCalls : Program := { functions := [integerEcho] }
@[core_pure_rule] private theorem pureIntegerEcho (value : Int) (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr integerCalls state (.call integerEcho.id [.value (.signed .i32 value)])
      (.signed .i32 value) after ∧ PureFrame state after := by
  core_call integerEcho
  core_stmt

private def positive (value : Int) : Bool := decide (value > 0)

example (a b : Bool) (rejected : ¬(a || b) = true) : (a || b) = false := by core_guard_logic
example (count id : Int) (valid : Bool) (bad : count ≤ 0 ∨ id < 0 ∨ valid = false) :
    (decide (count ≤ 0) || decide (id < 0) || !valid) = true := by core_guard_logic
example (count id : Int) (valid : Bool) (good : ¬(count ≤ 0 ∨ id < 0 ∨ valid = false)) :
    (decide (count ≤ 0) || decide (id < 0) || !valid) = false := by core_guard_logic
example (count id value : Int) (good : ¬(count ≤ 0 ∨ id < 0 ∨ positive value = false)) :
    (false || !positive value) = false := by core_guard_logic
example (value : Int) (below : value < 1000000000) : decide (value < 1000000000) = true := by core_guard_logic
example (value : Int) (above : 1000000000 ≤ value) : decide (value < 1000000000) = false := by core_guard_logic
example (program : Program) (state : State) (value : Nat) :
    RunsExpr program state (.binary .less (.value (.signed .i32 value)) (.value (.signed .i32 0)))
      (.boolean false) state := by core_run

example (state : State) (formed : state.CellsWellFormed) (value : Int) :
    ∃ after, RunsStmt integerCalls (state.bindLocal 9 (.signed .i32 value))
      (.returnValue (some (.binary .greater (.call integerEcho.id [.local 9]) (.value (.signed .i32 0)))))
      (.returned (some (.boolean (positive value)))) after ∧
      PureFrame (state.bindLocal 9 (.signed .i32 value)) after := by core_pure

example (_state : State) (_formed : _state.CellsWellFormed) (value : Int) : True := by
  fail_if_success
    suffices wrong : ∃ after, RunsExpr integerCalls _state
        (.binary .greater (.call integerEcho.id [.value (.signed .i32 value)]) (.value (.signed .i32 0)))
        (.boolean (decide (value ≤ 0))) after ∧ PureFrame _state after by trivial
    solve | core_pure_expr
  trivial

#print axioms RunsExpr.binaryPure
#print axioms RunsExpr.logicalOrPure
#print axioms RunsStmt.letFramedPure

private def recordEcho : Function := {
  id := 101, parameters := [(9, .scalar .bool)], returnType := .structure 7,
  body := some (.returnValue (some (.structValue 7 [.local 9]))) }
private def recordCalls : Program := {
  structures := [{ id := 7, fields := [.scalar .bool] }], functions := [recordEcho] }
@[core_pure_rule] private theorem pureRecordEcho (value : Bool) (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr recordCalls state (.call recordEcho.id [.value (.boolean value)])
      (.structure 7 [.boolean value]) after ∧ PureFrame state after := by
  core_call recordEcho
  core_stmt

example (state : State) (formed : state.CellsWellFormed) (value : Bool) :
    ∃ after, RunsExpr recordCalls state (.field (.call recordEcho.id [.value (.boolean value)]) 0)
      (.boolean value) after ∧ PureFrame state after := by core_pure_expr
example (_state : State) (_formed : _state.CellsWellFormed) : True := by
  fail_if_success
    suffices wrong : ∃ after, RunsExpr recordCalls _state
        (.field (.call recordEcho.id [.value (.boolean true)]) 1) (.boolean true) after ∧
        PureFrame _state after by trivial
    solve | core_pure_expr
  trivial

#print axioms RunsExpr.fieldPure

-- A read-only false left operand keeps heap-read evidence available to the
-- right call; successful pure calls may themselves allocate fresh cells.
example (state : State) (formed : state.CellsWellFormed) (argument : Expr) (value : Bool)
    (read : RunsExpr recordCalls state argument (.boolean value) state) :
    ∃ after, RunsExpr recordCalls state
      (.binary .logicalOr (.value (.boolean false))
        (.field (.call recordEcho.id [argument]) 0)) (.boolean value) after ∧ PureFrame state after := by
  core_pure_expr

example (_state : State) (_formed : _state.CellsWellFormed) (argument : Expr)
    (_read : RunsExpr recordCalls _state argument (.boolean false) _state) : True := by
  fail_if_success
    suffices wrong : ∃ after, RunsExpr recordCalls _state
        (.binary .logicalOr (.value (.boolean false))
          (.field (.call recordEcho.id [argument]) 0)) (.boolean true) after ∧ PureFrame _state after by trivial
    solve | core_pure_expr
  trivial

#print axioms RunsExpr.logicalOrFalsePure

-- Native reads retain their evidence across multiple pure helper calls and
-- fresh local bindings. An unrelated heap must not acquire that evidence.
example (before middle after : State) (first : PureFrame before middle)
    (second : PureFrame (middle.bindLocal 21 .unit) after)
    (read : readRawSliceIndex calls before element address count index = .ok value) :
    readRawSliceIndex calls (after.bindLocal 22 .unit) element address count index = .ok value := by
  core_contract

example (_before after : State)
    (_read : readRawSliceIndex calls _before element address count index = .ok value) : True := by
  fail_if_success
    have wrong : readRawSliceIndex calls after element address count index = .ok value := by core_contract
  trivial

-- A false read-only call short-circuits without evaluating a missing callee.
example (state : State) (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr calls state
      (.binary .logicalAnd (.call echo.id [.value (.boolean false)]) (.call 999 []))
      (.boolean false) after ∧ PureFrame state after := by core_pure_expr

-- A true state-identical operand composes the right call's fresh-cell frame.
example (state : State) (formed : state.CellsWellFormed) (argument : Expr) (value : Bool)
    (read : RunsExpr recordCalls state argument (.boolean value) state) :
    ∃ after, RunsExpr recordCalls state
      (.binary .logicalAnd (.value (.boolean true))
        (.field (.call recordEcho.id [argument]) 0)) (.boolean value) after ∧ PureFrame state after := by
  core_pure_expr

example (_state : State) (_formed : _state.CellsWellFormed) : True := by
  fail_if_success
    suffices wrong : ∃ after, RunsExpr calls _state
        (.binary .logicalAnd (.value (.boolean true)) (.call echo.id [.value (.boolean false)]))
        (.boolean true) after ∧ PureFrame _state after by trivial
    solve | core_pure_expr
  trivial

#print axioms RunsExpr.logicalAndFalsePure
#print axioms RunsExpr.logicalAndTruePure

-- Nested calls allocate fresh parameter cells, and a later local argument
-- must still read the original caller cell after those allocations.
example (state : State) (formed : state.CellsWellFormed) (value : Bool) :
    ∃ after, RunsExpr calls state
      (.call echo.id [.call echo.id [.value (.boolean value)]]) (.boolean value) after ∧
      PureFrame state after := by core_pure_expr

example (state : State) (formed : state.CellsWellFormed) (value : Bool)
    (found : state.local? 17 = some (.boolean value)) :
    ∃ after, RunsExprs calls state
      [.call echo.id [.local 17], .local 17] [.boolean value, .boolean value] after ∧
      PureFrame state after := by core_pure_arguments

theorem rejectsWrongNestedResult (_state : State) (_formed : _state.CellsWellFormed) : True := by
  fail_if_success
    suffices wrong : ∃ after, RunsExpr calls _state
        (.call echo.id [.call echo.id [.value (.boolean true)]]) (.boolean false) after ∧
        PureFrame _state after by trivial
    solve | core_pure_expr
  trivial

#print axioms RunsExprs.consPure
#print axioms RunsExpr.callFramedPureArguments

-- An argument's successful run alone does not establish read-only effects.
example (_program : Program) (_state : State) (expression : Expr) (value : Value)
    (_run : ∃ after, RunsExpr _program _state expression value after) : True := by
  fail_if_success
    suffices unframed : ∃ after, RunsExprs _program _state [expression] [value] after ∧
        PureFrame _state after by trivial
    solve | core_pure_arguments
  trivial

-- Conditional automation fixtures, not compiler-correctness theorems.
-- The specialized inner contract requires retaining the exact stable prefix state.
theorem stablePrefixNestedCall (program : Program) (state : State) (headExpr : Expr)
    (prefixValue value retained : Value) (innerId outerId localId : Lanius.FunctionId)
    (formed : state.CellsWellFormed) (stable : RunsExpr program state headExpr prefixValue state)
    (found : state.local? localId = some retained)
    (inner : ∃ after, RunsExpr program state (.call innerId []) value after ∧ PureFrame state after)
    (outer : ∀ current : State, current.CellsWellFormed → ∃ after,
      RunsExpr program current (.call outerId [.value value]) value after ∧ PureFrame current after) :
    ∃ after, RunsExprs program state [headExpr, .call outerId [.call innerId []], .local localId]
      [prefixValue, value, retained] after ∧ PureFrame state after := by core_pure_arguments

theorem callThroughAnchoredFrames (program : Program) (before middle after : State)
    (fixedHeap : Lanius.Memory.Heap) (id : Lanius.FunctionId) (value : Value)
    (anchor : before.heap = fixedHeap) (first : PureFrame before middle)
    (second : PureFrame (middle.bindLocal 21 .unit) after)
    (contract : ∀ current : State, current.heap = fixedHeap → current.CellsWellFormed → ∃ done,
      RunsExpr program current (.call id []) value done ∧ PureFrame current done) :
    ∃ done, RunsExpr program after (.call id []) value done ∧ PureFrame after done := by core_pure_expr

theorem rejectsCyclicMissingHeap (before middle : State) (fixedHeap : Lanius.Memory.Heap)
    (forward : PureFrame before middle) (backward : PureFrame middle before) : True := by
  fail_if_success
    have wrong : middle.heap = fixedHeap := by core_contract
  trivial

theorem rejectsWrongHeapCall (program : Program) (before after : State)
    (fixedHeap wrongHeap : Lanius.Memory.Heap) (id : Lanius.FunctionId) (value : Value)
    (frame : PureFrame before after) (wrong : before.heap = wrongHeap) (different : wrongHeap ≠ fixedHeap)
    (contract : ∀ current : State, current.heap = fixedHeap → current.CellsWellFormed → ∃ done,
      RunsExpr program current (.call id []) value done ∧ PureFrame current done) : True := by
  fail_if_success
    have unsupported : ∃ done, RunsExpr program after (.call id []) value done ∧ PureFrame after done := by
      core_pure_expr
  trivial

theorem rejectsDifferentFramedLocal (program : Program) (before after : State) (value : Value)
    (frame : PureFrame before after) (found : before.local? 17 = some value) : True := by
  have right : RunsExpr program after (.local 17) value after := by core_run
  fail_if_success
    have wrong : RunsExpr program after (.local 18) value after := by core_run
  trivial

#print axioms stablePrefixNestedCall
#print axioms callThroughAnchoredFrames

private def pointerEcho : Function := {
  id := 102, parameters := [(9, .scalar .rawPtr)], returnType := .scalar .rawPtr,
  body := some (.returnValue (some (.local 9))) }
private def nominalCalls : Program := {
  structures := [{ id := 8, fields := [.scalar .bool] }], functions := [pointerEcho] }
@[core_pure_rule] private theorem purePointerEcho (address : Nat) (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr nominalCalls state (.call pointerEcho.id [.value (.pointer address)])
      (.pointer address) after ∧ PureFrame state after := by
  core_call pointerEcho
  core_stmt

theorem emptyNominalAfterCall (state : State) (formed : state.CellsWellFormed)
    (found : state.local? 17 = some (.signed .i32 0)) :
    ∃ after, RunsExpr nominalCalls state
      (.typedSliceFromRawParts (.structure 8) (.call pointerEcho.id [.value (.pointer 64)]) (.local 17))
      (.rawSlice (.structure 8) 64 0) after ∧ PureFrame state after := by core_pure_expr

theorem recordWithPureFields (state : State) (formed : state.CellsWellFormed)
    (found : state.local? 17 = some (.signed .i32 0)) :
    ∃ after, RunsExpr nominalCalls state
      (.structValue 19 [.call pointerEcho.id [.value (.pointer 64)], .local 17,
        .typedSliceFromRawParts (.structure 8) (.call pointerEcho.id [.value (.pointer 64)]) (.local 17)])
      (.structure 19 [.pointer 64, .signed .i32 0, .rawSlice (.structure 8) 64 0]) after ∧
      PureFrame state after := by core_pure_expr

theorem rejectsNonemptyNominal (_state : State) (_formed : _state.CellsWellFormed) : True := by
  fail_if_success
    suffices unsupported : ∃ after, RunsExpr nominalCalls _state
        (.typedSliceFromRawParts (.structure 8) (.call pointerEcho.id [.value (.pointer 64)])
          (.value (.signed .i32 1))) (.rawSlice (.structure 8) 64 1) after ∧ PureFrame _state after by trivial
    solve | core_pure_expr
  trivial

theorem rejectsUnframedNominal (program : Program) (state : State) (id : Lanius.FunctionId)
    (_formed : state.CellsWellFormed)
    (_unframed : ∃ after, RunsExpr program state (.call id []) (.pointer 64) after) : True := by
  fail_if_success
    suffices unsupported : ∃ after, RunsExpr program state
        (.typedSliceFromRawParts (.structure 8) (.call id []) (.value (.signed .i32 0)))
        (.rawSlice (.structure 8) 64 0) after ∧ PureFrame state after by trivial
    solve | core_pure_expr
  trivial

#print axioms RunsExpr.structPure
#print axioms RunsExpr.emptyRawNominalPure
#print axioms emptyNominalAfterCall
#print axioms recordWithPureFields
#print axioms rejectsNonemptyNominal
#print axioms rejectsUnframedNominal

-- A real helper call allocates its parameter cell while shadowing caller 9.
-- The numeric cast composes that frame rather than requiring identical states.
theorem castAfterFreshCall (state : State) (formed : state.CellsWellFormed)
    (found : state.local? 9 = some (.signed .i32 91)) :
    ∃ after, RunsExpr integerCalls state
      (.cast (.unsigned .usize) (.call integerEcho.id [.value (.signed .i32 7)]))
      (.unsigned .usize 7) after ∧ PureFrame state after ∧
      after.local? 9 = some (.signed .i32 91) := by
  obtain ⟨after, run, frame⟩ : ∃ after, RunsExpr integerCalls state
      (.cast (.unsigned .usize) (.call integerEcho.id [.value (.signed .i32 7)]))
      (.unsigned .usize 7) after ∧ PureFrame state after := by core_pure_expr
  exact ⟨after, run, frame, frame.localFound found⟩

theorem rejectsUnframedCast (program : Program) (state : State) (id : Lanius.FunctionId)
    (_formed : state.CellsWellFormed)
    (_unframed : ∃ after, RunsExpr program state (.call id []) (.signed .i32 7) after) : True := by
  fail_if_success
    suffices unsupported : ∃ after, RunsExpr program state
        (.cast (.unsigned .usize) (.call id [])) (.unsigned .usize 7) after ∧
        PureFrame state after by trivial
    solve | core_pure_expr
  trivial

example (state : State) (formed : state.CellsWellFormed) : True := by
  fail_if_success
    suffices wrong : ∃ after, RunsExpr integerCalls state
        (.cast (.unsigned .usize) (.call integerEcho.id [.value (.signed .i32 7)]))
        (.unsigned .usize 8) after ∧ PureFrame state after by trivial
    solve | core_pure_expr
  trivial

#print axioms castAfterFreshCall
#print axioms rejectsUnframedCast

private def castInitial : State := {
  locals := [(9, 0), (17, 1)]
  cells := [{ id := 0, value := some (.signed .i32 91) },
    { id := 1, value := some (.array [.signed .i32 5]) }]
  nextCell := 2
  heap := {
    blocks := [{ base := 64, size := 4, alignment := 4, bytes := [5, 0, 0, 0], owned := false }]
    nextAddress := 68 }
  world := { standardInput := [1], standardOutput := [2], standardError := [3] }
  i32ArrayViews := [{ address := 64, root := 1, projections := [], length := 1 }] }

#eval do
  let .done value after := evalExpr 100 integerCalls castInitial
      (.cast (.unsigned .usize) (.call integerEcho.id [.value (.signed .i32 7)]))
    | throw (IO.userError "cast around actual pure call failed")
  unless value == Value.unsigned .usize 7 && after.nextCell > castInitial.nextCell &&
      after.locals == castInitial.locals && after.local? 9 == some (Value.signed .i32 91) &&
      after.cell? 1 == some (Value.array [.signed .i32 5]) &&
      (after.heap.loadBytes 64 4).toOption == some [5, 0, 0, 0] &&
      after.heap.nextAddress == castInitial.heap.nextAddress &&
      after.world.standardInput == [1] && after.world.standardOutput == [2] &&
      after.world.standardError == [3] && after.world.calls.isEmpty do
    throw (IO.userError "cast lost its result, fresh call cells or caller frame")
  match after.i32ArrayViews with
  | [view] =>
    unless view.address == 64 && view.root == 1 && view.projections.isEmpty && view.length == 1 do
      throw (IO.userError "cast changed caller native view")
  | _ => throw (IO.userError "cast lost caller native view")
  IO.println "actual pure cast fixtures: fresh call cells, shadow lookup and heap/world/views preserved"

#eval do
  for (expression, expected) in [
      (falseCallsOr, false), (.binary .logicalOr (echoCall true) (.call 999 []), true)] do
    let .done value after := evalExpr 100 calls castInitial expression
      | throw (IO.userError "actual OR guard failed")
    unless value == Value.boolean expected && after.nextCell > castInitial.nextCell &&
        after.locals == castInitial.locals && after.local? 9 == some (Value.signed .i32 91) &&
        after.cell? 1 == some (Value.array [.signed .i32 5]) &&
        (after.heap.loadBytes 64 4).toOption == some [5, 0, 0, 0] &&
        after.heap.nextAddress == castInitial.heap.nextAddress &&
        after.world.standardInput == [1] && after.world.standardOutput == [2] &&
        after.world.standardError == [3] && after.world.calls.isEmpty do
      throw (IO.userError "OR guard lost its Boolean result or caller frame")
    match after.i32ArrayViews with
    | [view] =>
      unless view.address == 64 && view.root == 1 && view.projections.isEmpty && view.length == 1 do
        throw (IO.userError "OR guard changed caller native view")
    | _ => throw (IO.userError "OR guard lost caller native view")
  IO.println "actual OR guard fixtures: false calls compose fresh frames, true skips missing call"

end Lanius.Semantics
