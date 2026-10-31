import Lanius.Mini.LowerStops

/-! Core to mini for effectful expressions whose Core evaluation fails: the
lowered code stops within `n` ticks. Each sub-expression Core evaluates first
either fails itself, and its code stops (`eff_split`), or completes within the
limit, and the forward simulation gives its code's run (`EvalSound`). Once
every operand is evaluated, the operation either completes, which a failing
run cannot do, traps undefined, or traps where the mini code's own check
(a shift amount, a bound, a division) stops. -/

namespace Lanius.Mini

open Lanius.Core (Value)
open Lanius.Semantics (State Cell Completion evalExpr evalExprs execStmt restoreLocals)

/-- A lowered effectful expression whose Core evaluation fails stops within
`n` ticks. -/
def EffStops (sp : SrcProgram) (mp : Program) (n : Nat) (e : SrcEff) : Prop :=
  ∀ {hp : Heap} {scope : List Binding} {slot : Nat} {ev : Evaluated}
    {frame : Nat → Nat} {base : Nat} {st : State} {env : Env},
    e.eval (sigs sp.funcs) sp.decls scope slot = some ev →
    Corr scope frame st env → Layout scope frame base slot → st.Fresh →
    HeapCorr st.heap st.world hp → st.heap.nextAddress ≤ hp.limit →
    EFails sp hp.limit st e.toCore → ∃ d, Stops mp d env hp ev.stmt n

/-! ## Core's traps pass outward -/

section Traps

variable {P : Core.Program} {st : State}

theorem unary_trap {op : Core.UnaryOp} {e : Core.Expr} {j : Nat} {r : Lanius.Trap} {s : State}
    (h : evalExpr j P st e = .trapped r s) : evalExpr (j + 1) P st (.unary op e) = .trapped r s := by
  rw [evalExpr.eq_def]; simp only [h]

theorem unary_done {op : Core.UnaryOp} {e : Core.Expr} {k : Nat} {w r : Value} {s : State}
    (h : evalExpr k P st e = .done w s) (ok : Semantics.evalUnaryValue P.target op w = .ok r) :
    evalExpr (k + 1) P st (.unary op e) = .done r s := by
  rw [evalExpr.eq_def]; simp only [h, ok]

theorem cast_trap {ty : Core.ScalarTy} {e : Core.Expr} {j : Nat} {r : Lanius.Trap} {s : State}
    (h : evalExpr j P st e = .trapped r s) : evalExpr (j + 1) P st (.cast ty e) = .trapped r s := by
  rw [evalExpr.eq_def]; simp only [h]

theorem cast_done {ty : Core.ScalarTy} {e : Core.Expr} {k : Nat} {w r : Value} {s : State}
    (h : evalExpr k P st e = .done w s) (ok : Semantics.evalScalarCast P.target ty w = .ok r) :
    evalExpr (k + 1) P st (.cast ty e) = .done r s := by
  rw [evalExpr.eq_def]; simp only [h, ok]

theorem binary_trap_left {op : Core.BinaryOp} {l r : Core.Expr} {j : Nat} {reason : Lanius.Trap} {s : State}
    (h : evalExpr j P st l = .trapped reason s) : evalExpr (j + 1) P st (.binary op l r) = .trapped reason s := by
  cases op <;> (rw [evalExpr.eq_def]; simp only [h])

theorem binary_trap_right {op : Core.BinaryOp} (general : op ≠ .logicalAnd ∧ op ≠ .logicalOr)
    {l r : Core.Expr} {k j : Nat} {vl : Value} {st1 : State} {reason : Lanius.Trap} {s : State}
    (hl : evalExpr k P st l = .done vl st1) (h : evalExpr j P st1 r = .trapped reason s) :
    evalExpr (max k j + 1) P st (.binary op l r) = .trapped reason s := by
  have l' := Semantics.evalExpr_of_le hl (by intro h; cases h) (Nat.le_max_left k j)
  have r' := Semantics.evalExpr_of_le h (by intro h; cases h) (Nat.le_max_right k j)
  cases op <;> simp only [ne_eq, not_true_eq_false, false_and, and_false, reduceCtorEq, not_false_eq_true,
    and_self] at general <;> (rw [evalExpr.eq_def]; simp only [l', r'])

theorem binary_done {op : Core.BinaryOp} (general : op ≠ .logicalAnd ∧ op ≠ .logicalOr)
    {l r : Core.Expr} {k j : Nat} {vl vr v : Value} {st1 st2 : State}
    (hl : evalExpr k P st l = .done vl st1) (hr : evalExpr j P st1 r = .done vr st2)
    (ok : Semantics.evalBinaryValue P.target op vl vr = .ok v) :
    evalExpr (max k j + 1) P st (.binary op l r) = .done v st2 := by
  have l' := Semantics.evalExpr_of_le hl (by intro h; cases h) (Nat.le_max_left k j)
  have r' := Semantics.evalExpr_of_le hr (by intro h; cases h) (Nat.le_max_right k j)
  cases op <;> simp only [ne_eq, not_true_eq_false, false_and, and_false, reduceCtorEq, not_false_eq_true,
    and_self] at general <;> (rw [evalExpr.eq_def]; simp only [l', r', ok])

theorem logical_trap_right {op : Core.BinaryOp} {go : Bool}
    (which : op = .logicalAnd ∧ go = true ∨ op = .logicalOr ∧ go = false)
    {l r : Core.Expr} {k j : Nat} {st1 : State} {reason : Lanius.Trap} {s : State}
    (hl : evalExpr k P st l = .done (.boolean go) st1) (h : evalExpr j P st1 r = .trapped reason s) :
    evalExpr (max k j + 1) P st (.binary op l r) = .trapped reason s := by
  have l' := Semantics.evalExpr_of_le hl (by intro h; cases h) (Nat.le_max_left k j)
  have r' := Semantics.evalExpr_of_le h (by intro h; cases h) (Nat.le_max_right k j)
  rcases which with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ <;> (rw [evalExpr.eq_def]; simp only [l', r'])

theorem logical_done_right {op : Core.BinaryOp} {go : Bool}
    (which : op = .logicalAnd ∧ go = true ∨ op = .logicalOr ∧ go = false)
    {l r : Core.Expr} {k j : Nat} {st1 : State} {v : Value} {s : State}
    (hl : evalExpr k P st l = .done (.boolean go) st1) (h : evalExpr j P st1 r = .done v s) :
    evalExpr (max k j + 1) P st (.binary op l r) = .done v s := by
  have l' := Semantics.evalExpr_of_le hl (by intro h; cases h) (Nat.le_max_left k j)
  have r' := Semantics.evalExpr_of_le h (by intro h; cases h) (Nat.le_max_right k j)
  rcases which with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ <;> (rw [evalExpr.eq_def]; simp only [l', r'])

theorem logical_done_left {op : Core.BinaryOp} {stop : Bool}
    (which : op = .logicalAnd ∧ stop = false ∨ op = .logicalOr ∧ stop = true)
    {l r : Core.Expr} {k : Nat} {st1 : State}
    (hl : evalExpr k P st l = .done (.boolean stop) st1) :
    evalExpr (k + 1) P st (.binary op l r) = .done (.boolean stop) st1 := by
  rcases which with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ <;> (rw [evalExpr.eq_def]; simp only [hl])

theorem exprs_trap_head {e : Core.Expr} {es : List Core.Expr} {j : Nat} {r : Lanius.Trap} {s : State}
    (h : evalExpr j P st e = .trapped r s) : evalExprs (j + 1) P st (e :: es) = .trapped r s := by
  simp only [evalExprs, h]

theorem exprs_trap_tail {e : Core.Expr} {es : List Core.Expr} {k j : Nat} {v : Value} {st1 : State}
    {r : Lanius.Trap} {s : State} (hd : evalExpr k P st e = .done v st1) (h : evalExprs j P st1 es = .trapped r s) :
    evalExprs (max k j + 1) P st (e :: es) = .trapped r s := by
  have hd' := Semantics.evalExpr_of_le hd (by intro h; cases h) (Nat.le_max_left k j)
  have h' := (h ▸ Semantics.evalExprs_refines (program := P) (state := st1) (expressions := es)
    (Nat.le_max_right k j)).completed (by intro h; cases h)
  simp only [evalExprs, hd', h']

theorem exprs_done {e : Core.Expr} {es : List Core.Expr} {k j : Nat} {v : Value} {vs : List Value}
    {st1 s : State} (hd : evalExpr k P st e = .done v st1) (h : evalExprs j P st1 es = .done vs s) :
    evalExprs (max k j + 1) P st (e :: es) = .done (v :: vs) s := by
  have hd' := Semantics.evalExpr_of_le hd (by intro h; cases h) (Nat.le_max_left k j)
  have h' := (h ▸ Semantics.evalExprs_refines (program := P) (state := st1) (expressions := es)
    (Nat.le_max_right k j)).completed (by intro h; cases h)
  simp only [evalExprs, hd', h']

theorem call_trap {id : Nat} {args : List Core.Expr} {j : Nat} {r : Lanius.Trap} {s : State}
    (h : evalExprs j P st args = .trapped r s) : evalExpr (j + 1) P st (.call id args) = .trapped r s := by
  rw [evalExpr.eq_def]; simp only [h]

theorem struct_trap {id : Nat} {args : List Core.Expr} {j : Nat} {r : Lanius.Trap} {s : State}
    (h : evalExprs j P st args = .trapped r s) : evalExpr (j + 1) P st (.structValue id args) = .trapped r s := by
  rw [evalExpr.eq_def]; simp only [h]

theorem struct_done {id : Nat} {args : List Core.Expr} {k : Nat} {vs : List Value} {s : State}
    (h : evalExprs k P st args = .done vs s) : evalExpr (k + 1) P st (.structValue id args) = .done (.structure id vs) s := by
  rw [evalExpr.eq_def]; simp only [h]

theorem array_trap {ty : Core.Ty} {args : List Core.Expr} {j : Nat} {r : Lanius.Trap} {s : State}
    (h : evalExprs j P st args = .trapped r s) : evalExpr (j + 1) P st (.array ty args) = .trapped r s := by
  rw [evalExpr.eq_def]; simp only [h]

theorem array_done {ty : Core.Ty} {args : List Core.Expr} {k : Nat} {vs : List Value} {s : State}
    (h : evalExprs k P st args = .done vs s) : evalExpr (k + 1) P st (.array ty args) = .done (.array vs) s := by
  rw [evalExpr.eq_def]; simp only [h]

/-- `array[idx]` of an array local whose index traps traps. -/
theorem arrayIndex_trap {slice : Nat} {idx : Core.Expr} {vs : List Value} {j : Nat}
    {r : Lanius.Trap} {s : State}
    (base : evalExpr (j + 1) P st (.local slice) = .done (.array vs) st)
    (h : evalExpr j P st idx = .trapped r s) : evalExpr (j + 2) P st (.index (.local slice) idx) = .trapped r s := by
  have h' := Semantics.evalExpr_of_le h (by intro h; cases h) (Nat.le_succ j)
  rw [evalExpr.eq_def]; simp only [base, h']

/-- `array[idx]` of an array local, the index in bounds, completes. -/
theorem arrayIndex_done {k : Nat} {slice : Nat} {idx : Core.Expr} {vs : List Value} {iv : Value} {pos : Nat}
    {st1 : State} (base : evalExpr (k + 1) P st (.local slice) = .done (.array vs) st)
    (idxRun : evalExpr (k + 1) P st idx = .done iv st1) (posOk : Semantics.integerIndex iv = .ok pos)
    (lt : pos < vs.length) :
    evalExpr (k + 2) P st (.index (.local slice) idx) = .done vs[pos] st1 := by
  rw [evalExpr.eq_def]; simp only [base, idxRun, posOk, List.getElem?_eq_getElem lt]

theorem enum_trap {id variant : Nat} {args : List Core.Expr} {j : Nat} {r : Lanius.Trap} {s : State}
    (h : evalExprs j P st args = .trapped r s) :
    evalExpr (j + 1) P st (.enumValue id variant args) = .trapped r s := by
  rw [evalExpr.eq_def]; simp only [h]

theorem enum_done {id variant : Nat} {args : List Core.Expr} {k : Nat} {vs : List Value} {s : State}
    (h : evalExprs k P st args = .done vs s) :
    evalExpr (k + 1) P st (.enumValue id variant args) = .done (.enumeration id variant vs) s := by
  rw [evalExpr.eq_def]; simp only [h]

theorem match_trap {e : Core.Expr} {arms : List (Core.Pattern × Core.Expr)} {j : Nat} {r : Lanius.Trap} {s : State}
    (h : evalExpr j P st e = .trapped r s) : evalExpr (j + 1) P st (.matchValue e arms) = .trapped r s := by
  rw [evalExpr.eq_def]; simp only [h]

theorem match_arms {e : Core.Expr} {arms : List (Core.Pattern × Core.Expr)} {k : Nat} {w : Value} {st1 : State}
    (h : evalExpr k P st e = .done w st1) {j : Nat} (le : k ≤ j) :
    evalExpr (j + 1) P st (.matchValue e arms) = Semantics.evalMatchArms j P st1 w arms := by
  have h' := Semantics.evalExpr_of_le h (by intro h; cases h) le
  rw [evalExpr.eq_def]; simp only [h']

theorem index_trap {slice : Nat} {idx : Core.Expr} {element : Core.Ty} {address length j : Nat}
    {r : Lanius.Trap} {s : State}
    (base : evalExpr (j + 1) P st (.local slice) = .done (.rawSlice element address length) st)
    (h : evalExpr j P st idx = .trapped r s) : evalExpr (j + 2) P st (.index (.local slice) idx) = .trapped r s := by
  have h' := Semantics.evalExpr_of_le h (by intro h; cases h) (Nat.le_succ j)
  rw [evalExpr.eq_def]; simp only [base, h']

/-- Core's read of `slice[idx]` from a raw slice local, the index evaluated
from `st` to `st1` and in bounds: a value, or an undefined trap. -/
theorem index_eff_outcome {k : Nat} {slice : Nat} {idx : Core.Expr} {element : Core.Ty}
    {address length : Nat} {iv : Value} {pos : Nat} {st1 : State}
    (base : evalExpr (k + 1) P st (.local slice) = .done (.rawSlice element address length) st)
    (idxRun : evalExpr (k + 1) P st idx = .done iv st1) (posOk : Semantics.integerIndex iv = .ok pos)
    (lt : pos < length) :
    (∃ v, evalExpr (k + 2) P st (.index (.local slice) idx) = .done v st1) ∨
    ∃ r, evalExpr (k + 2) P st (.index (.local slice) idx) = .trapped r st1 ∧ undefinedTrap r = true := by
  have eq : evalExpr (k + 2) P st (.index (.local slice) idx) =
      match Semantics.readRawSliceIndex P st1 element address length pos with
      | .ok value => .done value st1
      | .error reason => .trapped reason st1 := by
    rw [evalExpr.eq_def]
    simp only [base, idxRun, posOk]
    cases Semantics.readRawSliceIndex P st1 element address length pos <;> rfl
  rw [eq]
  cases read : Semantics.readRawSliceIndex P st1 element address length pos with
  | ok v => exact .inl ⟨v, rfl⟩
  | error r => exact .inr ⟨r, rfl, readRawSliceIndex_undef lt r read⟩

theorem intrinsic_trap {op : Core.Intrinsic} {e : Core.Expr} {j : Nat} {r : Lanius.Trap} {s : State}
    (h : evalExpr j P st e = .trapped r s) : evalExpr (j + 1) P st (.intrinsic op e) = .trapped r s := by
  rw [evalExpr.eq_def]; simp only [h]

theorem assert_true_done {e : Core.Expr} {k : Nat} {st1 : State}
    (h : evalExpr k P st e = .done (.boolean true) st1) : evalExpr (k + 1) P st (.intrinsic .assert e) = .done .unit st1 := by
  rw [evalExpr.eq_def]; simp only [h]

end Traps

/-! ## Operators with results on typed values -/

theorem negate_defined {inner t : Typed} {w : Value} {x : BitVec 64} (lowered : lowerNegateTyped inner = some t)
    (holds : inner.ty.Holds w x) : ∃ r, Semantics.evalUnaryValue .x86_64 .negate w = .ok r := by
  simp only [lowerNegateTyped] at lowered
  split at lowered
  · rename_i isFloat
    cases hty : inner.ty <;> simp [hty, SrcType.isFloatAny] at isFloat
    rename_i ft
    rw [hty] at holds
    obtain ⟨rfl, _⟩ := holds
    cases ft <;> exact ⟨_, rfl⟩
  split at lowered
  · rename_i isInt
    cases hty : inner.ty <;> simp [hty, SrcType.isI32] at isInt
    rw [hty] at holds
    obtain ⟨rfl, _⟩ := holds
    exact ⟨_, rfl⟩
  split at lowered
  · rename_i isIsize
    cases hty : inner.ty <;> simp [hty, SrcType.isIsize] at isIsize
    rw [hty] at holds
    subst holds
    exact ⟨_, rfl⟩
  split at lowered
  · simp at lowered
  · rename_i k hk
    rw [SrcType.eq_of_sintKind hk] at holds
    obtain ⟨n, rfl⟩ := sint_value holds
    exact ⟨_, rfl⟩

theorem not_defined {inner t : Typed} {w : Value} {x : BitVec 64} (lowered : lowerNotTyped inner = some t)
    (holds : inner.ty.Holds w x) : ∃ r, Semantics.evalUnaryValue .x86_64 .logicalNot w = .ok r := by
  simp only [lowerNotTyped] at lowered
  split at lowered
  · rename_i isBool
    cases hty : inner.ty <;> simp [hty, SrcType.isBool] at isBool
    rw [hty] at holds
    obtain ⟨b, rfl, _⟩ := holds
    exact ⟨_, rfl⟩
  · simp at lowered

/-- A signed division the mini check passes has a result. -/
theorem i32_div_ok {x y : BitVec 32} {op : DivOp} {cop : Core.BinaryOp}
    (h : (cop = .divide ∧ op = .sDiv) ∨ (cop = .remainder ∧ op = .sRem)) (defined : op.defined x y = true) :
    ∃ v, Semantics.evalBinaryValue .x86_64 cop (.signed .i32 x.toInt) (.signed .i32 y.toInt) = .ok v := by
  have hy : ¬ y.toInt = 0 := fun z => by
    have : y = 0 := BitVec.eq_of_toInt_eq (by simpa using z)
    rcases (show (op = .sDiv ∨ op = .sRem) by rcases h with ⟨_, rfl⟩ | ⟨_, rfl⟩ <;> simp) with rfl | rfl <;>
      simp [DivOp.defined, this] at defined
  have hm : ¬ (x.toInt = -Semantics.signedSignBit .x86_64 .i32 ∧ y.toInt = -1) := fun ⟨hx, hy1⟩ => by
    have ex : x = BitVec.intMin 32 := BitVec.eq_of_toInt_eq (by rw [hx]; rfl)
    have ey : y = -1 := BitVec.eq_of_toInt_eq (by rw [hy1]; rfl)
    rcases (show (op = .sDiv ∨ op = .sRem) by rcases h with ⟨_, rfl⟩ | ⟨_, rfl⟩ <;> simp) with rfl | rfl <;>
      simp [DivOp.defined, ex, ey] at defined
  rcases h with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ <;>
  · simp only [Semantics.evalBinaryValue, Semantics.evalSignedBinary]
    simp [hy, hm]

/-- An unsigned division the mini check passes has a result. -/
theorem uint_div_ok (k : UintTy) {a b : BitVec 64} {op : DivOp} {cop : Core.BinaryOp}
    (h : (cop = .divide ∧ op = .uDiv) ∨ (cop = .remainder ∧ op = .uRem)) (defined : op.defined a b = true) :
    ∃ v, Semantics.evalBinaryValue .x86_64 cop (.unsigned k.toCore a.toNat) (.unsigned k.toCore b.toNat) = .ok v := by
  have hb : ¬ b.toNat = 0 := fun z => by
    have : b = 0 := BitVec.eq_of_toNat_eq (by simpa using z)
    rcases (show (op = .uDiv ∨ op = .uRem) by rcases h with ⟨_, rfl⟩ | ⟨_, rfl⟩ <;> simp) with rfl | rfl <;>
      simp [DivOp.defined, this] at defined
  rcases h with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ <;>
  · simp only [Semantics.evalBinaryValue, Semantics.evalUnsignedBinary]
    simp [hb]

/-- A failed overflow check: the least value over -1. -/
theorem overflowGuard_ne {k : UintTy} {slot : Nat} {env : Env} (g : (overflowGuard k slot).eval env ≠ 0) :
    ¬(low (env slot) = low k.leastBits ∧ low (env (slot + 1)) = -1) := by
  rintro ⟨a, b⟩
  apply g
  have b' : low (env (slot + 1)) = 4294967295#32 := b.trans (by decide)
  simp only [low] at a b'
  simp [overflowGuard, Expr.eval, Word.holds, Word.apply, BinOp.apply, CmpOp.holds, CmpOp.holdsU, low, a, b']

/-- A narrow signed division the overflow check and the mini check pass has a result. -/
theorem narrow_div_ok {k : UintTy} (narrow : k.isWide = false) {op : DivOp} {cop : Core.BinaryOp}
    (h : (cop = .divide ∧ op = .sDiv) ∨ (cop = .remainder ∧ op = .sRem)) {a b : BitVec 64} {vl vr : Value}
    (hl : k.SintHolds vl a) (hr : k.SintHolds vr b) (guard : ¬(low a = low k.leastBits ∧ low b = -1))
    (defined : op.defined (low a) (low b) = true) :
    ∃ v, Semantics.evalBinaryValue .x86_64 cop vl vr = .ok v := by
  rw [sintHolds_narrow narrow] at hl hr
  obtain ⟨rfl, -, -, -⟩ := hl
  obtain ⟨rfl, -, -, -⟩ := hr
  have least : (low k.leastBits).toInt = -2 ^ (k.width - 1) := by
    cases k <;> simp only [UintTy.isWide, Bool.true_eq_false] at narrow <;> decide
  have sign : Semantics.signedSignBit .x86_64 k.toSigned = 2 ^ (k.width - 1) := by
    simp only [Semantics.signedSignBit, UintTy.bits_toSigned]
  generalize low a = x at *
  generalize low b = y at *
  have hy : ¬ y.toInt = 0 := fun z => by
    have : y = 0 := BitVec.eq_of_toInt_eq (by simpa using z)
    rcases (show (op = .sDiv ∨ op = .sRem) by rcases h with ⟨_, rfl⟩ | ⟨_, rfl⟩ <;> simp) with rfl | rfl <;>
      simp [DivOp.defined, this] at defined
  have hm : ¬ (x.toInt = -Semantics.signedSignBit .x86_64 k.toSigned ∧ y.toInt = -1) := fun ⟨hx, hy1⟩ => by
    have ex : x = low k.leastBits := BitVec.eq_of_toInt_eq (by rw [hx, sign, least])
    have ey : y = -1 := BitVec.eq_of_toInt_eq (by rw [hy1]; rfl)
    exact guard ⟨ex, ey⟩
  rcases h with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ <;>
  · simp only [Semantics.evalBinaryValue, Semantics.evalSignedBinary]
    simp [hy, hm]

theorem isize_div_ok {x y : BitVec 64} {op : DivOp} {cop : Core.BinaryOp}
    (h : (cop = .divide ∧ op = .sDiv) ∨ (cop = .remainder ∧ op = .sRem)) (defined : op.defined x y = true) :
    ∃ v, Semantics.evalBinaryValue .x86_64 cop (.signed .isize x.toInt) (.signed .isize y.toInt) = .ok v := by
  have hy : ¬ y.toInt = 0 := fun z => by
    have : y = 0 := BitVec.eq_of_toInt_eq (by simpa using z)
    rcases (show (op = .sDiv ∨ op = .sRem) by rcases h with ⟨_, rfl⟩ | ⟨_, rfl⟩ <;> simp) with rfl | rfl <;>
      simp [DivOp.defined, this] at defined
  have hm : ¬ (x.toInt = -Semantics.signedSignBit .x86_64 .isize ∧ y.toInt = -1) := fun ⟨hx, hy1⟩ => by
    have ex : x = BitVec.intMin 64 := BitVec.eq_of_toInt_eq (by rw [hx]; rfl)
    have ey : y = -1 := BitVec.eq_of_toInt_eq (by rw [hy1]; rfl)
    rcases (show (op = .sDiv ∨ op = .sRem) by rcases h with ⟨_, rfl⟩ | ⟨_, rfl⟩ <;> simp) with rfl | rfl <;>
      simp [DivOp.defined, ex, ey] at defined
  rcases h with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ <;>
  · simp only [Semantics.evalBinaryValue, Semantics.evalSignedBinary]
    simp [hy, hm]

/-- A 64-bit signed division the mini check passes has a result. -/
theorem wide_div_ok {k : UintTy} (wide : k.isWide = true) {op : DivOp} {cop : Core.BinaryOp}
    (h : (cop = .divide ∧ op = .sDiv) ∨ (cop = .remainder ∧ op = .sRem)) {a b : BitVec 64} {vl vr : Value}
    (hl : k.SintHolds vl a) (hr : k.SintHolds vr b) (defined : op.defined a b = true) :
    ∃ v, Semantics.evalBinaryValue .x86_64 cop vl vr = .ok v := by
  rw [sintHolds_wide wide] at hl hr
  subst hl hr
  obtain ⟨v, ok⟩ := isize_div_ok h defined
  rcases UintTy.wide_cases wide with rfl | rfl
  · simp only [UintTy.toSigned]
    rw [evalBinaryValue_i64, ok]
    exact ⟨_, rfl⟩
  · exact ⟨v, ok⟩

/-! ## Sub-expressions -/

section Split

variable {sp : SrcProgram} {mp : Program} {n : Nat}

/-- A sub-expression Core evaluates first: its code stops, or Core completes
it within the limit and its code runs. -/
theorem eff_split (lowered : lowerFuncs (sigs sp.funcs) sp.decls sp.funcs = some mp.funcs)
    {β : Type} {whole : Nat → Semantics.Outcome β} {e : SrcEff} (ih : EffStops sp mp n e)
    {hp : Heap} {scope : List Binding} {slot : Nat} {ev : Evaluated} {frame : Nat → Nat} {base : Nat}
    {st : State} {env : Env}
    (ok : e.eval (sigs sp.funcs) sp.decls scope slot = some ev) (corr : Corr scope frame st env)
    (fr : Layout scope frame base slot) (fresh : st.Fresh) (hc : HeapCorr st.heap st.world hp)
    (within : st.heap.nextAddress ≤ hp.limit) (fails : ∀ j, Failing hp.limit (whole j))
    (propagate : ∀ j reason s, evalExpr j sp.toCore st e.toCore = .trapped reason s →
      ∃ j' s', whole j' = .trapped reason s' ∧ s'.heap.nextAddress = s.heap.nextAddress) :
    (∃ d, Stops mp d env hp ev.stmt n) ∨ ∃ k v st1, evalExpr k sp.toCore st e.toCore = .done v st1 ∧
      st1.heap.nextAddress ≤ hp.limit ∧ Evaluates mp hp slot st env ev v st1 := by
  by_cases done : Completes hp.limit fun k => evalExpr k sp.toCore st e.toCore
  · obtain ⟨k, v, st1, run, bound⟩ := done
    exact .inr ⟨k, v, st1, run, bound, (sound_both lowered k).2 ok corr fr fresh hc run bound⟩
  · exact .inl (ih ok corr fr fresh hc within (failing_of_not_completes fails propagate done))

/-- Arguments whose Core evaluation fails: their code stops. -/
theorem args_stops (lowered : lowerFuncs (sigs sp.funcs) sp.decls sp.funcs = some mp.funcs) :
    ∀ (args : List SrcEff), (∀ e ∈ args, EffStops sp mp n e) →
    ∀ {hp : Heap} {scope : List Binding} {slot : Nat} {ea : EvaluatedArgs} {frame : Nat → Nat} {base : Nat}
      {st : State} {env : Env},
    evalArgs (sigs sp.funcs) sp.decls scope args slot = some ea → Corr scope frame st env →
    Layout scope frame base slot → st.Fresh → HeapCorr st.heap st.world hp → st.heap.nextAddress ≤ hp.limit →
    (∀ j, Failing hp.limit (evalExprs j sp.toCore st (SrcEff.toCoreList args))) →
    ∃ d, Stops mp d env hp ea.stmt n
  | [], _, hp, scope, slot, ea, frame, base, st, env, ok, corr, fr, fresh, hc, within, fails => by
    have := fails 1
    simp only [SrcEff.toCoreList, evalExprs, Failing] at this
    exact absurd within (Nat.not_le.mpr this)
  | e :: es, each, hp, scope, slot, ea, frame, base, st, env, ok, corr, fr, fresh, hc, within, fails => by
    simp only [evalArgs] at ok
    split at ok
    · simp at ok
    rename_i first firstOk
    simp only [consArgs] at ok
    split at ok
    · simp at ok
    rename_i rest restOk
    simp only [Option.some.injEq] at ok
    subst ok
    simp only [SrcEff.toCoreList] at fails
    rcases eff_split lowered (each e List.mem_cons_self) firstOk corr fr fresh hc within fails
        (fun j r s h => ⟨j + 1, s, exprs_trap_head h, rfl⟩) with
      ⟨d, stops⟩ | ⟨k, v, st1, run, bound, fresh1, keeps1, locals1, _, d1, env1, hp1, exec1, same1, _, hc1⟩
    · exact ⟨d, .seqFirst stops⟩
    · have limit := exec1.limit_normal
      have restFails : ∀ j, Failing hp1.limit (evalExprs j sp.toCore st1 (SrcEff.toCoreList es)) := by
        rw [limit]
        refine failing_after exprs_mono (k := k) fun j le => ?_
        have := fails (j + 1)
        simp only [evalExprs, value_after run le] at this
        cases h : evalExprs j sp.toCore st1 (SrcEff.toCoreList es) <;> rw [h] at this <;>
          first | exact this | trivial
      obtain ⟨d2, stops⟩ := args_stops lowered es (fun e' mem => each e' (List.mem_cons_of_mem _ mem)) restOk
        (corr.after fr fresh keeps1 locals1 same1) (fr.mono (Nat.le_add_right _ _)) fresh1 hc1
        (by rw [limit]; exact bound) restFails
      exact ⟨_, Stops.after exec1 stops⟩

/-- Arguments Core evaluates first: their code stops, or Core completes them
within the limit and their code runs. -/
theorem args_split (lowered : lowerFuncs (sigs sp.funcs) sp.decls sp.funcs = some mp.funcs)
    {β : Type} {whole : Nat → Semantics.Outcome β} {args : List SrcEff} (each : ∀ e ∈ args, EffStops sp mp n e)
    {hp : Heap} {scope : List Binding} {slot : Nat} {ea : EvaluatedArgs} {frame : Nat → Nat} {base : Nat}
    {st : State} {env : Env}
    (ok : evalArgs (sigs sp.funcs) sp.decls scope args slot = some ea) (corr : Corr scope frame st env)
    (fr : Layout scope frame base slot) (fresh : st.Fresh) (hc : HeapCorr st.heap st.world hp)
    (within : st.heap.nextAddress ≤ hp.limit) (fails : ∀ j, Failing hp.limit (whole j))
    (propagate : ∀ j reason s, evalExprs j sp.toCore st (SrcEff.toCoreList args) = .trapped reason s →
      ∃ j' s', whole j' = .trapped reason s' ∧ s'.heap.nextAddress = s.heap.nextAddress) :
    (∃ d, Stops mp d env hp ea.stmt n) ∨ ∃ k vs st1, evalExprs k sp.toCore st (SrcEff.toCoreList args) = .done vs st1 ∧
      st1.heap.nextAddress ≤ hp.limit ∧ st1.Fresh ∧ Keeps st.nextCell st st1 ∧ st1.locals = st.locals ∧
      ∃ d env' hp', Exec mp d env hp ea.stmt (.normal env' hp') ∧ (∀ j < slot, env' j = env j) ∧
        FieldsHold ea.types vs env' slot ∧ HeapCorr st1.heap st1.world hp' := by
  by_cases done : Completes hp.limit fun k => evalExprs k sp.toCore st (SrcEff.toCoreList args)
  · obtain ⟨k, vs, st1, run, bound⟩ := done
    exact .inr ⟨k, vs, st1, run, bound,
      evalArgs_sound args (fun m _ => (sound_both lowered m).2) ok corr fr fresh hc run bound⟩
  · exact .inl (args_stops lowered args each ok corr fr fresh hc within
      (failing_of_not_completes fails propagate done))

/-- Two operands of a strict binary operator, into `slot` and `slot + 1`: their
code stops, or Core completes both within the limit and their code runs. -/
theorem pair_split (lowered : lowerFuncs (sigs sp.funcs) sp.decls sp.funcs = some mp.funcs) {l r : SrcEff}
    (ihl : EffStops sp mp n l) (ihr : EffStops sp mp n r) {cop : Core.BinaryOp}
    (general : cop ≠ .logicalAnd ∧ cop ≠ .logicalOr) {hp : Heap} {scope : List Binding} {slot : Nat}
    {le re : Evaluated} {frame : Nat → Nat} {base : Nat} {st : State} {env : Env}
    (leOk : l.eval (sigs sp.funcs) sp.decls scope slot = some le)
    (reOk : r.eval (sigs sp.funcs) sp.decls scope (slot + 1) = some re) (corr : Corr scope frame st env)
    (fr : Layout scope frame base slot) (fresh : st.Fresh) (hc : HeapCorr st.heap st.world hp)
    (within : st.heap.nextAddress ≤ hp.limit) (fails : EFails sp hp.limit st (.binary cop l.toCore r.toCore))
    (rest : Stmt) :
    (∃ d, Stops mp d env hp (.seq le.stmt (.seq re.stmt rest)) n) ∨
    ∃ k1 vl st1 k2 vr st2 env1 env2 hp2,
      evalExpr k1 sp.toCore st l.toCore = .done vl st1 ∧ evalExpr k2 sp.toCore st1 r.toCore = .done vr st2 ∧
      st2.heap.nextAddress ≤ hp.limit ∧ le.ty.HoldsAt vl env1 slot ∧ (∀ j < slot + 1, env2 j = env1 j) ∧
      re.ty.HoldsAt vr env2 (slot + 1) ∧
      ∀ d', Stops mp d' env2 hp2 rest n → ∃ d, Stops mp d env hp (.seq le.stmt (.seq re.stmt rest)) n := by
  rcases eff_split lowered ihl leOk corr fr fresh hc within fails (fun j r s h => ⟨j + 1, s, binary_trap_left h, rfl⟩) with
    ⟨d, stops⟩ | ⟨k1, vl, st1, run1, bound1, fresh1, keeps1, locals1, _, d1, env1, hp1, exec1, same1, holds1, hc1⟩
  · exact .inl ⟨d, .seqFirst stops⟩
  have limit := exec1.limit_normal
  have fails1 : EFails sp hp1.limit st (.binary cop l.toCore r.toCore) := by rw [limit]; exact fails
  rcases eff_split lowered ihr reOk (corr.after fr fresh keeps1 locals1 same1) (fr.mono (Nat.le_succ _)) fresh1 hc1
      (by rw [limit]; exact bound1) fails1 (fun j r s h => ⟨_, s, binary_trap_right general run1 h, rfl⟩) with
    ⟨d, stops⟩ | ⟨k2, vr, st2, run2, bound2, -, -, -, _, d2, env2, hp2, exec2, same2, holds2, -⟩
  · exact .inl ⟨_, Stops.after exec1 (.seqFirst stops)⟩
  · exact .inr ⟨k1, vl, st1, k2, vr, st2, env1, env2, hp2, run1, run2, by rw [← limit]; exact bound2, holds1, same2,
      holds2, fun d' stops => ⟨_, Stops.after exec1 (Stops.after exec2 stops)⟩⟩

end Split

/-! ## The expressions -/

section Cases

variable {sp : SrcProgram} {mp : Program} {n : Nat}

theorem eff_pure {e : SrcExpr} : EffStops sp mp n (.ePure e) := by
  intro hp scope slot ev frame base st env ok corr fr fresh hc within fails
  simp only [SrcEff.toCore] at fails
  simp only [SrcEff.eval, evalPure] at ok
  split at ok
  · rename_i t lowered
    simp only [evalChecked, Option.some.injEq] at ok
    subst ok
    refine Stops.checked fun g => ?_
    obtain ⟨k, v, run⟩ := e.progress corr (SrcProgram.target_toCore sp) lowered g
    exact (fails.not_done run within).elim
  · cases e
    case «local» id =>
      simp only [evalCopy] at ok
      split at ok
      · simp at ok
      rename_i b found
      obtain ⟨w, run, -⟩ := corr.local found 0 sp.toCore
      exact (fails.not_done run within).elim
    case field id index =>
      simp only [evalFieldCopy] at ok
      split at ok
      · simp at ok
      rename_i b found
      simp only [evalFieldOf] at ok
      split at ok
      case h_4 =>
        simp only [evalFieldType] at ok
        split at ok
        · simp at ok
        rename_i ty hfield
        split at ok
        case isFalse => simp at ok
        simp only [evalValues] at ok
        split at ok
        · simp at ok
        rename_i xs valueOk
        obtain ⟨k, v, run⟩ := lowerValue_progress corr (SrcProgram.target_toCore sp) valueOk
          (by simp [SrcExpr.guard, Expr.eval])
        exact (fails.not_done run within).elim
      all_goals simp at ok
    all_goals simp at ok

theorem eff_neg (lowered : lowerFuncs (sigs sp.funcs) sp.decls sp.funcs = some mp.funcs) {operand : SrcEff}
    (ih : EffStops sp mp n operand) : EffStops sp mp n (.eNeg operand) := by
  intro hp scope slot ev frame base st env ok corr fr fresh hc within fails
  simp only [SrcEff.eval, evalNegate] at ok
  split at ok
  · simp at ok
  rename_i o operandOk
  cases lowered' : lowerNegateTyped ({ expr := Expr.var slot, ty := o.ty } : Typed) with
  | none => simp [lowered', evalThen] at ok
  | some t =>
    rw [lowered'] at ok
    simp only [evalThen, Option.some.injEq] at ok
    subst ok
    simp only [SrcEff.toCore] at fails
    rcases eff_split lowered ih operandOk corr fr fresh hc within fails (fun j r s h => ⟨j + 1, s, unary_trap h, rfl⟩) with
      ⟨d, stops⟩ | ⟨k, w, st1, run, bound, -, -, -, -, d1, env1, hp1, exec1, -, holds1, -⟩
    · exact ⟨d, .seqFirst stops⟩
    · obtain ⟨r, okv⟩ := negate_defined lowered' (holds_var holds1 (negate_scalar lowered'))
      exact (fails.not_done (unary_done run okv) bound).elim

theorem eff_not (lowered : lowerFuncs (sigs sp.funcs) sp.decls sp.funcs = some mp.funcs) {operand : SrcEff}
    (ih : EffStops sp mp n operand) : EffStops sp mp n (.eNot operand) := by
  intro hp scope slot ev frame base st env ok corr fr fresh hc within fails
  simp only [SrcEff.eval, evalNot] at ok
  split at ok
  · simp at ok
  rename_i o operandOk
  cases lowered' : lowerNotTyped ({ expr := Expr.var slot, ty := o.ty } : Typed) with
  | none => simp [lowered', evalThen] at ok
  | some t =>
    rw [lowered'] at ok
    simp only [evalThen, Option.some.injEq] at ok
    subst ok
    simp only [SrcEff.toCore] at fails
    rcases eff_split lowered ih operandOk corr fr fresh hc within fails (fun j r s h => ⟨j + 1, s, unary_trap h, rfl⟩) with
      ⟨d, stops⟩ | ⟨k, w, st1, run, bound, -, -, -, -, d1, env1, hp1, exec1, -, holds1, -⟩
    · exact ⟨d, .seqFirst stops⟩
    · obtain ⟨r, okv⟩ := not_defined lowered' (holds_var holds1 (not_scalar lowered'))
      exact (fails.not_done (unary_done run okv) bound).elim

theorem eff_cast (lowered : lowerFuncs (sigs sp.funcs) sp.decls sp.funcs = some mp.funcs) {ty : SrcType}
    {operand : SrcEff} (ih : EffStops sp mp n operand) : EffStops sp mp n (.eCast ty operand) := by
  intro hp scope slot ev frame base st env ok corr fr fresh hc within fails
  simp only [SrcEff.eval, evalCast] at ok
  split at ok
  · simp at ok
  rename_i o operandOk
  cases lowered' : scalarCast ty ({ expr := Expr.var slot, ty := o.ty } : Typed) with
  | none => simp [lowered', evalThen] at ok
  | some t =>
    rw [lowered'] at ok
    simp only [evalThen, Option.some.injEq] at ok
    subst ok
    simp only [scalarCast] at lowered'
    split at lowered'
    case isFalse => simp at lowered'
    rename_i scalar
    simp only [SrcEff.toCore] at fails
    rcases eff_split lowered ih operandOk corr fr fresh hc within fails (fun j r s h => ⟨j + 1, s, cast_trap h, rfl⟩) with
      ⟨d, stops⟩ | ⟨k, w, st1, run, bound, -, -, -, -, d1, env1, hp1, exec1, -, holds1, -⟩
    · exact ⟨d, .seqFirst stops⟩
    · obtain ⟨r, okv⟩ := castTo_defined lowered' (holds_var holds1 scalar)
      exact (fails.not_done (cast_done run okv) bound).elim

theorem eff_stride {slice : Nat} : EffStops sp mp n (.eStride slice) := by
  intro hp scope slot ev frame base st env ok corr fr fresh hc within fails
  simp only [SrcEff.eval, evalStride] at ok
  split at ok
  · simp at ok
  rename_i b found
  split at ok
  · simp at ok
  rename_i element elementOk
  obtain ⟨w, localRun, holdsW⟩ := corr.local found 0 sp.toCore
  rw [eq_of_elementOf elementOk] at holdsW
  cases holdsW with
  | slice =>
  have := fails 2
  simp only [SrcEff.toCore] at this
  rw [evalExpr.eq_def] at this
  simp only [localRun] at this
  split at this
  · exact absurd within (Nat.not_le.mpr this)
  · simp only [Failing, undefinedTrap] at this
    rcases this with h | h
    · cases h
    · exact absurd within (Nat.not_le.mpr h)

theorem eff_apply (lowered : lowerFuncs (sigs sp.funcs) sp.decls sp.funcs = some mp.funcs) {op : SrcOp}
    {l r : SrcEff} (ihl : EffStops sp mp n l) (ihr : EffStops sp mp n r) : EffStops sp mp n (.eApply op l r) := by
  intro hp scope slot ev frame base st env ok corr fr fresh hc within fails
  simp only [SrcEff.eval, evalApply] at ok
  split at ok
  · simp at ok
  rename_i le leOk
  split at ok
  · simp at ok
  rename_i re reOk
  simp only [SrcEff.toCore] at fails
  simp only [evalOperands] at ok
  split at ok
  · rename_i checks
    simp only [Bool.and_eq_true, decide_eq_true_eq] at checks
    obtain ⟨⟨scalarL, scalarR⟩, strictOp⟩ := checks
    split at ok
    · simp at ok
    rename_i t lowered'
    simp only [Option.some.injEq] at ok
    subst ok
    have strict : op ≠ .logicalAnd ∧ op ≠ .logicalOr := by cases op <;> simp_all [shortCircuit]
    have general : op.toCore ≠ .logicalAnd ∧ op.toCore ≠ .logicalOr := by
      cases op <;> simp_all [SrcOp.toCore]
    rcases pair_split lowered ihl ihr general leOk reOk corr fr fresh hc within fails _ with
      stops | ⟨k1, vl, st1, k2, vr, st2, env1, env2, hp2, run1, run2, bound2, holds1, same2, holds2, after⟩
    · exact stops
    have sizeL := SrcType.size_scalar scalarL
    have holdsl := holds_var (env := env2) (holds1.congr fun i below => same2 _ (by omega)) scalarL
    have holdsr := holds_var holds2 scalarR
    by_cases zero : (operandGuard op le.ty (slot + 1)).eval (env2.set slot (t.expr.eval env2)) = 0
    · exact after 0 (Stops.thenCheck (Exec.assign (depth := 0)) zero)
    · obtain ⟨v, okv⟩ := SrcOp.lower_defined lowered' strict holdsl holdsr fun shift => by
        rcases shift with rfl | rfl <;>
        · have := amountGuard_ne (by simpa [operandGuard] using zero)
          simpa [Expr.eval, Env.set] using this
      exact (fails.not_done (binary_done general run1 run2 okv) bound2).elim
  · rename_i notStrict
    split at ok
    · rename_i checks
      simp only [Bool.and_eq_true, decide_eq_true_eq] at checks
      obtain ⟨⟨boolL, boolR⟩, isAnd⟩ := checks
      simp only [Option.some.injEq] at ok
      subst ok
      have opEq : op = .logicalAnd := by cases op <;> simp_all [shortCircuit]
      subst opEq
      simp only [SrcOp.toCore] at fails
      cases hl : le.ty <;> simp [hl, SrcType.isBool] at boolL
      cases hr : re.ty <;> simp [hr, SrcType.isBool] at boolR
      rcases eff_split lowered ihl leOk corr fr fresh hc within fails (fun j r s h => ⟨j + 1, s, binary_trap_left h, rfl⟩) with
        ⟨d, stops⟩ | ⟨k1, vl, st1, run1, bound1, fresh1, keeps1, locals1, _, d1, env1, hp1, exec1, same1, holds1, hc1⟩
      · exact ⟨d, .seqFirst stops⟩
      rw [hl] at holds1
      obtain ⟨b, eq, x⟩ := bool_bits ((SrcType.holdsAt_scalar rfl).mp holds1)
      cases eq
      cases b with
      | false => exact (fails.not_done (logical_done_left (.inl ⟨rfl, rfl⟩) run1) bound1).elim
      | true =>
        have limit := exec1.limit_normal
        have fails1 : EFails sp hp1.limit st (.binary .logicalAnd l.toCore r.toCore) := by rw [limit]; exact fails
        rcases eff_split lowered ihr reOk (corr.after fr fresh keeps1 locals1 same1) (fr.mono (Nat.le_succ _)) fresh1
            hc1 (by rw [limit]; exact bound1) fails1
            (fun j r s h => ⟨_, s, logical_trap_right (.inl ⟨rfl, rfl⟩) run1 h, rfl⟩) with
          ⟨d, stops⟩ | ⟨k2, vr, st2, run2, bound2, -⟩
        · exact ⟨_, Stops.after exec1 (.ifTrue (by simp [Expr.eval, x, boolBits]) (.seqFirst stops))⟩
        · exact (fails1.not_done (logical_done_right (.inl ⟨rfl, rfl⟩) run1 run2) bound2).elim
    · rename_i notAnd
      split at ok
      · rename_i checks
        simp only [Bool.and_eq_true, decide_eq_true_eq] at checks
        obtain ⟨⟨boolL, boolR⟩, isOr⟩ := checks
        simp only [Option.some.injEq] at ok
        subst ok
        have opEq : op = .logicalOr := by cases op <;> simp_all [shortCircuit]
        subst opEq
        simp only [SrcOp.toCore] at fails
        cases hl : le.ty <;> simp [hl, SrcType.isBool] at boolL
        cases hr : re.ty <;> simp [hr, SrcType.isBool] at boolR
        rcases eff_split lowered ihl leOk corr fr fresh hc within fails
            (fun j r s h => ⟨j + 1, s, binary_trap_left h, rfl⟩) with
          ⟨d, stops⟩ | ⟨k1, vl, st1, run1, bound1, fresh1, keeps1, locals1, _, d1, env1, hp1, exec1, same1, holds1, hc1⟩
        · exact ⟨d, .seqFirst stops⟩
        rw [hl] at holds1
        obtain ⟨b, eq, x⟩ := bool_bits ((SrcType.holdsAt_scalar rfl).mp holds1)
        cases eq
        cases b with
        | true => exact (fails.not_done (logical_done_left (.inr ⟨rfl, rfl⟩) run1) bound1).elim
        | false =>
          have limit := exec1.limit_normal
          have fails1 : EFails sp hp1.limit st (.binary .logicalOr l.toCore r.toCore) := by rw [limit]; exact fails
          rcases eff_split lowered ihr reOk (corr.after fr fresh keeps1 locals1 same1) (fr.mono (Nat.le_succ _))
              fresh1 hc1 (by rw [limit]; exact bound1) fails1
              (fun j r s h => ⟨_, s, logical_trap_right (.inr ⟨rfl, rfl⟩) run1 h, rfl⟩) with
            ⟨d, stops⟩ | ⟨k2, vr, st2, run2, bound2, -⟩
          · exact ⟨_, Stops.after exec1 (.ifFalse (by simp [Expr.eval, x, boolBits]) (.seqFirst stops))⟩
          · exact (fails1.not_done (logical_done_right (.inr ⟨rfl, rfl⟩) run1 run2) bound2).elim
      · simp at ok

theorem eff_divide (lowered : lowerFuncs (sigs sp.funcs) sp.decls sp.funcs = some mp.funcs) {op : SrcDivOp}
    {l r : SrcEff} (ihl : EffStops sp mp n l) (ihr : EffStops sp mp n r) : EffStops sp mp n (.eDivide op l r) := by
  intro hp scope slot ev frame base st env ok corr fr fresh hc within fails
  simp only [SrcEff.eval, evalDivision] at ok
  split at ok
  · simp at ok
  rename_i le leOk
  split at ok
  · simp at ok
  rename_i re reOk
  simp only [SrcEff.toCore] at fails
  have general : op.toCore ≠ .logicalAnd ∧ op.toCore ≠ .logicalOr := by cases op <;> simp [SrcDivOp.toCore]
  simp only [evalDivide] at ok
  split at ok
  · rename_i both
    simp only [Bool.and_eq_true] at both
    simp only [Option.some.injEq] at ok
    subst ok
    rcases pair_split lowered ihl ihr general leOk reOk corr fr fresh hc within fails _ with
      stops | ⟨k1, vl, st1, k2, vr, st2, env1, env2, hp2, run1, run2, bound2, holds1, same2, holds2, after⟩
    · exact stops
    rw [eq_of_isI32 both.1] at holds1
    rw [eq_of_isI32 both.2] at holds2
    have holdsl := holds_var (env := env2) (holds1.congr fun i lt => same2 _ (by simp [SrcType.size] at lt; omega)) rfl
    have holdsr := holds_var holds2 rfl
    obtain ⟨rfl, -⟩ := holdsl
    obtain ⟨rfl, -⟩ := holdsr
    by_cases div : Word.s32.divides (signedDiv op) ((Expr.var slot).eval env2) ((Expr.var (slot + 1)).eval env2) = true
    · obtain ⟨v, okv⟩ := i32_div_ok (divOp_signed op) div
      exact (fails.not_done (binary_done general run1 run2 okv) bound2).elim
    · exact after 0 (.divide (by simpa using div))
  split at ok
  · rename_i both
    simp only [Bool.and_eq_true] at both
    simp only [Option.some.injEq] at ok
    subst ok
    rcases pair_split lowered ihl ihr general leOk reOk corr fr fresh hc within fails _ with
      stops | ⟨k1, vl, st1, k2, vr, st2, env1, env2, hp2, run1, run2, bound2, holds1, same2, holds2, after⟩
    · exact stops
    rw [eq_of_isIsize both.1] at holds1
    rw [eq_of_isIsize both.2] at holds2
    have holdsl := holds_var (env := env2) (holds1.congr fun i lt => same2 _ (by simp [SrcType.size] at lt; omega)) rfl
    have holdsr := holds_var holds2 rfl
    by_cases div : Word.u64.divides (signedDiv op) ((Expr.var slot).eval env2) ((Expr.var (slot + 1)).eval env2) = true
    · obtain ⟨v, okv⟩ := isize_div_ok (divOp_signed op) div
      exact (fails.not_done (binary_done general run1 run2 (holdsl ▸ holdsr ▸ okv)) bound2).elim
    · exact after 0 (.divide (by simpa using div))
  · split at ok
    · split at ok
      · simp at ok
      rename_i kind hk
      simp only [evalDivideUint] at ok
      split at ok
      · rename_i hr
        simp only [Option.some.injEq] at ok
        subst ok
        rcases pair_split lowered ihl ihr general leOk reOk corr fr fresh hc within fails _ with
          stops | ⟨k1, vl, st1, k2, vr, st2, env1, env2, hp2, run1, run2, bound2, holds1, same2, holds2, after⟩
        · exact stops
        have lty : le.ty = .uint kind := by cases hty : le.ty <;> simp_all [SrcType.uintKind]
        rw [lty] at holds1
        rw [eq_of_isUint hr] at holds2
        have holdsl := holds_var (env := env2) (holds1.congr fun i lt => same2 _ (by simp [SrcType.size] at lt; omega)) rfl
        have holdsr := holds_var holds2 rfl
        obtain ⟨rfl, -⟩ := holdsl
        obtain ⟨rfl, -⟩ := holdsr
        by_cases div : Word.u64.divides (unsignedDiv op) ((Expr.var slot).eval env2) ((Expr.var (slot + 1)).eval env2) = true
        · obtain ⟨v, okv⟩ := uint_div_ok kind (divOp_unsigned op) div
          exact (fails.not_done (binary_done general run1 run2 okv) bound2).elim
        · exact after 0 (.divide (by simpa using div))
      · simp at ok
    · rename_i kind hk
      simp only [evalDivideSint] at ok
      split at ok
      · rename_i hr
        simp only [Bool.and_eq_true] at hr
        simp only [Option.some.injEq] at ok
        subst ok
        rcases pair_split lowered ihl ihr general leOk reOk corr fr fresh hc within fails _ with
          stops | ⟨k1, vl, st1, k2, vr, st2, env1, env2, hp2, run1, run2, bound2, holds1, same2, holds2, after⟩
        · exact stops
        rw [SrcType.eq_of_sintKind hk] at holds1
        rw [SrcType.eq_of_isSint hr.1] at holds2
        have holdsl := holds_var (env := env2) (holds1.congr fun i lt => same2 _ (by simp [SrcType.size] at lt; omega)) rfl
        have holdsr := holds_var holds2 rfl
        by_cases div : Word.u64.divides (signedDiv op) ((Expr.var slot).eval env2) ((Expr.var (slot + 1)).eval env2) = true
        · obtain ⟨v, okv⟩ := wide_div_ok hr.2 (divOp_signed op) holdsl holdsr div
          exact (fails.not_done (binary_done general run1 run2 okv) bound2).elim
        · exact after 0 (.divide (by simpa using div))
      split at ok
      · rename_i notWide hr
        have narrow : kind.isWide = false := by simp_all
        simp only [Option.some.injEq] at ok
        subst ok
        rcases pair_split lowered ihl ihr general leOk reOk corr fr fresh hc within fails _ with
          stops | ⟨k1, vl, st1, k2, vr, st2, env1, env2, hp2, run1, run2, bound2, holds1, same2, holds2, after⟩
        · exact stops
        rw [SrcType.eq_of_sintKind hk] at holds1
        rw [SrcType.eq_of_isSint hr] at holds2
        have holdsl := holds_var (env := env2) (holds1.congr fun i lt => same2 _ (by simp [SrcType.size] at lt; omega)) rfl
        have holdsr := holds_var holds2 rfl
        refine after 0 (Stops.check fun pass => ?_)
        by_cases div : Word.s32.divides (signedDiv op) ((Expr.var slot).eval env2) ((Expr.var (slot + 1)).eval env2) = true
        · obtain ⟨v, okv⟩ := narrow_div_ok narrow (divOp_signed op) holdsl holdsr (overflowGuard_ne pass) div
          exact (fails.not_done (binary_done general run1 run2 okv) bound2).elim
        · exact .divide (by simpa using div)
      · simp at ok

theorem boundsGuard_ne {b : Binding} {i : Expr} {env : Env} (g : (boundsGuard b i).eval env ≠ 0) :
    (i.eval env).toNat < (env (b.slot + 1)).toNat := by
  simp only [boundsGuard, Expr.eval, Word.holds, CmpOp.holdsU, BitVec.ult] at g
  by_cases h : (i.eval env).toNat < (env (b.slot + 1)).toNat
  · exact h
  · simp [h] at g

theorem eff_arrayIndex (lowered : lowerFuncs (sigs sp.funcs) sp.decls sp.funcs = some mp.funcs) {slice : Nat}
    {index : SrcEff} (ih : EffStops sp mp n index) {hp : Heap} {scope : List Binding} {slot : Nat}
    {ev : Evaluated} {frame : Nat → Nat} {base : Nat} {st : State} {env : Env} {b : Binding}
    (found : lookup scope slice = some b)
    (ok : evalArrayIndex b slot (index.eval (sigs sp.funcs) sp.decls scope slot) = some ev)
    (corr : Corr scope frame st env) (fr : Layout scope frame base slot) (fresh : st.Fresh)
    (hc : HeapCorr st.heap st.world hp) (within : st.heap.nextAddress ≤ hp.limit)
    (fails : EFails sp hp.limit st (.index (.local slice) index.toCore)) : ∃ d, Stops mp d env hp ev.stmt n := by
  obtain ⟨e, n', i, bty, indexOk, kind, -, nsmall, -, rfl⟩ := evalArrayIndex_some ok
  obtain ⟨w0, localRun0, holdsW⟩ := corr.local found 0 sp.toCore
  rw [bty] at holdsW
  cases holdsW with
  | @array _ _ vs _ _ elems =>
  rcases eff_split lowered ih indexOk corr fr fresh hc within fails
      (fun j r s h => ⟨j + 2, s, arrayIndex_trap (value_after localRun0 (by omega)) h, rfl⟩) with
    ⟨d, stops⟩ | ⟨k, iv, st1, run, bound, -, -, -, _, d1, env1, hp1, exec1, same1, holds1, -⟩
  · exact ⟨d, .seqFirst stops⟩
  by_cases zero : (Expr.compare .u64 .lt (.var slot) (.lit (BitVec.ofNat 64 n'))).eval env1 = 0
  · exact ⟨_, Stops.after exec1 (Stops.check (d := 0) fun h => absurd zero h)⟩
  have inBounds : (env1 slot).toNat < n' := by
    have small : n' < 2 ^ 64 := by omega
    by_cases h : (env1 slot).toNat < n'
    · exact h
    · simp [Expr.eval, Word.holds, CmpOp.holdsU, BitVec.ult, Nat.mod_eq_of_lt small, h] at zero
  have len : vs.length = n' := by rw [elems.length, List.length_replicate]
  have scalar : i.ty.isScalar = true := by
    cases hty : i.ty <;> simp_all [SrcType.isI32, SrcType.isUint, SrcType.isScalar]
  have posOk := index_ok (t := { expr := .var slot, ty := i.ty }) kind (holds_var holds1 scalar) (by
    simp only [Expr.eval]; omega)
  have done := arrayIndex_done (value_after localRun0 (by omega : 0 + 1 ≤ k + 1)) (value_after run (Nat.le_succ k))
    posOk (by simp only [Expr.eval]; omega)
  exact (fails.not_done done bound).elim

theorem eff_index (lowered : lowerFuncs (sigs sp.funcs) sp.decls sp.funcs = some mp.funcs) {slice : Nat}
    {index : SrcEff} (ih : EffStops sp mp n index) : EffStops sp mp n (.eIndex slice index) := by
  intro hp scope slot ev frame base st env ok corr fr fresh hc within fails
  simp only [SrcEff.eval, evalIndex] at ok
  split at ok
  · simp at ok
  rename_i b found
  split at ok
  · simp only [SrcEff.toCore] at fails
    exact eff_arrayIndex lowered ih found ok corr fr fresh hc within fails
  rename_i element elementOk
  have bty := eq_of_elementOf elementOk
  simp only [SrcEff.toCore] at fails
  have shape : ∃ i rest, index.eval (sigs sp.funcs) sp.decls scope slot = some i ∧
      (i.ty.isI32 || i.ty.isUint .usize) = true ∧
      ev.stmt = .seq i.stmt (checkThen slot (boundsGuard b (.var slot)) rest) := by
    simp only [evalElement] at ok
    split at ok
    · split at ok
      · simp at ok
      rename_i i indexOk
      simp only [evalLoad] at ok
      split at ok
      case isFalse => simp at ok
      rename_i kind
      simp only [Option.some.injEq] at ok
      subst ok
      exact ⟨i, _, indexOk, kind, rfl⟩
    · split at ok
      · simp at ok
      rename_i i indexOk
      simp only [evalWordElement] at ok
      split at ok
      case isFalse => simp at ok
      rename_i cond
      simp only [Bool.and_eq_true] at cond
      simp only [Option.some.injEq] at ok
      subst ok
      exact ⟨i, _, indexOk, cond.2, rfl⟩
  obtain ⟨i, rest, indexOk, kind, shape⟩ := shape
  rw [shape]
  obtain ⟨w0, localRun0, holdsW⟩ := corr.local found 0 sp.toCore
  rw [bty] at holdsW
  cases holdsW with
  | @slice _ len _ _ lenSlot lenSmall =>
  rcases eff_split lowered ih indexOk corr fr fresh hc within fails
      (fun j r s h => ⟨j + 2, s, index_trap (value_after localRun0 (by omega)) h, rfl⟩) with
    ⟨d, stops⟩ | ⟨k, iv, st1, run, bound, -, -, -, _, d1, env1, hp1, exec1, same1, holds1, -⟩
  · exact ⟨d, .seqFirst stops⟩
  by_cases zero : (boundsGuard b (.var slot)).eval env1 = 0
  · exact ⟨_, Stops.after exec1 (Stops.check (d := 0) fun h => absurd zero h)⟩
  have slot2 : b.slot + 1 < slot := by
    have := fr.slots b (lookup_mem found).1
    rw [bty] at this
    simp only [SrcType.size] at this
    omega
  have inBounds := boundsGuard_ne zero
  rw [same1 _ slot2, lenSlot] at inBounds
  have scalar : i.ty.isScalar = true := by
    cases hty : i.ty <;> simp_all [SrcType.isI32, SrcType.isUint, SrcType.isScalar]
  have posOk := index_ok (t := { expr := .var slot, ty := i.ty }) kind (holds_var holds1 scalar) (by omega)
  rcases index_eff_outcome (value_after localRun0 (by omega : 0 + 1 ≤ k + 1)) (value_after run (Nat.le_succ k))
      posOk inBounds with ⟨v, done⟩ | ⟨r, trapRun, undefined⟩
  · exact (fails.not_done done bound).elim
  · have := fails (k + 2)
    simp only [trapRun, Failing] at this
    exact (trap_within this undefined bound).elim

theorem eff_struct (lowered : lowerFuncs (sigs sp.funcs) sp.decls sp.funcs = some mp.funcs) {ty : SrcType}
    {fields : List SrcEff} (each : ∀ e ∈ fields, EffStops sp mp n e) : EffStops sp mp n (.eStruct ty fields) := by
  intro hp scope slot ev frame base st env ok corr fr fresh hc within fails
  simp only [SrcEff.eval, evalStruct] at ok
  split at ok
  · simp at ok
  rename_i ea argsOk
  simp only [SrcEff.toCore] at fails
  cases ty
  case struct sid types =>
    simp only [evalStructOf] at ok
    split at ok
    case isFalse => simp at ok
    simp only [Option.some.injEq] at ok
    subst ok
    simp only [SrcType.literal] at fails
    rcases args_split lowered each argsOk corr fr fresh hc within fails
        (fun j r s h => ⟨j + 1, s, struct_trap h, rfl⟩) with stops | ⟨k, vs, st1, run, bound, -⟩
    · exact stops
    · exact (fails.not_done (struct_done run) bound).elim
  case array e n =>
    simp only [evalStructOf] at ok
    split at ok
    case isFalse => simp at ok
    simp only [Option.some.injEq] at ok
    subst ok
    simp only [SrcType.literal] at fails
    rcases args_split lowered each argsOk corr fr fresh hc within fails
        (fun j r s h => ⟨j + 1, s, array_trap h, rfl⟩) with stops | ⟨k, vs, st1, run, bound, -⟩
    · exact stops
    · exact (fails.not_done (array_done run) bound).elim
  all_goals simp at ok

theorem eff_variant (lowered : lowerFuncs (sigs sp.funcs) sp.decls sp.funcs = some mp.funcs) {ty : SrcType}
    {variant : Nat} {payload : List SrcEff} (each : ∀ e ∈ payload, EffStops sp mp n e) :
    EffStops sp mp n (.eVariant ty variant payload) := by
  intro hp scope slot ev frame base st env ok corr fr fresh hc within fails
  simp only [SrcEff.eval, evalVariant] at ok
  split at ok
  · simp at ok
  rename_i ea argsOk
  simp only [SrcEff.toCore] at fails
  cases ty
  case enum eid variants =>
    simp only [evalTagged] at ok
    split at ok
    case isFalse => simp at ok
    split at ok
    · simp at ok
    rename_i fs found
    simp only [evalPayload] at ok
    split at ok
    case isFalse => simp at ok
    simp only [Option.some.injEq] at ok
    subst ok
    rcases args_split lowered each argsOk corr (fr.mono (Nat.le_succ _)) fresh hc within fails
        (fun j r s h => ⟨j + 1, s, enum_trap h, rfl⟩) with ⟨d, stops⟩ | ⟨k, vs, st1, run, bound, -⟩
    · exact ⟨d, .seqFirst stops⟩
    · exact (fails.not_done (enum_done run) bound).elim
  all_goals simp at ok

theorem loadBytesFrom_undefined {heap : Memory.Heap} {p : Nat} {r : Lanius.Trap} :
    ∀ (n o : Nat), Memory.loadBytesFrom heap p o n = .error r → undefinedTrap r = true
  | 0, _, h => by simp [Memory.loadBytesFrom] at h
  | n + 1, o, h => by
    simp only [Memory.loadBytesFrom] at h
    split at h
    · rename_i reason loaded
      cases h
      exact loadByte_undefined loaded
    · split at h
      · rename_i reason rest
        cases h
        exact loadBytesFrom_undefined n (o + 1) rest
      · cases h

/-- A heap load's traps are raw memory errors. -/
theorem loadBytes_undefined {heap : Memory.Heap} {p n : Nat} {r : Lanius.Trap}
    (h : heap.loadBytes p n = .error r) : undefinedTrap r = true :=
  loadBytesFrom_undefined n 0 h

theorem eff_call (lowered : lowerFuncs (sigs sp.funcs) sp.decls sp.funcs = some mp.funcs)
    (returns : funcsReturn sp.funcs = true) (prev : StmtStops sp mp n) {callee : Nat} {args : List SrcEff}
    (each : ∀ e ∈ args, EffStops sp mp (n + 1) e) : EffStops sp mp (n + 1) (.eCall callee args) := by
  intro hp scope slot ev frame base st env ok corr fr fresh hc within fails
  simp only [SrcEff.eval, evalCall, sigs_get] at ok
  cases found : sp.funcs[callee]? with
  | none =>
    simp only [found, Option.map_none] at ok
    split at ok
    · simp at ok
    rename_i ea argsOk
    have outside : sp.funcs.length ≤ callee := List.getElem?_eq_none_iff.mp found
    obtain ⟨service, code, hs, stmtEq, shape⟩ := evalHost_some ok
    simp only [SrcEff.toCore] at fails
    rcases args_split lowered each argsOk corr fr fresh hc within fails (fun j r s h => ⟨j + 1, s, call_trap h, rfl⟩) with
      ⟨d, stops⟩ | ⟨k, vs, st1, argsRun, bound, fresh1, keeps1, locals1, d1, env1, hp1, exec1, same1, holdsA, hc1⟩
    · rw [stmtEq]
      exact ⟨d, .seqFirst stops⟩
    exfalso
    have len : vs.length = 2 := by
      rw [holdsA.length]
      rcases shape with ⟨-, tys⟩ | ⟨-, tys⟩ <;> rw [tys] <;> rfl
    have outcome := fails (k + 1)
    rw [host_call_eval outside hs len argsRun fresh1.2] at outcome
    rcases shape with ⟨rfl, tys⟩ | ⟨which, tys⟩
    · obtain ⟨_, _, valuesA, -⟩ := two_i32 holdsA tys
      subst valuesA
      obtain ⟨v, world', called⟩ := writeByte_returns st1.heap st1.world (low (env1 slot)).toInt
        (low (env1 (slot + 1))).toInt
      rw [called, worldCall_returned fresh1.2] at outcome
      exact Nat.lt_irrefl _ (Nat.lt_of_lt_of_le outcome bound)
    · have valuesA := ptr_usize holdsA tys
      subst valuesA
      rcases writeOut_outcome which st1.heap st1.world (env1 slot).toNat (env1 (slot + 1)).toNat with
        ⟨v, world', called⟩ | ⟨r, world', called, loaded⟩
      · rw [called, worldCall_returned fresh1.2] at outcome
        exact Nat.lt_irrefl _ (Nat.lt_of_lt_of_le outcome bound)
      · rw [called] at outcome
        exact trap_within outcome (loadBytes_undefined loaded) bound
  | some f =>
  simp only [found, Option.map_some] at ok
  split at ok
  · simp at ok
  rename_i ea argsOk
  simp only [evalCallSig] at ok
  split at ok
  case isFalse => simp at ok
  rename_i checks
  simp only [Bool.and_eq_true, decide_eq_true_eq] at checks
  obtain ⟨same, sized⟩ := checks
  have tyEq := typesSame_eq _ same
  simp only [Option.some.injEq] at ok
  subst ok
  simp only [SrcEff.toCore] at fails
  rcases args_split lowered each argsOk corr fr fresh hc within fails (fun j r s h => ⟨j + 1, s, call_trap h, rfl⟩) with
    ⟨d, stops⟩ | ⟨k, vs, st1, argsRun, bound, fresh1, keeps1, locals1, d1, env1, hp1, exec1, same1, holdsA, hc1⟩
  · exact ⟨d, .seqFirst stops⟩
  rw [tyEq] at holdsA
  have holdsEntry : FieldsHold (paramTypes f.params) vs
      (Func.entry (Expr.evalAll env1 (slotVars slot (sizes (paramTypes f.params))))) 0 :=
    holdsA.congr fun i below => by rw [Nat.zero_add, entry_slotVars env1 slot _ below]
  have limit := exec1.limit_normal
  obtain ⟨d, g, gFound, arity, stops⟩ := callee_stops lowered returns prev argsRun found fresh1 hc1
    (by rw [limit]; exact bound) holdsEntry (by rw [evalAll_length, slotVars_length, paramsSize_eq])
    (by rw [limit]; exact fails)
  exact ⟨_, Stops.after exec1 (.call gFound (by rw [← arity, evalAll_length]) (Nat.lt_succ_self d) stops)⟩

/-- The arm a match's tag picks: its value's code stops when Core's
evaluation of it fails. -/
theorem arms_stops {dst eid : Nat} {ty : SrcType} {scope : List Binding} {slot : Nat} :
    ∀ (values : List SrcEff) {variants : List (List SrcType)} {binders : List (List Nat)} {j kv : Nat}
      {stmt : Stmt} {fs : List SrcType} {vs : List Value} {hp : Heap} {frame : Nat → Nat} {st : State}
      {env : Env},
      (∀ e ∈ values, EffStops sp mp n e) → Corr scope frame st env → Layout scope frame 0 slot → st.Fresh →
      HeapCorr st.heap st.world hp → st.heap.nextAddress ≤ hp.limit →
      evalArms (sigs sp.funcs) sp.decls scope slot dst ty j variants binders values = some stmt →
      values.length = variants.length → binders.length = variants.length →
      (∀ fs ∈ variants, slot + 1 + sizes fs ≤ dst) → j ≤ kv → variants[kv - j]? = some fs → kv < 2 ^ 64 →
      env slot = BitVec.ofNat 64 kv → FieldsHold fs vs env (slot + 1) →
      (∀ k, Failing hp.limit (Semantics.evalMatchArms k sp.toCore st (.enumeration eid kv vs)
        (SrcEff.coreArms eid j binders values))) →
      ∃ d, Stops mp d env hp stmt n := by
  intro values
  induction values with
  | nil =>
    intro variants binders j kv stmt fs vs hp frame st env each corr fr fresh hc within ok
    simp [evalArms] at ok
  | cons value rest ih =>
    intro variants binders j kv stmt fs vs hp frame st env each corr fr fresh hc within ok vlen blen room le
      found small tag payload fails
    cases variants with
    | nil => simp [evalArms] at ok
    | cons types more =>
    cases binders with
    | nil => simp [evalArms] at ok
    | cons bs others =>
    simp only [evalArms] at ok
    split at ok
    · simp at ok
    rename_i s' scopeOk
    split at ok
    · simp at ok
    rename_i e valueOk
    simp only [evalArm, evalSame] at ok
    have same : e.ty.same ty = true := by
      apply Classical.byContradiction
      intro hne
      rw [if_neg hne] at ok
      simp at ok
    rw [if_pos same] at ok
    by_cases hj : j = kv
    · subst hj
      simp only [Nat.sub_self, List.getElem?_cons_zero, Option.some.injEq] at found
      subst found
      obtain ⟨frame', corr', fr', fresh', keeps', blen'⟩ :=
        armScope_layout bs scopeOk payload (fr.mono (Nat.le_succ _)) corr fresh
      have armFails : EFails sp hp.limit (st.bindLocals (bs.zip vs)) value.toCore := fun k => by
        have := fails (k + 1)
        simp only [SrcEff.coreArms, Semantics.evalMatchArms, Semantics.matchPattern, beq_self_eq_true,
          Bool.and_self, ↓reduceIte, matchBinds _ _ blen'] at this
        exact (failing_restore _ _).mp this
      have hc' : HeapCorr (st.bindLocals (bs.zip vs)).heap (st.bindLocals (bs.zip vs)).world hp := by
        rw [(bindLocals_same _ st).1, bindLocals_world]
        exact hc
      have within' : (st.bindLocals (bs.zip vs)).heap.nextAddress ≤ hp.limit := by
        rw [(bindLocals_same _ st).1]
        exact within
      obtain ⟨d, stops⟩ := each value List.mem_cons_self valueOk corr' (fr'.mono (room _ List.mem_cons_self))
        fresh' hc' within' armFails
      cases rest with
      | nil =>
        simp only [Option.some.injEq] at ok
        subst ok
        exact ⟨d, stops⟩
      | cons next more' =>
        cases ho : evalArms (sigs sp.funcs) sp.decls scope slot dst ty (j + 1) more others (next :: more') with
        | none => simp [ho] at ok
        | some o =>
          simp only [ho, Option.some.injEq] at ok
          subst ok
          exact ⟨d, .ifTrue (by simp [Expr.eval, Word.holds, CmpOp.holdsU, tag]) stops⟩
    · have hne : (j == kv) = false := by simpa using hj
      have found' : more[kv - (j + 1)]? = some fs := by
        rw [show kv - j = kv - (j + 1) + 1 by omega] at found
        simpa using found
      cases rest with
      | nil =>
        have := (List.getElem?_eq_some_iff.mp found').1
        simp only [List.length_cons, List.length_nil] at vlen
        omega
      | cons next more' =>
        cases ho : evalArms (sigs sp.funcs) sp.decls scope slot dst ty (j + 1) more others (next :: more') with
        | none => simp [ho] at ok
        | some o =>
          simp only [ho, Option.some.injEq] at ok
          subst ok
          have fails' : ∀ k, Failing hp.limit (Semantics.evalMatchArms k sp.toCore st (.enumeration eid kv vs)
              (SrcEff.coreArms eid (j + 1) others (next :: more'))) := fun k => by
            have := fails (k + 1)
            simp only [SrcEff.coreArms, Semantics.evalMatchArms, Semantics.matchPattern, beq_self_eq_true,
              Bool.true_and, hne, Bool.false_eq_true, ↓reduceIte] at this
            exact this
          obtain ⟨d, stops⟩ := ih (fun e' mem => each e' (List.mem_cons_of_mem _ mem)) corr fr fresh hc within ho
            (by simpa using vlen) (by simpa using blen) (fun fs mem => room fs (List.mem_cons_of_mem _ mem))
            (by omega) found' small tag payload fails'
          have differ : BitVec.ofNat 64 kv ≠ BitVec.ofNat 64 j := ofNat_ne small (by omega) (Ne.symm hj)
          exact ⟨d, .ifFalse (by simp [Expr.eval, Word.holds, CmpOp.holdsU, tag, differ]) stops⟩

theorem eff_match (lowered : lowerFuncs (sigs sp.funcs) sp.decls sp.funcs = some mp.funcs) {scrutinee : SrcEff}
    {ety ty : SrcType} {binders : List (List Nat)} {values : List SrcEff} (ih : EffStops sp mp n scrutinee)
    (each : ∀ e ∈ values, EffStops sp mp n e) : EffStops sp mp n (.eMatch scrutinee ety ty binders values) := by
  intro hp scope slot ev frame base st env ok corr fr fresh hc within fails
  simp only [SrcEff.eval, evalMatch] at ok
  split at ok
  · simp at ok
  rename_i s scrutOk
  split at ok
  · simp at ok
  rename_i a armsOk
  simp only [evalMatchOf] at ok
  split at ok
  case isFalse => simp at ok
  rename_i cond
  simp only [Bool.and_eq_true, decide_eq_true_eq] at cond
  obtain ⟨⟨⟨⟨same, sized⟩, blen⟩, vlen⟩, small⟩ := cond
  simp only [Option.some.injEq] at ok
  subst ok
  simp only [SrcEff.toCore] at fails
  rcases eff_split lowered ih scrutOk corr fr fresh hc within fails (fun j r s h => ⟨j + 1, s, match_trap h, rfl⟩) with
    ⟨d, stops⟩ | ⟨k, w, st1, scrutRun, bound1, fresh1, keeps1, locals1, _, d1, env1, hp1, exec1, same1, holds1, hc1⟩
  · exact ⟨d, .seqFirst stops⟩
  rw [SrcType.same_eq same] at holds1
  have fr0 : Layout scope frame 0 slot := ⟨fr.slots, fr.sized, fun _ _ => Nat.zero_le _, fr.inj, fr.apart⟩
  have limit := exec1.limit_normal
  cases ety with
  | enum eid variants =>
    cases holds1 with
    | enum found tag payload =>
      rename_i kv fs vs
      simp only [matchVariants] at blen vlen small armsOk
      have kvLt := (List.getElem?_eq_some_iff.mp found).1
      have armsFails : ∀ j, Failing hp1.limit (Semantics.evalMatchArms j sp.toCore st1 (.enumeration eid kv vs)
          (SrcEff.coreArms eid 0 binders values)) := by
        rw [limit]
        refine failing_after (fun le => Semantics.evalMatchArms_refines le) (k := k) fun j le => ?_
        have := fails (j + 1)
        rw [match_arms scrutRun le] at this
        simpa [SrcType.typeId] using this
      obtain ⟨d2, stops⟩ := arms_stops values each (corr.after fr fresh keeps1 locals1 same1) fr0 fresh1 hc1
        (by rw [limit]; exact bound1) armsOk vlen blen (fun fs mem => by
          have := sizes_le_maxSize_of_mem mem
          have := Nat.le_max_left (SrcType.enum eid variants).size ty.size
          simp only [matchDst, SrcType.size] at this ⊢
          omega) (Nat.zero_le _) (by simpa using found) (by omega) tag payload armsFails
      exact ⟨_, Stops.after exec1 (.seqFirst stops)⟩
  | i32 => cases values <;> simp [matchVariants, evalArms] at armsOk
  | bool => cases values <;> simp [matchVariants, evalArms] at armsOk
  | uint => cases values <;> simp [matchVariants, evalArms] at armsOk
  | struct => cases values <;> simp [matchVariants, evalArms] at armsOk
  | ptr => cases values <;> simp [matchVariants, evalArms] at armsOk
  | slice => cases values <;> simp [matchVariants, evalArms] at armsOk
  | array => cases values <;> simp [matchVariants, evalArms] at armsOk
  | unit => cases values <;> simp [matchVariants, evalArms] at armsOk
  | isize => cases values <;> simp [matchVariants, evalArms] at armsOk
  | char => cases values <;> simp [matchVariants, evalArms] at armsOk
  | float => cases values <;> simp [matchVariants, evalArms] at armsOk
  | sint => cases values <;> simp [matchVariants, evalArms] at armsOk

end Cases

/-! ## Statements that evaluate effectful expressions -/

section Statements

variable {sp : SrcProgram} {mp : Program} {n : Nat}

theorem local_assign_trap {P : Core.Program} {scope frame st env} (corr : Corr scope frame st env) {id : Nat}
    {b : Binding} (found : lookup scope id = some b) {e : Core.Expr} {j : Nat} {r : Lanius.Trap} {s : State}
    (h : evalExpr j P st e = .trapped r s) : evalExpr (j + 2) P st (.assign .set (.local id) e) = .trapped r s := by
  obtain ⟨v0, entry, _⟩ := corr.values b (lookup_mem found).1
  have place : Semantics.evalPlace (j + 1) P st .address (.local id) =
      .done { root := frame b.slot, projections := [], value := some v0 } st := by
    simp [Semantics.evalPlace, corr.cellId, found, entry]
  rw [evalExpr.eq_def]
  simp only [place, Semantics.evalExpr_of_le h (by intro h; cases h) (Nat.le_succ j)]

theorem field_assign_trap {P : Core.Program} {scope frame st env} (corr : Corr scope frame st env)
    {id : Nat} {b : Binding} (found : lookup scope id = some b) {sid : Nat} {vs : List Value}
    (entry : st.cellEntry? (frame b.slot) = some ⟨frame b.slot, some (.structure sid vs)⟩)
    {index : Nat} {old : Value} (got : vs[index]? = some old) {e : Core.Expr} {j : Nat} {r : Lanius.Trap}
    {s : State} (h : evalExpr j P st e = .trapped r s) :
    evalExpr (j + 3) P st (.assign .set (.field (.local id) index) e) = .trapped r s := by
  have place : Semantics.evalPlace (j + 2) P st .address (.field (.local id) index) =
      .done { root := frame b.slot, projections := [.field index], value := some old } st := by
    simp [Semantics.evalPlace, corr.cellId, found, entry, got]
  rw [evalExpr.eq_def]
  simp only [place, Semantics.evalExpr_of_le h (by intro h; cases h) (Nat.le_add_right j 2)]

/-- Core's `id.index = e` on a struct local completes once `e` does, when the
struct is still there. -/
theorem field_assign_progress_eff {P : Core.Program} {scope frame st env} (corr : Corr scope frame st env)
    {id : Nat} {b : Binding} (found : lookup scope id = some b) {sid : Nat} {vs : List Value}
    (entry : st.cellEntry? (frame b.slot) = some ⟨frame b.slot, some (.structure sid vs)⟩)
    {index : Nat} {old : Value} (got : vs[index]? = some old) {e : Core.Expr} {k : Nat} {rv : Value}
    {st2 : State} (valueRun : evalExpr k P st e = .done rv st2) (views : st2.i32ArrayViews = [])
    (entry2 : st2.cellEntry? (frame b.slot) = some ⟨frame b.slot, some (.structure sid vs)⟩) :
    ∃ k' st3, evalExpr k' P st (.assign .set (.field (.local id) index) e) = .done .unit st3 ∧
      st3.heap = st2.heap := by
  have place : Semantics.evalPlace (k + 2) P st .address (.field (.local id) index) =
      .done { root := frame b.slot, projections := [.field index], value := some old } st := by
    simp [Semantics.evalPlace, corr.cellId, found, entry, got]
  have valueRun' := Semantics.evalExpr_of_le valueRun (by intro h; cases h) (Nat.le_add_right k 2)
  have synced := sync_ok
    (st := { st2 with cells := Semantics.replaceCell st2.cells (frame b.slot) (.structure sid (Semantics.setValue vs index rv)) })
    views
  refine ⟨k + 3, { st2 with cells := Semantics.replaceCell st2.cells (frame b.slot) (.structure sid (Semantics.setValue vs index rv)) },
    ?_, rfl⟩
  rw [evalExpr.eq_def]
  simp only [place, valueRun', Semantics.evalAssignValue, Semantics.assignOpBinary?,
    Semantics.writeResolvedPlaceNative, Semantics.writeResolvedPlace, entry2,
    Semantics.replaceProjectedValue, got, assignCell_some entry2, synced, ite_self]

theorem stops_letEval (lowered : lowerFuncs (sigs sp.funcs) sp.decls sp.funcs = some mp.funcs) {id : Nat}
    {ty : SrcType} {value : SrcEff} {body : SrcStmt} (ihe : EffStops sp mp n value) (ih : SrcStops sp mp n body) :
    SrcStops sp mp n (.letEval id ty value body) := by
  intro hp ret scope next stmt frame base st env ok corr fr fresh le hc within fails
  simp only [SrcStmt.lower, lowerLetEval] at ok
  split at ok
  · simp at ok
  rename_i ev valueOk
  split at ok
  · simp at ok
  rename_i bstmt bodyOk
  simp only [evalSame] at ok
  split at ok
  case isFalse => simp at ok
  rename_i same
  have tyEq := SrcType.same_eq same
  simp only [Option.some.injEq] at ok
  subst ok
  simp only [SrcStmt.toCore] at fails
  rcases eff_split lowered ihe valueOk corr fr fresh hc within fails
      (fun j r s h => ⟨j + 1, s, by simp only [execStmt, h], rfl⟩) with
    ⟨d, stops⟩ | ⟨k, v, st1, valueRun, bound1, fresh1, keeps1, locals1, sized, d1, env1, hp1, exec1, same1, holds1, hc1⟩
  · exact ⟨d, .seqFirst stops⟩
  rw [tyEq] at sized holds1
  have limit := exec1.limit_normal
  obtain ⟨d2, stops⟩ := let_stops ih bodyOk (corr.keeps fresh keeps1 locals1) fr fresh1 (Nat.le_trans le keeps1.next)
    sized (fr.agree same1) holds1 hc1 (by rw [limit]; exact bound1) (by rw [limit]; exact fails.letBody valueRun)
  exact ⟨_, Stops.after exec1 stops⟩

theorem stops_setEval (lowered : lowerFuncs (sigs sp.funcs) sp.decls sp.funcs = some mp.funcs) {id : Nat}
    {value : SrcEff} (ihe : EffStops sp mp n value) : SrcStops sp mp n (.setEval id value) := by
  intro hp ret scope next stmt frame base st env ok corr fr fresh le hc within fails
  simp only [SrcStmt.lower, lowerSetEval] at ok
  split at ok
  · simp at ok
  rename_i b found
  split at ok
  · simp at ok
  rename_i ev valueOk
  simp only [evalSame] at ok
  split at ok
  case isFalse => simp at ok
  simp only [Option.some.injEq] at ok
  subst ok
  simp only [SrcStmt.toCore] at fails
  rcases eff_split lowered ihe valueOk corr fr fresh hc within fails.expression
      (fun j r s h => ⟨j + 2, s, local_assign_trap corr found h, rfl⟩) with
    ⟨d, stops⟩ | ⟨k, rv, st2, valueRun, bound, fresh2, keeps2, locals2, -⟩
  · exact ⟨d, .seqFirst stops⟩
  obtain ⟨v2, entry2, _⟩ := (corr.keeps fresh keeps2 locals2).values b (lookup_mem found).1
  exact (fails.assign_done corr found valueRun fresh2.2 (by rw [entry2]; rfl) bound).elim

theorem stops_setFieldEval (lowered : lowerFuncs (sigs sp.funcs) sp.decls sp.funcs = some mp.funcs)
    {id index : Nat} {value : SrcEff} (ihe : EffStops sp mp n value) :
    SrcStops sp mp n (.setFieldEval id index value) := by
  intro hp ret scope next stmt frame base st env ok corr fr fresh le hc within fails
  simp only [SrcStmt.lower, lowerSetFieldEval] at ok
  split at ok
  · simp at ok
  rename_i b found
  split at ok
  · simp at ok
  rename_i ev valueOk
  simp only [setFieldEvalOf] at ok
  split at ok
  · simp at ok
  · simp at ok
  · simp at ok
  case h_5 => simp at ok
  case h_6 => simp at ok
  case h_7 => simp at ok
  case h_8 => simp at ok
  case h_9 => simp at ok
  case h_10 => simp at ok
  case h_11 => simp at ok
  case h_12 => simp at ok
  case h_13 => simp at ok
  rename_i sid types hty
  simp only [setFieldEvalAt] at ok
  split at ok
  · simp at ok
  rename_i f fieldFound
  split at ok
  case isFalse => simp at ok
  simp only [evalSame] at ok
  split at ok
  case isFalse => simp at ok
  simp only [Option.some.injEq] at ok
  subst ok
  have bmem := (lookup_mem found).1
  obtain ⟨v0, entry, holds0⟩ := corr.values b bmem
  rw [hty] at holds0
  cases holds0 with
  | @struct _ _ vs _ _ fieldsHold =>
  obtain ⟨old, got, _⟩ := fieldsHold.get fieldFound
  simp only [SrcStmt.toCore] at fails
  rcases eff_split lowered ihe valueOk corr fr fresh hc within fails.expression
      (fun j r s h => ⟨j + 3, s, field_assign_trap corr found entry got h, rfl⟩) with
    ⟨d, stops⟩ | ⟨k, rv, st2, valueRun, bound, fresh2, keeps2, locals2, -⟩
  · exact ⟨d, .seqFirst stops⟩
  have entry2 : st2.cellEntry? (frame b.slot) = some ⟨frame b.slot, some (.structure sid vs)⟩ := by
    rw [keeps2.cells _ (corr.below fresh b bmem)]; exact entry
  obtain ⟨k', st3, run, heap⟩ := field_assign_progress_eff corr found entry got valueRun fresh2.2 entry2
  exact (fails.not_done (k := k' + 1) (c := .next) (st' := st3) (by simp only [execStmt, run])
    (by rw [heap]; exact bound)).elim

theorem stops_ifEval (lowered : lowerFuncs (sigs sp.funcs) sp.decls sp.funcs = some mp.funcs)
    {condition : SrcEff} {thenBranch elseBranch : SrcStmt} (ihe : EffStops sp mp n condition)
    (ih1 : SrcStops sp mp n thenBranch) (ih2 : SrcStops sp mp n elseBranch) :
    SrcStops sp mp n (.ifEval condition thenBranch elseBranch) := by
  intro hp ret scope next stmt frame base st env ok corr fr fresh le hc within fails
  simp only [SrcStmt.lower, lowerIfEval] at ok
  split at ok
  · simp at ok
  rename_i cv condOk
  split at ok
  · simp at ok
  rename_i tstmt thenOk
  split at ok
  · simp at ok
  rename_i estmt elseOk
  simp only [evalSame] at ok
  split at ok
  case isFalse => simp at ok
  rename_i same
  have tyEq := SrcType.same_eq same
  simp only [Option.some.injEq] at ok
  subst ok
  simp only [SrcStmt.toCore] at fails
  rcases eff_split lowered ihe condOk corr fr fresh hc within fails
      (fun j r s h => ⟨j + 1, s, by simp only [execStmt, h], rfl⟩) with
    ⟨d, stops⟩ | ⟨k, v, st1, condRun, bound1, fresh1, keeps1, locals1, _, d1, env1, hp1, exec1, same1, holds1, hc1⟩
  · exact ⟨d, .seqFirst stops⟩
  rw [tyEq] at holds1
  obtain ⟨y, eq, bits⟩ := bool_bits ((SrcType.holdsAt_scalar rfl).mp holds1)
  cases eq
  have limit := exec1.limit_normal
  have corr1 := corr.after fr fresh keeps1 locals1 same1
  have branch := fails.ifBranch condRun
  cases y with
  | true =>
    obtain ⟨d, stops⟩ := ih1 thenOk corr1 fr fresh1 (Nat.le_trans le keeps1.next) hc1 (by rw [limit]; exact bound1)
      (by rw [limit]; exact branch)
    exact ⟨_, Stops.after exec1 (.ifTrue (by simp [Expr.eval, bits, boolBits]) stops)⟩
  | false =>
    obtain ⟨d, stops⟩ := ih2 elseOk corr1 fr fresh1 (Nat.le_trans le keeps1.next) hc1 (by rw [limit]; exact bound1)
      (by rw [limit]; exact branch)
    exact ⟨_, Stops.after exec1 (.ifFalse (by simp [Expr.eval, bits, boolBits]) stops)⟩

/-- A loop that computes its condition at the top of every iteration and
breaks when it is false: it stops within `j` ticks for every `j` up to the
ticks its body and condition stop within. -/
theorem loop_stops (lowered : lowerFuncs (sigs sp.funcs) sp.decls sp.funcs = some mp.funcs) {c : SrcEff}
    {body : SrcStmt} {m : Nat} (ihc : EffStops sp mp m c) (ihb : SrcStops sp mp m body) {ret : SrcType}
    {scope : List Binding} {next : Nat} {cv : Evaluated} {bstmt : Stmt} {frame : Nat → Nat} {base : Nat}
    (condOk : c.eval (sigs sp.funcs) sp.decls scope next = some cv)
    (bodyOk : body.lower (sigs sp.funcs) sp.decls ret scope next = some bstmt) (isBool : cv.ty = .bool)
    (fr : Layout scope frame base next) :
    ∀ j ≤ m, ∀ {hp : Heap} {st0 : State} {env0 : Env},
      Corr scope frame st0 env0 → st0.Fresh → base ≤ st0.nextCell → HeapCorr st0.heap st0.world hp →
      st0.heap.nextAddress ≤ hp.limit → Fails sp hp.limit st0 (.whileLoop c.toCore body.toCore) →
      ∃ d, Stops mp d env0 hp (.loop (.lit 1) (.seq cv.stmt (.ite (.var next) bstmt .brk))) j := by
  intro j
  induction j with
  | zero => intros; exact ⟨0, .zero⟩
  | succ j ihj =>
    intro le hp st0 env0 corr0 fresh0 le0 hc0 within0 fails
    rcases eff_split lowered ihc condOk corr0 fr fresh0 hc0 within0 fails
        (fun i r s h => ⟨i + 1, s, by simp only [execStmt, h], rfl⟩) with
      ⟨d, stops⟩ | ⟨k, w, st1, condRun, bound1, fresh1, keeps1, locals1, _, d1, env1, hp1, exec1, same1, holds1, hc1⟩
    · exact ⟨d, .loopBody (Expr.lit_one_ne env0) (.seqFirst (stops.mono le))⟩
    rw [isBool] at holds1
    obtain ⟨y, eq, bits⟩ := bool_bits ((SrcType.holdsAt_scalar rfl).mp holds1)
    cases eq
    have limit1 := exec1.limit_normal
    have corr1 := corr0.after fr fresh0 keeps1 locals1 same1
    have le1 : base ≤ st1.nextCell := Nat.le_trans le0 keeps1.next
    cases y with
    | false =>
      have := fails (k + 1)
      simp only [execStmt, condRun] at this
      exact absurd bound1 (Nat.not_le.mpr this)
    | true =>
      have condTrue : (Expr.var next).eval env1 ≠ 0 := by simp [Expr.eval, bits, boolBits]
      by_cases done : Completes hp.limit fun i => execStmt i sp.toCore st1 body.toCore
      · obtain ⟨k', cpl, st2, run1, bound2⟩ := done
        obtain ⟨fresh2, keeps2, d2, out2, exec2, matched2⟩ :=
          stmt_sound lowered k' bodyOk corr1 fr fresh1 le1 hc1 run1 (by rw [limit1]; exact bound2)
        cases matched2 with
        | @next env2 hp2 corr2 hc2 =>
          have limit2 := exec2.limit_normal
          obtain ⟨d3, stops⟩ := ihj (by omega) corr2 fresh2 (Nat.le_trans le1 keeps2.next) hc2
            (by rw [limit2, limit1]; exact bound2) (by rw [limit2, limit1]; exact fails.whileNext condRun run1)
          exact ⟨d1 + d2 + d3, .loopNext (Expr.lit_one_ne env0)
            (.seq (exec1.mono (by omega)) (.ifTrue condTrue (exec2.mono (by omega)))) (stops.deeper (by omega))⟩
        | @continued env2 hp2 corr2 hc2 =>
          have limit2 := exec2.limit
          simp only [Outcome.heap] at limit2
          obtain ⟨d3, stops⟩ := ihj (by omega) corr2 fresh2 (Nat.le_trans le1 keeps2.next) hc2
            (by rw [limit2, limit1]; exact bound2) (by rw [limit2, limit1]; exact fails.whileContinue condRun run1)
          exact ⟨d1 + d2 + d3, .loopContinued (Expr.lit_one_ne env0)
            (.seq (exec1.mono (by omega)) (.ifTrue condTrue (exec2.mono (by omega)))) (stops.deeper (by omega))⟩
        | returned | broke =>
          have := fails (max k k' + 1)
          simp only [execStmt, value_after condRun (Nat.le_max_left k k'),
            done_after run1 (Nat.le_max_right k k')] at this
          exact absurd bound2 (Nat.not_le.mpr this)
      · obtain ⟨d, stops⟩ := ihb bodyOk corr1 fr fresh1 le1 hc1 (by rw [limit1]; exact bound1)
          (by rw [limit1]; exact fails.whileBody condRun done)
        exact ⟨_, .loopBody (Expr.lit_one_ne env0) (Stops.after exec1 (.ifTrue condTrue (stops.mono le)))⟩

theorem stops_whileEval (lowered : lowerFuncs (sigs sp.funcs) sp.decls sp.funcs = some mp.funcs)
    {condition : SrcEff} {body : SrcStmt} (ihe : EffStops sp mp n condition) (ih : SrcStops sp mp n body) :
    SrcStops sp mp n (.whileEval condition body) := by
  intro hp ret scope next stmt frame base st env ok corr fr fresh le hc within fails
  simp only [SrcStmt.lower, lowerWhileEval] at ok
  split at ok
  · simp at ok
  rename_i cv condOk
  split at ok
  · simp at ok
  rename_i bstmt bodyOk
  simp only [evalSame] at ok
  split at ok
  case isFalse => simp at ok
  rename_i same
  have tyEq := SrcType.same_eq same
  simp only [Option.some.injEq] at ok
  subst ok
  simp only [SrcStmt.toCore] at fails
  exact loop_stops lowered ihe ih condOk bodyOk tyEq fr n (Nat.le_refl _) corr fresh le hc within fails

/-- `break;` and `continue;` complete at once, so they never fail. -/
theorem stops_break : SrcStops sp mp n .break := by
  intro hp ret scope next stmt frame base st env ok corr fr fresh le hc within fails
  have := fails 1
  simp only [SrcStmt.toCore, execStmt, Failing] at this
  exact absurd within (Nat.not_le.mpr this)

theorem stops_continue : SrcStops sp mp n .continue := by
  intro hp ret scope next stmt frame base st env ok corr fr fresh le hc within fails
  have := fails 1
  simp only [SrcStmt.toCore, execStmt, Failing] at this
  exact absurd within (Nat.not_le.mpr this)

theorem stops_returnEval (lowered : lowerFuncs (sigs sp.funcs) sp.decls sp.funcs = some mp.funcs)
    {value : SrcEff} (ihe : EffStops sp mp n value) : SrcStops sp mp n (.returnEval value) := by
  intro hp ret scope next stmt frame base st env ok corr fr fresh le hc within fails
  simp only [SrcStmt.lower, lowerReturnEval] at ok
  split at ok
  · simp at ok
  rename_i ev valueOk
  simp only [evalSame] at ok
  split at ok
  case isFalse => simp at ok
  simp only [Option.some.injEq] at ok
  subst ok
  simp only [SrcStmt.toCore] at fails
  rcases eff_split lowered ihe valueOk corr fr fresh hc within fails
      (fun j r s h => ⟨j + 1, s, by simp only [execStmt, h], rfl⟩) with ⟨d, stops⟩ | ⟨k, v, st1, valueRun, bound, -⟩
  · exact ⟨d, .seqFirst stops⟩
  · have := fails (k + 1)
    simp only [execStmt, valueRun, Failing] at this
    exact absurd bound (Nat.not_le.mpr this)

theorem stops_discard {value : SrcEff} (ihe : EffStops sp mp n value) : SrcStops sp mp n (.discard value) := by
  intro hp ret scope next stmt frame base st env ok corr fr fresh le hc within fails
  simp only [SrcStmt.lower, lowerDiscard] at ok
  split at ok
  · simp at ok
  rename_i ev valueOk
  simp only [Option.some.injEq] at ok
  subst ok
  simp only [SrcStmt.toCore] at fails
  exact ihe valueOk corr fr fresh hc within fails.expression

theorem stops_assert (lowered : lowerFuncs (sigs sp.funcs) sp.decls sp.funcs = some mp.funcs)
    {condition : SrcEff} (ihe : EffStops sp mp n condition) : SrcStops sp mp n (.assert condition) := by
  intro hp ret scope next stmt frame base st env ok corr fr fresh le hc within fails
  simp only [SrcStmt.lower, lowerAssert] at ok
  split at ok
  · simp at ok
  rename_i cv condOk
  simp only [evalSame] at ok
  split at ok
  case isFalse => simp at ok
  rename_i same
  have tyEq := SrcType.same_eq same
  simp only [Option.some.injEq] at ok
  subst ok
  simp only [SrcStmt.toCore] at fails
  rcases eff_split lowered ihe condOk corr fr fresh hc within fails.expression
      (fun j r s h => ⟨j + 1, s, intrinsic_trap h, rfl⟩) with
    ⟨d, stops⟩ | ⟨k, v, st1, condRun, bound, -, -, -, -, d1, env1, hp1, exec1, -, holds1, -⟩
  · exact ⟨d, .seqFirst stops⟩
  rw [tyEq] at holds1
  obtain ⟨y, eq, bits⟩ := bool_bits ((SrcType.holdsAt_scalar rfl).mp holds1)
  cases eq
  cases y with
  | true => exact (fails.expression.not_done (assert_true_done condRun) bound).elim
  | false =>
    exact ⟨_, Stops.after (d' := 0) exec1 (.divide (by simp [Expr.eval, bits, boolBits, Word.divides, DivOp.defined]))⟩

theorem stops_returnUnit : SrcStops sp mp n .returnUnit := by
  intro hp ret scope next stmt frame base st env ok corr fr fresh le hc within fails
  have := fails 1
  simp only [SrcStmt.toCore, execStmt, Failing] at this
  exact absurd within (Nat.not_le.mpr this)

/-! ### `slice[index] = value` with effectful operands -/

section SetIndex

variable {P : Core.Program} {k : Nat} {st : State} {slice : Nat} {idx e : Core.Expr} {element : Core.Ty}
  {address length root : Nat}

theorem setIndex_idx_trap {r : Lanius.Trap} {s : State}
    (base : Semantics.evalPlace (k + 1) P st .read (.local slice) =
      .done { root, projections := [], value := some (.rawSlice element address length) } st)
    (h : evalExpr (k + 1) P st idx = .trapped r s) :
    evalExpr (k + 3) P st (.assign .set (.index (.local slice) idx) e) = .trapped r s := by
  generalize hout : evalExpr (k + 3) P st (.assign .set (.index (.local slice) idx) e) = out
  rw [evalExpr] at hout
  rw [Semantics.evalPlace] at hout
  rw [base] at hout
  simp only [h] at hout
  exact hout.symm

theorem setIndex_address_undef {iv : Value} {st1 : State} {pos : Nat} {r : Lanius.Trap}
    (base : Semantics.evalPlace (k + 1) P st .read (.local slice) =
      .done { root, projections := [], value := some (.rawSlice element address length) } st)
    (idxRun : evalExpr (k + 1) P st idx = .done iv st1) (posOk : Semantics.integerIndex iv = .ok pos)
    (lt : pos < length) (located : Semantics.rawSliceElementAddress? P element address pos = .error r) :
    evalExpr (k + 3) P st (.assign .set (.index (.local slice) idx) e) = .trapped r st1 ∧ undefinedTrap r = true := by
  refine ⟨?_, rawSliceElementAddress_undef P element address pos r located⟩
  generalize hout : evalExpr (k + 3) P st (.assign .set (.index (.local slice) idx) e) = out
  rw [evalExpr] at hout
  rw [Semantics.evalPlace] at hout
  rw [base] at hout
  simp only [idxRun, posOk, lt, if_true, decide_true, located] at hout
  exact hout.symm

theorem setIndex_value_trap {iv : Value} {st1 : State} {pos at_ : Nat} {r : Lanius.Trap} {s : State}
    (base : Semantics.evalPlace (k + 1) P st .read (.local slice) =
      .done { root, projections := [], value := some (.rawSlice element address length) } st)
    (idxRun : evalExpr (k + 1) P st idx = .done iv st1) (posOk : Semantics.integerIndex iv = .ok pos)
    (lt : pos < length) (located : Semantics.rawSliceElementAddress? P element address pos = .ok at_)
    (h : evalExpr (k + 2) P st1 e = .trapped r s) :
    evalExpr (k + 3) P st (.assign .set (.index (.local slice) idx) e) = .trapped r s := by
  generalize hout : evalExpr (k + 3) P st (.assign .set (.index (.local slice) idx) e) = out
  rw [evalExpr] at hout
  rw [Semantics.evalPlace] at hout
  rw [base] at hout
  simp only [idxRun, posOk, lt, if_true, decide_true, located, h] at hout
  exact hout.symm

theorem setIndex_value_done {iv : Value} {st1 : State} {pos at_ : Nat} {right : Value} {st2 : State}
    (views : st2.i32ArrayViews = [])
    (base : Semantics.evalPlace (k + 1) P st .read (.local slice) =
      .done { root, projections := [], value := some (.rawSlice element address length) } st)
    (idxRun : evalExpr (k + 1) P st idx = .done iv st1) (posOk : Semantics.integerIndex iv = .ok pos)
    (lt : pos < length) (located : Semantics.rawSliceElementAddress? P element address pos = .ok at_)
    (eRun : evalExpr (k + 2) P st1 e = .done right st2) :
    (∃ st', evalExpr (k + 3) P st (.assign .set (.index (.local slice) idx) e) = .done .unit st' ∧
      st'.heap.nextAddress = st2.heap.nextAddress) ∨
    ∃ r, evalExpr (k + 3) P st (.assign .set (.index (.local slice) idx) e) = .trapped r st2 ∧
      undefinedTrap r = true := by
  generalize hout : evalExpr (k + 3) P st (.assign .set (.index (.local slice) idx) e) = out
  rw [evalExpr] at hout
  rw [Semantics.evalPlace] at hout
  rw [base] at hout
  simp only [idxRun, posOk, lt, if_true, decide_true, located, eRun, Semantics.evalAssignValue,
    Semantics.assignOpBinary?, Semantics.writeResolvedPlaceNative] at hout
  cases stored : Semantics.writeNativeValue NativeLayout.maxDepth P st2 st2.heap element at_ right with
  | error r =>
    simp only [stored, bind, Except.bind] at hout
    exact .inr ⟨r, hout.symm, writeNativeValue_undef _ _ _ _ _ _ _ views r stored⟩
  | ok heap =>
    simp only [stored, bind, Except.bind, pure, Except.pure, Semantics.syncI32ViewsFromHeap, views,
      Semantics.syncI32ViewsFromHeapFrom, ite_self] at hout
    exact .inl ⟨_, hout.symm, writeNativeValue_next _ stored⟩

end SetIndex

theorem stops_setIndexEval (lowered : lowerFuncs (sigs sp.funcs) sp.decls sp.funcs = some mp.funcs)
    {slice : Nat} {index value : SrcEff} (ihi : EffStops sp mp n index) (ihv : EffStops sp mp n value) :
    SrcStops sp mp n (.setIndexEval slice index value) := by
  intro hp ret scope next stmt frame base st env ok corr fr fresh le hc within fails
  simp only [SrcStmt.lower, lowerSetIndexEval] at ok
  split at ok
  · simp at ok
  rename_i b found
  split at ok
  · simp at ok
  rename_i element elementOk
  have bty := eq_of_elementOf elementOk
  have shape : ∃ i w rest, index.eval (sigs sp.funcs) sp.decls scope next = some i ∧
      value.eval (sigs sp.funcs) sp.decls scope (next + 1) = some w ∧
      (i.ty.isI32 || i.ty.isUint .usize) = true ∧
      stmt = .seq i.stmt (checkThen next (boundsGuard b (.var next)) (.seq w.stmt rest)) := by
    simp only [storeEvalElement] at ok
    split at ok
    · split at ok
      · simp at ok
      rename_i i indexOk
      split at ok
      · simp at ok
      rename_i w valueOk
      simp only [storeEval] at ok
      split at ok
      case isFalse => simp at ok
      rename_i cond
      simp only [Bool.and_eq_true] at cond
      simp only [Option.some.injEq] at ok
      exact ⟨i, w, _, indexOk, valueOk, cond.1, ok.symm⟩
    · split at ok
      · simp at ok
      rename_i i indexOk
      split at ok
      · simp at ok
      rename_i w valueOk
      have cond := storeEvalWord_cond ok
      simp only [Bool.and_eq_true] at cond
      simp only [storeEvalWord] at ok
      split at ok
      case isFalse => simp at ok
      simp only [storeEvalThen] at ok
      split at ok
      case isFalse => simp at ok
      split at ok
      · simp at ok
      simp only [Option.some.injEq] at ok
      exact ⟨i, w, _, indexOk, valueOk, cond.1, ok.symm⟩
  obtain ⟨i, w, rest, indexOk, valueOk, kind, rfl⟩ := shape
  have bmem := (lookup_mem found).1
  obtain ⟨w0, place0, holdsW⟩ := corr.readPlace found 0 sp.toCore
  rw [bty] at holdsW
  cases holdsW with
  | @slice _ len _ _ lenSlot lenSmall =>
  have placeAt : ∀ f, Semantics.evalPlace (f + 1) sp.toCore st .read (.local slice) =
      .done { root := frame b.slot, projections := [], value := some (.rawSlice element.toCore (env b.slot).toNat len) }
        st := fun f => by
    have refines := Semantics.evalPlace_refines (program := sp.toCore) (state := st) (access := .read)
      (place := .local slice) (Nat.le_add_left 1 f)
    rw [place0] at refines
    exact refines.completed (by intro h; cases h)
  simp only [SrcStmt.toCore] at fails
  have efails := fails.expression
  rcases eff_split lowered ihi indexOk corr fr fresh hc within efails
      (fun j r s h => ⟨j + 3, s, setIndex_idx_trap (placeAt j)
        (Semantics.evalExpr_of_le h (by intro h; cases h) (Nat.le_succ j)), rfl⟩) with
    ⟨d, stops⟩ | ⟨k, iv, st1, indexRun, bound1, fresh1, keeps1, locals1, _, d1, env1, hp1, exec1, same1, holds1, hc1⟩
  · exact ⟨d, .seqFirst stops⟩
  by_cases zero : (boundsGuard b (.var next)).eval env1 = 0
  · exact ⟨_, Stops.after exec1 (Stops.check (d := 0) fun h => absurd zero h)⟩
  have slot2 : b.slot + 1 < next := by
    have := fr.slots b bmem
    rw [bty] at this
    simp only [SrcType.size] at this
    omega
  have inBounds := boundsGuard_ne zero
  rw [same1 _ slot2, lenSlot] at inBounds
  have scalar : i.ty.isScalar = true := by
    cases hty : i.ty <;> simp_all [SrcType.isI32, SrcType.isUint, SrcType.isScalar]
  have posOk := index_ok (t := { expr := .var next, ty := i.ty }) kind (holds_var holds1 scalar) (by omega)
  have limit := exec1.limit_normal
  cases located : Semantics.rawSliceElementAddress? sp.toCore element.toCore (env b.slot).toNat
      ((Expr.var next).eval env1).toNat with
  | error r =>
    obtain ⟨run, undefined⟩ := setIndex_address_undef (e := value.toCore) (placeAt k)
      (value_after indexRun (Nat.le_succ k)) posOk inBounds located
    have := efails (k + 3)
    rw [run] at this
    simp only [Failing] at this
    exact (trap_within this undefined bound1).elim
  | ok at_ =>
    have efails1 : EFails sp hp1.limit st (.assign .set (.index (.local slice) index.toCore) value.toCore) := by
      rw [limit]; exact efails
    rcases eff_split lowered ihv valueOk (corr.after fr fresh keeps1 locals1 same1) (fr.mono (Nat.le_succ _))
        fresh1 hc1 (by rw [limit]; exact bound1) efails1
        (fun j r s h => ⟨k + j + 3, s, setIndex_value_trap (placeAt (k + j))
          (value_after indexRun (by omega)) posOk inBounds located
          (Semantics.evalExpr_of_le h (by intro h; cases h) (by omega)), rfl⟩) with
      ⟨d, stops⟩ | ⟨j, right, st2, valueRun, bound2, fresh2, -⟩
    · exact ⟨_, Stops.after exec1 (Stops.check fun _ => .seqFirst stops)⟩
    · rcases setIndex_value_done fresh2.2 (placeAt (k + j)) (value_after indexRun (by omega)) posOk inBounds
          located (value_after valueRun (by omega)) with ⟨st', run, keepsNext⟩ | ⟨r, run, undefined⟩
      · exact (efails1.not_done run (by rw [keepsNext]; exact bound2)).elim
      · have := efails (k + j + 3)
        rw [run] at this
        simp only [Failing] at this
        exact (trap_within this undefined (by rw [← limit]; exact bound2)).elim

end Statements

end Lanius.Mini

namespace Lanius.Mini

/-- Every lowered effectful expression whose Core evaluation fails stops
within `n + 1` ticks, given that every failing statement stops within `n`
(for the bodies of the calls in it). -/
theorem effStops_all {sp : SrcProgram} {mp : Program} {n : Nat}
    (lowered : lowerFuncs (sigs sp.funcs) sp.decls sp.funcs = some mp.funcs)
    (returns : funcsReturn sp.funcs = true) (prev : StmtStops sp mp n) : ∀ e, EffStops sp mp (n + 1) e
  | .ePure _ => eff_pure
  | .eCall _ args => eff_call lowered returns prev fun e _ => effStops_all lowered returns prev e
  | .eApply _ l r => eff_apply lowered (effStops_all lowered returns prev l) (effStops_all lowered returns prev r)
  | .eNeg operand => eff_neg lowered (effStops_all lowered returns prev operand)
  | .eNot operand => eff_not lowered (effStops_all lowered returns prev operand)
  | .eCast _ operand => eff_cast lowered (effStops_all lowered returns prev operand)
  | .eIndex _ index => eff_index lowered (effStops_all lowered returns prev index)
  | .eStruct _ fields => eff_struct lowered fun e _ => effStops_all lowered returns prev e
  | .eVariant _ _ payload => eff_variant lowered fun e _ => effStops_all lowered returns prev e
  | .eMatch scrutinee _ _ _ values =>
      eff_match lowered (effStops_all lowered returns prev scrutinee) fun e _ => effStops_all lowered returns prev e
  | .eDivide _ l r => eff_divide lowered (effStops_all lowered returns prev l) (effStops_all lowered returns prev r)
  | .eStride _ => eff_stride
termination_by e => sizeOf e

/-- Every lowered statement whose Core run fails stops within `n + 1` ticks
when every one stops within `n`: by structural recursion on the statement,
with a loop's next iteration and a callee's body at `n`. -/
theorem stmtStops_succ {sp : SrcProgram} {mp : Program} {n : Nat}
    (lowered : lowerFuncs (sigs sp.funcs) sp.decls sp.funcs = some mp.funcs)
    (returns : funcsReturn sp.funcs = true) (prev : StmtStops sp mp n) : StmtStops sp mp (n + 1)
  | .nop => stops_nop
  | .let _ _ _ body => stops_let (stmtStops_succ lowered returns prev body)
  | .letStruct _ _ _ body => stops_letStruct (stmtStops_succ lowered returns prev body)
  | .letCall _ _ _ _ body => stops_letCall lowered returns prev (stmtStops_succ lowered returns prev body)
  | .letEnum _ _ _ _ body => stops_letEnum (stmtStops_succ lowered returns prev body)
  | .letMatch _ _ _ _ _ body => stops_letMatch (stmtStops_succ lowered returns prev body)
  | .set _ _ => stops_set
  | .setField _ _ _ => stops_setField
  | .setCall _ _ _ => stops_setCall lowered returns prev
  | .then first second =>
      stops_then lowered (stmtStops_succ lowered returns prev first) (stmtStops_succ lowered returns prev second)
  | .if _ thenBranch elseBranch =>
      stops_if lowered (stmtStops_succ lowered returns prev thenBranch)
        (stmtStops_succ lowered returns prev elseBranch)
  | .while _ body => stops_while lowered prev (stmtStops_succ lowered returns prev body)
  | .return _ => stops_return
  | .letAlloc _ _ _ body => stops_letAlloc (stmtStops_succ lowered returns prev body)
  | .letLoad _ _ _ body => stops_letLoad (stmtStops_succ lowered returns prev body)
  | .setByte _ _ _ => stops_setByte
  | .free _ _ _ => stops_free
  | .letSlice _ _ _ _ body => stops_letSlice (stmtStops_succ lowered returns prev body)
  | .letIndex _ _ slice index body => stops_letIndex (stmtStops_succ lowered returns prev body)
      (stops_letEval lowered (effStops_all lowered returns prev (.eIndex slice (.ePure index)))
        (stmtStops_succ lowered returns prev body))
  | .setIndex _ _ _ => stops_setIndex
  | .letEval _ _ value body =>
      stops_letEval lowered (effStops_all lowered returns prev value) (stmtStops_succ lowered returns prev body)
  | .setEval _ value => stops_setEval lowered (effStops_all lowered returns prev value)
  | .ifEval condition thenBranch elseBranch =>
      stops_ifEval lowered (effStops_all lowered returns prev condition)
        (stmtStops_succ lowered returns prev thenBranch) (stmtStops_succ lowered returns prev elseBranch)
  | .whileEval condition body =>
      stops_whileEval lowered (effStops_all lowered returns prev condition) (stmtStops_succ lowered returns prev body)
  | .returnEval value => stops_returnEval lowered (effStops_all lowered returns prev value)
  | .discard value => stops_discard (effStops_all lowered returns prev value)
  | .setIndexEval _ index value =>
      stops_setIndexEval lowered (effStops_all lowered returns prev index) (effStops_all lowered returns prev value)
  | .setFieldEval _ _ value => stops_setFieldEval lowered (effStops_all lowered returns prev value)
  | .returnUnit => stops_returnUnit
  | .break => stops_break
  | .continue => stops_continue
  | .matchArm _ _ _ _ _ _ body rest =>
      stops_matchArm (stmtStops_succ lowered returns prev body) (stmtStops_succ lowered returns prev rest)
  | .assert condition => stops_assert lowered (effStops_all lowered returns prev condition)
  | .unreachable _ _ => stops_unreachable

/-- Every lowered statement whose Core run fails stops for every number of
ticks. -/
theorem stmtStops_all {sp : SrcProgram} {mp : Program}
    (lowered : lowerFuncs (sigs sp.funcs) sp.decls sp.funcs = some mp.funcs)
    (returns : funcsReturn sp.funcs = true) : ∀ n, StmtStops sp mp n
  | 0 => fun _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ => ⟨0, .zero⟩
  | n + 1 => stmtStops_succ lowered returns (stmtStops_all lowered returns n)

end Lanius.Mini
