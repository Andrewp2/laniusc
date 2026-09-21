import Lanius.X86.Machine.FrameSlots

namespace Lanius.X86.Machine.FrameSlotsTests

open Lanius.X86
open Lanius.X86.Machine

#eval frameBytes 1
#eval frameBytes 2
#eval frameBytes 3
#eval framePatchOffset

#check framePrologue_steps
#check frameEpilogue_steps

example (slot : Nat) :
    decode (frameStoreBytes slot) =
      some (.store32 0 rbpRegister
        (BitVec.ofInt 32 (frameDisplacement slot)), (frameStoreBytes slot).length) :=
  frameStore_decodes slot

example :
    decode rightToRcxBytes =
      some (.move32 rcxRegister 0, rightToRcxBytes.length) := by
  exact rightToRcx_decodes

example (slots : Nat) :
    framePrologueBytes slots =
      frameProloguePrefix ++ displacementBytes (frameSizeBits slots) ++
        framePrologueSuffix :=
  framePrologue_patched slots

example {count slot : Nat} {operation : Alu}
    {leftValue rightValue : BitVec 32} {before stored rightState : State}
    (storeLoaded : CodeAt before.memory before.rip (frameStoreBytes slot))
    (storeResult : stored = before.store32 0 rbpRegister
      (BitVec.ofInt 32 (frameDisplacement slot)) (frameStoreBytes slot).length)
    (leftValue_eq : (before.registers 0).setWidth 32 = leftValue)
    (rightSteps : Steps count stored rightState)
    (sameRbp : rightState.registers rbpRegister = before.registers rbpRegister)
    (sameSlot : read32 rightState.memory
      (frameSlotAddress (before.registers rbpRegister) slot) =
      read32 stored.memory (frameSlotAddress (before.registers rbpRegister) slot))
    (rightResult : rightState.registers 0 = rightValue.setWidth 64)
    (loaded : CodeAt rightState.memory rightState.rip (frameAluBytes slot operation)) :
    ∃ after : State, Steps (count + 4) before after ∧
      after.registers 0 = (operation.result leftValue rightValue).setWidth 64 := by
  have h := frameStore_then_alu_protocol count slot operation leftValue rightValue before stored rightState
    storeLoaded storeResult leftValue_eq rightSteps sameRbp sameSlot rightResult loaded
  cases h with
  | intro after rest => exact ⟨after, rest.1, rest.2.1⟩

example (count slot : Nat) (leftValue rightValue : BitVec 32)
    (before stored rightState : State)
    (storeLoaded : CodeAt before.memory before.rip (frameStoreBytes slot))
    (storeResult : stored = before.store32 0 rbpRegister (BitVec.ofInt 32 (frameDisplacement slot)) (frameStoreBytes slot).length)
    (leftValue_eq : (before.registers 0).setWidth 32 = leftValue)
    (rightSteps : Steps count stored rightState)
    (sameRbp : rightState.registers rbpRegister = before.registers rbpRegister)
    (sameSlot : read32 rightState.memory (frameSlotAddress (before.registers rbpRegister) slot) = read32 stored.memory (frameSlotAddress (before.registers rbpRegister) slot))
    (rightResult : rightState.registers 0 = rightValue.setWidth 64)
    (loaded : CodeAt rightState.memory rightState.rip (frameMultiplyBytes slot)) :
    ∃ after, Steps (count + 4) before after ∧ after.registers 0 = (leftValue * rightValue).setWidth 64 ∧ after.registers rbpRegister = before.registers rbpRegister ∧ after.memory = rightState.memory ∧ after.rip = rightState.rip + BitVec.ofNat 64 (frameMultiplyBytes slot).length :=
  frameStore_then_multiply_protocol count slot leftValue rightValue before stored rightState storeLoaded storeResult leftValue_eq rightSteps sameRbp sameSlot rightResult loaded

end Lanius.X86.Machine.FrameSlotsTests
