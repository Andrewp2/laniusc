import Lanius.Faithful.Fwd.Step
import Lanius.Faithful.Sim.Stmt
import Lanius.Faithful.Cost

/-! # Forward: effectful expressions complete in Core

An effectful expression `effTy` types, with a cost-semantics value `(p, h)`
on locals that mean `env`, completes in Core from some fuel on, when the heap
has `h` bytes left below `2 ^ 64` and Core completes the calls the cost
semantics makes (`FuncLive`): `eff_live`. The heap grows by at most `h`.
Each case runs the parts forward, then gets the relation of the whole from
the backward simulation, at a fuel where Core completed (`eff_rel`). -/

namespace Lanius.Faithful

open Lanius.Mini
open Lanius.Core (Value)
open Lanius.Semantics (State Completion evalExpr evalExprs evalMatchArms execStmt restoreLocals)

section
variable (sp : SrcProgram) (prims : Prims) (outside : List Nat) (cost : Nat → Nat)

/-- Core completes, within the cost, the bodies of the calls the cost
semantics gives a value with fuel `N` (the converse of `FuncSim`). -/
def FuncLive (N : Nat) : Prop :=
  ∀ {c : Nat} {f : SrcFunc} {values ps : List Value} {st : State} {w : Value} {h : Nat},
    sp.funcs[c]? = some f → outside.contains c = false → values.length = f.params.length → Inv st →
    VRels sp.toCore (boxElem sp prims) st.heap (f.params.map SrcParam.ty) values ps →
    qcall sp prims cost N c ps = some (w, h) → st.heap.nextAddress + h ≤ 2 ^ 64 → st.heap.remaining = none →
    ∃ compl completed v,
      Ev (fun k => execStmt k sp.toCore (({ st with locals := [] } : State).bindLocals
        (paramBindings f.params values)) f.body.toCore) compl completed ∧
      CallResult f.ret compl v ∧ completed.heap.nextAddress ≤ st.heap.nextAddress + h ∧
        completed.heap.remaining = none

end

/-! ## Costs -/

theorem qthen_some {α β : Type} {o : Option (α × Nat)} {k : α → Option (β × Nat)} {b : β} {h : Nat}
    (e : qthen o k = some (b, h)) : ∃ a h1 h2, o = some (a, h1) ∧ k a = some (b, h2) ∧ h = h1 + h2 := by
  cases o with
  | none => simp [qthen] at e
  | some p =>
    obtain ⟨a, h1⟩ := p
    simp only [qthen, Option.bind_some, addC] at e
    cases hk : k a with
    | none => rw [hk] at e; simp at e
    | some q =>
      obtain ⟨b', h2⟩ := q
      rw [hk] at e
      simp only [Option.map_some, Option.some.injEq, Prod.mk.injEq] at e
      obtain ⟨rfl, rfl⟩ := e
      exact ⟨a, h1, h2, rfl, hk, rfl⟩

theorem qfree_some {α : Type} {o : Option α} {b : α} {h : Nat} (e : qfree o = some (b, h)) : o = some b ∧ h = 0 := by
  cases o with
  | none => simp [qfree] at e
  | some a =>
    simp only [qfree, Option.map_some, Option.some.injEq, Prod.mk.injEq] at e
    obtain ⟨rfl, rfl⟩ := e
    exact ⟨rfl, rfl⟩

theorem qapplyOp_binary {op : SrcOp} (notAnd : op ≠ .logicalAnd) (notOr : op ≠ .logicalOr)
    (l r : Option (Value × Nat)) : qapplyOp op l r = qbinary op.toCore l r := by
  cases op <;> simp_all [qapplyOp]

theorem qbinary_some {op : Core.BinaryOp} {l r : Option (Value × Nat)} {p : Value} {h : Nat}
    (e : qbinary op l r = some (p, h)) :
    ∃ a b h1 h2, l = some (a, h1) ∧ r = some (b, h2) ∧ h = h1 + h2 ∧
      Semantics.evalBinaryValue target op a b = .ok p := by
  obtain ⟨a, h1, h', hl, rest, rfl⟩ := qthen_some e
  obtain ⟨b, h2, h3, hr, free, rfl⟩ := qthen_some rest
  obtain ⟨ok, rfl⟩ := qfree_some free
  exact ⟨a, b, h1, h2, hl, hr, by aomega, toOption_some ok⟩

/-- The bound of a part of a budget. -/
private theorem part {a b : Nat} (le : a ≤ b) (budget : b ≤ 2 ^ 64) : a ≤ 2 ^ 64 := Nat.le_trans le budget

/-! ## The pure values, and the relations of completed runs -/

section
variable {sp : SrcProgram} {prims : Prims} {outside : List Nat} {cost : Nat → Nat} {N : Nat}

theorem callsLe {M : Nat} (le : N ≤ M) : CallsLe (pcall sp prims N) (pcall sp prims M) :=
  fun _ _ _ h => pcall_mono sp prims N h le

theorem peff_of {env : Env} {e : SrcEff} {p : Value} {h : Nat}
    (hq : qeff (qcall sp prims cost N) env e = some (p, h)) : peff (pcall sp prims N) env e = some p := by
  rw [peff_eq (pcall_eq_qcall sp prims cost N), hq]; rfl

theorem peffs_of {env : Env} {es : List SrcEff} {ps : List Value} {h : Nat}
    (hq : qeffs (qcall sp prims cost N) env es = some (ps, h)) : peffs (pcall sp prims N) env es = some ps := by
  rw [peffs_eq (pcall_eq_qcall sp prims cost N), hq]; rfl

theorem parms_of {env : Env} {v : Value} {id j : Nat} {binders : List (List Nat)} {values : List SrcEff}
    {p : Value} {h : Nat} (hq : qarms (qcall sp prims cost N) env v id j binders values = some (p, h)) :
    parms (pcall sp prims N) env v id j binders values = some p := by
  rw [parms_eq (pcall_eq_qcall sp prims cost N), hq]; rfl

theorem pstmt_of {env : Env} {s : SrcStmt} {d : Done} {h : Nat}
    (hq : qstmt (qcall sp prims cost N) env s = some (d, h)) : pstmt (pcall sp prims N) env s = some d := by
  rw [pstmt_eq (pcall_eq_qcall sp prims cost N), hq]; rfl

variable (calls : ∀ m, FuncSim sp prims outside m)
include calls

theorem eff_rel {tenv : TEnv} {env : Env} {st : State} {e : SrcEff} {t : SrcType} {p v : Value} {st' : State}
    (ht : effTy sp outside (boxElem sp prims) tenv e = some t) (inv : Inv st)
    (rel : EnvRel sp.toCore (boxElem sp prims) st.heap tenv env st) (hp : peff (pcall sp prims N) env e = some p)
    (run : Ev (fun k => evalExpr k sp.toCore st e.toCore) v st') (bound : st'.heap.nextAddress ≤ 2 ^ 64) :
    VRel sp.toCore (boxElem sp prims) st'.heap t v p ∧ Ran st st' := by
  obtain ⟨k, hk⟩ := run.at
  obtain ⟨p', hp', r, ran⟩ := effOk (N := max N (k + 1)) (by aomega) (fun i _ => calls i) hk ht inv rel bound
  rw [peff_mono (callsLe (Nat.le_max_left N (k + 1))) hp, Option.some.injEq] at hp'
  subst hp'
  exact ⟨r, ran⟩

theorem effs_rel {tenv : TEnv} {env : Env} {st : State} {es : List SrcEff} {ts : List SrcType}
    {ps vs : List Value} {st' : State}
    (ht : effTys sp outside (boxElem sp prims) tenv es = some ts) (inv : Inv st)
    (rel : EnvRel sp.toCore (boxElem sp prims) st.heap tenv env st) (hp : peffs (pcall sp prims N) env es = some ps)
    (run : Ev (fun k => evalExprs k sp.toCore st (SrcEff.toCoreList es)) vs st')
    (bound : st'.heap.nextAddress ≤ 2 ^ 64) :
    VRels sp.toCore (boxElem sp prims) st'.heap ts vs ps ∧ Ran st st' := by
  obtain ⟨k, hk⟩ := run.at
  obtain ⟨ps', hp', r, ran⟩ :=
    (eff_sim (N := max N (k + 1)) k (by aomega) (fun i _ => calls i)).2.1 hk ht inv rel bound
  rw [peffs_mono (callsLe (Nat.le_max_left N (k + 1))) hp, Option.some.injEq] at hp'
  subst hp'
  exact ⟨r, ran⟩

theorem arms_rel {tenv : TEnv} {env : Env} {st : State} {id kk j : Nat} {vs ps : List Value} {fs : List SrcType}
    {rty : SrcType} {variants : List (List SrcType)} {binders : List (List Nat)} {values : List SrcEff}
    {p v : Value} {st' : State} (le : j ≤ kk) (hfs : variants[kk - j]? = some fs)
    (rs : VRels sp.toCore (boxElem sp prims) st.heap fs vs ps)
    (ok : armsOk sp outside (boxElem sp prims) tenv rty variants binders values = true) (inv : Inv st)
    (rel : EnvRel sp.toCore (boxElem sp prims) st.heap tenv env st)
    (hp : parms (pcall sp prims N) env (.enumeration id kk ps) id j binders values = some p)
    (run : Ev (fun k => evalMatchArms k sp.toCore st (.enumeration id kk vs) (SrcEff.coreArms id j binders values))
      v st') (bound : st'.heap.nextAddress ≤ 2 ^ 64) :
    VRel sp.toCore (boxElem sp prims) st'.heap rty v p ∧ Ran st st' := by
  obtain ⟨k, hk⟩ := run.at
  obtain ⟨p', hp', r, ran⟩ :=
    (eff_sim (N := max N (k + 1)) k (by aomega) (fun i _ => calls i)).2.2 hk le hfs rs ok inv rel bound
  rw [parms_mono (callsLe (Nat.le_max_left N (k + 1))) hp, Option.some.injEq] at hp'
  subst hp'
  exact ⟨r, ran⟩

/-! ## Effects, lists and arms -/

mutual
/-- **An effectful expression with a cost-semantics value completes in Core.** -/
theorem eff_live (live : FuncLive sp prims outside cost N) : ∀ (e : SrcEff) {tenv : TEnv} {env : Env} {st : State} {t : SrcType} {p : Value} {h : Nat},
    effTy sp outside (boxElem sp prims) tenv e = some t → Inv st →
    EnvRel sp.toCore (boxElem sp prims) st.heap tenv env st →
    qeff (qcall sp prims cost N) env e = some (p, h) → st.heap.nextAddress + h ≤ 2 ^ 64 → st.heap.remaining = none →
    ∃ v st', Ev (fun k => evalExpr k sp.toCore st e.toCore) v st' ∧
      VRel sp.toCore (boxElem sp prims) st'.heap t v p ∧ Ran st st' ∧
      st'.heap.nextAddress ≤ st.heap.nextAddress + h ∧ st'.heap.remaining = none
  | .ePure e, tenv, env, st, t, p, h, ht, inv, rel, hq, budget, fr => by
    have hq' := hq
    simp only [qeff] at hq'
    obtain ⟨hpe, rfl⟩ := qfree_some hq'
    simp only [effTy] at ht
    obtain ⟨v, ev⟩ := expr_live (toCore_target sp) tenv env e ht rel hpe
    have ev' : Ev (fun k => evalExpr k sp.toCore st (SrcEff.ePure e).toCore) v st := by
      simpa only [SrcEff.toCore] using ev
    have g : st.heap.nextAddress ≤ st.heap.nextAddress + 0 := by aomega
    obtain ⟨r, ran⟩ := eff_rel calls (by simpa only [effTy] using ht) inv rel (peff_of hq) ev' (part g budget)
    exact ⟨v, st, ev', r, ran, g, fr⟩
  | .eCall callee args, tenv, env, st, t, p, h, ht, inv, rel, hq, budget, fr => by
    have hq' := hq
    simp only [qeff] at hq'
    obtain ⟨ps, h1, h2, hps, hc, rfl⟩ := qthen_some hq'
    have ht' := ht
    simp only [effTy, Option.bind_eq_some_iff] at ht'
    obtain ⟨ts, hts, hct⟩ := ht'
    obtain ⟨notOut, f, found, rfl, rfl⟩ := callTy_some hct
    obtain ⟨vs, s1, ev1, rs, ran1, g1, f1⟩ :=
      effs_live live args hts inv rel hps (part (by aomega) budget) fr
    obtain ⟨compl, completed, v, evb, result, g2, f2⟩ :=
      live found notOut (by simpa using rs.length.1) ran1.inv rs hc (part (by aomega) budget) f1
    have ev := call_fwd ev1 found (by simpa using rs.length.1) evb result
    have ev' : Ev (fun k => evalExpr k sp.toCore st (SrcEff.eCall callee args).toCore) v
        (restoreLocals s1 completed) := by
      simpa only [SrcEff.toCore] using ev
    have g : (restoreLocals s1 completed).heap.nextAddress ≤ st.heap.nextAddress + (h1 + h2) := by
      show completed.heap.nextAddress ≤ _
      aomega
    obtain ⟨r, ran⟩ := eff_rel calls ht inv rel (peff_of hq) ev' (part g budget)
    exact ⟨v, _, ev', r, ran, g, f2⟩
  | .eApply op l r, tenv, env, st, t, p, h, ht, inv, rel, hq, budget, fr => by
    have ht' := ht
    simp only [effTy, Option.bind_eq_some_iff] at ht'
    obtain ⟨tl, htl, tr, htr, hop⟩ := ht'
    have hq' := hq
    simp only [qeff] at hq'
    by_cases isAnd : op = .logicalAnd
    · subst isAnd
      obtain ⟨rfl, rfl⟩ := opTy_and hop
      have hb : tl = .bool := by
        simp only [opTy] at hop
        split at hop
        · rename_i hb
          simp only [Bool.and_eq_true] at hb
          exact SrcType.isBool_eq hb.1
        · simp at hop
      subst hb
      simp only [qapplyOp] at hq'
      obtain ⟨lv, h1, h2, hql, rest, rfl⟩ := qthen_some hq'
      obtain ⟨wl, s1, evl, rl, ran1, g1, f1⟩ := eff_live live l htl inv rel hql (part (by aomega) budget) fr
      obtain ⟨rfl, b, rfl⟩ : lv = wl ∧ ∃ b, wl = .boolean b := rl.scalar_ty rfl
      cases b with
      | false =>
        simp only [asBool, Option.bind_some, Bool.false_eq_true, if_false, Option.some.injEq,
          Prod.mk.injEq] at rest
        obtain ⟨rfl, rfl⟩ := rest
        have ev : Ev (fun k => evalExpr k sp.toCore st (SrcEff.eApply .logicalAnd l r).toCore) (.boolean false) s1 := by
          simpa only [SrcEff.toCore, SrcOp.toCore] using and_false_fwd (b := r.toCore) evl
        have g : s1.heap.nextAddress ≤ st.heap.nextAddress + (h1 + 0) := by aomega
        obtain ⟨r', ran⟩ := eff_rel calls ht inv rel (peff_of hq) ev (part g budget)
        exact ⟨_, s1, ev, r', ran, g, f1⟩
      | true =>
        simp only [asBool, Option.bind_some, if_true] at rest
        obtain ⟨wr, s2, evr, rr, ran2, g2, f2⟩ :=
          eff_live live r htr ran1.inv (rel.step ran1.step ran1.locals) rest (part (by aomega) budget) f1
        have ev : Ev (fun k => evalExpr k sp.toCore st (SrcEff.eApply .logicalAnd l r).toCore) wr s2 := by
          simpa only [SrcEff.toCore, SrcOp.toCore] using and_true_fwd evl evr
        have g : s2.heap.nextAddress ≤ st.heap.nextAddress + (h1 + h2) := by aomega
        obtain ⟨r', ran⟩ := eff_rel calls ht inv rel (peff_of hq) ev (part g budget)
        exact ⟨_, s2, ev, r', ran, g, f2⟩
    by_cases isOr : op = .logicalOr
    · subst isOr
      obtain ⟨rfl, rfl⟩ := opTy_or hop
      have hb : tl = .bool := by
        simp only [opTy] at hop
        split at hop
        · rename_i hb
          simp only [Bool.and_eq_true] at hb
          exact SrcType.isBool_eq hb.1
        · simp at hop
      subst hb
      simp only [qapplyOp] at hq'
      obtain ⟨lv, h1, h2, hql, rest, rfl⟩ := qthen_some hq'
      obtain ⟨wl, s1, evl, rl, ran1, g1, f1⟩ := eff_live live l htl inv rel hql (part (by aomega) budget) fr
      obtain ⟨rfl, b, rfl⟩ : lv = wl ∧ ∃ b, wl = .boolean b := rl.scalar_ty rfl
      cases b with
      | true =>
        simp only [asBool, Option.bind_some, if_true, Option.some.injEq, Prod.mk.injEq] at rest
        obtain ⟨rfl, rfl⟩ := rest
        have ev : Ev (fun k => evalExpr k sp.toCore st (SrcEff.eApply .logicalOr l r).toCore) (.boolean true) s1 := by
          simpa only [SrcEff.toCore, SrcOp.toCore] using or_true_fwd (b := r.toCore) evl
        have g : s1.heap.nextAddress ≤ st.heap.nextAddress + (h1 + 0) := by aomega
        obtain ⟨r', ran⟩ := eff_rel calls ht inv rel (peff_of hq) ev (part g budget)
        exact ⟨_, s1, ev, r', ran, g, f1⟩
      | false =>
        simp only [asBool, Option.bind_some, Bool.false_eq_true, if_false] at rest
        obtain ⟨wr, s2, evr, rr, ran2, g2, f2⟩ :=
          eff_live live r htr ran1.inv (rel.step ran1.step ran1.locals) rest (part (by aomega) budget) f1
        have ev : Ev (fun k => evalExpr k sp.toCore st (SrcEff.eApply .logicalOr l r).toCore) wr s2 := by
          simpa only [SrcEff.toCore, SrcOp.toCore] using or_false_fwd evl evr
        have g : s2.heap.nextAddress ≤ st.heap.nextAddress + (h1 + h2) := by aomega
        obtain ⟨r', ran⟩ := eff_rel calls ht inv rel (peff_of hq) ev (part g budget)
        exact ⟨_, s2, ev, r', ran, g, f2⟩
    rw [qapplyOp_binary isAnd isOr] at hq'
    obtain ⟨lv, rv, h1, h2, hql, hqr, rfl, ok⟩ := qbinary_some hq'
    obtain ⟨wl, s1, evl, rl, ran1, g1, f1⟩ := eff_live live l htl inv rel hql (part (by aomega) budget) fr
    obtain ⟨wr, s2, evr, rr, ran2, g2, f2⟩ :=
      eff_live live r htr ran1.inv (rel.step ran1.step ran1.locals) hqr (part (by aomega) budget) f1
    have scalars : scalarTy tl = true ∧ tr = tl := by
      cases op
      all_goals first
        | exact absurd rfl isAnd
        | exact absurd rfl isOr
        | skip
      all_goals
        simp only [opTy] at hop
        split at hop
        · rename_i ok
          simp only [Bool.and_eq_true] at ok
          first
            | exact ⟨ok.1, (SrcType.same_eq ok.2).symm⟩
            | exact ⟨numTy_scalar ok.1, (SrcType.same_eq ok.2).symm⟩
        · simp at hop
    obtain ⟨sl, rfl⟩ := scalars
    obtain ⟨rfl, -⟩ := rl.scalar_ty sl
    obtain ⟨rfl, -⟩ := rr.scalar_ty sl
    have ev : Ev (fun k => evalExpr k sp.toCore st (SrcEff.eApply op l r).toCore) p s2 := by
      simp only [SrcEff.toCore]
      refine binary_fwd (SrcOp.toCore_ne_and isAnd) (SrcOp.toCore_ne_or isOr) evl evr ?_
      rw [toCore_target]
      exact ok
    have g : s2.heap.nextAddress ≤ st.heap.nextAddress + (h1 + h2) := by aomega
    obtain ⟨r', ran⟩ := eff_rel calls ht inv rel (peff_of hq) ev (part g budget)
    exact ⟨_, s2, ev, r', ran, g, f2⟩
  | .eNeg o, tenv, env, st, t, p, h, ht, inv, rel, hq, budget, fr => by
    have ht' := ht
    simp only [effTy, Option.bind_eq_some_iff] at ht'
    obtain ⟨to, hto, hn⟩ := ht'
    obtain ⟨-, num⟩ := numOf_some hn
    have hq' := hq
    simp only [qeff] at hq'
    obtain ⟨q, h1, h2, hqo, free, rfl⟩ := qthen_some hq'
    obtain ⟨hu, rfl⟩ := qfree_some free
    obtain ⟨w, s1, evo, rq, -, g1, f1⟩ := eff_live live o hto inv rel hqo (part (by aomega) budget) fr
    obtain ⟨rfl, -⟩ := rq.scalar_ty (numTy_scalar num)
    have ev : Ev (fun k => evalExpr k sp.toCore st (SrcEff.eNeg o).toCore) p s1 := by
      simp only [SrcEff.toCore]
      refine unary_fwd evo ?_
      rw [toCore_target]
      exact toOption_some hu
    have g : s1.heap.nextAddress ≤ st.heap.nextAddress + (h1 + 0) := by aomega
    obtain ⟨r', ran⟩ := eff_rel calls ht inv rel (peff_of hq) ev (part g budget)
    exact ⟨_, s1, ev, r', ran, g, f1⟩
  | .eNot o, tenv, env, st, t, p, h, ht, inv, rel, hq, budget, fr => by
    have ht' := ht
    simp only [effTy, Option.bind_eq_some_iff] at ht'
    obtain ⟨to, hto, hb⟩ := ht'
    obtain ⟨-, rfl⟩ := boolOf_some hb
    have hq' := hq
    simp only [qeff] at hq'
    obtain ⟨q, h1, h2, hqo, free, rfl⟩ := qthen_some hq'
    obtain ⟨hu, rfl⟩ := qfree_some free
    obtain ⟨w, s1, evo, rq, -, g1, f1⟩ := eff_live live o hto inv rel hqo (part (by aomega) budget) fr
    obtain ⟨rfl, -⟩ := rq.scalar_ty rfl
    have ev : Ev (fun k => evalExpr k sp.toCore st (SrcEff.eNot o).toCore) p s1 := by
      simp only [SrcEff.toCore]
      refine unary_fwd evo ?_
      rw [toCore_target]
      exact toOption_some hu
    have g : s1.heap.nextAddress ≤ st.heap.nextAddress + (h1 + 0) := by aomega
    obtain ⟨r', ran⟩ := eff_rel calls ht inv rel (peff_of hq) ev (part g budget)
    exact ⟨_, s1, ev, r', ran, g, f1⟩
  | .eCast ty o, tenv, env, st, t, p, h, ht, inv, rel, hq, budget, fr => by
    have ht' := ht
    simp only [effTy, Option.bind_eq_some_iff] at ht'
    obtain ⟨to, hto, hc⟩ := ht'
    obtain ⟨-, numFrom, -⟩ := castTy_some hc
    have hq' := hq
    simp only [qeff] at hq'
    obtain ⟨q, h1, h2, hqo, free, rfl⟩ := qthen_some hq'
    obtain ⟨hu, rfl⟩ := qfree_some free
    obtain ⟨w, s1, evo, rq, -, g1, f1⟩ := eff_live live o hto inv rel hqo (part (by aomega) budget) fr
    obtain ⟨rfl, -⟩ := rq.scalar_ty (numTy_scalar numFrom)
    have ev : Ev (fun k => evalExpr k sp.toCore st (SrcEff.eCast ty o).toCore) p s1 := by
      simp only [SrcEff.toCore]
      refine cast_fwd evo ?_
      rw [toCore_target]
      exact toOption_some hu
    have g : s1.heap.nextAddress ≤ st.heap.nextAddress + (h1 + 0) := by aomega
    obtain ⟨r', ran⟩ := eff_rel calls ht inv rel (peff_of hq) ev (part g budget)
    exact ⟨_, s1, ev, r', ran, g, f1⟩
  | .eIndex _ _, _, _, _, _, _, _, ht, _, _, _, _, _ => by simp [effTy] at ht
  | .eStruct ty fields, tenv, env, st, t, p, h, ht, inv, rel, hq, budget, fr => by
    have ht' := ht
    simp only [effTy, Option.bind_eq_some_iff] at ht'
    obtain ⟨ts, hts, hs⟩ := ht'
    obtain ⟨sid, rfl, -, rfl⟩ := structTy_some hs
    have hq' := hq
    simp only [qeff] at hq'
    obtain ⟨ps, h1, h2, hps, rest, rfl⟩ := qthen_some hq'
    simp only [Option.some.injEq, Prod.mk.injEq] at rest
    obtain ⟨rfl, rfl⟩ := rest
    obtain ⟨vs, s1, evs, -, -, g1, f1⟩ := effs_live live fields hts inv rel hps (part (by aomega) budget) fr
    have ev : Ev (fun k => evalExpr k sp.toCore st (SrcEff.eStruct (.struct sid ts) fields).toCore)
        (.structure sid vs) s1 := by
      simpa only [SrcEff.toCore, SrcType.literal] using struct_fwd (id := sid) evs
    have g : s1.heap.nextAddress ≤ st.heap.nextAddress + (h1 + 0) := by aomega
    obtain ⟨r', ran⟩ := eff_rel calls ht inv rel (peff_of hq) ev (part g budget)
    exact ⟨_, s1, ev, r', ran, g, f1⟩
  | .eVariant ty variant payload, tenv, env, st, t, p, h, ht, inv, rel, hq, budget, fr => by
    have ht' := ht
    simp only [effTy, Option.bind_eq_some_iff] at ht'
    obtain ⟨ts, hts, hs⟩ := ht'
    obtain ⟨eid, variants, rfl, -, rfl⟩ := variantTy_some hs
    have hq' := hq
    simp only [qeff] at hq'
    obtain ⟨ps, h1, h2, hps, rest, rfl⟩ := qthen_some hq'
    simp only [Option.some.injEq, Prod.mk.injEq] at rest
    obtain ⟨rfl, rfl⟩ := rest
    obtain ⟨vs, s1, evs, -, -, g1, f1⟩ := effs_live live payload hts inv rel hps (part (by aomega) budget) fr
    have ev : Ev (fun k => evalExpr k sp.toCore st (SrcEff.eVariant (.enum eid variants) variant payload).toCore)
        (.enumeration eid variant vs) s1 := by
      simpa only [SrcEff.toCore, SrcType.typeId] using enum_fwd (id := eid) (variant := variant) evs
    have g : s1.heap.nextAddress ≤ st.heap.nextAddress + (h1 + 0) := by aomega
    obtain ⟨r', ran⟩ := eff_rel calls ht inv rel (peff_of hq) ev (part g budget)
    exact ⟨_, s1, ev, r', ran, g, f1⟩
  | .eMatch scrutinee ety rty binders values, tenv, env, st, t, p, h, ht, inv, rel, hq, budget, fr => by
    have ht' := ht
    simp only [effTy, Option.bind_eq_some_iff] at ht'
    obtain ⟨ts, hts, hm⟩ := ht'
    have hq' := hq
    simp only [qeff] at hq'
    obtain ⟨q, h1, h2, hqs, hqa, rfl⟩ := qthen_some hq'
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
        obtain ⟨sv, s1, evs, rq, ran1, g1, f1⟩ := eff_live live scrutinee hts inv rel hqs (part (by aomega) budget) fr
        obtain ⟨kk, fs, vs, ps, rfl, rfl, hk, rs⟩ := rq.enum_inv
        simp only [SrcType.typeId] at hqa
        obtain ⟨v, s2, eva, -, -, g2, f2⟩ := arms_live live binders values (Nat.zero_le _) (by simpa using hk) rs aok
          ran1.inv (rel.step ran1.step ran1.locals) hqa (part (by aomega) budget) f1
        have ev : Ev (fun k => evalExpr k sp.toCore st
            (SrcEff.eMatch scrutinee (.enum eid variants) rty binders values).toCore) v s2 := by
          simpa only [SrcEff.toCore, SrcType.typeId] using match_fwd evs eva
        have g : s2.heap.nextAddress ≤ st.heap.nextAddress + (h1 + h2) := by aomega
        obtain ⟨r', ran⟩ := eff_rel calls ht inv rel (peff_of hq) ev (part g budget)
        exact ⟨_, s2, ev, r', ran, g, f2⟩
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
    | float => simp at hm
    | sint => simp at hm
    | array => simp at hm
  | .eDivide op l r, tenv, env, st, t, p, h, ht, inv, rel, hq, budget, fr => by
    have ht' := ht
    simp only [effTy, Option.bind_eq_some_iff] at ht'
    obtain ⟨tl, htl, tr, htr, hd⟩ := ht'
    obtain ⟨-, num, rfl⟩ := divTy_some hd
    have hq' := hq
    simp only [qeff] at hq'
    obtain ⟨lv, rv, h1, h2, hql, hqr, rfl, ok⟩ := qbinary_some hq'
    obtain ⟨wl, s1, evl, rl, ran1, g1, f1⟩ := eff_live live l htl inv rel hql (part (by aomega) budget) fr
    obtain ⟨wr, s2, evr, rr, ran2, g2, f2⟩ :=
      eff_live live r htr ran1.inv (rel.step ran1.step ran1.locals) hqr (part (by aomega) budget) f1
    obtain ⟨rfl, -⟩ := rl.scalar_ty (numTy_scalar num)
    obtain ⟨rfl, -⟩ := rr.scalar_ty (numTy_scalar num)
    have notAnd : op.toCore ≠ .logicalAnd := by cases op <;> simp [SrcDivOp.toCore]
    have notOr : op.toCore ≠ .logicalOr := by cases op <;> simp [SrcDivOp.toCore]
    have ev : Ev (fun k => evalExpr k sp.toCore st (SrcEff.eDivide op l r).toCore) p s2 := by
      simp only [SrcEff.toCore]
      refine binary_fwd notAnd notOr evl evr ?_
      rw [toCore_target]
      exact ok
    have g : s2.heap.nextAddress ≤ st.heap.nextAddress + (h1 + h2) := by aomega
    obtain ⟨r', ran⟩ := eff_rel calls ht inv rel (peff_of hq) ev (part g budget)
    exact ⟨_, s2, ev, r', ran, g, f2⟩
  | .eStride _, _, _, _, _, _, _, ht, _, _, _, _, _ => by simp [effTy] at ht
  | .arraySlice _ _, _, _, _, _, _, _, ht, _, _, _, _, _ => by simp [effTy] at ht
  | .eIf _ _ _ _, _, _, _, _, _, _, ht, _, _, _, _, _ => by simp [effTy] at ht
  | .eLet _ _ _ _ _, _, _, _, _, _, _, ht, _, _, _, _, _ => by simp [effTy] at ht
  | .eLen _, _, _, _, _, _, _, ht, _, _, _, _, _ => by simp [effTy] at ht

theorem effs_live (live : FuncLive sp prims outside cost N) : ∀ (es : List SrcEff) {tenv : TEnv} {env : Env} {st : State} {ts : List SrcType}
    {ps : List Value} {h : Nat},
    effTys sp outside (boxElem sp prims) tenv es = some ts → Inv st →
    EnvRel sp.toCore (boxElem sp prims) st.heap tenv env st →
    qeffs (qcall sp prims cost N) env es = some (ps, h) → st.heap.nextAddress + h ≤ 2 ^ 64 → st.heap.remaining = none →
    ∃ vs st', Ev (fun k => evalExprs k sp.toCore st (SrcEff.toCoreList es)) vs st' ∧
      VRels sp.toCore (boxElem sp prims) st'.heap ts vs ps ∧ Ran st st' ∧
      st'.heap.nextAddress ≤ st.heap.nextAddress + h ∧ st'.heap.remaining = none
  | [], tenv, env, st, ts, ps, h, ht, inv, rel, hq, budget, fr => by
    simp only [qeffs, Option.some.injEq, Prod.mk.injEq] at hq
    obtain ⟨rfl, rfl⟩ := hq
    simp only [effTys, Option.some.injEq] at ht
    subst ht
    exact ⟨[], st, by simpa only [SrcEff.toCoreList] using exprs_nil_fwd, .nil, .refl inv, by aomega, fr⟩
  | e :: es, tenv, env, st, ts, ps, h, ht, inv, rel, hq, budget, fr => by
    have hq' := hq
    simp only [qeffs] at hq'
    obtain ⟨p, h1, h', hp, rest, rfl⟩ := qthen_some hq'
    obtain ⟨ps', h2, h3, hps, last, rfl⟩ := qthen_some rest
    simp only [Option.some.injEq, Prod.mk.injEq] at last
    obtain ⟨rfl, rfl⟩ := last
    have ht' := ht
    simp only [effTys, Option.bind_eq_some_iff, Option.map_eq_some_iff] at ht'
    obtain ⟨t, het, ts', hts, rfl⟩ := ht'
    obtain ⟨v, s1, ev1, -, ran1, g1, f1⟩ := eff_live live e het inv rel hp (part (by aomega) budget) fr
    obtain ⟨vs, s2, ev2, -, -, g2, f2⟩ :=
      effs_live live es hts ran1.inv (rel.step ran1.step ran1.locals) hps (part (by aomega) budget) f1
    have ev : Ev (fun k => evalExprs k sp.toCore st (SrcEff.toCoreList (e :: es))) (v :: vs) s2 := by
      simpa only [SrcEff.toCoreList] using exprs_cons_fwd ev1 ev2
    have g : s2.heap.nextAddress ≤ st.heap.nextAddress + (h1 + (h2 + 0)) := by aomega
    obtain ⟨rs, ran⟩ := effs_rel calls ht inv rel (peffs_of hq) ev (part g budget)
    exact ⟨_, s2, ev, rs, ran, g, f2⟩

theorem arms_live (live : FuncLive sp prims outside cost N) : ∀ (binders : List (List Nat)) (values : List SrcEff) {tenv : TEnv} {env : Env} {st : State}
    {id kk j : Nat} {vs ps : List Value} {fs : List SrcType} {rty : SrcType} {variants : List (List SrcType)}
    {p : Value} {h : Nat},
    j ≤ kk → variants[kk - j]? = some fs → VRels sp.toCore (boxElem sp prims) st.heap fs vs ps →
    armsOk sp outside (boxElem sp prims) tenv rty variants binders values = true → Inv st →
    EnvRel sp.toCore (boxElem sp prims) st.heap tenv env st →
    qarms (qcall sp prims cost N) env (.enumeration id kk ps) id j binders values = some (p, h) →
    st.heap.nextAddress + h ≤ 2 ^ 64 → st.heap.remaining = none →
    ∃ v st', Ev (fun k => evalMatchArms k sp.toCore st (.enumeration id kk vs) (SrcEff.coreArms id j binders values))
        v st' ∧
      VRel sp.toCore (boxElem sp prims) st'.heap rty v p ∧ Ran st st' ∧
      st'.heap.nextAddress ≤ st.heap.nextAddress + h ∧ st'.heap.remaining = none
  | [], _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, hq, _, _ => by simp [qarms] at hq
  | _ :: _, [], _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, hq, _, _ => by simp [qarms] at hq
  | bs :: rest, value :: values, tenv, env, st, id, kk, j, vs, ps, fs, rty, variants, p, h, le, hfs, rs, ok, inv,
      rel, hq, budget, fr => by
    cases variants with
    | nil => simp [armsOk] at ok
    | cons fs0 vrest =>
    have ok' := ok
    simp only [armsOk, Bool.and_eq_true, beq_iff_eq] at ok'
    obtain ⟨⟨len, hval⟩, okRest⟩ := ok'
    have lens := rs.length
    have hq' := hq
    simp only [qarms] at hq'
    by_cases same : j = kk
    · subst same
      simp only [Nat.sub_self, List.getElem?_cons_zero, Option.some.injEq] at hfs
      subst hfs
      have pm := matchPattern_variant id j j bs ps
      simp only [true_and, len, lens.2, if_true] at pm
      rw [pm] at hq'
      have vm := matchPattern_variant id j j bs vs
      simp only [true_and, len, lens.1, if_true] at vm
      split at hval
      · rename_i t' het
        have rel' : EnvRel sp.toCore (boxElem sp prims) (st.bindLocals (bs.zip vs)).heap
            (tenv.bindAll (bs.zip fs0)) (env.bindAll (bs.zip ps)) (st.bindLocals (bs.zip vs)) := by
          rw [(bindLocals_same _ _).1]
          exact EnvRel.bindAll bs inv rel rs len
        have heq : (st.bindLocals (bs.zip vs)).heap.nextAddress = st.heap.nextAddress := by
          rw [(bindLocals_same _ _).1]
        obtain ⟨v, s2, ev1, -, -, g1, f1⟩ := eff_live live value het (inv.bindLocals _) rel' hq'
          (by rw [heq]; exact budget) (by rw [(bindLocals_same _ _).1]; exact fr)
        have ev : Ev (fun k => evalMatchArms k sp.toCore st (.enumeration id j vs)
            (SrcEff.coreArms id j (bs :: rest) (value :: values))) v (restoreLocals st s2) := by
          simpa only [SrcEff.coreArms] using arms_hit_fwd (arms := SrcEff.coreArms id (j + 1) rest values) vm ev1
        have g : (restoreLocals st s2).heap.nextAddress ≤ st.heap.nextAddress + h := by
          show s2.heap.nextAddress ≤ _
          aomega
        obtain ⟨r', ran⟩ := arms_rel calls (Nat.le_refl j) (by simp) rs ok inv rel (parms_of hq) ev (part g budget)
        exact ⟨_, _, ev, r', ran, g, f1⟩
      · simp at hval
    · have lt : j < kk := by aomega
      have pm := matchPattern_variant id j kk bs ps
      simp only [same, false_and, if_false] at pm
      rw [pm] at hq'
      have vm := matchPattern_variant id j kk bs vs
      simp only [same, false_and, if_false] at vm
      have hfs' : vrest[kk - (j + 1)]? = some fs := by
        rw [show kk - j = (kk - (j + 1)) + 1 by aomega, List.getElem?_cons_succ] at hfs
        exact hfs
      obtain ⟨v, s2, ev1, -, -, g1, f1⟩ := arms_live live rest values lt hfs' rs okRest inv rel hq' budget fr
      have ev : Ev (fun k => evalMatchArms k sp.toCore st (.enumeration id kk vs)
          (SrcEff.coreArms id j (bs :: rest) (value :: values))) v s2 := by
        simpa only [SrcEff.coreArms] using arms_skip_fwd (body := value.toCore) vm ev1
      obtain ⟨r', ran⟩ := arms_rel calls le hfs rs ok inv rel (parms_of hq) ev (part g1 budget)
      exact ⟨_, _, ev, r', ran, g1, f1⟩
end

end

end Lanius.Faithful
