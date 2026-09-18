import Lanius.X86.Frame.Layout
import Lanius.X86.Machine.Encoding

namespace Lanius.X86.Frame

def slotBytes (load : Bool) (register : Machine.Register) (slot : Nat) : List UInt8 :=
  Machine.memoryBytes .w32 load register 5 (displacement slot)

theorem displacement_signed (slot : Nat) (bounded : slot ≤ 1048576) :
    (BitVec.ofInt 32 (displacement slot)).toInt = displacement slot := by
  apply BitVec.toInt_ofInt_eq_self (by decide)
  all_goals simp only [displacement, Int.natCast_add, Int.natCast_one]; omega

theorem Layout.operand (layout : Layout) (slot : Fin layout.slots) {before : Machine.State} (bounded : layout.slots ≤ 1048576)
    (base : before.registers 5 = BitVec.ofNat 64 layout.base) :
    before.registers 5 + (BitVec.ofInt 32 (Frame.displacement slot.val)).signExtend 64 = layout.address slot := by
  rw [base, BitVec.signExtend, displacement_signed slot.val (by have := slot.isLt; omega)]
  exact (layout.displacement slot).symm

theorem slot_decodes (load : Bool) (register : Machine.Register) (slot : Nat) :
    Machine.decode (slotBytes load register slot) =
      some (Machine.memoryInstruction .w32 load register 5 (BitVec.ofInt 32 (displacement slot)),
        (slotBytes load register slot).length) := by
  simpa only [slotBytes, List.append_nil] using Machine.memory_decodes .w32 load register 5 (displacement slot) []

/-- A decoded store updates exactly one represented Core local/temporary;
registers and flags are unchanged. Code/data separation is not silently
assumed: preserving subsequent instructions is a separate byte-window fact. -/
theorem store_correct (layout : Layout) (slot : Fin layout.slots) (source : Machine.Register)
    (before : Machine.State) {values : Fin layout.slots → BitVec 32} (bounded : layout.slots ≤ 1048576)
    (base : before.registers 5 = BitVec.ofNat 64 layout.base)
    (represented : Represents layout values before.memory)
    (loaded : Machine.CodeAt before.memory before.rip (slotBytes false source slot.val)) :
    let after := before.store32 source 5 (BitVec.ofInt 32 (displacement slot.val)) (slotBytes false source slot.val).length
    Machine.Step before after ∧
      Represents layout (fun candidate => if candidate = slot then (before.registers source).setWidth 32 else values candidate) after.memory ∧
      after.registers = before.registers ∧ after.flags = before.flags ∧
      after.memory = Machine.write32 before.memory (layout.address slot) ((before.registers source).setWidth 32) := by
  dsimp only
  refine ⟨.decoded _ loaded _ _ (slot_decodes false source slot.val) rfl, ?_, rfl, rfl, ?_⟩
  · simp only [Machine.State.store32, layout.operand slot bounded base]
    exact represented.store slot _
  · simp only [Machine.State.store32, layout.operand slot bounded base]

/-- A decoded frame load retrieves the represented value and zeroes the
upper half of its destination register, preserving every other register,
memory, and flags. -/
theorem load_correct (layout : Layout) (slot : Fin layout.slots) (destination : Machine.Register)
    (before : Machine.State) {values : Fin layout.slots → BitVec 32} (bounded : layout.slots ≤ 1048576)
    (base : before.registers 5 = BitVec.ofNat 64 layout.base)
    (represented : Represents layout values before.memory)
    (loaded : Machine.CodeAt before.memory before.rip (slotBytes true destination slot.val)) :
    let after := before.load32 destination 5 (BitVec.ofInt 32 (displacement slot.val)) (slotBytes true destination slot.val).length
    Machine.Step before after ∧ after.registers destination = (values slot).setWidth 64 ∧
      (∀ register, register ≠ destination → after.registers register = before.registers register) ∧
      after.memory = before.memory ∧ after.flags = before.flags := by
  dsimp only
  refine ⟨.decoded _ loaded _ _ (slot_decodes true destination slot.val) rfl, ?_, ?_, rfl, rfl⟩
  · simp only [Machine.State.load32, Machine.State.immediate32, ↓reduceIte, layout.operand slot bounded base, represented slot]
  · intro register different
    simp only [Machine.State.load32, Machine.State.immediate32, if_neg different]

/-- The spill/reload pair used by recursive expression lowering is a real
two-instruction execution over loaded bytes, not just a memory equation.
The stored value survives and all other represented slots are retained. -/
theorem spill_reload (layout : Layout) (slot : Fin layout.slots) (source destination : Machine.Register)
    (before : Machine.State) {values : Fin layout.slots → BitVec 32} (bounded : layout.slots ≤ 1048576)
    (base : before.registers 5 = BitVec.ofNat 64 layout.base)
    (represented : Represents layout values before.memory)
    (loaded : Machine.CodeAt before.memory before.rip (slotBytes false source slot.val ++ slotBytes true destination slot.val))
    (disjoint : ∀ index, index < (slotBytes false source slot.val ++ slotBytes true destination slot.val).length →
      ∀ lane : Fin 4, before.rip + BitVec.ofNat 64 index ≠ layout.address slot + BitVec.ofNat 64 lane.val) :
    ∃ middle after, Machine.Step before middle ∧ Machine.Step middle after ∧
      after.registers destination = ((before.registers source).setWidth 32).setWidth 64 ∧
      Represents layout (fun candidate => if candidate = slot then (before.registers source).setWidth 32 else values candidate) after.memory ∧
      (∀ register, register ≠ destination → after.registers register = before.registers register) ∧
      after.flags = before.flags := by
  let middle := before.store32 source 5 (BitVec.ofInt 32 (displacement slot.val)) (slotBytes false source slot.val).length
  let after := middle.load32 destination 5 (BitVec.ofInt 32 (displacement slot.val)) (slotBytes true destination slot.val).length
  have stored := store_correct layout slot source before bounded base represented loaded.prefix
  have preserved := loaded.write32 ((before.registers source).setWidth 32) disjoint
  have next : Machine.CodeAt middle.memory middle.rip (slotBytes true destination slot.val) := by
    change Machine.CodeAt middle.memory (before.rip + BitVec.ofNat 64 (slotBytes false source slot.val).length) _
    rw [stored.2.2.2.2]
    exact preserved.suffix
  have restored := load_correct layout slot destination middle bounded base stored.2.1 next
  refine ⟨middle, after, stored.1, restored.1, ?_, ?_, restored.2.2.1, restored.2.2.2.2⟩
  · simpa only [↓reduceIte] using restored.2.1
  · exact stored.2.1

end Lanius.X86.Frame
