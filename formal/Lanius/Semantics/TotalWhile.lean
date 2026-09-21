import Lanius.Semantics.Loop
import Lanius.Semantics.Stable

namespace Lanius.Semantics

open Lanius Lanius.Core

def normalizeCompletion : Completion → Completion
  | .breakLoop => .next
  | completion => completion

/-- The condition/body contracts needed to execute a Core `whileLoop`.

    `Inv` is required only at loop entries.  A true-condition body may either
    decrease the supplied measure and re-enter the loop, or complete early;
    the latter completion is returned by `executeTotalWhile` unchanged (apart
    from Core's prescribed `breakLoop` to `next` conversion). -/
structure TotalWhileOracle
    (measure : State → Nat) (program : Program)
    (condition : Expr) (body : Stmt) where
  Inv : State → Prop
  Done : Completion → State → Prop
  step : ∀ {state}, Inv state →
    (∃ threshold after,
      StableExpr threshold program state condition (.boolean false) after ∧
      Done .next after) ∨
    (∃ conditionThreshold bodyThreshold conditionAfter completion bodyAfter,
      StableExpr conditionThreshold program state condition (.boolean true)
        conditionAfter ∧
      StableStmt bodyThreshold program conditionAfter body completion bodyAfter ∧
      (completion ≠ .next ∧ completion ≠ .continueLoop →
        Done (normalizeCompletion completion) bodyAfter) ∧
      (completion = .next ∨ completion = .continueLoop →
      measure bodyAfter < measure state ∧ Inv bodyAfter))

/- A countdown-loop specification packages the only algorithm-specific facts
   needed by `executeTotalWhile`: an invariant indexed by the iteration, a
   terminal false-condition contract, and one true-condition/body step.  The
   resulting oracle deliberately fixes successful body completion to `.next`;
   early returns belong in a separate `TotalWhileOracle` when an algorithm has
   them. -/
structure CountdownWhileSpec
    (measure : State → Nat) (program : Program)
    (condition : Expr) (body : Stmt) (bound : Nat) where
  Inv : Nat → State → Prop
  Done : Completion → State → Prop
  terminal : ∀ {state}, Inv bound state →
    ∃ conditionThreshold after,
      StableExpr conditionThreshold program state condition (.boolean false) after ∧
      Done .next after
  step : ∀ {index state}, index < bound → Inv index state →
    ∃ conditionThreshold bodyThreshold conditionAfter bodyAfter,
      StableExpr conditionThreshold program state condition (.boolean true)
        conditionAfter ∧
      StableStmt bodyThreshold program conditionAfter body .next bodyAfter ∧
      measure bodyAfter < measure state ∧
      Inv (index + 1) bodyAfter

def countdownWhileOracle
    (measure : State → Nat) (program : Program)
    (condition : Expr) (body : Stmt) (bound : Nat)
    (spec : CountdownWhileSpec measure program condition body bound) :
    TotalWhileOracle measure program condition body where
  Inv state := ∃ index, index ≤ bound ∧ spec.Inv index state
  Done := spec.Done
  step := by
    intro state invariant
    obtain ⟨index, indexBound, indexInvariant⟩ := invariant
    by_cases terminal : index = bound
    · subst index
      obtain ⟨conditionThreshold, after, conditionRun, afterInvariant⟩ :=
        spec.terminal indexInvariant
      left
      exact ⟨conditionThreshold, after, conditionRun, afterInvariant⟩
    · have indexBelow : index < bound := by omega
      obtain ⟨conditionThreshold, bodyThreshold, conditionAfter, bodyAfter,
        conditionRun, bodyRun, decrease, nextInvariant⟩ :=
        spec.step indexBelow indexInvariant
      right
      refine ⟨conditionThreshold, bodyThreshold, conditionAfter, .next, bodyAfter,
        conditionRun, bodyRun, ?_, ?_⟩
      · intro notNext
        exact (notNext.1 rfl).elim
      · intro _
        exact ⟨decrease, ⟨index + 1, by omega, nextInvariant⟩⟩

private theorem stableWhileEarly
    (conditionRun : StableExpr conditionThreshold program state condition (.boolean true)
      conditionAfter)
    (bodyRun : StableStmt bodyThreshold program conditionAfter body completion bodyAfter)
    (notNext : completion ≠ .next)
    (notContinue : completion ≠ .continueLoop) :
    StableStmt (max conditionThreshold bodyThreshold + 1) program state
      (.whileLoop condition body) (normalizeCompletion completion) bodyAfter := by
  intro fuel enough
  rw [← show (fuel - 1).succ = fuel by omega]
  cases completion with
  | next => exact (notNext rfl).elim
  | returned value =>
      rw [execStmt.eq_def]
      simp [normalizeCompletion,
        conditionRun (fuel - 1) (by omega), bodyRun (fuel - 1) (by omega)]
  | breakLoop =>
      rw [execStmt.eq_def]
      simp [normalizeCompletion,
        conditionRun (fuel - 1) (by omega), bodyRun (fuel - 1) (by omega)]
  | continueLoop => exact (notContinue rfl).elim

/-- A well-founded, fuel-stable execution of an actual Core `whileLoop`,
    together with its oracle-certified terminal postcondition. -/
theorem executeTotalWhile
    (measure : State → Nat) (program : Program)
    (condition : Expr) (body : Stmt)
    (oracle : TotalWhileOracle measure program condition body)
    (state : State) (initialInvariant : oracle.Inv state) :
    ∃ threshold completion after,
      StableStmt threshold program state
        (.whileLoop condition body) completion after ∧
      oracle.Done completion after := by
  generalize hn : measure state = n
  induction n using Nat.strongRecOn generalizing state with
  | ind n ih =>
      obtain falseStep | trueStep := oracle.step initialInvariant
      · obtain ⟨conditionThreshold, conditionAfter, conditionRun⟩ := falseStep
        obtain ⟨conditionRun, terminalDone⟩ := conditionRun
        refine ⟨conditionThreshold + 1, .next, conditionAfter, ?_, terminalDone⟩
        intro fuel enough
        rw [← show (fuel - 1).succ = fuel by omega]
        apply execStmt_while_false (fuel := fuel - 1)
          program state condition body conditionAfter
        simpa [show fuel - 1 + 1 = fuel by omega] using
          conditionRun (fuel - 1) (by omega)
      · obtain ⟨conditionThreshold, bodyThreshold, conditionAfter, completion,
          bodyAfter, conditionRun, bodyRun, terminal, continuation⟩ := trueStep
        by_cases completesLoop : completion = .next ∨ completion = .continueLoop
        · obtain ⟨smaller, nextInvariant⟩ := continuation completesLoop
          have smaller' : measure bodyAfter < n := by
            simpa [← hn] using smaller
          obtain ⟨recursiveThreshold, finalCompletion, finalState,
            recursiveRun, recursiveDone⟩ :=
            ih (measure bodyAfter) smaller' bodyAfter nextInvariant (by rfl)
          let threshold := max (recursiveThreshold + 1)
            (max conditionThreshold bodyThreshold + 1)
          refine ⟨threshold, finalCompletion, finalState, ?_, recursiveDone⟩
          intro fuel enough
          have bounds : recursiveThreshold ≤ fuel - 1 ∧
              conditionThreshold ≤ fuel - 1 ∧ bodyThreshold ≤ fuel - 1 := by
            dsimp [threshold] at enough
            omega
          rw [← show (fuel - 1).succ = fuel by omega]
          apply execStmt_while_true_step (fuel := fuel - 1)
            program state condition body conditionAfter bodyAfter finalState
            completion finalCompletion
          · simpa [show fuel - 1 + 1 = fuel by omega] using
              conditionRun (fuel - 1) bounds.2.1
          · exact bodyRun (fuel - 1) bounds.2.2
          · exact completesLoop
          · exact recursiveRun (fuel - 1) bounds.1
        · have terminalDone : oracle.Done (normalizeCompletion completion) bodyAfter :=
            terminal (by
              constructor <;> intro equal
              · exact completesLoop (Or.inl equal)
              · exact completesLoop (Or.inr equal))
          have earlyRun := stableWhileEarly conditionRun bodyRun
            (by intro equal; exact completesLoop (Or.inl equal))
            (by intro equal; exact completesLoop (Or.inr equal))
          exact ⟨max conditionThreshold bodyThreshold + 1,
            normalizeCompletion completion, bodyAfter, earlyRun, terminalDone⟩

end Lanius.Semantics
