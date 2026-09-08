import Lanius.Semantics.CellRenaming.Execution.Step
import Std.Tactic

namespace Lanius.Semantics.CellRenaming.Execution
open Lanius.Core

theorem forValues {rename : Permutation boundary} (step : Step fuel rename program)
    (before : State) (id : VarId) (input : List Value) (body : Stmt)
    (result : Completion) (after : State) (ready : boundary ≤ before.nextCell)
    (executed : execForValues (fuel + 1) program before id input body = .done result after) :
    execForValues (fuel + 1) program (state rename.forward before) id (values rename.forward input)
        (CellRenaming.statement rename.forward body) =
      .done (completion rename.forward result) (state rename.forward after) ∧ boundary ≤ after.nextCell := by
  cases input with
  | nil => cases executed; exact ⟨rfl, ready⟩
  | cons first rest =>
      simp only [values, execForValues] at executed ⊢
      rw [← bindLocal rename before ready]
      cases run : execStmt fuel program (before.bindLocal id first) body with
      | done result completed =>
          obtain ⟨transport, completedReady⟩ :=
            step.statement (Nat.le_trans ready (Nat.le_succ before.nextCell)) run
          rw [transport]
          cases result <;> simp only [run, completion, ← CellRenaming.restoreLocals] at executed ⊢
          all_goals first
            | exact step.forValues completedReady executed
            | obtain ⟨rfl, rfl⟩ := Outcome.done.inj executed; exact ⟨rfl, completedReady⟩
      | _ => simp [run] at executed

theorem forRange {rename : Permutation boundary} (step : Step fuel rename program)
    (before : State) (id : VarId) (current : Int) (stop : Option Int) (inclusive : Bool) (body : Stmt)
    (result : Completion) (after : State) (ready : boundary ≤ before.nextCell)
    (executed : execForRange (fuel + 1) program before id current stop inclusive body = .done result after) :
    execForRange (fuel + 1) program (state rename.forward before) id current stop inclusive
        (CellRenaming.statement rename.forward body) =
      .done (completion rename.forward result) (state rename.forward after) ∧ boundary ≤ after.nextCell := by
  simp only [execForRange] at executed ⊢
  split at executed
  · rename_i finished
    simp only [finished, ↓reduceIte]
    cases executed
    exact ⟨rfl, ready⟩
  · rename_i unfinished
    simp only [unfinished, ↓reduceIte]
    have bound : (state rename.forward before).bindLocal id (.signed .i32 current) =
        state rename.forward (before.bindLocal id (.signed .i32 current)) :=
      (bindLocal rename before ready id (.signed .i32 current)).symm
    rw [bound]
    cases run : execStmt fuel program (before.bindLocal id (.signed .i32 current)) body with
    | done result completed =>
        obtain ⟨transport, completedReady⟩ :=
          step.statement (Nat.le_trans ready (Nat.le_succ before.nextCell)) run
        rw [transport]
        cases result <;> simp only [run, completion] at executed ⊢
        all_goals repeat' first
          | split at executed
          | simp_all only [Bool.false_eq_true, ↓reduceIte, ← CellRenaming.restoreLocals]
        all_goals first
          | exact step.forRange completedReady executed
          | obtain ⟨rfl, rfl⟩ := Outcome.done.inj executed; exact ⟨rfl, completedReady⟩
    | _ => simp [run] at executed

end Lanius.Semantics.CellRenaming.Execution
