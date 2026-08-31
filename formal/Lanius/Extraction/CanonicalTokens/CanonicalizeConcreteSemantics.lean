import Lanius.Extraction.CanonicalTokens.CanonicalizeAgreement
import Lanius.Extraction.CanonicalTokens.CanonicalizeHelperContracts
import Lanius.FunctionalViewCoreCheckedSimulation

namespace Lanius.Extraction.CanonicalTokens.CanonicalizeConcreteSemantics

open Lanius
open Lanius.Core
open Lanius.Compiler
open Lanius.Compiler.Lexer
open Lanius.Semantics
open Lanius.Properties
open Lanius.Separation
open Lanius.CallContracts
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.Stateful
open Lanius.FunctionalView.Core.EffectfulStateful
open Lanius.FunctionalView.FreshSimulation
open Lanius.Extraction.CanonicalTokens

private theorem raw_split_at (raw : List RawToken) (row : Nat)
    (rowBound : row < raw.length) :
    raw.take row ++ raw[row] :: raw.drop (row + 1) = raw := by
  calc
    raw.take row ++ raw[row] :: raw.drop (row + 1) =
        raw.take (row + 1) ++ raw.drop (row + 1) := by
      rw [List.take_succ_eq_append_getElem rowBound]
      simp
    _ = raw := List.take_append_drop (row + 1) raw

private theorem encoded_start_at_index (raw : List RawToken) (row : Nat)
    (rowBound : row < raw.length) :
    (CanonicalizeModel.encodeTokens raw)[3 * row + 1]! =
      Int.ofNat raw[row].start := by
  have found := CanonicalizeAgreement.Model.encoded_start_at
    (raw.take row) (raw.drop (row + 1)) raw[row]
  have takeLength : (raw.take row).length = row := by simp [Nat.le_of_lt rowBound]
  rw [takeLength] at found
  rw [raw_split_at raw row rowBound] at found
  exact found

private theorem encoded_finish_at_index (raw : List RawToken) (row : Nat)
    (rowBound : row < raw.length) :
    (CanonicalizeModel.encodeTokens raw)[3 * row + 2]! =
      Int.ofNat raw[row].finish := by
  have found := CanonicalizeAgreement.Model.encoded_finish_at
    (raw.take row) (raw.drop (row + 1)) raw[row]
  have takeLength : (raw.take row).length = row := by simp [Nat.le_of_lt rowBound]
  rw [takeLength] at found
  rw [raw_split_at raw row rowBound] at found
  exact found

/-- The independent logical request invariant supplies every physical-row
precondition used by the exact checked compaction loop.  In particular, this
is the explicit bridge from raw tokens to their flat mutable GPU encoding. -/
theorem request_rowsValid (request : CanonicalizeModel.Request) :
    CanonicalizeExecution.RowsValid
      (CanonicalizeModel.sourceIntegers request.source)
      request.records request.raw.length := by
  constructor
  · exact request.recordsLength
  · rw [← request.recordsLength]
    exact request.recordsFitI32
  · simpa [CanonicalizeModel.sourceIntegers] using request.sourceFitsI32
  · intro row rowBound
    rw [request.recordsEncodeRaw, encoded_start_at_index request.raw row rowBound]
    exact Int.natCast_nonneg _
  · intro row rowBound
    rw [request.recordsEncodeRaw, encoded_finish_at_index request.raw row rowBound]
    exact Int.natCast_nonneg _
  · intro row rowBound
    rw [request.recordsEncodeRaw, encoded_start_at_index request.raw row rowBound,
      encoded_finish_at_index request.raw row rowBound]
    simpa using
      request.spansOrdered request.raw[row] (List.getElem_mem rowBound)
  · intro row rowBound
    rw [request.recordsEncodeRaw, encoded_finish_at_index request.raw row rowBound]
    simpa [CanonicalizeModel.sourceIntegers] using
      request.spansInBounds request.raw[row] (List.getElem_mem rowBound)

/-- Exact FunctionalView execution of `canonicalize_in_place`, stated against
the independent lexer model rather than the loop implementation's private
accumulators. -/
theorem request_command_evaluates (request : CanonicalizeModel.Request) :
    Lanius.FunctionalView.Stateful.Command.Evaluates
      (termMachine
        (Lanius.FunctionalView.Core.Effectful.evaluateOperation
          verifiedFrontendCore CanonicalizeExecution.calls))
      (machineWith verifiedFrontendCore
        (Lanius.FunctionalView.Core.Effectful.evaluateOperation
          verifiedFrontendCore CanonicalizeExecution.calls))
      (CanonicalizeExecution.world
        (CanonicalizeModel.sourceIntegers request.source) request.records)
      (CanonicalizeExecution.initialEnvironment
        (CanonicalizeModel.sourceIntegers request.source) request.records
        request.raw.length)
      Functions.canonicalizeInPlaceView.command
      (.returned (some (.signed .i32 request.resultCount)))
      (CanonicalizeExecution.world
        (CanonicalizeModel.sourceIntegers request.source)
        request.resultRecords)
      (CanonicalizeExecution.initialEnvironment
        (CanonicalizeModel.sourceIntegers request.source)
        request.resultRecords request.raw.length) := by
  rw [CanonicalizeStructure.recovered_command_exact]
  have evaluated := CanonicalizeExecution.command_evaluates
    (CanonicalizeModel.sourceIntegers request.source) request.records
    request.raw.length (request_rowsValid request)
  rw [CanonicalizeAgreement.Model.result_agrees request] at evaluated
  exact evaluated

/-- The exact checked Core body refines a logical canonicalization request.
The only parameter here is the already-independent trivia/keyword helper
contract; the canonical-kind route and every mutable loop step are discharged
inside this theorem. -/
theorem request_body_executes
    (baseSound : FramePreservingCallSoundness verifiedFrontendCore
      Model.callModel)
    (request : CanonicalizeModel.Request)
    {localCell : Fin 3 → CellId} {state : State}
    (represented : Representation identityLayout localCell
      (CanonicalizeExecution.world
        (CanonicalizeModel.sourceIntegers request.source) request.records)
      (CanonicalizeExecution.initialEnvironment
        (CanonicalizeModel.sourceIntegers request.source) request.records
        request.raw.length)
      state)
    (wellFormed : StateWellFormed state) :
    ∃ after writes,
      Executes verifiedFrontendCore state Functions.canonicalizeInPlaceBody
        (.returned (some (.signed .i32 request.resultCount))) after ∧
      StateWellFormed after ∧
      Representation identityLayout localCell
        (CanonicalizeExecution.world
          (CanonicalizeModel.sourceIntegers request.source)
          request.resultRecords)
        (CanonicalizeExecution.initialEnvironment
          (CanonicalizeModel.sourceIntegers request.source)
          request.resultRecords request.raw.length)
        after ∧
      ModifiesOnly writes state after := by
  exact CheckedSimulation.bodyExecutes
    (CanonicalizeHelperContracts.callSoundness baseSound)
    (request_command_evaluates request) represented
    (LayoutBelow.identity (arity := 3)) wellFormed
    Functions.canonicalizeInPlaceView_toCore_exactly

/-- Real checked-program call semantics for the exact source function.  The
conclusion includes the concrete logical count, the physical post-call record
encoding, and the separation-logic write frame. -/
theorem request_call_executes
    (baseSound : FramePreservingCallSoundness verifiedFrontendCore
      Model.callModel)
    (request : CanonicalizeModel.Request)
    {localCell : Fin 3 → CellId}
    {before afterArguments : State} {arguments : List Expr}
    {values : List Value}
    (argumentsResult : ArgumentsEvaluateTo verifiedFrontendCore before
      arguments values afterArguments)
    (parametersBound : bindParameters
        Functions.canonicalizeInPlaceFunction.parameters values =
      some (parameterBindings
        (CanonicalizeExecution.initialEnvironment
          (CanonicalizeModel.sourceIntegers request.source) request.records
          request.raw.length)))
    (represented : Representation identityLayout localCell
      (CanonicalizeExecution.world
        (CanonicalizeModel.sourceIntegers request.source) request.records)
      (CanonicalizeExecution.initialEnvironment
        (CanonicalizeModel.sourceIntegers request.source) request.records
        request.raw.length)
      (enterCall afterArguments (parameterBindings
        (CanonicalizeExecution.initialEnvironment
          (CanonicalizeModel.sourceIntegers request.source) request.records
          request.raw.length))))
    (calleeWellFormed : StateWellFormed
      (enterCall afterArguments (parameterBindings
        (CanonicalizeExecution.initialEnvironment
          (CanonicalizeModel.sourceIntegers request.source) request.records
          request.raw.length)))) :
    ∃ completed writes,
      Evaluates verifiedFrontendCore before
        (.call Functions.canonicalizeInPlaceFunction.id arguments)
        (.signed .i32 request.resultCount)
        (restoreLocals afterArguments completed) ∧
      StateWellFormed completed ∧
      Representation identityLayout localCell
        (CanonicalizeExecution.world
          (CanonicalizeModel.sourceIntegers request.source)
          request.resultRecords)
        (CanonicalizeExecution.initialEnvironment
          (CanonicalizeModel.sourceIntegers request.source)
          request.resultRecords request.raw.length)
        completed ∧
      ModifiesOnly writes
        (enterCall afterArguments (parameterBindings
          (CanonicalizeExecution.initialEnvironment
            (CanonicalizeModel.sourceIntegers request.source) request.records
            request.raw.length))) completed := by
  exact CheckedSimulation.callExecutes
    (CanonicalizeHelperContracts.callSoundness baseSound)
    argumentsResult parametersBound
    Functions.verifiedFrontendCore_finds_canonicalizeInPlace
    Functions.canonicalizeInPlaceFunction_has_body
    (request_command_evaluates request) represented calleeWellFormed
    Functions.canonicalizeInPlaceView_toCore_exactly

end Lanius.Extraction.CanonicalTokens.CanonicalizeConcreteSemantics
