import Lanius.Extraction.VerifiedFrontend.Parser.Basics
import Lanius.FunctionalViewCoreEffectfulStateful
import Lanius.FunctionalViewCoreStatefulReification

namespace Lanius.Extraction.ParserRange.FunctionalView

open Lanius.Core
open Lanius.Typing
open Lanius.Semantics
open Lanius.Properties
open Lanius.Separation
open Lanius.Extraction.ParserBasics
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.ReadOnly
open Lanius.FunctionalView.Core.Effectful
open Lanius.FunctionalView.Core.Stateful
open Lanius.FunctionalView.Core.Stateful.Reification

/-! # FunctionalView representation of `parser.lani::range_valid` -/

def parameterLayout : Layout 3 := identityLayout

def parameterContext : Context :=
  Lanius.Typing.parameterContext extractedParserRangeValidFunction.parameters

private def reification? :=
  reifyCommand? verifiedParserCore extractedParserRangeValidFunction.returnType
    parameterContext false parameterLayout 3 parserRangeValidBody

theorem reification_exists : reification?.isSome := by
  native_decide

def view := reification?.get reification_exists

theorem view_toCore_exactly :
    toCoreStmt actionAdapter parameterLayout 3 view.command =
      parserRangeValidBody :=
  view.toCoreExactly

theorem semantic_body_agrees_with_reification :
    toCoreStmt parameterLayout 3 ParserBasics.Proof.body =
      toCoreStmt actionAdapter parameterLayout 3 view.command := by
  calc
    _ = parserRangeValidBody := by
      simpa [parameterLayout] using ParserBasics.Proof.body_toCore_exactly
    _ = _ := view_toCore_exactly.symm

def arguments (offset count length : Int) : List Value := [
  .signed .i32 offset, .signed .i32 count, .signed .i32 length]

def result (offset count length : Int) : Value :=
  .boolean (parserRangeValidValue verifiedParserCore.target offset count length)

def calls : CallModel where
  evaluate := fun world function values =>
    if function = extractedParserRangeValidFunction.id then
      match values with
      | [.signed .i32 offset, .signed .i32 count, .signed .i32 length] =>
          .ok (result offset count length, world)
      | _ => .error .typeMismatch
    else
      .error .invalidPointer

theorem calls_at_arguments :
    calls.evaluate world extractedParserRangeValidFunction.id
        (arguments offset count length) =
      .ok (result offset count length, world) := by
  simp [calls, arguments, result]

theorem calls_success
    (evaluated : calls.evaluate world function values =
      .ok (value, afterWorld)) :
    ∃ offset count length,
      function = extractedParserRangeValidFunction.id ∧
      values = arguments offset count length ∧
      value = result offset count length ∧
      afterWorld = world := by
  simp only [calls] at evaluated
  split at evaluated
  next functionEq =>
    split at evaluated
    next offset count length =>
      obtain ⟨rfl, rfl⟩ := evaluated
      exact ⟨offset, count, length, functionEq, rfl, rfl, rfl⟩
    next => contradiction
  next => contradiction

theorem call_soundness :
    Lanius.FunctionalView.Core.EffectfulStateful.CallSoundness
      verifiedParserCore calls := by
  constructor
  · intro arity commandLayout localCell beforeWorld afterWorld environment
      before afterArguments function callArguments values value argumentWrites
      afterArgumentsWellFormed represented argumentsExecution argumentsEffect
      evaluated
    obtain ⟨offset, count, length, functionEq, valuesEq, valueEq, worldEq⟩ :=
      calls_success evaluated
    subst function
    subst values
    subst value
    subst afterWorld
    obtain ⟨callExecution, callEffect, afterWellFormed⟩ :=
      extractedParserRangeValidCall_evaluates before afterArguments
        (toCoreExprs commandLayout callArguments) offset count length
        afterArgumentsWellFormed argumentsExecution
    let after := restoreLocals afterArguments
      (parserRangeValidCallee afterArguments offset count length)
    have afterRepresented : Representation commandLayout localCell beforeWorld
        environment after := {
      worldOwned := callEffect.empty_preserves_assertion
        afterArgumentsWellFormed (World.owns beforeWorld)
        represented.worldOwned
      localOwned := fun index => callEffect.empty_preserves_assertion
        afterArgumentsWellFormed
        (Assertion.localPointsTo (commandLayout index) (localCell index)
          (some (environment index))) (represented.localOwned index)
      localCellsInjective := represented.localCellsInjective
      worldLocalsDisjoint := represented.worldLocalsDisjoint
    }
    exact ⟨after, CellSet.union argumentWrites CellSet.empty,
      by simpa [after, arguments, result] using callExecution,
      afterWellFormed, afterRepresented, argumentsEffect.trans callEffect⟩
  · intro beforeWorld afterWorld function values value evaluated cell
    obtain ⟨offset, count, length, functionEq, valuesEq, valueEq, worldEq⟩ :=
      calls_success evaluated
    exact congrArg (fun currentWorld : World =>
      (currentWorld.i32Slice? cell).map List.length) worldEq

end Lanius.Extraction.ParserRange.FunctionalView
