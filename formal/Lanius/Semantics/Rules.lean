import Lanius.Semantics

namespace Lanius.Semantics

open Lanius
open Lanius.Core

/-! Small compositional rules for the executable Core evaluator.

These rules deliberately expose only the evaluator shapes needed by a phase
proof.  They do not impose a global state invariant, hide fuel in a public
statement, or unfold the whole mutual evaluator through simplification.
-/

theorem evalExpr_value
    (fuel : Nat) (program : Program) (state : State) (value : Value) :
    evalExpr fuel.succ program state (.value value) = .done value state := by
  rw [evalExpr.eq_def]

theorem evalExpr_local_of_local?
    (fuel : Nat) (program : Program) (state : State)
    (id : VarId) (value : Value)
    (localFound : state.local? id = some value) :
    evalExpr fuel.succ program state (.local id) = .done value state := by
  rw [evalExpr.eq_def]
  unfold State.local? at localFound
  cases idFound : state.cellId? id with
  | none => simp [idFound] at localFound
  | some cell =>
    cases valueFound : state.cellEntry? cell with
    | none => simp [idFound, State.cell?, valueFound] at localFound
    | some entry =>
      cases entry with
      | mk entryId entryValue =>
        cases entryValue with
        | none => simp [idFound, State.cell?, valueFound] at localFound
        | some entryValue =>
          simp_all [State.cell?]

def signedComparison (operation : BinaryOp) (left right : Int) : Bool :=
  match operation with
  | .less => left < right
  | .lessEqual => left <= right
  | .greater => left > right
  | .greaterEqual => left >= right
  | _ => false

theorem evalBinaryValue_signed_comparison
    (target : Target) (operation : BinaryOp) (type : SignedIntTy)
    (left right : Int)
    (operationIsComparison :
      operation = .less ∨ operation = .lessEqual ∨
      operation = .greater ∨ operation = .greaterEqual) :
    evalBinaryValue target operation (.signed type left) (.signed type right) =
      .ok (.boolean (signedComparison operation left right)) := by
  rcases operationIsComparison with rfl | rfl | rfl | rfl <;>
    simp only [evalBinaryValue, evalSignedBinary, signedComparison] <;> simp

theorem evalBinaryValue_signed_equal
    (target : Target) (type : SignedIntTy) (left right : Int) :
    evalBinaryValue target .equal (.signed type left) (.signed type right) =
      .ok (.boolean (left == right)) := by
  simp [evalBinaryValue, scalarEqual]

theorem evalExpr_binary_done
    (fuel : Nat) (program : Program) (state : State)
    (operation : BinaryOp) (left right : Expr)
    (leftValue rightValue result : Value) (afterLeft afterRight : State)
    (leftEvaluates : evalExpr fuel program state left = .done leftValue afterLeft)
    (rightEvaluates : evalExpr fuel program afterLeft right =
      .done rightValue afterRight)
    (operationIsEager : operation ≠ .logicalAnd ∧ operation ≠ .logicalOr)
    (operationEvaluates :
      evalBinaryValue program.target operation leftValue rightValue = .ok result) :
    evalExpr fuel.succ program state (.binary operation left right) =
      .done result afterRight := by
  rw [evalExpr.eq_def]
  dsimp only
  cases operation
  case logicalAnd => exact (operationIsEager.1 rfl).elim
  case logicalOr => exact (operationIsEager.2 rfl).elim
  all_goals
    dsimp only
    simp only [leftEvaluates, rightEvaluates, operationEvaluates]

theorem evalExpr_logicalAnd_booleans
    (fuel : Nat) (program : Program) (state : State)
    (left right : Expr) (leftBool rightBool : Bool)
    (leftEvaluates : evalExpr fuel program state left =
      .done (.boolean leftBool) state)
    (rightEvaluates : evalExpr fuel program state right =
      .done (.boolean rightBool) state) :
    evalExpr fuel.succ program state (.binary .logicalAnd left right) =
      .done (.boolean (leftBool && rightBool)) state := by
  rw [evalExpr.eq_def]
  dsimp only
  simp only [leftEvaluates]
  cases leftBool <;> simp only [Bool.false_and, Bool.true_and, rightEvaluates]


theorem evalExpr_logicalOr_booleans
    (fuel : Nat) (program : Program) (state : State)
    (left right : Expr) (leftBool rightBool : Bool)
    (leftEvaluates : evalExpr fuel program state left =
      .done (.boolean leftBool) state)
    (rightEvaluates : evalExpr fuel program state right =
      .done (.boolean rightBool) state) :
    evalExpr fuel.succ program state (.binary .logicalOr left right) =
      .done (.boolean (leftBool || rightBool)) state := by
  rw [evalExpr.eq_def]
  dsimp only
  simp only [leftEvaluates]
  cases leftBool <;> simp only [Bool.false_or, Bool.true_or, rightEvaluates]

theorem evalExpr_logicalOr_true
    (fuel : Nat) (program : Program) (state : State)
    (left right : Expr) (afterLeft : State)
    (leftEvaluates : evalExpr fuel program state left =
      .done (.boolean true) afterLeft) :
    evalExpr fuel.succ program state (.binary .logicalOr left right) =
      .done (.boolean true) afterLeft := by
  rw [evalExpr.eq_def]
  dsimp only
  simp only [leftEvaluates]

theorem evalExpr_logicalOr_false
    (fuel : Nat) (program : Program) (state : State)
    (left right : Expr) (rightValue : Value) (afterLeft afterRight : State)
    (leftEvaluates : evalExpr fuel program state left =
      .done (.boolean false) afterLeft)
    (rightEvaluates : evalExpr fuel program afterLeft right =
      .done rightValue afterRight) :
    evalExpr fuel.succ program state (.binary .logicalOr left right) =
      .done rightValue afterRight := by
  rw [evalExpr.eq_def]
  dsimp only
  simp only [leftEvaluates, rightEvaluates]

theorem evalExprs_single_value
    (fuel : Nat) (program : Program) (state : State)
    (expression : Expr) (value : Value) (after : State)
    (evaluates : evalExpr fuel.succ program state expression =
      .done value after) :
    evalExprs fuel.succ.succ program state [expression] =
      .done [value] after := by
  rw [evalExprs.eq_def]
  dsimp only
  simp only [evaluates]
  rw [evalExprs.eq_def]

theorem execStmt_sequence_completed
    (fuel : Nat) (program : Program) (state : State)
    (first second : Stmt) (completion : Completion) (after : State)
    (firstEvaluates : execStmt fuel program state first =
      .done completion after)
    (notNext : completion ≠ .next) :
    execStmt fuel.succ program state (.sequence first second) =
      .done completion after := by
  rw [execStmt.eq_def]
  simp only [firstEvaluates]

theorem execStmt_return
    (fuel : Nat) (program : Program) (state : State)
    (expression : Expr) (value : Value) (after : State)
    (evaluates : evalExpr fuel program state expression = .done value after) :
    execStmt fuel.succ program state (.returnValue (some expression)) =
      .done (.returned (some value)) after := by
  simp only [execStmt.eq_def, evaluates]

theorem evalExpr_call_internal
    (fuel : Nat) (program : Program) (caller : State)
    (functionId : FunctionId) (arguments : List Expr)
    (function : Function) (body : Stmt) (values : List Value)
    (bindings : List (VarId × Value))
    (afterArguments completed : State) (value : Value)
    (functionFound : program.function? functionId = some function)
    (bodyFound : function.body = some body)
    (argumentsEvaluate :
      evalExprs fuel program caller arguments = .done values afterArguments)
    (parametersBind : bindParameters function.parameters values = some bindings)
    (bodyEvaluates :
      execStmt fuel program
        (({ afterArguments with locals := [] }).bindLocals bindings)
        body = .done (.returned (some value)) completed) :
    evalExpr fuel.succ program caller (.call functionId arguments) =
      .done value (restoreLocals afterArguments completed) := by
  simp only [evalExpr.eq_def, argumentsEvaluate, functionFound, bodyFound, parametersBind,
    bodyEvaluates]

end Lanius.Semantics
