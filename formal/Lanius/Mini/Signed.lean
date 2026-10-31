module

public import Lanius.Mini.Unsigned
public import Lanius.Mini.Shifts
-- import all: Lanius.Mini.Compiler
import all Lanius.Mini.Compiler.Types
import all Lanius.Mini.Compiler.P.Lists_empty
import all Lanius.Mini.Compiler.P.DivOp_size
import all Lanius.Mini.Compiler.P.codeSize
import all Lanius.Mini.Compiler.P.compileArgs
import all Lanius.Mini.Compiler.P.arities
import all Lanius.Mini.Compiler.P.FloatTy_rex
import all Lanius.Mini.Compiler.P.FArith_opcode
import all Lanius.Mini.Compiler.P.Code_size
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
import all Lanius.Mini.Compiler.P.UintTy_half
import all Lanius.Mini.Compiler.P.SrcType_size
import all Lanius.Mini.Compiler.P.arithUint
import all Lanius.Mini.Compiler.P.floatApply
import all Lanius.Mini.Compiler.P.lowerShift
import all Lanius.Mini.Compiler.P.arithShiftRight
import all Lanius.Mini.Compiler.P.equality
import all Lanius.Mini.Compiler.P.conjunction
import all Lanius.Mini.Compiler.P.lowerLocal
import all Lanius.Mini.Compiler.P.sintToUint
import all Lanius.Mini.Compiler.P.lowerApply
import all Lanius.Mini.Compiler.P.guardAnd
import all Lanius.Mini.Compiler.P.leftTrue
import all Lanius.Mini.Compiler.P.applyGuard
import all Lanius.Mini.Compiler.P.SrcExpr_guard
import all Lanius.Mini.Compiler.P.repeatType
import all Lanius.Mini.Compiler.P.lowerTagged
import all Lanius.Mini.Compiler.P.armScope
import all Lanius.Mini.Compiler.P.assignFrom
import all Lanius.Mini.Compiler.P.armBodyScope
import all Lanius.Mini.Compiler.P.armPayload
import all Lanius.Mini.Compiler.P.lowerCallSig
import all Lanius.Mini.Compiler.P.consArgs
import all Lanius.Mini.Compiler.P.shortCircuit
import all Lanius.Mini.Compiler.P.evalDivideSint
import all Lanius.Mini.Compiler.P.evalDivide
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
import all Lanius.Mini.Compiler.P.lowerSlice
import all Lanius.Mini.Compiler.P.indexOf
import all Lanius.Mini.Compiler.P.elementAddress
import all Lanius.Mini.Compiler.P.lowerLoadType
import all Lanius.Mini.Compiler.P.wordStride
import all Lanius.Mini.Compiler.P.storeEvalWord
import all Lanius.Mini.Compiler.P.storeArray
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
import all Lanius.Mini.Compiler.P.larger
import all Lanius.Mini.Compiler.P.Inline_arithOf
import all Lanius.Mini.Compiler.P.Inline_lowerSetScalar
import all Lanius.Mini.Compiler.P.Inline_factOr
-- end import all
-- import parts: Lanius.Mini.Compiler norm castTo arithSint orderSint signKey
public import Lanius.Mini.Compiler.P.SrcType_size
public import Lanius.Mini.Compiler.P.arithShiftRight
public import Lanius.Mini.Compiler.P.arithUint
public import Lanius.Mini.Compiler.P.sintToUint
-- end import parts

@[expose] public section

/-! The signed types other than `i32` and `isize`: `i8`, `i16` and `i64`
(`SrcType.sint`). A narrow one's slot is its value as an `i32`; `norm`
brings any 32 bits to the value of the narrow type their low bits are. -/

namespace Lanius.Mini

open Lanius.Core (Value)
open Semantics

theorem UintTy.bits_toSigned (k : UintTy) : Core.SignedIntTy.bits .x86_64 k.toSigned = k.width := by
  cases k <;> rfl

theorem wrapSigned_narrow {k : UintTy} (n : Int) :
    wrapSigned .x86_64 k.toSigned n =
      if n % 2 ^ k.width ≥ 2 ^ (k.width - 1) then n % 2 ^ k.width - 2 ^ k.width else n % 2 ^ k.width := by
  simp only [wrapSigned, signedModulus, signedSignBit, UintTy.bits_toSigned]

theorem wrapSigned_range {k : UintTy} (narrow : k.isWide = false) (n : Int) :
    -2 ^ (k.width - 1) ≤ wrapSigned .x86_64 k.toSigned n ∧ wrapSigned .x86_64 k.toSigned n < 2 ^ (k.width - 1) := by
  rw [wrapSigned_narrow]
  by_cases h : n % 2 ^ k.width ≥ 2 ^ (k.width - 1)
  · rw [if_pos h]
    cases k <;> simp only [UintTy.isWide, Bool.true_eq_false] at narrow <;> simp only [UintTy.width] at h ⊢ <;> omega
  · rw [if_neg h]
    cases k <;> simp only [UintTy.isWide, Bool.true_eq_false] at narrow <;> simp only [UintTy.width] at h ⊢ <;> omega

theorem ofInt_wrap_toInt {k : UintTy} (narrow : k.isWide = false) (n : Int) :
    (BitVec.ofInt 32 (wrapSigned .x86_64 k.toSigned n)).toInt = wrapSigned .x86_64 k.toSigned n := by
  have := wrapSigned_range narrow n
  have : k.width ≤ 32 := by cases k <;> simp_all [UintTy.isWide, UintTy.width]
  have : 2 ^ (k.width - 1) ≤ (2 : Int) ^ 31 := by
    have := Nat.pow_le_pow_right (show 0 < 2 by decide) (show k.width - 1 ≤ 31 by omega)
    exact_mod_cast this
  apply BitVec.toInt_ofInt_eq_self (by decide) <;> simp only [Nat.add_one_sub_one] <;> omega

theorem sext (s : Nat) (y : BitVec 32) (hs : s = 24 ∨ s = 16 ∨ s = 0) :
    ((y <<< s).sshiftRight s).toInt =
      if (y.toNat : Int) % 2 ^ (32 - s) ≥ 2 ^ (31 - s) then (y.toNat : Int) % 2 ^ (32 - s) - 2 ^ (32 - s)
      else (y.toNat : Int) % 2 ^ (32 - s) := by
  have := y.isLt
  rcases hs with rfl | rfl | rfl <;>
    rw [BitVec.toInt_sshiftRight, Int.shiftRight_eq_div_pow, BitVec.toInt_eq_toNat_cond, BitVec.toNat_shiftLeft] <;>
    simp only [Nat.shiftLeft_eq] <;> split <;> split <;> omega

theorem norm_eval {k : UintTy} (narrow : k.isWide = false) (e : Expr) (env : Env) :
    (norm k e).eval env =
      widen (BitVec.ofInt 32 (wrapSigned .x86_64 k.toSigned ((e.eval env).toNat : Int))) := by
  have spare : (low k.spare).toNat % 32 = 32 - k.width ∧ (32 - k.width = 24 ∨ 32 - k.width = 16 ∨ 32 - k.width = 0) := by
    cases k <;> simp_all [UintTy.spare, UintTy.isWide, UintTy.width]
  simp only [norm, Expr.eval, Word.apply, BinOp.apply, spare.1, low_widen]
  apply congrArg widen
  apply BitVec.eq_of_toInt_eq
  rw [sext _ _ spare.2, ofInt_wrap_toInt narrow, wrapSigned_narrow]
  have : k.width ≤ 32 := by cases k <;> simp_all [UintTy.isWide, UintTy.width]
  have := (e.eval env).isLt
  simp only [BitVec.toNat_setWidth]
  rw [show 32 - (32 - k.width) = k.width by omega, show 31 - (32 - k.width) = k.width - 1 by omega]
  have eq : (((e.eval env).toNat % 2 ^ 32 : Nat) : Int) % 2 ^ k.width = ((e.eval env).toNat : Int) % 2 ^ k.width := by
    cases k <;> simp only [UintTy.isWide, Bool.true_eq_false] at narrow <;> simp only [UintTy.width] <;> omega
  rw [eq]

theorem sintHolds_narrow {k : UintTy} (narrow : k.isWide = false) {v : Core.Value} {bits : BitVec 64} :
    k.SintHolds v bits ↔ NarrowHolds k.toSigned k.width v bits := by
  cases k <;> simp_all [UintTy.isWide, UintTy.SintHolds, UintTy.toSigned, UintTy.width]

theorem sintHolds_wide {k : UintTy} (wide : k.isWide = true) {v : Core.Value} {bits : BitVec 64} :
    k.SintHolds v bits ↔ v = .signed k.toSigned bits.toInt := by
  cases k <;> simp_all [UintTy.isWide, UintTy.SintHolds, UintTy.toSigned]

theorem UintTy.width_le {k : UintTy} (narrow : k.isWide = false) : k.width ≤ 32 := by
  cases k <;> simp_all [UintTy.isWide, UintTy.width]

theorem UintTy.width_pos (k : UintTy) : 0 < k.width := by
  cases k <;> simp [UintTy.width]

theorem dvd32 {k : UintTy} (narrow : k.isWide = false) : (2 : Int) ^ k.width ∣ 2 ^ 32 := by
  cases k <;> simp only [UintTy.isWide, Bool.true_eq_false] at narrow <;> simp only [UintTy.width] <;> decide

/-- A narrow value Core wraps from `m`, held by 32 bits as wide as `m`'s low bits. -/
theorem narrow_of_wrap {k : UintTy} (narrow : k.isWide = false) {m : Int} {z : BitVec 64}
    (hz : (z.toNat : Int) % 2 ^ k.width = m % 2 ^ k.width) :
    k.SintHolds (.signed k.toSigned (wrapSigned .x86_64 k.toSigned m))
      (widen (BitVec.ofInt 32 (wrapSigned .x86_64 k.toSigned (z.toNat : Int)))) := by
  rw [sintHolds_narrow narrow]
  have same : wrapSigned .x86_64 k.toSigned (z.toNat : Int) = wrapSigned .x86_64 k.toSigned m := by
    rw [wrapSigned_narrow, wrapSigned_narrow, hz]
  rw [same]
  have range := wrapSigned_range narrow m
  refine ⟨?_, by rw [low_widen], ?_⟩
  · simp only [low_widen, ofInt_wrap_toInt narrow]
  · simp only [low_widen, ofInt_wrap_toInt narrow]; exact range

theorem toNat_emod32 (x : BitVec 32) : (x.toNat : Int) % 2 ^ 32 = x.toInt % 2 ^ 32 := by
  rw [BitVec.toInt_eq_toNat_cond]
  have := x.isLt
  split <;> omega

theorem widen_toNat_int (x : BitVec 32) : ((widen x).toNat : Int) = x.toNat := by
  simp only [BitVec.toNat_setWidth]
  have := x.isLt
  omega

/-- 32 bits as wide as an integer mod `2^32` are as wide mod `2^k.width`. -/
theorem emod_width {k : UintTy} (narrow : k.isWide = false) {z : BitVec 32} {m : Int}
    (h : z.toInt % 2 ^ 32 = m % 2 ^ 32) : ((widen z).toNat : Int) % 2 ^ k.width = m % 2 ^ k.width := by
  rw [widen_toNat_int, ← Int.emod_emod_of_dvd _ (dvd32 narrow), toNat_emod32, h, Int.emod_emod_of_dvd _ (dvd32 narrow)]

theorem sbits {k : UintTy} (narrow : k.isWide = false) (x : BitVec 32) :
    (x.toInt % 2 ^ k.width).toNat = x.toNat % 2 ^ k.width := by
  have : x.toInt % 2 ^ k.width = ((x.toNat % 2 ^ k.width : Nat) : Int) := by
    rw [← Int.emod_emod_of_dvd _ (dvd32 narrow), ← toNat_emod32, Int.emod_emod_of_dvd _ (dvd32 narrow)]
    simp
  rw [this, Int.toNat_natCast]

theorem bit_mod {w : Nat} {f : Nat → Nat → Nat} (hf : ∀ a b, f a b % 2 ^ w = f (a % 2 ^ w) (b % 2 ^ w))
    (a b : Nat) : ((f a b : Nat) : Int) % 2 ^ w = Int.ofNat (f (a % 2 ^ w) (b % 2 ^ w)) % 2 ^ w := by
  have cast (n : Nat) : (n : Int) % 2 ^ w = ((n % 2 ^ w : Nat) : Int) := by
    rw [Int.natCast_emod, Int.natCast_pow]; rfl
  rw [Int.ofNat_eq_natCast, cast, cast, hf, hf, Nat.mod_mod, Nat.mod_mod]

theorem bmod32 (a : Int) : a.bmod (2 ^ 32) % 2 ^ 32 = a % 2 ^ 32 := by
  rw [Int.bmod_def]
  split <;> omega

theorem narrow_binop {k : UintTy} (narrow : k.isWide = false) {op : BinOp} {cop : Core.BinaryOp}
    (h : (cop = .add ∧ op = .add) ∨ (cop = .subtract ∧ op = .sub) ∨ (cop = .multiply ∧ op = .mul) ∨
      (cop = .bitAnd ∧ op = .and) ∨ (cop = .bitOr ∧ op = .or) ∨ (cop = .bitXor ∧ op = .xor))
    {el er : Expr} {env : Env} {vl vr v : Core.Value}
    (hl : k.SintHolds vl (el.eval env)) (hr : k.SintHolds vr (er.eval env))
    (ev : evalBinaryValue .x86_64 cop vl vr = .ok v) :
    k.SintHolds v ((norm k (.binary .s32 op el er)).eval env) := by
  rw [sintHolds_narrow narrow] at hl hr
  obtain ⟨rfl, -, -⟩ := hl
  obtain ⟨rfl, -, -⟩ := hr
  rw [norm_eval narrow]
  simp only [Expr.eval, Word.apply]
  generalize low (el.eval env) = x at ev ⊢
  generalize low (er.eval env) = y at ev ⊢
  rcases h with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ <;>
    simp only [evalBinaryValue, beq_self_eq_true, ↓reduceIte, evalSignedBinary, Except.ok.injEq] at ev <;>
    subst ev <;> apply narrow_of_wrap narrow
  · apply emod_width narrow
    simp only [BinOp.apply, BitVec.toInt_add, bmod32]
  · apply emod_width narrow
    simp only [BinOp.apply, BitVec.toInt_sub, bmod32]
  · apply emod_width narrow
    simp only [BinOp.apply, BitVec.toInt_mul, bmod32]
  all_goals
    rw [widen_toNat_int]
    simp only [BinOp.apply, BitVec.toNat_and, BitVec.toNat_or, BitVec.toNat_xor, signedBits,
      signedModulus, UintTy.bits_toSigned, sbits narrow]
  · exact bit_mod (f := Nat.land) (fun _ _ => Nat.and_mod_two_pow) _ _
  · exact bit_mod (f := Nat.lor) (fun _ _ => Nat.or_mod_two_pow) _ _
  · exact bit_mod (f := Nat.xor) (fun _ _ => Nat.xor_mod_two_pow) _ _

theorem emod_width_nat {k : UintTy} (narrow : k.isWide = false) {z : BitVec 32} {m : Int}
    (h : (z.toNat : Int) % 2 ^ 32 = m % 2 ^ 32) : ((widen z).toNat : Int) % 2 ^ k.width = m % 2 ^ k.width := by
  rw [widen_toNat_int, ← Int.emod_emod_of_dvd _ (dvd32 narrow), h, Int.emod_emod_of_dvd _ (dvd32 narrow)]

theorem narrow_shift {k : UintTy} (narrow : k.isWide = false) {op : BinOp} {cop : Core.BinaryOp}
    (h : (cop = .shiftLeft ∧ op = .shl) ∨ (cop = .shiftRight ∧ op = .sar))
    {el er : Expr} {env : Env} {vl vr v : Core.Value}
    (hl : k.SintHolds vl (el.eval env)) (hr : k.SintHolds vr (er.eval env))
    (ev : evalBinaryValue .x86_64 cop vl vr = .ok v) :
    k.SintHolds v ((norm k (.binary .s32 op el er)).eval env) := by
  rw [sintHolds_narrow narrow] at hl hr
  obtain ⟨rfl, -, -⟩ := hl
  obtain ⟨rfl, -, -⟩ := hr
  rw [norm_eval narrow]
  simp only [Expr.eval, Word.apply]
  generalize low (el.eval env) = x at ev ⊢
  generalize low (er.eval env) = y at ev ⊢
  have le := UintTy.width_le narrow
  rcases h with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ <;>
    simp only [evalBinaryValue, beq_self_eq_true, ↓reduceIte, evalSignedBinary, UintTy.bits_toSigned] at ev
  all_goals
    split at ev
    · simp at ev
    rename_i inRange
    obtain ⟨amount, below⟩ := signed_amount y k.width le inRange
    simp only [Except.ok.injEq] at ev
    subst ev
    apply narrow_of_wrap narrow
    apply emod_width narrow
    simp only [BinOp.apply, amount, Nat.mod_eq_of_lt (show y.toNat < 32 by omega)]
  · rw [← shl_toInt, BitVec.toInt_ofInt, bmod32]
  · rw [BitVec.toInt_sshiftRight, arithmeticShiftRight_eq]

theorem narrow_neg {k : UintTy} (narrow : k.isWide = false) {e : Expr} {env : Env} {v w : Core.Value}
    (h : k.SintHolds v (e.eval env)) (ev : evalUnaryValue .x86_64 .negate v = .ok w) :
    k.SintHolds w ((norm k (.neg e)).eval env) := by
  rw [sintHolds_narrow narrow] at h
  obtain ⟨rfl, -, -⟩ := h
  rw [norm_eval narrow]
  simp only [evalUnaryValue, Except.ok.injEq] at ev
  subst ev
  apply narrow_of_wrap narrow
  apply emod_width narrow
  simp only [BitVec.toInt_neg, bmod32]

theorem eval_order_signed (t : Core.SignedIntTy) (a b : BitVec 32) (cop : Core.BinaryOp) (op : CmpOp)
    (h : (cop = .less ∧ op = .lt) ∨ (cop = .lessEqual ∧ op = .le) ∨
      (cop = .greater ∧ op = .gt) ∨ (cop = .greaterEqual ∧ op = .ge)) :
    evalBinaryValue .x86_64 cop (.signed t a.toInt) (.signed t b.toInt) =
      .ok (.boolean (op.holds a b)) := by
  rcases h with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ <;>
    simp [evalBinaryValue, evalSignedBinary, CmpOp.holds, BitVec.slt, BitVec.sle]

/-- Core's 64-bit signed types compute alike: `i64` as `isize` on x86-64. -/
def retag (t : Core.SignedIntTy) : Core.Value → Core.Value
  | .signed _ n => .signed t n
  | v => v

theorem evalSignedBinary_i64 (op : Core.BinaryOp) (a b : Int) :
    evalSignedBinary .x86_64 op .i64 a b = (evalSignedBinary .x86_64 op .isize a b).map (retag .i64) := by
  have w : wrapSigned .x86_64 .i64 = wrapSigned .x86_64 .isize := rfl
  have s : signedBits .x86_64 .i64 = signedBits .x86_64 .isize := rfl
  have m : signedSignBit .x86_64 .i64 = signedSignBit .x86_64 .isize := rfl
  have bits : Core.SignedIntTy.bits .x86_64 .i64 = Core.SignedIntTy.bits .x86_64 .isize := rfl
  cases op <;> simp only [evalSignedBinary, w, s, m, bits] <;> (try split) <;> (try split) <;> rfl

theorem evalBinaryValue_i64 (op : Core.BinaryOp) (a b : Int) :
    evalBinaryValue .x86_64 op (.signed .i64 a) (.signed .i64 b) =
      (evalBinaryValue .x86_64 op (.signed .isize a) (.signed .isize b)).map (retag .i64) := by
  cases op <;> simp [evalBinaryValue, scalarEqual, evalSignedBinary_i64, Except.map, retag]

theorem UintTy.wide_cases {k : UintTy} (wide : k.isWide = true) : k = .uint64 ∨ k = .usize := by
  cases k <;> simp_all [UintTy.isWide]

theorem wide_binop {k : UintTy} (wide : k.isWide = true) {op : BinOp} {cop : Core.BinaryOp}
    (h : (cop = .add ∧ op = .add) ∨ (cop = .subtract ∧ op = .sub) ∨ (cop = .multiply ∧ op = .mul) ∨
      (cop = .bitAnd ∧ op = .and) ∨ (cop = .bitOr ∧ op = .or) ∨ (cop = .bitXor ∧ op = .xor))
    {a b : BitVec 64} {vl vr v : Value} (hl : k.SintHolds vl a) (hr : k.SintHolds vr b)
    (ev : evalBinaryValue .x86_64 cop vl vr = .ok v) : k.SintHolds v (op.apply a b) := by
  rw [sintHolds_wide wide] at hl hr ⊢
  subst hl hr
  rcases UintTy.wide_cases wide with rfl | rfl <;> simp only [UintTy.toSigned] at ev ⊢
  · rw [evalBinaryValue_i64, eval_isize_binop _ _ h] at ev
    simp only [Except.map, retag, Except.ok.injEq] at ev
    exact ev.symm
  · rw [eval_isize_binop _ _ h, Except.ok.injEq] at ev
    exact ev.symm

theorem wide_shift {k : UintTy} (wide : k.isWide = true) {op : BinOp} {cop : Core.BinaryOp}
    (h : (cop = .shiftLeft ∧ op = .shl) ∨ (cop = .shiftRight ∧ op = .sar))
    {a b : BitVec 64} {vl vr v : Value} (hl : k.SintHolds vl a) (hr : k.SintHolds vr b)
    (ev : evalBinaryValue .x86_64 cop vl vr = .ok v) : k.SintHolds v (op.apply a b) := by
  rw [sintHolds_wide wide] at hl hr ⊢
  subst hl hr
  have isize : ∀ {v' : Value}, evalBinaryValue .x86_64 cop (.signed .isize a.toInt) (.signed .isize b.toInt) = .ok v' →
      v' = .signed .isize (op.apply a b).toInt := by
    intro v' ev'
    rcases h with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩
    · exact eval_shl_isize _ _ ev'
    · exact eval_sar_isize _ _ ev'
  rcases UintTy.wide_cases wide with rfl | rfl <;> simp only [UintTy.toSigned] at ev ⊢
  · rw [evalBinaryValue_i64] at ev
    cases ev' : evalBinaryValue .x86_64 cop (.signed .isize a.toInt) (.signed .isize b.toInt) with
    | error => simp [ev', Except.map] at ev
    | ok v' =>
      rw [ev'] at ev
      simp only [Except.map, Except.ok.injEq] at ev
      rw [← ev, isize ev', retag]
  · exact isize ev

theorem wide_order {k : UintTy} (wide : k.isWide = true) {cop : Core.BinaryOp} {op : CmpOp}
    (h : (cop = .less ∧ op = .lt) ∨ (cop = .lessEqual ∧ op = .le) ∨
      (cop = .greater ∧ op = .gt) ∨ (cop = .greaterEqual ∧ op = .ge))
    {a b : BitVec 64} {vl vr v : Value} (hl : k.SintHolds vl a) (hr : k.SintHolds vr b)
    (ev : evalBinaryValue .x86_64 cop vl vr = .ok v) : v = .boolean (op.holdsU (flip a) (flip b)) := by
  rw [sintHolds_wide wide] at hl hr
  subst hl hr
  rcases UintTy.wide_cases wide with rfl | rfl <;> simp only [UintTy.toSigned] at ev
  · rw [evalBinaryValue_i64, eval_isize_order _ _ h] at ev
    simp only [Except.map, retag, Except.ok.injEq] at ev
    exact ev.symm
  · rw [eval_isize_order _ _ h, Except.ok.injEq] at ev
    exact ev.symm

theorem narrow_order {k : UintTy} (narrow : k.isWide = false) {cop : Core.BinaryOp} {op : CmpOp}
    (h : (cop = .less ∧ op = .lt) ∨ (cop = .lessEqual ∧ op = .le) ∨
      (cop = .greater ∧ op = .gt) ∨ (cop = .greaterEqual ∧ op = .ge))
    {a b : BitVec 64} {vl vr v : Value} (hl : k.SintHolds vl a) (hr : k.SintHolds vr b)
    (ev : evalBinaryValue .x86_64 cop vl vr = .ok v) : v = .boolean (op.holds (low a) (low b)) := by
  rw [sintHolds_narrow narrow] at hl hr
  obtain ⟨rfl, -, -⟩ := hl
  obtain ⟨rfl, -, -⟩ := hr
  rw [eval_order_signed _ _ _ _ _ h, Except.ok.injEq] at ev
  exact ev.symm

/-- Equal signed values: their slots are equal, on the low 32 bits when narrow. -/
theorem toInt_beq (a b : BitVec 32) : (a.toInt == b.toInt) = (a == b) := by
  rw [Bool.eq_iff_iff]
  simp [BitVec.toInt_inj]

theorem sint_equal {k : UintTy} {cop : Core.BinaryOp} {op : CmpOp}
    (h : (cop = .equal ∧ op = .eq) ∨ (cop = .notEqual ∧ op = .ne))
    {a b : BitVec 64} {vl vr v : Value} (hl : k.SintHolds vl a) (hr : k.SintHolds vr b)
    (ev : evalBinaryValue .x86_64 cop vl vr = .ok v) :
    v = .boolean (k.signedWord.holds op a b) := by
  by_cases wide : k.isWide = true
  · rw [sintHolds_wide wide] at hl hr
    subst hl hr
    simp only [UintTy.signedWord, wide, ↓reduceIte, Word.holds]
    rcases h with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ <;>
      simp [evalBinaryValue, scalarEqual, CmpOp.holdsU, toInt64_beq, bne] at ev ⊢ <;> exact ev.symm
  · rw [sintHolds_narrow (by simpa using wide)] at hl hr
    obtain ⟨rfl, -, -⟩ := hl
    obtain ⟨rfl, -, -⟩ := hr
    simp only [UintTy.signedWord, wide, Bool.false_eq_true, ↓reduceIte, Word.holds]
    rcases h with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ <;>
      simp only [evalBinaryValue, scalarEqual, beq_self_eq_true, ↓reduceIte, toInt_beq,
        Except.ok.injEq] at ev <;> rw [← ev] <;> rfl

theorem wide_neg {k : UintTy} (wide : k.isWide = true) {a : BitVec 64} {v w : Value}
    (h : k.SintHolds v a) (ev : evalUnaryValue .x86_64 .negate v = .ok w) : k.SintHolds w (0 - a) := by
  rw [sintHolds_wide wide] at h ⊢
  subst h
  have wrap : wrapSigned .x86_64 k.toSigned = wrapSigned .x86_64 .isize := by
    rcases UintTy.wide_cases wide with rfl | rfl <;> rfl
  simp only [evalUnaryValue, Except.ok.injEq, wrap] at ev
  rw [← ev]
  have := eval_isize_neg a
  simp only [evalUnaryValue, Except.ok.injEq, Value.signed.injEq, true_and] at this
  rw [this]

/-! Casts. Core's cast of a signed value reads only its number, so a signed
source is as good as an `i32` (narrow) or an `isize` (wide) with its bits. -/

theorem cast_signed_source (dst : Core.ScalarTy) (t u : Core.SignedIntTy) (n : Int) :
    evalScalarCast .x86_64 dst (.signed t n) = evalScalarCast .x86_64 dst (.signed u n) := by
  cases dst <;> rfl

theorem cast_i64 (v : Value) :
    evalScalarCast .x86_64 (.signed .i64) v = (evalScalarCast .x86_64 (.signed .isize) v).map (retag .i64) := by
  cases v <;> rfl

/-- The type whose slots a signed type's are: `isize` when wide, else `i32`. -/
def UintTy.base (k : UintTy) : SrcType := if k.isWide then .isize else .i32

theorem UintTy.base_sintKind (k : UintTy) : k.base.sintKind = none := by
  unfold UintTy.base; split <;> rfl

theorem sint_base {k : UintTy} {w : Value} {bits : BitVec 64} (h : (SrcType.sint k).Holds w bits) :
    ∃ w', k.base.Holds w' bits ∧ ∀ dst, evalScalarCast .x86_64 dst w = evalScalarCast .x86_64 dst w' := by
  simp only [SrcType.Holds] at h
  by_cases wide : k.isWide = true
  · rw [sintHolds_wide wide] at h
    subst h
    refine ⟨.signed .isize bits.toInt, ?_, fun dst => cast_signed_source dst _ _ _⟩
    simp only [UintTy.base, wide, ↓reduceIte, SrcType.Holds]
  · rw [sintHolds_narrow (by simpa using wide)] at h
    obtain ⟨rfl, hb, -⟩ := h
    refine ⟨.signed .i32 (low bits).toInt, ?_, fun dst => cast_signed_source dst _ _ _⟩
    simp only [UintTy.base, wide, Bool.false_eq_true, ↓reduceIte, SrcType.Holds]
    exact ⟨trivial, hb⟩

theorem castTo_base {ty : SrcType} {inner : Typed} {k : UintTy} (hty : inner.ty = .sint k) :
    castTo ty inner = castTo ty { inner with ty := k.base } := by
  by_cases wide : k.isWide = true <;>
    cases ty <;> simp [castTo, castToI32, castToUint, castToIsize, castToSint, hty, UintTy.base, wide,
      sintToI32, sintToUint, sintToWide, SrcType.isScalar, SrcType.isBool, SrcType.isPtr, castToFloat,
      UintTy.signedWord, SrcType.isFloatAny]

theorem toInt64_emod_width {k : UintTy} (narrow : k.isWide = false) (b : BitVec 64) :
    (b.toNat : Int) % 2 ^ k.width = b.toInt % 2 ^ k.width := by
  have dvd : (2 : Int) ^ k.width ∣ 18446744073709551616 := by
    cases k <;> simp only [UintTy.isWide, Bool.true_eq_false] at narrow <;> simp only [UintTy.width] <;> decide
  rw [← Int.emod_emod_of_dvd b.toInt dvd, toInt64_emod]

/-- A cast to a narrow signed type is `norm` of the source's slot. -/
theorem narrow_cast_holds {k : UintTy} (narrow : k.isWide = false) {ty : SrcType}
    (scalar : (ty.isScalar && !ty.isBool && !ty.isPtr && !ty.isFloatAny) = true) {w result : Value} {e : Expr}
    {env : Env} (holds : ty.Holds w (e.eval env))
    (casted : evalScalarCast .x86_64 (.signed k.toSigned) w = .ok result) :
    k.SintHolds result ((norm k e).eval env) := by
  rw [norm_eval narrow]
  generalize e.eval env = b at holds ⊢
  cases ty with
  | i32 =>
    obtain ⟨rfl, hb⟩ := holds
    simp only [evalScalarCast, Except.ok.injEq] at casted
    subst casted
    apply narrow_of_wrap narrow
    rw [hb]
    exact emod_width narrow (by rw [low_widen])
  | uint _ =>
    obtain ⟨rfl, -⟩ := holds
    simp only [evalScalarCast, Except.ok.injEq] at casted
    subst casted
    exact narrow_of_wrap narrow rfl
  | isize =>
    simp only [SrcType.Holds] at holds
    subst holds
    simp only [evalScalarCast, Except.ok.injEq] at casted
    subst casted
    exact narrow_of_wrap narrow (toInt64_emod_width narrow b)
  | char =>
    obtain ⟨rfl, small⟩ := holds
    simp only [evalScalarCast, Except.ok.injEq] at casted
    subst casted
    apply narrow_of_wrap narrow
    simp [Nat.mod_eq_of_lt small]
  | float _ => simp [SrcType.isFloatAny] at scalar
  | sint k' =>
    simp only [SrcType.Holds] at holds
    by_cases wide' : k'.isWide = true
    · rw [sintHolds_wide wide'] at holds
      subst holds
      simp only [evalScalarCast, Except.ok.injEq] at casted
      subst casted
      exact narrow_of_wrap narrow (toInt64_emod_width narrow b)
    · rw [sintHolds_narrow (by simpa using wide')] at holds
      obtain ⟨rfl, hb, -⟩ := holds
      simp only [evalScalarCast, Except.ok.injEq] at casted
      subst casted
      apply narrow_of_wrap narrow
      rw [hb]
      exact emod_width narrow (by rw [low_widen])
  | bool | ptr => simp [SrcType.isScalar, SrcType.isBool, SrcType.isPtr] at scalar
  | struct | enum | slice | array | unit => simp [SrcType.Holds] at holds

theorem holds_compare (c : Bool) : SrcType.Holds .bool (.boolean c) (if c then 1 else 0) :=
  ⟨c, rfl, by cases c <;> rfl⟩

/-- `signKey` flips the sign bit. -/
theorem signKey_eval (e : Expr) (env : Env) : (signKey e).eval env = flip (e.eval env) := by
  simp only [signKey, Expr.eval, Word.apply, BinOp.apply, flip]

theorem SrcType.eq_of_isSint {ty : SrcType} {k : UintTy} (h : ty.isSint k = true) : ty = .sint k := by
  cases ty <;> simp only [SrcType.isSint, decide_eq_true_eq, reduceCtorEq, beq_iff_eq] at h ⊢
  rename_i k'
  cases k <;> cases k' <;> simp_all [UintTy.code]

theorem SrcType.eq_of_sintKind {ty : SrcType} {k : UintTy} (h : ty.sintKind = some k) : ty = .sint k := by
  cases ty <;> simp_all [SrcType.sintKind]

/-- Signed arithmetic other than `i32`'s and `isize`'s holds Core's result. -/
theorem arithSint_holds {op : BinOp} {cop : Core.BinaryOp}
    (h : (cop = .add ∧ op = .add) ∨ (cop = .subtract ∧ op = .sub) ∨ (cop = .multiply ∧ op = .mul) ∨
      (cop = .bitAnd ∧ op = .and) ∨ (cop = .bitOr ∧ op = .or) ∨ (cop = .bitXor ∧ op = .xor) ∨
      (cop = .shiftLeft ∧ op = .shl) ∨ (cop = .shiftRight ∧ op = .sar))
    {tl tr t : Typed} {env : Env} {vl vr v : Value}
    (lowered : arithSint op tl tr tl.ty.sintKind = some t)
    (holdsl : tl.ty.Holds vl (tl.expr.eval env)) (holdsr : tr.ty.Holds vr (tr.expr.eval env))
    (ev : evalBinaryValue .x86_64 cop vl vr = .ok v) : t.ty.Holds v (t.expr.eval env) := by
  cases hk : tl.ty.sintKind with
  | none => simp [hk, arithSint] at lowered
  | some k =>
    rw [hk] at lowered
    rw [SrcType.eq_of_sintKind hk] at holdsl
    simp only [arithSint] at lowered
    split at lowered
    · rename_i both
      simp only [Bool.and_eq_true] at both
      rw [SrcType.eq_of_isSint both.1] at holdsr
      simp only [Option.some.injEq] at lowered
      subst lowered
      show k.SintHolds v (op.apply _ _)
      rcases h with h | h | h | h | h | h | h | h
      · exact wide_binop both.2 (.inl h) holdsl holdsr ev
      · exact wide_binop both.2 (.inr (.inl h)) holdsl holdsr ev
      · exact wide_binop both.2 (.inr (.inr (.inl h))) holdsl holdsr ev
      · exact wide_binop both.2 (.inr (.inr (.inr (.inl h)))) holdsl holdsr ev
      · exact wide_binop both.2 (.inr (.inr (.inr (.inr (.inl h))))) holdsl holdsr ev
      · exact wide_binop both.2 (.inr (.inr (.inr (.inr (.inr h))))) holdsl holdsr ev
      · exact wide_shift both.2 (.inl h) holdsl holdsr ev
      · exact wide_shift both.2 (.inr h) holdsl holdsr ev
    split at lowered
    · rename_i wide hr
      have narrow : k.isWide = false := by simpa [hr] using wide
      rw [SrcType.eq_of_isSint hr] at holdsr
      simp only [Option.some.injEq] at lowered
      subst lowered
      show k.SintHolds v _
      rcases h with h | h | h | h | h | h | h | h
      · exact narrow_binop narrow (.inl h) holdsl holdsr ev
      · exact narrow_binop narrow (.inr (.inl h)) holdsl holdsr ev
      · exact narrow_binop narrow (.inr (.inr (.inl h))) holdsl holdsr ev
      · exact narrow_binop narrow (.inr (.inr (.inr (.inl h)))) holdsl holdsr ev
      · exact narrow_binop narrow (.inr (.inr (.inr (.inr (.inl h))))) holdsl holdsr ev
      · exact narrow_binop narrow (.inr (.inr (.inr (.inr (.inr h))))) holdsl holdsr ev
      · exact narrow_shift narrow (.inl h) holdsl holdsr ev
      · exact narrow_shift narrow (.inr h) holdsl holdsr ev
    · simp at lowered

/-- A signed order other than `i32`'s and `isize`'s holds Core's result. -/
theorem orderSint_holds {op : CmpOp} {cop : Core.BinaryOp}
    (h : (cop = .less ∧ op = .lt) ∨ (cop = .lessEqual ∧ op = .le) ∨
      (cop = .greater ∧ op = .gt) ∨ (cop = .greaterEqual ∧ op = .ge))
    {tl tr t : Typed} {env : Env} {vl vr v : Value}
    (lowered : orderSint op tl tr tl.ty.sintKind = some t)
    (holdsl : tl.ty.Holds vl (tl.expr.eval env)) (holdsr : tr.ty.Holds vr (tr.expr.eval env))
    (ev : evalBinaryValue .x86_64 cop vl vr = .ok v) : t.ty.Holds v (t.expr.eval env) := by
  cases hk : tl.ty.sintKind with
  | none => simp [hk, orderSint] at lowered
  | some k =>
    rw [hk] at lowered
    rw [SrcType.eq_of_sintKind hk] at holdsl
    simp only [orderSint] at lowered
    split at lowered
    · rename_i both
      simp only [Bool.and_eq_true] at both
      rw [SrcType.eq_of_isSint both.1] at holdsr
      simp only [Option.some.injEq] at lowered
      subst lowered
      rw [wide_order both.2 h holdsl holdsr ev]
      simp only [Expr.eval, Word.holds, signKey_eval]
      exact holds_compare _
    split at lowered
    · rename_i wide hr
      have narrow : k.isWide = false := by simpa [hr] using wide
      rw [SrcType.eq_of_isSint hr] at holdsr
      simp only [Option.some.injEq] at lowered
      subst lowered
      rw [narrow_order narrow h holdsl holdsr ev]
      simp only [Expr.eval, Word.holds]
      exact holds_compare _
    · simp at lowered

theorem arithSint_types {op : BinOp} {tl tr t : Typed} (lowered : arithSint op tl tr tl.ty.sintKind = some t) :
    ∃ k, tl.ty = .sint k ∧ tr.ty = .sint k ∧ t.ty = .sint k := by
  cases hk : tl.ty.sintKind with
  | none => simp [hk, arithSint] at lowered
  | some k =>
    rw [hk] at lowered
    simp only [arithSint] at lowered
    split at lowered
    · rename_i both
      simp only [Bool.and_eq_true] at both
      simp only [Option.some.injEq] at lowered
      subst lowered
      exact ⟨k, SrcType.eq_of_sintKind hk, SrcType.eq_of_isSint both.1, rfl⟩
    split at lowered
    · rename_i hr
      simp only [Option.some.injEq] at lowered
      subst lowered
      exact ⟨k, SrcType.eq_of_sintKind hk, SrcType.eq_of_isSint hr, rfl⟩
    · simp at lowered

theorem orderSint_types {op : CmpOp} {tl tr t : Typed} (lowered : orderSint op tl tr tl.ty.sintKind = some t) :
    ∃ k, tl.ty = .sint k ∧ tr.ty = .sint k ∧ t.ty = .bool := by
  cases hk : tl.ty.sintKind with
  | none => simp [hk, orderSint] at lowered
  | some k =>
    rw [hk] at lowered
    simp only [orderSint] at lowered
    split at lowered
    · rename_i both
      simp only [Bool.and_eq_true] at both
      simp only [Option.some.injEq] at lowered
      subst lowered
      exact ⟨k, SrcType.eq_of_sintKind hk, SrcType.eq_of_isSint both.1, rfl⟩
    split at lowered
    · rename_i hr
      simp only [Option.some.injEq] at lowered
      subst lowered
      exact ⟨k, SrcType.eq_of_sintKind hk, SrcType.eq_of_isSint hr, rfl⟩
    · simp at lowered

/-- A shift Core evaluates has its amount below the signed type's width. -/
theorem amount_sint {k : UintTy} {cop : Core.BinaryOp} (shift : cop = .shiftLeft ∨ cop = .shiftRight)
    {a b : BitVec 64} {vl vr v : Value} (hl : k.SintHolds vl a) (hr : k.SintHolds vr b)
    (ev : evalBinaryValue .x86_64 cop vl vr = .ok v) : b.toNat < k.width := by
  have amount : ∀ {n : Nat} (y : BitVec n) {A : Int} {u : Value}, k.width ≤ n →
      evalBinaryValue .x86_64 cop (.signed k.toSigned A) (.signed k.toSigned y.toInt) = .ok u → y.toNat < k.width := by
    intro n y A u le ev
    rcases shift with rfl | rfl <;>
      simp only [evalBinaryValue, beq_self_eq_true, ↓reduceIte, evalSignedBinary,
        UintTy.bits_toSigned] at ev
    all_goals
      split at ev
      · simp at ev
      rename_i inRange
      exact (signed_amount y k.width le inRange).2
  by_cases wide : k.isWide = true
  · rw [sintHolds_wide wide] at hl hr
    subst hl hr
    exact amount b (by rw [UintTy.width_of_wide wide]; exact Nat.le_refl _) ev
  · have narrow : k.isWide = false := by simpa using wide
    rw [sintHolds_narrow narrow] at hl hr
    obtain ⟨rfl, -, -⟩ := hl
    obtain ⟨rfl, hb, -⟩ := hr
    have := amount (low b) (UintTy.width_le narrow) ev
    rw [hb]
    simp only [BitVec.toNat_setWidth] at this ⊢
    omega

end Lanius.Mini
