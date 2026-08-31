import Lanius.Extraction.Number.Functions
import Lanius.Extraction.Decimal.Functions
import Lanius.Extraction.Lexer.Digits

namespace Lanius.Extraction.Number.Commands

open Lanius
open Lanius.Core
open Lanius.Extraction
open Lanius.Compiler.Lexer.Program
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.Stateful
open Lanius.FunctionalView.Stateful

def boolType : Ty := .scalar .bool
def resultType : Ty := .structure 1
def digitResultType : Ty := .structure 2
def sliceType : Ty := .slice i32Type

def slot {arity : Nat} (index : Fin arity) : Term signature arity :=
  reference index

def i32 {arity : Nat} (value : Int) : Term signature arity :=
  literal (.signed .i32 value)

def binary {arity : Nat} (operation : BinaryOp)
    (left right : Term signature arity) (result : Ty) : Term signature arity :=
  apply (.binary operation i32Type i32Type result) [left, right]

def unary {arity : Nat} (operation : UnaryOp)
    (value : Term signature arity) : Term signature arity :=
  apply (.unary operation boolType boolType) [value]

def call {arity : Nat} (function : Function)
    (argumentTypes : List Ty) (arguments : List (Term signature arity)) :
    Term signature arity :=
  apply (.call function.id argumentTypes function.returnType) arguments

def index {arity : Nat} (base position : Term signature arity) :
    Term signature arity :=
  apply (.index sliceType i32Type i32Type) [base, position]

def add {arity : Nat} (left right : Term signature arity) :
    Term signature arity := binary .add left right i32Type

def comparison {arity : Nat} (operation : BinaryOp)
    (left right : Term signature arity) : Term signature arity :=
  binary operation left right boolType

def digitCall {arity : Nat} (source bound start base :
    Term signature arity) : Term signature arity :=
  call extractedScanDigitRunFunction [sliceType, i32Type, i32Type, i32Type]
    [source, bound, start, base]

def digitSucceeded {arity : Nat} (result : Term signature arity) :
    Term signature arity :=
  call Lexer.Digits.digitScanSucceededFunction [digitResultType] [result]

def digitEnd {arity : Nat} (result : Term signature arity) :
    Term signature arity :=
  call Lexer.Digits.digitScanEndOffsetFunction [digitResultType] [result]

def digitError {arity : Nat} (result : Term signature arity) :
    Term signature arity :=
  call Lexer.Digits.digitScanErrorOffsetFunction [digitResultType] [result]

def numberFailure {arity : Nat} (offset : Term signature arity) :
    Term signature arity :=
  call Decimal.Functions.numberFailureFunction [i32Type] [offset]

def integerScan {arity : Nat} (offset : Term signature arity) :
    Term signature arity :=
  call Decimal.Functions.integerScanFunction [i32Type] [offset]

def floatScan {arity : Nat} (offset : Term signature arity) :
    Term signature arity :=
  call Decimal.Functions.floatScanFunction [i32Type] [offset]

def scanExponent {arity : Nat} (source bound start :
    Term signature arity) : Term signature arity :=
  call Decimal.Functions.scanExponentFunction [sliceType, i32Type, i32Type]
    [source, bound, start]

def finishDecimal {arity : Nat} (source bound start :
    Term signature arity) : Term signature arity :=
  call Decimal.Functions.finishDecimalFunction [sliceType, i32Type, i32Type]
    [source, bound, start]

def returned {arity : Nat} (value : Term signature arity) :
    Command signature actions arity :=
  (Command.returnValue (some value)).sequence .skip

def statement {arity : Nat} (command : Command signature actions arity) :
    Command signature actions arity :=
  command.sequence .skip

def chooseBase : Command signature actions 5 :=
  .ifThenElse
    ((comparison .equal (slot 3) (i32 120)).logicalOr
      (comparison .equal (slot 3) (i32 88)))
    (statement (.setLocal 4 (i32 16)))
    (statement
      (.ifThenElse
        ((comparison .equal (slot 3) (i32 98)).logicalOr
          (comparison .equal (slot 3) (i32 66)))
        (statement (.setLocal 4 (i32 2)))
        (statement
          (.ifThenElse
            ((comparison .equal (slot 3) (i32 111)).logicalOr
              (comparison .equal (slot 3) (i32 79)))
            (statement (.setLocal 4 (i32 8))) .skip))))

def prefixedReturn : Command signature actions 5 :=
  .ifThenElse (comparison .notEqual (slot 4) (i32 0))
    (.letValue digitResultType
      (digitCall (slot 0) (slot 1) (add (slot 2) (i32 2)) (slot 4))
      (.sequence
        (.ifThenElse (unary .logicalNot (digitSucceeded (slot 5)))
          (returned (numberFailure (digitError (slot 5)))) .skip)
        (returned (integerScan (digitEnd (slot 5))))))
    .skip

def prefixedBranch : Command signature actions 3 :=
  .letValue i32Type (index (slot 0) (add (slot 2) (i32 1)))
    (.letValue i32Type (i32 0)
      (.sequence chooseBase (.sequence prefixedReturn .skip)))

def decimalBranch : Command signature actions 3 :=
  .letValue digitResultType
    (digitCall (slot 0) (slot 1) (slot 2) (i32 10))
    (.sequence
      (.ifThenElse (unary .logicalNot (digitSucceeded (slot 3)))
        (returned (numberFailure (digitError (slot 3)))) .skip)
      (returned (finishDecimal (slot 0) (slot 1) (digitEnd (slot 3)))))

def scanNumber : Command signature actions 3 :=
  .sequence
    (.ifThenElse
      ((comparison .equal (index (slot 0) (slot 2)) (i32 48)).logicalAnd
        (comparison .less (add (slot 2) (i32 1)) (slot 1)))
      prefixedBranch .skip)
    decimalBranch

theorem scanNumber_toCore_exactly :
    toCoreStmt actionAdapter identityLayout 3 scanNumber =
      Functions.scanNumberBody := by
  rfl

def scanLeadingDotNumber : Command signature actions 3 :=
  .letValue digitResultType
    (digitCall (slot 0) (slot 1) (add (slot 2) (i32 1)) (i32 10))
    (.sequence
      (.ifThenElse (unary .logicalNot (digitSucceeded (slot 3)))
        (returned (numberFailure (digitError (slot 3)))) .skip)
      (.letValue i32Type (digitEnd (slot 3))
        (.sequence
          (.ifThenElse (comparison .less (slot 4) (slot 1))
            (.letValue i32Type (index (slot 0) (slot 4))
              (.sequence
                (.ifThenElse
                  ((comparison .equal (slot 5) (i32 101)).logicalOr
                    (comparison .equal (slot 5) (i32 69)))
                  (returned (scanExponent (slot 0) (slot 1) (slot 4)))
                  .skip)
                .skip))
            .skip)
          (returned (floatScan (slot 4))))))

theorem scanLeadingDotNumber_toCore_exactly :
    toCoreStmt actionAdapter identityLayout 3 scanLeadingDotNumber =
      Functions.scanLeadingDotNumberBody := by
  rfl

end Lanius.Extraction.Number.Commands
