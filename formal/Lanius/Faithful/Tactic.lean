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

/-- A hypothesis `(pcall ..).bind f = some w` (or `.map`): the lemma that
takes the call off (`pcall_bind`, in Simp.lean). -/
def peelable? (t : Expr) : MetaM (Option Name) := do
  let t ← instantiateMVars t
  let some (_, lhs, _) := t.eq? | return none
  let lemma := if lhs.isAppOfArity ``Option.bind 4 then `Lanius.Faithful.pcall_bind
    else if lhs.isAppOfArity ``Option.map 4 then `Lanius.Faithful.pcall_map else .anonymous
  if lemma.isAnonymous then return none
  -- `Option.bind x f`, `Option.map f x`
  let x := if lhs.isAppOfArity ``Option.bind 4 then lhs.appFn!.appArg! else lhs.appArg!
  unless x.getAppFn.isConstOf ``pcall do return none
  return some lemma

/-- Take the calls off the hypotheses that start with one: `pcall .. = some x`
and the rest, `f x = ..`, beta-reduced. -/
partial def peelCalls (fuel : Nat) : TacticM Unit := do
  if fuel = 0 then return
  let goal ← getMainGoal
  let found ← goal.withContext do
    for d in ← getLCtx do
      if d.isImplementationDetail then continue
      if let some lemma ← peelable? d.type then return some (d.fvarId, lemma)
    return none
  let some (h, lemma) := found | return
  let goal ← goal.withContext do
    let ex ← mkAppM lemma #[mkFVar h]
    let goal ← goal.assert `peeled (← inferType ex) ex
    let goal ← goal.tryClear h
    let (e, goal) ← goal.intro1
    let #[s1] ← goal.cases e | throwError "peelCalls"
    let #[s2] ← s1.mvarId.cases s1.fields[1]!.fvarId! | throwError "peelCalls"
    let goal := s2.mvarId
    let rest := s2.fields[1]!.fvarId!
    goal.withContext do
      let t ← instantiateMVars (← rest.getType)
      let some (ty, lhs, rhs) := t.eq? | return goal
      goal.replaceLocalDeclDefEq rest (mkApp3 (mkConst ``Eq [← getLevel ty]) ty lhs.headBeta rhs)
  replaceMainGoal [goal]
  peelCalls (fuel - 1)

elab "peel" : tactic => peelCalls 10000

initialize registerTraceClass `faithful.rep

/-- Prove a representation goal `Rep.. x v` with the constructors of its
relation, the one whose indices unify, and the side conditions (`n < 2 ^ 64`)
from the hypotheses: a hypothesis that is the goal, `omega`, or `decide` on
a literal. No search: a goal that fails fails quickly. -/
partial def repGoal (fuel : Nat) (goal : MVarId) : MetaM Bool := do
  if fuel = 0 then return false
  if ← goal.isAssigned then return true
  let t := (← instantiateMVars (← goal.getType)).cleanupAnnotations
  let saved ← saveState
  let tryClose (tac : MVarId → MetaM Unit) : MetaM Bool := do
    try
      tac goal
      if ← goal.isAssigned then return true
      saved.restore
      return false
    catch _ =>
      saved.restore
      return false
  if ← tryClose (fun g => g.assumption) then return true
  let .const n _ := t.getAppFn | do trace[faithful.rep] "not a relation: {t}"; return false
  match (← getEnv).find? n with
  | some (.inductInfo info) =>
    if n == ``Eq then
      -- `RepNat.of_eq`'s equation.
      return ← tryClose (fun g => do
        let gs ← Lean.Elab.Term.TermElabM.run' (Lean.Elab.Tactic.run g (Lean.Elab.Tactic.evalTactic
          (← `(tactic| first
            | rfl
            | omega
            | (simp only [Nat.max_def, Nat.min_def]; split <;> omega)
            | rw [Nat.mod_eq_of_lt (Nat.lt_of_le_of_lt (Nat.div_le_self _ _) (by omega))]
            | rw [Nat.mod_eq_of_lt (Nat.lt_of_le_of_lt (Nat.mod_le _ _) (by omega))]))))
        unless gs.isEmpty do throwError "left goals")
    -- `RepNat.of_eq` (in Rep.lean) after the constructor: a computed number.
    let ctors := info.ctors ++
      if n == `Lanius.Faithful.RepNat then [`Lanius.Faithful.RepNat.of_eq]
      else if n == `Lanius.Faithful.RepU8 then [`Lanius.Faithful.RepU8.lit]
      else if n == `Lanius.Faithful.RepU32 then [`Lanius.Faithful.RepU32.lit]
      else []
    for ctor in ctors do
      let saved ← saveState
      try
        let subgoals ← goal.apply (← mkConstWithFreshMVarLevels ctor)
        let mut ok := true
        for g in subgoals do
          unless ← repGoal (fuel - 1) g do
            ok := false
            break
        if ok then return true
        saved.restore
      catch e =>
        let m ← e.toMessageData.toString
        saved.restore
        trace[faithful.rep] "{ctor}: {m}"
    return false
  | _ =>
    -- A side condition: a bound.
    if ← tryClose (fun g => do
        let gs ← Lean.Elab.Term.TermElabM.run' (Lean.Elab.Tactic.run g (Lean.Elab.Tactic.evalTactic
          (← `(tactic| first | omega | decide))))
        unless gs.isEmpty do throwError "open") then return true
    return false

elab "rep" : tactic => do
  let goals ← getGoals
  if goals.isEmpty then return
  let goal ← getMainGoal
  unless ← repGoal 200 goal do throwError m!"rep: no representation{indentD (MessageData.ofGoal goal)}"
  replaceMainGoal []

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
