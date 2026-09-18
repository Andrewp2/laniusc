import Lanius.Extraction.Input.Source
import Lanius.Extraction.Input.Request
import Lanius.Extraction.CompactOutput.Source
import Lanius.Extraction.Host.External

namespace Lanius.Extraction.Input.File

open Lanius.Core Lanius.Extraction.CompactOutput

def negativeTwo : Expr := .unary .negate (number 2)

def unpackLocals : UnpackLocals := ⟨3, 1, some 5, 10, 9⟩

def updateTotal : Stmt :=
  .sequence (.expression (.assign .add (.local 5) (read 9))) .skip

def unpackAndAdvance : Stmt :=
  .letLocal 10 i32 (number 0) (.sequence unpackLocals.loop updateTotal)

def errorGuard : Expr :=
  binary .logicalOr (binary .lessEqual (read 9) negativeOne) (binary .greater (read 9) (read 6))
def eofGuard : Expr := binary .equal (read 9) (number 0)
def overflowGuard : Expr := binary .greater (read 9) (read 7)

def countGuards : Stmt :=
  .sequence (.ifThenElse errorGuard
    (returned negativeOne) .skip)
    (.sequence (.ifThenElse eofGuard (returned (read 5)) .skip)
      (.sequence (.ifThenElse overflowGuard (returned negativeTwo) .skip) unpackAndAdvance))

def readChunk (reader : FunctionId) : Stmt :=
  .letLocal 8 (.scalar (.unsigned .usize)) (.cast (.unsigned .usize) (read 6))
    (.letLocal 9 i32 (.call reader [read 0, read 4, read 8]) countGuards)

def iteration (reader : FunctionId) (words : Lanius.ConstantId) : Stmt :=
  .letLocal 6 i32 (binary .multiply (.constant words) (number 4))
    (.letLocal 7 i32 (binary .subtract (read 2) (read 5))
      (.sequence (RequestLocals.adjust ⟨7, 6⟩) (readChunk reader)))

def loop (reader : FunctionId) (words : Lanius.ConstantId) : Stmt := .whileLoop (.value (.boolean true)) (iteration reader words)

def body (reader : FunctionId) (words : Lanius.ConstantId) : Stmt :=
  .sequence (.ifThenElse (binary .lessEqual (read 2) negativeOne) (returned negativeTwo) .skip)
    (.letLocal 4 (.scalar .rawPtr) (.i32SliceDataPtr (read 3))
      (.sequence (.ifThenElse (binary .equal (read 4) (.value (.pointer 0))) (returned negativeTwo) .skip)
        (.letLocal 5 i32 (number 0) (.sequence (loop reader words) (returned (read 5))))))

def parameters : List (VarId × Ty) := [(0, i32), (1, .slice i32), (2, i32), (3, .slice i32)]

structure Checked (program : CoreSynthesis.Program.CheckedProgram artifacts) where
  reader : Host.CheckedExternal program.core .read 3
  words : Constant
  wordsFound : program.core.constant? words.id = some words
  wordsValue : words.value = .signed .i32 16384
  source : Source.CheckedInternal program ["verified", "byte_io"] "read_file" parameters i32 (body reader.function.id words.id)

def check? (program : CoreSynthesis.Program.CheckedProgram artifacts) : Option (Checked program) := do
  let reader ← program.core.functions.find? fun function => function.body.isNone && function.external == some (.host .read)
  let host ← Host.checkExternal? program.core .read 3 reader.id
  let found ← CoreSynthesis.Program.checkSourceFunction? program ["verified", "byte_io"] "read_file"
  let some (.sequence _ (.letLocal _ _ _ pointerBody)) := found.function.body | none
  let .sequence _ (.letLocal _ _ _ totalBody) := pointerBody | none
  let .sequence (.whileLoop _ (.letLocal _ _ (.binary .multiply (.constant id) _) _)) _ := totalBody | none
  match located : program.core.constant? id with
  | none => none
  | some words => do
    let value ← Equality.value? words.value (.signed .i32 16384)
    let source ← Source.checkInternal? program ["verified", "byte_io"] "read_file" parameters i32 (body host.function.id words.id)
    pure ⟨host, words, by
      have same : words.id = id := by simpa using List.find?_some located
      simpa only [same] using located, value.equal, source⟩

end Lanius.Extraction.Input.File
