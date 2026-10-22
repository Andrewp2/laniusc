import Lanius.X86.Machine.ControlEncoding

namespace Lanius.X86.Machine

open Lanius.X86

/-! A while loop is laid out as the condition code, then the guard (TEST and
    JE over the body), then the body, then a JMP back to the start of the
    condition code, so every iteration re-evaluates the condition. -/

def loopDistance (condition body : List UInt8) : Nat :=
  condition.length + (conditionalPrefix body).length + body.length + (jumpBytes 0).length

def loopBackDisplacement (condition body : List UInt8) : BitVec 32 :=
  -BitVec.ofNat 32 (loopDistance condition body)

/-- The bytes that follow the condition code. -/
def loopBytes (condition body : List UInt8) : List UInt8 :=
  conditionalPrefix body ++ body ++ jumpBytes (loopBackDisplacement condition body)

theorem loop_back_target_address {address : Address} {condition body : List UInt8}
    (bound : loopDistance condition body < 2 ^ 31) :
    address + BitVec.ofNat 64 condition.length +
        BitVec.ofNat 64 (conditionalPrefix body).length +
        BitVec.ofNat 64 body.length +
        BitVec.ofNat 64 (jumpBytes (loopBackDisplacement condition body)).length +
        (loopBackDisplacement condition body).signExtend 64 = address := by
  have negExtend {n : Nat} (h : n < 2 ^ 31) :
      (-BitVec.ofNat 32 n).signExtend 64 = -BitVec.ofNat 64 n := by
    simp only [BitVec.signExtend]
    have bmod : (- (n : Int)).bmod (2 ^ 32) = - (n : Int) := by
      apply Int.bmod_eq_of_le <;> omega
    have natBmod : (n : Int).bmod (2 ^ 32) = n := by
      apply Int.bmod_eq_of_le <;> omega
    rw [BitVec.toInt_neg, BitVec.toInt_ofNat', natBmod, bmod, BitVec.ofInt_neg]
    rfl
  rw [show loopBackDisplacement condition body =
    -BitVec.ofNat 32 (loopDistance condition body) by rfl]
  rw [negExtend bound]
  simp [loopDistance, jumpBytes, displacementBytes, BitVec.ofNat_add,
    BitVec.add_assoc, BitVec.add_right_neg]

theorem loop_code_targets_suffix {memory : Memory} {address : Address}
    {condition body suffix : List UInt8} (bound : loopDistance condition body < 2 ^ 31)
    (loaded : CodeAt memory address (condition ++ loopBytes condition body ++ suffix)) :
    CodeAt memory (address + BitVec.ofNat 64 condition.length +
        BitVec.ofNat 64 (conditionalPrefix body).length)
        (body ++ jumpBytes (loopBackDisplacement condition body) ++ suffix) ∧
      CodeAt memory (address + BitVec.ofNat 64 condition.length +
        BitVec.ofNat 64 (conditionalPrefix body).length +
        BitVec.ofNat 64 body.length +
          BitVec.ofNat 64 (jumpBytes (loopBackDisplacement condition body)).length +
          (loopBackDisplacement condition body).signExtend 64) condition := by
  have exact : CodeAt memory address
      (condition ++ conditionalPrefix body ++ body ++
        jumpBytes (loopBackDisplacement condition body) ++ suffix) := by
    simpa [loopBytes, List.append_assoc] using loaded
  have split : CodeAt memory address ((condition ++ conditionalPrefix body) ++
      (body ++ jumpBytes (loopBackDisplacement condition body) ++ suffix)) := by
    simpa [List.append_assoc] using exact
  have bodyAt := split.suffix
  refine ⟨?_, ?_⟩
  · simpa [List.length_append, BitVec.ofNat_add, BitVec.add_assoc, List.append_assoc]
      using bodyAt
  have prefixAt : CodeAt memory address condition := by
    apply CodeAt.prefix (first := condition)
      (rest := conditionalPrefix body ++ body ++
        jumpBytes (loopBackDisplacement condition body) ++ suffix)
    simpa [List.append_assoc] using exact
  rw [loop_back_target_address bound]
  exact prefixAt

theorem loop_guard_steps (before middle after : State) (body : List UInt8)
    (loaded : CodeAt before.memory before.rip (conditionalPrefix body))
    (testResult : middle = before.test32 0 0 (before.flags.getLsbD 4)
      (testBytes .w32 0 0).length)
    (branchResult : after = middle.branch 4
      (BitVec.ofNat 32 (body.length + 5)) 6)
    (taken : condition middle.flags 4 = true) :
    Steps 2 before after ∧
      after.rip = before.rip + BitVec.ofNat 64 (conditionalPrefix body).length +
        (BitVec.ofNat 32 (body.length + 5)).signExtend 64 := by
  have testLoaded : CodeAt before.memory before.rip (testBytes .w32 0 0) := by
    simpa [conditionalPrefix] using loaded.prefix
  have branchLoaded : CodeAt middle.memory middle.rip
      (branchBytes ⟨4, by decide⟩ (BitVec.ofNat 32 (body.length + 5))) := by
    simpa [testResult, State.test32, State.test, conditionalPrefix] using loaded.suffix
  have first : Step before middle :=
    test_step .w32 before middle 0 0 testLoaded (before.flags.getLsbD 4) testResult
  have second := branch_step_rip middle after 4 _ branchLoaded taken branchResult
  refine ⟨?_, ?_⟩
  · simpa using Steps.cons first (Steps.cons second.1 (Steps.refl after))
  · simpa [testResult, State.test32, State.test, conditionalPrefix,
      List.length_append, branchBytes, displacementBytes, BitVec.ofNat_add,
      BitVec.add_assoc] using second.2

theorem loop_guard_decodes (body : List UInt8) :
    decode (testBytes .w32 0 0) = some (.test32 0 0, 2) ∧
      decode (branchBytes ⟨4, by decide⟩ (BitVec.ofNat 32 (body.length + 5))) =
        some (.branch ⟨4, by decide⟩ (BitVec.ofNat 32 (body.length + 5)), 6) :=
  ⟨test_decodes _ _ _, branch_decodes _ _⟩

theorem loop_back_jump_step_rip (before after : State) (condition body : List UInt8)
    (loaded : CodeAt before.memory before.rip
      (jumpBytes (loopBackDisplacement condition body)))
    (result : after = before.jump (loopBackDisplacement condition body)
      (jumpBytes (loopBackDisplacement condition body)).length) :
    Step before after ∧
      after.rip = before.rip + BitVec.ofNat 64
        (jumpBytes (loopBackDisplacement condition body)).length +
        (loopBackDisplacement condition body).signExtend 64 := by
  refine ⟨jump_step before after _ loaded result, ?_⟩
  simp [result, State.jump]

example : loopBytes [] [] = [133, 192, 15, 132, 5, 0, 0, 0, 233, 243, 255, 255, 255] := by decide
example : loopBytes [] [] ≠ [133, 192, 15, 132, 5, 0, 0, 0, 233, 242, 255, 255, 255] := by decide
-- One byte of condition code moves the jump back one byte further.
example : loopBytes [144] [] = [133, 192, 15, 132, 5, 0, 0, 0, 233, 242, 255, 255, 255] := by decide

example {memory : Memory} {address : Address} {suffix : List UInt8}
    (loaded : CodeAt memory address ([144] ++ loopBytes [144] [] ++ suffix)) :
    CodeAt memory address [144] := by
  have target := (loop_code_targets_suffix (condition := [144]) (body := [])
    (bound := by decide) loaded).2
  rw [loop_back_target_address (address := address) (condition := [144]) (body := [])
    (by decide)] at target
  exact target

end Lanius.X86.Machine
