import Lanius.CallContracts.Expression
import Lanius.Automation.Execute

namespace Lanius.Automation

open Lanius.CallContracts
open Lean Meta Elab Tactic

/-- Compose known expression contracts and pure arguments. Like `core_args`,
this never unfolds a callee or invents an execution assumption. -/
syntax "core_spec" "[" Lean.Parser.Tactic.dsimpArg,* "]" : tactic
elab_rules : tactic
| `(tactic| core_spec [$facts,*]) => withMainContext do
  let saved ← saveState
  try evalTactic (← `(tactic| solve_by_elim (maxDepth := 1))); return catch _ => saved.restore
  let target := (← instantiateMVars (← getMainTarget)).consumeMData
  if target.isAppOfArity ``ArgsSpec 7 then
    let expressions ← whnf target.getAppArgs[3]!
    if expressions.isAppOf ``List.nil then evalTactic (← `(tactic| exact ArgsSpec.nil))
    else evalTactic (← `(tactic| apply ArgsSpec.cons <;> core_spec [$facts,*]))
  else if target.isAppOfArity ``ExprSpec 7 then
    let expression ← whnf target.getAppArgs[3]!
    if expression.isAppOf ``Lanius.Core.Expr.call then
      evalTactic (← `(tactic| (
        apply ExprSpec.call
        rotate_left
        · assumption
        · first | exact (fun _ held => held) | exact Lanius.Separation.CellSet.empty_subset
        · core_spec [$facts,*])))
    else
      evalTactic (← `(tactic| (
        apply ExprSpec.pure
        intro state frame
        have reads := frame.reads
        first | solve_by_elim (maxDepth := 2) | core_eval [$facts,*])))
  else throwError "core_spec expects an expression or argument contract"

end Lanius.Automation
