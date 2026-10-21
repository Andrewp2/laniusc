import Lean.Elab.Tactic
import Lean.Elab.Tactic.Split

namespace Lanius.Semantics.Automation

open Lean Meta Elab Tactic

/-- Apply proved contracts to fully applied, closed calls and split their
    results. Normalization and the final state reasoning belong to the
    invariant's client. Every generated term is checked by the kernel. -/
partial def solveInvariant (predicates : Array Name) (normalize finish : Syntax)
    (contracts : Array Syntax) : TacticM Unit := do
  evalTactic normalize
  if (← getGoals).isEmpty then return
  evalTactic finish
  if (← getGoals).isEmpty then return
  withMainContext do
    let goal ← getMainGoal
    let target ← instantiateMVars (← goal.getType)
    for contractTerm in contracts do
      let contract ← Term.elabTerm contractTerm none
      let proof? ← withNewMCtxDepth do
        let mut conclusion ← inferType contract
        let mut arguments := #[]
        while true do
          if predicates.any conclusion.isAppOf then break
          let binder ← whnf conclusion
          unless binder.isForall do break
          let argument ← mkFreshExprMVar binder.bindingDomain!
          arguments := arguments.push argument
          conclusion := (binder.bindingBody!.instantiate1 argument).consumeMData
        unless conclusion.isApp do return none
        let pattern := conclusion.getAppArgs.back!.consumeMData
        unless pattern.isApp && pattern.getAppFn.isConst do return none
        let call? := target.find? (fun e => !e.hasLooseBVars &&
          e.isAppOfArity pattern.getAppFn.constName! pattern.getAppArgs.size)
        let some call := call? | return none
        unless ← isDefEq pattern call do return none
        let proof ← instantiateMVars (mkAppN contract arguments)
        if proof.hasExprMVar then return none
        return some (proof, call)
      if let some (proof, call) := proof? then
        let proofSyntax ← Term.exprToSyntax proof
        let callSyntax ← Term.exprToSyntax call
        evalTactic (← `(tactic| have invariant := $proofSyntax))
        evalTactic (← `(tactic| cases observation : $callSyntax))
        let branches ← getGoals
        for branch in branches do
          setGoals [branch]
          solveInvariant predicates normalize finish contracts
        setGoals []
        return
    let mut branches? ← Lean.Meta.splitTarget? goal
    if branches?.isNone then
      for declaration in ← getLCtx do
        if declaration.type.isAppOfArity ``Eq 3 then
          branches? ← Lean.Meta.splitLocalDecl? goal declaration.fvarId
          if branches?.isSome then break
    let some branches := branches? |
      throwError "no proved state contract or common branch:\n{MessageData.ofGoal goal}"
    for branch in branches do
      setGoals [branch]
      solveInvariant predicates normalize finish contracts
    setGoals []

end Lanius.Semantics.Automation
