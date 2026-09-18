import Lanius.X86.Source.Encode

namespace Lanius.X86.Source

open Lanius.Core Lanius.Extraction

/-- Public register instructions whose complete body is one returned helper
call. Guarded operations and division's local selection are separate bodies. -/
inductive RegisterWrapper where
  | move | multiply | signExtend | zeroExtend | negate
  deriving DecidableEq, BEq, Repr

def RegisterWrapper.name : RegisterWrapper → String
  | .move => "move_register"
  | .multiply => "multiply"
  | .signExtend => "sign_extend_i32"
  | .zeroExtend => "zero_extend_byte"
  | .negate => "negate"

def RegisterWrapper.parameters : RegisterWrapper → List (VarId × Ty)
  | .move | .multiply => [(0, .slice i32), (1, i32), (2, i32), (3, i32), (4, i32), (5, i32)]
  | .signExtend | .zeroExtend | .negate => [(0, .slice i32), (1, i32), (2, i32), (3, i32), (4, i32)]

def RegisterWrapper.arguments : RegisterWrapper → List Expr
  | .move => [read 0, read 1, read 2, read 3, number 137, read 5, read 4, .value (.boolean false)]
  | .multiply => [read 0, read 1, read 2, read 3, number 4015, read 4, read 5, .value (.boolean false)]
  | .signExtend => [read 0, read 1, read 2, number 64, number 99, read 3, read 4, .value (.boolean false)]
  | .zeroExtend => [read 0, read 1, read 2, number 32, number 4022, read 3, read 4,
      .binary .greaterEqual (read 4) (number 4)]
  | .negate => [read 0, read 1, read 2, read 3, number 247, number 3, read 4, .value (.boolean false)]

def RegisterWrapper.body (kind : RegisterWrapper) (form : FunctionId) : Stmt :=
  returned (.call form kind.arguments)

abbrev CheckedRegisterWrapper (program : CoreSynthesis.Program.CheckedProgram artifacts)
    {valid : CheckedValidation program .register} {width : CheckedValidation program .width}
    {rex : CheckedRex program} {fits : CheckedFits program}
    (form : CheckedRegisterForm program valid width rex fits) (kind : RegisterWrapper) :=
  Extraction.Source.CheckedInternal program ["x86", "encode"] kind.name kind.parameters i32
    (kind.body form.source.function.id)

def checkRegisterWrapper? (program : CoreSynthesis.Program.CheckedProgram artifacts)
    {valid : CheckedValidation program .register} {width : CheckedValidation program .width}
    {rex : CheckedRex program} {fits : CheckedFits program}
    (form : CheckedRegisterForm program valid width rex fits) (kind : RegisterWrapper) :
    Option (CheckedRegisterWrapper program form kind) :=
  Extraction.Source.checkInternal? program ["x86", "encode"] kind.name kind.parameters i32
    (kind.body form.source.function.id)

end Lanius.X86.Source
