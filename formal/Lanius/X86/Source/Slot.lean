import Lanius.X86.Source.Constant
import Lanius.X86.Source.Memory
import Lanius.X86.Frame.Source

namespace Lanius.X86.Source.Slot

open Lanius.Core Lanius.Extraction

inductive Kind where
  | load32 | load64 | save64
  deriving DecidableEq
def Kind.modulePath : Kind → Names.ModulePath
  | .load32 => ["backend", "frame"]
  | .load64 | .save64 => ["backend", "value"]
def Kind.name : Kind → Surface.Name
  | .load32 => "load" | .load64 => "load_word" | .save64 => "save_word"
def Kind.width : Kind → Register.Width
  | .load32 => .w32 | .load64 | .save64 => .w64
def Kind.load : Kind → Bool
  | .load32 | .load64 => true | .save64 => false
def parameters : List (VarId × Ty) := [(0, .slice i32), (1, i32), (2, .slice i32), (3, i32), (4, i32)]
def cursor (code : ConstantId) : Expr := .index (read 2) (.constant code)
def arguments (kind : Kind) (offset : FunctionId) (code base : ConstantId) : List Expr :=
  [read 0, read 1, cursor code, number kind.width.bits, read 4, .constant base, .call offset [read 3]]
def body (kind : Kind) (emit offset : FunctionId) (code base : ConstantId) : Stmt :=
  .sequence (.expression (.assign .set (.index (.local 2) (.constant code))
    (.call emit (arguments kind offset code base)))) (returned (cursor code))

structure Checked (program : CoreSynthesis.Program.CheckedProgram artifacts) (kind : Kind)
    {valid : CheckedValidation program .register} {width : CheckedValidation program .width}
    {rex : CheckedRex program} {fits : CheckedFits program} {word : CheckedWord program}
    {form : Memory.Checked program valid width rex fits word}
    (emit : Memory.CheckedMove program form kind.load) (offset : Frame.CheckedDisplacement program) where
  code : IntegerConstant program.core
  codeValue : code.value = 1
  base : IntegerConstant program.core
  baseValue : base.value = 5
  internal : Extraction.Source.CheckedInternal program kind.modulePath kind.name parameters i32
    (body kind emit.source.function.id offset.source.function.id code.id base.id)

def check? (program : CoreSynthesis.Program.CheckedProgram artifacts) (kind : Kind)
    {valid : CheckedValidation program .register} {width : CheckedValidation program .width}
    {rex : CheckedRex program} {fits : CheckedFits program} {word : CheckedWord program}
    {form : Memory.Checked program valid width rex fits word}
    (emit : Memory.CheckedMove program form kind.load) (offset : Frame.CheckedDisplacement program) :
    Option (Checked program kind emit offset) := do
  let source ← CoreSynthesis.Program.checkSourceFunction? program kind.modulePath kind.name
  let some (.sequence (.expression (.assign .set (.index (.local 2) (.constant codeId))
    (.call _ [_, _, _, _, _, .constant baseId, _]))) _) := source.function.body | none
  let code ← integerConstant? program.core codeId
  let base ← integerConstant? program.core baseId
  if codeValue : code.value = 1 then
    if baseValue : base.value = 5 then
      let internal ← Extraction.Source.checkInternal? program kind.modulePath kind.name parameters i32
        (body kind emit.source.function.id offset.source.function.id code.id base.id)
      pure ⟨code, codeValue, base, baseValue, internal⟩
    else none
  else none

end Lanius.X86.Source.Slot
