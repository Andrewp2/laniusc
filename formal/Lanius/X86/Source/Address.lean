import Lanius.X86.Source.Slot

namespace Lanius.X86.Source.Address

open Lanius.Core Lanius.Extraction

def parameters : List (VarId × Ty) :=
  [(0, .slice i32), (1, i32), (2, i32), (3, i32), (4, i32), (5, i32)]
def arguments : List Expr :=
  [read 0, read 1, read 2, number 64, number 141, read 3, read 4, read 5, .value (.boolean false)]

abbrev Checked (program : CoreSynthesis.Program.CheckedProgram artifacts)
    {valid : CheckedValidation program .register} {width : CheckedValidation program .width}
    {rex : CheckedRex program} {fits : CheckedFits program} {word : CheckedWord program}
    (form : Memory.Checked program valid width rex fits word) :=
  Extraction.Source.CheckedInternal program ["x86", "encode"] "address" parameters i32
    (returned (.call form.source.function.id arguments))

def check? (program : CoreSynthesis.Program.CheckedProgram artifacts)
    {valid : CheckedValidation program .register} {width : CheckedValidation program .width}
    {rex : CheckedRex program} {fits : CheckedFits program} {word : CheckedWord program}
    (form : Memory.Checked program valid width rex fits word) : Option (Checked program form) :=
  Extraction.Source.checkInternal? program ["x86", "encode"] "address" parameters i32
    (returned (.call form.source.function.id arguments))

def frameArguments (offset : FunctionId) (code base : ConstantId) : List Expr :=
  [read 0, read 1, Slot.cursor code, read 4, .constant base, .call offset [read 3]]
def frameBody (emit offset : FunctionId) (code base : ConstantId) : Stmt :=
  .sequence (.expression (.assign .set (.index (.local 2) (.constant code))
    (.call emit (frameArguments offset code base)))) (returned (Slot.cursor code))

structure CheckedFrame (program : CoreSynthesis.Program.CheckedProgram artifacts)
    {valid : CheckedValidation program .register} {width : CheckedValidation program .width}
    {rex : CheckedRex program} {fits : CheckedFits program} {word : CheckedWord program}
    {form : Memory.Checked program valid width rex fits word}
    (emit : Checked program form) (offset : Frame.CheckedDisplacement program) where
  code : IntegerConstant program.core
  codeValue : code.value = 1
  base : IntegerConstant program.core
  baseValue : base.value = 5
  internal : Extraction.Source.CheckedInternal program ["backend", "value"] "address" Slot.parameters i32
    (frameBody emit.source.function.id offset.source.function.id code.id base.id)

def checkFrame? (program : CoreSynthesis.Program.CheckedProgram artifacts)
    {valid : CheckedValidation program .register} {width : CheckedValidation program .width}
    {rex : CheckedRex program} {fits : CheckedFits program} {word : CheckedWord program}
    {form : Memory.Checked program valid width rex fits word}
    (emit : Checked program form) (offset : Frame.CheckedDisplacement program) :
    Option (CheckedFrame program emit offset) := do
  let source ← CoreSynthesis.Program.checkSourceFunction? program ["backend", "value"] "address"
  let some (.sequence (.expression (.assign .set (.index (.local 2) (.constant codeId))
    (.call _ [_, _, _, _, .constant baseId, _]))) _) := source.function.body | none
  let code ← integerConstant? program.core codeId
  let base ← integerConstant? program.core baseId
  if codeValue : code.value = 1 then
    if baseValue : base.value = 5 then
      let internal ← Extraction.Source.checkInternal? program ["backend", "value"] "address" Slot.parameters i32
        (frameBody emit.source.function.id offset.source.function.id code.id base.id)
      pure ⟨code, codeValue, base, baseValue, internal⟩
    else none
  else none

end Lanius.X86.Source.Address
