import Lanius.Semantics
import Lean.Elab.Tactic
import Lean.Elab.Tactic.Split

namespace Lanius.Semantics

open Lanius.Core

/-- Fuel exhaustion carries no observation. Every completed outcome retains
    its value or reason and its full state when refined. -/
def Outcome.Refines (first second : Outcome α) : Prop :=
  first = .outOfFuel ∨ second = first

theorem Outcome.Refines.refl (result : Outcome α) : result.Refines result := .inr rfl
theorem Outcome.Refines.pending (result : Outcome α) : Outcome.outOfFuel.Refines result := .inl rfl

theorem Outcome.Refines.completed {first second : Outcome α} (refined : first.Refines second)
    (finished : first ≠ .outOfFuel) : second = first :=
  refined.resolve_left finished

theorem Outcome.Refines.trans {first middle last : Outcome α}
    (one : first.Refines middle) (two : middle.Refines last) : first.Refines last := by
  rcases one with pending | rfl
  · exact .inl pending
  · exact two

/-- All seven mutually recursive entry points advance together. The invariant
    quantifies over every program, state and input; typing is not a premise. -/
private structure FuelStep (fuel : Nat) : Prop where
  expression : ∀ program state expression,
    (evalExpr fuel program state expression).Refines (evalExpr (fuel + 1) program state expression)
  expressions : ∀ program state expressions,
    (evalExprs fuel program state expressions).Refines (evalExprs (fuel + 1) program state expressions)
  matching : ∀ program state value arms,
    (evalMatchArms fuel program state value arms).Refines (evalMatchArms (fuel + 1) program state value arms)
  place : ∀ program state access place,
    (evalPlace fuel program state access place).Refines (evalPlace (fuel + 1) program state access place)
  valuesLoop : ∀ program state id values body,
    (execForValues fuel program state id values body).Refines (execForValues (fuel + 1) program state id values body)
  rangeLoop : ∀ program state id current stop inclusive body,
    (execForRange fuel program state id current stop inclusive body).Refines
      (execForRange (fuel + 1) program state id current stop inclusive body)
  statement : ∀ program state statement,
    (execStmt fuel program state statement).Refines (execStmt (fuel + 1) program state statement)

open Lean Meta Elab Tactic in
private def recursiveEntries : Array (Name × Name × Nat) := #[
  (``evalExpr, ``FuelStep.expression, 4), (``evalExprs, ``FuelStep.expressions, 4),
  (``evalMatchArms, ``FuelStep.matching, 5), (``evalPlace, ``FuelStep.place, 5),
  (``execForValues, ``FuelStep.valuesLoop, 6), (``execForRange, ``FuelStep.rangeLoop, 8),
  (``execStmt, ``FuelStep.statement, 4)]

open Lean Meta Elab Tactic in
/-- Transport recursive outcomes using the mutual induction hypothesis before
    splitting the evaluator's remaining, fuel-independent branches. -/
private partial def solveFuelStep (ih : Ident) : TacticM Unit := withMainContext do
    let goal ← getMainGoal
    let target ← instantiateMVars (← goal.getType)
    unless target.isAppOfArity ``Outcome.Refines 3 do throwError "expected an outcome refinement"
    let old := target.getAppArgs[1]!
    let next := target.getAppArgs[2]!
    if old == next then
      evalTactic (← `(tactic| exact Outcome.Refines.refl _))
      return
    if (← whnf old).isAppOf ``Outcome.outOfFuel then
      evalTactic (← `(tactic| exact Outcome.Refines.pending _))
      return
    for (entry, field, arity) in recursiveEntries do
      if let some call := old.find? (fun e => !e.hasLooseBVars && e.isAppOfArity entry arity) then
        let args := call.getAppArgs
        let larger? := next.find? (fun e => !e.hasLooseBVars && e.isAppOfArity entry arity &&
          (e.getAppArgs.extract 1 arity) == args.extract 1 arity)
        if let some larger := larger? then
          unless ← isDefEq larger.getAppArgs[0]! (mkApp (mkConst ``Nat.succ) args[0]!) do continue
          let hypothesis ← getFVarId ih
          let proof ← mkAppM field #[mkFVar hypothesis]
          let proof := mkAppN proof (args.extract 1 args.size)
          let proofSyntax ← Term.exprToSyntax proof
          evalTactic (← `(tactic| rcases ($proofSyntax) with pending | same))
          let branches ← getGoals
          for branch in branches do
            setGoals [branch]
            evalTactic (← `(tactic| first | rw [pending] | rw [same]))
            solveFuelStep ih
          setGoals []
          return
    let some branches ← Lean.Meta.splitTarget? goal | throwError "no recursive refinement or common branch:\n{MessageData.ofGoal goal}"
    for branch in branches do
      setGoals [branch]
      evalTactic (← `(tactic| try simp_all only [Nat.succ.injEq, Nat.add_one]))
      evalTactic (← `(tactic| try dsimp only [restoreOutcomeLocals]))
      unless (← getGoals).isEmpty do solveFuelStep ih
    setGoals []

open Lean Meta Elab Tactic in
elab "fuel_step" ih:ident : tactic => do
  evalTactic (← `(tactic| try simp only [Nat.add_one]))
  solveFuelStep ih

private theorem fuelStep (fuel : Nat) : FuelStep fuel := by
  induction fuel with
  | zero =>
    constructor <;> intros <;> exact .pending _
  | succ fuel ih =>
    constructor
    all_goals intros
    · conv => lhs; rw [evalExpr.eq_def]
      conv => rhs; rw [evalExpr.eq_def]
      fuel_step ih
    · conv => lhs; rw [evalExprs.eq_def]
      conv => rhs; rw [evalExprs.eq_def]
      fuel_step ih
    · conv => lhs; rw [evalMatchArms.eq_def]
      conv => rhs; rw [evalMatchArms.eq_def]
      fuel_step ih
    · conv => lhs; rw [evalPlace.eq_def]
      conv => rhs; rw [evalPlace.eq_def]
      fuel_step ih
    · conv => lhs; rw [execForValues.eq_def]
      conv => rhs; rw [execForValues.eq_def]
      fuel_step ih
    · conv => lhs; rw [execForRange.eq_def]
      conv => rhs; rw [execForRange.eq_def]
      fuel_step ih
    · conv => lhs; rw [execStmt.eq_def]
      conv => rhs; rw [execStmt.eq_def]
      fuel_step ih

private theorem refinements (run : Nat → Outcome α)
    (step : ∀ fuel, (run fuel).Refines (run (fuel + 1))) (enough : low ≤ high) :
    (run low).Refines (run high) := by
  obtain ⟨difference, rfl⟩ := Nat.exists_eq_add_of_le enough
  clear enough
  induction difference with
  | zero => exact .refl _
  | succ difference ih => exact ih.trans (step (low + difference))

/-- Increasing fuel cannot change a completed value, trap, exit or state.
    Exhaustion alone may be replaced by any later outcome. -/
theorem evalExpr_refines (enough : low ≤ high) :
    (evalExpr low program state expression).Refines (evalExpr high program state expression) :=
  refinements _ (fun fuel => (fuelStep fuel).expression _ _ _) enough

theorem evalExprs_refines (enough : low ≤ high) :
    (evalExprs low program state expressions).Refines (evalExprs high program state expressions) :=
  refinements _ (fun fuel => (fuelStep fuel).expressions _ _ _) enough

theorem evalMatchArms_refines (enough : low ≤ high) :
    (evalMatchArms low program state value arms).Refines (evalMatchArms high program state value arms) :=
  refinements _ (fun fuel => (fuelStep fuel).matching _ _ _ _) enough

theorem evalPlace_refines (enough : low ≤ high) :
    (evalPlace low program state access place).Refines (evalPlace high program state access place) :=
  refinements _ (fun fuel => (fuelStep fuel).place _ _ _ _) enough

theorem execForValues_refines {id : VarId} (enough : low ≤ high) :
    (execForValues low program state id values body).Refines (execForValues high program state id values body) :=
  refinements _ (fun fuel => (fuelStep fuel).valuesLoop _ _ _ _ _) enough

theorem execForRange_refines {id : VarId} (enough : low ≤ high) :
    (execForRange low program state id current stop inclusive body).Refines
      (execForRange high program state id current stop inclusive body) :=
  refinements _ (fun fuel => (fuelStep fuel).rangeLoop _ _ _ _ _ _ _) enough

theorem execStmt_refines (enough : low ≤ high) :
    (execStmt low program state statement).Refines (execStmt high program state statement) :=
  refinements _ (fun fuel => (fuelStep fuel).statement _ _ _) enough

theorem evalExpr_of_le (run : evalExpr low program state expression = outcome)
    (finished : outcome ≠ .outOfFuel) (enough : low ≤ high) :
    evalExpr high program state expression = outcome :=
  (run ▸ evalExpr_refines (program := program) (state := state) (expression := expression) enough).completed finished

theorem execStmt_of_le (run : execStmt low program state statement = outcome)
    (finished : outcome ≠ .outOfFuel) (enough : low ≤ high) :
    execStmt high program state statement = outcome :=
  (run ▸ execStmt_refines (program := program) (state := state) (statement := statement) enough).completed finished

/-- Compare observations at a common budget. This establishes uniqueness
    across different fuel values, not merely determinism of a fixed function. -/
private theorem uniqueOutcome (run : Nat → Outcome α)
    (monotone : ∀ {low high}, low ≤ high → (run low).Refines (run high))
    (one : run firstFuel = first) (firstFinished : first ≠ .outOfFuel)
    (two : run secondFuel = second) (secondFinished : second ≠ .outOfFuel) : first = second := by
  have firstAt := (one ▸ monotone (Nat.le_max_left firstFuel secondFuel)).completed firstFinished
  have secondAt := (two ▸ monotone (Nat.le_max_right firstFuel secondFuel)).completed secondFinished
  exact firstAt.symm.trans secondAt

theorem evalExpr_unique (one : evalExpr firstFuel program state expression = first)
    (firstFinished : first ≠ .outOfFuel) (two : evalExpr secondFuel program state expression = second)
    (secondFinished : second ≠ .outOfFuel) : first = second :=
  uniqueOutcome _ (fun enough => evalExpr_refines enough) one firstFinished two secondFinished

theorem execStmt_unique (one : execStmt firstFuel program state statement = first)
    (firstFinished : first ≠ .outOfFuel) (two : execStmt secondFuel program state statement = second)
    (secondFinished : second ≠ .outOfFuel) : first = second :=
  uniqueOutcome _ (fun enough => execStmt_refines enough) one firstFinished two secondFinished

theorem Evaluates.unique (one : Evaluates program state expression value after)
    (two : Evaluates program state expression other final) : value = other ∧ after = final := by
  obtain ⟨firstFuel, first⟩ := one
  obtain ⟨secondFuel, second⟩ := two
  exact Outcome.done.inj (evalExpr_unique first (by intro h; cases h) second (by intro h; cases h))

theorem Executes.unique (one : Executes program state statement completion after)
    (two : Executes program state statement other final) : completion = other ∧ after = final := by
  obtain ⟨firstFuel, first⟩ := one
  obtain ⟨secondFuel, second⟩ := two
  exact Outcome.done.inj (execStmt_unique first (by intro h; cases h) second (by intro h; cases h))

theorem Evaluates.not_traps (run : Evaluates program state expression value after) :
    ¬ Traps program state expression reason final := by
  rintro ⟨secondFuel, second⟩
  obtain ⟨firstFuel, first⟩ := run
  cases evalExpr_unique first (by intro h; cases h) second (by intro h; cases h)

#print axioms evalExpr_refines
#print axioms execStmt_refines
#print axioms evalExpr_unique
#print axioms Evaluates.not_traps

end Lanius.Semantics
