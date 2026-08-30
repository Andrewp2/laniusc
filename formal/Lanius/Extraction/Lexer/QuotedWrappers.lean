import Lanius.Extraction.Lexer.Quoted
import Lanius.Extraction.Lexer.Scanners

namespace Lanius.Extraction.Lexer.QuotedWrappers

open Lanius
open Lanius.Core
open Lanius.Semantics
open Lanius.Compiler.Lexer
open Lanius.Compiler.Lexer.Program
open Lanius.Extraction
open Lanius.Extraction.Lexer
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.Stateful

/-! `scan_string_end` and `scan_character_end` are checked source wrappers
around the checked `scan_quoted_end` function.  This module connects those
wrapper artifacts to the quoted scanner's call semantics without changing the
program being executed from `verifiedFrontendLexerCore` to the handwritten
lexer model. -/

theorem scanStringEndBody_normalizes :
    removeTrailingSkips Scanners.scanStringEndBody = quotedWrapperBody 34 := by
  rfl

theorem scanCharacterEndBody_normalizes :
    removeTrailingSkips Scanners.scanCharacterEndBody = quotedWrapperBody 39 := by
  rfl

theorem scanStringEndBody_normalization_supported :
    SkipNormalizationSupported Scanners.scanStringEndBody := by
  native_decide

theorem scanCharacterEndBody_normalization_supported :
    SkipNormalizationSupported Scanners.scanCharacterEndBody := by
  native_decide

private def quotedLocalCall (delimiter : Byte) : Expr :=
  .call Scanners.scanQuotedEndFunction.id
    [.local 0, .local 1, .local 2, i32Literal delimiter.val]

private theorem quotedLocalCall_executes
    (source : List Byte) (start : Nat) (delimiter : Byte)
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length) :
    ∃ finalState,
      Evaluates verifiedFrontendLexerCore (scannerParameterState source start)
        (quotedLocalCall delimiter)
        (scanEndValue (scanQuotedEnd source start delimiter)) finalState := by
  simpa only [quotedLocalCall] using
    Quoted.call_from_scanner_parameters_executes source start delimiter
      sourceBound startInBounds

private theorem wrapperBody_executes_of_call
    (source : List Byte) (start : Nat) (delimiter : Byte) (result : Value)
    (callExec : ∃ finalState,
      Evaluates verifiedFrontendLexerCore (scannerParameterState source start)
        (quotedLocalCall delimiter) result finalState) :
    ∃ finalState,
      Executes verifiedFrontendLexerCore (scannerParameterState source start)
        (quotedWrapperBody delimiter.val)
        (.returned (some result)) finalState := by
  obtain ⟨finalState, evaluation⟩ := callExec
  have sameFunctionId : Scanners.scanQuotedEndFunction.id =
      Lanius.Compiler.Lexer.Program.scanQuotedEndFunction.id := by
    rfl
  exact ⟨finalState, by
    simpa only [quotedWrapperBody, quotedLocalCall, sameFunctionId]
      using executesReturnValue evaluation⟩

private theorem stringBody_executes_of_quoted_call
    (source : List Byte) (start : Nat) (result : Value)
    (callExec : ∃ finalState,
      Evaluates verifiedFrontendLexerCore (scannerParameterState source start)
        (quotedLocalCall doubleQuoteByte) result finalState) :
    ∃ finalState,
      Executes verifiedFrontendLexerCore (scannerParameterState source start)
        Scanners.scanStringEndBody (.returned (some result)) finalState := by
  apply Exists.imp (fun finalState execution =>
    removeTrailingSkips_executes_complete
      scanStringEndBody_normalization_supported execution)
  rw [scanStringEndBody_normalizes]
  exact wrapperBody_executes_of_call source start doubleQuoteByte result callExec

private theorem characterBody_executes_of_quoted_call
    (source : List Byte) (start : Nat) (result : Value)
    (callExec : ∃ finalState,
      Evaluates verifiedFrontendLexerCore (scannerParameterState source start)
        (quotedLocalCall singleQuoteByte) result finalState) :
    ∃ finalState,
      Executes verifiedFrontendLexerCore (scannerParameterState source start)
        Scanners.scanCharacterEndBody (.returned (some result)) finalState := by
  apply Exists.imp (fun finalState execution =>
    removeTrailingSkips_executes_complete
      scanCharacterEndBody_normalization_supported execution)
  rw [scanCharacterEndBody_normalizes]
  exact wrapperBody_executes_of_call source start singleQuoteByte result callExec

private theorem stringView_executes_of_quoted_call
    (source : List Byte) (start : Nat) (result : Value)
    (callExec : ∃ finalState,
      Evaluates verifiedFrontendLexerCore (scannerParameterState source start)
        (quotedLocalCall doubleQuoteByte) result finalState) :
    ∃ finalState,
      Executes verifiedFrontendLexerCore (scannerParameterState source start)
        (Lanius.FunctionalView.Core.Stateful.toCoreStmt actionAdapter
          identityLayout 3 Scanners.scanStringEndView.command)
        (.returned (some result)) finalState := by
  rw [Scanners.scanStringEndView_toCore_exactly]
  exact stringBody_executes_of_quoted_call source start result callExec

private theorem characterView_executes_of_quoted_call
    (source : List Byte) (start : Nat) (result : Value)
    (callExec : ∃ finalState,
      Evaluates verifiedFrontendLexerCore (scannerParameterState source start)
        (quotedLocalCall singleQuoteByte) result finalState) :
    ∃ finalState,
      Executes verifiedFrontendLexerCore (scannerParameterState source start)
        (Lanius.FunctionalView.Core.Stateful.toCoreStmt actionAdapter
          identityLayout 3 Scanners.scanCharacterEndView.command)
        (.returned (some result)) finalState := by
  rw [Scanners.scanCharacterEndView_toCore_exactly]
  exact characterBody_executes_of_quoted_call source start result callExec

private theorem stringCall_executes_of_body
    (source : List Byte) (start : Nat) (result : Value)
    (bodyExec : ∃ finalState,
      Executes verifiedFrontendLexerCore (scannerParameterState source start)
        Scanners.scanStringEndBody (.returned (some result)) finalState) :
    ∃ finalState,
      Evaluates verifiedFrontendLexerCore (sourceState source)
        (scannerCall Scanners.scanStringEndFunction source start)
        result finalState := by
  exact scannerCall_executesBody verifiedFrontendLexerCore
    Scanners.scanStringEndFunction Scanners.scanStringEndBody result
    Scanners.verifiedFrontendLexerCore_finds_scanStringEnd
    (by rfl) Scanners.scanStringEndFunction_has_body source start bodyExec

private theorem characterCall_executes_of_body
    (source : List Byte) (start : Nat) (result : Value)
    (bodyExec : ∃ finalState,
      Executes verifiedFrontendLexerCore (scannerParameterState source start)
        Scanners.scanCharacterEndBody (.returned (some result)) finalState) :
    ∃ finalState,
      Evaluates verifiedFrontendLexerCore (sourceState source)
        (scannerCall Scanners.scanCharacterEndFunction source start)
        result finalState := by
  exact scannerCall_executesBody verifiedFrontendLexerCore
    Scanners.scanCharacterEndFunction Scanners.scanCharacterEndBody result
    Scanners.verifiedFrontendLexerCore_finds_scanCharacterEnd
    (by rfl) Scanners.scanCharacterEndFunction_has_body source start bodyExec

theorem stringBody_executes
    (source : List Byte) (start : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length) :
    ∃ finalState,
      Executes verifiedFrontendLexerCore (scannerParameterState source start)
        Scanners.scanStringEndBody
        (.returned (some
          (scanEndValue (scanQuotedEnd source start doubleQuoteByte))))
        finalState := by
  exact stringBody_executes_of_quoted_call source start
    (scanEndValue (scanQuotedEnd source start doubleQuoteByte))
    (quotedLocalCall_executes source start doubleQuoteByte sourceBound
      startInBounds)

theorem characterBody_executes
    (source : List Byte) (start : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length) :
    ∃ finalState,
      Executes verifiedFrontendLexerCore (scannerParameterState source start)
        Scanners.scanCharacterEndBody
        (.returned (some
          (scanEndValue (scanQuotedEnd source start singleQuoteByte))))
        finalState := by
  exact characterBody_executes_of_quoted_call source start
    (scanEndValue (scanQuotedEnd source start singleQuoteByte))
    (quotedLocalCall_executes source start singleQuoteByte sourceBound
      startInBounds)

theorem stringView_core_executes
    (source : List Byte) (start : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length) :
    ∃ finalState,
      Executes verifiedFrontendLexerCore (scannerParameterState source start)
        (Lanius.FunctionalView.Core.Stateful.toCoreStmt actionAdapter
          identityLayout 3 Scanners.scanStringEndView.command)
        (.returned (some
          (scanEndValue (scanQuotedEnd source start doubleQuoteByte))))
        finalState := by
  exact stringView_executes_of_quoted_call source start
    (scanEndValue (scanQuotedEnd source start doubleQuoteByte))
    (quotedLocalCall_executes source start doubleQuoteByte sourceBound
      startInBounds)

theorem characterView_core_executes
    (source : List Byte) (start : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length) :
    ∃ finalState,
      Executes verifiedFrontendLexerCore (scannerParameterState source start)
        (Lanius.FunctionalView.Core.Stateful.toCoreStmt actionAdapter
          identityLayout 3 Scanners.scanCharacterEndView.command)
        (.returned (some
          (scanEndValue (scanQuotedEnd source start singleQuoteByte))))
        finalState := by
  exact characterView_executes_of_quoted_call source start
    (scanEndValue (scanQuotedEnd source start singleQuoteByte))
    (quotedLocalCall_executes source start singleQuoteByte sourceBound
      startInBounds)

theorem stringCall_executes
    (source : List Byte) (start : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length) :
    ∃ finalState,
      Evaluates verifiedFrontendLexerCore (sourceState source)
        (scannerCall Scanners.scanStringEndFunction source start)
        (scanEndValue (scanQuotedEnd source start doubleQuoteByte))
        finalState := by
  exact stringCall_executes_of_body source start
    (scanEndValue (scanQuotedEnd source start doubleQuoteByte))
    (stringBody_executes source start sourceBound startInBounds)

theorem characterCall_executes
    (source : List Byte) (start : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length) :
    ∃ finalState,
      Evaluates verifiedFrontendLexerCore (sourceState source)
        (scannerCall Scanners.scanCharacterEndFunction source start)
        (scanEndValue (scanQuotedEnd source start singleQuoteByte))
        finalState := by
  exact characterCall_executes_of_body source start
    (scanEndValue (scanQuotedEnd source start singleQuoteByte))
    (characterBody_executes source start sourceBound startInBounds)

end Lanius.Extraction.Lexer.QuotedWrappers
