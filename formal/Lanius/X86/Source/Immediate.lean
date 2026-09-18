import Lanius.X86.Source.Encode

namespace Lanius.X86.Source.Immediate

open Lanius.Core Lanius.Extraction

def parameters : List (VarId × Ty) :=
  [(0, .slice i32), (1, i32), (2, i32), (3, i32), (4, i32), (5, i32), (6, i32)]
def guard (valid width : FunctionId) : Expr :=
  .binary .logicalOr (.unary .logicalNot (.call valid [read 4]))
    (.unary .logicalNot (.call width [read 3]))
def wide : Expr := .binary .equal (read 3) (number 64)
def hasRex : Expr := .binary .notEqual (read 7) (number 0)
def opcode : Expr := .binary .add (number 184) (.binary .remainder (read 4) (number 8))
def wideSize : Stmt := .ifThenElse wide
  (.sequence (.expression (.assign .add (.local 8) (number 4))) .skip) .skip
def highWord (word : FunctionId) : Stmt := .ifThenElse wide
  (.sequence (.expression (.assign .set (.local 9) (.call word [read 0, read 9, read 6]))) .skip) .skip
def tail (word : FunctionId) : Stmt :=
  .sequence (.expression (.assign .set (.index (.local 0) (read 9)) opcode))
    (.sequence (.expression (.assign .set (.local 9)
      (.call word [read 0, .binary .add (read 9) (number 1), read 5])))
      (.sequence (highWord word) (returned (read 9))))
def write (word : FunctionId) : Stmt :=
  .sequence (appendPrefix 9 hasRex (read 7)) (tail word)
def afterSize (fits word : FunctionId) : Stmt :=
  .sequence (.ifThenElse (.unary .logicalNot (.call fits [read 1, read 2, read 8]))
    (returned negativeOne) .skip) (.letLocal 9 i32 (read 2) (write word))
def size (fits word : FunctionId) : Stmt :=
  .letLocal 8 i32 (number 5) (.sequence wideSize
    (.sequence (countPrefix 8 hasRex) (afterSize fits word)))
def body (valid width rex fits word : FunctionId) : Stmt :=
  .sequence (.ifThenElse (guard valid width) (returned negativeOne) .skip)
    (.letLocal 7 i32 (.call rex [read 3, number 0, read 4, .value (.boolean false)]) (size fits word))

abbrev Checked (program : CoreSynthesis.Program.CheckedProgram artifacts)
    (valid : CheckedValidation program .register) (width : CheckedValidation program .width)
    (rex : CheckedRex program) (fits : CheckedFits program) (word : CheckedWord program) :=
  Extraction.Source.CheckedInternal program ["x86", "encode"] "immediate" parameters i32
    (body valid.source.function.id width.source.function.id rex.source.function.id fits.source.function.id word.source.function.id)

def check? (program : CoreSynthesis.Program.CheckedProgram artifacts)
    (valid : CheckedValidation program .register) (width : CheckedValidation program .width)
    (rex : CheckedRex program) (fits : CheckedFits program) (word : CheckedWord program) :
    Option (Checked program valid width rex fits word) :=
  Extraction.Source.checkInternal? program ["x86", "encode"] "immediate" parameters i32
    (body valid.source.function.id width.source.function.id rex.source.function.id fits.source.function.id word.source.function.id)

end Lanius.X86.Source.Immediate
