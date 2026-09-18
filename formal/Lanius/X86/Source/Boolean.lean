import Lanius.X86.Source.Check
import Lanius.X86.Source.Constant

namespace Lanius.X86.Source.Boolean

open Lanius.Core Lanius.Extraction

def parameters : List (VarId × Ty) := [(0, .slice i32), (1, i32), (2, i32), (3, i32)]
def first (set : FunctionId) (rax : ConstantId) : Expr :=
  .call set [read 0, read 1, read 2, read 3, .constant rax]
def arguments (set : FunctionId) (rax : ConstantId) : List Expr :=
  [read 0, read 1, first set rax, .constant rax, .constant rax]
def body (set widen : FunctionId) (rax : ConstantId) : Stmt := returned (.call widen (arguments set rax))

structure Checked (emitters : CheckedBuffer encoded sources) where
  rax : IntegerConstant emitters.pack.program.core
  zero : rax.value = 0
  internal : Extraction.Source.CheckedInternal emitters.pack.program ["backend", "operation"] "boolean"
    parameters i32 (body emitters.condition.source.function.id
      (emitters.registerWrappers .zeroExtend).source.function.id rax.id)

def check? (emitters : CheckedBuffer encoded sources) : Option (Checked emitters) := do
  let source ← CoreSynthesis.Program.checkSourceFunction? emitters.pack.program ["backend", "operation"] "boolean"
  let some (.sequence (.returnValue (some (.call _ [_, _, _, .constant raxId, _]))) .skip) :=
    source.function.body | none
  let rax ← integerConstant? emitters.pack.program.core raxId
  if zero : rax.value = 0 then
    let internal ← Extraction.Source.checkInternal? emitters.pack.program ["backend", "operation"] "boolean"
      parameters i32 (body emitters.condition.source.function.id
        (emitters.registerWrappers .zeroExtend).source.function.id rax.id)
    pure ⟨rax, zero, internal⟩
  else none

end Lanius.X86.Source.Boolean
