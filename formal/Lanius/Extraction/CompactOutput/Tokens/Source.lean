import Lanius.Extraction.CompactOutput.Tokens.Fields

namespace Lanius.Extraction.CompactOutput.Tokens

open Lanius.Core Lanius.Extraction.Source

def parameters : List (VarId × Ty) :=
  [(0, .slice i32), (1, i32), (2, i32), (3, i32), (4, .slice i32), (5, i32), (6, i32)]
def condition : Expr := binary .notEqual (read 8) (read 2)
def failureGuard : Expr := binary .lessEqual (read 7) negativeOne
def increment : Expr := .assign .add (.local 8) (number 1)
def kindWrite (wordId : FunctionId) : Expr := Word.assignCall wordId 7 (read 4) (read 5) kindRead
def startWrite (wordId : FunctionId) : Expr := Word.assignCall wordId 7 (read 4) (read 5) (read 10)
def finishWrite (wordId : FunctionId) : Expr := Word.assignCall wordId 7 (read 4) (read 5) (read 11)
def step (wordId : FunctionId) : Stmt :=
  .letLocal 9 i32 rowIndex
    (.letLocal 10 i32 startRead
      (.letLocal 11 i32 finishRead
        (.sequence (.ifThenElse fieldGuard (returned negativeOne) .skip)
          (.sequence (.expression (kindWrite wordId))
            (.sequence (.expression (startWrite wordId))
              (.sequence (.expression (finishWrite wordId))
                (.sequence (.ifThenElse failureGuard (returned negativeOne) .skip)
                  (.sequence (.expression increment) .skip))))))))
def loop (wordId : FunctionId) : Stmt := .whileLoop condition (step wordId)
def entryGuard : Expr := binary .logicalOr (binary .lessEqual (read 2) negativeOne)
  (.unary .logicalNot (binary .lessEqual (read 2) (binary .divide (read 1) (number 3))))
def body (wordId : FunctionId) : Stmt :=
  .sequence (.ifThenElse entryGuard (returned negativeOne) .skip)
    (.letLocal 7 i32 (read 6) (.letLocal 8 i32 (number 0)
      (.sequence (loop wordId) (returned (read 7)))))

abbrev Checked (program : CoreSynthesis.Program.CheckedProgram artifacts)
    (byte : CheckedByte program) (digit : CheckedDigit program)
    (word : Word.Checked program byte digit) :=
  CheckedInternal program ["verified", "compact_artifact_output"] "tokens" parameters i32
    (body word.source.function.id)

def check? (program : CoreSynthesis.Program.CheckedProgram artifacts)
    (byte : CheckedByte program) (digit : CheckedDigit program)
    (word : Word.Checked program byte digit) : Option (Checked program byte digit word) :=
  checkInternal? program ["verified", "compact_artifact_output"] "tokens" parameters i32
    (body word.source.function.id)

end Lanius.Extraction.CompactOutput.Tokens
