import Lanius.Extraction.CompactOutput.Source

namespace Lanius.Extraction.CompactOutput.Word

open Lanius.Core Lanius.Extraction.Source

def assignment (byteId digitId : FunctionId) : Expr :=
  .assign .set (.local 4) (digitCall byteId digitId (read 0) (read 1) (read 4)
    (digitArgument (read 3) (read 5)))

def failureGuard : Expr := binary .lessEqual (read 4) negativeOne
def condition : Expr := binary .greaterEqual (read 5) (number 0)
def decrement : Expr := .assign .subtract (.local 5) (number 4)
def step (byteId digitId : FunctionId) : Stmt :=
  .sequence (.expression (assignment byteId digitId))
    (.sequence (.ifThenElse failureGuard (returned negativeOne) .skip)
      (.sequence (.expression decrement) .skip))
def loop (byteId digitId : FunctionId) : Stmt := .whileLoop condition (step byteId digitId)
def body (byteId digitId : FunctionId) : Stmt :=
  .sequence (.ifThenElse (binary .lessEqual (read 3) negativeOne) (returned negativeOne) .skip)
    (.letLocal 4 i32 (read 2) (.letLocal 5 i32 (number 28)
      (.sequence (loop byteId digitId) (returned (read 4)))))

abbrev Checked (program : CoreSynthesis.Program.CheckedProgram artifacts)
    (byte : CheckedByte program) (digit : CheckedDigit program) :=
  CheckedInternal program ["verified", "compact_artifact_output"] "hex_u32" byteParameters i32
    (body byte.source.function.id digit.source.function.id)

def check? (program : CoreSynthesis.Program.CheckedProgram artifacts)
    (byte : CheckedByte program) (digit : CheckedDigit program) : Option (Checked program byte digit) :=
  checkInternal? program ["verified", "compact_artifact_output"] "hex_u32" byteParameters i32
    (body byte.source.function.id digit.source.function.id)

end Lanius.Extraction.CompactOutput.Word
