import Lean.Elab.Tactic.Basic
import Lean.Elab.Tactic.ElabTerm
import Lean.Meta.Tactic.AuxLemma

/-! Kernel reduction for closed certificate equalities. Like `decide +kernel`,
this checks an auxiliary theorem once and reuses it. Unlike `decide`, it needs
no `DecidableEq` instance for the generated syntax trees. -/

open Lean Meta Elab Tactic

/-- Prove a closed definitional equality by checking `Eq.refl` in the kernel.
No native evaluation, new axiom, or unchecked declaration is involved. -/
elab "kernel_rfl" : tactic => do
  closeMainGoalUsing `kernel_rfl fun target _ => do
    let target ← instantiateMVars target
    let target ← if target.hasFVar then zetaReduce target else pure target
    if target.hasFVar || target.hasMVar then
      throwError "kernel_rfl requires a closed equality"
    let equality ← if target.eq?.isSome then pure target
      else withTransparency .all (whnf target)
    let some (_, _, rhs) := equality.eq?
      | throwError "kernel_rfl requires an equality"
    let proof ← mkEqRefl rhs
    let levelsInType := (collectLevelParams {} target).params
    let levels := (← Term.getLevelNames).reverse.filter levelsInType.contains
    let name ← withOptions (Elab.async.set · false) do
      mkAuxLemma levels target proof
    return mkConst name (levels.map .param)
