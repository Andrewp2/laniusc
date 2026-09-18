import Lanius.X86.Frame.Protocol

namespace Lanius.X86.Frame

/-- The non-RBP callee-saved integer registers in System V AMD64. RBP's
original value is held in memory until the epilogue restores it. -/
def savedRegister (register : Machine.Register) : Prop :=
  register = 3 ∨ register = 12 ∨ register = 13 ∨ register = 14 ∨ register = 15

/-- The body compiler must preserve the caller's saved state. This is the
explicit remaining interface to the recursive body simulation, not an axiom
or a claim that the current visitor already establishes it. -/
structure BodyFrame (entry started completed : Machine.State) : Prop where
  framePointer : completed.registers 5 = started.registers 5
  savedPointer : Machine.read64 completed.memory (started.registers 5) = entry.registers 5
  returnAddress : Machine.read64 completed.memory (started.registers 5 + 8) =
    Machine.read64 entry.memory (entry.registers 4)
  registers : ∀ register, savedRegister register → completed.registers register = entry.registers register
  direction : completed.flags.getLsbD 10 = started.flags.getLsbD 10

theorem setup_frame (entry : Machine.State) (amount : Nat) (bounded : amount < 4294967296) :
    BodyFrame entry (setup entry amount) (setup entry amount) := by
  have fields := setup_fields entry amount bounded
  refine ⟨rfl, ?_, ?_, ?_, rfl⟩
  · rw [fields.1, fields.2.2.2.2, Machine.read64_write64]
  · rw [fields.1, fields.2.2.2.2]
    simp only [BitVec.sub_add_cancel]
    apply Machine.read64_frame
    intro i j
    have ib := i.isLt
    have jb := j.isLt
    have separate := Machine.offset_ne (entry.registers 4 - 8) (8 + i.val) j.val (by omega) (by omega) (by omega)
    simpa [BitVec.ofNat_add, ← BitVec.add_assoc, BitVec.sub_add_cancel] using separate
  · intro register saved
    apply fields.2.2.2.1
    all_goals rcases saved with rfl | rfl | rfl | rfl | rfl <;> decide

/-- Both private frame stores and heap-element stores preserve caller state
when their four-byte destination is separate from the saved frame header. -/
theorem BodyFrame.write32 {entry started before : Machine.State} (frame : BodyFrame entry started before)
    (source base : Machine.Register) (displacement : BitVec 32) (size : Nat)
    (separate : ∀ header : Fin 16, ∀ lane : Fin 4,
      started.registers 5 + BitVec.ofNat 64 header.val ≠
        before.registers base + displacement.signExtend 64 + BitVec.ofNat 64 lane.val) :
    BodyFrame entry started (before.store32 source base displacement size) := by
  refine ⟨frame.framePointer, ?_, ?_, frame.registers, frame.direction⟩
  · change Machine.read64 (Machine.write32 _ _ _) _ = _
    have untouched : Machine.read64
        (Machine.write32 before.memory (before.registers base + displacement.signExtend 64)
          ((before.registers source).setWidth 32))
        (started.registers 5) = Machine.read64 before.memory (started.registers 5) := by
      apply Machine.read64_write32_frame
      intro i j
      exact separate ⟨i.val, by have := i.isLt; omega⟩ j
    exact untouched.trans frame.savedPointer
  · change Machine.read64 (Machine.write32 _ _ _) _ = _
    have untouched : Machine.read64
        (Machine.write32 before.memory (before.registers base + displacement.signExtend 64)
          ((before.registers source).setWidth 32))
        (started.registers 5 + 8) = Machine.read64 before.memory (started.registers 5 + 8) := by
      apply Machine.read64_write32_frame
      intro i j
      have index := i.isLt
      simpa [BitVec.ofNat_add, BitVec.add_assoc] using
        separate ⟨8 + i.val, by omega⟩ j
    exact untouched.trans frame.returnAddress

/-- The private slot stores used for locals and expression temporaries retain
the saved caller state required by the whole-function composition theorem. -/
theorem BodyFrame.store {entry started before : Machine.State} (frame : BodyFrame entry started before)
    (layout : Layout) (slot : Fin layout.slots) (source : Machine.Register) (size : Nat)
    (bounded : layout.slots ≤ 1048576) (headerBound : layout.base + 16 ≤ 2 ^ 64)
    (base : started.registers 5 = BitVec.ofNat 64 layout.base) :
    BodyFrame entry started (before.store32 source 5 (BitVec.ofInt 32 (displacement slot.val)) size) := by
  apply frame.write32
  intro header lane
  rw [layout.operand slot bounded (frame.framePointer.trans base), base]
  exact layout.saved_disjoint slot headerBound header lane

/-- Bind the generic byte protocol to the allocator's actual frame layout.
The entry RSP is eight bytes above the saved-RBP address. -/
theorem Layout.setup (layout : Layout) (entry : Machine.State) (bounded : layout.slots ≤ 1048576)
    (stack : entry.registers 4 = BitVec.ofNat 64 (layout.base + 8)) (aligned : layout.base % 16 = 0) :
    (Frame.setup entry (bytes layout.slots)).registers 5 = BitVec.ofNat 64 layout.base ∧
    (Frame.setup entry (bytes layout.slots)).registers 4 = BitVec.ofNat 64 (layout.base - bytes layout.slots) ∧
    ((Frame.setup entry (bytes layout.slots)).registers 4).toNat % 16 = 0 := by
  have room := bytes_room layout.slots
  have fields := setup_fields entry (bytes layout.slots) (by omega)
  have frame : entry.registers 4 - 8 = BitVec.ofNat 64 layout.base := by
    rw [stack, BitVec.ofNat_add]
    simp [BitVec.add_sub_cancel]
  have subtraction : BitVec.ofNat 64 layout.base - BitVec.ofNat 64 (bytes layout.slots) =
      BitVec.ofNat 64 (layout.base - bytes layout.slots) := by
    calc
      _ = BitVec.ofInt 64 ((layout.base : Int) - (bytes layout.slots : Int)) := by
        simp only [Int.sub_eq_add_neg, BitVec.ofInt_add, BitVec.ofInt_neg, BitVec.ofInt_natCast, BitVec.sub_eq_add_neg]
      _ = _ := by rw [← Int.natCast_sub layout.belowBase, BitVec.ofInt_natCast]
  have rsp : (Frame.setup entry (bytes layout.slots)).registers 4 = BitVec.ofNat 64 (layout.base - bytes layout.slots) := by
    rw [fields.2.1, frame, subtraction]
  refine ⟨fields.1.trans frame, rsp, ?_⟩
  have addressRange : layout.base - bytes layout.slots < 2 ^ 64 :=
    Nat.lt_of_le_of_lt (Nat.sub_le _ _) layout.addressBound
  rw [rsp, BitVec.toNat_ofNat, Nat.mod_eq_of_lt addressRange]
  have allocation := layout.belowBase
  have multiple := bytes_aligned layout.slots
  omega

/-- Compose the actual prologue, a proved body execution, and the actual
epilogue. The body premise remains explicit until recursive lowering is
proved. RAX is the body's result; RSP/RBP, all callee-saved registers, the
return address, and the ABI direction flag survive the whole call. -/
theorem function_returns (entry completed : Machine.State) (amount count : Nat) (body : List UInt8)
    (bounded : amount < 4294967296)
    (loaded : Machine.CodeAt entry.memory entry.rip (prologue amount ++ body))
    (disjoint : ∀ index, index < (prologue amount ++ body).length → ∀ lane : Fin 8,
      entry.rip + BitVec.ofNat 64 index ≠ entry.registers 4 - 8 + BitVec.ofNat 64 lane.val)
    (execution : Machine.Steps count (setup entry amount) completed)
    (bodyFrame : BodyFrame entry (setup entry amount) completed)
    (returnCode : Machine.CodeAt completed.memory completed.rip epilogue) :
    Machine.Steps (count + 7) entry (teardown completed) ∧
    (teardown completed).registers 0 = completed.registers 0 ∧
    (teardown completed).registers 4 = entry.registers 4 + 8 ∧
    (teardown completed).registers 5 = entry.registers 5 ∧
    (teardown completed).rip = Machine.read64 entry.memory (entry.registers 4) ∧
    (∀ register, savedRegister register → (teardown completed).registers register = entry.registers register) ∧
    (teardown completed).flags.getLsbD 10 = entry.flags.getLsbD 10 := by
  have entered := prologue_steps entry amount body loaded disjoint
  have returned := epilogue_steps completed returnCode
  have fields := teardown_fields completed
  have starting := setup_fields entry amount bounded
  refine ⟨?_, fields.2.2.2.1 0 (by decide) (by decide), ?_, ?_, ?_, ?_, ?_⟩
  · simpa [Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using (entered.1.trans execution).trans returned
  · rw [fields.2.1, bodyFrame.framePointer, starting.1]
    simp [BitVec.sub_eq_add_neg, BitVec.add_assoc]
  · rw [fields.1, bodyFrame.framePointer, bodyFrame.savedPointer]
  · rw [fields.2.2.1, bodyFrame.framePointer, bodyFrame.returnAddress]
  · intro register saved
    rw [fields.2.2.2.1]
    · exact bodyFrame.registers register saved
    all_goals rcases saved with rfl | rfl | rfl | rfl | rfl <;> decide
  · rw [fields.2.2.2.2.2, bodyFrame.direction, setup_direction]

end Lanius.X86.Frame
