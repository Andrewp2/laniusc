import Lanius.Extraction.RawLexer.LexInto.Execution
import Lanius.FunctionalViewCoreEffectfulStateful
import Lanius.CallContracts

namespace Lanius.Extraction.RawLexer.LexInto.EndToEnd

open Lanius
open Lanius.Core
open Lanius.Semantics
open Lanius.Properties
open Lanius.Separation
open Lanius.CallContracts
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.Stateful
open Lanius.Extraction.RawLexer.LexInto.Functions

/-! # Checked end-to-end execution of `raw_lexer.lani::lex_into`

The functional loop theorem is lifted through the exact Stateful-to-Core
simulation.  The helper-call soundness premise is discharged by the concrete
merged frontend registry below; keeping this lower lemma explicit makes the
simulation boundary reusable without weakening the public theorem.
-/

/-- A fully supported physical invocation.  The record-length equality is part
of the contract rather than a latent theorem-side assumption, so a caller
cannot obtain the success theorem for an undersized output slice. -/
structure Invocation extends Model.Request where
  records : List Int
  recordsLength : records.length = 3 * capacity

theorem output_records_exact (request : Model.Request) (records : List Int) :
    (Model.run request.source request.capacity records).records =
      Model.writeTokens records 0 (Model.emittedTokens request.outcome) := by
  exact Model.run_records request.source request.capacity records

theorem checkedBody_executes
    (request : Model.Request) (records : List Int)
    (recordsLength : records.length = 3 * request.capacity)
    (callSoundness :
      Lanius.FunctionalView.Core.EffectfulStateful.CallSoundness
        verifiedFrontendCore (Calls.callModel request.source))
    {localCell : Fin 4 → CellId} {state : State}
    (represented : Representation identityLayout localCell
      (Execution.world request.source records)
      (Execution.initialEnvironment request.source records request.capacity)
      state)
    (wellFormed : StateWellFormed state) :
    ∃ after writes,
      Executes verifiedFrontendCore state lexIntoBody
        (.returned (some (Model.resultValue request.outcome))) after ∧
      StateWellFormed after ∧
      Representation identityLayout localCell
        (Execution.world request.source
          (Model.run request.source request.capacity records).records)
        (Execution.initialEnvironment request.source
          (Model.run request.source request.capacity records).records
          request.capacity)
        after ∧
      ModifiesOnly writes state after := by
  have evaluated := Execution.command_evaluates_request request records
    recordsLength
  have logical :
      (Model.run request.source request.capacity records).outcome =
        request.outcome := by
    exact Model.run_outcome request.source request.capacity records
  have evaluatedLogical : Lanius.FunctionalView.Stateful.Command.Evaluates
      (termMachine
        (Lanius.FunctionalView.Core.Effectful.evaluateOperation
          verifiedFrontendCore (Calls.callModel request.source)))
      (machineWith verifiedFrontendCore
        (Lanius.FunctionalView.Core.Effectful.evaluateOperation
          verifiedFrontendCore (Calls.callModel request.source)))
      (Execution.world request.source records)
      (Execution.initialEnvironment request.source records request.capacity)
      Structure.command
      (.returned (some (Model.resultValue request.outcome)))
      (Execution.world request.source
        (Model.run request.source request.capacity records).records)
      (Execution.initialEnvironment request.source
        (Model.run request.source request.capacity records).records
        request.capacity) := by
    simpa only [logical] using evaluated
  obtain ⟨after, writes, execution, afterWellFormed, afterRepresented,
      effect⟩ := command_executes
    (Lanius.FunctionalView.Core.EffectfulStateful.expressionSoundness
      verifiedFrontendCore (Calls.callModel request.source) callSoundness)
    (Lanius.FunctionalView.Core.EffectfulStateful.actionSoundness
      verifiedFrontendCore (Calls.callModel request.source) callSoundness)
    evaluatedLogical represented (LayoutBelow.identity (arity := 4)) wellFormed
  rw [Structure.command_toCore_exactly] at execution
  exact ⟨after, writes, execution, afterWellFormed, afterRepresented, effect⟩

theorem checkedCall_executes
    (request : Model.Request) (records : List Int)
    (recordsLength : records.length = 3 * request.capacity)
    (callSoundness :
      Lanius.FunctionalView.Core.EffectfulStateful.CallSoundness
        verifiedFrontendCore (Calls.callModel request.source))
    {before afterArguments : State} {arguments : List Expr}
    {values : List Value} {localCell : Fin 4 → CellId}
    (argumentsResult : ArgumentsEvaluateTo verifiedFrontendCore before arguments
      values afterArguments)
    (parametersBound : bindParameters lexIntoFunction.parameters values =
      some (parameterBindings
        (Execution.initialEnvironment request.source records request.capacity)))
    (represented : Representation identityLayout localCell
      (Execution.world request.source records)
      (Execution.initialEnvironment request.source records request.capacity)
      (enterCall afterArguments
        (parameterBindings
          (Execution.initialEnvironment request.source records request.capacity))))
    (wellFormed : StateWellFormed
      (enterCall afterArguments
        (parameterBindings
          (Execution.initialEnvironment request.source records request.capacity)))) :
    ∃ completed writes,
      Evaluates verifiedFrontendCore before (.call lexIntoFunction.id arguments)
        (Model.resultValue request.outcome)
        (restoreLocals afterArguments completed) ∧
      StateWellFormed completed ∧
      Representation identityLayout localCell
        (Execution.world request.source
          (Model.run request.source request.capacity records).records)
        (Execution.initialEnvironment request.source
          (Model.run request.source request.capacity records).records
          request.capacity)
        completed ∧
      ModifiesOnly writes
        (enterCall afterArguments
          (parameterBindings
            (Execution.initialEnvironment request.source records request.capacity)))
        completed := by
  obtain ⟨completed, writes, bodyExecution, completedWellFormed,
      completedRepresented, bodyEffect⟩ :=
    checkedBody_executes request records recordsLength callSoundness represented
      wellFormed
  exact ⟨completed, writes,
    evaluatesCallReturned argumentsResult
      verifiedFrontendCore_finds_lexInto parametersBound lexInto_has_body
      bodyExecution,
    completedWellFormed, completedRepresented, bodyEffect⟩

/-- Premise-free end-to-end correctness of the real checked
`raw_lexer.lani::lex_into` call.  All nested helper calls are discharged by
their concrete checked frontend registries. -/
theorem call_executes
    (request : Model.Request) (records : List Int)
    (recordsLength : records.length = 3 * request.capacity)
    {before afterArguments : State} {arguments : List Expr}
    {values : List Value} {localCell : Fin 4 → CellId}
    (argumentsResult : ArgumentsEvaluateTo verifiedFrontendCore before arguments
      values afterArguments)
    (parametersBound : bindParameters lexIntoFunction.parameters values =
      some (parameterBindings
        (Execution.initialEnvironment request.source records request.capacity)))
    (represented : Representation identityLayout localCell
      (Execution.world request.source records)
      (Execution.initialEnvironment request.source records request.capacity)
      (enterCall afterArguments
        (parameterBindings
          (Execution.initialEnvironment request.source records request.capacity))))
    (wellFormed : StateWellFormed
      (enterCall afterArguments
        (parameterBindings
          (Execution.initialEnvironment request.source records request.capacity)))) :
    ∃ completed writes,
      Evaluates verifiedFrontendCore before (.call lexIntoFunction.id arguments)
        (Model.resultValue request.outcome)
        (restoreLocals afterArguments completed) ∧
      StateWellFormed completed ∧
      Representation identityLayout localCell
        (Execution.world request.source
          (Model.run request.source request.capacity records).records)
        (Execution.initialEnvironment request.source
          (Model.run request.source request.capacity records).records
          request.capacity)
        completed ∧
      ModifiesOnly writes
        (enterCall afterArguments
          (parameterBindings
            (Execution.initialEnvironment request.source records request.capacity)))
        completed :=
  checkedCall_executes request records recordsLength
    (Calls.callSoundness request.source) argumentsResult parametersBound
      represented wellFormed

end Lanius.Extraction.RawLexer.LexInto.EndToEnd
