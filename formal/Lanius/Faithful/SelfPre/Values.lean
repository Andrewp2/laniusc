import Lanius.Faithful.SelfPre.HBLib
import Lanius.Faithful.GenB.SelfBModel4
import Lanius.Mini.Reading.FloatBits

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

/-! Value facts `pre_auto` adds (`valueFacts`): `val_F xs` for a call `F xs`,
`vals_F xs v h` for a hypothesis `h : F xs = some v`. -/

theorem val_flLog2Or0 (a : List Bool) : Lanius.Mini.flLog2Or0 a ≤ hb a := by
  have := length_le_hb a
  unfold Lanius.Mini.flLog2Or0
  split
  · omega
  · rename_i i h
    have := flLog2_lt a i h
    omega

theorem vals_flLog2 (a : List Bool) (i : Nat) (h : Lanius.Mini.flLog2 a = some i) : i < hb a := by
  have := flLog2_lt a i h
  have := length_le_hb a
  omega

theorem val_flBit (x : Bool) : Lanius.Mini.flBit x ≤ 1 := flBit_le x

/-- Rounding up adds at most one. -/
theorem val_flRoundUp (up : Bool) (q : List Bool) :
    Lanius.Mini.flToNat (Lanius.Mini.flRoundUp up q) ≤ Lanius.Mini.flToNat q + 1 := by
  unfold Lanius.Mini.flRoundUp
  split
  · rw [Lanius.Mini.Reading.flToNat_eq, Lanius.Mini.Reading.flToNat_eq, Lanius.Mini.Reading.flAdd_val]
    simp
  · omega

/-- `N * 2^a < D * 2^b` scales to `N * 2^P < D * 2^R` when `P + b ≤ R + a`. -/
theorem ratio_scale {N D a b P R : Nat} (h : N * 2 ^ a < D * 2 ^ b) (e : P + b ≤ R + a) :
    N * 2 ^ P < D * 2 ^ R := by
  have h1 : N * 2 ^ a * 2 ^ P < D * 2 ^ b * 2 ^ P := Nat.mul_lt_mul_of_pos_right h (Nat.two_pow_pos P)
  have h2 : D * 2 ^ b * 2 ^ P ≤ D * 2 ^ R * 2 ^ a := by
    rw [Nat.mul_assoc, Nat.mul_assoc, ← Nat.pow_add, ← Nat.pow_add]
    exact Nat.mul_le_mul_left _ (Nat.pow_le_pow_right (by omega) (by omega))
  have h3 : N * 2 ^ P * 2 ^ a < D * 2 ^ R * 2 ^ a := by
    rw [Nat.mul_right_comm]
    exact Nat.lt_of_lt_of_le h1 h2
  exact Nat.lt_of_mul_lt_mul_right h3

/-- `flRound`'s quotient on naturals: the unit `U` puts `N / D` scaled by
`2^(B + f - 1 - U)` below `2^(f + 1)` (`c` corrects `log2 N - log2 D` down by
one when the ratio is below `2^(log2 N - log2 D)`; at `U = 0` the scale is
smaller still). -/
theorem roundQ_lt (B f N D c : Nat) (hB : 1 ≤ B) (hD : 0 < D)
    (hc : c = if D * 2 ^ (Nat.log2 N - Nat.log2 D) ≤ N * 2 ^ (Nat.log2 D - Nat.log2 N) then 0 else 1) :
    N * 2 ^ (B + f - 1 - (Nat.log2 N + B - (c + 1) - Nat.log2 D)) /
      (D * 2 ^ (Nat.log2 N + B - (c + 1) - Nat.log2 D - (B + f - 1))) < 2 ^ (f + 1) := by
  rw [Nat.div_lt_iff_lt_mul (Nat.mul_pos hD (Nat.two_pow_pos _)), Nat.mul_comm (2 ^ (f + 1)),
    Nat.mul_assoc, ← Nat.pow_add]
  have hN : N < 2 ^ (Nat.log2 N + 1) := Nat.lt_log2_self
  have hDl : 2 ^ (Nat.log2 D) ≤ D := Nat.log2_self_le (by omega)
  split at hc
  · subst hc
    have base : N * 2 ^ (Nat.log2 D) < D * 2 ^ (Nat.log2 N + 1) := by
      calc N * 2 ^ (Nat.log2 D) ≤ N * D := Nat.mul_le_mul_left _ hDl
        _ < 2 ^ (Nat.log2 N + 1) * D := Nat.mul_lt_mul_of_pos_right hN hD
        _ = D * 2 ^ (Nat.log2 N + 1) := Nat.mul_comm _ _
    exact ratio_scale base (by omega)
  · subst hc
    rename_i h
    exact ratio_scale (Nat.lt_of_not_le h) (by omega)

/-- `flRound`'s quotient (before rounding up) is below `2^(f + 1)`, as
`Pre_fl_round` spells it. -/
theorem flRound_q_lt (ew f : Nat) (num den : List Bool) (hd : 0 < Lanius.Mini.flToNat den)
    (hB : 1 ≤ Lanius.Mini.flPow2 (ew - 1) - 1) :
    Lanius.Mini.flToNat (Lanius.Mini.flDivmod (Lanius.Mini.flShl num (Lanius.Mini.flSat ((((Lanius.Mini.flPow2 ((ew - 1))) - 1) + f) - 1) (Lanius.Mini.flSat ((((Lanius.Mini.flLog2Or0 num) + ((Lanius.Mini.flPow2 ((ew - 1))) - 1)) - ((Lanius.Mini.flBit ((!(Lanius.Mini.flRatioOk ((Lanius.Mini.flLog2Or0 num)) ((Lanius.Mini.flLog2Or0 den)) num den)))) + 1))) ((Lanius.Mini.flLog2Or0 den))))) (Lanius.Mini.flShl den (Lanius.Mini.flSat (Lanius.Mini.flSat ((((Lanius.Mini.flLog2Or0 num) + ((Lanius.Mini.flPow2 ((ew - 1))) - 1)) - ((Lanius.Mini.flBit ((!(Lanius.Mini.flRatioOk ((Lanius.Mini.flLog2Or0 num)) ((Lanius.Mini.flLog2Or0 den)) num den)))) + 1))) ((Lanius.Mini.flLog2Or0 den))) ((((Lanius.Mini.flPow2 ((ew - 1))) - 1) + f) - 1)))).q < 2 ^ (f + 1) := by
  rw [Lanius.Mini.Reading.flToNat_eq] at hd ⊢
  generalize Lanius.Mini.flPow2 (ew - 1) - 1 = B at hB ⊢
  have hbit : ∀ p : Prop, ∀ [Decidable p], Lanius.Mini.flBit (!decide p) = if p then 0 else 1 := by
    intro p _; by_cases h : p <;> simp [h, Lanius.Mini.flBit]
  simp only [Lanius.Mini.Reading.flSat_eq, Lanius.Mini.Reading.flLog2Or0_eq, Lanius.Mini.Reading.flRatioOk_eq, hbit]
  generalize hc : (if Lanius.Mini.Reading.bval den * 2 ^ (Nat.log2 (Lanius.Mini.Reading.bval num) - Nat.log2 (Lanius.Mini.Reading.bval den)) ≤
    Lanius.Mini.Reading.bval num * 2 ^ (Nat.log2 (Lanius.Mini.Reading.bval den) - Nat.log2 (Lanius.Mini.Reading.bval num)) then 0 else 1) = c
  have dpos : 0 < Lanius.Mini.Reading.bval (Lanius.Mini.flShl den (Nat.log2 (Lanius.Mini.Reading.bval num) + B - (c + 1) - Nat.log2 (Lanius.Mini.Reading.bval den) - (B + f - 1))) := by
    rw [Lanius.Mini.Reading.flShl_val]; exact Nat.mul_pos hd (Nat.two_pow_pos _)
  rw [(Lanius.Mini.Reading.flDivmod_val dpos _).1, Lanius.Mini.Reading.flShl_val, Lanius.Mini.Reading.flShl_val]
  exact roundQ_lt B f _ _ c hB hd hc.symm

theorem flTimes10_one_pos (k : Nat) : 0 < Lanius.Mini.flToNat (Lanius.Mini.flTimes10 [true] k) := by
  rw [Lanius.Mini.Reading.flToNat_eq, Lanius.Mini.Reading.flTimes10_val]
  simp only [Lanius.Mini.Reading.bval_cons, Lanius.Mini.Reading.bval_nil, if_true]
  exact Nat.mul_pos (by omega) (Nat.pow_pos (by omega))

theorem val_kid (c : Lanius.Mini.CTree) (i : Nat) : hb (Lanius.Mini.kid c i) ≤ hb c := by
  unfold Lanius.Mini.kid
  rw [List.getD_eq_getElem?_getD]
  cases c with
  | leaf t => simp [Lanius.Mini.kidsOf, Lanius.Mini.noToken]
  | node p kids =>
    simp only [Lanius.Mini.kidsOf, hb_CTree_node]
    cases h : kids[i]? with
    | none => simp [Lanius.Mini.noToken]
    | some k =>
      simp only [Option.getD_some]
      exact Nat.le_of_lt (hb_le_of_mem (List.mem_of_getElem? h))

theorem val_kidToken (c : Lanius.Mini.CTree) (i : Nat) : hb (Lanius.Mini.kidToken c i) ≤ hb c := by
  have := val_kid c i
  unfold Lanius.Mini.kidToken Lanius.Mini.leafToken
  split
  · rename_i t h
    rw [h] at this
    simpa using this
  · simp [Lanius.Mini.noToken]

theorem val_start (t : Lanius.Mini.Token) : t.start ≤ hb t := hb_le_Token_start t

theorem position_lt : ∀ (l : List (List Nat)) (name : List Nat) (k j : Nat),
    Lanius.Mini.position l name k = some j → j < k + l.length
  | [], name, k, j, h => by simp [Lanius.Mini.position] at h
  | n :: rest, name, k, j, h => by
    unfold Lanius.Mini.position at h
    split at h
    · injection h with h
      subst h
      simp
    · have := position_lt rest name (k + 1) j h
      simp only [List.length_cons]
      omega

/-- A field index is below the environment's height. -/
theorem vals_fieldIndex (env : Lanius.Mini.FrontEnv) (t : Lanius.Mini.Ty) (name : List Nat) (j : Nat)
    (h : Lanius.Mini.fieldIndex env t name = some j) : j < hb env := by
  cases t <;> simp [Lanius.Mini.fieldIndex] at h
  rename_i d args
  unfold Lanius.Mini.fieldIn at h
  split at h
  · contradiction
  · rename_i e he
    have h1 := position_lt _ _ _ _ h
    have h2 := length_le_hb e.fields
    have h3 := hb_le_TypeDecl_fields e
    have h4 := hb_le_of_mem (List.mem_of_getElem? he)
    have h5 := hb_le_Decls_types env.decls
    have h6 := hb_le_FrontEnv_decls env
    omega

end Lanius.Faithful.SelfPre
