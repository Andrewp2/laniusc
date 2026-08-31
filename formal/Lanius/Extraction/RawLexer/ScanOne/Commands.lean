import Lanius.Extraction.RawLexer.ScanOne.Functions
import Lanius.Extraction.Lexer.Functions
import Lanius.Extraction.Lexer.Scanners
import Lanius.Extraction.Number.Functions
import Lanius.Extraction.Symbol.Functions
import Lanius.Extraction.TokenScan.Functions

namespace Lanius.Extraction.RawLexer.ScanOne.Commands

open Lanius
open Lanius.Core
open Lanius.Extraction
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.Stateful
open Lanius.FunctionalView.Stateful

def boolType : Ty := .scalar .bool
def i32Type : Ty := .scalar (.signed .i32)
def sliceType : Ty := .slice i32Type
def scanEndType : Ty := .structure 0
def tokenScanType : Ty := .structure 1
def tokenMatchType : Ty := .structure 3

def slot {arity : Nat} (index : Fin arity) : Term signature arity :=
  .reference (.slot index)

def i32 {arity : Nat} (value : Int) : Term signature arity :=
  .reference (.literal (.signed .i32 value))

def constant {arity : Nat} (id : ConstantId) : Term signature arity :=
  .apply (.constant id i32Type) []

def call {arity : Nat} (function : Function)
    (arguments : List (Term signature arity)) : Term signature arity :=
  .apply (.call function.id (function.parameters.map Prod.snd)
    function.returnType) arguments

def binary {arity : Nat} (operation : BinaryOp)
    (left right : Term signature arity) (result : Ty) : Term signature arity :=
  .apply (.binary operation i32Type i32Type result) [left, right]

def comparison {arity : Nat} (operation : BinaryOp)
    (left right : Term signature arity) : Term signature arity :=
  binary operation left right boolType

def add {arity : Nat} (left right : Term signature arity) :
    Term signature arity :=
  binary .add left right i32Type

def logicalNot {arity : Nat} (value : Term signature arity) :
    Term signature arity :=
  .apply (.unary .logicalNot boolType boolType) [value]

def index {arity : Nat} (source position : Term signature arity) :
    Term signature arity :=
  .apply (.index sliceType i32Type i32Type) [source, position]

def returned {arity : Nat} (value : Term signature arity) :
    Command signature actions arity :=
  (Command.returnValue (some value)).sequence .skip

def statement {arity : Nat} (command : Command signature actions arity) :
    Command signature actions arity :=
  command.sequence .skip

def failed {arity : Nat} (offset : Term signature arity) :
    Term signature arity :=
  call TokenScan.Functions.failedFunction [offset]

def successful {arity : Nat} (kind finish : Term signature arity) :
    Term signature arity :=
  call TokenScan.Functions.successfulFunction [kind, finish]

def scanSucceeded {arity : Nat} (result : Term signature arity) :
    Term signature arity :=
  call Lexer.Functions.scanSucceededFunction [result]

def scanEndOffset {arity : Nat} (result : Term signature arity) :
    Term signature arity :=
  call Lexer.Functions.scanEndOffsetFunction [result]

def scanErrorOffset {arity : Nat} (result : Term signature arity) :
    Term signature arity :=
  call Lexer.Functions.scanErrorOffsetFunction [result]

def delimitedBranch (scanner : Function) (kind : ConstantId) :
    Command signature actions 5 :=
  .letValue scanEndType (call scanner [slot 0, slot 1, slot 2])
    (.sequence
      (.ifThenElse (logicalNot (scanSucceeded (slot 5)))
        (returned (failed (scanErrorOffset (slot 5)))) .skip)
      (returned (successful (constant kind) (scanEndOffset (slot 5)))))

def blockCommentBranch : Command signature actions 7 :=
  .letValue scanEndType
    (call Lexer.Scanners.scanBlockCommentEndFunction [slot 0, slot 1, slot 2])
    (.sequence
      (.ifThenElse (logicalNot (scanSucceeded (slot 7)))
        (returned (failed (scanErrorOffset (slot 7)))) .skip)
      (returned (successful (slot 6) (scanEndOffset (slot 7)))))

def symbolTail : Command signature actions 5 :=
  .letValue tokenMatchType
    (call Symbol.Functions.matchSymbolHeadFunction [slot 0, slot 1, slot 2])
    (.letValue i32Type
      (call Symbol.Functions.tokenMatchKindFunction [slot 5])
      (.sequence
        (.ifThenElse (comparison .equal (slot 6) (constant 16))
          (returned (successful (slot 6)
            (call Lexer.Scanners.scanLineCommentEndFunction
              [slot 0, slot 1, slot 2]))) .skip)
        (.sequence
          (.ifThenElse (comparison .equal (slot 6) (constant 17))
            blockCommentBranch .skip)
          (returned (successful (slot 6)
            (add (slot 2)
              (call Symbol.Functions.tokenMatchLengthFunction [slot 5])))))))

def dotNumberBranch : Command signature actions 5 :=
  .letValue i32Type (index (slot 0) (add (slot 2) (i32 1)))
    (statement
      (.ifThenElse
        (call Lexer.Functions.isDecimalDigitFunction [slot 5])
        (returned (call Number.Functions.scanLeadingDotNumberFunction
          [slot 0, slot 1, slot 2])) .skip))

def symbolBranch : Command signature actions 5 :=
  .sequence
    (.ifThenElse
      ((comparison .equal (slot 3) (i32 46)).logicalAnd
        (comparison .less (add (slot 2) (i32 1)) (slot 1)))
      dotNumberBranch .skip)
    symbolTail

def dispatch : Command signature actions 5 :=
  .sequence
    (.ifThenElse (comparison .equal (slot 4) (constant 0))
      (returned (successful (constant 7)
        (call Lexer.Scanners.scanIdentifierEndFunction
          [slot 0, slot 1, slot 2]))) .skip)
    (.sequence
      (.ifThenElse (comparison .equal (slot 4) (constant 1))
        (returned (call Number.Functions.scanNumberFunction
          [slot 0, slot 1, slot 2])) .skip)
      (.sequence
        (.ifThenElse (comparison .equal (slot 4) (constant 2))
          (returned (successful (constant 9)
            (call Lexer.Scanners.scanWhitespaceEndFunction
              [slot 0, slot 1, slot 2]))) .skip)
        (.sequence
          (.ifThenElse (comparison .equal (slot 4) (constant 4))
            (delimitedBranch Lexer.Scanners.scanStringEndFunction 34) .skip)
          (.sequence
            (.ifThenElse (comparison .equal (slot 4) (constant 5))
              (delimitedBranch Lexer.Scanners.scanCharacterEndFunction 36) .skip)
            (.sequence
              (.ifThenElse (comparison .equal (slot 4) (constant 3))
                symbolBranch .skip)
              (returned (failed (slot 2))))))))

def scanOne : Command signature actions 3 :=
  .sequence
    (.ifThenElse (comparison .greaterEqual (slot 2) (slot 1))
      (returned (failed (slot 2))) .skip)
    (.letValue i32Type (index (slot 0) (slot 2))
      (.letValue i32Type
        (call Lexer.Functions.classifyStartFunction [slot 3])
        dispatch))

/-- The readable command is an exact presentation of the selected checked
`scan_one` body, not an independent source-level implementation. -/
theorem scanOne_toCore_exactly :
    toCoreStmt actionAdapter identityLayout 3 scanOne =
      Functions.scanOneBody := by
  rfl

end Lanius.Extraction.RawLexer.ScanOne.Commands
