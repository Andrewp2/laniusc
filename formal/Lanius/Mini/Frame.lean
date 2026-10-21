import Lanius.X86.Machine.FrameSlots
import Lanius.Mini.Compile

/-! Frame layout arithmetic. Slot `k` is the four bytes at `rbp - 8 * (k + 1)`;
the saved rbp and the return address are the sixteen bytes at `rbp`. All of
these are offsets from rbp, so they never meet whatever rbp is; only the code
image needs a separation hypothesis. -/

namespace Lanius.Mini
open Lanius.X86.Machine

private theorem bmod32_self {d : Int} (lower : -(2^31 : Int) ≤ d) (upper : d < 2^31) :
    d.bmod (2^32) = d := by
  rw [Int.bmod_eq_emod]
  have := Int.emod_nonneg d (show (2^32 : Int) ≠ 0 by decide)
  have := Int.emod_lt_of_pos d (show (0 : Int) < 2^32 by decide)
  split <;> omega

private theorem bmod64_self {d : Int} (lower : -(2^63 : Int) ≤ d) (upper : d < 2^63) :
    d.bmod (2^64) = d := by
  rw [Int.bmod_eq_emod]
  have := Int.emod_nonneg d (show (2^64 : Int) ≠ 0 by decide)
  have := Int.emod_lt_of_pos d (show (0 : Int) < 2^64 by decide)
  split <;> omega

theorem slotAddress_eq (rbp : BitVec 64) {slot : Nat} (bound : slot < frameLimit) :
    frameSlotAddress rbp slot = rbp - BitVec.ofNat 64 ((slot + 1) * 8) := by
  unfold frameSlotAddress frameDisplacement frameLimit at *
  have lower : -(2^31 : Int) ≤ -Int.ofNat ((slot + 1) * 8) := by simp only [Int.ofNat_eq_natCast]; omega
  have upper : -Int.ofNat ((slot + 1) * 8) < (2^31 : Int) := by simp only [Int.ofNat_eq_natCast]; omega
  have extended : (BitVec.ofInt 32 (-Int.ofNat ((slot + 1) * 8))).signExtend 64 =
      BitVec.ofInt 64 (-Int.ofNat ((slot + 1) * 8)) := by
    apply BitVec.eq_of_toInt_eq
    rw [BitVec.toInt_signExtend, BitVec.toInt_ofInt, BitVec.toInt_ofInt]
    simp only [Nat.min_eq_right (by decide : 32 ≤ 64), bmod32_self lower upper,
      bmod64_self (d := -Int.ofNat ((slot + 1) * 8)) (by omega) (by omega)]
  rw [extended, BitVec.ofInt_neg, Int.ofNat_eq_natCast, BitVec.ofInt_natCast, BitVec.sub_eq_add_neg]

theorem slots_disjoint (rbp : BitVec 64) {slot other : Nat} (different : slot ≠ other)
    (slotBound : slot < frameLimit) (otherBound : other < frameLimit) (i j : Fin 4) :
    frameSlotAddress rbp slot + BitVec.ofNat 64 i.val ≠
      frameSlotAddress rbp other + BitVec.ofNat 64 j.val := by
  rw [slotAddress_eq rbp slotBound, slotAddress_eq rbp otherBound]
  have := i.isLt; have := j.isLt
  unfold frameLimit at *
  bv_omega

/-- The saved rbp word, at rbp, is apart from every slot. -/
theorem saved_disjoint (rbp : BitVec 64) {slot : Nat} (bound : slot < frameLimit) (i : Fin 8) (j : Fin 4) :
    rbp + BitVec.ofNat 64 i.val ≠ frameSlotAddress rbp slot + BitVec.ofNat 64 j.val := by
  rw [slotAddress_eq rbp bound]
  have := i.isLt; have := j.isLt
  unfold frameLimit at *
  bv_omega

/-- The return address word, at rbp + 8, is apart from every slot. -/
theorem return_disjoint (rbp : BitVec 64) {slot : Nat} (bound : slot < frameLimit) (i : Fin 8) (j : Fin 4) :
    rbp + 8 + BitVec.ofNat 64 i.val ≠ frameSlotAddress rbp slot + BitVec.ofNat 64 j.val := by
  rw [slotAddress_eq rbp bound]
  have := i.isLt; have := j.isLt
  unfold frameLimit at *
  bv_omega

end Lanius.Mini
