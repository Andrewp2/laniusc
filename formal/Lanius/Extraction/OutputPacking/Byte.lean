import Lanius.Extraction.OutputPacking

namespace Lanius.Extraction.OutputPacking

open Lanius.Semantics

/-- Replace one packed byte, including the sign-bit lane, without requiring
    unused bytes of the destination word to be zero. -/
def replaceByte (word : BitVec 32) (lane : Fin 4) (byte : BitVec 8) : BitVec 32 :=
  let shift := lane.val * 8
  (word &&& (((255 : BitVec 32) <<< shift) ^^^ (-1))) |||
    (byte.setWidth 32 <<< shift)

theorem replaceByte_bit (word : BitVec 32) (lane : Fin 4) (byte : BitVec 8)
    (bit : Fin 32) :
    (replaceByte word lane byte).getLsbD bit =
      if lane.val * 8 ≤ bit.val ∧ bit.val < lane.val * 8 + 8 then
        byte.getLsbD (bit.val - lane.val * 8)
      else word.getLsbD bit := by
  have mask : (255 : BitVec 32) = (BitVec.allOnes 8).setWidth 32 := rfl
  have ones : (-1 : BitVec 32) = BitVec.allOnes 32 := rfl
  have offset : bit.val - lane.val * 8 < 32 := by omega
  simp only [replaceByte, mask, ones, BitVec.xor_allOnes,
    BitVec.getLsbD_or, BitVec.getLsbD_and, BitVec.getLsbD_not,
    BitVec.getLsbD_shiftLeft, BitVec.getLsbD_setWidth,
    BitVec.getLsbD_allOnes, bit.isLt, offset, decide_true, Bool.true_and]
  by_cases before : bit.val < lane.val * 8
  · simp [before, show ¬ lane.val * 8 ≤ bit.val by omega]
  · by_cases inside : bit.val - lane.val * 8 < 8
    · simp [before, inside, show lane.val * 8 ≤ bit.val by omega,
        show bit.val < lane.val * 8 + 8 by omega]
    · simp [before, inside, show ¬ bit.val < lane.val * 8 + 8 by omega,
        BitVec.getLsbD_of_ge byte _ (by omega : 8 ≤ bit.val - lane.val * 8)]

def byteAt (word : BitVec 32) (lane : Fin 4) : BitVec 8 :=
  word.extractLsb' (lane.val * 8) 8

/-- An arithmetic shift's sign extension cannot affect the masked byte,
    including the highest lane of a negative i32. -/
theorem byteAt_shift_mask (word : BitVec 32) (lane : Fin 4) :
    word.sshiftRight (lane.val * 8) &&& 255 = (byteAt word lane).setWidth 32 := by
  apply BitVec.eq_of_getLsbD_eq
  intro bit
  have mask : (255 : BitVec 32) = (BitVec.allOnes 8).setWidth 32 := rfl
  rw [mask]
  simp only [BitVec.getLsbD_and, BitVec.getLsbD_setWidth,
    BitVec.getLsbD_allOnes, BitVec.getLsbD_sshiftRight, byteAt, BitVec.getLsbD_extractLsb']
  by_cases inside : bit < 8
  · have total : lane.val * 8 + bit < 32 := by omega
    simp only [inside, total,
      show bit < 32 by omega, show ¬ 32 ≤ bit by omega]
    simp
  · simp [inside]

theorem byteAt_toInt (word : BitVec 32) (lane : Fin 4) :
    ((byteAt word lane).setWidth 32).toInt = (byteAt word lane).toNat := by
  rw [BitVec.toInt_setWidth]
  have bound := (byteAt word lane).isLt
  apply Int.bmod_eq_of_le <;> omega

/-- The selected byte is replaced and every other byte is unchanged. -/
theorem replaceByte_at (word : BitVec 32) (lane index : Fin 4) (byte : BitVec 8) :
    byteAt (replaceByte word lane byte) index =
      if index = lane then byte else byteAt word index := by
  apply BitVec.eq_of_getLsbD_eq
  intro bit
  by_cases bound : bit < 8
  · have total : index.val * 8 + bit < 32 := by omega
    have updated := replaceByte_bit word lane byte ⟨index.val * 8 + bit, total⟩
    by_cases same : index = lane
    · subst index
      simpa [byteAt, bound, show lane.val * 8 ≤ lane.val * 8 + bit by omega,
        show lane.val * 8 + bit < lane.val * 8 + 8 by omega] using updated
    · have different : index.val ≠ lane.val := fun h => same (Fin.ext h)
      have outside : ¬ (lane.val * 8 ≤ index.val * 8 + bit ∧
          index.val * 8 + bit < lane.val * 8 + 8) := by omega
      simpa [byteAt, bound, same, outside] using updated
  · simp [BitVec.getLsbD_of_ge _ _ (by omega : 8 ≤ bit)]

/-- Bit lanes agree with the actual serializer used by native heap stores. -/
theorem i32Bytes_at (word : BitVec 32) (lane : Fin 4) :
    (i32Bytes word.toInt)[lane.val]? = some (UInt8.ofBitVec (byteAt word lane)) := by
  have bits : (word.toInt % (2 ^ 32 : Int)).toNat = word.toNat :=
    signedBits_i32_bitvec_x86 word word.toInt rfl
  simp only [i32Bytes, bits, List.getElem?_map, List.getElem?_range lane.isLt, Option.map_some]
  congr 1
  apply UInt8.toNat.inj
  simp [byteAt, Nat.shiftRight_eq_div_pow, Nat.mul_comm]

theorem i32Bytes_replaceByte (word : BitVec 32) (lane index : Fin 4) (byte : BitVec 8) :
    (i32Bytes (replaceByte word lane byte).toInt)[index.val]? =
      if index = lane then some (UInt8.ofBitVec byte) else (i32Bytes word.toInt)[index.val]? := by
  rw [i32Bytes_at, replaceByte_at, i32Bytes_at]
  split <;> rfl


theorem readRawSliceIndex_i32Nat (program : Lanius.Core.Program) (state : State) (value : Nat)
    (fits : value < 2 ^ 31) (bound : position < length)
    (loaded : state.heap.loadBytes (address + position * 4) 4 = .ok (i32Bytes value)) :
    readRawSliceIndex program state (.scalar (.signed .i32)) address length position =
      .ok (.signed .i32 value) := by
  have exact : (BitVec.ofNat 32 value).toInt = (value : Int) := by
    rw [BitVec.toInt_eq_msb_cond, BitVec.msb_eq_decide, BitVec.toNat_ofNat,
      Nat.mod_eq_of_lt (by omega : value < 2 ^ 32)]
    simp only [show ¬(value ≥ 2 ^ 31) by omega, decide_false, Bool.false_eq_true, ↓reduceIte]
  simpa only [exact] using readRawSliceIndex_i32Bytes program state (word := BitVec.ofNat 32 value)
    bound (by simpa only [exact] using loaded)

end Lanius.Extraction.OutputPacking
