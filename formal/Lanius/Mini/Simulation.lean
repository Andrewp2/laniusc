import Lanius.Mini.Bytes
import Lanius.Mini.CompileCorrect

/-! The x86 bytes of each abstract instruction simulate it. One relation holds
between an x86 state and an abstract machine throughout a function body. -/

namespace Lanius.Mini
open Lanius.X86.Machine

/-- Registers compiled code may change: rax, rcx, rsp, rbp, r11. -/
def Scratch (register : Register) : Prop :=
  register = 0 ∨ register = rcxRegister ∨ register = rspRegister ∨ register = rbpRegister ∨
    register = r11Register

structure Frame where
  rbp : BitVec 64
  slots : Nat
  /-- The caller's rbp, saved at `rbp`. -/
  saved : BitVec 64
  /-- Stored at `rbp + 8` by the call. -/
  returnAddress : BitVec 64
  /-- The caller's registers. -/
  preserved : Register → BitVec 64

/-- The x86 state holds the abstract machine in this frame. -/
structure Rel (frame : Frame) (s : State) (m : Machine) : Prop where
  rbp : s.registers rbpRegister = frame.rbp
  acc : (s.registers 0).setWidth 32 = m.acc
  slots : ∀ slot, slot < frame.slots → read32 s.memory (frameSlotAddress frame.rbp slot) = m.slots slot
  saved : read64 s.memory frame.rbp = frame.saved
  returnAddress : read64 s.memory (frame.rbp + 8) = frame.returnAddress
  preserved : ∀ register, ¬Scratch register → s.registers register = frame.preserved register

/-- The code bytes from `code` on are apart from every frame slot. -/
def Separate (frame : Frame) (code : BitVec 64) (length : Nat) : Prop :=
  ∀ index, index < length → ∀ slot, slot < frame.slots → ∀ lane : Fin 4,
    code + BitVec.ofNat 64 index ≠ frameSlotAddress frame.rbp slot + BitVec.ofNat 64 lane.val

/-- The remaining code is at rip, apart from the frame. -/
structure At (frame : Frame) (s : State) (bytes : List UInt8) : Prop where
  loaded : CodeAt s.memory s.rip bytes
  separate : Separate frame s.rip bytes.length

/-- The function has returned `value` to its caller. -/
structure Returned (frame : Frame) (s : State) (value : BitVec 32) : Prop where
  rip : s.rip = frame.returnAddress
  rsp : s.registers rspRegister = frame.rbp + 16
  rbp : s.registers rbpRegister = frame.saved
  value : (s.registers 0).setWidth 32 = value
  preserved : ∀ register, ¬Scratch register → s.registers register = frame.preserved register

variable {frame : Frame} {s s' : State} {m : Machine} {first rest : List UInt8} {slot : Nat}
  {value : BitVec 32}

theorem CodeAt.middle {memory : Memory} {address : BitVec 64} {middle : List UInt8}
    (loaded : CodeAt memory address (first ++ middle ++ rest)) :
    CodeAt memory (address + BitVec.ofNat 64 first.length) middle := by
  rw [List.append_assoc] at loaded
  exact loaded.suffix.prefix

theorem Separate.suffix {code : BitVec 64} (separate : Separate frame code (first ++ rest).length) :
    Separate frame (code + BitVec.ofNat 64 first.length) rest.length := by
  intro index bound slot inFrame lane
  have apart := separate (first.length + index) (by simp only [List.length_append]; omega) slot inFrame lane
  simpa only [BitVec.ofNat_add, BitVec.add_assoc] using apart

/-- An instruction that leaves memory alone moves `At` past its bytes. -/
theorem At.advance (at_ : At frame s (first ++ rest)) (memory : s'.memory = s.memory)
    (rip : s'.rip = s.rip + BitVec.ofNat 64 first.length) : At frame s' rest where
  loaded := by rw [memory, rip]; exact at_.loaded.suffix
  separate := by rw [rip]; exact at_.separate.suffix

theorem not_scratch {register : Register} (other : ¬Scratch register) :
    register ≠ 0 ∧ register ≠ 1 ∧ register ≠ 4 ∧ register ≠ 5 ∧ register ≠ 11 := by
  simp only [Scratch, rcxRegister, rspRegister, rbpRegister, r11Register, not_or] at other
  exact other

/-- An instruction that writes only rax and rcx keeps the relation, given the new accumulator. -/
theorem Rel.accumulate (rel : Rel frame s m) (memory : s'.memory = s.memory)
    (registers : ∀ register, register ≠ 0 → register ≠ 1 → s'.registers register = s.registers register)
    (acc : (s'.registers 0).setWidth 32 = value) : Rel frame s' { m with acc := value } where
  rbp := (registers _ (by decide) (by decide)).trans rel.rbp
  acc := acc
  slots := by rw [memory]; exact rel.slots
  saved := by rw [memory]; exact rel.saved
  returnAddress := by rw [memory]; exact rel.returnAddress
  preserved register other := by
    obtain ⟨zero, one, -⟩ := not_scratch other
    rw [registers register zero one]
    exact rel.preserved register other

theorem imm_simulates (rel : Rel frame s m) (at_ : At frame s ((Instr.imm value).encode ++ rest)) :
    ∃ n s', Steps n s s' ∧ Rel frame s' ((Instr.imm value).step m) ∧ At frame s' rest := by
  let s' := s.immediate32 0 value (immediateBytes .w32 0 value 0).length
  have step : Step s s' := immediate_step s s' .w32 0 value 0 at_.loaded.prefix rfl
  refine ⟨1, s', .cons step (.refl _), ?_, at_.advance rfl rfl⟩
  refine Rel.accumulate (s' := s') rel rfl ?_ ?_
  · intro register zero _
    simp only [s', State.immediate32, if_neg zero]
  · simp [s', State.immediate32]

theorem load_simulates (rel : Rel frame s m) (inFrame : slot < frame.slots)
    (at_ : At frame s ((Instr.load slot).encode ++ rest)) :
    ∃ n s', Steps n s s' ∧ Rel frame s' ((Instr.load slot).step m) ∧ At frame s' rest := by
  let s' := s.load32 0 rbpRegister (BitVec.ofInt 32 (frameDisplacement slot)) (frameLoadBytes slot).length
  have step : Step s s' := frameLoad_step s s' slot at_.loaded.prefix rfl
  refine ⟨1, s', .cons step (.refl _), ?_, at_.advance rfl rfl⟩
  refine Rel.accumulate (s' := s') rel rfl ?_ ?_
  · intro register zero _
    simp only [s', State.load32, State.immediate32, if_neg zero]
  · have slotValue := rel.slots slot inFrame
    simp only [frameSlotAddress] at slotValue
    simp [s', State.load32, State.immediate32, rel.rbp, slotValue]

theorem neg_simulates (rel : Rel frame s m) (at_ : At frame s (Instr.neg.encode ++ rest)) :
    ∃ n s', Steps n s s' ∧ Rel frame s' (Instr.neg.step m) ∧ At frame s' rest := by
  let s' := s.negate 32 0 s.flags (negateBytes .w32 0).length
  have step : Step s s' := negate_step .w32 s s' 0 at_.loaded.prefix s.flags rfl
  refine ⟨1, s', .cons step (.refl _), ?_, at_.advance rfl rfl⟩
  refine Rel.accumulate (s' := s') rel rfl ?_ ?_
  · intro register zero _
    simp only [s', State.negate, if_neg zero]
  · simp [s', State.negate, ← rel.acc]

theorem store_simulates (rel : Rel frame s m) (limit : frame.slots ≤ frameLimit)
    (inFrame : slot < frame.slots) (at_ : At frame s ((Instr.store slot).encode ++ rest)) :
    ∃ n s', Steps n s s' ∧ Rel frame s' ((Instr.store slot).step m) ∧ At frame s' rest := by
  let s' := s.store32 0 rbpRegister (BitVec.ofInt 32 (frameDisplacement slot)) (frameStoreBytes slot).length
  have step : Step s s' := frameStore_step s s' slot at_.loaded.prefix rfl
  have address : s.registers rbpRegister + (BitVec.ofInt 32 (frameDisplacement slot)).signExtend 64 =
      frameSlotAddress frame.rbp slot := by rw [rel.rbp]; rfl
  have memory : s'.memory = write32 s.memory (frameSlotAddress frame.rbp slot) m.acc := by
    simp only [s', State.store32, address, rel.acc]
  refine ⟨1, s', .cons step (.refl _), ?_, ?_⟩
  · refine ⟨rel.rbp, rel.acc, ?_, ?_, ?_, rel.preserved⟩
    · intro other otherInFrame
      rw [memory]
      simp only [Instr.step, Machine.store]
      split
      · rename_i same
        rw [same, read32_write32]
      · rename_i different
        rw [read32_frame _ _ _ _ (slots_disjoint frame.rbp different (by omega) (by omega))]
        exact rel.slots other otherInFrame
    · rw [memory, read64_write32_frame _ _ _ _ (saved_disjoint frame.rbp (slot := slot) (by omega))]
      exact rel.saved
    · rw [memory, read64_write32_frame _ _ _ _ (return_disjoint frame.rbp (slot := slot) (by omega))]
      exact rel.returnAddress
  · constructor
    · rw [memory]
      apply CodeAt.write32 at_.loaded.suffix
      intro index bound lane
      have apart := at_.separate ((Instr.store slot).encode.length + index)
        (by simp only [List.length_append]; omega) slot inFrame lane
      simpa only [BitVec.ofNat_add, BitVec.add_assoc] using apart
    · exact at_.separate.suffix

/-- `mov ecx, eax; mov eax, [slot]; op eax, ecx` -/
theorem alu_simulates (operation : Alu) (rel : Rel frame s m) (inFrame : slot < frame.slots)
    (at_ : At frame s (frameAluBytes slot operation ++ rest)) :
    ∃ n s', Steps n s s' ∧
      Rel frame s' { m with acc := operation.result (m.slots slot) m.acc } ∧ At frame s' rest := by
  let moved := s.move32 rcxRegister 0 rightToRcxBytes.length
  let loadedLeft := moved.load32 0 rbpRegister
    (BitVec.ofInt 32 (frameDisplacement slot)) (frameLoadBytes slot).length
  let s' := loadedLeft.alu32 operation 0 rcxRegister false (aluBytes .w32 operation 0 rcxRegister).length
  have bytes := at_.loaded
  simp only [frameAluBytes] at bytes
  have first := rightToRcx_step s moved bytes.prefix.prefix.prefix rfl
  have second := frameLoad_step moved loadedLeft slot (CodeAt.middle (first := rightToRcxBytes) bytes.prefix) rfl
  have third := frameAlu_step loadedLeft s' operation
    (by simpa only [loadedLeft, moved, State.load32, State.immediate32, State.move32,
      BitVec.ofNat_add, BitVec.add_assoc, List.length_append] using
      CodeAt.middle (first := rightToRcxBytes ++ frameLoadBytes slot) bytes) false rfl
  refine ⟨3, s', .cons first (.cons second (.cons third (.refl _))), ?_, at_.advance rfl ?_⟩
  · refine Rel.accumulate (s' := s') rel rfl ?_ ?_
    · intro register zero one
      simp only [s', loadedLeft, moved, State.alu32, State.alu, State.load32, State.immediate32,
        State.move32, rcxRegister]
      simp only [if_neg zero]
      exact if_neg one
    · have slotValue := rel.slots slot inFrame
      have rbp := rel.rbp
      simp only [frameSlotAddress] at slotValue
      simp only [rbpRegister] at rbp
      simp [s', loadedLeft, moved, State.alu32, State.alu, State.load32, State.immediate32,
        State.move32, rcxRegister, rbpRegister, ← rel.acc, rbp, slotValue]
  · simp only [s', loadedLeft, moved, State.alu32, State.alu, State.load32, State.immediate32,
      State.move32, frameAluBytes, List.length_append, BitVec.ofNat_add, BitVec.add_assoc]

/-- `mov ecx, eax; mov eax, [slot]; imul eax, ecx` -/
theorem multiply_simulates (rel : Rel frame s m) (inFrame : slot < frame.slots)
    (at_ : At frame s (frameMultiplyBytes slot ++ rest)) :
    ∃ n s', Steps n s s' ∧ Rel frame s' { m with acc := m.slots slot * m.acc } ∧ At frame s' rest := by
  let moved := s.move32 rcxRegister 0 rightToRcxBytes.length
  let loadedLeft := moved.load32 0 rbpRegister
    (BitVec.ofInt 32 (frameDisplacement slot)) (frameLoadBytes slot).length
  let s' := loadedLeft.multiply 32 0 rcxRegister s.flags (multiplyBytes .w32 0 rcxRegister).length
  have bytes := at_.loaded
  simp only [frameMultiplyBytes] at bytes
  have first := rightToRcx_step s moved bytes.prefix.prefix.prefix rfl
  have second := frameLoad_step moved loadedLeft slot (CodeAt.middle (first := rightToRcxBytes) bytes.prefix) rfl
  have third := frameMultiply_step loadedLeft s'
    (by simpa only [loadedLeft, moved, State.load32, State.immediate32, State.move32,
      BitVec.ofNat_add, BitVec.add_assoc, List.length_append] using
      CodeAt.middle (first := rightToRcxBytes ++ frameLoadBytes slot) bytes) s.flags rfl
  refine ⟨3, s', .cons first (.cons second (.cons third (.refl _))), ?_, at_.advance rfl ?_⟩
  · refine Rel.accumulate (s' := s') rel rfl ?_ ?_
    · intro register zero one
      simp only [s', loadedLeft, moved, State.multiply, State.load32, State.immediate32,
        State.move32, rcxRegister]
      simp only [if_neg zero]
      exact if_neg one
    · have slotValue := rel.slots slot inFrame
      have rbp := rel.rbp
      simp only [frameSlotAddress] at slotValue
      simp only [rbpRegister] at rbp
      simp [s', loadedLeft, moved, State.multiply, State.load32, State.immediate32,
        State.move32, rcxRegister, rbpRegister, ← rel.acc, rbp, slotValue]
  · simp only [s', loadedLeft, moved, State.multiply, State.load32, State.immediate32,
      State.move32, frameMultiplyBytes, List.length_append, BitVec.ofNat_add, BitVec.add_assoc]

theorem ret_simulates (rel : Rel frame s m) (at_ : At frame s (Instr.ret.encode ++ rest)) :
    ∃ n s', Steps n s s' ∧ Returned frame s' m.acc := by
  refine ⟨3, epilogueState s, frameEpilogue_steps s at_.loaded.prefix, ?_⟩
  have rbp := rel.rbp
  simp only [rbpRegister] at rbp
  constructor
  · simpa [epilogueState, State.returnNear, State.pop64, State.move64, rspRegister, rbpRegister,
      rbp] using rel.returnAddress
  · simp [epilogueState, State.returnNear, State.pop64, State.move64, rspRegister, rbpRegister,
      rbp, BitVec.add_assoc]
  · simp [epilogueState, State.returnNear, State.pop64, State.move64, rspRegister, rbpRegister,
      rbp, rel.saved]
  · simp [epilogueState, State.returnNear, State.pop64, State.move64, rspRegister, rbpRegister,
      rel.acc]
  · intro register other
    obtain ⟨-, -, four, five, -⟩ := not_scratch other
    simp [epilogueState, State.returnNear, State.pop64, State.move64, rspRegister, rbpRegister,
      four, five, rel.preserved register other]

theorem Instr.simulates (i : Instr) (notRet : i ≠ .ret) (fits : i.fits frame.slots)
    (limit : frame.slots ≤ frameLimit) (rel : Rel frame s m) (at_ : At frame s (i.encode ++ rest)) :
    ∃ n s', Steps n s s' ∧ Rel frame s' (i.step m) ∧ At frame s' rest := by
  cases i with
  | imm value => exact imm_simulates rel at_
  | load slot => exact load_simulates rel fits at_
  | store slot => exact store_simulates rel limit fits at_
  | neg => exact neg_simulates rel at_
  | op operation slot =>
    cases operation
    case mul => exact multiply_simulates rel fits at_
    all_goals exact alu_simulates _ rel fits at_
  | ret => exact absurd rfl notRet

/-- The bytes of a body simulate its abstract run to the first `ret`. -/
theorem encodeAll_simulates (limit : frame.slots ≤ frameLimit) (instrs : List Instr)
    (fits : ∀ i ∈ instrs, i.fits frame.slots) (rel : Rel frame s m)
    (at_ : At frame s (encodeAll instrs)) (ran : Instr.run instrs m = some value) :
    ∃ n s', Steps n s s' ∧ Returned frame s' value := by
  induction instrs generalizing s m with
  | nil => simp [Instr.run] at ran
  | cons i rest ih =>
    by_cases isRet : i = .ret
    · subst isRet
      simp only [Instr.run, Option.some.injEq] at ran
      exact ran ▸ ret_simulates rel at_
    · rw [Instr.run_cons i rest m isRet] at ran
      obtain ⟨n, middle, steps, middleRel, middleAt⟩ :=
        Instr.simulates i isRet (fits i (List.mem_cons_self ..)) limit rel at_
      obtain ⟨n', s', rest', returned⟩ :=
        ih (fun j mem => fits j (List.mem_cons_of_mem _ mem)) middleRel middleAt ran
      exact ⟨_, _, steps.trans rest', returned⟩

end Lanius.Mini
