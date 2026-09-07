import Lanius.Semantics.Relocation.Execution.Step
import Std.Tactic

namespace Lanius.Semantics.Relocation.Execution

open Lanius.Core

private theorem bindNone (symbols : Core.Relocation.Symbols) (before : State) (id : VarId) :
    (state symbols before).bindCell id none = state symbols (before.bindCell id none) :=
  (bindCell symbols before id none).symm

theorem statement (step : Step fuel symbols smaller larger)
    (before : State) (body : Stmt) (result : Completion) (after : State)
    (executed : execStmt (fuel + 1) smaller before body = .done result after) :
    execStmt (fuel + 1) larger (state symbols before) (Core.Relocation.statement symbols body) =
      .done (completion symbols result) (state symbols after) := by
  cases body <;> simp only [Core.Relocation.statement, execStmt] at executed ⊢
  all_goals
    repeat' first
      | rw [step.expression (by assumption)]
      | rw [step.statement (by assumption)]
      | rw [step.forValues (by assumption)]
      | rw [step.forRange (by assumption)]
      | simp_all only [Core.Relocation.value, completion, Option.map, Stmt.returnValue.injEq,
          ← bindLocal, bindNone, State.bindUninitialized, sliceValues, Except.map]
      | split at executed
    all_goals first
      | exact step.statement executed
      | exact step.forValues executed
      | exact step.forRange executed
      | exact restoredStatement step _ _ _ _ _ executed
      | skip
    all_goals grind only [→ step.expression, → step.statement, → step.forValues, → step.forRange,
      restoredStatement, sliceValues, Relocation.restoreLocals, completion]

end Lanius.Semantics.Relocation.Execution
