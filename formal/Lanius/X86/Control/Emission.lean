import Lanius.X86.Control.Decode
import Lanius.X86.Buffer.Fixed

namespace Lanius.X86.Control

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.X86.Source Lanius.X86.Buffer

/-- The decoder consumes Core's little-endian bytes as the original 32-bit
pattern, including negative displacements. Trailing instructions are ignored. -/
theorem displacement?_i32Bytes (value : Int) (tail : List UInt8) :
    displacement? (i32Bytes value ++ tail) = some (BitVec.ofInt 32 value) := by
  have byteRoundTrip (byte : Fin 256) : (UInt8.ofNat byte.val).toFin = byte := by
    apply Fin.ext
    change byte.val % 256 = byte.val
    exact Nat.mod_eq_of_lt byte.isLt
  rw [← wordBytes_core]
  simp only [WordBytes.toBytes, List.cons_append, List.nil_append, displacement?, byteRoundTrip]
  exact congrArg some (readBytes_wordBytes _)

theorem decode_jump (value : Int) (tail : List UInt8) :
    decode (0xe9 :: (i32Bytes value ++ tail)) = some (.jump (BitVec.ofInt 32 value), 5) := by
  simp [decode, displacement?_i32Bytes]

theorem decode_call (value : Int) (tail : List UInt8) :
    decode (0xe8 :: (i32Bytes value ++ tail)) = some (.call (BitVec.ofInt 32 value), 5) := by
  simp [decode, displacement?_i32Bytes]

theorem decode_branch (condition : Fin 16) (value : Int) (tail : List UInt8) :
    decode (0x0f :: UInt8.ofNat (128 + condition.val) :: (i32Bytes value ++ tail)) =
      some (.branch condition (BitVec.ofInt 32 value), 6) := by
  have byteValue : (UInt8.ofNat (128 + condition.val)).toNat = 128 + condition.val := by
    rw [UInt8.toNat_ofNat', Nat.mod_eq_of_lt (by omega)]
  have notSyscall : ¬ 128 + condition.val = 5 := by omega
  have notTrap : ¬ 128 + condition.val = 11 := by omega
  have valid : 128 ≤ 128 + condition.val ∧ 128 + condition.val < 144 := by omega
  simp only [decode, byteValue, if_neg notSyscall, if_neg notTrap, dif_pos valid]
  rw [displacement?_i32Bytes]
  simp

def Fixed.sourceName : Fixed → String
  | .returnNear => "return_near"
  | .syscall => "syscall"
  | .ud2 => "trap"

/-- The real Lanius call emits bytes that decode to the requested x86
instruction. This proves emission, not execution of RET/SYSCALL/UD2. Their
stack, host, and exception semantics are later simulation obligations. -/
theorem fixed_emits (instruction : Fixed)
    (checked : CheckedFixed program fits ["x86", "control"] instruction.sourceName instruction.bytes)
    (capacity cursor : Nat) (wellFormed : StateWellFormed before)
    (room : cursor + instruction.bytes.length ≤ capacity) (storage : capacity ≤ values.length)
    (capacityBound : capacity ≤ 2147483647)
    (backing : before.cellEntry? cell = some {
      id := cell, value := some (.array (signedI32Values values)) })
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments
      (fixedValues (.slice i32 cell [] 0 values.length) capacity cursor) before) :
    ∃ after emitted, Evaluates program.core caller (.call checked.source.function.id arguments)
        (.signed .i32 (cursor + instruction.bytes.length : Nat)) after ∧
      after.cellEntry? cell = some {
        id := cell, value := some (.array (signedI32Values emitted)) } ∧
      decode (byteSlice emitted cursor instruction.bytes.length) =
        some (instruction.instruction, instruction.bytes.length) ∧
      emitted.length = values.length ∧
      (∀ index, index < cursor ∨ cursor + instruction.bytes.length ≤ index →
        emitted[index]? = values[index]?) ∧
      CellEffect (CellSet.singleton cell) before after ∧ HeapFrame before after := by
  obtain ⟨after, run, contents, effect, heapFrame⟩ :=
    fixed_success checked capacity cursor wellFormed room storage capacityBound backing argumentsResult
  refine ⟨after, writtenBytes values cursor instruction.bytes, run, contents, ?_,
    writtenBytes_length, fun _ outside => writtenBytes_frame outside, effect, heapFrame⟩
  rw [writtenBytes_byteSlice (by omega)]
  simpa only [List.append_nil] using instruction.decode []

end Lanius.X86.Control
