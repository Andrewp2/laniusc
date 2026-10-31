import Lanius.Faithful.Sim.EffStep
import Lanius.Faithful.Safe.Expr
import Lanius.Faithful.Safe.Grows

/-! # Effectful expressions do not trap undefined

An effectful expression `effTy` types, on locals that mean `env`, that Core
runs until it traps within the heap bound, traps with a defined trap
(`eff_safe`), when Core's runs of its callees' bodies with less fuel do
(`FuncSafe`). The parts Core completed on the way have their pure meanings
(`eff_sim`), so each part that traps is typed and on related locals. -/

namespace Lanius.Faithful

open Lanius.Mini
open Lanius.Core (Value)
open Lanius.Semantics (State Completion evalExpr evalExprs evalMatchArms execStmt restoreLocals)

/-! ## Subset statements end with `next` or a return -/

/-- How a subset statement can end: never with `break` or `continue`. -/
def Ends : Completion → Prop
  | .next => True
  | .returned _ => True
  | .breakLoop => False
  | .continueLoop => False

theorem stmt_ends (sp : SrcProgram) :
    ∀ (fuel : Nat) {st : State} {s : SrcStmt} {c : Completion} {st' : State},
      execStmt fuel sp.toCore st s.toCore = .done c st' → Ends c := by
  intro fuel
  induction fuel using Nat.strongRecOn with
  | _ fuel ih =>
  intro st s c st' run
  have letCase : ∀ {id : Nat} {ty : Core.Ty} {e : Core.Expr} {body : SrcStmt},
      execStmt fuel sp.toCore st (.letLocal id ty e body.toCore) = .done c st' → Ends c := by
    intro id ty e body run
    obtain ⟨j, v, s1, s2, rfl, -, brun, -⟩ := letLocal_inv run
    exact ih j (Nat.lt_succ_self j) brun
  have exprCase : ∀ {e : Core.Expr}, execStmt fuel sp.toCore st (.expression e) = .done c st' → Ends c := by
    intro e run
    obtain ⟨j, v, -, -, rfl⟩ := expression_inv run
    trivial
  cases s with
  | nop => obtain ⟨rfl, -⟩ := skip_inv run; trivial
  | «let» => exact letCase run
  | letStruct => exact letCase run
  | letCall => exact letCase run
  | letEnum => exact letCase run
  | letMatch => exact letCase run
  | letAlloc => exact letCase run
  | letLoad => exact letCase run
  | letSlice => exact letCase run
  | letIndex => exact letCase run
  | letEval => exact letCase run
  | set => exact exprCase run
  | setField => exact exprCase run
  | setCall => exact exprCase run
  | setByte => exact exprCase run
  | free => exact exprCase run
  | setIndex => exact exprCase run
  | setEval => exact exprCase run
  | discard => exact exprCase run
  | setIndexEval => exact exprCase run
  | setFieldEval => exact exprCase run
  | «assert» => exact exprCase run
  | «then» first second =>
    obtain ⟨j, s1, c1, rfl, frun, ⟨-, srun⟩ | ⟨-, rfl, -⟩⟩ := sequence_inv run
    · exact ih j (Nat.lt_succ_self j) (s := second) srun
    · exact ih j (Nat.lt_succ_self j) (s := first) frun
  | «if» condition thenBranch elseBranch =>
    obtain ⟨j, s1, x, rfl, -, brun⟩ := if_inv run
    cases x
    · exact ih j (Nat.lt_succ_self j) (s := elseBranch) brun
    · exact ih j (Nat.lt_succ_self j) (s := thenBranch) brun
  | ifEval condition thenBranch elseBranch =>
    obtain ⟨j, s1, x, rfl, -, brun⟩ := if_inv run
    cases x
    · exact ih j (Nat.lt_succ_self j) (s := elseBranch) brun
    · exact ih j (Nat.lt_succ_self j) (s := thenBranch) brun
  | «while» condition body =>
    cases fuel with
    | zero => simp [execStmt] at run
    | succ f =>
      simp only [SrcStmt.toCore, execStmt] at run
      split at run
      · simp only [Semantics.Outcome.done.injEq] at run; rw [← run.1]; trivial
      · split at run
        all_goals first
          | (simp at run; done)
          | (simp only [Semantics.Outcome.done.injEq] at run; rw [← run.1]; trivial)
          | exact ih f (Nat.lt_succ_self f) (s := .while condition body) run
      all_goals simp at run
  | whileEval condition body =>
    cases fuel with
    | zero => simp [execStmt] at run
    | succ f =>
      simp only [SrcStmt.toCore, execStmt] at run
      split at run
      · simp only [Semantics.Outcome.done.injEq] at run; rw [← run.1]; trivial
      · split at run
        all_goals first
          | (simp at run; done)
          | (simp only [Semantics.Outcome.done.injEq] at run; rw [← run.1]; trivial)
          | exact ih f (Nat.lt_succ_self f) (s := .whileEval condition body) run
      all_goals simp at run
  | «return» => obtain ⟨j, v, -, -, rfl⟩ := return_inv run; trivial
  | returnEval => obtain ⟨j, v, -, -, rfl⟩ := return_inv run; trivial
  | returnUnit => obtain ⟨rfl, -⟩ := returnUnit_inv run; trivial

/-! ## Definitions -/

section
variable (sp : SrcProgram) (prims : Prims) (outside : List Nat)

/-- Core's runs of a callee's body with fuel `m` that trap within the heap
bound trap defined. -/
def FuncSafe (m : Nat) : Prop :=
  ∀ {c : Nat} {f : SrcFunc} {values ps : List Value} {st completed : State} {r : Lanius.Trap},
    sp.funcs[c]? = some f → outside.contains c = false → values.length = f.params.length → Inv st →
    completed.heap.nextAddress ≤ 2 ^ 64 →
    VRels sp.toCore (boxElem sp prims) st.heap (f.params.map SrcParam.ty) values ps →
    execStmt m sp.toCore (({ st with locals := [] } : State).bindLocals (paramBindings f.params values))
      f.body.toCore = .trapped r completed →
    undefinedTrap r = false

def EffSafe (k : Nat) : Prop :=
  ∀ {tenv : TEnv} {env : Env} {st : State} {e : SrcEff} {r : Lanius.Trap} {st' : State} {t : SrcType},
    evalExpr k sp.toCore st e.toCore = .trapped r st' → effTy sp outside (boxElem sp prims) tenv e = some t →
    Inv st → EnvRel sp.toCore (boxElem sp prims) st.heap tenv env st → st'.heap.nextAddress ≤ 2 ^ 64 →
    undefinedTrap r = false

def EffsSafe (k : Nat) : Prop :=
  ∀ {tenv : TEnv} {env : Env} {st : State} {es : List SrcEff} {r : Lanius.Trap} {st' : State}
    {ts : List SrcType},
    evalExprs k sp.toCore st (SrcEff.toCoreList es) = .trapped r st' →
    effTys sp outside (boxElem sp prims) tenv es = some ts →
    Inv st → EnvRel sp.toCore (boxElem sp prims) st.heap tenv env st → st'.heap.nextAddress ≤ 2 ^ 64 →
    undefinedTrap r = false

def ArmsSafe (k : Nat) : Prop :=
  ∀ {tenv : TEnv} {env : Env} {st : State} {id kk j : Nat} {vs ps : List Value} {fs : List SrcType}
    {rty : SrcType} {variants : List (List SrcType)} {binders : List (List Nat)} {values : List SrcEff}
    {r : Lanius.Trap} {st' : State},
    evalMatchArms k sp.toCore st (.enumeration id kk vs) (SrcEff.coreArms id j binders values) = .trapped r st' →
    j ≤ kk → variants[kk - j]? = some fs → VRels sp.toCore (boxElem sp prims) st.heap fs vs ps →
    armsOk sp outside (boxElem sp prims) tenv rty variants binders values = true →
    Inv st → EnvRel sp.toCore (boxElem sp prims) st.heap tenv env st → st'.heap.nextAddress ≤ 2 ^ 64 →
    undefinedTrap r = false

end

/-! ## Facts the cases use -/

theorem effTrapGrows {sp : SrcProgram} {k : Nat} {st st' : State} {e : SrcEff} {r : Lanius.Trap}
    (run : evalExpr k sp.toCore st e.toCore = .trapped r st') : Grows st st' :=
  eff_trap_grows' run

theorem effsTrapGrows {sp : SrcProgram} {k : Nat} {st st' : State} {es : List SrcEff} {r : Lanius.Trap}
    (run : evalExprs k sp.toCore st (SrcEff.toCoreList es) = .trapped r st') : Grows st st' :=
  effs_trap_grows es (eff_grows k (grows sp k)) (eff_trap_grows k (grows sp k) (grows_trap sp k)) run

theorem effArmsTrapGrows {sp : SrcProgram} {k : Nat} {st st' : State} {sv : Value} {id j : Nat}
    {binders : List (List Nat)} {values : List SrcEff} {r : Lanius.Trap}
    (run : evalMatchArms k sp.toCore st sv (SrcEff.coreArms id j binders values) = .trapped r st') : Grows st st' :=
  effArms_trap_grows binders values id j (eff_trap_grows k (grows sp k) (grows_trap sp k)) run

theorem VRel.bool_inv {P : Core.Program} {boxes : Boxes} {heap : Memory.Heap} {v p : Value}
    (r : VRel P boxes heap .bool v p) : ∃ b, v = .boolean b :=
  (r.scalar_ty rfl).2

/-- A call of a function `callTy` accepts, whose arguments mean their pure
values and whose body traps or ends wrongly: the trap is defined when the
body's are. -/
theorem call_body_safe {sp : SrcProgram} {prims : Prims} {outside : List Nat} {k : Nat}
    (funcs : FuncSafe sp prims outside k) {callee : Nat} {f : SrcFunc} {values ps : List Value}
    {afterArgs completed : State} {r : Lanius.Trap}
    (notOut : outside.contains callee = false) (found : sp.funcs[callee]? = some f)
    (len : values.length = f.params.length) (inv : Inv afterArgs)
    (bound : completed.heap.nextAddress ≤ 2 ^ 64)
    (rs : VRels sp.toCore (boxElem sp prims) afterArgs.heap (f.params.map SrcParam.ty) values ps)
    (body : execStmt k sp.toCore (({ afterArgs with locals := [] } : State).bindLocals
        (paramBindings f.params values)) f.body.toCore = .trapped r completed ∨
      ∃ c, execStmt k sp.toCore (({ afterArgs with locals := [] } : State).bindLocals
        (paramBindings f.params values)) f.body.toCore = .done c completed ∧
        (r = .missingReturn ∨ ((c = .breakLoop ∨ c = .continueLoop) ∧ r = .typeMismatch))) :
    undefinedTrap r = false := by
  rcases body with body | ⟨c, body, rfl | ⟨bad, -⟩⟩
  · exact funcs found notOut len inv bound rs body
  · rfl
  · have ends := stmt_ends sp k body
    rcases bad with rfl | rfl <;> exact ends.elim

/-- The values of typed arguments are as many as the callee's parameters. -/
theorem VRels.length_params {P : Core.Program} {boxes : Boxes} {heap : Memory.Heap} {f : SrcFunc}
    {values ps : List Value} (rs : VRels P boxes heap (f.params.map SrcParam.ty) values ps) :
    values.length = f.params.length := by
  simpa using rs.length.1

/-! ## By Core's fuel -/

section
variable {sp : SrcProgram} {prims : Prims} {outside : List Nat} {k : Nat}

theorem eff_safe_step (calls : ∀ m, FuncSim sp prims outside m) (funcs : FuncSafe sp prims outside k)
    (eff : EffSafe sp prims outside k) (effs : EffsSafe sp prims outside k) (arms : ArmsSafe sp prims outside k) :
    EffSafe sp prims outside (k + 1) := by
  have sims := eff_sim (N := k) k (Nat.le_refl k) (fun j _ => calls j)
  have effD : EffOk sp prims outside k k := sims.1
  have effsD : EffsOk sp prims outside k k := sims.2.1
  intro tenv env st e r st' t run ht inv rel bound
  cases e with
  | ePure e =>
    simp only [SrcEff.toCore] at run
    simp only [effTy] at ht
    exact (expr_safe (toCore_target sp) tenv env e run ht rel).2
  | eCall callee args =>
    simp only [SrcEff.toCore] at run
    simp only [effTy, Option.bind_eq_some_iff] at ht
    obtain ⟨ts, hts, hc⟩ := ht
    obtain ⟨notOut, f, found, rfl, rfl⟩ := callTy_some hc
    obtain ⟨j, hj, h⟩ := call_trap_inv run
    obtain rfl : k = j := Nat.succ.inj hj
    rcases h with argsRun | ⟨values, afterArgs, argsRun, h⟩
    · exact effs argsRun hts inv rel bound
    cases h with
    | inl h =>
      obtain ⟨rfl, bad⟩ := h
      obtain ⟨ps, -, rs, -⟩ := effsD argsRun hts inv rel bound
      exact absurd rs.length_params (bad f found)
    | inr h =>
      obtain ⟨f', completed, found', len, rfl, body⟩ := h
      rw [found, Option.some.injEq] at found'
      subst found'
      have entry := bindLocals_same (paramBindings f.params values) { afterArgs with locals := [] }
      have gBody : Grows afterArgs completed := by
        refine (Grows.same entry.1 entry.2).trans ?_
        rcases body with body | ⟨c, body, -⟩
        · exact execStmt_trap_grows body
        · exact execStmt_grows body
      have b1 := Grows.bound (effsGrows argsRun) gBody inv.views bound
      obtain ⟨ps, -, rs, ran1⟩ := effsD argsRun hts inv rel b1
      exact call_body_safe (completed := completed) funcs notOut found len ran1.inv bound rs body
  | eApply op left right =>
    simp only [SrcEff.toCore] at run
    simp only [effTy, Option.bind_eq_some_iff] at ht
    obtain ⟨tl, htl, tr, htr, ht⟩ := ht
    by_cases isAnd : op = .logicalAnd
    · subst isAnd
      obtain ⟨rfl, rfl, rfl⟩ := opTy_bools ht (.inl rfl)
      simp only [SrcOp.toCore] at run
      obtain ⟨j, hj, lrun | ⟨l, lrun, notBool, -⟩ | ⟨s1, lrun, rrun⟩⟩ := logicalAnd_trap_inv run
      all_goals obtain rfl : k = j := Nat.succ.inj hj
      · exact eff lrun htl inv rel bound
      · obtain ⟨q, -, rl, -⟩ := effD lrun htl inv rel bound
        obtain ⟨b, rfl⟩ := rl.bool_inv
        exact (notBool b rfl).elim
      · have b1 := Grows.bound (effGrows lrun) (effTrapGrows rrun) inv.views bound
        obtain ⟨q, -, rl, ran1⟩ := effD lrun htl inv rel b1
        exact eff rrun htr ran1.inv (rel.step ran1.step ran1.locals) bound
    by_cases isOr : op = .logicalOr
    · subst isOr
      obtain ⟨rfl, rfl, rfl⟩ := opTy_bools ht (.inr rfl)
      simp only [SrcOp.toCore] at run
      obtain ⟨j, hj, lrun | ⟨l, lrun, notBool, -⟩ | ⟨s1, lrun, rrun⟩⟩ := logicalOr_trap_inv run
      all_goals obtain rfl : k = j := Nat.succ.inj hj
      · exact eff lrun htl inv rel bound
      · obtain ⟨q, -, rl, -⟩ := effD lrun htl inv rel bound
        obtain ⟨b, rfl⟩ := rl.bool_inv
        exact (notBool b rfl).elim
      · have b1 := Grows.bound (effGrows lrun) (effTrapGrows rrun) inv.views bound
        obtain ⟨q, -, rl, ran1⟩ := effD lrun htl inv rel b1
        exact eff rrun htr ran1.inv (rel.step ran1.step ran1.locals) bound
    obtain ⟨j, hj, lrun | ⟨l, s1, lrun, rrun | ⟨rv, rrun, bad⟩⟩⟩ :=
      binary_trap_inv (SrcOp.toCore_ne_and isAnd) (SrcOp.toCore_ne_or isOr) run
    all_goals obtain rfl : k = j := Nat.succ.inj hj
    · exact eff lrun htl inv rel bound
    · have b1 := Grows.bound (effGrows lrun) (effTrapGrows rrun) inv.views bound
      obtain ⟨q, -, rl, ran1⟩ := effD lrun htl inv rel b1
      exact eff rrun htr ran1.inv (rel.step ran1.step ran1.locals) bound
    · have b1 := Grows.bound (effGrows lrun) (effGrows rrun) inv.views bound
      obtain ⟨ql, -, rl, ran1⟩ := effD lrun htl inv rel b1
      obtain ⟨qr, -, rr, ran2⟩ := effD rrun htr ran1.inv (rel.step ran1.step ran1.locals) bound
      have sl := opTy_scalar ht
      obtain ⟨rfl, -⟩ := opTy_same ht isAnd isOr
      rw [toCore_target] at bad
      exact binary_defined ht isAnd isOr (rl.scalar_ty sl).2 (rr.scalar_ty sl).2 bad
  | eDivide op left right =>
    simp only [SrcEff.toCore] at run
    simp only [effTy, Option.bind_eq_some_iff] at ht
    obtain ⟨tl, htl, tr, htr, hd⟩ := ht
    have notAnd : op.toCore ≠ .logicalAnd := by cases op <;> simp [SrcDivOp.toCore]
    have notOr : op.toCore ≠ .logicalOr := by cases op <;> simp [SrcDivOp.toCore]
    obtain ⟨j, hj, lrun | ⟨l, s1, lrun, rrun | ⟨rv, rrun, bad⟩⟩⟩ := binary_trap_inv notAnd notOr run
    all_goals obtain rfl : k = j := Nat.succ.inj hj
    · exact eff lrun htl inv rel bound
    · have b1 := Grows.bound (effGrows lrun) (effTrapGrows rrun) inv.views bound
      obtain ⟨q, -, rl, ran1⟩ := effD lrun htl inv rel b1
      exact eff rrun htr ran1.inv (rel.step ran1.step ran1.locals) bound
    · have b1 := Grows.bound (effGrows lrun) (effGrows rrun) inv.views bound
      obtain ⟨ql, -, rl, ran1⟩ := effD lrun htl inv rel b1
      obtain ⟨qr, -, rr, ran2⟩ := effD rrun htr ran1.inv (rel.step ran1.step ran1.locals) bound
      obtain ⟨rfl, num, rfl⟩ := divTy_some hd
      rw [toCore_target] at bad
      exact divide_defined hd (rl.scalar_ty (numTy_scalar num)).2 (rr.scalar_ty (numTy_scalar num)).2 bad
  | eNeg operand =>
    simp only [SrcEff.toCore] at run
    simp only [effTy, Option.bind_eq_some_iff] at ht
    obtain ⟨to, hto, hn⟩ := ht
    obtain ⟨rfl, num⟩ := numOf_some hn
    obtain ⟨j, hj, sub | ⟨w, sub, bad⟩⟩ := unary_trap_inv run
    all_goals obtain rfl : k = j := Nat.succ.inj hj
    · exact eff sub hto inv rel bound
    · obtain ⟨q, -, rq, -⟩ := effD sub hto inv rel bound
      rw [toCore_target] at bad
      exact (neg_ok num (rq.scalar_ty (numTy_scalar num)).2 bad).elim
  | eNot operand =>
    simp only [SrcEff.toCore] at run
    simp only [effTy, Option.bind_eq_some_iff] at ht
    obtain ⟨to, hto, hb⟩ := ht
    obtain ⟨rfl, rfl⟩ := boolOf_some hb
    obtain ⟨j, hj, sub | ⟨w, sub, bad⟩⟩ := unary_trap_inv run
    all_goals obtain rfl : k = j := Nat.succ.inj hj
    · exact eff sub hto inv rel bound
    · obtain ⟨q, -, rq, -⟩ := effD sub hto inv rel bound
      exact (not_ok (rq.scalar_ty rfl).2 bad).elim
  | eCast ty operand =>
    simp only [SrcEff.toCore] at run
    simp only [effTy, Option.bind_eq_some_iff] at ht
    obtain ⟨to, hto, hc⟩ := ht
    obtain ⟨rfl, num, numTo⟩ := castTy_some hc
    obtain ⟨j, hj, sub | ⟨w, sub, bad⟩⟩ := cast_trap_inv run
    all_goals obtain rfl : k = j := Nat.succ.inj hj
    · exact eff sub hto inv rel bound
    · obtain ⟨q, -, rq, -⟩ := effD sub hto inv rel bound
      rw [toCore_target] at bad
      exact (cast_ok num numTo (rq.scalar_ty (numTy_scalar num)).2 bad).elim
  | eIndex => simp [effTy] at ht
  | eStride => simp [effTy] at ht
  | eStruct ty fields =>
    simp only [SrcEff.toCore] at run
    simp only [effTy, Option.bind_eq_some_iff] at ht
    obtain ⟨ts, hts, -⟩ := ht
    obtain ⟨j, hj, frun⟩ := structValue_trap_inv run
    obtain rfl : k = j := Nat.succ.inj hj
    exact effs frun hts inv rel bound
  | eVariant ty variant payload =>
    simp only [SrcEff.toCore] at run
    simp only [effTy, Option.bind_eq_some_iff] at ht
    obtain ⟨ts, hts, -⟩ := ht
    obtain ⟨j, hj, prun⟩ := enumValue_trap_inv run
    obtain rfl : k = j := Nat.succ.inj hj
    exact effs prun hts inv rel bound
  | eMatch scrutinee ety rty binders values =>
    simp only [SrcEff.toCore] at run
    simp only [effTy, Option.bind_eq_some_iff] at ht
    obtain ⟨ts, hts, hm⟩ := ht
    obtain ⟨j, hj, srun | ⟨sv, s1, srun, arun⟩⟩ := matchValue_trap_inv run
    all_goals obtain rfl : k = j := Nat.succ.inj hj
    · exact eff srun hts inv rel bound
    cases ety with
    | enum eid variants =>
      simp only at hm
      split at hm
      · rename_i ok
        simp only [Bool.and_eq_true] at ok
        obtain ⟨same, aok⟩ := ok
        simp only [Option.some.injEq] at hm
        subst hm
        have := SrcType.same_eq same
        subst this
        simp only [SrcType.typeId] at arun
        have b1 := Grows.bound (effGrows srun) (effArmsTrapGrows arun) inv.views bound
        obtain ⟨q, -, rq, ran1⟩ := effD srun hts inv rel b1
        obtain ⟨kk, fs, vs, ps, rfl, rfl, hk, rs⟩ := rq.enum_inv
        exact arms arun (Nat.zero_le _) (by simpa using hk) rs aok ran1.inv (rel.step ran1.step ran1.locals) bound
      · simp at hm
    | i32 => simp at hm
    | bool => simp at hm
    | uint => simp at hm
    | struct => simp at hm
    | ptr => simp at hm
    | slice => simp at hm
    | unit => simp at hm
    | isize => simp at hm
    | char => simp at hm
    | sint => simp at hm

theorem effs_safe_step (calls : ∀ m, FuncSim sp prims outside m) (eff : EffSafe sp prims outside k)
    (effs : EffsSafe sp prims outside k) : EffsSafe sp prims outside (k + 1) := by
  have effD : EffOk sp prims outside k k := (eff_sim (N := k) k (Nat.le_refl k) (fun j _ => calls j)).1
  intro tenv env st es r st' ts run ht inv rel bound
  cases es with
  | nil => simp only [SrcEff.toCoreList] at run; exact (exprs_nil_trap run).elim
  | cons e es =>
    simp only [SrcEff.toCoreList] at run
    simp only [effTys, Option.bind_eq_some_iff, Option.map_eq_some_iff] at ht
    obtain ⟨t, het, ts', hts, rfl⟩ := ht
    obtain ⟨j, hj, erun | ⟨v, s1, erun, esrun⟩⟩ := exprs_cons_trap_inv run
    all_goals obtain rfl : k = j := Nat.succ.inj hj
    · exact eff erun het inv rel bound
    · have b1 := Grows.bound (effGrows erun) (effsTrapGrows esrun) inv.views bound
      obtain ⟨p, -, -, ran1⟩ := effD erun het inv rel b1
      exact effs esrun hts ran1.inv (rel.step ran1.step ran1.locals) bound

theorem arms_safe_step (eff : EffSafe sp prims outside k) (arms : ArmsSafe sp prims outside k) :
    ArmsSafe sp prims outside (k + 1) := by
  intro tenv env st id kk j vs ps fs rty variants binders values r st' run le hfs rs ok inv rel bound
  cases binders with
  | nil => simp only [SrcEff.coreArms] at run; obtain ⟨rfl, -⟩ := arms_nil_trap run; rfl
  | cons bs rest =>
  cases values with
  | nil => simp only [SrcEff.coreArms] at run; obtain ⟨rfl, -⟩ := arms_nil_trap run; rfl
  | cons value values =>
  cases variants with
  | nil => simp [armsOk] at ok
  | cons fs0 vrest =>
  simp only [armsOk, Bool.and_eq_true, beq_iff_eq] at ok
  obtain ⟨⟨len, hval⟩, okRest⟩ := ok
  simp only [SrcEff.coreArms] at run
  obtain ⟨j', hj, alt⟩ := arms_cons_trap_inv run
  obtain rfl : k = j' := Nat.succ.inj hj
  have lens := rs.length
  by_cases same : j = kk
  · subst same
    simp only [Nat.sub_self, List.getElem?_cons_zero, Option.some.injEq] at hfs
    subst hfs
    have matched := matchPattern_variant id j j bs vs
    simp only [true_and, len, lens.1, if_true] at matched
    rcases alt with ⟨none, -⟩ | ⟨bs', s2, hbs, vrun, rfl⟩
    · rw [matched] at none; cases none
    rw [matched, Option.some.injEq] at hbs
    subst hbs
    split at hval
    · rename_i t' het
      have rel' : EnvRel sp.toCore (boxElem sp prims) (st.bindLocals (bs.zip vs)).heap
          (tenv.bindAll (bs.zip fs0)) (env.bindAll (bs.zip ps)) (st.bindLocals (bs.zip vs)) := by
        rw [(bindLocals_same _ _).1]
        exact EnvRel.bindAll bs inv rel rs len
      exact eff vrun het (inv.bindLocals _) rel' bound
    · simp at hval
  · have lt : j < kk := by omega
    have none := matchPattern_variant id j kk bs vs
    simp only [same, false_and, if_false] at none
    rcases alt with ⟨-, rest'⟩ | ⟨bs', s2, hbs, -, -⟩
    · have hfs' : vrest[kk - (j + 1)]? = some fs := by
        rw [show kk - j = (kk - (j + 1)) + 1 by omega, List.getElem?_cons_succ] at hfs
        exact hfs
      exact arms rest' lt hfs' rs okRest inv rel bound
    · rw [none] at hbs; cases hbs

/-- Every effectful expression Core runs with fuel `k` until it traps, within
the heap bound, traps defined, when the callees' bodies with less fuel do. -/
theorem eff_safe (calls : ∀ m, FuncSim sp prims outside m) :
    ∀ k, (∀ j < k, FuncSafe sp prims outside j) →
      EffSafe sp prims outside k ∧ EffsSafe sp prims outside k ∧ ArmsSafe sp prims outside k
  | 0, _ =>
    ⟨fun run => by simp [evalExpr] at run, fun run => by simp [evalExprs] at run,
      fun run => by simp [evalMatchArms] at run⟩
  | k + 1, funcs =>
    let ⟨eff, effs, arms⟩ := eff_safe calls k (fun j lt => funcs j (by omega))
    ⟨eff_safe_step calls (funcs k (by omega)) eff effs arms, effs_safe_step calls eff effs, arms_safe_step eff arms⟩

end

end Lanius.Faithful
