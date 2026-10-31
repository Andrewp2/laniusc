module

public import Lanius.Mini.Signed
-- import all: Lanius.Mini.Compiler
import all Lanius.Mini.Compiler.Types
import all Lanius.Mini.Compiler.P.Lists_empty
import all Lanius.Mini.Compiler.P.DivOp_size
import all Lanius.Mini.Compiler.P.codeSize
import all Lanius.Mini.Compiler.P.compileArgs
import all Lanius.Mini.Compiler.P.arities
import all Lanius.Mini.Compiler.P.FloatTy_rex
import all Lanius.Mini.Compiler.P.FArith_opcode
import all Lanius.Mini.Compiler.P.loadAtBytes
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
-- import parts: Lanius.Mini.Compiler shiftWidth
public import Lanius.Mini.Compiler.P.guardAnd
-- end import parts

@[expose] public section

/-! A shift by an amount of another integer type than its left operand's
(`lowerShift`): Core evaluates it as a shift by the amount's number
(`evalShiftBy`), which traps unless it is below the left operand's width, so
the amount's slot then holds it as the left operand's type would
(`shift_retype`). -/

namespace Lanius.Mini

open Lanius.Core (Value)
open Lanius.Semantics (evalBinaryValue evalShiftBy evalSignedBinary evalUnsignedBinary)


/-- A shift by a signed amount is a shift by its number. -/
theorem shift_signedAmount {tgt : Core.Target} {cop : Core.BinaryOp} (shift : cop = .shiftLeft ∨ cop = .shiftRight)
    {l : Value} (int : (∃ t a, l = .signed t a) ∨ (∃ t a, l = .unsigned t a)) (t' : Core.SignedIntTy) (n : Int) :
    evalBinaryValue tgt cop l (.signed t' n) = evalShiftBy tgt cop l n := by
  rcases int with ⟨t, a, rfl⟩ | ⟨t, a, rfl⟩
  · rcases shift with rfl | rfl <;> simp only [evalBinaryValue] <;> split <;> (try rfl)
    all_goals rename_i same; obtain rfl := beq_iff_eq.mp same; rfl
  · rcases shift with rfl | rfl <;> rfl

theorem shift_unsignedAmount {tgt : Core.Target} {cop : Core.BinaryOp} (shift : cop = .shiftLeft ∨ cop = .shiftRight)
    {l : Value} (int : (∃ t a, l = .signed t a) ∨ (∃ t a, l = .unsigned t a)) (t' : Core.UnsignedIntTy) (n : Nat) :
    evalBinaryValue tgt cop l (.unsigned t' n) = evalShiftBy tgt cop l (Int.ofNat n) := by
  rcases int with ⟨t, a, rfl⟩ | ⟨t, a, rfl⟩
  · rcases shift with rfl | rfl <;> rfl
  · rcases shift with rfl | rfl <;> simp only [evalBinaryValue] <;> split <;> (try rfl)
    all_goals
      rename_i same; obtain rfl := beq_iff_eq.mp same
      simp [evalShiftBy]

theorem signedShift_range {cop : Core.BinaryOp} (shift : cop = .shiftLeft ∨ cop = .shiftRight)
    {t : Core.SignedIntTy} {a n : Int} {v : Value} (h : evalSignedBinary .x86_64 cop t a n = .ok v) :
    0 ≤ n ∧ n < Int.ofNat (t.bits .x86_64) := by
  rcases shift with rfl | rfl <;> simp only [evalSignedBinary] at h <;> split at h
  all_goals first
    | (simp at h; done)
    | (rename_i inRange; simp only [Bool.or_eq_true, decide_eq_true_eq, not_or] at inRange; omega)

theorem unsignedShift_range {cop : Core.BinaryOp} (shift : cop = .shiftLeft ∨ cop = .shiftRight)
    {t : Core.UnsignedIntTy} {a n : Nat} {v : Value} (h : evalUnsignedBinary .x86_64 cop t a n = .ok v) :
    n < t.bits .x86_64 := by
  rcases shift with rfl | rfl <;> simp only [evalUnsignedBinary] at h <;> split at h
  all_goals first
    | (simp at h; done)
    | (rename_i inRange; omega)

/-- A shift Core evaluates has its amount in `0 ..` the left operand's width. -/
theorem shiftBy_range {cop : Core.BinaryOp} (shift : cop = .shiftLeft ∨ cop = .shiftRight) {tl : SrcType}
    {vl v : Value} {wl : BitVec 64} {n : Int} (hl : tl.Holds vl wl) (h : evalShiftBy .x86_64 cop vl n = .ok v) :
    0 ≤ n ∧ n.toNat < (shiftWidth tl).toNat := by
  have signed : ∀ {t a}, vl = .signed t a → 0 ≤ n ∧ n < Int.ofNat (t.bits .x86_64) := by
    intro t a e
    subst e
    rcases shift with rfl | rfl <;> simp only [evalShiftBy] at h <;> exact signedShift_range (by simp) h
  have unsigned : ∀ {t a}, vl = .unsigned t a → 0 ≤ n ∧ n.toNat < t.bits .x86_64 := by
    intro t a e
    subst e
    rcases shift with rfl | rfl <;> simp only [evalShiftBy] at h <;> split at h
    all_goals first
      | (simp at h; done)
      | (rename_i neg; exact ⟨by omega, unsignedShift_range (by simp) h⟩)
  cases tl with
  | i32 =>
    obtain ⟨e, -⟩ := hl
    have := signed e
    simp [shiftWidth, Core.SignedIntTy.bits, Core.Target.x86_64, Core.PointerWidth.bits] at this ⊢
    omega
  | isize =>
    have := signed hl
    simp [shiftWidth, Core.SignedIntTy.bits, Core.Target.x86_64, Core.PointerWidth.bits] at this ⊢
    omega
  | uint k =>
    obtain ⟨e, -⟩ := hl
    have := unsigned e
    cases k <;> simp_all [shiftWidth, UintTy.bits, UintTy.toCore, Core.UnsignedIntTy.bits, Core.Target.x86_64, Core.PointerWidth.bits]
  | sint k =>
    cases k with
    | uint8 =>
      obtain ⟨e, -⟩ := hl
      have := signed e
      simp [shiftWidth, UintTy.bits, Core.SignedIntTy.bits, Core.Target.x86_64, Core.PointerWidth.bits] at this ⊢
      omega
    | uint16 =>
      obtain ⟨e, -⟩ := hl
      have := signed e
      simp [shiftWidth, UintTy.bits, Core.SignedIntTy.bits, Core.Target.x86_64, Core.PointerWidth.bits] at this ⊢
      omega
    | uint32 =>
      obtain ⟨e, -⟩ := hl
      have := signed e
      simp [shiftWidth, UintTy.bits, Core.SignedIntTy.bits, Core.Target.x86_64, Core.PointerWidth.bits] at this ⊢
      omega
    | uint64 =>
      have := signed hl
      simp [shiftWidth, UintTy.bits, Core.SignedIntTy.bits, Core.Target.x86_64, Core.PointerWidth.bits] at this ⊢
      omega
    | usize =>
      have := signed hl
      simp [shiftWidth, UintTy.bits, Core.SignedIntTy.bits, Core.Target.x86_64, Core.PointerWidth.bits] at this ⊢
      omega
  | bool => obtain ⟨b, rfl, -⟩ := hl; simp [evalShiftBy] at h
  | char => obtain ⟨rfl, -⟩ := hl; simp [evalShiftBy] at h
  | float t => obtain ⟨rfl, -⟩ := hl; cases t <;> simp [evalShiftBy, FloatTy.value] at h
  | unit => exact hl.elim
  | struct => exact hl.elim
  | enum => exact hl.elim
  | ptr => subst hl; simp [evalShiftBy] at h
  | slice => exact hl.elim
  | array => exact hl.elim

theorem small_bits {n : Nat} (lt : n < 64) :
    low (BitVec.ofNat 64 n) = BitVec.ofNat 32 n ∧ widen (BitVec.ofNat 32 n) = BitVec.ofNat 64 n ∧
      (BitVec.ofNat 32 n).toInt = n ∧ (BitVec.ofNat 64 n).toInt = n := by
  refine ⟨BitVec.eq_of_toNat_eq ?_, BitVec.eq_of_toNat_eq ?_, ?_, ?_⟩
  · simp only [low, BitVec.toNat_setWidth, BitVec.toNat_ofNat]; omega
  · simp only [widen, BitVec.toNat_setWidth, BitVec.toNat_ofNat]; omega
  · rw [BitVec.toInt_eq_toNat_cond]; simp; split <;> omega
  · rw [BitVec.toInt_eq_toNat_cond]; simp; split <;> omega

theorem shiftWidth_le {tl : SrcType} (int : tl.isInteger = true) : (shiftWidth tl).toNat ≤ 64 := by
  cases tl with
  | i32 => decide
  | isize => decide
  | char => simp [SrcType.isInteger] at int
  | float _ => simp [SrcType.isInteger] at int
  | uint k => cases k <;> decide
  | sint k => cases k <;> decide
  | bool => simp [SrcType.isInteger] at int
  | unit => simp [SrcType.isInteger] at int
  | struct => simp [SrcType.isInteger] at int
  | enum => simp [SrcType.isInteger] at int
  | ptr => simp [SrcType.isInteger] at int
  | slice => simp [SrcType.isInteger] at int
  | array => simp [SrcType.isInteger] at int

/-- An integer value: a shift by it is a shift by its number `m`; its slot is
`m` when `m` is a shift amount. -/
theorem amount_of {tr : SrcType} (int : tr.isInteger = true) {vr : Value} {wr : BitVec 64}
    (hr : tr.Holds vr wr) : ∃ m : Int,
      (∀ {tgt : Core.Target} {cop : Core.BinaryOp} {l : Value}, (cop = .shiftLeft ∨ cop = .shiftRight) →
        ((∃ t a, l = .signed t a) ∨ (∃ t a, l = .unsigned t a)) →
        evalBinaryValue tgt cop l vr = evalShiftBy tgt cop l m) ∧
      (0 ≤ m → m < 64 → wr = BitVec.ofNat 64 m.toNat) ∧ (wr.toNat < 64 → m = wr.toNat) := by
  have narrow : ∀ {t : Core.SignedIntTy}, vr = .signed t (low wr).toInt → wr = widen (low wr) → ∃ m : Int,
      (∀ {tgt : Core.Target} {cop : Core.BinaryOp} {l : Value}, (cop = .shiftLeft ∨ cop = .shiftRight) →
        ((∃ t a, l = .signed t a) ∨ (∃ t a, l = .unsigned t a)) →
        evalBinaryValue tgt cop l vr = evalShiftBy tgt cop l m) ∧
      (0 ≤ m → m < 64 → wr = BitVec.ofNat 64 m.toNat) ∧ (wr.toNat < 64 → m = wr.toNat) := by
    intro t e w
    refine ⟨(low wr).toInt, fun shift int => by rw [e]; exact shift_signedAmount shift int _ _, fun m0 _ => ?_,
      fun lt => ?_⟩
    · rw [w]
      apply BitVec.eq_of_toNat_eq
      rw [BitVec.toInt_eq_toNat_cond] at m0 ⊢
      simp only [widen, BitVec.toNat_setWidth, BitVec.toNat_ofNat] at m0 ⊢
      split at m0 <;> split <;> omega
    · rw [w] at lt ⊢
      rw [BitVec.toInt_eq_toNat_cond]
      simp only [widen, low, BitVec.toNat_setWidth] at lt ⊢
      split <;> omega
  have wide : ∀ {t : Core.SignedIntTy}, vr = .signed t wr.toInt → ∃ m : Int,
      (∀ {tgt : Core.Target} {cop : Core.BinaryOp} {l : Value}, (cop = .shiftLeft ∨ cop = .shiftRight) →
        ((∃ t a, l = .signed t a) ∨ (∃ t a, l = .unsigned t a)) →
        evalBinaryValue tgt cop l vr = evalShiftBy tgt cop l m) ∧
      (0 ≤ m → m < 64 → wr = BitVec.ofNat 64 m.toNat) ∧ (wr.toNat < 64 → m = wr.toNat) := by
    intro t e
    refine ⟨wr.toInt, fun shift int => by rw [e]; exact shift_signedAmount shift int _ _, fun m0 _ => ?_,
      fun lt => ?_⟩
    · apply BitVec.eq_of_toNat_eq
      rw [BitVec.toInt_eq_toNat_cond] at m0 ⊢
      simp only [BitVec.toNat_ofNat] at m0 ⊢
      split at m0 <;> split <;> omega
    · rw [BitVec.toInt_eq_toNat_cond]
      split <;> omega
  cases tr with
  | i32 => exact narrow hr.1 hr.2
  | isize => exact wide hr
  | char => simp [SrcType.isInteger] at int
  | float _ => simp [SrcType.isInteger] at int
  | uint k =>
    obtain ⟨e, -⟩ := hr
    refine ⟨wr.toNat, fun shift int => by rw [e]; exact shift_unsignedAmount shift int _ _, fun _ _ => ?_,
      fun _ => rfl⟩
    simp
  | sint k =>
    cases k with
    | uint8 => exact narrow hr.1 hr.2.1
    | uint16 => exact narrow hr.1 hr.2.1
    | uint32 => exact narrow hr.1 hr.2.1
    | uint64 => exact wide hr
    | usize => exact wide hr
  | bool => simp [SrcType.isInteger] at int
  | unit => simp [SrcType.isInteger] at int
  | struct => simp [SrcType.isInteger] at int
  | enum => simp [SrcType.isInteger] at int
  | ptr => simp [SrcType.isInteger] at int
  | slice => simp [SrcType.isInteger] at int
  | array => simp [SrcType.isInteger] at int

/-- An amount below the left operand's width, as that type holds it. -/
theorem retype_holds {tl : SrcType} (int : tl.isInteger = true) {n : Nat} (lt : n < (shiftWidth tl).toNat) :
    ∃ vr, tl.Holds vr (BitVec.ofNat 64 n) ∧
      ∀ {tgt : Core.Target} {cop : Core.BinaryOp} {l : Value}, (cop = .shiftLeft ∨ cop = .shiftRight) →
        ((∃ t a, l = .signed t a) ∨ (∃ t a, l = .unsigned t a)) →
        evalBinaryValue tgt cop l vr = evalShiftBy tgt cop l n := by
  have n64 : n < 64 := Nat.lt_of_lt_of_le lt (shiftWidth_le int)
  obtain ⟨hlow, hwiden, h32, h64⟩ := small_bits n64
  have narrow : ∀ (t : Core.SignedIntTy) (w : Nat), n < 2 ^ (w - 1) → NarrowHolds t w (.signed t n) (BitVec.ofNat 64 n) := by
    intro t w nw
    have cast : ((2 : Int) ^ (w - 1)) = ((2 ^ (w - 1) : Nat) : Int) := by norm_cast
    refine ⟨?_, ?_, ?_, ?_⟩ <;> simp only [hlow, h32, hwiden]
    · omega
    · omega
  have signed : ∀ (t : Core.SignedIntTy) {tgt : Core.Target} {cop : Core.BinaryOp} {l : Value},
      (cop = .shiftLeft ∨ cop = .shiftRight) → ((∃ t a, l = .signed t a) ∨ (∃ t a, l = .unsigned t a)) →
      evalBinaryValue tgt cop l (.signed t n) = evalShiftBy tgt cop l n :=
    fun t _ _ _ shift int => shift_signedAmount shift int t n
  cases tl with
  | i32 =>
    refine ⟨.signed .i32 n, ⟨by rw [hlow, h32], by rw [hlow, hwiden]⟩, signed _⟩
  | isize => exact ⟨.signed .isize n, by simp only [SrcType.Holds, h64], signed _⟩
  | char => simp [SrcType.isInteger] at int
  | float _ => simp [SrcType.isInteger] at int
  | uint k =>
    have w : (shiftWidth (.uint k)).toNat = k.width := by cases k <;> rfl
    rw [w] at lt
    refine ⟨.unsigned k.toCore n, holds_uint k (Nat.lt_trans lt Nat.lt_two_pow_self), ?_⟩
    intro tgt cop l shift int
    exact shift_unsignedAmount shift int _ _
  | sint k =>
    cases k with
    | uint8 => exact ⟨.signed .i8 n, narrow .i8 8 (by simp [shiftWidth, UintTy.bits] at lt; omega), signed _⟩
    | uint16 => exact ⟨.signed .i16 n, narrow .i16 16 (by simp [shiftWidth, UintTy.bits] at lt; omega), signed _⟩
    | uint32 => exact ⟨.signed .i32 n, narrow .i32 32 (by simp [shiftWidth, UintTy.bits] at lt; omega), signed _⟩
    | uint64 => exact ⟨.signed .i64 n, by simp only [SrcType.Holds, UintTy.SintHolds, h64], signed _⟩
    | usize => exact ⟨.signed .isize n, by simp only [SrcType.Holds, UintTy.SintHolds, h64], signed _⟩
  | bool => simp [SrcType.isInteger] at int
  | unit => simp [SrcType.isInteger] at int
  | struct => simp [SrcType.isInteger] at int
  | enum => simp [SrcType.isInteger] at int
  | ptr => simp [SrcType.isInteger] at int
  | slice => simp [SrcType.isInteger] at int
  | array => simp [SrcType.isInteger] at int

theorem integer_value {tl : SrcType} (int : tl.isInteger = true) {vl : Value} {wl : BitVec 64}
    (hl : tl.Holds vl wl) : (∃ t a, vl = .signed t a) ∨ (∃ t a, vl = .unsigned t a) := by
  cases tl with
  | i32 => exact .inl ⟨_, _, hl.1⟩
  | isize => exact .inl ⟨_, _, hl⟩
  | char => simp [SrcType.isInteger] at int
  | float _ => simp [SrcType.isInteger] at int
  | uint k => exact .inr ⟨_, _, hl.1⟩
  | sint k =>
    cases k with
    | uint8 => exact .inl ⟨_, _, hl.1⟩
    | uint16 => exact .inl ⟨_, _, hl.1⟩
    | uint32 => exact .inl ⟨_, _, hl.1⟩
    | uint64 => exact .inl ⟨_, _, hl⟩
    | usize => exact .inl ⟨_, _, hl⟩
  | bool => simp [SrcType.isInteger] at int
  | unit => simp [SrcType.isInteger] at int
  | struct => simp [SrcType.isInteger] at int
  | enum => simp [SrcType.isInteger] at int
  | ptr => simp [SrcType.isInteger] at int
  | slice => simp [SrcType.isInteger] at int
  | array => simp [SrcType.isInteger] at int

/-- A shift Core evaluates by an amount of another integer type evaluates the
same with the amount's slot read as the left operand's type (`lowerShift`). -/
theorem shift_retype {cop : Core.BinaryOp} (shift : cop = .shiftLeft ∨ cop = .shiftRight) {tl tr : SrcType}
    (il : tl.isInteger = true) (ir : tr.isInteger = true) {vl vr v : Value} {wl wr : BitVec 64}
    (hl : tl.Holds vl wl) (hr : tr.Holds vr wr) (ev : evalBinaryValue .x86_64 cop vl vr = .ok v) :
    ∃ vr', tl.Holds vr' wr ∧ evalBinaryValue .x86_64 cop vl vr' = .ok v := by
  have intl := integer_value il hl
  obtain ⟨m, evr, word, -⟩ := amount_of ir hr
  rw [evr shift intl] at ev
  obtain ⟨m0, mlt⟩ := shiftBy_range shift hl ev
  have m64 : m < 64 := by have := shiftWidth_le il; omega
  obtain ⟨vr', h', evr'⟩ := retype_holds il mlt
  refine ⟨vr', by rw [word m0 m64]; exact h', ?_⟩
  rw [evr' shift intl, show ((m.toNat : Nat) : Int) = m by omega]
  exact ev

/-- An amount slot below the left operand's width, read as the left
operand's type, gives the same shift. -/
theorem shift_retype_lt {cop : Core.BinaryOp} (shift : cop = .shiftLeft ∨ cop = .shiftRight) {tl tr : SrcType}
    (il : tl.isInteger = true) (ir : tr.isInteger = true) {vl vr : Value} {wl wr : BitVec 64}
    (hl : tl.Holds vl wl) (hr : tr.Holds vr wr) (lt : wr.toNat < (shiftWidth tl).toNat) :
    ∃ vr', tl.Holds vr' wr ∧ evalBinaryValue .x86_64 cop vl vr' = evalBinaryValue .x86_64 cop vl vr := by
  have intl := integer_value il hl
  obtain ⟨m, evr, -, number⟩ := amount_of ir hr
  have w64 : wr.toNat < 64 := Nat.lt_of_lt_of_le lt (shiftWidth_le il)
  obtain ⟨vr', h', evr'⟩ := retype_holds il lt
  refine ⟨vr', by rwa [BitVec.ofNat_toNat, BitVec.setWidth_eq] at h', ?_⟩
  rw [evr' shift intl, evr shift intl, number w64]

end Lanius.Mini
