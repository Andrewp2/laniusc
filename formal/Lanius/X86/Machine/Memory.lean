import Lanius.X86.Machine.State

namespace Lanius.X86.Machine

/-- The little-endian 32-bit memory operand used by scalar frame loads. -/
def read32 (memory : Memory) (address : Address) : BitVec 32 :=
  readBytes ⟨⟨(memory address).toNat, UInt8.toNat_lt _⟩,
    ⟨(memory (address + 1)).toNat, UInt8.toNat_lt _⟩,
    ⟨(memory (address + 2)).toNat, UInt8.toNat_lt _⟩,
    ⟨(memory (address + 3)).toNat, UInt8.toNat_lt _⟩⟩

/-- Quadwords use the same little-endian word representation as scalar
storage: low four bytes, followed by high four bytes. -/
def read64 (memory : Memory) (address : Address) : BitVec 64 :=
  BitVec.ofNat 64 ((read32 memory address).toNat + 4294967296 * (read32 memory (address + 4)).toNat)

theorem read64_low (memory : Memory) (address : Address) :
    (read64 memory address).setWidth 32 = read32 memory address := by
  apply BitVec.eq_of_toNat_eq
  have low := (read32 memory address).isLt
  have high := (read32 memory (address + 4)).isLt
  simp only [read64, BitVec.toNat_setWidth, BitVec.toNat_ofNat]
  omega

theorem read32_congr (left right : Memory) (address : Address)
    (same : ∀ lane : Fin 4, left (address + BitVec.ofNat 64 lane.val) = right (address + BitVec.ofNat 64 lane.val)) :
    read32 left address = read32 right address := by
  have zero : left address = right address := by simpa using same ⟨0, by decide⟩
  have one : left (address + 1) = right (address + 1) := same ⟨1, by decide⟩
  have two : left (address + 2) = right (address + 2) := same ⟨2, by decide⟩
  have three : left (address + 3) = right (address + 3) := same ⟨3, by decide⟩
  simp only [read32, zero, one, two, three]

theorem read64_congr (left right : Memory) (address : Address)
    (same : ∀ lane : Fin 8, left (address + BitVec.ofNat 64 lane.val) = right (address + BitVec.ofNat 64 lane.val)) :
    read64 left address = read64 right address := by
  have word (offset : Nat) (bounded : offset + 4 ≤ 8) :
      read32 left (address + BitVec.ofNat 64 offset) = read32 right (address + BitVec.ofNat 64 offset) := by
    apply read32_congr
    intro lane
    have index := lane.isLt
    simpa only [BitVec.ofNat_add, BitVec.add_assoc] using same ⟨offset + lane.val, by omega⟩
  have low : read32 left address = read32 right address := by simpa using word 0 (by decide)
  have high : read32 left (address + 4) = read32 right (address + 4) := word 4 (by decide)
  simp only [read64, low, high]

/-- Only the four addressed bytes change, including at the 64-bit wrap
boundary. Mapping/protection and non-wrapping stack allocation remain separate
environmental conditions, as for the existing machine model. -/
def write32 (memory : Memory) (address : Address) (value : BitVec 32) : Memory :=
  let bytes := wordBytes value
  fun candidate =>
    if candidate = address then UInt8.ofNat bytes.low.val
    else if candidate = address + 1 then UInt8.ofNat bytes.second.val
    else if candidate = address + 2 then UInt8.ofNat bytes.third.val
    else if candidate = address + 3 then UInt8.ofNat bytes.high.val
    else memory candidate

theorem byte_roundtrip (byte : Fin 256) : (UInt8.ofNat byte.val).toNat = byte.val := by
  change byte.val % 256 = byte.val
  exact Nat.mod_eq_of_lt byte.isLt

theorem read32_write32 (memory : Memory) (address : Address) (value : BitVec 32) :
    read32 (write32 memory address value) address = value := by
  have one : address + 1 ≠ address := by simp [BitVec.add_right_eq_self]
  have two : address + 2 ≠ address := by simp [BitVec.add_right_eq_self]
  have three : address + 3 ≠ address := by simp [BitVec.add_right_eq_self]
  have twoOne : address + 2 ≠ address + 1 := by simp [BitVec.add_right_inj]
  have threeOne : address + 3 ≠ address + 1 := by simp [BitVec.add_right_inj]
  have threeTwo : address + 3 ≠ address + 2 := by simp [BitVec.add_right_inj]
  simpa only [read32, write32, ↓reduceIte, if_neg one, if_neg two, if_neg three,
    if_neg twoOne, if_neg threeOne, if_neg threeTwo, byte_roundtrip]
    using readBytes_wordBytes value

theorem write32_frame (memory : Memory) (address candidate : Address) (value : BitVec 32)
    (outside : candidate ≠ address ∧ candidate ≠ address + 1 ∧ candidate ≠ address + 2 ∧ candidate ≠ address + 3) :
    write32 memory address value candidate = memory candidate := by
  simp only [write32, if_neg outside.1, if_neg outside.2.1, if_neg outside.2.2.1, if_neg outside.2.2.2]

theorem read32_frame (memory : Memory) (address other : Address) (value : BitVec 32)
    (disjoint : ∀ i j : Fin 4, other + BitVec.ofNat 64 i.val ≠ address + BitVec.ofNat 64 j.val) :
    read32 (write32 memory address value) other = read32 memory other := by
  have lane (i : Fin 4) : write32 memory address value (other + BitVec.ofNat 64 i.val) = memory (other + BitVec.ofNat 64 i.val) := by
    apply write32_frame
    exact ⟨by simpa using disjoint i ⟨0, by decide⟩, disjoint i ⟨1, by decide⟩,
      disjoint i ⟨2, by decide⟩, disjoint i ⟨3, by decide⟩⟩
  have zero : write32 memory address value other = memory other := by simpa using lane ⟨0, by decide⟩
  have one : write32 memory address value (other + 1) = memory (other + 1) := lane ⟨1, by decide⟩
  have two : write32 memory address value (other + 2) = memory (other + 2) := lane ⟨2, by decide⟩
  have three : write32 memory address value (other + 3) = memory (other + 3) := lane ⟨3, by decide⟩
  simp only [read32, zero, one, two, three]

/-- Stack stores cannot modify future instructions when their byte windows
are disjoint. The precondition is required even in the flat memory model. -/
theorem CodeAt.write32 (loaded : CodeAt memory code bytes) (value : BitVec 32)
    (disjoint : ∀ index, index < bytes.length → ∀ lane : Fin 4,
      code + BitVec.ofNat 64 index ≠ address + BitVec.ofNat 64 lane.val) :
    CodeAt (write32 memory address value) code bytes := by
  intro index bound
  rw [write32_frame]
  · exact loaded index bound
  · exact ⟨by simpa using disjoint index bound ⟨0, by decide⟩,
      disjoint index bound ⟨1, by decide⟩, disjoint index bound ⟨2, by decide⟩,
      disjoint index bound ⟨3, by decide⟩⟩

/-- A quadword store consists of the low word followed by the high word in
little-endian byte memory. Used for saved frame pointers and return addresses. -/
def write64 (memory : Memory) (address : Address) (value : BitVec 64) : Memory :=
  write32 (write32 memory address (value.setWidth 32)) (address + 4) ((value >>> 32).setWidth 32)

theorem half_disjoint (address : Address) (i j : Fin 4) :
    address + BitVec.ofNat 64 i.val ≠ address + 4 + BitVec.ofNat 64 j.val := by
  intro equal
  have lanes : BitVec.ofNat 64 i.val = BitVec.ofNat 64 (4 + j.val) := by
    simpa [BitVec.ofNat_add, BitVec.add_assoc, BitVec.add_right_inj] using equal
  have same := congrArg BitVec.toNat lanes
  have ib := i.isLt
  have jb := j.isLt
  simp only [BitVec.toNat_ofNat] at same
  omega

theorem read64_write64 (memory : Memory) (address : Address) (value : BitVec 64) :
    read64 (write64 memory address value) address = value := by
  unfold read64
  simp only [write64, read32_frame _ _ _ _ (half_disjoint address), read32_write32]
  apply BitVec.eq_of_toNat_eq
  have bound := value.isLt
  simp only [BitVec.toNat_ofNat, BitVec.toNat_setWidth, BitVec.toNat_ushiftRight]
  omega

theorem write64_frame (memory : Memory) (address other : Address) (value : BitVec 64)
    (outside : ∀ lane : Fin 8, other ≠ address + BitVec.ofNat 64 lane.val) :
    write64 memory address value other = memory other := by
  unfold write64
  rw [write32_frame, write32_frame]
  · exact ⟨by simpa using outside ⟨0, by decide⟩, outside ⟨1, by decide⟩,
      outside ⟨2, by decide⟩, outside ⟨3, by decide⟩⟩
  · exact ⟨outside ⟨4, by decide⟩, by simpa [BitVec.add_assoc] using outside ⟨5, by decide⟩,
      by simpa [BitVec.add_assoc] using outside ⟨6, by decide⟩,
      by simpa [BitVec.add_assoc] using outside ⟨7, by decide⟩⟩

theorem CodeAt.write64 (loaded : CodeAt memory code bytes) (value : BitVec 64)
    (disjoint : ∀ index, index < bytes.length → ∀ lane : Fin 8,
      code + BitVec.ofNat 64 index ≠ address + BitVec.ofNat 64 lane.val) :
    CodeAt (write64 memory address value) code bytes := by
  intro index bound
  rw [write64_frame _ _ _ _ (disjoint index bound)]
  exact loaded index bound

theorem read64_frame (memory : Memory) (address other : Address) (value : BitVec 64)
    (disjoint : ∀ i j : Fin 8, other + BitVec.ofNat 64 i.val ≠ address + BitVec.ofNat 64 j.val) :
    read64 (write64 memory address value) other = read64 memory other := by
  apply read64_congr
  intro lane
  exact write64_frame _ _ _ _ (disjoint lane)

theorem read64_write32_frame (memory : Memory) (address other : Address) (value : BitVec 32)
    (disjoint : ∀ i : Fin 8, ∀ j : Fin 4, other + BitVec.ofNat 64 i.val ≠ address + BitVec.ofNat 64 j.val) :
    read64 (write32 memory address value) other = read64 memory other := by
  apply read64_congr
  intro lane
  apply write32_frame
  exact ⟨by simpa using disjoint lane ⟨0, by decide⟩, disjoint lane ⟨1, by decide⟩,
    disjoint lane ⟨2, by decide⟩, disjoint lane ⟨3, by decide⟩⟩

end Lanius.X86.Machine
