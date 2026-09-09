import Lanius.Extraction.CompactOutput.Source

namespace Lanius.Extraction.CompactOutput.Bytes

open Lanius.Core Lanius.Extraction.Source

def parameters : List (VarId × Ty) :=
  [(0, .slice i32), (1, i32), (2, .slice i32), (3, i32), (4, i32)]

def writeCall (hexByteId : FunctionId) : Expr :=
  .call hexByteId [read 2, read 3, read 5, .index (read 0) (read 6)]

def assignment (hexByteId : FunctionId) : Expr :=
  .assign .set (.local 5) (writeCall hexByteId)

def condition : Expr := binary .notEqual (read 6) (read 1)
def failureGuard : Expr := binary .lessEqual (read 5) negativeOne
def increment : Expr := .assign .add (.local 6) (number 1)
def step (hexByteId : FunctionId) : Stmt :=
  .sequence (.expression (assignment hexByteId))
    (.sequence (.ifThenElse failureGuard (returned negativeOne) .skip)
      (.sequence (.expression increment) .skip))
def loop (hexByteId : FunctionId) : Stmt := .whileLoop condition (step hexByteId)
def body (hexByteId : FunctionId) : Stmt :=
  .sequence (.ifThenElse (binary .lessEqual (read 1) negativeOne) (returned negativeOne) .skip)
    (.letLocal 5 i32 (read 4) (.letLocal 6 i32 (number 0)
      (.sequence (loop hexByteId) (returned (read 5)))))

abbrev Checked (program : CoreSynthesis.Program.CheckedProgram artifacts)
    (byte : CheckedByte program) (digit : CheckedDigit program)
    (hex : CheckedHexByte program byte digit) :=
  CheckedInternal program ["verified", "compact_artifact_output"] "bytes" parameters i32
    (body hex.source.function.id)

def check? (program : CoreSynthesis.Program.CheckedProgram artifacts)
    (byte : CheckedByte program) (digit : CheckedDigit program)
    (hex : CheckedHexByte program byte digit) : Option (Checked program byte digit hex) :=
  checkInternal? program ["verified", "compact_artifact_output"] "bytes" parameters i32
    (body hex.source.function.id)

end Lanius.Extraction.CompactOutput.Bytes
