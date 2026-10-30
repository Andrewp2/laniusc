import Lanius.Faithful.Sim.Eff

/-! # Effectful expressions, by Core's fuel

Each effectful expression Core completes with fuel `k + 1` has its pure
value when the parts Core ran with fuel `k` have theirs (`eff_step`), so all
of them do (`eff_sim`). -/

namespace Lanius.Faithful

open Lanius.Mini
open Lanius.Core (Value)
open Lanius.Semantics (State evalExpr evalExprs evalMatchArms)

section
variable {sp : SrcProgram} {prims : Prims} {outside : List Nat} {N k : Nat}

theorem effArmsGrows {k : Nat} {st st' : State} {sv v : Value} {id j : Nat} {binders : List (List Nat)}
    {values : List SrcEff}
    (run : evalMatchArms k sp.toCore st sv (SrcEff.coreArms id j binders values) = .done v st') : Grows st st' :=
  effArms_grows binders values id j (eff_grows k (grows sp k)) run

theorem eff_step (le : k + 1 ≤ N) (calls : FuncSim sp prims outside k) (eff : EffOk sp prims outside N k)
    (effs : EffsOk sp prims outside N k) (arms : ArmsOk sp prims outside N k) :
    EffOk sp prims outside N (k + 1) := by
  intro tenv env st e v st' t run ht inv rel bound
  cases e with
  | ePure e =>
    simp only [SrcEff.toCore] at run
    simp only [effTy] at ht
    have := e.eval_state run
    subst this
    obtain ⟨p, hp, r⟩ := expr_sim (toCore_target sp) tenv env e run ht rel
    exact ⟨p, hp, r, .refl inv⟩
  | eCall callee args =>
    simp only [SrcEff.toCore] at run
    obtain ⟨j, f, values, afterArgs, completed, c, hj, argsRun, found, len, bodyRun, result, rfl⟩ := call_inv' run
    obtain rfl : j = k := by omega
    simp only [effTy, Option.bind_eq_some_iff] at ht
    obtain ⟨ts, hts, hc⟩ := ht
    obtain ⟨notOut, f', found', rfl, rfl⟩ := callTy_some hc
    rw [found, Option.some.injEq] at found'
    subst found'
    have entry := bindLocals_same (paramBindings f.params values) { afterArgs with locals := [] }
    have gBody : Grows afterArgs completed := (Grows.same entry.1 entry.2).trans (execStmt_grows bodyRun)
    have b1 := Grows.bound (effsGrows argsRun) gBody inv.views bound
    obtain ⟨ps, hps, rs, ran1⟩ := effs argsRun hts inv rel b1
    obtain ⟨w, hw, rw, invc, stepc⟩ := calls found notOut len ran1.inv (show completed.heap.nextAddress ≤ 2 ^ 64 from bound) rs bodyRun result
    refine ⟨w, ?_, rw, ⟨invc.restore afterArgs, (ran1.step.trans stepc).restore afterArgs, ran1.locals⟩⟩
    simp only [peff, hps, Option.bind_some]
    exact pcall_mono sp prims _ hw le
  | eApply op l r =>
    simp only [SrcEff.toCore] at run
    simp only [effTy, Option.bind_eq_some_iff] at ht
    obtain ⟨tl, htl, tr, htr, ht⟩ := ht
    by_cases isAnd : op = .logicalAnd
    · subst isAnd
      obtain ⟨rfl, rfl⟩ := opTy_and ht
      simp only [SrcOp.toCore] at run
      obtain ⟨j, s1, x, hj, lrun, rest⟩ := logicalAnd_inv run
      obtain rfl : j = k := by omega
      rcases rest with ⟨rfl, rfl, rfl⟩ | ⟨rfl, rrun⟩
      · obtain ⟨ql, hql, rl, ran⟩ := eff lrun htl inv rel bound
        rw [rl.boolean] at hql
        exact ⟨_, by simp [peff, applyOp, hql, asBool], .scalar ⟨_, rfl⟩, ran⟩
      · have b1 := Grows.bound (effGrows lrun) (effGrows rrun) inv.views bound
        obtain ⟨ql, hql, rl, ran1⟩ := eff lrun htl inv rel b1
        rw [rl.boolean] at hql
        obtain ⟨qr, hqr, rr, ran2⟩ := eff rrun htr ran1.inv (rel.step ran1.step ran1.locals) bound
        exact ⟨qr, by simp [peff, applyOp, hql, asBool, hqr], rr, ran1.trans ran2⟩
    by_cases isOr : op = .logicalOr
    · subst isOr
      obtain ⟨rfl, rfl⟩ := opTy_or ht
      simp only [SrcOp.toCore] at run
      obtain ⟨j, s1, x, hj, lrun, rest⟩ := logicalOr_inv run
      obtain rfl : j = k := by omega
      rcases rest with ⟨rfl, rfl, rfl⟩ | ⟨rfl, rrun⟩
      · obtain ⟨ql, hql, rl, ran⟩ := eff lrun htl inv rel bound
        rw [rl.boolean] at hql
        exact ⟨_, by simp [peff, applyOp, hql, asBool], .scalar ⟨_, rfl⟩, ran⟩
      · have b1 := Grows.bound (effGrows lrun) (effGrows rrun) inv.views bound
        obtain ⟨ql, hql, rl, ran1⟩ := eff lrun htl inv rel b1
        rw [rl.boolean] at hql
        obtain ⟨qr, hqr, rr, ran2⟩ := eff rrun htr ran1.inv (rel.step ran1.step ran1.locals) bound
        exact ⟨qr, by simp [peff, applyOp, hql, asBool, hqr], rr, ran1.trans ran2⟩
    obtain ⟨j, lv, s1, rv, hj, lrun, rrun, hv⟩ :=
      binary_inv (SrcOp.toCore_ne_and isAnd) (SrcOp.toCore_ne_or isOr) run
    obtain rfl : j = k := by omega
    have b1 := Grows.bound (effGrows lrun) (effGrows rrun) inv.views bound
    obtain ⟨ql, hql, rl, ran1⟩ := eff lrun htl inv rel b1
    obtain ⟨qr, hqr, rr, ran2⟩ := eff rrun htr ran1.inv (rel.step ran1.step ran1.locals) bound
    rw [toCore_target] at hv
    obtain ⟨happ, sv⟩ := binary_sim isAnd isOr ht (rl.mono ran2.step.reads ran2.step.ranges) rr hv
    exact ⟨v, by simp only [peff, hql, hqr, happ], .scalar sv, ran1.trans ran2⟩
  | eNeg o =>
    simp only [SrcEff.toCore] at run
    obtain ⟨j, w, hj, sub, hw⟩ := unary_inv run
    obtain rfl : j = k := by omega
    simp only [effTy, Option.bind_eq_some_iff] at ht
    obtain ⟨to, hto, hn⟩ := ht
    obtain ⟨rfl, -⟩ := numOf_some hn
    obtain ⟨q, hq, rq, ran⟩ := eff sub hto inv rel bound
    obtain ⟨rfl, sw⟩ := rq.flat (unary_flat hw)
    rw [toCore_target] at hw
    refine ⟨v, ?_, .scalar (neg_sty sw hw), ran⟩
    simp only [peff, hq, Option.bind_some, unary, Lanius.Faithful.target, hw]
    rfl
  | eNot o =>
    simp only [SrcEff.toCore] at run
    obtain ⟨j, w, hj, sub, hw⟩ := unary_inv run
    obtain rfl : j = k := by omega
    simp only [effTy, Option.bind_eq_some_iff] at ht
    obtain ⟨to, hto, hb⟩ := ht
    obtain ⟨rfl, -⟩ := boolOf_some hb
    obtain ⟨q, hq, rq, ran⟩ := eff sub hto inv rel bound
    obtain ⟨rfl, -⟩ := rq.flat (unary_flat hw)
    rw [toCore_target] at hw
    refine ⟨v, ?_, .scalar (not_sty hw), ran⟩
    simp only [peff, hq, Option.bind_some, unary, Lanius.Faithful.target, hw]
    rfl
  | eCast ty o =>
    simp only [SrcEff.toCore] at run
    obtain ⟨j, w, hj, sub, hw⟩ := cast_inv run
    obtain rfl : j = k := by omega
    simp only [effTy, Option.bind_eq_some_iff] at ht
    obtain ⟨to, hto, hc⟩ := ht
    obtain ⟨rfl, -, numTo⟩ := castTy_some hc
    obtain ⟨q, hq, rq, ran⟩ := eff sub hto inv rel bound
    obtain ⟨rfl, sw⟩ := rq.flat (cast_flat hw)
    rw [toCore_target] at hw
    refine ⟨v, ?_, .scalar (cast_sty sw numTo hw), ran⟩
    simp only [peff, hq, Option.bind_some, cast, Lanius.Faithful.target, hw]
    rfl
  | eIndex => simp [effTy] at ht
  | eStruct ty fields =>
    simp only [SrcEff.toCore] at run
    obtain ⟨j, vs, hj, frun, rfl⟩ := structValue_inv run
    obtain rfl : j = k := by omega
    simp only [effTy, Option.bind_eq_some_iff] at ht
    obtain ⟨ts, hts, hs⟩ := ht
    obtain ⟨id, rfl, hb, rfl⟩ := structTy_some hs
    obtain ⟨ps, hps, rs, ran⟩ := effs frun hts inv rel bound
    exact ⟨.structure id ps, by simp [peff, hps, SrcType.typeId], .struct hb rs, ran⟩
  | eVariant ty variant payload =>
    simp only [SrcEff.toCore] at run
    obtain ⟨j, vs, hj, prun, rfl⟩ := enumValue_inv run
    obtain rfl : j = k := by omega
    simp only [effTy, Option.bind_eq_some_iff] at ht
    obtain ⟨ts, hts, hs⟩ := ht
    obtain ⟨id, variants, rfl, hk, rfl⟩ := variantTy_some hs
    obtain ⟨ps, hps, rs, ran⟩ := effs prun hts inv rel bound
    exact ⟨.enumeration id variant ps, by simp [peff, hps, SrcType.typeId], .enum hk rs, ran⟩
  | eMatch scrutinee ety rty binders values =>
    simp only [SrcEff.toCore] at run
    obtain ⟨j, sv, s1, hj, srun, arun⟩ := matchValue_inv run
    obtain rfl : j = k := by omega
    simp only [effTy, Option.bind_eq_some_iff] at ht
    obtain ⟨ts, hts, hm⟩ := ht
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
        have b1 := Grows.bound (effGrows srun) (effArmsGrows arun) inv.views bound
        obtain ⟨q, hq, rq, ran1⟩ := eff srun hts inv rel b1
        obtain ⟨kk, fs, vs, ps, rfl, rfl, hk, rs⟩ := rq.enum_inv
        obtain ⟨p, hp, r, ran2⟩ := arms arun (Nat.zero_le _) (by simpa using hk) rs aok ran1.inv
          (rel.step ran1.step ran1.locals) bound
        refine ⟨p, ?_, r, ran1.trans ran2⟩
        simp only [peff, hq, Option.bind_some, SrcType.typeId]
        exact hp
      · simp at hm
    | i32 => simp at hm
    | bool => simp at hm
    | uint => simp at hm
    | struct => simp at hm
    | ptr => simp at hm
    | slice => simp at hm
    | unit => simp at hm
    | isize => simp at hm
    | sint => simp at hm
  | eDivide op l r =>
    simp only [SrcEff.toCore] at run
    have notAnd : op.toCore ≠ .logicalAnd := by cases op <;> simp [SrcDivOp.toCore]
    have notOr : op.toCore ≠ .logicalOr := by cases op <;> simp [SrcDivOp.toCore]
    obtain ⟨j, lv, s1, rv, hj, lrun, rrun, hv⟩ := binary_inv notAnd notOr run
    obtain rfl : j = k := by omega
    simp only [effTy, Option.bind_eq_some_iff] at ht
    obtain ⟨tl, htl, tr, htr, hd⟩ := ht
    obtain ⟨rfl, -⟩ := divTy_some hd
    have b1 := Grows.bound (effGrows lrun) (effGrows rrun) inv.views bound
    obtain ⟨ql, hql, rl, ran1⟩ := eff lrun htl inv rel b1
    obtain ⟨qr, hqr, rr, ran2⟩ := eff rrun htr ran1.inv (rel.step ran1.step ran1.locals) bound
    rw [toCore_target] at hv
    have flat := binary_flat hv
    obtain ⟨rfl, sl⟩ := (rl.mono ran2.step.reads ran2.step.ranges).flat
      (flat.2 (by cases op <;> simp [SrcDivOp.toCore]) (by cases op <;> simp [SrcDivOp.toCore]))
    obtain ⟨rfl, -⟩ := rr.flat (flat.1 sl)
    refine ⟨v, ?_, .scalar (divide_sty sl hv), ran1.trans ran2⟩
    simp only [peff, hql, hqr, binary, Option.bind_some, Lanius.Faithful.target, hv]
    rfl
  | eStride => simp [effTy] at ht

/-- Every effectful expression Core completes with fuel `k ≤ N` has its pure value. -/
theorem eff_sim : ∀ k, k ≤ N → (∀ j < k, FuncSim sp prims outside j) →
    EffOk sp prims outside N k ∧ EffsOk sp prims outside N k ∧ ArmsOk sp prims outside N k
  | 0, _, _ =>
    ⟨fun run => by simp [evalExpr] at run, fun run => by simp [evalExprs] at run,
      fun run => by simp [evalMatchArms] at run⟩
  | k + 1, le, calls =>
    let ⟨eff, effs, arms⟩ := eff_sim k (by omega) (fun j lt => calls j (by omega))
    ⟨eff_step le (calls k (by omega)) eff effs arms, effs_step eff effs, arms_step eff arms⟩

end

end Lanius.Faithful
