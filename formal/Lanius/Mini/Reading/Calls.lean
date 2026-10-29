import Lanius.Mini.Reading.Infer

/-! # The reading, V8d: effectful expression types and calls

`EffTy decls scope x t`: the type of an effectful expression, as type
arguments are inferred from it (a call's is its instance's result type,
`InstRet`). A call `path(args)` is a static method call `T::m(args)` when
the path's prefix is a type parameter or primitive type, and else a call of
the free function the path names, at the type arguments written or
inferred; `x.m(args)` is `T::m(x, args)` for `x`'s type `T`. -/

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

/-! ## Calls -/

/-- A call's instance by inference: none to infer, or the instance
inferred from the arguments' types. -/
def InferCall (decls : Decls) (scope : List Local) (d : Nat) (fd : FnDecl) (start : List Bind) (es : List SrcExpr)
    (expected : Ty) (inst : Inst) : Prop :=
  (fd.implParams ++ fd.params = [] ∧ inst = ⟨d, []⟩) ∨
  ∃ ts, ListRel (ExprTy decls scope) es ts ∧ InferInst decls d fd start (some ts) expected inst

theorem inferCall_sound {fuel : Nat} {env : FrontEnv} {scope : List Local} {d : Nat} {fd : FnDecl} {start : List Bind}
    {es : List SrcExpr} {expected : Ty} {inst : Inst}
    (h : inferInst fuel env.decls d fd start (exprsTys fuel env scope es) expected = some inst) :
    InferCall env.decls scope d fd start es expected inst := by
  have r := inferInst_sound h
  cases ht : exprsTys fuel env scope es with
  | none =>
    rw [ht] at r
    cases r with
    | plain e => exact .inl ⟨e, rfl⟩
    | infer _ e => cases e
  | some ts =>
    rw [ht] at r
    exact .inr ⟨ts, exprsTys_sound ht, r⟩

/-- A call of the free function `d`: at the type arguments inferred, or
written. -/
inductive FreeCall (env : FrontEnv) (scope : List Local) (expected : Ty) (d : Nat) (targs : List CTree)
    (es : List SrcExpr) : Called → Prop
  | inferred {fd : FnDecl} {inst : Inst} : env.decls.fns[d]? = some fd → targs = [] →
      InferCall env.decls scope d fd [] es expected inst → FreeCall env scope expected d targs es ⟨inst, es⟩
  | explicit {fd : FnDecl} {inst : Inst} : env.decls.fns[d]? = some fd → targs ≠ [] → ExplicitInst env d fd targs inst →
      FreeCall env scope expected d targs es ⟨inst, es⟩

theorem freeCall_sound {fuel : Nat} {env : FrontEnv} {scope : List Local} {expected : Ty} {d : Nat}
    {targs : List CTree} {es : List SrcExpr} {c : Called} (h : freeCall fuel env scope expected d targs es = some c) :
    FreeCall env scope expected d targs es c := by
  unfold freeCall at h
  cases hf : env.decls.fns[d]? with
  | none => rw [hf] at h; cases h
  | some fd =>
    rw [hf] at h
    simp only [freeCallOf] at h
    by_cases nt : noTrees targs = true
    · rw [if_pos nt] at h
      simp only [called] at h
      cases hi : inferInst fuel env.decls d fd [] (exprsTys fuel env scope es) expected with
      | none => rw [hi] at h; cases h
      | some inst =>
        rw [hi, Option.some.injEq] at h
        subst h
        exact .inferred hf ((noTrees_iff _).1 nt) (inferCall_sound hi)
    · rw [if_neg nt] at h
      simp only [called] at h
      cases hi : explicitInst fuel env d fd targs with
      | none => rw [hi] at h; cases h
      | some inst =>
        rw [hi, Option.some.injEq] at h
        subst h
        exact .explicit hf (fun e => nt ((noTrees_iff _).2 e)) (explicitInst_sound hi)

/-- `T::m(args)` for the type `t`: a method `m` whose impl's type matches
`t`, at the type arguments inferred from the impl's and the arguments. -/
def StaticCall (env : FrontEnv) (scope : List Local) (expected : Ty) (t : Ty) (name : Name) (es : List SrcExpr)
    (c : Called) : Prop :=
  ∃ found fd inst, MethodFor env.decls env.decls.fns 0 name t found ∧ env.decls.fns[found.decl]? = some fd ∧
    InferCall env.decls scope found.decl fd found.binds es expected inst ∧ c = ⟨inst, es⟩

theorem staticCall_sound {fuel : Nat} {env : FrontEnv} {scope : List Local} {expected t : Ty} {name : Name}
    {es : List SrcExpr} {c : Called} (h : staticCall fuel env scope expected (some t) name es = some c) :
    StaticCall env scope expected t name es c := by
  simp only [staticCall, methodInst] at h
  cases hm : findMethod fuel env.decls env.decls.fns 0 name t with
  | none => rw [hm] at h; cases h
  | some found =>
    rw [hm] at h
    simp only at h
    cases hf : env.decls.fns[found.decl]? with
    | none => rw [hf] at h; cases h
    | some fd =>
      rw [hf] at h
      simp only [called] at h
      cases hi : inferInst fuel env.decls found.decl fd found.binds (exprsTys fuel env scope es) expected with
      | none => rw [hi] at h; cases h
      | some inst =>
        rw [hi, Option.some.injEq] at h
        exact ⟨found, fd, inst, findMethod_sound hm, hf, inferCall_sound hi, h.symm⟩

/-- A path's prefix that names a type: one segment, a type parameter or a
primitive type. -/
def TypeOwner (env : FrontEnv) (front : ModPath) (n : Name) : Prop :=
  front = [n] ∧ (n ∈ env.names ∨ primName n ≠ none)

/-- The type a type owner names. -/
def OwnerTy (env : FrontEnv) (n : Name) (t : Ty) : Prop :=
  ParamTy env n t ∨ (NoParam env n ∧ primTys.lookup n = some t)

/-- `front::name(args)`: a static call when `front` names a type and no
type arguments are written, else a call of the free function the path
names. -/
inductive PathCall (env : FrontEnv) (scope : List Local) (expected : Ty) (front : ModPath) (name : Name)
    (targs : List CTree) (es : List SrcExpr) : Called → Prop
  | static {n : Name} {t : Ty} {c : Called} : TypeOwner env front n → targs = [] → OwnerTy env n t →
      StaticCall env scope expected t name es c → PathCall env scope expected front name targs es c
  | free {d : Nat} {c : Called} : ¬(∃ n, TypeOwner env front n ∧ targs = []) →
      FnNamed env.decls (if front = [] then env.home else front) name d → FreeCall env scope expected d targs es c →
      PathCall env scope expected front name targs es c

theorem isTypeParam_iff (env : FrontEnv) (front : ModPath) :
    (isTypeParam env (singleName front) = true) ↔ ∃ n, TypeOwner env front n := by
  rw [singleName_eq]
  match front with
  | [n] =>
    simp only [isTypeParam, Bool.or_eq_true, member_iff, Bool.not_eq_true', primitive_eq, TypeOwner]
    constructor
    · intro h
      refine ⟨n, rfl, ?_⟩
      rcases h with h | h
      · exact .inl h
      · right
        cases hp : primName n <;> simp_all [isNoneType]
    · rintro ⟨m, e, h⟩
      cases e
      rcases h with h | h
      · exact .inl h
      · right
        cases hp : primName n <;> simp_all [isNoneType]
  | [] => simp [isTypeParam, TypeOwner]
  | _ :: _ :: _ => simp [isTypeParam, TypeOwner]

theorem pathCall_sound {fuel : Nat} {env : FrontEnv} {scope : List Local} {expected : Ty} {s : Split}
    {targs : List CTree} {es : List SrcExpr} {c : Called} (h : pathCall fuel env scope expected s targs es = some c) :
    PathCall env scope expected s.home s.name targs es c := by
  unfold pathCall at h
  simp only at h
  by_cases st : (isTypeParam env (singleName s.home) && noTrees targs) = true
  · rw [if_pos st] at h
    simp only [Bool.and_eq_true] at st
    obtain ⟨n, own⟩ := (isTypeParam_iff env s.home).1 st.1
    have hs : singleName s.home = some n := by rw [own.1]; rfl
    rw [hs] at h
    simp only [ownerTy] at h
    cases hp : paramTy env n with
    | some t =>
      rw [hp] at h
      exact .static own ((noTrees_iff _).1 st.2) (.inl (paramTy_sound hp)) (staticCall_sound h)
    | none =>
      rw [hp] at h
      simp only at h
      rw [primTy_eq] at h
      cases hq : primTys.lookup n with
      | none => rw [hq] at h; simp [staticCall] at h
      | some t =>
        rw [hq] at h
        exact .static own ((noTrees_iff _).1 st.2) (.inr ⟨paramTy_none hp, hq⟩) (staticCall_sound h)
  · rw [if_neg st] at h
    cases hf : findFn env.decls.fns (moduleOr env.home s.home) s.name 0 with
    | none => rw [hf] at h; cases h
    | some d =>
      rw [hf] at h
      refine .free (fun ⟨n, own, e⟩ => st ?_) (by rw [← moduleOr_eq]; exact findFn_sound hf) (freeCall_sound h)
      simp only [Bool.and_eq_true]
      exact ⟨(isTypeParam_iff env s.home).2 ⟨n, own⟩, (noTrees_iff _).2 e⟩

/-- `path(args)` as a call, its value stored at type `expected`. -/
def PathCallOf (env : FrontEnv) (scope : List Local) (expected : Ty) (path args : CTree) (c : Called) : Prop :=
  ∃ pr front name es, PathRefR (kid path 0) (kid path 1) pr ∧ pr.segments = front ++ [name] ∧
    ArgsOfR env scope args es ∧ PathCall env scope expected front name pr.targs es c

theorem pathCallOf_sound {fuel : Nat} {env : FrontEnv} {scope : List Local} {expected : Ty} {path args : CTree}
    {c : Called} (h : pathCallOf fuel env scope expected path args = some c) : PathCallOf env scope expected path args c := by
  unfold pathCallOf at h
  cases hp : pathRef fuel (kid path 0) (kid path 1) with
  | none => rw [hp] at h; cases h
  | some pr =>
    rw [hp] at h
    simp only at h
    cases hs : splitLast pr.segments with
    | none => rw [hs] at h; cases h
    | some s =>
      rw [hs] at h
      simp only at h
      cases ha : argsOf fuel env scope args with
      | none => rw [ha] at h; cases h
      | some es =>
        rw [ha] at h
        exact ⟨pr, s.home, s.name, es, pathRef_sound hp, splitLast_sound hs, argsOf_sound ha, pathCall_sound h⟩

/-- `recv.m(args)`, the receiver a local. -/
def MethodCallOf (env : FrontEnv) (scope : List Local) (expected : Ty) (pf : CTree) (c : Called) : Prop :=
  ∃ l es, LocalOf scope (kid pf 0) l ∧ ArgsOfR env scope (kid (kid (kid pf 1) 3) 1) es ∧
    StaticCall env scope expected l.ty (kidToken (kid pf 1) 1).text (.local l.id :: es) c

theorem methodCallOf_sound {fuel : Nat} {env : FrontEnv} {scope : List Local} {expected : Ty} {pf : CTree}
    {c : Called} (h : methodCallOf fuel env scope expected pf = some c) : MethodCallOf env scope expected pf c := by
  unfold methodCallOf at h
  simp only [methodCall] at h
  cases hl : localOf env scope (kid pf 0) with
  | none => rw [hl] at h; cases h
  | some l =>
    rw [hl] at h
    simp only at h
    cases ha : argsOf fuel env scope (kid (kid (kid pf 1) 3) 1) with
    | none => rw [ha] at h; cases h
    | some es =>
      rw [ha] at h
      exact ⟨l, es, localOf_sound hl, argsOf_sound ha, staticCall_sound h⟩

end Lanius.Mini.Reading
