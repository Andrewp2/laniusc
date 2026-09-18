import Lanius.X86.Source.Boolean
import Lanius.X86.Source.Guarded
import Lanius.X86.Lower.Condition

namespace Lanius.X86.Source.Operation

open Lanius.Core Lanius.Extraction

def arguments (cmp rax rcx : ConstantId) : List Expr :=
  [read 0, read 1, read 2, number 32, .constant cmp, .constant rax, .constant rcx]
def booleanArguments (binary : FunctionId) (cmp rax rcx : ConstantId) : List Expr :=
  [read 0, read 1, .call binary (arguments cmp rax rcx), read 4]
def branch (binary boolean : FunctionId) (cmp rax rcx : ConstantId) : Stmt :=
  returned (.call boolean (booleanArguments binary cmp rax rcx))
def body (selector binary boolean : FunctionId) (cmp rax rcx : ConstantId) (rest : Stmt) : Stmt :=
  .letLocal 4 i32 (.call selector [read 3]) (.sequence
    (.ifThenElse (.binary .greaterEqual (read 4) (number 0)) (branch binary boolean cmp rax rcx) .skip) rest)

/-- Authenticate the whole body while retaining the unselected arithmetic
tail verbatim. The comparison proof must return before that tail can run. -/
structure Checked (emitters : CheckedBuffer encoded sources) where
  selector : Lower.Condition.Checked emitters.pack.program
  binary : CheckedGuardedRegister emitters.pack.program emitters.registerForm .binary
  boolean : Boolean.Checked emitters
  cmp : IntegerConstant emitters.pack.program.core
  rax : IntegerConstant emitters.pack.program.core
  rcx : IntegerConstant emitters.pack.program.core
  values : cmp.value = 57 ∧ rax.value = 0 ∧ rcx.value = 1
  rest : Stmt
  internal : Extraction.Source.CheckedInternal emitters.pack.program ["backend", "operation"] "binary"
    Boolean.parameters i32 (body selector.internal.source.function.id binary.internal.source.function.id
      boolean.internal.source.function.id cmp.id rax.id rcx.id rest)

def check? (emitters : CheckedBuffer encoded sources) : Option (Checked emitters) := do
  let selector ← Lower.Condition.check? emitters.pack.program
  let binary ← checkGuardedRegister? emitters.pack.program emitters.registerForm .binary
  let boolean ← Boolean.check? emitters
  let source ← CoreSynthesis.Program.checkSourceFunction? emitters.pack.program ["backend", "operation"] "binary"
  let some (.letLocal _ _ _ (.sequence (.ifThenElse _ (.sequence (.returnValue (some (.call _ [_, _,
      .call _ [_, _, _, _, .constant cmpId, .constant raxId, .constant rcxId], _]))) _) _) rest)) := source.function.body | none
  let cmp ← integerConstant? emitters.pack.program.core cmpId
  let rax ← integerConstant? emitters.pack.program.core raxId
  let rcx ← integerConstant? emitters.pack.program.core rcxId
  if values : cmp.value = 57 ∧ rax.value = 0 ∧ rcx.value = 1 then
    let internal ← Extraction.Source.checkInternal? emitters.pack.program ["backend", "operation"] "binary"
      Boolean.parameters i32 (body selector.internal.source.function.id binary.internal.source.function.id
        boolean.internal.source.function.id cmp.id rax.id rcx.id rest)
    pure ⟨selector, binary, boolean, cmp, rax, rcx, values, rest, internal⟩
  else none

end Lanius.X86.Source.Operation
