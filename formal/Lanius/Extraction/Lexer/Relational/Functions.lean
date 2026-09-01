import Lanius.Extraction.VerifiedFrontendCheckedProgram
import Lanius.Extraction.Lexer.Scanners
import Lanius.Extraction.Lexer.Functions

namespace Lanius.Extraction.Lexer.Relational.Functions

open Lanius.Core
open Lanius.Compiler.Lexer.Program
open Lanius.Extraction
open Lanius.Extraction.Lexer
open Lanius.Relational

def scannerSignature : FnSignature where
  arguments := [.slice i32Type, i32Type, i32Type]
  result := i32Type

def predicateSignature : FnSignature where
  arguments := [i32Type]
  result := .scalar .bool

/-- Typed checked handle for the identifier-start helper used by
`is_identifier_continue`. -/
def isIdentifierStart : checkedFrontend.FnRef predicateSignature where
  function := Lanius.Extraction.Lexer.Functions.isIdentifierStartFunction
  body := Lanius.Extraction.Lexer.Functions.functionBody
    Lanius.Extraction.Lexer.Functions.isIdentifierStartFunction
  found := by rfl
  bodyFound := by rfl
  parameterTypes := by rfl
  resultType := by rfl
  source := {
    path := "verified_compiler/src/verified/lexer.lani"
    name := "verified::lexer::is_identifier_start"
    span := some ⟨⟨16, 1, none⟩, ⟨16, 1, none⟩⟩
  }

/-- Typed checked handle for the decimal-digit helper used by
`is_identifier_continue`. -/
def isDecimalDigit : checkedFrontend.FnRef predicateSignature where
  function := Lanius.Extraction.Lexer.Functions.isDecimalDigitFunction
  body := Lanius.Extraction.Lexer.Functions.functionBody
    Lanius.Extraction.Lexer.Functions.isDecimalDigitFunction
  found := by rfl
  bodyFound := by rfl
  parameterTypes := by rfl
  resultType := by rfl
  source := {
    path := "verified_compiler/src/verified/lexer.lani"
    name := "verified::lexer::is_decimal_digit"
    span := some ⟨⟨26, 1, none⟩, ⟨26, 1, none⟩⟩
  }

/-- Typed checked handle for the identifier-continuation predicate. -/
def isIdentifierContinue : checkedFrontend.FnRef predicateSignature where
  function := Lanius.Extraction.Lexer.Functions.isIdentifierContinueFunction
  body := Lanius.Extraction.Lexer.Functions.functionBody Lanius.Extraction.Lexer.Functions.isIdentifierContinueFunction
  found := by rfl
  bodyFound := by rfl
  parameterTypes := by rfl
  resultType := by rfl
  source := {
    path := "verified_compiler/src/verified/lexer.lani"
    name := "verified::lexer::is_identifier_continue"
    span := some ⟨⟨22, 1, none⟩, ⟨22, 1, none⟩⟩
  }

/-- Typed checked handle for the whitespace predicate. -/
def isWhitespace : checkedFrontend.FnRef predicateSignature where
  function := Lanius.Extraction.Lexer.Functions.isWhitespaceFunction
  body := Lanius.Extraction.Lexer.Functions.functionBody Lanius.Extraction.Lexer.Functions.isWhitespaceFunction
  found := by rfl
  bodyFound := by rfl
  parameterTypes := by rfl
  resultType := by rfl
  source := {
    path := "verified_compiler/src/verified/lexer.lani"
    name := "verified::lexer::is_whitespace"
    span := some ⟨⟨30, 1, none⟩, ⟨30, 1, none⟩⟩
  }

/-- Typed, body-bearing handle generated from the checked frontend function. -/
def scanIdentifierEnd : checkedFrontend.FnRef scannerSignature where
  function := Scanners.scanIdentifierEndFunction
  body := Scanners.scanIdentifierEndBody
  found := by rfl
  bodyFound := Scanners.scanIdentifierEndFunction_has_body
  parameterTypes := by rfl
  resultType := by rfl
  source := {
    path := "verified_compiler/src/verified/lexer.lani"
    name := "verified::lexer::scan_identifier_end"
    span := some ⟨⟨114, 1, none⟩, ⟨114, 1, none⟩⟩
  }

/-- Typed, body-bearing handle generated from the checked frontend function. -/
def scanWhitespaceEnd : checkedFrontend.FnRef scannerSignature where
  function := Scanners.scanWhitespaceEndFunction
  body := Scanners.scanWhitespaceEndBody
  found := by rfl
  bodyFound := Scanners.scanWhitespaceEndFunction_has_body
  parameterTypes := by rfl
  resultType := by rfl
  source := {
    path := "verified_compiler/src/verified/lexer.lani"
    name := "verified::lexer::scan_whitespace_end"
    span := some ⟨⟨124, 1, none⟩, ⟨124, 1, none⟩⟩
  }

/-- Source identity for the loop whose invariant drives the identifier scanner
VCs.  It is separate from the function handle because diagnostics should point
at the control construct, not merely its enclosing declaration. -/
def scanIdentifierEndLoop : SourceIdentity where
  path := "verified_compiler/src/verified/lexer.lani"
  name := "verified::lexer::scan_identifier_end while"
  span := some ⟨⟨116, 5, none⟩, ⟨116, 5, none⟩⟩

def scanWhitespaceEndLoop : SourceIdentity where
  path := "verified_compiler/src/verified/lexer.lani"
  name := "verified::lexer::scan_whitespace_end while"
  span := some ⟨⟨126, 5, none⟩, ⟨126, 5, none⟩⟩

end Lanius.Extraction.Lexer.Relational.Functions
