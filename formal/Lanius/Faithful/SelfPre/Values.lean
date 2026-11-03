import Lanius.Faithful.SelfPre.HBLib
import Lanius.Faithful.GenB.SelfBModel4

/-! # Values of the self compiler's numeric functions (F14)

Heights count numbers as 0, so a precondition that a number does not wrap
needs the number's value bounded another way: these lemmas bound the values
of the front end's numeric helpers, for the hand proofs in
`tools/pre_certs.py` (`PRE_HAND`). -/

namespace Lanius.Faithful.SelfPre

/-- A literal's base prefix (`0x`, `0o`, `0b`) is 16, 8 or 2. -/
theorem litBase_cases {p v : Nat} (h : Lanius.Mini.litBase p = some v) :
    v = 2 ∨ v = 8 ∨ v = 16 := by
  unfold Lanius.Mini.litBase at h
  split at h
  · cases h; simp
  · split at h
    · cases h; simp
    · split at h
      · cases h; simp
      · cases h

/-- A digit is below its base. -/
theorem baseDigit_lt {c base d : Nat} (h : Lanius.Mini.baseDigit c base = some d) : d < base := by
  unfold Lanius.Mini.baseDigit Lanius.Mini.digitBelow at h
  split at h
  · split at h
    · cases h; assumption
    · cases h
  · split at h
    · split at h
      · cases h; assumption
      · cases h
    · split at h
      · split at h
        · cases h; assumption
        · cases h
      · cases h

end Lanius.Faithful.SelfPre
