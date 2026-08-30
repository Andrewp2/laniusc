import Lanius.Extraction.VerifiedParserValidation
import Lanius.FunctionalViewCoreStatefulReification
import Lanius.FunctionalViewCoreEffectfulStateful

namespace Lanius.Extraction.ParserValidation.FunctionalView

open Lanius.Core
open Lanius.Typing
open Lanius.Semantics
open Lanius.Properties
open Lanius.Separation
open Lanius.CallContracts
open Lanius.Compiler.Parser
open Lanius.Extraction.ParserAccessors
open Lanius.Extraction.ParserValidation
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.ReadOnly
open Lanius.FunctionalView.Core.Effectful
open Lanius.FunctionalView.Core.Stateful
open Lanius.FunctionalView.Core.Stateful.Reification

/-! # FunctionalView representation of `grammar_is_valid`

The command below is mechanically recovered from the checked `parser.lani`
artifact.  Its round-trip theorem ensures that the proof-facing program
contains exactly the extracted guards, reads, loops, helper calls, and returns.
-/

def parameterLayout : Layout 2 := identityLayout

def parameterContext : Context :=
  Lanius.Typing.parameterContext
    extractedParserGrammarValidFunction.parameters

private def reification? :=
  reifyCommand? verifiedParserCore extractedParserGrammarValidFunction.returnType
    parameterContext false parameterLayout 2 extractedParserGrammarValidBody

theorem reification_exists : reification?.isSome := by
  native_decide

/-- The complete mutable FunctionalView command recovered from the real
    `parser.lani::grammar_is_valid` function. -/
def view := reification?.get reification_exists

/-- Lowering the proof-facing command recreates the checked Core body exactly. -/
theorem view_toCore_exactly :
    toCoreStmt actionAdapter parameterLayout 2 view.command =
      extractedParserGrammarValidBody :=
  view.toCoreExactly

/-- Partial functional call semantics for the validated grammar accepted by
    the source-derived semantic contract. -/
noncomputable def calls (words : List Int) (grammarCell : CellId) : CallModel := by
  classical
  exact {
    evaluate := fun world function values =>
      if function = extractedParserGrammarValidFunction.id then
        if values = [parserGrammarValue words grammarCell,
            .signed .i32 (Int.ofNat words.length)] then
          if world.i32Slice? grammarCell = some words then
            .ok (.boolean true, world)
          else
            .error .invalidPointer
        else
          .error .typeMismatch
      else
        .error .invalidPointer
  }

theorem calls_at_encoded_arguments
    (found : world.i32Slice? grammarCell = some words) :
    (calls words grammarCell).evaluate world
        extractedParserGrammarValidFunction.id
        [parserGrammarValue words grammarCell,
          .signed .i32 (Int.ofNat words.length)] =
      .ok (.boolean true, world) := by
  simp [calls, found]

theorem calls_success
    (evaluated : (calls words grammarCell).evaluate world function values =
      .ok (value, afterWorld)) :
    function = extractedParserGrammarValidFunction.id ∧
      values = [parserGrammarValue words grammarCell,
        .signed .i32 (Int.ofNat words.length)] ∧
      world.i32Slice? grammarCell = some words ∧
      value = .boolean true ∧ afterWorld = world := by
  simp only [calls] at evaluated
  split at evaluated
  next functionEq =>
    split at evaluated
    next valuesEq =>
      split at evaluated
      next found =>
        obtain ⟨rfl, rfl⟩ := evaluated
        exact ⟨functionEq, valuesEq, found, rfl, rfl⟩
      next => contradiction
    next => contradiction
  next => contradiction

/-- Every successful modeled validator call executes the exact checked source
    function, returns `true`, and preserves all caller-owned memory and locals. -/
theorem call_soundness
    (encoded : EncodesGrammar layout grammar words)
    (grammarWellFormed : grammar.WellFormed)
    (wordsI32 : words.length ≤ 2147483647) :
    Lanius.FunctionalView.Core.EffectfulStateful.CallSoundness
      verifiedParserCore (calls words grammarCell) := by
  constructor
  · intro arity commandLayout localCell beforeWorld afterWorld environment
      before afterArguments function arguments values value argumentWrites
      afterArgumentsWellFormed represented argumentsExecution argumentsEffect
      evaluated
    obtain ⟨functionEq, valuesEq, found, valueEq, worldEq⟩ :=
      calls_success evaluated
    subst function
    subst values
    subst value
    subst afterWorld
    let callee := parserGrammarValidCallee afterArguments words grammarCell
    have calleeWellFormed : StateWellFormed callee := by
      simpa [callee, parserGrammarValidCallee, parserGrammarValidBindings] using
        (enterCall_preserves_wellFormed
          (bindings := parserGrammarValidBindings words grammarCell)
          afterArgumentsWellFormed)
    have grammarLocal : callee.local? 0 =
        some (parserGrammarValue words grammarCell) := by
      simpa [callee, parserGrammarValidCallee, parserGrammarValidBindings] using
        enterCall_local_of_binding afterArguments []
          [(1, .signed .i32 (Int.ofNat words.length))] 0
          (parserGrammarValue words grammarCell) afterArgumentsWellFormed
          (by simp)
    have grammarLengthLocal : callee.local? 1 =
        some (.signed .i32 (Int.ofNat words.length)) := by
      simpa [callee, parserGrammarValidCallee, parserGrammarValidBindings] using
        enterCall_local_of_binding afterArguments
          [(0, parserGrammarValue words grammarCell)] [] 1
          (.signed .i32 (Int.ofNat words.length)) afterArgumentsWellFormed
          (by simp)
    have argumentBacking := represented.worldOwned grammarCell words found
    have grammarBacking : callee.cellEntry? grammarCell = some {
        id := grammarCell
        value := some (.array (signedI32Values words)) } := by
      have old := StateWellFormed.cell_lt_next_of_entry
        afterArgumentsWellFormed argumentBacking
      exact ((enterCall_effect afterArguments
        (parserGrammarValidBindings words grammarCell)).oldCells grammarCell old
          (by simp [CellSet.empty])).trans argumentBacking
    have invariant : GrammarValidationInvariant layout grammar words grammarCell
        callee := {
      encoded := encoded
      grammarWellFormed := grammarWellFormed
      wordsI32 := wordsI32
      stateWellFormed := calleeWellFormed
      grammarLocal := grammarLocal
      grammarLengthLocal := grammarLengthLocal
      grammarBacking := grammarBacking
    }
    obtain ⟨after, callExecution, callEffect, afterWellFormed⟩ :=
      extractedParserGrammarValidCall_accepts_encoded before afterArguments
        (toCoreExprs commandLayout arguments) argumentsExecution invariant
        afterArgumentsWellFormed
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
    exact ⟨after, CellSet.union argumentWrites CellSet.empty, callExecution,
      afterWellFormed, afterRepresented, argumentsEffect.trans callEffect⟩
  · intro beforeWorld afterWorld function values value evaluated cell
    exact congrArg (fun currentWorld =>
      (currentWorld.i32Slice? cell).map List.length)
      (calls_success evaluated).2.2.2.2

end Lanius.Extraction.ParserValidation.FunctionalView
