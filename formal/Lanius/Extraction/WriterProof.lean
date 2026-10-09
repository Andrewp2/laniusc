import Lanius.Extraction.WriterFrame
import Lanius.Semantics.StatementProof

namespace Lanius.Extraction

open Lanius.Semantics

/-- Compose checked writer contracts through reads, locals, and matches.
    Writes and algorithm-specific contracts must still be supplied. -/
syntax "core_writer_expr" : tactic
syntax "core_writer" : tactic

open Lean Meta Elab Tactic in
/-- Choose a source rule before descending, and commit the checked read-only
    prefix. A failed continuation must not retry other guard/initializer paths. -/
elab "core_writer_node" : tactic => withMainContext do
  let target ← whnf (← instantiateMVars (← (← getMainGoal).getType))
  unless target.isAppOfArity ``Exists 2 do throwError "expected a writer statement contract"
  let .lam _ _ body _ := target.getAppArgs[1]! | throwError "expected a state binder"
  unless body.isAppOfArity ``And 2 do throwError "expected execution and a frame"
  let run := (← instantiateMVars body.getAppArgs[0]!).consumeMData
  unless run.isAppOfArity ``Lanius.Semantics.RunsStmt 5 do throwError "expected a statement contract"
  let statement ← whnf run.getAppArgs[2]!
  let rule ← match statement.getAppFn.constName? with
    | some ``Lanius.Core.Stmt.returnValue => `(tactic|
        (apply Lanius.Extraction.RunsStmt.returnWriter; core_writer_expr))
    | some ``Lanius.Core.Stmt.letLocal => `(tactic| (
        apply Lanius.Extraction.RunsStmt.letPureWriter; core_run; core_formed;
        core_writer))
    | some ``Lanius.Core.Stmt.sequence => `(tactic| (
        (first
          | (apply Lanius.Extraction.RunsStmt.guardPureWriter false; (solve | simp); core_run)
          | (apply Lanius.Extraction.RunsStmt.guardPureWriter true; (solve | simp); core_run));
        core_writer))
    | _ => throwError "statement requires a supplied writer contract"
  evalTactic rule

macro_rules
  | `(tactic| core_writer_expr) => `(tactic| first
      | core_contract
      | (apply Lanius.Extraction.RunsExpr.writerArguments; core_arguments; core_contract)
      | (apply Lanius.Extraction.RunsExpr.matchWriter; core_run; rfl; core_formed; core_writer_expr))
  | `(tactic| core_writer) => `(tactic| first | core_contract | core_writer_node)

end Lanius.Extraction
