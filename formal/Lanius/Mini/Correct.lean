import Lanius.Mini.Simulation

/-! Milestone 1, the top-level theorem: a compiled function, entered by a near
call, returns what the source function returns. -/

namespace Lanius.Mini
open Lanius.X86.Machine

/-- The code image is apart from the stack window the function uses: from its
deepest slot up to and including the return address at rsp. -/
def StackApart (s : State) (slots length : Nat) : Prop :=
  ∀ index, index < length → ∀ offset, offset < 8 * slots + 24 →
    s.rip + BitVec.ofNat 64 index ≠
      s.registers rspRegister - BitVec.ofNat 64 (8 * slots + 16) + BitVec.ofNat 64 offset

theorem compile_correct (func : Func) (code : Code) (compiled : compileFunc func = some code)
    (args : Env) (value : BitVec 32) (returns : func.run args = some value) (s : State)
    (loaded : CodeAt s.memory s.rip code.image)
    (apart : StackApart s code.slots code.image.length)
    (locals : ∀ index, index < func.locals →
      read32 s.memory (s.registers rspRegister - BitVec.ofNat 64 (8 * index + 16)) = args index) :
    ∃ n s', Steps n s s' ∧
      s'.rip = read64 s.memory (s.registers rspRegister) ∧
      s'.registers rspRegister = s.registers rspRegister + 8 ∧
      s'.registers rbpRegister = s.registers rbpRegister ∧
      (s'.registers 0).setWidth 32 = value ∧
      ∀ register, ¬Scratch register → s'.registers register = s.registers register := by
  obtain ⟨localsFit, limit, fits⟩ := compileFunc_fits func code compiled
  have frameBound : code.slots ≤ 2 ^ 24 := limit
  have image : CodeAt s.memory s.rip (framePrologueBytes code.slots ++ encodeAll code.instrs) := loaded
  have imageLength : code.image.length =
      (framePrologueBytes code.slots).length + (encodeAll code.instrs).length := by
    simp only [Code.image, List.length_append]
  let rsp := s.registers rspRegister
  let frame : Frame :=
    { rbp := rsp - 8
      slots := code.slots
      saved := s.registers rbpRegister
      returnAddress := read64 s.memory rsp
      preserved := s.registers }
  let entered := prologueState s code.slots
  have pushApart : ∀ index, index < code.image.length → ∀ lane : Fin 8,
      s.rip + BitVec.ofNat 64 index ≠ rsp - 8 + BitVec.ofNat 64 lane.val := by
    intro index bound lane
    have apartLane := apart index bound (8 * code.slots + 8 + lane.val) (by omega)
    have same : rsp - BitVec.ofNat 64 (8 * code.slots + 16) +
        BitVec.ofNat 64 (8 * code.slots + 8 + lane.val) = rsp - 8 + BitVec.ofNat 64 lane.val := by
      have := lane.isLt
      bv_omega
    rwa [same] at apartLane
  have steps : Steps 4 s entered := by
    apply framePrologue_steps code.slots s image.prefix
    intro index bound lane
    have pushed := pushApart ((pushBytes rbpRegister).length + index) (by
      simp only [imageLength, framePrologueBytes, List.length_append] at bound ⊢; omega) lane
    simpa [BitVec.ofNat_add, BitVec.add_assoc] using pushed
  have memory : entered.memory = write64 s.memory (rsp - 8) (s.registers rbpRegister) := by
    simp [entered, prologueState, State.alu64, State.alu, State.immediate32, State.move64,
      State.push64, rsp, rspRegister, rbpRegister]
  have slotAddress (slot : Nat) (bound : slot < frameLimit) :
      frameSlotAddress (rsp - 8) slot = rsp - BitVec.ofNat 64 (8 * slot + 16) := by
    rw [slotAddress_eq _ bound]
    unfold frameLimit at bound
    bv_omega
  let start : Machine :=
    { acc := (entered.registers 0).setWidth 32
      slots := fun slot => read32 entered.memory (frameSlotAddress frame.rbp slot) }
  have rel : Rel frame entered start := by
    refine ⟨?_, rfl, fun _ _ => rfl, ?_, ?_, ?_⟩
    · simp [entered, frame, prologueState, State.alu64, State.alu, State.immediate32, State.move64,
        State.push64, rsp, rspRegister, rbpRegister, r11Register]
    · simp only [frame, memory, read64_write64]
    · simp only [frame, memory, show rsp - 8 + 8 = rsp by bv_omega]
      apply read64_frame
      intro i j
      have := i.isLt; have := j.isLt
      bv_omega
    · intro register other
      obtain ⟨-, -, four, five, eleven⟩ := not_scratch other
      simp [entered, frame, prologueState, State.alu64, State.alu, State.immediate32, State.move64,
        State.push64, rspRegister, rbpRegister, r11Register, four, five, eleven]
  have at_ : At frame entered (encodeAll code.instrs) := by
    constructor
    · apply framePrologue_tail code.slots s _ image
      intro index bound lane
      have pushed := pushApart ((framePrologueBytes code.slots).length + index) (by omega) lane
      simpa [BitVec.ofNat_add, BitVec.add_assoc] using pushed
    · rw [framePrologue_rip]
      intro index bound slot inFrame lane
      have inSlots : slot < code.slots := inFrame
      have apartSlot := apart ((framePrologueBytes code.slots).length + index) (by omega)
        (8 * (code.slots - slot) + lane.val) (by omega)
      have same : rsp - BitVec.ofNat 64 (8 * code.slots + 16) +
          BitVec.ofNat 64 (8 * (code.slots - slot) + lane.val) =
          frameSlotAddress frame.rbp slot + BitVec.ofNat 64 lane.val := by
        rw [slotAddress (slot := slot) (by unfold frameLimit; omega)]
        have := lane.isLt
        bv_omega
      rw [same, BitVec.ofNat_add, ← BitVec.add_assoc] at apartSlot
      exact apartSlot
  have agree : Agree func.locals args start := by
    intro index below
    have bound : index < frameLimit := by unfold frameLimit; omega
    show read32 entered.memory (frameSlotAddress (rsp - 8) index) = args index
    rw [memory, slotAddress index bound, ← locals index below]
    apply read32_congr
    intro lane
    apply write64_frame
    intro other
    have := lane.isLt; have := other.isLt
    bv_omega
  have ran : Instr.run code.instrs start = some value :=
    (compileFunc_correct func code compiled args start agree).trans returns
  obtain ⟨n, final, body, returned⟩ := encodeAll_simulates limit code.instrs fits rel at_ ran
  refine ⟨_, final, steps.trans body, returned.rip, ?_, returned.rbp, returned.value,
    returned.preserved⟩
  rw [returned.rsp]
  show rsp - 8 + 16 = rsp + 8
  bv_omega

end Lanius.Mini
