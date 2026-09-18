import Lanius.X86.Storage.Slice.Descriptor

namespace Lanius.X86.Machine.Slice.Raw

open Lanius.Semantics

variable {layout : Frame.Layout} {count : Nat} {data : Address}

def moveBytes : List UInt8 := [137, 192]
def storeBytes (slot : Nat) : List UInt8 :=
  memoryBytes .w64 false 0 5 (Frame.displacement (slot - 1))
def addressBytes (slot : Nat) : List UInt8 :=
  [72, 141, 133] ++ i32Bytes (Frame.displacement slot)
def continuationBytes (slot : Nat) : List UInt8 :=
  moveBytes ++ storeBytes slot ++ addressBytes slot

theorem address_decodes (slot : Nat) (tail : List UInt8) :
    decode (addressBytes slot ++ tail) =
      some (.address64 0 5 none 0 (BitVec.ofInt 32 (Frame.displacement slot)), 7) := by
  simp [addressBytes, decode, decodeOpcode, addressForm, X86.Register.Rex.decode?,
    Control.displacement?_i32Bytes, extendRegister, List.append_assoc]

def lengthSlot (slot : Fin layout.slots) : Fin layout.slots := ⟨slot.val - 1, by omega⟩

theorem previous_address (layout : Frame.Layout) (slot : Fin layout.slots) (positive : 0 < slot.val) :
    layout.address (lengthSlot slot) = layout.address slot + 8 := by
  rw [layout.displacement, layout.displacement]
  have displacement : Frame.displacement (slot.val - 1) = Frame.displacement slot.val + 8 := by
    simp only [Frame.displacement, Int.natCast_add, Int.natCast_sub (by omega : 1 ≤ slot.val)]
    omega
  simp [lengthSlot, displacement, BitVec.ofInt_add, BitVec.add_assoc]

theorem descriptor_bound (layout : Frame.Layout) (slot : Fin layout.slots) (positive : 0 < slot.val) :
    (layout.address slot).toNat + 16 ≤ 2^64 := by
  have room := (Frame.bytes_room layout.slots).1
  have allocated := layout.belowBase
  have index := slot.isLt
  have endBound : layout.offset slot + 16 ≤ layout.base := by
    simp only [Frame.Layout.offset]
    omega
  have representable := layout.addressBound
  simp only [Frame.Layout.address, BitVec.toNat_ofNat,
    Nat.mod_eq_of_lt (by omega : layout.offset slot < 2^64)]
  omega

def continuation (before : State) (slot : Nat) : State :=
  let normalized := before.move32 0 0 moveBytes.length
  let stored := normalized.store64 0 5 (BitVec.ofInt 32 (Frame.displacement (slot - 1)))
    (storeBytes slot).length
  stored.address64 0 5 none 0 (BitVec.ofInt 32 (Frame.displacement slot)) 7

/-- The sole memory write is the length word; the previously saved backing
pointer is not written a second time. MOV EAX,EAX first clears any high garbage. -/
theorem continuation_fields (before : State) (layout : Frame.Layout) (slot : Fin layout.slots)
    (positive : 0 < slot.val) (bounded : layout.slots ≤ 1048576)
    (frame : before.registers 5 = BitVec.ofNat 64 layout.base)
    (value : ((before.registers 0).setWidth 32).toNat = count) :
    let after := continuation before slot.val
    after.memory = write64 before.memory (layout.address slot + 8) (BitVec.ofNat 64 count) ∧
    after.registers 0 = layout.address slot ∧
    (∀ register, register ≠ 0 → after.registers register = before.registers register) ∧
    after.flags = before.flags ∧
    after.rip = before.rip + BitVec.ofNat 64 (continuationBytes slot.val).length := by
  have widened : ((before.registers 0).setWidth 32).setWidth 64 = BitVec.ofNat 64 count := by
    apply BitVec.eq_of_toNat_eq
    simp only [BitVec.toNat_setWidth, BitVec.toNat_ofNat, value]
  have storeOperand := layout.operand (lengthSlot slot) bounded frame
  rw [previous_address layout slot positive] at storeOperand
  have addressOperand := layout.operand slot bounded frame
  simp [continuation, State.move32, State.store64, State.address64, widened,
    show before.registers 5 + (BitVec.ofInt 32 (Frame.displacement (slot.val - 1))).signExtend 64 =
      layout.address slot + 8 from storeOperand,
    addressOperand, continuationBytes, addressBytes, i32Bytes, BitVec.ofNat_add, BitVec.add_assoc]
  intro register different
  simp [different]

theorem continuation_steps (before : State) (slot : Nat) (tail : List UInt8)
    (loaded : CodeAt before.memory before.rip (continuationBytes slot ++ tail))
    (separate : ∀ index, index < (continuationBytes slot ++ tail).length → ∀ lane : Fin 8,
      before.rip + BitVec.ofNat 64 index ≠
        before.registers 5 + (BitVec.ofInt 32 (Frame.displacement (slot - 1))).signExtend 64 +
          BitVec.ofNat 64 lane.val) :
    Steps 3 before (continuation before slot) ∧
    CodeAt (continuation before slot).memory (continuation before slot).rip tail := by
  let normalized := before.move32 0 0 moveBytes.length
  let stored := normalized.store64 0 5 (BitVec.ofInt 32 (Frame.displacement (slot - 1)))
    (storeBytes slot).length
  have code : CodeAt before.memory before.rip
      (moveBytes ++ (storeBytes slot ++ (addressBytes slot ++ tail))) := by
    simpa only [continuationBytes, List.append_assoc] using loaded
  have moveStep : Step before normalized := .decoded _ code.prefix _ _ (by rfl) rfl
  have storeCode : CodeAt normalized.memory normalized.rip (storeBytes slot ++ (addressBytes slot ++ tail)) :=
    code.suffix
  have storeStep : Step normalized stored := .decoded _ storeCode.prefix _ _
    (by simpa only [storeBytes, memoryInstruction, Bool.false_eq_true, ↓reduceIte, List.append_nil]
      using memory_decodes .w64 false 0 5 (Frame.displacement (slot - 1)) []) rfl
  have allCode : CodeAt stored.memory before.rip (continuationBytes slot ++ tail) := by
    change CodeAt (write64 before.memory _ _) _ _
    apply loaded.write64
    exact separate
  have addressCode : CodeAt stored.memory stored.rip (addressBytes slot ++ tail) := by
    change CodeAt stored.memory (before.rip + BitVec.ofNat 64 moveBytes.length +
      BitVec.ofNat 64 (storeBytes slot).length) _
    have code' : CodeAt stored.memory before.rip
        ((moveBytes ++ storeBytes slot) ++ (addressBytes slot ++ tail)) := by
      simpa only [continuationBytes, List.append_assoc] using allCode
    simpa only [List.length_append, BitVec.ofNat_add, BitVec.add_assoc] using code'.suffix
  have addressStep : Step stored (continuation before slot) := .decoded _ addressCode.prefix _ _
    (by simpa using address_decodes slot []) rfl
  refine ⟨.cons moveStep (.cons storeStep (.cons addressStep (.refl _))), ?_⟩
  have addressLength : (addressBytes slot).length = 7 := by simp [addressBytes, i32Bytes]
  change CodeAt stored.memory (stored.rip + 7#64) tail
  simpa only [addressLength] using addressCode.suffix

/-- Reuse the shared value-layout relation for the descriptor produced by
the actual continuation. The initial pointer word is the only saved-data premise. -/
theorem continuation_represents (locations : Storage.Locations) (before : State)
    (layout : Frame.Layout) (slot : Fin layout.slots) (positive : 0 < slot.val)
    (bounded : layout.slots ≤ 1048576) (frame : before.registers 5 = BitVec.ofNat 64 layout.base)
    (value : ((before.registers 0).setWidth 32).toNat = count)
    (saved : read64 before.memory (layout.address slot) = data)
    (root : Lanius.CellId) (path : List Lanius.Core.ValueProjection) (start : Nat) :
    Storage.Represents (Storage.Slice.Descriptor.install locations root path start data)
      (continuation before slot.val).memory (layout.address slot)
      (.slice (.scalar (.signed .i32)) root path start count) := by
  have fields := continuation_fields before layout slot positive bounded frame value
  have countBound : count < 2^64 := by have := ((before.registers 0).setWidth 32).isLt; omega
  rw [fields.1]
  refine ⟨[.full data, .full (BitVec.ofNat 64 count)], ?_, ?_⟩
  · simp [Storage.shape, countBound]
  · intro index inside
    have cases : index = 0 ∨ index = 1 := by simp only [List.length_cons, List.length_nil] at inside; omega
    rcases cases with rfl | rfl
    · simp only [List.getElem_cons_zero, Storage.Word.holds]
      rw [show Copy.address (layout.address slot) 0 = layout.address slot from by simp [Copy.address]]
      have separated : ∀ i j : Fin 8, layout.address slot + BitVec.ofNat 64 i.val ≠
          layout.address slot + 8 + BitVec.ofNat 64 j.val := by
        intro i j
        rw [← previous_address layout slot positive]
        apply layout.word_disjoint slot (lengthSlot slot)
        intro same
        have := congrArg Fin.val same
        simp only [lengthSlot] at this
        omega
      rw [read64_frame _ _ _ _ separated, saved]
    · simp only [List.getElem_cons_succ, List.getElem_cons_zero, Storage.Word.holds]
      rw [show Copy.address (layout.address slot) 1 = layout.address slot + 8 from by simp [Copy.address]]
      exact read64_write64 before.memory (layout.address slot + 8) (BitVec.ofNat 64 count)

end Lanius.X86.Machine.Slice.Raw
