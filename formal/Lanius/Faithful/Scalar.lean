module

public import Lanius.Faithful.Rep
public import Lanius.Mini.Source

@[expose] public section

/-! # Core's scalar operations on represented values

Each lemma is one Core operation on the pure values of Lean scalars, as the
Lean operation the extraction writes for it: the `usize` comparisons as
`decide` on `Nat`, the `u64`/`u32` arithmetic as `BitVec`'s, and so on. They
are `pure_rule`s, so `pure_simp` leaves a body's arithmetic in Lean's terms. -/

namespace Lanius.Faithful

open Lanius.Mini
open Lanius.Core (Value)
open Lanius.Semantics (evalBinaryValue evalUnsignedBinary evalUnaryValue evalScalarCast scalarEqual)

/-! ## `usize` and the other unsigned types on `Nat` -/

theorem nat_beq (a b : Nat) : (a == b) = decide (a = b) := by
  by_cases h : a = b <;> simp [h]

section Unsigned

variable (k : Core.UnsignedIntTy) (a b : Nat)

@[pure_rule] theorem unsigned_less :
    evalBinaryValue target .less (.unsigned k a) (.unsigned k b) = .ok (.boolean (decide (a < b))) := by
  simp [evalBinaryValue, evalUnsignedBinary]

@[pure_rule] theorem unsigned_lessEqual :
    evalBinaryValue target .lessEqual (.unsigned k a) (.unsigned k b) = .ok (.boolean (decide (a ≤ b))) := by
  simp [evalBinaryValue, evalUnsignedBinary]

@[pure_rule] theorem unsigned_greater :
    evalBinaryValue target .greater (.unsigned k a) (.unsigned k b) = .ok (.boolean (decide (b < a))) := by
  simp [evalBinaryValue, evalUnsignedBinary]

@[pure_rule] theorem unsigned_greaterEqual :
    evalBinaryValue target .greaterEqual (.unsigned k a) (.unsigned k b) = .ok (.boolean (decide (b ≤ a))) := by
  simp [evalBinaryValue, evalUnsignedBinary]

@[pure_rule] theorem unsigned_equal :
    evalBinaryValue target .equal (.unsigned k a) (.unsigned k b) = .ok (.boolean (decide (a = b))) := by
  simp [evalBinaryValue, scalarEqual, nat_beq]

@[pure_rule] theorem unsigned_notEqual :
    evalBinaryValue target .notEqual (.unsigned k a) (.unsigned k b) = .ok (.boolean (!decide (a = b))) := by
  simp [evalBinaryValue, scalarEqual, nat_beq]

end Unsigned

@[pure_rule] theorem usize_add (a b : Nat) :
    evalBinaryValue target .add (.unsigned .usize a) (.unsigned .usize b) =
      .ok (.unsigned .usize ((a + b) % 2 ^ 64)) := rfl

@[pure_rule] theorem usize_subtract (a b : Nat) :
    evalBinaryValue target .subtract (.unsigned .usize a) (.unsigned .usize b) =
      .ok (.unsigned .usize ((a + 2 ^ 64 - b % 2 ^ 64) % 2 ^ 64)) := rfl

@[pure_rule] theorem usize_multiply (a b : Nat) :
    evalBinaryValue target .multiply (.unsigned .usize a) (.unsigned .usize b) =
      .ok (.unsigned .usize (a * b % 2 ^ 64)) := rfl

/-! ## `u64` on `BitVec 64`

A `u64` value is `.unsigned .u64 x.toNat` for a `BitVec 64` term `x`, a
literal included (`(c#64).toNat`). -/

section U64

open Lanius.Semantics (wrapUnsigned unsignedModulus)

variable (x y : BitVec 64)

theorem u64_modulus : unsignedModulus target .u64 = 2 ^ 64 := rfl

@[pure_rule] theorem u64_add :
    evalBinaryValue target .add (.unsigned .u64 x.toNat) (.unsigned .u64 y.toNat) =
      .ok (.unsigned .u64 (x + y).toNat) := by
  simp [evalBinaryValue, evalUnsignedBinary, wrapUnsigned, u64_modulus, BitVec.toNat_add]

@[pure_rule] theorem u64_subtract :
    evalBinaryValue target .subtract (.unsigned .u64 x.toNat) (.unsigned .u64 y.toNat) =
      .ok (.unsigned .u64 (x - y).toNat) := by
  simp only [evalBinaryValue, evalUnsignedBinary, wrapUnsigned, u64_modulus, BitVec.toNat_sub, beq_self_eq_true,
    if_true, Except.ok.injEq, Value.unsigned.injEq, true_and]
  have := x.isLt
  have := y.isLt
  rw [Nat.mod_eq_of_lt y.isLt]
  congr 1
  omega

@[pure_rule] theorem u64_multiply :
    evalBinaryValue target .multiply (.unsigned .u64 x.toNat) (.unsigned .u64 y.toNat) =
      .ok (.unsigned .u64 (x * y).toNat) := by
  simp [evalBinaryValue, evalUnsignedBinary, wrapUnsigned, u64_modulus, BitVec.toNat_mul]

@[pure_rule] theorem u64_bitAnd :
    evalBinaryValue target .bitAnd (.unsigned .u64 x.toNat) (.unsigned .u64 y.toNat) =
      .ok (.unsigned .u64 (x &&& y).toNat) := by
  simp only [evalBinaryValue, evalUnsignedBinary, wrapUnsigned, u64_modulus, beq_self_eq_true, if_true,
    BitVec.toNat_and]
  exact congrArg (fun n => Except.ok (Value.unsigned _ n)) (Nat.mod_eq_of_lt (Nat.and_lt_two_pow _ y.isLt))

@[pure_rule] theorem u64_bitOr :
    evalBinaryValue target .bitOr (.unsigned .u64 x.toNat) (.unsigned .u64 y.toNat) =
      .ok (.unsigned .u64 (x ||| y).toNat) := by
  simp only [evalBinaryValue, evalUnsignedBinary, wrapUnsigned, u64_modulus, beq_self_eq_true, if_true,
    BitVec.toNat_or]
  exact congrArg (fun n => Except.ok (Value.unsigned _ n)) (Nat.mod_eq_of_lt (Nat.or_lt_two_pow x.isLt y.isLt))

@[pure_rule] theorem u64_bitXor :
    evalBinaryValue target .bitXor (.unsigned .u64 x.toNat) (.unsigned .u64 y.toNat) =
      .ok (.unsigned .u64 (x ^^^ y).toNat) := by
  simp only [evalBinaryValue, evalUnsignedBinary, wrapUnsigned, u64_modulus, beq_self_eq_true, if_true,
    BitVec.toNat_xor]
  exact congrArg (fun n => Except.ok (Value.unsigned _ n)) (Nat.mod_eq_of_lt (Nat.xor_lt_two_pow x.isLt y.isLt))

@[pure_rule] theorem u64_shiftRight :
    evalBinaryValue target .shiftRight (.unsigned .u64 x.toNat) (.unsigned .u64 y.toNat) =
      if y.toNat < 64 then .ok (.unsigned .u64 (x >>> y.toNat).toNat) else .error .invalidShift := by
  by_cases h : y.toNat < 64
  · have : ¬ (y.toNat ≥ 64) := by omega
    simp only [evalBinaryValue, evalUnsignedBinary, wrapUnsigned, u64_modulus, beq_self_eq_true, if_true, h,
      BitVec.toNat_ushiftRight]
    have : x.toNat / 2 ^ y.toNat < 2 ^ 64 := Nat.lt_of_le_of_lt (Nat.div_le_self _ _) x.isLt
    simp [Core.UnsignedIntTy.bits, Nat.shiftRight_eq_div_pow, Nat.mod_eq_of_lt this, *]
  · have : y.toNat ≥ 64 := by omega
    simp [evalBinaryValue, evalUnsignedBinary, h, Core.UnsignedIntTy.bits, this]

@[pure_rule] theorem u64_shiftLeft :
    evalBinaryValue target .shiftLeft (.unsigned .u64 x.toNat) (.unsigned .u64 y.toNat) =
      if y.toNat < 64 then .ok (.unsigned .u64 (x <<< y.toNat).toNat) else .error .invalidShift := by
  by_cases h : y.toNat < 64
  · have : ¬ (y.toNat ≥ 64) := by omega
    simp [evalBinaryValue, evalUnsignedBinary, wrapUnsigned, u64_modulus, h, Core.UnsignedIntTy.bits,
      BitVec.toNat_shiftLeft, Nat.shiftLeft_eq, this]
  · have : y.toNat ≥ 64 := by omega
    simp [evalBinaryValue, evalUnsignedBinary, h, Core.UnsignedIntTy.bits, this]

/-- A literal shift amount is decided. -/
@[pure_rule] theorem literal_lt (c n : Nat) :
    ((no_index (OfNat.ofNat c : BitVec 64)).toNat < n) = (c % 2 ^ 64 < n) := by
  show ((BitVec.ofNat 64 c).toNat < n) = _
  simp [BitVec.toNat_ofNat]

end U64

@[pure_rule] theorem usize_divide (a b : Nat) :
    evalBinaryValue target .divide (.unsigned .usize a) (.unsigned .usize b) =
      if b = 0 then .error .divisionByZero else .ok (.unsigned .usize (a / b % 2 ^ 64)) := by
  by_cases h : b = 0 <;> simp [evalBinaryValue, evalUnsignedBinary, h] <;> rfl

@[pure_rule] theorem usize_remainder (a b : Nat) :
    evalBinaryValue target .remainder (.unsigned .usize a) (.unsigned .usize b) =
      if b = 0 then .error .divisionByZero else .ok (.unsigned .usize (a % b % 2 ^ 64)) := by
  by_cases h : b = 0 <;> simp [evalBinaryValue, evalUnsignedBinary, h] <;> rfl

/-- The prelude's `times` checks its product by dividing it back. -/
@[pure_rule] theorem mul_check (a b : Nat) :
    ((a * b % 18446744073709551616) / a % 18446744073709551616 = b) =
      ((a = 0 ∧ b = 0) ∨ (¬a = 0 ∧ a * b < 18446744073709551616)) := by
  apply propext
  have hm : a * b % 18446744073709551616 < 18446744073709551616 := Nat.mod_lt _ (by decide)
  rw [Nat.mod_eq_of_lt (Nat.lt_of_le_of_lt (Nat.div_le_self _ _) hm)]
  by_cases a0 : a = 0
  · subst a0; simp; omega
  · constructor
    · intro h
      right
      refine ⟨a0, ?_⟩
      have : a * b ≤ a * b % 18446744073709551616 := by
        have := (Nat.le_div_iff_mul_le (Nat.pos_of_ne_zero a0)).mp (Nat.le_of_eq h.symm)
        rwa [Nat.mul_comm b a] at this
      have := Nat.mod_le (a * b) 18446744073709551616
      omega
    · rintro (⟨h, _⟩ | ⟨_, h⟩)
      · exact absurd h a0
      · rw [Nat.mod_eq_of_lt h, Nat.mul_div_cancel_left _ (Nat.pos_of_ne_zero a0)]

/-! ## Literals

A literal is a `BitVec 64` (`SrcExpr.unsigned`); its value at a type other
than `u64` is the number it stands for, as the extraction writes it. -/

@[pure_rule] theorem usize_literal (c : Nat) :
    Value.unsigned .usize (no_index (OfNat.ofNat c : BitVec 64)).toNat = .unsigned .usize (c % 2 ^ 64) := rfl

@[pure_rule] theorem u32_literal (c : Nat) :
    Value.unsigned .u32 (no_index (OfNat.ofNat c : BitVec 64)).toNat = .unsigned .u32 (c % 2 ^ 64) := rfl

@[pure_rule] theorem u8_literal (c : Nat) :
    Value.unsigned .u8 (no_index (OfNat.ofNat c : BitVec 64)).toNat = .unsigned .u8 (c % 2 ^ 64) := rfl

@[pure_rule] theorem usize_literal' (c : Nat) :
    Value.unsigned .usize (BitVec.ofNat 64 c).toNat = .unsigned .usize (c % 2 ^ 64) := rfl

@[pure_rule] theorem u32_literal' (c : Nat) :
    Value.unsigned .u32 (BitVec.ofNat 64 c).toNat = .unsigned .u32 (c % 2 ^ 64) := rfl

@[pure_rule] theorem u8_literal' (c : Nat) :
    Value.unsigned .u8 (BitVec.ofNat 64 c).toNat = .unsigned .u8 (c % 2 ^ 64) := rfl

@[pure_rule] theorem literal_lt' (c n : Nat) : ((BitVec.ofNat 64 c).toNat < n) = (c % 2 ^ 64 < n) := by
  simp [BitVec.toNat_ofNat]

/-! ## `u32` on `BitVec 32` -/

@[pure_rule] theorem u32_shiftRight (x : BitVec 32) (s : Nat) :
    evalBinaryValue target .shiftRight (.unsigned .u32 x.toNat) (.unsigned .u32 s) =
      if s < 32 then .ok (.unsigned .u32 (x >>> s).toNat) else .error .invalidShift := by
  by_cases h : s < 32
  · have : ¬ (s ≥ 32) := by omega
    have : x.toNat / 2 ^ s < 2 ^ 32 := Nat.lt_of_le_of_lt (Nat.div_le_self _ _) x.isLt
    simp [evalBinaryValue, evalUnsignedBinary, Lanius.Semantics.wrapUnsigned, Lanius.Semantics.unsignedModulus, h,
      Core.UnsignedIntTy.bits, BitVec.toNat_ushiftRight, Nat.shiftRight_eq_div_pow, Nat.mod_eq_of_lt this, *]
  · have : s ≥ 32 := by omega
    simp [evalBinaryValue, evalUnsignedBinary, h, Core.UnsignedIntTy.bits, this]

/-! ## `i32` on `BitVec 32` -/

section I32

open Lanius.Semantics (evalSignedBinary)

variable (x y : BitVec 32)

@[pure_rule] theorem i32_add :
    evalBinaryValue target .add (.signed .i32 x.toInt) (.signed .i32 y.toInt) = .ok (.signed .i32 (x + y).toInt) := by
  simp only [evalBinaryValue, evalSignedBinary]
  rw [show target = Core.Target.x86_64 from rfl, wrapSigned_i32, BitVec.toInt_ofInt, BitVec.toInt_add]
  rfl

@[pure_rule] theorem i32_subtract :
    evalBinaryValue target .subtract (.signed .i32 x.toInt) (.signed .i32 y.toInt) =
      .ok (.signed .i32 (x - y).toInt) := by
  simp only [evalBinaryValue, evalSignedBinary]
  rw [show target = Core.Target.x86_64 from rfl, wrapSigned_i32, BitVec.toInt_ofInt, BitVec.toInt_sub]
  rfl

@[pure_rule] theorem i32_multiply :
    evalBinaryValue target .multiply (.signed .i32 x.toInt) (.signed .i32 y.toInt) =
      .ok (.signed .i32 (x * y).toInt) := by
  simp only [evalBinaryValue, evalSignedBinary]
  rw [show target = Core.Target.x86_64 from rfl, wrapSigned_i32, BitVec.toInt_ofInt, BitVec.toInt_mul]
  rfl

end I32

/-! ## Casts, as the extraction writes them -/

section Casts

open Lanius.Semantics (wrapSigned wrapUnsigned wrapUnsignedInt unsignedModulus)

/-- `i32 -> u32`: the same bits. -/
@[pure_rule] theorem cast_i32_u32 (x : BitVec 32) :
    evalScalarCast target (.unsigned .u32) (.signed .i32 x.toInt) = .ok (.unsigned .u32 x.toNat) := by
  simp only [evalScalarCast, wrapUnsignedInt, unsignedModulus, Except.ok.injEq, Value.unsigned.injEq, true_and]
  show Int.toNat (x.toInt % ((2 ^ 32 : Nat) : Int)) = x.toNat
  rw [BitVec.toInt_eq_toNat_cond]
  have := x.isLt
  split <;> omega

/-- `i32 -> u8` and the unsigned types to `u8`: the low byte. -/
@[pure_rule] theorem cast_i32_u8 (x : BitVec 32) :
    evalScalarCast target (.unsigned .u8) (.signed .i32 x.toInt) = .ok (.unsigned .u8 (UInt8.ofNat x.toNat).toNat) := by
  simp only [evalScalarCast, wrapUnsignedInt, unsignedModulus, Except.ok.injEq, Value.unsigned.injEq, true_and,
    UInt8.toNat_ofNat]
  show Int.toNat (x.toInt % ((2 ^ 8 : Nat) : Int)) = x.toNat % 2 ^ 8
  rw [BitVec.toInt_eq_toNat_cond]
  have := x.isLt
  split <;> omega

@[pure_rule] theorem cast_unsigned_u8 (k : Core.UnsignedIntTy) (a : Nat) :
    evalScalarCast target (.unsigned .u8) (.unsigned k a) = .ok (.unsigned .u8 (UInt8.ofNat a).toNat) := by
  simp [evalScalarCast, wrapUnsigned, unsignedModulus, Core.UnsignedIntTy.bits, UInt8.toNat_ofNat]

/-- `u32 -> u64`: zero-extended. -/
@[pure_rule] theorem cast_u32_u64 (x : BitVec 32) :
    evalScalarCast target (.unsigned .u64) (.unsigned .u32 x.toNat) =
      .ok (.unsigned .u64 (x.setWidth 64).toNat) := by
  have : x.toNat < 2 ^ 64 := Nat.lt_trans x.isLt (by decide)
  simp [evalScalarCast, wrapUnsigned, unsignedModulus, Core.UnsignedIntTy.bits, BitVec.toNat_setWidth,
    Nat.mod_eq_of_lt this]

/-- `usize -> u64`. -/
@[pure_rule] theorem cast_usize_u64 (n : Nat) :
    evalScalarCast target (.unsigned .u64) (.unsigned .usize n) = .ok (.unsigned .u64 (BitVec.ofNat 64 n).toNat) := by
  simp [evalScalarCast, wrapUnsigned, unsignedModulus, Core.UnsignedIntTy.bits, BitVec.toNat_ofNat]

/-- `usize -> i32`. -/
@[pure_rule] theorem cast_usize_i32 (n : Nat) :
    evalScalarCast target (.signed .i32) (.unsigned .usize n) = .ok (.signed .i32 (BitVec.ofNat 32 n).toInt) := by
  simp only [evalScalarCast, Except.ok.injEq, Value.signed.injEq, true_and]
  rw [show target = Core.Target.x86_64 from rfl, wrapSigned_i32]
  congr 1

end Casts

/-! ## Booleans -/

@[pure_rule] theorem bool_not (b : Bool) : evalUnaryValue target .logicalNot (.boolean b) = .ok (.boolean !b) := rfl

@[pure_rule] theorem bool_equal (a b : Bool) :
    evalBinaryValue target .equal (.boolean a) (.boolean b) = .ok (.boolean (a == b)) := by
  simp [evalBinaryValue, scalarEqual]

@[pure_rule] theorem bool_notEqual (a b : Bool) :
    evalBinaryValue target .notEqual (.boolean a) (.boolean b) = .ok (.boolean !(a == b)) := by
  simp [evalBinaryValue, scalarEqual]

end Lanius.Faithful
