import Lanius.Semantics.Assignment
import Lanius.Semantics.Branch

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

theorem RunsExpr.ofStable {threshold : Nat}
    (contract : StableExpr threshold program state expression value after)
    (locals : after.locals = state.locals) :
    RunsExpr program state expression value after :=
  ⟨threshold, contract, locals⟩

theorem RunsStmt.ofStable {threshold : Nat}
    (contract : StableStmt threshold program state statement completion after)
    (locals : after.locals = state.locals) :
    RunsStmt program state statement completion after :=
  ⟨threshold, contract, locals⟩

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
