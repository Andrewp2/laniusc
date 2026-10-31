import Lanius.Mini.Reading.Method

/-! # The reading, V8d: effectful expression types, arguments and paths

`EffTy decls scope x t`: the type of an effectful expression, as type
arguments are inferred from it (a call's is its instance's result type,
`InstRet`). A path's prefix names a type (`TypeOwner`) when it is one
segment, a type parameter, a primitive type or a type of the current
module; the calls themselves are
read in `Reading/Effs`. -/

namespace Lanius.Mini.Reading

open Lanius.Mini Lanius.Mini.Prod

/-! ## Result types and effectful expression types -/

/-- The result type of a function instance: the last type argument of a
diverging one, its declared result type at its type arguments, or a
projection's field type. -/
inductive InstRet (decls : Decls) (inst : Inst) : Ty → Prop
  | diverge {fd : FnDecl} {t : Ty} : decls.fns[inst.decl]? = some fd → diverges fd inst = true →
      lastTy inst.args = some t → InstRet decls inst t
  | ret {fd : FnDecl} {r : CTree} {t : Ty} : decls.fns[inst.decl]? = some fd → diverges fd inst = false →
      RetPattern fd r → TyR (declScope decls fd.home (fd.implParams ++ fd.params) inst.args) r t → InstRet decls inst t
  | projection {a : Ty} {rest : List Ty} {d : Nat} {args ts : List Ty} {t : Ty} : decls.fns[inst.decl]? = none →
      inst.args = a :: rest → a = .tyNamed d args → FieldTys decls d args ts → ts[inst.decl - decls.fns.length]? = some t →
      InstRet decls inst t

inductive EffTy (decls : Decls) (scope : List Local) : MEff → Ty → Prop
  | pure {e : SrcExpr} {t : Ty} : ExprTy decls scope e t → EffTy decls scope (.xPure e) t
  | call {inst : Inst} {args : List MEff} {t : Ty} : InstRet decls inst t → EffTy decls scope (.xCall inst args) t
  | compare {op : SrcOp} {l r : MEff} : givesBool op = true → EffTy decls scope (.xApply op l r) .tyBool
  | left {op : SrcOp} {l r : MEff} {t : Ty} : givesBool op = false → bareEff l = false → EffTy decls scope l t →
      EffTy decls scope (.xApply op l r) t
  | right {op : SrcOp} {l r : MEff} {t : Ty} : givesBool op = false → bareEff l = true → EffTy decls scope r t →
      EffTy decls scope (.xApply op l r) t
  | neg {a : MEff} {t : Ty} : EffTy decls scope a t → EffTy decls scope (.xNeg a) t
  | not {a : MEff} : EffTy decls scope (.xNot a) .tyBool
  | cast {s : SrcType} {a : MEff} {t : Ty} : ScalarTy t s → EffTy decls scope (.xCast s a) t
  | index {s : Nat} {i : MEff} {l : Local} {t : Ty} : LocalWithId scope s l → l.ty = .tySlice t →
      EffTy decls scope (.xIndex s i) t
  | struct {t : Ty} {fs : List MEff} : EffTy decls scope (.xStruct t fs) t
  | variant {t : Ty} {k : Nat} {ps : List MEff} : EffTy decls scope (.xVariant t k ps) t
  | «match» {s : MEff} {ety t : Ty} {bs : List (List Nat)} {vs : List MEff} : EffTy decls scope (.xMatch s ety t bs vs) t
  | divideLeft {op : SrcDivOp} {l r : MEff} {t : Ty} : bareEff l = false → EffTy decls scope l t →
      EffTy decls scope (.xDivide op l r) t
  | divideRight {op : SrcDivOp} {l r : MEff} {t : Ty} : bareEff l = true → EffTy decls scope r t →
      EffTy decls scope (.xDivide op l r) t
  | stride {sl : Nat} : EffTy decls scope (.xStride sl) .tyIsize

theorem instRet_sound {fuel : Nat} {decls : Decls} {inst : Inst} {t : Ty} (h : instRet fuel decls inst = some t) :
    InstRet decls inst t := by
  unfold instRet at h
  cases hf : decls.fns[inst.decl]? with
  | some fd =>
    rw [hf] at h
    simp only [fnInstRet] at h
    by_cases dv : diverges fd inst = true
    · rw [if_pos dv] at h
      exact .diverge hf dv h
    · rw [if_neg dv] at h
      cases hr : retPattern fd with
      | none => rw [hr] at h; cases h
      | some r =>
        rw [hr] at h
        exact .ret hf (by simpa using dv) (retPattern_sound hr) (tyOf_sound h)
  | none =>
    rw [hf] at h
    simp only [projectionRet] at h
    cases ha : inst.args with
    | nil => rw [ha] at h; cases h
    | cons a rest =>
      rw [ha] at h
      simp only at h
      cases hs : structFieldTys fuel decls a with
      | none => rw [hs] at h; cases h
      | some ts =>
        rw [hs] at h
        simp only at h
        unfold structFieldTys at hs
        cases a with
        | tyNamed d args => exact .projection hf ha rfl (fieldTys_sound hs) h
        | tyI32 => cases hs
        | tyBool => cases hs
        | tyUint _ => cases hs
        | tyPtr => cases hs
        | tyIsize => cases hs
        | tyChar => cases hs
        | tySint _ => cases hs
        | tySlice _ => cases hs

theorem effTy_sound : ∀ {fuel : Nat} {env : FrontEnv} {scope : List Local} {x : MEff} {t : Ty},
    effTy fuel env scope x = some t → EffTy env.decls scope x t
  | 0, _, _, _, _, h => by rw [effTy.eq_def] at h; simp at h
  | f + 1, env, scope, x, t, h => by
    rw [effTy.eq_def] at h
    simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
    cases x with
    | xPure e => exact .pure (exprTy_sound h)
    | xCall inst args => exact .call (instRet_sound h)
    | xApply op l r =>
      simp only [applyTy] at h
      by_cases g : givesBool op = true
      · rw [if_pos g, Option.some.injEq] at h
        subst h
        exact .compare g
      · rw [if_neg g] at h
        have g' : givesBool op = false := by simpa using g
        simp only [pickTy] at h
        by_cases bl : bareEff l = true
        · rw [if_pos bl] at h
          exact .right g' bl (effTy_sound h)
        · rw [if_neg bl] at h
          exact .left g' (by simpa using bl) (effTy_sound h)
    | xNeg a => exact .neg (effTy_sound h)
    | xNot a => cases h; exact .not
    | xCast s a => exact .cast (srcTy_sound h)
    | xIndex s i =>
      simp only [indexTy] at h
      cases hl : findLocalId scope s with
      | none => rw [hl] at h; cases h
      | some l =>
        rw [hl] at h
        simp only at h
        unfold sliceElem at h
        cases hty : l.ty with
        | tySlice e => rw [hty] at h; cases h; exact .index (findLocalId_sound hl) hty
        | tyI32 => rw [hty] at h; cases h
        | tyBool => rw [hty] at h; cases h
        | tyUint _ => rw [hty] at h; cases h
        | tyPtr => rw [hty] at h; cases h
        | tyIsize => rw [hty] at h; cases h
        | tyChar => rw [hty] at h; cases h
        | tySint _ => rw [hty] at h; cases h
        | tyNamed _ _ => rw [hty] at h; cases h
    | xStruct t' fs => cases h; exact .struct
    | xVariant t' k ps => cases h; exact .variant
    | xMatch s ety t' bs vs => cases h; exact .match
    | xDivide op l r =>
      simp only [pickTy] at h
      by_cases bl : bareEff l = true
      · rw [if_pos bl] at h
        exact .divideRight bl (effTy_sound h)
      · rw [if_neg bl] at h
        exact .divideLeft (by simpa using bl) (effTy_sound h)
    | xStride sl => cases h; exact .stride

theorem effsTys_sound {fuel : Nat} {env : FrontEnv} {scope : List Local} :
    ∀ {xs : List MEff} {ts : List Ty}, effsTys fuel env scope xs = some ts → ListRel (EffTy env.decls scope) xs ts
  | [], ts, h => by
    simp only [effsTys, Option.some.injEq] at h
    subst h
    exact .nil
  | x :: rest, ts, h => by
    simp only [effsTys, consTy] at h
    cases hx : effTy fuel env scope x with
    | none => rw [hx] at h; cases h
    | some t =>
      rw [hx] at h
      simp only [consTyTail] at h
      cases hr : effsTys fuel env scope rest with
      | none => rw [hr] at h; cases h
      | some tr =>
        rw [hr, Option.some.injEq] at h
        subst h
        exact .cons (effTy_sound hx) (effsTys_sound hr)

/-! ## Arguments -/

/-- Expressions read in order. -/
def ExprsR (env : FrontEnv) (scope : List Local) (items : List CTree) (es : List SrcExpr) : Prop :=
  ListRel (ExprR env scope) items es

/-- A call's argument list. -/
def ArgsOfR (env : FrontEnv) (scope : List Local) (args : CTree) (es : List SrcExpr) : Prop :=
  ∃ items, Items args items ∧ ExprsR env scope items es

theorem exprsOf_sound {fuel : Nat} {env : FrontEnv} {scope : List Local} :
    ∀ {items : List CTree} {es : List SrcExpr}, exprsOf fuel env scope items = some es → ExprsR env scope items es
  | [], es, h => by
    simp only [exprsOf, Option.some.injEq] at h
    subst h
    exact .nil
  | e :: rest, es, h => by
    simp only [exprsOf, consExpr] at h
    cases he : exprOf fuel env scope e with
    | none => rw [he] at h; cases h
    | some x =>
      rw [he] at h
      simp only [consExprTail] at h
      cases hr : exprsOf fuel env scope rest with
      | none => rw [hr] at h; cases h
      | some xs =>
        rw [hr, Option.some.injEq] at h
        subst h
        exact .cons (exprOf_sound he) (exprsOf_sound hr)

theorem argsOf_sound {fuel : Nat} {env : FrontEnv} {scope : List Local} {args : CTree} {es : List SrcExpr}
    (h : argsOf fuel env scope args = some es) : ArgsOfR env scope args es := by
  unfold argsOf at h
  cases hi : listItems fuel args with
  | none => rw [hi] at h; cases h
  | some items => rw [hi] at h; exact ⟨items, listItems_sound hi, exprsOf_sound h⟩

/-- A path's segments and its last segment's type arguments
(`a::b::f::<T>`). -/
inductive PathRefR : CTree → CTree → PathRef → Prop
  | last {segment tail : CTree} : nodeProd segment = pPathIdent → nodeProd tail = pPathEnd →
      PathRefR segment tail ⟨[(kidToken segment 0).text], []⟩
  | args {segment tail : CTree} {gs : List CTree} : nodeProd segment = pPathIdentArgs → nodeProd tail = pPathEnd →
      Items segment gs → PathRefR segment tail ⟨[(kidToken segment 0).text], gs⟩
  | more {segment tail : CTree} {r : PathRef} : nodeProd segment = pPathIdent → nodeProd tail = pPathMore →
      PathRefR (kid tail 2) (kid tail 3) r → PathRefR segment tail ⟨(kidToken segment 0).text :: r.segments, r.targs⟩

theorem pathRef_sound : ∀ {fuel : Nat} {segment tail : CTree} {pr : PathRef},
    pathRef fuel segment tail = some pr → PathRefR segment tail pr
  | 0, _, _, _, h => by rw [pathRef.eq_def] at h; simp at h
  | f + 1, segment, tail, pr, h => by
    rw [pathRef.eq_def] at h
    simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
    by_cases one : nodeProd segment = pPathIdent ∧ nodeProd tail = pPathEnd
    · rw [if_pos (by simpa using one), Option.some.injEq] at h
      subst h
      exact .last one.1 one.2
    rw [if_neg (by simpa using one)] at h
    by_cases ar : nodeProd segment = pPathIdentArgs ∧ nodeProd tail = pPathEnd
    · rw [if_pos (by simpa using ar)] at h
      simp only [argsSegment] at h
      cases hi : listItems (f + 1) segment with
      | none => rw [hi] at h; cases h
      | some gs =>
        rw [hi, Option.some.injEq] at h
        subst h
        exact .args ar.1 ar.2 (listItems_sound hi)
    rw [if_neg (by simpa using ar)] at h
    by_cases mo : nodeProd segment = pPathIdent ∧ nodeProd tail = pPathMore
    · rw [if_pos (by simpa using mo)] at h
      simp only [consSegment] at h
      cases hr : pathRef f (kid tail 2) (kid tail 3) with
      | none => rw [hr] at h; cases h
      | some r =>
        rw [hr, Option.some.injEq] at h
        subst h
        exact .more mo.1 mo.2 (pathRef_sound hr)
    rw [if_neg (by simpa using mo)] at h
    cases h

/-! ## Type owners -/

/-- A path's prefix that names a type: one segment, a type parameter, a
primitive type or a struct of the current module (an enum's path names its
variants). -/
def TypeOwner (env : FrontEnv) (front : ModPath) (n : Name) : Prop :=
  front = [n] ∧ (n ∈ env.names ∨ primName n ≠ none ∨
    ∃ d t, DeclAt env [n] d ∧ env.decls.types[d]? = some t ∧ t.isEnum = false)

/-- The type a type owner names: a type of the current module stands for
itself with no type arguments. -/
def OwnerTy (env : FrontEnv) (n : Name) (t : Ty) : Prop :=
  ParamTy env n t ∨ (NoParam env n ∧ primTys.lookup n = some t) ∨
    (NoParam env n ∧ primTys.lookup n = none ∧ ∃ d, DeclAt env [n] d ∧ Arity env.decls d 0 ∧ t = .tyNamed d [])

theorem isStructAt_typeDeclAt (env : FrontEnv) (ss : List Name) :
    isStructAt env (typeDeclAt env ss) = true ↔
      ∃ d t, DeclAt env ss d ∧ env.decls.types[d]? = some t ∧ t.isEnum = false := by
  cases h : typeDeclAt env ss with
  | some d =>
    have a := typeDeclAt_sound h
    unfold isStructAt
    cases ht : env.decls.types[d]? with
    | none =>
      simp only [ht]
      refine ⟨fun e => absurd e (by decide), ?_⟩
      rintro ⟨d', t, a', ht', -⟩
      rw [declAt_unique a a', ht'] at ht
      cases ht
    | some t =>
      simp only [ht, Bool.not_eq_true']
      refine ⟨fun e => ⟨d, t, a, ht, e⟩, ?_⟩
      rintro ⟨d', t', a', ht', e⟩
      rw [declAt_unique a a', ht'] at ht
      cases ht
      exact e
  | none =>
    refine ⟨fun e => (by simp [isStructAt] at e), ?_⟩
    rintro ⟨d, -, a, -⟩
    exact absurd a (noDeclAt_not (typeDeclAt_none h))

theorem isTypeParam_iff (env : FrontEnv) (front : ModPath) :
    (isTypeParam env (singleName front) = true) ↔ ∃ n, TypeOwner env front n := by
  rw [singleName_eq]
  match front with
  | [n] =>
    simp only [isTypeParam, Bool.or_eq_true, member_iff, Bool.not_eq_true', primitive_eq, TypeOwner,
      isStructAt_typeDeclAt]
    constructor
    · intro h
      refine ⟨n, rfl, ?_⟩
      rcases h with (h | h) | h
      · exact .inl h
      · right; left
        cases hp : primName n <;> simp_all [isNoneType]
      · exact .inr (.inr h)
    · rintro ⟨m, e, h⟩
      cases e
      rcases h with h | h | h
      · exact .inl (.inl h)
      · left; right
        cases hp : primName n <;> simp_all [isNoneType]
      · exact .inr h
  | [] => simp [isTypeParam, TypeOwner]
  | _ :: _ :: _ => simp [isTypeParam, TypeOwner]

end Lanius.Mini.Reading
