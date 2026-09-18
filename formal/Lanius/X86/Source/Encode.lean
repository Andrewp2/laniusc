import Lanius.X86.Source.Register
import Lanius.X86.Source.Patch

namespace Lanius.X86.Source

open Lanius.Core Lanius.Extraction

def registerGuard (valid width : FunctionId) : Expr :=
  .binary .logicalOr
    (.binary .logicalOr (.unary .logicalNot (.call valid [read 5]))
      (.unary .logicalNot (.call valid [read 6])))
    (.unary .logicalNot (.call width [read 3]))

def hasRex : Expr := .binary .notEqual (read 8) (number 0)
def hasEscape : Expr := .binary .greater (read 4) (number 255)
def increment (id : VarId) : Expr := .assign .add (.local id) (number 1)

def countPrefix (id : VarId) (guard : Expr) : Stmt :=
  .ifThenElse guard (.sequence (.expression (increment id)) .skip) .skip

def appendPrefix (id : VarId) (guard byte : Expr) : Stmt :=
  .ifThenElse guard (.sequence (.expression (.assign .set (.index (.local 0) (read id)) byte))
    (.sequence (.expression (increment id)) .skip)) .skip

def registerModRM : Expr :=
  .binary .add (.binary .add (number 192)
    (.binary .multiply (.binary .remainder (read 5) (number 8)) (number 8)))
    (.binary .remainder (read 6) (number 8))

def registerTail : Stmt :=
  .sequence (.expression (.assign .set (.index (.local 0) (read 10))
    (.binary .bitAnd (read 4) (number 255))))
    (.sequence (.expression (.assign .set (.index (.local 0) (.binary .add (read 10) (number 1))) registerModRM))
      (returned (.binary .add (read 10) (number 2))))

def registerWrite : Stmt :=
  .sequence (appendPrefix 10 hasRex (read 8))
    (.sequence (appendPrefix 10 hasEscape (number 15)) registerTail)

def registerAfterSize (fits : FunctionId) : Stmt :=
  .sequence (.ifThenElse (.unary .logicalNot (.call fits [read 1, read 2, read 9]))
    (returned negativeOne) .skip) (.letLocal 10 i32 (read 2) registerWrite)

def registerSize (fits : FunctionId) : Stmt :=
  .letLocal 9 i32 (number 2) (.sequence (countPrefix 9 hasRex)
    (.sequence (countPrefix 9 hasEscape) (registerAfterSize fits)))

def registerBody (valid width rex fits : FunctionId) : Stmt :=
  .sequence (.ifThenElse (registerGuard valid width) (returned negativeOne) .skip)
    (.letLocal 8 i32 (.call rex [read 3, read 5, read 6, read 7]) (registerSize fits))

abbrev CheckedRegisterForm (program : CoreSynthesis.Program.CheckedProgram artifacts)
    (valid : CheckedValidation program .register) (width : CheckedValidation program .width)
    (rex : CheckedRex program) (fits : CheckedFits program) :=
  Extraction.Source.CheckedInternal program ["x86", "encode"] "register_form"
    [(0, .slice i32), (1, i32), (2, i32), (3, i32), (4, i32), (5, i32), (6, i32), (7, .scalar .bool)] i32
    (registerBody valid.source.function.id width.source.function.id rex.source.function.id fits.source.function.id)

def checkRegisterForm? (program : CoreSynthesis.Program.CheckedProgram artifacts)
    (valid : CheckedValidation program .register) (width : CheckedValidation program .width)
    (rex : CheckedRex program) (fits : CheckedFits program) : Option (CheckedRegisterForm program valid width rex fits) :=
  Extraction.Source.checkInternal? program ["x86", "encode"] "register_form"
    [(0, .slice i32), (1, i32), (2, i32), (3, i32), (4, i32), (5, i32), (6, i32), (7, .scalar .bool)] i32
    (registerBody valid.source.function.id width.source.function.id rex.source.function.id fits.source.function.id)

end Lanius.X86.Source
