import Lanius.Mini.WordSteps
import Lanius.Mini.DivSteps
import Lanius.Mini.Frame
import Lanius.Mini.Fits
import Lanius.Mini.FloatSteps

/-! The x86 bytes of each abstract instruction simulate it. One relation holds
between an x86 state and an abstract machine throughout an activation. The
activation may change only the `window` stack bytes below its return address
and the heap; everything else, the program image included, stays as it was at
entry. The heap is `limit` bytes from the base in r12, with the limit in r14
and the allocation cursor in r13; heap addresses are the abstract ones offset
by the base. -/

namespace Lanius.Mini
open Lanius.X86.Machine

/-- Registers compiled code may change: rax, rcx, rsp, rbp, r11, r13, and the
system call arguments rdx, rsi and rdi. -/
def Scratch (register : Register) : Prop :=
  register = 0 ∨ register = rcxRegister ∨ register = rspRegister ∨ register = rbpRegister ∨
    register = r11Register ∨ register = cursorRegister ∨ register = rdxRegister ∨ register = rsiRegister ∨
    register = rdiRegister ∨ register = fspRegister

theorem not_scratch {register : Register} (other : ¬Scratch register) :
    register ≠ 0 ∧ register ≠ 1 ∧ register ≠ 4 ∧ register ≠ 5 ∧ register ≠ 11 ∧ register ≠ 13 ∧
      register ≠ 2 ∧ register ≠ 6 ∧ register ≠ 7 := by
  simp only [Scratch, rcxRegister, rspRegister, rbpRegister, r11Register, cursorRegister, rdxRegister,
    rsiRegister, rdiRegister, fspRegister, not_or] at other
  obtain ⟨a, b, c, d, e, f, g, h, i, -⟩ := other
  exact ⟨a, b, c, d, e, f, g, h, i⟩

theorem heapBase_not_scratch : ¬Scratch heapBaseRegister := by unfold Scratch; decide
theorem limit_not_scratch : ¬Scratch limitRegister := by unfold Scratch; decide
theorem stack_not_scratch : ¬Scratch stackRegister := by unfold Scratch; decide

/-- The `limit` bytes from `base`. -/
def InHeap (base : BitVec 64) (limit : Nat) (address : BitVec 64) : Prop :=
  ∃ a, a < limit ∧ address = base + BitVec.ofNat 64 a

/-- The heap as the registers of `s` place it. -/
def _root_.Lanius.X86.Machine.State.InHeap (s : State) : BitVec 64 → Prop :=
  Lanius.Mini.InHeap (s.registers heapBaseRegister) (s.registers limitRegister).toNat

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
  /-- Stack bytes below the limit in r15 that a call may write before the callee's check. -/
  guard : Nat

def Frame.heapBase (frame : Frame) : BitVec 64 := frame.preserved heapBaseRegister
def Frame.heapLimit (frame : Frame) : Nat := (frame.preserved limitRegister).toNat
def Frame.InHeap (frame : Frame) : BitVec 64 → Prop := Lanius.Mini.InHeap frame.heapBase frame.heapLimit

/-- Sizes that keep the stack arithmetic exact, and a heap apart from the
stack window and the return address. -/
structure Frame.Fits (frame : Frame) : Prop where
  slots : frame.slots ≤ frameLimit
  window : frameBytes frame.slots + 16 ≤ frame.window
  bounded : frame.window ≤ 2 ^ 62
  heapSmall : frame.heapLimit < 2 ^ 62
  heapApart : ∀ address, frame.InHeap address → ¬Below (frame.top + 8) (frame.window + 8) address
  /-- The window runs from `guard` bytes below the stack limit in r15, which is above 4 GiB. -/
  stack : (frame.preserved stackRegister).toNat + frame.window = frame.top.toNat + frame.guard
  high : 2 ^ 32 ≤ (frame.preserved stackRegister).toNat
  /-- The prologue's check passed. -/
  checked : frameBytes frame.slots + 8 + frame.guard ≤ frame.window

/-- The x86 state holds the abstract machine in this activation. -/
structure Rel (frame : Frame) (s : State) (m : Machine) : Prop where
  rip : s.rip = frame.base + BitVec.ofNat 64 m.pc
  rbp : s.registers rbpRegister = frame.top - 8
  rsp : s.registers rspRegister = frame.top - BitVec.ofNat 64 (frameBytes frame.slots + 8)
  acc : s.registers 0 = m.acc
  slots : ∀ slot, slot < frame.slots → read64 s.memory (frameSlotAddress (frame.top - 8) slot) = m.slots slot
  saved : read64 s.memory (frame.top - 8) = frame.saved
  preserved : ∀ register, ¬Scratch register → s.registers register = frame.preserved register
  unchanged : ∀ address, ¬Below frame.top frame.window address → ¬frame.InHeap address →
    s.memory address = frame.entry address
  cursor : s.registers cursorRegister = BitVec.ofNat 64 m.heap.cursor
  limit : m.heap.limit = frame.heapLimit
  /-- No frame memory on x86 yet: the heap's top is its limit. -/
  top : m.heap.top = m.heap.limit
  /-- rbx holds the frame pointer. -/
  fsp : s.registers fspRegister = BitVec.ofNat 64 m.heap.fsp
  heap : ∀ a, a < m.heap.limit → s.memory (frame.heapBase + BitVec.ofNat 64 a) = m.heap.bytes a
  /-- The trace so far: only system calls add to it. -/
  io : s.io = m.heap.io

/-- The activation has left with `value` in rax. -/
structure Frame.Left (frame : Frame) (s : State) (value : BitVec 64) : Prop where
  rip : s.rip = read64 frame.entry frame.top
  rsp : s.registers rspRegister = frame.top + 8
  rbp : s.registers rbpRegister = frame.saved
  value : s.registers 0 = value
  preserved : ∀ register, ¬Scratch register → s.registers register = frame.preserved register
  unchanged : ∀ address, ¬Below frame.top frame.window address → ¬frame.InHeap address →
    s.memory address = frame.entry address

variable {frame : Frame} {s s' : State} {m : Machine} {slot : Nat} {value : BitVec 64}

theorem Below.up {top address : BitVec 64} {window : Nat} (below : Below top window address)
    (bound : window ≤ 2 ^ 62) : Below (top + 8) (window + 8) address := by
  unfold Below at *
  obtain ⟨positive, within⟩ := below
  constructor <;> bv_omega

/-- The stack window holds no heap byte. -/
theorem Frame.Fits.notHeap (fits : frame.Fits) {address : BitVec 64} (below : Below frame.top frame.window address) :
    ¬frame.InHeap address :=
  fun inHeap => fits.heapApart address inHeap (below.up fits.bounded)

/-- Nor does the return address. -/
theorem Frame.Fits.returnNotHeap (fits : frame.Fits) {lane : Nat} (small : lane < 8) :
    ¬frame.InHeap (frame.top + BitVec.ofNat 64 lane) := by
  intro inHeap
  apply fits.heapApart _ inHeap
  have bounded := fits.bounded
  unfold Below
  constructor <;> bv_omega

theorem Frame.inHeap (frame : Frame) {a : Nat} (below : a < frame.heapLimit) :
    frame.InHeap (frame.heapBase + BitVec.ofNat 64 a) := ⟨a, below, rfl⟩

theorem Rel.heapBase (rel : Rel frame s m) : s.registers heapBaseRegister = frame.heapBase :=
  rel.preserved _ heapBase_not_scratch

theorem Rel.limitNat (rel : Rel frame s m) : (s.registers limitRegister).toNat = m.heap.limit := by
  rw [rel.preserved _ limit_not_scratch, rel.limit]; rfl

theorem Rel.advance (rel : Rel frame s m) (size : Nat) :
    s.rip + BitVec.ofNat 64 size = frame.base + BitVec.ofNat 64 (m.pc + size) := by
  rw [rel.rip, BitVec.ofNat_add, BitVec.add_assoc]

/-- Instructions that write only rax and rcx keep the relation, given the new accumulator. -/
theorem Rel.accumulate (rel : Rel frame s m) (memory : s'.memory = s.memory) (size : Nat)
    (rip : s'.rip = s.rip + BitVec.ofNat 64 size)
    (registers : ∀ register, register ≠ 0 → register ≠ 1 → s'.registers register = s.registers register)
    (acc : s'.registers 0 = value) (io : s'.io = s.io := by rfl) :
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
  cursor := (registers _ (by decide) (by decide)).trans rel.cursor
  limit := rel.limit
  top := rel.top
  fsp := (registers _ (by decide) (by decide)).trans rel.fsp
  heap := by rw [memory]; exact rel.heap
  io := io.trans rel.io

/-- `Rel.accumulate` for code that also writes r11. -/
theorem Rel.accumulate11 (rel : Rel frame s m) (memory : s'.memory = s.memory) (size : Nat)
    (rip : s'.rip = s.rip + BitVec.ofNat 64 size)
    (registers : ∀ register, register ≠ 0 → register ≠ 1 → register ≠ 11 →
      s'.registers register = s.registers register)
    (acc : s'.registers 0 = value) (io : s'.io = s.io := by rfl) :
    Rel frame s' { m with pc := m.pc + size, acc := value } where
  rip := rip.trans (rel.advance size)
  rbp := (registers _ (by decide) (by decide) (by decide)).trans rel.rbp
  rsp := (registers _ (by decide) (by decide) (by decide)).trans rel.rsp
  acc := acc
  slots := by rw [memory]; exact rel.slots
  saved := by rw [memory]; exact rel.saved
  preserved register other := by
    obtain ⟨zero, one, -, -, eleven, -⟩ := not_scratch other
    rw [registers register zero one eleven]
    exact rel.preserved register other
  unchanged := by rw [memory]; exact rel.unchanged
  cursor := (registers _ (by decide) (by decide) (by decide)).trans rel.cursor
  limit := rel.limit
  top := rel.top
  fsp := (registers _ (by decide) (by decide) (by decide)).trans rel.fsp
  heap := by rw [memory]; exact rel.heap
  io := io.trans rel.io

/-- Control transfers change only rip and flags. -/
theorem Rel.jump (rel : Rel frame s m) (memory : s'.memory = s.memory) (registers : s'.registers = s.registers)
    {pc : Nat} (rip : s'.rip = frame.base + BitVec.ofNat 64 pc) (io : s'.io = s.io := by rfl) : Rel frame s' { m with pc := pc } where
  rip := rip
  rbp := by rw [registers]; exact rel.rbp
  rsp := by rw [registers]; exact rel.rsp
  acc := by rw [registers]; exact rel.acc
  slots := by rw [memory]; exact rel.slots
  saved := by rw [memory]; exact rel.saved
  preserved := by rw [registers]; exact rel.preserved
  unchanged := by rw [memory]; exact rel.unchanged
  cursor := by rw [registers]; exact rel.cursor
  limit := rel.limit
  top := rel.top
  fsp := by rw [registers]; exact rel.fsp
  heap := by rw [memory]; exact rel.heap
  io := io.trans rel.io

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

theorem slotLoad_noRead {st : State} {slot : Nat} (loaded : CodeAt st.memory st.rip (slotLoadBytes slot)) :
    NoRead st :=
  memory_noRead loaded

theorem slotStore_noRead {st : State} {slot : Nat} (loaded : CodeAt st.memory st.rip (slotStoreBytes slot)) :
    NoRead st :=
  memory_noRead loaded

/-- `mov [rbp + disp32], rbx`: the frame pointer saved in a slot. -/
theorem fspSave_step (before after : State) (slot : Nat)
    (loaded : CodeAt before.memory before.rip (fspSaveBytes slot))
    (result : after = before.store64 fspRegister rbpRegister
      (BitVec.ofInt 32 (frameDisplacement slot)) (fspSaveBytes slot).length) :
    Lanius.X86.Machine.Step before after :=
  Lanius.X86.Machine.Step.decoded (fspSaveBytes slot) loaded _ _
    (by simpa [fspSaveBytes, memoryInstruction] using
      memory_decodes .w64 false fspRegister rbpRegister (frameDisplacement slot) [])
    (by rw [result]; rfl) rfl

/-- `mov rbx, [rbp + disp32]`: the frame pointer loaded back. -/
theorem fspLoad_step (before after : State) (slot : Nat)
    (loaded : CodeAt before.memory before.rip (fspLoadBytes slot))
    (result : after = before.load64 fspRegister rbpRegister
      (BitVec.ofInt 32 (frameDisplacement slot)) (fspLoadBytes slot).length) :
    Lanius.X86.Machine.Step before after :=
  Lanius.X86.Machine.Step.decoded (fspLoadBytes slot) loaded _ _
    (by simpa [fspLoadBytes, memoryInstruction] using
      memory_decodes .w64 true fspRegister rbpRegister (frameDisplacement slot) [])
    (by rw [result]; rfl) rfl

theorem fspSave_noRead {st : State} {slot : Nat} (loaded : CodeAt st.memory st.rip (fspSaveBytes slot)) :
    NoRead st :=
  memory_noRead loaded

theorem fspLoad_noRead {st : State} {slot : Nat} (loaded : CodeAt st.memory st.rip (fspLoadBytes slot)) :
    NoRead st :=
  memory_noRead loaded

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
  | .shl => st.shift word.width.bits .left 0 st.flags (operation.opBytes word).length
  | .shr => st.shift word.width.bits .right 0 st.flags (operation.opBytes word).length
  | .sar => st.shift word.width.bits .arithmeticRight 0 st.flags (operation.opBytes word).length

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
  · exact shift_step .w32 st _ .left 0 loaded st.flags rfl
  · exact shift_step .w32 st _ .right 0 loaded st.flags rfl
  · exact shift_step .w32 st _ .arithmeticRight 0 loaded st.flags rfl
  · exact alu_step .w64 st _ .add 0 rcxRegister loaded false rfl
  · exact alu_step .w64 st _ .subtract 0 rcxRegister loaded false rfl
  · exact multiply_step .w64 st _ 0 rcxRegister loaded st.flags rfl
  · exact alu_step .w64 st _ .and 0 rcxRegister loaded false rfl
  · exact alu_step .w64 st _ .or 0 rcxRegister loaded false rfl
  · exact alu_step .w64 st _ .xor 0 rcxRegister loaded false rfl
  · exact shift_step .w64 st _ .left 0 loaded st.flags rfl
  · exact shift_step .w64 st _ .right 0 loaded st.flags rfl
  · exact shift_step .w64 st _ .arithmeticRight 0 loaded st.flags rfl

theorem BinOp.final_noRead (word : Word) (operation : BinOp) {st : State}
    (loaded : CodeAt st.memory st.rip (operation.opBytes word)) : NoRead st := by
  cases operation
  case shl | shr | sar => exact shift_noRead loaded
  case mul => exact multiply_noRead loaded
  all_goals exact alu_noRead loaded

theorem BinOp.final_registers (word : Word) (operation : BinOp) (st : State) (register : Register) :
    (operation.final word st).registers register =
      if register = 0 then word.apply operation (st.registers 0) (st.registers rcxRegister)
      else st.registers register := by
  cases operation
  case shl | shr | sar =>
    by_cases zero : register = 0
    · subst zero
      have count : ∀ x : BitVec 64, (x.setWidth 32).toNat % 32 = x.toNat % 32 := fun x => by
        rw [BitVec.toNat_setWidth]; exact Nat.mod_mod_of_dvd _ (by decide)
      cases word <;>
        simp only [BinOp.final, State.shift, Word.apply, BinOp.apply, Word.width,
          X86.Register.Width.bits, rcxRegister, ↓reduceIte, count] <;> rfl
    · cases word <;> simp [zero, BinOp.final, State.shift]
  all_goals
    by_cases zero : register = 0 <;> cases word <;>
      simp [zero, BinOp.final, State.alu, State.multiply, Word.apply, BinOp.apply, Alu.result, Word.width,
        X86.Register.Width.bits] <;> rfl

theorem BinOp.final_memory (word : Word) (operation : BinOp) (st : State) :
    (operation.final word st).memory = st.memory := by
  cases operation <;> rfl

theorem BinOp.final_io (word : Word) (operation : BinOp) (st : State) :
    (operation.final word st).io = st.io := by
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

theorem Word.compared_writes (word : Word) {st : State} (loaded : CodeAt st.memory st.rip word.compareBytes) :
    Writes st := by
  cases word
  · exact compare_writes loaded
  · exact Writes.of (i := .compare64 0 rcxRegister) (k := 3) loaded (by decide) rfl

theorem Word.compared_condition (word : Word) (operation : CmpOp) (st : State) :
    condition (word.compared st).flags (operation.code word) =
      word.holds operation (st.registers 0) (st.registers rcxRegister) := by
  cases word
  · exact CmpOp.condition _ _ _ _
  · exact CmpOp.conditionU _ _ _ _

theorem Word.compared_io (word : Word) (st : State) : (word.compared st).io = st.io := by
  cases word <;> rfl

theorem Word.compared_rip (word : Word) (st : State) :
    (word.compared st).rip = st.rip + BitVec.ofNat 64 word.compareBytes.length := by
  cases word <;> rfl

theorem rel_slot (rel : Rel frame s m) (inFrame : slot < frame.slots) :
    read64 s.memory (s.registers 5 + (BitVec.ofInt 32 (frameDisplacement slot)).signExtend 64) = m.slots slot := by
  rw [show (5 : Register) = rbpRegister from rfl, rel.rbp]; exact rel.slots slot inFrame

theorem imm_simulates (rel : Rel frame s m)
    (loaded : CodeAt s.memory s.rip (immediateBytes .w64 0 (lowHalf value) (highHalf value))) :
    ∃ n s', Steps n s s' ∧ Det n s s' ∧ Rel frame s' ((Instr.imm value).step m) := by
  let s' := s.immediate64 0 (BitVec.ofNat 64 ((lowHalf value).toNat + 4294967296 * (highHalf value).toNat))
    (immediateBytes .w64 0 (lowHalf value) (highHalf value)).length
  have step : Lanius.X86.Machine.Step s s' := immediate_step s s' .w64 0 _ _ loaded rfl
  have length : (immediateBytes .w64 0 (lowHalf value) (highHalf value)).length = 10 :=
    Instr.bytes_length ⟨0, 0, []⟩ 0 (.imm value)
  refine ⟨1, s', .cons step (.refl _), Det.step step (immediate_noRead loaded),
    Rel.accumulate (s' := s') rel rfl 10
    (by simp only [s', State.immediate64, length]) ?_ ?_⟩
  · intro register zero _
    simp only [s', State.immediate64, if_neg zero]
  · simp [s', State.immediate64, lowHalf_highHalf, Instr.update]

theorem load_simulates (rel : Rel frame s m) (inFrame : slot < frame.slots)
    (loaded : CodeAt s.memory s.rip (slotLoadBytes slot)) :
    ∃ n s', Steps n s s' ∧ Det n s s' ∧ Rel frame s' ((Instr.load slot).step m) := by
  let s' := s.load64 0 rbpRegister (BitVec.ofInt 32 (frameDisplacement slot)) (slotLoadBytes slot).length
  have step : Lanius.X86.Machine.Step s s' := slotLoad_step s s' slot loaded rfl
  refine ⟨1, s', .cons step (.refl _), Det.step step (slotLoad_noRead loaded),
    Rel.accumulate (s' := s') rel rfl 7
    (by simp only [s', State.load64, slotLoadBytes_length]) ?_ ?_⟩
  · intro register zero _
    simp only [s', State.load64, if_neg zero]
  · simp [s', State.load64, rbpRegister, rel_slot rel inFrame, Instr.update]

theorem neg_simulates (rel : Rel frame s m) (loaded : CodeAt s.memory s.rip (negateBytes .w32 0)) :
    ∃ n s', Steps n s s' ∧ Det n s s' ∧ Rel frame s' (Instr.neg.step m) := by
  let s' := s.negate 32 0 s.flags (negateBytes .w32 0).length
  have step : Lanius.X86.Machine.Step s s' := negate_step .w32 s s' 0 loaded s.flags rfl
  refine ⟨1, s', .cons step (.refl _), Det.step step (negate_noRead loaded),
    Rel.accumulate (s' := s') rel rfl 2
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
    ∃ n s', Steps n s s' ∧ Det n s s' ∧ Rel frame s' ((Instr.op word operation slot).step m) := by
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
  have det : Det 3 s s' :=
    Det.cons first (move_noRead bytes.prefix.prefix)
      (Det.cons second (slotLoad_noRead
        (by simpa only [moved, State.move64, accToRcx_length] using bytes.prefix.suffix))
        (Det.cons third (operation.final_noRead word
          (by simpa only [loadedLeft, moved, State.load64, State.move64, accToRcx_length,
            BitVec.ofNat_add, BitVec.add_assoc, List.length_append] using bytes.suffix)) (Det.refl _)))
  refine ⟨3, s', .cons first (.cons second (.cons third (.refl _))), det, ?_⟩
  refine Rel.accumulate (s' := s') rel (BinOp.final_memory ..) _ ?_ ?_ ?_ (BinOp.final_io ..)
  · simp only [s', BinOp.final_rip, loadedLeft, moved, State.load64, State.move64, slotLoadBytes_length, size]
    bv_omega
  · intro register zero one
    have one' : register ≠ rcxRegister := one
    simp only [s', BinOp.final_registers, if_neg zero, loadedLeft, moved, State.load64, State.move64,
      if_neg one']
  · simp [s', BinOp.final_registers, loadedLeft, moved, State.load64, State.move64, rcxRegister,
      rbpRegister, ← rel.acc, rel_slot rel inFrame, Instr.update]

theorem fp_size (operation : FOp) (slot : Nat) :
    (Instr.fp operation slot).size = 10 + operation.opcodeBytes.length := by
  rcases operation with ⟨t, operation⟩ | ⟨t, operation⟩ | ⟨t, word⟩ | _ | _ <;>
    (try cases t) <;> (try cases word) <;> rfl

/-- `mov rcx, rax; mov rax, [slot]`, then the SSE code of the operation
(`FOp.program`), which leaves its result in rax. -/
theorem fp_simulates (operation : FOp) (rel : Rel frame s m) (inFrame : slot < frame.slots)
    (loaded : CodeAt s.memory s.rip (accToRcxBytes ++ slotLoadBytes slot ++ operation.opcodeBytes)) :
    ∃ n s', Steps n s s' ∧ Det n s s' ∧ Rel frame s' ((Instr.fp operation slot).step m) := by
  let moved := s.move64 rcxRegister 0 3
  let loadedLeft := moved.load64 0 rbpRegister
    (BitVec.ofInt 32 (frameDisplacement slot)) (slotLoadBytes slot).length
  let s' := runPlain operation.program loadedLeft
  have first := accToRcx_step s moved loaded.prefix.prefix rfl
  have bytes1 : CodeAt moved.memory moved.rip (slotLoadBytes slot) := by
    simpa only [moved, State.move64, accToRcx_length] using loaded.prefix.suffix
  have second := slotLoad_step moved loadedLeft slot bytes1 rfl
  have code : CodeAt loadedLeft.memory loadedLeft.rip (operation.program.flatMap Prod.fst) := by
    rw [FOp.program_bytes]
    simpa only [loadedLeft, moved, State.load64, State.move64, accToRcx_length,
      BitVec.ofNat_add, BitVec.add_assoc, List.length_append] using loaded.suffix
  obtain ⟨run, det⟩ := runPlain_steps _ loadedLeft operation.program_plain code
  obtain ⟨memory, rip⟩ := runPlain_effect _ loadedLeft operation.program_plain
  have size := fp_size operation slot
  refine ⟨_, s', .cons first (.cons second run),
    Det.cons first (move_noRead loaded.prefix.prefix) (Det.cons second (slotLoad_noRead bytes1) det), ?_⟩
  refine Rel.accumulate (s' := s') rel (by rw [memory]; rfl) _ ?_ ?_ ?_ (runPlain_io _ _)
  · rw [rip, FOp.program_bytes]
    simp only [loadedLeft, moved, State.load64, State.move64, slotLoadBytes_length, size]
    bv_omega
  · intro register zero one
    have one' : register ≠ rcxRegister := one
    rw [FOp.program_other _ _ zero]
    simp only [loadedLeft, moved, State.load64, State.move64, if_neg zero, if_neg one']
  · rw [FOp.program_acc]
    simp [loadedLeft, moved, State.load64, State.move64, rcxRegister, rbpRegister, ← rel.acc,
      rel_slot rel inFrame, Instr.update]

/-- `mov rcx, rax; mov rax, [slot]; mov r11, rdx`, the dividend's high half,
`idiv` or `div`, `mov rax, rdx` for a remainder, `mov rdx, r11` -/
theorem div_simulates (word : Word) (operation : DivOp) (rel : Rel frame s m) (inFrame : slot < frame.slots)
    (loaded : CodeAt s.memory s.rip (operation.spec word slot))
    (defined : word.divides operation (m.slots slot) m.acc = true) :
    ∃ n s', Steps n s s' ∧ Det n s s' ∧ Rel frame s' { m with
      pc := m.pc + (Instr.div word operation slot).size
      acc := word.divide operation (m.slots slot) m.acc } := by
  have split : operation.spec word slot = accToRcxBytes ++ (slotLoadBytes slot ++
      (moveBytes .w64 r11Register rdxRegister ++
      ((dividendBytes word operation.signed ++ divisionBytes word.width operation.signed rcxRegister) ++
      (resultBytes operation.remainder ++ moveBytes .w64 rdxRegister r11Register)))) := by
    simp only [DivOp.spec, List.append_assoc]
  rw [split] at loaded
  let s1 := s.move64 rcxRegister 0 3
  have t1 := accToRcx_step s s1 loaded.prefix rfl
  have c1 := loaded.next (s' := s1) rfl (by simp [s1, State.move64, accToRcx_length])
  let s2 := s1.load64 0 rbpRegister (BitVec.ofInt 32 (frameDisplacement slot)) (slotLoadBytes slot).length
  have t2 := slotLoad_step s1 s2 slot c1.prefix rfl
  have c2 := c1.next (s' := s2) rfl rfl
  let s3 := s2.move64 r11Register rdxRegister (moveBytes .w64 r11Register rdxRegister).length
  have t3 := move_step s2 s3 .w64 r11Register rdxRegister c2.prefix rfl
  have c3 := c2.next (s' := s3) rfl rfl
  have a3 : s3.registers 0 = m.slots slot := by
    simp [s3, s2, s1, State.move64, State.load64, rdxRegister, r11Register, rbpRegister, rcxRegister,
      rel_slot rel inFrame]
  have b3 : s3.registers rcxRegister = m.acc := by
    simp [s3, s2, s1, State.move64, State.load64, rdxRegister, r11Register, rcxRegister, rel.acc]
  have r3 : s3.registers r11Register = s.registers rdxRegister := by
    simp [s3, s2, s1, State.move64, State.load64, rdxRegister, r11Register, rcxRegister]
  have k3 : ∀ register, register ≠ 0 → register ≠ 1 → register ≠ 11 → s3.registers register = s.registers register := by
    intro register zero one eleven
    have one' : register ≠ rcxRegister := one
    have eleven' : register ≠ r11Register := eleven
    simp [s3, s2, s1, State.move64, State.load64, zero, one', eleven']
  obtain ⟨nonzero, fits⟩ := word.divides_cases operation _ _ defined
  rw [← b3] at nonzero
  rw [← a3, ← b3] at fits
  obtain ⟨s5, steps5, det5, io5, memory5, rip5, q5, r5, k5⟩ :=
    divide_steps word operation.signed s3 c3.prefix nonzero fits
  have c5 := c3.next (s' := s5) memory5 rip5
  obtain ⟨n7, s7, steps7, det7, io7, memory7, rip7, acc7, rdx7, k7⟩ := result_steps operation.remainder s5 c5
  refine ⟨_, s7, .cons t1 (.cons t2 (.cons t3 (steps5.trans steps7))),
    Det.cons t1 (move_noRead loaded.prefix) (Det.cons t2 (slotLoad_noRead c1.prefix)
      (Det.cons t3 (move_noRead c2.prefix) (det5.trans det7))), ?_⟩
  have size := Instr.bytes_length ⟨0, 0, []⟩ 0 (.div word operation slot)
  simp only [Instr.bytes, split, List.length_append, accToRcx_length, slotLoadBytes_length] at size
  refine Rel.accumulate11 (s' := s7) rel (by rw [memory7, memory5]; rfl) _ ?_ ?_ ?_ (by rw [io7, io5]; rfl)
  · rw [rip7, rip5, ← size]
    simp only [s3, s2, s1, State.move64, State.load64, slotLoadBytes_length, List.length_append,
      BitVec.ofNat_add, BitVec.add_assoc]
  · intro register zero one eleven
    by_cases two : register = 2
    · subst two
      rw [rdx7, k5 _ (by decide) (by decide), r3]
      rfl
    · rw [k7 register zero two, k5 register zero two, k3 register zero one eleven]
  · rw [acc7, Word.divide_eq, DivOp.apply_eq, ← a3, ← b3]
    cases operation.remainder
    · simp [q5]
    · simp [r5]

theorem setCondition_value (high : BitVec 56) (holds : Bool) :
    (((high ++ (if holds then (1 : BitVec 8) else 0)).setWidth 8).setWidth 64 : BitVec 64) =
      if holds then 1 else 0 := by
  rw [BitVec.setWidth_append_eq_right]
  cases holds <;> rfl

/-- `mov rcx, rax; mov rax, [slot]; cmp; setcc al; movzx eax, al` -/
theorem cmp_simulates (word : Word) (operation : CmpOp) (rel : Rel frame s m) (inFrame : slot < frame.slots)
    (loaded : CodeAt s.memory s.rip (cmpBytes word operation slot)) :
    ∃ n s', Steps n s s' ∧ Det n s s' ∧ Rel frame s' ((Instr.cmp word operation slot).step m) := by
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
  refine ⟨5, s', .cons first (.cons second (.cons third (.cons fourth (.cons fifth (.refl _))))),
    Det.cons first (move_noRead bytes.prefix) (Det.cons second (slotLoad_noRead bytes1.prefix)
      (Det.pairCons third (word.compared_writes bytes2.prefix) fourth ⟨_, bytes3.prefix, setCondition_decodes _ _⟩
        (Det.cons fifth (zeroExtendByte_noRead bytes4) (Det.refl _)))), ?_⟩
  refine Rel.accumulate (s' := s') rel (by
    simp only [s', set, State.zeroExtendByte, State.setCondition]
    rw [comparedMemory]
    rfl) _ ?_ ?_ ?_ (Word.compared_io word loadedLeft)
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

theorem slot_below (fits : frame.Fits) (inFrame : slot < frame.slots) {lane : Nat} (small : lane < 8) :
    Below frame.top frame.window (frameSlotAddress (frame.top - 8) slot + BitVec.ofNat 64 lane) := by
  have limit : frame.slots ≤ 2 ^ 20 := fits.slots
  have room := fits.window
  have bounded := fits.bounded
  have big := frameBytes_slots frame.slots
  rw [slot_lane _ (by unfold slotLimit; omega) _ small]
  exact below_depth _ (by omega) (by omega) (by omega)

theorem saved_below (fits : frame.Fits) {lane : Nat} (small : lane < 8) :
    Below frame.top frame.window (frame.top - 8 + BitVec.ofNat 64 lane) := by
  have room := fits.window
  have bounded := fits.bounded
  rw [show frame.top - 8 = frame.top - BitVec.ofNat 64 8 from rfl, depth_lane _ _ _ (by omega)]
  exact below_depth _ (by omega) (by omega) (by omega)

/-- A heap byte is not in the stack window. -/
theorem heap_ne_below (fits : frame.Fits) {a : Nat} (inside : a < frame.heapLimit) {address : BitVec 64}
    (below : Below frame.top frame.window address) : frame.heapBase + BitVec.ofNat 64 a ≠ address := by
  intro same
  exact fits.notHeap below (same ▸ frame.inHeap inside)

theorem store_simulates (rel : Rel frame s m) (fits : frame.Fits) (inFrame : slot < frame.slots)
    (loaded : CodeAt s.memory s.rip (slotStoreBytes slot)) :
    ∃ n s', Steps n s s' ∧ Det n s s' ∧ Rel frame s' ((Instr.store slot).step m) := by
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
  refine ⟨1, s', .cons step (.refl _), Det.step step (slotStore_noRead loaded), ?_⟩
  refine ⟨?_, rel.rbp, rel.rsp, rel.acc, ?_, ?_, rel.preserved, ?_, rel.cursor, rel.limit, rel.top, rel.fsp, ?_, rel.io⟩
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
  · intro other outside notHeap
    rw [memory, write64_frame _ _ _ _ (fun lane => by
      rw [slot_lane _ bound _ (by omega)]
      exact ne_of_below outside (below_depth _ (by omega) (by omega) (by omega)))]
    exact rel.unchanged other outside notHeap
  · intro a inside
    rw [memory, write64_frame _ _ _ _ (fun lane =>
      heap_ne_below fits (by rw [← rel.limit]; exact inside) (slot_below fits inFrame lane.isLt))]
    exact rel.heap a inside

theorem jmp_simulates (rel : Rel frame s m) {target : Nat} (small : m.pc + 5 < 2 ^ 31) (targetSmall : target < 2 ^ 31)
    (loaded : CodeAt s.memory s.rip (jumpBytes (relative (m.pc + 5) target))) :
    ∃ n s', 0 < n ∧ Steps n s s' ∧ Det n s s' ∧ Rel frame s' { m with pc := target } := by
  let s' := s.jump (relative (m.pc + 5) target) (jumpBytes (relative (m.pc + 5) target)).length
  have step : Lanius.X86.Machine.Step s s' := jump_step s s' _ loaded rfl
  refine ⟨1, s', by omega, .cons step (.refl _), Det.step step (jump_noRead loaded), rel.jump (s' := s') rfl rfl ?_⟩
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
    ∃ n s', 0 < n ∧ Steps n s s' ∧ Det n s s' ∧ Rel frame s' { m with pc := if m.acc = 0 then target else m.pc + 9 } := by
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
    refine ⟨2, s', by omega, .cons first (.cons second (.refl _)), Det.pair first (test_writes loaded.prefix) second ⟨_, bytes, branch_decodes _ _⟩, ?_⟩
    rw [if_pos accZero]
    refine rel.jump (s' := s') rfl rfl ?_
    rw [rip, testedRip]
    exact relative_eq _ _ _ small targetSmall
  · obtain ⟨second, rip⟩ := branch_step_rip_not_taken tested s' 4 _ bytes
      (by rw [zero]; simpa using accZero) rfl
    refine ⟨2, s', by omega, .cons first (.cons second (.refl _)), Det.pair first (test_writes loaded.prefix) second ⟨_, bytes, branch_decodes _ _⟩, ?_⟩
    rw [if_neg accZero]
    refine rel.jump (s' := s') rfl rfl ?_
    rw [rip, testedRip]
    bv_omega

/-- The frame epilogue and `ret`. -/
theorem epilogue_simulates (rel : Rel frame s m) (fits : frame.Fits) (loaded : CodeAt s.memory s.rip epilogueBytes) :
    ∃ n s', Steps n s s' ∧ Det n s s' ∧ s'.io = s.io ∧ frame.Left s' m.acc ∧ s'.memory = s.memory ∧
      s'.registers cursorRegister = s.registers cursorRegister := by
  refine ⟨3, epilogueState s, frameEpilogue_steps s loaded, frameEpilogue_det s loaded, rfl, ?_, by
    simp only [epilogueState, State.returnNear, State.pop64, State.move64], by
    simp [epilogueState, State.returnNear, State.pop64, State.move64, rspRegister, rbpRegister, cursorRegister]⟩
  have rbp : s.registers 5 = frame.top - 8 := rel.rbp
  have bounded := fits.bounded
  constructor
  · simp only [epilogueState, State.returnNear, State.pop64, State.move64, rspRegister, rbpRegister]
    simp only [show (4 : Register) ≠ 5 by decide, if_true, if_false, rbp, BitVec.sub_add_cancel]
    apply read64_congr
    intro lane
    exact rel.unchanged _ (not_below_return _ lane.isLt (by omega)) (fits.returnNotHeap lane.isLt)
  · simp [epilogueState, State.returnNear, State.pop64, State.move64, rspRegister, rbpRegister, rbp]
    bv_omega
  · simp [epilogueState, State.returnNear, State.pop64, State.move64, rspRegister, rbpRegister, rbp]
    exact rel.saved
  · simp [epilogueState, State.returnNear, State.pop64, State.move64, rspRegister, rbpRegister, rel.acc]
  · intro register other
    obtain ⟨-, -, four, five, -⟩ := not_scratch other
    simp [epilogueState, State.returnNear, State.pop64, State.move64, rspRegister, rbpRegister,
      four, five, rel.preserved register other]
  · intro address outside notHeap
    simp only [epilogueState, State.returnNear, State.pop64, State.move64]
    exact rel.unchanged address outside notHeap

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
      ∃ n s', Steps n s s' ∧ Det n s s' ∧ s'.io = s.io ∧ s'.rip = s.rip + BitVec.ofNat 64 (14 * args.length) ∧
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
    exact ⟨0, s, .refl _, Det.refl _, rfl, by simp, fun _ _ => rfl, fun _ _ => rfl, fun j bound => absurd bound (by simp), rfl⟩
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
    obtain ⟨n, s', steps, det, io', rip', registers', memory', reads', rax'⟩ := ih (k + 1) s2 rbp2 loaded2
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
    refine ⟨_, s', .cons step1 (.cons step2 steps),
      Det.cons step1 (slotLoad_noRead bytes.prefix.prefix) (Det.cons step2 (slotStore_noRead
        (by simpa only [s1, State.load64, State.immediate32] using bytes.prefix.suffix)) det),
      io', ?_, ?_, ?_, ?_, ?_⟩
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
    (slots : ∀ slot, slot < frame.slots → m'.slots slot = m.slots slot) (heap : m'.heap = m.heap) :
    Rel frame s m' where
  rip := by rw [pc]; exact rel.rip
  rbp := rel.rbp
  rsp := rel.rsp
  acc := by rw [acc]; exact rel.acc
  slots slot inFrame := by rw [slots slot inFrame]; exact rel.slots slot inFrame
  saved := rel.saved
  preserved := rel.preserved
  unchanged := rel.unchanged
  cursor := by rw [heap]; exact rel.cursor
  limit := by rw [heap]; exact rel.limit
  top := by rw [heap]; exact rel.top
  fsp := by rw [heap]; exact rel.fsp
  heap := by rw [heap]; exact rel.heap
  io := by rw [heap]; exact rel.io

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
    ∃ n s', Steps n s s' ∧ Det n s s' ∧ Rel frame s' (m.copied (14 * sources.length) target
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
  obtain ⟨n, s', steps, det, io', rip', registers', memory', reads', rax'⟩ :=
    copy_steps frame.top target sources 0 s rel.rbp loaded
      (fun index bound j inSources lane => ne_of_below (apart index bound) (targetBelow j inSources lane))
      (fun j inSources src mem i lane => slot_lanes_ne _ (small src mem) (by unfold slotLimit; omega)
        (by have := away src mem; omega) i lane)
      (fun j j' less inSources i lane =>
        slot_lanes_ne _ (by unfold slotLimit; omega) (by unfold slotLimit; omega) (by omega) i lane)
  refine ⟨n, s', steps, det, ?_⟩
  simp only [Machine.copied]
  refine ⟨?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, rel.limit, rel.top,
    (registers' _ (by decide)).trans rel.fsp, ?_, io'.trans rel.io⟩
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
  · intro address outside notHeap
    rw [memory' address (fun j bound lane => ne_of_below outside (targetBelow j bound lane))]
    exact rel.unchanged address outside notHeap
  · rw [registers' _ (by decide)]; exact rel.cursor
  · intro a inside
    rw [memory' _ (fun j bound lane =>
      heap_ne_below fits (by rw [← rel.limit]; exact inside) (targetBelow j bound lane))]
    exact rel.heap a inside

/-- The activation has returned `values` to its caller: they replace the
arguments, and rax holds the last one. -/
structure Frame.Exit (frame : Frame) (s : State) (values : List (BitVec 64)) (final : Heap) : Prop where
  rip : s.rip = read64 frame.entry frame.top
  rsp : s.registers rspRegister = frame.top + 8
  rbp : s.registers rbpRegister = frame.saved
  value : ∀ v, values.getLast? = some v → s.registers 0 = v
  results : ∀ k (bound : k < values.length),
    read64 s.memory (frame.top - BitVec.ofNat 64 (8 * k + 16)) = values[k]
  preserved : ∀ register, ¬Scratch register → s.registers register = frame.preserved register
  unchanged : ∀ address, ¬Below frame.top frame.window address → ¬frame.InHeap address →
    s.memory address = frame.entry address
  cursor : s.registers cursorRegister = BitVec.ofNat 64 final.cursor
  limit : final.limit = frame.heapLimit
  top : final.top = final.limit
  heap : ∀ a, a < final.limit → s.memory (frame.heapBase + BitVec.ofNat 64 a) = final.bytes a
  io : s.io = final.io

theorem readSlots_eq_map (slots : Nat → BitVec 64) (args : List Nat) : readSlots slots args = args.map slots := by
  induction args <;> simp_all [readSlots]

/-- A return: copy the results to the first slots, then the epilogue. -/
theorem ret_simulates (rel : Rel frame s m) (fits : frame.Fits) {sources : List Nat} {bound funcs : Nat}
    (loaded : CodeAt s.memory s.rip (copyBytes 0 sources 0 ++ epilogueBytes))
    (apart : ∀ index, index < (Instr.ret sources).size →
      ¬Below frame.top frame.window (s.rip + BitVec.ofNat 64 index))
    (codeHeap : ∀ index, index < (Instr.ret sources).size → ¬frame.InHeap (s.rip + BitVec.ofNat 64 index))
    (fitted : (Instr.ret sources).Fits frame.slots bound funcs) :
    ∃ n s', Steps n s s' ∧ Det n s s' ∧ frame.Exit s' (readSlots m.slots sources) m.heap := by
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
  obtain ⟨n1, s1, steps1, det1, rel1⟩ := copy_simulates rel fits loaded.prefix
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
    have heapAway := codeHeap (14 * sources.length + index) (by omega)
    rw [addr, rel1.unchanged _ away heapAway, ← rel.unchanged _ away heapAway, BitVec.ofNat_add, ← BitVec.add_assoc]
    exact tail index small
  obtain ⟨n2, s2, steps2, det2, io2, left, memory2, cursor2⟩ := epilogue_simulates rel1 fits loaded1
  refine ⟨_, s2, steps1.trans steps2, det1.trans det2, left.rip, left.rsp, left.rbp, ?_, ?_, left.preserved, left.unchanged,
    cursor2.trans rel1.cursor, rel1.limit, rel1.top, fun a inside => by rw [memory2]; exact rel1.heap a inside,
    io2.trans rel1.io⟩
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
structure Returned (window : Nat) (s s' : State) (values : List (BitVec 64)) (after : Heap) : Prop where
  rip : s'.rip = read64 s.memory (s.registers rspRegister)
  rsp : s'.registers rspRegister = s.registers rspRegister + 8
  rbp : s'.registers rbpRegister = s.registers rbpRegister
  value : ∀ v, values.getLast? = some v → s'.registers 0 = v
  results : ∀ k (bound : k < values.length),
    read64 s'.memory (s.registers rspRegister - BitVec.ofNat 64 (8 * k + 16)) = values[k]
  preserved : ∀ register, ¬Scratch register → s'.registers register = s.registers register
  unchanged : ∀ address, ¬Below (s.registers rspRegister) window address → ¬s.InHeap address →
    s'.memory address = s.memory address
  cursor : s'.registers cursorRegister = BitVec.ofNat 64 after.cursor
  limit : after.limit = (s.registers limitRegister).toNat
  top : after.top = after.limit
  heap : ∀ a, a < after.limit → s'.memory (s.registers heapBaseRegister + BitVec.ofNat 64 a) = after.bytes a
  io : s'.io = after.io

/-- `s` holds `heap` where its registers place it, apart from the stack a call
may use and its return address. -/
structure HeapAt (window : Nat) (s : State) (heap : Heap) : Prop where
  cursor : s.registers cursorRegister = BitVec.ofNat 64 heap.cursor
  limit : heap.limit = (s.registers limitRegister).toNat
  top : heap.top = heap.limit
  fsp : s.registers fspRegister = BitVec.ofNat 64 heap.fsp
  small : heap.limit < 2 ^ 62
  bytes : ∀ a, a < heap.limit → s.memory (s.registers heapBaseRegister + BitVec.ofNat 64 a) = heap.bytes a
  apart : ∀ address, s.InHeap address → ¬Below (s.registers rspRegister + 8) (window + 8) address
  io : s.io = heap.io

/-- The `window` stack bytes below the return address run from `guard` bytes
below the limit in r15, which is above 4 GiB. -/
structure StackAt (guard window : Nat) (s : State) : Prop where
  limit : (s.registers stackRegister).toNat + window = (s.registers rspRegister).toNat + guard
  high : 2 ^ 32 ≤ (s.registers stackRegister).toNat
  /-- r15 is at most 8 bytes above the return address. -/
  low : guard ≤ window + 8

/-- Function `callee` of `binary`, loaded at `imageBase` and entered by a near
call with `args` just below the return address and `window` bytes of stack,
returns `values` within the window, or, with fewer than `need` bytes, may
instead stop at a fault (the prologue's stack check). -/
def Contract (binary : Binary) (imageBase : BitVec 64) (need window callee : Nat) (args : List (BitVec 64))
    (heap : Heap) (values : List (BitVec 64)) (after : Heap) : Prop :=
  ∀ s : State, window ≤ 2 ^ 62 → CodeAt s.memory imageBase binary.image →
    (∀ index, index < binary.image.length →
      ¬Below (s.registers rspRegister) window (imageBase + BitVec.ofNat 64 index)) →
    (∀ index, index < binary.image.length → ¬s.InHeap (imageBase + BitVec.ofNat 64 index)) →
    s.rip = imageBase + BitVec.ofNat 64 (binary.entries.getD callee 0) →
    (∀ k (bound : k < args.length),
      read64 s.memory (s.registers rspRegister - BitVec.ofNat 64 (8 * k + 16)) = args[k]) →
    HeapAt window s heap → StackAt binary.guard window s →
    (∃ n s', Steps n s s' ∧ Det n s s' ∧ Returned window s s' values after) ∨ (window < need ∧ Faults s)

theorem Contract.mono {binary : Binary} {imageBase : BitVec 64} {need need' window callee : Nat}
    {args values : List (BitVec 64)} {heap after : Heap}
    (contract : Contract binary imageBase need window callee args heap values after)
    (larger : need ≤ need') : Contract binary imageBase need' window callee args heap values after := by
  intro s bounded loaded apart imageHeap entry params heapAt stack
  rcases contract s bounded loaded apart imageHeap entry params heapAt stack with returned | ⟨short, faults⟩
  · exact .inl returned
  · exact .inr ⟨by omega, faults⟩

/-- A call: copy the arguments below the stack, `call rel32`, the callee's
contract carries the activation across, then copy the results to `target`. -/
theorem call_simulates {binary : Binary} {imageBase : BitVec 64} {place : Place} {callee : Nat}
    {args : List Nat} {target count : Nat} (rel : Rel frame s m) (fits : frame.Fits)
    (loaded : CodeAt s.memory s.rip ((Instr.call callee args target count).bytes place m.pc))
    (apart : ∀ index, index < (Instr.call callee args target count).size →
      ¬Below frame.top frame.window (s.rip + BitVec.ofNat 64 index))
    (codeHeap : ∀ index, index < (Instr.call callee args target count).size →
      ¬frame.InHeap (s.rip + BitVec.ofNat 64 index))
    (placeSlots : place.slots = frame.slots) (placeEntries : place.entries = binary.entries)
    (base : frame.base = imageBase + BitVec.ofNat 64 place.body)
    (small : place.body + m.pc + (Instr.call callee args target count).size < 2 ^ 31)
    (entrySmall : binary.entries.getD callee 0 < 2 ^ 31)
    (argsFit : ∀ slot ∈ args, slot < frame.slots) (argsCount : args.length ≤ frame.slots)
    (targetFit : target + count ≤ frame.slots) (positive : 0 < count)
    (image : CodeAt frame.entry imageBase binary.image)
    (imageApart : ∀ index, index < binary.image.length →
      ¬Below frame.top frame.window (imageBase + BitVec.ofNat 64 index))
    (imageHeap : ∀ index, index < binary.image.length → ¬frame.InHeap (imageBase + BitVec.ofNat 64 index))
    (guard : frame.guard = binary.guard)
    {inner : Nat} (innerFits : frameBytes frame.slots + 16 + inner = frame.window)
    (room : 8 * args.length + 16 ≤ inner)
    {values : List (BitVec 64)} {after : Heap} {P : Prop} {Q : State → Prop}
    (contract : ∀ s : State, inner ≤ 2 ^ 62 → CodeAt s.memory imageBase binary.image →
      (∀ index, index < binary.image.length →
        ¬Below (s.registers rspRegister) inner (imageBase + BitVec.ofNat 64 index)) →
      (∀ index, index < binary.image.length → ¬s.InHeap (imageBase + BitVec.ofNat 64 index)) →
      s.rip = imageBase + BitVec.ofNat 64 (binary.entries.getD callee 0) →
      (∀ k (bound : k < (readSlots m.slots args).length),
        read64 s.memory (s.registers rspRegister - BitVec.ofNat 64 (8 * k + 16)) = (readSlots m.slots args)[k]) →
      HeapAt inner s m.heap → StackAt binary.guard inner s →
      (P ∧ ∃ n s', Steps n s s' ∧ Det n s s' ∧ Returned inner s s' values after) ∨ Q s)
    (counted : values.length = count) :
    (P ∧ ∃ n s', Steps n s s' ∧ Det n s s' ∧
      Rel frame s' { m with pc := m.pc + (Instr.call callee args target count).size,
                            acc := values.getLastD m.acc, slots := writeSlots m.slots target values,
                            heap := { after with fsp := m.heap.fsp } }) ∨
      (∃ k s', 0 < k ∧ Det k s s' ∧ Q s') := by
  have limit : frame.slots ≤ 2 ^ 20 := fits.slots
  have bounded := fits.bounded
  have big := frameBytes_slots frame.slots
  have le := frameBytes_le frame.slots
  have mul := frameBytes_mul frame.slots
  have size : (Instr.call callee args target count).size = 14 * args.length + 19 + 14 * count := rfl
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
      fspSaveBytes target ++
      callBytes (relative (place.body + m.pc + 14 * args.length + 12) (binary.entries.getD callee 0)) ++
      fspLoadBytes target ++ copyBytes target (slotRange first count) 0 := by
    simp only [Instr.bytes, placeSlots, placeEntries, first]
  rw [encoded] at loaded
  have callLength : ∀ d, (callBytes d).length = 5 := fun d => by simp [callBytes, displacementBytes]
  have address : ∀ k, k < 2 ^ 21 → frame.top - BitVec.ofNat 64 (fb + 16) - BitVec.ofNat 64 (8 * k + 16) =
      frameSlotAddress (frame.top - 8) (first + 0 + k) := by
    intro k bound
    rw [slot_eq _ (by unfold slotLimit; omega),
      show 8 * (first + 0 + k) + 16 = fb + 32 + 8 * k by omega]
    bv_omega
  obtain ⟨n1, s1, steps1, det1, io1, rip1, registers1, memory1, reads1, -⟩ := copy_steps frame.top first args 0 s rel.rbp
    loaded.prefix.prefix.prefix.prefix
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
  -- `mov [rbp + disp32], rbx`: the caller's frame pointer, in the first result slot
  have targetIn : target < frame.slots := by omega
  have targetBound : target < slotLimit := by unfold slotLimit; omega
  have targetDepth : ∀ lane, lane < 8 → frameSlotAddress (frame.top - 8) target + BitVec.ofNat 64 lane =
      frame.top - BitVec.ofNat 64 (8 * target + 16 - lane) :=
    fun lane small => slot_lane _ targetBound lane small
  have targetLaneBelow : ∀ lane : Fin 8,
      Below frame.top frame.window (frameSlotAddress (frame.top - 8) target + BitVec.ofNat 64 lane.val) :=
    fun lane => slot_below fits targetIn lane.isLt
  have rbx1 : s1.registers fspRegister = BitVec.ofNat 64 m.heap.fsp :=
    (registers1 fspRegister (by decide)).trans rel.fsp
  have saveLoaded : CodeAt s1.memory s1.rip (fspSaveBytes target) := by
    have tail := loaded.prefix.prefix.prefix.suffix
    rw [copyBytes_length] at tail
    rw [rip1]
    intro index bound
    rw [memory1 _ (by
      intro j inArgs lane
      have := apart (14 * args.length + index) (by rw [fspSaveBytes_length] at bound; omega)
      rw [BitVec.ofNat_add, ← BitVec.add_assoc] at this
      exact ne_of_below this (targetBelow j inArgs lane))]
    exact tail index bound
  let s1b := s1.store64 fspRegister rbpRegister (BitVec.ofInt 32 (frameDisplacement target))
    (fspSaveBytes target).length
  have step1b : Lanius.X86.Machine.Step s1 s1b := fspSave_step s1 s1b target saveLoaded rfl
  have rip1b : s1b.rip = s.rip + BitVec.ofNat 64 (14 * args.length + 7) := by
    simp only [s1b, State.store64, fspSaveBytes_length]
    rw [rip1]
    bv_omega
  have memory1b : s1b.memory =
      write64 s1.memory (frameSlotAddress (frame.top - 8) target) (BitVec.ofNat 64 m.heap.fsp) := by
    have address : s1.registers rbpRegister + (BitVec.ofInt 32 (frameDisplacement target)).signExtend 64 =
        frameSlotAddress (frame.top - 8) target := by rw [registers1 rbpRegister (by decide), rel.rbp]; rfl
    simp only [s1b, State.store64, address, rbx1]
  -- `call rel32`
  let displacement := relative (place.body + m.pc + 14 * args.length + 12) (binary.entries.getD callee 0)
  have callLoaded : CodeAt s1b.memory s1b.rip (callBytes displacement) := by
    have tail := loaded.prefix.prefix.suffix
    rw [List.length_append, copyBytes_length, fspSaveBytes_length] at tail
    rw [rip1b]
    intro index bound
    have away := apart (14 * args.length + 7 + index) (by simp [callBytes, displacementBytes] at bound; omega)
    rw [BitVec.ofNat_add, ← BitVec.add_assoc] at away
    rw [memory1b, write64_frame _ _ _ _ (fun lane => ne_of_below away (targetLaneBelow lane)),
      memory1 _ (fun j inArgs lane => ne_of_below away (targetBelow j inArgs lane))]
    exact tail index bound
  let s2 := s1b.call displacement (callBytes displacement).length
  have step2 := call_step s1b s2 displacement callLoaded rfl
  have rsp2 : s2.registers rspRegister = frame.top - BitVec.ofNat 64 (fb + 16) := by
    simp only [s2, s1b, State.call, State.store64, rspRegister, if_pos]
    rw [registers1 4 (by decide)]
    have := rel.rsp
    rw [fbEq] at this
    simp only [rspRegister] at this
    rw [this]
    bv_omega
  have next : s1b.rip + BitVec.ofNat 64 (callBytes displacement).length =
      frame.base + BitVec.ofNat 64 (m.pc + 14 * args.length + 12) := by
    rw [rip1b, rel.rip, callLength]
    bv_omega
  have memory2 : s2.memory = write64 s1b.memory (frame.top - BitVec.ofNat 64 (fb + 16))
      (frame.base + BitVec.ofNat 64 (m.pc + 14 * args.length + 12)) := by
    simp only [s2, State.call]
    rw [next]
    congr 1
  have rip2 : s2.rip = imageBase + BitVec.ofNat 64 (binary.entries.getD callee 0) := by
    simp only [s2, State.call]
    rw [next, base, BitVec.add_assoc imageBase, ← BitVec.ofNat_add]
    rw [show place.body + (m.pc + 14 * args.length + 12) = place.body + m.pc + 14 * args.length + 12 by omega]
    exact relative_eq _ _ _ (by omega) entrySmall
  -- s2 agrees with the entry memory outside the frame's window and the heap
  have outside2 : ∀ address, ¬Below frame.top frame.window address → ¬frame.InHeap address →
      s2.memory address = frame.entry address := by
    intro address outside notHeap
    rw [memory2, write64_frame _ _ _ _ (fun lane => ne_of_below outside (pushBelow lane)),
      memory1b, write64_frame _ _ _ _ (fun lane => ne_of_below outside (targetLaneBelow lane)),
      memory1 _ (fun j inArgs lane => ne_of_below outside (targetBelow j inArgs lane))]
    exact rel.unchanged address outside notHeap
  -- the heap, as the callee sees it
  have registers2 : ∀ register, register ≠ 0 → register ≠ 4 → s2.registers register = s.registers register := by
    intro register zero four
    simp only [s2, s1b, State.call, State.store64, if_neg four]
    exact registers1 register zero
  have base2 : s2.registers heapBaseRegister = frame.heapBase :=
    (registers2 _ (by decide) (by decide)).trans rel.heapBase
  have limit2 : (s2.registers limitRegister).toNat = frame.heapLimit := by
    rw [registers2 _ (by decide) (by decide), rel.preserved _ limit_not_scratch]; rfl
  have heap2 : s2.InHeap = frame.InHeap := by
    unfold State.InHeap Frame.InHeap
    rw [base2, limit2]
  have shifted : frame.top - BitVec.ofNat 64 (fb + 16) + 8 = frame.top - BitVec.ofNat 64 (fb + 8) := by
    bv_omega
  have heapAt2 : HeapAt inner s2 m.heap :=
    { cursor := (registers2 _ (by decide) (by decide)).trans rel.cursor
      fsp := (registers2 _ (by decide) (by decide)).trans rel.fsp
      limit := by rw [limit2]; exact rel.limit
      top := rel.top
      small := by rw [rel.limit]; exact fits.heapSmall
      bytes := fun a inside => by
        have inside' : a < frame.heapLimit := by rw [← rel.limit]; exact inside
        rw [base2, memory2, write64_frame _ _ _ _ (fun lane => heap_ne_below fits inside' (pushBelow lane)),
          memory1b, write64_frame _ _ _ _ (fun lane => heap_ne_below fits inside' (targetLaneBelow lane)),
          memory1 _ (fun j inArgs lane => heap_ne_below fits inside' (targetBelow j inArgs lane))]
        exact rel.heap a inside
      apart := fun address inHeap below => by
        rw [heap2] at inHeap
        rw [rsp2, shifted] at below
        exact fits.notHeap ((below.shift (by omega)).mono (by omega)) inHeap
      io := io1.trans rel.io }
  have stack2 : StackAt binary.guard inner s2 := by
    have stack := fits.stack
    have high := fits.high
    have checked := fits.checked
    rw [← guard]
    constructor
    · rw [registers2 _ (by decide) (by decide), rel.preserved _ stack_not_scratch, rsp2, BitVec.toNat_sub,
        BitVec.toNat_ofNat]
      omega
    · rw [registers2 _ (by decide) (by decide), rel.preserved _ stack_not_scratch]
      exact high
    · omega
  -- the callee
  rcases contract s2 (by omega)
    (by
      intro index bound
      rw [outside2 _ (imageApart index bound) (imageHeap index bound)]
      exact image index bound)
    (by
      intro index bound below
      rw [rsp2] at below
      exact imageApart index bound ((below.shift (by omega)).mono (by omega)))
    (by rw [heap2]; exact imageHeap)
    rip2
    (by
      intro k bound
      rw [readSlots_length] at bound
      rw [rsp2, readSlots_getElem _ _ _ bound, ← rel.slots _ (argsFit _ (List.getElem_mem _)), ← reads1 k bound]
      rw [address k (by omega), memory2, read64_frame, memory1b, read64_frame]
      all_goals
        intro i lane
        rw [targetLane k bound i.val (by omega)]
        first
          | (rw [pushLane lane.val lane.isLt]; exact depth_ne _ (by omega) (by omega) (by omega))
          | (rw [targetDepth lane.val lane.isLt]; exact depth_ne _ (by omega) (by omega) (by omega)))
    heapAt2 stack2 with ⟨p, n3, s3, steps3, det3, returned⟩ | q
  case inr =>
    exact .inr ⟨_, s2, by omega,
      det1.trans (Det.cons step1b (fspSave_noRead saveLoaded) (Det.step step2 (call_noRead callLoaded))), q⟩
  -- the activation after the call: the frame as it was after the save
  have frameKept : ∀ d, d ≤ fb + 8 → 0 < d →
      s3.memory (frame.top - BitVec.ofNat 64 d) = s1b.memory (frame.top - BitVec.ofNat 64 d) := by
    intro d small positive
    rw [returned.unchanged _ (by rw [rsp2]; exact not_below_above _ (by omega) (by omega))
      (by rw [heap2]; exact fits.notHeap (below_depth _ (by omega) (by omega) (by omega))), memory2,
      write64_frame _ _ _ _ (by
        intro lane
        rw [pushLane lane.val lane.isLt]
        exact depth_ne _ (by omega) (by omega) (by omega))]
  have keptS : ∀ d, d ≤ fb + 8 → 0 < d → (∀ lane, lane < 8 → d ≠ 8 * target + 16 - lane) →
      s1b.memory (frame.top - BitVec.ofNat 64 d) = s.memory (frame.top - BitVec.ofNat 64 d) := by
    intro d small positive away
    rw [memory1b, write64_frame _ _ _ _ (by
        intro lane
        rw [targetDepth lane.val lane.isLt]
        exact depth_ne _ (away lane.val lane.isLt) (by omega) (by omega)),
      memory1 _ (by
        intro j inArgs lane
        rw [targetLane j inArgs lane.val (by omega)]
        exact depth_ne _ (by omega) (by omega) (by omega))]
  have unchanged3 : ∀ address, ¬Below frame.top frame.window address → ¬frame.InHeap address →
      s3.memory address = frame.entry address := by
    intro address outside notHeap
    rw [returned.unchanged _ (by
      rw [rsp2]
      intro below
      exact outside ((below.shift (by omega)).mono (by omega))) (by rw [heap2]; exact notHeap)]
    exact outside2 address outside notHeap
  have rip3 : s3.rip = frame.base + BitVec.ofNat 64 (m.pc + 14 * args.length + 12) := by
    rw [returned.rip, rsp2, memory2, read64_write64]
  have rbp3 : s3.registers rbpRegister = frame.top - 8 := by
    rw [returned.rbp]
    simp only [s2, s1b, State.call, State.store64, rbpRegister, if_neg (show (5 : Register) ≠ 4 by decide)]
    rw [registers1 5 (by decide)]
    exact rel.rbp
  -- `mov rbx, [rbp + disp32]`: the caller's frame pointer again
  have loadLoaded : CodeAt s3.memory s3.rip (fspLoadBytes target) := by
    have tail := loaded.prefix.suffix
    rw [List.length_append, List.length_append, copyBytes_length, fspSaveBytes_length, callLength] at tail
    intro index bound
    have away := apart (14 * args.length + 7 + 5 + index) (by rw [fspLoadBytes_length] at bound; omega)
    have heapAway := codeHeap (14 * args.length + 7 + 5 + index) (by rw [fspLoadBytes_length] at bound; omega)
    have here : s3.rip + BitVec.ofNat 64 index = s.rip + BitVec.ofNat 64 (14 * args.length + 7 + 5 + index) := by
      rw [rip3, rel.rip]
      bv_omega
    rw [here, unchanged3 _ away heapAway, ← rel.unchanged _ away heapAway, BitVec.ofNat_add, ← BitVec.add_assoc]
    exact tail index bound
  let s3b := s3.load64 fspRegister rbpRegister (BitVec.ofInt 32 (frameDisplacement target))
    (fspLoadBytes target).length
  have step3b : Lanius.X86.Machine.Step s3 s3b := fspLoad_step s3 s3b target loadLoaded rfl
  have regs3b : ∀ register, register ≠ fspRegister → s3b.registers register = s3.registers register :=
    fun register ne => by simp only [s3b, State.load64, if_neg ne]
  have rbx3 : s3b.registers fspRegister = BitVec.ofNat 64 m.heap.fsp := by
    have address : s3.registers rbpRegister + (BitVec.ofInt 32 (frameDisplacement target)).signExtend 64 =
        frameSlotAddress (frame.top - 8) target := by rw [rbp3]; rfl
    show (if fspRegister = fspRegister then read64 s3.memory (s3.registers rbpRegister +
      (BitVec.ofInt 32 (frameDisplacement target)).signExtend 64) else s3.registers fspRegister) = _
    rw [if_pos rfl, address,← read64_write64 s1.memory (frameSlotAddress (frame.top - 8) target) (BitVec.ofNat 64 m.heap.fsp),
      ← memory1b]
    apply read64_congr
    intro lane
    rw [targetDepth lane.val (by omega)]
    exact frameKept _ (by omega) (by omega)
  let m3 : Machine := { m with pc := m.pc + 14 * args.length + 19, acc := s3b.registers 0,
                               slots := fun k => if k = target then BitVec.ofNat 64 m.heap.fsp else m.slots k,
                               heap := { after with fsp := m.heap.fsp } }
  have rel3 : Rel frame s3b m3 := by
    refine ⟨?_, ?_, ?_, rfl, ?_, ?_, ?_, ?_, ?_, ?_, returned.top, rbx3, ?_, returned.io⟩
    · show s3.rip + BitVec.ofNat 64 (fspLoadBytes target).length =
        frame.base + BitVec.ofNat 64 (m.pc + 14 * args.length + 19)
      rw [rip3, fspLoadBytes_length, BitVec.add_assoc, ← BitVec.ofNat_add,
        show m.pc + 14 * args.length + 12 + 7 = m.pc + 14 * args.length + 19 by omega]
    · rw [regs3b _ (by decide)]
      exact rbp3
    · rw [regs3b _ (by decide), returned.rsp, rsp2, fbEq]
      bv_omega
    · intro other inFrame
      have toS1b : read64 s3b.memory (frameSlotAddress (frame.top - 8) other) =
          read64 s1b.memory (frameSlotAddress (frame.top - 8) other) := by
        apply read64_congr
        intro lane
        rw [sourceLane other inFrame lane.val (by omega)]
        exact frameKept _ (by omega) (by omega)
      rw [toS1b]
      show _ = if other = target then BitVec.ofNat 64 m.heap.fsp else m.slots other
      by_cases same : other = target
      · rw [if_pos same, same, memory1b, read64_write64]
      · rw [if_neg same, ← rel.slots other inFrame]
        apply read64_congr
        intro lane
        rw [sourceLane other inFrame lane.val (by omega)]
        exact keptS _ (by omega) (by omega) (fun l small => by omega)
    · rw [← rel.saved]
      apply read64_congr
      intro lane
      rw [savedLane lane.val lane.isLt]
      show s3.memory _ = _
      rw [frameKept _ (by omega) (by omega)]
      exact keptS _ (by omega) (by omega) (fun l small => by omega)
    · intro register other
      have notFsp : register ≠ fspRegister := by
        rintro rfl
        exact other (.inr (.inr (.inr (.inr (.inr (.inr (.inr (.inr (.inr rfl)))))))))
      obtain ⟨zero, -, four, -, -⟩ := not_scratch other
      rw [regs3b register notFsp, returned.preserved register other]
      simp only [s2, s1b, State.call, State.store64, if_neg four]
      rw [registers1 register zero]
      exact rel.preserved register other
    · intro address outside notHeap
      exact unchanged3 address outside notHeap
    · rw [regs3b _ (by decide)]
      exact returned.cursor
    · show after.limit = _
      rw [returned.limit, limit2]
    · intro a inside
      show s3.memory _ = after.bytes a
      rw [← base2]
      exact returned.heap a inside
  -- the results, copied from below the stack to `target`
  have results3 : ∀ k (bound : k < values.length),
      read64 s3b.memory (frameSlotAddress (frame.top - 8) (first + k)) = values[k] := by
    intro k bound
    show read64 s3.memory _ = _
    rw [show first + k = first + 0 + k by omega, ← address k (by omega), ← rsp2]
    exact returned.results k bound
  have addr3 : ∀ index, s3b.rip + BitVec.ofNat 64 index =
      s.rip + BitVec.ofNat 64 (14 * args.length + 7 + 5 + 7 + index) := by
    intro index
    rw [rel3.rip, rel.rip, BitVec.add_assoc, BitVec.add_assoc, ← BitVec.ofNat_add, ← BitVec.ofNat_add]
    congr 2
    show m.pc + 14 * args.length + 19 + index = _
    omega
  have loaded3 : CodeAt s3b.memory s3b.rip (copyBytes target (slotRange first count) 0) := by
    have tail := loaded.suffix
    rw [List.length_append, List.length_append, List.length_append, copyBytes_length, fspSaveBytes_length,
      callLength, fspLoadBytes_length] at tail
    intro index bound
    rw [copyBytes_length, slotRange_length] at bound
    have away := apart (14 * args.length + 7 + 5 + 7 + index) (by omega)
    have heapAway := codeHeap (14 * args.length + 7 + 5 + 7 + index) (by omega)
    rw [addr3, rel3.unchanged _ away heapAway, ← rel.unchanged _ away heapAway, BitVec.ofNat_add,
      ← BitVec.add_assoc]
    exact tail index (by rw [copyBytes_length, slotRange_length]; omega)
  have inRange : ∀ src ∈ slotRange first count, first ≤ src ∧ src < first + count := by
    intro src mem
    rw [slotRange_eq, List.mem_range'_1] at mem
    exact mem
  obtain ⟨n4, s4, steps4, det4, rel4⟩ := copy_simulates rel3 fits (target := target) loaded3
    (fun index bound => by
      rw [slotRange_length] at bound
      rw [addr3]
      exact apart _ (by omega))
    (by rw [slotRange_length]; omega)
    (fun src mem => by have := inRange src mem; unfold slotLimit; omega)
    (fun src mem => .inr (by have := inRange src mem; rw [slotRange_length]; omega))
  have got : (slotRange first count).map (fun src => read64 s3b.memory (frameSlotAddress (frame.top - 8) src)) =
      values := by
    apply List.ext_getElem (by rw [List.length_map, slotRange_length, counted])
    intro k bound bound'
    rw [List.getElem_map, ← results3 k bound']
    simp only [slotRange_eq, List.getElem_range', Nat.one_mul]
  rw [got, slotRange_length] at rel4
  refine .inl ⟨p, _, s4, (steps1.trans (.cons step1b (.cons step2 (steps3.trans (.cons step3b steps4))))),
    det1.trans (Det.cons step1b (fspSave_noRead saveLoaded) (Det.cons step2 (call_noRead callLoaded)
      (det3.trans (Det.cons step3b (fspLoad_noRead loadLoaded) det4)))),
    rel4.congr ?_ ?_ ?_ rfl⟩
  · simp only [Machine.copied, m3, size]
    omega
  · simp only [Machine.copied, m3]
    cases values with
    | nil => simp at counted; omega
    | cons v rest => rfl
  · intro k _
    simp only [Machine.copied, writeSlots, m3]
    by_cases inside : target ≤ k ∧ k < target + values.length
    · simp only [if_pos inside]
    · have ne : k ≠ target := fun h => inside ⟨by omega, by omega⟩
      simp only [if_neg inside, if_neg ne]

/-- `bump`: round the cursor up, check the limit, advance the cursor. -/
theorem bump_simulates (rel : Rel frame s m) (fits : frame.Fits) {shift : Nat} (shiftSmall : shift < 32)
    (loaded : CodeAt s.memory s.rip (bumpSpec shift))
    (room : alignUp m.heap.cursor shift + m.acc.toNat ≤ m.heap.limit) :
    ∃ n s', Steps n s s' ∧ Det n s s' ∧ Rel frame s' { m with
      pc := m.pc + (Instr.bump shift).size
      acc := BitVec.ofNat 64 (alignUp m.heap.cursor shift)
      heap := { m.heap with cursor := alignUp m.heap.cursor shift + m.acc.toNat } } := by
  obtain ⟨s', steps, det, io, memory, rip, acc, cursor, kept⟩ := bump_steps s shift shiftSmall loaded rel.cursor
    rel.limitNat (by rw [rel.limit]; exact fits.heapSmall) (by rw [rel.acc]; exact room)
  rw [rel.acc] at cursor
  refine ⟨12, s', steps, det, ?_⟩
  exact
    { rip := rip.trans (rel.advance 58)
      rbp := (kept _ (by decide) (by decide) (by decide) (by decide)).trans rel.rbp
      rsp := (kept _ (by decide) (by decide) (by decide) (by decide)).trans rel.rsp
      acc := acc
      slots := by rw [memory]; exact rel.slots
      saved := by rw [memory]; exact rel.saved
      preserved := fun register other => by
        obtain ⟨zero, one, -, -, eleven, thirteen, -⟩ := not_scratch other
        rw [kept register zero one eleven thirteen]
        exact rel.preserved register other
      unchanged := by rw [memory]; exact rel.unchanged
      cursor := cursor
      limit := rel.limit
      top := rel.top
      fsp := (kept _ (by decide) (by decide) (by decide) (by decide)).trans rel.fsp
      heap := by rw [memory]; exact rel.heap
      io := io.trans rel.io }

/-- `loadAt`: the heap byte at the accumulator. -/
theorem loadAt_simulates (rel : Rel frame s m) (loaded : CodeAt s.memory s.rip loadAtSpec)
    (inside : m.acc.toNat < m.heap.limit) :
    ∃ n s', Steps n s s' ∧ Det n s s' ∧ Rel frame s' { m with
      pc := m.pc + Instr.loadAt.size
      acc := BitVec.ofNat 64 (m.heap.bytes m.acc.toNat).toNat } := by
  obtain ⟨s', steps, det, io, memory, rip, acc, kept⟩ := loadAt_steps s loaded
  refine ⟨2, s', steps, det, Rel.accumulate rel memory 10 rip (fun register zero _ => kept register zero) ?_ io⟩
  rw [acc, rel.heapBase, rel.acc, ← rel.heap _ inside, BitVec.ofNat_toNat, BitVec.setWidth_eq]

/-- `storeAt slot`: the low byte of the accumulator to the heap at the offset in `slot`. -/
theorem storeAt_simulates (rel : Rel frame s m) (fits : frame.Fits) (inFrame : slot < frame.slots)
    (loaded : CodeAt s.memory s.rip (storeAtSpec slot)) (inside : (m.slots slot).toNat < m.heap.limit) :
    ∃ n s', Steps n s s' ∧ Det n s s' ∧ Rel frame s' { m with
      pc := m.pc + (Instr.storeAt slot).size
      heap := m.heap.write (m.slots slot).toNat (lowByte m.acc) } := by
  obtain ⟨s', steps, det, io, rip, memory, kept⟩ := storeAt_steps s slot loaded
  have target : s.registers heapBaseRegister + read64 s.memory (s.registers rbpRegister +
      (BitVec.ofInt 32 (frameDisplacement slot)).signExtend 64) =
      frame.heapBase + BitVec.ofNat 64 (m.slots slot).toNat := by
    rw [rel.heapBase, show rbpRegister = (5 : Register) from rfl, rel_slot rel inFrame, BitVec.ofNat_toNat,
      BitVec.setWidth_eq]
  rw [target, rel.acc] at memory
  have targetHeap : frame.InHeap (frame.heapBase + BitVec.ofNat 64 (m.slots slot).toNat) :=
    frame.inHeap (by rw [← rel.limit]; exact inside)
  have away : ∀ address, Below frame.top frame.window address → s'.memory address = s.memory address := by
    intro address below
    simp only [memory]
    rw [if_neg (fun (same : address = _) => fits.notHeap below (same ▸ targetHeap))]
  have limitSmall := fits.heapSmall
  refine ⟨3, s', steps, det, ?_⟩
  exact
    { rip := rip.trans (rel.advance 16)
      rbp := (kept _ (by decide)).trans rel.rbp
      rsp := (kept _ (by decide)).trans rel.rsp
      acc := (kept _ (by decide)).trans rel.acc
      slots := fun other otherIn => by
        rw [← rel.slots other otherIn]
        apply read64_congr
        intro lane
        exact away _ (slot_below fits otherIn lane.isLt)
      saved := by
        rw [← rel.saved]
        apply read64_congr
        intro lane
        exact away _ (saved_below fits lane.isLt)
      preserved := fun register other => by
        obtain ⟨-, one, -⟩ := not_scratch other
        rw [kept register one]
        exact rel.preserved register other
      unchanged := fun address outside notHeap => by
        simp only [memory]
        rw [if_neg (fun (same : address = _) => notHeap (same ▸ targetHeap))]
        exact rel.unchanged address outside notHeap
      cursor := (kept _ (by decide)).trans rel.cursor
      fsp := (kept _ (by decide)).trans rel.fsp
      limit := rel.limit
      top := rel.top
      heap := fun a below => by
        have small : a < 2 ^ 62 := by
          have := rel.limit
          have : a < m.heap.limit := below
          omega
        simp only [memory, Heap.write]
        by_cases same : a = (m.slots slot).toNat
        · rw [if_pos (by rw [same]), if_pos same]
        · rw [if_neg ?_, if_neg same]
          · exact rel.heap a below
          · intro eq
            apply same
            have := (m.slots slot).isLt
            bv_omega
      io := io.trans rel.io }

/-- `loadWordAt width`: the heap word at the accumulator. -/
theorem loadWordAt_simulates (rel : Rel frame s m) {width : MemWidth} (loaded : CodeAt s.memory s.rip (loadWordSpec width))
    (inside : m.acc.toNat + width.bytes ≤ m.heap.limit) :
    ∃ n s', Steps n s s' ∧ Det n s s' ∧ Rel frame s' { m with
      pc := m.pc + (Instr.loadWordAt width).size
      acc := BitVec.ofNat 64 (m.heap.readLE m.acc.toNat width.bytes) } := by
  obtain ⟨s', steps, det, io, memory, rip, acc, kept⟩ := loadWord_steps s width loaded
  refine ⟨2, s', steps, det, Rel.accumulate rel memory _ rip (fun register zero _ => kept register zero) ?_ io⟩
  rw [acc, rel.heapBase, rel.acc, wordRead_eq,
    show frame.heapBase + m.acc = frame.heapBase + BitVec.ofNat 64 m.acc.toNat by simp,
    memLE_heap _ _ _ _ _ (fun k lt => rel.heap _ (by omega))]

/-- `storeWordAt width slot`: the low bytes of the accumulator to the heap at the offset in `slot`. -/
theorem storeWordAt_simulates (rel : Rel frame s m) (fits : frame.Fits) {width : MemWidth} (inFrame : slot < frame.slots)
    (loaded : CodeAt s.memory s.rip (storeWordSpec width slot))
    (inside : (m.slots slot).toNat + width.bytes ≤ m.heap.limit) :
    ∃ n s', Steps n s s' ∧ Det n s s' ∧ Rel frame s' { m with
      pc := m.pc + (Instr.storeWordAt width slot).size
      heap := m.heap.writeLE (m.slots slot).toNat m.acc.toNat width.bytes } := by
  obtain ⟨s', steps, det, io, rip, memory, kept⟩ := storeWord_steps s width slot loaded
  have target : s.registers heapBaseRegister + read64 s.memory (s.registers rbpRegister +
      (BitVec.ofInt 32 (frameDisplacement slot)).signExtend 64) =
      frame.heapBase + BitVec.ofNat 64 (m.slots slot).toNat := by
    rw [rel.heapBase, show rbpRegister = (5 : Register) from rfl, rel_slot rel inFrame, BitVec.ofNat_toNat,
      BitVec.setWidth_eq]
  rw [target, rel.acc] at memory
  have limitSmall := fits.heapSmall
  have heapLimit := rel.limit
  have lanes : ∀ k, k < width.bytes →
      frame.InHeap (frame.heapBase + BitVec.ofNat 64 (m.slots slot).toNat + BitVec.ofNat 64 k) :=
    fun k lt => ⟨(m.slots slot).toNat + k, by omega, by rw [BitVec.add_assoc, ← BitVec.ofNat_add]⟩
  have outside : ∀ address, ¬frame.InHeap address → s'.memory address = s.memory address := by
    intro address notHeap
    rw [memory]
    exact wordWrite_outside _ _ _ _ _ fun k lt same => notHeap (same ▸ lanes k lt)
  have away : ∀ address, Below frame.top frame.window address → s'.memory address = s.memory address :=
    fun address below => outside address (fits.notHeap below)
  refine ⟨3, s', steps, det, ?_⟩
  exact
    { rip := rip.trans (rel.advance _)
      rbp := (kept _ (by decide)).trans rel.rbp
      rsp := (kept _ (by decide)).trans rel.rsp
      acc := (kept _ (by decide)).trans rel.acc
      slots := fun other otherIn => by
        rw [← rel.slots other otherIn]
        apply read64_congr
        intro lane
        exact away _ (slot_below fits otherIn lane.isLt)
      saved := by
        rw [← rel.saved]
        apply read64_congr
        intro lane
        exact away _ (saved_below fits lane.isLt)
      preserved := fun register other => by
        obtain ⟨-, one, -⟩ := not_scratch other
        rw [kept register one]
        exact rel.preserved register other
      unchanged := fun address outsideStack notHeap => by
        rw [outside address notHeap]
        exact rel.unchanged address outsideStack notHeap
      cursor := by
        rw [(Heap.writeLE_limit _ _ _ _).2]
        exact (kept _ (by decide)).trans rel.cursor
      limit := by rw [(Heap.writeLE_limit _ _ _ _).1]; exact rel.limit
      top := by rw [(Heap.writeLE_top _ _ _ _).1, (Heap.writeLE_limit _ _ _ _).1]; exact rel.top
      fsp := by rw [(Heap.writeLE_top _ _ _ _).2]; exact (kept _ (by decide)).trans rel.fsp
      heap := fun a below => by
        rw [(Heap.writeLE_limit _ _ _ _).1] at below
        have small : a < 2 ^ 62 := by omega
        have pSmall := (m.slots slot).isLt
        rw [Heap.writeLE_bytes]
        by_cases hit : (m.slots slot).toNat ≤ a ∧ a < (m.slots slot).toNat + width.bytes
        · rw [if_pos hit, show frame.heapBase + BitVec.ofNat 64 a = frame.heapBase +
              BitVec.ofNat 64 (m.slots slot).toNat + BitVec.ofNat 64 (a - (m.slots slot).toNat) by
              rw [BitVec.add_assoc, ← BitVec.ofNat_add, Nat.add_sub_cancel' hit.1],
            memory, wordWrite_lane _ _ _ _ _ (by omega)]
        · rw [if_neg hit, memory, wordWrite_outside _ _ _ _ _ fun k lt same => hit ?_]
          · exact rel.heap a below
          · have := MemWidth.bytes_le width
            bv_omega
      io := by rw [Heap.writeLE_io]; exact io.trans rel.io }

/-- The bytes `write` sends from the heap are the heap's. -/
theorem bytesAt_heap (rel : Rel frame s m) :
    ∀ (count a : Nat), a + count ≤ m.heap.limit →
      bytesAt s.memory (frame.heapBase + BitVec.ofNat 64 a) count = m.heap.slice a count
  | 0, _, _ => rfl
  | count + 1, a, inside => by
    rw [bytesAt, Heap.slice, rel.heap a (by omega),
      show frame.heapBase + BitVec.ofNat 64 a + 1 = frame.heapBase + BitVec.ofNat 64 (a + 1) by
        rw [BitVec.add_assoc]; congr 1; bv_omega,
      bytesAt_heap rel count (a + 1) (by omega)]

theorem memoryBytes_length7 (reg : Register) (slot : Nat) :
    (memoryBytes .w64 true reg rbpRegister (frameDisplacement slot)).length =
      (memoryHeader .w64 true reg rbpRegister).length + 4 := by
  simp only [memoryBytes, Lanius.Semantics.i32Bytes, List.length_append, List.length_map, List.length_range]

/-- The kernel's `read` stores bytes that fit in the heap: it leaves every
address outside the heap as it was. -/
theorem writeBytes_outside (memory : Memory) {base : BitVec 64} {a limit : Nat} {bytes : List UInt8}
    (fit : bytes = [] ∨ a + bytes.length ≤ limit) {address : BitVec 64} (outside : ¬InHeap base limit address) :
    writeBytes memory (base + BitVec.ofNat 64 a) bytes address = memory address := by
  unfold writeBytes
  rw [if_neg]
  intro lt
  rcases fit with empty | fit
  · subst empty; simp at lt
  apply outside
  refine ⟨a + (address - (base + BitVec.ofNat 64 a)).toNat, by omega, ?_⟩
  rw [BitVec.ofNat_add, BitVec.ofNat_toNat, BitVec.setWidth_eq, ← BitVec.add_assoc]
  bv_omega

/-- At a heap offset `b`, the kernel's `read` from heap offset `a` leaves the
heap's `writeAll`. -/
theorem writeBytes_heap (memory : Memory) {base : BitVec 64} {a b limit : Nat} {bytes : List UInt8}
    (fit : bytes = [] ∨ a + bytes.length ≤ limit) (small : limit < 2 ^ 62) (below : b < limit) :
    writeBytes memory (base + BitVec.ofNat 64 a) bytes (base + BitVec.ofNat 64 b) =
      if a ≤ b ∧ b - a < bytes.length then bytes.getD (b - a) 0 else memory (base + BitVec.ofNat 64 b) := by
  unfold writeBytes
  have diff : base + BitVec.ofNat 64 b - (base + BitVec.ofNat 64 a) = BitVec.ofNat 64 b - BitVec.ofNat 64 a := by
    bv_omega
  rw [diff]
  rcases fit with empty | fit
  · subst empty; simp
  by_cases le : a ≤ b
  · have nat : (BitVec.ofNat 64 b - BitVec.ofNat 64 a).toNat = b - a := by
      rw [BitVec.toNat_sub, BitVec.toNat_ofNat, BitVec.toNat_ofNat]
      omega
    rw [nat]
    simp only [le, true_and]
  · have big : bytes.length ≤ (BitVec.ofNat 64 b - BitVec.ofNat 64 a).toNat := by
      rw [BitVec.toNat_sub, BitVec.toNat_ofNat, BitVec.toNat_ofNat]
      omega
    rw [if_neg (by omega), if_neg (by omega)]

/-- `sys .read slot`: as `sys .write slot`, but the kernel stores the bytes it
read in the heap. -/
theorem read_simulates (rel : Rel frame s m) (fits : frame.Fits) (inFrame : slot + 3 ≤ frame.slots)
    (loaded : CodeAt s.memory s.rip (sysSpec .read slot))
    (codeHeap : ∀ index, index < 34 → ¬frame.InHeap (s.rip + BitVec.ofNat 64 index))
    {result : BitVec 64} {after : Heap}
    (ran : Syscall.read.run [m.slots slot, m.slots (slot + 1), m.slots (slot + 2)] m.heap = some (result, after)) :
    ∃ n s', Steps n s s' ∧ Det n s s' ∧ Rel frame s' { m with
      pc := m.pc + (Instr.sys .read slot).size, acc := result, heap := after } := by
  rw [Syscall.run] at ran
  split at ran
  next ok =>
    obtain ⟨fdOk, countOk, inside⟩ := ok
    cases ran
    have c0 := loaded
    simp only [sysSpec] at c0
    let s1 := s.load64 rdiRegister rbpRegister (BitVec.ofInt 32 (frameDisplacement slot))
      (memoryBytes .w64 true rdiRegister rbpRegister (frameDisplacement slot)).length
    have t1 : Lanius.X86.Machine.Step s s1 :=
      Lanius.X86.Machine.Step.decoded _ c0.prefix _ _
        (by simpa [memoryInstruction] using
          memory_decodes .w64 true rdiRegister rbpRegister (frameDisplacement slot) [])
        rfl rfl
    have c1 := c0.next (s' := s1) rfl rfl
    let s2 := s1.load64 rsiRegister rbpRegister (BitVec.ofInt 32 (frameDisplacement (slot + 1)))
      (memoryBytes .w64 true rsiRegister rbpRegister (frameDisplacement (slot + 1))).length
    have t2 : Lanius.X86.Machine.Step s1 s2 :=
      Lanius.X86.Machine.Step.decoded _ c1.prefix _ _
        (by simpa [memoryInstruction] using
          memory_decodes .w64 true rsiRegister rbpRegister (frameDisplacement (slot + 1)) [])
        rfl rfl
    have c2 := c1.next (s' := s2) rfl rfl
    let s3 := s2.alu64 .add rsiRegister heapBaseRegister false (aluBytes .w64 .add rsiRegister heapBaseRegister).length
    have t3 : Lanius.X86.Machine.Step s2 s3 := alu_step .w64 s2 s3 .add _ _ c2.prefix false rfl
    have c3 := c2.next (s' := s3) rfl rfl
    let s4 := s3.load64 rdxRegister rbpRegister (BitVec.ofInt 32 (frameDisplacement (slot + 2)))
      (memoryBytes .w64 true rdxRegister rbpRegister (frameDisplacement (slot + 2))).length
    have t4 : Lanius.X86.Machine.Step s3 s4 :=
      Lanius.X86.Machine.Step.decoded _ c3.prefix _ _
        (by simpa [memoryInstruction] using
          memory_decodes .w64 true rdxRegister rbpRegister (frameDisplacement (slot + 2)) [])
        rfl rfl
    have c4 := c3.next (s' := s4) rfl rfl
    let s5 := s4.immediate32 0 Syscall.read.linux (immediateBytes .w32 0 Syscall.read.linux 0).length
    have t5 : Lanius.X86.Machine.Step s4 s5 := immediate_step s4 s5 .w32 0 _ _ c4.prefix rfl
    have c5 := c4.next (s' := s5) rfl rfl
    have r7 : s5.registers 7 = m.slots slot := rel_slot (slot := slot) rel (by omega)
    have r2 : s5.registers 2 = m.slots (slot + 2) := by
      show read64 s.memory (s.registers 5 + (BitVec.ofInt 32 (frameDisplacement (slot + 2))).signExtend 64) = _
      exact rel_slot rel (by omega)
    have r6 : s5.registers 6 = m.slots (slot + 1) + frame.heapBase := by
      have base : s2.registers heapBaseRegister = frame.heapBase := rel.heapBase
      have six : s2.registers 6 = m.slots (slot + 1) := by
        show read64 s.memory (s.registers 5 + (BitVec.ofInt 32 (frameDisplacement (slot + 1))).signExtend 64) = _
        exact rel_slot rel (by omega)
      show (Alu.add.result ((s2.registers 6).setWidth 64) ((s2.registers heapBaseRegister).setWidth 64)).setWidth 64 = _
      rw [base, six]
      simp [Alu.result]
    have r0 : s5.registers 0 = 0 := by
      show (Syscall.read.linux).setWidth 64 = 0
      decide
    have io5 : s5.io = m.heap.io := rel.io
    have memory5 : s5.memory = s.memory := rfl
    have address : m.slots (slot + 1) + frame.heapBase =
        frame.heapBase + BitVec.ofNat 64 (m.slots (slot + 1)).toNat := by
      rw [BitVec.ofNat_toNat, BitVec.setWidth_eq, BitVec.add_comm]
    let bytes := m.heap.io.input.take (m.slots (slot + 2)).toNat
    have bytes5 : s5.io.input.take (s5.registers 2).toNat = bytes := by rw [io5, r2]
    let s6 := s5.syscalled (BitVec.ofNat 64 (s5.io.input.take (s5.registers 2).toNat).length) 0
      (writeBytes s5.memory (s5.registers 6) (s5.io.input.take (s5.registers 2).toNat))
      { s5.io with input := s5.io.input.drop (s5.registers 2).toNat }
    have kernel : Kernel s5 s6 := .read r0 (by rw [r7]; exact fdOk) (by rw [r2]; exact countOk) 0
    have t6 : Lanius.X86.Machine.Step s5 s6 := .syscalled c5.prefix kernel
    have limitSmall : frame.heapLimit < 2 ^ 62 := fits.heapSmall
    have fit : bytes = [] ∨ (m.slots (slot + 1)).toNat + bytes.length ≤ frame.heapLimit := by
      rw [← rel.limit, ← rel.top]; exact inside
    have memory6 : s6.memory = writeBytes s.memory (frame.heapBase + BitVec.ofNat 64 (m.slots (slot + 1)).toNat)
        bytes := by
      show writeBytes s5.memory (s5.registers 6) (s5.io.input.take (s5.registers 2).toNat) = _
      rw [bytes5, r6, address, memory5]
    have away : ∀ address, ¬frame.InHeap address → s6.memory address = s.memory address := by
      intro address outside
      rw [memory6]
      exact writeBytes_outside _ fit outside
    have rip5 : s5.rip = s.rip + BitVec.ofNat 64 29 := by
      have l1 := memoryBytes_length7 rdiRegister slot
      have l2 := memoryBytes_length7 rsiRegister (slot + 1)
      have l4 := memoryBytes_length7 rdxRegister (slot + 2)
      simp only [s5, s4, s3, s2, s1, State.immediate32, State.load64,
        State.alu64, State.alu, l1, l2, l4, show (memoryHeader .w64 true rdiRegister rbpRegister).length = 3 from rfl,
        show (memoryHeader .w64 true rsiRegister rbpRegister).length = 3 from rfl,
        show (memoryHeader .w64 true rdxRegister rbpRegister).length = 3 from rfl,
        show (aluBytes .w64 .add rsiRegister heapBaseRegister).length = 3 from rfl,
        show (immediateBytes .w32 0 Syscall.read.linux 0).length = 5 from rfl]
      bv_omega
    have c6 : CodeAt s6.memory s6.rip (moveBytes .w64 r11Register rcxRegister) := by
      have moved : CodeAt s5.memory (s5.rip + BitVec.ofNat 64 2) (moveBytes .w64 r11Register rcxRegister) :=
        c5.suffix
      intro index small
      have size : (moveBytes .w64 r11Register rcxRegister).length = 3 := rfl
      have rip6 : s6.rip = s5.rip + BitVec.ofNat 64 2 := rfl
      rw [rip6, away _ ?_]
      · exact moved index small
      · rw [rip5, BitVec.add_assoc, BitVec.add_assoc, ← BitVec.ofNat_add, ← BitVec.ofNat_add]
        exact codeHeap _ (by omega)
    let s7 := s6.move64 r11Register rcxRegister (moveBytes .w64 r11Register rcxRegister).length
    have t7 : Lanius.X86.Machine.Step s6 s7 := move_step s6 s7 .w64 _ _ c6 rfl
    have det : Det 7 s s7 :=
      Det.cons t1 (memory_noRead c0.prefix) (Det.cons t2 (memory_noRead c1.prefix)
        (Det.cons t3 (alu_noRead c2.prefix) (Det.cons t4 (memory_noRead c3.prefix)
          (Det.cons t5 (immediate_noRead c4.prefix) (Det.syscall t6 c5.prefix (by decide) c6 t7)))))
    have kept : ∀ register, register ≠ 0 → register ≠ 1 → register ≠ 2 → register ≠ 6 → register ≠ 7 →
        register ≠ 11 → s7.registers register = s.registers register := by
      intro register a b c d e f
      simp [s7, s6, s5, s4, s3, s2, s1, State.move64, State.syscalled, State.immediate32, State.load64,
        State.alu64, State.alu, a, b, c, d, e, f, rdiRegister, rsiRegister, rdxRegister, r11Register,
        heapBaseRegister]
    have rip7 : s7.rip = s.rip + BitVec.ofNat 64 34 := by
      show s5.rip + 2 + BitVec.ofNat 64 (moveBytes .w64 r11Register rcxRegister).length = _
      rw [rip5, show (moveBytes .w64 r11Register rcxRegister).length = 3 from rfl]
      bv_omega
    have memory7 : s7.memory = s6.memory := rfl
    have acc7 : s7.registers 0 = BitVec.ofNat 64 bytes.length := by
      rw [← bytes5]
      simp [s7, s6, State.move64, State.syscalled, r11Register]
    have io7 : s7.io = { m.heap.io with input := m.heap.io.input.drop (m.slots (slot + 2)).toNat } := by
      show { s5.io with input := s5.io.input.drop (s5.registers 2).toNat } = _
      rw [io5, r2]
    refine ⟨7, s7, .cons t1 (.cons t2 (.cons t3 (.cons t4 (.cons t5 (.cons t6 (.cons t7 (.refl _))))))), det, ?_⟩
    exact
      { rip := rip7.trans (rel.advance 34)
        rbp := (kept 5 (by decide) (by decide) (by decide) (by decide) (by decide) (by decide)).trans rel.rbp
        rsp := (kept 4 (by decide) (by decide) (by decide) (by decide) (by decide) (by decide)).trans rel.rsp
        acc := acc7
        slots := fun other otherIn => by
          rw [← rel.slots other otherIn, memory7]
          apply read64_congr
          intro lane
          exact away _ (fits.notHeap (slot_below fits otherIn lane.isLt))
        saved := by
          rw [← rel.saved, memory7]
          apply read64_congr
          intro lane
          exact away _ (fits.notHeap (saved_below fits lane.isLt))
        preserved := fun register other => by
          obtain ⟨zero, one, -, -, eleven, -, two, six, seven⟩ := not_scratch other
          rw [kept register zero one two six seven eleven]
          exact rel.preserved register other
        unchanged := fun address outside notHeap => by
          rw [memory7, away address notHeap]
          exact rel.unchanged address outside notHeap
        cursor := (kept 13 (by decide) (by decide) (by decide) (by decide) (by decide) (by decide)).trans rel.cursor
        fsp := (kept 3 (by decide) (by decide) (by decide) (by decide) (by decide) (by decide)).trans rel.fsp
        limit := rel.limit
        top := rel.top
        heap := fun a below => by
          have below' : a < frame.heapLimit := by rw [← rel.limit]; exact below
          rw [memory7, memory6, writeBytes_heap _ fit limitSmall below']
          simp only [Heap.writeAll]
          split
          · rfl
          · exact rel.heap a below
        io := io7 }
  next => cases ran

/-- `sys kind slot`: the arguments to rdi, rsi (made an address) and rdx, the
number to rax, `syscall`, then `mov r11, rcx`. -/
theorem sys_simulates (rel : Rel frame s m) (fits : frame.Fits) (inFrame : slot + 3 ≤ frame.slots) {kind : Syscall}
    (loaded : CodeAt s.memory s.rip (sysSpec kind slot))
    (codeHeap : ∀ index, index < 34 → ¬frame.InHeap (s.rip + BitVec.ofNat 64 index))
    {result : BitVec 64} {after : Heap}
    (ran : kind.run [m.slots slot, m.slots (slot + 1), m.slots (slot + 2)] m.heap = some (result, after)) :
    ∃ n s', Steps n s s' ∧ Det n s s' ∧ Rel frame s' { m with
      pc := m.pc + (Instr.sys kind slot).size, acc := result, heap := after } := by
  cases kind
  case read => exact read_simulates rel fits inFrame loaded codeHeap ran
  rw [Syscall.run] at ran
  split at ran
  next ok =>
    obtain ⟨fdOk, countOk, inside⟩ := ok
    cases ran
    have c0 := loaded
    simp only [sysSpec] at c0
    let s1 := s.load64 rdiRegister rbpRegister (BitVec.ofInt 32 (frameDisplacement slot))
      (memoryBytes .w64 true rdiRegister rbpRegister (frameDisplacement slot)).length
    have t1 : Lanius.X86.Machine.Step s s1 :=
      Lanius.X86.Machine.Step.decoded _ c0.prefix _ _
        (by simpa [memoryInstruction] using
          memory_decodes .w64 true rdiRegister rbpRegister (frameDisplacement slot) [])
        rfl rfl
    have c1 := c0.next (s' := s1) rfl rfl
    let s2 := s1.load64 rsiRegister rbpRegister (BitVec.ofInt 32 (frameDisplacement (slot + 1)))
      (memoryBytes .w64 true rsiRegister rbpRegister (frameDisplacement (slot + 1))).length
    have t2 : Lanius.X86.Machine.Step s1 s2 :=
      Lanius.X86.Machine.Step.decoded _ c1.prefix _ _
        (by simpa [memoryInstruction] using
          memory_decodes .w64 true rsiRegister rbpRegister (frameDisplacement (slot + 1)) [])
        rfl rfl
    have c2 := c1.next (s' := s2) rfl rfl
    let s3 := s2.alu64 .add rsiRegister heapBaseRegister false (aluBytes .w64 .add rsiRegister heapBaseRegister).length
    have t3 : Lanius.X86.Machine.Step s2 s3 := alu_step .w64 s2 s3 .add _ _ c2.prefix false rfl
    have c3 := c2.next (s' := s3) rfl rfl
    let s4 := s3.load64 rdxRegister rbpRegister (BitVec.ofInt 32 (frameDisplacement (slot + 2)))
      (memoryBytes .w64 true rdxRegister rbpRegister (frameDisplacement (slot + 2))).length
    have t4 : Lanius.X86.Machine.Step s3 s4 :=
      Lanius.X86.Machine.Step.decoded _ c3.prefix _ _
        (by simpa [memoryInstruction] using
          memory_decodes .w64 true rdxRegister rbpRegister (frameDisplacement (slot + 2)) [])
        rfl rfl
    have c4 := c3.next (s' := s4) rfl rfl
    let s5 := s4.immediate32 0 Syscall.write.linux (immediateBytes .w32 0 Syscall.write.linux 0).length
    have t5 : Lanius.X86.Machine.Step s4 s5 := immediate_step s4 s5 .w32 0 _ _ c4.prefix rfl
    have c5 := c4.next (s' := s5) rfl rfl
    have r7 : s5.registers 7 = m.slots slot := rel_slot (slot := slot) rel (by omega)
    have r2 : s5.registers 2 = m.slots (slot + 2) := by
      show read64 s.memory (s.registers 5 + (BitVec.ofInt 32 (frameDisplacement (slot + 2))).signExtend 64) = _
      exact rel_slot rel (by omega)
    have r6 : s5.registers 6 = m.slots (slot + 1) + frame.heapBase := by
      have base : s2.registers heapBaseRegister = frame.heapBase := rel.heapBase
      have six : s2.registers 6 = m.slots (slot + 1) := by
        show read64 s.memory (s.registers 5 + (BitVec.ofInt 32 (frameDisplacement (slot + 1))).signExtend 64) = _
        exact rel_slot rel (by omega)
      show (Alu.add.result ((s2.registers 6).setWidth 64) ((s2.registers heapBaseRegister).setWidth 64)).setWidth 64 = _
      rw [base, six]
      simp [Alu.result]
    have r0 : s5.registers 0 = 1 := by
      show (Syscall.write.linux).setWidth 64 = 1
      decide
    let s6 := s5.syscalled (s5.registers 2) 0 s5.memory
      { s5.io with trace := s5.io.trace ++
        [.write (s5.registers 7).toNat (bytesAt s5.memory (s5.registers 6) (s5.registers 2).toNat)] }
    have kernel : Kernel s5 s6 := .write r0 (by rw [r7]; exact fdOk) (by rw [r2]; exact countOk) 0
    have t6 : Lanius.X86.Machine.Step s5 s6 := .syscalled c5.prefix kernel
    have c6 : CodeAt s6.memory s6.rip (moveBytes .w64 r11Register rcxRegister) := c5.next (s' := s6) rfl rfl
    let s7 := s6.move64 r11Register rcxRegister (moveBytes .w64 r11Register rcxRegister).length
    have t7 : Lanius.X86.Machine.Step s6 s7 := move_step s6 s7 .w64 _ _ c6 rfl
    have det : Det 7 s s7 :=
      Det.cons t1 (memory_noRead c0.prefix) (Det.cons t2 (memory_noRead c1.prefix)
        (Det.cons t3 (alu_noRead c2.prefix) (Det.cons t4 (memory_noRead c3.prefix)
          (Det.cons t5 (immediate_noRead c4.prefix) (Det.syscall t6 c5.prefix (by decide) c6 t7)))))
    have kept : ∀ register, register ≠ 0 → register ≠ 1 → register ≠ 2 → register ≠ 6 → register ≠ 7 →
        register ≠ 11 → s7.registers register = s.registers register := by
      intro register a b c d e f
      simp [s7, s6, s5, s4, s3, s2, s1, State.move64, State.syscalled, State.immediate32, State.load64,
        State.alu64, State.alu, a, b, c, d, e, f, rdiRegister, rsiRegister, rdxRegister, r11Register,
        heapBaseRegister]
    have rip7 : s7.rip = s.rip + BitVec.ofNat 64 34 := by
      have l1 := memoryBytes_length7 rdiRegister slot
      have l2 := memoryBytes_length7 rsiRegister (slot + 1)
      have l4 := memoryBytes_length7 rdxRegister (slot + 2)
      simp only [s7, s6, s5, s4, s3, s2, s1, State.move64, State.syscalled, State.immediate32, State.load64,
        State.alu64, State.alu, l1, l2, l4, show (memoryHeader .w64 true rdiRegister rbpRegister).length = 3 from rfl,
        show (memoryHeader .w64 true rsiRegister rbpRegister).length = 3 from rfl,
        show (memoryHeader .w64 true rdxRegister rbpRegister).length = 3 from rfl,
        show (aluBytes .w64 .add rsiRegister heapBaseRegister).length = 3 from rfl,
        show (immediateBytes .w32 0 Syscall.write.linux 0).length = 5 from rfl,
        show (moveBytes .w64 r11Register rcxRegister).length = 3 from rfl]
      bv_omega
    have io7 : s7.io = { s.io with trace := s.io.trace ++
        [.write (s5.registers 7).toNat (bytesAt s.memory (s5.registers 6) (s5.registers 2).toNat)] } := rfl
    have address : m.slots (slot + 1) + frame.heapBase =
        frame.heapBase + BitVec.ofNat 64 (m.slots (slot + 1)).toNat := by
      rw [BitVec.ofNat_toNat, BitVec.setWidth_eq, BitVec.add_comm]
    refine ⟨7, s7, .cons t1 (.cons t2 (.cons t3 (.cons t4 (.cons t5 (.cons t6 (.cons t7 (.refl _))))))), det, ?_⟩
    exact
      { rip := rip7.trans (rel.advance 34)
        rbp := (kept 5 (by decide) (by decide) (by decide) (by decide) (by decide) (by decide)).trans rel.rbp
        rsp := (kept 4 (by decide) (by decide) (by decide) (by decide) (by decide) (by decide)).trans rel.rsp
        acc := r2
        slots := rel.slots
        saved := rel.saved
        preserved := fun register other => by
          obtain ⟨zero, one, -, -, eleven, -, two, six, seven⟩ := not_scratch other
          rw [kept register zero one two six seven eleven]
          exact rel.preserved register other
        unchanged := rel.unchanged
        cursor := (kept 13 (by decide) (by decide) (by decide) (by decide) (by decide) (by decide)).trans rel.cursor
        fsp := (kept 3 (by decide) (by decide) (by decide) (by decide) (by decide) (by decide)).trans rel.fsp
        limit := rel.limit
        top := rel.top
        heap := rel.heap
        io := by rw [io7, r7, r6, r2, rel.io, address, bytesAt_heap rel _ _ (rel.top ▸ inside)] }
  next => cases ran

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
  codeHeap : ∀ index, index < codeSize instrs → ¬frame.InHeap (frame.base + BitVec.ofNat 64 index)
  imageHeap : ∀ index, index < binary.image.length → ¬frame.InHeap (imageBase + BitVec.ofNat 64 index)
  guard : frame.guard = binary.guard

variable {binary : Binary} {imageBase : BitVec 64} {place : Place} {instrs : List Instr}

/-- The fetched instruction's bytes are at rip, apart from the stack window and the heap. -/
theorem Body.fetch (body : Body frame binary imageBase place instrs) (rel : Rel frame s m) {i : Instr}
    (fetched : Lanius.Mini.fetch instrs m.pc = some i) :
    CodeAt s.memory s.rip (i.bytes place m.pc) ∧
      (∀ index, index < i.size → ¬Below frame.top frame.window (s.rip + BitVec.ofNat 64 index)) ∧
      m.pc + i.size ≤ codeSize instrs ∧
      (∀ index, index < i.size → ¬frame.InHeap (s.rip + BitVec.ofNat 64 index)) := by
  obtain ⟨pre, post, split, length, bound⟩ := fetch_bytes place fetched
  have apart : ∀ index, index < i.size → ¬Below frame.top frame.window (s.rip + BitVec.ofNat 64 index) := by
    intro index small
    rw [rel.rip, BitVec.add_assoc, ← BitVec.ofNat_add]
    exact body.apart _ (by omega)
  have codeHeap : ∀ index, index < i.size → ¬frame.InHeap (s.rip + BitVec.ofNat 64 index) := by
    intro index small
    rw [rel.rip, BitVec.add_assoc, ← BitVec.ofNat_add]
    exact body.codeHeap _ (by omega)
  refine ⟨?_, apart, bound, codeHeap⟩
  have inEntry : CodeAt frame.entry (frame.base + BitVec.ofNat 64 m.pc) (i.bytes place m.pc) := by
    have whole := body.loaded
    rw [split, Instr.encode_eq] at whole
    have := CodeAt.middle whole
    rwa [length] at this
  intro index small
  have small' : index < i.size := by rw [Instr.bytes_length] at small; exact small
  rw [rel.unchanged _ (apart index small') (codeHeap index small'), rel.rip]
  exact inEntry index small

/-- A run between two offsets of the frame takes a step. -/
theorem Rel.positive (rel : Rel frame s m) {m' : Machine} (moved : m.pc < m'.pc) (small : m'.pc < 2 ^ 64)
    (done : ∃ n s', Steps n s s' ∧ Det n s s' ∧ Rel frame s' m') :
    ∃ n s', 0 < n ∧ Steps n s s' ∧ Det n s s' ∧ Rel frame s' m' := by
  obtain ⟨n, s', steps, det, rel'⟩ := done
  refine ⟨n, s', ?_, steps, det, rel'⟩
  cases steps with
  | refl =>
    have same : frame.base + BitVec.ofNat 64 m.pc = frame.base + BitVec.ofNat 64 m'.pc := rel.rip.symm.trans rel'.rip
    have := congrArg BitVec.toNat same
    simp only [BitVec.toNat_add, BitVec.toNat_ofNat] at this
    omega
  | cons => omega

/-- One abstract step, given the callees' contracts. -/
theorem step_simulates (body : Body frame binary imageBase place instrs) (fits : frame.Fits) {calls : Calls}
    {need : Nat}
    (callContract : ∀ callee vals heap value after, calls callee vals heap value after → ∃ needC,
      needC + frameBytes frame.slots + 16 ≤ need ∧ 8 * vals.length + 16 ≤ frame.window - (frameBytes frame.slots + 16) ∧
        Contract binary imageBase needC (frame.window - (frameBytes frame.slots + 16)) callee vals heap value after)
    (rel : Rel frame s m) {m' : Machine} (step : Step calls instrs m m') :
    (∃ n s', 0 < n ∧ Steps n s s' ∧ Det n s s' ∧ Rel frame s' m') ∨ (frame.window < need ∧ Faults s) := by
  have small := body.small
  have limit : imageLimit = 2 ^ 30 := rfl
  have forward : ∀ {i : Instr} {m' : Machine}, Lanius.Mini.fetch instrs m.pc = some i → m'.pc = m.pc + i.size →
      (∃ n s', Steps n s s' ∧ Det n s s' ∧ Rel frame s' m') →
      ∃ n s', 0 < n ∧ Steps n s s' ∧ Det n s s' ∧ Rel frame s' m' := by
    intro i m' fetched pc done
    obtain ⟨-, -, bound, -⟩ := body.fetch rel fetched
    have positive := i.size_pos
    exact rel.positive (by omega) (by omega) done
  cases step with
  | @straight i _ fetched isStraight =>
    obtain ⟨loaded, -, -⟩ := body.fetch rel fetched
    have fitted := body.fits i (fetch_mem fetched)
    cases i with
    | imm value => exact .inl <| forward fetched rfl <| imm_simulates rel loaded
    | load slot => exact .inl <| forward fetched rfl <| load_simulates rel fitted loaded
    | store slot => exact .inl <| forward fetched rfl <| store_simulates rel fits fitted loaded
    | neg => exact .inl <| forward fetched rfl <| neg_simulates rel loaded
    | op word operation slot => exact .inl <| forward fetched rfl <| op_simulates word operation rel fitted loaded
    | cmp word operation slot => exact .inl <| forward fetched rfl <| cmp_simulates word operation rel fitted loaded
    | fp operation slot => exact .inl <| forward fetched rfl <| fp_simulates operation rel fitted loaded
    | jmp | jz | call | ret | bump | loadAt | storeAt | loadWordAt | storeWordAt | div | sys =>
      simp [Instr.straight] at isStraight
  | @jmp target _ fetched =>
    obtain ⟨loaded, -, bound, -⟩ := body.fetch rel fetched
    have fitted : target ≤ codeSize instrs := body.fits _ (fetch_mem fetched)
    exact .inl <| jmp_simulates rel (by simp only [Instr.size] at bound; omega) (by omega) loaded
  | @jzTaken target _ fetched zero =>
    obtain ⟨loaded, -, bound, -⟩ := body.fetch rel fetched
    have fitted : target ≤ codeSize instrs := body.fits _ (fetch_mem fetched)
    have := jz_simulates rel (by simp only [Instr.size] at bound; omega) (by omega) loaded
    exact .inl (by rwa [if_pos zero] at this)
  | @jzNot target _ fetched nonzero =>
    obtain ⟨loaded, -, bound, -⟩ := body.fetch rel fetched
    have fitted : target ≤ codeSize instrs := body.fits _ (fetch_mem fetched)
    have := jz_simulates rel (by simp only [Instr.size] at bound; omega) (by omega) loaded
    exact .inl (by rwa [if_neg nonzero] at this)
  | @call callee args target count values after _ fetched returns counted =>
    obtain ⟨loaded, apart, bound, codeHeap⟩ := body.fetch rel fetched
    obtain ⟨-, argsCount, argsFit, targetFit, positive⟩ := body.fits _ (fetch_mem fetched)
    obtain ⟨needC, needFits, room, contract⟩ := callContract _ _ _ _ _ returns
    rw [readSlots_length] at room
    have window := fits.window
    rcases call_simulates (P := True) (Q := fun s => frame.window - (frameBytes frame.slots + 16) < needC ∧ Faults s)
      rel fits loaded apart codeHeap body.slots body.entries body.base (by omega)
      (by have := body.entrySmall callee; omega) argsFit argsCount targetFit positive body.image body.imageApart
      body.imageHeap body.guard (by omega) room
      (fun s a b c d e f g h => (contract s a b c d e f g h).imp (fun r => ⟨trivial, r⟩) id) counted with
      ⟨-, finished⟩ | ⟨k, s2, -, det, short, faults⟩
    · exact .inl (forward fetched rfl finished)
    · exact .inr ⟨by omega, det.faults faults⟩
  | bump fetched room =>
    obtain ⟨loaded, -⟩ := body.fetch rel fetched
    exact .inl <| forward fetched rfl <| bump_simulates rel fits (body.fits _ (fetch_mem fetched)) loaded room
  | loadAt fetched inside =>
    obtain ⟨loaded, -⟩ := body.fetch rel fetched
    exact .inl <| forward fetched rfl <| loadAt_simulates rel loaded (rel.top ▸ inside)
  | storeAt fetched inside =>
    obtain ⟨loaded, -⟩ := body.fetch rel fetched
    exact .inl <| forward fetched rfl <|
      storeAt_simulates rel fits (body.fits _ (fetch_mem fetched)) loaded (rel.top ▸ inside)
  | loadWordAt fetched inside =>
    obtain ⟨loaded, -⟩ := body.fetch rel fetched
    exact .inl <| forward fetched rfl <| loadWordAt_simulates rel loaded (rel.top ▸ inside)
  | storeWordAt fetched inside =>
    obtain ⟨loaded, -⟩ := body.fetch rel fetched
    exact .inl <| forward fetched rfl <|
      storeWordAt_simulates rel fits (body.fits _ (fetch_mem fetched)) loaded (rel.top ▸ inside)
  | div fetched defined =>
    obtain ⟨loaded, -⟩ := body.fetch rel fetched
    exact .inl <| forward fetched rfl <| div_simulates _ _ rel (body.fits _ (fetch_mem fetched)) loaded defined
  | sys fetched ran =>
    obtain ⟨loaded, -, -, codeHeap⟩ := body.fetch rel fetched
    exact .inl <| forward fetched rfl <| sys_simulates rel fits (body.fits _ (fetch_mem fetched)) loaded
      codeHeap ran

/-- The bytes of a body simulate its abstract run to `ret`. -/
theorem body_simulates (body : Body frame binary imageBase place instrs) (fits : frame.Fits) {calls : Calls}
    {need : Nat}
    (callContract : ∀ callee vals heap value after, calls callee vals heap value after → ∃ needC,
      needC + frameBytes frame.slots + 16 ≤ need ∧ 8 * vals.length + 16 ≤ frame.window - (frameBytes frame.slots + 16) ∧
        Contract binary imageBase needC (frame.window - (frameBytes frame.slots + 16)) callee vals heap value after)
    {m m' : Machine} {sources : List Nat} (run : Star calls instrs m m')
    (atRet : fetch instrs m'.pc = some (.ret sources)) :
    ∀ s, Rel frame s m → (∃ n s', Steps n s s' ∧ Det n s s' ∧ frame.Exit s' (readSlots m'.slots sources) m'.heap) ∨
      (frame.window < need ∧ Faults s) := by
  induction run with
  | refl m =>
    intro s rel
    obtain ⟨loaded, apart, -, codeHeap⟩ := body.fetch rel atRet
    exact .inl (ret_simulates rel fits loaded apart codeHeap (body.fits _ (fetch_mem atRet)))
  | step head _ ih =>
    intro s rel
    rcases step_simulates body fits callContract rel head with ⟨n, middle, -, steps, det, middleRel⟩ | bad
    · rcases ih atRet middle middleRel with ⟨n', s', rest, det', exit⟩ | ⟨short, faults⟩
      · exact .inl ⟨_, s', steps.trans rest, det.trans det', exit⟩
      · exact .inr ⟨short, det.faults faults⟩
    · exact .inr bad

end Lanius.Mini
