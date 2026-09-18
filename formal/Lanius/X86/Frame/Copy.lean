import Lanius.X86.Frame.Function
import Lanius.X86.Storage.Value

namespace Lanius.X86.Frame

/-- A value block starts at its lowest-address slot and extends upwards.
This is the allocator's `top - 1` base plus ascending field-word offsets. -/
theorem Layout.block_saved_disjoint (layout : Layout) (slot : Fin layout.slots) (count : Nat)
    (room : count ≤ slot.val + 1) (headerBound : layout.base + 16 ≤ 2^64)
    (header : Fin 16) (index : Nat) (indexBound : index < count) (lane : Fin 8) :
    BitVec.ofNat 64 layout.base + BitVec.ofNat 64 header.val ≠
      Machine.Copy.address (layout.address slot) index + BitVec.ofNat 64 lane.val := by
  have allocated := layout.belowBase
  have slotsRoom := (bytes_room layout.slots).1
  have slotBound := slot.isLt
  have headBound := header.isLt
  have laneBound := lane.isLt
  have endBound : layout.offset slot + index * 8 + lane.val < layout.base := by
    simp only [Layout.offset]
    omega
  intro equal
  have same := congrArg BitVec.toNat equal
  simp only [Machine.Copy.address, Layout.address, ← BitVec.ofNat_add, BitVec.toNat_ofNat] at same
  rw [Nat.mod_eq_of_lt (by omega), Nat.mod_eq_of_lt (by omega)] at same
  omega

/-- The actual decoded aggregate-copy sequence preserves the whole-function
saved-state invariant whenever its destination is a private allocated block.
No separate caller-state premise is needed for each copied field. -/
theorem BodyFrame.copy {entry started before after : Machine.State}
    (frame : BodyFrame entry started before) (copied : Machine.Copy.Result before after 0 count)
    (layout : Layout) (slot : Fin layout.slots) (room : count ≤ slot.val + 1)
    (headerBound : layout.base + 16 ≤ 2^64)
    (base : started.registers 5 = BitVec.ofNat 64 layout.base)
    (destination : before.registers 11 = layout.address slot) :
    BodyFrame entry started after := by
  have header (offset : Nat) (bounded : offset + 8 ≤ 16) :
      Machine.read64 after.memory (BitVec.ofNat 64 layout.base + BitVec.ofNat 64 offset) =
        Machine.read64 before.memory (BitVec.ofNat 64 layout.base + BitVec.ofNat 64 offset) := by
    apply Machine.read64_congr
    intro lane
    apply copied.frame
    rw [destination]
    intro index indexBound byte
    have laneBound := lane.isLt
    simpa [BitVec.ofNat_add, BitVec.add_assoc] using layout.block_saved_disjoint slot count room headerBound
      ⟨offset + lane.val, by omega⟩ index indexBound byte
  refine ⟨(copied.registers 5 (by decide)).trans frame.framePointer, ?_, ?_, ?_, ?_⟩
  · rw [base]
    have same : Machine.read64 after.memory (BitVec.ofNat 64 layout.base) =
        Machine.read64 before.memory (BitVec.ofNat 64 layout.base) := by simpa using header 0 (by decide)
    rw [same, ← base]
    exact frame.savedPointer
  · have same : Machine.read64 after.memory (BitVec.ofNat 64 layout.base + 8) =
        Machine.read64 before.memory (BitVec.ofNat 64 layout.base + 8) := by simpa using header 8 (by decide)
    rw [base, same, ← base]
    exact frame.returnAddress
  · intro register saved
    rw [copied.registers]
    · exact frame.registers register saved
    · rcases saved with rfl | rfl | rfl | rfl | rfl <;> decide
  · rw [copied.flags]
    exact frame.direction

end Lanius.X86.Frame
