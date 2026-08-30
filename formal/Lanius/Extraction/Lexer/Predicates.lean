import Lanius.Extraction.Lexer.Functions
import Lanius.CallContracts
import Lanius.FunctionalViewCoreEffectful

namespace Lanius.Extraction.Lexer.Predicates

open Lanius
open Lanius.Core
open Lanius.Compiler.Lexer
open Lanius.Semantics
open Lanius.Properties
open Lanius.Separation
open Lanius.CallContracts
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.ReadOnly
open Lanius.Extraction.Lexer.Functions

def world : World := { i32Slice? := fun _ => none }

def byteEnvironment (byte : Byte) : Env 1 :=
  fun _ => .signed .i32 (Int.ofNat byte.val)

def returnedBool? : Result worldType → Option Bool
  | .done (.returned (some (.boolean value))) _ => some value
  | _ => none

def returnedI32? : Result worldType → Option Int
  | .done (.returned (some (.signed .i32 value))) _ => some value
  | _ => none

theorem isIdentifierStartView_evaluates :
    ∀ byte : Byte,
      returnedBool? (Block.evaluate (machine verifiedFrontendLexerCore) world
          (byteEnvironment byte) isIdentifierStartView.block) =
        some (isIdentifierStart byte) := by
  native_decide

theorem isDecimalDigitView_evaluates :
    ∀ byte : Byte,
      returnedBool? (Block.evaluate (machine verifiedFrontendLexerCore) world
          (byteEnvironment byte) isDecimalDigitView.block) =
        some (isDecimalDigit byte) := by
  native_decide

theorem isWhitespaceView_evaluates :
    ∀ byte : Byte,
      returnedBool? (Block.evaluate (machine verifiedFrontendLexerCore) world
          (byteEnvironment byte) isWhitespaceView.block) =
        some (isWhitespace byte) := by
  native_decide

theorem isSymbolStartView_evaluates :
    ∀ byte : Byte,
      returnedBool? (Block.evaluate (machine verifiedFrontendLexerCore) world
          (byteEnvironment byte) isSymbolStartView.block) =
        some (isSymbolStart byte) := by
  native_decide

theorem classifyStartView_evaluates :
    ∀ byte : Byte,
      returnedI32? (Block.evaluate (machine verifiedFrontendLexerCore) world
          (byteEnvironment byte) classifyStartView.block) =
        some (Int.ofNat (classifyStartCode byte)) := by
  native_decide

private theorem returnedBool?_some
    {result : Result worldType} {value : Bool}
    (projected : returnedBool? result = some value) :
    ∃ afterWorld,
      result = .done (.returned (some (.boolean value))) afterWorld := by
  cases result with
  | trapped reason afterWorld => simp [returnedBool?] at projected
  | done completion afterWorld =>
      cases completion with
      | next => simp [returnedBool?] at projected
      | returned returnedValue =>
          cases returnedValue with
          | none => simp [returnedBool?] at projected
          | some returnedValue =>
              cases returnedValue <;> simp_all [returnedBool?]

private theorem returnedI32?_some
    {result : Result worldType} {value : Int}
    (projected : returnedI32? result = some value) :
    ∃ afterWorld,
      result = .done (.returned (some (.signed .i32 value))) afterWorld := by
  cases result with
  | trapped reason afterWorld => simp [returnedI32?] at projected
  | done completion afterWorld =>
      cases completion with
      | next => simp [returnedI32?] at projected
      | returned returnedValue =>
          cases returnedValue with
          | none => simp [returnedI32?] at projected
          | some returnedValue =>
              cases returnedValue <;> simp_all [returnedI32?]
              case signed type value =>
                cases type <;> simp_all

def byteCalleeState (state : State) (byte : Byte) : State :=
  enterCall state (parameterBindings (byteEnvironment byte))

def byteCallState (state : State) (byte : Byte) : State :=
  restoreLocals state (byteCalleeState state byte)

private theorem pureUnaryBlock_executes
    (state : State) (wellFormed : StateWellFormed state)
    (environment : Env 1) (block : Block signature 1) (result : Value)
    (afterWorld : World)
    (evaluated : Block.evaluate (machine verifiedFrontendLexerCore) world
      environment block = .done (.returned (some result)) afterWorld)
    (noLocals : localCapacity block = 0) :
    Executes verifiedFrontendLexerCore
      (enterCall state (parameterBindings environment))
      (toCoreStmt identityLayout 1 block)
      (.returned (some result))
      (enterCall state (parameterBindings environment)) := by
  have represented : ReadOnly.World.Represents world
      (enterCall state (parameterBindings environment)) := by
    intro _ _ found
    simp [world] at found
  exact (block_executes_without_locals
    (nextLocal := 1) (ReadOnly.bridge verifiedFrontendLexerCore) represented
    (enterCall_parameterBindings_matches wellFormed) noLocals evaluated).1

theorem isSymbolStartBody_executes
    (state : State) (wellFormed : StateWellFormed state) (byte : Byte) :
    Executes verifiedFrontendLexerCore
      (byteCalleeState state byte)
      (functionBody isSymbolStartFunction)
      (.returned (some (.boolean (isSymbolStart byte))))
      (byteCalleeState state byte) := by
  have execution := pureUnaryBlock_executes state wellFormed
    (byteEnvironment byte) isSymbolStartView.block
    (.boolean (isSymbolStart byte))
  obtain ⟨afterWorld, evaluated⟩ := returnedBool?_some
    (isSymbolStartView_evaluates byte)
  have execution := execution afterWorld evaluated (by native_decide)
  rw [isSymbolStartView_toCore_exactly] at execution
  simpa [byteCalleeState] using execution

theorem classifyStartBody_executes
    (state : State) (wellFormed : StateWellFormed state) (byte : Byte) :
    Executes verifiedFrontendLexerCore
      (byteCalleeState state byte)
      (functionBody classifyStartFunction)
      (.returned (some
        (.signed .i32 (Int.ofNat (classifyStartCode byte)))))
      (byteCalleeState state byte) := by
  have execution := pureUnaryBlock_executes state wellFormed
    (byteEnvironment byte) classifyStartView.block
    (.signed .i32 (Int.ofNat (classifyStartCode byte)))
  obtain ⟨afterWorld, evaluated⟩ := returnedI32?_some
    (classifyStartView_evaluates byte)
  have execution := execution afterWorld evaluated (by native_decide)
  rw [classifyStartView_toCore_exactly] at execution
  simpa [byteCalleeState] using execution

theorem isSymbolStartCall_executes
    (before afterArguments : State) (arguments : List Expr) (byte : Byte)
    (afterArgumentsWellFormed : StateWellFormed afterArguments)
    (argumentsResult : ArgumentsEvaluateTo verifiedFrontendLexerCore before
      arguments [.signed .i32 byte.val] afterArguments) :
    Evaluates verifiedFrontendLexerCore before
      (.call isSymbolStartFunction.id arguments)
      (.boolean (isSymbolStart byte))
      (byteCallState afterArguments byte) := by
  have body := isSymbolStartBody_executes afterArguments
    afterArgumentsWellFormed byte
  exact evaluatesCallReturned
    (bindings := parameterBindings (byteEnvironment byte))
    (body := functionBody isSymbolStartFunction)
    argumentsResult (by rfl) (by rfl) (by rfl) body

theorem classifyStartCall_executes
    (before afterArguments : State) (arguments : List Expr) (byte : Byte)
    (afterArgumentsWellFormed : StateWellFormed afterArguments)
    (argumentsResult : ArgumentsEvaluateTo verifiedFrontendLexerCore before
      arguments [.signed .i32 byte.val] afterArguments) :
    Evaluates verifiedFrontendLexerCore before
      (.call classifyStartFunction.id arguments)
      (.signed .i32 (Int.ofNat (classifyStartCode byte)))
      (byteCallState afterArguments byte) := by
  have body := classifyStartBody_executes afterArguments
    afterArgumentsWellFormed byte
  exact evaluatesCallReturned
    (bindings := parameterBindings (byteEnvironment byte))
    (body := functionBody classifyStartFunction)
    argumentsResult (by rfl) (by rfl) (by rfl) body

theorem isIdentifierContinueBody_executes
    (state : State) (wellFormed : StateWellFormed state) (byte : Byte) :
    Executes verifiedFrontendLexerCore
      (Program.unaryCalleeState state byte)
      (functionBody isIdentifierContinueFunction)
      (.returned (some (.boolean (isIdentifierContinue byte))))
      (Program.identifierContinueBodyState state byte) := by
  change Executes verifiedFrontendLexerCore
    (Program.unaryCalleeState state byte)
    extractedIsIdentifierContinueBody
    (.returned (some (.boolean (isIdentifierContinue byte))))
    (Program.identifierContinueBodyState state byte)
  exact ⟨14,
    extracted_isIdentifierContinueBody_executes_at_fuel state wellFormed byte⟩

theorem isIdentifierContinueCall_executes
    (before afterArguments : State) (arguments : List Expr) (byte : Byte)
    (afterArgumentsWellFormed : StateWellFormed afterArguments)
    (argumentsResult : ArgumentsEvaluateTo verifiedFrontendLexerCore before
      arguments [.signed .i32 byte.val] afterArguments) :
    Evaluates verifiedFrontendLexerCore before
      (.call isIdentifierContinueFunction.id arguments)
      (.boolean (isIdentifierContinue byte))
      (restoreLocals afterArguments
        (Program.identifierContinueBodyState afterArguments byte)) := by
  have body := isIdentifierContinueBody_executes afterArguments
    afterArgumentsWellFormed byte
  apply evaluatesCallReturned
    (bindings := [(0, .signed .i32 byte.val)])
    (body := functionBody isIdentifierContinueFunction)
    argumentsResult (by rfl) (by rfl) (by rfl)
  simpa [Program.unaryCalleeState, Program.clearLocals, enterCall,
    State.bindLocals] using body

namespace IdentifierContinue

open Lanius.FunctionalView.Core.Effectful

def calls : CallModel where
  evaluate := fun currentWorld function arguments =>
    match arguments with
    | [.signed .i32 byte] =>
        if function = isIdentifierStartFunction.id then
          .ok (.boolean
            ((97 ≤ byte && byte ≤ 122) || (65 ≤ byte && byte ≤ 90) ||
              byte == 95), currentWorld)
        else if function = isDecimalDigitFunction.id then
          .ok (.boolean (48 ≤ byte && byte ≤ 57), currentWorld)
        else
          .error .invalidPointer
    | _ => .error .typeMismatch

theorem calls_identifierStart (currentWorld : World) (byte : Byte) :
    calls.evaluate currentWorld isIdentifierStartFunction.id
        [.signed .i32 (Int.ofNat byte.val)] =
      .ok (.boolean
        ((97 ≤ (Int.ofNat byte.val) && (Int.ofNat byte.val) ≤ 122) ||
          (65 ≤ (Int.ofNat byte.val) && (Int.ofNat byte.val) ≤ 90) ||
          (Int.ofNat byte.val) == 95), currentWorld) := by
  simp [calls]

theorem calls_decimalDigit (currentWorld : World) (byte : Byte) :
    calls.evaluate currentWorld isDecimalDigitFunction.id
        [.signed .i32 (Int.ofNat byte.val)] =
      .ok (.boolean
        (48 ≤ (Int.ofNat byte.val) && (Int.ofNat byte.val) ≤ 57),
        currentWorld) := by
  have different : isDecimalDigitFunction.id ≠
      isIdentifierStartFunction.id := by native_decide
  simp [calls, different]

theorem view_evaluates :
    ∀ byte : Byte,
      returnedBool? (Block.evaluate
          (Lanius.FunctionalView.Core.Effectful.machine
            verifiedFrontendLexerCore calls)
          world (byteEnvironment byte) isIdentifierContinueView.block) =
        some (isIdentifierContinue byte) := by
  native_decide

end IdentifierContinue

end Lanius.Extraction.Lexer.Predicates
