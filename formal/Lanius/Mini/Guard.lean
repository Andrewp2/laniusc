module

public import Lanius.Mini.LowerExpr
public import Lanius.Mini.Compiler
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
import all Lanius.Mini.Compiler.P.lowerSlice
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
import all Lanius.Mini.Compiler.P.larger
import all Lanius.Mini.Compiler.P.Inline_arithOf
import all Lanius.Mini.Compiler.P.Inline_lowerSetScalar
import all Lanius.Mini.Compiler.P.Inline_branchAgrees
-- end import all

@[expose] public section

/-! Checked shifts (roadmap V2a). Core traps on a shift amount outside the
operand type's bits, where x86 masks the amount, so the lowered code first
divides 1 by the expression's guard (`SrcExpr.guard`). When Core evaluates an
expression to a value, every shift it evaluated had its amount in range, and
the guard is 1 (`SrcExpr.guard_sound`), so the check passes. -/

namespace Lanius.Mini

open Lanius.Core (Value)
open Lanius.Semantics (State evalExpr)

theorem amountGuard_one {width : BitVec 64} {amount : Expr} {env : Env}
    (lt : (amount.eval env).toNat < width.toNat) : (amountGuard width amount).eval env = 1 := by
  unfold amountGuard
  split
  · rfl
  · simp [Expr.eval, Word.holds, CmpOp.holdsU, BitVec.ult, lt]

theorem guardAnd_one {a b : Expr} {env : Env} (ha : a.eval env = 1) (hb : b.eval env = 1) :
    (guardAnd a b).eval env = 1 := by
  unfold guardAnd
  split
  · exact hb
  split
  · exact ha
  simp [Expr.eval, Word.apply, BinOp.apply, ha, hb]

theorem guardOr_one {a b : Expr} {env : Env} (h : a.eval env ≠ 0 ∨ b.eval env ≠ 0) :
    (guardOr a b).eval env = 1 := by
  unfold guardOr
  split
  · rfl
  simp only [Expr.eval, Word.holds, CmpOp.holdsU, Word.apply, BinOp.apply]
  simp
  intro ha hb
  rcases h with h | h
  · exact h ha
  · exact h hb

theorem guardAll_one {scope : List Binding} {env : Env} :
    ∀ {es : List SrcExpr}, (∀ e ∈ es, (e.guard scope).eval env = 1) → (guardAll scope es).eval env = 1
  | [], _ => rfl
  | e :: rest, each => by
    simp only [guardAll]
    exact guardAnd_one (each e List.mem_cons_self)
      (guardAll_one fun e' mem => each e' (List.mem_cons_of_mem _ mem))

theorem widen_toNat (a : BitVec 32) : (widen a).toNat = a.toNat := by
  simp [widen, BitVec.toNat_setWidth]
  omega

section
open Semantics

theorem amount_i32 {cop : Core.BinaryOp} (shift : cop = .shiftLeft ∨ cop = .shiftRight) (a b : BitVec 32)
    {v : Value} (ev : evalBinaryValue .x86_64 cop (.signed .i32 a.toInt) (.signed .i32 b.toInt) = .ok v) :
    b.toNat < 32 := by
  rcases shift with rfl | rfl
  · simp only [evalBinaryValue, beq_self_eq_true, ↓reduceIte, evalSignedBinary] at ev
    split at ev
    · simp at ev
    · rename_i inRange
      exact (signed_amount b 32 (by decide) inRange).2
  · simp only [evalBinaryValue, beq_self_eq_true, ↓reduceIte, evalSignedBinary_shiftRight] at ev
    split at ev
    · simp at ev
    · rename_i inRange
      exact (signed_amount b 32 (by decide) inRange).2

theorem amount_isize {cop : Core.BinaryOp} (shift : cop = .shiftLeft ∨ cop = .shiftRight) (a b : BitVec 64)
    {v : Value} (ev : evalBinaryValue .x86_64 cop (.signed .isize a.toInt) (.signed .isize b.toInt) = .ok v) :
    b.toNat < 64 := by
  rcases shift with rfl | rfl
  · simp only [evalBinaryValue, beq_self_eq_true, ↓reduceIte, evalSignedBinary] at ev
    split at ev
    · simp at ev
    · rename_i inRange
      exact (signed_amount b 64 (by decide) inRange).2
  · simp only [evalBinaryValue, beq_self_eq_true, ↓reduceIte, evalSignedBinary_shiftRight] at ev
    split at ev
    · simp at ev
    · rename_i inRange
      exact (signed_amount b 64 (by decide) inRange).2

theorem amount_uint (k : UintTy) {cop : Core.BinaryOp} (shift : cop = .shiftLeft ∨ cop = .shiftRight)
    (a b : BitVec 64) {v : Value}
    (ev : evalBinaryValue .x86_64 cop (.unsigned k.toCore a.toNat) (.unsigned k.toCore b.toNat) = .ok v) :
    b.toNat < (UintTy.bits k).toNat := by
  have width : (UintTy.bits k).toNat = k.width := by cases k <;> rfl
  rw [width]
  rcases shift with rfl | rfl <;>
    simp only [evalBinaryValue, beq_self_eq_true, ↓reduceIte, evalUnsignedBinary, wrapUnsigned,
      unsignedModulus, UintTy.bits_toCore] at ev
  all_goals
    split at ev
    · simp at ev
    rename_i below
    omega

end

/-- A shift Core evaluates has its amount below the left operand's bits. -/
theorem shift_amount {op : SrcOp} (shift : op = .shiftLeft ∨ op = .shiftRight) {tl tr t : Typed}
    (lowered : op.lower tl tr = some t) {env : Env} {vl vr v : Value}
    (holdsl : tl.ty.Holds vl (tl.expr.eval env)) (holdsr : tr.ty.Holds vr (tr.expr.eval env))
    (evaluated : Semantics.evalBinaryValue .x86_64 op.toCore vl vr = .ok v) :
    (tr.expr.eval env).toNat < (shiftWidth tl.ty).toNat := by
  have cshift : op.toCore = .shiftLeft ∨ op.toCore = .shiftRight := by
    rcases shift with rfl | rfl
    · exact .inl rfl
    · exact .inr rfl
  have both : arith .shl tl tr = some t ∨ arith .sar tl tr = some t ∨ arith .shr tl tr = some t := by
    rcases shift with rfl | rfl
    · exact .inl lowered
    · simp only [SrcOp.lower, arithShiftRight] at lowered
      split at lowered
      · exact .inr (.inl lowered)
      · exact .inr (.inr lowered)
  have core : ∀ {o : BinOp}, arith o tl tr = some t → (tr.expr.eval env).toNat < (shiftWidth tl.ty).toNat := by
    intro o ar
    simp only [arith] at ar
    split at ar
    · rename_i types
      cases htl : tl.ty <;> cases htr : tr.ty <;> simp [htl, htr, SrcType.isI32] at types
      rw [htl] at holdsl
      rw [htr] at holdsr
      obtain ⟨rfl, _⟩ := holdsl
      obtain ⟨rfl, hb⟩ := holdsr
      rw [hb, widen_toNat]
      exact amount_i32 cshift _ _ evaluated
    split at ar
    · rename_i types
      cases htl : tl.ty <;> cases htr : tr.ty <;> simp [htl, htr, SrcType.isIsize] at types
      rw [htl] at holdsl
      rw [htr] at holdsr
      subst holdsl
      subst holdsr
      exact amount_isize cshift _ _ evaluated
    · obtain ⟨k, hk, htr, -⟩ := arithUint_some ar
      rw [SrcType.eq_of_uintKind hk] at holdsl ⊢
      rw [htr] at holdsr
      obtain ⟨rfl, _⟩ := holdsl
      obtain ⟨rfl, _⟩ := holdsr
      exact amount_uint k cshift _ _ evaluated
  rcases both with h | h | h <;> exact core h

theorem SrcExpr.guard_sound (e : SrcExpr) {scope : List Binding} {frame : Nat → Nat} {st : State}
    {env : Env} {prog : Core.Program} (corr : Corr scope frame st env) (target : prog.target = .x86_64) :
    ∀ {t : Typed} {fuel : Nat} {v : Value} {st' : State}, e.lower scope = some t →
      evalExpr fuel prog st e.toCore = .done v st' → (e.guard scope).eval env = 1 := by
  induction e with
  | int x => intro t fuel v st' _ _; rfl
  | boolean x => intro t fuel v st' _ _; rfl
  | null => intro t fuel v st' _ _; rfl
  | unsigned kind value => intro t fuel v st' _ _; rfl
  | «local» id => intro t fuel v st' _ _; rfl
  | field id index => intro t fuel v st' _ _; rfl
  | negate operand ih =>
    intro t fuel v st' lowered run
    cases fuel with
    | zero => simp [evalExpr] at run
    | succ fuel =>
      simp only [SrcExpr.lower, lowerNegate] at lowered
      split at lowered
      · simp at lowered
      rename_i inner innerLowered
      simp only [SrcExpr.toCore, evalExpr] at run
      split at run
      · rename_i w mid innerRun
        exact ih innerLowered innerRun
      all_goals simp at run
  | «not» operand ih =>
    intro t fuel v st' lowered run
    cases fuel with
    | zero => simp [evalExpr] at run
    | succ fuel =>
      simp only [SrcExpr.lower, lowerNot] at lowered
      split at lowered
      · simp at lowered
      rename_i inner innerLowered
      simp only [SrcExpr.toCore, evalExpr] at run
      split at run
      · rename_i w mid innerRun
        exact ih innerLowered innerRun
      all_goals simp at run
  | cast ty operand ih =>
    intro t fuel v st' lowered run
    cases fuel with
    | zero => simp [evalExpr] at run
    | succ fuel =>
      simp only [SrcExpr.lower, lowerCast] at lowered
      split at lowered
      · simp at lowered
      rename_i inner innerLowered
      simp only [SrcExpr.toCore, evalExpr] at run
      split at run
      · rename_i w mid innerRun
        exact ih innerLowered innerRun
      all_goals simp at run
  | apply op left right ihl ihr =>
    intro t fuel v st' lowered run
    cases fuel with
    | zero => simp [evalExpr] at run
    | succ fuel =>
      simp only [SrcExpr.lower, lowerApply] at lowered
      split at lowered
      · simp at lowered
      rename_i tl leftLowered
      split at lowered
      · simp at lowered
      rename_i tr rightLowered
      simp only [SrcExpr.guard, leftLowered, rightLowered]
      simp only [SrcExpr.toCore] at run
      cases op
      case logicalAnd =>
        simp only [applyGuard]
        simp only [SrcOp.toCore, evalExpr] at run
        split at run
        · rename_i mid leftRun
          have gl := ihl leftLowered leftRun
          obtain ⟨rfl, holdsl⟩ := left.lower_sound corr target leftLowered leftRun
          simp only [SrcOp.lower, conjunction] at lowered
          split at lowered
          · rename_i types
            cases htl : tl.ty <;> simp [htl, SrcType.isBool] at types
            rw [htl] at holdsl
            obtain ⟨x, hx, bitsl⟩ := holdsl
            cases hx
            refine guardAnd_one gl (guardOr_one (.inl ?_))
            simp [leftFalse, Expr.eval, Word.holds, CmpOp.holdsU, bitsl, boolBits]
          · simp at lowered
        · rename_i mid leftRun
          have gl := ihl leftLowered leftRun
          obtain ⟨rfl, -⟩ := left.lower_sound corr target leftLowered leftRun
          exact guardAnd_one gl (guardOr_one (.inr (by rw [ihr rightLowered run]; decide)))
        all_goals simp at run
      case logicalOr =>
        simp only [applyGuard]
        simp only [SrcOp.toCore, evalExpr] at run
        split at run
        · rename_i mid leftRun
          have gl := ihl leftLowered leftRun
          obtain ⟨rfl, holdsl⟩ := left.lower_sound corr target leftLowered leftRun
          simp only [SrcOp.lower, disjunction] at lowered
          split at lowered
          · rename_i types
            cases htl : tl.ty <;> simp [htl, SrcType.isBool] at types
            rw [htl] at holdsl
            obtain ⟨x, hx, bitsl⟩ := holdsl
            cases hx
            refine guardAnd_one gl (guardOr_one (.inl ?_))
            simp [leftTrue, bitsl, boolBits]
          · simp at lowered
        · rename_i mid leftRun
          have gl := ihl leftLowered leftRun
          obtain ⟨rfl, -⟩ := left.lower_sound corr target leftLowered leftRun
          exact guardAnd_one gl (guardOr_one (.inr (by rw [ihr rightLowered run]; decide)))
        all_goals simp at run
      all_goals
        simp only [SrcOp.toCore, evalExpr] at run
        split at run
        · rename_i vl midl leftRun
          have gl := ihl leftLowered leftRun
          obtain ⟨rfl, holdsl⟩ := left.lower_sound corr target leftLowered leftRun
          split at run
          · rename_i vr midr rightRun
            have gr := ihr rightLowered rightRun
            obtain ⟨rfl, holdsr⟩ := right.lower_sound corr target rightLowered rightRun
            split at run
            · rename_i result evaluated
              rw [target] at evaluated
              first
                | exact guardAnd_one gl gr
                | exact guardAnd_one (guardAnd_one gl gr) (amountGuard_one
                    (shift_amount (by simp) lowered holdsl holdsr evaluated))
            · simp at run
          all_goals simp at run
        all_goals simp at run

/-- A guarded statement lowered: the statement under the check. -/
theorem guarded_some {slot : Nat} {g : Expr} {s : Option Stmt} {out : Stmt}
    (h : guarded slot g s = some out) : ∃ b, s = some b ∧ out = checkThen slot g b := by
  cases s with
  | none => simp [guarded] at h
  | some b =>
    simp only [guarded, Option.some.injEq] at h
    exact ⟨b, rfl, h.symm⟩

theorem Exec.checkThen {prog : Program} {d : Nat} {env : Env} {hp : Heap} {s : Stmt} {out : Outcome}
    {slot : Nat} {g : Expr} (one : g.eval env = 1) (exec : Exec prog d env hp s out) :
    Exec prog d env hp (Lanius.Mini.checkThen slot g s) out := by
  unfold Lanius.Mini.checkThen
  split
  · exact exec
  · exact .ifTrue (by rw [one]; decide) exec

theorem Exec.thenCheck {prog : Program} {d : Nat} {env env' : Env} {hp hp' : Heap} {s : Stmt}
    {slot : Nat} {g : Expr} (exec : Exec prog d env hp s (.normal env' hp')) (pass : g.eval env' ≠ 0) :
    Exec prog d env hp (Lanius.Mini.thenCheck slot g s) (.normal env' hp') := by
  unfold Lanius.Mini.thenCheck
  split
  · exact exec
  · exact .seq exec (.ifTrue pass .skip)

/-- The trap has no derivation. -/
theorem Exec.not_trap {prog : Program} {d : Nat} {env : Env} {hp : Heap} {slot : Nat} {out : Outcome}
    (exec : Exec prog d env hp (trap slot) out) : False := by
  cases exec with
  | divide defined => simp [Expr.eval, Word.divides, DivOp.defined] at defined

theorem isOne_eval {g : Expr} (one : isOne g = true) (env : Env) : g.eval env = 1 := by
  cases g <;> simp_all [isOne, Expr.eval]

/-- A derivation through a check: the check passed. -/
theorem Exec.checkThen_inv {prog : Program} {d : Nat} {env : Env} {hp : Heap} {s : Stmt} {out : Outcome}
    {slot : Nat} {g : Expr} (exec : Exec prog d env hp (Lanius.Mini.checkThen slot g s) out) :
    g.eval env ≠ 0 ∧ Exec prog d env hp s out := by
  unfold Lanius.Mini.checkThen at exec
  split at exec
  · rename_i one
    exact ⟨by rw [isOne_eval one]; decide, exec⟩
  · cases exec with
    | ifTrue pass exec => exact ⟨pass, exec⟩
    | ifFalse _ exec => exact exec.not_trap.elim

theorem Exec.thenCheck_returned {prog : Program} {d : Nat} {env : Env} {hp hp' : Heap} {s : Stmt}
    {slot : Nat} {g : Expr} {bits : List (BitVec 64)} (exec : Exec prog d env hp s (.returned bits hp')) :
    Exec prog d env hp (Lanius.Mini.thenCheck slot g s) (.returned bits hp') := by
  unfold Lanius.Mini.thenCheck
  split
  · exact exec
  · exact .seqReturned exec

end Lanius.Mini
