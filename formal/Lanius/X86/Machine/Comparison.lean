import Lanius.X86.Machine.Equality

namespace Lanius.X86.Machine

theorem arithmeticFlags_signed (before : BitVec 64) (carry parity auxiliary zero sign overflow : Bool) :
    condition (arithmeticFlags before carry parity auxiliary zero sign overflow) 12 = (sign != overflow) := by
  change ((arithmeticFlags before carry parity auxiliary zero sign overflow).getLsbD 7 !=
    (arithmeticFlags before carry parity auxiliary zero sign overflow).getLsbD 11) = _
  cases carry <;> cases parity <;> cases auxiliary <;> cases zero <;> cases sign <;> cases overflow <;>
    simp [arithmeticFlags]

/-- Correct signed ordering even when subtraction overflows: SF alone is
insufficient; SF xor OF recovers the ordering of the original operands. -/
theorem compare_less (before : BitVec 64) (left right : BitVec width) :
    condition (subtractFlags before left right) 12 = decide (left.toInt < right.toInt) := by
  unfold subtractFlags
  rw [arithmeticFlags_signed]
  by_cases same : left.msb = right.msb
  · have noOverflow : ¬ left.ssubOverflow right := by
      have := BitVec.le_toInt left
      have := BitVec.le_toInt right
      have := BitVec.toInt_lt (x := left)
      have := BitVec.toInt_lt (x := right)
      simp only [BitVec.msb_eq_toInt, decide_eq_decide] at same
      simp only [BitVec.ssubOverflow, Bool.or_eq_true, decide_eq_true_eq]
      omega
    simp only [same, bne_self_eq_false, Bool.false_and, Bool.bne_false]
    rw [BitVec.msb_eq_toInt, BitVec.toInt_sub_of_not_ssubOverflow noOverflow]
    apply Bool.eq_iff_iff.mpr
    simp only [decide_eq_true_eq]
    omega
  · have signs := same
    simp only [BitVec.msb_eq_toInt, decide_eq_decide] at signs
    cases l : left.msb <;> cases r : right.msb <;> simp_all [BitVec.msb_eq_toInt] <;> omega

theorem compare_greaterEqual (before : BitVec 64) (left right : BitVec width) :
    condition (subtractFlags before left right) 13 = decide (right.toInt ≤ left.toInt) := by
  have complement (flags : BitVec 64) : condition flags 13 = !condition flags 12 := by
    change (_ == _) = !(_ != _)
    cases flags.getLsbD 7 <;> cases flags.getLsbD 11 <;> rfl
  rw [complement]
  rw [compare_less]
  apply Bool.eq_iff_iff.mpr
  simp only [Bool.not_eq_true', decide_eq_false_iff_not, decide_eq_true_eq]
  omega

theorem compare_lessEqual (before : BitVec 64) (left right : BitVec width) :
    condition (subtractFlags before left right) 14 = decide (left.toInt ≤ right.toInt) := by
  change (condition (subtractFlags before left right) 4 || condition (subtractFlags before left right) 12) = _
  rw [compare_equal, compare_less]
  apply Bool.eq_iff_iff.mpr
  simp only [Bool.or_eq_true, decide_eq_true_eq, ← BitVec.toInt_inj]
  omega

theorem compare_greater (before : BitVec 64) (left right : BitVec width) :
    condition (subtractFlags before left right) 15 = decide (right.toInt < left.toInt) := by
  change ((!condition (subtractFlags before left right) 4) && condition (subtractFlags before left right) 13) = _
  rw [compare_equal, compare_greaterEqual]
  apply Bool.eq_iff_iff.mpr
  simp only [Bool.and_eq_true, Bool.not_eq_true', decide_eq_false_iff_not, decide_eq_true_eq, ← BitVec.toInt_inj]
  omega

end Lanius.X86.Machine
