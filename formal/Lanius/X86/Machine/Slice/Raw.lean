import Lanius.X86.Machine.Slice.Raw.Continuation

namespace Lanius.X86.Machine.Slice.Raw

variable {before entry started : State} {length : Int} {data : Address} {values : List Int}

def testBytes : List UInt8 := [133, 192]
def branchBytes : List UInt8 := [15, 141, 2, 0, 0, 0, 15, 11]
def guardBytes : List UInt8 := testBytes ++ branchBytes
def bytes (slot : Nat) : List UInt8 := guardBytes ++ continuationBytes slot

@[simp] theorem guardBytes_length : guardBytes.length = 10 := rfl
@[simp] theorem bytes_length : (bytes slot).length = 10 + (continuationBytes slot).length := by
  rw [bytes, List.length_append, guardBytes_length]

def guarded (before : State) (auxiliary : Bool) : State :=
  (before.test32 0 0 auxiliary 2).branch 13 2 6

theorem test_decodes (tail : List UInt8) :
    decode (testBytes ++ tail) = some (.test32 0 0, 2) := by rfl

theorem branch_decodes (tail : List UInt8) :
    decode (branchBytes ++ tail) = some (.branch 13 2, 6) := by rfl

/-- The scalar value premise is exactly the signed low-32-bit observation;
high RAX bits may be arbitrary. Canonical i32 source representations supply it. -/
theorem canonical_i32 (length : Int) (canonical : -2147483648 ≤ length ∧ length ≤ 2147483647)
    (value : (before.registers 0).setWidth 32 = BitVec.ofInt 32 length) :
    ((before.registers 0).setWidth 32).toInt = length := by
  rw [value]
  exact BitVec.toInt_ofInt_eq_self (by decide) canonical.1 (by omega)

theorem guard_selected (before : State) (auxiliary : Bool)
    (scalar : ((before.registers 0).setWidth 32).toInt = length) :
    condition (before.test32 0 0 auxiliary 2).flags 13 = decide (0 ≤ length) := by
  simp only [State.test32, BitVec.and_self, logical32Flags_greaterEqual, BitVec.msb_eq_toInt, scalar]
  by_cases nonnegative : 0 ≤ length
  · simp [nonnegative, show ¬ length < 0 by omega]
  · simp [nonnegative, show length < 0 by omega]

/-- Both choices of the undefined AF bit take the same branch. A negative
length reaches UD2 without any register or memory write, including no length store. -/
theorem guard (before : State) (auxiliary : Bool) (tail : List UInt8)
    (scalar : ((before.registers 0).setWidth 32).toInt = length)
    (loaded : CodeAt before.memory before.rip (guardBytes ++ tail)) :
    Steps 2 before (guarded before auxiliary) ∧
    (guarded before auxiliary).memory = before.memory ∧
    (guarded before auxiliary).registers = before.registers ∧
    (guarded before auxiliary).flags.getLsbD 10 = before.flags.getLsbD 10 ∧
    (if 0 ≤ length then
      (guarded before auxiliary).rip = before.rip + 10 ∧
        CodeAt (guarded before auxiliary).memory (guarded before auxiliary).rip tail
    else (guarded before auxiliary).rip = before.rip + 8 ∧ Fault (guarded before auxiliary)) := by
  let tested := before.test32 0 0 auxiliary 2
  have code : CodeAt before.memory before.rip (testBytes ++ (branchBytes ++ tail)) := by
    simpa only [guardBytes, List.append_assoc] using loaded
  have testStep : Step before tested := .tested _ code.prefix 0 0 2 (test_decodes []) auxiliary rfl
  have branchCode : CodeAt tested.memory tested.rip (branchBytes ++ tail) := code.suffix
  have branchStep : Step tested (guarded before auxiliary) := .decoded _ branchCode _ _
    (branch_decodes tail) rfl
  refine ⟨.cons testStep (.cons branchStep (.refl _)), rfl, rfl,
    logical32Flags_direction _ _ auxiliary, ?_⟩
  have selected := guard_selected before auxiliary scalar
  split <;> rename_i sign
  · have rip : (guarded before auxiliary).rip = before.rip + 10 := by
      change before.rip + 2#64 + 6#64 +
        (if condition (before.test32 0 0 auxiliary 2).flags 13 then (2#32).signExtend 64 else 0#64) = _
      rw [selected]
      simp [sign, BitVec.add_assoc]
    refine ⟨rip, ?_⟩
    rw [rip]
    exact loaded.suffix
  · have rip : (guarded before auxiliary).rip = before.rip + 8 := by
      change before.rip + 2#64 + 6#64 +
        (if condition (before.test32 0 0 auxiliary 2).flags 13 then (2#32).signExtend 64 else 0#64) = _
      rw [selected]
      simp [sign, BitVec.add_assoc]
    refine ⟨rip, .ud2 ?_⟩
    rw [rip]
    exact (show CodeAt before.memory before.rip
      ([133, 192, 15, 141, 2, 0, 0, 0] ++ ([15, 11] ++ tail)) from loaded).suffix.prefix

/-- Nonnegative canonical i32 observation makes MOV EAX,EAX the exact
64-bit unsigned element count needed by the descriptor. -/
theorem unsigned_count (before : State)
    (scalar : ((before.registers 0).setWidth 32).toInt = length) (nonnegative : 0 ≤ length) :
    ((before.registers 0).setWidth 32).toNat = length.toNat := by
  have sign : ((before.registers 0).setWidth 32).msb = false := by
    rw [BitVec.msb_eq_toInt, scalar]
    simp [show ¬ length < 0 by omega]
  exact (congrArg Int.toNat ((BitVec.toInt_eq_toNat_of_msb sign).symm.trans scalar))

/-- Native continuation for the actual raw-slice instruction window. It
requires the pointer already saved by the first child and receives the length
from the second child. No emitter execution or recursive compiler proof is assumed.
Every AF outcome is covered by the explicit `auxiliary` parameter. -/
theorem correct (locations : Storage.Locations) (before : State) (auxiliary : Bool)
    (layout : Frame.Layout) (slot : Fin layout.slots) (positive : 0 < slot.val)
    (bounded : layout.slots ≤ 1048576) (frame : before.registers 5 = BitVec.ofNat 64 layout.base)
    (scalar : ((before.registers 0).setWidth 32).toInt = length) (nonnegative : 0 ≤ length)
    (saved : read64 before.memory (layout.address slot) = data)
    (root : Lanius.CellId) (path : List Lanius.Core.ValueProjection) (start : Nat) (tail : List UInt8)
    (loaded : CodeAt before.memory before.rip (bytes slot.val ++ tail))
    (separate : ∀ index, index < (bytes slot.val ++ tail).length → ∀ lane : Fin 8,
      before.rip + BitVec.ofNat 64 index ≠ layout.address slot + 8 + BitVec.ofNat 64 lane.val) :
    let after := continuation (guarded before auxiliary) slot.val
    Steps 5 before after ∧ after.registers 0 = layout.address slot ∧
    Storage.Represents (Storage.Slice.Descriptor.install locations root path start data)
      after.memory (layout.address slot) (.slice (.scalar (.signed .i32)) root path start length.toNat) ∧
    after.memory = write64 before.memory (layout.address slot + 8) (BitVec.ofNat 64 length.toNat) ∧
    (∀ register, register ≠ 0 → after.registers register = before.registers register) ∧
    after.flags.getLsbD 10 = before.flags.getLsbD 10 ∧
    after.rip = before.rip + BitVec.ofNat 64 (bytes slot.val).length ∧
    CodeAt after.memory after.rip tail := by
  have code : CodeAt before.memory before.rip (guardBytes ++ (continuationBytes slot.val ++ tail)) := by
    simpa only [bytes, List.append_assoc] using loaded
  have guardRun := guard before auxiliary (continuationBytes slot.val ++ tail) scalar code
  have success := guardRun.2.2.2.2
  rw [if_pos nonnegative] at success
  have value := unsigned_count before scalar nonnegative
  have fields := continuation_fields (guarded before auxiliary) layout slot positive bounded frame value
  have operand := layout.operand (lengthSlot slot) bounded frame
  rw [previous_address layout slot positive] at operand
  simp only [lengthSlot] at operand
  have next := continuation_steps (guarded before auxiliary) slot.val tail success.2 (by
    intro index inside lane
    change (guarded before auxiliary).rip + BitVec.ofNat 64 index ≠
      before.registers 5 + (BitVec.ofInt 32 (Frame.displacement (slot.val - 1))).signExtend 64 +
        BitVec.ofNat 64 lane.val
    rw [success.1, operand]
    have past : 10 + index < (bytes slot.val ++ tail).length := by
      simp only [List.length_append, bytes_length]
      simp only [List.length_append] at inside
      omega
    simpa [BitVec.ofNat_add, BitVec.add_assoc] using separate (10 + index) past lane)
  refine ⟨guardRun.1.trans next.1, fields.2.1,
    continuation_represents locations (guarded before auxiliary) layout slot positive bounded frame value saved root path start,
    fields.1, fields.2.2.1, ?_, ?_, next.2⟩
  · rw [fields.2.2.2.1]
    exact guardRun.2.2.2.1
  · rw [fields.2.2.2.2, success.1]
    rw [bytes_length, BitVec.ofNat_add]
    change before.rip + 10#64 + BitVec.ofNat 64 (continuationBytes slot.val).length =
      before.rip + (10#64 + BitVec.ofNat 64 (continuationBytes slot.val).length)
    exact BitVec.add_assoc _ _ _

theorem rejects_negative (before : State) (auxiliary : Bool) (slot : Nat) (tail : List UInt8)
    (scalar : ((before.registers 0).setWidth 32).toInt = length) (negative : length < 0)
    (loaded : CodeAt before.memory before.rip (bytes slot ++ tail)) :
    Steps 2 before (guarded before auxiliary) ∧ Fault (guarded before auxiliary) ∧
    (guarded before auxiliary).memory = before.memory ∧
    (guarded before auxiliary).registers = before.registers ∧
    (guarded before auxiliary).rip = before.rip + 8 := by
  have result := guard before auxiliary (continuationBytes slot ++ tail) scalar
    (by simpa only [bytes, List.append_assoc] using loaded)
  have fault := result.2.2.2.2
  rw [if_neg (by omega : ¬ 0 ≤ length)] at fault
  exact ⟨result.1, fault.2, result.2.1, result.2.2.1, fault.1⟩

/-- Only the descriptor's length word changes. Packed backing is retained
under explicit byte separation, including the empty-array case. -/
theorem preserves_backing (before : State) (auxiliary : Bool) (layout : Frame.Layout)
    (slot : Fin layout.slots) (positive : 0 < slot.val) (bounded : layout.slots ≤ 1048576)
    (frame : before.registers 5 = BitVec.ofNat 64 layout.base)
    (stored : Storage.Slice.Represents before.memory data values)
    (separate : ∀ index, index < values.length → ∀ source : Fin 4, ∀ target : Fin 8,
      Storage.Slice.address data index + BitVec.ofNat 64 source.val ≠
        layout.address slot + 8 + BitVec.ofNat 64 target.val) :
    Storage.Slice.Represents (continuation (guarded before auxiliary) slot.val).memory data values := by
  have fields := continuation_fields (guarded before auxiliary) layout slot positive bounded frame rfl
  rw [fields.1]
  apply stored.frame
  intro index inside lane
  exact write64_frame _ _ _ _ (separate index inside lane)

/-- The complete mapped-block correspondence survives descriptor storage;
no raw-pointer map, logical allocation, ownership, or liveness fact changes. -/
theorem preserves_heap (before : State) (auxiliary : Bool) (layout : Frame.Layout)
    (slot : Fin layout.slots) (positive : 0 < slot.val) (bounded : layout.slots ≤ 1048576)
    (frame : before.registers 5 = BitVec.ofNat 64 layout.base)
    (related : Storage.Heap.Correspondence heap before.memory locations)
    (separate : ∀ block, block ∈ heap.blocks → ∀ base,
      locations.pointer block.base = some base → ∀ offset, offset < block.size → ∀ lane : Fin 8,
      base + BitVec.ofNat 64 offset ≠ layout.address slot + 8 + BitVec.ofNat 64 lane.val) :
    Storage.Heap.Correspondence heap (continuation (guarded before auxiliary) slot.val).memory locations := by
  have fields := continuation_fields (guarded before auxiliary) layout slot positive bounded frame rfl
  rw [fields.1]
  refine ⟨related.wellFormed, ?_, related.offsets, related.covered, related.disjoint⟩
  intro block member base mapped
  apply (related.mappedBlock block member base mapped).frame
  intro offset inside
  exact write64_frame _ _ _ _ (separate block member base mapped offset inside)

theorem preserves_caller (before : State) (auxiliary : Bool) (layout : Frame.Layout)
    (slot : Fin layout.slots) (positive : 0 < slot.val) (bounded : layout.slots ≤ 1048576)
    (base : before.registers 5 = BitVec.ofNat 64 layout.base)
    (frame : Frame.BodyFrame entry started before)
    (separate : ∀ header : Fin 16, ∀ lane : Fin 8,
      started.registers 5 + BitVec.ofNat 64 header.val ≠
        layout.address slot + 8 + BitVec.ofNat 64 lane.val) :
    Frame.BodyFrame entry started (continuation (guarded before auxiliary) slot.val) := by
  have fields := continuation_fields (guarded before auxiliary) layout slot positive bounded base rfl
  refine ⟨(fields.2.2.1 5 (by decide)).trans frame.framePointer, ?_, ?_, ?_, ?_⟩
  · rw [fields.1, read64_frame]
    · exact frame.savedPointer
    · intro i j
      exact separate ⟨i.val, by have := i.isLt; omega⟩ j
  · rw [fields.1, read64_frame]
    · exact frame.returnAddress
    · intro i j
      simpa [BitVec.ofNat_add, BitVec.add_assoc] using
        separate ⟨8 + i.val, by have := i.isLt; omega⟩ j
  · intro register saved
    rw [fields.2.2.1 register (by rcases saved with rfl | rfl | rfl | rfl | rfl <;> decide)]
    exact frame.registers register saved
  · rw [fields.2.2.2.1]
    exact (logical32Flags_direction _ _ auxiliary).trans frame.direction

/-- All other private frame words survive, not merely the pointer word. -/
theorem preserves_slot (before : State) (auxiliary : Bool) (layout : Frame.Layout)
    (slot other : Fin layout.slots) (positive : 0 < slot.val) (bounded : layout.slots ≤ 1048576)
    (frame : before.registers 5 = BitVec.ofNat 64 layout.base)
    (different : other ≠ lengthSlot slot) (lane : Fin 8) :
    (continuation (guarded before auxiliary) slot.val).memory
      (layout.address other + BitVec.ofNat 64 lane.val) =
    before.memory (layout.address other + BitVec.ofNat 64 lane.val) := by
  have fields := continuation_fields (guarded before auxiliary) layout slot positive bounded frame rfl
  rw [fields.1, ← previous_address layout slot positive]
  exact write64_frame _ _ _ _ (layout.word_disjoint other (lengthSlot slot) different lane)

end Lanius.X86.Machine.Slice.Raw
