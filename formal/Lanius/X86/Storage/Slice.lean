import Lanius.X86.Storage.Value

namespace Lanius.X86.Storage.Slice

open Machine

/-- Heap i32 elements occupy four bytes, unlike padded internal value words. -/
def address (base : Machine.Address) (index : Nat) : Machine.Address :=
  base + BitVec.ofNat 64 (index * 4)

/-- A live, nonwrapping packed allocation. Mapping and ownership are supplied
by the enclosing heap relation; this relation records its extent and contents. -/
structure Represents (memory : Memory) (base : Machine.Address) (values : List Int) : Prop where
  bounded : base.toNat + values.length * 4 ≤ 2^64
  signed : ∀ value ∈ values, -2147483648 ≤ value ∧ value ≤ 2147483647
  elements : ∀ index, ∀ bound : index < values.length,
    read32 memory (address base index) = BitVec.ofInt 32 values[index]

theorem address_add (base : Machine.Address) (start index : Nat) :
    address (address base start) index = address base (start + index) := by
  simp [address, Nat.add_mul, BitVec.ofNat_add, BitVec.add_assoc]

/-- The actual shift/add address calculation cannot wrap for an in-bounds
element of a represented allocation. Every byte remains inside its extent. -/
theorem Represents.lane (stored : Represents memory base values)
    (index : Nat) (inside : index < values.length) (lane : Fin 4) :
    (address base index + BitVec.ofNat 64 lane.val).toNat =
      base.toNat + index * 4 + lane.val ∧
    base.toNat + index * 4 + lane.val < base.toNat + values.length * 4 := by
  have extent := stored.bounded
  have byte := lane.isLt
  have bound : base.toNat + index * 4 + lane.val < 2^64 := by omega
  constructor
  · simp only [address, BitVec.toNat_add, BitVec.toNat_ofNat]
    omega
  · omega

theorem Represents.disjoint (stored : Represents memory base values)
    (left right : Nat) (leftBound : left < values.length) (rightBound : right < values.length)
    (different : left ≠ right) (i j : Fin 4) :
    address base left + BitVec.ofNat 64 i.val ≠ address base right + BitVec.ofNat 64 j.val := by
  intro same
  have numbers := congrArg BitVec.toNat same
  rw [(stored.lane left leftBound i).1, (stored.lane right rightBound j).1] at numbers
  have ib := i.isLt
  have jb := j.isLt
  omega

theorem Represents.read (stored : Represents memory base values)
    (start length index : Nat) (view : start + length ≤ values.length) (inside : index < length) :
    (read32 memory (address (address base start) index)).toInt = values[start + index] := by
  rw [address_add, stored.elements (start + index) (by omega)]
  have signed := stored.signed values[start + index] (List.getElem_mem (by omega))
  exact BitVec.toInt_ofInt_eq_self (by decide) signed.1 (by omega)

/-- A single native store implements Core's list update for the entire
backing array, so other slices of the same allocation observe the update too. -/
theorem Represents.store (stored : Represents memory base values)
    (index : Nat) (inside : index < values.length) (value : Int)
    (signed : -2147483648 ≤ value ∧ value ≤ 2147483647) :
    Represents (write32 memory (address base index) (BitVec.ofInt 32 value)) base (values.set index value) := by
  refine ⟨by simpa using stored.bounded, ?_, ?_⟩
  · intro item member
    rcases List.mem_or_eq_of_mem_set member with original | equal
    · exact stored.signed item original
    · subst item; exact signed
  · intro other bound
    have original : other < values.length := by simpa using bound
    by_cases same : other = index
    · subst other
      simpa using read32_write32 memory (address base index) (BitVec.ofInt 32 value)
    · rw [read32_frame _ _ _ _ (stored.disjoint other index original inside same)]
      simpa [List.getElem_set, Ne.symm same] using stored.elements other original

/-- All bytes outside the selected element survive, including other heap
allocations, descriptors, caller frames, and loaded instructions. -/
theorem store_frame (memory : Memory) (base : Machine.Address) (index : Nat) (value : Int) (candidate : Machine.Address)
    (outside : ∀ lane : Fin 4, candidate ≠ address base index + BitVec.ofNat 64 lane.val) :
    write32 memory (address base index) (BitVec.ofInt 32 value) candidate = memory candidate := by
  apply write32_frame
  exact ⟨by simpa using outside ⟨0, by decide⟩, outside ⟨1, by decide⟩,
    outside ⟨2, by decide⟩, outside ⟨3, by decide⟩⟩

theorem Represents.frame (stored : Represents before base values)
    (same : ∀ index, index < values.length → ∀ lane : Fin 4,
      after (address base index + BitVec.ofNat 64 lane.val) =
        before (address base index + BitVec.ofNat 64 lane.val)) :
    Represents after base values := by
  refine ⟨stored.bounded, stored.signed, ?_⟩
  intro index inside
  rw [read32_congr after before _ (same index inside)]
  exact stored.elements index inside

end Lanius.X86.Storage.Slice
