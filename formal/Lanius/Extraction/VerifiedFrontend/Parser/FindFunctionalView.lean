import Lanius.Extraction.VerifiedFrontend.Parser.Find
import Lanius.FunctionalViewCoreEffectfulStateful
import Lanius.FunctionalViewCoreStatefulReification

namespace Lanius.Extraction.ParserFind.Functional

open Lanius.Core
open Lanius.Typing
open Lanius.Semantics
open Lanius.Properties
open Lanius.Separation
open Lanius.Extraction.ParserFind
open Lanius.Compiler.Parser
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.ReadOnly
open Lanius.FunctionalView.Core.Stateful
open Lanius.FunctionalView.Core.Stateful.Reification

/-! # FunctionalView contract for `parser.lani::find_state`

The command below is mechanically recovered from the checked source artifact.
The call model exposes its logical lookup result without exposing the old
statement-by-statement execution proof to FunctionalView clients.
-/

def parameterLayout : Layout 4 := identityLayout

def parameterContext : Context :=
  Lanius.Typing.parameterContext extractedParserFindStateFunction.parameters

private def reification? :=
  reifyCommand? verifiedParserCore extractedParserFindStateFunction.returnType
    parameterContext false parameterLayout 4 extractedParserFindStateBody

theorem reification_exists : reification?.isSome := by
  native_decide

/-- The complete stateful FunctionalView command recovered from the extracted
    `find_state` body. -/
def view := reification?.get reification_exists

/-- FunctionalView lowers to the exact body decoded from `parser.json`. -/
theorem view_toCore_exactly :
    toCoreStmt actionAdapter parameterLayout 4 view.command =
      extractedParserFindStateBody :=
  view.toCoreExactly

def argumentValues (layout : WorkspaceLayout) (values : List Int)
    (workspaceCell : CellId) (position : Nat) (seed : StateSeed) :
    List Value := [
  workspaceValue values workspaceCell,
  .signed .i32 (Int.ofNat (stateBase layout.tokenCount)),
  .signed .i32 (Int.ofNat position),
  stateSeedValue seed]

def resultValue (workspace : LogicalWorkspace) (position : Nat)
    (seed : StateSeed) : Value :=
  .signed .i32 (encodeStateId (workspace.findStateId? position seed.key))

namespace Call

open Lanius.FunctionalView.Core.Effectful

/-- Functional semantics for the one concrete encoded workspace accepted by
    this registry. Other functions, argument tuples, and worlds are rejected
    rather than assigned unproved behavior. -/
noncomputable def calls (layout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (values : List Int) (workspaceCell : CellId) (position : Nat)
    (seed : StateSeed) : CallModel := by
  classical
  exact {
    evaluate := fun world function arguments =>
      if function = extractedParserFindStateFunction.id then
        if arguments = argumentValues layout values workspaceCell position seed then
          if world.i32Slice? workspaceCell = some values then
            .ok (resultValue workspace position seed, world)
          else
            .error .invalidPointer
        else
          .error .typeMismatch
      else
        .error .invalidPointer
  }

theorem evaluates_expected
    (found : world.i32Slice? workspaceCell = some values) :
    (calls layout workspace values workspaceCell position seed).evaluate world
        extractedParserFindStateFunction.id
        (argumentValues layout values workspaceCell position seed) =
      .ok (resultValue workspace position seed, world) := by
  simp [calls, found]

theorem success
    (evaluated :
      (calls layout workspace values workspaceCell position seed).evaluate
          world function arguments = .ok (value, afterWorld)) :
    function = extractedParserFindStateFunction.id ∧
      arguments = argumentValues layout values workspaceCell position seed ∧
      world.i32Slice? workspaceCell = some values ∧
      value = resultValue workspace position seed ∧
      afterWorld = world := by
  simp only [calls] at evaluated
  split at evaluated
  next functionEq =>
    split at evaluated
    next argumentsEq =>
      split at evaluated
      next found =>
        obtain ⟨rfl, rfl⟩ := evaluated
        exact ⟨functionEq, argumentsEq, found, rfl, rfl⟩
      next => contradiction
    next => contradiction
  next => contradiction

/-- Every successful functional call evaluation executes the checked
    source-extracted function, preserves the encoded workspace, and returns
    the logical `findStateId?` result. -/
theorem soundness
    (valuesLength : values.length = layout.workspaceLength)
    (encoded : EncodesWorkspace layout workspace (listWords values))
    (positionBound : position ≤ finalPosition layout.tokenCount) :
    Lanius.FunctionalView.Core.EffectfulStateful.CallSoundness
      verifiedParserCore
      (calls layout workspace values workspaceCell position seed) := by
  constructor
  · intro arity commandLayout localCell beforeWorld afterWorld environment
      before afterArguments function arguments argumentValues' value
      argumentWrites afterArgumentsWellFormed represented argumentsExecution
      argumentsEffect evaluated
    obtain ⟨functionEq, argumentsEq, found, valueEq, worldEq⟩ :=
      success evaluated
    subst function
    subst argumentValues'
    subst value
    subst afterWorld
    have backing := represented.worldOwned workspaceCell values found
    obtain ⟨after, callExecution, callEffect, afterWellFormed, afterBacking⟩ :=
      extractedParserFindStateCall_evaluates layout workspace values
        workspaceCell position seed before afterArguments
        (toCoreExprs commandLayout arguments) valuesLength encoded positionBound
        afterArgumentsWellFormed argumentsExecution backing
    have afterRepresented :
        Lanius.FunctionalView.Core.Stateful.Representation commandLayout
          localCell beforeWorld environment after := {
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
    exact ⟨after, CellSet.union argumentWrites CellSet.empty, callExecution,
      afterWellFormed, afterRepresented, argumentsEffect.trans callEffect⟩
  · intro beforeWorld afterWorld function arguments value evaluated cell
    exact congrArg (fun candidate =>
      (candidate.i32Slice? cell).map List.length) (success evaluated).2.2.2.2

end Call

end Lanius.Extraction.ParserFind.Functional
