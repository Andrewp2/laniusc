import Lanius.X86.Source.Encode

namespace Lanius.X86.Source.Memory

open Lanius.Core Lanius.Extraction

def parameters : List (VarId × Ty) :=
  [(0, .slice i32), (1, i32), (2, i32), (3, i32), (4, i32), (5, i32), (6, i32), (7, i32), (8, .scalar .bool)]
def hasRex : Expr := .binary .notEqual (read 9) (number 0)
def hasSib : Expr := .binary .equal (.binary .remainder (read 6) (number 8)) (number 4)
def modRM : Expr := .binary .add (.binary .add (number 128)
  (.binary .multiply (.binary .remainder (read 5) (number 8)) (number 8)))
  (.binary .remainder (read 6) (number 8))
def tail (word : FunctionId) : Stmt :=
  .sequence (.expression (.assign .set (.index (.local 0) (read 11)) (.binary .bitAnd (read 4) (number 255))))
    (.sequence (.expression (.assign .set (.index (.local 0) (.binary .add (read 11) (number 1))) modRM))
      (.sequence (.expression (.assign .add (.local 11) (number 2)))
        (.sequence (appendPrefix 11 hasSib (number 36)) (returned (.call word [read 0, read 11, read 7])))))
def write (word : FunctionId) : Stmt := .sequence (appendPrefix 11 hasRex (read 9))
  (.sequence (appendPrefix 11 hasEscape (number 15)) (tail word))
def afterSize (fits word : FunctionId) : Stmt :=
  .sequence (.ifThenElse (.unary .logicalNot (.call fits [read 1, read 2, read 10])) (returned negativeOne) .skip)
    (.letLocal 11 i32 (read 2) (write word))
def size (fits word : FunctionId) : Stmt := .letLocal 10 i32 (number 6)
  (.sequence (countPrefix 10 hasRex) (.sequence (countPrefix 10 hasEscape)
    (.sequence (countPrefix 10 hasSib) (afterSize fits word))))
def body (valid width rex fits word : FunctionId) : Stmt :=
  .sequence (.ifThenElse (registerGuard valid width) (returned negativeOne) .skip)
    (.letLocal 9 i32 (.call rex [read 3, read 5, read 6, read 8]) (size fits word))

abbrev Checked (program : CoreSynthesis.Program.CheckedProgram artifacts)
    (valid : CheckedValidation program .register) (width : CheckedValidation program .width)
    (rex : CheckedRex program) (fits : CheckedFits program) (word : CheckedWord program) :=
  Extraction.Source.CheckedInternal program ["x86", "encode"] "memory_form" parameters i32
    (body valid.source.function.id width.source.function.id rex.source.function.id fits.source.function.id word.source.function.id)

def check? (program : CoreSynthesis.Program.CheckedProgram artifacts)
    (valid : CheckedValidation program .register) (width : CheckedValidation program .width)
    (rex : CheckedRex program) (fits : CheckedFits program) (word : CheckedWord program) :
    Option (Checked program valid width rex fits word) :=
  Extraction.Source.checkInternal? program ["x86", "encode"] "memory_form" parameters i32
    (body valid.source.function.id width.source.function.id rex.source.function.id fits.source.function.id word.source.function.id)

def moveParameters : List (VarId × Ty) :=
  [(0, .slice i32), (1, i32), (2, i32), (3, i32), (4, i32), (5, i32), (6, i32)]
def moveArguments (load : Bool) : List Expr :=
  [read 0, read 1, read 2, read 3, number (if load then 139 else 137),
    read 4, read 5, read 6, .value (.boolean false)]

abbrev CheckedMove (program : CoreSynthesis.Program.CheckedProgram artifacts)
    {valid : CheckedValidation program .register} {width : CheckedValidation program .width}
    {rex : CheckedRex program} {fits : CheckedFits program} {word : CheckedWord program}
    (form : Checked program valid width rex fits word) (load : Bool) :=
  Extraction.Source.CheckedInternal program ["x86", "encode"] (if load then "load" else "store") moveParameters i32
    (returned (.call form.source.function.id (moveArguments load)))

def checkMove? (program : CoreSynthesis.Program.CheckedProgram artifacts)
    {valid : CheckedValidation program .register} {width : CheckedValidation program .width}
    {rex : CheckedRex program} {fits : CheckedFits program} {word : CheckedWord program}
    (form : Checked program valid width rex fits word) (load : Bool) : Option (CheckedMove program form load) :=
  Extraction.Source.checkInternal? program ["x86", "encode"] (if load then "load" else "store") moveParameters i32
    (returned (.call form.source.function.id (moveArguments load)))

end Lanius.X86.Source.Memory
