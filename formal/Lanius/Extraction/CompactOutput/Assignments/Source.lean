import Lanius.Extraction.CompactOutput.Assignments.Write

namespace Lanius.Extraction.CompactOutput.Assignments

open Lanius.Core Lanius.Extraction.Source

def parameters : List (VarId × Ty) :=
  [(0, .slice i32), (1, i32), (2, i32), (3, .slice i32), (4, i32), (5, i32)]
def firstIndex : Expr := binary .multiply (read 7) (number 2)
def secondIndex : Expr := binary .add firstIndex (number 1)
def condition : Expr := binary .notEqual (read 7) (read 2)
def failureGuard : Expr := binary .lessEqual (read 6) negativeOne
def increment : Expr := .assign .add (.local 7) (number 1)
def step (wordId : FunctionId) : Stmt :=
  .letLocal 8 i32 (.index (read 0) firstIndex)
    (.letLocal 9 i32 (.index (read 0) secondIndex)
      (.sequence (.ifThenElse fieldGuard (returned negativeOne) .skip)
        (.sequence (.expression (firstWrite wordId))
          (.sequence (.expression (secondWrite wordId))
            (.sequence (.ifThenElse failureGuard (returned negativeOne) .skip)
              (.sequence (.expression increment) .skip))))))
def loop (wordId : FunctionId) : Stmt := .whileLoop condition (step wordId)
def entryGuard : Expr := binary .logicalOr (binary .lessEqual (read 2) negativeOne)
  (.unary .logicalNot (binary .lessEqual (read 2) (binary .divide (read 1) (number 2))))
def body (wordId : FunctionId) : Stmt :=
  .sequence (.ifThenElse entryGuard (returned negativeOne) .skip)
    (.letLocal 6 i32 (read 5) (.letLocal 7 i32 (number 0)
      (.sequence (loop wordId) (returned (read 6)))))

abbrev Checked (program : CoreSynthesis.Program.CheckedProgram artifacts)
    (byte : CheckedByte program) (digit : CheckedDigit program)
    (word : Word.Checked program byte digit) :=
  CheckedInternal program ["verified", "compact_artifact_output"] "semantic" parameters i32
    (body word.source.function.id)

def check? (program : CoreSynthesis.Program.CheckedProgram artifacts)
    (byte : CheckedByte program) (digit : CheckedDigit program)
    (word : Word.Checked program byte digit) : Option (Checked program byte digit word) :=
  checkInternal? program ["verified", "compact_artifact_output"] "semantic" parameters i32
    (body word.source.function.id)

end Lanius.Extraction.CompactOutput.Assignments
