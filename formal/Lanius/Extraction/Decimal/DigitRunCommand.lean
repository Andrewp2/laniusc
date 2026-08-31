import Lanius.Extraction.Lexer.Digits

namespace Lanius.Extraction.Decimal.DigitRunCommand

open Lanius
open Lanius.Core
open Lanius.Extraction
open Lanius.Compiler.Lexer.Program
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.Stateful
open Lanius.FunctionalView.Stateful

def boolType : Ty := .scalar .bool
def resultType : Ty := .structure 2
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

def failed {arity : Nat} (offset : Term signature arity) :
    Term signature arity :=
  call extractedFailedDigitsFunction [i32Type] [offset]

def successful {arity : Nat} (offset : Term signature arity) :
    Term signature arity :=
  call extractedSuccessfulDigitsFunction [i32Type] [offset]

def isDigit {arity : Nat} (byte base : Term signature arity) :
    Term signature arity :=
  call extractedIsDigitForBaseFunction [i32Type, i32Type] [byte, base]

def add {arity : Nat} (left right : Term signature arity) :
    Term signature arity := binary .add left right i32Type

def comparison {arity : Nat} (operation : BinaryOp)
    (left right : Term signature arity) : Term signature arity :=
  binary operation left right boolType

def returned {arity : Nat} (value : Term signature arity) :
    Command signature actions arity :=
  (Command.returnValue (some value)).sequence .skip

def statement {arity : Nat} (command : Command signature actions arity) :
    Command signature actions arity :=
  command.sequence .skip

def startOutOfBounds : Term signature 4 :=
  comparison .greaterEqual (slot 2) (slot 1)

def initialInvalid : Term signature 4 :=
  unary .logicalNot (isDigit (index (slot 0) (slot 2)) (slot 3))

def offsetInitializer : Term signature 4 := add (slot 2) (i32 1)

def loopCondition : Term signature 5 :=
  comparison .less (slot 4) (slot 1)

def currentByte : Term signature 5 := index (slot 0) (slot 4)

def currentValid : Term signature 6 := isDigit (slot 5) (slot 3)

def currentSeparator : Term signature 6 :=
  comparison .equal (slot 5) (i32 95)

def requiredInitializer : Term signature 6 := add (slot 4) (i32 1)

def requiredOutOfBounds : Term signature 7 :=
  comparison .greaterEqual (slot 6) (slot 1)

def requiredInvalid : Term signature 7 :=
  unary .logicalNot (isDigit (index (slot 0) (slot 6)) (slot 3))

def offsetAfterRequired : Term signature 7 := add (slot 6) (i32 1)

def loopBody : Command signature actions 5 :=
  .letValue i32Type currentByte
    (statement
      (.ifThenElse currentValid
        (statement (.updateLocal .add 4 (i32 1)))
        (statement
          (.ifThenElse currentSeparator
            (.letValue i32Type requiredInitializer
              (.sequence
                (.ifThenElse requiredOutOfBounds
                  (returned (failed (slot 6))) .skip)
                (.sequence
                  (.ifThenElse requiredInvalid
                    (returned (failed (slot 6))) .skip)
                  (statement (.setLocal 4 offsetAfterRequired)))))
            (returned (successful (slot 4)))))))

def command : Command signature actions 4 :=
  .sequence
    (.ifThenElse startOutOfBounds
      (returned (failed (slot 2))) .skip)
    (.sequence
      (.ifThenElse initialInvalid
        (returned (failed (slot 2))) .skip)
      (.letValue i32Type offsetInitializer
        (.sequence
          (.whileLoop loopCondition loopBody)
          (returned (successful (slot 4))))))

theorem toCore_exactly :
    toCoreStmt actionAdapter identityLayout 4 command =
      Lanius.Extraction.Lexer.Digits.scanDigitRunBody := by
  rfl

end Lanius.Extraction.Decimal.DigitRunCommand
