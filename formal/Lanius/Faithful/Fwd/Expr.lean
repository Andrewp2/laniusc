import Lanius.Faithful.Sim.Expr

/-! # Forward: pure expressions complete in Core

A subset expression `exprTy` types, with a pure value on locals that mean
`env`, completes in Core from some fuel on, in the same state (`expr_live`).
The value it completes with means the pure one by `expr_sim`. -/

namespace Lanius.Faithful

open Lanius.Mini
open Lanius.Core (Value)
open Lanius.Semantics (State Outcome evalExpr evalExprs)

/-- A run completes with `v` in `s` at every fuel from some on. -/
def Ev {α : Type} (run : Nat → Outcome α) (v : α) (s : State) : Prop :=
  ∃ K, ∀ k, K ≤ k → run k = .done v s

theorem Ev.at {α : Type} {run : Nat → Outcome α} {v : α} {s : State} (h : Ev run v s) :
    ∃ k, run k = .done v s :=
  let ⟨K, hK⟩ := h
  ⟨K, hK K (Nat.le_refl _)⟩

theorem toOption_some {ε α : Type} {x : Except ε α} {a : α} (h : x.toOption = some a) : x = .ok a := by
  cases x with
  | error => simp [Except.toOption] at h
  | ok b => simp only [Except.toOption, Option.some.injEq] at h; rw [h]

theorem numTy_scalar {t : SrcType} (h : numTy t = true) : scalarTy t = true := by
  cases t <;> simp_all [numTy, scalarTy]

section
variable {P : Core.Program} {st : State}

theorem value_fwd (x : Value) : Ev (fun k => evalExpr k P st (.value x)) x st :=
  ⟨1, fun k hk => by
    obtain ⟨j, rfl⟩ : ∃ j, k = j + 1 := ⟨k - 1, by omega⟩
    simp [evalExpr]⟩

theorem local_fwd {id : Nat} {v : Value} (h : st.local? id = some v) : Ev (fun k => evalExpr k P st (.local id)) v st := by
  refine ⟨1, fun k hk => ?_⟩
  obtain ⟨j, rfl⟩ : ∃ j, k = j + 1 := ⟨k - 1, by omega⟩
  unfold State.local? State.cell? at h
  cases hc : st.cellId? id with
  | none => rw [hc] at h; cases h
  | some cell =>
    rw [hc, Option.bind_some] at h
    cases he : st.cellEntry? cell with
    | none => rw [he] at h; cases h
    | some entry =>
      rw [he, Option.bind_some] at h
      rcases entry with ⟨eid, _ | value⟩
      · cases h
      · simp only [Option.some.injEq] at h
        subst h
        simp only [evalExpr, hc, he]

theorem unary_fwd {op : Core.UnaryOp} {e : Core.Expr} {w v : Value} {s : State}
    (sub : Ev (fun k => evalExpr k P st e) w s) (ok : Semantics.evalUnaryValue P.target op w = .ok v) :
    Ev (fun k => evalExpr k P st (.unary op e)) v s := by
  obtain ⟨K, hK⟩ := sub
  refine ⟨K + 1, fun k hk => ?_⟩
  obtain ⟨j, rfl⟩ : ∃ j, k = j + 1 := ⟨k - 1, by omega⟩
  simp only [evalExpr, hK j (by omega), ok]

theorem cast_fwd {ty : Core.ScalarTy} {e : Core.Expr} {w v : Value} {s : State}
    (sub : Ev (fun k => evalExpr k P st e) w s) (ok : Semantics.evalScalarCast P.target ty w = .ok v) :
    Ev (fun k => evalExpr k P st (.cast ty e)) v s := by
  obtain ⟨K, hK⟩ := sub
  refine ⟨K + 1, fun k hk => ?_⟩
  obtain ⟨j, rfl⟩ : ∃ j, k = j + 1 := ⟨k - 1, by omega⟩
  simp only [evalExpr, hK j (by omega), ok]

theorem field_fwd {e : Core.Expr} {id index : Nat} {fields : List Value} {v : Value} {s : State}
    (sub : Ev (fun k => evalExpr k P st e) (.structure id fields) s) (found : fields[index]? = some v) :
    Ev (fun k => evalExpr k P st (.field e index)) v s := by
  obtain ⟨K, hK⟩ := sub
  refine ⟨K + 1, fun k hk => ?_⟩
  obtain ⟨j, rfl⟩ : ∃ j, k = j + 1 := ⟨k - 1, by omega⟩
  simp only [evalExpr, hK j (by omega), found]

theorem binary_fwd {op : Core.BinaryOp} (notAnd : op ≠ .logicalAnd) (notOr : op ≠ .logicalOr)
    {a b : Core.Expr} {l r v : Value} {s1 s2 : State}
    (left : Ev (fun k => evalExpr k P st a) l s1) (right : Ev (fun k => evalExpr k P s1 b) r s2)
    (ok : Semantics.evalBinaryValue P.target op l r = .ok v) :
    Ev (fun k => evalExpr k P st (.binary op a b)) v s2 := by
  obtain ⟨K1, h1⟩ := left
  obtain ⟨K2, h2⟩ := right
  refine ⟨max K1 K2 + 1, fun k hk => ?_⟩
  obtain ⟨j, rfl⟩ : ∃ j, k = j + 1 := ⟨k - 1, by omega⟩
  have e1 := h1 j (by omega)
  have e2 := h2 j (by omega)
  cases op
  all_goals first
    | exact absurd rfl notAnd
    | exact absurd rfl notOr
    | simp only [evalExpr, e1, e2, ok]

theorem and_false_fwd {a b : Core.Expr} {s1 : State}
    (left : Ev (fun k => evalExpr k P st a) (.boolean false) s1) :
    Ev (fun k => evalExpr k P st (.binary .logicalAnd a b)) (.boolean false) s1 := by
  obtain ⟨K, h⟩ := left
  refine ⟨K + 1, fun k hk => ?_⟩
  obtain ⟨j, rfl⟩ : ∃ j, k = j + 1 := ⟨k - 1, by omega⟩
  simp only [evalExpr, h j (by omega)]

theorem and_true_fwd {a b : Core.Expr} {s1 s2 : State} {v : Value}
    (left : Ev (fun k => evalExpr k P st a) (.boolean true) s1) (right : Ev (fun k => evalExpr k P s1 b) v s2) :
    Ev (fun k => evalExpr k P st (.binary .logicalAnd a b)) v s2 := by
  obtain ⟨K1, h1⟩ := left
  obtain ⟨K2, h2⟩ := right
  refine ⟨max K1 K2 + 1, fun k hk => ?_⟩
  obtain ⟨j, rfl⟩ : ∃ j, k = j + 1 := ⟨k - 1, by omega⟩
  simp only [evalExpr, h1 j (by omega), h2 j (by omega)]

theorem or_true_fwd {a b : Core.Expr} {s1 : State}
    (left : Ev (fun k => evalExpr k P st a) (.boolean true) s1) :
    Ev (fun k => evalExpr k P st (.binary .logicalOr a b)) (.boolean true) s1 := by
  obtain ⟨K, h⟩ := left
  refine ⟨K + 1, fun k hk => ?_⟩
  obtain ⟨j, rfl⟩ : ∃ j, k = j + 1 := ⟨k - 1, by omega⟩
  simp only [evalExpr, h j (by omega)]

theorem or_false_fwd {a b : Core.Expr} {s1 s2 : State} {v : Value}
    (left : Ev (fun k => evalExpr k P st a) (.boolean false) s1) (right : Ev (fun k => evalExpr k P s1 b) v s2) :
    Ev (fun k => evalExpr k P st (.binary .logicalOr a b)) v s2 := by
  obtain ⟨K1, h1⟩ := left
  obtain ⟨K2, h2⟩ := right
  refine ⟨max K1 K2 + 1, fun k hk => ?_⟩
  obtain ⟨j, rfl⟩ : ∃ j, k = j + 1 := ⟨k - 1, by omega⟩
  simp only [evalExpr, h1 j (by omega), h2 j (by omega)]

theorem exprs_nil_fwd : Ev (fun k => evalExprs k P st []) [] st :=
  ⟨1, fun k hk => by
    obtain ⟨j, rfl⟩ : ∃ j, k = j + 1 := ⟨k - 1, by omega⟩
    simp [evalExprs]⟩

theorem exprs_cons_fwd {e : Core.Expr} {es : List Core.Expr} {v : Value} {vs : List Value} {s1 s2 : State}
    (head : Ev (fun k => evalExpr k P st e) v s1) (tail : Ev (fun k => evalExprs k P s1 es) vs s2) :
    Ev (fun k => evalExprs k P st (e :: es)) (v :: vs) s2 := by
  obtain ⟨K1, h1⟩ := head
  obtain ⟨K2, h2⟩ := tail
  refine ⟨max K1 K2 + 1, fun k hk => ?_⟩
  obtain ⟨j, rfl⟩ : ∃ j, k = j + 1 := ⟨k - 1, by omega⟩
  simp only [evalExprs, h1 j (by omega), h2 j (by omega)]

end

section
variable {P : Core.Program} {boxes : Boxes}

/-- A field the pure value has, of a struct type that is not a box. -/
theorem VRel.field_fwd {heap : Memory.Heap} {t ft : SrcType} {v p q : Value} {index : Nat}
    (r : VRel P boxes heap t v p) (ht : fieldTy boxes t index = some ft) (hq : fieldOf p index = some q) :
    ∃ id fields x, v = .structure id fields ∧ fields[index]? = some x := by
  cases r with
  | scalar s => simp [fieldTy] at ht <;> (cases t <;> simp_all [STy])
  | struct none rs =>
    rename_i id fs vs ps
    simp only [fieldOf] at hq
    have hlen := rs.length
    have lt : index < vs.length := by
      have := (List.getElem?_eq_some_iff.mp hq).1
      omega
    exact ⟨id, vs, vs[index], rfl, List.getElem?_eq_getElem lt⟩
  | enum => simp [fieldTy] at ht
  | box some => simp [fieldTy, some] at ht

/-- **A pure expression completes in Core**, in the state it starts in. -/
theorem expr_live (target : P.target = .x86_64) (tenv : TEnv) (env : Env) (e : SrcExpr) :
    ∀ {st : State} {t : SrcType} {p : Value},
      exprTy boxes tenv e = some t → EnvRel P boxes st.heap tenv env st → pexpr env e = some p →
      ∃ v, Ev (fun k => evalExpr k P st e.toCore) v st := by
  induction e with
  | int value => intro _ _ _ _ _ _; exact ⟨_, value_fwd _⟩
  | boolean value => intro _ _ _ _ _ _; exact ⟨_, value_fwd _⟩
  | unsigned kind value => intro _ _ _ _ _ _; exact ⟨_, value_fwd _⟩
  | «local» id =>
    intro st t p ht rel _
    obtain ⟨v, q, hv, -, -⟩ := rel id t ht
    exact ⟨v, local_fwd hv⟩
  | field id index =>
    intro st t p ht rel hp
    simp only [exprTy, Option.bind_eq_some_iff] at ht
    obtain ⟨tl, htl, hft⟩ := ht
    obtain ⟨v, q, hv, hq, r⟩ := rel id tl htl
    simp only [pexpr, hq, Option.bind_some] at hp
    obtain ⟨sid, fields, x, rfl, found⟩ := r.field_fwd hft hp
    exact ⟨x, field_fwd (local_fwd hv) found⟩
  | negate operand ih =>
    intro st t p ht rel hp
    simp only [exprTy, Option.bind_eq_some_iff] at ht
    obtain ⟨to, hto, hn⟩ := ht
    obtain ⟨-, num⟩ := numOf_some hn
    simp only [pexpr, Option.bind_eq_some_iff] at hp
    obtain ⟨q, hq, hu⟩ := hp
    obtain ⟨w, hw⟩ := ih hto rel hq
    obtain ⟨k, hk⟩ := hw.at
    obtain ⟨q', hq', rq⟩ := expr_sim target tenv env operand hk hto rel
    rw [hq, Option.some.injEq] at hq'
    subst hq'
    obtain ⟨rfl, -⟩ := rq.scalar_ty (numTy_scalar num)
    refine ⟨p, unary_fwd hw ?_⟩
    rw [target]
    exact toOption_some hu
  | «not» operand ih =>
    intro st t p ht rel hp
    simp only [exprTy, Option.bind_eq_some_iff] at ht
    obtain ⟨to, hto, hb⟩ := ht
    obtain ⟨-, rfl⟩ := boolOf_some hb
    simp only [pexpr, Option.bind_eq_some_iff] at hp
    obtain ⟨q, hq, hu⟩ := hp
    obtain ⟨w, hw⟩ := ih hto rel hq
    obtain ⟨k, hk⟩ := hw.at
    obtain ⟨q', hq', rq⟩ := expr_sim target tenv env operand hk hto rel
    rw [hq, Option.some.injEq] at hq'
    subst hq'
    obtain ⟨rfl, -⟩ := rq.scalar_ty rfl
    refine ⟨p, unary_fwd hw ?_⟩
    rw [target]
    exact toOption_some hu
  | cast ty operand ih =>
    intro st t p ht rel hp
    simp only [exprTy, Option.bind_eq_some_iff] at ht
    obtain ⟨to, hto, hc⟩ := ht
    obtain ⟨-, numFrom, -⟩ := castTy_some hc
    simp only [pexpr, Option.bind_eq_some_iff] at hp
    obtain ⟨q, hq, hu⟩ := hp
    obtain ⟨w, hw⟩ := ih hto rel hq
    obtain ⟨k, hk⟩ := hw.at
    obtain ⟨q', hq', rq⟩ := expr_sim target tenv env operand hk hto rel
    rw [hq, Option.some.injEq] at hq'
    subst hq'
    obtain ⟨rfl, -⟩ := rq.scalar_ty (numTy_scalar numFrom)
    refine ⟨p, cast_fwd hw ?_⟩
    rw [target]
    exact toOption_some hu
  | apply op left right ihl ihr =>
    intro st t p ht rel hp
    simp only [exprTy, Option.bind_eq_some_iff] at ht
    obtain ⟨tl, htl, tr, htr, ht⟩ := ht
    simp only [pexpr] at hp
    -- the left operand
    cases hql : pexpr env left with
    | none =>
      rw [hql] at hp
      cases op <;> simp [applyOp, binary] at hp
    | some ql =>
    obtain ⟨wl, hwl⟩ := ihl htl rel hql
    obtain ⟨kl, hkl⟩ := hwl.at
    obtain ⟨ql', hql', rl⟩ := expr_sim target tenv env left hkl htl rel
    rw [hql, Option.some.injEq] at hql'
    subst hql'
    by_cases isAnd : op = .logicalAnd
    · subst isAnd
      obtain ⟨rfl, rfl⟩ := opTy_and ht
      have hb : tl = .bool := by
        simp only [opTy] at ht
        split at ht
        · rename_i hb
          simp only [Bool.and_eq_true] at hb
          exact SrcType.isBool_eq hb.1
        · simp at ht
      subst hb
      obtain ⟨rfl, b, rfl⟩ : ql = wl ∧ ∃ b, wl = .boolean b := by
        obtain ⟨e, s⟩ := rl.scalar_ty rfl
        exact ⟨e, s⟩
      cases b with
      | false => exact ⟨_, and_false_fwd hwl⟩
      | true =>
        simp only [applyOp, hql, Option.bind_some, asBool, if_true] at hp
        obtain ⟨wr, hwr⟩ := ihr htr rel hp
        exact ⟨wr, and_true_fwd hwl hwr⟩
    by_cases isOr : op = .logicalOr
    · subst isOr
      obtain ⟨rfl, rfl⟩ := opTy_or ht
      have hb : tl = .bool := by
        simp only [opTy] at ht
        split at ht
        · rename_i hb
          simp only [Bool.and_eq_true] at hb
          exact SrcType.isBool_eq hb.1
        · simp at ht
      subst hb
      obtain ⟨rfl, b, rfl⟩ : ql = wl ∧ ∃ b, wl = .boolean b := by
        obtain ⟨e, s⟩ := rl.scalar_ty rfl
        exact ⟨e, s⟩
      cases b with
      | true => exact ⟨_, or_true_fwd hwl⟩
      | false =>
        simp only [applyOp, hql, Option.bind_some, asBool, Bool.false_eq_true, if_false] at hp
        obtain ⟨wr, hwr⟩ := ihr htr rel hp
        exact ⟨wr, or_false_fwd hwl hwr⟩
    -- the other operators: both sides, then Core's operator
    rw [applyOp_binary isAnd isOr, hql] at hp
    cases hqr : pexpr env right with
    | none => rw [hqr] at hp; simp [binary] at hp
    | some qr =>
    rw [hqr] at hp
    obtain ⟨wr, hwr⟩ := ihr htr rel hqr
    obtain ⟨kr, hkr⟩ := hwr.at
    obtain ⟨qr', hqr', rr⟩ := expr_sim target tenv env right hkr htr rel
    rw [hqr, Option.some.injEq] at hqr'
    subst hqr'
    have scalars : scalarTy tl = true ∧ tr = tl := by
      cases op
      all_goals first
        | exact absurd rfl isAnd
        | exact absurd rfl isOr
        | skip
      all_goals
        simp only [opTy] at ht
        split at ht
        · rename_i ok
          simp only [Bool.and_eq_true] at ok
          first
            | exact ⟨ok.1, (SrcType.same_eq ok.2).symm⟩
            | exact ⟨numTy_scalar ok.1, (SrcType.same_eq ok.2).symm⟩
        · simp at ht
    obtain ⟨sl, rfl⟩ := scalars
    obtain ⟨rfl, -⟩ := rl.scalar_ty sl
    obtain ⟨rfl, -⟩ := rr.scalar_ty sl
    simp only [binary, Option.bind_some] at hp
    refine ⟨p, binary_fwd (SrcOp.toCore_ne_and isAnd) (SrcOp.toCore_ne_or isOr) hwl hwr ?_⟩
    rw [target]
    exact toOption_some hp
  | null => intro _ _ _ ht; simp [exprTy] at ht
  | char _ => intro _ _ _ ht; simp [exprTy] at ht
  | float _ _ => intro _ _ _ ht; simp [exprTy] at ht

theorem exprs_live (target : P.target = .x86_64) (tenv : TEnv) (env : Env) :
    ∀ (es : List SrcExpr) {st : State} {ts : List SrcType} {ps : List Value},
      exprTys boxes tenv es = some ts → EnvRel P boxes st.heap tenv env st → pexprs env es = some ps →
      ∃ vs, Ev (fun k => evalExprs k P st (es.map SrcExpr.toCore)) vs st
  | [], _, _, _, _, _, _ => ⟨[], exprs_nil_fwd⟩
  | e :: es, st, ts, ps, ht, rel, hp => by
    simp only [exprTys, Option.bind_eq_some_iff, Option.map_eq_some_iff] at ht
    obtain ⟨t, het, ts', hts, rfl⟩ := ht
    simp only [pexprs, Option.bind_eq_some_iff, Option.map_eq_some_iff] at hp
    obtain ⟨p, hpe, ps', hps, rfl⟩ := hp
    obtain ⟨v, hv⟩ := expr_live target tenv env e het rel hpe
    obtain ⟨vs, hvs⟩ := exprs_live target tenv env es hts rel hps
    exact ⟨v :: vs, exprs_cons_fwd hv hvs⟩

end

end Lanius.Faithful
