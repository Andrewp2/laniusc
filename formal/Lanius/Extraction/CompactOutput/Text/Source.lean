import Lanius.Extraction.CompactOutput.Source
import Lanius.Extraction.Input.Buffer

namespace Lanius.Extraction.CompactOutput.Text

open Lanius.Core Lanius.Extraction.Source

def parameters : List (VarId × Ty) :=
  [(0, .slice i32), (1, i32), (2, i32), (3, .scalar .string), (4, i32)]

def valueExpression : Expr := Input.packedByteExpression (read 5) (read 7)
def writeCall (byteId : FunctionId) : Expr :=
  .call byteId [read 0, read 1, read 6, read 8]
def condition : Expr := binary .notEqual (read 7) (read 4)
def step (byteId : FunctionId) : Stmt :=
  .letLocal 8 i32 valueExpression
    (.sequence (.expression (.assign .set (.local 6) (writeCall byteId)))
      (.sequence (.ifThenElse (binary .equal (read 6) negativeOne)
        (returned negativeOne) .skip)
        (.sequence (.expression (.assign .add (.local 7) (number 1))) .skip)))
def loop (byteId : FunctionId) : Stmt := .whileLoop condition (step byteId)
def body (byteId : FunctionId) : Stmt :=
  .sequence (.ifThenElse (binary .lessEqual (read 4) negativeOne)
    (returned negativeOne) .skip)
    (.letLocal 5 (.slice i32)
      (.i32SliceFromRawParts (.stringDataPtr (read 3))
        (binary .divide (binary .add (read 4) (number 3)) (number 4)))
      (.letLocal 6 i32 (read 2) (.letLocal 7 i32 (number 0)
        (.sequence (loop byteId) (returned (read 6))))))

/-- Text writes the fitting prefix even when its final result is an error. -/
def emitted (bytes : List UInt8) (position capacity : Nat) : List UInt8 :=
  bytes.take (capacity - position)

def finalPosition (length position capacity : Nat) : Int :=
  if position + length ≤ capacity then Int.ofNat (position + length) else -1

theorem emitted_of_fits (fits : position + bytes.length ≤ capacity) :
    emitted bytes position capacity = bytes := by
  exact List.take_of_length_le (by omega)

theorem finalPosition_of_fits (fits : position + length ≤ capacity) :
    finalPosition length position capacity = Int.ofNat (position + length) := if_pos fits

theorem finalPosition_of_full (full : capacity < position + length) :
    finalPosition length position capacity = -1 := if_neg (by omega)

abbrev Checked (program : CoreSynthesis.Program.CheckedProgram artifacts)
    (byte : CheckedByte program) :=
  CheckedInternal program ["verified", "output"] "text" parameters i32
    (body byte.source.function.id)

def check? (program : CoreSynthesis.Program.CheckedProgram artifacts)
    (byte : CheckedByte program) : Option (Checked program byte) :=
  checkInternal? program ["verified", "output"] "text" parameters i32
    (body byte.source.function.id)

end Lanius.Extraction.CompactOutput.Text
