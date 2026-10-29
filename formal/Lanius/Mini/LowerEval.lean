import Lanius.Mini.LowerStmt

/-! Effectful expressions (`SrcEff`): calls anywhere in an expression, in
Core's evaluation order. `e.eval sigs scope slot` is code that leaves the
value in the slots from `slot`; `EvalSound` says it represents Core's value.
It is proved together with `StmtSound`, by induction on Core's fuel, which
drops at every subexpression, so `SrcEff` (which nests through `List`) needs
no structural induction. -/

namespace Lanius.Mini

open Lanius.Core (Value)
open Lanius.Semantics (State Cell Completion evalExpr evalExprs execStmt restoreLocals)

/-! ## Slots -/

theorem SrcType.Holds.scalar {ty : SrcType} {v : Value} {x : BitVec 64} (holds : ty.Holds v x) :
    ty.isScalar = true := by
  cases ty <;> simp_all [SrcType.Holds, SrcType.isScalar]

theorem set_below {env : Env} {slot j : Nat} {x : BitVec 64} (below : j < slot) : env.set slot x j = env j := by
  simp only [Env.set]
  rw [if_neg (by omega)]

theorem holdsAt_set {ty : SrcType} {v : Value} {x : BitVec 64} (holds : ty.Holds v x) (env : Env)
    (slot : Nat) : ty.HoldsAt v (env.set slot x) slot :=
  (SrcType.holdsAt_scalar holds.scalar).mpr (by simpa [Env.set] using holds)

theorem holds_var {ty : SrcType} {v : Value} {env : Env} {slot : Nat} (holds : ty.HoldsAt v env slot)
    (scalar : ty.isScalar = true) : ty.Holds v ((Expr.var slot).eval env) :=
  (SrcType.holdsAt_scalar scalar).mp holds

theorem entry_slotVars (env : Env) (slot n : Nat) {i : Nat} (below : i < n) :
    Func.entry (Expr.evalAll env (slotVars slot n)) i = env (slot + i) := by
  rw [entry_evalAll env _ i _ (slotVars_get slot n i below)]
  rfl

theorem setFrom_slotVars (env : Env) {src dst n i : Nat} (apart : src + n ≤ dst ∨ dst + n ≤ src)
    (below : i < n) : env.setFrom dst (slotVars src n) (dst + i) = env (src + i) := by
  rw [setFrom_value _ dst env (Insens.copy (.inr apart)) i _ (slotVars_get src n i below)]
  rfl

/-- A copy down to `dst` from `src` above it never reads a slot it has
already written. -/
theorem Insens.down {src dst n : Nat} (le : dst ≤ src) : Insens (slotVars src n) dst := by
  intro i x found j below E w
  have inRange : i < n := by
    obtain ⟨h, _⟩ := List.getElem?_eq_some_iff.mp found
    rw [slotVars_length] at h
    exact h
  rw [slotVars_get src n i inRange, Option.some.injEq] at found
  subst found
  simp only [Expr.eval, Env.set]
  rw [if_neg (by omega)]

/-- A value at `slot + 1` copied down by one slot. -/
theorem copy_down {ty : SrcType} {v : Value} {F : Env} {slot : Nat} (holds : ty.HoldsAt v F (slot + 1)) :
    ty.HoldsAt v (F.setFrom slot (slotVars (slot + 1) ty.size)) slot ∧
      ∀ j < slot, F.setFrom slot (slotVars (slot + 1) ty.size) j = F j :=
  ⟨holds.congr fun i below => by
      rw [setFrom_value _ slot F (Insens.down (Nat.le_succ slot)) i _ (slotVars_get (slot + 1) ty.size i below)]
      rfl,
    fun j lt => setFrom_outside _ slot F j (.inl lt)⟩

theorem Corr.after {scope frame st env base slot} (corr : Corr scope frame st env)
    (fr : Layout scope frame base slot) (fresh : st.Fresh) {st' : State} {env' : Env}
    (keeps : Keeps st.nextCell st st') (locals : st'.locals = st.locals) (same : ∀ j < slot, env' j = env j) :
    Corr scope frame st' env' :=
  (corr.keeps fresh keeps locals).env_congr (fr.agree same)

theorem Keeps.chain {st st1 st2 : State} (first : Keeps st.nextCell st st1)
    (second : Keeps st1.nextCell st1 st2) : Keeps st.nextCell st st2 :=
  first.trans (second.lower first.next)

/-- The cursor after a subexpression is within any bound the end is. -/
theorem grown_bound {st st' : State} (grown : Grows st st') (fresh : st.Fresh) {L : Nat}
    (bound : st'.heap.nextAddress ≤ L) : st.heap.nextAddress ≤ L :=
  Nat.le_trans (grown fresh.2).2 bound

theorem eff_grown {sp : SrcProgram} {k : Nat} {st : State} {e : SrcEff} {v : Value} {st' : State}
    (run : evalExpr k sp.toCore st e.toCore = .done v st') : Grows st st' :=
  eff_grows k (grows sp k) k (Nat.le_refl _) run

/-! ## Unary operators -/

theorem negate_holds {inner t : Typed} {env : Env} {w r : Value} (lowered : lowerNegateTyped inner = some t)
    (holds : inner.ty.Holds w (inner.expr.eval env))
    (run : Semantics.evalUnaryValue .x86_64 .negate w = .ok r) : t.ty.Holds r (t.expr.eval env) := by
  simp only [lowerNegateTyped] at lowered
  split at lowered
  · rename_i isInt
    simp only [Option.some.injEq] at lowered
    subst lowered
    cases hty : inner.ty <;> simp [hty, SrcType.isI32] at isInt
    rw [hty] at holds
    obtain ⟨rfl, _⟩ := holds
    simp only [Semantics.evalUnaryValue, Except.ok.injEq] at run
    subst run
    simp only [Expr.eval]
    rw [wrap_neg]
    exact holds_i32 _
  split at lowered
  · rename_i isIsize
    simp only [Option.some.injEq] at lowered
    subst lowered
    cases hty : inner.ty <;> simp [hty, SrcType.isIsize] at isIsize
    rw [hty] at holds
    subst holds
    rw [eval_isize_neg, Except.ok.injEq] at run
    subst run
    rfl
  · simp at lowered

theorem not_holds {inner t : Typed} {env : Env} {w r : Value} (lowered : lowerNotTyped inner = some t)
    (holds : inner.ty.Holds w (inner.expr.eval env))
    (run : Semantics.evalUnaryValue .x86_64 .logicalNot w = .ok r) : t.ty.Holds r (t.expr.eval env) := by
  simp only [lowerNotTyped] at lowered
  split at lowered
  · rename_i isBool
    simp only [Option.some.injEq] at lowered
    subst lowered
    cases hty : inner.ty <;> simp [hty, SrcType.isBool] at isBool
    rw [hty] at holds
    obtain ⟨x, rfl, bits⟩ := holds
    simp only [Semantics.evalUnaryValue, Except.ok.injEq] at run
    subst run
    refine ⟨!x, rfl, ?_⟩
    cases x <;> simp [Expr.eval, Word.holds, CmpOp.holds, bits, boolBits] <;> decide
  · simp at lowered

/-- Core evaluates a strict binary operator's sides in order. -/
theorem binary_inv {P : Core.Program} {st : State} {l r : Core.Expr} {cop : Core.BinaryOp} {fuel : Nat}
    {v : Value} {st' : State} (general : cop ≠ .logicalAnd ∧ cop ≠ .logicalOr)
    (run : evalExpr (fuel + 1) P st (.binary cop l r) = .done v st') :
    ∃ vl st1 vr, evalExpr fuel P st l = .done vl st1 ∧ evalExpr fuel P st1 r = .done vr st' ∧
      Semantics.evalBinaryValue P.target cop vl vr = .ok v := by
  cases cop <;> simp only [ne_eq, not_true_eq_false, false_and, and_false, reduceCtorEq,
    not_false_eq_true, and_self] at general <;>
  · simp only [evalExpr] at run
    split at run
    · rename_i vl st1 leftRun
      split at run
      · rename_i vr st2 rightRun
        split at run
        · rename_i result evaluated
          simp only [Semantics.Outcome.done.injEq] at run
          obtain ⟨rfl, rfl⟩ := run
          exact ⟨vl, st1, vr, leftRun, rightRun, evaluated⟩
        · simp at run
      all_goals simp at run
    all_goals simp at run

/-- Core evaluates a unary operator's operand, then applies it. -/
theorem unary_inv {P : Core.Program} {st : State} {e : Core.Expr} {op : Core.UnaryOp} {fuel : Nat}
    {v : Value} {st' : State} (run : evalExpr (fuel + 1) P st (.unary op e) = .done v st') :
    ∃ w, evalExpr fuel P st e = .done w st' ∧ Semantics.evalUnaryValue P.target op w = .ok v := by
  simp only [evalExpr] at run
  split at run
  · rename_i w st1 operandRun
    split at run
    · rename_i result evaluated
      simp only [Semantics.Outcome.done.injEq] at run
      obtain ⟨rfl, rfl⟩ := run
      exact ⟨w, operandRun, evaluated⟩
    · simp at run
  all_goals simp at run

theorem cast_inv {P : Core.Program} {st : State} {e : Core.Expr} {ty : Core.ScalarTy} {fuel : Nat}
    {v : Value} {st' : State} (run : evalExpr (fuel + 1) P st (.cast ty e) = .done v st') :
    ∃ w, evalExpr fuel P st e = .done w st' ∧ Semantics.evalScalarCast P.target ty w = .ok v := by
  simp only [evalExpr] at run
  split at run
  · rename_i w st1 operandRun
    split at run
    · rename_i result evaluated
      simp only [Semantics.Outcome.done.injEq] at run
      obtain ⟨rfl, rfl⟩ := run
      exact ⟨w, operandRun, evaluated⟩
    · simp at run
  all_goals simp at run

/-! ## Division -/

theorem truncDiv_eq_tdiv (l r : Int) : Semantics.truncDiv l r = l.tdiv r := by
  unfold Semantics.truncDiv
  cases l with
  | ofNat m =>
    have hm : ¬((m : Int) < 0) := by omega
    cases r with
    | ofNat n =>
      have hn : ¬((n : Int) < 0) := by omega
      simp [Int.tdiv, hm, hn]
    | negSucc n => simp [Int.tdiv, Int.negSucc_lt_zero, hm]
  | negSucc m =>
    cases r with
    | ofNat n =>
      have hn : ¬((n : Int) < 0) := by omega
      simp [Int.tdiv, Int.negSucc_lt_zero, hn]
    | negSucc n => simp [Int.tdiv, Int.negSucc_lt_zero]

theorem eval_i32_div {x y : BitVec 32} {op : DivOp} {cop : Core.BinaryOp}
    (h : (cop = .divide ∧ op = .sDiv) ∨ (cop = .remainder ∧ op = .sRem)) {v : Core.Value}
    (run : Semantics.evalBinaryValue .x86_64 cop (.signed .i32 x.toInt) (.signed .i32 y.toInt) = .ok v) :
    op.defined x y = true ∧ v = .signed .i32 (op.apply x y).toInt := by
  rcases h with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩
  all_goals
    simp [Semantics.evalBinaryValue, Semantics.evalSignedBinary] at run
    split at run
    · simp at run
    rename_i nonzero
    split at run
    · simp at run
    rename_i notMin
    simp only [Except.ok.injEq] at run
    subst run
    have y0 : y ≠ 0 := fun h => nonzero (by simp [h])
    have notBoth : ¬(x = BitVec.intMin 32 ∧ y = -1) := fun ⟨hx, hy⟩ =>
      notMin ⟨by subst hx; decide, by subst hy; decide⟩
    refine ⟨by simp only [DivOp.defined]; simp; by_cases hx : x = BitVec.intMin 32 <;> simp_all, ?_⟩
  · rw [truncDiv_eq_tdiv, wrapSigned_i32, BitVec.toInt_ofInt, DivOp.apply, BitVec.toInt_sdiv]
  · rw [truncDiv_eq_tdiv, show x.toInt - x.toInt.tdiv y.toInt * y.toInt = x.toInt.tmod y.toInt by rw [Int.tmod_def, Int.mul_comm],
      DivOp.apply, ← BitVec.toInt_srem, wrapSigned_i32, BitVec.ofInt_toInt]

theorem eval_uint_div (k : UintTy) {a b : BitVec 64} (ha : a.toNat < 2 ^ k.width) {op : DivOp}
    {cop : Core.BinaryOp} (h : (cop = .divide ∧ op = .uDiv) ∨ (cop = .remainder ∧ op = .uRem))
    {v : Core.Value}
    (run : Semantics.evalBinaryValue .x86_64 cop (.unsigned k.toCore a.toNat) (.unsigned k.toCore b.toNat) = .ok v) :
    op.defined a b = true ∧ v = .unsigned k.toCore (op.apply a b).toNat ∧ (op.apply a b).toNat < 2 ^ k.width := by
  rcases h with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩
  all_goals
    simp [Semantics.evalBinaryValue, Semantics.evalUnsignedBinary] at run
    split at run
    · simp at run
    rename_i nonzero
    simp only [Except.ok.injEq] at run
    subst run
    have b0 : b ≠ 0 := fun h => nonzero (by simp [h])
  · have le := Nat.div_le_self a.toNat b.toNat
    refine ⟨by simp [DivOp.defined]; exact b0, ?_, by simp only [DivOp.apply, BitVec.toNat_udiv]; omega⟩
    simp only [DivOp.apply, BitVec.toNat_udiv, Semantics.wrapUnsigned, Semantics.unsignedModulus, UintTy.bits_toCore]
    rw [Nat.mod_eq_of_lt (by omega)]
  · have pos : 0 < b.toNat := by
      rcases Nat.eq_zero_or_pos b.toNat with z | p
      · exact absurd (BitVec.eq_of_toNat_eq (by simp [z])) b0
      · exact p
    have le := Nat.mod_lt a.toNat pos
    have le2 := Nat.mod_le a.toNat b.toNat
    refine ⟨by simp [DivOp.defined]; exact b0, ?_, by simp only [DivOp.apply, BitVec.toNat_umod]; omega⟩
    simp only [DivOp.apply, BitVec.toNat_umod, Semantics.wrapUnsigned, Semantics.unsignedModulus, UintTy.bits_toCore]
    rw [Nat.mod_eq_of_lt (by omega)]

theorem divOp_signed (op : SrcDivOp) :
    (op.toCore = .divide ∧ signedDiv op = .sDiv) ∨ (op.toCore = .remainder ∧ signedDiv op = .sRem) := by
  cases op <;> simp [SrcDivOp.toCore, signedDiv]

theorem divOp_unsigned (op : SrcDivOp) :
    (op.toCore = .divide ∧ unsignedDiv op = .uDiv) ∨ (op.toCore = .remainder ∧ unsignedDiv op = .uRem) := by
  cases op <;> simp [SrcDivOp.toCore, unsignedDiv]

theorem eq_of_isI32 {ty : SrcType} (h : ty.isI32 = true) : ty = .i32 := by
  cases ty <;> simp_all [SrcType.isI32]

theorem eq_of_isUint {ty : SrcType} {k : UintTy} (h : ty.isUint k = true) : ty = .uint k := by
  cases ty <;> simp [SrcType.isUint] at h
  rw [UintTy.eq_of_code h]

/-! ## The simulation of an expression -/

/-- What the code of an effectful expression does: Core went from `st` to
`st'` with value `v`, and the mini code runs from `env` to an `env'` that
holds `v` from `slot` and agrees with `env` below it. -/
abbrev Evaluates (mp : Program) (hp : Heap) (slot : Nat) (st : State) (env : Env) (ev : Evaluated)
    (v : Value) (st' : State) : Prop :=
  st'.Fresh ∧ Keeps st.nextCell st st' ∧ st'.locals = st.locals ∧ 0 < ev.ty.size ∧
    ∃ d env' hp', Exec mp d env hp ev.stmt (.normal env' hp') ∧ (∀ j < slot, env' j = env j) ∧
      ev.ty.HoldsAt v env' slot ∧ HeapCorr st'.heap hp'

/-- Every effectful expression lowered for `sp` that Core evaluates with
`fuel`, ending with its heap cursor within the mini heap's limit, has mini
code leaving a representation of its value from `slot`. -/
def EvalSound (sp : SrcProgram) (mp : Program) (fuel : Nat) : Prop :=
  ∀ {hp : Heap} {e : SrcEff} {scope : List Binding} {slot : Nat} {ev : Evaluated}
    {frame : Nat → Nat} {base : Nat} {st : State} {env : Env} {v : Value} {st' : State},
    e.eval (sigs sp.funcs) sp.decls scope slot = some ev →
    Corr scope frame st env → Layout scope frame base slot → st.Fresh →
    HeapCorr st.heap hp → evalExpr fuel sp.toCore st e.toCore = .done v st' →
    st'.heap.nextAddress ≤ hp.limit →
    Evaluates mp hp slot st env ev v st'

/-- The amount check of a shift of two evaluated operands passes. -/
theorem operandGuard_pass {op : SrcOp} {slot : Nat} {lty rty : SrcType} {t : Typed}
    (lowered : op.lower ⟨.var slot, lty⟩ ⟨.var (slot + 1), rty⟩ = some t) {env : Env} {vl vr v : Value}
    (holdsl : lty.Holds vl ((Expr.var slot).eval env)) (holdsr : rty.Holds vr ((Expr.var (slot + 1)).eval env))
    (evaluated : Semantics.evalBinaryValue .x86_64 op.toCore vl vr = .ok v) {x : BitVec 64} :
    (operandGuard op lty (slot + 1)).eval (env.set slot x) ≠ 0 := by
  have amount : (operandGuard op lty (slot + 1)).eval (env.set slot x) = 1 := by
    cases op
    case shiftLeft | shiftRight =>
      refine amountGuard_one ?_
      have lt := shift_amount (by simp) lowered holdsl holdsr evaluated
      simpa [Expr.eval, Env.set] using lt
    all_goals rfl
  rw [amount]
  decide

section Cases

variable {sp : SrcProgram} {mp : Program} {hp : Heap} {scope : List Binding} {slot : Nat}
  {ev : Evaluated} {frame : Nat → Nat} {base : Nat} {st : State} {env : Env} {v : Value} {st' : State}

theorem eval_pure {e : SrcExpr} {fuel : Nat} (ok : evalPure scope e slot = some ev)
    (corr : Corr scope frame st env) (fr : Layout scope frame base slot) (fresh : st.Fresh)
    (hc : HeapCorr st.heap hp) (run : evalExpr fuel sp.toCore st e.toCore = .done v st') :
    Evaluates mp hp slot st env ev v st' := by
  simp only [evalPure] at ok
  split at ok
  · rename_i t lowered
    simp only [evalChecked, Option.some.injEq] at ok
    subst ok
    have one := e.guard_sound corr (SrcProgram.target_toCore sp) lowered run
    obtain ⟨rfl, holds⟩ := e.lower_sound corr (SrcProgram.target_toCore sp) lowered run
    exact ⟨fresh, Keeps.refl _ _, rfl, by rw [SrcType.size_scalar holds.scalar]; decide, 0, _, hp, Exec.assign.checkThen one,
      fun j below => set_below below, holdsAt_set holds env slot, hc⟩
  · cases e
    case «local» id =>
      simp only [evalCopy] at ok
      split at ok
      · simp at ok
      rename_i b found
      simp only [evalValues] at ok
      split at ok
      · simp at ok
      rename_i xs valueOk
      simp only [Option.some.injEq] at ok
      subst ok
      obtain ⟨rfl, flat, shape⟩ := lowerValue_sound corr (SrcProgram.target_toCore sp) valueOk run
      exact ⟨fresh, Keeps.refl _ _, rfl, fr.sized b (lookup_mem found).1, 0, _, hp, assignFrom_exec xs slot .skip,
        fun j below => setFrom_outside xs slot env j (.inl below), flat.store (shape.insens_next fr), hc⟩
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
        rename_i pos
        simp only [evalValues] at ok
        split at ok
        · simp at ok
        rename_i xs valueOk
        simp only [Option.some.injEq] at ok
        subst ok
        obtain ⟨rfl, flat, shape⟩ := lowerValue_sound corr (SrcProgram.target_toCore sp) valueOk run
        exact ⟨fresh, Keeps.refl _ _, rfl, pos, 0, _, hp, assignFrom_exec xs slot .skip,
          fun j below => setFrom_outside xs slot env j (.inl below), flat.store (shape.insens_next fr), hc⟩
      all_goals simp at ok
    all_goals simp at ok

/-- Arguments evaluated one after another into consecutive slots. -/
theorem evalArgs_sound : ∀ (args : List SrcEff) {k : Nat}, (∀ m < k, EvalSound sp mp m) →
    ∀ {hp : Heap} {slot : Nat} {ea : EvaluatedArgs} {st : State} {env : Env} {vs : List Value} {st' : State},
    evalArgs (sigs sp.funcs) sp.decls scope args slot = some ea → Corr scope frame st env →
    Layout scope frame base slot → st.Fresh → HeapCorr st.heap hp →
    evalExprs k sp.toCore st (SrcEff.toCoreList args) = .done vs st' → st'.heap.nextAddress ≤ hp.limit →
    st'.Fresh ∧ Keeps st.nextCell st st' ∧ st'.locals = st.locals ∧
      ∃ d env' hp', Exec mp d env hp ea.stmt (.normal env' hp') ∧ (∀ j < slot, env' j = env j) ∧
        FieldsHold ea.types vs env' slot ∧ HeapCorr st'.heap hp'
  | [], k, _, hp, slot, ea, st, env, vs, st', ok, corr, fr, fresh, hc, run, bound => by
    cases k with
    | zero => simp [evalExprs] at run
    | succ k =>
      simp only [SrcEff.toCoreList, evalExprs, Semantics.Outcome.done.injEq] at run
      obtain ⟨rfl, rfl⟩ := run
      simp only [evalArgs, Option.some.injEq] at ok
      subst ok
      exact ⟨fresh, Keeps.refl _ _, rfl, 0, env, hp, .skip, fun _ _ => rfl, .nil, hc⟩
  | e :: es, k, ihe, hp, slot, ea, st, env, vs, st', ok, corr, fr, fresh, hc, run, bound => by
    cases k with
    | zero => simp [evalExprs] at run
    | succ k =>
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
      simp only [SrcEff.toCoreList, evalExprs] at run
      split at run
      · rename_i v st1 headRun
        split at run
        · rename_i vs' st2 restRun
          simp only [Semantics.Outcome.done.injEq] at run
          obtain ⟨rfl, rfl⟩ := run
          have views1 := (eff_grown headRun fresh.2).1
          have grown := effs_grows es (eff_grows k (grows sp k)) restRun
          obtain ⟨fresh1, keeps1, locals1, _, d1, env1, hp1, exec1, same1, holds1, hc1⟩ :=
            ihe k (Nat.lt_succ_self k) firstOk corr fr fresh hc headRun (Nat.le_trans (grown views1).2 bound)
          obtain ⟨fresh2, keeps2, locals2, d2, env2, hp2, exec2, same2, holds2, hc2⟩ :=
            evalArgs_sound es (fun m lt => ihe m (by omega)) restOk (corr.after fr fresh keeps1 locals1 same1)
              (fr.mono (Nat.le_add_right _ _)) fresh1 hc1 restRun (by rw [exec1.limit_normal]; exact bound)
          exact ⟨fresh2, keeps1.chain keeps2, locals2.trans locals1, max d1 d2, env2, hp2,
            .seq (exec1.mono (Nat.le_max_left _ _)) (exec2.mono (Nat.le_max_right _ _)),
            fun j below => (same2 j (by omega)).trans (same1 j below),
            .cons (holds1.congr fun i below => same2 _ (by omega)) holds2, hc2⟩
        all_goals simp at run
      all_goals simp at run

theorem eval_call (lowered : lowerFuncs (sigs sp.funcs) sp.decls sp.funcs = some mp.funcs) {k : Nat}
    (ih : StmtSound sp mp k) (ihe : ∀ m < k, EvalSound sp mp m) {callee : Nat} {args : List SrcEff}
    (ok : evalCall (sigs sp.funcs)[callee]? callee slot (evalArgs (sigs sp.funcs) sp.decls scope args slot) = some ev)
    (corr : Corr scope frame st env) (fr : Layout scope frame base slot) (fresh : st.Fresh)
    (hc : HeapCorr st.heap hp)
    (run : evalExpr (k + 1) sp.toCore st (.call callee (SrcEff.toCoreList args)) = .done v st')
    (bound : st'.heap.nextAddress ≤ hp.limit) :
    Evaluates mp hp slot st env ev v st' := by
  obtain ⟨f, values, afterArgs, completed, c, argsRun, found, _, bodyRun, result, rfl⟩ := call_inv run
  simp only [sigs_get, found, Option.map_some, evalCall] at ok
  split at ok
  · simp at ok
  rename_i ea argsOk
  simp only [evalCallSig] at ok
  split at ok
  · rename_i checks
    simp only [Bool.and_eq_true, decide_eq_true_eq] at checks
    obtain ⟨same, sized⟩ := checks
    have tyEq := typesSame_eq _ same
    simp only [Option.some.injEq] at ok
    subst ok
    have bound' : completed.heap.nextAddress ≤ hp.limit := bound
    have viewsA := (effs_grows args (eff_grows k (grows sp k)) argsRun fresh.2).1
    have entry := bindLocals_same (paramBindings f.params values) { afterArgs with locals := [] }
    have bodyGrown := (Grows.same entry.1 entry.2).trans (grows sp (k + 1) k (Nat.lt_succ_self k) bodyRun)
    obtain ⟨freshA, keepsA, localsA, dA, envA, hpA, execA, sameA, holdsA, hcA⟩ :=
      evalArgs_sound args ihe argsOk corr fr fresh hc argsRun (Nat.le_trans (bodyGrown viewsA).2 bound')
    rw [tyEq] at holdsA
    have holdsEntry : FieldsHold (paramTypes f.params) values
        (Func.entry (Expr.evalAll envA (slotVars slot (sizes (paramTypes f.params))))) 0 :=
      holdsA.congr fun i below => by rw [Nat.zero_add, entry_slotVars envA slot _ below]
    obtain ⟨freshDone, keeps, d, rs, hp', ⟨g, gFound, arity, exec⟩, holdsRet, len, hcDone⟩ :=
      body_sound lowered ih found (hp := hpA) freshA hcA holdsEntry
        (by rw [evalAll_length, slotVars_length, paramsSize_eq]) bodyRun result (by rw [execA.limit_normal]; exact bound')
    refine ⟨restore_fresh freshDone, keepsA.chain (keeps.trans (restore_keeps _ _ _)), localsA, sized,
      max dA (d + 1), envA.setMany slot rs, hp', .seq (execA.mono (Nat.le_max_left _ _))
        (Exec.call gFound ?_ len (by omega) exec), fun j below => ?_, setMany_holds holdsRet len envA slot, hcDone⟩
    · rw [← arity, evalAll_length]
    · rw [setMany_eq, if_neg (by omega)]
      exact sameA j below
  · simp at ok

/-- Core's `&&` and `||` evaluate the left side, and the right side only when
it decides the value. -/
theorem logical_inv {P : Core.Program} {st : State} {l r : Core.Expr} {fuel : Nat} {v : Value} {st' : State}
    {op : Core.BinaryOp} {stop : Bool} (which : op = .logicalAnd ∧ stop = false ∨ op = .logicalOr ∧ stop = true)
    (run : evalExpr (fuel + 1) P st (.binary op l r) = .done v st') :
    ∃ b st1, evalExpr fuel P st l = .done (.boolean b) st1 ∧
      (b = stop ∧ v = .boolean stop ∧ st' = st1 ∨ b = !stop ∧ evalExpr fuel P st1 r = .done v st') := by
  rcases which with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ <;>
  · simp only [evalExpr] at run
    split at run
    · rename_i st1 leftRun
      simp only [Semantics.Outcome.done.injEq] at run
      obtain ⟨rfl, rfl⟩ := run
      exact ⟨_, st1, leftRun, .inl ⟨rfl, rfl, rfl⟩⟩
    · rename_i st1 leftRun
      exact ⟨_, st1, leftRun, .inr ⟨rfl, run⟩⟩
    all_goals simp at run

theorem bool_bits {v : Value} {x : BitVec 64} (holds : SrcType.bool.Holds v x) :
    ∃ b, v = .boolean b ∧ x = boolBits b := holds

theorem eval_apply {k : Nat} (ihe : EvalSound sp mp k) {op : SrcOp} {l r : SrcEff}
    (ok : evalApply op slot (l.eval (sigs sp.funcs) sp.decls scope slot) (r.eval (sigs sp.funcs) sp.decls scope (slot + 1)) = some ev)
    (corr : Corr scope frame st env) (fr : Layout scope frame base slot) (fresh : st.Fresh)
    (hc : HeapCorr st.heap hp)
    (run : evalExpr (k + 1) sp.toCore st (.binary op.toCore l.toCore r.toCore) = .done v st')
    (bound : st'.heap.nextAddress ≤ hp.limit) :
    Evaluates mp hp slot st env ev v st' := by
  simp only [evalApply] at ok
  split at ok
  · simp at ok
  rename_i le leOk
  split at ok
  · simp at ok
  rename_i re reOk
  simp only [evalOperands] at ok
  split at ok
  · rename_i checks
    simp only [Bool.and_eq_true, decide_eq_true_eq] at checks
    obtain ⟨⟨scalarL, scalarR⟩, strictOp⟩ := checks
    split at ok
    · simp at ok
    rename_i t lowered
    simp only [Option.some.injEq] at ok
    subst ok
    have strict : op ≠ .logicalAnd ∧ op ≠ .logicalOr := by cases op <;> simp_all [shortCircuit]
    have general : op.toCore ≠ .logicalAnd ∧ op.toCore ≠ .logicalOr := by
      cases op <;> simp_all [SrcOp.toCore]
    obtain ⟨vl, st1, vr, lRun, rRun, evaluated⟩ := binary_inv general run
    have views1 := (eff_grown lRun fresh.2).1
    obtain ⟨fresh1, keeps1, locals1, _, d1, env1, hp1, exec1, same1, holds1, hc1⟩ :=
      ihe leOk corr fr fresh hc lRun (Nat.le_trans ((eff_grown rRun) views1).2 bound)
    obtain ⟨fresh2, keeps2, locals2, _, d2, env2, hp2, exec2, same2, holds2, hc2⟩ :=
      ihe reOk (corr.after fr fresh keeps1 locals1 same1) (fr.mono (Nat.le_succ _)) fresh1 hc1 rRun
        (by rw [exec1.limit_normal]; exact bound)
    have sizeL := SrcType.size_scalar scalarL
    have holdsl := holds_var (env := env2) (holds1.congr fun i below => same2 _ (by omega)) scalarL
    have holds := SrcOp.lower_holds lowered strict holdsl (holds_var holds2 scalarR) evaluated
    refine ⟨fresh2, keeps1.chain keeps2, locals2.trans locals1, by rw [SrcType.size_scalar holds.scalar]; decide,
      max d1 d2, _, hp2, .seq (exec1.mono (Nat.le_max_left _ _))
        (.seq (exec2.mono (Nat.le_max_right _ _)) (Exec.assign.thenCheck (operandGuard_pass lowered holdsl
          (holds_var holds2 scalarR) evaluated))),
      fun j below => by rw [set_below below, same2 j (by omega), same1 j below], holdsAt_set holds env2 slot, hc2⟩
  · rename_i notStrict
    split at ok
    · rename_i checks
      simp only [Bool.and_eq_true, decide_eq_true_eq] at checks
      obtain ⟨⟨boolL, boolR⟩, isAnd⟩ := checks
      simp only [Option.some.injEq] at ok
      subst ok
      have opEq : op = .logicalAnd := by cases op <;> simp_all [shortCircuit]
      subst opEq
      cases hl : le.ty <;> simp [hl, SrcType.isBool] at boolL
      cases hr : re.ty <;> simp [hr, SrcType.isBool] at boolR
      obtain ⟨b, st1, lRun, rest⟩ := logical_inv (stop := false) (.inl ⟨rfl, rfl⟩) run
      rcases rest with ⟨rfl, rfl, rfl⟩ | ⟨rfl, rRun⟩
      · obtain ⟨fresh1, keeps1, locals1, _, d1, env1, hp1, exec1, same1, holds1, hc1⟩ :=
          ihe leOk corr fr fresh hc lRun bound
        rw [hl] at holds1
        have bits := (SrcType.holdsAt_scalar rfl).mp holds1
        obtain ⟨_, eq, x⟩ := bool_bits bits
        cases eq
        exact ⟨fresh1, keeps1, locals1, by simp [SrcType.size], d1, env1, hp1,
          .seq exec1 (.ifFalse (by simp [Expr.eval, x, boolBits]) .skip), same1, holds1, hc1⟩
      · have views1 := (eff_grown lRun fresh.2).1
        obtain ⟨fresh1, keeps1, locals1, _, d1, env1, hp1, exec1, same1, holds1, hc1⟩ :=
          ihe leOk corr fr fresh hc lRun (Nat.le_trans ((eff_grown rRun) views1).2 bound)
        rw [hl] at holds1
        obtain ⟨_, eq, x⟩ := bool_bits ((SrcType.holdsAt_scalar rfl).mp holds1)
        cases eq
        obtain ⟨fresh2, keeps2, locals2, _, d2, env2, hp2, exec2, same2, holds2, hc2⟩ :=
          ihe reOk (corr.after fr fresh keeps1 locals1 same1) (fr.mono (Nat.le_succ _)) fresh1 hc1 rRun
            (by rw [exec1.limit_normal]; exact bound)
        rw [hr] at holds2
        refine ⟨fresh2, keeps1.chain keeps2, locals2.trans locals1, by simp [SrcType.size], max d1 d2, _, hp2,
          .seq (exec1.mono (Nat.le_max_left _ _))
            (.ifTrue (by simp [Expr.eval, x, boolBits]) (.seq (exec2.mono (Nat.le_max_right _ _)) .assign)),
          fun j below => by rw [set_below below, same2 j (by omega), same1 j below],
          holdsAt_set ((SrcType.holdsAt_scalar rfl).mp holds2) env2 slot, hc2⟩
    · rename_i notAnd
      split at ok
      · rename_i checks
        simp only [Bool.and_eq_true, decide_eq_true_eq] at checks
        obtain ⟨⟨boolL, boolR⟩, isOr⟩ := checks
        simp only [Option.some.injEq] at ok
        subst ok
        have opEq : op = .logicalOr := by cases op <;> simp_all [shortCircuit]
        subst opEq
        cases hl : le.ty <;> simp [hl, SrcType.isBool] at boolL
        cases hr : re.ty <;> simp [hr, SrcType.isBool] at boolR
        obtain ⟨b, st1, lRun, rest⟩ := logical_inv (stop := true) (.inr ⟨rfl, rfl⟩) run
        rcases rest with ⟨rfl, rfl, rfl⟩ | ⟨rfl, rRun⟩
        · obtain ⟨fresh1, keeps1, locals1, _, d1, env1, hp1, exec1, same1, holds1, hc1⟩ :=
            ihe leOk corr fr fresh hc lRun bound
          rw [hl] at holds1
          obtain ⟨_, eq, x⟩ := bool_bits ((SrcType.holdsAt_scalar rfl).mp holds1)
          cases eq
          exact ⟨fresh1, keeps1, locals1, by simp [SrcType.size], d1, env1, hp1,
            .seq exec1 (.ifTrue (by simp [Expr.eval, x, boolBits]) .skip), same1, holds1, hc1⟩
        · have views1 := (eff_grown lRun fresh.2).1
          obtain ⟨fresh1, keeps1, locals1, _, d1, env1, hp1, exec1, same1, holds1, hc1⟩ :=
            ihe leOk corr fr fresh hc lRun (Nat.le_trans ((eff_grown rRun) views1).2 bound)
          rw [hl] at holds1
          obtain ⟨_, eq, x⟩ := bool_bits ((SrcType.holdsAt_scalar rfl).mp holds1)
          cases eq
          obtain ⟨fresh2, keeps2, locals2, _, d2, env2, hp2, exec2, same2, holds2, hc2⟩ :=
            ihe reOk (corr.after fr fresh keeps1 locals1 same1) (fr.mono (Nat.le_succ _)) fresh1 hc1 rRun
              (by rw [exec1.limit_normal]; exact bound)
          rw [hr] at holds2
          refine ⟨fresh2, keeps1.chain keeps2, locals2.trans locals1, by simp [SrcType.size], max d1 d2, _, hp2,
            .seq (exec1.mono (Nat.le_max_left _ _))
              (.ifFalse (by simp [Expr.eval, x, boolBits]) (.seq (exec2.mono (Nat.le_max_right _ _)) .assign)),
            fun j below => by rw [set_below below, same2 j (by omega), same1 j below],
            holdsAt_set ((SrcType.holdsAt_scalar rfl).mp holds2) env2 slot, hc2⟩
      · simp at ok

/-- A division: both operands, then the mini division, which has a run
whenever Core's has a value. -/
theorem eval_divide {k : Nat} (ihe : EvalSound sp mp k) {op : SrcDivOp} {l r : SrcEff}
    (ok : evalDivision op slot (l.eval (sigs sp.funcs) sp.decls scope slot) (r.eval (sigs sp.funcs) sp.decls scope (slot + 1)) =
      some ev)
    (corr : Corr scope frame st env) (fr : Layout scope frame base slot) (fresh : st.Fresh)
    (hc : HeapCorr st.heap hp)
    (run : evalExpr (k + 1) sp.toCore st (.binary op.toCore l.toCore r.toCore) = .done v st')
    (bound : st'.heap.nextAddress ≤ hp.limit) :
    Evaluates mp hp slot st env ev v st' := by
  simp only [evalDivision] at ok
  split at ok
  · simp at ok
  rename_i le leOk
  split at ok
  · simp at ok
  rename_i re reOk
  have general : op.toCore ≠ .logicalAnd ∧ op.toCore ≠ .logicalOr := by cases op <;> simp [SrcDivOp.toCore]
  obtain ⟨vl, st1, vr, lRun, rRun, evaluated⟩ := binary_inv general run
  have views1 := (eff_grown lRun fresh.2).1
  obtain ⟨fresh1, keeps1, locals1, sized1, d1, env1, hp1, exec1, same1, holds1, hc1⟩ :=
    ihe leOk corr fr fresh hc lRun (Nat.le_trans ((eff_grown rRun) views1).2 bound)
  obtain ⟨fresh2, keeps2, locals2, _, d2, env2, hp2, exec2, same2, holds2, hc2⟩ :=
    ihe reOk (corr.after fr fresh keeps1 locals1 same1) (fr.mono (Nat.le_succ _)) fresh1 hc1 rRun
      (by rw [exec1.limit_normal]; exact bound)
  have below : ∀ (x : BitVec 64), ∀ j < slot, (env2.set slot x) j = env j := fun x j lt => by
    rw [set_below lt, same2 j (by omega), same1 j lt]
  simp only [evalDivide] at ok
  split at ok
  · rename_i both
    simp only [Bool.and_eq_true] at both
    simp only [Option.some.injEq] at ok
    subst ok
    rw [eq_of_isI32 both.1] at holds1
    rw [eq_of_isI32 both.2] at holds2
    have holdsl := holds_var (env := env2) (holds1.congr fun i lt => same2 _ (by simp [SrcType.size] at lt; omega)) rfl
    have holdsr := holds_var holds2 rfl
    obtain ⟨rfl, -⟩ := holdsl
    obtain ⟨rfl, -⟩ := holdsr
    obtain ⟨defined, rfl⟩ := eval_i32_div (divOp_signed op) evaluated
    refine ⟨fresh2, keeps1.chain keeps2, locals2.trans locals1, by simp [SrcType.size], max d1 d2, _, hp2,
      .seq (exec1.mono (Nat.le_max_left _ _)) (.seq (exec2.mono (Nat.le_max_right _ _)) (.divide defined)),
      below _, holdsAt_set (holds_i32 _) env2 slot, hc2⟩
  · split at ok
    · simp at ok
    rename_i kind hk
    simp only [evalDivideUint] at ok
    split at ok
    · rename_i hr
      simp only [Option.some.injEq] at ok
      subst ok
      have lty : le.ty = .uint kind := by cases hty : le.ty <;> simp_all [SrcType.uintKind]
      rw [lty] at holds1
      rw [eq_of_isUint hr] at holds2
      have holdsl := holds_var (env := env2) (holds1.congr fun i lt => same2 _ (by simp [SrcType.size] at lt; omega)) rfl
      have holdsr := holds_var holds2 rfl
      obtain ⟨rfl, small⟩ := holdsl
      obtain ⟨rfl, -⟩ := holdsr
      obtain ⟨defined, rfl, fits⟩ := eval_uint_div kind small (divOp_unsigned op) evaluated
      refine ⟨fresh2, keeps1.chain keeps2, locals2.trans locals1, by simp [SrcType.size], max d1 d2, _, hp2,
        .seq (exec1.mono (Nat.le_max_left _ _)) (.seq (exec2.mono (Nat.le_max_right _ _)) (.divide defined)),
        below _, holdsAt_set (ty := .uint kind) ⟨rfl, fits⟩ env2 slot, hc2⟩
    · simp at ok

theorem eq_of_elementOf {ty e : SrcType} (h : elementOf ty = some e) : ty = .slice e := by
  cases ty <;> simp_all [elementOf]

theorem stride_inv {P : Core.Program} {k : Nat} {st : State} {slice : Nat}
    {element : Core.Ty} {address length : Nat} {v : Value} {st1 : State}
    (base : evalExpr (k + 1) P st (.local slice) = .done (.rawSlice element address length) st)
    (run : evalExpr (k + 2) P st (.intrinsic .sliceStride (.local slice)) = .done v st1) :
    st1 = st ∧ ∃ stride, Semantics.rawSliceStride? P (.rawSlice element address length) = some stride ∧
      v = .signed .isize stride := by
  simp only [evalExpr] at run base
  rw [base] at run
  simp only at run
  split at run
  · rename_i stride found
    simp only [Semantics.Outcome.done.injEq] at run
    obtain ⟨rfl, rfl⟩ := run
    exact ⟨rfl, stride, found, rfl⟩
  · simp at run

/-- `slice_stride(slice)` of a slice local: Core's stride of the view, as
`isize` bits in `slot`. -/
theorem eval_stride {k slice : Nat} (ok : evalStride sp.decls scope slice slot = some ev)
    (corr : Corr scope frame st env) (fresh : st.Fresh) (hc : HeapCorr st.heap hp)
    (run : evalExpr (k + 2) sp.toCore st (.intrinsic .sliceStride (.local slice)) = .done v st') :
    Evaluates mp hp slot st env ev v st' := by
  simp only [evalStride] at ok
  split at ok
  · simp at ok
  rename_i b found
  split at ok
  · simp at ok
  rename_i element elementOk
  have bty := eq_of_elementOf elementOk
  obtain ⟨w, localRun, holdsW⟩ := corr.local found k sp.toCore
  rw [bty] at holdsW
  cases holdsW with
  | @slice _ len _ _ lenSlot _ =>
  obtain ⟨rfl, stride, strideOk, rfl⟩ := stride_inv localRun run
  suffices code : ∃ e, ev = { stmt := .assign slot e, ty := .isize } ∧
      SrcType.isize.Holds (.signed .isize stride) (e.eval env) by
    obtain ⟨e, rfl, holds⟩ := code
    exact ⟨fresh, Keeps.refl _ _, rfl, by simp [SrcType.size], 0, _, hp, .assign,
      fun j below => set_below below, holdsAt_set holds env slot, hc⟩
  simp only [evalStrideOf] at ok
  split at ok
  · rename_i isI32
    have := eq_of_isI32 isI32
    subst this
    simp only [Option.some.injEq] at ok
    subst ok
    simp [Semantics.rawSliceStride?, NativeLayout.elementStride?, SrcType.toCore] at strideOk
    subst strideOk
    exact ⟨_, rfl, by simp only [SrcType.Holds, Expr.eval]; rfl⟩
  simp only [evalWordStride] at ok
  split at ok
  case isFalse => simp at ok
  rename_i hel
  simp only [Option.some.injEq] at ok
  subst ok
  have wok := wordElement_wordType hel
  have agg : (∃ id, element.toCore = .structure id) ∨ ∃ id, element.toCore = .enumeration id := by
    cases element <;> simp_all [wordElement, SrcType.toCore]
  have agg2 := agg
  rcases agg2 with ⟨id, e⟩ | ⟨id, e⟩ <;>
    (simp only [Semantics.rawSliceStride?, NativeLayout.elementStride?, e] at strideOk; rw [← e] at strideOk)
  all_goals
    cases hwords : NativeLayout.valueWords? sp.toCore element.toCore with
    | none => simp [hwords] at strideOk
    | some words =>
    simp only [hwords, Option.some.injEq] at strideOk
    subst strideOk
    rw [NativeLayout.valueWords?, show NativeLayout.maxDepth = 63 + 1 from rfl] at hwords
    have small := words_le_max agg hwords
    have wEq := wordType_words element wok hwords
    subst wEq
    refine ⟨_, rfl, ?_⟩
    simp only [SrcType.Holds, Expr.eval, Word.apply, BinOp.apply]
    rw [stride_word_bits (by simpa [NativeLayout.maxWords] using small)]
    rfl

/-- `slice[index]` of a raw slice of `i32`: the index in `slot`, then the
element loaded over it. -/
theorem eval_index {k : Nat} (ihe : EvalSound sp mp (k + 1)) {slice : Nat} {index : SrcEff}
    (ok : evalIndex sp.decls scope slice slot (index.eval (sigs sp.funcs) sp.decls scope slot) = some ev)
    (corr : Corr scope frame st env) (fr : Layout scope frame base slot) (fresh : st.Fresh)
    (hc : HeapCorr st.heap hp)
    (run : evalExpr (k + 2) sp.toCore st (.index (.local slice) index.toCore) = .done v st')
    (bound : st'.heap.nextAddress ≤ hp.limit) :
    Evaluates mp hp slot st env ev v st' := by
  simp only [evalIndex] at ok
  split at ok
  · simp at ok
  rename_i b found
  split at ok
  · simp at ok
  rename_i element elementOk
  have bty := eq_of_elementOf elementOk
  simp only [evalElement] at ok
  split at ok
  case isFalse =>
    split at ok
    · simp at ok
    rename_i i indexOk
    obtain ⟨w, localRun, holdsW⟩ := corr.local found k sp.toCore
    rw [bty] at holdsW
    cases holdsW with
    | @slice _ len _ _ lenSlot _ =>
    obtain ⟨iv, pos, indexRun, posOk, read⟩ := eval_index_raw localRun run
    obtain ⟨fresh1, keeps1, locals1, -, d1, env1, hp1, exec1, same1, holds1, hc1⟩ :=
      ihe indexOk corr fr fresh hc indexRun bound
    have bslotLt : b.slot < slot := by
      have := fr.slots b (lookup_mem found).1
      have := fr.sized b (lookup_mem found).1
      omega
    have bslot : env1 b.slot = env b.slot := same1 b.slot bslotLt
    rw [← bslot] at read
    have tail : st'.heap.nextAddress ≤ hp1.limit := by rw [exec1.limit_normal]; exact bound
    simp only [evalWordElement] at ok
    split at ok
    case isFalse => simp at ok
    rename_i cond
    simp only [Bool.and_eq_true] at cond
    obtain ⟨hel, kind⟩ := cond
    simp only [Option.some.injEq] at ok
    subst ok
    have scalar : i.ty.isScalar = true := by
      cases hty : i.ty <;> simp_all [SrcType.isI32, SrcType.isUint, SrcType.isScalar]
    have posEq := index_toNat (t := { expr := .var slot, ty := i.ty }) kind (holds_var holds1 scalar) posOk
    have below : (elementBase b.slot element.size (.var slot)).Below (slot + 1) :=
      ⟨(by simp only [Expr.Below]; omega), (by simp only [Expr.Below]; omega), trivial⟩
    obtain ⟨env2, agree2, holds, load⟩ := loadElement_sound (mp := mp) hc1 tail hel posEq below read
    obtain ⟨copied, agree⟩ := copy_down holds
    have slot2 : b.slot + 1 < slot := by
      have := fr.slots b (lookup_mem found).1
      rw [bty] at this
      simp only [SrcType.size] at this
      omega
    have inBounds := readRawSliceIndex_lt read
    have pass : (boundsGuard b (.var slot)).eval env1 = 1 :=
      boundsGuard_one (by rw [same1 _ slot2, lenSlot]; omega)
    refine ⟨fresh1, keeps1, locals1, wordElement_size hel, d1, _, hp1,
      .seq exec1 ((load (assignFrom_exec _ slot .skip)).checkThen pass), fun j lt => ?_, copied, hc1⟩
    rw [agree j lt, agree2 j (.inl (by omega)), same1 j lt]
  rename_i isI32
  have eltEq := eq_of_isI32 isI32
  subst eltEq
  split at ok
  · simp at ok
  rename_i i indexOk
  simp only [evalLoad] at ok
  split at ok
  case isFalse => simp at ok
  rename_i kind
  simp only [Option.some.injEq] at ok
  subst ok
  obtain ⟨w, localRun, holdsW⟩ := corr.local found k sp.toCore
  rw [bty] at holdsW
  cases holdsW with
  | @slice _ len _ _ lenSlot _ =>
  obtain ⟨iv, pos, indexRun, posOk, read⟩ := eval_index_raw localRun run
  obtain ⟨fresh1, keeps1, locals1, -, d1, env1, hp1, exec1, same1, holds1, hc1⟩ :=
    ihe indexOk corr fr fresh hc indexRun bound
  have scalar : i.ty.isScalar = true := by
    cases hty : i.ty <;> simp_all [SrcType.isI32, SrcType.isUint, SrcType.isScalar]
  have holdsI := holds_var holds1 scalar
  have posEq := index_toNat (t := { expr := .var slot, ty := i.ty }) kind holdsI posOk
  have bslot : env1 b.slot = env b.slot := same1 b.slot (by have := fr.slots b (lookup_mem found).1; have := fr.sized b (lookup_mem found).1; omega)
  have slot2 : b.slot + 1 < slot := by
    have := fr.slots b (lookup_mem found).1
    rw [bty] at this
    simp only [SrcType.size] at this
    omega
  have inBounds := readRawSliceIndex_lt read
  have pass : (boundsGuard b (.var slot)).eval env1 = 1 :=
    boundsGuard_one (by rw [same1 _ slot2, lenSlot]; simp only [Expr.eval] at posEq ⊢; omega)
  simp only [Semantics.readRawSliceIndex] at read
  split at read
  · simp at read
  simp only [Semantics.rawSliceElementAddress?, SrcType.toCore] at read
  obtain ⟨elt, eltOk, read⟩ := except_bind_ok read
  simp only [pure, Except.pure, Except.ok.injEq] at eltOk
  subst eltOk
  simp only [NativeLayout.maxDepth, Semantics.readNativeValue] at read
  obtain ⟨bits, loaded, wrapped⟩ := except_bind_ok read
  simp only [pure, Except.pure, Except.ok.injEq] at wrapped
  subst wrapped
  obtain ⟨rfl, inside⟩ := hc1.loadNatLE loaded
  have inside := inside (by decide)
  have small := hc1.small
  have limit := exec1.limit_normal
  have address : ((Expr.binary Word.u64 BinOp.add (Expr.var b.slot)
      (Expr.binary Word.u64 BinOp.mul (Expr.var slot) (Expr.lit 4))).eval env1).toNat =
      (env b.slot).toNat + pos * 4 := by
    have four : (4 : BitVec 64).toNat = 4 := rfl
    simp only [Expr.eval, Word.apply, BinOp.apply, BitVec.toNat_add, BitVec.toNat_mul, four, bslot]
    simp only [Expr.eval] at posEq
    rw [posEq]
    rw [Nat.mod_eq_of_lt (a := pos * 4) (by addr_omega), Nat.mod_eq_of_lt (by addr_omega)]
  have room : ((Expr.binary Word.u64 BinOp.add (Expr.var b.slot)
      (Expr.binary Word.u64 BinOp.mul (Expr.var slot) (Expr.lit 4))).eval env1).toNat + MemWidth.m32.bytes ≤
      hp1.limit := by
    rw [address]; simp only [MemWidth.bytes]; addr_omega
  have lt32 := hp1.readLE_lt ((env b.slot).toNat + pos * 4) 4
  refine ⟨fresh1, keeps1, locals1, by simp [SrcType.size], d1, _, hp1, .seq exec1 ((Exec.loadWord room).checkThen pass),
    fun j lt => by rw [set_below lt, same1 j lt], .i32 ?_, hc1⟩
  simp only [Env.set, if_pos, address, MemWidth.bytes]
  exact i32_load_holds (by simpa using lt32)

/-- A struct literal: its fields, one after another from `slot`. -/
theorem eval_struct {k : Nat} (ihe : ∀ m < k, EvalSound sp mp m) {ty : SrcType} {fields : List SrcEff}
    (ok : evalStruct ty (evalArgs (sigs sp.funcs) sp.decls scope fields slot) = some ev)
    (corr : Corr scope frame st env) (fr : Layout scope frame base slot) (fresh : st.Fresh)
    (hc : HeapCorr st.heap hp)
    (run : evalExpr (k + 1) sp.toCore st (.structValue ty.typeId (SrcEff.toCoreList fields)) = .done v st')
    (bound : st'.heap.nextAddress ≤ hp.limit) :
    Evaluates mp hp slot st env ev v st' := by
  simp only [evalStruct] at ok
  split at ok
  · simp at ok
  rename_i ea argsOk
  cases ty with
  | struct sid types =>
    simp only [evalStructOf] at ok
    split at ok
    · rename_i checks
      simp only [Bool.and_eq_true, decide_eq_true_eq] at checks
      simp only [Option.some.injEq] at ok
      subst ok
      simp only [SrcType.typeId, evalExpr] at run
      split at run
      · rename_i vs st2 argsRun
        simp only [Semantics.Outcome.done.injEq] at run
        obtain ⟨rfl, rfl⟩ := run
        obtain ⟨fresh', keeps, locals, d, env', hp', exec, same, holds, hc'⟩ :=
          evalArgs_sound fields ihe argsOk corr fr fresh hc argsRun bound
        rw [typesSame_eq _ checks.1] at holds
        exact ⟨fresh', keeps, locals, by simp only [SrcType.size]; exact checks.2, d, env', hp', exec, same,
          .struct holds, hc'⟩
      all_goals simp at run
    · simp at ok
  | i32 => simp at ok
  | bool => simp at ok
  | uint => simp at ok
  | enum => simp at ok
  | ptr => simp at ok
  | slice => simp at ok
  | unit => simp at ok
  | isize => simp at ok

/-- An enum literal: its payload from `slot + 1`, then its tag in `slot`. -/
theorem eval_variant {k : Nat} (ihe : ∀ m < k, EvalSound sp mp m) {ty : SrcType} {variant : Nat}
    {payload : List SrcEff}
    (ok : evalVariant ty variant slot (evalArgs (sigs sp.funcs) sp.decls scope payload (slot + 1)) = some ev)
    (corr : Corr scope frame st env) (fr : Layout scope frame base slot) (fresh : st.Fresh)
    (hc : HeapCorr st.heap hp)
    (run : evalExpr (k + 1) sp.toCore st (.enumValue ty.typeId variant (SrcEff.toCoreList payload)) = .done v st')
    (bound : st'.heap.nextAddress ≤ hp.limit) :
    Evaluates mp hp slot st env ev v st' := by
  simp only [evalVariant] at ok
  split at ok
  · simp at ok
  rename_i ea argsOk
  cases ty with
  | enum eid variants =>
    simp only [evalTagged] at ok
    split at ok
    · split at ok
      · simp at ok
      rename_i fs found
      simp only [evalPayload] at ok
      split at ok
      · rename_i same
        simp only [Option.some.injEq] at ok
        subst ok
        simp only [SrcType.typeId, evalExpr] at run
        split at run
        · rename_i vs st2 argsRun
          simp only [Semantics.Outcome.done.injEq] at run
          obtain ⟨rfl, rfl⟩ := run
          obtain ⟨fresh', keeps, locals, d, env', hp', exec, same', holds, hc'⟩ :=
            evalArgs_sound payload ihe argsOk corr (fr.mono (Nat.le_succ _)) fresh hc argsRun bound
          rw [typesSame_eq _ same] at holds
          refine ⟨fresh', keeps, locals, by simp only [SrcType.size]; omega, d, _, hp', .seq exec .assign,
            fun j lt => by rw [set_below lt, same' j (by omega)], .enum found (by simp [Env.set, Expr.eval])
              (holds.congr fun i _ => by simp only [Env.set]; rw [if_neg (by omega)]), hc'⟩
        all_goals simp at run
      · simp at ok
    · simp at ok
  | i32 => simp at ok
  | bool => simp at ok
  | uint => simp at ok
  | struct => simp at ok
  | ptr => simp at ok
  | slice => simp at ok
  | unit => simp at ok
  | isize => simp at ok

/-- Binding an arm's payload above the scope keeps the layout. -/
theorem armScope_layout :
    ∀ (binders : List Nat) {types : List SrcType} {vs : List Value} {slot : Nat}
      {scope s' : List Binding} {frame : Nat → Nat} {st : State} {env : Env},
      armScope binders types slot scope = some s' → FieldsHold types vs env slot →
      Layout scope frame 0 slot → Corr scope frame st env → st.Fresh →
      ∃ frame', Corr s' frame' (st.bindLocals (binders.zip vs)) env ∧
        Layout s' frame' 0 (slot + sizes types) ∧ (st.bindLocals (binders.zip vs)).Fresh ∧
        Keeps st.nextCell st (st.bindLocals (binders.zip vs)) ∧ binders.length = vs.length
  | [], types, vs, slot, scope, s', frame, st, env, ok, holds, fr, corr, fresh => by
    cases types with
    | cons => simp [armScope] at ok
    | nil =>
      simp only [armScope, Option.some.injEq] at ok
      subst ok
      cases holds
      exact ⟨frame, corr, by simpa [sizes] using fr, fresh, Keeps.refl _ _, rfl⟩
  | binder :: rest, types, vs, slot, scope, s', frame, st, env, ok, holds, fr, corr, fresh => by
    cases types with
    | nil => simp [armScope] at ok
    | cons f more =>
      simp only [armScope] at ok
      split at ok
      · rename_i sized
        cases holds with
        | cons head tail =>
        rename_i v vs'
        rw [List.zip_cons_cons, bindLocals_cons]
        have pushed := corr.alias fresh (j := slot) (fun b mem => by
          have := fr.slots b mem
          have := fr.sized b mem
          omega) binder head
        have pushedL := fr.push (corr.below fresh) (Nat.zero_le _) binder sized
        obtain ⟨frame', corr', fr', fresh', keeps', len⟩ :=
          armScope_layout rest ok tail pushedL pushed (bindLocal_fresh fresh binder v)
        refine ⟨frame', corr', ?_, fresh', (bindLocal_keeps (Nat.le_refl _) binder v).trans
          (keeps'.lower (Nat.le_succ _)), by simp [len]⟩
        simpa [sizes, Nat.add_assoc] using fr'
      · simp at ok

/-- The tag tests pick the arm Core picks, and it evaluates that arm's value
from `dst`, above the payload. -/
theorem evalArms_sound {dst eid : Nat} {ty : SrcType} :
    ∀ (values : List SrcEff) {variants : List (List SrcType)} {binders : List (List Nat)} {j kv : Nat}
      {stmt : Stmt} {fs : List SrcType} {vs : List Value} {v : Value} {st' : State} {k : Nat}
      {hp : Heap} {frame : Nat → Nat} {st : State} {env : Env},
      (∀ m < k, EvalSound sp mp m) → Corr scope frame st env → Layout scope frame 0 slot → st.Fresh →
      HeapCorr st.heap hp →
      evalArms (sigs sp.funcs) sp.decls scope slot dst ty j variants binders values = some stmt →
      values.length = variants.length → binders.length = variants.length →
      (∀ fs ∈ variants, slot + 1 + sizes fs ≤ dst) → j ≤ kv → variants[kv - j]? = some fs → kv < 2 ^ 64 →
      env slot = BitVec.ofNat 64 kv → FieldsHold fs vs env (slot + 1) →
      Semantics.evalMatchArms k sp.toCore st (.enumeration eid kv vs) (SrcEff.coreArms eid j binders values) =
        .done v st' → st'.heap.nextAddress ≤ hp.limit →
      st'.Fresh ∧ Keeps st.nextCell st st' ∧ st'.locals = st.locals ∧
        ∃ d env' hp', Exec mp d env hp stmt (.normal env' hp') ∧ (∀ i < dst, env' i = env i) ∧
          ty.HoldsAt v env' dst ∧ HeapCorr st'.heap hp' := by
  intro values
  induction values with
  | nil =>
    intro variants binders j kv stmt fs vs v st' k hp frame st env ihe corr fr fresh hc ok
    simp [evalArms] at ok
  | cons value rest ih =>
    intro variants binders j kv stmt fs vs v st' k hp frame st env ihe corr fr fresh hc ok vlen blen room le
      found small tag payload run bound
    cases variants with
    | nil => simp [evalArms] at ok
    | cons types more =>
    cases binders with
    | nil => simp [evalArms] at ok
    | cons bs others =>
    cases k with
    | zero => simp [Semantics.evalMatchArms] at run
    | succ k =>
    simp only [evalArms] at ok
    simp only [SrcEff.coreArms, Semantics.evalMatchArms, Semantics.matchPattern] at run
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
      simp only [beq_self_eq_true, Bool.and_self, ↓reduceIte, matchBinds _ _ blen'] at run
      cases armRun : evalExpr k sp.toCore (st.bindLocals (bs.zip vs)) value.toCore with
      | done w st2 =>
        simp only [armRun, Semantics.restoreOutcomeLocals, Semantics.Outcome.done.injEq] at run
        obtain ⟨rfl, rfl⟩ := run
        have hc' : HeapCorr (st.bindLocals (bs.zip vs)).heap hp := by
          rw [(bindLocals_same _ st).1]
          exact hc
        obtain ⟨fresh2, keeps2, locals2, _, d, env2, hp2, exec, same2, holds2, hc2⟩ :=
          ihe k (Nat.lt_succ_self k) valueOk corr' (fr'.mono (room _ (List.mem_cons_self ..))) fresh' hc'
            armRun bound
        rw [SrcType.same_eq same] at holds2
        refine ⟨restore_fresh fresh2, (keeps'.chain keeps2).trans (restore_keeps _ _ _), rfl, d, env2, hp2,
          ?_, same2, holds2, hc2⟩
        cases rest with
        | nil =>
          simp only [Option.some.injEq] at ok
          subst ok
          exact exec
        | cons next more' =>
          cases ho : evalArms (sigs sp.funcs) sp.decls scope slot dst ty (j + 1) more others (next :: more') with
          | none => simp [ho] at ok
          | some o =>
            simp only [ho, Option.some.injEq] at ok
            subst ok
            exact .ifTrue (by simp [Expr.eval, Word.holds, CmpOp.holdsU, tag]) exec
      | trapped => simp [armRun, Semantics.restoreOutcomeLocals] at run
      | exited => simp [armRun, Semantics.restoreOutcomeLocals] at run
      | outOfFuel => simp [armRun, Semantics.restoreOutcomeLocals] at run
    · have hne : (j == kv) = false := by simpa using hj
      simp only [beq_self_eq_true, Bool.true_and, hne, Bool.false_eq_true, ↓reduceIte] at run
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
          obtain ⟨fresh', keeps', locals', d, env', hp', exec', same', holds', hc'⟩ :=
            ih (fun m lt => ihe m (by omega)) corr fr fresh hc ho (by simpa using vlen) (by simpa using blen)
              (fun fs mem => room fs (List.mem_cons_of_mem _ mem)) (by omega) found' small tag payload run bound
          have differ : BitVec.ofNat 64 kv ≠ BitVec.ofNat 64 j := ofNat_ne small (by omega) (Ne.symm hj)
          exact ⟨fresh', keeps', locals', d, env', hp', .ifFalse (by simp [Expr.eval, Word.holds, CmpOp.holdsU,
            tag, differ]) exec', same', holds', hc'⟩

/-- A `match`: the scrutinee in `slot`, the arm its tag picks from
`matchDst`, then that value copied down to `slot`. -/
theorem eval_match {k : Nat} (ihe : ∀ m ≤ k, EvalSound sp mp m) {scrutinee : SrcEff} {ety ty : SrcType}
    {binders : List (List Nat)} {values : List SrcEff}
    (ok : evalMatch slot ety ty (scrutinee.eval (sigs sp.funcs) sp.decls scope slot)
      (evalArms (sigs sp.funcs) sp.decls scope slot (matchDst slot ety ty) ty 0 (matchVariants ety) binders values)
      binders.length values.length = some ev)
    (corr : Corr scope frame st env) (fr : Layout scope frame base slot) (fresh : st.Fresh)
    (hc : HeapCorr st.heap hp)
    (run : evalExpr (k + 1) sp.toCore st (SrcEff.eMatch scrutinee ety ty binders values).toCore = .done v st')
    (bound : st'.heap.nextAddress ≤ hp.limit) :
    Evaluates mp hp slot st env ev v st' := by
  simp only [evalMatch] at ok
  split at ok
  · simp at ok
  rename_i s scrutOk
  split at ok
  · simp at ok
  rename_i a armsOk
  simp only [evalMatchOf] at ok
  split at ok
  · rename_i cond
    simp only [Bool.and_eq_true, decide_eq_true_eq] at cond
    obtain ⟨⟨⟨⟨same, sized⟩, blen⟩, vlen⟩, small⟩ := cond
    simp only [Option.some.injEq] at ok
    subst ok
    simp only [SrcEff.toCore, evalExpr] at run
    split at run
    · rename_i w st1 scrutRun
      have views1 := (eff_grown scrutRun fresh.2).1
      have grown := effArms_grows binders values ety.typeId 0 (eff_grows k (grows sp k)) run
      obtain ⟨fresh1, keeps1, locals1, _, d1, env1, hp1, exec1, same1, holds1, hc1⟩ :=
        ihe k (Nat.le_refl _) scrutOk corr fr fresh hc scrutRun (Nat.le_trans (grown views1).2 bound)
      rw [SrcType.same_eq same] at holds1
      have fr0 : Layout scope frame 0 slot := ⟨fr.slots, fr.sized, fun _ _ => Nat.zero_le _, fr.inj, fr.apart⟩
      cases ety with
      | enum eid variants =>
        cases holds1 with
        | enum found tag payload =>
          rename_i kv fs vs
          simp only [SrcType.typeId] at run
          simp only [matchVariants] at blen vlen small armsOk
          have kvLt := (List.getElem?_eq_some_iff.mp found).1
          have hdst : slot + ty.size ≤ matchDst slot (.enum eid variants) ty := by
            have := Nat.le_max_right (SrcType.enum eid variants).size ty.size
            simp only [matchDst]
            omega
          obtain ⟨fresh2, keeps2, locals2, d2, env2, hp2, exec2, same2, holds2, hc2⟩ :=
            evalArms_sound values (fun m lt => ihe m (Nat.le_of_lt lt)) (corr.after fr fresh keeps1 locals1 same1)
              fr0 fresh1 hc1 armsOk vlen blen (fun fs mem => by
                have := sizes_le_maxSize_of_mem mem
                have := Nat.le_max_left (SrcType.enum eid variants).size ty.size
                simp only [matchDst, SrcType.size] at this ⊢
                omega) (Nat.zero_le _) (by simpa using found) (by omega) tag payload run
              (by rw [exec1.limit_normal]; exact bound)
          refine ⟨fresh2, keeps1.chain keeps2, locals2.trans locals1, sized, max d1 d2,
            env2.setFrom slot (slotVars (matchDst slot (.enum eid variants) ty) ty.size), hp2,
            .seq (exec1.mono (Nat.le_max_left _ _)) (.seq (exec2.mono (Nat.le_max_right _ _))
              (assignFrom_exec _ slot .skip)), fun j lt => ?_, ?_, hc2⟩
          · rw [setFrom_outside _ slot env2 j (.inl lt), same2 j (by omega), same1 j lt]
          · exact holds2.congr fun i below => setFrom_slotVars env2 (.inr hdst) below
      | i32 => cases values <;> simp [matchVariants, evalArms] at armsOk
      | bool => cases values <;> simp [matchVariants, evalArms] at armsOk
      | uint => cases values <;> simp [matchVariants, evalArms] at armsOk
      | struct => cases values <;> simp [matchVariants, evalArms] at armsOk
      | ptr => cases values <;> simp [matchVariants, evalArms] at armsOk
      | slice => cases values <;> simp [matchVariants, evalArms] at armsOk
      | unit => cases values <;> simp [matchVariants, evalArms] at armsOk
      | isize => cases values <;> simp [matchVariants, evalArms] at armsOk
    all_goals simp at run
  · simp at ok

/-- An operator applied in place to its operand's slot. -/
theorem eval_then {k : Nat} (ihe : EvalSound sp mp k) {operand : SrcEff} {o : Evaluated}
    (operandOk : operand.eval (sigs sp.funcs) sp.decls scope slot = some o) {t : Typed}
    (ok : evalThen slot o (some t) = some ev) {w : Value}
    (corr : Corr scope frame st env) (fr : Layout scope frame base slot) (fresh : st.Fresh)
    (hc : HeapCorr st.heap hp) (operandRun : evalExpr k sp.toCore st operand.toCore = .done w st')
    (bound : st'.heap.nextAddress ≤ hp.limit) (scalar : o.ty.isScalar = true)
    (applied : ∀ {env : Env}, o.ty.Holds w ((Expr.var slot).eval env) → t.ty.Holds v (t.expr.eval env)) :
    Evaluates mp hp slot st env ev v st' := by
  simp only [evalThen, Option.some.injEq] at ok
  subst ok
  obtain ⟨fresh1, keeps1, locals1, _, d1, env1, hp1, exec1, same1, holds1, hc1⟩ :=
    ihe operandOk corr fr fresh hc operandRun bound
  have holds := applied (holds_var holds1 scalar)
  exact ⟨fresh1, keeps1, locals1, by rw [SrcType.size_scalar holds.scalar]; decide, d1, _, hp1, .seq exec1 .assign,
    fun j below => by rw [set_below below, same1 j below], holdsAt_set holds env1 slot, hc1⟩

end Cases

end Lanius.Mini

namespace Lanius.Mini

open Lanius.Core (Value)
open Lanius.Semantics (State Cell Completion evalExpr evalExprs execStmt restoreLocals)

theorem negate_scalar {inner t : Typed} (lowered : lowerNegateTyped inner = some t) : inner.ty.isScalar = true := by
  simp only [lowerNegateTyped] at lowered
  split at lowered
  · rename_i isInt
    cases hty : inner.ty <;> simp_all [SrcType.isI32, SrcType.isScalar]
  split at lowered
  · rename_i isIsize
    cases hty : inner.ty <;> simp_all [SrcType.isIsize, SrcType.isScalar]
  · simp at lowered

theorem not_scalar {inner t : Typed} (lowered : lowerNotTyped inner = some t) : inner.ty.isScalar = true := by
  simp only [lowerNotTyped] at lowered
  split at lowered
  · rename_i isBool
    cases hty : inner.ty <;> simp_all [SrcType.isBool, SrcType.isScalar]
  · simp at lowered

/-! ## Statements with effectful expressions -/

section Statements

variable {sp : SrcProgram} {mp : Program} {fuel : Nat} {ret : SrcType} {scope : List Binding}
  {next : Nat} {stmt : Stmt} {frame : Nat → Nat} {base : Nat} {st : State} {env : Env}
  {c : Completion} {st' : State} {hp : Heap}

theorem stmt_letEval (ih : StmtSound sp mp fuel) (ihe : EvalSound sp mp fuel) {id : Nat} {ty : SrcType}
    {value : SrcEff} {body : SrcStmt}
    (ok : (SrcStmt.letEval id ty value body).lower (sigs sp.funcs) sp.decls ret scope next = some stmt)
    (corr : Corr scope frame st env) (fr : Layout scope frame base next) (fresh : st.Fresh)
    (le : base ≤ st.nextCell)
    (hc : HeapCorr st.heap hp) (run : execStmt (fuel + 1) sp.toCore st (SrcStmt.letEval id ty value body).toCore =
      .done c st') (bound : st'.heap.nextAddress ≤ hp.limit) :
    Simulates mp hp ret scope frame base st env stmt c st' := by
  simp only [SrcStmt.lower, lowerLetEval] at ok
  split at ok
  · simp at ok
  rename_i ev valueOk
  split at ok
  · simp at ok
  rename_i bstmt bodyOk
  simp only [evalSame] at ok
  split at ok
  · rename_i same
    have tyEq := SrcType.same_eq same
    simp only [Option.some.injEq] at ok
    subst ok
    simp only [SrcStmt.toCore, execStmt] at run
    split at run
    · rename_i v st1 valueRun
      have views1 := (eff_grown valueRun fresh.2).1
      obtain ⟨fresh1, keeps1, locals1, sized, d1, env1, hp1, exec1, same1, holds1, hc1⟩ :=
        ihe valueOk corr fr fresh hc valueRun (tail_bound views1 run bound)
      rw [tyEq] at sized holds1
      obtain ⟨fresh', keeps', d2, out, exec, matched⟩ :=
        let_tail ih bodyOk (corr.keeps fresh keeps1 locals1) fr fresh1 (Nat.le_trans le keeps1.next) sized
          (fr.agree same1) holds1 hc1 run (by rw [exec1.limit_normal]; exact bound)
      exact ⟨fresh', (keeps1.lower le).trans keeps', max d1 d2, out,
        .seq (exec1.mono (Nat.le_max_left _ _)) (exec.mono (Nat.le_max_right _ _)), matched⟩
    all_goals simp at run
  · simp at ok

theorem stmt_setEval (ihe : ∀ m ≤ fuel, EvalSound sp mp m) {id : Nat} {value : SrcEff}
    (ok : (SrcStmt.setEval id value).lower (sigs sp.funcs) sp.decls ret scope next = some stmt)
    (corr : Corr scope frame st env) (fr : Layout scope frame base next) (fresh : st.Fresh)
    (le : base ≤ st.nextCell)
    (hc : HeapCorr st.heap hp) (run : execStmt (fuel + 1) sp.toCore st (SrcStmt.setEval id value).toCore = .done c st')
    (bound : st'.heap.nextAddress ≤ hp.limit) :
    Simulates mp hp ret scope frame base st env stmt c st' := by
  simp only [SrcStmt.lower, lowerSetEval] at ok
  split at ok
  · simp at ok
  rename_i b found
  split at ok
  · simp at ok
  rename_i ev valueOk
  simp only [evalSame] at ok
  split at ok
  · rename_i same
    have tyEq := SrcType.same_eq same
    simp only [Option.some.injEq] at ok
    subst ok
    have bmem := (lookup_mem found).1
    simp only [SrcStmt.toCore, execStmt] at run
    split at run
    · rename_i u st3 assignRun
      simp only [Semantics.Outcome.done.injEq] at run
      obtain ⟨rfl, rfl⟩ := run
      cases fuel with
      | zero => simp [evalExpr] at assignRun
      | succ k =>
        obtain ⟨rv, st2, valueRun, rfl⟩ := assign_step corr found assignRun fun valueRun =>
          (eff_grown valueRun fresh.2).1
        obtain ⟨fresh2, keeps2, locals2, -, d, env1, hp1, exec1, same1, holds1, hc1⟩ :=
          ihe k (Nat.le_succ _) valueOk corr fr fresh hc valueRun bound
        rw [tyEq] at holds1
        refine ⟨assigned_fresh fresh2 _ _, (keeps2.lower le).trans (assigned_keeps (fr.above b bmem) _ _), d, _,
          .seq exec1 (assignFrom_exec _ b.slot .skip),
          .next ((corr.after fr fresh keeps2 locals2 same1).assign fr bmem (fun j away => ?_) ?_) hc1⟩
        · exact setFrom_outside _ b.slot env1 j (by rw [slotVars_length]; exact away)
        · exact holds1.congr fun i below => setFrom_slotVars env1 (.inr (fr.slots b bmem)) below
    all_goals simp at run
  · simp at ok

/-- A write to a cell place changes only the cells. -/
theorem writeResolvedPlace_cells {state s : State} {place : Semantics.ResolvedPlace} {value : Value}
    (h : Semantics.writeResolvedPlace state place value = .ok s) : ∃ cells, s = { state with cells } := by
  unfold Semantics.writeResolvedPlace at h
  split at h
  · split at h
    · rename_i assigned hassigned
      simp only [Semantics.State.assignCell] at hassigned
      split at hassigned
      · simp only [Option.some.injEq, Except.ok.injEq] at hassigned h
        exact ⟨_, by rw [← h, ← hassigned]⟩
      · simp at hassigned
    · simp at h
  · split at h
    · simp at h
    · simp at h
    · split at h
      · simp at h
      · split at h
        · rename_i assigned hassigned
          simp only [Semantics.State.assignCell] at hassigned
          split at hassigned
          · simp only [Option.some.injEq, Except.ok.injEq] at hassigned h
            exact ⟨_, by rw [← h, ← hassigned]⟩
          · simp at hassigned
        · simp at h

/-- Core's `x.field = value` with a value that may change the state: the
place first, then the value, then the write into the cell as it is then. -/
theorem field_assign_eff {P : Core.Program} {scope frame st env} (corr : Corr scope frame st env)
    {id : Nat} {b : Binding} (found : lookup scope id = some b) {sid : Nat} {vs : List Value}
    (entry : st.cellEntry? (frame b.slot) = some ⟨frame b.slot, some (.structure sid vs)⟩)
    {index : Nat} {old : Value} (got : vs[index]? = some old)
    {e : Core.Expr} {k : Nat} {u : Value} {st' : State}
    (run : evalExpr (k + 1) P st (.assign .set (.field (.local id) index) e) = .done u st')
    (views : ∀ {rv st2}, evalExpr k P st e = .done rv st2 → st2.i32ArrayViews = []) :
    ∃ rv st2, evalExpr k P st e = .done rv st2 ∧ st'.heap = st2.heap ∧
      (st2.cellEntry? (frame b.slot) = some ⟨frame b.slot, some (.structure sid vs)⟩ →
        st' = { st2 with
          cells := Semantics.replaceCell st2.cells (frame b.slot) (.structure sid (Semantics.setValue vs index rv)) }) := by
  cases k with
  | zero => simp [evalExpr, Semantics.evalPlace] at run
  | succ j =>
    cases j with
    | zero => simp [evalExpr, Semantics.evalPlace] at run
    | succ m =>
      have place : Semantics.evalPlace (m + 2) P st .address (.field (.local id) index) =
          .done { root := frame b.slot, projections := [.field index], value := some old } st := by
        simp [Semantics.evalPlace, corr.cellId, found, entry, got]
      simp only [evalExpr, place] at run
      split at run
      · rename_i rv st2 valueRun
        have views2 := views valueRun
        refine ⟨rv, st2, valueRun, ?_, fun entry2 => ?_⟩
        · simp only [Semantics.evalAssignValue, Semantics.assignOpBinary?,
            Semantics.writeResolvedPlaceNative] at run
          split at run
          · rename_i assigned written
            obtain ⟨cells, rfl⟩ := writeResolvedPlace_cells written
            rw [sync_ok (st := { st2 with cells }) views2, ite_self] at run
            simp only [Semantics.Outcome.done.injEq] at run
            rw [← run.2]
          · simp at run
        · have synced := sync_ok
            (st := { st2 with cells := Semantics.replaceCell st2.cells (frame b.slot) (.structure sid (Semantics.setValue vs index rv)) })
            views2
          simp only [Semantics.evalAssignValue, Semantics.assignOpBinary?,
            Semantics.writeResolvedPlaceNative, Semantics.writeResolvedPlace, entry2,
            Semantics.replaceProjectedValue, got, assignCell_some entry2, synced, ite_self,
            Semantics.Outcome.done.injEq] at run
          exact run.2.symm
      all_goals simp at run

/-- `x.field = value` for a scalar field: the value in `next`, then copied
to the field's slot. -/
theorem stmt_setFieldEval (ihe : ∀ m ≤ fuel, EvalSound sp mp m) {id index : Nat} {value : SrcEff}
    (ok : (SrcStmt.setFieldEval id index value).lower (sigs sp.funcs) sp.decls ret scope next = some stmt)
    (corr : Corr scope frame st env) (fr : Layout scope frame base next) (fresh : st.Fresh)
    (le : base ≤ st.nextCell) (hc : HeapCorr st.heap hp)
    (run : execStmt (fuel + 1) sp.toCore st (SrcStmt.setFieldEval id index value).toCore = .done c st')
    (bound : st'.heap.nextAddress ≤ hp.limit) :
    Simulates mp hp ret scope frame base st env stmt c st' := by
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
  rename_i sid types hty
  simp only [setFieldEvalAt] at ok
  split at ok
  · simp at ok
  rename_i f fieldFound
  split at ok
  case isFalse => simp at ok
  rename_i scalar
  simp only [evalSame] at ok
  split at ok
  case isFalse => simp at ok
  rename_i same
  have tyEq := SrcType.same_eq same
  simp only [Option.some.injEq] at ok
  subst ok
  have bmem := (lookup_mem found).1
  obtain ⟨v0, entry, holds0⟩ := corr.values b bmem
  rw [hty] at holds0
  cases holds0 with
  | @struct _ _ vs _ _ fieldsHold =>
  obtain ⟨old, got, _⟩ := fieldsHold.get fieldFound
  simp only [SrcStmt.toCore, execStmt] at run
  split at run
  · rename_i u st3 assignRun
    simp only [Semantics.Outcome.done.injEq] at run
    obtain ⟨rfl, rfl⟩ := run
    cases fuel with
    | zero => simp [evalExpr] at assignRun
    | succ k =>
      obtain ⟨rv, st2, valueRun, heapEq, write⟩ := field_assign_eff corr found entry got assignRun
        fun valueRun => (eff_grown valueRun fresh.2).1
      obtain ⟨fresh2, keeps2, locals2, -, d, env1, hp1, exec1, same1, holds1, hc1⟩ :=
        ihe k (Nat.le_succ _) valueOk corr fr fresh hc valueRun (by rw [← heapEq]; exact bound)
      have entry2 : st2.cellEntry? (frame b.slot) = some ⟨frame b.slot, some (.structure sid vs)⟩ := by
        rw [keeps2.cells _ (corr.below fresh b bmem)]; exact entry
      rw [write entry2]
      rw [tyEq] at holds1
      have holdsV := holds_var holds1 scalar
      have sizeB := fr.sized b bmem
      have slotB := fr.slots b bmem
      rw [hty] at sizeB slotB
      have holdsS : (SrcType.struct sid types).HoldsAt (.structure sid vs) env1 b.slot :=
        (SrcType.HoldsAt.struct fieldsHold).congr fun i lt => same1 _ (by omega)
      cases holdsS with
      | @struct _ _ _ _ _ fieldsHold1 =>
      have inRange := fieldOffset_lt fieldFound
      refine ⟨assigned_fresh fresh2 _ _, (keeps2.lower le).trans (assigned_keeps (fr.above b bmem) _ _), d, _,
        .seq exec1 .assign,
        .next ((corr.after fr fresh keeps2 locals2 same1).assign fr bmem (fun j away => ?_) ?_) hc1⟩
      · simp only [Env.set]
        rw [hty] at away
        simp only [SrcType.size] at away
        have one := SrcType.size_scalar scalar
        rw [if_neg (by omega)]
      · rw [hty]
        exact .struct (fieldsHold1.set fieldFound scalar holdsV)
  all_goals simp at run

/-- Core's `slice[idx] = value` on a raw slice local, with operands that may
change the state: the index first, then the value, then the write. -/
theorem eval_setIndex_eff {P : Core.Program} {k : Nat} {st : State} {slice : Nat} {idx e : Core.Expr}
    {element : Core.Ty} {address length : Nat} {root : Nat} {u : Value} {st' : State}
    (views : st.i32ArrayViews = [])
    (idxGrows : ∀ {v s}, evalExpr (k + 1) P st idx = .done v s → Grows st s)
    (eGrows : ∀ {s1 v s2}, evalExpr (k + 2) P s1 e = .done v s2 → Grows s1 s2)
    (base : Semantics.evalPlace (k + 1) P st .read (.local slice) =
      .done { root, projections := [], value := some (.rawSlice element address length) } st)
    (run : evalExpr (k + 3) P st (.assign .set (.index (.local slice) idx) e) = .done u st') :
    ∃ iv st1 pos at_ right st2 heap, evalExpr (k + 1) P st idx = .done iv st1 ∧
      Semantics.integerIndex iv = .ok pos ∧ pos < length ∧
      Semantics.rawSliceElementAddress? P element address pos = .ok at_ ∧
      evalExpr (k + 2) P st1 e = .done right st2 ∧
      Semantics.writeNativeValue NativeLayout.maxDepth P st2 st2.heap element at_ right = .ok heap ∧
      st' = { st2 with heap } := by
  rw [evalExpr] at run
  rw [Semantics.evalPlace] at run
  rw [base] at run
  simp only at run
  split at run
  · rename_i resolved st1 placeRun
    split at placeRun
    · rename_i iv afterIndex indexRun
      have views1 := (idxGrows indexRun views).1
      split at placeRun
      · simp at placeRun
      rename_i pos posOk
      split at placeRun
      case isFalse => simp at placeRun
      rename_i inside
      split at placeRun
      · simp at placeRun
      rename_i at_ located
      simp only [Semantics.Outcome.done.injEq] at placeRun
      obtain ⟨rfl, rfl⟩ := placeRun
      split at run
      · rename_i right st2 valueRun
        have views2 := (eGrows valueRun views1).1
        simp only [Semantics.evalAssignValue, Semantics.assignOpBinary?,
          Semantics.writeResolvedPlaceNative] at run
        split at run
        · rename_i assigned written
          obtain ⟨heap, stored, wrapped⟩ := except_bind_ok written
          simp only [pure, Except.pure, Except.ok.injEq] at wrapped
          subst wrapped
          simp only [Semantics.syncI32ViewsFromHeap, views2, Semantics.syncI32ViewsFromHeapFrom, ite_self,
            Semantics.Outcome.done.injEq] at run
          obtain ⟨-, rfl⟩ := run
          exact ⟨iv, afterIndex, pos, at_, right, st2, heap, indexRun, posOk, inside, located, valueRun, stored,
            by rw [views2]⟩
        · simp at run
      all_goals simp at run
    all_goals simp at placeRun
  all_goals simp at run

/-- `slice[index] = value` on a raw `i32` slice: the index in `next`, the
value in `next + 1`, then the 32-bit store. -/
theorem stmt_setIndexEval (ihe : ∀ m ≤ fuel, EvalSound sp mp m) {slice : Nat} {index value : SrcEff}
    (ok : (SrcStmt.setIndexEval slice index value).lower (sigs sp.funcs) sp.decls ret scope next = some stmt)
    (corr : Corr scope frame st env) (fr : Layout scope frame base next) (fresh : st.Fresh)
    (le : base ≤ st.nextCell) (hc : HeapCorr st.heap hp)
    (run : execStmt (fuel + 1) sp.toCore st (SrcStmt.setIndexEval slice index value).toCore = .done c st')
    (bound : st'.heap.nextAddress ≤ hp.limit) :
    Simulates mp hp ret scope frame base st env stmt c st' := by
  simp only [SrcStmt.lower, lowerSetIndexEval] at ok
  split at ok
  · simp at ok
  rename_i b found
  split at ok
  · simp at ok
  rename_i element elementOk
  have bty := eq_of_elementOf elementOk
  simp only [storeEvalElement] at ok
  split at ok
  case isFalse =>
    split at ok
    · simp at ok
    rename_i i indexOk
    split at ok
    · simp at ok
    rename_i w valueOk
    have cond := storeEvalWord_cond ok
    simp only [Bool.and_eq_true] at cond
    obtain ⟨kind, wSame⟩ := cond
    have wty := SrcType.same_eq wSame
    have bmem := (lookup_mem found).1
    simp only [SrcStmt.toCore, execStmt] at run
    split at run
    · rename_i u st3 assignRun
      simp only [Semantics.Outcome.done.injEq] at run
      obtain ⟨rfl, rfl⟩ := run
      cases fuel with
      | zero => simp [evalExpr] at assignRun
      | succ k =>
      cases k with
      | zero => simp [evalExpr, Semantics.evalPlace] at assignRun
      | succ k =>
      cases k with
      | zero =>
        simp only [evalExpr, Semantics.evalPlace] at assignRun
        repeat' split at assignRun
        all_goals simp_all [evalExpr]
      | succ k =>
      obtain ⟨wv, place, holdsW⟩ := corr.readPlace found k sp.toCore
      rw [bty] at holdsW
      cases holdsW with
      | @slice _ len _ _ lenSlot _ =>
      obtain ⟨iv, st1, pos, at_, right, st2, heap, indexRun, posOk, inside, located, valueRun, stored, rfl⟩ :=
        eval_setIndex_eff fresh.2 (fun r => eff_grown r) (fun r => eff_grown r) place assignRun
      have bound2 : st2.heap.nextAddress ≤ hp.limit := by
        rw [← writeNativeValue_next _ stored]
        exact bound
      have views1 := (eff_grown indexRun fresh.2).1
      obtain ⟨fresh1, keeps1, locals1, -, d1, env1, hp1, exec1, same1, holds1, hc1⟩ :=
        ihe (k + 1) (by omega) indexOk corr fr fresh hc indexRun
          (Nat.le_trans ((eff_grown valueRun views1).2) bound2)
      have limit1 := exec1.limit_normal
      obtain ⟨fresh2, keeps2, locals2, -, d2, env2, hp2, exec2, same2, holds2, hc2⟩ :=
        ihe (k + 2) (by omega) valueOk (corr.after fr fresh keeps1 locals1 same1) (fr.mono (Nat.le_succ _))
          fresh1 hc1 valueRun (by rw [limit1]; exact bound2)
      have limit2 := exec2.limit_normal
      have scalar : i.ty.isScalar = true := by
        simp only [Bool.or_eq_true] at kind
        rcases kind with c | c
        · rw [eq_of_isI32 c]; rfl
        · rw [eq_of_isUint c]; rfl
      have holdsI := holds_var (holds1.congr (env' := env2) (slot' := next) fun _ below =>
        same2 _ (by have := SrcType.size_scalar scalar; omega)) scalar
      have posEq := index_toNat (t := { expr := .var next, ty := i.ty }) kind holdsI posOk
      rw [wty] at holds2
      have bslot : env2 b.slot = env b.slot := by
        have := fr.slots b bmem
        have := fr.sized b bmem
        rw [same2 b.slot (by omega), same1 b.slot (by omega)]
      rw [← bslot] at located
      have flat : FlatValue element right env2 (slotVars (next + 1) element.size) :=
        ⟨slotVars_length _ _, holds2.congr fun j lt => by
          rw [Nat.zero_add]; exact entry_slotVars env2 (next + 1) _ lt⟩
      have bound3 : heap.nextAddress ≤ hp2.limit := by rw [limit2, limit1]; exact bound
      have finish : ∀ {s hp'}, Exec mp 0 env2 hp2 s (.normal env2 hp') → HeapCorr heap hp' →
          Simulates mp hp ret scope frame base st env (i.stmt.seq (w.stmt.seq s)) .next { st2 with heap } :=
        fun exec hc' =>
        ⟨fresh2, ((keeps1.chain keeps2).lower le).trans ⟨fun _ _ => rfl, Nat.le_refl _⟩, max d1 d2, _,
          .seq (exec1.mono (Nat.le_max_left _ _)) (.seq (exec2.mono (Nat.le_max_right _ _)) (exec.mono (Nat.zero_le _))),
          .next (((corr.after fr fresh (keeps1.chain keeps2) (locals2.trans locals1)
            (fun j lt => (same2 j (by omega)).trans (same1 j lt)))).cells_congr rfl fun _ _ => rfl) hc'⟩
      simp only [storeEvalWord] at ok
      split at ok
      case isFalse => simp at ok
      rename_i hel
      simp only [storeEvalThen] at ok
      split at ok
      case isFalse => simp at ok
      split at ok
      · simp at ok
      rename_i s sOk
      simp only [Option.some.injEq] at ok
      subst ok
      replace sOk := guarded_some sOk
      obtain ⟨s, sOk, rfl⟩ := sOk
      have slot2 : b.slot + 1 < next := by
        have := fr.slots b bmem
        rw [bty] at this
        simp only [SrcType.size] at this
        omega
      have pass : (boundsGuard b (.var next)).eval env2 = 1 :=
        boundsGuard_one (by
          rw [same2 _ (by omega), same1 _ slot2, lenSlot]
          simp only [Expr.eval] at posEq ⊢
          omega)
      obtain ⟨hp', exec, hc'⟩ := storeElement_sound (mp := mp) hc2 hel posEq located stored flat sOk bound3
      exact finish (exec.checkThen pass) hc'
    all_goals simp at run
  rename_i isI32
  have eltEq := eq_of_isI32 isI32
  subst eltEq
  split at ok
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
  obtain ⟨kind, wI32⟩ := cond
  simp only [Option.some.injEq] at ok
  subst ok
  have bmem := (lookup_mem found).1
  simp only [SrcStmt.toCore, execStmt] at run
  split at run
  · rename_i u st3 assignRun
    simp only [Semantics.Outcome.done.injEq] at run
    obtain ⟨rfl, rfl⟩ := run
    cases fuel with
    | zero => simp [evalExpr] at assignRun
    | succ k =>
    cases k with
    | zero => simp [evalExpr, Semantics.evalPlace] at assignRun
    | succ k =>
    cases k with
    | zero =>
      simp only [evalExpr, Semantics.evalPlace] at assignRun
      repeat' split at assignRun
      all_goals simp_all [evalExpr]
    | succ k =>
    obtain ⟨wv, place, holdsW⟩ := corr.readPlace found k sp.toCore
    rw [bty] at holdsW
    cases holdsW with
    | @slice _ len _ _ lenSlot _ =>
    obtain ⟨iv, st1, pos, at_, right, st2, heap, indexRun, posOk, inside, located, valueRun, stored, rfl⟩ :=
      eval_setIndex_eff fresh.2 (fun r => eff_grown r) (fun r => eff_grown r) place assignRun
    have bound2 : st2.heap.nextAddress ≤ hp.limit := by
      rw [← writeNativeValue_next _ stored]
      exact bound
    simp only [Semantics.rawSliceElementAddress?, SrcType.toCore, Except.ok.injEq] at located
    subst located
    have views1 := (eff_grown indexRun fresh.2).1
    obtain ⟨fresh1, keeps1, locals1, -, d1, env1, hp1, exec1, same1, holds1, hc1⟩ :=
      ihe (k + 1) (by omega) indexOk corr fr fresh hc indexRun
        (Nat.le_trans ((eff_grown valueRun views1).2) bound2)
    have limit1 := exec1.limit_normal
    obtain ⟨fresh2, keeps2, locals2, -, d2, env2, hp2, exec2, same2, holds2, hc2⟩ :=
      ihe (k + 2) (by omega) valueOk (corr.after fr fresh keeps1 locals1 same1) (fr.mono (Nat.le_succ _))
        fresh1 hc1 valueRun (by rw [limit1]; exact bound2)
    have limit2 := exec2.limit_normal
    have scalar : i.ty.isScalar = true := by
      simp only [Bool.or_eq_true] at kind
      rcases kind with c | c
      · rw [eq_of_isI32 c]; rfl
      · rw [eq_of_isUint c]; rfl
    have holdsI := holds_var (holds1.congr (env' := env2) (slot' := next) fun _ below =>
      same2 _ (by have := SrcType.size_scalar scalar; omega)) scalar
    have posEq := index_toNat (t := { expr := .var next, ty := i.ty }) kind holdsI posOk
    rw [eq_of_isI32 wI32] at holds2
    cases holds2 with
    | i32 holdsV =>
    obtain ⟨rfl, bitsV⟩ := holdsV
    simp only [NativeLayout.maxDepth, Semantics.writeNativeValue, SrcType.toCore] at stored
    have sameNext := storeBytes_next stored
    have bslot : env2 b.slot = env b.slot := by
      have := fr.slots b bmem
      have := fr.sized b bmem
      rw [same2 b.slot (by omega), same1 b.slot (by omega)]
    have slot2 : b.slot + 1 < next := by
      have := fr.slots b bmem
      rw [bty] at this
      simp only [SrcType.size] at this
      omega
    have pass : (boundsGuard b (.var next)).eval env2 = 1 :=
      boundsGuard_one (by
        rw [same2 _ (by omega), same1 _ slot2, lenSlot]
        simp only [Expr.eval] at posEq ⊢
        omega)
    obtain ⟨hc', inside⟩ := HeapCorr.storeBytesFrom _ 0 hc2 stored
    have inside := inside (by simp [Semantics.i32Bytes])
    have small := hc2.small
    simp only [Semantics.i32Bytes, List.length_map, List.length_range, Nat.add_zero] at inside hc'
    have address : ((Expr.binary Word.u64 BinOp.add (Expr.var b.slot)
        (Expr.binary Word.u64 BinOp.mul (Expr.var next) (Expr.lit 4))).eval env2).toNat =
        (env b.slot).toNat + pos * 4 := by
      have four : (4 : BitVec 64).toNat = 4 := rfl
      simp only [Expr.eval, Word.apply, BinOp.apply, BitVec.toNat_add, BitVec.toNat_mul, four, bslot]
      simp only [Expr.eval] at posEq
      rw [posEq]
      rw [Nat.mod_eq_of_lt (a := pos * 4) (by addr_omega), Nat.mod_eq_of_lt (by addr_omega)]
    have room : ((Expr.binary Word.u64 BinOp.add (Expr.var b.slot)
        (Expr.binary Word.u64 BinOp.mul (Expr.var next) (Expr.lit 4))).eval env2).toNat + MemWidth.m32.bytes ≤
        hp2.limit := by
      rw [address]; simp only [MemWidth.bytes]; addr_omega
    refine ⟨fresh2, ((keeps1.chain keeps2).lower le).trans ⟨fun _ _ => rfl, Nat.le_refl _⟩, max d1 d2, _,
      .seq (exec1.mono (Nat.le_max_left _ _)) (.seq (exec2.mono (Nat.le_max_right _ _))
        ((Exec.storeWord room).checkThen pass)),
      .next (((corr.after fr fresh (keeps1.chain keeps2) (locals2.trans locals1)
        (fun j lt => (same2 j (by omega)).trans (same1 j lt)))).cells_congr rfl fun _ _ => rfl) ?_⟩
    rw [address]
    simp only [MemWidth.bytes, Expr.eval]
    rw [writeLE_eq_writeBytes, i32_store_bytes bitsV]
    simpa [Semantics.i32Bytes] using hc'
  all_goals simp at run

theorem stmt_ifEval (ih : StmtSound sp mp fuel) (ihe : EvalSound sp mp fuel) {condition : SrcEff}
    {thenBranch elseBranch : SrcStmt}
    (ok : (SrcStmt.ifEval condition thenBranch elseBranch).lower (sigs sp.funcs) sp.decls ret scope next = some stmt)
    (corr : Corr scope frame st env) (fr : Layout scope frame base next) (fresh : st.Fresh)
    (le : base ≤ st.nextCell)
    (hc : HeapCorr st.heap hp)
    (run : execStmt (fuel + 1) sp.toCore st (SrcStmt.ifEval condition thenBranch elseBranch).toCore = .done c st')
    (bound : st'.heap.nextAddress ≤ hp.limit) :
    Simulates mp hp ret scope frame base st env stmt c st' := by
  simp only [SrcStmt.lower, lowerIfEval] at ok
  split at ok
  · simp at ok
  rename_i ev condOk
  split at ok
  · simp at ok
  rename_i ts thenOk
  split at ok
  · simp at ok
  rename_i es elseOk
  simp only [evalSame] at ok
  split at ok
  · rename_i same
    have tyEq := SrcType.same_eq same
    simp only [Option.some.injEq] at ok
    subst ok
    simp only [SrcStmt.toCore, execStmt] at run
    split at run
    · rename_i mid condRun
      obtain ⟨fresh1, keeps1, locals1, -, d1, env1, hp1, exec1, same1, holds1, hc1⟩ :=
        ihe condOk corr fr fresh hc condRun (stmt_bound (eff_grown condRun fresh.2).1 run bound)
      rw [tyEq] at holds1
      obtain ⟨_, eq, bits⟩ := bool_bits ((SrcType.holdsAt_scalar rfl).mp holds1)
      cases eq
      obtain ⟨fresh', keeps, d, out, exec, matched⟩ :=
        ih thenOk (corr.after fr fresh keeps1 locals1 same1) fr fresh1 (Nat.le_trans le keeps1.next) hc1 run
          (by rw [exec1.limit_normal]; exact bound)
      exact ⟨fresh', (keeps1.lower le).trans keeps, max d1 d, out,
        .seq (exec1.mono (Nat.le_max_left _ _))
          (.ifTrue (by simp [Expr.eval, bits, boolBits]) (exec.mono (Nat.le_max_right _ _))), matched⟩
    · rename_i mid condRun
      obtain ⟨fresh1, keeps1, locals1, -, d1, env1, hp1, exec1, same1, holds1, hc1⟩ :=
        ihe condOk corr fr fresh hc condRun (stmt_bound (eff_grown condRun fresh.2).1 run bound)
      rw [tyEq] at holds1
      obtain ⟨_, eq, bits⟩ := bool_bits ((SrcType.holdsAt_scalar rfl).mp holds1)
      cases eq
      obtain ⟨fresh', keeps, d, out, exec, matched⟩ :=
        ih elseOk (corr.after fr fresh keeps1 locals1 same1) fr fresh1 (Nat.le_trans le keeps1.next) hc1 run
          (by rw [exec1.limit_normal]; exact bound)
      exact ⟨fresh', (keeps1.lower le).trans keeps, max d1 d, out,
        .seq (exec1.mono (Nat.le_max_left _ _))
          (.ifFalse (by simp [Expr.eval, bits, boolBits]) (exec.mono (Nat.le_max_right _ _))), matched⟩
    · simp at run
    all_goals simp at run
  · simp at ok

/-- The loop's code computes the condition again after the body; Core's
remaining iterations are the same statement with less fuel. -/
theorem stmt_whileEval (ih : StmtSound sp mp fuel) (ihe : EvalSound sp mp fuel) {condition : SrcEff}
    {body : SrcStmt}
    (ok : (SrcStmt.whileEval condition body).lower (sigs sp.funcs) sp.decls ret scope next = some stmt)
    (corr : Corr scope frame st env) (fr : Layout scope frame base next) (fresh : st.Fresh)
    (le : base ≤ st.nextCell)
    (hc : HeapCorr st.heap hp)
    (run : execStmt (fuel + 1) sp.toCore st (SrcStmt.whileEval condition body).toCore = .done c st')
    (bound : st'.heap.nextAddress ≤ hp.limit) :
    Simulates mp hp ret scope frame base st env stmt c st' := by
  have whileOk := ok
  simp only [SrcStmt.lower, lowerWhileEval] at ok
  split at ok
  · simp at ok
  rename_i ev condOk
  split at ok
  · simp at ok
  rename_i bstmt bodyOk
  simp only [evalSame] at ok
  split at ok
  · rename_i same
    have tyEq := SrcType.same_eq same
    simp only [Option.some.injEq] at ok
    subst ok
    simp only [SrcStmt.toCore, execStmt] at run
    split at run
    · rename_i mid condRun
      simp only [Semantics.Outcome.done.injEq] at run
      obtain ⟨rfl, rfl⟩ := run
      obtain ⟨fresh1, keeps1, locals1, -, d1, env1, hp1, exec1, same1, holds1, hc1⟩ :=
        ihe condOk corr fr fresh hc condRun bound
      rw [tyEq] at holds1
      obtain ⟨_, eq, bits⟩ := bool_bits ((SrcType.holdsAt_scalar rfl).mp holds1)
      cases eq
      exact ⟨fresh1, keeps1.lower le, d1, _, .seq exec1 (.loopDone (by simp [Expr.eval, bits, boolBits])),
        .next (corr.after fr fresh keeps1 locals1 same1) hc1⟩
    · rename_i mid condRun
      have views1 := (eff_grown condRun fresh.2).1
      split at run
      · rename_i completed bodyRun
        obtain ⟨fresh1, keeps1, locals1, -, d1, env1, hp1, exec1, same1, holds1, hc1⟩ :=
          ihe condOk corr fr fresh hc condRun
            (stmt_bound views1 bodyRun (stmt_bound (execStmt_grows bodyRun views1).1
              (s := .whileEval condition body) run bound))
        rw [tyEq] at holds1
        obtain ⟨_, eq, bits⟩ := bool_bits ((SrcType.holdsAt_scalar rfl).mp holds1)
        cases eq
        have condTrue : (Expr.var next).eval env1 ≠ 0 := by simp [Expr.eval, bits, boolBits]
        obtain ⟨fresh2, keeps2, d2, out2, exec2, matched2⟩ :=
          ih bodyOk (corr.after fr fresh keeps1 locals1 same1) fr fresh1 (Nat.le_trans le keeps1.next) hc1 bodyRun
            (stmt_bound (execStmt_grows bodyRun views1).1 (s := .whileEval condition body) run
              (by rw [exec1.limit_normal]; exact bound))
        cases matched2 with
        | next corr2 hc2 =>
          obtain ⟨fresh3, keeps3, d3, out3, exec3, matched3⟩ :=
            ih whileOk corr2 fr fresh2 (Nat.le_trans (Nat.le_trans le keeps1.next) keeps2.next) hc2 run
              (by rw [exec2.limit_normal, exec1.limit_normal]; exact bound)
          have exec1' := exec1.mono (Nat.le_max_left d1 (max d2 d3))
          have exec2' := exec2.mono (Nat.le_trans (Nat.le_max_left d2 d3) (Nat.le_max_right d1 _))
          have exec3' := exec3.mono (Nat.le_trans (Nat.le_max_right d2 d3) (Nat.le_max_right d1 _))
          refine ⟨fresh3, ((keeps1.lower le).trans keeps2).trans keeps3, max d1 (max d2 d3), out3, ?_, matched3⟩
          cases exec3' with
          | seq execC execLoop => exact .seq exec1' (.loopNext condTrue (.seq exec2' execC) execLoop)
          | seqReturned execC => exact .seq exec1' (.loopReturned condTrue (.seq exec2' execC))
      · rename_i completed bodyRun
        obtain ⟨fresh1, keeps1, locals1, -, d1, env1, hp1, exec1, same1, holds1, hc1⟩ :=
          ihe condOk corr fr fresh hc condRun
            (stmt_bound views1 bodyRun (stmt_bound (execStmt_grows bodyRun views1).1
              (s := .whileEval condition body) run bound))
        obtain ⟨_, _, _, _, _, matched2⟩ :=
          ih bodyOk (corr.after fr fresh keeps1 locals1 same1) fr fresh1 (Nat.le_trans le keeps1.next) hc1 bodyRun
            (stmt_bound (execStmt_grows bodyRun views1).1 (s := .whileEval condition body) run
              (by rw [exec1.limit_normal]; exact bound))
        cases matched2
      · rename_i completed bodyRun
        simp only [Semantics.Outcome.done.injEq] at run
        obtain ⟨-, rfl⟩ := run
        obtain ⟨fresh1, keeps1, locals1, -, d1, env1, hp1, exec1, same1, holds1, hc1⟩ :=
          ihe condOk corr fr fresh hc condRun (stmt_bound views1 bodyRun bound)
        obtain ⟨_, _, _, _, _, matched2⟩ :=
          ih bodyOk (corr.after fr fresh keeps1 locals1 same1) fr fresh1 (Nat.le_trans le keeps1.next) hc1 bodyRun
            (by rw [exec1.limit_normal]; exact bound)
        cases matched2
      · rename_i value completed bodyRun
        simp only [Semantics.Outcome.done.injEq] at run
        obtain ⟨rfl, rfl⟩ := run
        obtain ⟨fresh1, keeps1, locals1, -, d1, env1, hp1, exec1, same1, holds1, hc1⟩ :=
          ihe condOk corr fr fresh hc condRun (stmt_bound views1 bodyRun bound)
        rw [tyEq] at holds1
        obtain ⟨_, eq, bits⟩ := bool_bits ((SrcType.holdsAt_scalar rfl).mp holds1)
        cases eq
        have condTrue : (Expr.var next).eval env1 ≠ 0 := by simp [Expr.eval, bits, boolBits]
        obtain ⟨fresh2, keeps2, d2, out2, exec2, matched2⟩ :=
          ih bodyOk (corr.after fr fresh keeps1 locals1 same1) fr fresh1 (Nat.le_trans le keeps1.next) hc1 bodyRun
            (by rw [exec1.limit_normal]; exact bound)
        cases matched2 with
        | returned holds len hc2 =>
          exact ⟨fresh2, (keeps1.lower le).trans keeps2, max d1 d2, _,
            .seq (exec1.mono (Nat.le_max_left _ _)) (.loopReturned condTrue (.seqReturned (exec2.mono (Nat.le_max_right _ _)))),
            .returned holds len hc2⟩
      all_goals simp at run
    · simp at run
    all_goals simp at run
  · simp at ok

theorem stmt_returnEval (ihe : EvalSound sp mp fuel) {value : SrcEff}
    (ok : (SrcStmt.returnEval value).lower (sigs sp.funcs) sp.decls ret scope next = some stmt)
    (corr : Corr scope frame st env) (fr : Layout scope frame base next) (fresh : st.Fresh)
    (le : base ≤ st.nextCell)
    (hc : HeapCorr st.heap hp) (run : execStmt (fuel + 1) sp.toCore st (SrcStmt.returnEval value).toCore = .done c st')
    (bound : st'.heap.nextAddress ≤ hp.limit) :
    Simulates mp hp ret scope frame base st env stmt c st' := by
  simp only [SrcStmt.lower, lowerReturnEval] at ok
  split at ok
  · simp at ok
  rename_i ev valueOk
  simp only [evalSame] at ok
  split at ok
  · rename_i same
    have tyEq := SrcType.same_eq same
    simp only [Option.some.injEq] at ok
    subst ok
    simp only [SrcStmt.toCore, execStmt] at run
    split at run
    · rename_i v mid valueRun
      simp only [Semantics.Outcome.done.injEq] at run
      obtain ⟨rfl, rfl⟩ := run
      obtain ⟨fresh1, keeps1, -, -, d1, env1, hp1, exec1, -, holds1, hc1⟩ :=
        ihe valueOk corr fr fresh hc valueRun bound
      rw [tyEq] at holds1
      exact ⟨fresh1, keeps1.lower le, d1, _, .seq exec1 .ret,
        .returned (holds1.congr fun i below => by rw [Nat.zero_add, entry_slotVars env1 next _ below])
          (by rw [evalAll_length, slotVars_length]) hc1⟩
    all_goals simp at run
  · simp at ok

theorem stmt_discard (ihe : EvalSound sp mp fuel) {value : SrcEff}
    (ok : (SrcStmt.discard value).lower (sigs sp.funcs) sp.decls ret scope next = some stmt)
    (corr : Corr scope frame st env) (fr : Layout scope frame base next) (fresh : st.Fresh)
    (le : base ≤ st.nextCell)
    (hc : HeapCorr st.heap hp) (run : execStmt (fuel + 1) sp.toCore st (SrcStmt.discard value).toCore = .done c st')
    (bound : st'.heap.nextAddress ≤ hp.limit) :
    Simulates mp hp ret scope frame base st env stmt c st' := by
  simp only [SrcStmt.lower, lowerDiscard] at ok
  split at ok
  · simp at ok
  rename_i ev valueOk
  simp only [Option.some.injEq] at ok
  subst ok
  simp only [SrcStmt.toCore, execStmt] at run
  split at run
  · rename_i u st1 valueRun
    simp only [Semantics.Outcome.done.injEq] at run
    obtain ⟨rfl, rfl⟩ := run
    obtain ⟨fresh1, keeps1, locals1, -, d1, env1, hp1, exec1, same1, -, hc1⟩ :=
      ihe valueOk corr fr fresh hc valueRun bound
    exact ⟨fresh1, keeps1.lower le, d1, _, exec1, .next (corr.after fr fresh keeps1 locals1 same1) hc1⟩
  all_goals simp at run

/-- `assert(condition)`: the condition's code, then `1 / condition` into the
condition's slot. Core continues only when the condition is true, and then
the division has a run. -/
theorem stmt_assert (ihe : ∀ m ≤ fuel, EvalSound sp mp m) {condition : SrcEff}
    (ok : (SrcStmt.assert condition).lower (sigs sp.funcs) sp.decls ret scope next = some stmt)
    (corr : Corr scope frame st env) (fr : Layout scope frame base next) (fresh : st.Fresh)
    (le : base ≤ st.nextCell)
    (hc : HeapCorr st.heap hp) (run : execStmt (fuel + 1) sp.toCore st (SrcStmt.assert condition).toCore = .done c st')
    (bound : st'.heap.nextAddress ≤ hp.limit) :
    Simulates mp hp ret scope frame base st env stmt c st' := by
  simp only [SrcStmt.lower, lowerAssert] at ok
  split at ok
  · simp at ok
  rename_i ev condOk
  simp only [evalSame] at ok
  split at ok
  case isFalse => simp at ok
  rename_i same
  simp only [Option.some.injEq] at ok
  subst ok
  simp only [SrcStmt.toCore, execStmt] at run
  split at run
  · rename_i u st1 assertRun
    simp only [Semantics.Outcome.done.injEq] at run
    obtain ⟨rfl, rfl⟩ := run
    cases fuel with
    | zero => simp [evalExpr] at assertRun
    | succ k =>
      simp only [evalExpr] at assertRun
      split at assertRun
      · rename_i w mid condRun
        have done : mid = st1 ∧ w = .boolean true := by
          split at assertRun
          all_goals (try simp only [Semantics.Outcome.done.injEq, reduceCtorEq] at assertRun)
          all_goals simp_all
        obtain ⟨rfl, rfl⟩ := done
        obtain ⟨fresh1, keeps1, locals1, -, d1, env1, hp1, exec1, same1, holds1, hc1⟩ :=
          ihe k (Nat.le_succ _) condOk corr fr fresh hc condRun bound
        rw [SrcType.same_eq same] at holds1
        have one : env1 next = 1 := by
          obtain ⟨b, hb, bits⟩ := holds_var holds1 rfl
          simp only [Value.boolean.injEq] at hb
          subst hb
          simpa [Expr.eval, boolBits] using bits
        have defined : Word.u64.divides DivOp.uDiv ((Expr.lit 1).eval env1) ((Expr.var next).eval env1) = true := by
          simp [Expr.eval, one, Word.divides, DivOp.defined]
        have below : ∀ j < next, (env1.set next (Word.u64.divide DivOp.uDiv ((Expr.lit 1).eval env1)
            ((Expr.var next).eval env1))) j = env j := fun j lt => by
          rw [set_below lt, same1 j lt]
        exact ⟨fresh1, keeps1.lower le, d1, _, .seq exec1 (.divide defined),
          .next (corr.after fr fresh keeps1 locals1 below) hc1⟩
      all_goals simp at assertRun
  all_goals simp at run

/-- `return;` in a unit function: one slot, whose bits do not matter. -/
theorem stmt_returnUnit
    (ok : SrcStmt.returnUnit.lower (sigs sp.funcs) sp.decls ret scope next = some stmt)
    (fresh : st.Fresh) (hc : HeapCorr st.heap hp)
    (run : execStmt (fuel + 1) sp.toCore st SrcStmt.returnUnit.toCore = .done c st') :
    Simulates mp hp ret scope frame base st env stmt c st' := by
  simp only [SrcStmt.lower, lowerReturnUnit] at ok
  split at ok
  case isFalse => simp at ok
  rename_i isUnit
  simp only [Option.some.injEq] at ok
  subst ok
  simp only [SrcStmt.toCore, execStmt, Semantics.Outcome.done.injEq] at run
  obtain ⟨rfl, rfl⟩ := run
  have unit : ret = .unit := by cases ret <;> simp_all [SrcType.isUnit]
  exact ⟨fresh, Keeps.refl _ _, 0, _, .ret, .returned unit (by rw [unit]; rfl) hc⟩

end Statements

/-! ## The simulation -/

/-- Statements and effectful expressions together, by induction on Core's fuel. -/
theorem sound_both {sp : SrcProgram} {mp : Program}
    (lowered : lowerFuncs (sigs sp.funcs) sp.decls sp.funcs = some mp.funcs) :
    ∀ fuel, StmtSound sp mp fuel ∧ EvalSound sp mp fuel := by
  intro fuel
  induction fuel using Nat.strongRecOn with
  | _ fuel ih =>
    cases fuel with
    | zero =>
      refine ⟨fun _ _ _ _ _ _ run _ => by simp [execStmt] at run, ?_⟩
      intro hp e scope slot ev frame base st env v st' ok corr fr fresh hc run bound
      cases e <;> simp [evalExpr] at run
    | succ fuel =>
      have below : ∀ m ≤ fuel, StmtSound sp mp m := fun m h => (ih m (Nat.lt_succ_of_le h)).1
      have belowE : ∀ m ≤ fuel, EvalSound sp mp m := fun m h => (ih m (Nat.lt_succ_of_le h)).2
      have here : StmtSound sp mp fuel := below fuel (Nat.le_refl _)
      have hereE : EvalSound sp mp fuel := belowE fuel (Nat.le_refl _)
      refine ⟨?_, ?_⟩
      · intro hp s ret scope next stmt frame base st env c st' ok corr fr fresh le hc run bound
        cases s with
        | nop => exact stmt_nop ok corr fresh hc run bound
        | «let» => exact stmt_let here ok corr fr fresh le hc run bound
        | letStruct => exact stmt_letStruct here ok corr fr fresh le hc run bound
        | letCall => exact stmt_letCall lowered below ok corr fr fresh le hc run bound
        | letEnum => exact stmt_letEnum here ok corr fr fresh le hc run bound
        | letMatch => exact stmt_letMatch here ok corr fr fresh le hc run bound
        | set => exact stmt_set ok corr fr fresh hc run bound
        | setField => exact stmt_setField ok corr fr fresh hc run bound
        | setCall => exact stmt_setCall lowered below ok corr fr fresh le hc run bound
        | «then» => exact stmt_then here ok corr fr fresh le hc run bound
        | «if» => exact stmt_if here ok corr fr fresh le hc run bound
        | «while» => exact stmt_while here ok corr fr fresh le hc run bound
        | «return» => exact stmt_return ok corr fresh hc run bound
        | letAlloc => exact stmt_letAlloc here ok corr fr fresh le hc run bound
        | letLoad => exact stmt_letLoad here ok corr fr fresh le hc run bound
        | setByte => exact stmt_setByte ok corr fresh hc run bound
        | free => exact stmt_free ok corr fresh hc run
        | letSlice => exact stmt_letSlice here ok corr fr fresh le hc run bound
        | letIndex => exact stmt_letIndex here ok corr fr fresh le hc run bound
        | setIndex => exact stmt_setIndex ok corr fresh hc run bound
        | letEval => exact stmt_letEval here hereE ok corr fr fresh le hc run bound
        | setEval => exact stmt_setEval belowE ok corr fr fresh le hc run bound
        | ifEval => exact stmt_ifEval here hereE ok corr fr fresh le hc run bound
        | whileEval => exact stmt_whileEval here hereE ok corr fr fresh le hc run bound
        | returnEval => exact stmt_returnEval hereE ok corr fr fresh le hc run bound
        | discard => exact stmt_discard hereE ok corr fr fresh le hc run bound
        | assert => exact stmt_assert belowE ok corr fr fresh le hc run bound
        | returnUnit => exact stmt_returnUnit ok fresh hc run
        | setIndexEval => exact stmt_setIndexEval belowE ok corr fr fresh le hc run bound
        | setFieldEval => exact stmt_setFieldEval belowE ok corr fr fresh le hc run bound
      · intro hp e scope slot ev frame base st env v st' ok corr fr fresh hc run bound
        cases e with
        | ePure e => exact eval_pure ok corr fr fresh hc run
        | eCall callee args =>
          simp only [SrcEff.eval] at ok
          exact eval_call lowered here (fun m lt => belowE m (Nat.le_of_lt lt)) ok corr fr fresh hc run bound
        | eApply op l r =>
          simp only [SrcEff.eval] at ok
          exact eval_apply hereE ok corr fr fresh hc run bound
        | eNeg operand =>
          simp only [SrcEff.eval, evalNegate] at ok
          split at ok
          · simp at ok
          rename_i o operandOk
          obtain ⟨w, operandRun, evaluated⟩ := unary_inv run
          cases lowered' : lowerNegateTyped ({ expr := Expr.var slot, ty := o.ty } : Typed) with
          | none => simp [lowered', evalThen] at ok
          | some t =>
            rw [lowered'] at ok
            exact eval_then hereE operandOk ok corr fr fresh hc operandRun bound (negate_scalar lowered')
              fun holds => negate_holds lowered' holds evaluated
        | eNot operand =>
          simp only [SrcEff.eval, evalNot] at ok
          split at ok
          · simp at ok
          rename_i o operandOk
          obtain ⟨w, operandRun, evaluated⟩ := unary_inv run
          cases lowered' : lowerNotTyped ({ expr := Expr.var slot, ty := o.ty } : Typed) with
          | none => simp [lowered', evalThen] at ok
          | some t =>
            rw [lowered'] at ok
            exact eval_then hereE operandOk ok corr fr fresh hc operandRun bound (not_scalar lowered')
              fun holds => not_holds lowered' holds evaluated
        | eCast ty operand =>
          simp only [SrcEff.eval, evalCast] at ok
          split at ok
          · simp at ok
          rename_i o operandOk
          obtain ⟨w, operandRun, evaluated⟩ := cast_inv run
          cases lowered' : scalarCast ty ({ expr := Expr.var slot, ty := o.ty } : Typed) with
          | none => simp [lowered', evalThen] at ok
          | some t =>
            rw [lowered'] at ok
            simp only [scalarCast] at lowered'
            split at lowered'
            · rename_i scalar
              exact eval_then hereE operandOk ok corr fr fresh hc operandRun bound scalar
                fun holds => cast_sound holds lowered' evaluated
            · simp at lowered'
        | eIndex slice index =>
          simp only [SrcEff.eval] at ok
          cases fuel with
          | zero => simp [SrcEff.toCore, evalExpr] at run
          | succ k => exact eval_index hereE ok corr fr fresh hc run bound
        | eStruct ty fields =>
          simp only [SrcEff.eval] at ok
          exact eval_struct (fun m lt => belowE m (Nat.le_of_lt lt)) ok corr fr fresh hc run bound
        | eVariant ty variant payload =>
          simp only [SrcEff.eval] at ok
          exact eval_variant (fun m lt => belowE m (Nat.le_of_lt lt)) ok corr fr fresh hc run bound
        | eMatch scrutinee ety ty binders values =>
          simp only [SrcEff.eval] at ok
          exact eval_match belowE ok corr fr fresh hc run bound
        | eDivide op l r =>
          simp only [SrcEff.eval] at ok
          exact eval_divide hereE ok corr fr fresh hc run bound
        | eStride slice =>
          simp only [SrcEff.eval] at ok
          cases fuel with
          | zero => simp [SrcEff.toCore, evalExpr] at run
          | succ k => exact eval_stride ok corr fresh hc run

/-- The simulation, by induction on Core's fuel. -/
theorem stmt_sound {sp : SrcProgram} {mp : Program}
    (lowered : lowerFuncs (sigs sp.funcs) sp.decls sp.funcs = some mp.funcs) : ∀ fuel, StmtSound sp mp fuel :=
  fun fuel => (sound_both lowered fuel).1

end Lanius.Mini
