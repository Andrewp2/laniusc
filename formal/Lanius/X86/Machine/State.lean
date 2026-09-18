import Lanius.X86.Word

namespace Lanius.X86.Machine

abbrev Register := Fin 16
abbrev Address := BitVec 64
abbrev Memory := Address → UInt8

/-- Exception-free 64-bit user-mode state. Memory is the architectural byte
view. Mapping/protection, canonical-address checks, asynchronous events, and
CET remain explicit environmental obligations, not modeled ISA guarantees. -/
structure State where
  registers : Register → BitVec 64
  rip : Address
  memory : Memory
  flags : BitVec 64

theorem offset_ne (address : Address) (left right : Nat)
    (leftBound : left < 2 ^ 64) (rightBound : right < 2 ^ 64) (different : left ≠ right) :
    address + BitVec.ofNat 64 left ≠ address + BitVec.ofNat 64 right := by
  intro equal
  have words : BitVec.ofNat 64 left = BitVec.ofNat 64 right := (BitVec.add_right_inj _).mp equal
  have same := congrArg BitVec.toNat words
  simp only [BitVec.toNat_ofNat, Nat.mod_eq_of_lt leftBound, Nat.mod_eq_of_lt rightBound] at same
  exact different same

def CodeAt (memory : Memory) (address : Address) (bytes : List UInt8) : Prop :=
  ∀ index (bound : index < bytes.length), memory (address + BitVec.ofNat 64 index) = bytes[index]

theorem CodeAt.prefix (loaded : CodeAt memory address (first ++ rest)) : CodeAt memory address first := by
  intro index bound
  have byte := loaded index (by simp only [List.length_append]; omega)
  rw [List.getElem_append_left bound] at byte
  exact byte

theorem CodeAt.suffix (loaded : CodeAt memory address (first ++ rest)) :
    CodeAt memory (address + BitVec.ofNat 64 first.length) rest := by
  intro index bound
  have byte := loaded (first.length + index) (by simp only [List.length_append]; omega)
  simpa only [List.getElem_append_right (Nat.le_add_right _ _), Nat.add_sub_cancel_left,
    BitVec.ofNat_add, BitVec.add_assoc] using byte

end Lanius.X86.Machine
