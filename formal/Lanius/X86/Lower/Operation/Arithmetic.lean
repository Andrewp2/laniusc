import Lanius.X86.Source.Operation.Arithmetic
import Lanius.X86.Encode.Boolean
import Lanius.X86.Buffer.Scope
import Lanius.Extraction.Source.Storage

namespace Lanius.X86.Lower.Operation.Arithmetic

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.X86.Buffer Lanius.X86.Source

def inputs (output : Value) (capacity start : Int) (operation : Machine.Alu) : List Value :=
  Encode.Boolean.inputs output capacity start (Transport.binaryTag (Encode.Arithmetic.coreOp operation))

/-- Dispatch transfers the selected emitter's contract to the actual backend
function. Callers supply a callee contract, not an execution callback. -/
theorem dispatch {parent : Source.Operation.Checked emitters} {pre : Storage} {post : List Cell → Prop}
    (checked : Source.Operation.Arithmetic.Checked parent) (operation : Machine.Alu)
    (emits : parent.binary.internal.Spec (Encode.Guarded.inputs .binary output capacity start 32 operation.opcode 0 1)
      result (fun before => pre.holds before.cells) (fun _ after => post after.cells) writes) :
    parent.internal.Spec (inputs output capacity start operation) result
      (fun before => pre.holds before.cells) (fun _ after => post after.cells) writes := by
  apply parent.internal.specStorage rfl
  intro before wellFormed reads ready
  have locals := Locals.ofReads wellFormed (fun index => reads index.val index.isLt)
  have condition := Condition.selects parent.selector (Encode.Arithmetic.coreOp operation)
  have negative : Condition.code (Encode.Arithmetic.coreOp operation) = -1 := by cases operation <;> rfl
  rw [negative] at condition
  apply locals.letCall wellFormed condition (by have := locals.found; core_args [inputs, Encode.Boolean.inputs])
  intro selected first
  have initialReads := first.locals.found
  have opcode := Source.Operation.Arithmetic.selects checked.selector operation
  suffices tail : Returns emitters.pack.program.core (selected.bindLocal 4 (.signed .i32 (-1)))
      parent.rest result (fun after => post after.cells) writes by
    obtain ⟨after, run, held, effect, heap⟩ := tail
    exact ⟨after, by core_exec [inputs, Encode.Boolean.inputs], held, effect, heap⟩
  rw [checked.bodyExact]
  apply first.locals.letCall first.wellFormed opcode (by core_args [inputs, Encode.Boolean.inputs])
  intro chosen second
  have reads := second.locals.found
  have rax := parent.rax.evaluates (before := chosen.bindLocal 5 (.signed .i32 operation.opcode))
  have rcx := parent.rcx.evaluates (before := chosen.bindLocal 5 (.signed .i32 operation.opcode))
  simp only [parent.values.2.1, parent.values.2.2] at rax rcx
  obtain ⟨after, call, held, effect, heap⟩ := emits.call
    (caller := chosen.bindLocal 5 (.signed .i32 operation.opcode))
    (arguments := Source.Operation.Arithmetic.arguments parent.rax.id parent.rcx.id) second.wellFormed
    (by core_args [Source.Operation.Arithmetic.arguments, Encode.Guarded.inputs, inputs, Encode.Boolean.inputs])
    (pre.stable (first.trans second).entry ready)
  have nonnegative : 0 ≤ (operation.opcode : Int) := Int.natCast_nonneg _
  exact ⟨after, by core_exec [Source.Operation.Arithmetic.body, inputs, Encode.Boolean.inputs], held, effect, heap⟩

/-- The backend accepts a Core arithmetic tag, selects its opcode, emits it,
and retains native correctness of the actual output window. -/
theorem succeeds {parent : Source.Operation.Checked emitters}
    (checked : Source.Operation.Arithmetic.Checked parent) (operation : Machine.Alu) (capacity start : Nat)
    (room : start + 2 ≤ capacity) (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647) :
    Encode.Arithmetic.Produces parent.internal (inputs (.slice i32 cell [] 0 values.length) capacity start operation)
      operation 0 1 cell values start := by
  unfold Encode.Arithmetic.Produces
  apply dispatch (pre := Storage.entry cell (some (.array (signedI32Values values))))
    checked operation
  exact Encode.Arithmetic.succeeds parent.binary operation 0 1 capacity start
    (by cases operation <;> exact room) storage bounded

/-- Invalid cursors and short buffers return -1 before accessing output,
which need not be a slice. Both read-only selector scopes are restored. -/
theorem rejects {parent : Source.Operation.Checked emitters}
    (checked : Source.Operation.Arithmetic.Checked parent) (operation : Machine.Alu) (output : Value) (capacity start : Int)
    (bounded : capacity ≤ 2147483647) (bad : reserved capacity start 2 = false) :
    parent.internal.Spec (inputs output capacity start operation) (.signed .i32 (-1)) := by
  apply dispatch (pre := Storage.pure True) (post := fun _ => True) checked operation
  exact Encode.Guarded.rejects_capacity parent.binary (Encode.Arithmetic.choice operation) .w32 0 1 output capacity start bounded
    (by cases operation <;> exact bad)

end Lanius.X86.Lower.Operation.Arithmetic
