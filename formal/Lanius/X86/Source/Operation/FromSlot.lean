import Lanius.X86.Source.Operation.Arithmetic
import Lanius.X86.Source.Memory
import Lanius.X86.Frame.Source

namespace Lanius.X86.Source.Operation.FromSlot

open Lanius.Core Lanius.Extraction

def parameters : List (VarId × Ty) := Boolean.parameters ++ [(4, i32)]
def move (function : FunctionId) (rax rcx : ConstantId) : Expr :=
  .call function [read 0, read 1, read 2, number 32, .constant rcx, .constant rax]
def loadArguments (moving offset : FunctionId) (rax rcx rbp : ConstantId) : List Expr :=
  [read 0, read 1, move moving rax rcx, number 32, .constant rax, .constant rbp, .call offset [read 3]]
def arguments (moving loading offset : FunctionId) (rax rcx rbp : ConstantId) : List Expr :=
  [read 0, read 1, .call loading (loadArguments moving offset rax rcx rbp), read 4]
def body (binary moving loading offset : FunctionId) (rax rcx rbp : ConstantId) : Stmt :=
  returned (.call binary (arguments moving loading offset rax rcx rbp))

structure Checked (parent : Operation.Checked emitters) where
  memory : Memory.Checked emitters.pack.program emitters.registerValid emitters.widthValid emitters.rex emitters.fits emitters.word
  load : Memory.CheckedMove emitters.pack.program memory true
  offset : Frame.CheckedDisplacement emitters.pack.program
  rbp : IntegerConstant emitters.pack.program.core
  base : rbp.value = 5
  internal : Extraction.Source.CheckedInternal emitters.pack.program ["backend", "operation"] "from_slot" parameters i32
    (body parent.internal.source.function.id (emitters.registerWrappers .move).source.function.id
      load.source.function.id offset.source.function.id parent.rax.id parent.rcx.id rbp.id)

def check? (parent : Operation.Checked emitters) : Option (Checked parent) := do
  let program := emitters.pack.program
  let source ← CoreSynthesis.Program.checkSourceFunction? program ["backend", "operation"] "from_slot"
  let some (.sequence (.returnValue (some (.call _ [_, _, .call _ [_, _, _, _, _, .constant baseId, _], _]))) .skip) :=
    source.function.body | none
  let memory ← Memory.check? program emitters.registerValid emitters.widthValid emitters.rex emitters.fits emitters.word
  let load ← Memory.checkMove? program memory true
  let offset ← Frame.checkDisplacement? program
  let rbp ← integerConstant? program.core baseId
  if base : rbp.value = 5 then
    let internal ← Extraction.Source.checkInternal? program ["backend", "operation"] "from_slot" parameters i32
      (body parent.internal.source.function.id (emitters.registerWrappers .move).source.function.id
        load.source.function.id offset.source.function.id parent.rax.id parent.rcx.id rbp.id)
    pure ⟨memory, load, offset, rbp, base, internal⟩
  else none

end Lanius.X86.Source.Operation.FromSlot
