import Lanius.Extraction.Decimal.Dependencies

namespace Lanius.Extraction.Decimal.Constructors

open Lanius
open Lanius.Core
open Lanius.Semantics
open Lanius.Properties
open Lanius.Separation
open Lanius.CallContracts
open Lanius.Compiler.Lexer.Program
open Lanius.Extraction
open Lanius.Extraction.Decimal

theorem verifiedFrontendCore_finds_integerScan :
    verifiedFrontendCore.function? Functions.integerScanFunction.id =
      some Functions.integerScanFunction := by rfl

theorem verifiedFrontendCore_finds_floatScan :
    verifiedFrontendCore.function? Functions.floatScanFunction.id =
      some Functions.floatScanFunction := by rfl

theorem verifiedFrontendCore_finds_numberFailure :
    verifiedFrontendCore.function? Functions.numberFailureFunction.id =
      some Functions.numberFailureFunction := by rfl

private theorem tokenKindConstant_evaluates
    (state : State) (constant : ConstantId) (kind : Int)
    (found : verifiedFrontendCore.constant? constant =
      some { id := constant, type := i32Type, value := .signed .i32 kind }) :
    Evaluates verifiedFrontendCore state (.constant constant)
      (.signed .i32 kind) state := by
  exact evaluatesConstant found

private theorem wrapperBody_executes
    (state : State) (wellFormed : StateWellFormed state)
    (body : Stmt) (constant : ConstantId) (kind : Int) (offset : Nat)
    (bodyShape : body = .sequence
      (.returnValue (some (.call Dependencies.successfulTokenScanFunction.id
        [.constant constant, .local 0]))) .skip)
    (constantFound : verifiedFrontendCore.constant? constant =
      some { id := constant, type := i32Type, value := .signed .i32 kind }) :
    Executes verifiedFrontendCore
      (singleArgumentCalleeState state (.signed .i32 offset)) body
      (.returned (some (Dependencies.tokenScanValue true kind offset 0)))
      (twoI32CallState
        (singleArgumentCalleeState state (.signed .i32 offset)) kind offset) := by
  let callee := singleArgumentCalleeState state (.signed .i32 offset)
  have calleeWellFormed := singleArgumentCalleeState_well_formed state
    wellFormed (.signed .i32 offset)
  have kindResult := tokenKindConstant_evaluates callee constant kind
    constantFound
  have offsetResult : Evaluates verifiedFrontendCore callee (.local 0)
      (.signed .i32 offset) callee := by
    exact ⟨1, evalLocal_of_local 0 verifiedFrontendCore callee 0
      (.signed .i32 offset)
      (singleArgumentCalleeState_local state wellFormed
        (.signed .i32 offset))⟩
  have call := Dependencies.successfulTokenScanCall_executes callee
    calleeWellFormed (.constant constant) (.local 0) kind offset
    kindResult offsetResult
  rw [bodyShape]
  exact executesSequenceReturned (executesReturnValue call)

theorem integerScanBody_executes
    (state : State) (wellFormed : StateWellFormed state) (endOffset : Nat) :
    Executes verifiedFrontendCore
      (singleArgumentCalleeState state (.signed .i32 endOffset))
      Functions.integerScanBody
      (.returned (some (Dependencies.tokenScanValue true 2 endOffset 0)))
      (twoI32CallState
        (singleArgumentCalleeState state (.signed .i32 endOffset)) 2 endOffset) := by
  exact wrapperBody_executes state wellFormed Functions.integerScanBody 8 2
    endOffset (by rfl) (by rfl)

theorem floatScanBody_executes
    (state : State) (wellFormed : StateWellFormed state) (endOffset : Nat) :
    Executes verifiedFrontendCore
      (singleArgumentCalleeState state (.signed .i32 endOffset))
      Functions.floatScanBody
      (.returned (some (Dependencies.tokenScanValue true 33 endOffset 0)))
      (twoI32CallState
        (singleArgumentCalleeState state (.signed .i32 endOffset)) 33 endOffset) := by
  exact wrapperBody_executes state wellFormed Functions.floatScanBody 35 33
    endOffset (by rfl) (by rfl)

theorem numberFailureBody_executes
    (state : State) (wellFormed : StateWellFormed state) (errorOffset : Nat) :
    Executes verifiedFrontendCore
      (singleArgumentCalleeState state (.signed .i32 errorOffset))
      Functions.numberFailureBody
      (.returned (some (Dependencies.tokenScanValue false 0 0 errorOffset)))
      (singleArgumentCallState
        (singleArgumentCalleeState state (.signed .i32 errorOffset))
        (.signed .i32 errorOffset)) := by
  let callee := singleArgumentCalleeState state (.signed .i32 errorOffset)
  have calleeWellFormed := singleArgumentCalleeState_well_formed state
    wellFormed (.signed .i32 errorOffset)
  have argument : Evaluates verifiedFrontendCore callee (.local 0)
      (.signed .i32 errorOffset) callee := by
    exact ⟨1, evalLocal_of_local 0 verifiedFrontendCore callee 0
      (.signed .i32 errorOffset)
      (singleArgumentCalleeState_local state wellFormed
        (.signed .i32 errorOffset))⟩
  have call := Dependencies.failedTokenScanCall_executes callee
    calleeWellFormed (.local 0) errorOffset argument
  rw [show Functions.numberFailureBody = .sequence
      (.returnValue (some (.call Dependencies.failedTokenScanFunction.id
        [.local 0]))) .skip by rfl]
  exact executesSequenceReturned (executesReturnValue call)

theorem integerScanCall_executes
    (state : State) (wellFormed : StateWellFormed state)
    (argument : Expr) (endOffset : Nat)
    (argumentResult : Evaluates verifiedFrontendCore state argument
      (.signed .i32 endOffset) state) :
    ∃ finalState,
      Evaluates verifiedFrontendCore state
        (.call Functions.integerScanFunction.id [argument])
        (Dependencies.tokenScanValue true 2 endOffset 0) finalState := by
  have arguments := ArgumentsEvaluateTo.singleton argumentResult
  have body := integerScanBody_executes state wellFormed endOffset
  exact ⟨_, evaluatesCallReturned
    (bindings := [(0, .signed .i32 endOffset)])
    (body := Functions.integerScanBody) arguments
    verifiedFrontendCore_finds_integerScan (by rfl) (by rfl) body⟩

theorem floatScanCall_executes
    (state : State) (wellFormed : StateWellFormed state)
    (argument : Expr) (endOffset : Nat)
    (argumentResult : Evaluates verifiedFrontendCore state argument
      (.signed .i32 endOffset) state) :
    ∃ finalState,
      Evaluates verifiedFrontendCore state
        (.call Functions.floatScanFunction.id [argument])
        (Dependencies.tokenScanValue true 33 endOffset 0) finalState := by
  have arguments := ArgumentsEvaluateTo.singleton argumentResult
  have body := floatScanBody_executes state wellFormed endOffset
  exact ⟨_, evaluatesCallReturned
    (bindings := [(0, .signed .i32 endOffset)])
    (body := Functions.floatScanBody) arguments
    verifiedFrontendCore_finds_floatScan (by rfl) (by rfl) body⟩

theorem numberFailureCall_executes
    (state : State) (wellFormed : StateWellFormed state)
    (argument : Expr) (errorOffset : Nat)
    (argumentResult : Evaluates verifiedFrontendCore state argument
      (.signed .i32 errorOffset) state) :
    ∃ finalState,
      Evaluates verifiedFrontendCore state
        (.call Functions.numberFailureFunction.id [argument])
        (Dependencies.tokenScanValue false 0 0 errorOffset) finalState := by
  have arguments := ArgumentsEvaluateTo.singleton argumentResult
  have body := numberFailureBody_executes state wellFormed errorOffset
  exact ⟨_, evaluatesCallReturned
    (bindings := [(0, .signed .i32 errorOffset)])
    (body := Functions.numberFailureBody) arguments
    verifiedFrontendCore_finds_numberFailure (by rfl) (by rfl) body⟩

end Lanius.Extraction.Decimal.Constructors
