import Lanius.FunctionalView.Stateful.Footprint
import Lanius.FunctionalViewCoreFreshSimulation

namespace Lanius.FunctionalView.StatefulFrame

open Lanius Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.FunctionalView Lanius.FunctionalView.Core Lanius.FunctionalView.Core.Stateful
open Lanius.FunctionalView.Stateful Lanius.FunctionalView.FreshSimulation

/-- A store with caller-preserving argument calls can modify only an owned
    slice. The argument expressions, address, and store all execute here;
    the caller does not supply a physical write-footprint certificate. -/
theorem action_executes (calls : EffectfulStateful.CallSoundness program model)
    (operations : FramePreservingOperationSoundness program model)
    (wellFormed : StateWellFormed before)
    (represented : Representation layout localCell world environment before)
    (evaluated : (machineWith program (Effectful.evaluateOperation program model)).evalAction
      world environment action = .ok afterWorld) :
    ∃ after, Executes program before (actionAdapter.toCoreStmt layout action) .next after ∧
      StateWellFormed after ∧ Representation layout localCell afterWorld environment after ∧
      ModifiesOnly (ReadOnly.World.owns world).footprint before after := by
  cases action with
  | setI32Index base index value =>
    change evaluateActionWith (Effectful.evaluateOperation program model) world environment
      (.setI32Index base index value) = .ok afterWorld at evaluated
    cases indexResult : Term.evaluate (termMachine (Effectful.evaluateOperation program model)) world environment index with
    | error reason => simp [evaluateActionWith, indexResult, bind, Except.bind] at evaluated
    | ok result =>
      obtain ⟨indexValue, indexWorld⟩ := result
      simp only [evaluateActionWith, indexResult, bind, Except.bind] at evaluated
      obtain ⟨afterIndex, indexExecution, indexWF, indexRepresented, indexEffect⟩ :=
        termSoundness operations wellFormed represented indexResult
      cases valueResult : Term.evaluate (termMachine (Effectful.evaluateOperation program model))
          indexWorld environment value with
      | error reason => rw [valueResult] at evaluated; contradiction
      | ok result =>
        obtain ⟨replacementValue, rightWorld⟩ := result
        rw [valueResult] at evaluated
        simp only [bind, Except.bind] at evaluated
        obtain ⟨afterRight, rightExecution, rightWF, rightRepresented, rightEffect⟩ :=
          termSoundness operations indexWF indexRepresented valueResult
        obtain ⟨cell, rightValues, position, replacement, baseValue, indexEq, replacementEq,
          foundRight, inBounds, rfl⟩ := writeI32Slice_result evaluated
        subst indexValue
        subst replacementValue
        have shape := EffectfulStateful.term_evaluate_shape calls valueResult cell
        rw [foundRight] at shape
        cases foundIndex : indexWorld.i32Slice? cell with
        | none => simp [foundIndex] at shape
        | some indexValues =>
          have sameLength : indexValues.length = rightValues.length := by
            simpa [foundIndex] using shape.symm
          obtain ⟨after, executed, afterWF, afterRepresented, effect⟩ :=
            EffectfulStateful.Representation.setI32IndexAfterTerms represented indexRepresented rightRepresented rightWF
              baseValue indexExecution indexEffect rightExecution rightEffect foundIndex foundRight sameLength inBounds
          refine ⟨after, executed, afterWF, afterRepresented, effect.weaken ?_⟩
          intro candidate written
          rcases written with impossible | impossible | same
          · exact False.elim impossible
          · exact False.elim impossible
          · change candidate = cell at same
            subst candidate
            rw [← term_footprint calls indexResult]
            exact ⟨indexValues, foundIndex⟩

end Lanius.FunctionalView.StatefulFrame
