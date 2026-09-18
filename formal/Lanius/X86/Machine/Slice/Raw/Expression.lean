import Lanius.X86.Machine.Slice.Raw
import Lanius.X86.Encode.Immediate

namespace Lanius.X86.Machine.Slice.Raw.Expression

variable {length : Int} {data : Address} {entry started : State}

/-- The pointer child is a frame MOV64 load, not a register-register move. -/
def pointerBytes (sourceSlot : Nat) : List UInt8 := memoryBytes .w64 true 0 5 (Frame.displacement sourceSlot)
def captureBytes (top : Nat) : List UInt8 := memoryBytes .w64 false 0 5 (Frame.displacement (top + 1))
def prefixBytes (sourceSlot top : Nat) (length : Int) : List UInt8 :=
  pointerBytes sourceSlot ++ captureBytes top ++ Encode.Immediate.bytes length
def bytes (sourceSlot top : Nat) (length : Int) : List UInt8 :=
  prefixBytes sourceSlot top length ++ Raw.bytes (top + 1)

@[simp] theorem pointerBytes_length : (pointerBytes sourceSlot).length = 7 := by
  change ([72, 139, 133] ++ Lanius.Semantics.i32Bytes (Frame.displacement sourceSlot)).length = 7
  rw [List.length_append, Lanius.Properties.i32Bytes_length]
  rfl
@[simp] theorem captureBytes_length : (captureBytes top).length = 7 := by
  change ([72, 137, 133] ++ Lanius.Semantics.i32Bytes (Frame.displacement (top + 1))).length = 7
  rw [List.length_append, Lanius.Properties.i32Bytes_length]
  rfl
@[simp] theorem prefixBytes_length : (prefixBytes sourceSlot top length).length = 19 := by
  simp [prefixBytes]

def prepared (before : State) (sourceSlot top : Nat) (length : Int) : State :=
  let pointer := before.load64 0 5 (BitVec.ofInt 32 (Frame.displacement sourceSlot)) 7
  let captured := pointer.store64 0 5 (BitVec.ofInt 32 (Frame.displacement (top + 1))) 7
  captured.immediate32 0 (BitVec.ofInt 32 length) 5

theorem prepared_fields (before : State) (layout : Frame.Layout)
    (sourceSlot slot : Fin layout.slots) (position : slot.val = top + 1)
    (bounded : layout.slots ≤ 1048576) (base : before.registers 5 = BitVec.ofNat 64 layout.base)
    (pointer : read64 before.memory (layout.address sourceSlot) = data) :
    let after := prepared before sourceSlot.val top length
    after.memory = write64 before.memory (layout.address slot) data ∧
    (after.registers 0).setWidth 32 = BitVec.ofInt 32 length ∧
    (∀ register, register ≠ 0 → after.registers register = before.registers register) ∧
    after.flags = before.flags ∧ after.rip = before.rip + 19 := by
  have localOperand := layout.operand sourceSlot bounded base
  have slotOperand := layout.operand slot bounded base
  rw [position] at slotOperand
  simp [prepared, State.load64, State.store64, State.immediate32, localOperand, slotOperand,
    pointer, BitVec.add_assoc]
  intro register different
  simp [different]

/-- The complete first three instructions derive the saved-pointer and
literal-value premises used by the guard. Pointer and destination need not be
assumed distinct: the pointer is loaded before its capture store. Live-slot
preservation below derives separation from the allocator frontier instead. -/
theorem prepares (before : State) (layout : Frame.Layout)
    (sourceSlot slot : Fin layout.slots) (top : Nat) (position : slot.val = top + 1)
    (bounded : layout.slots ≤ 1048576) (base : before.registers 5 = BitVec.ofNat 64 layout.base)
    (pointer : read64 before.memory (layout.address sourceSlot) = data) (tail : List UInt8)
    (loaded : CodeAt before.memory before.rip (prefixBytes sourceSlot.val top length ++ tail))
    (separate : ∀ index, index < (prefixBytes sourceSlot.val top length ++ tail).length → ∀ lane : Fin 8,
      before.rip + BitVec.ofNat 64 index ≠ layout.address slot + BitVec.ofNat 64 lane.val) :
    Steps 3 before (prepared before sourceSlot.val top length) ∧
    read64 (prepared before sourceSlot.val top length).memory (layout.address slot) = data ∧
    CodeAt (prepared before sourceSlot.val top length).memory (prepared before sourceSlot.val top length).rip tail := by
  let fetched := before.load64 0 5 (BitVec.ofInt 32 (Frame.displacement sourceSlot.val)) 7
  let captured := fetched.store64 0 5 (BitVec.ofInt 32 (Frame.displacement (top + 1))) 7
  have code : CodeAt before.memory before.rip
      (pointerBytes sourceSlot.val ++ (captureBytes top ++ (Encode.Immediate.bytes length ++ tail))) := by
    simpa only [prefixBytes, List.append_assoc] using loaded
  have pointerDecoded : decode (pointerBytes sourceSlot.val) =
      some (.load64 0 5 (BitVec.ofInt 32 (Frame.displacement sourceSlot.val)),
        (pointerBytes sourceSlot.val).length) := by
    simpa only [pointerBytes, memoryInstruction, ↓reduceIte, List.append_nil] using
      memory_decodes .w64 true 0 5 (Frame.displacement sourceSlot.val) []
  rw [pointerBytes_length] at pointerDecoded
  have loadStep : Step before fetched := .decoded _ code.prefix _ _ pointerDecoded rfl
  have captureCode : CodeAt fetched.memory fetched.rip
      (captureBytes top ++ (Encode.Immediate.bytes length ++ tail)) := by
    change CodeAt before.memory (before.rip + 7#64) _
    simpa only [pointerBytes_length] using code.suffix
  have captureDecoded : decode (captureBytes top) =
      some (.store64 0 5 (BitVec.ofInt 32 (Frame.displacement (top + 1))), (captureBytes top).length) := by
    simpa only [captureBytes, memoryInstruction, Bool.false_eq_true, ↓reduceIte, List.append_nil] using
      memory_decodes .w64 false 0 5 (Frame.displacement (top + 1)) []
  rw [captureBytes_length] at captureDecoded
  have captureStep : Step fetched captured := .decoded _ captureCode.prefix _ _ captureDecoded rfl
  have fields := prepared_fields (length := length) before layout sourceSlot slot position bounded base pointer
  have written : captured.memory = write64 before.memory (layout.address slot) data := fields.1
  have allCode : CodeAt captured.memory before.rip (prefixBytes sourceSlot.val top length ++ tail) := by
    rw [written]
    exact loaded.write64 data separate
  have immediateCode : CodeAt captured.memory captured.rip (Encode.Immediate.bytes length ++ tail) := by
    have code' : CodeAt captured.memory before.rip
        ((pointerBytes sourceSlot.val ++ captureBytes top) ++ (Encode.Immediate.bytes length ++ tail)) := by
      simpa only [prefixBytes, List.append_assoc] using allCode
    change CodeAt captured.memory (before.rip + 7#64 + 7#64) _
    simpa only [List.length_append, pointerBytes_length, captureBytes_length, BitVec.ofNat_add,
      BitVec.add_assoc] using code'.suffix
  have literalStep : Step captured (prepared before sourceSlot.val top length) :=
    Encode.Immediate.executes captured immediateCode.prefix
  refine ⟨.cons loadStep (.cons captureStep (.cons literalStep (.refl _))), ?_, ?_⟩
  · rw [fields.1, read64_write64]
  · change CodeAt captured.memory (captured.rip + 5#64) tail
    simpa only [Encode.Immediate.bytes_length] using immediateCode.suffix

/-- The first capture preserves every represented heap block under explicit
separation. This supplies the heap premise of the already connected Core raw
constructor theorem without assuming the entire expression has executed. -/
theorem prepares_heap (before : State) (layout : Frame.Layout)
    (sourceSlot slot : Fin layout.slots) (position : slot.val = top + 1)
    (bounded : layout.slots ≤ 1048576) (base : before.registers 5 = BitVec.ofNat 64 layout.base)
    (pointer : read64 before.memory (layout.address sourceSlot) = data)
    (related : Storage.Heap.Correspondence heap before.memory locations)
    (separate : ∀ block ∈ heap.blocks, ∀ native,
      locations.pointer block.base = some native → ∀ offset, offset < block.size → ∀ lane : Fin 8,
      native + BitVec.ofNat 64 offset ≠ layout.address slot + BitVec.ofNat 64 lane.val) :
    Storage.Heap.Correspondence heap (prepared before sourceSlot.val top length).memory locations := by
  have fields := prepared_fields (length := length) before layout sourceSlot slot position bounded base pointer
  rw [fields.1]
  refine ⟨related.wellFormed, ?_, related.offsets, related.covered, related.disjoint⟩
  intro block member native mapped
  apply (related.mappedBlock block member native mapped).frame
  intro offset inside
  exact write64_frame _ _ _ _ (separate block member native mapped offset inside)

theorem prepares_caller (before : State) (layout : Frame.Layout)
    (sourceSlot slot : Fin layout.slots) (position : slot.val = top + 1)
    (bounded : layout.slots ≤ 1048576) (base : before.registers 5 = BitVec.ofNat 64 layout.base)
    (pointer : read64 before.memory (layout.address sourceSlot) = data)
    (frame : Frame.BodyFrame entry started before) (headerBound : layout.base + 16 ≤ 2^64) :
    Frame.BodyFrame entry started (prepared before sourceSlot.val top length) := by
  have fields := prepared_fields (length := length) before layout sourceSlot slot position bounded base pointer
  have header := frame.framePointer.symm.trans base
  refine ⟨(fields.2.2.1 5 (by decide)).trans frame.framePointer, ?_, ?_, ?_, ?_⟩
  · rw [fields.1, read64_frame]
    · exact frame.savedPointer
    · intro i j
      rw [header]
      exact layout.saved_word_disjoint slot headerBound ⟨i.val, by have := i.isLt; omega⟩ j
  · rw [fields.1, read64_frame]
    · exact frame.returnAddress
    · intro i j
      rw [header]
      simpa [BitVec.ofNat_add, BitVec.add_assoc] using
        layout.saved_word_disjoint slot headerBound ⟨8 + i.val, by have := i.isLt; omega⟩ j
  · intro register saved
    rw [fields.2.2.1 register (by rcases saved with rfl | rfl | rfl | rfl | rfl <;> decide)]
    exact frame.registers register saved
  · rw [fields.2.2.2.1]
    exact frame.direction

theorem prepares_slot (before : State) (layout : Frame.Layout)
    (sourceSlot slot other : Fin layout.slots) (position : slot.val = top + 1)
    (bounded : layout.slots ≤ 1048576) (base : before.registers 5 = BitVec.ofNat 64 layout.base)
    (pointer : read64 before.memory (layout.address sourceSlot) = data) (live : other.val < top)
    (lane : Fin 8) :
    (prepared before sourceSlot.val top length).memory (layout.address other + BitVec.ofNat 64 lane.val) =
      before.memory (layout.address other + BitVec.ofNat 64 lane.val) := by
  have fields := prepared_fields (length := length) before layout sourceSlot slot position bounded base pointer
  rw [fields.1]
  apply write64_frame
  apply layout.word_disjoint other slot
  intro same
  have equal := congrArg Fin.val same
  omega

end Lanius.X86.Machine.Slice.Raw.Expression
