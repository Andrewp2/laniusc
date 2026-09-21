import Lean.Elab.Tactic.Omega
import Lanius.Compiler.Lexer
import Lanius.Semantics.Stable

namespace Lanius.Compiler.Lexer

open Lanius Lanius.Core Lanius.Semantics

inductive UnaryI32Op where
  | equal
  | greaterEqual
  | lessEqual
deriving DecidableEq, Repr

def UnaryI32Op.core : UnaryI32Op → BinaryOp
  | .equal => .equal
  | .greaterEqual => .greaterEqual
  | .lessEqual => .lessEqual

def UnaryI32Op.accepts (op : UnaryI32Op) (input constant : Int) : Bool :=
  match op with
  | .equal => input == constant
  | .greaterEqual => constant ≤ input
  | .lessEqual => input ≤ constant

inductive UnaryI32Predicate where
  | atom (op : UnaryI32Op) (constant : Int)
  | and (left right : UnaryI32Predicate)
  | or (left right : UnaryI32Predicate)
deriving Repr

def UnaryI32Predicate.accepts : UnaryI32Predicate → Int → Bool
  | .atom op constant => fun input => op.accepts input constant
  | .and left right => fun input => left.accepts input && right.accepts input
  | .or left right => fun input => left.accepts input || right.accepts input

def UnaryI32Predicate.compile (parameter : VarId) : UnaryI32Predicate → Expr
  | .atom op constant =>
      .binary op.core (.local parameter) (.value (.signed .i32 constant))
  | .and left right =>
      .binary .logicalAnd (left.compile parameter) (right.compile parameter)
  | .or left right =>
      .binary .logicalOr (left.compile parameter) (right.compile parameter)

def UnaryI32Predicate.exprFuel : UnaryI32Predicate → Nat
  | .atom _ _ => 2
  | .and left right | .or left right =>
      max left.exprFuel right.exprFuel + 1

private theorem evalUnaryI32Op (program : Program) (op : UnaryI32Op) (input constant : Int) :
    evalBinaryValue program.target op.core (.signed .i32 input) (.signed .i32 constant) =
      .ok (.boolean (op.accepts input constant)) := by
  cases op <;> simp [UnaryI32Op.core, UnaryI32Op.accepts, evalBinaryValue_signed_equal,
    evalBinaryValue_signed_comparison, signedComparison]

def unaryI32PredicateFunction
    (functionId parameter : Nat) (predicate : UnaryI32Predicate) : Function :=
  { id := functionId
    parameters := [(parameter, .scalar (.signed .i32))]
    returnType := .scalar .bool
    body := some (.sequence
      (.returnValue (some (predicate.compile parameter))) .skip)
    external := none }

def unaryI32PredicateCall (functionId : FunctionId) (input : Int) : Expr :=
  .call functionId [.value (.signed .i32 input)]

theorem evalExpr_unaryI32Predicate (predicate : UnaryI32Predicate) (fuel : Nat)
    (fuelEnough : predicate.exprFuel ≤ fuel) (program : Program) (state : State)
    (parameter : VarId) (input : Int)
    (localFound : state.local? parameter = some (.signed .i32 input)) :
    evalExpr fuel program state (predicate.compile parameter) = .done (.boolean (predicate.accepts input)) state := by
  induction predicate generalizing fuel with
  | atom op constant =>
      have fuelEnough' : 2 ≤ fuel := by
        simpa [UnaryI32Predicate.exprFuel] using fuelEnough
      have localEvaluates := by simpa [show fuel - 2 + 1 = fuel - 1 by omega] using
        (evalExpr_local_of_local? (fuel - 2) program state parameter (.signed .i32 input) localFound)
      have valueEvaluates := by simpa [show fuel - 2 + 1 = fuel - 1 by omega] using
        (evalExpr_value (fuel - 2) program state (.signed .i32 constant))
      have operationEvaluates := evalUnaryI32Op program op input constant
      simpa [UnaryI32Predicate.compile, UnaryI32Predicate.accepts,
        show fuel - 1 + 1 = fuel by omega] using (evalExpr_binary_done (fuel := fuel - 1) program state
          op.core (.local parameter) (.value (.signed .i32 constant)) (.signed .i32 input)
          (.signed .i32 constant) (.boolean (op.accepts input constant)) state state
          localEvaluates valueEvaluates (by cases op <;> simp [UnaryI32Op.core]) operationEvaluates)
  | and left right ihLeft ihRight
  | or left right ihLeft ihRight =>
      have enough : max left.exprFuel right.exprFuel + 1 ≤ fuel := by simpa [UnaryI32Predicate.exprFuel] using fuelEnough
      have leftEvaluates := ihLeft (fuel - 1) (by omega)
      have rightEvaluates := ihRight (fuel - 1) (by omega)
      first
      | simpa [UnaryI32Predicate.compile, UnaryI32Predicate.accepts, show fuel - 1 + 1 = fuel by omega] using
          (evalExpr_logicalAnd_booleans (fuel := fuel - 1) program state (left.compile parameter)
            (right.compile parameter) (left.accepts input) (right.accepts input) leftEvaluates rightEvaluates)
      | simpa [UnaryI32Predicate.compile, UnaryI32Predicate.accepts, show fuel - 1 + 1 = fuel by omega] using
          (evalExpr_logicalOr_booleans (fuel := fuel - 1) program state (left.compile parameter)
            (right.compile parameter) (left.accepts input) (right.accepts input) leftEvaluates rightEvaluates)

theorem evalExpr_unaryI32PredicateCall_of_fuel (fuel : Nat) (program : Program) (caller : State)
    (functionId parameter : Nat) (predicate : UnaryI32Predicate) (argument : Expr) (input : Int)
    (functionFound : program.function? functionId = some (unaryI32PredicateFunction functionId parameter predicate))
    (callerFormed : caller.CellsWellFormed) (fuelEnough : predicate.exprFuel + 3 ≤ fuel)
    (argumentEvaluates : evalExpr (fuel - 2) program caller argument = .done (.signed .i32 input) caller) :
    evalExpr fuel program caller (.call functionId [argument]) = .done (.boolean (predicate.accepts input))
      (restoreLocals caller (({ caller with locals := [] }).bindLocal parameter (.signed .i32 input))) := by
  let argumentValue : Value := .signed .i32 input
  let callee : State := ({ caller with locals := [] }).bindLocal parameter argumentValue
  have clearedFormed : ({ caller with locals := [] }).CellsWellFormed :=
    callerFormed
  have argumentExecution : evalExprs (fuel - 1) program caller [argument] =
      .done [argumentValue] caller := by
    simpa [show fuel - 3 + 2 = fuel - 1 by omega] using
      (evalExprs_single_value (fuel := fuel - 3) program caller argument
        argumentValue caller (by
          simpa [show fuel - 3 + 1 = fuel - 2 by omega, argumentValue] using
            argumentEvaluates))
  have bodyExpression := evalExpr_unaryI32Predicate predicate (fuel - 3) (by omega)
    program callee parameter input (by simpa [callee, argumentValue] using
      (clearedFormed.bindLocal_local parameter argumentValue))
  have bodyExecution : execStmt (fuel - 1) program callee
      (.sequence (.returnValue (some (predicate.compile parameter))) .skip) =
      .done (.returned (some (.boolean (predicate.accepts input)))) callee := by
    simpa [show fuel - 2 + 1 = fuel - 1 by omega] using
      (execStmt_sequence_completed (fuel := fuel - 2) program callee
        (.returnValue (some (predicate.compile parameter))) .skip
        (.returned (some (.boolean (predicate.accepts input)))) callee
        (by simpa [show fuel - 3 + 1 = fuel - 2 by omega] using
          (execStmt_return (fuel := fuel - 3) program callee
            (predicate.compile parameter) (.boolean (predicate.accepts input)) callee
            bodyExpression)) (by simp))
  simpa [callee, argumentValue, show fuel - 1 + 1 = fuel by omega] using
    (evalExpr_call_internal (fuel := fuel - 1) program caller functionId [argument]
      (unaryI32PredicateFunction functionId parameter predicate)
      (.sequence (.returnValue (some (predicate.compile parameter))) .skip)
      [argumentValue] [(parameter, argumentValue)] caller callee
      (.boolean (predicate.accepts input)) functionFound rfl argumentExecution rfl bodyExecution)

theorem purelyEvaluates_unaryI32PredicateCall
    (program : Program) (caller : State)
    (functionId parameter : Nat) (predicate : UnaryI32Predicate) (input : Int)
    (functionFound :
      program.function? functionId =
        some (unaryI32PredicateFunction functionId parameter predicate))
    (callerFormed : caller.CellsWellFormed) :
    PurelyEvaluates program caller (unaryI32PredicateCall functionId input)
      (.boolean (predicate.accepts input)) := by
  refine ThresholdPure.erase (fuelThreshold := predicate.exprFuel + 3)
    (after := restoreLocals caller
      (({ caller with locals := [] }).bindLocal parameter (.signed .i32 input)))
    ⟨?_, ?_⟩
  · intro fuel enough
    simpa [unaryI32PredicateCall] using
      (evalExpr_unaryI32PredicateCall_of_fuel fuel program caller functionId
        parameter predicate (.value (.signed .i32 input)) input functionFound
        callerFormed enough
        (by simpa [show fuel - 3 + 1 = fuel - 2 by omega] using
          (evalExpr_value (fuel - 3) program caller (.signed .i32 input))))
  · refine ⟨callerFormed, ?_, rfl, rfl, rfl, rfl⟩
    change FreshCellFrame caller (caller.bindLocal parameter (.signed .i32 input))
    exact FreshCellFrame.bindLocal caller parameter (.signed .i32 input)

end Lanius.Compiler.Lexer
