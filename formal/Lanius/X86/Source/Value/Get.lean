import Lanius.X86.Source.Slot
import Lanius.X86.Source.Expression.Literal

namespace Lanius.X86.Source.Value.Get

open Lanius.Core Lanius.Extraction

def parameters : List (VarId × Ty) := [(0, .slice i32), (1, i32), (2, .slice i32), (3, i32), (4, i32)]
def arguments (width offset : FunctionId) (code rax base : ConstantId) : List Expr :=
  [read 0, read 1, Slot.cursor code, .call width [read 4], .constant rax, .constant base, .call offset [read 3]]
def tail (emit width offset : FunctionId) (code rax base : ConstantId) : Stmt :=
  .sequence (.expression (.assign .set (.index (.local 2) (.constant code))
    (.call emit (arguments width offset code rax base)))) (returned (Slot.cursor code))
def body (aggregate emit width offset : FunctionId) (code rax base : ConstantId) (aggregateBranch : Stmt) : Stmt :=
  .sequence (.ifThenElse (.call aggregate [read 4]) aggregateBranch .skip) (tail emit width offset code rax base)

/-- Keep the source's aggregate/address branch intact but opaque. The scalar
proof establishes that its actual aggregate predicate is false before loading. -/
structure Checked (program : CoreSynthesis.Program.CheckedProgram artifacts)
    (layout : Expression.Literal.Layout program)
    {valid : CheckedValidation program .register} {width : CheckedValidation program .width}
    {rex : CheckedRex program} {fits : CheckedFits program} {word : CheckedWord program}
    {form : Memory.Checked program valid width rex fits word}
    (emit : Memory.CheckedMove program form true) (offset : Frame.CheckedDisplacement program) where
  code : IntegerConstant program.core
  rax : IntegerConstant program.core
  base : IntegerConstant program.core
  values : code.value = 1 ∧ rax.value = 0 ∧ base.value = 5
  aggregateBranch : Stmt
  internal : Extraction.Source.CheckedInternal program ["backend", "value"] "get" parameters i32
    (body layout.aggregate.source.function.id emit.source.function.id layout.width.source.function.id
      offset.source.function.id code.id rax.id base.id aggregateBranch)

def check? (program : CoreSynthesis.Program.CheckedProgram artifacts) (layout : Expression.Literal.Layout program)
    {valid : CheckedValidation program .register} {width : CheckedValidation program .width}
    {rex : CheckedRex program} {fits : CheckedFits program} {word : CheckedWord program}
    {form : Memory.Checked program valid width rex fits word}
    (emit : Memory.CheckedMove program form true) (offset : Frame.CheckedDisplacement program) :
    Option (Checked program layout emit offset) := do
  let source ← CoreSynthesis.Program.checkSourceFunction? program ["backend", "value"] "get"
  let some (.sequence (.ifThenElse _ aggregateBranch _)
    (.sequence (.expression (.assign .set (.index (.local 2) (.constant codeId))
      (.call _ [_, _, _, _, .constant raxId, .constant baseId, _]))) _)) := source.function.body | none
  let code ← integerConstant? program.core codeId
  let rax ← integerConstant? program.core raxId
  let base ← integerConstant? program.core baseId
  if values : code.value = 1 ∧ rax.value = 0 ∧ base.value = 5 then
    let internal ← Extraction.Source.checkInternal? program ["backend", "value"] "get" parameters i32
      (body layout.aggregate.source.function.id emit.source.function.id layout.width.source.function.id
        offset.source.function.id code.id rax.id base.id aggregateBranch)
    pure ⟨code, rax, base, values, aggregateBranch, internal⟩
  else none

end Lanius.X86.Source.Value.Get
