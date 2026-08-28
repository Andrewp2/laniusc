import Lanius.Compiler.Lexer
import Lanius.Semantics
import Lanius.Typing

namespace Lanius.Compiler.Lexer.Program

open Lanius
open Lanius.Core
open Lanius.Semantics
open Lanius.Typing

/-!
This file is the semantic bridge between the executable compiler source in
`verified_compiler/src/verified/lexer.lani` and the abstract lexer contract.
Definitions here are Lanius core syntax, not a second executable Lean lexer.
Their theorems therefore state properties of executing Lanius functions under
the language's formal dynamic semantics.
-/

def i32Type : Ty := .scalar (.signed .i32)

def i32Literal (value : Int) : Expr := .value (.signed .i32 value)

def byteLocal : Expr := .local 0

def compareByte (operation : BinaryOp) (value : Int) : Expr :=
  .binary operation byteLocal (i32Literal value)

def andExpr (left right : Expr) : Expr := .binary .logicalAnd left right

def orExpr (left right : Expr) : Expr := .binary .logicalOr left right

def byteInClosedRange (lower upper : Int) : Expr :=
  andExpr (compareByte .greaterEqual lower) (compareByte .lessEqual upper)

/-- Left-associated equality disjunction, matching a Lanius `a || b || c`
expression. The empty case is useful to make the constructor total. -/
def byteEqualsAny : List Int → Expr
  | [] => .value (.boolean false)
  | first :: rest =>
      rest.foldl (fun result value => orExpr result (compareByte .equal value))
        (compareByte .equal first)

def identifierStartExpr : Expr :=
  orExpr
    (orExpr (byteInClosedRange 97 122) (byteInClosedRange 65 90))
    (compareByte .equal 95)

def decimalDigitExpr : Expr := byteInClosedRange 48 57

def whitespaceExpr : Expr := byteEqualsAny [32, 9, 10, 13]

def symbolStartExpr : Expr := byteEqualsAny
  [40, 41, 43, 42, 61, 45, 47, 33, 91, 93, 123, 125,
   60, 62, 38, 124, 37, 94, 126, 44, 59, 58, 63, 46]

def startIdentifierConstant : Constant := { id := 0, type := i32Type, value := .signed .i32 1 }
def startDecimalNumberConstant : Constant := { id := 1, type := i32Type, value := .signed .i32 2 }
def startWhitespaceConstant : Constant := { id := 2, type := i32Type, value := .signed .i32 3 }
def startSymbolConstant : Constant := { id := 3, type := i32Type, value := .signed .i32 4 }
def startStringLiteralConstant : Constant := { id := 4, type := i32Type, value := .signed .i32 5 }
def startCharacterLiteralConstant : Constant := { id := 5, type := i32Type, value := .signed .i32 6 }
def startInvalidConstant : Constant := { id := 6, type := i32Type, value := .signed .i32 7 }

def returnClass (constant : Constant) : Stmt :=
  .returnValue (some (.constant constant.id))

def returnBool (expression : Expr) : Stmt := .returnValue (some expression)

def isIdentifierStartFunction : Function := {
  id := 1
  parameters := [(0, i32Type)]
  returnType := .scalar .bool
  body := some (returnBool identifierStartExpr)
}

def isDecimalDigitFunction : Function := {
  id := 2
  parameters := [(0, i32Type)]
  returnType := .scalar .bool
  body := some (returnBool decimalDigitExpr)
}

def identifierContinueExpr : Expr :=
  orExpr
    (.call isIdentifierStartFunction.id [byteLocal])
    (.call isDecimalDigitFunction.id [byteLocal])

def isIdentifierContinueFunction : Function := {
  id := 3
  parameters := [(0, i32Type)]
  returnType := .scalar .bool
  body := some (returnBool identifierContinueExpr)
}

def isWhitespaceFunction : Function := {
  id := 4
  parameters := [(0, i32Type)]
  returnType := .scalar .bool
  body := some (returnBool whitespaceExpr)
}

def isSymbolStartFunction : Function := {
  id := 5
  parameters := [(0, i32Type)]
  returnType := .scalar .bool
  body := some (returnBool symbolStartExpr)
}

def scanEndDeclaration : StructDecl := {
  id := 0
  fields := [.scalar .bool, i32Type, i32Type]
}

def scanSucceededFunction : Function := {
  id := 6
  parameters := [(0, .structure scanEndDeclaration.id)]
  returnType := .scalar .bool
  body := some (.returnValue (some (.field (.local 0) 0)))
}

def scanEndOffsetFunction : Function := {
  id := 7
  parameters := [(0, .structure scanEndDeclaration.id)]
  returnType := i32Type
  body := some (.returnValue (some (.field (.local 0) 1)))
}

def scanErrorOffsetFunction : Function := {
  id := 8
  parameters := [(0, .structure scanEndDeclaration.id)]
  returnType := i32Type
  body := some (.returnValue (some (.field (.local 0) 2)))
}

def successfulScanFunction : Function := {
  id := 9
  parameters := [(0, i32Type)]
  returnType := .structure scanEndDeclaration.id
  body := some (.returnValue (some (.structValue scanEndDeclaration.id
    [.value (.boolean true), .local 0, i32Literal 0])))
}

def failedScanFunction : Function := {
  id := 10
  parameters := [(0, i32Type)]
  returnType := .structure scanEndDeclaration.id
  body := some (.returnValue (some (.structValue scanEndDeclaration.id
    [.value (.boolean false), i32Literal 0, .local 0])))
}

def scannerParameters : List (VarId × Ty) :=
  [(0, .slice i32Type), (1, i32Type), (2, i32Type)]

def scannerCondition (predicate : Function) : Expr :=
  andExpr
    (.binary .less (.local 3) (.local 1))
    (.call predicate.id [.index (.local 0) (.local 3)])

def scannerBody (predicate : Function) : Stmt :=
  .letLocal 3 i32Type (.binary .add (.local 2) (i32Literal 1))
    (.sequence
      (.whileLoop (scannerCondition predicate)
        (.expression (.assign .add (.local 3) (i32Literal 1))))
      (.returnValue (some (.local 3))))

def scanIdentifierEndFunction : Function := {
  id := 11
  parameters := scannerParameters
  returnType := i32Type
  body := some (scannerBody isIdentifierContinueFunction)
}

def scanWhitespaceEndFunction : Function := {
  id := 12
  parameters := scannerParameters
  returnType := i32Type
  body := some (scannerBody isWhitespaceFunction)
}

def quotedScannerParameters : List (VarId × Ty) :=
  scannerParameters ++ [(3, i32Type)]

def assignLocal (id : VarId) (value : Expr) : Stmt :=
  .expression (.assign .set (.local id) value)

def incrementLocal (id : VarId) (amount : Int) : Stmt :=
  .expression (.assign .add (.local id) (i32Literal amount))

def callScanConstructor (constructor : Function) (offset : Expr) : Expr :=
  .call constructor.id [offset]

def quotedUnescapedBody : Stmt :=
  .sequence
    (.ifThenElse (.binary .equal (.local 6) (i32Literal 10))
      (.returnValue (some
        (callScanConstructor failedScanFunction (.local 4))))
      .skip)
    (.sequence
      (.ifThenElse (.binary .equal (.local 6) (.local 3))
        (.returnValue (some (callScanConstructor successfulScanFunction
          (.binary .add (.local 4) (i32Literal 1)))))
        .skip)
      (.sequence
        (.ifThenElse (.binary .equal (.local 6) (i32Literal 92))
          (assignLocal 5 (.value (.boolean true)))
          .skip)
        (incrementLocal 4 1)))

def quotedLoopBody : Stmt :=
  .letLocal 6 i32Type (.index (.local 0) (.local 4))
    (.ifThenElse (.local 5)
      (.sequence
        (assignLocal 5 (.value (.boolean false)))
        (incrementLocal 4 1))
      quotedUnescapedBody)

def quotedScannerBody : Stmt :=
  .letLocal 4 i32Type (.binary .add (.local 2) (i32Literal 1))
    (.letLocal 5 (.scalar .bool) (.value (.boolean false))
      (.sequence
        (.whileLoop (.binary .less (.local 4) (.local 1)) quotedLoopBody)
        (.returnValue (some
          (callScanConstructor failedScanFunction (.local 1))))))

def scanQuotedEndFunction : Function := {
  id := 13
  parameters := quotedScannerParameters
  returnType := .structure scanEndDeclaration.id
  body := some quotedScannerBody
}

def quotedWrapperBody (delimiter : Int) : Stmt :=
  .returnValue (some (.call scanQuotedEndFunction.id
    [.local 0, .local 1, .local 2, i32Literal delimiter]))

def scanStringEndFunction : Function := {
  id := 14
  parameters := scannerParameters
  returnType := .structure scanEndDeclaration.id
  body := some (quotedWrapperBody 34)
}

def scanCharacterEndFunction : Function := {
  id := 15
  parameters := scannerParameters
  returnType := .structure scanEndDeclaration.id
  body := some (quotedWrapperBody 39)
}

def lineCommentCondition : Expr :=
  andExpr
    (.binary .less (.local 3) (.local 1))
    (.binary .notEqual (.index (.local 0) (.local 3)) (i32Literal 10))

def lineCommentBody : Stmt :=
  .letLocal 3 i32Type (.binary .add (.local 2) (i32Literal 2))
    (.sequence
      (.whileLoop lineCommentCondition (incrementLocal 3 1))
      (.returnValue (some (.local 3))))

def scanLineCommentEndFunction : Function := {
  id := 16
  parameters := scannerParameters
  returnType := i32Type
  body := some lineCommentBody
}

def blockCommentCloseCondition : Expr :=
  andExpr
    (.binary .equal (.index (.local 0) (.local 3)) (i32Literal 42))
    (andExpr
      (.binary .less
        (.binary .add (.local 3) (i32Literal 1)) (.local 1))
      (.binary .equal
        (.index (.local 0)
          (.binary .add (.local 3) (i32Literal 1)))
        (i32Literal 47)))

def blockCommentLoopBody : Stmt :=
  .sequence
    (.ifThenElse blockCommentCloseCondition
      (.returnValue (some (callScanConstructor successfulScanFunction
        (.binary .add (.local 3) (i32Literal 2)))))
      .skip)
    (incrementLocal 3 1)

def blockCommentBody : Stmt :=
  .letLocal 3 i32Type (.binary .add (.local 2) (i32Literal 2))
    (.sequence
      (.whileLoop (.binary .less (.local 3) (.local 1))
        blockCommentLoopBody)
      (.returnValue (some
        (callScanConstructor failedScanFunction (.local 1)))))

def scanBlockCommentEndFunction : Function := {
  id := 17
  parameters := scannerParameters
  returnType := .structure scanEndDeclaration.id
  body := some blockCommentBody
}

def tokenScanDeclaration : StructDecl := {
  id := 1
  fields := [.scalar .bool, i32Type, i32Type, i32Type]
}

def tokenScanSucceededFunction : Function := {
  id := 18
  parameters := [(0, .structure tokenScanDeclaration.id)]
  returnType := .scalar .bool
  body := some (.returnValue (some (.field (.local 0) 0)))
}

def tokenScanKindFunction : Function := {
  id := 19
  parameters := [(0, .structure tokenScanDeclaration.id)]
  returnType := i32Type
  body := some (.returnValue (some (.field (.local 0) 1)))
}

def tokenScanEndOffsetFunction : Function := {
  id := 20
  parameters := [(0, .structure tokenScanDeclaration.id)]
  returnType := i32Type
  body := some (.returnValue (some (.field (.local 0) 2)))
}

def tokenScanErrorOffsetFunction : Function := {
  id := 21
  parameters := [(0, .structure tokenScanDeclaration.id)]
  returnType := i32Type
  body := some (.returnValue (some (.field (.local 0) 3)))
}

def successfulTokenScanFunction : Function := {
  id := 22
  parameters := [(0, i32Type), (1, i32Type)]
  returnType := .structure tokenScanDeclaration.id
  body := some (.returnValue (some (.structValue tokenScanDeclaration.id
    [.value (.boolean true), .local 0, .local 1, i32Literal 0])))
}

def failedTokenScanFunction : Function := {
  id := 23
  parameters := [(0, i32Type)]
  returnType := .structure tokenScanDeclaration.id
  body := some (.returnValue (some (.structValue tokenScanDeclaration.id
    [.value (.boolean false), i32Literal 0, i32Literal 0, .local 0])))
}

def digitScanDeclaration : StructDecl := {
  id := 2
  fields := [.scalar .bool, i32Type, i32Type]
}

def digitScanSucceededFunction : Function := {
  id := 24
  parameters := [(0, .structure digitScanDeclaration.id)]
  returnType := .scalar .bool
  body := some (.returnValue (some (.field (.local 0) 0)))
}

def digitScanEndOffsetFunction : Function := {
  id := 25
  parameters := [(0, .structure digitScanDeclaration.id)]
  returnType := i32Type
  body := some (.returnValue (some (.field (.local 0) 1)))
}

def digitScanErrorOffsetFunction : Function := {
  id := 26
  parameters := [(0, .structure digitScanDeclaration.id)]
  returnType := i32Type
  body := some (.returnValue (some (.field (.local 0) 2)))
}

def successfulDigitsFunction : Function := {
  id := 27
  parameters := [(0, i32Type)]
  returnType := .structure digitScanDeclaration.id
  body := some (.returnValue (some (.structValue digitScanDeclaration.id
    [.value (.boolean true), .local 0, i32Literal 0])))
}

def failedDigitsFunction : Function := {
  id := 28
  parameters := [(0, i32Type)]
  returnType := .structure digitScanDeclaration.id
  body := some (.returnValue (some (.structValue digitScanDeclaration.id
    [.value (.boolean false), i32Literal 0, .local 0])))
}

def digitByteInRange (lower upper : Int) : Expr :=
  andExpr
    (.binary .greaterEqual (.local 0) (i32Literal lower))
    (.binary .lessEqual (.local 0) (i32Literal upper))

def digitValueLessBase (lower adjustment : Int) : Expr :=
  .binary .less
    (.binary .add
      (.binary .subtract (.local 0) (i32Literal lower))
      (i32Literal adjustment))
    (.local 1)

def isDigitForBaseBody : Stmt :=
  .ifThenElse (digitByteInRange 48 57)
    (.returnValue (some (digitValueLessBase 48 0)))
    (.ifThenElse (digitByteInRange 97 102)
      (.returnValue (some (digitValueLessBase 97 10)))
      (.ifThenElse (digitByteInRange 65 70)
        (.returnValue (some (digitValueLessBase 65 10)))
        (.returnValue (some (.value (.boolean false))))))

def isDigitForBaseFunction : Function := {
  id := 29
  parameters := [(0, i32Type), (1, i32Type)]
  returnType := .scalar .bool
  body := some isDigitForBaseBody
}

def digitRunParameters : List (VarId × Ty) :=
  scannerParameters ++ [(3, i32Type)]

def callIsDigitForBase (byte base : Expr) : Expr :=
  .call isDigitForBaseFunction.id [byte, base]

def callSuccessfulDigits (offset : Expr) : Expr :=
  .call successfulDigitsFunction.id [offset]

def callFailedDigits (offset : Expr) : Expr :=
  .call failedDigitsFunction.id [offset]

def digitRunLoopBody : Stmt :=
  .letLocal 5 i32Type (.index (.local 0) (.local 4))
    (.ifThenElse (callIsDigitForBase (.local 5) (.local 3))
      (incrementLocal 4 1)
      (.ifThenElse (.binary .equal (.local 5) (i32Literal 95))
        (.letLocal 6 i32Type (.binary .add (.local 4) (i32Literal 1))
          (.sequence
            (.ifThenElse (.binary .greaterEqual (.local 6) (.local 1))
              (.returnValue (some (callFailedDigits (.local 6))))
              .skip)
            (.sequence
              (.ifThenElse
                (.unary .logicalNot
                  (callIsDigitForBase
                    (.index (.local 0) (.local 6)) (.local 3)))
                (.returnValue (some (callFailedDigits (.local 6))))
                .skip)
              (assignLocal 4
                (.binary .add (.local 6) (i32Literal 1))))))
        (.returnValue (some (callSuccessfulDigits (.local 4))))))

def scanDigitRunBody : Stmt :=
  .sequence
    (.ifThenElse (.binary .greaterEqual (.local 2) (.local 1))
      (.returnValue (some (callFailedDigits (.local 2))))
      .skip)
    (.sequence
      (.ifThenElse
        (.unary .logicalNot
          (callIsDigitForBase
            (.index (.local 0) (.local 2)) (.local 3)))
        (.returnValue (some (callFailedDigits (.local 2))))
        .skip)
      (.letLocal 4 i32Type (.binary .add (.local 2) (i32Literal 1))
        (.sequence
          (.whileLoop (.binary .less (.local 4) (.local 1))
            digitRunLoopBody)
          (.returnValue (some (callSuccessfulDigits (.local 4)))))))

def scanDigitRunFunction : Function := {
  id := 30
  parameters := digitRunParameters
  returnType := .structure digitScanDeclaration.id
  body := some scanDigitRunBody
}

/-- Core body of `verified::lexer::classify_start`. Its nested shape follows
the source function rather than replacing it with a lookup table. -/
def classifyStartBody : Stmt :=
  .ifThenElse identifierStartExpr (returnClass startIdentifierConstant)
    (.ifThenElse decimalDigitExpr (returnClass startDecimalNumberConstant)
      (.ifThenElse whitespaceExpr (returnClass startWhitespaceConstant)
        (.ifThenElse (compareByte .equal 34) (returnClass startStringLiteralConstant)
          (.ifThenElse (compareByte .equal 39) (returnClass startCharacterLiteralConstant)
            (.ifThenElse symbolStartExpr (returnClass startSymbolConstant)
              (returnClass startInvalidConstant))))))

def classifyStartFunction : Function := {
  id := 0
  parameters := [(0, i32Type)]
  returnType := i32Type
  body := some classifyStartBody
}

def lexerProgram : Core.Program := {
  structures := [scanEndDeclaration, tokenScanDeclaration, digitScanDeclaration]
  constants := [startIdentifierConstant, startDecimalNumberConstant,
    startWhitespaceConstant, startSymbolConstant, startStringLiteralConstant,
    startCharacterLiteralConstant, startInvalidConstant]
  functions := [classifyStartFunction, isIdentifierStartFunction,
    isDecimalDigitFunction, isIdentifierContinueFunction,
    isWhitespaceFunction, isSymbolStartFunction, scanSucceededFunction,
    scanEndOffsetFunction, scanErrorOffsetFunction, successfulScanFunction,
    failedScanFunction, scanIdentifierEndFunction, scanWhitespaceEndFunction,
    scanQuotedEndFunction, scanStringEndFunction, scanCharacterEndFunction,
    scanLineCommentEndFunction, scanBlockCommentEndFunction,
    tokenScanSucceededFunction, tokenScanKindFunction,
    tokenScanEndOffsetFunction, tokenScanErrorOffsetFunction,
    successfulTokenScanFunction, failedTokenScanFunction,
    digitScanSucceededFunction, digitScanEndOffsetFunction,
    digitScanErrorOffsetFunction, successfulDigitsFunction,
    failedDigitsFunction, isDigitForBaseFunction, scanDigitRunFunction]
}

private theorem i32Literal_typed
    (value : Int)
    (lower : signedMin lexerProgram.target .i32 ≤ value)
    (upper : value ≤ signedMax lexerProgram.target .i32)
    (context : Context) :
    ExprHasType lexerProgram context (i32Literal value) i32Type := by
  exact .value (.signed .i32 value lower upper) rfl

private theorem byteLocal_typed :
    ExprHasType lexerProgram (parameterContext classifyStartFunction.parameters)
      byteLocal i32Type := by
  exact .local (by rfl)

private theorem compareByte_typed
    (operation : BinaryOp)
    (value : Int)
    (lower : signedMin lexerProgram.target .i32 ≤ value)
    (upper : value ≤ signedMax lexerProgram.target .i32)
    (operationTyped :
      BinaryOpHasType operation i32Type i32Type (.scalar .bool)) :
    ExprHasType lexerProgram (parameterContext classifyStartFunction.parameters)
      (compareByte operation value) (.scalar .bool) := by
  exact .binary byteLocal_typed
    (i32Literal_typed value lower upper _) operationTyped

private theorem andExpr_typed
    {left right : Expr}
    (leftTyped : ExprHasType lexerProgram
      (parameterContext classifyStartFunction.parameters) left (.scalar .bool))
    (rightTyped : ExprHasType lexerProgram
      (parameterContext classifyStartFunction.parameters) right (.scalar .bool)) :
    ExprHasType lexerProgram (parameterContext classifyStartFunction.parameters)
      (andExpr left right) (.scalar .bool) := by
  exact .binary leftTyped rightTyped .logicalAnd

private theorem orExpr_typed
    {left right : Expr}
    (leftTyped : ExprHasType lexerProgram
      (parameterContext classifyStartFunction.parameters) left (.scalar .bool))
    (rightTyped : ExprHasType lexerProgram
      (parameterContext classifyStartFunction.parameters) right (.scalar .bool)) :
    ExprHasType lexerProgram (parameterContext classifyStartFunction.parameters)
      (orExpr left right) (.scalar .bool) := by
  exact .binary leftTyped rightTyped .logicalOr

private theorem byteInClosedRange_typed (lower upper : Int)
    (lowerLower : signedMin lexerProgram.target .i32 ≤ lower)
    (lowerUpper : lower ≤ signedMax lexerProgram.target .i32)
    (upperLower : signedMin lexerProgram.target .i32 ≤ upper)
    (upperUpper : upper ≤ signedMax lexerProgram.target .i32) :
    ExprHasType lexerProgram (parameterContext classifyStartFunction.parameters)
      (byteInClosedRange lower upper) (.scalar .bool) := by
  apply andExpr_typed
  · exact compareByte_typed .greaterEqual lower lowerLower lowerUpper (.greaterEqual (.signed .i32))
  · exact compareByte_typed .lessEqual upper upperLower upperUpper (.lessEqual (.signed .i32))

private theorem byteEqualsAny_fold_typed
    (values : List Int) (accumulator : Expr)
    (accumulatorTyped : ExprHasType lexerProgram
      (parameterContext classifyStartFunction.parameters) accumulator (.scalar .bool))
    (valuesBounded : ∀ value ∈ values,
      signedMin lexerProgram.target .i32 ≤ value ∧
      value ≤ signedMax lexerProgram.target .i32) :
    ExprHasType lexerProgram (parameterContext classifyStartFunction.parameters)
      (values.foldl (fun result value => orExpr result (compareByte .equal value)) accumulator)
      (.scalar .bool) := by
  induction values generalizing accumulator with
  | nil => simpa
  | cons value rest inductionHypothesis =>
      simp only [List.foldl_cons]
      apply inductionHypothesis
      · apply orExpr_typed accumulatorTyped
        have bounds := valuesBounded value (by simp)
        exact compareByte_typed .equal value bounds.1 bounds.2 (.equal (.signed .i32))
      · intro candidate member
        exact valuesBounded candidate (by simp [member])

private theorem byteEqualsAny_typed
    (values : List Int)
    (valuesBounded : ∀ value ∈ values,
      signedMin lexerProgram.target .i32 ≤ value ∧
      value ≤ signedMax lexerProgram.target .i32) :
    ExprHasType lexerProgram (parameterContext classifyStartFunction.parameters)
      (byteEqualsAny values) (.scalar .bool) := by
  cases values with
  | nil => exact .value (.boolean false)
  | cons first rest =>
      simp only [byteEqualsAny]
      apply byteEqualsAny_fold_typed
      · have bounds := valuesBounded first (by simp)
        exact compareByte_typed .equal first bounds.1 bounds.2 (.equal (.signed .i32))
      · intro value member
        exact valuesBounded value (by simp [member])

private theorem returnClass_typed (constant : Constant)
    (found : lexerProgram.constant? constant.id = some constant)
    (classType : constant.type = i32Type) :
    StmtHasType lexerProgram i32Type
      (parameterContext classifyStartFunction.parameters) false (returnClass constant) := by
  have typed := ExprHasType.constant (context :=
    parameterContext classifyStartFunction.parameters) constant found
  rw [classType] at typed
  exact .returnValue typed

private theorem predicateCall_typed (function : Function)
    (found : lexerProgram.function? function.id = some function)
    (returnsBool : function.returnType = .scalar .bool)
    (parameters : function.parameters.map Prod.snd = [i32Type]) :
    ExprHasType lexerProgram (parameterContext classifyStartFunction.parameters)
      (.call function.id [byteLocal]) (.scalar .bool) := by
  rw [← returnsBool]
  apply ExprHasType.call function found
  rw [parameters]
  exact .cons byteLocal_typed .nil

theorem isIdentifierStartFunction_well_typed :
    FunctionWellTyped lexerProgram isIdentifierStartFunction := by
  refine ⟨rfl, StmtHasType.returnValue ?_, .inr .returnValue⟩
  apply orExpr_typed
  · apply orExpr_typed
    · exact byteInClosedRange_typed 97 122 (by decide) (by decide) (by decide) (by decide)
    · exact byteInClosedRange_typed 65 90 (by decide) (by decide) (by decide) (by decide)
  · exact compareByte_typed .equal 95 (by decide) (by decide) (.equal (.signed .i32))

theorem isDecimalDigitFunction_well_typed :
    FunctionWellTyped lexerProgram isDecimalDigitFunction := by
  refine ⟨rfl, StmtHasType.returnValue ?_, .inr .returnValue⟩
  exact byteInClosedRange_typed 48 57 (by decide) (by decide) (by decide) (by decide)

theorem isIdentifierContinueFunction_well_typed :
    FunctionWellTyped lexerProgram isIdentifierContinueFunction := by
  refine ⟨rfl, StmtHasType.returnValue ?_, .inr .returnValue⟩
  apply orExpr_typed
  · exact predicateCall_typed isIdentifierStartFunction (by rfl) rfl rfl
  · exact predicateCall_typed isDecimalDigitFunction (by rfl) rfl rfl

theorem isWhitespaceFunction_well_typed :
    FunctionWellTyped lexerProgram isWhitespaceFunction := by
  refine ⟨rfl, StmtHasType.returnValue ?_, .inr .returnValue⟩
  exact byteEqualsAny_typed [32, 9, 10, 13] (by native_decide)

theorem isSymbolStartFunction_well_typed :
    FunctionWellTyped lexerProgram isSymbolStartFunction := by
  refine ⟨rfl, StmtHasType.returnValue ?_, .inr .returnValue⟩
  exact byteEqualsAny_typed
    [40, 41, 43, 42, 61, 45, 47, 33, 91, 93, 123, 125,
     60, 62, 38, 124, 37, 94, 126, 44, 59, 58, 63, 46]
    (by native_decide)

private theorem scanEndLocal_typed :
    ExprHasType lexerProgram (parameterContext scanSucceededFunction.parameters)
      (.local 0) (.structure scanEndDeclaration.id) := by
  exact .local (by rfl)

private theorem scanEndField_typed (field : FieldId) (type : Ty)
    (fieldFound : scanEndDeclaration.fields[field]? = some type) :
    ExprHasType lexerProgram (parameterContext scanSucceededFunction.parameters)
      (.field (.local 0) field) type := by
  exact .field scanEndLocal_typed scanEndDeclaration (by rfl) fieldFound

theorem scanSucceededFunction_well_typed :
    FunctionWellTyped lexerProgram scanSucceededFunction := by
  exact ⟨rfl, .returnValue (scanEndField_typed 0 (.scalar .bool) rfl),
    .inr .returnValue⟩

theorem scanEndOffsetFunction_well_typed :
    FunctionWellTyped lexerProgram scanEndOffsetFunction := by
  exact ⟨rfl, .returnValue (scanEndField_typed 1 i32Type rfl),
    .inr .returnValue⟩

theorem scanErrorOffsetFunction_well_typed :
    FunctionWellTyped lexerProgram scanErrorOffsetFunction := by
  exact ⟨rfl, .returnValue (scanEndField_typed 2 i32Type rfl),
    .inr .returnValue⟩

private theorem scanConstructor_typed (success : Bool) (offsetField : FieldId) :
    ExprHasType lexerProgram (parameterContext successfulScanFunction.parameters)
      (.structValue scanEndDeclaration.id
        (if offsetField = 1 then
          [.value (.boolean success), .local 0, i32Literal 0]
        else [.value (.boolean success), i32Literal 0, .local 0]))
      (.structure scanEndDeclaration.id) := by
  apply ExprHasType.structValue scanEndDeclaration (by rfl)
  by_cases endField : offsetField = 1
  · simp only [endField, ↓reduceIte]
    exact .cons (.value (.boolean success) rfl)
      (.cons (.local (by rfl))
        (.cons (i32Literal_typed 0 (by decide) (by decide) _) .nil))
  · simp only [endField, ↓reduceIte]
    exact .cons (.value (.boolean success) rfl)
      (.cons (i32Literal_typed 0 (by decide) (by decide) _)
        (.cons (.local (by rfl)) .nil))

theorem successfulScanFunction_well_typed :
    FunctionWellTyped lexerProgram successfulScanFunction := by
  refine ⟨rfl, .returnValue ?_, .inr .returnValue⟩
  simpa [successfulScanFunction] using scanConstructor_typed true 1

theorem failedScanFunction_well_typed :
    FunctionWellTyped lexerProgram failedScanFunction := by
  refine ⟨rfl, .returnValue ?_, .inr .returnValue⟩
  simpa [failedScanFunction, successfulScanFunction] using scanConstructor_typed false 2

private def scannerContext : Context := parameterContext scannerParameters
private def scannerLoopContext : Context := scannerContext.bind 3 i32Type

private theorem scannerSource_typed :
    ExprHasType lexerProgram scannerLoopContext (.local 0) (.slice i32Type) := by
  exact .local (by rfl)

private theorem scannerLength_typed :
    ExprHasType lexerProgram scannerLoopContext (.local 1) i32Type := by
  exact .local (by rfl)

private theorem scannerEnd_typed :
    ExprHasType lexerProgram scannerLoopContext (.local 3) i32Type := by
  exact .local (by rfl)

private theorem scannerIndexedByte_typed :
    ExprHasType lexerProgram scannerLoopContext
      (.index (.local 0) (.local 3)) i32Type := by
  exact .indexSlice scannerSource_typed scannerEnd_typed (.signed .i32)

private theorem scannerCondition_typed (predicate : Function)
    (found : lexerProgram.function? predicate.id = some predicate)
    (returnsBool : predicate.returnType = .scalar .bool)
    (parameters : predicate.parameters.map Prod.snd = [i32Type]) :
    ExprHasType lexerProgram scannerLoopContext (scannerCondition predicate)
      (.scalar .bool) := by
  apply ExprHasType.binary
  · exact .binary scannerEnd_typed scannerLength_typed (.less (.signed .i32))
  · have callTyped : ExprHasType lexerProgram scannerLoopContext
        (.call predicate.id [.index (.local 0) (.local 3)]) predicate.returnType := by
      apply ExprHasType.call predicate found
      rw [parameters]
      exact .cons scannerIndexedByte_typed .nil
    rw [returnsBool] at callTyped
    exact callTyped
  · exact .logicalAnd

private theorem scannerBody_typed (predicate : Function)
    (found : lexerProgram.function? predicate.id = some predicate)
    (returnsBool : predicate.returnType = .scalar .bool)
    (parameters : predicate.parameters.map Prod.snd = [i32Type]) :
    StmtHasType lexerProgram i32Type scannerContext false (scannerBody predicate) := by
  apply StmtHasType.letLocal
  · exact .binary (.local (by rfl))
      (i32Literal_typed 1 (by decide) (by decide) _) (.add (.signed .i32))
  · apply StmtHasType.sequence
    · apply StmtHasType.whileLoop
      · exact scannerCondition_typed predicate found returnsBool parameters
      · apply StmtHasType.expression
        exact .assign (.local (by rfl))
          (i32Literal_typed 1 (by decide) (by decide) _) (.add (.signed .i32))
    · exact .returnValue scannerEnd_typed

theorem scanIdentifierEndFunction_well_typed :
    FunctionWellTyped lexerProgram scanIdentifierEndFunction := by
  exact ⟨rfl,
    scannerBody_typed isIdentifierContinueFunction (by rfl) rfl rfl,
    .inr (.letLocal (.sequenceRight .returnValue))⟩

theorem scanWhitespaceEndFunction_well_typed :
    FunctionWellTyped lexerProgram scanWhitespaceEndFunction := by
  exact ⟨rfl,
    scannerBody_typed isWhitespaceFunction (by rfl) rfl rfl,
    .inr (.letLocal (.sequenceRight .returnValue))⟩

private theorem lineCommentCondition_typed :
    ExprHasType lexerProgram scannerLoopContext lineCommentCondition
      (.scalar .bool) := by
  unfold lineCommentCondition
  exact .binary
    (.binary scannerEnd_typed scannerLength_typed (.less (.signed .i32)))
    (.binary scannerIndexedByte_typed
      (i32Literal_typed 10 (by decide) (by decide) _)
      (.notEqual (.signed .i32)))
    .logicalAnd

theorem scanLineCommentEndFunction_well_typed :
    FunctionWellTyped lexerProgram scanLineCommentEndFunction := by
  refine ⟨rfl, ?_, .inr (.letLocal (.sequenceRight .returnValue))⟩
  unfold lineCommentBody
  apply StmtHasType.letLocal
  · exact .binary (.local (by rfl))
      (i32Literal_typed 2 (by decide) (by decide) _) (.add (.signed .i32))
  · apply StmtHasType.sequence
    · apply StmtHasType.whileLoop
      · exact lineCommentCondition_typed
      · exact .expression (.assign (.local (by rfl))
          (i32Literal_typed 1 (by decide) (by decide) _) (.add (.signed .i32)))
    · exact .returnValue scannerEnd_typed

private def quotedContext : Context := parameterContext quotedScannerParameters
private def quotedOffsetContext : Context := quotedContext.bind 4 i32Type
private def quotedLoopContext : Context :=
  quotedOffsetContext.bind 5 (.scalar .bool)
private def quotedByteContext : Context := quotedLoopContext.bind 6 i32Type

private theorem quotedSource_typed :
    ExprHasType lexerProgram quotedLoopContext (.local 0) (.slice i32Type) := by
  exact .local (by rfl)

private theorem quotedLength_typed :
    ExprHasType lexerProgram quotedLoopContext (.local 1) i32Type := by
  exact .local (by rfl)

private theorem quotedOffset_typed :
    ExprHasType lexerProgram quotedLoopContext (.local 4) i32Type := by
  exact .local (by rfl)

private theorem quotedEscaping_typed :
    ExprHasType lexerProgram quotedLoopContext (.local 5) (.scalar .bool) := by
  exact .local (by rfl)

private theorem quotedByte_typed :
    ExprHasType lexerProgram quotedByteContext (.local 6) i32Type := by
  exact .local (by rfl)

private theorem quotedDelimiter_typed :
    ExprHasType lexerProgram quotedByteContext (.local 3) i32Type := by
  exact .local (by rfl)

private theorem quotedByteOffset_typed :
    ExprHasType lexerProgram quotedByteContext (.local 4) i32Type := by
  exact .local (by rfl)

private theorem failedScanCall_typed
    (context : Context)
    (offset : ExprHasType lexerProgram context offsetExpr i32Type) :
    ExprHasType lexerProgram context
      (callScanConstructor failedScanFunction offsetExpr)
      (.structure scanEndDeclaration.id) := by
  exact .call failedScanFunction (by rfl) (.cons offset .nil)

private theorem successfulScanCall_typed
    (context : Context)
    (offset : ExprHasType lexerProgram context offsetExpr i32Type) :
    ExprHasType lexerProgram context
      (callScanConstructor successfulScanFunction offsetExpr)
      (.structure scanEndDeclaration.id) := by
  exact .call successfulScanFunction (by rfl) (.cons offset .nil)

private theorem quotedIncrement_typed :
    StmtHasType lexerProgram (.structure scanEndDeclaration.id)
      quotedByteContext true (incrementLocal 4 1) := by
  exact .expression (.assign (.local (by rfl))
    (i32Literal_typed 1 (by decide) (by decide) _)
    (.add (.signed .i32)))

private theorem quotedUnescapedBody_typed :
    StmtHasType lexerProgram (.structure scanEndDeclaration.id)
      quotedByteContext true quotedUnescapedBody := by
  unfold quotedUnescapedBody
  apply StmtHasType.sequence
  · apply StmtHasType.ifThenElse
    · exact .binary quotedByte_typed
        (i32Literal_typed 10 (by decide) (by decide) _)
        (.equal (.signed .i32))
    · exact .returnValue (failedScanCall_typed _ quotedByteOffset_typed)
    · exact .skip
  · apply StmtHasType.sequence
    · apply StmtHasType.ifThenElse
      · exact .binary quotedByte_typed quotedDelimiter_typed
          (.equal (.signed .i32))
      · apply StmtHasType.returnValue
        apply successfulScanCall_typed
        exact .binary quotedByteOffset_typed
          (i32Literal_typed 1 (by decide) (by decide) _)
          (.add (.signed .i32))
      · exact .skip
    · apply StmtHasType.sequence
      · apply StmtHasType.ifThenElse
        · exact .binary quotedByte_typed
            (i32Literal_typed 92 (by decide) (by decide) _)
            (.equal (.signed .i32))
        · exact .expression (.assign (.local (by rfl))
            (.value (.boolean true) rfl) .set)
        · exact .skip
      · exact quotedIncrement_typed

private theorem quotedLoopBody_typed :
    StmtHasType lexerProgram (.structure scanEndDeclaration.id)
      quotedLoopContext true quotedLoopBody := by
  unfold quotedLoopBody
  apply StmtHasType.letLocal
  · exact .indexSlice quotedSource_typed quotedOffset_typed (.signed .i32)
  · apply StmtHasType.ifThenElse
    · exact .local (by rfl)
    · apply StmtHasType.sequence
      · exact .expression (.assign (.local (by rfl))
          (.value (.boolean false) rfl) .set)
      · exact quotedIncrement_typed
    · exact quotedUnescapedBody_typed

theorem scanQuotedEndFunction_well_typed :
    FunctionWellTyped lexerProgram scanQuotedEndFunction := by
  refine ⟨rfl, ?_, .inr (.letLocal (.letLocal (.sequenceRight .returnValue)))⟩
  unfold quotedScannerBody
  apply StmtHasType.letLocal
  · exact .binary (.local (by rfl))
      (i32Literal_typed 1 (by decide) (by decide) _)
      (.add (.signed .i32))
  · apply StmtHasType.letLocal
    · exact .value (.boolean false) rfl
    · apply StmtHasType.sequence
      · apply StmtHasType.whileLoop
        · exact .binary quotedOffset_typed quotedLength_typed (.less (.signed .i32))
        · exact quotedLoopBody_typed
      · exact .returnValue (failedScanCall_typed _ quotedLength_typed)

private theorem quotedWrapperBody_typed (delimiter : Int)
    (lower : signedMin lexerProgram.target .i32 ≤ delimiter)
    (upper : delimiter ≤ signedMax lexerProgram.target .i32) :
    StmtHasType lexerProgram (.structure scanEndDeclaration.id)
      scannerContext false (quotedWrapperBody delimiter) := by
  apply StmtHasType.returnValue
  apply ExprHasType.call scanQuotedEndFunction (by rfl)
  exact .cons (.local (by rfl))
    (.cons (.local (by rfl))
      (.cons (.local (by rfl))
        (.cons (i32Literal_typed delimiter lower upper _) .nil)))

theorem scanStringEndFunction_well_typed :
    FunctionWellTyped lexerProgram scanStringEndFunction := by
  exact ⟨rfl, quotedWrapperBody_typed 34 (by decide) (by decide),
    .inr .returnValue⟩

theorem scanCharacterEndFunction_well_typed :
    FunctionWellTyped lexerProgram scanCharacterEndFunction := by
  exact ⟨rfl, quotedWrapperBody_typed 39 (by decide) (by decide),
    .inr .returnValue⟩

private theorem scannerEndPlusOne_typed :
    ExprHasType lexerProgram scannerLoopContext
      (.binary .add (.local 3) (i32Literal 1)) i32Type := by
  exact .binary scannerEnd_typed
    (i32Literal_typed 1 (by decide) (by decide) _)
    (.add (.signed .i32))

private theorem blockCommentCloseCondition_typed :
    ExprHasType lexerProgram scannerLoopContext blockCommentCloseCondition
      (.scalar .bool) := by
  unfold blockCommentCloseCondition
  exact .binary
    (.binary scannerIndexedByte_typed
      (i32Literal_typed 42 (by decide) (by decide) _)
      (.equal (.signed .i32)))
    (.binary
      (.binary scannerEndPlusOne_typed scannerLength_typed
        (.less (.signed .i32)))
      (.binary
        (.indexSlice scannerSource_typed scannerEndPlusOne_typed
          (.signed .i32))
        (i32Literal_typed 47 (by decide) (by decide) _)
        (.equal (.signed .i32)))
      .logicalAnd)
    .logicalAnd

private theorem blockCommentLoopBody_typed :
    StmtHasType lexerProgram (.structure scanEndDeclaration.id)
      scannerLoopContext true blockCommentLoopBody := by
  unfold blockCommentLoopBody
  apply StmtHasType.sequence
  · apply StmtHasType.ifThenElse
    · exact blockCommentCloseCondition_typed
    · apply StmtHasType.returnValue
      apply successfulScanCall_typed
      exact .binary scannerEnd_typed
        (i32Literal_typed 2 (by decide) (by decide) _)
        (.add (.signed .i32))
    · exact .skip
  · exact .expression (.assign (.local (by rfl))
      (i32Literal_typed 1 (by decide) (by decide) _)
      (.add (.signed .i32)))

theorem scanBlockCommentEndFunction_well_typed :
    FunctionWellTyped lexerProgram scanBlockCommentEndFunction := by
  refine ⟨rfl, ?_, .inr (.letLocal (.sequenceRight .returnValue))⟩
  unfold blockCommentBody
  apply StmtHasType.letLocal
  · exact .binary (.local (by rfl))
      (i32Literal_typed 2 (by decide) (by decide) _)
      (.add (.signed .i32))
  · apply StmtHasType.sequence
    · apply StmtHasType.whileLoop
      · exact .binary scannerEnd_typed scannerLength_typed
          (.less (.signed .i32))
      · exact blockCommentLoopBody_typed
    · exact .returnValue (failedScanCall_typed _ scannerLength_typed)

private theorem tokenScanLocal_typed :
    ExprHasType lexerProgram
      (parameterContext tokenScanSucceededFunction.parameters)
      (.local 0) (.structure tokenScanDeclaration.id) := by
  exact .local (by rfl)

private theorem tokenScanField_typed (field : FieldId) (type : Ty)
    (fieldFound : tokenScanDeclaration.fields[field]? = some type) :
    ExprHasType lexerProgram
      (parameterContext tokenScanSucceededFunction.parameters)
      (.field (.local 0) field) type := by
  exact .field tokenScanLocal_typed tokenScanDeclaration (by rfl) fieldFound

theorem tokenScanSucceededFunction_well_typed :
    FunctionWellTyped lexerProgram tokenScanSucceededFunction := by
  exact ⟨rfl, .returnValue (tokenScanField_typed 0 (.scalar .bool) rfl),
    .inr .returnValue⟩

theorem tokenScanKindFunction_well_typed :
    FunctionWellTyped lexerProgram tokenScanKindFunction := by
  exact ⟨rfl, .returnValue (tokenScanField_typed 1 i32Type rfl),
    .inr .returnValue⟩

theorem tokenScanEndOffsetFunction_well_typed :
    FunctionWellTyped lexerProgram tokenScanEndOffsetFunction := by
  exact ⟨rfl, .returnValue (tokenScanField_typed 2 i32Type rfl),
    .inr .returnValue⟩

theorem tokenScanErrorOffsetFunction_well_typed :
    FunctionWellTyped lexerProgram tokenScanErrorOffsetFunction := by
  exact ⟨rfl, .returnValue (tokenScanField_typed 3 i32Type rfl),
    .inr .returnValue⟩

theorem successfulTokenScanFunction_well_typed :
    FunctionWellTyped lexerProgram successfulTokenScanFunction := by
  refine ⟨rfl, .returnValue ?_, .inr .returnValue⟩
  apply ExprHasType.structValue tokenScanDeclaration (by rfl)
  exact .cons (.value (.boolean true) rfl)
    (.cons (.local (by rfl))
      (.cons (.local (by rfl))
        (.cons (i32Literal_typed 0 (by decide) (by decide) _) .nil)))

theorem failedTokenScanFunction_well_typed :
    FunctionWellTyped lexerProgram failedTokenScanFunction := by
  refine ⟨rfl, .returnValue ?_, .inr .returnValue⟩
  apply ExprHasType.structValue tokenScanDeclaration (by rfl)
  exact .cons (.value (.boolean false) rfl)
    (.cons (i32Literal_typed 0 (by decide) (by decide) _)
      (.cons (i32Literal_typed 0 (by decide) (by decide) _)
        (.cons (.local (by rfl)) .nil)))

private theorem digitScanLocal_typed :
    ExprHasType lexerProgram
      (parameterContext digitScanSucceededFunction.parameters)
      (.local 0) (.structure digitScanDeclaration.id) := by
  exact .local (by rfl)

private theorem digitScanField_typed (field : FieldId) (type : Ty)
    (fieldFound : digitScanDeclaration.fields[field]? = some type) :
    ExprHasType lexerProgram
      (parameterContext digitScanSucceededFunction.parameters)
      (.field (.local 0) field) type := by
  exact .field digitScanLocal_typed digitScanDeclaration (by rfl) fieldFound

theorem digitScanSucceededFunction_well_typed :
    FunctionWellTyped lexerProgram digitScanSucceededFunction := by
  exact ⟨rfl, .returnValue (digitScanField_typed 0 (.scalar .bool) rfl),
    .inr .returnValue⟩

theorem digitScanEndOffsetFunction_well_typed :
    FunctionWellTyped lexerProgram digitScanEndOffsetFunction := by
  exact ⟨rfl, .returnValue (digitScanField_typed 1 i32Type rfl),
    .inr .returnValue⟩

theorem digitScanErrorOffsetFunction_well_typed :
    FunctionWellTyped lexerProgram digitScanErrorOffsetFunction := by
  exact ⟨rfl, .returnValue (digitScanField_typed 2 i32Type rfl),
    .inr .returnValue⟩

theorem successfulDigitsFunction_well_typed :
    FunctionWellTyped lexerProgram successfulDigitsFunction := by
  refine ⟨rfl, .returnValue ?_, .inr .returnValue⟩
  apply ExprHasType.structValue digitScanDeclaration (by rfl)
  exact .cons (.value (.boolean true) rfl)
    (.cons (.local (by rfl))
      (.cons (i32Literal_typed 0 (by decide) (by decide) _) .nil))

theorem failedDigitsFunction_well_typed :
    FunctionWellTyped lexerProgram failedDigitsFunction := by
  refine ⟨rfl, .returnValue ?_, .inr .returnValue⟩
  apply ExprHasType.structValue digitScanDeclaration (by rfl)
  exact .cons (.value (.boolean false) rfl)
    (.cons (i32Literal_typed 0 (by decide) (by decide) _)
      (.cons (.local (by rfl)) .nil))

private def digitFunctionContext : Context :=
  parameterContext isDigitForBaseFunction.parameters

private theorem digitByte_typed :
    ExprHasType lexerProgram digitFunctionContext (.local 0) i32Type := by
  exact .local (by rfl)

private theorem digitBase_typed :
    ExprHasType lexerProgram digitFunctionContext (.local 1) i32Type := by
  exact .local (by rfl)

private theorem digitByteInRange_typed (lower upper : Int)
    (lowerMin : signedMin lexerProgram.target .i32 ≤ lower)
    (lowerMax : lower ≤ signedMax lexerProgram.target .i32)
    (upperMin : signedMin lexerProgram.target .i32 ≤ upper)
    (upperMax : upper ≤ signedMax lexerProgram.target .i32) :
    ExprHasType lexerProgram digitFunctionContext
      (digitByteInRange lower upper) (.scalar .bool) := by
  exact .binary
    (.binary digitByte_typed
      (i32Literal_typed lower lowerMin lowerMax _)
      (.greaterEqual (.signed .i32)))
    (.binary digitByte_typed
      (i32Literal_typed upper upperMin upperMax _)
      (.lessEqual (.signed .i32)))
    .logicalAnd

private theorem digitValueLessBase_typed (lower adjustment : Int)
    (lowerMin : signedMin lexerProgram.target .i32 ≤ lower)
    (lowerMax : lower ≤ signedMax lexerProgram.target .i32)
    (adjustmentMin : signedMin lexerProgram.target .i32 ≤ adjustment)
    (adjustmentMax : adjustment ≤ signedMax lexerProgram.target .i32) :
    ExprHasType lexerProgram digitFunctionContext
      (digitValueLessBase lower adjustment) (.scalar .bool) := by
  exact .binary
    (.binary
      (.binary digitByte_typed
        (i32Literal_typed lower lowerMin lowerMax _)
        (.subtract (.signed .i32)))
      (i32Literal_typed adjustment adjustmentMin adjustmentMax _)
      (.add (.signed .i32)))
    digitBase_typed (.less (.signed .i32))

theorem isDigitForBaseFunction_well_typed :
    FunctionWellTyped lexerProgram isDigitForBaseFunction := by
  refine ⟨rfl, ?_, .inr (.ifThenElse .returnValue
    (.ifThenElse .returnValue (.ifThenElse .returnValue .returnValue)))⟩
  unfold isDigitForBaseBody
  apply StmtHasType.ifThenElse
  · exact digitByteInRange_typed 48 57 (by decide) (by decide)
      (by decide) (by decide)
  · exact .returnValue (digitValueLessBase_typed 48 0
      (by decide) (by decide) (by decide) (by decide))
  · apply StmtHasType.ifThenElse
    · exact digitByteInRange_typed 97 102 (by decide) (by decide)
        (by decide) (by decide)
    · exact .returnValue (digitValueLessBase_typed 97 10
        (by decide) (by decide) (by decide) (by decide))
    · apply StmtHasType.ifThenElse
      · exact digitByteInRange_typed 65 70 (by decide) (by decide)
          (by decide) (by decide)
      · exact .returnValue (digitValueLessBase_typed 65 10
          (by decide) (by decide) (by decide) (by decide))
      · exact .returnValue (.value (.boolean false) rfl)

private def digitRunContext : Context :=
  parameterContext digitRunParameters

private def digitRunOffsetContext : Context :=
  digitRunContext.bind 4 i32Type

private def digitRunByteContext : Context :=
  digitRunOffsetContext.bind 5 i32Type

private def digitRunRequiredContext : Context :=
  digitRunByteContext.bind 6 i32Type

private theorem isDigitForBaseCall_typed
    {context : Context} {byte base : Expr}
    (byteTyped : ExprHasType lexerProgram context byte i32Type)
    (baseTyped : ExprHasType lexerProgram context base i32Type) :
    ExprHasType lexerProgram context (callIsDigitForBase byte base)
      (.scalar .bool) := by
  exact .call isDigitForBaseFunction (by rfl)
    (.cons byteTyped (.cons baseTyped .nil))

private theorem successfulDigitsCall_typed
    {context : Context} {offset : Expr}
    (offsetTyped : ExprHasType lexerProgram context offset i32Type) :
    ExprHasType lexerProgram context (callSuccessfulDigits offset)
      (.structure digitScanDeclaration.id) := by
  exact .call successfulDigitsFunction (by rfl) (.cons offsetTyped .nil)

private theorem failedDigitsCall_typed
    {context : Context} {offset : Expr}
    (offsetTyped : ExprHasType lexerProgram context offset i32Type) :
    ExprHasType lexerProgram context (callFailedDigits offset)
      (.structure digitScanDeclaration.id) := by
  exact .call failedDigitsFunction (by rfl) (.cons offsetTyped .nil)

private theorem digitRunLoopBody_typed :
    StmtHasType lexerProgram (.structure digitScanDeclaration.id)
      digitRunOffsetContext true digitRunLoopBody := by
  unfold digitRunLoopBody
  apply StmtHasType.letLocal
  · exact .indexSlice (.local (by rfl)) (.local (by rfl)) (.signed .i32)
  · apply StmtHasType.ifThenElse
    · exact isDigitForBaseCall_typed (.local (by rfl)) (.local (by rfl))
    · exact .expression (.assign (.local (by rfl))
        (i32Literal_typed 1 (by decide) (by decide) _) (.add (.signed .i32)))
    · apply StmtHasType.ifThenElse
      · exact .binary (.local (by rfl))
          (i32Literal_typed 95 (by decide) (by decide) _)
          (.equal (.signed .i32))
      · apply StmtHasType.letLocal
        · exact .binary (.local (by rfl))
            (i32Literal_typed 1 (by decide) (by decide) _)
            (.add (.signed .i32))
        · apply StmtHasType.sequence
          · apply StmtHasType.ifThenElse
            · exact .binary (.local (by rfl)) (.local (by rfl))
                (.greaterEqual (.signed .i32))
            · exact .returnValue (failedDigitsCall_typed (.local (by rfl)))
            · exact .skip
          · apply StmtHasType.sequence
            · apply StmtHasType.ifThenElse
              · exact .unary
                  (isDigitForBaseCall_typed
                    (.indexSlice (.local (by rfl)) (.local (by rfl))
                      (.signed .i32))
                    (.local (by rfl)))
                  .logicalNot
              · exact .returnValue (failedDigitsCall_typed (.local (by rfl)))
              · exact .skip
            · exact .expression (.assign (.local (by rfl))
                (.binary (.local (by rfl))
                  (i32Literal_typed 1 (by decide) (by decide) _)
                  (.add (.signed .i32))) .set)
      · exact .returnValue (successfulDigitsCall_typed (.local (by rfl)))

theorem scanDigitRunFunction_well_typed :
    FunctionWellTyped lexerProgram scanDigitRunFunction := by
  refine ⟨rfl, ?_, .inr
    (.sequenceRight (.sequenceRight (.letLocal (.sequenceRight .returnValue))))⟩
  unfold scanDigitRunBody
  apply StmtHasType.sequence
  · apply StmtHasType.ifThenElse
    · exact .binary (.local (by rfl)) (.local (by rfl))
        (.greaterEqual (.signed .i32))
    · exact .returnValue (failedDigitsCall_typed (.local (by rfl)))
    · exact .skip
  · apply StmtHasType.sequence
    · apply StmtHasType.ifThenElse
      · exact .unary
          (isDigitForBaseCall_typed
            (.indexSlice (.local (by rfl)) (.local (by rfl)) (.signed .i32))
            (.local (by rfl)))
          .logicalNot
      · exact .returnValue (failedDigitsCall_typed (.local (by rfl)))
      · exact .skip
    · apply StmtHasType.letLocal
      · exact .binary (.local (by rfl))
          (i32Literal_typed 1 (by decide) (by decide) _)
          (.add (.signed .i32))
      · apply StmtHasType.sequence
        · apply StmtHasType.whileLoop
          · exact .binary (.local (by rfl)) (.local (by rfl))
              (.less (.signed .i32))
          · exact digitRunLoopBody_typed
        · exact .returnValue (successfulDigitsCall_typed (.local (by rfl)))

theorem classifyStartFunction_well_typed :
    FunctionWellTyped lexerProgram classifyStartFunction := by
  refine ⟨rfl, ?_, .inr ?_⟩
  · unfold classifyStartBody
    apply StmtHasType.ifThenElse
    · apply orExpr_typed
      · apply orExpr_typed
        · exact byteInClosedRange_typed 97 122 (by decide) (by decide) (by decide) (by decide)
        · exact byteInClosedRange_typed 65 90 (by decide) (by decide) (by decide) (by decide)
      · exact compareByte_typed .equal 95 (by decide) (by decide) (.equal (.signed .i32))
    · exact returnClass_typed startIdentifierConstant (by rfl) rfl
    · apply StmtHasType.ifThenElse
      · exact byteInClosedRange_typed 48 57 (by decide) (by decide) (by decide) (by decide)
      · exact returnClass_typed startDecimalNumberConstant (by rfl) rfl
      · apply StmtHasType.ifThenElse
        · exact byteEqualsAny_typed [32, 9, 10, 13] (by native_decide)
        · exact returnClass_typed startWhitespaceConstant (by rfl) rfl
        · apply StmtHasType.ifThenElse
          · exact compareByte_typed .equal 34 (by decide) (by decide) (.equal (.signed .i32))
          · exact returnClass_typed startStringLiteralConstant (by rfl) rfl
          · apply StmtHasType.ifThenElse
            · exact compareByte_typed .equal 39 (by decide) (by decide) (.equal (.signed .i32))
            · exact returnClass_typed startCharacterLiteralConstant (by rfl) rfl
            · apply StmtHasType.ifThenElse
              · exact byteEqualsAny_typed
                  [40, 41, 43, 42, 61, 45, 47, 33, 91, 93, 123, 125,
                   60, 62, 38, 124, 37, 94, 126, 44, 59, 58, 63, 46]
                  (by native_decide)
              · exact returnClass_typed startSymbolConstant (by rfl) rfl
              · exact returnClass_typed startInvalidConstant (by rfl) rfl
  · unfold classifyStartBody
    exact .ifThenElse .returnValue
      (.ifThenElse .returnValue
        (.ifThenElse .returnValue
          (.ifThenElse .returnValue
            (.ifThenElse .returnValue
              (.ifThenElse .returnValue .returnValue)))))

theorem lexerProgram_well_typed : ProgramWellTyped lexerProgram := by
  constructor
  · intro constant member
    simp only [lexerProgram, List.mem_cons, List.not_mem_nil, or_false] at member
    rcases member with rfl | rfl | rfl | rfl | rfl | rfl | rfl <;>
      exact .signed .i32 _ (by decide) (by decide)
  · intro function member
    simp only [lexerProgram, List.mem_cons, List.not_mem_nil, or_false] at member
    rcases member with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl |
      rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl |
      rfl | rfl | rfl | rfl | rfl | rfl | rfl
    · exact classifyStartFunction_well_typed
    · exact isIdentifierStartFunction_well_typed
    · exact isDecimalDigitFunction_well_typed
    · exact isIdentifierContinueFunction_well_typed
    · exact isWhitespaceFunction_well_typed
    · exact isSymbolStartFunction_well_typed
    · exact scanSucceededFunction_well_typed
    · exact scanEndOffsetFunction_well_typed
    · exact scanErrorOffsetFunction_well_typed
    · exact successfulScanFunction_well_typed
    · exact failedScanFunction_well_typed
    · exact scanIdentifierEndFunction_well_typed
    · exact scanWhitespaceEndFunction_well_typed
    · exact scanQuotedEndFunction_well_typed
    · exact scanStringEndFunction_well_typed
    · exact scanCharacterEndFunction_well_typed
    · exact scanLineCommentEndFunction_well_typed
    · exact scanBlockCommentEndFunction_well_typed
    · exact tokenScanSucceededFunction_well_typed
    · exact tokenScanKindFunction_well_typed
    · exact tokenScanEndOffsetFunction_well_typed
    · exact tokenScanErrorOffsetFunction_well_typed
    · exact successfulTokenScanFunction_well_typed
    · exact failedTokenScanFunction_well_typed
    · exact digitScanSucceededFunction_well_typed
    · exact digitScanEndOffsetFunction_well_typed
    · exact digitScanErrorOffsetFunction_well_typed
    · exact successfulDigitsFunction_well_typed
    · exact failedDigitsFunction_well_typed
    · exact isDigitForBaseFunction_well_typed
    · exact scanDigitRunFunction_well_typed

def outcomeI32? : Outcome Value → Option Int
  | .done (.signed .i32 value) _ => some value
  | _ => none

def outcomeBool? : Outcome Value → Option Bool
  | .done (.boolean value) _ => some value
  | _ => none

def outcomeScanEnd? : Outcome Value → Option (Bool × Int × Int)
  | .done (.structure 0 [.boolean success, .signed .i32 endOffset,
      .signed .i32 errorOffset]) _ => some (success, endOffset, errorOffset)
  | _ => none

def outcomeTokenScan? : Outcome Value → Option (Bool × Int × Int × Int)
  | .done (.structure 1 [.boolean success, .signed .i32 kind,
      .signed .i32 endOffset, .signed .i32 errorOffset]) _ =>
      some (success, kind, endOffset, errorOffset)
  | _ => none

def outcomeDigitScan? : Outcome Value → Option (Bool × Int × Int)
  | .done (.structure 2 [.boolean success, .signed .i32 endOffset,
      .signed .i32 errorOffset]) _ => some (success, endOffset, errorOffset)
  | _ => none

theorem scanSucceededFunction_correct (success : Bool) (endOffset errorOffset : Int) :
    outcomeBool? (evalExpr 16 lexerProgram {}
      (.call scanSucceededFunction.id [.value (.structure scanEndDeclaration.id
        [.boolean success, .signed .i32 endOffset, .signed .i32 errorOffset])])) =
      some success := by
  rfl

theorem scanEndOffsetFunction_correct (success : Bool) (endOffset errorOffset : Int) :
    outcomeI32? (evalExpr 16 lexerProgram {}
      (.call scanEndOffsetFunction.id [.value (.structure scanEndDeclaration.id
        [.boolean success, .signed .i32 endOffset, .signed .i32 errorOffset])])) =
      some endOffset := by
  rfl

theorem scanErrorOffsetFunction_correct (success : Bool) (endOffset errorOffset : Int) :
    outcomeI32? (evalExpr 16 lexerProgram {}
      (.call scanErrorOffsetFunction.id [.value (.structure scanEndDeclaration.id
        [.boolean success, .signed .i32 endOffset, .signed .i32 errorOffset])])) =
      some errorOffset := by
  rfl

theorem successfulScanFunction_correct (endOffset : Int) :
    outcomeScanEnd? (evalExpr 16 lexerProgram {}
      (.call successfulScanFunction.id [i32Literal endOffset])) =
      some (true, endOffset, 0) := by
  rfl

theorem failedScanFunction_correct (errorOffset : Int) :
    outcomeScanEnd? (evalExpr 16 lexerProgram {}
      (.call failedScanFunction.id [i32Literal errorOffset])) =
      some (false, 0, errorOffset) := by
  rfl

theorem tokenScanSucceededFunction_correct
    (success : Bool) (kind endOffset errorOffset : Int) :
    outcomeBool? (evalExpr 16 lexerProgram {}
      (.call tokenScanSucceededFunction.id
        [.value (.structure tokenScanDeclaration.id
          [.boolean success, .signed .i32 kind, .signed .i32 endOffset,
            .signed .i32 errorOffset])])) = some success := by
  rfl

theorem tokenScanKindFunction_correct
    (success : Bool) (kind endOffset errorOffset : Int) :
    outcomeI32? (evalExpr 16 lexerProgram {}
      (.call tokenScanKindFunction.id
        [.value (.structure tokenScanDeclaration.id
          [.boolean success, .signed .i32 kind, .signed .i32 endOffset,
            .signed .i32 errorOffset])])) = some kind := by
  rfl

theorem tokenScanEndOffsetFunction_correct
    (success : Bool) (kind endOffset errorOffset : Int) :
    outcomeI32? (evalExpr 16 lexerProgram {}
      (.call tokenScanEndOffsetFunction.id
        [.value (.structure tokenScanDeclaration.id
          [.boolean success, .signed .i32 kind, .signed .i32 endOffset,
            .signed .i32 errorOffset])])) = some endOffset := by
  rfl

theorem tokenScanErrorOffsetFunction_correct
    (success : Bool) (kind endOffset errorOffset : Int) :
    outcomeI32? (evalExpr 16 lexerProgram {}
      (.call tokenScanErrorOffsetFunction.id
        [.value (.structure tokenScanDeclaration.id
          [.boolean success, .signed .i32 kind, .signed .i32 endOffset,
            .signed .i32 errorOffset])])) = some errorOffset := by
  rfl

theorem successfulTokenScanFunction_correct (kind endOffset : Int) :
    outcomeTokenScan? (evalExpr 16 lexerProgram {}
      (.call successfulTokenScanFunction.id
        [i32Literal kind, i32Literal endOffset])) =
      some (true, kind, endOffset, 0) := by
  rfl

theorem failedTokenScanFunction_correct (errorOffset : Int) :
    outcomeTokenScan? (evalExpr 16 lexerProgram {}
      (.call failedTokenScanFunction.id [i32Literal errorOffset])) =
      some (false, 0, 0, errorOffset) := by
  rfl

theorem digitScanSucceededFunction_correct
    (success : Bool) (endOffset errorOffset : Int) :
    outcomeBool? (evalExpr 16 lexerProgram {}
      (.call digitScanSucceededFunction.id
        [.value (.structure digitScanDeclaration.id
          [.boolean success, .signed .i32 endOffset,
            .signed .i32 errorOffset])])) = some success := by
  rfl

theorem digitScanEndOffsetFunction_correct
    (success : Bool) (endOffset errorOffset : Int) :
    outcomeI32? (evalExpr 16 lexerProgram {}
      (.call digitScanEndOffsetFunction.id
        [.value (.structure digitScanDeclaration.id
          [.boolean success, .signed .i32 endOffset,
            .signed .i32 errorOffset])])) = some endOffset := by
  rfl

theorem digitScanErrorOffsetFunction_correct
    (success : Bool) (endOffset errorOffset : Int) :
    outcomeI32? (evalExpr 16 lexerProgram {}
      (.call digitScanErrorOffsetFunction.id
        [.value (.structure digitScanDeclaration.id
          [.boolean success, .signed .i32 endOffset,
            .signed .i32 errorOffset])])) = some errorOffset := by
  rfl

theorem successfulDigitsFunction_correct (endOffset : Int) :
    outcomeDigitScan? (evalExpr 16 lexerProgram {}
      (.call successfulDigitsFunction.id [i32Literal endOffset])) =
      some (true, endOffset, 0) := by
  rfl

theorem failedDigitsFunction_correct (errorOffset : Int) :
    outcomeDigitScan? (evalExpr 16 lexerProgram {}
      (.call failedDigitsFunction.id [i32Literal errorOffset])) =
      some (false, 0, errorOffset) := by
  rfl

theorem isIdentifierStartFunction_correct : ∀ byte : Byte,
    outcomeBool? (evalExpr 24 lexerProgram {}
      (.call isIdentifierStartFunction.id [i32Literal byte.val])) =
      some (isIdentifierStart byte) := by
  native_decide

theorem isDecimalDigitFunction_correct : ∀ byte : Byte,
    outcomeBool? (evalExpr 24 lexerProgram {}
      (.call isDecimalDigitFunction.id [i32Literal byte.val])) =
      some (isDecimalDigit byte) := by
  native_decide

theorem isIdentifierContinueFunction_correct : ∀ byte : Byte,
    outcomeBool? (evalExpr 32 lexerProgram {}
      (.call isIdentifierContinueFunction.id [i32Literal byte.val])) =
      some (isIdentifierContinue byte) := by
  native_decide

theorem isWhitespaceFunction_correct : ∀ byte : Byte,
    outcomeBool? (evalExpr 24 lexerProgram {}
      (.call isWhitespaceFunction.id [i32Literal byte.val])) =
      some (isWhitespace byte) := by
  native_decide

theorem isSymbolStartFunction_correct : ∀ byte : Byte,
    outcomeBool? (evalExpr 32 lexerProgram {}
      (.call isSymbolStartFunction.id [i32Literal byte.val])) =
      some (isSymbolStart byte) := by
  native_decide

/-- Executing the represented Lanius `classify_start` function returns the
abstract lexer's unique classification for every source byte. -/
theorem classifyStartFunction_correct : ∀ byte : Byte,
    outcomeI32? (evalExpr 32 lexerProgram {}
      (.call classifyStartFunction.id [i32Literal byte.val])) =
      some (Int.ofNat (classifyStartCode byte)) := by
  native_decide

theorem classifyStartFunction_deterministic
    (byte : Byte) {left right : Int}
    (leftResult : outcomeI32? (evalExpr 32 lexerProgram {}
      (.call classifyStartFunction.id [i32Literal byte.val])) = some left)
    (rightResult : outcomeI32? (evalExpr 32 lexerProgram {}
      (.call classifyStartFunction.id [i32Literal byte.val])) = some right) :
    left = right := by
  exact Option.some.inj (leftResult.symm.trans rightResult)

end Lanius.Compiler.Lexer.Program
