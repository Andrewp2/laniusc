import Lanius.Compiler.Lexer.Artifact

namespace Lanius.Compiler.Lexer.Artifact

open Lanius Lanius.Core

private def i32Type : Ty := .scalar (.signed .i32)

private def boolType : Ty := .scalar .bool

private def sourceType : Ty := .slice i32Type

private def scanEndType : Ty := .structure 0

private def i32Value (value : Int) : Expr :=
  .value (.signed .i32 value)

private def boolValue (value : Bool) : Expr :=
  .value (.boolean value)

private def sequence : List Stmt → Stmt
  | [] => .skip
  | statement :: statements => .sequence statement (sequence statements)

private def expressionStatement (expression : Expr) : Stmt :=
  .expression expression

private def assignStatement (operation : AssignOp) (id : VarId) (value : Expr) : Stmt :=
  expressionStatement (.assign operation (.local id) value)

private def returnStatement (value : Expr) : Stmt :=
  .returnValue (some value)

private def scanCall (function : FunctionId) (argument : Expr) : Expr :=
  .call function [argument]

private def failedScan (argument : Expr) : Expr := scanCall 12 argument

private def successfulScan (argument : Expr) : Expr := scanCall 11 argument

def quotedLoopEscaped : Stmt := sequence [
  assignStatement .set 5 (boolValue false), assignStatement .add 4 (i32Value 1)]

def quotedLoopNewlineReturn : Stmt := sequence [returnStatement (failedScan (.local 4))]

def quotedLoopDelimiterReturn : Stmt := sequence [returnStatement
  (successfulScan (.binary .add (.local 4) (i32Value 1)))]

def quotedLoopBeginEscape : Stmt := sequence [assignStatement .set 5 (boolValue true)]

def quotedLoopAdvance : Stmt := assignStatement .add 4 (i32Value 1)

def quotedLoopPlain : Stmt := sequence [
  .ifThenElse (.binary .equal (.local 6) (i32Value 10)) quotedLoopNewlineReturn .skip,
  .ifThenElse (.binary .equal (.local 6) (.local 3)) quotedLoopDelimiterReturn .skip,
  .ifThenElse (.binary .equal (.local 6) (i32Value 92)) quotedLoopBeginEscape .skip,
  quotedLoopAdvance]

def quotedLoopInner : Stmt := sequence [
  .ifThenElse (.local 5) quotedLoopEscaped quotedLoopPlain]

def scanQuotedLoopBody : Stmt :=
  .letLocal 6 i32Type (.index (.local 0) (.local 4)) quotedLoopInner

private def scanQuotedBody : Stmt :=
  .letLocal 4 i32Type
    (.binary .add (.local 2) (i32Value 1))
    (.letLocal 5 boolType (boolValue false)
      (sequence [
        .whileLoop
          (.binary .lessEqual (.local 4)
            (.binary .subtract (.local 1) (i32Value 1)))
          scanQuotedLoopBody,
        returnStatement (failedScan (.local 1))]))

private def quotedParameters : List (VarId × Ty) :=
  [(0, sourceType), (1, i32Type), (2, i32Type), (3, i32Type)]

private def simpleQuotedParameters : List (VarId × Ty) :=
  [(0, sourceType), (1, i32Type), (2, i32Type)]

def scanQuotedEndFunction : Function := {
  id := 13
  parameters := quotedParameters
  returnType := scanEndType
  body := some scanQuotedBody
}

private def scanQuotedCall (delimiter : Int) : Expr :=
  .call 13 [
    .local 0,
    .local 1,
    .local 2,
    i32Value delimiter]

private def simpleQuotedFunction (id : FunctionId) (delimiter : Int) : Function := {
  id
  parameters := simpleQuotedParameters
  returnType := scanEndType
  body := some (sequence [returnStatement (scanQuotedCall delimiter)])
}

def scanStringEndFunction : Function := simpleQuotedFunction 14 34

def scanCharacterEndFunction : Function := simpleQuotedFunction 15 39

theorem scanQuotedEndFunction_found :
    lexerProgram.function? scanQuotedEndFunction.id = some scanQuotedEndFunction := by
  rfl

theorem scanStringEndFunction_found :
    lexerProgram.function? scanStringEndFunction.id = some scanStringEndFunction := by
  rfl

theorem scanCharacterEndFunction_found :
    lexerProgram.function? scanCharacterEndFunction.id = some scanCharacterEndFunction := by
  rfl

end Lanius.Compiler.Lexer.Artifact
