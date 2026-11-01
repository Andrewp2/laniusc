import Lanius.Mini.Reading.Types
import Lanius.IEEE

/-! # The reading: a float literal's rounding

The front end rounds a decimal literal `m * 10^e` to binary32 and binary64
on naturals held as bit lists, least significant bit first (`flAdd`,
`flSub`, `flDivmod`, ...: `formal/lani/mini/frontend.lani`). This file
proves that `flDecimal` computes `Lanius.IEEE.Format.ofDecimal`, the trusted
specification of the nearest pattern. -/

namespace Lanius.Mini.Reading

open Lanius.Mini Lanius.IEEE

/-- A bit list's value, least significant bit first. -/
def bval : List Bool → Nat
  | [] => 0
  | b :: r => (if b then 1 else 0) + 2 * bval r

@[simp] theorem bval_nil : bval [] = 0 := rfl
@[simp] theorem bval_cons (b : Bool) (r : List Bool) : bval (b :: r) = (if b then 1 else 0) + 2 * bval r := rfl

/-! ## Addition, comparison, subtraction -/

theorem flAdd_val : ∀ (a b : List Bool) (c : Bool),
    bval (flAdd a b c) = bval a + bval b + (if c then 1 else 0)
  | [], [], c => by cases c <;> simp [flAdd, flCarryOut]
  | [], y :: rb, c => by
    have ih := flAdd_val [] rb (y && c)
    simp only [flAdd, bval_cons, ih, bval_nil]
    cases y <;> cases c <;> simp [flXor] <;> omega
  | x :: ra, [], c => by
    have ih := flAdd_val ra [] (x && c)
    simp only [flAdd, bval_cons, ih, bval_nil]
    cases x <;> cases c <;> simp [flXor] <;> omega
  | x :: ra, y :: rb, c => by
    have ih := flAdd_val ra rb (flCarry x y c)
    simp only [flAdd, bval_cons, ih]
    cases x <;> cases y <;> cases c <;> simp [flXor, flCarry] <;> omega

theorem flLess_iff : ∀ (a b : List Bool) (c : Bool),
    flLess a b c = decide (bval a < bval b + (if c then 1 else 0))
  | [], [], c => by cases c <;> simp [flLess]
  | [], y :: rb, c => by
    have ih := flLess_iff [] rb (flBorrowBit false y c)
    simp only [flLess, ih, bval_cons, bval_nil]
    cases y <;> cases c <;> simp [flBorrowBit] <;> omega
  | x :: ra, [], c => by
    have ih := flLess_iff ra [] (flBorrowBit x false c)
    simp only [flLess, ih, bval_cons, bval_nil]
    cases x <;> cases c <;> simp [flBorrowBit] <;> omega
  | x :: ra, y :: rb, c => by
    have ih := flLess_iff ra rb (flBorrowBit x y c)
    simp only [flLess, ih, bval_cons]
    cases x <;> cases y <;> cases c <;> simp [flBorrowBit] <;> omega

theorem flSub_val : ∀ (a b : List Bool) (c : Bool), bval b + (if c then 1 else 0) ≤ bval a →
    bval (flSub a b c) = bval a - bval b - (if c then 1 else 0)
  | [], b, c, h => by simp only [flSub, bval_nil] at h ⊢; omega
  | x :: ra, [], c, h => by
    have ih := flSub_val ra [] (flBorrowBit x false c)
    simp only [flSub, bval_cons, bval_nil] at h ih ⊢
    cases x <;> cases c <;> simp [flXor, flBorrowBit] at h ih ⊢ <;> omega
  | x :: ra, y :: rb, c, h => by
    have ih := flSub_val ra rb (flBorrowBit x y c)
    simp only [flSub, bval_cons] at h ih ⊢
    cases x <;> cases y <;> cases c <;> simp [flXor, flBorrowBit] at h ih ⊢ <;> omega

/-! ## Shifts, tens, small numbers -/

theorem flShl_val (a : List Bool) : ∀ k, bval (flShl a k) = bval a * 2 ^ k
  | 0 => by simp [flShl]
  | k + 1 => by
    rw [flShl]
    simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel, bval_cons, flShl_val a k, Nat.pow_succ]
    simp only [Bool.false_eq_true, if_false, Nat.zero_add]
    rw [Nat.mul_comm (2 ^ k) 2, Nat.mul_left_comm]

theorem flMul10_val (a : List Bool) : bval (flMul10 a) = bval a * 10 := by
  simp only [flMul10, flAdd_val, bval_cons, Bool.false_eq_true, if_false, Nat.zero_add, Nat.add_zero]
  omega

theorem flTimes10_val (a : List Bool) : ∀ k, bval (flTimes10 a k) = bval a * 10 ^ k
  | 0 => by simp [flTimes10]
  | k + 1 => by
    rw [flTimes10]
    simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel, flMul10_val, flTimes10_val a k, Nat.pow_succ]
    rw [Nat.mul_assoc]

theorem flNatHalf_eq (n : Nat) : flNatHalf n = n / 2 := by
  induction n using Nat.strongRecOn with
  | _ n ih =>
    rw [flNatHalf]
    by_cases h : n < 2
    · simp only [h, if_true]; omega
    · simp only [h, if_false, ih (n - 2) (by omega)]; omega

theorem flNatOdd_eq (n : Nat) : flNatOdd n = decide (n % 2 = 1) := by
  induction n using Nat.strongRecOn with
  | _ n ih =>
    rw [flNatOdd]
    by_cases h : n < 2
    · simp only [h, if_true]
      by_cases h1 : n = 1
      · subst h1; rfl
      · have : n = 0 := by omega
        subst this; rfl
    · simp only [h, if_false, ih (n - 2) (by omega)]
      have : (n - 2) % 2 = n % 2 := by omega
      rw [this]

theorem flOfNat_val : ∀ (n k : Nat), bval (flOfNat n k) = n % 2 ^ k
  | n, 0 => by simp [flOfNat, Nat.mod_one]
  | n, k + 1 => by
    rw [flOfNat]
    simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel, bval_cons, flNatHalf_eq, flNatOdd_eq,
      flOfNat_val (n / 2) k]
    rw [Nat.pow_succ, Nat.mul_comm (2 ^ k) 2, Nat.mod_mul]
    have := Nat.mod_two_eq_zero_or_one n
    rcases this with h | h <;> simp [h]

theorem flPow2_eq : ∀ k, flPow2 k = 2 ^ k
  | 0 => by simp [flPow2]
  | k + 1 => by
    rw [flPow2]
    simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel, flPow2_eq k, Nat.pow_succ]
    omega

theorem flToNat_eq : ∀ a, flToNat a = bval a
  | [] => rfl
  | x :: rest => by
    simp only [flToNat, flToNat_eq rest, bval_cons, flBit]

theorem flSat_eq (a b : Nat) : flSat a b = a - b := by
  unfold flSat; split <;> omega

theorem flOdd_eq (a : List Bool) : flOdd a = (bval a % 2 == 1) := by
  cases a with
  | nil => rfl
  | cons x rest => cases x <;> simp [flOdd] <;> omega

/-! ## The highest bit -/

theorem log2_double (x : Bool) (v : Nat) (pos : 0 < v) :
    Nat.log2 ((if x then 1 else 0) + 2 * v) = Nat.log2 v + 1 := by
  rw [Nat.log2_def, if_pos (by split <;> omega)]
  congr 2
  split <;> omega

theorem flLog2_eq : ∀ a, flLog2 a = if bval a = 0 then none else some (Nat.log2 (bval a))
  | [] => rfl
  | x :: rest => by
    simp only [flLog2, flLog2_eq rest, bval_cons]
    by_cases z : bval rest = 0
    · have l1 : Nat.log2 1 = 0 := by rw [Nat.log2_def]; rfl
      simp only [z, if_true, Nat.mul_zero, Nat.add_zero]
      cases x <;> simp [flLog2Up, flLowBit, l1]
    · simp only [z, if_false, flLog2Up]
      have nz : ¬((if x = true then 1 else 0) + 2 * bval rest = 0) := by split <;> omega
      simp only [nz, if_false, log2_double x _ (Nat.pos_of_ne_zero z)]

theorem flLog2Or0_eq (a : List Bool) : flLog2Or0 a = Nat.log2 (bval a) := by
  unfold flLog2Or0
  rw [flLog2_eq]
  by_cases z : bval a = 0
  · simp [z]
  · simp [z]

/-! ## Division -/

theorem flDivmod_val {d : List Bool} (pos : 0 < bval d) : ∀ n,
    bval (flDivmod n d).q = bval n / bval d ∧ bval (flDivmod n d).r = bval n % bval d
  | [] => by simp [flDivmod]
  | x :: rest => by
    obtain ⟨hq, hr⟩ := flDivmod_val pos rest
    simp only [flDivmod, flDivStep]
    have lt := Nat.mod_lt (bval rest) pos
    have dm := Nat.div_add_mod (bval rest) (bval d)
    have xb : (if x = true then 1 else 0) ≤ 1 := by split <;> omega
    rw [flLess_iff]
    simp only [bval_cons, hr, Bool.false_eq_true, if_false, Nat.add_zero]
    by_cases small : (if x then 1 else 0) + 2 * (bval rest % bval d) < bval d
    · rw [if_pos (by simpa using small)]
      simp only [bval_cons, hq, hr, Bool.false_eq_true, if_false, Nat.zero_add]
      have e : bval d * (2 * (bval rest / bval d)) = 2 * (bval d * (bval rest / bval d)) := Nat.mul_left_comm _ _ _
      obtain ⟨h1, h2⟩ := (Nat.div_mod_unique (c := (if x then 1 else 0) + 2 * (bval rest % bval d))
        (a := (if x then 1 else 0) + 2 * bval rest) (d := 2 * (bval rest / bval d)) pos).2 ⟨by rw [e]; omega, small⟩
      exact ⟨h1.symm, h2.symm⟩
    · rw [if_neg (by simpa using small)]
      simp only [bval_cons, hq, if_true]
      rw [flSub_val _ _ _ (by simp only [bval_cons, hr, Bool.false_eq_true, if_false]; omega)]
      simp only [bval_cons, hr, Bool.false_eq_true, if_false, Nat.sub_zero]
      have e : bval d * (1 + 2 * (bval rest / bval d)) = bval d + 2 * (bval d * (bval rest / bval d)) := by
        rw [Nat.mul_add, Nat.mul_one, Nat.mul_left_comm]
      obtain ⟨h1, h2⟩ := (Nat.div_mod_unique (c := (if x then 1 else 0) + 2 * (bval rest % bval d) - bval d)
        (a := (if x then 1 else 0) + 2 * bval rest) (d := 1 + 2 * (bval rest / bval d)) pos).2 ⟨by rw [e]; omega, by omega⟩
      exact ⟨h1.symm, h2.symm⟩

/-! ## Rounding -/

theorem bias_pos (F : Format) (he : 2 ≤ F.e) : 1 ≤ F.bias := by
  unfold Format.bias
  have : 2 ^ 1 ≤ 2 ^ (F.e - 1) := Nat.pow_le_pow_right (by omega) (by omega)
  simp at this
  omega

theorem flRatioOk_eq (L M : Nat) (num den : List Bool) :
    flRatioOk L M num den = decide (bval den * 2 ^ (L - M) ≤ bval num * 2 ^ (M - L)) := by
  simp only [flRatioOk, flLess_iff, flShl_val, flSat_eq, Bool.false_eq_true, if_false, Nat.add_zero,
    ← decide_not, Nat.not_lt]

/-- `roundRatio false num den 0` on naturals: the ratio test's correction
`c`, the biased unit `U = (u - uMin).toNat` and the scale `2 ^ (k0 - U)`
(`k0 = bias + f - 1`), as `flRound` computes them. -/
def roundNat (F : Format) (N D : Nat) : Nat :=
  let c := if D * 2 ^ (Nat.log2 N - Nat.log2 D) ≤ N * 2 ^ (Nat.log2 D - Nat.log2 N) then 0 else 1
  let U := Nat.log2 N + F.bias - (c + 1) - Nat.log2 D
  let n := N * 2 ^ (F.bias + F.f - 1 - U)
  let d := D * 2 ^ (U - (F.bias + F.f - 1))
  let q := if d < 2 * (n % d) || (2 * (n % d) == d && n / d % 2 == 1) then n / d + 1 else n / d
  if F.infBits ≤ U * 2 ^ F.f + q then F.infBits else U * 2 ^ F.f + q

theorem floorLog2Ratio_nat (N D : Nat) : floorLog2Ratio N D =
    (Nat.log2 N : Int) - Nat.log2 D -
      ((if D * 2 ^ (Nat.log2 N - Nat.log2 D) ≤ N * 2 ^ (Nat.log2 D - Nat.log2 N) then 0 else 1 : Nat) : Int) := by
  unfold floorLog2Ratio
  have t1 : ((Nat.log2 N : Int) - (Nat.log2 D : Int)).toNat = Nat.log2 N - Nat.log2 D := by omega
  have t2 : (-((Nat.log2 N : Int) - (Nat.log2 D : Int))).toNat = Nat.log2 D - Nat.log2 N := by omega
  simp only [t1, t2]
  split <;> simp

theorem roundRatio_nat (F : Format) (b1 : 1 ≤ F.bias) (N D : Nat) :
    F.roundRatio false N D 0 = roundNat F N D := by
  unfold Format.roundRatio roundNat
  simp only [floorLog2Ratio_nat, Bool.false_eq_true, if_false]
  have c1 : (if D * 2 ^ (Nat.log2 N - Nat.log2 D) ≤ N * 2 ^ (Nat.log2 D - Nat.log2 N) then 0 else 1) ≤ 1 := by
    split <;> omega
  have hu : (max F.uMin ((Nat.log2 N : Int) - Nat.log2 D -
      ((if D * 2 ^ (Nat.log2 N - Nat.log2 D) ≤ N * 2 ^ (Nat.log2 D - Nat.log2 N) then 0 else 1 : Nat) : Int) + 0 - F.f)
      - F.uMin).toNat =
      Nat.log2 N + F.bias - ((if D * 2 ^ (Nat.log2 N - Nat.log2 D) ≤ N * 2 ^ (Nat.log2 D - Nat.log2 N) then 0 else 1) + 1) -
        Nat.log2 D := by
    unfold Format.uMin; omega
  have hk : (0 - max F.uMin ((Nat.log2 N : Int) - Nat.log2 D -
      ((if D * 2 ^ (Nat.log2 N - Nat.log2 D) ≤ N * 2 ^ (Nat.log2 D - Nat.log2 N) then 0 else 1 : Nat) : Int) + 0 - F.f)).toNat =
      F.bias + F.f - 1 - (Nat.log2 N + F.bias -
        ((if D * 2 ^ (Nat.log2 N - Nat.log2 D) ≤ N * 2 ^ (Nat.log2 D - Nat.log2 N) then 0 else 1) + 1) - Nat.log2 D) := by
    unfold Format.uMin; omega
  have hk' : (-(0 - max F.uMin ((Nat.log2 N : Int) - Nat.log2 D -
      ((if D * 2 ^ (Nat.log2 N - Nat.log2 D) ≤ N * 2 ^ (Nat.log2 D - Nat.log2 N) then 0 else 1 : Nat) : Int) + 0 - F.f))).toNat =
      (Nat.log2 N + F.bias -
        ((if D * 2 ^ (Nat.log2 N - Nat.log2 D) ≤ N * 2 ^ (Nat.log2 D - Nat.log2 N) then 0 else 1) + 1) - Nat.log2 D) -
        (F.bias + F.f - 1) := by
    unfold Format.uMin; omega
  simp only [hu, hk, hk']

/-- `flRound` is `roundRatio` of a positive `num / den` (sign `+`, scale 1). -/
theorem flRound_eq (F : Format) (he : 2 ≤ F.e) {num den : List Bool} (hn : 0 < bval num) (hd : 0 < bval den) :
    flRound F.e F.f num den = F.roundRatio false (bval num) (bval den) 0 := by
  have b1 := bias_pos F he
  rw [roundRatio_nat F b1]
  have hb : flPow2 (F.e - 1) - 1 = F.bias := by rw [flPow2_eq]; rfl
  have hinf : (flPow2 F.e - 1) * flPow2 F.f = F.infBits := by rw [flPow2_eq, flPow2_eq]; rfl
  unfold roundNat flRound
  simp only [hb, hinf, flLog2Or0_eq, flSat_eq, flRatioOk_eq, flToNat_eq]
  simp only [flPow2_eq]
  have hbit : ∀ p : Prop, ∀ [Decidable p], flBit (!decide p) = if p then 0 else 1 := by
    intro p _; by_cases h : p <;> simp [h, flBit]
  simp only [hbit]
  generalize (if bval den * 2 ^ (Nat.log2 (bval num) - Nat.log2 (bval den)) ≤
    bval num * 2 ^ (Nat.log2 (bval den) - Nat.log2 (bval num)) then 0 else 1) = c
  generalize Nat.log2 (bval num) + F.bias - (c + 1) - Nat.log2 (bval den) = U
  have dpos : 0 < bval (flShl den (U - (F.bias + F.f - 1))) := by
    rw [flShl_val]; exact Nat.mul_pos hd (Nat.two_pow_pos _)
  obtain ⟨hq, hr⟩ := flDivmod_val dpos (flShl num (F.bias + F.f - 1 - U))
  generalize flDivmod (flShl num (F.bias + F.f - 1 - U)) (flShl den (U - (F.bias + F.f - 1))) = s at hq hr ⊢
  have hdd := flShl_val den (U - (F.bias + F.f - 1))
  have hnn := flShl_val num (F.bias + F.f - 1 - U)
  generalize flShl den (U - (F.bias + F.f - 1)) = dl at hq hr hdd dpos ⊢
  generalize flShl num (F.bias + F.f - 1 - U) = nl at hq hr hnn ⊢
  rw [hdd] at hq hr dpos
  rw [hnn] at hq hr
  generalize bval num * 2 ^ (F.bias + F.f - 1 - U) = n at hq hr ⊢
  generalize bval den * 2 ^ (U - (F.bias + F.f - 1)) = d at hq hr dpos hdd ⊢
  have hup : (flLess dl (false :: s.r) false ||
      !flLess (false :: s.r) dl false && !flLess dl (false :: s.r) false && flOdd s.q) =
      (d < 2 * (n % d) || (2 * (n % d) == d && n / d % 2 == 1)) := by
    simp only [flLess_iff, hdd, bval_cons, hr, flOdd_eq, hq, Bool.false_eq_true, if_false, Nat.zero_add, Nat.add_zero]
    cases h1 : decide (d < 2 * (n % d)) <;> cases h2 : decide (2 * (n % d) < d) <;>
      cases h3 : (n / d % 2 == 1) <;> simp_all <;> omega
  simp only [hup]
  have hq' : bval (flRoundUp (d < 2 * (n % d) || (2 * (n % d) == d && n / d % 2 == 1)) s.q) =
      (if (d < 2 * (n % d) || (2 * (n % d) == d && n / d % 2 == 1)) = true then n / d + 1 else n / d) := by
    unfold flRoundUp
    split <;> simp_all [flAdd_val]
  simp only [hq']
  split
  · rename_i big
    have : F.infBits ≤ U * 2 ^ F.f := by
      unfold Format.infBits; exact Nat.mul_le_mul_right _ big
    rw [if_pos (by split <;> omega)]
  · rfl

/-- `flDecimal` is `ofDecimal` of `m * 10^(±mag)`. -/
theorem flDecimal_eq (F : Format) (he : 2 ≤ F.e) (m : List Bool) (neg : Bool) (mag : Nat) :
    flDecimal F.e F.f m neg mag = F.ofDecimal (bval m) (if neg then -(mag : Int) else mag) := by
  have hinf : (flPow2 F.e - 1) * flPow2 F.f = F.infBits := by rw [flPow2_eq, flPow2_eq]; rfl
  unfold flDecimal Format.ofDecimal
  rw [flLog2_eq]
  by_cases z : bval m = 0
  · simp [z]
  · simp only [z, if_false, beq_iff_eq]
    unfold flDecimalAt
    have mpos : 0 < bval m := Nat.pos_of_ne_zero z
    cases neg with
    | false =>
      simp only [Bool.not_false, Bool.true_and, Bool.false_and, Bool.false_eq_true, if_false, hinf,
        decide_eq_true_eq]
      by_cases big : 400 < mag
      · have : (400 : Int) < (mag : Int) := by omega
        simp [big, this]
      · have nbig : ¬(400 : Int) < (mag : Int) := by omega
        have nsmall : ¬((mag : Int) + (Nat.log2 (bval m) : Int) + 1 < -400) := by omega
        simp only [big, nbig, nsmall, if_false, if_true, show (0 : Int) ≤ mag from by omega]
        rw [flRound_eq F he (by rw [flTimes10_val]; exact Nat.mul_pos mpos (Nat.pos_of_ne_zero (by simp)))
          (by simp)]
        simp [flTimes10_val]
    | true =>
      simp only [Bool.not_true, Bool.false_and, Bool.true_and, Bool.false_eq_true, if_false, if_true,
        decide_eq_true_eq]
      have nbig : ¬(400 : Int) < -(mag : Int) := by omega
      simp only [nbig, if_false]
      by_cases small : Nat.log2 (bval m) + 1 + 400 < mag
      · have : -(mag : Int) + (Nat.log2 (bval m) : Int) + 1 < -400 := by omega
        simp [small, this]
      · have : ¬(-(mag : Int) + (Nat.log2 (bval m) : Int) + 1 < -400) := by omega
        simp only [small, this, if_false]
        rw [flRound_eq F he mpos (by rw [flTimes10_val]; exact Nat.mul_pos (by simp) (Nat.pos_of_ne_zero (by simp)))]
        by_cases zero : mag = 0
        · subst zero
          simp [flTimes10_val]
        · have : ¬(0 : Int) ≤ -(mag : Int) := by omega
          simp only [this, if_false, flTimes10_val, bval_cons, bval_nil]
          simp

end Lanius.Mini.Reading
