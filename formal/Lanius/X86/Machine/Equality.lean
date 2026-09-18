import Lanius.X86.Machine.Flags

namespace Lanius.X86.Machine

theorem arithmeticFlags_zero (before : BitVec 64)
    (carry parity auxiliary zero sign overflow : Bool) :
    (arithmeticFlags before carry parity auxiliary zero sign overflow).getLsbD 6 = zero := by
  cases carry <;> cases parity <;> cases auxiliary <;> cases zero <;> cases sign <;>
    cases overflow <;> simp [arithmeticFlags]

/-- Full-width equality observes the zero flag, independently of numerical
ordering. This is the comparison a relocated raw pointer can preserve. -/
theorem compare_equal (before : BitVec 64) (left right : BitVec width) :
    condition (subtractFlags before left right) 4 = decide (left = right) := by
  change (arithmeticFlags before _ _ _ _ _ _).getLsbD 6 = _
  rw [arithmeticFlags_zero]
  apply Bool.eq_iff_iff.mpr
  simp [BitVec.sub_eq_iff_eq_add]

theorem compare_notEqual (before : BitVec 64) (left right : BitVec width) :
    condition (subtractFlags before left right) 5 = decide (left ≠ right) := by
  change Bool.not (condition (subtractFlags before left right) 4) = _
  rw [compare_equal]
  simp

end Lanius.X86.Machine
