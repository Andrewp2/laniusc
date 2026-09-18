import Lanius.X86.Source.Encode

namespace Lanius.X86.Source

open Lanius.Core Lanius.Extraction

/-- Retain actual constant lookups, not a guessed position in the constant
pool. The source guard refers to constants rather than inline integers. -/
inductive ConstantGuard (program : Program) where
  | compare (id : ConstantId) (value : Int) (declaration : Constant)
      (found : program.constant? id = some declaration)
      (valueExact : declaration.value = .signed .i32 value)
  | both (left right : ConstantGuard program)

def ConstantGuard.expression : ConstantGuard program → Expr
  | .compare id _ _ _ _ => .binary .notEqual (read 4) (.constant id)
  | .both left right => .binary .logicalAnd left.expression right.expression

def ConstantGuard.values : ConstantGuard program → List Int
  | .compare _ value _ _ _ => [value]
  | .both left right => left.values ++ right.values

def checkConstantGuard? (program : Program) : Expr → Option (ConstantGuard program)
  | .binary .notEqual (.local 4) (.constant id) =>
      match found : program.constant? id with
      | none => none
      | some declaration =>
          match valueExact : declaration.value with
          | .signed .i32 value => some (.compare id value declaration found valueExact)
          | _ => none
  | .binary .logicalAnd left right => do
      pure (.both (← checkConstantGuard? program left) (← checkConstantGuard? program right))
  | _ => none

inductive GuardedRegister where
  | binary | shift
  deriving DecidableEq, BEq, Repr

def GuardedRegister.name : GuardedRegister → String
  | .binary => "binary" | .shift => "shift"

def GuardedRegister.allowed : GuardedRegister → List Int
  | .binary => [1, 9, 33, 41, 49, 57, 133]
  | .shift => [4, 5, 7]

def GuardedRegister.parameters : GuardedRegister → List (VarId × Ty)
  | .binary => [(0, .slice i32), (1, i32), (2, i32), (3, i32), (4, i32), (5, i32), (6, i32)]
  | .shift => [(0, .slice i32), (1, i32), (2, i32), (3, i32), (4, i32), (5, i32)]

def GuardedRegister.arguments : GuardedRegister → List Expr
  | .binary => [read 0, read 1, read 2, read 3, read 4, read 6, read 5, .value (.boolean false)]
  | .shift => [read 0, read 1, read 2, read 3, number 211, read 4, read 5, .value (.boolean false)]

def GuardedRegister.body (kind : GuardedRegister) (guard : Expr) (form : FunctionId) : Stmt :=
  .sequence (.ifThenElse guard (returned negativeOne) .skip) (returned (.call form kind.arguments))

structure CheckedGuardedRegister (program : CoreSynthesis.Program.CheckedProgram artifacts)
    {valid : CheckedValidation program .register} {width : CheckedValidation program .width}
    {rex : CheckedRex program} {fits : CheckedFits program}
    (form : CheckedRegisterForm program valid width rex fits) (kind : GuardedRegister) where
  guard : ConstantGuard program.core
  valuesExact : guard.values = kind.allowed
  internal : Extraction.Source.CheckedInternal program ["x86", "encode"] kind.name kind.parameters i32
    (kind.body guard.expression form.source.function.id)

def checkGuardedRegister? (program : CoreSynthesis.Program.CheckedProgram artifacts)
    {valid : CheckedValidation program .register} {width : CheckedValidation program .width}
    {rex : CheckedRex program} {fits : CheckedFits program}
    (form : CheckedRegisterForm program valid width rex fits) (kind : GuardedRegister) :
    Option (CheckedGuardedRegister program form kind) := do
  let source ← CoreSynthesis.Program.checkSourceFunction? program ["x86", "encode"] kind.name
  let some (.sequence (.ifThenElse expression _ _) _) := source.function.body | none
  let guard ← checkConstantGuard? program.core expression
  if valuesExact : guard.values = kind.allowed then
    let internal ← Extraction.Source.checkInternal? program ["x86", "encode"] kind.name kind.parameters i32
      (kind.body guard.expression form.source.function.id)
    pure ⟨guard, valuesExact, internal⟩
  else none

end Lanius.X86.Source
