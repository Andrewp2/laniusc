import Lean

namespace Lanius.Semantics

open Lean Meta Elab Tactic

/-- Expose proved fields from the explicitly supplied contract records.
    Only projections are generated; no program or checker is executed. -/
private def recordFacts (value : Expr) : Nat → MetaM (Array Expr)
  | 0 => pure #[]
  | depth + 1 => do
    let type ← whnf (← inferType value)
    let some name := type.getAppFn.constName? | return #[]
    unless isStructure (← getEnv) name do return #[]
    let mut facts := #[]
    for field in getStructureFields (← getEnv) name do
      let projection ← mkProjection value field
      if ← isProp (← inferType projection) then facts := facts.push projection
      facts := facts ++ (← recordFacts projection depth)
    return facts

private def exposeFacts (records : TSyntaxArray `ident) (depth : Nat) : TacticM Unit := withMainContext do
  let mut goal ← getMainGoal
  for record in records do
    let value ← Term.elabTerm record none
    for fact in ← recordFacts value depth do
      let (_, next) ← goal.note (← mkFreshUserName `coreFact) fact
      goal := next
  replaceMainGoal [goal]

elab "core_facts" "[" records:ident,* "]" : tactic => exposeFacts records.getElems 3
elab "core_facts" depth:num "[" records:ident,* "]" : tactic =>
  exposeFacts records.getElems depth.getNat

/-- Lookup transport rules may be registered by later semantic modules. -/
initialize localRules : LabelExtension ←
  registerLabelAttr `core_local_rule "proved transport of local lookups"

syntax "core_local" : tactic
syntax "core_contract" : tactic

elab "core_local_rule" : tactic => withMainContext do
  let goal ← getMainGoal
  let remaining := (← getGoals).tail
  for name in localRules.getState (← getEnv) do
    let saved ← saveState
    try
      setGoals (← goal.apply (← mkConstWithFreshMVarLevels name))
      evalTactic (← `(tactic| all_goals first | core_contract | rfl | decide | core_local))
      unless (← getGoals).isEmpty do throwError "lookup premises remain"
      setGoals remaining
      return
    catch _ => saved.restore
  throwError "no applicable local-lookup transport rule"

end Lanius.Semantics
