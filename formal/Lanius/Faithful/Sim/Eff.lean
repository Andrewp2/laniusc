import Lanius.Faithful.Sim.Expr
import Lanius.Faithful.Sim.Mono

/-! # Effectful expressions

An effectful expression `effTy` types, that Core completes, has the pure
value of `peff` with calls `pcall N`, when Core's calls of its callees with
less fuel have the pure values `pcall` gives them (`FuncSim`). This file has
the definitions, the facts each case uses, and the arms of a `match`. -/

namespace Lanius.Faithful

open Lanius.Mini
open Lanius.Core (Value)
open Lanius.Semantics (State Completion evalExpr evalExprs evalMatchArms execStmt restoreLocals matchPattern
  matchPatterns)

/-- What a completed run kept: the invariant, the cells and heap reads, the locals. -/
structure Ran (st st' : State) : Prop where
  inv : Inv st'
  step : Step st st'
  locals : st'.locals = st.locals

theorem Ran.refl {st : State} (inv : Inv st) : Ran st st := ⟨inv, Step.refl st, rfl⟩

theorem Ran.trans {a b c : State} (first : Ran a b) (second : Ran b c) : Ran a c :=
  ⟨second.inv, first.step.trans second.step, second.locals.trans first.locals⟩

section
variable (sp : SrcProgram) (prims : Prims) (outside : List Nat)

/-- Core runs a callee's body with fuel `m` as `pcall (m + 1)` says it calls. -/
def FuncSim (m : Nat) : Prop :=
  ∀ {c : Nat} {f : SrcFunc} {values ps : List Value} {st completed : State} {compl : Completion} {v : Value},
    sp.funcs[c]? = some f → outside.contains c = false → values.length = f.params.length → Inv st →
    completed.heap.nextAddress ≤ 2 ^ 64 →
    VRels sp.toCore (boxElem sp prims) st.heap (f.params.map SrcParam.ty) values ps →
    execStmt m sp.toCore (({ st with locals := [] } : State).bindLocals (paramBindings f.params values))
      f.body.toCore = .done compl completed →
    CallResult f.ret compl v →
    ∃ w, pcall sp prims (m + 1) c ps = some w ∧ VRel sp.toCore (boxElem sp prims) completed.heap f.ret v w ∧
      Inv completed ∧ Step st completed

/-- Effectful expressions Core completes with fuel `k`. -/
def EffOk (N k : Nat) : Prop :=
  ∀ {tenv : TEnv} {env : Env} {st : State} {e : SrcEff} {v : Value} {st' : State} {t : SrcType},
    evalExpr k sp.toCore st e.toCore = .done v st' → effTy sp outside (boxElem sp prims) tenv e = some t →
    Inv st → EnvRel sp.toCore (boxElem sp prims) st.heap tenv env st → st'.heap.nextAddress ≤ 2 ^ 64 →
    ∃ p, peff (pcall sp prims N) env e = some p ∧ VRel sp.toCore (boxElem sp prims) st'.heap t v p ∧ Ran st st'

def EffsOk (N k : Nat) : Prop :=
  ∀ {tenv : TEnv} {env : Env} {st : State} {es : List SrcEff} {vs : List Value} {st' : State}
    {ts : List SrcType},
    evalExprs k sp.toCore st (SrcEff.toCoreList es) = .done vs st' →
    effTys sp outside (boxElem sp prims) tenv es = some ts →
    Inv st → EnvRel sp.toCore (boxElem sp prims) st.heap tenv env st → st'.heap.nextAddress ≤ 2 ^ 64 →
    ∃ ps, peffs (pcall sp prims N) env es = some ps ∧ VRels sp.toCore (boxElem sp prims) st'.heap ts vs ps ∧
      Ran st st'

/-- The arms from arm `j` on, of a `match` on variant `kk`, whose payload
types are those of `variants` from `j` on. -/
def ArmsOk (N k : Nat) : Prop :=
  ∀ {tenv : TEnv} {env : Env} {st : State} {id kk j : Nat} {vs ps : List Value} {fs : List SrcType}
    {rty : SrcType} {variants : List (List SrcType)} {binders : List (List Nat)} {values : List SrcEff}
    {v : Value} {st' : State},
    evalMatchArms k sp.toCore st (.enumeration id kk vs) (SrcEff.coreArms id j binders values) = .done v st' →
    j ≤ kk → variants[kk - j]? = some fs → VRels sp.toCore (boxElem sp prims) st.heap fs vs ps →
    armsOk sp outside (boxElem sp prims) tenv rty variants binders values = true →
    Inv st → EnvRel sp.toCore (boxElem sp prims) st.heap tenv env st → st'.heap.nextAddress ≤ 2 ^ 64 →
    ∃ p, parms (pcall sp prims N) env (.enumeration id kk ps) id j binders values = some p ∧
      VRel sp.toCore (boxElem sp prims) st'.heap rty v p ∧ Ran st st'

end

/-! ## Facts the cases use -/

private theorem matchPatterns_binds : ∀ (bs : List Nat) (vs : List Value),
    matchPatterns (bs.map .bind) vs = if bs.length = vs.length then some (bs.zip vs) else none
  | [], [] => by simp [matchPatterns]
  | [], _ :: _ => by simp [matchPatterns]
  | _ :: _, [] => by simp [matchPatterns]
  | b :: bs, v :: vs => by
    simp only [List.map_cons, matchPatterns, matchPattern, matchPatterns_binds bs vs, List.length_cons,
      Nat.add_right_cancel_iff, List.zip_cons_cons]
    by_cases h : bs.length = vs.length <;> simp [h]

theorem matchPattern_variant (id j kk : Nat) (bs : List Nat) (vs : List Value) :
    matchPattern (.enumVariant id j (bs.map .bind)) (.enumeration id kk vs) =
      if j = kk ∧ bs.length = vs.length then some (bs.zip vs) else none := by
  simp only [matchPattern, beq_self_eq_true, Bool.true_and, matchPatterns_binds]
  by_cases same : j = kk
  · subst same; simp
  · simp [same]

theorem VRel.enum_inv {P : Core.Program} {boxes : Boxes} {heap : Memory.Heap} {id : Nat}
    {variants : List (List SrcType)} {v q : Value} (r : VRel P boxes heap (.enum id variants) v q) :
    ∃ kk fs vs ps, v = .enumeration id kk vs ∧ q = .enumeration id kk ps ∧ variants[kk]? = some fs ∧
      VRels P boxes heap fs vs ps := by
  cases r with
  | scalar s => exact s.elim
  | enum hk rs => exact ⟨_, _, _, _, rfl, rfl, hk, rs⟩

theorem callTy_some {sp : SrcProgram} {outside : List Nat} {callee : Nat} {ts : List SrcType} {t : SrcType}
    (h : callTy sp outside callee ts = some t) :
    outside.contains callee = false ∧ ∃ f, sp.funcs[callee]? = some f ∧ ts = f.params.map SrcParam.ty ∧ t = f.ret := by
  simp only [callTy] at h
  split at h
  · simp at h
  · rename_i notOutside
    refine ⟨by simpa using notOutside, ?_⟩
    split at h
    · rename_i f found
      split at h
      · rename_i same
        simp only [Option.some.injEq] at h
        exact ⟨f, found, typesSame_eq _ same, h.symm⟩
      · simp at h
    · simp at h

theorem structTy_some {boxes : Boxes} {ty t : SrcType} {ts : List SrcType} (h : structTy boxes ty ts = some t) :
    ∃ id, ty = .struct id ts ∧ boxes id = none ∧ t = ty := by
  cases ty with
  | struct id fs =>
    simp only [structTy] at h
    split at h
    · rename_i ok
      simp only [Bool.and_eq_true, Option.isNone_iff_eq_none] at ok
      simp only [Option.some.injEq] at h
      rw [typesSame_eq _ ok.2]
      exact ⟨id, rfl, ok.1, h.symm⟩
    · simp at h
  | i32 => simp [structTy] at h
  | bool => simp [structTy] at h
  | uint => simp [structTy] at h
  | enum => simp [structTy] at h
  | ptr => simp [structTy] at h
  | slice => simp [structTy] at h
  | unit => simp [structTy] at h
  | isize => simp [structTy] at h

theorem variantTy_some {ty t : SrcType} {k : Nat} {ts : List SrcType} (h : variantTy ty k ts = some t) :
    ∃ id variants, ty = .enum id variants ∧ variants[k]? = some ts ∧ t = ty := by
  cases ty with
  | enum id variants =>
    simp only [variantTy] at h
    split at h
    · rename_i fs found
      split at h
      · rename_i same
        simp only [Option.some.injEq] at h
        rw [typesSame_eq _ same] at *
        exact ⟨id, variants, rfl, found, h.symm⟩
      · simp at h
    · simp at h
  | i32 => simp [variantTy] at h
  | bool => simp [variantTy] at h
  | uint => simp [variantTy] at h
  | struct => simp [variantTy] at h
  | ptr => simp [variantTy] at h
  | slice => simp [variantTy] at h
  | unit => simp [variantTy] at h
  | isize => simp [variantTy] at h

/-- A state between two that grow is below the later one's cursor. -/
theorem Grows.bound {a b c : State} (first : Grows a b) (second : Grows b c) (views : a.i32ArrayViews = [])
    (bound : c.heap.nextAddress ≤ 2 ^ 64) : b.heap.nextAddress ≤ 2 ^ 64 :=
  Nat.le_trans (second (first views).1).2 bound

theorem effGrows {sp : SrcProgram} {k : Nat} {st st' : State} {e : SrcEff} {v : Value}
    (run : evalExpr k sp.toCore st e.toCore = .done v st') : Grows st st' :=
  eff_grows k (grows sp k) k (Nat.le_refl k) run

theorem effsGrows {sp : SrcProgram} {k : Nat} {st st' : State} {es : List SrcEff} {vs : List Value}
    (run : evalExprs k sp.toCore st (SrcEff.toCoreList es) = .done vs st') : Grows st st' :=
  effs_grows es (eff_grows k (grows sp k)) run

theorem toCore_target (sp : SrcProgram) : sp.toCore.target = .x86_64 := rfl

/-! ## Lists and arms -/

section
variable {sp : SrcProgram} {prims : Prims} {outside : List Nat} {N k : Nat}

theorem effs_step (eff : EffOk sp prims outside N k) (effs : EffsOk sp prims outside N k) :
    EffsOk sp prims outside N (k + 1) := by
  intro tenv env st es vs st' ts run ht inv rel bound
  cases es with
  | nil =>
    obtain ⟨rfl, rfl⟩ := exprs_nil_inv run
    simp only [effTys, Option.some.injEq] at ht
    subst ht
    exact ⟨[], rfl, .nil, .refl inv⟩
  | cons e es =>
    obtain ⟨j, v, s1, rest, hj, erun, esrun, rfl⟩ := exprs_cons_inv run
    obtain rfl : j = k := by omega
    simp only [effTys, Option.bind_eq_some_iff, Option.map_eq_some_iff] at ht
    obtain ⟨t, het, ts', hts, rfl⟩ := ht
    have b1 := Grows.bound (effGrows erun) (effsGrows esrun) inv.views bound
    obtain ⟨p, hp, r, ran1⟩ := eff erun het inv rel b1
    obtain ⟨ps, hps, rs, ran2⟩ := effs esrun hts ran1.inv (rel.step ran1.step ran1.locals) bound
    exact ⟨p :: ps, by simp [peffs, hp, hps], .cons (r.mono ran2.step.reads) rs, ran1.trans ran2⟩

theorem arms_step (eff : EffOk sp prims outside N k) (arms : ArmsOk sp prims outside N k) :
    ArmsOk sp prims outside N (k + 1) := by
  intro tenv env st id kk j vs ps fs rty variants binders values v st' run le hfs rs ok inv rel bound
  cases binders with
  | nil => simp only [SrcEff.coreArms] at run; exact (arms_nil_inv run).elim
  | cons bs rest =>
  cases values with
  | nil => simp only [SrcEff.coreArms] at run; exact (arms_nil_inv run).elim
  | cons value values =>
  cases variants with
  | nil => simp [armsOk] at ok
  | cons fs0 vrest =>
  simp only [armsOk, Bool.and_eq_true, beq_iff_eq] at ok
  obtain ⟨⟨len, hval⟩, okRest⟩ := ok
  simp only [SrcEff.coreArms] at run
  obtain ⟨j', hj, alt⟩ := arms_cons_inv run
  obtain rfl : j' = k := by omega
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
      obtain ⟨p, hp, r, ran⟩ := eff vrun het (inv.bindLocals _) rel' bound
      rw [SrcType.same_eq hval] at r
      refine ⟨p, ?_, r, ⟨ran.inv.restore st, (Step.bindLocals _ st).trans ran.step |>.restore st, rfl⟩⟩
      have pm := matchPattern_variant id j j bs ps
      simp only [true_and, len, lens.2, if_true] at pm
      simp only [parms, pm]
      exact hp
    · simp at hval
  · have lt : j < kk := by omega
    have none := matchPattern_variant id j kk bs vs
    simp only [same, false_and, if_false] at none
    rcases alt with ⟨-, rest'⟩ | ⟨bs', s2, hbs, -, -⟩
    · have hfs' : vrest[kk - (j + 1)]? = some fs := by
        rw [show kk - j = (kk - (j + 1)) + 1 by omega, List.getElem?_cons_succ] at hfs
        exact hfs
      obtain ⟨p, hp, r, ran⟩ := arms rest' lt hfs' rs okRest inv rel bound
      refine ⟨p, ?_, r, ran⟩
      have pm := matchPattern_variant id j kk bs ps
      simp only [same, false_and, if_false] at pm
      simp only [parms, pm]
      exact hp
    · rw [none] at hbs; cases hbs

end

end Lanius.Faithful
