import Lanius.Compiler.Lexer.Artifact

namespace Lanius.Compiler.Lexer.Artifact

open Lanius Lanius.Core

private def i32Type : Ty := .scalar (.signed .i32)

def scannerParameters : List (VarId × Ty) :=
  [(0, .slice i32Type), (1, i32Type), (2, i32Type)]

def scannerCondition (predicateFunctionId : FunctionId) : Expr :=
  .binary .logicalAnd
    (.binary .lessEqual (.local 3)
      (.binary .subtract (.local 1) (.value (.signed .i32 1))))
    (.call predicateFunctionId [.index (.local 0) (.local 3)])

def scannerLoopBody : Stmt :=
  .sequence
    (.expression (.assign .add (.local 3)
      (.value (.signed .i32 1)))) .skip

def scannerBody (predicateFunctionId : FunctionId) : Stmt :=
  .letLocal 3 i32Type (.binary .add (.local 2) (.value (.signed .i32 1)))
    (.sequence
      (.whileLoop (scannerCondition predicateFunctionId)
        scannerLoopBody)
      (.sequence (.returnValue (some (.local 3))) .skip))

def scannerFunction (functionId predicateFunctionId : FunctionId) : Function := {
  id := functionId
  parameters := scannerParameters
  returnType := i32Type
  body := some (scannerBody predicateFunctionId)
}

def scanIdentifierEndFunction : Function := scannerFunction 6 1

def scanWhitespaceEndFunction : Function := scannerFunction 7 3

theorem scanIdentifierEndFunction_found :
    lexerProgram.function? scanIdentifierEndFunction.id =
      some scanIdentifierEndFunction := by
  rfl

theorem scanWhitespaceEndFunction_found :
    lexerProgram.function? scanWhitespaceEndFunction.id =
      some scanWhitespaceEndFunction := by
  rfl

end Lanius.Compiler.Lexer.Artifact
