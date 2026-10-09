import Lanius.Semantics.PureProof
import Lanius.Semantics.ScopedEffect

namespace Lanius.Semantics

open Lean Meta Elab Tactic

/-- Follow proved frame edges only. Binding locals reduces the projection,
    while an effect edge may preserve views/world but never supplies heap
    equality. Search is bounded by the number of available frames. -/
private def frameEquality (left right : Expr) (edges : Array Expr) (fuel : Nat) : MetaM (Option Expr) := do
  if ← isDefEq left right then return some (← mkEqRefl left)
  let fuel + 1 := fuel | return none
  for edge in edges do
    let saved ← saveState
    let some (_, after, before) := (← inferType edge).eq? | continue
    if ← isDefEq left after then
      if let some rest ← frameEquality before right edges fuel then
        return some (← mkEqTrans edge rest)
    saved.restore
  return none

private def frameEdges : TacticM (Array Expr) := do
  let mut edges := #[]
  for declaration in (← getLCtx) do
    let type := declaration.type.consumeMData
    let frame := mkFVar declaration.fvarId
    if type.isAppOfArity ``PureFrame 2 || type.isAppOfArity ``CallerFrame 2 then
      let frameName := if type.isAppOf ``PureFrame then ``PureFrame else ``CallerFrame
      for field in ["heap", "views", "world"] do
        edges := edges.push (← mkAppM (frameName ++ Name.mkSimple field) #[frame])
    else if type.isAppOfArity ``MemoryEffect 3 then
      let tail ← mkAppM ``And.right #[frame]
      edges := edges.push (← mkAppM ``And.left #[tail])
      edges := edges.push (← mkAppM ``And.left #[← mkAppM ``And.right #[tail]])
  return edges

elab "core_frame" : tactic => withMainContext do
  let goal ← getMainGoal
  let some (_, left, right) := (← goal.getType).eq? | throwError "expected frame equality"
  let edges ← frameEdges
  let some proof ← frameEquality left right edges (edges.size + 1) | throwError "no proved frame path"
  goal.assign proof
  replaceMainGoal []

/-- Retain a supplied heap relation across pure setup. This cannot turn an
    effect into heap equality or manufacture a relation with no proved edge. -/
elab "core_memory_relation" : tactic => withMainContext do
  let goal ← getMainGoal
  let target ← instantiateMVars (← goal.getType)
  let edges ← frameEdges
  for declaration in (← getLCtx) do
    let type := declaration.type.consumeMData
    unless type.isAppOfArity ``MemoryEffect 3 do continue
    let saved ← saveState
    try
      let effect := mkFVar declaration.fvarId
      let relation := type.getAppArgs[0]!
      let first ← mkAppM ``State.heap #[type.getAppArgs[1]!]
      let last ← mkAppM ``State.heap #[type.getAppArgs[2]!]
      unless target.getAppNumArgs ≥ 2 do throwError "not a binary heap relation"
      let args := target.getAppArgs
      let n := args.size
      let targetRelation := mkAppN target.getAppFn (args.extract 0 (n - 2))
      unless ← isDefEq relation targetRelation do throwError "different heap relation"
      let some firstEq ← frameEquality first args[n - 2]! edges (edges.size + 1) |
        throwError "different initial heap"
      let some lastEq ← frameEquality args[n - 1]! last edges (edges.size + 1) |
        throwError "no retained final heap"
      let heapProof ← mkAppM ``And.right #[← mkAppM ``And.right #[← mkAppM ``And.right #[effect]]]
      let equality ← mkCongr (← mkCongrArg relation firstEq) (← mkEqSymm lastEq)
      goal.assign (← mkEqMP equality heapProof)
      replaceMainGoal []
      return
    catch _ => saved.restore
  throwError "no proved retained heap relation"

elab "core_effect_contract" : tactic => withMainContext do
  let goal ← getMainGoal
  let remaining := (← getGoals).tail
  let callee ← contractCall? (← goal.getType)
  for declaration in (← getLCtx) do
    unless !declaration.isImplementationDetail && declaration.type.isForall do continue
    let saved ← saveState
    try
      if let some callee := callee then
        let some other ← contractCall? declaration.type | throwError "not a call contract"
        unless ← isDefEq callee other do throwError "different callee"
      setGoals (← goal.apply (mkFVar declaration.fvarId))
      evalTactic (← `(tactic| all_goals (first
        | core_contract | core_local | core_frame | core_formed | core_memory_relation)))
      unless (← getGoals).isEmpty do throwError "effect contract premises remain"
      setGoals remaining
      return
    catch _ => saved.restore
  throwError "no applicable proved effect contract"

syntax "core_effect_expr" : tactic
syntax "core_effect" term : tactic

macro_rules
  | `(tactic| core_effect_expr) => `(tactic| first
      | core_contract
      | core_effect_contract
      | (apply RunsExpr.argumentsEffect; core_arguments; core_effect_contract)
      | (apply RunsExpr.callFramedEffectArguments (MemoryEffect.scopeStable _);
          core_pure_arguments; intro middle frame; core_effect_contract)
      | (apply RunsExpr.matchEffect (MemoryEffect.scopeStable _);
          core_run; rfl; core_formed; core_effect_expr)
      | (apply RunsExpr.callMemoryArgument; core_effect_expr;
          intro middle effect;
          have cells := effect.1;
          have formed := cells.after_cellsWellFormed (by core_formed);
          core_pure_expr))

elab "core_effect_node" compose:term : tactic => withMainContext do
  let target ← whnf (← instantiateMVars (← (← getMainGoal).getType))
  unless target.isAppOfArity ``Exists 2 do throwError "expected effectful statement contract, got {target}"
  let .lam _ _ body _ := target.getAppArgs[1]! | throwError "expected output state binder"
  let body := body.consumeMData
  unless body.isAppOfArity ``And 2 do throwError "expected execution and effect"
  let run := body.getAppArgs[0]!
  unless run.isAppOfArity ``RunsStmt 5 do throwError "expected statement execution"
  let effect := body.getAppArgs[1]!
  unless effect.isAppOfArity ``MemoryEffect 3 do throwError "expected a native memory effect"
  let relation ← Term.exprToSyntax effect.getAppArgs[0]!
  let statement ← whnf run.getAppArgs[2]!
  let rule ← match statement.getAppFn.constName? with
    | some ``Lanius.Core.Stmt.letLocal => `(tactic| (
        (first
          | (apply RunsStmt.letEffect (MemoryEffect.scopeStable _); core_run; core_formed)
          | (apply RunsStmt.letFramedEffect (MemoryEffect.scopeStable _);
              core_pure_expr; intro middle frame)
          | (apply RunsStmt.letMemoryEffect; core_effect_expr;
              intro middle run effect;
              have cells := effect.1;
              have formed := cells.after_cellsWellFormed (by core_formed);
              core_pure)
          | (apply RunsStmt.letMemoryThen (relation := $relation) $compose; core_effect_expr;
              intro middle run effect;
              have cells := effect.1;
              have formed := cells.after_cellsWellFormed (by core_formed)));
        all_goals core_effect $compose))
    | some ``Lanius.Core.Stmt.sequence => `(tactic| (
        (first
          | (apply RunsStmt.guardEffectFalse (MemoryEffect.scopeStable _);
              core_pure_guard; intro middle frame)
          | (apply RunsStmt.guardEffectTrue (MemoryEffect.scopeStable _);
              (solve | simp); core_pure_guard; intro middle frame));
        core_effect $compose))
    | some ``Lanius.Core.Stmt.returnValue => `(tactic|
        (apply RunsStmt.returnEffect; core_effect_expr))
    | _ => `(tactic| core_effect_contract)
  evalTactic rule

macro_rules
  | `(tactic| core_effect $compose) => `(tactic| first
      | core_contract
      | core_effect_contract
      | core_effect_node $compose)

end Lanius.Semantics
