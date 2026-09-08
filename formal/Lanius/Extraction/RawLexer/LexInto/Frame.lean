import Lanius.Extraction.RawLexer.LexInto.EndToEnd
import Lanius.Extraction.RawLexer.LexInto.Buffer
import Lanius.FunctionalView.Stateful.Frame
import Lanius.FunctionalViewCoreCallFrame
import Lanius.Separation.CellEffect

namespace Lanius.Extraction.RawLexer.LexInto.Frame

open Lanius Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView Lanius.FunctionalView.Core Lanius.FunctionalView.Core.Stateful
open Lanius.FunctionalView.FreshSimulation Lanius.Extraction.RawLexer.LexInto.Functions

/-- Reuse the existing complete lexer algorithm proof with a concrete physical
    frame. The source buffer is removed from the write set using its exact
    preserved representation, not an assumed read-only execution. -/
theorem body_executes (request : Model.Request) (records : List Int)
    (recordsCapacity : 3 * request.capacity ≤ records.length)
    (represented : Representation identityLayout localCell (Execution.world request.source records)
      (Execution.initialEnvironment request.source records request.capacity) before)
    (wellFormed : StateWellFormed before)
    (localsFresh : LocalsFresh frontier localCell) (nextFresh : frontier ≤ before.nextCell) :
    ∃ after, Executes verifiedFrontendCore before lexIntoBody
        (.returned (some (Model.resultValue request.outcome))) after ∧
      StateWellFormed after ∧
      Representation identityLayout localCell
        (Execution.world request.source (Model.run request.source request.capacity records).records)
        (Execution.initialEnvironment request.source (Model.run request.source request.capacity records).records request.capacity)
        after ∧
      ModifiesOnly (CellSet.union (CellSet.singleton 1) (freshCells frontier)) before after := by
  obtain ⟨after, execution, afterWF, afterRepresented, effect⟩ :=
    StatefulFrame.command_executes (Calls.callSoundness request.source)
      (operationSoundness verifiedFrontendCore (Calls.callModel request.source)
        (Calls.framePreservingCallSoundness request.source))
      (Execution.command_evaluates_request request records recordsCapacity)
      represented (LayoutBelow.identity (arity := 4)) wellFormed localsFresh nextFresh
  rw [Structure.command_toCore_exactly, Model.run_outcome] at execution
  refine ⟨after, execution, afterWF, afterRepresented, { effect with oldCells := ?_ }⟩
  intro cell old untouched
  by_cases source : cell = 0
  · subst cell
    exact (afterRepresented.worldOwned 0 _ (Execution.world_source _ _)).trans
      (represented.worldOwned 0 _ (Execution.world_source _ _)).symm
  · apply effect.oldCells cell old
    intro written
    rcases written with ⟨values, found⟩ | fresh
    · have output : cell = 1 := by
        by_cases different : cell = 1
        · exact different
        · simp [Execution.world, ReadOnly.World.pair, source, different] at found
      exact untouched (Or.inl output)
    · exact untouched (Or.inr fresh)

/-- The actual source call in model buffer coordinates. The caller supplies
    ordinary argument evaluation and owned storage, not callee locals or a
    frame certificate. Fresh parameter/cursor writes disappear on return. -/
theorem call_executes (request : Model.Request) (records : List Int)
    (recordsCapacity : 3 * request.capacity ≤ records.length)
    (wellFormed : StateWellFormed afterArguments)
    (owned : (ReadOnly.World.owns (Execution.world request.source records)).holds afterArguments)
    (argumentsResult : ArgumentsEvaluateTo verifiedFrontendCore before arguments
      [.slice Structure.i32Type 0 [] 0 request.source.length, .signed .i32 request.source.length,
        .slice Structure.i32Type 1 [] 0 records.length, .signed .i32 request.capacity] afterArguments) :
    ∃ after, Evaluates verifiedFrontendCore before (.call lexIntoFunction.id arguments)
        (Model.resultValue request.outcome) after ∧
      (ReadOnly.World.owns (Execution.world request.source
        (CanonicalTokens.CanonicalizeModel.encodeTokens (Model.emittedTokens request.outcome) ++
          records.drop (3 * (Model.emittedTokens request.outcome).length)))).holds after ∧
      CellEffect (CellSet.singleton 1) afterArguments after := by
  let environment := Execution.initialEnvironment request.source records request.capacity
  let bindings := parameterBindings environment
  have emptyRepresentation : Representation (identityLayout (arity := 0)) (fun index => Fin.elim0 index)
      (Execution.world request.source records) (fun index => Fin.elim0 index) afterArguments := {
    worldOwned := owned
    localOwned := fun index => Fin.elim0 index
    localCellsInjective := fun index => Fin.elim0 index
    worldLocalsDisjoint := by
      intro cell worldMember localMember
      obtain ⟨index, _⟩ := localMember
      exact Fin.elim0 index
  }
  have represented := emptyRepresentation.enterCallParameters (environment := environment) wellFormed
  obtain ⟨completed, executed, completedWF, completedRepresentation, bodyEffect⟩ :=
    body_executes request records recordsCapacity represented (enterCall_preserves_wellFormed wellFormed)
      (frontier := afterArguments.nextCell) (fun index => Nat.le_add_right _ _)
      (enterCall_effect afterArguments bindings).nextCell
  have bound : bindParameters lexIntoFunction.parameters
      [.slice Structure.i32Type 0 [] 0 request.source.length, .signed .i32 request.source.length,
        .slice Structure.i32Type 1 [] 0 records.length, .signed .i32 request.capacity] = some bindings := by rfl
  have buffers := completedRepresentation.worldOwned
  rw [run_records_prefix request.source request.capacity records recordsCapacity] at buffers
  have closed := CellEffect.closeCall afterArguments bindings wellFormed
    (CellEffect.ofModifiesOnly bodyEffect completedWF)
  refine ⟨restoreLocals afterArguments completed,
    evaluatesCallReturned argumentsResult verifiedFrontendCore_finds_lexInto bound lexInto_has_body executed,
    buffers, closed.narrow ?_⟩
  intro cell old written
  rcases written with output | fresh
  · exact output
  · exact (Nat.not_le_of_lt old fresh).elim

end Lanius.Extraction.RawLexer.LexInto.Frame
