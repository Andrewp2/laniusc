import Lanius.Extraction.Lexer.Functions
import Lanius.CallContracts

namespace Lanius.Extraction.Lexer.ScanEnd

open Lanius
open Lanius.Core
open Lanius.Semantics
open Lanius.Properties
open Lanius.Separation
open Lanius.CallContracts
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.ReadOnly
open Lanius.Extraction.Lexer.Functions

def world : World := { i32Slice? := fun _ => none }

def value (success : Bool) (endOffset errorOffset : Int) : Value :=
  .structure 0 [
    .boolean success,
    .signed .i32 endOffset,
    .signed .i32 errorOffset]

def resultEnvironment (success : Bool) (endOffset errorOffset : Int) : Env 1 :=
  fun _ => value success endOffset errorOffset

def offsetEnvironment (offset : Int) : Env 1 :=
  fun _ => .signed .i32 offset

theorem scanSucceededBlock_evaluates
    (success : Bool) (endOffset errorOffset : Int) :
    Block.evaluate (machine verifiedFrontendLexerCore) world
        (resultEnvironment success endOffset errorOffset)
        scanSucceededBlock =
      .done (.returned (some (.boolean success))) world := by
  rfl

theorem scanEndOffsetBlock_evaluates
    (success : Bool) (endOffset errorOffset : Int) :
    Block.evaluate (machine verifiedFrontendLexerCore) world
        (resultEnvironment success endOffset errorOffset)
        scanEndOffsetBlock =
      .done (.returned (some (.signed .i32 endOffset))) world := by
  rfl

theorem scanErrorOffsetBlock_evaluates
    (success : Bool) (endOffset errorOffset : Int) :
    Block.evaluate (machine verifiedFrontendLexerCore) world
        (resultEnvironment success endOffset errorOffset)
        scanErrorOffsetBlock =
      .done (.returned (some (.signed .i32 errorOffset))) world := by
  rfl

theorem successfulScanBlock_evaluates (endOffset : Int) :
    Block.evaluate (machine verifiedFrontendLexerCore) world
        (offsetEnvironment endOffset) successfulScanBlock =
      .done (.returned (some (value true endOffset 0))) world := by
  rfl

theorem failedScanBlock_evaluates (errorOffset : Int) :
    Block.evaluate (machine verifiedFrontendLexerCore) world
        (offsetEnvironment errorOffset) failedScanBlock =
      .done (.returned (some (value false 0 errorOffset))) world := by
  rfl

def resultCalleeState (state : State) (success : Bool)
    (endOffset errorOffset : Int) : State :=
  enterCall state
    (parameterBindings (resultEnvironment success endOffset errorOffset))

def resultCallState (state : State) (success : Bool)
    (endOffset errorOffset : Int) : State :=
  restoreLocals state
    (resultCalleeState state success endOffset errorOffset)

private theorem pureResultBlock_executes
    (state : State) (wellFormed : StateWellFormed state)
    (success : Bool) (endOffset errorOffset : Int)
    (block : Block signature 1) (result : Value)
    (evaluated : Block.evaluate (machine verifiedFrontendLexerCore) world
      (resultEnvironment success endOffset errorOffset) block =
        .done (.returned (some result)) world)
    (noLocals : localCapacity block = 0) :
    Executes verifiedFrontendLexerCore
      (resultCalleeState state success endOffset errorOffset)
      (toCoreStmt identityLayout 1 block)
      (.returned (some result))
      (resultCalleeState state success endOffset errorOffset) := by
  have represented : ReadOnly.World.Represents world
      (resultCalleeState state success endOffset errorOffset) := by
    intro _ _ found
    simp [world] at found
  have execution := block_executes_without_locals
    (nextLocal := 1) (ReadOnly.bridge verifiedFrontendLexerCore) represented
    (enterCall_parameterBindings_matches wellFormed) noLocals evaluated
  simpa [resultCalleeState, toCoreCompletion] using execution.1

theorem scanSucceededBody_executes
    (state : State) (wellFormed : StateWellFormed state)
    (success : Bool) (endOffset errorOffset : Int) :
    Executes verifiedFrontendLexerCore
      (resultCalleeState state success endOffset errorOffset)
      (functionBody scanSucceededFunction)
      (.returned (some (.boolean success)))
      (resultCalleeState state success endOffset errorOffset) := by
  have execution := pureResultBlock_executes state wellFormed success
    endOffset errorOffset scanSucceededBlock (.boolean success)
    (scanSucceededBlock_evaluates success endOffset errorOffset)
    (by native_decide)
  rw [scanSucceededBlock_toCore_exactly] at execution
  exact execution

theorem scanEndOffsetBody_executes
    (state : State) (wellFormed : StateWellFormed state)
    (success : Bool) (endOffset errorOffset : Int) :
    Executes verifiedFrontendLexerCore
      (resultCalleeState state success endOffset errorOffset)
      (functionBody scanEndOffsetFunction)
      (.returned (some (.signed .i32 endOffset)))
      (resultCalleeState state success endOffset errorOffset) := by
  have execution := pureResultBlock_executes state wellFormed success
    endOffset errorOffset scanEndOffsetBlock (.signed .i32 endOffset)
    (scanEndOffsetBlock_evaluates success endOffset errorOffset)
    (by native_decide)
  rw [scanEndOffsetBlock_toCore_exactly] at execution
  exact execution

theorem scanErrorOffsetBody_executes
    (state : State) (wellFormed : StateWellFormed state)
    (success : Bool) (endOffset errorOffset : Int) :
    Executes verifiedFrontendLexerCore
      (resultCalleeState state success endOffset errorOffset)
      (functionBody scanErrorOffsetFunction)
      (.returned (some (.signed .i32 errorOffset)))
      (resultCalleeState state success endOffset errorOffset) := by
  have execution := pureResultBlock_executes state wellFormed success
    endOffset errorOffset scanErrorOffsetBlock (.signed .i32 errorOffset)
    (scanErrorOffsetBlock_evaluates success endOffset errorOffset)
    (by native_decide)
  rw [scanErrorOffsetBlock_toCore_exactly] at execution
  exact execution

theorem scanSucceededCall_executes
    (before afterArguments : State) (arguments : List Expr)
    (success : Bool) (endOffset errorOffset : Int)
    (afterArgumentsWellFormed : StateWellFormed afterArguments)
    (argumentsResult : ArgumentsEvaluateTo verifiedFrontendLexerCore before
      arguments [value success endOffset errorOffset] afterArguments) :
    Evaluates verifiedFrontendLexerCore before
      (.call scanSucceededFunction.id arguments) (.boolean success)
      (resultCallState afterArguments success endOffset errorOffset) := by
  have body := scanSucceededBody_executes afterArguments
    afterArgumentsWellFormed success endOffset errorOffset
  exact evaluatesCallReturned
    (bindings := parameterBindings
      (resultEnvironment success endOffset errorOffset))
    (body := functionBody scanSucceededFunction)
    argumentsResult (by rfl) (by rfl) (by rfl) body

theorem scanEndOffsetCall_executes
    (before afterArguments : State) (arguments : List Expr)
    (success : Bool) (endOffset errorOffset : Int)
    (afterArgumentsWellFormed : StateWellFormed afterArguments)
    (argumentsResult : ArgumentsEvaluateTo verifiedFrontendLexerCore before
      arguments [value success endOffset errorOffset] afterArguments) :
    Evaluates verifiedFrontendLexerCore before
      (.call scanEndOffsetFunction.id arguments) (.signed .i32 endOffset)
      (resultCallState afterArguments success endOffset errorOffset) := by
  have body := scanEndOffsetBody_executes afterArguments
    afterArgumentsWellFormed success endOffset errorOffset
  exact evaluatesCallReturned
    (bindings := parameterBindings
      (resultEnvironment success endOffset errorOffset))
    (body := functionBody scanEndOffsetFunction)
    argumentsResult (by rfl) (by rfl) (by rfl) body

theorem scanErrorOffsetCall_executes
    (before afterArguments : State) (arguments : List Expr)
    (success : Bool) (endOffset errorOffset : Int)
    (afterArgumentsWellFormed : StateWellFormed afterArguments)
    (argumentsResult : ArgumentsEvaluateTo verifiedFrontendLexerCore before
      arguments [value success endOffset errorOffset] afterArguments) :
    Evaluates verifiedFrontendLexerCore before
      (.call scanErrorOffsetFunction.id arguments) (.signed .i32 errorOffset)
      (resultCallState afterArguments success endOffset errorOffset) := by
  have body := scanErrorOffsetBody_executes afterArguments
    afterArgumentsWellFormed success endOffset errorOffset
  exact evaluatesCallReturned
    (bindings := parameterBindings
      (resultEnvironment success endOffset errorOffset))
    (body := functionBody scanErrorOffsetFunction)
    argumentsResult (by rfl) (by rfl) (by rfl) body

end Lanius.Extraction.Lexer.ScanEnd
