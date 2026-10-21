import Lanius.Semantics.StatementProof

namespace Lanius.Semantics

open Lean Meta Elab Tactic

-- Named implicit arguments must precede a rule's already supplied positional
-- arguments. Inserting them outside a parenthesized application is too late:
-- Lean has already instantiated those implicit binders.
private partial def specializeRule (rule function values bindings : TSyntax `term) :
    TacticM (TSyntax `term) := do
  match rule with
  | `(term| ($inner:term)) => specializeRule inner function values bindings
  | `(term| $head:term $arguments:term*) =>
      let head ← specializeRule head function values bindings
      `(term| $head $arguments:term*)
  | _ => `(term| $rule (function := $function) (values := $values) (bindings := $bindings))

/-- Set up a pure call contract from the actual declaration and value arguments.
    The kernel checks lookup and parameter binding; proving the body remains
    the caller's obligation. No evaluator or typing checker is run. -/
private def setupCall (function : TSyntax `term) (calleeName : Option (TSyntax `ident) := none)
    (callRule : Option (TSyntax `term) := none) :
    TacticM Unit := withMainContext do
  let target ← whnf (← (← getMainGoal).getType)
  unless target.isAppOfArity ``Exists 2 do throwError "expected an existential call contract"
  let .lam _ _ body _ := target.getAppArgs[1]! | throwError "expected a call result binder"
  unless body.isAppOfArity ``And 2 do throwError "expected execution and a frame"
  let run := body.getAppArgs[0]!
  unless run.isAppOfArity ``RunsExpr 5 do throwError "expected an expression call contract"
  let call ← whnf run.getAppArgs[2]!
  unless call.isAppOfArity ``Lanius.Core.Expr.call 2 do throwError "expected a function call"
  let declaration ← Term.elabTerm function (some (mkConst ``Lanius.Core.Function))
  let mut parameters ← mkAppM ``Lanius.Core.Function.parameters #[declaration]
  let mut arguments := call.getAppArgs[1]!
  let mut values := #[]
  let mut bindings := #[]
  let mut parameterIds := #[]
  repeat
    let list ← whnf arguments
    if list.isAppOfArity ``List.nil 1 then break
    let #[_, head, tail] := list.getAppArgs | throwError "expected a concrete argument list"
    unless list.isAppOfArity ``List.cons 3 do throwError "expected a concrete argument list"
    let value ← whnf head
    unless value.isAppOfArity ``Lanius.Core.Expr.value 1 do
      throwError "prove effectful arguments before applying a value-call contract"
    let parameter ← whnf parameters
    unless parameter.isAppOfArity ``List.cons 3 do throwError "too many arguments"
    let id ← whnf (← mkAppM ``Prod.fst #[parameter.getAppArgs[1]!])
    let value := value.getAppArgs[0]!
    values := values.push value
    bindings := bindings.push (← mkAppM ``Prod.mk #[id, value])
    parameterIds := parameterIds.push id
    parameters := parameter.getAppArgs[2]!
    arguments := tail
  unless (← whnf parameters).isAppOfArity ``List.nil 1 do throwError "too few arguments"
  let valueTerms ← Term.exprToSyntax (← mkListLit (mkConst ``Lanius.Core.Value) values.toList)
  let bindingType ← mkAppM ``Prod #[mkConst ``Lanius.VarId, mkConst ``Lanius.Core.Value]
  let bindingTerms ← Term.exprToSyntax (← mkListLit bindingType bindings.toList)
  let defaultRule := mkIdent (if calleeName.isSome then ``RunsExpr.callPure else ``RunsExpr.callUnchanged)
  let rule : TSyntax `term := callRule.getD ⟨defaultRule⟩
  let application ← specializeRule rule function valueTerms bindingTerms
  evalTactic (← `(tactic| apply $application:term))
  evalTactic (← `(tactic| all_goals try (first | core_contract | core_lookup | rfl | core_formed)))
  let mut goal ← getMainGoal
  let mut body ← instantiateMVars (← goal.getType)
  if let some name := calleeName then
    unless body.isAppOfArity ``Exists 2 do
      throwError "expected an existential body contract, got {body}"
    let .lam _ _ contract _ := body.getAppArgs[1]! | throwError "expected a body result binder"
    unless contract.isAppOfArity ``And 2 do throwError "expected body execution and its frame"
    body := contract.getAppArgs[0]!
    let (_, next) ← (← goal.define name.getId (mkConst ``State) body.getAppArgs[1]!).intro1P
    goal := next
  unless body.isAppOfArity ``RunsStmt 5 do throwError "expected the remaining body obligation"
  let formed ← mkAppM ``State.CellsWellFormed #[body.getAppArgs[1]!]
  let proof ← Term.elabTerm (← `(by core_formed)) (some formed)
  let (_, noted) ← goal.note (← mkFreshUserName `calleeFormed) proof
  goal := noted
  -- Retain the parameter lookups established by this call boundary. Clients
  -- should transport these facts, not reconstruct the binding list per read.
  let state := body.getAppArgs[1]!
  if calleeName.isSome && state.isAppOfArity ``State.bindLocals 2 && parameterIds.all (·.isRawNatLit) &&
      parameterIds.toList.eraseDups.length == parameterIds.size then
    try
      let base := state.getAppArgs[0]!
      let list := state.getAppArgs[1]!
      let baseFormed ← mkAppM ``State.CellsWellFormed #[base]
      let formedProof ← Term.elabTerm (← `(by core_formed)) (some baseFormed)
      let uniqueSyntax ← `(term| (($bindingTerms).map Prod.fst).Nodup)
      let uniqueType ← Term.elabTerm uniqueSyntax none
      let uniqueProof ← Term.elabTerm
        (← `(by simp only [List.map_cons, List.map_nil, Prod.fst]; decide)) (some uniqueType)
      for index in [:bindings.size] do
        let binding := bindings[index]!
        let entry ← mkAppM ``Option.some #[binding]
        let localProof ← mkAppM ``State.bindLocals_local?_get?
          #[base, list, formedProof, uniqueProof, mkNatLit index, binding, ← mkEqRefl entry]
        let (_, next) ← goal.note (← mkFreshUserName `parameterFound) localProof
        goal := next
    catch _ => pure () -- Symbolic/duplicate IDs retain the general binding rules.
  replaceMainGoal [goal]

elab "core_call " function:term : tactic => setupCall function

/-- Name the input state already present in an execution goal, including a
    scoped effect contract. This selects a term; it proves no execution fact. -/
elab "core_state " name:ident : tactic => withMainContext do
  let goal ← getMainGoal
  let mut run := (← instantiateMVars (← goal.getType)).consumeMData
  if run.isAppOfArity ``Exists 2 then
    let .lam _ _ body _ := run.getAppArgs[1]! | throwError "expected a result binder"
    unless body.isAppOfArity ``And 2 do throwError "expected execution and an effect"
    run := body.getAppArgs[0]!
  unless run.isAppOfArity ``RunsExpr 5 || run.isAppOfArity ``RunsStmt 5 ||
      run.isAppOfArity ``RunsExprs 5 do throwError "expected an execution goal"
  let (_, next) ← (← goal.define name.getId (mkConst ``State) run.getAppArgs[1]!).intro1P
  replaceMainGoal [next]

/-- Named entry state for a proved, framed body which allocates fresh locals. -/
elab "core_call_pure " function:term " as " callee:ident : tactic =>
  setupCall function (some callee)

/-- Use an explicitly supplied, kernel-checked framing rule with the same
    call boundary. The body and its effects remain proof obligations. -/
elab "core_call_framed " rule:term:max function:term " as " callee:ident : tactic =>
  setupCall function (some callee) (some rule)

end Lanius.Semantics
