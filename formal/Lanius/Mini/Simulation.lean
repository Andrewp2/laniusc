import Lanius.Mini.Flags
import Lanius.Mini.Frame
import Lanius.Mini.Fits

/-! The x86 bytes of each abstract instruction simulate it. One relation holds
between an x86 state and an abstract machine throughout an activation. The
activation may change only the `window` stack bytes below its return address;
everything else, the program image included, stays as it was at entry. -/

namespace Lanius.Mini
open Lanius.X86.Machine

/-- Registers compiled code may change: rax, rcx, rsp, rbp, r11. -/
def Scratch (register : Register) : Prop :=
  register = 0 ∨ register = rcxRegister ∨ register = rspRegister ∨ register = rbpRegister ∨
    register = r11Register

theorem not_scratch {register : Register} (other : ¬Scratch register) :
    register ≠ 0 ∧ register ≠ 1 ∧ register ≠ 4 ∧ register ≠ 5 ∧ register ≠ 11 := by
  simp only [Scratch, rcxRegister, rspRegister, rbpRegister, r11Register, not_or] at other
  exact other

/-- One activation of a compiled function. -/
structure Frame where
  /-- rsp at entry: the address of the return address. -/
  top : BitVec 64
  /-- The stack bytes below `top` this activation and its callees may use. -/
  window : Nat
  slots : Nat
  /-- Address of the body's first instruction. -/
  base : BitVec 64
  /-- The caller's rbp. -/
  saved : BitVec 64
  /-- The caller's registers. -/
  preserved : Register → BitVec 64
  /-- Memory at entry. -/
  entry : Memory

/-- Sizes that keep the stack arithmetic exact. -/
structure Frame.Fits (frame : Frame) : Prop where
  slots : frame.slots ≤ frameLimit
  window : frameBytes frame.slots + 16 ≤ frame.window
  bounded : frame.window ≤ 2 ^ 62

/-- The x86 state holds the abstract machine in this activation. -/
structure Rel (frame : Frame) (s : State) (m : Machine) : Prop where
  rip : s.rip = frame.base + BitVec.ofNat 64 m.pc
  rbp : s.registers rbpRegister = frame.top - 8
  rsp : s.registers rspRegister = frame.top - BitVec.ofNat 64 (frameBytes frame.slots + 8)
  acc : s.registers 0 = m.acc
  slots : ∀ slot, slot < frame.slots → read64 s.memory (frameSlotAddress (frame.top - 8) slot) = m.slots slot
  saved : read64 s.memory (frame.top - 8) = frame.saved
  preserved : ∀ register, ¬Scratch register → s.registers register = frame.preserved register
  unchanged : ∀ address, ¬Below frame.top frame.window address → s.memory address = frame.entry address

/-- The activation has left with `value` in rax. -/
structure Frame.Left (frame : Frame) (s : State) (value : BitVec 64) : Prop where
  rip : s.rip = read64 frame.entry frame.top
  rsp : s.registers rspRegister = frame.top + 8
  rbp : s.registers rbpRegister = frame.saved
  value : s.registers 0 = value
  preserved : ∀ register, ¬Scratch register → s.registers register = frame.preserved register
  unchanged : ∀ address, ¬Below frame.top frame.window address → s.memory address = frame.entry address

variable {frame : Frame} {s s' : State} {m : Machine} {slot : Nat} {value : BitVec 64}

theorem Rel.advance (rel : Rel frame s m) (size : Nat) :
    s.rip + BitVec.ofNat 64 size = frame.base + BitVec.ofNat 64 (m.pc + size) := by
  rw [rel.rip, BitVec.ofNat_add, BitVec.add_assoc]

/-- Instructions that write only rax and rcx keep the relation, given the new accumulator. -/
theorem Rel.accumulate (rel : Rel frame s m) (memory : s'.memory = s.memory) (size : Nat)
    (rip : s'.rip = s.rip + BitVec.ofNat 64 size)
    (registers : ∀ register, register ≠ 0 → register ≠ 1 → s'.registers register = s.registers register)
    (acc : s'.registers 0 = value) :
    Rel frame s' { m with pc := m.pc + size, acc := value } where
  rip := rip.trans (rel.advance size)
  rbp := (registers _ (by decide) (by decide)).trans rel.rbp
  rsp := (registers _ (by decide) (by decide)).trans rel.rsp
  acc := acc
  slots := by rw [memory]; exact rel.slots
  saved := by rw [memory]; exact rel.saved
  preserved register other := by
    obtain ⟨zero, one, -⟩ := not_scratch other
    rw [registers register zero one]
    exact rel.preserved register other
  unchanged := by rw [memory]; exact rel.unchanged

/-- Control transfers change only rip and flags. -/
theorem Rel.jump (rel : Rel frame s m) (memory : s'.memory = s.memory) (registers : s'.registers = s.registers)
    {pc : Nat} (rip : s'.rip = frame.base + BitVec.ofNat 64 pc) : Rel frame s' { m with pc := pc } where
  rip := rip
  rbp := by rw [registers]; exact rel.rbp
  rsp := by rw [registers]; exact rel.rsp
  acc := by rw [registers]; exact rel.acc
  slots := by rw [memory]; exact rel.slots
  saved := by rw [memory]; exact rel.saved
  preserved := by rw [registers]; exact rel.preserved
  unchanged := by rw [memory]; exact rel.unchanged

/-! The x86 steps of the slot encodings. -/

theorem slotLoad_step (before after : State) (slot : Nat)
    (loaded : CodeAt before.memory before.rip (slotLoadBytes slot))
    (result : after = before.load64 0 rbpRegister
      (BitVec.ofInt 32 (frameDisplacement slot)) (slotLoadBytes slot).length) :
    Lanius.X86.Machine.Step before after :=
  Lanius.X86.Machine.Step.decoded (slotLoadBytes slot) loaded _ _
    (by simpa [slotLoadBytes, memoryInstruction] using
      memory_decodes .w64 true 0 rbpRegister (frameDisplacement slot) [])
    (by rw [result]; rfl) rfl

theorem slotStore_step (before after : State) (slot : Nat)
    (loaded : CodeAt before.memory before.rip (slotStoreBytes slot))
    (result : after = before.store64 0 rbpRegister
      (BitVec.ofInt 32 (frameDisplacement slot)) (slotStoreBytes slot).length) :
    Lanius.X86.Machine.Step before after :=
  Lanius.X86.Machine.Step.decoded (slotStoreBytes slot) loaded _ _
    (by simpa [slotStoreBytes, memoryInstruction] using
      memory_decodes .w64 false 0 rbpRegister (frameDisplacement slot) [])
    (by rw [result]; rfl) rfl

theorem accToRcx_length : accToRcxBytes.length = 3 := by decide

theorem accToRcx_step (before after : State) (loaded : CodeAt before.memory before.rip accToRcxBytes)
    (result : after = before.move64 rcxRegister 0 3) : Lanius.X86.Machine.Step before after :=
  move_step before after .w64 rcxRegister 0 loaded result

/-- The last instruction of a binary operator: `op eax, ecx` or `op rax, rcx`. -/
def BinOp.final (word : Word) (operation : BinOp) (st : State) : State :=
  match operation with
  | .mul => st.multiply word.width.bits 0 rcxRegister st.flags (operation.opBytes word).length
  | .add => st.alu word.width.bits .add 0 rcxRegister false (operation.opBytes word).length
  | .sub => st.alu word.width.bits .subtract 0 rcxRegister false (operation.opBytes word).length
  | .and => st.alu word.width.bits .and 0 rcxRegister false (operation.opBytes word).length
  | .or => st.alu word.width.bits .or 0 rcxRegister false (operation.opBytes word).length
  | .xor => st.alu word.width.bits .xor 0 rcxRegister false (operation.opBytes word).length

theorem BinOp.final_step (word : Word) (operation : BinOp) (st : State)
    (loaded : CodeAt st.memory st.rip (operation.opBytes word)) :
    Lanius.X86.Machine.Step st (operation.final word st) := by
  cases word <;> cases operation
  · exact alu_step .w32 st _ .add 0 rcxRegister loaded false rfl
  · exact alu_step .w32 st _ .subtract 0 rcxRegister loaded false rfl
  · exact multiply_step .w32 st _ 0 rcxRegister loaded st.flags rfl
  · exact alu_step .w32 st _ .and 0 rcxRegister loaded false rfl
  · exact alu_step .w32 st _ .or 0 rcxRegister loaded false rfl
  · exact alu_step .w32 st _ .xor 0 rcxRegister loaded false rfl
  · exact alu_step .w64 st _ .add 0 rcxRegister loaded false rfl
  · exact alu_step .w64 st _ .subtract 0 rcxRegister loaded false rfl
  · exact multiply_step .w64 st _ 0 rcxRegister loaded st.flags rfl
  · exact alu_step .w64 st _ .and 0 rcxRegister loaded false rfl
  · exact alu_step .w64 st _ .or 0 rcxRegister loaded false rfl
  · exact alu_step .w64 st _ .xor 0 rcxRegister loaded false rfl

theorem BinOp.final_registers (word : Word) (operation : BinOp) (st : State) (register : Register) :
    (operation.final word st).registers register =
      if register = 0 then word.apply operation (st.registers 0) (st.registers rcxRegister)
      else st.registers register := by
  by_cases zero : register = 0 <;> cases word <;> cases operation <;>
    simp [zero, BinOp.final, State.alu, State.multiply, Word.apply, BinOp.apply, Alu.result, Word.width,
      X86.Register.Width.bits] <;> rfl

theorem BinOp.final_memory (word : Word) (operation : BinOp) (st : State) :
    (operation.final word st).memory = st.memory := by
  cases operation <;> rfl

theorem BinOp.final_rip (word : Word) (operation : BinOp) (st : State) :
    (operation.final word st).rip = st.rip + BitVec.ofNat 64 (operation.opBytes word).length := by
  cases operation <;> rfl

/-- `cmp eax, ecx` or `cmp rax, rcx` -/
def Word.compared (word : Word) (st : State) : State :=
  match word with
  | .s32 => st.compare32 0 rcxRegister 2
  | .u64 => st.compare64 0 rcxRegister 3

theorem Word.compareBytes_length (word : Word) : word.compareBytes.length = word.prefix + 2 := by
  cases word <;> decide

theorem Word.compared_step (word : Word) (st : State) (loaded : CodeAt st.memory st.rip word.compareBytes) :
    Lanius.X86.Machine.Step st (word.compared st) := by
  cases word
  · exact compare_step st _ 0 rcxRegister loaded rfl
  · exact Lanius.X86.Machine.Step.decoded [72, 57, 200] loaded (.compare64 0 rcxRegister) 3 (by decide) rfl rfl

theorem Word.compared_condition (word : Word) (operation : CmpOp) (st : State) :
    condition (word.compared st).flags (operation.code word) =
      word.holds operation (st.registers 0) (st.registers rcxRegister) := by
  cases word
  · exact CmpOp.condition _ _ _ _
  · exact CmpOp.conditionU _ _ _ _

theorem Word.compared_rip (word : Word) (st : State) :
    (word.compared st).rip = st.rip + BitVec.ofNat 64 word.compareBytes.length := by
  cases word <;> rfl

theorem rel_slot (rel : Rel frame s m) (inFrame : slot < frame.slots) :
    read64 s.memory (s.registers 5 + (BitVec.ofInt 32 (frameDisplacement slot)).signExtend 64) = m.slots slot := by
  rw [show (5 : Register) = rbpRegister from rfl, rel.rbp]; exact rel.slots slot inFrame

theorem lowHalf_highHalf (value : BitVec 64) :
    BitVec.ofNat 64 ((lowHalf value).toNat + 4294967296 * (highHalf value).toNat) = value := by
  apply BitVec.eq_of_toNat_eq
  simp only [lowHalf, highHalf, BitVec.toNat_ofNat, BitVec.toNat_setWidth, BitVec.toNat_ushiftRight,
    Nat.shiftRight_eq_div_pow]
  have := value.isLt
  omega

theorem imm_simulates (rel : Rel frame s m)
    (loaded : CodeAt s.memory s.rip (immediateBytes .w64 0 (lowHalf value) (highHalf value))) :
    ∃ n s', Steps n s s' ∧ Rel frame s' ((Instr.imm value).step m) := by
  let s' := s.immediate64 0 (BitVec.ofNat 64 ((lowHalf value).toNat + 4294967296 * (highHalf value).toNat))
    (immediateBytes .w64 0 (lowHalf value) (highHalf value)).length
  have step : Lanius.X86.Machine.Step s s' := immediate_step s s' .w64 0 _ _ loaded rfl
  have length : (immediateBytes .w64 0 (lowHalf value) (highHalf value)).length = 10 :=
    Instr.bytes_length ⟨0, 0, []⟩ 0 (.imm value)
  refine ⟨1, s', .cons step (.refl _), Rel.accumulate (s' := s') rel rfl 10
    (by simp only [s', State.immediate64, length]) ?_ ?_⟩
  · intro register zero _
    simp only [s', State.immediate64, if_neg zero]
  · simp [s', State.immediate64, lowHalf_highHalf, Instr.update]

theorem load_simulates (rel : Rel frame s m) (inFrame : slot < frame.slots)
    (loaded : CodeAt s.memory s.rip (slotLoadBytes slot)) :
    ∃ n s', Steps n s s' ∧ Rel frame s' ((Instr.load slot).step m) := by
  let s' := s.load64 0 rbpRegister (BitVec.ofInt 32 (frameDisplacement slot)) (slotLoadBytes slot).length
  have step : Lanius.X86.Machine.Step s s' := slotLoad_step s s' slot loaded rfl
  refine ⟨1, s', .cons step (.refl _), Rel.accumulate (s' := s') rel rfl 7
    (by simp only [s', State.load64, slotLoadBytes_length]) ?_ ?_⟩
  · intro register zero _
    simp only [s', State.load64, if_neg zero]
  · simp [s', State.load64, rbpRegister, rel_slot rel inFrame, Instr.update]

theorem neg_simulates (rel : Rel frame s m) (loaded : CodeAt s.memory s.rip (negateBytes .w32 0)) :
    ∃ n s', Steps n s s' ∧ Rel frame s' (Instr.neg.step m) := by
  let s' := s.negate 32 0 s.flags (negateBytes .w32 0).length
  have step : Lanius.X86.Machine.Step s s' := negate_step .w32 s s' 0 loaded s.flags rfl
  refine ⟨1, s', .cons step (.refl _), Rel.accumulate (s' := s') rel rfl 2
    (by simp only [s', State.negate]; rfl) ?_ ?_⟩
  · intro register zero _
    simp only [s', State.negate, if_neg zero]
  · simp [s', State.negate, ← rel.acc, Instr.update]

theorem op_size (word : Word) (operation : BinOp) (slot : Nat) :
    (Instr.op word operation slot).size = 10 + (operation.opBytes word).length := by
  cases word <;> cases operation <;> rfl

theorem cmp_size (word : Word) (operation : CmpOp) (slot : Nat) :
    (Instr.cmp word operation slot).size = 10 + word.compareBytes.length + 6 := by
  cases word <;> rfl

/-- `mov rcx, rax; mov rax, [slot]; op` -/
theorem op_simulates (word : Word) (operation : BinOp) (rel : Rel frame s m) (inFrame : slot < frame.slots)
    (loaded : CodeAt s.memory s.rip (operation.spec word slot)) :
    ∃ n s', Steps n s s' ∧ Rel frame s' ((Instr.op word operation slot).step m) := by
  let moved := s.move64 rcxRegister 0 3
  let loadedLeft := moved.load64 0 rbpRegister
    (BitVec.ofInt 32 (frameDisplacement slot)) (slotLoadBytes slot).length
  let s' := operation.final word loadedLeft
  have bytes := loaded
  simp only [BinOp.spec] at bytes
  have first := accToRcx_step s moved bytes.prefix.prefix rfl
  have second := slotLoad_step moved loadedLeft slot
    (by simpa only [moved, State.move64, accToRcx_length] using bytes.prefix.suffix) rfl
  have third := operation.final_step word loadedLeft
    (by simpa only [loadedLeft, moved, State.load64, State.move64, accToRcx_length,
      BitVec.ofNat_add, BitVec.add_assoc, List.length_append] using bytes.suffix)
  have size := op_size word operation slot
  refine ⟨3, s', .cons first (.cons second (.cons third (.refl _))), ?_⟩
  refine Rel.accumulate (s' := s') rel (BinOp.final_memory ..) _ ?_ ?_ ?_
  · simp only [s', BinOp.final_rip, loadedLeft, moved, State.load64, State.move64, slotLoadBytes_length, size]
    bv_omega
  · intro register zero one
    have one' : register ≠ rcxRegister := one
    simp only [s', BinOp.final_registers, if_neg zero, loadedLeft, moved, State.load64, State.move64,
      if_neg one']
  · simp [s', BinOp.final_registers, loadedLeft, moved, State.load64, State.move64, rcxRegister,
      rbpRegister, ← rel.acc, rel_slot rel inFrame, Instr.update]

theorem setCondition_value (high : BitVec 56) (holds : Bool) :
    (((high ++ (if holds then (1 : BitVec 8) else 0)).setWidth 8).setWidth 64 : BitVec 64) =
      if holds then 1 else 0 := by
  rw [BitVec.setWidth_append_eq_right]
  cases holds <;> rfl

/-- `mov rcx, rax; mov rax, [slot]; cmp; setcc al; movzx eax, al` -/
theorem cmp_simulates (word : Word) (operation : CmpOp) (rel : Rel frame s m) (inFrame : slot < frame.slots)
    (loaded : CodeAt s.memory s.rip (cmpBytes word operation slot)) :
    ∃ n s', Steps n s s' ∧ Rel frame s' ((Instr.cmp word operation slot).step m) := by
  let moved := s.move64 rcxRegister 0 3
  let loadedLeft := moved.load64 0 rbpRegister
    (BitVec.ofInt 32 (frameDisplacement slot)) (slotLoadBytes slot).length
  let compared := word.compared loadedLeft
  let set := compared.setCondition (operation.code word) 0 (setConditionBytes (operation.code word) 0).length
  let s' := set.zeroExtendByte 0 0 (zeroExtendByteBytes 0 0).length
  have bytes : CodeAt s.memory s.rip (accToRcxBytes ++ (slotLoadBytes slot ++ (word.compareBytes ++
      (setConditionBytes (operation.code word) 0 ++ zeroExtendByteBytes 0 0)))) := by
    simpa only [cmpBytes, List.append_assoc] using loaded
  have first := accToRcx_step s moved bytes.prefix rfl
  have bytes1 : CodeAt moved.memory moved.rip (slotLoadBytes slot ++ (word.compareBytes ++
      (setConditionBytes (operation.code word) 0 ++ zeroExtendByteBytes 0 0))) := by
    simpa only [moved, State.move64, accToRcx_length] using bytes.suffix
  have second := slotLoad_step moved loadedLeft slot bytes1.prefix rfl
  have bytes2 : CodeAt loadedLeft.memory loadedLeft.rip (word.compareBytes ++
      (setConditionBytes (operation.code word) 0 ++ zeroExtendByteBytes 0 0)) := by
    simpa only [loadedLeft, State.load64] using bytes1.suffix
  have third := word.compared_step loadedLeft bytes2.prefix
  have comparedMemory : compared.memory = loadedLeft.memory := by cases word <;> rfl
  have comparedRegisters : compared.registers = loadedLeft.registers := by cases word <;> rfl
  have bytes3 : CodeAt compared.memory compared.rip
      (setConditionBytes (operation.code word) 0 ++ zeroExtendByteBytes 0 0) := by
    rw [comparedMemory, Word.compared_rip]
    exact bytes2.suffix
  have fourth := setCondition_step compared set (operation.code word) 0 bytes3.prefix rfl
  have bytes4 : CodeAt set.memory set.rip (zeroExtendByteBytes 0 0) := by
    simpa only [set, State.setCondition] using bytes3.suffix
  have fifth := zeroExtendByte_step set s' 0 0 bytes4 rfl
  have size := cmp_size word operation slot
  refine ⟨5, s', .cons first (.cons second (.cons third (.cons fourth (.cons fifth (.refl _))))), ?_⟩
  refine Rel.accumulate (s' := s') rel (by
    simp only [s', set, State.zeroExtendByte, State.setCondition]
    rw [comparedMemory]
    rfl) _ ?_ ?_ ?_
  · simp only [s', set, State.zeroExtendByte, State.setCondition, compared, Word.compared_rip, loadedLeft,
      moved, State.load64, State.move64, slotLoadBytes_length, size]
    have : (setConditionBytes (operation.code word) 0).length = 3 := by
      simp only [setConditionBytes, List.length_append, List.length_cons, List.length_nil]; decide
    have : (zeroExtendByteBytes 0 0).length = 3 := by decide
    simp only [*]
    bv_omega
  · intro register zero one
    have one' : register ≠ rcxRegister := one
    simp only [s', set, State.zeroExtendByte, State.setCondition, comparedRegisters, loadedLeft, moved,
      State.load64, State.move64, if_neg zero, if_neg one']
  · have holds := word.compared_condition operation loadedLeft
    have left : loadedLeft.registers 0 = m.slots slot := by
      simp [loadedLeft, moved, State.load64, State.move64, rbpRegister, rcxRegister, rel_slot rel inFrame]
    have right : loadedLeft.registers rcxRegister = m.acc := by
      simp [loadedLeft, moved, State.load64, State.move64, rcxRegister, rel.acc]
    rw [left, right] at holds
    simp only [s', set, State.zeroExtendByte, State.setCondition, if_pos, Instr.step, Instr.update]
    rw [show condition compared.flags (operation.code word) = _ from holds]
    exact setCondition_value _ _

theorem store_simulates (rel : Rel frame s m) (fits : frame.Fits) (inFrame : slot < frame.slots)
    (loaded : CodeAt s.memory s.rip (slotStoreBytes slot)) :
    ∃ n s', Steps n s s' ∧ Rel frame s' ((Instr.store slot).step m) := by
  let s' := s.store64 0 rbpRegister (BitVec.ofInt 32 (frameDisplacement slot)) (slotStoreBytes slot).length
  have step : Lanius.X86.Machine.Step s s' := slotStore_step s s' slot loaded rfl
  have limit : frame.slots ≤ 2 ^ 20 := fits.slots
  have bound : slot < slotLimit := by unfold slotLimit; omega
  have address : s.registers rbpRegister + (BitVec.ofInt 32 (frameDisplacement slot)).signExtend 64 =
      frameSlotAddress (frame.top - 8) slot := by rw [rel.rbp]; rfl
  have memory : s'.memory = write64 s.memory (frameSlotAddress (frame.top - 8) slot) m.acc := by
    simp only [s', State.store64, address, rel.acc]
  have room := fits.window
  have bounded := fits.bounded
  have big := frameBytes_slots frame.slots
  refine ⟨1, s', .cons step (.refl _), ?_⟩
  refine ⟨?_, rel.rbp, rel.rsp, rel.acc, ?_, ?_, rel.preserved, ?_⟩
  · simp only [s', State.store64, slotStoreBytes_length]
    exact rel.advance 7
  · intro other otherInFrame
    have otherBound : other < slotLimit := by unfold slotLimit; omega
    rw [memory]
    simp only [Instr.step, Instr.update, Machine.store]
    by_cases same : other = slot
    · rw [if_pos same, same, read64_write64]
    · rw [if_neg same]
      rw [read64_frame _ _ _ _ (by
        intro i j
        rw [slot_lane _ otherBound _ (by omega), slot_lane _ bound _ (by omega)]
        exact depth_ne _ (by omega) (by omega) (by omega))]
      exact rel.slots other otherInFrame
  · rw [memory, read64_frame _ _ _ _ (by
      intro i j
      rw [slot_lane _ bound _ (by omega), show frame.top - 8 = frame.top - BitVec.ofNat 64 8 from rfl,
        depth_lane _ _ _ (by omega)]
      exact depth_ne _ (by omega) (by omega) (by omega))]
    exact rel.saved
  · intro other outside
    rw [memory, write64_frame _ _ _ _ (fun lane => by
      rw [slot_lane _ bound _ (by omega)]
      exact ne_of_below outside (below_depth _ (by omega) (by omega) (by omega)))]
    exact rel.unchanged other outside

theorem jmp_simulates (rel : Rel frame s m) {target : Nat} (small : m.pc + 5 < 2 ^ 31) (targetSmall : target < 2 ^ 31)
    (loaded : CodeAt s.memory s.rip (jumpBytes (relative (m.pc + 5) target))) :
    ∃ n s', Steps n s s' ∧ Rel frame s' { m with pc := target } := by
  let s' := s.jump (relative (m.pc + 5) target) (jumpBytes (relative (m.pc + 5) target)).length
  have step : Lanius.X86.Machine.Step s s' := jump_step s s' _ loaded rfl
  refine ⟨1, s', .cons step (.refl _), rel.jump (s' := s') rfl rfl ?_⟩
  have length : (jumpBytes (relative (m.pc + 5) target)).length = 5 := by simp [jumpBytes, displacementBytes]
  simp only [s', State.jump, length, rel.advance 5]
  exact relative_eq _ _ _ small targetSmall

theorem test64_zero_condition (before result : BitVec 64) (auxiliary : Bool) :
    condition (logicalFlags before result auxiliary) 4 = (result == 0) := by
  change (logicalFlags before result auxiliary).getLsbD 6 = (result == 0)
  unfold logicalFlags
  exact (arithmeticFlags_bits ..).1

/-- `test rax, rax; jz rel32` -/
theorem jz_simulates (rel : Rel frame s m) {target : Nat} (small : m.pc + 9 < 2 ^ 31)
    (targetSmall : target < 2 ^ 31)
    (loaded : CodeAt s.memory s.rip (testBytes .w64 0 0 ++ branchBytes 4 (relative (m.pc + 9) target))) :
    ∃ n s', Steps n s s' ∧ Rel frame s' { m with pc := if m.acc = 0 then target else m.pc + 9 } := by
  let tested := s.test64 0 0 false (testBytes .w64 0 0).length
  have first : Lanius.X86.Machine.Step s tested := test_step .w64 s tested 0 0 loaded.prefix false rfl
  let s' := tested.branch 4 (relative (m.pc + 9) target) 6
  have bytes : CodeAt tested.memory tested.rip (branchBytes 4 (relative (m.pc + 9) target)) := by
    simpa only [tested, State.test64, State.test] using loaded.suffix
  have zero : condition tested.flags 4 = (m.acc == 0) := by
    simp only [tested, State.test64, State.test, BitVec.and_self, BitVec.setWidth_eq, rel.acc]
    exact test64_zero_condition s.flags m.acc false
  have testedRip : tested.rip + BitVec.ofNat 64 6 = frame.base + BitVec.ofNat 64 (m.pc + 9) := by
    have : (testBytes .w64 0 0).length = 3 := by decide
    simp only [tested, State.test64, State.test, this, rel.advance 3]
    bv_omega
  by_cases accZero : m.acc = 0
  · obtain ⟨second, rip⟩ := branch_step_rip tested s' 4 _ bytes (by rw [zero, accZero]; rfl) rfl
    refine ⟨2, s', .cons first (.cons second (.refl _)), ?_⟩
    rw [if_pos accZero]
    refine rel.jump (s' := s') rfl rfl ?_
    rw [rip, testedRip]
    exact relative_eq _ _ _ small targetSmall
  · obtain ⟨second, rip⟩ := branch_step_rip_not_taken tested s' 4 _ bytes
      (by rw [zero]; simpa using accZero) rfl
    refine ⟨2, s', .cons first (.cons second (.refl _)), ?_⟩
    rw [if_neg accZero]
    refine rel.jump (s' := s') rfl rfl ?_
    rw [rip, testedRip]
    bv_omega

/-- The frame epilogue and `ret`. -/
theorem epilogue_simulates (rel : Rel frame s m) (fits : frame.Fits) (loaded : CodeAt s.memory s.rip epilogueBytes) :
    ∃ n s', Steps n s s' ∧ frame.Left s' m.acc ∧ s'.memory = s.memory := by
  refine ⟨3, epilogueState s, frameEpilogue_steps s loaded, ?_, by
    simp only [epilogueState, State.returnNear, State.pop64, State.move64]⟩
  have rbp : s.registers 5 = frame.top - 8 := rel.rbp
  have bounded := fits.bounded
  constructor
  · simp only [epilogueState, State.returnNear, State.pop64, State.move64, rspRegister, rbpRegister]
    simp only [show (4 : Register) ≠ 5 by decide, if_true, if_false, rbp, BitVec.sub_add_cancel]
    apply read64_congr
    intro lane
    exact rel.unchanged _ (not_below_return _ lane.isLt (by omega))
  · simp [epilogueState, State.returnNear, State.pop64, State.move64, rspRegister, rbpRegister, rbp]
    bv_omega
  · simp [epilogueState, State.returnNear, State.pop64, State.move64, rspRegister, rbpRegister, rbp]
    exact rel.saved
  · simp [epilogueState, State.returnNear, State.pop64, State.move64, rspRegister, rbpRegister, rel.acc]
  · intro register other
    obtain ⟨-, -, four, five, -⟩ := not_scratch other
    simp [epilogueState, State.returnNear, State.pop64, State.move64, rspRegister, rbpRegister,
      four, five, rel.preserved register other]
  · intro address outside
    simp only [epilogueState, State.returnNear, State.pop64, State.move64]
    exact rel.unchanged address outside

theorem readSlots_length (slots : Nat → BitVec 64) (args : List Nat) : (readSlots slots args).length = args.length := by
  induction args <;> simp_all [readSlots]

theorem readSlots_getElem (slots : Nat → BitVec 64) (args : List Nat) (k : Nat) (bound : k < args.length) :
    (readSlots slots args)[k]'(by rw [readSlots_length]; exact bound) = slots args[k] := by
  induction args generalizing k with
  | nil => simp at bound
  | cons slot rest ih =>
    cases k with
    | zero => rfl
    | succ k => exact ih k (by simp at bound; omega)

/-- The argument copies of a call: argument `j` goes from slot `args[j]` to
virtual slot `first + k + j`. -/
theorem copy_steps (top : BitVec 64) (first : Nat) :
    ∀ (args : List Nat) (k : Nat) (s : State),
      s.registers rbpRegister = top - 8 →
      CodeAt s.memory s.rip (copyBytes first args k) →
      (∀ index, index < 14 * args.length → ∀ j, j < args.length → ∀ lane : Fin 8,
        s.rip + BitVec.ofNat 64 index ≠ frameSlotAddress (top - 8) (first + k + j) + BitVec.ofNat 64 lane.val) →
      (∀ j, j < args.length → ∀ slot ∈ args, ∀ i lane : Fin 8,
        frameSlotAddress (top - 8) slot + BitVec.ofNat 64 i.val ≠
          frameSlotAddress (top - 8) (first + k + j) + BitVec.ofNat 64 lane.val) →
      (∀ j j', j < j' → j' < args.length → ∀ i lane : Fin 8,
        frameSlotAddress (top - 8) (first + k + j) + BitVec.ofNat 64 i.val ≠
          frameSlotAddress (top - 8) (first + k + j') + BitVec.ofNat 64 lane.val) →
      ∃ n s', Steps n s s' ∧ s'.rip = s.rip + BitVec.ofNat 64 (14 * args.length) ∧
        (∀ register, register ≠ 0 → s'.registers register = s.registers register) ∧
        (∀ address, (∀ j, j < args.length → ∀ lane : Fin 8,
            address ≠ frameSlotAddress (top - 8) (first + k + j) + BitVec.ofNat 64 lane.val) →
          s'.memory address = s.memory address) ∧
        (∀ j (bound : j < args.length), read64 s'.memory (frameSlotAddress (top - 8) (first + k + j)) =
          read64 s.memory (frameSlotAddress (top - 8) args[j])) ∧
        s'.registers 0 =
          (args.map fun slot => read64 s.memory (frameSlotAddress (top - 8) slot)).getLastD
            (s.registers 0) := by
  intro args
  induction args with
  | nil =>
    intro k s _ _ _ _ _
    exact ⟨0, s, .refl _, by simp, fun _ _ => rfl, fun _ _ => rfl, fun j bound => absurd bound (by simp), rfl⟩
  | cons slot rest ih =>
    intro k s rbp loaded codeApart reads distinct
    let s1 := s.load64 0 rbpRegister (BitVec.ofInt 32 (frameDisplacement slot)) (slotLoadBytes slot).length
    let s2 := s1.store64 0 rbpRegister (BitVec.ofInt 32 (frameDisplacement (first + k)))
      (slotStoreBytes (first + k)).length
    have bytes : CodeAt s.memory s.rip
        (slotLoadBytes slot ++ slotStoreBytes (first + k) ++ copyBytes first rest (k + 1)) := by
      simpa only [copyBytes, slotLoad_eq, slotStore_eq] using loaded
    have step1 := slotLoad_step s s1 slot bytes.prefix.prefix rfl
    have step2 := slotStore_step s1 s2 (first + k)
      (by simpa only [s1, State.load64, State.immediate32] using bytes.prefix.suffix) rfl
    have rbp1 : s1.registers rbpRegister = top - 8 := by
      simp only [s1, State.load64, State.immediate32, rbpRegister]; exact rbp
    have memory2 : s2.memory = write64 s.memory (frameSlotAddress (top - 8) (first + k))
        (read64 s.memory (frameSlotAddress (top - 8) slot)) := by
      have rbp' : s.registers 5 = top - 8 := rbp
      simp [s2, s1, State.store64, State.load64, State.immediate32, rbpRegister, rbp', frameSlotAddress]
    have rip2 : s2.rip = s.rip + BitVec.ofNat 64 14 := by
      simp only [s2, s1, State.store64, State.load64, State.immediate32, slotLoadBytes_length,
        slotStoreBytes_length]
      bv_omega
    have rbp2 : s2.registers rbpRegister = top - 8 := rbp1
    have target0 : ∀ lane : Fin 8, frameSlotAddress (top - 8) (first + k) + BitVec.ofNat 64 lane.val =
        frameSlotAddress (top - 8) (first + k + 0) + BitVec.ofNat 64 lane.val := fun _ => rfl
    have loaded2 : CodeAt s2.memory s2.rip (copyBytes first rest (k + 1)) := by
      rw [memory2, rip2]
      have tail : CodeAt s.memory (s.rip + BitVec.ofNat 64 14) (copyBytes first rest (k + 1)) := by
        have := bytes.suffix
        rwa [List.length_append, slotLoadBytes_length, slotStoreBytes_length] at this
      apply CodeAt.write64 tail
      intro index bound lane
      rw [copyBytes_length] at bound
      have := codeApart (14 + index) (by simp only [List.length_cons]; omega) 0 (by simp) lane
      rw [Nat.add_zero] at this
      rwa [BitVec.add_assoc, ← BitVec.ofNat_add]
    obtain ⟨n, s', steps, rip', registers', memory', reads', rax'⟩ := ih (k + 1) s2 rbp2 loaded2
      (by
        intro index bound j inRest lane
        rw [rip2, show first + (k + 1) + j = first + k + (j + 1) by omega]
        have := codeApart (14 + index) (by simp only [List.length_cons]; omega) (j + 1)
          (by simp only [List.length_cons]; omega) lane
        simpa only [BitVec.ofNat_add, BitVec.add_assoc] using this)
      (by
        intro j inRest other mem i lane
        rw [show first + (k + 1) + j = first + k + (j + 1) by omega]
        exact reads (j + 1) (by simp only [List.length_cons]; omega) other (List.mem_cons_of_mem _ mem) i lane)
      (by
        intro j j' less inRest i lane
        rw [show first + (k + 1) + j = first + k + (j + 1) by omega,
          show first + (k + 1) + j' = first + k + (j' + 1) by omega]
        exact distinct (j + 1) (j' + 1) (by omega) (by simp only [List.length_cons]; omega) i lane)
    refine ⟨_, s', .cons step1 (.cons step2 steps), ?_, ?_, ?_, ?_, ?_⟩
    rotate_right
    · rw [rax']
      simp only [List.map_cons, List.getLastD_cons]
      have rax2 : s2.registers 0 = read64 s.memory (frameSlotAddress (top - 8) slot) := by
        have rbp' : s.registers 5 = top - 8 := rbp
        simp [s2, s1, State.store64, State.load64, State.immediate32, rbpRegister, rbp', frameSlotAddress]
      have same : rest.map (fun slot => read64 s2.memory (frameSlotAddress (top - 8) slot)) =
          rest.map (fun slot => read64 s.memory (frameSlotAddress (top - 8) slot)) :=
        List.map_congr_left fun src mem => by
          rw [memory2, read64_frame]
          intro i lane
          exact reads 0 (by simp) src (List.mem_cons_of_mem _ mem) i lane
      rw [rax2, same]
    · rw [rip', rip2, BitVec.add_assoc, ← BitVec.ofNat_add]
      simp only [List.length_cons]
      congr 2
      omega
    · intro register zero
      rw [registers' register zero]
      simp only [s2, s1, State.store64, State.load64, State.immediate32, if_neg zero]
    · intro address apart
      rw [memory' address (by
        intro j inRest lane
        rw [show first + (k + 1) + j = first + k + (j + 1) by omega]
        exact apart (j + 1) (by simp only [List.length_cons]; omega) lane), memory2]
      exact write64_frame _ _ _ _ (fun lane => apart 0 (by simp) lane)
    · intro j bound
      cases j with
      | zero =>
        have kept : read64 s'.memory (frameSlotAddress (top - 8) (first + k + 0)) =
            read64 s2.memory (frameSlotAddress (top - 8) (first + k)) := by
          apply read64_congr
          intro i
          apply memory'
          intro j inRest lane
          rw [show first + (k + 1) + j = first + k + (j + 1) by omega]
          exact distinct 0 (j + 1) (by omega) (by simp only [List.length_cons]; omega) i lane
        rw [kept, memory2, read64_write64]
        rfl
      | succ j =>
        have := reads' j (by simp only [List.length_cons] at bound; omega)
        rw [show first + (k + 1) + j = first + k + (j + 1) by omega] at this
        rw [this, memory2, read64_frame]
        · rfl
        · intro i lane
          exact reads 0 (by simp) _ (List.mem_cons_of_mem _ (List.getElem_mem _)) i lane

theorem slot_lanes_ne (top : BitVec 64) {a b : Nat} (aBound : a < slotLimit) (bBound : b < slotLimit)
    (ne : a ≠ b) (i lane : Fin 8) :
    frameSlotAddress (top - 8) a + BitVec.ofNat 64 i.val ≠ frameSlotAddress (top - 8) b + BitVec.ofNat 64 lane.val := by
  rw [slot_lane _ aBound i.val (by omega), slot_lane _ bBound lane.val (by omega)]
  unfold slotLimit at *
  exact depth_ne _ (by omega) (by omega) (by omega)

theorem Rel.congr (rel : Rel frame s m) {m' : Machine} (pc : m'.pc = m.pc) (acc : m'.acc = m.acc)
    (slots : ∀ slot, slot < frame.slots → m'.slots slot = m.slots slot) : Rel frame s m' where
  rip := by rw [pc]; exact rel.rip
  rbp := rel.rbp
  rsp := rel.rsp
  acc := by rw [acc]; exact rel.acc
  slots slot inFrame := by rw [slots slot inFrame]; exact rel.slots slot inFrame
  saved := rel.saved
  preserved := rel.preserved
  unchanged := rel.unchanged

/-- The machine after copy code of `size` bytes stored `values` at `target`, ... -/
def Machine.copied (m : Machine) (size target : Nat) (values : List (BitVec 64)) : Machine :=
  { m with pc := m.pc + size, acc := values.getLastD m.acc, slots := writeSlots m.slots target values }

/-- Copying `sources` to the frame slots `target`, `target + 1`, ...: the
copy code of a call's results and of a return. -/
theorem copy_simulates (rel : Rel frame s m) (fits : frame.Fits) {target : Nat} {sources : List Nat}
    (loaded : CodeAt s.memory s.rip (copyBytes target sources 0))
    (apart : ∀ index, index < 14 * sources.length →
      ¬Below frame.top frame.window (s.rip + BitVec.ofNat 64 index))
    (inFrame : target + sources.length ≤ frame.slots)
    (small : ∀ src ∈ sources, src < slotLimit)
    (away : ∀ src ∈ sources, src < target ∨ target + sources.length ≤ src) :
    ∃ n s', Steps n s s' ∧ Rel frame s' (m.copied (14 * sources.length) target
      (sources.map fun src => read64 s.memory (frameSlotAddress (frame.top - 8) src))) := by
  have limit : frame.slots ≤ 2 ^ 20 := fits.slots
  have bounded := fits.bounded
  have big := frameBytes_slots frame.slots
  have window := fits.window
  have targetLane : ∀ j, j < sources.length → ∀ lane, lane < 8 →
      frameSlotAddress (frame.top - 8) (target + 0 + j) + BitVec.ofNat 64 lane =
        frame.top - BitVec.ofNat 64 (8 * (target + 0 + j) + 16 - lane) :=
    fun j bound lane small => slot_lane _ (by unfold slotLimit; omega) _ small
  have targetBelow : ∀ j, j < sources.length → ∀ lane : Fin 8,
      Below frame.top frame.window (frameSlotAddress (frame.top - 8) (target + 0 + j) + BitVec.ofNat 64 lane.val) := by
    intro j bound lane
    rw [targetLane j bound lane.val (by omega)]
    exact below_depth _ (by omega) (by omega) (by omega)
  obtain ⟨n, s', steps, rip', registers', memory', reads', rax'⟩ :=
    copy_steps frame.top target sources 0 s rel.rbp loaded
      (fun index bound j inSources lane => ne_of_below (apart index bound) (targetBelow j inSources lane))
      (fun j inSources src mem i lane => slot_lanes_ne _ (small src mem) (by unfold slotLimit; omega)
        (by have := away src mem; omega) i lane)
      (fun j j' less inSources i lane =>
        slot_lanes_ne _ (by unfold slotLimit; omega) (by unfold slotLimit; omega) (by omega) i lane)
  refine ⟨n, s', steps, ?_⟩
  simp only [Machine.copied]
  refine ⟨?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_⟩
  · rw [rip']
    exact rel.advance _
  · rw [registers' _ (by decide)]; exact rel.rbp
  · rw [registers' _ (by decide)]; exact rel.rsp
  · rw [rax', rel.acc]
  · intro slot inFrame'
    simp only [writeSlots, List.length_map]
    by_cases inside : target ≤ slot ∧ slot < target + sources.length
    · rw [if_pos inside]
      obtain ⟨j, rfl⟩ : ∃ j, slot = target + 0 + j := ⟨slot - target, by omega⟩
      rw [reads' j (by omega), show target + 0 + j - target = j by omega]
      simp [List.getD_eq_getElem?_getD, List.getElem?_eq_getElem (show j < sources.length by omega)]
    · rw [if_neg inside, ← rel.slots slot inFrame']
      apply read64_congr
      intro lane
      apply memory'
      intro j bound lane'
      exact slot_lanes_ne _ (by unfold slotLimit; omega) (by unfold slotLimit; omega) (by omega) lane lane'
  · rw [← rel.saved]
    apply read64_congr
    intro lane
    apply memory'
    intro j bound lane'
    rw [show frame.top - 8 + BitVec.ofNat 64 lane.val = frame.top - BitVec.ofNat 64 (8 - lane.val) from
      depth_lane _ 8 lane.val (by omega), targetLane j bound lane'.val (by omega)]
    exact depth_ne _ (by omega) (by omega) (by omega)
  · intro register other
    obtain ⟨zero, -⟩ := not_scratch other
    rw [registers' register zero]
    exact rel.preserved register other
  · intro address outside
    rw [memory' address (fun j bound lane => ne_of_below outside (targetBelow j bound lane))]
    exact rel.unchanged address outside

/-- The activation has returned `values` to its caller: they replace the
arguments, and rax holds the last one. -/
structure Frame.Exit (frame : Frame) (s : State) (values : List (BitVec 64)) : Prop where
  rip : s.rip = read64 frame.entry frame.top
  rsp : s.registers rspRegister = frame.top + 8
  rbp : s.registers rbpRegister = frame.saved
  value : ∀ v, values.getLast? = some v → s.registers 0 = v
  results : ∀ k (bound : k < values.length),
    read64 s.memory (frame.top - BitVec.ofNat 64 (8 * k + 16)) = values[k]
  preserved : ∀ register, ¬Scratch register → s.registers register = frame.preserved register
  unchanged : ∀ address, ¬Below frame.top frame.window address → s.memory address = frame.entry address

theorem readSlots_eq_map (slots : Nat → BitVec 64) (args : List Nat) : readSlots slots args = args.map slots := by
  induction args <;> simp_all [readSlots]

/-- A return: copy the results to the first slots, then the epilogue. -/
theorem ret_simulates (rel : Rel frame s m) (fits : frame.Fits) {sources : List Nat} {bound funcs : Nat}
    (loaded : CodeAt s.memory s.rip (copyBytes 0 sources 0 ++ epilogueBytes))
    (apart : ∀ index, index < (Instr.ret sources).size →
      ¬Below frame.top frame.window (s.rip + BitVec.ofNat 64 index))
    (fitted : (Instr.ret sources).Fits frame.slots bound funcs) :
    ∃ n s', Steps n s s' ∧ frame.Exit s' (readSlots m.slots sources) := by
  have limit : frame.slots ≤ 2 ^ 20 := fits.slots
  have bounded := fits.bounded
  simp only [Instr.Fits] at fitted
  have count : sources.length ≤ frame.slots := by
    cases sources with
    | nil => simp
    | cons src rest => have := fitted src (by simp); omega
  have size : (Instr.ret sources).size = 14 * sources.length + 5 := rfl
  have values : (sources.map fun src => read64 s.memory (frameSlotAddress (frame.top - 8) src)) =
      readSlots m.slots sources := by
    rw [readSlots_eq_map]
    exact List.map_congr_left fun src mem => rel.slots src (fitted src mem).1
  obtain ⟨n1, s1, steps1, rel1⟩ := copy_simulates rel fits loaded.prefix
    (fun index small => apart index (by omega)) (by omega)
    (fun src mem => by have := (fitted src mem).1; unfold slotLimit; omega)
    (fun src mem => .inr (by have := (fitted src mem).2; omega))
  rw [values] at rel1
  have loaded1 : CodeAt s1.memory s1.rip epilogueBytes := by
    have tail := loaded.suffix
    rw [copyBytes_length] at tail
    have rip1 : s1.rip = s.rip + BitVec.ofNat 64 (14 * sources.length) := by
      rw [rel1.rip, rel.advance]
      rfl
    intro index small
    have epilogueLength : epilogueBytes.length = 5 := by decide
    have addr : s1.rip + BitVec.ofNat 64 index = s.rip + BitVec.ofNat 64 (14 * sources.length + index) := by
      rw [rip1, BitVec.add_assoc, ← BitVec.ofNat_add]
    have away := apart (14 * sources.length + index) (by omega)
    rw [addr, rel1.unchanged _ away, ← rel.unchanged _ away, BitVec.ofNat_add, ← BitVec.add_assoc]
    exact tail index small
  obtain ⟨n2, s2, steps2, left, memory2⟩ := epilogue_simulates rel1 fits loaded1
  refine ⟨_, s2, steps1.trans steps2, left.rip, left.rsp, left.rbp, ?_, ?_, left.preserved, left.unchanged⟩
  · intro v last
    rw [left.value]
    simp [Machine.copied, last]
  · intro k small
    rw [readSlots_length] at small
    rw [memory2, ← slot_eq _ (by unfold slotLimit; omega), rel1.slots k (by omega)]
    simp only [Machine.copied, writeSlots, readSlots_length, Nat.zero_le, true_and, Nat.zero_add, if_pos small,
      Nat.sub_zero]
    simp [List.getD_eq_getElem?_getD, List.getElem?_eq_getElem (show k < (readSlots m.slots sources).length by
      rw [readSlots_length]; exact small)]

/-- What a callee guarantees: `s'` is `s` after the function returned
`values`, having changed at most the `window` stack bytes below the return
address. The results replace the arguments, and rax holds the last one. -/
structure Returned (window : Nat) (s s' : State) (values : List (BitVec 64)) : Prop where
  rip : s'.rip = read64 s.memory (s.registers rspRegister)
  rsp : s'.registers rspRegister = s.registers rspRegister + 8
  rbp : s'.registers rbpRegister = s.registers rbpRegister
  value : ∀ v, values.getLast? = some v → s'.registers 0 = v
  results : ∀ k (bound : k < values.length),
    read64 s'.memory (s.registers rspRegister - BitVec.ofNat 64 (8 * k + 16)) = values[k]
  preserved : ∀ register, ¬Scratch register → s'.registers register = s.registers register
  unchanged : ∀ address, ¬Below (s.registers rspRegister) window address → s'.memory address = s.memory address

/-- Function `callee` of `binary`, loaded at `imageBase` and entered by a near
call with `args` just below the return address, returns `values` using at most
`window` stack bytes. -/
def Contract (binary : Binary) (imageBase : BitVec 64) (window callee : Nat) (args : List (BitVec 64))
    (values : List (BitVec 64)) : Prop :=
  ∀ s : State, window ≤ 2 ^ 62 → CodeAt s.memory imageBase binary.image →
    (∀ index, index < binary.image.length →
      ¬Below (s.registers rspRegister) window (imageBase + BitVec.ofNat 64 index)) →
    s.rip = imageBase + BitVec.ofNat 64 (binary.entries.getD callee 0) →
    (∀ k (bound : k < args.length),
      read64 s.memory (s.registers rspRegister - BitVec.ofNat 64 (8 * k + 16)) = args[k]) →
    ∃ n s', Steps n s s' ∧ Returned window s s' values

theorem Contract.mono {binary : Binary} {imageBase : BitVec 64} {window window' callee : Nat}
    {args values : List (BitVec 64)} (contract : Contract binary imageBase window callee args values)
    (larger : window ≤ window') : Contract binary imageBase window' callee args values := by
  intro s bounded loaded apart entry params
  obtain ⟨n, s', steps, returned⟩ := contract s (by omega) loaded
    (fun index bound below => apart index bound (below.mono larger)) entry params
  exact ⟨n, s', steps, { returned with
    unchanged := fun address outside => returned.unchanged address (fun below => outside (below.mono larger)) }⟩

/-- A call: copy the arguments below the stack, `call rel32`, the callee's
contract carries the activation across, then copy the results to `target`. -/
theorem call_simulates {binary : Binary} {imageBase : BitVec 64} {place : Place} {callee : Nat}
    {args : List Nat} {target count : Nat} (rel : Rel frame s m) (fits : frame.Fits)
    (loaded : CodeAt s.memory s.rip ((Instr.call callee args target count).bytes place m.pc))
    (apart : ∀ index, index < (Instr.call callee args target count).size →
      ¬Below frame.top frame.window (s.rip + BitVec.ofNat 64 index))
    (placeSlots : place.slots = frame.slots) (placeEntries : place.entries = binary.entries)
    (base : frame.base = imageBase + BitVec.ofNat 64 place.body)
    (small : place.body + m.pc + (Instr.call callee args target count).size < 2 ^ 31)
    (entrySmall : binary.entries.getD callee 0 < 2 ^ 31)
    (argsFit : ∀ slot ∈ args, slot < frame.slots) (argsCount : args.length ≤ frame.slots)
    (targetFit : target + count ≤ frame.slots) (positive : 0 < count)
    (image : CodeAt frame.entry imageBase binary.image)
    (imageApart : ∀ index, index < binary.image.length →
      ¬Below frame.top frame.window (imageBase + BitVec.ofNat 64 index))
    {inner : Nat} (innerFits : frameBytes frame.slots + 16 + inner ≤ frame.window)
    (room : 8 * args.length + 16 ≤ inner)
    {values : List (BitVec 64)} (contract : Contract binary imageBase inner callee (readSlots m.slots args) values)
    (counted : values.length = count) :
    ∃ n s', Steps n s s' ∧
      Rel frame s' { m with pc := m.pc + (Instr.call callee args target count).size, acc := values.getLastD m.acc, slots := writeSlots m.slots target values } := by
  have limit : frame.slots ≤ 2 ^ 20 := fits.slots
  have bounded := fits.bounded
  have big := frameBytes_slots frame.slots
  have le := frameBytes_le frame.slots
  have mul := frameBytes_mul frame.slots
  have size : (Instr.call callee args target count).size = 14 * args.length + 5 + 14 * count := rfl
  generalize fbEq : frameBytes frame.slots = fb at *
  have top := frame.top
  let first := argBase frame.slots
  have firstEq : 8 * first = fb + 16 := by simp only [first, argBase, frameSize_eq, fbEq]; omega
  -- every address the call touches, as a depth below `frame.top`
  have targetLane : ∀ j, j < args.length → ∀ lane, lane < 8 →
      frameSlotAddress (frame.top - 8) (first + 0 + j) + BitVec.ofNat 64 lane =
        frame.top - BitVec.ofNat 64 (fb + 32 + 8 * j - lane) := by
    intro j bound lane small
    rw [slot_lane _ (by unfold slotLimit; omega) _ small]
    congr 2
    omega
  have sourceLane : ∀ slot, slot < frame.slots → ∀ lane, lane < 8 →
      frameSlotAddress (frame.top - 8) slot + BitVec.ofNat 64 lane =
        frame.top - BitVec.ofNat 64 (8 * slot + 16 - lane) :=
    fun slot bound lane small => slot_lane _ (by unfold slotLimit; omega) _ small
  have savedLane : ∀ lane, lane < 8 →
      frame.top - 8 + BitVec.ofNat 64 lane = frame.top - BitVec.ofNat 64 (8 - lane) :=
    fun lane small => depth_lane _ 8 lane (by omega)
  have pushLane : ∀ lane, lane < 8 →
      frame.top - BitVec.ofNat 64 (fb + 16) + BitVec.ofNat 64 lane =
        frame.top - BitVec.ofNat 64 (fb + 16 - lane) :=
    fun lane small => depth_lane _ _ lane (by omega)
  have targetBelow : ∀ j, j < args.length → ∀ lane : Fin 8,
      Below frame.top frame.window (frameSlotAddress (frame.top - 8) (first + 0 + j) + BitVec.ofNat 64 lane.val) := by
    intro j bound lane
    rw [targetLane j bound lane.val (by omega)]
    exact below_depth _ (by omega) (by omega) (by omega)
  have pushBelow : ∀ lane : Fin 8,
      Below frame.top frame.window (frame.top - BitVec.ofNat 64 (fb + 16) + BitVec.ofNat 64 lane.val) := by
    intro lane
    rw [pushLane lane.val lane.isLt]
    exact below_depth _ (by omega) (by omega) (by omega)
  -- the argument copies
  have encoded : (Instr.call callee args target count).bytes place m.pc = copyBytes first args 0 ++
      callBytes (relative (place.body + m.pc + 14 * args.length + 5) (binary.entries.getD callee 0)) ++
      copyBytes target (slotRange first count) 0 := by
    simp only [Instr.bytes, placeSlots, placeEntries, first]
  rw [encoded] at loaded
  have callLength : ∀ d, (callBytes d).length = 5 := fun d => by simp [callBytes, displacementBytes]
  have address : ∀ k, k < 2 ^ 21 → frame.top - BitVec.ofNat 64 (fb + 16) - BitVec.ofNat 64 (8 * k + 16) =
      frameSlotAddress (frame.top - 8) (first + 0 + k) := by
    intro k bound
    rw [slot_eq _ (by unfold slotLimit; omega),
      show 8 * (first + 0 + k) + 16 = fb + 32 + 8 * k by omega]
    bv_omega
  obtain ⟨n1, s1, steps1, rip1, registers1, memory1, reads1, -⟩ := copy_steps frame.top first args 0 s rel.rbp
    loaded.prefix.prefix
    (by
      intro index bound j inArgs lane
      exact ne_of_below (apart index (by omega)) (targetBelow j inArgs lane))
    (by
      intro j inArgs slot mem i lane
      rw [sourceLane slot (argsFit slot mem) i.val (by omega), targetLane j inArgs lane.val (by omega)]
      have := argsFit slot mem
      exact depth_ne _ (by omega) (by omega) (by omega))
    (by
      intro j j' less inArgs i lane
      rw [targetLane j (by omega) i.val (by omega), targetLane j' inArgs lane.val (by omega)]
      exact depth_ne _ (by omega) (by omega) (by omega))
  -- `call rel32`
  let displacement := relative (place.body + m.pc + 14 * args.length + 5) (binary.entries.getD callee 0)
  have callLoaded : CodeAt s1.memory s1.rip (callBytes displacement) := by
    have tail := loaded.prefix.suffix
    rw [copyBytes_length] at tail
    rw [rip1]
    intro index bound
    rw [memory1 _ (by
      intro j inArgs lane
      have := apart (14 * args.length + index) (by simp [callBytes, displacementBytes] at bound; omega)
      rw [BitVec.ofNat_add, ← BitVec.add_assoc] at this
      exact ne_of_below this (targetBelow j inArgs lane))]
    exact tail index bound
  let s2 := s1.call displacement (callBytes displacement).length
  have step2 := call_step s1 s2 displacement callLoaded rfl
  have rsp2 : s2.registers rspRegister = frame.top - BitVec.ofNat 64 (fb + 16) := by
    simp only [s2, State.call, rspRegister, if_pos]
    rw [registers1 4 (by decide)]
    have := rel.rsp
    rw [fbEq] at this
    simp only [rspRegister] at this
    rw [this]
    bv_omega
  have next : s1.rip + BitVec.ofNat 64 (callBytes displacement).length =
      frame.base + BitVec.ofNat 64 (m.pc + 14 * args.length + 5) := by
    rw [rip1, rel.rip, callLength]
    bv_omega
  have memory2 : s2.memory = write64 s1.memory (frame.top - BitVec.ofNat 64 (fb + 16))
      (frame.base + BitVec.ofNat 64 (m.pc + 14 * args.length + 5)) := by
    simp only [s2, State.call]
    rw [next]
    congr 1
  have rip2 : s2.rip = imageBase + BitVec.ofNat 64 (binary.entries.getD callee 0) := by
    simp only [s2, State.call]
    rw [next, base, BitVec.add_assoc imageBase, ← BitVec.ofNat_add]
    rw [show place.body + (m.pc + 14 * args.length + 5) = place.body + m.pc + 14 * args.length + 5 by omega]
    exact relative_eq _ _ _ (by omega) entrySmall
  -- s2 agrees with the entry memory outside the frame's window
  have outside2 : ∀ address, ¬Below frame.top frame.window address → s2.memory address = frame.entry address := by
    intro address outside
    rw [memory2, write64_frame _ _ _ _ (fun lane => ne_of_below outside (pushBelow lane)),
      memory1 _ (fun j inArgs lane => ne_of_below outside (targetBelow j inArgs lane))]
    exact rel.unchanged address outside
  -- the callee
  obtain ⟨n3, s3, steps3, returned⟩ := contract s2 (by omega)
    (by
      intro index bound
      rw [outside2 _ (imageApart index bound)]
      exact image index bound)
    (by
      intro index bound below
      rw [rsp2] at below
      exact imageApart index bound ((below.shift (by omega)).mono (by omega)))
    rip2
    (by
      intro k bound
      rw [readSlots_length] at bound
      rw [rsp2, readSlots_getElem _ _ _ bound, ← rel.slots _ (argsFit _ (List.getElem_mem _)), ← reads1 k bound]
      rw [address k (by omega), memory2, read64_frame]
      intro i lane
      rw [targetLane k bound i.val (by omega), pushLane lane.val lane.isLt]
      exact depth_ne _ (by omega) (by omega) (by omega))
  -- the activation after the call
  have frameKept : ∀ d, d ≤ fb + 8 → 0 < d →
      s3.memory (frame.top - BitVec.ofNat 64 d) = s.memory (frame.top - BitVec.ofNat 64 d) := by
    intro d small positive
    rw [returned.unchanged _ (by rw [rsp2]; exact not_below_above _ (by omega) (by omega)), memory2,
      write64_frame _ _ _ _ (by
        intro lane
        rw [pushLane lane.val lane.isLt]
        exact depth_ne _ (by omega) (by omega) (by omega)),
      memory1 _ (by
        intro j inArgs lane
        rw [targetLane j inArgs lane.val (by omega)]
        exact depth_ne _ (by omega) (by omega) (by omega))]
  let m3 : Machine := { m with pc := m.pc + 14 * args.length + 5, acc := s3.registers 0 }
  have rel3 : Rel frame s3 m3 := by
    refine ⟨?_, ?_, ?_, rfl, ?_, ?_, ?_, ?_⟩
    · rw [returned.rip, rsp2, memory2, read64_write64]
    · rw [returned.rbp]
      simp only [s2, State.call, rbpRegister, if_neg (show (5 : Register) ≠ 4 by decide)]
      rw [registers1 5 (by decide)]
      exact rel.rbp
    · rw [returned.rsp, rsp2, fbEq]
      bv_omega
    · intro other inFrame
      rw [← rel.slots other inFrame]
      apply read64_congr
      intro lane
      rw [sourceLane other inFrame lane.val (by omega)]
      exact frameKept _ (by omega) (by omega)
    · rw [← rel.saved]
      apply read64_congr
      intro lane
      rw [savedLane lane.val lane.isLt]
      exact frameKept _ (by omega) (by omega)
    · intro register other
      obtain ⟨zero, -, four, -, -⟩ := not_scratch other
      rw [returned.preserved register other]
      simp only [s2, State.call, if_neg four]
      rw [registers1 register zero]
      exact rel.preserved register other
    · intro address outside
      rw [returned.unchanged _ (by
        rw [rsp2]
        intro below
        exact outside ((below.shift (by omega)).mono (by omega)))]
      exact outside2 address outside
  -- the results, copied from below the stack to `target`
  have results3 : ∀ k (bound : k < values.length),
      read64 s3.memory (frameSlotAddress (frame.top - 8) (first + k)) = values[k] := by
    intro k bound
    rw [show first + k = first + 0 + k by omega, ← address k (by omega), ← rsp2]
    exact returned.results k bound
  have addr3 : ∀ index, s3.rip + BitVec.ofNat 64 index =
      s.rip + BitVec.ofNat 64 (14 * args.length + 5 + index) := by
    intro index
    rw [rel3.rip, rel.rip, BitVec.add_assoc, BitVec.add_assoc, ← BitVec.ofNat_add, ← BitVec.ofNat_add]
    congr 2
    show m.pc + 14 * args.length + 5 + index = _
    omega
  have loaded3 : CodeAt s3.memory s3.rip (copyBytes target (slotRange first count) 0) := by
    have tail := loaded.suffix
    rw [List.length_append, copyBytes_length, callLength] at tail
    intro index bound
    rw [copyBytes_length, slotRange_length] at bound
    have away := apart (14 * args.length + 5 + index) (by omega)
    rw [addr3, rel3.unchanged _ away, ← rel.unchanged _ away, BitVec.ofNat_add, ← BitVec.add_assoc]
    exact tail index (by rw [copyBytes_length, slotRange_length]; omega)
  have inRange : ∀ src ∈ slotRange first count, first ≤ src ∧ src < first + count := by
    intro src mem
    rw [slotRange_eq, List.mem_range'_1] at mem
    exact mem
  obtain ⟨n4, s4, steps4, rel4⟩ := copy_simulates rel3 fits (target := target) loaded3
    (fun index bound => by
      rw [slotRange_length] at bound
      rw [addr3]
      exact apart _ (by omega))
    (by rw [slotRange_length]; omega)
    (fun src mem => by have := inRange src mem; unfold slotLimit; omega)
    (fun src mem => .inr (by have := inRange src mem; rw [slotRange_length]; omega))
  have got : (slotRange first count).map (fun src => read64 s3.memory (frameSlotAddress (frame.top - 8) src)) =
      values := by
    apply List.ext_getElem (by rw [List.length_map, slotRange_length, counted])
    intro k bound bound'
    rw [List.getElem_map, ← results3 k bound']
    simp only [slotRange_eq, List.getElem_range', Nat.one_mul]
  rw [got, slotRange_length] at rel4
  refine ⟨_, s4, (steps1.trans (.cons step2 steps3)).trans steps4, rel4.congr ?_ ?_ fun _ _ => rfl⟩
  · simp only [Machine.copied, m3, size]
    omega
  · simp only [Machine.copied, m3]
    cases values with
    | nil => simp at counted; omega
    | cons v rest => rfl

theorem CodeAt.middle {memory : Memory} {address : BitVec 64} {first middle rest : List UInt8}
    (loaded : CodeAt memory address (first ++ middle ++ rest)) :
    CodeAt memory (address + BitVec.ofNat 64 first.length) middle := by
  rw [List.append_assoc] at loaded
  exact loaded.suffix.prefix

/-- Where the activation's code is: the body sits at `frame.base` in the entry
memory, inside the program image, apart from the stack window. -/
structure Body (frame : Frame) (binary : Binary) (imageBase : BitVec 64) (place : Place)
    (instrs : List Instr) : Prop where
  loaded : CodeAt frame.entry frame.base (encodeFrom place 0 instrs)
  apart : ∀ index, index < codeSize instrs → ¬Below frame.top frame.window (frame.base + BitVec.ofNat 64 index)
  slots : place.slots = frame.slots
  entries : place.entries = binary.entries
  base : frame.base = imageBase + BitVec.ofNat 64 place.body
  small : place.body + codeSize instrs ≤ imageLimit
  entrySmall : ∀ callee, binary.entries.getD callee 0 ≤ imageLimit
  image : CodeAt frame.entry imageBase binary.image
  imageApart : ∀ index, index < binary.image.length →
    ¬Below frame.top frame.window (imageBase + BitVec.ofNat 64 index)
  fits : ∀ i ∈ instrs, i.Fits frame.slots (codeSize instrs) binary.codes.length

variable {binary : Binary} {imageBase : BitVec 64} {place : Place} {instrs : List Instr}

/-- The fetched instruction's bytes are at rip, apart from the stack window. -/
theorem Body.fetch (body : Body frame binary imageBase place instrs) (rel : Rel frame s m) {i : Instr}
    (fetched : Lanius.Mini.fetch instrs m.pc = some i) :
    CodeAt s.memory s.rip (i.bytes place m.pc) ∧
      (∀ index, index < i.size → ¬Below frame.top frame.window (s.rip + BitVec.ofNat 64 index)) ∧
      m.pc + i.size ≤ codeSize instrs := by
  obtain ⟨pre, post, split, length, bound⟩ := fetch_bytes place fetched
  have apart : ∀ index, index < i.size → ¬Below frame.top frame.window (s.rip + BitVec.ofNat 64 index) := by
    intro index small
    rw [rel.rip, BitVec.add_assoc, ← BitVec.ofNat_add]
    exact body.apart _ (by omega)
  refine ⟨?_, apart, bound⟩
  have inEntry : CodeAt frame.entry (frame.base + BitVec.ofNat 64 m.pc) (i.bytes place m.pc) := by
    have whole := body.loaded
    rw [split, Instr.encode_eq] at whole
    have := CodeAt.middle whole
    rwa [length] at this
  intro index small
  have small' : index < i.size := by rw [Instr.bytes_length] at small; exact small
  rw [rel.unchanged _ (apart index small'), rel.rip]
  exact inEntry index small

/-- One abstract step, given the callees' contracts. -/
theorem step_simulates (body : Body frame binary imageBase place instrs) (fits : frame.Fits) {calls : Calls}
    (callContract : ∀ callee vals value, calls callee vals value → ∃ inner,
      frameBytes frame.slots + 16 + inner ≤ frame.window ∧ 8 * vals.length + 16 ≤ inner ∧
        Contract binary imageBase inner callee vals value)
    (rel : Rel frame s m) {m' : Machine} (step : Step calls instrs m m') :
    ∃ n s', Steps n s s' ∧ Rel frame s' m' := by
  have small := body.small
  have limit : imageLimit = 2 ^ 30 := rfl
  cases step with
  | @straight i _ fetched isStraight =>
    obtain ⟨loaded, -, -⟩ := body.fetch rel fetched
    have fitted := body.fits i (fetch_mem fetched)
    cases i with
    | imm value => exact imm_simulates rel loaded
    | load slot => exact load_simulates rel fitted loaded
    | store slot => exact store_simulates rel fits fitted loaded
    | neg => exact neg_simulates rel loaded
    | op word operation slot => exact op_simulates word operation rel fitted loaded
    | cmp word operation slot => exact cmp_simulates word operation rel fitted loaded
    | jmp | jz | call | ret => simp [Instr.straight] at isStraight
  | @jmp target _ fetched =>
    obtain ⟨loaded, -, bound⟩ := body.fetch rel fetched
    have fitted : target ≤ codeSize instrs := body.fits _ (fetch_mem fetched)
    exact jmp_simulates rel (by simp only [Instr.size] at bound; omega) (by omega) loaded
  | @jzTaken target _ fetched zero =>
    obtain ⟨loaded, -, bound⟩ := body.fetch rel fetched
    have fitted : target ≤ codeSize instrs := body.fits _ (fetch_mem fetched)
    have := jz_simulates rel (by simp only [Instr.size] at bound; omega) (by omega) loaded
    rwa [if_pos zero] at this
  | @jzNot target _ fetched nonzero =>
    obtain ⟨loaded, -, bound⟩ := body.fetch rel fetched
    have fitted : target ≤ codeSize instrs := body.fits _ (fetch_mem fetched)
    have := jz_simulates rel (by simp only [Instr.size] at bound; omega) (by omega) loaded
    rwa [if_neg nonzero] at this
  | @call callee args target count values _ fetched returns counted =>
    obtain ⟨loaded, apart, bound⟩ := body.fetch rel fetched
    obtain ⟨-, argsCount, argsFit, targetFit, positive⟩ := body.fits _ (fetch_mem fetched)
    obtain ⟨inner, innerFits, room, contract⟩ := callContract _ _ _ returns
    rw [readSlots_length] at room
    exact call_simulates rel fits loaded apart body.slots body.entries body.base (by omega)
      (by have := body.entrySmall callee; omega) argsFit argsCount targetFit positive body.image body.imageApart
      innerFits room contract counted

/-- The bytes of a body simulate its abstract run to `ret`. -/
theorem body_simulates (body : Body frame binary imageBase place instrs) (fits : frame.Fits) {calls : Calls}
    (callContract : ∀ callee vals value, calls callee vals value → ∃ inner,
      frameBytes frame.slots + 16 + inner ≤ frame.window ∧ 8 * vals.length + 16 ≤ inner ∧
        Contract binary imageBase inner callee vals value)
    {m m' : Machine} {sources : List Nat} (run : Star calls instrs m m')
    (atRet : fetch instrs m'.pc = some (.ret sources)) :
    ∀ s, Rel frame s m → ∃ n s', Steps n s s' ∧ frame.Exit s' (readSlots m'.slots sources) := by
  induction run with
  | refl m =>
    intro s rel
    obtain ⟨loaded, apart, -⟩ := body.fetch rel atRet
    exact ret_simulates rel fits loaded apart (body.fits _ (fetch_mem atRet))
  | step head _ ih =>
    intro s rel
    obtain ⟨n, middle, steps, middleRel⟩ := step_simulates body fits callContract rel head
    obtain ⟨n', s', rest, exit⟩ := ih atRet middle middleRel
    exact ⟨_, s', steps.trans rest, exit⟩

end Lanius.Mini
