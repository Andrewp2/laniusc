import Lanius.Semantics.ExpressionProof
import Lanius.Semantics.StmtList
import Lanius.Semantics.AggregateRun

namespace Lanius.Semantics

/-- Compose straight-line statement contracts. Effectful expressions use
    supplied, proved contracts; this does not synthesize heap effects. -/
syntax "core_run" : tactic
syntax "core_stmt" : tactic
syntax "core_arguments" : tactic
syntax "core_stmt_forward" : tactic

/-- Expression evaluation restores lexical bindings; a proved fresh-cell
    frame additionally preserves their values, even across memory effects. -/
@[core_local_rule] theorem RunsExpr.localFound {id : Lanius.VarId}
    (run : RunsExpr program before expression result after)
    (frame : FreshCellFrame before after)
    (found : before.local? id = some value) : after.local? id = some value :=
  frame.localFound run.choose_spec.2 id value found

open Lean Meta Elab Tactic in
/-- Synthesize an expression contract with its input fixed. Its result and
    output state come from proved rules, not the final statement's poststate. -/
private def forwardExpression (program state expression : Expr) (value : Option Expr := none) :
    TacticM Expr := do
  let value ← value.map pure |>.getD (mkFreshExprMVar (mkConst ``Lanius.Core.Value))
  let after ← mkFreshExprMVar (mkConst ``State)
  let target ← mkAppM ``RunsExpr #[program, state, expression, value, after]
  let proof ← mkFreshExprSyntheticOpaqueMVar target
  let remaining ← getGoals
  setGoals [proof.mvarId!]
  try
    evalTactic (← `(tactic| core_run))
  catch error =>
    throwError "forward expression contract failed for {expression.getAppFn}: {error.toMessageData}"
  unless (← getGoals).isEmpty do throwError "expression contract has remaining premises"
  setGoals remaining
  instantiateMVars proof

open Lean Meta Elab Tactic in
/-- Select argument-list rules by syntax, then carry each proved effect
    forward. Trying the empty-list rule on a nonempty fuel-hidden contract
    can otherwise normalize the evaluator while rejecting that rule. Known
    requested values guide synthesis; the actual head output carries effects. -/
private partial def forwardArguments (program state expressions : Expr)
    (values : Option Expr := none) : TacticM Expr := do
  let expressions ← whnf expressions
  if expressions.isAppOfArity ``List.nil 1 then
    return ← mkAppOptM ``RunsExprs.nil #[some program, some state]
  let #[_, head, tail] := expressions.getAppArgs | throwError "expected a concrete argument list"
  unless expressions.isAppOfArity ``List.cons 3 do throwError "expected a concrete argument list"
  let requested ← match values with
    | some values => do
        let values ← whnf values
        pure (if values.isAppOfArity ``List.cons 3 then some values.getAppArgs else none)
    | none => pure none
  let headRun ← forwardExpression program state head (requested.map fun args => args[1]!)
  let headType ← inferType headRun
  let tailRun ← forwardArguments program headType.getAppArgs[4]! tail
    (requested.map fun args => args[2]!)
  mkAppM ``RunsExprs.cons #[headRun, tailRun]

open Lean Meta Elab Tactic in
elab "core_arguments_forward" : tactic => withMainContext do
  let goal ← getMainGoal
  let target := (← instantiateMVars (← goal.getType)).consumeMData
  unless target.isAppOfArity ``RunsExprs 5 do throwError "expected argument contract"
  let run ← forwardArguments target.getAppArgs[0]! target.getAppArgs[1]! target.getAppArgs[2]!
    (some target.getAppArgs[3]!)
  unless ← isDefEq (← inferType run) target do throwError "argument result differs from the requested postcondition"
  goal.assign run
  replaceMainGoal (← getGoals).tail

open Lean Meta Elab Tactic in
/-- Follow actual statement order. Every edge is a proved semantic rule or
    a supplied contract; this does not execute the program or a validator. -/
private partial def forwardStatement (program state statement : Expr) : TacticM Expr := do
  -- Reuse a supplied contract even when its statement has concrete syntax.
  let saved ← saveState
  let completion ← mkFreshExprMVar (mkConst ``Completion)
  let after ← mkFreshExprMVar (mkConst ``State)
  let target ← mkAppM ``RunsStmt #[program, state, statement, completion, after]
  let proof ← mkFreshExprSyntheticOpaqueMVar target
  let remaining ← getGoals
  setGoals [proof.mvarId!]
  try
    evalTactic (← `(tactic| core_contract))
    unless (← getGoals).isEmpty do throwError "statement contract has remaining premises"
    setGoals remaining
    return ← instantiateMVars proof
  catch _ => saved.restore
  let statement ← whnf statement
  match statement.getAppFn.constName? with
  | some ``Lanius.Core.Stmt.skip => mkAppM ``RunsStmt.skip #[program, state]
  | some ``Lanius.Core.Stmt.expression =>
      let run ← forwardExpression program state statement.getAppArgs[0]!
      mkAppM ``RunsStmt.expression #[run]
  | some ``Lanius.Core.Stmt.returnValue =>
      let argument ← whnf statement.getAppArgs[0]!
      unless argument.isAppOfArity ``Option.some 2 do throwError "return requires a value"
      let run ← forwardExpression program state argument.getAppArgs[1]!
      mkAppM ``RunsStmt.returnValue #[run]
  | some ``Lanius.Core.Stmt.letLocal =>
      let #[id, type, initial, body] := statement.getAppArgs | throwError "local statement shape"
      let initialRun ← forwardExpression program state initial
      let initialType ← inferType initialRun
      let value := initialType.getAppArgs[3]!
      let ready := initialType.getAppArgs[4]!
      let bound ← mkAppM ``State.bindLocal #[ready, id, value]
      let bodyRun ← forwardStatement program bound body
      mkAppOptM ``RunsStmt.letLocal #[some program, some state, some id, some type,
        some initial, some body, none, none, none, none, some initialRun, some bodyRun]
  | some ``Lanius.Core.Stmt.sequence =>
      let #[first, second] := statement.getAppArgs | throwError "sequence statement shape"
      let firstRun ← forwardStatement program state first
      let firstType ← inferType firstRun
      let completion ← whnf firstType.getAppArgs[3]!
      if completion.isConstOf ``Completion.next then
        let rest ← forwardStatement program firstType.getAppArgs[4]! second
        mkAppM ``RunsStmt.sequenceNext #[firstRun, rest]
      else
        let inequality ← mkAppM ``Ne #[completion, mkConst ``Completion.next]
        let notNext ← Term.elabTerm (← `(by simp)) (some inequality)
        mkAppM ``RunsStmt.sequenceCompleted #[firstRun, notNext, second]
  | some ``Lanius.Core.Stmt.ifThenElse =>
      let #[condition, yes, no] := statement.getAppArgs | throwError "conditional statement shape"
      let saved ← saveState
      let (guard, branchStmt, rule) ← try
        let falseValue ← mkAppM ``Lanius.Core.Value.boolean #[mkConst ``Bool.false]
        let guard ← forwardExpression program state condition (some falseValue)
        pure (guard, no, ``RunsStmt.ifThenElseFalse)
      catch _ =>
        saved.restore
        let trueValue ← mkAppM ``Lanius.Core.Value.boolean #[mkConst ``Bool.true]
        let guard ← forwardExpression program state condition (some trueValue)
        pure (guard, yes, ``RunsStmt.ifThenElseTrue)
      let guardType ← inferType guard
      let branch ← forwardStatement program guardType.getAppArgs[4]! branchStmt
      mkAppOptM rule #[some program, some state, some condition, none, some yes, some no,
        none, none, some guard, some branch]
  | _ => throwError "statement requires a supplied contract"

open Lean Meta Elab Tactic in
elab "core_stmt_forward" : tactic => withMainContext do
  let goal ← getMainGoal
  let target := (← instantiateMVars (← goal.getType)).consumeMData
  unless target.isAppOfArity ``RunsStmt 5 do throwError "expected statement contract"
  let run ← try
    forwardStatement target.getAppArgs[0]! target.getAppArgs[1]! target.getAppArgs[2]!
  catch error =>
    throwError "forward statement composition failed: {error.toMessageData}"
  unless ← isDefEq (← inferType run) target do throwError "forward result differs from the requested postcondition"
  goal.assign run
  replaceMainGoal (← getGoals).tail

open Lean Meta Elab Tactic in
elab "core_aggregate_run" : tactic => withMainContext do
  let target := (← instantiateMVars (← (← getMainGoal).getType)).consumeMData
  unless target.isAppOfArity ``RunsExpr 5 do throwError "expected expression contract"
  let expression ← whnf target.getAppArgs[2]!
  let rule ← match expression.getAppFn.constName? with
    | some ``Lanius.Core.Expr.structValue => `(tactic|
        (apply RunsExpr.structValue; core_arguments))
    | some ``Lanius.Core.Expr.enumValue => `(tactic|
        (apply RunsExpr.enumValue; core_arguments))
    | some ``Lanius.Core.Expr.call => `(tactic|
        (apply RunsExpr.callArguments <;> first | core_contract | core_arguments))
    | some ``Lanius.Core.Expr.field => `(tactic|
        (apply RunsExpr.field <;> first | core_run | rfl))
    | some ``Lanius.Core.Expr.unary => `(tactic|
        (apply RunsExpr.unary <;> first | core_run | core_scalar))
    | some ``Lanius.Core.Expr.binary =>
        if expression.getAppArgs[0]!.isConstOf ``Lanius.Core.BinaryOp.logicalOr then
          `(tactic| (apply RunsExpr.logicalOrFalse <;> core_run))
        else if expression.getAppArgs[0]!.isConstOf ``Lanius.Core.BinaryOp.logicalAnd then
          throwError "short-circuit expression"
        else `(tactic| (apply RunsExpr.binary <;> first
          | core_run | (solve | simp) | core_scalar))
    | _ => throwError "not a record expression"
  evalTactic rule

open Lean Meta Elab Tactic in
elab "core_stmt_node" : tactic => withMainContext do
  let target := (← instantiateMVars (← (← getMainGoal).getType)).consumeMData
  unless target.isAppOfArity ``RunsStmt 5 do throwError "expected statement contract"
  let statement ← whnf target.getAppArgs[2]!
  let rule ← match statement.getAppFn.constName? with
    | some ``Lanius.Core.Stmt.skip => `(tactic| exact RunsStmt.skip _ _)
    | some ``Lanius.Core.Stmt.returnValue => `(tactic| (apply RunsStmt.returnValue; core_run))
    | some ``Lanius.Core.Stmt.expression => `(tactic| (apply RunsStmt.expression; core_run))
    | some ``Lanius.Core.Stmt.letLocal =>
        if target.getAppArgs[4]!.isAppOf ``restoreLocals then
          `(tactic| (apply RunsStmt.letLocal; core_run; core_stmt))
        else `(tactic| apply RunsStmt.letLocalFrame <;> first | core_run | core_stmt | rfl)
    | some ``Lanius.Core.Stmt.sequence => `(tactic| first
        | (apply RunsStmt.sequenceCompleted; rotate_left; (solve | simp); core_stmt)
        | (apply RunsStmt.sequenceNext <;> core_stmt))
    | some ``Lanius.Core.Stmt.ifThenElse => `(tactic| first
        | (apply RunsStmt.ifThenElseFalse <;> first | core_run | core_stmt)
        | (apply RunsStmt.ifThenElseTrue <;> first | core_run | core_stmt))
    | _ => throwError "statement requires a supplied contract"
  evalTactic rule

open Lean Meta Elab Tactic in
/-- Keep tactic alternatives inside their own relation. Failed application
    across two fuel-hidden contracts must not unfold either evaluator. -/
private def requireRelation (relation : Name) : TacticM Unit := withMainContext do
  let target := (← instantiateMVars (← (← getMainGoal).getType)).consumeMData
  unless target.getAppFn.isConstOf relation do throwError "expected {relation} contract"

open Lean Elab Tactic in
elab "core_run_goal" : tactic => requireRelation ``RunsExpr

open Lean Elab Tactic in
elab "core_arguments_goal" : tactic => requireRelation ``RunsExprs

open Lean Elab Tactic in
elab "core_stmt_goal" : tactic => requireRelation ``RunsStmt

macro_rules
  | `(tactic| core_arguments) => `(tactic|
      core_arguments_goal;
      first | core_contract | core_arguments_forward)
  | `(tactic| core_run) => `(tactic|
      core_run_goal;
      first
      | core_contract
      | core_aggregate_run
      | (apply RunsExpr.ofStable <;> first | core_expr_step | core_guard_step | rfl))
  | `(tactic| core_stmt) => `(tactic|
      core_stmt_goal;
      first | core_contract | core_stmt_forward | core_stmt_node)

end Lanius.Semantics
