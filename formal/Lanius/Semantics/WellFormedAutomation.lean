import Lanius.Semantics.CallRun
import Lean

namespace Lanius.Semantics

open Lean Meta Elab Tactic

/-- Compare only the two fields used by the frontier invariant. Heap/world or
    scope changes need not match; neither evaluator bodies nor values are run. -/
private def sameInventory (left right : Expr) : MetaM Bool := withTransparency .reducible do
  return (← isDefEq (mkProj ``State 1 left) (mkProj ``State 1 right)) &&
    (← isDefEq (mkProj ``State 2 left) (mkProj ``State 2 right))

private def bindingFormed (known : Array (Expr × Expr)) (state : Expr) : Nat → MetaM (Option Expr)
  | 0 => pure none
  | fuel + 1 => do
    for (other, proof) in known do
      if ← sameInventory state other then return some proof
    let state ← withTransparency .reducible (whnf state)
    for (operation, rule, arity) in [(``State.bindLocal, ``State.CellsWellFormed.bindLocal, 3),
        (``State.bindLocals, ``State.CellsWellFormed.bindLocals, 2),
        (``State.bindCell, ``State.CellsWellFormed.bindCell, 3)] do
      if state.isAppOfArity operation arity then
        if let some proof ← bindingFormed known state.getAppArgs[0]! fuel then
          return some (← mkAppOptM rule
            (#[some state.getAppArgs[0]!, some proof] ++
              (state.getAppArgs.extract 1 arity).map some))
    return none

/-- Forward propagation of the proved allocation law through supplied execution
    contracts. Each contract is used at most once; cycles cannot invent a seed
    invariant. Every result is an ordinary lemma application checked by Lean. -/
elab "core_execution_formed" : tactic => withMainContext do
  let goal ← getMainGoal
  let target ← instantiateMVars (← goal.getType)
  unless target.isAppOfArity ``State.CellsWellFormed 1 do throwError "expected a cell-frontier invariant"
  let state := target.getAppArgs[0]!
  if state.hasExprMVar then throwError "the target state must be known"
  let mut known : Array (Expr × Expr) := #[]
  let mut executions : Array (Expr × Expr × Expr × Name) := #[]
  for declaration in ← getLCtx do
    if declaration.isImplementationDetail then continue
    let type := (← instantiateMVars declaration.type).consumeMData
    let proof := mkFVar declaration.fvarId
    if type.isAppOfArity ``State.CellsWellFormed 1 then
      known := known.push (type.getAppArgs[0]!, proof)
    for (contract, rule) in [(``RunsExpr, ``RunsExpr.cellsWellFormed),
        (``RunsStmt, ``RunsStmt.cellsWellFormed), (``RunsExprs, ``RunsExprs.cellsWellFormed),
        (``Evaluates, ``Evaluates.cellsWellFormed), (``Executes, ``Executes.cellsWellFormed)] do
      if type.isAppOfArity contract 5 then
        executions := executions.push (type.getAppArgs[1]!, type.getAppArgs[4]!, proof, rule)
  let fuel := (← getLCtx).numIndices + 1
  let mut used : Std.HashSet Nat := {}
  for _ in [:executions.size + 1] do
    if let some proof ← bindingFormed known state fuel then
      goal.assign proof
      replaceMainGoal (← getGoals).tail
      return
    let mut changed := false
    for index in [:executions.size] do
      if used.contains index then continue
      let (before, after, run, rule) := executions[index]!
      if let some formed ← bindingFormed known before fuel then
        known := known.push (after, ← mkAppM rule #[run, formed])
        used := used.insert index
        changed := true
    unless changed do break
  throwError "no proved execution chain establishes the cell-frontier invariant"

end Lanius.Semantics
