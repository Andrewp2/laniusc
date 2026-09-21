import Lanius.X86.Machine.Scalar
import Lanius.X86.Machine.AluEncoding

namespace Lanius.X86.Machine

open Lanius.X86

def displacementBytes (displacement : BitVec 32) : List UInt8 :=
  let bytes := wordBytes displacement
  [UInt8.ofNat bytes.low.val, UInt8.ofNat bytes.second.val,
    UInt8.ofNat bytes.third.val, UInt8.ofNat bytes.high.val]

def jumpBytes (displacement : BitVec 32) : List UInt8 :=
  233 :: displacementBytes displacement

def callBytes (displacement : BitVec 32) : List UInt8 :=
  232 :: displacementBytes displacement

theorem displacement_decodes (displacement : BitVec 32) :
    Control.displacement? (displacementBytes displacement) = some displacement := by
  simp [displacementBytes, Control.displacement?, readBytes]
  exact readBytes_wordBytes displacement

theorem jump_decodes (displacement : BitVec 32) :
    decode (jumpBytes displacement) = some (.jump displacement, 5) := by
  simp [jumpBytes, decode, X86.Register.Rex.decode?, decodeOpcode, displacement_decodes]

theorem call_decodes (displacement : BitVec 32) :
    decode (callBytes displacement) = some (.call displacement, 5) := by
  simp [callBytes, decode, X86.Register.Rex.decode?, decodeOpcode, displacement_decodes]

theorem jump_step (before after : State) (displacement : BitVec 32)
    (loaded : CodeAt before.memory before.rip (jumpBytes displacement))
    (result : after = before.jump displacement (jumpBytes displacement).length) :
    Step before after := by
  exact Step.jumped (jumpBytes displacement) loaded displacement
    (jumpBytes displacement).length (jump_decodes displacement) result

theorem call_step (before after : State) (displacement : BitVec 32)
    (loaded : CodeAt before.memory before.rip (callBytes displacement))
    (result : after = before.call displacement (callBytes displacement).length) :
    Step before after := by
  exact Step.called (callBytes displacement) loaded displacement
    (callBytes displacement).length (call_decodes displacement) result

def branchBytes (condition : Fin 16) (displacement : BitVec 32) : List UInt8 :=
  [15, UInt8.ofNat (128 + condition.val)] ++ displacementBytes displacement

theorem branch_decodes (condition : Fin 16) (displacement : BitVec 32) :
    decode (branchBytes condition displacement) = some (.branch condition displacement, 6) := by
  have bound : 128 + condition.val < 144 := by omega
  have byte : (UInt8.ofNat (128 + condition.val)).toNat = 128 + condition.val := by
    rw [UInt8.toNat_ofNat']
    exact Nat.mod_eq_of_lt (by omega)
  have byteExact : UInt8.ofNat (128 + condition.val) = 128 + UInt8.ofNat condition.val := by
    change UInt8.ofBitVec _ = UInt8.ofBitVec _
    congr 1
    apply BitVec.eq_of_toNat_eq
    simp [UInt8.ofNat, BitVec.toNat_add]
  have control : Control.decode
      (15 :: UInt8.ofNat (128 + condition.val) :: displacementBytes displacement) =
      some (.branch condition displacement, 6) := by
    simp only [Control.decode, byte]
    split <;> simp_all [displacement_decodes,
      show 128 + condition.val ≠ 5 by omega,
      show 128 + condition.val ≠ 11 by omega]
  have control' : Control.decode
      (15 :: (128 + UInt8.ofNat condition.val) :: displacementBytes displacement) =
      some (.branch condition displacement, 6) := by
    rw [← byteExact]
    exact control
  have dispEq : displacementBytes displacement =
      [UInt8.ofFin (wordBytes displacement).low,
        UInt8.ofFin (wordBytes displacement).second,
        UInt8.ofFin (wordBytes displacement).third,
        UInt8.ofFin (wordBytes displacement).high] := by
    simp [displacementBytes]
  have rangeFalse : ¬(144 ≤ 128 + condition.val ∧ 128 + condition.val < 160) := by omega
  have not182 : 128 + condition.val ≠ 182 := by omega
  have modulo : (128 + condition.val) % 256 = 128 + condition.val := by omega
  have not175 : 128 + condition.val ≠ 175 := by omega
  rw [show branchBytes condition displacement =
    [15, UInt8.ofNat (128 + condition.val)] ++ displacementBytes displacement by rfl]
  rw [dispEq] at control'
  rw [dispEq]
  simp [decode, X86.Register.Rex.decode?, decodeOpcode, escapedForm,
    Alu.ofOpcode?, byteExact, modulo, rangeFalse, not182, not175, control']

theorem test32_zero_condition (before : BitVec 64) (result : BitVec 32) (auxiliary : Bool) :
    condition (logical32Flags before result auxiliary) 4 = (result == 0) := by
  change (logical32Flags before result auxiliary).getLsbD 6 = (result == 0)
  unfold logical32Flags logicalFlags
  generalize evenParity result = parity
  generalize (result == 0) = zero
  generalize result.msb = sign
  cases parity <;> cases auxiliary <;> cases zero <;> cases sign <;>
    simp [arithmeticFlags]

theorem branch_step_rip (before after : State) (code : Fin 16) (displacement : BitVec 32)
    (loaded : CodeAt before.memory before.rip (branchBytes code displacement))
    (taken : condition before.flags code = true)
    (result : after = before.branch code displacement 6) :
    Step before after ∧
      after.rip = before.rip + BitVec.ofNat 64 6 + displacement.signExtend 64 := by
  refine ⟨?_, ?_⟩
  · exact Step.decoded (branchBytes code displacement) loaded
      (.branch code displacement) 6 (branch_decodes code displacement) result
  · simp [result, State.branch, taken]

theorem branch_step_rip_not_taken (before after : State) (code : Fin 16)
    (displacement : BitVec 32)
    (loaded : CodeAt before.memory before.rip (branchBytes code displacement))
    (not_taken : condition before.flags code = false)
    (result : after = before.branch code displacement 6) :
    Step before after ∧ after.rip = before.rip + BitVec.ofNat 64 6 + 0 := by
  refine ⟨?_, ?_⟩
  · exact Step.decoded (branchBytes code displacement) loaded
      (.branch code displacement) 6 (branch_decodes code displacement) result
  · simp [result, State.branch, not_taken]

def conditionalPrefix (thenBody : List UInt8) : List UInt8 :=
  testBytes .w32 0 0 ++ branchBytes ⟨4, by decide⟩ (BitVec.ofNat 32 (thenBody.length + 5))

def conditionalBytes (thenBody elseBody : List UInt8) : List UInt8 :=
  conditionalPrefix thenBody ++ thenBody ++ jumpBytes (BitVec.ofNat 32 elseBody.length) ++ elseBody

private theorem signExtend_ofNat_i32 {n : Nat} (h : n < 2 ^ 31) :
    (BitVec.ofNat 32 n).signExtend 64 = BitVec.ofNat 64 n := by
  apply BitVec.eq_of_toNat_eq
  have hs : (BitVec.ofNat 32 n).msb = false := by
    rw [BitVec.msb_eq_getMsbD_zero, BitVec.getMsbD_eq_getLsbD]
    simp only [show 0 < 32 by decide, decide_true, Bool.true_and,
      show 32 - 1 = 31 by decide]
    have hn : (BitVec.ofNat 32 n).toNat < 2 ^ 31 := by
      simpa [BitVec.toNat_ofNat, Nat.mod_eq_of_lt (show n < 2 ^ 32 by omega)] using h
    exact Nat.testBit_lt_two_pow hn
  simp [BitVec.toNat_signExtend, hs,
    Nat.mod_eq_of_lt (show n < 2 ^ 32 by omega),
    Nat.mod_eq_of_lt (show n < 2 ^ 64 by omega)]

theorem conditional_code_target_address {address : Address}
    {thenBody elseBody : List UInt8} (thenBound : thenBody.length + 5 < 2 ^ 31) :
    address + BitVec.ofNat 64 (conditionalPrefix thenBody).length +
        (BitVec.ofNat 32 (thenBody.length + 5)).signExtend 64 =
      address + BitVec.ofNat 64
        (conditionalPrefix thenBody ++ thenBody ++ jumpBytes
          (BitVec.ofNat 32 elseBody.length)).length := by
  rw [signExtend_ofNat_i32 thenBound]
  simp [conditionalPrefix, branchBytes, jumpBytes, displacementBytes,
    List.length_append, BitVec.ofNat_add, BitVec.add_assoc]
  rw [← BitVec.add_assoc, BitVec.add_comm (6#64), BitVec.add_assoc]
  rw [show (6#64 + 5#64) = 11#64 by decide]

theorem conditional_code_targets {memory : Memory} {address : Address}
    {thenBody elseBody : List UInt8} (thenBound : thenBody.length + 5 < 2 ^ 31)
    (_elseBound : elseBody.length < 2 ^ 31)
    (loaded : CodeAt memory address (conditionalBytes thenBody elseBody)) :
    CodeAt memory (address + BitVec.ofNat 64 (conditionalPrefix thenBody).length)
        (thenBody ++ jumpBytes (BitVec.ofNat 32 elseBody.length) ++ elseBody) ∧
      CodeAt memory (address + BitVec.ofNat 64 (conditionalPrefix thenBody).length +
        (BitVec.ofNat 32 (thenBody.length + 5)).signExtend 64) elseBody := by
  have dlen (d : BitVec 32) : (displacementBytes d).length = 4 := by simp [displacementBytes]
  have plen : (conditionalPrefix thenBody).length = 8 := by
    simp [conditionalPrefix, branchBytes, dlen] <;> decide
  have exact : CodeAt memory address
      (conditionalPrefix thenBody ++ thenBody ++ jumpBytes
        (BitVec.ofNat 32 elseBody.length) ++ elseBody) := by
    simpa [conditionalBytes, List.append_assoc] using loaded
  have fall := exact.suffix (first := conditionalPrefix thenBody)
    (rest := thenBody ++ jumpBytes (BitVec.ofNat 32 elseBody.length) ++ elseBody)
  have target := exact.suffix
    (first := conditionalPrefix thenBody ++ thenBody ++ jumpBytes
      (BitVec.ofNat 32 elseBody.length)) (rest := elseBody)
  refine ⟨fall, ?_⟩
  rw [conditional_code_target_address thenBound]
  exact target

theorem conditional_code_targets_suffix {memory : Memory} {address : Address}
    {thenBody elseBody suffix : List UInt8} (thenBound : thenBody.length + 5 < 2 ^ 31)
    (_elseBound : elseBody.length < 2 ^ 31)
    (loaded : CodeAt memory address (conditionalBytes thenBody elseBody ++ suffix)) :
    CodeAt memory (address + BitVec.ofNat 64 (conditionalPrefix thenBody).length)
        (thenBody ++ jumpBytes (BitVec.ofNat 32 elseBody.length) ++ elseBody ++ suffix) ∧
      CodeAt memory (address + BitVec.ofNat 64 (conditionalPrefix thenBody).length +
        (BitVec.ofNat 32 (thenBody.length + 5)).signExtend 64) (elseBody ++ suffix) := by
  have exact : CodeAt memory address
      (conditionalPrefix thenBody ++ thenBody ++
        jumpBytes (BitVec.ofNat 32 elseBody.length) ++ elseBody ++ suffix) := by
    simpa [conditionalBytes, List.append_assoc] using loaded
  have exact' : CodeAt memory address
      ((conditionalPrefix thenBody ++ thenBody ++
        jumpBytes (BitVec.ofNat 32 elseBody.length)) ++ (elseBody ++ suffix)) := by
    simpa [List.append_assoc] using exact
  have fall := exact.suffix (first := conditionalPrefix thenBody)
    (rest := thenBody ++ jumpBytes (BitVec.ofNat 32 elseBody.length) ++ elseBody ++ suffix)
  have target := exact'.suffix
    (first := conditionalPrefix thenBody ++ thenBody ++
      jumpBytes (BitVec.ofNat 32 elseBody.length)) (rest := elseBody ++ suffix)
  refine ⟨fall, ?_⟩
  rw [conditional_code_target_address thenBound]
  exact target

example {memory : Memory} {address : Address} {suffix : List UInt8}
    (loaded : CodeAt memory address (conditionalBytes [] [] ++ suffix)) :
    CodeAt memory (address + BitVec.ofNat 64 (conditionalPrefix ([] : List UInt8)).length)
        (jumpBytes (BitVec.ofNat 32 ([] : List UInt8).length) ++ suffix) ∧
      CodeAt memory (address + BitVec.ofNat 64 (conditionalPrefix ([] : List UInt8)).length +
        (BitVec.ofNat 32 (([] : List UInt8).length + 5)).signExtend 64) suffix := by
  simpa using conditional_code_targets_suffix (thenBound := by decide)
    (by decide) loaded

example : branchBytes ⟨4, by decide⟩ (BitVec.ofNat 32 5) = [15, 132, 5, 0, 0, 0] := by decide
example : branchBytes ⟨4, by decide⟩ (BitVec.ofNat 32 5) ≠ [15, 132, 4, 0, 0, 0] := by decide
example : decode (branchBytes ⟨4, by decide⟩ (BitVec.ofNat 32 5)) =
    some (.branch ⟨4, by decide⟩ (BitVec.ofNat 32 5), 6) :=
  branch_decodes _ _

example (before after : State) (loaded : CodeAt before.memory before.rip
    (branchBytes ⟨4, by decide⟩ (BitVec.ofNat 32 5)))
    (taken : condition before.flags 4 = true)
    (result : after = before.branch 4 (BitVec.ofNat 32 5) 6) :
    after.rip = before.rip + BitVec.ofNat 64 6 + (BitVec.ofNat 32 5).signExtend 64 :=
  (branch_step_rip before after 4 _ loaded taken result).2

example (before after : State) (loaded : CodeAt before.memory before.rip
    (branchBytes ⟨4, by decide⟩ (BitVec.ofNat 32 5)))
    (not_taken : condition before.flags 4 = false)
    (result : after = before.branch 4 (BitVec.ofNat 32 5) 6) :
    after.rip = before.rip + BitVec.ofNat 64 6 + 0 :=
  (branch_step_rip_not_taken before after 4 _ loaded not_taken result).2

end Lanius.X86.Machine
