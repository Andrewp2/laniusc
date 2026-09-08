import Lanius.FunctionalViewCoreEffectfulStateful

namespace Lanius.FunctionalView.StatefulFrame

open Lanius Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.FunctionalView Lanius.FunctionalView.Core Lanius.FunctionalView.Core.Stateful
open Lanius.FunctionalView.Stateful

/-- Expressions may update owned contents but cannot create or discard the
    abstract slice resources when their checked call registry preserves shape. -/
theorem term_footprint (calls : EffectfulStateful.CallSoundness program model)
    (evaluated : Term.evaluate (Effectful.machine program model) beforeWorld environment term =
      .ok (value, afterWorld)) :
    (ReadOnly.World.owns afterWorld).footprint = (ReadOnly.World.owns beforeWorld).footprint := by
  funext cell
  apply propext
  have shape := EffectfulStateful.term_evaluate_shape calls evaluated cell
  constructor
  · rintro ⟨contents, found⟩
    cases original : beforeWorld.i32Slice? cell with
    | none => simp [found, original] at shape
    | some values => exact ⟨values, original⟩
  · rintro ⟨contents, found⟩
    cases final : afterWorld.i32Slice? cell with
    | none => simp [found, final] at shape
    | some values => exact ⟨values, final⟩

theorem action_footprint (calls : EffectfulStateful.CallSoundness program model)
    (evaluated : (machineWith program (Effectful.evaluateOperation program model)).evalAction
      beforeWorld environment action = .ok afterWorld) :
    (ReadOnly.World.owns afterWorld).footprint = (ReadOnly.World.owns beforeWorld).footprint := by
  cases action with
  | setI32Index base index value =>
    change evaluateActionWith (Effectful.evaluateOperation program model) beforeWorld environment
      (.setI32Index base index value) = .ok afterWorld at evaluated
    cases indexResult : Term.evaluate (termMachine (Effectful.evaluateOperation program model)) beforeWorld environment index with
    | error reason => simp [evaluateActionWith, indexResult, bind, Except.bind] at evaluated
    | ok result =>
      obtain ⟨indexValue, indexWorld⟩ := result
      change Term.evaluate (termMachine (Effectful.evaluateOperation program model)) beforeWorld environment index =
        .ok (indexValue, indexWorld) at indexResult
      simp only [evaluateActionWith, indexResult, bind, Except.bind] at evaluated
      cases valueResult : Term.evaluate (termMachine (Effectful.evaluateOperation program model))
          indexWorld environment value with
      | error reason => rw [valueResult] at evaluated; contradiction
      | ok result =>
        obtain ⟨replacementValue, rightWorld⟩ := result
        rw [valueResult] at evaluated
        simp only [bind, Except.bind] at evaluated
        obtain ⟨cell, values, position, replacement, _, _, _, found, _, rfl⟩ := writeI32Slice_result evaluated
        exact (ReadOnly.World.setI32Slice_footprint found).trans
          ((term_footprint calls valueResult).trans (term_footprint calls indexResult))

/-- Whole-command resource membership is invariant, including loops, early
    returns, and stores. This is a logical resource fact, not a physical
    write-footprint claim by itself. -/
theorem command_footprint (calls : EffectfulStateful.CallSoundness program model)
    (evaluated : Command.Evaluates (Effectful.machine program model)
      (machineWith program (Effectful.evaluateOperation program model))
      beforeWorld environment command completion afterWorld afterEnvironment) :
    (ReadOnly.World.owns afterWorld).footprint = (ReadOnly.World.owns beforeWorld).footprint := by
  induction evaluated with
  | skip | breakLoop | continueLoop | returnNone => rfl
  | sequenceNext first second firstIH secondIH => exact secondIH.trans firstIH
  | sequenceStop first stops firstIH => exact firstIH
  | letValue initialized body bodyIH => exact bodyIH.trans (term_footprint calls initialized)
  | setLocal evaluated => exact term_footprint calls evaluated
  | updateLocal evaluated updated => exact term_footprint calls evaluated
  | action evaluated => exact action_footprint calls evaluated
  | ifTrue condition branch branchIH | ifFalse condition branch branchIH =>
    exact branchIH.trans (term_footprint calls condition)
  | whileFalse condition => exact term_footprint calls condition
  | whileNext condition body rest bodyIH restIH | whileContinue condition body rest bodyIH restIH =>
    exact restIH.trans (bodyIH.trans (term_footprint calls condition))
  | whileBreak condition body bodyIH | whileReturn condition body bodyIH =>
    exact bodyIH.trans (term_footprint calls condition)
  | returnSome evaluated => exact term_footprint calls evaluated

end Lanius.FunctionalView.StatefulFrame
