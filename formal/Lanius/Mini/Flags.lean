import Lanius.Mini.Bytes
import Lanius.X86.Machine.Flags

/-! After `cmp left, right`, each comparison's condition code holds exactly
when the source comparison does. -/

namespace Lanius.Mini
open Lanius.X86.Machine

theorem arithmeticFlags_bits (before : BitVec 64) (c p a z s o : Bool) :
    (arithmeticFlags before c p a z s o).getLsbD 6 = z ∧
    (arithmeticFlags before c p a z s o).getLsbD 7 = s ∧
    (arithmeticFlags before c p a z s o).getLsbD 11 = o := by
  cases c <;> cases p <;> cases a <;> cases z <;> cases s <;> cases o <;> simp [arithmeticFlags]

private theorem msb_toNat (x : BitVec 32) : x.msb = decide (2 ^ 31 ≤ x.toNat) := by
  rw [BitVec.msb_eq_decide]

set_option linter.unusedSimpArgs false in
/-- SF ≠ OF after a subtraction is signed less-than. -/
theorem signedLess (a b : BitVec 32) :
    ((a - b).msb != ((a.msb != b.msb) && ((a - b).msb != a.msb))) = a.slt b := by
  rw [BitVec.slt, msb_toNat, msb_toNat, msb_toNat, BitVec.toNat_sub,
    BitVec.toInt_eq_toNat_cond, BitVec.toInt_eq_toNat_cond]
  have ha := a.isLt; have hb := b.isLt
  generalize a.toNat = x at *
  generalize b.toNat = y at *
  by_cases h1 : 2 ^ 31 ≤ x <;> by_cases h2 : 2 ^ 31 ≤ y <;>
    by_cases h3 : 2 ^ 31 ≤ (2 ^ 32 - y + x) % 2 ^ 32 <;>
    simp only [h1, h2, h3, decide_true, decide_false, bne_self_eq_false, Bool.bne_false,
      Bool.false_bne, Bool.true_bne, Bool.bne_true, Bool.not_true, Bool.not_false,
      Bool.and_true, Bool.and_false, Bool.true_and, Bool.false_and] <;>
    (symm; simp only [decide_eq_true_eq, decide_eq_false_iff_not]) <;> split <;> split <;> omega

theorem sub_beq_zero (a b : BitVec 32) : (a - b == 0) = (a == b) := by
  by_cases h : a = b
  · subst h; simp
  · have : a - b ≠ 0 := by bv_omega
    rw [beq_false_of_ne h, beq_false_of_ne this]

theorem sle_eq (a b : BitVec 32) : a.sle b = (a == b || a.slt b) := by
  rw [BitVec.sle_eq_decide, BitVec.slt_eq_decide]
  by_cases h : a = b
  · subst h; simp
  · have : a.toInt ≠ b.toInt := fun e => h (BitVec.eq_of_toInt_eq e)
    simp only [beq_false_of_ne h, Bool.false_or, decide_eq_decide]
    omega

theorem slt_flip (a b : BitVec 32) : b.slt a = (!(a == b) && !a.slt b) := by
  rw [BitVec.slt_eq_decide, BitVec.slt_eq_decide]
  by_cases h : a = b
  · subst h; simp
  · have : a.toInt ≠ b.toInt := fun e => h (BitVec.eq_of_toInt_eq e)
    simp only [beq_false_of_ne h, Bool.not_false, Bool.true_and]
    by_cases less : a.toInt < b.toInt
    · simp [less]; omega
    · simp [less]; omega

theorem sle_not (a b : BitVec 32) : b.sle a = !a.slt b := by
  rw [BitVec.sle_eq_decide, BitVec.slt_eq_decide]
  by_cases less : a.toInt < b.toInt
  · simp [less]
  · simp [less]; omega

theorem CmpOp.condition (flags : BitVec 64) (operation : CmpOp) (a b : BitVec 32) :
    condition (subtractFlags flags a b) operation.code = operation.holds a b := by
  cases operation with
  | eq =>
    simp only [Lanius.X86.Machine.condition, subtractFlags, (arithmeticFlags_bits ..).1, sub_beq_zero]
    rfl
  | ne =>
    simp only [Lanius.X86.Machine.condition, subtractFlags, (arithmeticFlags_bits ..).1, sub_beq_zero]
    rfl
  | lt =>
    simp only [Lanius.X86.Machine.condition, subtractFlags, (arithmeticFlags_bits ..).2.1,
      (arithmeticFlags_bits ..).2.2]
    exact signedLess a b
  | le =>
    simp only [Lanius.X86.Machine.condition, subtractFlags, (arithmeticFlags_bits ..).1,
      (arithmeticFlags_bits ..).2.1, (arithmeticFlags_bits ..).2.2, sub_beq_zero]
    show ((a == b) || _) = a.sle b
    rw [signedLess, sle_eq]
  | gt =>
    simp only [Lanius.X86.Machine.condition, subtractFlags, (arithmeticFlags_bits ..).1,
      (arithmeticFlags_bits ..).2.1, (arithmeticFlags_bits ..).2.2, sub_beq_zero]
    show (!(a == b) && _) = b.slt a
    rw [slt_flip, ← signedLess a b]
    generalize ((a.msb != b.msb) && ((a - b).msb != a.msb)) = overflow
    generalize (a - b).msb = sign
    cases sign <;> cases overflow <;> rfl
  | ge =>
    simp only [Lanius.X86.Machine.condition, subtractFlags, (arithmeticFlags_bits ..).2.1,
      (arithmeticFlags_bits ..).2.2]
    show (_ == _) = b.sle a
    rw [sle_not, ← signedLess a b]
    generalize ((a.msb != b.msb) && ((a - b).msb != a.msb)) = overflow
    generalize (a - b).msb = sign
    cases sign <;> cases overflow <;> rfl

end Lanius.Mini
