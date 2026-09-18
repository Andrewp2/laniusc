import Lanius.X86.Lower.Expression.Indexed.Prepare
import Lanius.X86.Frame.Word

namespace Lanius.X86.Lower.Expression.Indexed

/-- Executing the exact saved-operand bytes stores
the original RAX descriptor, preserves all older live stack slots and the
caller frame, and leaves the following recursive code loaded. The eventual
frame layout must contain the newly allocated slot; its total size can grow
during later recursive compilation. -/
theorem captures (native : Machine.State) (layout : Frame.Layout) (slot : Fin layout.slots) (position : slot.val = top)
    (bounded : layout.slots ≤ 1048576) (base : native.registers 5 = BitVec.ofNat 64 layout.base)
    (frame : Frame.BodyFrame entry started native) (startedBase : started.registers 5 = BitVec.ofNat 64 layout.base)
    (headerBound : layout.base + 16 ≤ 2 ^ 64)
    (loaded : Machine.CodeAt native.memory native.rip
      (saveBytes top ++ suffix))
    (disjoint : ∀ index, index < (saveBytes top).length + suffix.length → ∀ lane : Fin 8,
      native.rip + BitVec.ofNat 64 index ≠ layout.address slot + BitVec.ofNat 64 lane.val) :
    ∃ captured, Machine.Step native captured ∧
      Machine.read64 captured.memory (layout.address slot) = native.registers 0 ∧
      (∀ live : Fin layout.slots, live.val < top → ∀ lane : Fin 8,
        captured.memory (layout.address live + BitVec.ofNat 64 lane.val) =
          native.memory (layout.address live + BitVec.ofNat 64 lane.val)) ∧
      Frame.BodyFrame entry started captured ∧
      captured.registers = native.registers ∧ captured.flags = native.flags ∧
      captured.rip = native.rip + BitVec.ofNat 64 (saveBytes top).length ∧
      captured.memory = Machine.write64 native.memory (layout.address slot) (native.registers 0) ∧
      Machine.CodeAt captured.memory captured.rip suffix := by
  let captured := native.store64 0 5 (BitVec.ofInt 32 (Frame.displacement slot.val)) (saveBytes top).length
  have memory : captured.memory = Machine.write64 native.memory (layout.address slot) (native.registers 0) := by
    simp only [captured, Machine.State.store64, layout.operand slot bounded base]
  have decoded : Machine.decode (saveBytes top) =
      some (.store64 0 5 (BitVec.ofInt 32 (Frame.displacement slot.val)), (saveBytes top).length) := by
    rw [position]
    simpa only [saveBytes, Frame.Slot.bytes, Source.Slot.Kind.width, Source.Slot.Kind.load,
      Machine.memoryInstruction, Bool.false_eq_true, ↓reduceIte, List.append_nil]
      using Machine.memory_decodes .w64 false 0 5 (Frame.displacement top) []
  refine ⟨captured, .decoded _ loaded.prefix _ _ decoded rfl, ?_, ?_,
    frame.store64 layout slot 0 _ bounded headerBound startedBase, rfl, rfl, rfl, memory, ?_⟩
  · rw [memory, Machine.read64_write64]
  · intro live older lane
    rw [memory]
    apply Machine.write64_frame
    apply layout.word_disjoint live slot
    intro same
    have : live.val = top := (congrArg Fin.val same).trans position
    omega
  · have preserved := loaded.write64 (native.registers 0) (by simpa only [List.length_append] using disjoint)
    change Machine.CodeAt captured.memory (native.rip + BitVec.ofNat 64 (saveBytes top).length) suffix
    rw [memory]
    exact preserved.suffix

end Lanius.X86.Lower.Expression.Indexed
