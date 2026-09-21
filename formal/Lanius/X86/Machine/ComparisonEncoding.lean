import Lanius.X86.Machine.FrameSlots

namespace Lanius.X86.Machine

open Lanius.X86

private theorem setCondition_zeroExtend (value : BitVec 64) (bit : Bool) :
    ((value.extractLsb' 8 56 ++ (if bit then (1 : BitVec 8) else 0)).setWidth 8).setWidth 64 =
      if bit then (1 : BitVec 64) else 0 := by
  rw [BitVec.setWidth_append_eq_right]
  cases bit <;> rfl

def frameCompareBytes (slot : Nat) (code : Fin 16) : List UInt8 :=
  rightToRcxBytes ++ frameLoadBytes slot ++ compareBytes 0 rcxRegister ++
    setConditionBytes code 0 ++ zeroExtendByteBytes 0 0

theorem frameCompare_protocol (slot : Nat) (code : Fin 16)
    (leftValue rightValue : BitVec 32) (before : State)
    (slotValue : read32 before.memory
      (before.registers rbpRegister +
        (BitVec.ofInt 32 (frameDisplacement slot)).signExtend 64) = leftValue)
    (rightResult : before.registers 0 = rightValue.setWidth 64)
    (loaded : CodeAt before.memory before.rip (frameCompareBytes slot code)) :
    ∃ moved loadedLeft compared conditioned after,
      Step before moved ∧ Step moved loadedLeft ∧ Step loadedLeft compared ∧
      Step compared conditioned ∧ Step conditioned after ∧
      after.registers 0 =
        (if condition (subtractFlags before.flags leftValue rightValue) code
          then (1 : BitVec 64) else 0) ∧
      after.registers rbpRegister = before.registers rbpRegister ∧
      after.memory = before.memory ∧
      after.rip = before.rip + BitVec.ofNat 64 (frameCompareBytes slot code).length := by
  let moved := before.move32 rcxRegister 0 rightToRcxBytes.length
  let loadedLeft := moved.load32 0 rbpRegister
    (BitVec.ofInt 32 (frameDisplacement slot)) (frameLoadBytes slot).length
  let compared := loadedLeft.compare32 0 rcxRegister (compareBytes 0 rcxRegister).length
  let conditioned := compared.setCondition code 0 (setConditionBytes code 0).length
  let after := conditioned.zeroExtendByte 0 0 (zeroExtendByteBytes 0 0).length
  have loaded' : CodeAt before.memory before.rip
      (rightToRcxBytes ++ (frameLoadBytes slot ++
        (compareBytes 0 rcxRegister ++
          (setConditionBytes code 0 ++ zeroExtendByteBytes 0 0)))) := by
    simpa [frameCompareBytes, List.append_assoc] using loaded
  have rightLoaded : CodeAt before.memory before.rip rightToRcxBytes := loaded'.prefix
  have moveTail : CodeAt moved.memory moved.rip
      (frameLoadBytes slot ++ (compareBytes 0 rcxRegister ++
        (setConditionBytes code 0 ++ zeroExtendByteBytes 0 0))) := by
    simpa [moved, State.move32] using loaded'.suffix
  have loadLoaded : CodeAt moved.memory moved.rip (frameLoadBytes slot) := moveTail.prefix
  have loadTail : CodeAt loadedLeft.memory loadedLeft.rip
      (compareBytes 0 rcxRegister ++ (setConditionBytes code 0 ++ zeroExtendByteBytes 0 0)) := by
    have suffix := moveTail.suffix
    simpa [loadedLeft, moved, State.load32, State.immediate32, State.move32,
      rbpRegister, rcxRegister] using suffix
  have compareLoaded : CodeAt loadedLeft.memory loadedLeft.rip
      (compareBytes 0 rcxRegister) := loadTail.prefix
  have compareTail : CodeAt compared.memory compared.rip
      (setConditionBytes code 0 ++ zeroExtendByteBytes 0 0) := by
    have suffix := loadTail.suffix
    simpa [compared, loadedLeft, moved, State.compare32, State.load32,
      State.immediate32, State.move32, rbpRegister, rcxRegister] using suffix
  have setLoaded : CodeAt compared.memory compared.rip (setConditionBytes code 0) :=
    compareTail.prefix
  have setTail : CodeAt conditioned.memory conditioned.rip
      (zeroExtendByteBytes 0 0) := by
    simpa [conditioned, compared, loadedLeft, moved, State.setCondition,
      State.compare32, State.load32, State.immediate32, State.move32,
      rbpRegister, rcxRegister] using compareTail.suffix
  have zeroLoaded : CodeAt conditioned.memory conditioned.rip
      (zeroExtendByteBytes 0 0) := setTail
  have first := rightToRcx_step before moved rightLoaded (by rfl)
  have second := frameLoad_step moved loadedLeft slot loadLoaded (by rfl)
  have third := compare_step loadedLeft compared 0 rcxRegister compareLoaded (by rfl)
  have fourth := setCondition_step compared conditioned code 0 setLoaded (by rfl)
  have fifth := zeroExtendByte_step conditioned after 0 0 zeroLoaded (by rfl)
  refine ⟨moved, loadedLeft, compared, conditioned, after,
    first, second, third, fourth, fifth, ?_, ?_, ?_, ?_⟩
  have slotValue' : read32 before.memory
      (before.registers 5 +
        (BitVec.ofInt 32 (frameDisplacement slot)).signExtend 64) = leftValue := by
    simpa [rbpRegister] using slotValue
  have leftRegister : (loadedLeft.registers 0).setWidth 32 = leftValue := by
    simp [loadedLeft, moved, State.load32, State.immediate32, State.move32,
      rbpRegister, rcxRegister, slotValue']
  have rightRegister : (loadedLeft.registers rcxRegister).setWidth 32 = rightValue := by
    simpa [loadedLeft, moved, State.load32, State.immediate32, State.move32,
      rbpRegister, rcxRegister] using
      congrArg (fun value : BitVec 64 => value.setWidth 32) rightResult
  have compareFlags : compared.flags = subtractFlags before.flags leftValue rightValue := by
    change subtractFlags before.flags
        ((loadedLeft.registers 0).setWidth 32)
        ((loadedLeft.registers rcxRegister).setWidth 32) = _
    rw [leftRegister, rightRegister]
  have conditionValue : condition compared.flags code =
      condition (subtractFlags before.flags leftValue rightValue) code := by
    rw [compareFlags]
  · by_cases h : condition (subtractFlags before.flags leftValue rightValue) code
    · simpa [after, conditioned, State.zeroExtendByte, State.setCondition,
        conditionValue, h] using setCondition_zeroExtend (compared.registers 0) true
    · simpa [after, conditioned, State.zeroExtendByte, State.setCondition,
        conditionValue, h] using setCondition_zeroExtend (compared.registers 0) false
  · rfl
  · rfl
  · simp [after, conditioned, compared, loadedLeft, moved, State.zeroExtendByte,
      State.setCondition, State.compare32, State.load32, State.immediate32,
      State.move32, rbpRegister, rcxRegister, BitVec.ofNat_add, BitVec.add_assoc,
      frameCompareBytes, rightToRcxBytes, frameLoadBytes]

end Lanius.X86.Machine
