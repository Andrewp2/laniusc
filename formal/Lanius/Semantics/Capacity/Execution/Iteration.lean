import Lanius.Semantics.Capacity.Execution.Step

namespace Lanius.Semantics.Capacity.Execution
open Lanius.Core

theorem forRange {id : VarId} (valid : config.Valid) (step : Step fuel config allowed program) (ready : Ready config before)
    (supported : Fragment.statement allowed body = true)
    (executed : execForRange (fuel + 1) program before id current stop inclusive body = .done result after) :
    execForRange (fuel + 1) program (state config before) id current stop inclusive body =
        .done (completion config result) (state config after) ∧ Ready config after ∧ completionClosed config result := by
  simp only [execForRange] at executed ⊢
  split at executed
  · rename_i finished
    obtain ⟨rfl, rfl⟩ := Outcome.done.inj executed
    exact ⟨by simp only [finished, ↓reduceIte]; rfl, ready, trivial⟩
  · rename_i unfinished
    simp only [unfinished, Bool.false_eq_true, ↓reduceIte, State.bindLocal]
    have bound : (state config before).bindCell id (some (.signed .i32 current)) =
        state config (before.bindCell id (some (.signed .i32 current))) :=
      (bindCell valid before ready.frontier id (some (.signed .i32 current))).symm
    rw [bound]
    cases run : execStmt fuel program (before.bindLocal id (.signed .i32 current)) body with
    | done returned completed =>
      obtain ⟨transport, completedReady, resultClosed⟩ := step.statement (ready.bindLocal valid id _ rfl) supported run
      simp only [State.bindLocal] at transport
      rw [transport]
      have restoredReady := completedReady.restoreLocals ready
      cases returned <;> simp only [run, completion, ← restore] at executed ⊢
      all_goals try (split at executed)
      all_goals try simp_all only [Bool.false_eq_true, ↓reduceIte]
      all_goals first
        | exact step.forRange restoredReady supported executed
        | obtain ⟨rfl, rfl⟩ := Outcome.done.inj executed; exact ⟨rfl, restoredReady, resultClosed⟩
    | _ => simp [run] at executed

end Lanius.Semantics.Capacity.Execution
