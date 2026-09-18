import Lanius.X86.Source.Operation
import Lanius.X86.Encode.Arithmetic

namespace Lanius.X86.Source.Operation.Arithmetic

open Lanius.Core Lanius.Extraction

def entries : List (Int × Int) :=
  ([.add, .subtract, .and, .or, .xor] : List Machine.Alu).map fun operation =>
    (Transport.binaryTag (Encode.Arithmetic.coreOp operation), operation.opcode)

abbrev Selector (program : CoreSynthesis.Program.CheckedProgram artifacts) :=
  Table.Checked program ["backend", "operation"] "opcode" entries

def arguments (rax rcx : ConstantId) : List Expr :=
  [read 0, read 1, read 2, number 32, read 5, .constant rax, .constant rcx]

def body (selector binary : FunctionId) (rax rcx : ConstantId) (rest : Stmt) : Stmt :=
  .letLocal 5 i32 (.call selector [read 3]) (.sequence
    (.ifThenElse (.binary .greaterEqual (read 5) (number 0))
      (returned (.call binary (arguments rax rcx))) .skip) rest)

structure Checked (checked : Operation.Checked emitters) where
  selector : Selector emitters.pack.program
  rest : Stmt
  bodyExact : checked.rest = body selector.internal.source.function.id checked.binary.internal.source.function.id
    checked.rax.id checked.rcx.id rest

def check? (checked : Operation.Checked emitters) : Option (Checked checked) := do
  let selector ← Table.check? emitters.pack.program ["backend", "operation"] "opcode" entries
  let .letLocal _ _ _ (.sequence _ rest) := checked.rest | none
  let exactBody ← Core.Equality.statement? checked.rest
    (body selector.internal.source.function.id checked.binary.internal.source.function.id checked.rax.id checked.rcx.id rest)
  pure ⟨selector, rest, exactBody.equal⟩

theorem selects (checked : Selector program) (operation : Machine.Alu) :
    checked.internal.Spec [.signed .i32 (Transport.binaryTag (Encode.Arithmetic.coreOp operation))]
      (.signed .i32 operation.opcode) := by
  have selected := checked.spec (Transport.binaryTag (Encode.Arithmetic.coreOp operation))
  cases operation <;> simpa [Table.lookup, entries, Transport.binaryTag, Encode.Arithmetic.coreOp, Machine.Alu.opcode] using selected

end Lanius.X86.Source.Operation.Arithmetic
