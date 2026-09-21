import Lanius.X86.Machine.ComparisonEncoding

namespace Lanius.X86.Machine.ComparisonEncodingTests

open Lanius.X86
open Lanius.X86.Machine

example : frameCompareBytes 0 4 =
    [137, 193, 139, 133, 248, 255, 255, 255, 57, 200, 15, 148, 192, 15, 182, 192] := by decide

example (slot : Nat) (code : Fin 16) (leftValue rightValue : BitVec 32) (before : State)
    (slotValue : read32 before.memory (before.registers rbpRegister + (BitVec.ofInt 32 (frameDisplacement slot)).signExtend 64) = leftValue)
    (rightResult : before.registers 0 = rightValue.setWidth 64)
    (loaded : CodeAt before.memory before.rip (frameCompareBytes slot code)) :
    ∃ moved loadedLeft compared conditioned after, Step before moved ∧ Step moved loadedLeft ∧ Step loadedLeft compared ∧ Step compared conditioned ∧ Step conditioned after ∧ after.registers 0 = (if condition (subtractFlags before.flags leftValue rightValue) code then (1 : BitVec 64) else 0) ∧ after.registers rbpRegister = before.registers rbpRegister ∧ after.memory = before.memory ∧ after.rip = before.rip + BitVec.ofNat 64 (frameCompareBytes slot code).length := by
  exact frameCompare_protocol slot code leftValue rightValue before slotValue rightResult loaded

end Lanius.X86.Machine.ComparisonEncodingTests
