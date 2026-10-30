import Lanius.Faithful.Sim.State
import Lanius.Faithful.Sim.Scalar

/-! # Pure expressions

A subset expression `exprTy` types, that Core completes on locals meaning
`env`, has a pure value meaning Core's (`expr_sim`). Its evaluation leaves the
state as it was (`SrcExpr.eval_state`). -/

namespace Lanius.Faithful

open Lanius.Mini
open Lanius.Core (Value)
open Lanius.Semantics (State evalExpr evalExprs)

section
variable {P : Core.Program} {boxes : Boxes}

/-- A value of a scalar type means itself. -/
theorem VRel.scalar_ty {heap : Memory.Heap} {t : SrcType} {v p : Value} (r : VRel P boxes heap t v p)
    (scalar : scalarTy t = true) : p = v ∧ STy t v := by
  cases r with
  | scalar s => exact ⟨rfl, s⟩
  | struct => simp [scalarTy] at scalar
  | enum => simp [scalarTy] at scalar
  | box => simp [scalarTy] at scalar

/-- Field `index` of a struct that is not a box means the pure field. -/
theorem VRel.field {heap : Memory.Heap} {t ft : SrcType} {id index : Nat} {fields : List Value} {p x : Value}
    (r : VRel P boxes heap t (.structure id fields) p) (ht : fieldTy boxes t index = some ft)
    (found : fields[index]? = some x) : ∃ q, fieldOf p index = some q ∧ VRel P boxes heap ft x q := by
  cases r with
  | scalar s => rcases sty_cases s with ⟨_, h⟩ | ⟨_, _, h⟩ | ⟨_, _, h⟩ | h <;> cases h
  | struct none rs =>
    simp only [fieldTy, none, Option.isNone_none, if_true] at ht
    obtain ⟨t', q, hf, hq, rq⟩ := rs.get found
    rw [ht] at hf
    cases hf
    exact ⟨q, hq, rq⟩
  | box some => simp [fieldTy, some] at ht

theorem applyOp_binary {op : SrcOp} (notAnd : op ≠ .logicalAnd) (notOr : op ≠ .logicalOr) (l r : Option Value) :
    applyOp op l r = binary op.toCore l r := by
  cases op <;> simp_all [applyOp]

theorem SrcOp.toCore_ne_and {op : SrcOp} (h : op ≠ .logicalAnd) : op.toCore ≠ .logicalAnd :=
  fun e => h (SrcOp.toCore_logicalAnd e)

theorem SrcOp.toCore_ne_or {op : SrcOp} (h : op ≠ .logicalOr) : op.toCore ≠ .logicalOr :=
  fun e => h (SrcOp.toCore_logicalOr e)

theorem opTy_and {tl tr t : SrcType} (h : opTy .logicalAnd tl tr = some t) : t = .bool ∧ tr = .bool := by
  simp only [opTy] at h
  split at h
  · rename_i hb
    simp only [Option.some.injEq] at h
    cases tr <;> simp_all [SrcType.isBool]
  · simp at h

theorem opTy_or {tl tr t : SrcType} (h : opTy .logicalOr tl tr = some t) : t = .bool ∧ tr = .bool := by
  simp only [opTy] at h
  split at h
  · rename_i hb
    simp only [Option.some.injEq] at h
    cases tr <;> simp_all [SrcType.isBool]
  · simp at h

theorem opTy_equal {op : SrcOp} {tl tr t : SrcType} (h : opTy op tl tr = some t) (eq : op = .equal ∨ op = .notEqual) :
    scalarTy tl = true := by
  rcases eq with rfl | rfl <;>
  · simp only [opTy] at h
    split at h
    · rename_i ok
      simp only [Bool.and_eq_true] at ok
      exact ok.1
    · simp at h

/-- Core's binary operator on operands meaning `ql` and `qr`, of types `tl` and `tr`. -/
theorem binary_sim {heap : Memory.Heap} {op : SrcOp} {tl tr t : SrcType} {l r v ql qr : Value}
    (notAnd : op ≠ .logicalAnd) (notOr : op ≠ .logicalOr) (ht : opTy op tl tr = some t)
    (rl : VRel P boxes heap tl l ql) (rr : VRel P boxes heap tr r qr)
    (h : Semantics.evalBinaryValue .x86_64 op.toCore l r = .ok v) :
    applyOp op (some ql) (some qr) = some v ∧ STy t v := by
  have flat := binary_flat h
  have left : ql = l ∧ STy tl l := by
    by_cases eq : op = .equal ∨ op = .notEqual
    · exact rl.scalar_ty (opTy_equal ht eq)
    · apply rl.flat
      apply flat.2 <;> intro e <;> apply eq <;> cases op <;> simp_all [SrcOp.toCore]
  obtain ⟨rfl, sl⟩ := left
  obtain ⟨rfl, -⟩ := rr.flat (flat.1 sl)
  refine ⟨?_, binary_sty sl ht notAnd notOr h⟩
  rw [applyOp_binary notAnd notOr]
  simp only [binary, Option.bind_some, target, h]
  rfl

/-- A pure expression: Core's value means `pexpr`'s. -/
theorem expr_sim (target : P.target = .x86_64) (tenv : TEnv) (env : Env) (e : SrcExpr) :
    ∀ {k : Nat} {st : State} {v : Value} {st' : State} {t : SrcType},
      evalExpr k P st e.toCore = .done v st' → exprTy boxes tenv e = some t →
      EnvRel P boxes st.heap tenv env st →
      ∃ p, pexpr env e = some p ∧ VRel P boxes st.heap t v p := by
  induction e with
  | int value =>
    intro k st v st' t run ht rel
    obtain ⟨rfl, -⟩ := value_inv run
    simp only [exprTy, Option.some.injEq] at ht
    subst ht
    exact ⟨_, rfl, .scalar ⟨_, rfl, BitVec.le_toInt value, BitVec.toInt_lt⟩⟩
  | boolean value =>
    intro k st v st' t run ht rel
    obtain ⟨rfl, -⟩ := value_inv run
    simp only [exprTy, Option.some.injEq] at ht
    subst ht
    exact ⟨_, rfl, .scalar ⟨_, rfl⟩⟩
  | unsigned kind value =>
    intro k st v st' t run ht rel
    obtain ⟨rfl, -⟩ := value_inv run
    simp only [exprTy] at ht
    split at ht
    · rename_i lt
      simp only [Option.some.injEq] at ht
      subst ht
      exact ⟨_, rfl, .scalar ⟨_, rfl, lt⟩⟩
    · simp at ht
  | «local» id =>
    intro k st v st' t run ht rel
    obtain ⟨found, -⟩ := local_inv run
    obtain ⟨v', p, hv, hp, r⟩ := rel id t ht
    rw [found, Option.some.injEq] at hv
    subst hv
    exact ⟨p, hp, r⟩
  | field id index =>
    intro k st v st' t run ht rel
    obtain ⟨j, sid, fields, -, base, found⟩ := field_inv run
    obtain ⟨hl, -⟩ := local_inv base
    simp only [exprTy, Option.bind_eq_some_iff] at ht
    obtain ⟨tl, htl, hft⟩ := ht
    obtain ⟨v', p, hv, hp, r⟩ := rel id tl htl
    rw [hl, Option.some.injEq] at hv
    subst hv
    obtain ⟨q, hq, rq⟩ := r.field hft found
    exact ⟨q, by simp only [pexpr, hp, Option.bind_some, hq], rq⟩
  | negate operand ih =>
    intro k st v st' t run ht rel
    obtain ⟨j, w, -, sub, hw⟩ := unary_inv run
    simp only [exprTy, Option.bind_eq_some_iff] at ht
    obtain ⟨to, hto, hn⟩ := ht
    obtain ⟨rfl, -⟩ := numOf_some hn
    obtain ⟨q, hq, rq⟩ := ih sub hto rel
    obtain ⟨rfl, sw⟩ := rq.flat (unary_flat hw)
    rw [target] at hw
    refine ⟨v, ?_, .scalar (neg_sty sw hw)⟩
    simp only [pexpr, hq, Option.bind_some, unary, Lanius.Faithful.target, hw]
    rfl
  | «not» operand ih =>
    intro k st v st' t run ht rel
    obtain ⟨j, w, -, sub, hw⟩ := unary_inv run
    simp only [exprTy, Option.bind_eq_some_iff] at ht
    obtain ⟨to, hto, hb⟩ := ht
    obtain ⟨rfl, -⟩ := boolOf_some hb
    obtain ⟨q, hq, rq⟩ := ih sub hto rel
    obtain ⟨rfl, -⟩ := rq.flat (unary_flat hw)
    rw [target] at hw
    refine ⟨v, ?_, .scalar (not_sty hw)⟩
    simp only [pexpr, hq, Option.bind_some, unary, Lanius.Faithful.target, hw]
    rfl
  | apply op left right ihl ihr =>
    intro k st v st' t run ht rel
    simp only [exprTy, Option.bind_eq_some_iff] at ht
    obtain ⟨tl, htl, tr, htr, ht⟩ := ht
    by_cases isAnd : op = .logicalAnd
    · subst isAnd
      obtain ⟨rfl, rfl⟩ := opTy_and ht
      obtain ⟨j, s1, x, -, lrun, rest⟩ := logicalAnd_inv run
      have := left.eval_state lrun
      subst this
      obtain ⟨ql, hql, rl⟩ := ihl lrun htl rel
      rw [rl.boolean] at hql
      rcases rest with ⟨rfl, rfl, rfl⟩ | ⟨rfl, rrun⟩
      · exact ⟨_, by simp [pexpr, applyOp, hql, asBool], .scalar ⟨_, rfl⟩⟩
      · obtain ⟨qr, hqr, rr⟩ := ihr rrun htr rel
        exact ⟨qr, by simp [pexpr, applyOp, hql, asBool, hqr], rr⟩
    by_cases isOr : op = .logicalOr
    · subst isOr
      obtain ⟨rfl, rfl⟩ := opTy_or ht
      obtain ⟨j, s1, x, -, lrun, rest⟩ := logicalOr_inv run
      have := left.eval_state lrun
      subst this
      obtain ⟨ql, hql, rl⟩ := ihl lrun htl rel
      rw [rl.boolean] at hql
      rcases rest with ⟨rfl, rfl, rfl⟩ | ⟨rfl, rrun⟩
      · exact ⟨_, by simp [pexpr, applyOp, hql, asBool], .scalar ⟨_, rfl⟩⟩
      · obtain ⟨qr, hqr, rr⟩ := ihr rrun htr rel
        exact ⟨qr, by simp [pexpr, applyOp, hql, asBool, hqr], rr⟩
    obtain ⟨j, l, s1, r, -, lrun, rrun, hv⟩ :=
      binary_inv (SrcOp.toCore_ne_and isAnd) (SrcOp.toCore_ne_or isOr) run
    have := left.eval_state lrun
    subst this
    obtain ⟨ql, hql, rl⟩ := ihl lrun htl rel
    obtain ⟨qr, hqr, rr⟩ := ihr rrun htr rel
    rw [target] at hv
    obtain ⟨happ, sv⟩ := binary_sim isAnd isOr ht rl rr hv
    exact ⟨v, by simp only [pexpr, hql, hqr, happ], .scalar sv⟩
  | cast ty operand ih =>
    intro k st v st' t run ht rel
    obtain ⟨j, w, -, sub, hw⟩ := cast_inv run
    simp only [exprTy, Option.bind_eq_some_iff] at ht
    obtain ⟨to, hto, hc⟩ := ht
    obtain ⟨rfl, -, numTo⟩ := castTy_some hc
    obtain ⟨q, hq, rq⟩ := ih sub hto rel
    obtain ⟨rfl, sw⟩ := rq.flat (cast_flat hw)
    rw [target] at hw
    refine ⟨v, ?_, .scalar (cast_sty sw numTo hw)⟩
    simp only [pexpr, hq, Option.bind_some, cast, Lanius.Faithful.target, hw]
    rfl
  | null =>
    intro k st v st' t run ht rel
    simp [exprTy] at ht

theorem exprs_sim (target : P.target = .x86_64) (tenv : TEnv) (env : Env) :
    ∀ (es : List SrcExpr) {k : Nat} {st : State} {vs : List Value} {st' : State} {ts : List SrcType},
      evalExprs k P st (es.map SrcExpr.toCore) = .done vs st' → exprTys boxes tenv es = some ts →
      EnvRel P boxes st.heap tenv env st →
      ∃ ps, pexprs env es = some ps ∧ VRels P boxes st.heap ts vs ps
  | [], k, st, vs, st', ts, run, ht, rel => by
    obtain ⟨rfl, -⟩ := exprs_nil_inv run
    simp only [exprTys, Option.some.injEq] at ht
    subst ht
    exact ⟨[], rfl, .nil⟩
  | e :: es, k, st, vs, st', ts, run, ht, rel => by
    obtain ⟨j, v, s1, rest, -, erun, esrun, rfl⟩ := exprs_cons_inv run
    have := e.eval_state erun
    subst this
    simp only [exprTys, Option.bind_eq_some_iff, Option.map_eq_some_iff] at ht
    obtain ⟨t, het, ts', hts, rfl⟩ := ht
    obtain ⟨p, hp, r⟩ := expr_sim target tenv env e erun het rel
    obtain ⟨ps, hps, rs⟩ := exprs_sim target tenv env es esrun hts rel
    exact ⟨p :: ps, by simp [pexprs, hp, hps], .cons r rs⟩

end

end Lanius.Faithful
