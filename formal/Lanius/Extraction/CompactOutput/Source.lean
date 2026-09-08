import Lanius.Extraction.Source.Internal

namespace Lanius.Extraction.CompactOutput

open Lanius.Core Lanius.Extraction.Source

abbrev i32 : Ty := .scalar (.signed .i32)
abbrev number (n : Nat) : Expr := .value (.signed .i32 n)
abbrev read (id : VarId) : Expr := .local id
abbrev binary (op : BinaryOp) (a b : Expr) : Expr := .binary op a b
def negativeOne : Expr := .unary .negate (number 1)
def returned (value : Expr) : Stmt := .sequence (.returnValue (some value)) .skip

def byteGuard : Expr :=
  binary .logicalOr (binary .logicalOr (binary .logicalOr
    (binary .lessEqual (read 2) negativeOne) (binary .greaterEqual (read 2) (read 1)))
    (binary .lessEqual (read 3) negativeOne)) (binary .greaterEqual (read 3) (number 256))

def byteBody : Stmt :=
  .sequence (.ifThenElse byteGuard (returned negativeOne) .skip)
    (.sequence (.expression (.assign .set (.index (.local 0) (read 2)) (read 3)))
      (returned (binary .add (read 2) (number 1))))

def byteParameters : List (VarId × Ty) := [(0, .slice i32), (1, i32), (2, i32), (3, i32)]
abbrev CheckedByte (program : CoreSynthesis.Program.CheckedProgram artifacts) :=
  CheckedInternal program ["verified", "output"] "byte" byteParameters i32 byteBody
def checkByte? (program : CoreSynthesis.Program.CheckedProgram artifacts) : Option (CheckedByte program) :=
  checkInternal? program ["verified", "output"] "byte" byteParameters i32 byteBody

def digitBody : Stmt :=
  .sequence (.ifThenElse (binary .less (read 0) (number 10))
    (returned (binary .add (number 48) (read 0))) .skip)
    (returned (binary .add (number 87) (read 0)))

abbrev CheckedDigit (program : CoreSynthesis.Program.CheckedProgram artifacts) :=
  CheckedInternal program ["verified", "compact_artifact_output"] "hex_digit" [(0, i32)] i32 digitBody
def checkDigit? (program : CoreSynthesis.Program.CheckedProgram artifacts) : Option (CheckedDigit program) :=
  checkInternal? program ["verified", "compact_artifact_output"] "hex_digit" [(0, i32)] i32 digitBody

def digitArgument (value shift : Expr) : Expr :=
  binary .bitAnd (binary .shiftRight value shift) (number 15)

def digitCall (byteId digitId : FunctionId) (output capacity position value : Expr) : Expr :=
  .call byteId [output, capacity, position, .call digitId [value]]

def hexByteBody (byteId digitId : FunctionId) : Stmt :=
  .sequence (.ifThenElse (binary .logicalOr (binary .lessEqual (read 3) negativeOne)
    (binary .greaterEqual (read 3) (number 256))) (returned negativeOne) .skip)
    (.letLocal 4 i32 (digitCall byteId digitId (read 0) (read 1) (read 2)
      (digitArgument (read 3) (number 4)))
      (returned (digitCall byteId digitId (read 0) (read 1) (read 4)
        (binary .bitAnd (read 3) (number 15)))))

abbrev CheckedHexByte (program : CoreSynthesis.Program.CheckedProgram artifacts)
    (byte : CheckedByte program) (digit : CheckedDigit program) :=
  CheckedInternal program ["verified", "compact_artifact_output"] "hex_byte" byteParameters i32
    (hexByteBody byte.source.function.id digit.source.function.id)

def checkHexByte? (program : CoreSynthesis.Program.CheckedProgram artifacts)
    (byte : CheckedByte program) (digit : CheckedDigit program) : Option (CheckedHexByte program byte digit) :=
  checkInternal? program ["verified", "compact_artifact_output"] "hex_byte" byteParameters i32
    (hexByteBody byte.source.function.id digit.source.function.id)

end Lanius.Extraction.CompactOutput
