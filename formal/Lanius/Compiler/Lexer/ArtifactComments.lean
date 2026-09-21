import Lanius.Compiler.Lexer.ArtifactScanners

namespace Lanius.Compiler.Lexer.Artifact

open Lanius Lanius.Core

private def i32Type : Ty := .scalar (.signed .i32)

private def commentParameters : List (VarId × Ty) :=
  [(0, .slice i32Type), (1, i32Type), (2, i32Type)]

private def literal (value : Int) : Expr := .value (.signed .i32 value)

private def add (left right : Expr) : Expr := .binary .add left right

private def indexAt (source offset : Expr) : Expr := .index source offset

private def commentFunction (id : FunctionId) (returnType : Ty)
    (condition : Expr) (loopBody : Stmt) (result : Expr) : Function := {
  id := id
  parameters := commentParameters
  returnType := returnType
  body := some (.letLocal 3 i32Type (add (.local 2) (literal 2))
    (.sequence (.whileLoop condition loopBody)
      (.sequence (.returnValue (some result)) .skip)))
}

private def lineCondition : Expr :=
  .binary .logicalAnd
    (.binary .lessEqual (.local 3)
      (.binary .subtract (.local 1) (literal 1)))
    (.binary .notEqual (indexAt (.local 0) (.local 3)) (literal 10))

def scanLineCommentEndFunction : Function :=
  commentFunction 16 i32Type lineCondition scannerLoopBody (.local 3)

def blockCondition : Expr :=
  .binary .logicalAnd
    (.binary .logicalAnd
      (.binary .equal (indexAt (.local 0) (.local 3)) (literal 42))
      (.binary .lessEqual (add (.local 3) (literal 1))
        (.binary .subtract (.local 1) (literal 1))))
    (.binary .equal
      (indexAt (.local 0) (add (.local 3) (literal 1))) (literal 47))

def blockReturn : Stmt :=
  .sequence
    (.returnValue (some (.call 11 [add (.local 3) (literal 2)]))) .skip

def blockLoopBody : Stmt :=
  .sequence (.ifThenElse blockCondition blockReturn .skip) scannerLoopBody

def scanBlockCommentEndFunction : Function :=
  commentFunction 17 (.structure 0)
    (.binary .lessEqual (.local 3)
      (.binary .subtract (.local 1) (literal 1))) blockLoopBody
    (.call 12 [.local 1])

theorem scanLineCommentEndFunction_found :
    lexerProgram.function? scanLineCommentEndFunction.id =
      some scanLineCommentEndFunction := by
  rfl

theorem scanBlockCommentEndFunction_found :
    lexerProgram.function? scanBlockCommentEndFunction.id =
      some scanBlockCommentEndFunction := by
  rfl

end Lanius.Compiler.Lexer.Artifact
