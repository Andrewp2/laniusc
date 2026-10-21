import Lanius.Semantics.Assignment
import Lanius.Semantics.Branch
import Lanius.Semantics.LexicalFrame
import Lanius.Semantics.Allocation

namespace Lanius.Semantics

open Lanius Lanius.Core

/-! Fuel-hidden contracts for small statement fragments.  The existential
    threshold is intentionally kept at this boundary: callers compose Core
    statements without carrying max/+1 arithmetic through their proofs. -/

def RunsExpr (program : Program) (state : State) (expression : Expr)
    (value : Value) (after : State) : Prop :=
  ∃ threshold, StableExpr threshold program state expression value after ∧
    after.locals = state.locals

def RunsStmt (program : Program) (state : State) (statement : Stmt)
    (completion : Completion) (after : State) : Prop :=
  ∃ threshold, StableStmt threshold program state statement completion after ∧
    after.locals = state.locals

theorem RunsExpr.ofEval (run : evalExpr fuel program state expression = .done value after) :
    RunsExpr program state expression value after :=
  ⟨fuel, .ofEval run, evalExpr_locals run⟩

theorem RunsStmt.ofExec (run : execStmt fuel program state statement = .done completion after) :
    RunsStmt program state statement completion after :=
  ⟨fuel, .ofExec run, execStmt_locals run⟩

/-- Finite successful execution already contains the lexical-frame guarantee. -/
theorem Evaluates.runs (run : Evaluates program state expression value after) :
    RunsExpr program state expression value after := by
  obtain ⟨_, run⟩ := run
  exact .ofEval run

theorem Executes.runs (run : Executes program state statement completion after) :
    RunsStmt program state statement completion after := by
  obtain ⟨_, run⟩ := run
  exact .ofExec run

theorem RunsExpr.evaluates (run : RunsExpr program state expression value after) :
    Evaluates program state expression value after := by
  obtain ⟨fuel, stable, _⟩ := run
  exact ⟨fuel, stable fuel (Nat.le_refl _)⟩

theorem RunsStmt.executes (run : RunsStmt program state statement completion after) :
    Executes program state statement completion after := by
  obtain ⟨fuel, stable, _⟩ := run
  exact ⟨fuel, stable fuel (Nat.le_refl _)⟩

theorem RunsExpr.inventory (run : RunsExpr program state expression value after) :
    state.cellInventory.Extends after.cellInventory := run.evaluates.inventory

theorem RunsStmt.inventory (run : RunsStmt program state statement completion after) :
    state.cellInventory.Extends after.cellInventory := run.executes.inventory

theorem RunsExpr.cellsWellFormed (run : RunsExpr program state expression value after)
    (formed : state.CellsWellFormed) : after.CellsWellFormed := run.inventory.cellsWellFormed formed

theorem RunsStmt.cellsWellFormed (run : RunsStmt program state statement completion after)
    (formed : state.CellsWellFormed) : after.CellsWellFormed := run.inventory.cellsWellFormed formed

/-- Two total contracts for the same computation agree. This compares their
    proved executions at a common fuel; it does not evaluate the program. -/
theorem RunsExpr.agree (left : RunsExpr program state expression value after)
    (right : RunsExpr program state expression other completed) :
    value = other ∧ after = completed := left.evaluates.unique right.evaluates

theorem RunsExpr.ofStable {threshold : Nat}
    (contract : StableExpr threshold program state expression value after)
    (locals : after.locals = state.locals) :
    RunsExpr program state expression value after :=
  ⟨threshold, contract, locals⟩

theorem RunsExpr.binary
    (left : RunsExpr program before leftExpression leftValue middle)
    (right : RunsExpr program middle rightExpression rightValue after)
    (eager : operation ≠ .logicalAnd ∧ operation ≠ .logicalOr)
    (evaluates : evalBinaryValue program.target operation leftValue rightValue = .ok result) :
    RunsExpr program before (.binary operation leftExpression rightExpression) result after := by
  obtain ⟨_, left, leftLocals⟩ := left
  obtain ⟨_, right, rightLocals⟩ := right
  exact .ofStable (StableExpr.binary left right eager evaluates) (rightLocals.trans leftLocals)

theorem RunsStmt.ofStable {threshold : Nat}
    (contract : StableStmt threshold program state statement completion after)
    (locals : after.locals = state.locals) :
    RunsStmt program state statement completion after :=
  ⟨threshold, contract, locals⟩

theorem RunsExpr.unary
    (operand : RunsExpr program before expression value after)
    (operation : evalUnaryValue program.target operator value = .ok result) :
    RunsExpr program before (.unary operator expression) result after :=
  .ofStable (StableExpr.unary operand.choose_spec.1 operation) operand.choose_spec.2

/-- The right operand may write memory; short-circuiting only determines
    whether it runs, not whether its effects can be discarded. -/
theorem RunsExpr.logicalOrFalse
    (left : RunsExpr program before leftExpr (.boolean false) middle)
    (right : RunsExpr program middle rightExpr value after) :
    RunsExpr program before (.binary .logicalOr leftExpr rightExpr) value after := by
  obtain ⟨leftFuel, left, leftLocals⟩ := left
  obtain ⟨rightFuel, right, rightLocals⟩ := right
  refine ⟨max leftFuel rightFuel + 1, ?_, rightLocals.trans leftLocals⟩
  intro fuel enough
  simpa only [show (fuel - 1).succ = fuel by omega] using
    evalExpr_logicalOr_false (fuel - 1) program before leftExpr rightExpr value middle after
      (left (fuel - 1) (by omega)) (right (fuel - 1) (by omega))

theorem RunsStmt.skip (program : Program) (state : State) :
    RunsStmt program state .skip .next state :=
  .ofStable (StableStmt.skip program state) rfl

theorem RunsStmt.expression
    {expression : Expr} {value : Value}
    (run : RunsExpr program state expression value after) :
    RunsStmt program state (.expression expression) .next after := by
  obtain ⟨fuel, run, locals⟩ := run
  exact ⟨fuel + 1, StableStmt.expression run, locals⟩

theorem RunsStmt.ifThenElseTrue
    {conditionExpr : Expr} {conditionAfter : State} {thenBranch elseBranch : Stmt}
    {completion : Completion} {after : State}
    (condition : RunsExpr program state conditionExpr (.boolean true) conditionAfter)
    (branch : RunsStmt program conditionAfter thenBranch completion after) :
    RunsStmt program state (.ifThenElse conditionExpr thenBranch elseBranch) completion after := by
  obtain ⟨conditionFuel, conditionRun, conditionLocals⟩ := condition
  obtain ⟨branchFuel, branchRun, branchLocals⟩ := branch
  exact ⟨max conditionFuel branchFuel + 1,
    StableStmt.ifThenElse_true conditionRun branchRun, branchLocals.trans conditionLocals⟩

theorem RunsStmt.ifThenElseFalse
    {conditionExpr : Expr} {conditionAfter : State} {thenBranch elseBranch : Stmt}
    {completion : Completion} {after : State}
    (condition : RunsExpr program state conditionExpr (.boolean false) conditionAfter)
    (branch : RunsStmt program conditionAfter elseBranch completion after) :
    RunsStmt program state (.ifThenElse conditionExpr thenBranch elseBranch) completion after := by
  obtain ⟨conditionFuel, conditionRun, conditionLocals⟩ := condition
  obtain ⟨branchFuel, branchRun, branchLocals⟩ := branch
  exact ⟨max conditionFuel branchFuel + 1,
    StableStmt.ifThenElse_false conditionRun branchRun, branchLocals.trans conditionLocals⟩

theorem RunsStmt.letLocal
    {id : VarId} {type : Ty} {initializer : Expr} {bodyStmt : Stmt}
    {value : Value} {afterInit afterBody : State} {completion : Completion}
    (initRun : RunsExpr program state initializer value afterInit)
    (bodyRunContract : RunsStmt program (afterInit.bindLocal id value)
      bodyStmt completion afterBody) :
    RunsStmt program state (.letLocal id type initializer bodyStmt) completion
      (restoreLocals afterInit afterBody) := by
  obtain ⟨initializerFuel, initializerRun, initializerLocals⟩ := initRun
  obtain ⟨bodyFuel, bodyRun, _bodyLocals⟩ := bodyRunContract
  exact ⟨max initializerFuel bodyFuel + 1,
    StableStmt.letLocal program state id type initializer bodyStmt value afterInit afterBody
      completion initializerRun bodyRun,
    (show (restoreLocals afterInit afterBody).locals = afterInit.locals from rfl).trans initializerLocals⟩

theorem RunsStmt.returnValueSequence
    {argument : Expr} {result : Value}
    (argRun : RunsExpr program state argument result after) :
    RunsStmt program state (.sequence (.returnValue (some argument)) .skip)
      (.returned (some result)) after := by
  obtain ⟨fuel, run, locals⟩ := argRun; exact ⟨fuel + 2, StableStmt.returnValueSequence program state argument result run, locals⟩

/-- Keep the inner local scope explicit when the final state is already known.
    This avoids guessing the body's locals through `restoreLocals`. -/
theorem RunsStmt.letLocalFrame {id : VarId}
    (initRun : RunsExpr program state initializer value afterInit)
    (bodyRun : RunsStmt program (afterInit.bindLocal id value) body completion
      { after with locals := (afterInit.bindLocal id value).locals })
    (locals : after.locals = state.locals) :
    RunsStmt program state (.letLocal id type initializer body) completion after := by
  have result := RunsStmt.letLocal (type := type) initRun bodyRun
  have restored : restoreLocals afterInit
      { after with locals := (afterInit.bindLocal id value).locals } = after := by
    obtain ⟨_, _, initLocals⟩ := initRun
    unfold restoreLocals
    rw [initLocals, ← locals]
  simpa only [restored] using result

theorem RunsStmt.returnValue (run : RunsExpr program state argument result after) :
    RunsStmt program state (.returnValue (some argument)) (.returned (some result)) after := by
  obtain ⟨fuel, run, locals⟩ := run
  exact ⟨fuel + 1, StableStmt.returnValue run, locals⟩

theorem RunsStmt.sequenceNext
    (first : RunsStmt program state firstStmt .next middle)
    (second : RunsStmt program middle secondStmt completion after) :
    RunsStmt program state (.sequence firstStmt secondStmt) completion after := by
  obtain ⟨firstFuel, firstRun, firstLocals⟩ := first
  obtain ⟨secondFuel, secondRun, secondLocals⟩ := second
  exact ⟨max firstFuel secondFuel + 1,
    StableStmt.sequence_next firstRun secondRun, secondLocals.trans firstLocals⟩

theorem RunsStmt.sequenceCompleted
    (first : RunsStmt program state firstStmt completion after)
    (notNext : completion ≠ .next) (second : Stmt) :
    RunsStmt program state (.sequence firstStmt second) completion after := by
  obtain ⟨fuel, run, locals⟩ := first; exact ⟨fuel + 1, StableStmt.sequence_completed run notNext, locals⟩

def Stmt.sequenceList : List Stmt → Stmt
  | [] => .skip
  | first :: rest => .sequence first (Stmt.sequenceList rest)

inductive StmtListRun (program : Program) : State → List Stmt → Completion → State → Prop
  | nil (state : State) : StmtListRun program state [] .next state
  | next {state middle after : State} {first : Stmt} {rest : List Stmt}
      (head : RunsStmt program state first .next middle)
      (tail : StmtListRun program middle rest completion after) :
      StmtListRun program state (first :: rest) completion after
  | completed {state after : State} {first : Stmt} {rest : List Stmt}
      (head : RunsStmt program state first completion after)
      (notNext : completion ≠ .next) :
      StmtListRun program state (first :: rest) completion after

theorem StmtListRun.toRuns
    (contract : StmtListRun program state statements completion after) :
    RunsStmt program state (Stmt.sequenceList statements) completion after := by
  induction contract with
  | nil state => exact RunsStmt.skip program state
  | next head tail ih => exact RunsStmt.sequenceNext head ih
  | completed head notNext =>
      exact RunsStmt.sequenceCompleted head notNext _

theorem StmtListRun.toStable
    (contract : StmtListRun program state statements completion after) :
    ∃ threshold, StableStmt threshold program state
      (Stmt.sequenceList statements) completion after := by
  rcases contract.toRuns with ⟨threshold, run, _⟩; exact ⟨threshold, run⟩

theorem threeStatementEarlyReturn
    {program : Program} {state after : State} {first second third : Stmt}
    {value : Option Value} {fuel : Nat}
    (head : StableStmt fuel program state first (.returned value) after) :
    ∃ threshold, StableStmt threshold program state
      (Stmt.sequenceList [first, second, third]) (.returned value) after := by
  exact ⟨fuel + 1, by simpa [Stmt.sequenceList] using
    StableStmt.sequence_completed head (by simp)⟩

end Lanius.Semantics
