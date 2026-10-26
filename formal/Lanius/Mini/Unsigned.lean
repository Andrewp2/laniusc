module

public import Lanius.Mini.Source
-- import all: Lanius.Mini.Compiler
import all Lanius.Mini.Compiler.Types
import all Lanius.Mini.Compiler.P.Lists_empty
import all Lanius.Mini.Compiler.P.DivOp_size
import all Lanius.Mini.Compiler.P.codeSize
import all Lanius.Mini.Compiler.P.compileArgs
import all Lanius.Mini.Compiler.P.arities
import all Lanius.Mini.Compiler.P.pow2
import all Lanius.Mini.Compiler.P.moduleExports
import all Lanius.Mini.Compiler.P.importOk
import all Lanius.Mini.Compiler.P.importsOk
import all Lanius.Mini.Compiler.P.modulesOk
import all Lanius.Mini.Compiler.P.moduleFirsts
import all Lanius.Mini.Compiler.P.Instr_pieces
import all Lanius.Mini.Compiler.P.compileModules
import all Lanius.Mini.Compiler.P.render
import all Lanius.Mini.Compiler.P.UintTy_mask
import all Lanius.Mini.Compiler.P.UintTy_isWide
import all Lanius.Mini.Compiler.P.lookup
import all Lanius.Mini.Compiler.P.arithShiftRight
import all Lanius.Mini.Compiler.P.equality
import all Lanius.Mini.Compiler.P.conjunction
import all Lanius.Mini.Compiler.P.lowerLocal
import all Lanius.Mini.Compiler.P.copyBinding
import all Lanius.Mini.Compiler.P.lowerTagged
import all Lanius.Mini.Compiler.P.armScope
import all Lanius.Mini.Compiler.P.assignFrom
import all Lanius.Mini.Compiler.P.lowerMatchArms
import all Lanius.Mini.Compiler.P.lowerCallSig
import all Lanius.Mini.Compiler.P.consArgs
import all Lanius.Mini.Compiler.P.shortCircuit
import all Lanius.Mini.Compiler.P.evalNot
import all Lanius.Mini.Compiler.P.evalSame
import all Lanius.Mini.Compiler.P.matchDst
import all Lanius.Mini.Compiler.P.matchVariants
import all Lanius.Mini.Compiler.P.lowerSetValues
import all Lanius.Mini.Compiler.P.lowerSetCallArgs
import all Lanius.Mini.Compiler.P.lowerReturn
import all Lanius.Mini.Compiler.P.lowerAddress
import all Lanius.Mini.Compiler.P.structFields
import all Lanius.Mini.Compiler.P.enumVariants
import all Lanius.Mini.Compiler.P.usizeWidth
import all Lanius.Mini.Compiler.P.wordWidth
import all Lanius.Mini.Compiler.P.wordElement
import all Lanius.Mini.Compiler.P.widthOf
import all Lanius.Mini.Compiler.P.elementBase
import all Lanius.Mini.Compiler.P.iteThen
import all Lanius.Mini.Compiler.P.storeType
import all Lanius.Mini.Compiler.P.indexOf
import all Lanius.Mini.Compiler.P.lowerLoadType
import all Lanius.Mini.Compiler.P.storeEvalWord
import all Lanius.Mini.Compiler.P.sigs
import all Lanius.Mini.Compiler.P.lowerBody
import all Lanius.Mini.Compiler.P.declareFuncs
import all Lanius.Mini.Compiler.P.declareProgram
import all Lanius.Mini.Compiler.P.BinOp_folds
import all Lanius.Mini.Compiler.P.Word_compute
import all Lanius.Mini.Compiler.P.Word_narrows
import all Lanius.Mini.Compiler.P.binaryConstant
import all Lanius.Mini.Compiler.P.Expr_agrees
import all Lanius.Mini.Compiler.P.assignAgrees
import all Lanius.Mini.Compiler.P.callAgrees
import all Lanius.Mini.Compiler.P.substAll
import all Lanius.Mini.Compiler.P.Stmt_kills
import all Lanius.Mini.Compiler.P.optKill
import all Lanius.Mini.Compiler.P.optimizeNeg
import all Lanius.Mini.Compiler.P.optimizeLeft
import all Lanius.Mini.Compiler.P.optimizeIte
import all Lanius.Mini.Compiler.P.compileOr
import all Lanius.Mini.Compiler.P.compileSource
import all Lanius.Mini.Compiler.P.Inline_arithOf
import all Lanius.Mini.Compiler.P.Inline_lowerSetScalar
import all Lanius.Mini.Compiler.P.Inline_branchAgrees
-- end import all
-- import parts: Lanius.Mini.Compiler UintTy.isWide UintTy.mask fromI32
public import Lanius.Mini.Compiler.P.UintTy_isWide
public import Lanius.Mini.Compiler.P.UintTy_mask
public import Lanius.Mini.Compiler.P.lowerLocal
-- end import parts

@[expose] public section

/-! Core's unsigned arithmetic, comparisons and the casts between `i32` and
the unsigned types, as arithmetic on 64-bit slots. A value of an unsigned type
of width `w` sits in its slot as its number, below `2 ^ w`. -/

namespace Lanius.Mini

open Lanius.Core (Value)

theorem UintTy.bits_toCore (k : UintTy) : Core.UnsignedIntTy.bits .x86_64 k.toCore = k.width := by
  cases k <;> rfl

theorem UintTy.pow_le (k : UintTy) : 2 ^ k.width ≤ 2 ^ 64 := by
  cases k <;> decide

theorem UintTy.mask_toNat (k : UintTy) : k.mask.toNat = 2 ^ k.width - 1 := by
  cases k <;> rfl

theorem UintTy.width_of_wide {k : UintTy} (wide : k.isWide = true) : k.width = 64 := by
  cases k <;> simp_all [UintTy.isWide, UintTy.width]

theorem UintTy.width_of_narrow {k : UintTy} (narrow : ¬k.isWide = true) : k.width ≤ 32 := by
  cases k <;> simp_all [UintTy.isWide, UintTy.width]

/-- `wrap` reduces a slot to its type's width. -/
theorem wrap_eval (k : UintTy) (e : Expr) (env : Env) :
    (wrap k e).eval env = BitVec.ofNat 64 ((e.eval env).toNat % 2 ^ k.width) := by
  apply BitVec.eq_of_toNat_eq
  have bound := (e.eval env).isLt
  have le := k.pow_le
  by_cases wide : k.isWide = true
  · simp only [wrap, wide, ↓reduceIte, BitVec.toNat_ofNat, UintTy.width_of_wide wide]
    omega
  · simp only [wrap, wide, Bool.false_eq_true, ↓reduceIte, Expr.eval, Word.apply, BinOp.apply,
      BitVec.toNat_and, UintTy.mask_toNat, Nat.and_two_pow_sub_one_eq_mod, BitVec.toNat_ofNat]
    omega

theorem holds_uint (k : UintTy) {m : Nat} (bound : m < 2 ^ k.width) :
    (SrcType.uint k).Holds (.unsigned k.toCore m) (BitVec.ofNat 64 m) := by
  have le := k.pow_le
  have : m % 2 ^ 64 = m := Nat.mod_eq_of_lt (by omega)
  simp only [SrcType.Holds, BitVec.toNat_ofNat, this, true_and]
  exact bound

section Values

open Semantics

theorem eval_uint_binop (k : UintTy) {a b : BitVec 64} (hb : b.toNat < 2 ^ k.width)
    {op : BinOp} {cop : Core.BinaryOp}
    (h : (cop = .add ∧ op = .add) ∨ (cop = .subtract ∧ op = .sub) ∨ (cop = .multiply ∧ op = .mul) ∨
      (cop = .bitAnd ∧ op = .and) ∨ (cop = .bitOr ∧ op = .or) ∨ (cop = .bitXor ∧ op = .xor)) :
    evalBinaryValue .x86_64 cop (.unsigned k.toCore a.toNat) (.unsigned k.toCore b.toNat) =
      .ok (.unsigned k.toCore ((op.apply a b).toNat % 2 ^ k.width)) := by
  have le := k.pow_le
  rcases h with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ <;>
  simp only [evalBinaryValue, beq_self_eq_true, ↓reduceIte, evalUnsignedBinary, wrapUnsigned,
    unsignedModulus, UintTy.bits_toCore, BinOp.apply, BitVec.toNat_add, BitVec.toNat_sub,
    BitVec.toNat_mul, BitVec.toNat_and, BitVec.toNat_or, BitVec.toNat_xor, Except.ok.injEq,
    Value.unsigned.injEq, true_and]
  · cases k <;> simp only [UintTy.width] <;> omega
  · cases k <;> simp only [UintTy.width] at hb ⊢ <;> omega
  · cases k <;> simp only [UintTy.width] <;> omega
  · rfl
  · rfl
  · rfl

theorem eval_uint_order (k : UintTy) (a b : BitVec 64) {cop : Core.BinaryOp} {op : CmpOp}
    (h : (cop = .less ∧ op = .lt) ∨ (cop = .lessEqual ∧ op = .le) ∨
      (cop = .greater ∧ op = .gt) ∨ (cop = .greaterEqual ∧ op = .ge)) :
    evalBinaryValue .x86_64 cop (.unsigned k.toCore a.toNat) (.unsigned k.toCore b.toNat) =
      .ok (.boolean (op.holdsU a b)) := by
  rcases h with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ <;>
    simp [evalBinaryValue, evalUnsignedBinary, CmpOp.holdsU, BitVec.ult, BitVec.ule]

theorem toNat_beq (a b : BitVec 64) : (a.toNat == b.toNat) = (a == b) := by
  rw [Bool.eq_iff_iff]
  simp [BitVec.toNat_inj]

theorem eval_uint_eq (k : UintTy) (a b : BitVec 64) :
    evalBinaryValue .x86_64 .equal (.unsigned k.toCore a.toNat) (.unsigned k.toCore b.toNat) =
      .ok (.boolean (CmpOp.eq.holdsU a b)) := by
  simp [evalBinaryValue, scalarEqual, CmpOp.holdsU, toNat_beq]

theorem eval_uint_ne (k : UintTy) (a b : BitVec 64) :
    evalBinaryValue .x86_64 .notEqual (.unsigned k.toCore a.toNat) (.unsigned k.toCore b.toNat) =
      .ok (.boolean (CmpOp.ne.holdsU a b)) := by
  simp [evalBinaryValue, scalarEqual, CmpOp.holdsU, toNat_beq, bne]

theorem eval_ptr_eq (a b : BitVec 64) :
    evalBinaryValue .x86_64 .equal (.pointer a.toNat) (.pointer b.toNat) =
      .ok (.boolean (CmpOp.eq.holdsU a b)) := by
  simp [evalBinaryValue, scalarEqual, CmpOp.holdsU, toNat_beq]

theorem eval_ptr_ne (a b : BitVec 64) :
    evalBinaryValue .x86_64 .notEqual (.pointer a.toNat) (.pointer b.toNat) =
      .ok (.boolean (CmpOp.ne.holdsU a b)) := by
  simp [evalBinaryValue, scalarEqual, CmpOp.holdsU, toNat_beq, bne]

theorem cast_i32_i32 (x : BitVec 32) :
    evalScalarCast .x86_64 (.signed .i32) (.signed .i32 x.toInt) = .ok (.signed .i32 x.toInt) := by
  simp [evalScalarCast, wrapSigned_i32]

theorem cast_i32_uint (k : UintTy) (n : Nat) :
    evalScalarCast .x86_64 (.signed .i32) (.unsigned k.toCore n) =
      .ok (.signed .i32 (BitVec.ofNat 32 n).toInt) := by
  simp only [evalScalarCast, wrap_nat]

theorem cast_uint_uint (k source : UintTy) (n : Nat) :
    evalScalarCast .x86_64 (.unsigned k.toCore) (.unsigned source.toCore n) =
      .ok (.unsigned k.toCore (n % 2 ^ k.width)) := by
  simp [evalScalarCast, wrapUnsigned, unsignedModulus, UintTy.bits_toCore]

theorem cast_uint_i32 (k : UintTy) (x : BitVec 32) :
    evalScalarCast .x86_64 (.unsigned k.toCore) (.signed .i32 x.toInt) =
      .ok (.unsigned k.toCore (x.toInt % 2 ^ k.width).toNat) := by
  simp [evalScalarCast, wrapUnsignedInt, unsignedModulus, UintTy.bits_toCore]

end Values

theorem toInt_cases (x : BitVec 32) :
    (x.toNat < 2147483648 ∧ x.toInt = x.toNat) ∨ (2147483648 ≤ x.toNat ∧ x.toInt = x.toNat - 4294967296) := by
  rw [BitVec.toInt_eq_toNat_cond]
  have := x.isLt
  by_cases h : 2 * x.toNat < 2 ^ 32
  · left; rw [if_pos h]; omega
  · right; rw [if_neg h]; omega

/-- Sign extension as `fromI32` computes it. -/
theorem sext_toNat (x : BitVec 32) :
    (widen x - (if (2147483648 : BitVec 64).ule (widen x) then 1 else 0) * 4294967296).toNat =
      (x.toInt % 2 ^ 64).toNat := by
  have xLt := x.isLt
  have xNat : (widen x).toNat = x.toNat := by simp [widen]; omega
  rw [BitVec.toInt_eq_toNat_cond]
  by_cases neg : 2147483648 ≤ x.toNat
  · have c : (2147483648 : BitVec 64).ule (widen x) = true := by
      simp only [BitVec.ule, xNat, decide_eq_true_eq]; exact neg
    have : ((1 : BitVec 64) * 4294967296).toNat = 4294967296 := by simp
    rw [if_pos c, if_neg (by omega), BitVec.toNat_sub, this, xNat]
    omega
  · have c : (2147483648 : BitVec 64).ule (widen x) = false := by
      simp only [BitVec.ule, xNat, decide_eq_false_iff_not]; exact neg
    have : widen x - (0 : BitVec 64) * 4294967296 = widen x := by simp
    rw [if_neg (by rw [c]; simp), if_pos (by omega), this, xNat]
    omega

/-- `fromI32` gives the number Core's cast from `i32` does. -/
theorem fromI32_eval (k : UintTy) (e : Expr) (env : Env) {x : BitVec 32} (bits : e.eval env = widen x) :
    (fromI32 k e).eval env = BitVec.ofNat 64 (x.toInt % 2 ^ k.width).toNat := by
  have xLt := x.isLt
  have xNat : (widen x).toNat = x.toNat := by simp [widen]; omega
  by_cases wide : k.isWide = true
  · rw [UintTy.width_of_wide wide]
    simp only [fromI32, wide, ↓reduceIte, Expr.eval, Word.apply, Word.holds, CmpOp.holdsU, BinOp.apply, bits]
    apply BitVec.eq_of_toNat_eq
    rw [sext_toNat, BitVec.toNat_ofNat]
    omega
  · have w := UintTy.width_of_narrow wide
    simp only [fromI32, wide, Bool.false_eq_true, ↓reduceIte, wrap_eval, bits, xNat]
    congr 1
    rcases toInt_cases x with ⟨_, eq⟩ | ⟨_, eq⟩ <;> rw [eq] <;>
      cases k <;> simp_all [UintTy.isWide, UintTy.width] <;> omega


/-! Core's `isize` is `BitVec 64` arithmetic on `toInt`; its slot holds the
bits. Its order is the unsigned order of the bits with the sign bit flipped. -/

theorem toInt64_cond (x : BitVec 64) :
    x.toInt = if x.toNat < 9223372036854775808 then (x.toNat : Int) else (x.toNat : Int) - 18446744073709551616 := by
  rw [BitVec.toInt_eq_toNat_cond]
  have := x.isLt
  split <;> split <;> omega

theorem wrapSigned_isize (n : Int) :
    Semantics.wrapSigned Core.Target.x86_64 .isize n = (BitVec.ofInt 64 n).toInt := by
  rw [BitVec.toInt_ofInt]
  change (if n % 18446744073709551616 ≥ 9223372036854775808 then n % 18446744073709551616 - 18446744073709551616
      else n % 18446744073709551616) =
    (if n % 18446744073709551616 < 9223372036854775808 then n % 18446744073709551616
      else n % 18446744073709551616 - 18446744073709551616)
  by_cases h : 9223372036854775808 ≤ n % 18446744073709551616
  · rw [if_pos h, if_neg (by omega)]
  · rw [if_neg h, if_pos (by omega)]

theorem toInt64_emod (x : BitVec 64) : x.toInt % 18446744073709551616 = (x.toNat : Int) := by
  rw [toInt64_cond]
  have := x.isLt
  split <;> omega

theorem wrap_isize (x : BitVec 64) :
    Semantics.wrapSigned Core.Target.x86_64 .isize x.toInt = x.toInt := by
  rw [wrapSigned_isize, BitVec.ofInt_toInt]

theorem wrap_isize_nat (n : Nat) :
    Semantics.wrapSigned Core.Target.x86_64 .isize (Int.ofNat n) = (BitVec.ofNat 64 n).toInt := by
  rw [wrapSigned_isize]
  congr 1

/-- The bits with the sign bit flipped: `signKey` adds `2 ^ 63`. -/
def flip (a : BitVec 64) : BitVec 64 := a + 9223372036854775808

theorem flip_toNat (a : BitVec 64) :
    (flip a).toNat = (a.toNat + 9223372036854775808) % 18446744073709551616 := by
  have sign : (9223372036854775808 : BitVec 64).toNat = 9223372036854775808 := by rfl
  rw [flip, BitVec.toNat_add, sign]

theorem flip_lt (a b : BitVec 64) : (flip a).toNat < (flip b).toNat ↔ a.toInt < b.toInt := by
  rw [flip_toNat, flip_toNat, toInt64_cond, toInt64_cond]
  have := a.isLt
  have := b.isLt
  generalize a.toNat = x at *
  generalize b.toNat = y at *
  split <;> split <;> omega

theorem flip_le (a b : BitVec 64) : (flip a).toNat ≤ (flip b).toNat ↔ a.toInt ≤ b.toInt := by
  rw [flip_toNat, flip_toNat, toInt64_cond, toInt64_cond]
  have := a.isLt
  have := b.isLt
  generalize a.toNat = x at *
  generalize b.toNat = y at *
  split <;> split <;> omega

section Isize

open Semantics

variable (a b : BitVec 64)

theorem wrap64_add : Semantics.wrapSigned .x86_64 .isize (a.toInt + b.toInt) = (a + b).toInt := by
  rw [wrapSigned_isize, BitVec.toInt_ofInt, BitVec.toInt_add]

theorem wrap64_sub : Semantics.wrapSigned .x86_64 .isize (a.toInt - b.toInt) = (a - b).toInt := by
  rw [wrapSigned_isize, BitVec.toInt_ofInt, BitVec.toInt_sub]

theorem wrap64_mul : Semantics.wrapSigned .x86_64 .isize (a.toInt * b.toInt) = (a * b).toInt := by
  rw [wrapSigned_isize, BitVec.toInt_ofInt, BitVec.toInt_mul]

theorem wrap64_of {c : BitVec 64} {n : Nat} (h : n = c.toNat) :
    Semantics.wrapSigned .x86_64 .isize (Int.ofNat n) = c.toInt := by
  rw [wrap_isize_nat, h]
  simp

theorem eval_isize_binop {op : BinOp} {cop : Core.BinaryOp}
    (h : (cop = .add ∧ op = .add) ∨ (cop = .subtract ∧ op = .sub) ∨ (cop = .multiply ∧ op = .mul) ∨
      (cop = .bitAnd ∧ op = .and) ∨ (cop = .bitOr ∧ op = .or) ∨ (cop = .bitXor ∧ op = .xor)) :
    evalBinaryValue .x86_64 cop (.signed .isize a.toInt) (.signed .isize b.toInt) =
      .ok (.signed .isize (op.apply a b).toInt) := by
  rcases h with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ <;>
    simp only [evalBinaryValue, beq_self_eq_true, ↓reduceIte, evalSignedBinary, BinOp.apply]
  · rw [wrap64_add]
  · rw [wrap64_sub]
  · rw [wrap64_mul]
  · rw [signedBits_isize_x86_value, signedBits_isize_x86_value, toInt64_emod, toInt64_emod,
      Int.toNat_natCast, Int.toNat_natCast]
    exact congrArg (fun v => Except.ok (Value.signed .isize v)) (wrap64_of (BitVec.toNat_and a b).symm)
  · rw [signedBits_isize_x86_value, signedBits_isize_x86_value, toInt64_emod, toInt64_emod,
      Int.toNat_natCast, Int.toNat_natCast]
    exact congrArg (fun v => Except.ok (Value.signed .isize v)) (wrap64_of (BitVec.toNat_or a b).symm)
  · rw [signedBits_isize_x86_value, signedBits_isize_x86_value, toInt64_emod, toInt64_emod,
      Int.toNat_natCast, Int.toNat_natCast]
    exact congrArg (fun v => Except.ok (Value.signed .isize v)) (wrap64_of (BitVec.toNat_xor a b).symm)

theorem eval_isize_order {cop : Core.BinaryOp} {op : CmpOp}
    (h : (cop = .less ∧ op = .lt) ∨ (cop = .lessEqual ∧ op = .le) ∨
      (cop = .greater ∧ op = .gt) ∨ (cop = .greaterEqual ∧ op = .ge)) :
    evalBinaryValue .x86_64 cop (.signed .isize a.toInt) (.signed .isize b.toInt) =
      .ok (.boolean (op.holdsU (flip a) (flip b))) := by
  rcases h with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ <;>
    simp only [evalBinaryValue, beq_self_eq_true, ↓reduceIte, evalSignedBinary, CmpOp.holdsU, BitVec.ult, BitVec.ule, flip_lt,
      flip_le, gt_iff_lt, ge_iff_le]

theorem toInt64_beq : (a.toInt == b.toInt) = (a == b) := by
  rw [Bool.eq_iff_iff]
  simp [BitVec.toInt_inj]

theorem eval_isize_eq :
    evalBinaryValue .x86_64 .equal (.signed .isize a.toInt) (.signed .isize b.toInt) =
      .ok (.boolean (CmpOp.eq.holdsU a b)) := by
  simp [evalBinaryValue, scalarEqual, CmpOp.holdsU, toInt64_beq]

theorem eval_isize_ne :
    evalBinaryValue .x86_64 .notEqual (.signed .isize a.toInt) (.signed .isize b.toInt) =
      .ok (.boolean (CmpOp.ne.holdsU a b)) := by
  simp [evalBinaryValue, scalarEqual, CmpOp.holdsU, toInt64_beq, bne]

theorem eval_isize_neg :
    evalUnaryValue .x86_64 .negate (.signed .isize a.toInt) = .ok (.signed .isize (0 - a).toInt) := by
  simp only [evalUnaryValue, wrapSigned_isize, BitVec.toInt_ofInt]
  rw [show (0 : BitVec 64) - a = -a by simp, BitVec.toInt_neg]

theorem cast_isize_isize :
    evalScalarCast .x86_64 (.signed .isize) (.signed .isize a.toInt) = .ok (.signed .isize a.toInt) := by
  simp only [evalScalarCast, wrap_isize]

theorem cast_isize_i32 (x : BitVec 32) :
    evalScalarCast .x86_64 (.signed .isize) (.signed .i32 x.toInt) =
      .ok (.signed .isize (BitVec.ofInt 64 x.toInt).toInt) := by
  simp only [evalScalarCast, wrapSigned_isize]

theorem cast_isize_uint (k : UintTy) (n : Nat) :
    evalScalarCast .x86_64 (.signed .isize) (.unsigned k.toCore n) =
      .ok (.signed .isize (BitVec.ofNat 64 n).toInt) := by
  simp only [evalScalarCast, wrap_isize_nat]

theorem cast_i32_isize :
    evalScalarCast .x86_64 (.signed .i32) (.signed .isize a.toInt) =
      .ok (.signed .i32 (BitVec.ofNat 32 a.toNat).toInt) := by
  simp only [evalScalarCast, wrapSigned_i32, Except.ok.injEq, Value.signed.injEq, true_and]
  congr 1
  apply BitVec.eq_of_toNat_eq
  rw [BitVec.toNat_ofInt, BitVec.toNat_ofNat, toInt64_cond]
  have := a.isLt
  split <;> omega

theorem cast_uint_isize (k : UintTy) :
    evalScalarCast .x86_64 (.unsigned k.toCore) (.signed .isize a.toInt) =
      .ok (.unsigned k.toCore (a.toNat % 2 ^ k.width)) := by
  simp only [evalScalarCast, wrapUnsignedInt, unsignedModulus, UintTy.bits_toCore]
  rw [toInt64_cond]
  have := a.isLt
  cases k <;> simp only [UintTy.width] <;> split <;> simp <;> omega

end Isize

/-- The bits of a word slice's stride, `-(8 * words)`. -/
theorem stride_word_bits {w : Nat} (small : w ≤ 4096) :
    ((0 : BitVec 64) - BitVec.ofNat 64 (8 * w)).toInt = -((8 * w : Nat) : Int) := by
  rw [toInt64_cond]
  have lt : 8 * w < 18446744073709551616 := by omega
  have val : ((0 : BitVec 64) - BitVec.ofNat 64 (8 * w)).toNat =
      (18446744073709551616 - 8 * w) % 18446744073709551616 := by
    rw [BitVec.toNat_sub, BitVec.toNat_ofNat]
    have two : (2 : Nat) ^ 64 = 18446744073709551616 := by rfl
    rw [two, Nat.mod_eq_of_lt lt]
    rw [show BitVec.toNat (0 : BitVec 64) = 0 from rfl, Nat.add_zero]
  rw [val]
  by_cases zero : w = 0
  · subst zero; simp
  · rw [Nat.mod_eq_of_lt (by omega)]
    rw [if_neg (by omega)]
    omega

end Lanius.Mini
