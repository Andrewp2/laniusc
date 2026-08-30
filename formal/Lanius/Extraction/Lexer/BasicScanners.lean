import Lanius.Extraction.Lexer.Scanners

namespace Lanius.Extraction.Lexer.BasicScanners

open Lanius
open Lanius.Core
open Lanius.Semantics
open Lanius.Compiler.Lexer
open Lanius.Compiler.Lexer.Program
open Lanius.Extraction
open Lanius.Extraction.Lexer.Scanners
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.Stateful

theorem identifierView_core_executes
    (source : List Byte) (start : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length) :
    ∃ loopFinal,
      Executes verifiedFrontendLexerCore (scannerParameterState source start)
        (Lanius.FunctionalView.Core.Stateful.toCoreStmt actionAdapter
          identityLayout 3 scanIdentifierEndView.command)
        (.returned (some (.signed .i32 (scanIdentifierEnd source start))))
        (restoreLocals (scannerParameterState source start) loopFinal) := by
  rw [scanIdentifierEndView_toCore_exactly]
  obtain ⟨loopFinal, execution, _⟩ :=
    extracted_scanIdentifierEndBody_executes source start sourceBound
      startInBounds
  rw [scanIdentifierEndBody_eq_extracted]
  exact ⟨loopFinal, execution⟩

theorem whitespaceView_core_executes
    (source : List Byte) (start : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length) :
    ∃ loopFinal,
      Executes verifiedFrontendLexerCore (scannerParameterState source start)
        (Lanius.FunctionalView.Core.Stateful.toCoreStmt actionAdapter
          identityLayout 3 scanWhitespaceEndView.command)
        (.returned (some (.signed .i32 (scanWhitespaceEnd source start))))
        (restoreLocals (scannerParameterState source start) loopFinal) := by
  rw [scanWhitespaceEndView_toCore_exactly]
  obtain ⟨loopFinal, execution, _⟩ :=
    extracted_scanWhitespaceEndBody_executes source start sourceBound
      startInBounds
  rw [scanWhitespaceEndBody_eq_extracted]
  exact ⟨loopFinal, execution⟩

def scanIdentifierEndCall (source : List Byte) (start : Nat) : Expr :=
  scannerCall Scanners.scanIdentifierEndFunction source start

def scanWhitespaceEndCall (source : List Byte) (start : Nat) : Expr :=
  scannerCall Scanners.scanWhitespaceEndFunction source start

theorem scanIdentifierEndCall_executes
    (source : List Byte) (start : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length) :
    ∃ finalState,
      Evaluates verifiedFrontendLexerCore (sourceState source)
        (scanIdentifierEndCall source start)
        (.signed .i32 (scanIdentifierEnd source start)) finalState := by
  simpa [scanIdentifierEndCall, extractedScanIdentifierEndCall,
    scanIdentifierEndFunction_eq_extracted] using
    extracted_scanIdentifierEndCall_executes source start sourceBound
      startInBounds

theorem scanWhitespaceEndCall_executes
    (source : List Byte) (start : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length) :
    ∃ finalState,
      Evaluates verifiedFrontendLexerCore (sourceState source)
        (scanWhitespaceEndCall source start)
        (.signed .i32 (scanWhitespaceEnd source start)) finalState := by
  simpa [scanWhitespaceEndCall, extractedScanWhitespaceEndCall,
    scanWhitespaceEndFunction_eq_extracted] using
    extracted_scanWhitespaceEndCall_executes source start sourceBound
      startInBounds

end Lanius.Extraction.Lexer.BasicScanners
