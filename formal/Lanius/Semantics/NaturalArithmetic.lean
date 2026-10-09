import Lanius.Semantics.Loop

namespace Lanius.Semantics

open Lanius.Core

theorem eval_pointer_addNat (target : Target) (address offset : Nat)
    (bound : address + offset < 2 ^ target.pointerWidth.bits) :
    evalBinaryValue target .add (.pointer address) (.signed .i32 offset) = .ok (.pointer (address + offset)) := by
  have bounded : (address : Int) + offset < (2 : Int) ^ target.pointerWidth.bits := by
    exact_mod_cast bound
  change Except.ok (Value.pointer (((address : Int) + offset) % (2 : Int) ^ target.pointerWidth.bits).toNat) = _
  rw [Int.emod_eq_of_lt (by omega : 0 ≤ (address : Int) + offset) bounded]
  simp only [← Int.natCast_add, Int.toNat_natCast]

theorem eval_pointer_subNat (target : Target) (address offset : Nat) (ordered : offset ≤ address)
    (bound : address < 2 ^ target.pointerWidth.bits) :
    evalBinaryValue target .subtract (.pointer address) (.signed .i32 offset) = .ok (.pointer (address - offset)) := by
  have bounded : (address : Int) - offset < (2 : Int) ^ target.pointerWidth.bits := by
    have original : (address : Int) < (2 : Int) ^ target.pointerWidth.bits := by exact_mod_cast bound
    omega
  change Except.ok (Value.pointer (((address : Int) - offset) % (2 : Int) ^ target.pointerWidth.bits).toNat) = _
  rw [Int.emod_eq_of_lt (by omega : 0 ≤ (address : Int) - offset) bounded]
  simp only [← Int.natCast_sub ordered, Int.toNat_natCast]

/-- A nonnegative result rules out the single signed-overflow boundary when
    incrementing an already bounded natural. No larger resource limit is assumed. -/
theorem i32_succ_bound (target : Target) (value : Nat) (bound : value < 2 ^ 31)
    (nonnegative : 0 ≤ wrapSigned target .i32 ((value : Int) + 1)) : value + 1 < 2 ^ 31 := by
  have modulo : ((value : Int) + 1) % 4294967296 = (value : Int) + 1 :=
    Int.emod_eq_of_lt (by omega) (by omega)
  change 0 ≤ if ((value : Int) + 1) % 4294967296 ≥ 2147483648 then
    ((value : Int) + 1) % 4294967296 - 4294967296 else
    ((value : Int) + 1) % 4294967296 at nonnegative
  rw [modulo] at nonnegative
  split at nonnegative <;> omega

theorem eval_unsigned_castNat (target : Target) (destination : UnsignedIntTy)
    (source : SignedIntTy) (value : Nat) (bound : value < unsignedModulus target destination) :
    evalScalarCast target (.unsigned destination) (.signed source value) = .ok (.unsigned destination value) := by
  have modulo : (value : Int) % (unsignedModulus target destination : Nat) = value :=
    Int.emod_eq_of_lt (Int.natCast_nonneg _) (by omega)
  simp only [evalScalarCast, wrapUnsignedInt, Int.ofNat_eq_natCast, modulo, Int.toNat_natCast]

theorem eval_unsigned_mulNat (target : Target) (type : UnsignedIntTy) (left right : Nat)
    (bound : left * right < unsignedModulus target type) :
    evalBinaryValue target .multiply (.unsigned type left) (.unsigned type right) =
      .ok (.unsigned type (left * right)) := by
  simp only [evalBinaryValue, BEq.rfl, ↓reduceIte, evalUnsignedBinary,
    wrapUnsigned, Nat.mod_eq_of_lt bound]

theorem truncDiv_nat (left right : Nat) : truncDiv left right = (left / right : Nat) := by
  simp only [truncDiv, Int.natAbs_natCast, Int.not_lt_of_ge (Int.natCast_nonneg _),
    ↓reduceIte, Int.ofNat_eq_natCast]

/-- Signed arithmetic on nonnegative, representable i32 operands. Bounds are
    discharged at the source invariant, not by rerunning the typechecker. -/
theorem eval_i32_divNat (target : Target) (left right : Nat)
    (positive : 0 < right) (bound : left < 2 ^ 31) :
    evalBinaryValue target .divide (.signed .i32 left) (.signed .i32 right) =
      .ok (.signed .i32 (left / right : Nat)) := by
  have resultBound : left / right < 2 ^ 31 := Nat.lt_of_le_of_lt (Nat.div_le_self _ _) bound
  simp [evalBinaryValue, evalSignedBinary, truncDiv_nat, Nat.ne_of_gt positive]
  simpa using wrapSigned_i32_nat_lt target _ resultBound

theorem eval_i32_modNat (target : Target) (left right : Nat)
    (positive : 0 < right) (bound : left < 2 ^ 31) :
    evalBinaryValue target .remainder (.signed .i32 left) (.signed .i32 right) =
      .ok (.signed .i32 (left % right : Nat)) := by
  have resultBound : left % right < 2 ^ 31 := Nat.lt_of_le_of_lt (Nat.mod_le _ _) bound
  have remainder : (left : Int) - (left / right : Nat) * right = (left % right : Nat) := by
    have division := Nat.mod_add_div left right
    rw [Nat.mul_comm right] at division
    omega
  simp only [evalBinaryValue, BEq.rfl, ↓reduceIte, evalSignedBinary, truncDiv_nat]
  simp [Nat.ne_of_gt positive, -Int.natCast_ediv, remainder]
  simpa using wrapSigned_i32_nat_lt target _ resultBound

theorem eval_i32_addNat (target : Target) (left right : Nat) (bound : left + right < 2 ^ 31) :
    evalBinaryValue target .add (.signed .i32 left) (.signed .i32 right) =
      .ok (.signed .i32 (left + right : Nat)) := by
  simp only [evalBinaryValue, BEq.rfl, ↓reduceIte, evalSignedBinary,
    ← Int.natCast_add, wrapSigned_i32_nat_lt target _ bound]

theorem eval_i32_subNat (target : Target) (left right : Nat)
    (ordered : right ≤ left) (bound : left < 2 ^ 31) :
    evalBinaryValue target .subtract (.signed .i32 left) (.signed .i32 right) =
      .ok (.signed .i32 (left - right : Nat)) := by
  simp only [evalBinaryValue, BEq.rfl, ↓reduceIte, evalSignedBinary,
    ← Int.natCast_sub ordered,
    wrapSigned_i32_nat_lt target _ (Nat.lt_of_le_of_lt (Nat.sub_le _ _) bound)]

/-- A bounded reverse traversal may decrement zero to -1 without wrapping. -/
theorem eval_i32_predecessor (target : Target) (value : Nat) (bound : value < 2 ^ 31) :
    evalBinaryValue target .subtract (.signed .i32 value) (.signed .i32 1) =
      .ok (.signed .i32 ((value : Int) - 1)) := by
  cases value with
  | zero =>
      have modulo : (-1 : Int) % 4294967296 = 4294967295 := by omega
      simp [evalBinaryValue, evalSignedBinary, wrapSigned, signedModulus, signedSignBit, SignedIntTy.bits, modulo]
  | succ value =>
      simpa only [Nat.succ_sub_one, Int.natCast_add, Int.natCast_one, Int.add_sub_cancel] using
        eval_i32_subNat target (value + 1) 1 (by omega) bound

theorem eval_i32_subNonneg (target : Target) (left right : Int)
    (ordered : right ≤ left) (bound : left - right < 2 ^ 31) :
    evalBinaryValue target .subtract (.signed .i32 left) (.signed .i32 right) =
      .ok (.signed .i32 (left - right)) := by
  have cast := Int.toNat_of_nonneg (show 0 ≤ left - right by omega)
  simp only [evalBinaryValue, BEq.rfl, ↓reduceIte, evalSignedBinary]
  rw [← cast, wrapSigned_i32_nat_lt target _ (by omega)]

theorem eval_i32_addNonneg (target : Target) (left right : Int)
    (nonnegative : 0 ≤ left + right) (bound : left + right < 2 ^ 31) :
    evalBinaryValue target .add (.signed .i32 left) (.signed .i32 right) =
      .ok (.signed .i32 (left + right)) := by
  have cast := Int.toNat_of_nonneg nonnegative
  simp only [evalBinaryValue, BEq.rfl, ↓reduceIte, evalSignedBinary]
  rw [← cast, wrapSigned_i32_nat_lt target _ (by omega)]

theorem eval_i32_mulNat (target : Target) (left right : Nat) (bound : left * right < 2 ^ 31) :
    evalBinaryValue target .multiply (.signed .i32 left) (.signed .i32 right) =
      .ok (.signed .i32 (left * right : Nat)) := by
  simp only [evalBinaryValue, BEq.rfl, ↓reduceIte, evalSignedBinary,
    ← Int.natCast_mul, wrapSigned_i32_nat_lt target _ bound]

end Lanius.Semantics
