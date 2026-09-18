import Lanius.X86.Frame.Execution

namespace Lanius.X86.Frame

open Lanius.Semantics

/-- The exact frame protocol used by `backend::compile::function` and
`backend::frame::return_value`. R11 is caller-saved scratch, not an argument
register. The imm32 is patched after lowering establishes the frame size. -/
def allocationBytes (amount : Nat) : List UInt8 := [65, 187] ++ i32Bytes amount
def prologue (amount : Nat) : List UInt8 := [85] ++ [72, 137, 229] ++ allocationBytes amount ++ [76, 41, 220]
def epilogue : List UInt8 := [72, 137, 236] ++ [93] ++ [195]

def setup (before : Machine.State) (amount : Nat) : Machine.State :=
  (((before.push64 5 1).move64 5 4 3).immediate32 11 (BitVec.ofNat 32 amount) 6).subtract64 4 11 3

def teardown (before : Machine.State) : Machine.State :=
  ((before.move64 4 5 3).pop64 5 1).returnNear

theorem allocation_length (amount : Nat) : (allocationBytes amount).length = 6 := by
  simp [allocationBytes, i32Bytes]

theorem allocation_decodes (amount : Nat) :
    Machine.decode (allocationBytes amount) = some (.immediate32 11 (BitVec.ofNat 32 amount), 6) := by
  have word : Control.displacement? (i32Bytes amount) = some (BitVec.ofNat 32 amount) := by
    simpa using Control.displacement?_i32Bytes amount []
  simp [allocationBytes, Machine.decode, Machine.decodeOpcode, X86.Register.Rex.decode?,
    word, Machine.extendRegister]

/-- The saved RBP write preserves every instruction to follow. Instruction
fetch is proved at each successive RIP, not assumed from the final state. -/
theorem prologue_steps (before : Machine.State) (amount : Nat) (body : List UInt8)
    (loaded : Machine.CodeAt before.memory before.rip (prologue amount ++ body))
    (disjoint : ∀ index, index < (prologue amount ++ body).length → ∀ lane : Fin 8,
      before.rip + BitVec.ofNat 64 index ≠ before.registers 4 - 8 + BitVec.ofNat 64 lane.val) :
    Machine.Steps 4 before (setup before amount) ∧
      Machine.CodeAt (setup before amount).memory (setup before amount).rip body := by
  let one := before.push64 5 1
  let two := one.move64 5 4 3
  let three := two.immediate32 11 (BitVec.ofNat 32 amount) 6
  have code : Machine.CodeAt before.memory before.rip
      ([85] ++ ([72, 137, 229] ++ (allocationBytes amount ++ ([76, 41, 220] ++ body)))) := by
    simpa only [prologue, List.append_assoc] using loaded
  have preserved := loaded.write64 (before.registers 5) disjoint
  have patched : Machine.CodeAt (Machine.write64 before.memory (before.registers 4 - 8) (before.registers 5)) before.rip
      ([85] ++ ([72, 137, 229] ++ (allocationBytes amount ++ ([76, 41, 220] ++ body)))) := by
    simpa only [prologue, List.append_assoc] using preserved
  have next1 : Machine.CodeAt one.memory one.rip
      ([72, 137, 229] ++ (allocationBytes amount ++ ([76, 41, 220] ++ body))) := patched.suffix
  have next2 : Machine.CodeAt two.memory two.rip (allocationBytes amount ++ ([76, 41, 220] ++ body)) := next1.suffix
  have next3 : Machine.CodeAt three.memory three.rip ([76, 41, 220] ++ body) := by
    simpa [three, Machine.State.immediate32, allocation_length] using next2.suffix
  refine ⟨.cons (.decoded [85] code.prefix (.push64 5) 1 rfl rfl)
    (.cons (.decoded [72, 137, 229] next1.prefix (.move64 5 4) 3 rfl rfl)
      (.cons (.decoded (allocationBytes amount) next2.prefix _ 6 (allocation_decodes amount) rfl)
        (.cons (.decoded [76, 41, 220] next3.prefix (.subtract64 4 11) 3 rfl rfl) (.refl _)))), next3.suffix⟩

theorem setup_fields (before : Machine.State) (amount : Nat) (bounded : amount < 4294967296) :
    (setup before amount).registers 5 = before.registers 4 - 8 ∧
    (setup before amount).registers 4 = before.registers 4 - 8 - BitVec.ofNat 64 amount ∧
    (setup before amount).registers 11 = BitVec.ofNat 64 amount ∧
    (∀ register, register ≠ 4 → register ≠ 5 → register ≠ 11 →
      (setup before amount).registers register = before.registers register) ∧
    (setup before amount).memory = Machine.write64 before.memory (before.registers 4 - 8) (before.registers 5) := by
  have widened : (BitVec.ofNat 32 amount).setWidth 64 = BitVec.ofNat 64 amount := by
    apply BitVec.eq_of_toNat_eq
    simp only [BitVec.toNat_setWidth, BitVec.toNat_ofNat]
    rw [Nat.mod_eq_of_lt bounded]
  refine ⟨?_, ?_, ?_, ?_, rfl⟩
  · simp [setup, Machine.State.subtract64, Machine.State.immediate32, Machine.State.move64, Machine.State.push64]
  · simp [setup, Machine.State.subtract64, Machine.State.immediate32, Machine.State.move64, Machine.State.push64, widened]
  · simp [setup, Machine.State.subtract64, Machine.State.immediate32, widened]
  · intro register stack frame scratch
    simp [setup, Machine.State.subtract64, Machine.State.immediate32, Machine.State.move64, Machine.State.push64,
      stack, frame, scratch]

theorem setup_direction (before : Machine.State) (amount : Nat) :
    (setup before amount).flags.getLsbD 10 = before.flags.getLsbD 10 := by
  dsimp only [setup, Machine.State.subtract64, Machine.State.immediate32, Machine.State.move64, Machine.State.push64]
  exact Machine.subtractFlags_direction _ _ _

theorem epilogue_steps (before : Machine.State)
    (loaded : Machine.CodeAt before.memory before.rip epilogue) :
    Machine.Steps 3 before (teardown before) := by
  have code : Machine.CodeAt before.memory before.rip ([72, 137, 236] ++ ([93] ++ [195])) := loaded
  let one := before.move64 4 5 3
  let two := one.pop64 5 1
  have next1 : Machine.CodeAt one.memory one.rip ([93] ++ [195]) := code.suffix
  have next2 : Machine.CodeAt two.memory two.rip [195] := next1.suffix
  exact .cons (.decoded [72, 137, 236] code.prefix (.move64 4 5) 3 rfl rfl)
    (.cons (.decoded [93] next1.prefix (.pop64 5) 1 rfl rfl)
      (.cons (.decoded [195] next2 .returnNear 1 rfl rfl) (.refl _)))

/-- Teardown restores the saved frame pointer, consumes the return address,
and preserves the result and every register except RSP/RBP. Stack bytes are
not erased: ownership/liveness changes, not physical memory contents. -/
theorem teardown_fields (before : Machine.State) :
    (teardown before).registers 5 = Machine.read64 before.memory (before.registers 5) ∧
    (teardown before).registers 4 = before.registers 5 + 16 ∧
    (teardown before).rip = Machine.read64 before.memory (before.registers 5 + 8) ∧
    (∀ register, register ≠ 4 → register ≠ 5 → (teardown before).registers register = before.registers register) ∧
    (teardown before).memory = before.memory ∧ (teardown before).flags = before.flags := by
  refine ⟨?_, ?_, ?_, ?_, rfl, rfl⟩
  · simp [teardown, Machine.State.returnNear, Machine.State.pop64, Machine.State.move64]
  · simp [teardown, Machine.State.returnNear, Machine.State.pop64, Machine.State.move64, BitVec.add_assoc]
  · simp [teardown, Machine.State.returnNear, Machine.State.pop64, Machine.State.move64]
  · intro register stack frame
    simp [teardown, Machine.State.returnNear, Machine.State.pop64, Machine.State.move64, stack, frame]

end Lanius.X86.Frame
