import Lanius.Extraction.CompactOutput.Byte
import Lanius.Extraction.Host.Stderr

namespace Lanius.Extraction.Diagnostics.Natural

open Lanius.Core Lanius.Extraction.CompactOutput

def growCondition : Expr := binary .greaterEqual (binary .divide (read 0) (read 1)) (number 10)
def growStep : Stmt := .sequence (.expression (.assign .multiply (.local 1) (number 10))) .skip
def growLoop : Stmt := .whileLoop growCondition growStep
def digit : Expr := binary .add (number 48) (binary .remainder (binary .divide (read 0) (read 1)) (number 10))
def writeGuard (writer : FunctionId) (value : Expr) : Expr :=
  binary .notEqual (.call writer [number 2, value]) (number 1)
def digitStep (writer : FunctionId) : Stmt :=
  .sequence (.ifThenElse (writeGuard writer digit) (returned negativeOne) .skip)
    (.sequence (.expression (.assign .add (.local 2) (number 1)))
      (.sequence (.expression (.assign .divide (.local 1) (number 10))) .skip))
def digitLoop (writer : FunctionId) : Stmt :=
  .whileLoop (binary .notEqual (read 1) (number 0)) (digitStep writer)
def finish (writer : FunctionId) : Stmt :=
  .sequence (.ifThenElse (writeGuard writer (number 10)) (returned negativeOne) .skip)
    (returned (binary .add (read 2) (number 1)))
def body (writer : FunctionId) : Stmt :=
  .sequence (.ifThenElse (binary .lessEqual (read 0) negativeOne) (returned negativeOne) .skip)
    (.letLocal 1 i32 (number 1) (.sequence growLoop
      (.letLocal 2 i32 (number 0) (.sequence (digitLoop writer) (finish writer)))))

structure Checked (program : CoreSynthesis.Program.CheckedProgram artifacts) where
  writer : Host.CheckedExternal program.core .writeByte 2
  source : Source.CheckedInternal program ["verified", "byte_io"] "write_stderr_natural" [(0, i32)] i32
    (body writer.function.id)

def check? (program : CoreSynthesis.Program.CheckedProgram artifacts) : Option (Checked program) := do
  let writer ← program.core.functions.find? fun function => function.body.isNone && function.external == some (.host .writeByte)
  let host ← Host.checkExternal? program.core .writeByte 2 writer.id
  let source ← Source.checkInternal? program ["verified", "byte_io"] "write_stderr_natural" [(0, i32)] i32
    (body host.function.id)
  pure ⟨host, source⟩

end Lanius.Extraction.Diagnostics.Natural
