import Lanius.Extraction.Decimal.Functions
import Lanius.Extraction.Lexer.Digits

namespace Lanius.Extraction.Decimal.Commands

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

def isDigit {arity : Nat} (byte base : Term signature arity) :
    Term signature arity :=
  call extractedIsDigitForBaseFunction [i32Type, i32Type] [byte, base]

def numberFailure {arity : Nat} (offset : Term signature arity) :
    Term signature arity :=
  call Functions.numberFailureFunction [i32Type] [offset]

def integerScan {arity : Nat} (offset : Term signature arity) :
    Term signature arity :=
  call Functions.integerScanFunction [i32Type] [offset]

def floatScan {arity : Nat} (offset : Term signature arity) :
    Term signature arity :=
  call Functions.floatScanFunction [i32Type] [offset]

def scanExponentCall {arity : Nat} (source bound start :
    Term signature arity) : Term signature arity :=
  call Functions.scanExponentFunction [sliceType, i32Type, i32Type]
    [source, bound, start]

def returned {arity : Nat} (value : Term signature arity) :
    Command signature actions arity :=
  (Command.returnValue (some value)).sequence .skip

def statement {arity : Nat} (command : Command signature actions arity) :
    Command signature actions arity := command.sequence .skip

def scanExponent : Command signature actions 3 :=
  Functions.scanExponentView.command

/-! A readable decomposition of the mechanically recovered command.  The
theorem below is the authority: this definition is useful only because Lean
checks it against the exact checked artifact. -/
def scanExponentReadable : Command signature actions 3 :=
  Command.letValue i32Type (add (slot 2) (i32 1))
    ((Command.ifThenElse
        (comparison .less (slot 3) (slot 1))
        (Command.letValue i32Type (index (slot 0) (slot 3))
          ((Command.ifThenElse
              ((comparison .equal (slot 4) (i32 43)).logicalOr
                (comparison .equal (slot 4) (i32 45)))
              ((Command.updateLocal .add 3 (i32 1)).sequence .skip)
              .skip).sequence .skip))
        .skip).sequence
      (Command.letValue digitResultType
        (digitCall (slot 0) (slot 1) (slot 3) (i32 10))
        ((Command.ifThenElse
            (unary .logicalNot (digitSucceeded (slot 4)))
            (returned (numberFailure (digitError (slot 4))))
            .skip).sequence
          (returned (floatScan (digitEnd (slot 4)))))))

theorem scanExponentReadable_toCore_exactly :
    toCoreStmt actionAdapter identityLayout 3 scanExponentReadable =
      Functions.scanExponentBody := by
  rfl

theorem scanExponent_toCore_exactly :
    toCoreStmt actionAdapter identityLayout 3 scanExponent =
      Functions.scanExponentBody := by
  exact Functions.scanExponent_toCore_exactly

def finishDecimal : Command signature actions 3 :=
  Functions.finishDecimalView.command

def finishDecimalFractionBody : Command signature actions 5 :=
  ((Command.ifThenElse
      (isDigit (index (slot 0) (slot 4)) (i32 10))
      (Command.letValue digitResultType
        (digitCall (slot 0) (slot 1) (slot 4) (i32 10))
        ((Command.ifThenElse
            (unary .logicalNot (digitSucceeded (slot 5)))
            (returned (numberFailure (digitError (slot 5))))
            .skip).sequence
          (Command.letValue i32Type (digitEnd (slot 5))
            ((Command.ifThenElse
                (comparison .less (slot 6) (slot 1))
                (Command.letValue i32Type (index (slot 0) (slot 6))
                  ((Command.ifThenElse
                      ((comparison .equal (slot 7) (i32 101)).logicalOr
                        (comparison .equal (slot 7) (i32 69)))
                      (returned (scanExponentCall
                        (slot 0) (slot 1) (slot 6)))
                      .skip).sequence .skip))
                .skip).sequence
              (returned (floatScan (slot 6)))))))
      .skip).sequence
    (Command.letValue i32Type (index (slot 0) (slot 4))
      ((Command.ifThenElse
          ((comparison .equal (slot 5) (i32 101)).logicalOr
            (comparison .equal (slot 5) (i32 69)))
          (returned (scanExponentCall (slot 0) (slot 1) (slot 4)))
          .skip).sequence .skip)))

def finishDecimalTailBody : Command signature actions 5 :=
  (Command.ifThenElse
      (comparison .less (slot 4) (slot 1))
      finishDecimalFractionBody
      .skip).sequence
    (returned (floatScan (slot 4)))

def finishDecimalTail : Command signature actions 4 :=
  Command.letValue i32Type (add (slot 2) (i32 1)) finishDecimalTailBody

/-! Readable form of the exact checked `finish_decimal` command. -/
def finishDecimalReadable : Command signature actions 3 :=
  (Command.ifThenElse
      (comparison .greaterEqual (slot 2) (slot 1))
      (returned (integerScan (slot 2)))
      .skip).sequence
    (Command.letValue i32Type (index (slot 0) (slot 2))
      ((Command.ifThenElse
          ((comparison .equal (slot 3) (i32 101)).logicalOr
            (comparison .equal (slot 3) (i32 69)))
          (returned (scanExponentCall (slot 0) (slot 1) (slot 2)))
          .skip).sequence
        ((Command.ifThenElse
            (comparison .notEqual (slot 3) (i32 46))
            (returned (integerScan (slot 2)))
            .skip).sequence
          ((Command.ifThenElse
              (comparison .less (add (slot 2) (i32 1)) (slot 1))
              ((Command.ifThenElse
                  (comparison .equal
                    (index (slot 0) (add (slot 2) (i32 1))) (i32 46))
                  (returned (integerScan (slot 2)))
                  .skip).sequence .skip)
              .skip).sequence
            finishDecimalTail))))

theorem finishDecimalReadable_toCore_exactly :
    toCoreStmt actionAdapter identityLayout 3 finishDecimalReadable =
      Functions.finishDecimalBody := by
  rfl

theorem finishDecimal_toCore_exactly :
    toCoreStmt actionAdapter identityLayout 3 finishDecimal =
      Functions.finishDecimalBody := by
  exact Functions.finishDecimal_toCore_exactly

end Lanius.Extraction.Decimal.Commands
