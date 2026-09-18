import Lanius.X86.Lower.Expression.Raw.Prepare
import Lanius.X86.Lower.Expression.Indexed.Capture

namespace Lanius.X86.Lower.Expression.Raw

/-- The actual save-word bytes derived by preparation capture the raw pointer
before the length child runs. The saved pointer is a memory fact, not a claim
that recursive length evaluation preserves RAX. Earlier live slots, caller
state, and the following child code are retained under explicit separation. -/
theorem captures (native : Machine.State) (top : Nat) (layout : Frame.Layout)
    (slot : Fin layout.slots) (position : slot.val = top + 1)
    (bounded : layout.slots ≤ 1048576) (base : native.registers 5 = BitVec.ofNat 64 layout.base)
    (frame : Frame.BodyFrame entry started native) (startedBase : started.registers 5 = BitVec.ofNat 64 layout.base)
    (headerBound : layout.base + 16 ≤ 2^64)
    (loaded : Machine.CodeAt native.memory native.rip (saveBytes top ++ suffix))
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
  obtain ⟨captured, step, pointer, old, caller, registers, flags, rip, memory, code⟩ :=
    Indexed.captures native layout slot position bounded base frame startedBase headerBound loaded disjoint
  exact ⟨captured, step, pointer, fun live inside => old live (by omega), caller,
    registers, flags, rip, memory, code⟩

end Lanius.X86.Lower.Expression.Raw
