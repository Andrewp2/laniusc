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
    e.eval (sigs sp.funcs) scope slot = some ev →
    Corr scope frame st env → Layout scope frame base slot → st.Fresh →
    HeapCorr st.heap hp → evalExpr fuel sp.toCore st e.toCore = .done v st' →
    st'.heap.nextAddress ≤ hp.limit →
    Evaluates mp hp slot st env ev v st'

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
    simp only [evalScalar, Option.some.injEq] at ok
    subst ok
    obtain ⟨rfl, holds⟩ := e.lower_sound corr (SrcProgram.target_toCore sp) lowered run
    exact ⟨fresh, Keeps.refl _ _, rfl, by rw [SrcType.size_scalar holds.scalar]; decide, 0, _, hp, .assign,
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
    all_goals simp at ok

/-- Arguments evaluated one after another into consecutive slots. -/
theorem evalArgs_sound : ∀ (args : List SrcEff) {k : Nat}, (∀ m < k, EvalSound sp mp m) →
    ∀ {hp : Heap} {slot : Nat} {ea : EvaluatedArgs} {st : State} {env : Env} {vs : List Value} {st' : State},
    evalArgs (sigs sp.funcs) scope args slot = some ea → Corr scope frame st env →
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
    (ok : evalCall (sigs sp.funcs)[callee]? callee slot (evalArgs (sigs sp.funcs) scope args slot) = some ev)
    (corr : Corr scope frame st env) (fr : Layout scope frame base slot) (fresh : st.Fresh)
    (hc : HeapCorr st.heap hp)
    (run : evalExpr (k + 1) sp.toCore st (.call callee (SrcEff.toCoreList args)) = .done v st')
    (bound : st'.heap.nextAddress ≤ hp.limit) :
    Evaluates mp hp slot st env ev v st' := by
  obtain ⟨f, values, afterArgs, completed, argsRun, found, _, bodyRun, rfl⟩ := call_inv run
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
        (by rw [evalAll_length, slotVars_length, paramsSize_eq]) bodyRun (by rw [execA.limit_normal]; exact bound')
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
    (ok : evalApply op slot (l.eval (sigs sp.funcs) scope slot) (r.eval (sigs sp.funcs) scope (slot + 1)) = some ev)
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
      max d1 d2, _, hp2, .seq (exec1.mono (Nat.le_max_left _ _)) (.seq (exec2.mono (Nat.le_max_right _ _)) .assign),
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
    (ok : evalDivision op slot (l.eval (sigs sp.funcs) scope slot) (r.eval (sigs sp.funcs) scope (slot + 1)) =
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

/-- A struct literal: its fields, one after another from `slot`. -/
theorem eval_struct {k : Nat} (ihe : ∀ m < k, EvalSound sp mp m) {ty : SrcType} {fields : List SrcEff}
    (ok : evalStruct ty (evalArgs (sigs sp.funcs) scope fields slot) = some ev)
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

/-- An enum literal: its payload from `slot + 1`, then its tag in `slot`. -/
theorem eval_variant {k : Nat} (ihe : ∀ m < k, EvalSound sp mp m) {ty : SrcType} {variant : Nat}
    {payload : List SrcEff}
    (ok : evalVariant ty variant slot (evalArgs (sigs sp.funcs) scope payload (slot + 1)) = some ev)
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

/-- An operator applied in place to its operand's slot. -/
theorem eval_then {k : Nat} (ihe : EvalSound sp mp k) {operand : SrcEff} {o : Evaluated}
    (operandOk : operand.eval (sigs sp.funcs) scope slot = some o) {t : Typed}
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
        | eIndex => simp [SrcEff.eval] at ok
        | eStruct ty fields =>
          simp only [SrcEff.eval] at ok
          exact eval_struct (fun m lt => belowE m (Nat.le_of_lt lt)) ok corr fr fresh hc run bound
        | eVariant ty variant payload =>
          simp only [SrcEff.eval] at ok
          exact eval_variant (fun m lt => belowE m (Nat.le_of_lt lt)) ok corr fr fresh hc run bound
        | eMatch => simp [SrcEff.eval] at ok
        | eDivide op l r =>
          simp only [SrcEff.eval] at ok
          exact eval_divide hereE ok corr fr fresh hc run bound

/-- The simulation, by induction on Core's fuel. -/
theorem stmt_sound {sp : SrcProgram} {mp : Program}
    (lowered : lowerFuncs (sigs sp.funcs) sp.decls sp.funcs = some mp.funcs) : ∀ fuel, StmtSound sp mp fuel :=
  fun fuel => (sound_both lowered fuel).1

end Lanius.Mini
