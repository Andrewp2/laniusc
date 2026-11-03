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

/-- A float literal's digit test, as bounds (`pre_auto` simplifies an `if`'s
condition by `hb_simp`). -/
@[hb_simp] theorem flDigit_eq_true (b : Nat) :
    (Lanius.Mini.flDigit b = true) = (48 ≤ b ∧ b ≤ 57) := by
  simp [Lanius.Mini.flDigit]

theorem flBit_le (x : Bool) : Lanius.Mini.flBit x ≤ 1 := by
  cases x <;> simp [Lanius.Mini.flBit]

theorem flNatHalf_le (n : Nat) : Lanius.Mini.flNatHalf n ≤ n := by
  induction n using Nat.strongRecOn with
  | ind n ih =>
    rw [Lanius.Mini.flNatHalf.eq_def]
    split
    · omega
    · have := ih (n - 2) (by omega)
      omega

theorem flPow2_eq (k : Nat) : Lanius.Mini.flPow2 k = 2 ^ k := by
  induction k with
  | zero => rw [Lanius.Mini.flPow2.eq_def]; simp
  | succ k ih =>
    rw [Lanius.Mini.flPow2.eq_def]
    simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel, ih, Nat.pow_succ]
    omega

/-- A bit list's value is below 2 to its length. -/
theorem flToNat_lt (a : List Bool) : Lanius.Mini.flToNat a < 2 ^ a.length := by
  induction a with
  | nil => simp [Lanius.Mini.flToNat]
  | cons x rest ih =>
    have := flBit_le x
    rw [Lanius.Mini.flToNat, List.length_cons, Nat.pow_succ]
    omega

/-- The highest one bit's position is below the list's length. -/
theorem flLog2_lt : ∀ (a : List Bool) (i : Nat), Lanius.Mini.flLog2 a = some i → i < a.length
  | [], i, h => by simp [Lanius.Mini.flLog2] at h
  | x :: rest, i, h => by
    have ih := flLog2_lt rest
    rw [Lanius.Mini.flLog2] at h
    simp only [List.length_cons]
    cases hr : Lanius.Mini.flLog2 rest with
    | none =>
      rw [hr, Lanius.Mini.flLog2Up.eq_def] at h
      cases x <;> simp [Lanius.Mini.flLowBit] at h
      omega
    | some j =>
      rw [hr, Lanius.Mini.flLog2Up.eq_def] at h
      have := ih j hr
      simp only [Option.some.injEq] at h
      omega

end Lanius.Faithful.SelfPre
