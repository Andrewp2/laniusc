module

public import Lanius.Mini.Semantics
public import Lanius.Mini.Unsigned
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
import all Lanius.Mini.Compiler.P.guardAnd
import all Lanius.Mini.Compiler.P.leftTrue
import all Lanius.Mini.Compiler.P.applyGuard
import all Lanius.Mini.Compiler.P.SrcExpr_guard
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
import all Lanius.Mini.Compiler.P.elementAddress
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

@[expose] public section

/-! Core's `<<` and `>>` as the mini IR's shifts. Core traps on an amount
outside the type's bits, so a shift that returns has an amount below the
word's width, which is the amount x86's masked count keeps. `>>` is
arithmetic on `i32` and `isize` and logical on the unsigned types. -/

namespace Lanius.Mini

open Lanius.Core (Value)
open Semantics

/-- A non-negative `toInt` below `2 ^ (w - 1)` is the number. -/
theorem toNat_of_toInt {w : Nat} (b : BitVec w) (nonneg : 0 ≤ b.toInt) : (b.toNat : Int) = b.toInt := by
  rw [BitVec.toInt_eq_toNat_cond] at nonneg ⊢
  have := b.isLt
  split at nonneg <;> split <;> omega

theorem ofInt_twoPow (w k : Nat) : BitVec.ofInt w (Int.ofNat (2 ^ k)) = BitVec.twoPow w k := by
  rw [show Int.ofNat (2 ^ k) = ((2 ^ k : Nat) : Int) from rfl, BitVec.ofInt_natCast]
  apply BitVec.eq_of_toNat_eq
  rw [BitVec.toNat_twoPow, BitVec.toNat_ofNat]

theorem shl_toInt (w : Nat) (a : BitVec w) (k : Nat) :
    BitVec.ofInt w (a.toInt * Int.ofNat (2 ^ k)) = a <<< k := by
  rw [BitVec.ofInt_mul, BitVec.ofInt_toInt, ofInt_twoPow, BitVec.shiftLeft_eq_mul_twoPow]

/-- The amount of a signed shift that returns: below the width, so the count
x86 keeps. -/
theorem signed_amount {w : Nat} (b : BitVec w) (bits : Nat) (le : bits ≤ w)
    (inRange : ¬(b.toInt < 0 || b.toInt >= Int.ofNat bits) = true) :
    Int.toNat b.toInt = b.toNat ∧ b.toNat < bits := by
  simp only [Bool.or_eq_true, decide_eq_true_eq, not_or, Int.not_lt, ge_iff_le, Int.not_le,
    Int.ofNat_eq_coe] at inRange
  have same := toNat_of_toInt b inRange.1
  have := inRange.2
  constructor <;> omega

variable (a b : BitVec 32)

theorem eval_shl_i32 {v : Value}
    (ev : evalBinaryValue .x86_64 .shiftLeft (.signed .i32 a.toInt) (.signed .i32 b.toInt) = .ok v) :
    v = .signed .i32 (a <<< (b.toNat % 32)).toInt := by
  simp only [evalBinaryValue, beq_self_eq_true, ↓reduceIte, evalSignedBinary] at ev
  split at ev
  · simp at ev
  · rename_i inRange
    obtain ⟨amount, below⟩ := signed_amount b 32 (by decide) inRange
    simp only [Except.ok.injEq] at ev
    rw [← ev, amount, Nat.mod_eq_of_lt below, wrapSigned_i32, shl_toInt]

theorem eval_sar_i32 {v : Value}
    (ev : evalBinaryValue .x86_64 .shiftRight (.signed .i32 a.toInt) (.signed .i32 b.toInt) = .ok v) :
    v = .signed .i32 (a.sshiftRight (b.toNat % 32)).toInt := by
  simp only [evalBinaryValue, beq_self_eq_true, ↓reduceIte, evalSignedBinary_shiftRight] at ev
  split at ev
  · simp at ev
  · rename_i inRange
    obtain ⟨amount, below⟩ := signed_amount b 32 (by decide) inRange
    simp only [Except.ok.injEq] at ev
    rw [← ev, amount, Nat.mod_eq_of_lt below, ← BitVec.toInt_sshiftRight, wrapSigned_i32, BitVec.ofInt_toInt]

variable (x y : BitVec 64)

theorem eval_shl_isize {v : Value}
    (ev : evalBinaryValue .x86_64 .shiftLeft (.signed .isize x.toInt) (.signed .isize y.toInt) = .ok v) :
    v = .signed .isize (x <<< (y.toNat % 64)).toInt := by
  simp only [evalBinaryValue, beq_self_eq_true, ↓reduceIte, evalSignedBinary] at ev
  split at ev
  · simp at ev
  · rename_i inRange
    obtain ⟨amount, below⟩ := signed_amount y 64 (by decide) inRange
    simp only [Except.ok.injEq] at ev
    rw [← ev, amount, Nat.mod_eq_of_lt below, wrapSigned_isize, shl_toInt]

theorem eval_sar_isize {v : Value}
    (ev : evalBinaryValue .x86_64 .shiftRight (.signed .isize x.toInt) (.signed .isize y.toInt) = .ok v) :
    v = .signed .isize (x.sshiftRight (y.toNat % 64)).toInt := by
  simp only [evalBinaryValue, beq_self_eq_true, ↓reduceIte, evalSignedBinary_shiftRight] at ev
  split at ev
  · simp at ev
  · rename_i inRange
    obtain ⟨amount, below⟩ := signed_amount y 64 (by decide) inRange
    simp only [Except.ok.injEq] at ev
    rw [← ev, amount, Nat.mod_eq_of_lt below, ← BitVec.toInt_sshiftRight, wrap_isize]

/-- An unsigned `<<` or `>>` that returns is the 64-bit shift, reduced to the
type's width. -/
theorem eval_uint_shift (k : UintTy) {op : BinOp} {cop : Core.BinaryOp}
    (h : (cop = .shiftLeft ∧ op = .shl) ∨ (cop = .shiftRight ∧ op = .shr)) {v : Value}
    (ev : evalBinaryValue .x86_64 cop (.unsigned k.toCore x.toNat) (.unsigned k.toCore y.toNat) = .ok v) :
    v = .unsigned k.toCore ((op.apply x y).toNat % 2 ^ k.width) := by
  have le : k.width ≤ 64 := by cases k <;> decide
  rcases h with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ <;>
    simp only [evalBinaryValue, beq_self_eq_true, ↓reduceIte, evalUnsignedBinary, wrapUnsigned,
      unsignedModulus, UintTy.bits_toCore] at ev
  all_goals
    split at ev
    · simp at ev
    rename_i below
    have small : y.toNat % 64 = y.toNat := Nat.mod_eq_of_lt (by omega)
    simp only [Except.ok.injEq] at ev
    rw [← ev]
    simp only [BinOp.apply, small]
  · rw [BitVec.toNat_shiftLeft, Nat.shiftLeft_eq, Nat.mod_mod_of_dvd _ (Nat.pow_dvd_pow 2 le)]
  · rw [BitVec.toNat_ushiftRight, Nat.shiftRight_eq_div_pow]

end Lanius.Mini
