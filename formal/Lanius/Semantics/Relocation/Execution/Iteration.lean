import Lanius.Semantics.Relocation.Execution.Step
import Std.Tactic

namespace Lanius.Semantics.Relocation.Execution

open Lanius.Core

theorem forValues (step : Step fuel symbols smaller larger)
    (before : State) (id : VarId) (values : List Value) (body : Stmt)
    (result : Completion) (after : State)
    (executed : execForValues (fuel + 1) smaller before id values body = .done result after) :
    execForValues (fuel + 1) larger (state symbols before) id (Core.Relocation.values symbols values)
        (Core.Relocation.statement symbols body) =
      .done (completion symbols result) (state symbols after) := by
  cases values with
  | nil => cases executed; rfl
  | cons first rest =>
      simp only [Core.Relocation.values, execForValues, ← bindLocal] at executed ⊢
      cases run : execStmt fuel smaller (before.bindLocal id first) body with
      | done value completed =>
          rw [step.statement run]
          cases value <;> simp only [run, completion] at executed ⊢
          all_goals first
            | exact step.forValues executed
            | obtain ⟨rfl, rfl⟩ := Outcome.done.inj executed; rfl
      | _ => simp [run] at executed

theorem forRange (step : Step fuel symbols smaller larger) (target : smaller.target = larger.target)
    (before : State) (id : VarId) (current : Int) (stop : Option Int) (inclusive : Bool) (body : Stmt)
    (result : Completion) (after : State)
    (executed : execForRange (fuel + 1) smaller before id current stop inclusive body = .done result after) :
    execForRange (fuel + 1) larger (state symbols before) id current stop inclusive
        (Core.Relocation.statement symbols body) =
      .done (completion symbols result) (state symbols after) := by
  simp only [execForRange] at executed ⊢
  split at executed
  · rename_i finished
    simp only [finished, ↓reduceIte]
    cases executed
    rfl
  · rename_i unfinished
    simp only [unfinished, ↓reduceIte]
    have bound : (state symbols before).bindLocal id (.signed .i32 current) =
        state symbols (before.bindLocal id (.signed .i32 current)) :=
      (bindLocal symbols before id (.signed .i32 current)).symm
    rw [bound]
    cases run : execStmt fuel smaller (before.bindLocal id (.signed .i32 current)) body with
    | done value completed =>
        rw [step.statement run]
        cases value <;> simp only [run, completion] at executed ⊢
        all_goals repeat' first
          | split at executed
          | simp_all only [Bool.false_eq_true, ↓reduceIte, ← Relocation.restoreLocals]
        all_goals first
          | exact step.forRange executed
          | obtain ⟨rfl, rfl⟩ := Outcome.done.inj executed; rfl
    | _ => simp [run] at executed

end Lanius.Semantics.Relocation.Execution
