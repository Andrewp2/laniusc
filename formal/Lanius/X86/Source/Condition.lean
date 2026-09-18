import Lanius.X86.Source.Encode

namespace Lanius.X86.Source.Condition

open Lanius.Core Lanius.Extraction

def parameters : List (VarId × Ty) :=
  [(0, .slice i32), (1, i32), (2, i32), (3, i32), (4, i32)]

def guard : Expr := .binary .logicalOr
  (.binary .less (read 3) (number 0)) (.binary .greater (read 3) (number 15))

def arguments : List Expr :=
  [read 0, read 1, read 2, number 32, .binary .add (number 3984) (read 3), number 0,
    read 4, .binary .greaterEqual (read 4) (number 4)]

def body (form : FunctionId) : Stmt :=
  .sequence (.ifThenElse guard (returned negativeOne) .skip) (returned (.call form arguments))

abbrev Checked (program : CoreSynthesis.Program.CheckedProgram artifacts)
    {valid : CheckedValidation program .register} {width : CheckedValidation program .width}
    {rex : CheckedRex program} {fits : CheckedFits program}
    (form : CheckedRegisterForm program valid width rex fits) :=
  Extraction.Source.CheckedInternal program ["x86", "control"] "set_condition" parameters i32
    (body form.source.function.id)

def check? (program : CoreSynthesis.Program.CheckedProgram artifacts)
    {valid : CheckedValidation program .register} {width : CheckedValidation program .width}
    {rex : CheckedRex program} {fits : CheckedFits program}
    (form : CheckedRegisterForm program valid width rex fits) : Option (Checked program form) :=
  Extraction.Source.checkInternal? program ["x86", "control"] "set_condition" parameters i32
    (body form.source.function.id)

end Lanius.X86.Source.Condition
