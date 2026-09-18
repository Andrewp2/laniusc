import Lanius.X86.Source.Table
import Lanius.X86.Transport.Core
import Lanius.X86.Machine.Comparison
import Lanius.X86.Machine.Boolean

namespace Lanius.X86.Lower.Condition

open Lanius.Core Lanius.X86.Source

def entries : List (Int × Int) := [(2, 4), (3, 5), (4, 12), (5, 14), (6, 15), (7, 13)]

abbrev Checked (program : Lanius.Extraction.CoreSynthesis.Program.CheckedProgram artifacts) :=
  Table.Checked program ["backend", "operation"] "condition" entries

def check? (program : Lanius.Extraction.CoreSynthesis.Program.CheckedProgram artifacts) : Option (Checked program) :=
  Table.check? program ["backend", "operation"] "condition" entries

def code : BinaryOp → Int
  | .equal => 4 | .notEqual => 5 | .less => 12 | .lessEqual => 14 | .greater => 15 | .greaterEqual => 13
  | _ => -1

theorem code_range (operation : BinaryOp) : code operation = -1 ∨ 0 ≤ code operation ∧ code operation < 16 := by
  cases operation <;> decide

/-- The actual selector agrees with the Core operation transported to Lanius,
including -1 for non-comparisons, and preserves caller memory and host state. -/
theorem selects (checked : Checked program) (operation : BinaryOp) :
    checked.internal.Spec [.signed .i32 (Transport.binaryTag operation)] (.signed .i32 (code operation)) := by
  have run := checked.spec (Transport.binaryTag operation)
  cases operation <;> simpa [Table.lookup, entries, Transport.binaryTag, code] using run

def nativeCode (operation : BinaryOp) (_valid : 0 ≤ code operation) : Fin 16 :=
  ⟨(code operation).toNat, by have := code_range operation; omega⟩

/-- All six supported comparisons produce the actual Core result, rather
than a separately defined reference Boolean. Operands cover every i32 bit pattern. -/
theorem core_result (operation : BinaryOp) (valid : 0 ≤ code operation)
    (flags : BitVec 64) (left right : BitVec 32) :
    Lanius.Semantics.evalBinaryValue target operation (.signed .i32 left.toInt) (.signed .i32 right.toInt) =
      .ok (.boolean (Machine.condition (Machine.subtractFlags flags left right) (nativeCode operation valid))) := by
  cases operation <;> simp_all [code, nativeCode, Lanius.Semantics.evalBinaryValue,
    Lanius.Semantics.evalSignedBinary, Lanius.Semantics.scalarEqual, Machine.compare_equal,
    Machine.compare_notEqual, Machine.compare_less, Machine.compare_lessEqual,
    Machine.compare_greater, Machine.compare_greaterEqual, Bool.beq_eq_decide_eq, ← BitVec.toInt_inj] <;>
    (change (0 : Int) ≤ -1 at valid; omega)

/-- A reusable semantic contract for an emitted i32 comparison window. -/
def NativeRefines (target : Target) (operation : BinaryOp) (bytes : List UInt8) : Prop :=
  ∀ before : Machine.State, Machine.CodeAt before.memory before.rip bytes →
    ∃ value after, Machine.Steps 3 before after ∧
      Lanius.Semantics.evalBinaryValue target operation
        (.signed .i32 ((before.registers 0).setWidth 32).toInt)
        (.signed .i32 ((before.registers 1).setWidth 32).toInt) = .ok (.boolean value) ∧
      after.registers 0 = (if value then 1 else 0) ∧
      (∀ register, register ≠ 0 → after.registers register = before.registers register) ∧
      after.memory = before.memory ∧ after.rip = before.rip + 8

/-- Loaded CMP EAX,ECX; SETcc AL; MOVZX EAX,AL takes three steps and
returns the Core Boolean. No instruction execution is supplied as a premise. -/
theorem native_steps (operation : BinaryOp) (valid : 0 ≤ code operation) :
    NativeRefines target operation (Machine.ReadOnly.code (Machine.Boolean.comparison32 (nativeCode operation valid))) := by
  intro before loaded
  refine ⟨_, Machine.ReadOnly.run _ before, Machine.ReadOnly.steps _ _ loaded,
    core_result operation valid before.flags _ _, ?_⟩
  simp [Machine.Boolean.comparison32, Machine.ReadOnly.run, Machine.Boolean.materialize_run,
    Machine.Boolean.compare32, Machine.execute, Machine.State.compare32, BitVec.add_assoc]
  intro register different same
  exact (different same).elim

end Lanius.X86.Lower.Condition
