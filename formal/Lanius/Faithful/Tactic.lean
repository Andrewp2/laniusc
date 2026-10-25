import Lanius.Faithful.Pure
import Lanius.Faithful.Attr

/-! Tactics for the extraction certificates.

A certificate's proof unfolds the function's body in a hypothesis
`h : pcall .. = some w` and the extracted Lean function in the goal. What is
left are hypotheses `pcall sp prims n c args = some x`, one per call the
body made. `certs` applies callee `c`'s certificate to each, once the
representation premises of its arguments can be shown (`rep`), which also
fixes the Lean values the arguments represent. -/

namespace Lanius.Faithful

open Lean Elab Tactic Meta

/-- Split every hypothesis that is an `∃` or an `∧`, until none is. -/
partial def destructAll (fuel : Nat) : TacticM Unit := do
  if fuel = 0 then return
  let goal ← getMainGoal
  let found ← goal.withContext do
    for d in ← getLCtx do
      if d.isImplementationDetail then continue
      let t ← instantiateMVars d.type
      if t.isAppOfArity ``Exists 2 || t.isAppOfArity ``And 2 then return some d.fvarId
    return none
  match found with
  | none => return
  | some f =>
    let subgoals ← goal.cases f
    replaceMainGoal (subgoals.map (·.mvarId)).toList
    destructAll (fuel - 1)

elab "destruct" : tactic => destructAll 10000

/-- A representation premise: from the hypotheses and the `rep_rule`s. -/
macro "rep" : tactic => `(tactic| solve_by_elim (maxDepth := 40) using $(mkIdent `rep_rule))

/-- A call hypothesis: callee, argument count. -/
def callOf? (t : Expr) : MetaM (Option (Nat × Nat)) := do
  let t ← instantiateMVars t
  let some (_, lhs, _) := t.eq? | return none
  unless lhs.isAppOfArity ``pcall 5 do return none
  let args := lhs.getAppArgs
  let some callee := (← whnfR args[3]!).rawNatLit? <|> args[3]!.nat? | return none
  let some (_, values) := args[4]!.listLit? | return none
  return some (callee, values.length)

/-- Apply the certificates of the calls whose argument premises hold. A call
of `c` uses the hypothesis `ih{c}` if there is one (a call within the
function's recursive group), else the theorem `cert{c}` of `ns`. -/
partial def certsLoop (ns : Name) : TacticM Unit := do
  let mut progress := true
  while progress do
    progress := false
    let goal ← getMainGoal
    let calls ← goal.withContext do
      let mut out := #[]
      for d in ← getLCtx do
        if d.isImplementationDetail then continue
        if let some (c, k) ← callOf? d.type then out := out.push (d.userName, d.fvarId, c, k)
      return out
    for (_, fvar, c, k) in calls do
      let goal ← getMainGoal
      let ok ← goal.withContext do
        let local? := (← getLCtx).findFromUserName? (Name.mkSimple s!"ih{c}")
        let fn : Term ← match local? with
          | some d => pure ⟨mkIdent d.userName⟩
          | none => pure ⟨mkIdent (ns ++ Name.mkSimple s!"cert{c}")⟩
        let h ← `(term| $(⟨mkIdent (← fvar.getUserName)⟩))
        let mut app ← `(term| $fn $h)
        for _ in [0:k] do
          app ← `(term| $app (by rep))
        let saved ← saveState
        try
          evalTactic (← `(tactic| have := $app))
          return true
        catch _ =>
          saved.restore
          return false
      if ok then
        let goal ← getMainGoal
        replaceMainGoal [← goal.clear fvar]
        progress := true

elab "certs " ns:ident : tactic => certsLoop ns.getId

end Lanius.Faithful
