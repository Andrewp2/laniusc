import Lanius.X86.Machine.Memory

namespace Lanius.X86.Frame

/-- RBP points at the saved caller frame pointer. Scalar slots live below it,
eight bytes apart; loads/stores use their low four bytes. -/
def displacement (slot : Nat) : Int := -((slot + 1 : Nat) : Int) * 8
def bytes (slots : Nat) : Nat := ((slots + 1) / 2) * 16

theorem bytes_aligned (slots : Nat) : bytes slots % 16 = 0 := by simp [bytes]
theorem bytes_room (slots : Nat) : slots * 8 ≤ bytes slots ∧ bytes slots < slots * 8 + 16 := by
  simp only [bytes]
  omega

structure Layout where
  base : Nat
  slots : Nat
  belowBase : bytes slots ≤ base
  addressBound : base < 2 ^ 64

def Layout.offset (layout : Layout) (slot : Fin layout.slots) : Nat := layout.base - (slot.val + 1) * 8
def Layout.address (layout : Layout) (slot : Fin layout.slots) : Machine.Address := BitVec.ofNat 64 (layout.offset slot)

theorem Layout.bounds (layout : Layout) (slot : Fin layout.slots) :
    layout.base - bytes layout.slots ≤ layout.offset slot ∧ layout.offset slot + 8 ≤ layout.base := by
  have room := (bytes_room layout.slots).1
  have allocated := layout.belowBase
  have index := slot.isLt
  simp only [offset]
  omega

theorem Layout.displacement (layout : Layout) (slot : Fin layout.slots) :
    layout.address slot = BitVec.ofNat 64 layout.base + BitVec.ofInt 64 (displacement slot.val) := by
  have index := slot.isLt
  have allocated := layout.belowBase
  have room := (bytes_room layout.slots).1
  have bounded : (slot.val + 1) * 8 ≤ layout.base := by omega
  have cast : (layout.offset slot : Int) = (layout.base : Int) + Frame.displacement slot.val := by
    simp only [offset, Int.natCast_sub bounded, Frame.displacement, Int.natCast_add, Int.natCast_mul]
    omega
  calc
    layout.address slot = BitVec.ofInt 64 (layout.offset slot : Int) := (BitVec.ofInt_natCast _ _).symm
    _ = BitVec.ofInt 64 ((layout.base : Int) + Frame.displacement slot.val) := congrArg (BitVec.ofInt 64) cast
    _ = _ := by rw [BitVec.ofInt_add, BitVec.ofInt_natCast]

theorem Layout.separate (layout : Layout) (left right : Fin layout.slots) (different : left ≠ right) :
    layout.offset left + 8 ≤ layout.offset right ∨ layout.offset right + 8 ≤ layout.offset left := by
  have a := layout.bounds left
  have b := layout.bounds right
  have ids : left.val ≠ right.val := fun equal => different (Fin.ext equal)
  have room := (bytes_room layout.slots).1
  have allocated := layout.belowBase
  have leftBound := left.isLt
  have rightBound := right.isLt
  simp only [offset] at *
  omega

theorem Layout.lane (layout : Layout) (slot : Fin layout.slots) (lane : Fin 4) :
    (layout.address slot + BitVec.ofNat 64 lane.val).toNat = layout.offset slot + lane.val := by
  have bounds := layout.bounds slot
  have representable := layout.addressBound
  have index := lane.isLt
  simp only [address, ← BitVec.ofNat_add, BitVec.toNat_ofNat]
  apply Nat.mod_eq_of_lt
  omega

theorem Layout.disjoint (layout : Layout) (left right : Fin layout.slots) (different : left ≠ right)
    (i j : Fin 4) : layout.address left + BitVec.ofNat 64 i.val ≠ layout.address right + BitVec.ofNat 64 j.val := by
  intro equal
  have same := congrArg BitVec.toNat equal
  rw [layout.lane, layout.lane] at same
  have separate := layout.separate left right different
  have a := i.isLt
  have b := j.isLt
  omega

/-- A local/temporary lies below the saved RBP and return-address words.
The sixteen-byte header must itself have non-wrapping addresses. -/
theorem Layout.saved_disjoint (layout : Layout) (slot : Fin layout.slots)
    (headerBound : layout.base + 16 ≤ 2 ^ 64) (header : Fin 16) (lane : Fin 4) :
    BitVec.ofNat 64 layout.base + BitVec.ofNat 64 header.val ≠ layout.address slot + BitVec.ofNat 64 lane.val := by
  intro equal
  have same := congrArg BitVec.toNat equal
  rw [layout.lane] at same
  rw [← BitVec.ofNat_add, BitVec.toNat_ofNat, Nat.mod_eq_of_lt (by have := header.isLt; omega)] at same
  have slotBound := layout.bounds slot
  have laneBound := lane.isLt
  omega

/-- The storage invariant for scoped locals and expression temporaries. -/
def Represents (layout : Layout) (values : Fin layout.slots → BitVec 32) (memory : Machine.Memory) : Prop :=
  ∀ slot, Machine.read32 memory (layout.address slot) = values slot

theorem Represents.store (represented : Represents layout values memory) (slot : Fin layout.slots) (value : BitVec 32) :
    Represents layout (fun candidate => if candidate = slot then value else values candidate)
      (Machine.write32 memory (layout.address slot) value) := by
  intro candidate
  by_cases same : candidate = slot
  · subst candidate
    simp only [↓reduceIte, Machine.read32_write32]
  · simp only [if_neg same]
    rw [Machine.read32_frame memory (layout.address slot) (layout.address candidate) value
      (layout.disjoint candidate slot same)]
    exact represented candidate

end Lanius.X86.Frame
