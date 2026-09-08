import Lanius.Semantics.Restriction.Step
import Std.Tactic

namespace Lanius.Semantics.Restriction

open Lanius.Core

theorem forValues (step : Step fuel allowed original restricted)
    (before : State) (id : VarId) (values : List Value) (body : Stmt)
    (result : Completion) (after : State)
    (executed : execForValues (fuel + 1) original before id values body = .done result after)
    (closed : Dependencies.statement allowed body = true) :
    execForValues (fuel + 1) restricted before id values body = .done result after := by
  cases values with
  | nil => cases executed; rfl
  | cons first rest =>
      simp only [execForValues] at executed ⊢
      cases run : execStmt fuel original (before.bindLocal id first) body with
      | done value completed =>
          rw [step.statement run closed]
          cases value <;> simp only [run] at executed ⊢
          all_goals first
            | exact step.forValues executed closed
            | exact executed
      | _ => simp [run] at executed

theorem forRange (step : Step fuel allowed original restricted)
    (before : State) (id : VarId) (current : Int) (stop : Option Int) (inclusive : Bool) (body : Stmt)
    (result : Completion) (after : State)
    (executed : execForRange (fuel + 1) original before id current stop inclusive body = .done result after)
    (closed : Dependencies.statement allowed body = true) :
    execForRange (fuel + 1) restricted before id current stop inclusive body = .done result after := by
  simp only [execForRange] at executed ⊢
  split at executed
  · rename_i finished
    simpa only [finished, ↓reduceIte] using executed
  · rename_i unfinished
    simp only [unfinished, ↓reduceIte]
    cases run : execStmt fuel original (before.bindLocal id (.signed .i32 current)) body with
    | done value completed =>
        rw [step.statement run closed]
        cases value <;> simp only [run] at executed ⊢
        all_goals repeat' first
          | split at executed
          | simp_all only [Bool.false_eq_true, ↓reduceIte]
        all_goals first
          | exact step.forRange executed closed
          | exact executed
    | _ => simp [run] at executed

end Lanius.Semantics.Restriction
