import Lanius.Faithful.Sim.Expr
import Lanius.Faithful.Safe.Inv
import Lanius.Faithful.Safe.Value

/-! # Pure expressions do not trap undefined

A subset expression `exprTy` types, on locals that mean `env`, that Core
traps on: the trap is a defined one, at the state Core started from
(`expr_safe`). -/

namespace Lanius.Faithful

open Lanius.Mini
open Lanius.Core (Value)
open Lanius.Semantics (State evalExpr evalExprs)

theorem numTy_scalar {t : SrcType} (h : numTy t = true) : scalarTy t = true := by
  cases t <;> simp_all [numTy, scalarTy]

theorem opTy_bools {op : SrcOp} {tl tr t : SrcType} (h : opTy op tl tr = some t) (and : op = .logicalAnd ∨ op = .logicalOr) :
    tl = .bool ∧ tr = .bool ∧ t = .bool := by
  rcases and with rfl | rfl <;>
  · simp only [opTy] at h
    split at h
    · rename_i ok
      simp only [Bool.and_eq_true] at ok
      simp only [Option.some.injEq] at h
      exact ⟨SrcType.isBool_eq ok.1, SrcType.isBool_eq ok.2, h.symm⟩
    · simp at h

/-- The operands' types of a binary operator the checker accepts are scalar. -/
theorem opTy_scalar {op : SrcOp} {tl tr t : SrcType} (h : opTy op tl tr = some t) : scalarTy tl = true := by
  by_cases b : op = .logicalAnd ∨ op = .logicalOr
  · rw [(opTy_bools h b).1]; rfl
  · have notAnd : op ≠ .logicalAnd := fun e => b (.inl e)
    have notOr : op ≠ .logicalOr := fun e => b (.inr e)
    rcases (opTy_same h notAnd notOr).2 with rfl | rfl | n
    · exact opTy_equal h (.inl rfl)
    · exact opTy_equal h (.inr rfl)
    · exact numTy_scalar n

section
variable {P : Core.Program} {boxes : Boxes}

/-- A value of a type with field `index` is a struct with that field. -/
theorem VRel.field_some {heap : Memory.Heap} {t ft : SrcType} {index : Nat} {v p : Value}
    (r : VRel P boxes heap t v p) (ht : fieldTy boxes t index = some ft) :
    ∃ sid fields x, v = .structure sid fields ∧ fields[index]? = some x := by
  cases r with
  | scalar s => rcases sty_cases s with ⟨_, rfl⟩ | ⟨_, _, rfl⟩ | ⟨_, _, rfl⟩ | rfl <;> cases t <;> simp_all [fieldTy, STy]
  | struct none rs =>
    rename_i sid fs vs ps
    simp only [fieldTy, none, Option.isNone_none, if_true] at ht
    have lt : index < vs.length := by
      rw [rs.length.1]; exact (List.getElem?_eq_some_iff.mp ht).1
    exact ⟨sid, vs, vs[index], rfl, List.getElem?_eq_getElem lt⟩
  | enum => simp [fieldTy] at ht
  | box some => simp [fieldTy, some] at ht

/-- The value of a pure expression of a scalar type is that type's. -/
theorem expr_sty (target : P.target = .x86_64) {tenv : TEnv} {env : Env} {e : SrcExpr} {k : Nat} {st st' : State}
    {v : Value} {t : SrcType} (run : evalExpr k P st e.toCore = .done v st') (ht : exprTy boxes tenv e = some t)
    (rel : EnvRel P boxes st.heap tenv env st) (scalar : scalarTy t = true) : STy t v := by
  obtain ⟨p, -, r⟩ := expr_sim target tenv env e run ht rel
  exact (r.scalar_ty scalar).2

/-- A pure expression that traps does so at the state it started from, with
a defined trap. -/
theorem expr_safe (target : P.target = .x86_64) (tenv : TEnv) (env : Env) (e : SrcExpr) :
    ∀ {k : Nat} {st : State} {r : Lanius.Trap} {st' : State} {t : SrcType},
      evalExpr k P st e.toCore = .trapped r st' → exprTy boxes tenv e = some t →
      EnvRel P boxes st.heap tenv env st → st' = st ∧ undefinedTrap r = false := by
  induction e with
  | int value => intro k st r st' t run; exact (value_trap run).elim
  | boolean value => intro k st r st' t run; exact (value_trap run).elim
  | unsigned kind value => intro k st r st' t run; exact (value_trap run).elim
  | «local» id =>
    intro k st r st' t run ht rel
    obtain ⟨v', p, hv, -, -⟩ := rel id t ht
    exact (local_trap hv run).elim
  | field id index =>
    intro k st r st' t run ht rel
    simp only [exprTy, Option.bind_eq_some_iff] at ht
    obtain ⟨tl, htl, hft⟩ := ht
    obtain ⟨v', p, hv, -, rv⟩ := rel id tl htl
    obtain ⟨sid, fields, x, rfl, found⟩ := rv.field_some hft
    exact (field_local_trap hv found run).elim
  | negate operand ih =>
    intro k st r st' t run ht rel
    simp only [exprTy, Option.bind_eq_some_iff] at ht
    obtain ⟨to, hto, hn⟩ := ht
    obtain ⟨rfl, num⟩ := numOf_some hn
    obtain ⟨j, -, sub | ⟨w, sub, bad⟩⟩ := unary_trap_inv run
    · exact ih sub hto rel
    · rw [target] at bad
      exact (neg_ok num (expr_sty target sub hto rel (numTy_scalar num)) bad).elim
  | «not» operand ih =>
    intro k st r st' t run ht rel
    simp only [exprTy, Option.bind_eq_some_iff] at ht
    obtain ⟨to, hto, hb⟩ := ht
    obtain ⟨rfl, rfl⟩ := boolOf_some hb
    obtain ⟨j, -, sub | ⟨w, sub, bad⟩⟩ := unary_trap_inv run
    · exact ih sub hto rel
    · exact (not_ok (expr_sty target sub hto rel rfl) bad).elim
  | apply op left right ihl ihr =>
    intro k st r st' t run ht rel
    simp only [exprTy, Option.bind_eq_some_iff] at ht
    obtain ⟨tl, htl, tr, htr, ht⟩ := ht
    by_cases isAnd : op = .logicalAnd
    · subst isAnd
      obtain ⟨rfl, rfl, rfl⟩ := opTy_bools ht (.inl rfl)
      obtain ⟨j, -, lrun | ⟨l, lrun, notBool, -⟩ | ⟨s1, lrun, rrun⟩⟩ := logicalAnd_trap_inv run
      · exact ihl lrun htl rel
      · obtain ⟨b, rfl⟩ := expr_sty target lrun htl rel rfl
        exact (notBool b rfl).elim
      · have := left.eval_state lrun
        subst this
        exact ihr rrun htr rel
    by_cases isOr : op = .logicalOr
    · subst isOr
      obtain ⟨rfl, rfl, rfl⟩ := opTy_bools ht (.inr rfl)
      obtain ⟨j, -, lrun | ⟨l, lrun, notBool, -⟩ | ⟨s1, lrun, rrun⟩⟩ := logicalOr_trap_inv run
      · exact ihl lrun htl rel
      · obtain ⟨b, rfl⟩ := expr_sty target lrun htl rel rfl
        exact (notBool b rfl).elim
      · have := left.eval_state lrun
        subst this
        exact ihr rrun htr rel
    obtain ⟨j, -, lrun | ⟨l, s1, lrun, rrun | ⟨rv, rrun, bad⟩⟩⟩ :=
      binary_trap_inv (SrcOp.toCore_ne_and isAnd) (SrcOp.toCore_ne_or isOr) run
    · exact ihl lrun htl rel
    · have := left.eval_state lrun
      subst this
      exact ihr rrun htr rel
    · have := left.eval_state lrun
      subst this
      have := right.eval_state rrun
      subst this
      have sl := opTy_scalar ht
      obtain ⟨rfl, -⟩ := opTy_same ht isAnd isOr
      rw [target] at bad
      exact ⟨rfl, binary_defined ht isAnd isOr (expr_sty target lrun htl rel sl) (expr_sty target rrun htr rel sl) bad⟩
  | cast ty operand ih =>
    intro k st r st' t run ht rel
    simp only [exprTy, Option.bind_eq_some_iff] at ht
    obtain ⟨to, hto, hc⟩ := ht
    obtain ⟨rfl, num, numTo⟩ := castTy_some hc
    obtain ⟨j, -, sub | ⟨w, sub, bad⟩⟩ := cast_trap_inv run
    · exact ih sub hto rel
    · rw [target] at bad
      exact (cast_ok num numTo (expr_sty target sub hto rel (numTy_scalar num)) bad).elim
  | null =>
    intro k st r st' t run ht rel
    simp [exprTy] at ht

theorem exprs_safe (target : P.target = .x86_64) (tenv : TEnv) (env : Env) :
    ∀ (es : List SrcExpr) {k : Nat} {st : State} {r : Lanius.Trap} {st' : State} {ts : List SrcType},
      evalExprs k P st (es.map SrcExpr.toCore) = .trapped r st' → exprTys boxes tenv es = some ts →
      EnvRel P boxes st.heap tenv env st → st' = st ∧ undefinedTrap r = false
  | [], k, st, r, st', ts, run, ht, rel => (exprs_nil_trap run).elim
  | e :: es, k, st, r, st', ts, run, ht, rel => by
    simp only [exprTys, Option.bind_eq_some_iff, Option.map_eq_some_iff] at ht
    obtain ⟨t, het, ts', hts, rfl⟩ := ht
    obtain ⟨j, -, erun | ⟨v, s1, erun, esrun⟩⟩ := exprs_cons_trap_inv run
    · exact expr_safe target tenv env e erun het rel
    · have := e.eval_state erun
      subst this
      exact exprs_safe target tenv env es esrun hts rel

end

end Lanius.Faithful
