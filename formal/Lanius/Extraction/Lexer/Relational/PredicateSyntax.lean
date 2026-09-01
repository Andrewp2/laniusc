import Lanius.Extraction.Lexer.Relational.Functions
import Lanius.Relational.Reification
import Lanius.FunctionalViewCoreFreshSimulation

namespace Lanius.Extraction.Lexer.Relational.PredicateSyntax

open Lanius
open Lanius.Core
open Lanius.Compiler.Lexer
open Lanius.Compiler.Lexer.Program
open Lanius.Extraction.Lexer
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.Stateful
open Lanius.Relational

abbrev T := Term Core.signature 1
abbrev C := Stateful.Command Core.signature Stateful.actions 1

def environment (byte : Byte) : Env 1 :=
  fun _ => .signed .i32 (Int.ofNat byte.val)

def argument : T := reference ⟨0, by omega⟩
def literal (value : Int) : T := .reference (.literal (.signed .i32 value))

def comparison (operation : BinaryOp) (left right : T) : T :=
  apply (.binary operation i32Type i32Type (.scalar .bool)) [left, right]

def call (function : Lanius.FunctionId) : T :=
  apply (.call function [i32Type] (.scalar .bool)) [argument]

def identifierStartTerm : T :=
  logicalOr
    (logicalOr
      (logicalAnd
        (comparison .greaterEqual argument (literal 97))
        (comparison .lessEqual argument (literal 122)))
      (logicalAnd
        (comparison .greaterEqual argument (literal 65))
        (comparison .lessEqual argument (literal 90))))
    (comparison .equal argument (literal 95))

def decimalDigitTerm : T :=
  logicalAnd
    (comparison .greaterEqual argument (literal 48))
    (comparison .lessEqual argument (literal 57))

def identifierContinueTerm : T :=
  logicalOr
    (call Functions.isIdentifierStart.function.id)
    (call Functions.isDecimalDigit.function.id)

def whitespaceTerm : T :=
  logicalOr
    (logicalOr
      (logicalOr
        (comparison .equal argument (literal 32))
        (comparison .equal argument (literal 9)))
      (comparison .equal argument (literal 10)))
    (comparison .equal argument (literal 13))

def command (term : T) : C :=
  .sequence (.returnValue (some term)) .skip

def identifierStartReification : Reifies Functions.isIdentifierStart
    (command identifierStartTerm) where
  layout := identityLayout
  nextLocal := 1
  adapter := actionAdapter
  argumentCount := by rfl
  below := LayoutBelow.identity
  exact := by rfl

def decimalDigitReification : Reifies Functions.isDecimalDigit
    (command decimalDigitTerm) where
  layout := identityLayout
  nextLocal := 1
  adapter := actionAdapter
  argumentCount := by rfl
  below := LayoutBelow.identity
  exact := by rfl

def identifierContinueReification : Reifies Functions.isIdentifierContinue
    (command identifierContinueTerm) where
  layout := identityLayout
  nextLocal := 1
  adapter := actionAdapter
  argumentCount := by rfl
  below := LayoutBelow.identity
  exact := by rfl

def whitespaceReification : Reifies Functions.isWhitespace
    (command whitespaceTerm) where
  layout := identityLayout
  nextLocal := 1
  adapter := actionAdapter
  argumentCount := by rfl
  below := LayoutBelow.identity
  exact := by rfl

theorem command_actionFree (term : T) :
    Lanius.FunctionalView.FreshSimulation.actionFree (command term) = true := by
  rfl

theorem identifierStart_callFree :
    FunctionalView.Core.Effectful.termCallFree identifierStartTerm = true := by
  decide +kernel

theorem decimalDigit_callFree :
    FunctionalView.Core.Effectful.termCallFree decimalDigitTerm = true := by
  decide +kernel

theorem whitespace_callFree :
    FunctionalView.Core.Effectful.termCallFree whitespaceTerm = true := by
  decide +kernel

end Lanius.Extraction.Lexer.Relational.PredicateSyntax
