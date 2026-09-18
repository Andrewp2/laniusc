import Lanius.X86.Frame.Function

namespace Lanius.X86.Frame

/-- Full-width slots hold saved descriptors and pointer/usize operands.
All eight lanes, not just the scalar low half, must remain disjoint. -/
theorem Layout.word_lane (layout : Layout) (slot : Fin layout.slots) (lane : Fin 8) :
    (layout.address slot + BitVec.ofNat 64 lane.val).toNat = layout.offset slot + lane.val := by
  have bounds := layout.bounds slot
  have representable := layout.addressBound
  have index := lane.isLt
  simp only [Layout.address, ← BitVec.ofNat_add, BitVec.toNat_ofNat]
  apply Nat.mod_eq_of_lt
  omega

theorem Layout.word_disjoint (layout : Layout) (left right : Fin layout.slots) (different : left ≠ right)
    (i j : Fin 8) : layout.address left + BitVec.ofNat 64 i.val ≠ layout.address right + BitVec.ofNat 64 j.val := by
  intro equal
  have same := congrArg BitVec.toNat equal
  rw [layout.word_lane, layout.word_lane] at same
  have separate := layout.separate left right different
  have a := i.isLt
  have b := j.isLt
  omega

theorem Layout.saved_word_disjoint (layout : Layout) (slot : Fin layout.slots)
    (headerBound : layout.base + 16 ≤ 2 ^ 64) (header : Fin 16) (lane : Fin 8) :
    BitVec.ofNat 64 layout.base + BitVec.ofNat 64 header.val ≠ layout.address slot + BitVec.ofNat 64 lane.val := by
  intro equal
  have same := congrArg BitVec.toNat equal
  rw [layout.word_lane] at same
  rw [← BitVec.ofNat_add, BitVec.toNat_ofNat, Nat.mod_eq_of_lt (by have := header.isLt; omega)] at same
  have slotBound := layout.bounds slot
  have laneBound := lane.isLt
  omega

theorem BodyFrame.write64 {entry started before : Machine.State} (frame : BodyFrame entry started before)
    (source base : Machine.Register) (displacement : BitVec 32) (size : Nat)
    (separate : ∀ header : Fin 16, ∀ lane : Fin 8,
      started.registers 5 + BitVec.ofNat 64 header.val ≠
        before.registers base + displacement.signExtend 64 + BitVec.ofNat 64 lane.val) :
    BodyFrame entry started (before.store64 source base displacement size) := by
  refine ⟨frame.framePointer, ?_, ?_, frame.registers, frame.direction⟩
  · change Machine.read64 (Machine.write64 _ _ _) _ = _
    rw [Machine.read64_frame]
    · exact frame.savedPointer
    · intro i j
      exact separate ⟨i.val, by have := i.isLt; omega⟩ j
  · change Machine.read64 (Machine.write64 _ _ _) _ = _
    rw [Machine.read64_frame]
    · exact frame.returnAddress
    · intro i j
      have index := i.isLt
      simpa [BitVec.ofNat_add, BitVec.add_assoc] using separate ⟨8 + i.val, by omega⟩ j

theorem BodyFrame.store64 {entry started before : Machine.State} (frame : BodyFrame entry started before)
    (layout : Layout) (slot : Fin layout.slots) (source : Machine.Register) (size : Nat)
    (bounded : layout.slots ≤ 1048576) (headerBound : layout.base + 16 ≤ 2 ^ 64)
    (base : started.registers 5 = BitVec.ofNat 64 layout.base) :
    BodyFrame entry started (before.store64 source 5 (BitVec.ofInt 32 (displacement slot.val)) size) := by
  apply frame.write64
  intro header lane
  rw [layout.operand slot bounded (frame.framePointer.trans base), base]
  exact layout.saved_word_disjoint slot headerBound header lane

end Lanius.X86.Frame
