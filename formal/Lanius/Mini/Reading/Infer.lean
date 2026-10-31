import Lanius.Mini.Reading.Lower
import Lanius.Mini.Reading.Exprs

/-! # The reading, V8d: expression types and type arguments

`ExprTy decls scope e t`: the type type arguments are inferred from for the
expression `e` (an operator's type is its operand's, the right one's when
the left is a bare integer literal, whose type comes from its context).
`MatchTy env names pattern actual binds binds'`: the type expression
`pattern` of a declaration whose type parameters `names` are being
inferred matches the type `actual`, extending the bindings. A call's
instance is its function at the type arguments so inferred (`InferInst`),
or at those written (`ExplicitInst`); a method call's function is a method
of that spelling whose impl's type matches the receiver's (`MethodFor`, in
`Reading/Method.lean`). -/

namespace Lanius.Mini.Reading

open Lanius.Mini Lanius.Mini.Prod

/-! ## Expression types -/

/-- The innermost local with the id. -/
def LocalWithId (scope : List Local) (id : Nat) (l : Local) : Prop :=
  ∃ i, FirstWith scope (·.id = id) i l

inductive ExprTy (decls : Decls) (scope : List Local) : SrcExpr → Ty → Prop
  | int {k : BitVec 32} : ExprTy decls scope (.int k) .tyI32
  | boolean {b : Bool} : ExprTy decls scope (.boolean b) .tyBool
  | unsigned {u : UintTy} {k : BitVec 64} : ExprTy decls scope (.unsigned u k) (.tyUint u)
  | local {id : Nat} {l : Local} : LocalWithId scope id l → ExprTy decls scope (.local id) l.ty
  | field {id j : Nat} {l : Local} {d : Nat} {args ts : List Ty} {t : Ty} : LocalWithId scope id l →
      l.ty = .tyNamed d args → FieldTys decls d args ts → ts[j]? = some t → ExprTy decls scope (.field id j) t
  | negate {x : SrcExpr} {t : Ty} : ExprTy decls scope x t → ExprTy decls scope (.negate x) t
  | not {x : SrcExpr} : ExprTy decls scope (.not x) .tyBool
  | compare {op : SrcOp} {a b : SrcExpr} : givesBool op = true → ExprTy decls scope (.apply op a b) .tyBool
  | left {op : SrcOp} {a b : SrcExpr} {t : Ty} : givesBool op = false → bareInt a = false → ExprTy decls scope a t →
      ExprTy decls scope (.apply op a b) t
  | right {op : SrcOp} {a b : SrcExpr} {t : Ty} : givesBool op = false → bareInt a = true → ExprTy decls scope b t →
      ExprTy decls scope (.apply op a b) t
  | cast {s : SrcType} {x : SrcExpr} {t : Ty} : ScalarTy t s → ExprTy decls scope (.cast s x) t
  | null : ExprTy decls scope .null .tyPtr

theorem findLocalId_sound {scope : List Local} {id : Nat} {l : Local} (h : findLocalId scope id = some l) :
    LocalWithId scope id l :=
  pick_sound (fun l => decide (l.id = id)) _ (fun l => by simp) (fun xs => findLocalId xs id) rfl
    (fun y xs => by simp only [findLocalId, decide_eq_true_eq]) scope l h

theorem srcTy_sound {s : SrcType} {t : Ty} (h : srcTy s = some t) : ScalarTy t s := by
  cases s <;> simp [srcTy] at h <;> subst h <;> constructor

theorem exprTy_sound : ∀ {fuel : Nat} {env : FrontEnv} {scope : List Local} {e : SrcExpr} {t : Ty},
    exprTy fuel env scope e = some t → ExprTy env.decls scope e t
  | 0, _, _, _, _, h => by rw [exprTy.eq_def] at h; simp at h
  | f + 1, env, scope, e, t, h => by
    rw [exprTy.eq_def] at h
    simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
    cases e with
    | int k => cases h; exact .int
    | boolean b => cases h; exact .boolean
    | unsigned u k => cases h; exact .unsigned
    | «local» id =>
      simp only [localTy] at h
      cases hl : findLocalId scope id with
      | none => rw [hl] at h; cases h
      | some l =>
        rw [hl, Option.some.injEq] at h
        subst h
        exact .local (findLocalId_sound hl)
    | field id j =>
      simp only [fieldTy] at h
      cases hl : findLocalId scope id with
      | none => rw [hl] at h; cases h
      | some l =>
        rw [hl] at h
        simp only at h
        cases hs : structFieldTys (f + 1) env.decls l.ty with
        | none => rw [hs] at h; cases h
        | some ts =>
          rw [hs] at h
          simp only at h
          unfold structFieldTys at hs
          cases hty : l.ty with
          | tyNamed d args =>
            rw [hty] at hs
            exact .field (findLocalId_sound hl) hty (fieldTys_sound hs) h
          | tyI32 => rw [hty] at hs; cases hs
          | tyBool => rw [hty] at hs; cases hs
          | tyUint _ => rw [hty] at hs; cases hs
          | tyPtr => rw [hty] at hs; cases hs
          | tyIsize => rw [hty] at hs; cases hs
          | tyChar => rw [hty] at hs; cases hs
          | tySint _ => rw [hty] at hs; cases hs
          | tySlice _ => rw [hty] at hs; cases hs
    | negate x => exact .negate (exprTy_sound h)
    | not x => cases h; exact .not
    | apply op a b =>
      simp only [applyTy] at h
      by_cases g : givesBool op = true
      · rw [if_pos g, Option.some.injEq] at h
        subst h
        exact .compare g
      · rw [if_neg g] at h
        have g' : givesBool op = false := by simpa using g
        simp only [pickTy] at h
        by_cases ba : bareInt a = true
        · rw [if_pos ba] at h
          exact .right g' ba (exprTy_sound h)
        · rw [if_neg ba] at h
          exact .left g' (by simpa using ba) (exprTy_sound h)
    | cast s x => exact .cast (srcTy_sound h)
    | null => cases h; exact .null
    | char c => cases h

theorem exprsTys_sound {fuel : Nat} {env : FrontEnv} {scope : List Local} :
    ∀ {es : List SrcExpr} {ts : List Ty}, exprsTys fuel env scope es = some ts → ListRel (ExprTy env.decls scope) es ts
  | [], ts, h => by
    simp only [exprsTys, Option.some.injEq] at h
    subst h
    exact .nil
  | e :: rest, ts, h => by
    simp only [exprsTys, consTy] at h
    cases he : exprTy fuel env scope e with
    | none => rw [he] at h; cases h
    | some t =>
      rw [he] at h
      simp only [consTyTail] at h
      cases hr : exprsTys fuel env scope rest with
      | none => rw [hr] at h; cases h
      | some tr =>
        rw [hr, Option.some.injEq] at h
        subst h
        exact .cons (exprTy_sound he) (exprsTys_sound hr)

/-! ## Matching type expressions against types -/

/-- The first binding of the parameter `n` is to `t`. -/
def BindOf (binds : List Bind) (n : Name) (t : Ty) : Prop :=
  ∃ i b, FirstWith binds (·.name = n) i b ∧ b.ty = t

/-- The parameter `n` has no binding. -/
def Unbound (binds : List Bind) (n : Name) : Prop := ∀ b ∈ binds, b.name ≠ n

/-- The parameter `n` stands for `actual`: a new binding, or the one it has. -/
inductive BindTy (binds : List Bind) (n : Name) (actual : Ty) : List Bind → Prop
  | new : Unbound binds n → BindTy binds n actual (⟨n, actual⟩ :: binds)
  | same : BindOf binds n actual → BindTy binds n actual binds

/-- The pattern path is the parameter `n`, one being inferred. -/
def IsParam (names : List Name) (ss : List Name) (gs : List CTree) (n : Name) : Prop :=
  ss = [n] ∧ n ∈ names ∧ gs = []

/-- The pattern path is a primitive type. -/
def IsPrim (ss : List Name) (gs : List CTree) (t : Ty) : Prop :=
  ∃ n, ss = [n] ∧ gs = [] ∧ primTys.lookup n = some t

mutual
inductive MatchTy : FrontEnv → List Name → CTree → Ty → List Bind → List Bind → Prop
  | slice {env : FrontEnv} {names : List Name} {p : CTree} {a : Ty} {b b' : List Bind} :
      nodeProd p = pTypeArray → nodeProd (kid p 2) = pTypeSliceTail → MatchTy env names (kid p 1) a b b' →
      MatchTy env names p (.tySlice a) b b'
  | param {env : FrontEnv} {names : List Name} {p : CTree} {ss : List Name} {gs : List CTree} {n : Name} {actual : Ty}
      {b b' : List Bind} : nodeProd p = pTypeIdent → TypePathSpellings (kid (kid p 0) 0) (kid (kid p 0) 1) ss →
      Items (kid p 1) gs → IsParam names ss gs n → BindTy b n actual b' → MatchTy env names p actual b b'
  | prim {env : FrontEnv} {names : List Name} {p : CTree} {ss : List Name} {gs : List CTree} {actual : Ty}
      {b : List Bind} : nodeProd p = pTypeIdent → TypePathSpellings (kid (kid p 0) 0) (kid (kid p 0) 1) ss →
      Items (kid p 1) gs → (∀ n, ¬IsParam names ss gs n) → IsPrim ss gs actual → MatchTy env names p actual b b
  | decl {env : FrontEnv} {names : List Name} {p : CTree} {ss : List Name} {gs : List CTree} {d : Nat} {args : List Ty}
      {b b' : List Bind} : nodeProd p = pTypeIdent → TypePathSpellings (kid (kid p 0) 0) (kid (kid p 0) 1) ss →
      Items (kid p 1) gs → (∀ n, ¬IsParam names ss gs n) → (∀ t, ¬IsPrim ss gs t) → DeclAt env ss d →
      MatchArgs env names gs args b b' → MatchTy env names p (.tyNamed d args) b b'

/-- Generic arguments against the actual arguments, in order. -/
inductive MatchArgs : FrontEnv → List Name → List CTree → List Ty → List Bind → List Bind → Prop
  | nil {env : FrontEnv} {names : List Name} {b : List Bind} : MatchArgs env names [] [] b b
  | cons {env : FrontEnv} {names : List Name} {g : CTree} {rest : List CTree} {a : Ty} {more : List Ty}
      {b b1 b' : List Bind} : nodeProd g = pGenericArgumentType → MatchTy env names (kid g 0) a b b1 →
      MatchArgs env names rest more b1 b' → MatchArgs env names (g :: rest) (a :: more) b b'
end

/-- Type expressions against actual types, in order. -/
inductive MatchTys (env : FrontEnv) (names : List Name) : List CTree → List Ty → List Bind → List Bind → Prop
  | nil {b : List Bind} : MatchTys env names [] [] b b
  | cons {p : CTree} {rest : List CTree} {a : Ty} {more : List Ty} {b b1 b' : List Bind} :
      MatchTy env names p a b b1 → MatchTys env names rest more b1 b' → MatchTys env names (p :: rest) (a :: more) b b'

theorem findBind_sound : ∀ {binds : List Bind} {n : Name} {t : Ty}, findBind binds n = some t → BindOf binds n t
  | [], _, _, h => by simp [findBind] at h
  | b :: rest, n, t, h => by
    simp only [findBind] at h
    by_cases e : sameText b.name n = true
    · rw [if_pos e, Option.some.injEq] at h
      exact ⟨0, b, firstWith_zero rfl ((sameText_iff _ _).1 e), h⟩
    · rw [if_neg e] at h
      obtain ⟨i, x, fx, rfl⟩ := findBind_sound h
      exact ⟨i + 1, x, firstWith_succ (fun q => e ((sameText_iff _ _).2 q)) fx, rfl⟩

theorem findBind_none : ∀ {binds : List Bind} {n : Name}, findBind binds n = none → Unbound binds n
  | [], _, _ => by simp [Unbound]
  | b :: rest, n, h => by
    simp only [findBind] at h
    by_cases e : sameText b.name n = true
    · rw [if_pos e] at h; cases h
    · rw [if_neg e] at h
      intro x mem
      rcases List.mem_cons.1 mem with rfl | mem
      · exact fun q => e ((sameText_iff _ _).2 q)
      · exact findBind_none h x mem

theorem bindTy_sound {binds : List Bind} {n : Name} {actual : Ty} {b' : List Bind}
    (h : bindTy binds n actual = some b') : BindTy binds n actual b' := by
  unfold bindTy at h
  cases hf : findBind binds n with
  | none =>
    rw [hf, Option.some.injEq] at h
    subst h
    exact .new (findBind_none hf)
  | some t =>
    rw [hf] at h
    simp only [sameOrNone] at h
    by_cases s : sameTy t actual = true
    · rw [if_pos s, Option.some.injEq] at h
      subst h
      rw [(sameTy_iff _ _).1 s] at hf
      exact .same (findBind_sound hf)
    · rw [if_neg s] at h; cases h

theorem noTrees_iff (gs : List CTree) : noTrees gs = true ↔ gs = [] := by
  cases gs <;> simp [noTrees]

theorem paramSpelling_sound {names ss : List Name} {gs : List CTree} :
    (∀ {n}, paramSpelling names ss gs = some n → IsParam names ss gs n) ∧
    (paramSpelling names ss gs = none → ∀ n, ¬IsParam names ss gs n) := by
  unfold paramSpelling
  rw [singleName_eq]
  match ss with
  | [m] =>
    simp only [paramNamed]
    by_cases ok : (member names m && noTrees gs) = true
    · rw [if_pos ok]
      simp only [Bool.and_eq_true, member_iff, noTrees_iff] at ok
      exact ⟨fun h => (by cases h; exact ⟨rfl, ok.1, ok.2⟩), fun h => (by cases h)⟩
    · rw [if_neg ok]
      refine ⟨fun h => (by cases h), fun _ n ⟨e, mem, g⟩ => ok ?_⟩
      cases e
      simp [member_iff, noTrees_iff, mem, g]
  | [] => exact ⟨fun h => (by cases h), fun _ n ⟨e, _⟩ => (by cases e)⟩
  | _ :: _ :: _ => exact ⟨fun h => (by cases h), fun _ n ⟨e, _⟩ => (by cases e)⟩

theorem barePrim_sound {ss : List Name} {gs : List CTree} :
    (∀ {t}, barePrim ss gs = some t → IsPrim ss gs t) ∧ (barePrim ss gs = none → ∀ t, ¬IsPrim ss gs t) := by
  unfold barePrim
  rw [singleName_eq]
  match ss with
  | [m] =>
    simp only [primIf]
    by_cases ok : noTrees gs = true
    · rw [if_pos ok, primTy_eq]
      have g := (noTrees_iff gs).1 ok
      refine ⟨fun h => ⟨m, rfl, g, h⟩, fun h t ⟨n, e, _, l⟩ => ?_⟩
      cases e
      rw [h] at l; cases l
    · rw [if_neg ok]
      refine ⟨fun h => (by cases h), fun _ t ⟨n, _, g, _⟩ => ok ((noTrees_iff gs).2 g)⟩
  | [] => exact ⟨fun h => (by cases h), fun _ t ⟨n, e, _⟩ => (by cases e)⟩
  | _ :: _ :: _ => exact ⟨fun h => (by cases h), fun _ t ⟨n, e, _⟩ => (by cases e)⟩

/-- What a pattern path with its generic arguments matches. -/
def NamedMatch (env : FrontEnv) (names ss : List Name) (gs : List CTree) (actual : Ty) (b b' : List Bind) : Prop :=
  (∃ n, IsParam names ss gs n ∧ BindTy b n actual b') ∨
  ((∀ n, ¬IsParam names ss gs n) ∧ IsPrim ss gs actual ∧ b' = b) ∨
  ((∀ n, ¬IsParam names ss gs n) ∧ (∀ t, ¬IsPrim ss gs t) ∧
    ∃ d args, actual = .tyNamed d args ∧ DeclAt env ss d ∧ MatchArgs env names gs args b b')

def MatchSound (fuel : Nat) : Prop :=
  (∀ {env names p actual b b'}, matchTy fuel env names p actual b = some b' → MatchTy env names p actual b b') ∧
  (∀ {env names segs items actual b b'}, matchPath fuel env names segs items actual b = some b' →
    ∃ ss gs, segs = some ss ∧ items = some gs ∧ NamedMatch env names ss gs actual b b') ∧
  (∀ {env names ss gs actual b b'}, matchNamed fuel env names ss gs actual b = some b' →
    NamedMatch env names ss gs actual b b') ∧
  (∀ {env names dOpt items aOpt b b'}, matchDecl fuel env names dOpt items aOpt b = some b' →
    ∃ d a, dOpt = some d ∧ aOpt = some a ∧ d = a.decl ∧ MatchArgs env names items a.args b b') ∧
  (∀ {env names same items args b b'}, matchSameDecl fuel env names same items args b = some b' →
    same = true ∧ MatchArgs env names items args b b') ∧
  (∀ {env names items actuals b b'}, matchArgs fuel env names items actuals b = some b' →
    MatchArgs env names items actuals b b') ∧
  (∀ {env names g a b b'}, matchArg fuel env names g a b = some b' →
    nodeProd g = pGenericArgumentType ∧ MatchTy env names (kid g 0) a b b') ∧
  (∀ {env names items actuals got b'}, matchArgsNext fuel env names items actuals got = some b' →
    ∃ b, got = some b ∧ MatchArgs env names items actuals b b') ∧
  (∀ {env names ps actuals b b'}, matchTys fuel env names ps actuals b = some b' → MatchTys env names ps actuals b b') ∧
  (∀ {env names ps actuals got b'}, matchTysNext fuel env names ps actuals got = some b' →
    ∃ b, got = some b ∧ MatchTys env names ps actuals b b')

theorem matchSound : ∀ fuel, MatchSound fuel
  | 0 => by
    refine ⟨?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_⟩ <;> intros <;>
      first
      | (rename_i h; rw [matchTy.eq_def] at h; simp at h)
      | (rename_i h; rw [matchPath.eq_def] at h; simp at h)
      | (rename_i h; rw [matchNamed.eq_def] at h; simp at h)
      | (rename_i h; rw [matchDecl.eq_def] at h; simp at h)
      | (rename_i h; rw [matchSameDecl.eq_def] at h; simp at h)
      | (rename_i h; rw [matchArgs.eq_def] at h; simp at h)
      | (rename_i h; rw [matchArg.eq_def] at h; simp at h)
      | (rename_i h; rw [matchArgsNext.eq_def] at h; simp at h)
      | (rename_i h; rw [matchTys.eq_def] at h; simp at h)
      | (rename_i h; rw [matchTysNext.eq_def] at h; simp at h)
  | f + 1 => by
    obtain ⟨ty_ih, path_ih, named_ih, decl_ih, same_ih, args_ih, arg_ih, argsNext_ih, tys_ih, tysNext_ih⟩ :=
      matchSound f
    refine ⟨?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_⟩
    · intro env names p actual b b' h
      rw [matchTy.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      by_cases sl : nodeProd p = pTypeArray ∧ nodeProd (kid p 2) = pTypeSliceTail
      · rw [if_pos (by simpa using sl)] at h
        cases actual with
        | tySlice a => exact .slice sl.1 sl.2 (ty_ih h)
        | tyI32 => cases h
        | tyBool => cases h
        | tyUint _ => cases h
        | tyPtr => cases h
        | tyIsize => cases h
        | tyChar => cases h
        | tySint _ => cases h
        | tyNamed _ _ => cases h
      rw [if_neg (by simpa using sl)] at h
      by_cases ti : nodeProd p = pTypeIdent
      · rw [if_pos ti] at h
        obtain ⟨ss, gs, hs, hg, r⟩ := path_ih h
        have sp := typePathSpellings_sound hs
        have its := listItems_sound hg
        rcases r with ⟨n, ip, bt⟩ | ⟨np, pr, rfl⟩ | ⟨np, nr, d, args, rfl, da, ma⟩
        · exact .param ti sp its ip bt
        · exact .prim ti sp its np pr
        · exact .decl ti sp its np nr da ma
      · rw [if_neg ti] at h; cases h
    · intro env names segs items actual b b' h
      rw [matchPath.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      cases segs with
      | none => cases h
      | some ss =>
        cases items with
        | none => cases h
        | some gs => exact ⟨ss, gs, rfl, rfl, named_ih h⟩
    · intro env names ss gs actual b b' h
      rw [matchNamed.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      cases hp : paramSpelling names ss gs with
      | some n =>
        rw [hp] at h
        exact .inl ⟨n, paramSpelling_sound.1 hp, bindTy_sound h⟩
      | none =>
        rw [hp] at h
        simp only at h
        have np := paramSpelling_sound.2 hp
        cases hq : barePrim ss gs with
        | some t =>
          rw [hq] at h
          simp only [sameOrNone] at h
          by_cases s : sameTy t actual = true
          · rw [if_pos s, Option.some.injEq] at h
            rw [(sameTy_iff _ _).1 s] at hq
            exact .inr (.inl ⟨np, barePrim_sound.1 hq, h.symm⟩)
          · rw [if_neg s] at h; cases h
        | none =>
          rw [hq] at h
          simp only at h
          obtain ⟨d, a, hd, ha, rfl, ma⟩ := decl_ih h
          refine .inr (.inr ⟨np, barePrim_sound.2 hq, a.decl, a.args, ?_, typeDeclAt_sound hd, ma⟩)
          unfold namedParts at ha
          cases actual with
          | tyNamed x ys => simp only [Option.some.injEq] at ha; subst ha; rfl
          | tyI32 => cases ha
          | tyBool => cases ha
          | tyUint _ => cases ha
          | tyPtr => cases ha
          | tyIsize => cases ha
          | tyChar => cases ha
          | tySint _ => cases ha
          | tySlice _ => cases ha
    · intro env names dOpt items aOpt b b' h
      rw [matchDecl.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      cases dOpt with
      | none => cases h
      | some d =>
        cases aOpt with
        | none => cases h
        | some a =>
          simp only at h
          obtain ⟨same, ma⟩ := same_ih h
          exact ⟨d, a, rfl, rfl, by simpa using same, ma⟩
    · intro env names same items args b b' h
      rw [matchSameDecl.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      cases same with
      | true => exact ⟨rfl, args_ih h⟩
      | false => cases h
    · intro env names items actuals b b' h
      rw [matchArgs.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      cases items with
      | nil =>
        cases actuals with
        | nil => cases h; exact .nil
        | cons _ _ => cases h
      | cons g rest =>
        cases actuals with
        | nil => cases h
        | cons a more =>
          simp only at h
          obtain ⟨b1, hb, ma⟩ := argsNext_ih h
          obtain ⟨gp, mt⟩ := arg_ih hb
          exact .cons gp mt ma
    · intro env names g a b b' h
      rw [matchArg.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      by_cases gp : nodeProd g = pGenericArgumentType
      · rw [if_pos gp] at h
        exact ⟨gp, ty_ih h⟩
      · rw [if_neg gp] at h; cases h
    · intro env names items actuals got b' h
      rw [matchArgsNext.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      cases got with
      | none => cases h
      | some b => exact ⟨b, rfl, args_ih h⟩
    · intro env names ps actuals b b' h
      rw [matchTys.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      cases ps with
      | nil =>
        cases actuals with
        | nil => cases h; exact .nil
        | cons _ _ => cases h
      | cons p rest =>
        cases actuals with
        | nil => cases h
        | cons a more =>
          simp only at h
          obtain ⟨b1, hb, mt⟩ := tysNext_ih h
          exact .cons (ty_ih hb) mt
    · intro env names ps actuals got b' h
      rw [matchTysNext.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      cases got with
      | none => cases h
      | some b => exact ⟨b, rfl, tys_ih h⟩

theorem matchTy_sound {fuel : Nat} {env : FrontEnv} {names : List Name} {p : CTree} {actual : Ty} {b b' : List Bind}
    (h : matchTy fuel env names p actual b = some b') : MatchTy env names p actual b b' :=
  (matchSound fuel).1 h

theorem matchTys_sound {fuel : Nat} {env : FrontEnv} {names : List Name} {ps : List CTree} {actuals : List Ty}
    {b b' : List Bind} (h : matchTys fuel env names ps actuals b = some b') : MatchTys env names ps actuals b b' :=
  (matchSound fuel).2.2.2.2.2.2.2.2.1 h

/-! ## Call instances -/

/-- The declared type of a parameter: `name: T`, `self` (the impl's type)
or `self: T`. -/
inductive PatternOf (fd : FnDecl) (p : CTree) : CTree → Prop
  | named : nodeProd p = pParamNamed → PatternOf fd p (kid p 2)
  | self : nodeProd p = pParamSelf → nodeProd (kid p 1) = pSelfParamPlain → fd.inImpl = true → PatternOf fd p fd.selfType
  | selfTyped : nodeProd p = pParamSelf → nodeProd (kid p 1) = pSelfParamTyped → PatternOf fd p (kid (kid p 1) 1)

/-- The declared types of a function's parameters. -/
def ParamPatterns (fd : FnDecl) (ps : List CTree) : Prop :=
  ∃ items, Items (kid fd.tree 4) items ∧ ListRel (PatternOf fd) items ps

/-- The declared result type of a function. -/
def RetPattern (fd : FnDecl) (r : CTree) : Prop :=
  nodeProd (kid fd.tree 6) = pRetType ∧ r = kid (kid fd.tree 6) 1

/-- Where a function's declared types are read. -/
abbrev calleeScope (decls : Decls) (fd : FnDecl) : FrontEnv := declScope decls fd.home [] []

/-- The parameters' types, from their first bindings. -/
def BoundArgs (binds : List Bind) (names : List Name) (args : List Ty) : Prop :=
  ListRel (fun n t => BindOf binds n t) names args

/-- The instance a call of function `d` means: no type parameters, or the
type arguments inferred by matching its parameter types with the argument
types and its result type with the type the call's value is stored at,
starting from `start`. -/
inductive InferInst (decls : Decls) (d : Nat) (fd : FnDecl) (start : List Bind) (argTys : Option (List Ty))
    (expected : Ty) : Inst → Prop
  | plain : fd.implParams ++ fd.params = [] → InferInst decls d fd start argTys expected ⟨d, []⟩
  | infer {ts : List Ty} {ps : List CTree} {b1 : List Bind} {r : CTree} {b2 : List Bind} {args : List Ty} :
      fd.implParams ++ fd.params ≠ [] → argTys = some ts → ParamPatterns fd ps →
      MatchTys (calleeScope decls fd) (fd.implParams ++ fd.params) ps ts start b1 → RetPattern fd r →
      MatchTy (calleeScope decls fd) (fd.implParams ++ fd.params) r expected b1 b2 →
      BoundArgs b2 (fd.implParams ++ fd.params) args → InferInst decls d fd start argTys expected ⟨d, args⟩

theorem patternOf_sound {fd : FnDecl} {p q : CTree} (h : patternOf fd p = some q) : PatternOf fd p q := by
  unfold patternOf at h
  by_cases n : nodeProd p = pParamNamed
  · rw [if_pos n, Option.some.injEq] at h
    subst h
    exact .named n
  rw [if_neg n] at h
  by_cases s : nodeProd p = pParamSelf ∧ nodeProd (kid p 1) = pSelfParamPlain ∧ fd.inImpl = true
  · rw [if_pos (by simpa [and_assoc] using s), Option.some.injEq] at h
    subst h
    exact .self s.1 s.2.1 s.2.2
  rw [if_neg (by simpa [and_assoc] using s)] at h
  by_cases t : nodeProd p = pParamSelf ∧ nodeProd (kid p 1) = pSelfParamTyped
  · rw [if_pos (by simpa using t), Option.some.injEq] at h
    subst h
    exact .selfTyped t.1 t.2
  rw [if_neg (by simpa using t)] at h
  cases h

theorem patternsOf_sound {fd : FnDecl} :
    ∀ {items ps : List CTree}, patternsOf fd items = some ps → ListRel (PatternOf fd) items ps
  | [], ps, h => by
    simp only [patternsOf, Option.some.injEq] at h
    subst h
    exact .nil
  | p :: rest, ps, h => by
    simp only [patternsOf, consTree] at h
    cases hp : patternOf fd p with
    | none => rw [hp] at h; cases h
    | some q =>
      rw [hp] at h
      simp only [consTreeTail] at h
      cases hr : patternsOf fd rest with
      | none => rw [hr] at h; cases h
      | some qs =>
        rw [hr, Option.some.injEq] at h
        subst h
        exact .cons (patternOf_sound hp) (patternsOf_sound hr)

theorem paramPatterns_sound {fuel : Nat} {fd : FnDecl} {ps : List CTree} (h : paramPatterns fuel fd = some ps) :
    ParamPatterns fd ps := by
  unfold paramPatterns at h
  cases hi : listItems fuel (kid fd.tree 4) with
  | none => rw [hi] at h; cases h
  | some items => rw [hi] at h; exact ⟨items, listItems_sound hi, patternsOf_sound h⟩

theorem retPattern_sound {fd : FnDecl} {r : CTree} (h : retPattern fd = some r) : RetPattern fd r := by
  unfold retPattern at h
  by_cases rt : nodeProd (kid fd.tree 6) = pRetType
  · rw [if_pos rt, Option.some.injEq] at h
    exact ⟨rt, h.symm⟩
  · rw [if_neg rt] at h; cases h

theorem boundArgs_sound {binds : List Bind} :
    ∀ {names : List Name} {args : List Ty}, boundArgs names binds = some args → BoundArgs binds names args
  | [], args, h => by
    simp only [boundArgs, Option.some.injEq] at h
    subst h
    exact .nil
  | n :: rest, args, h => by
    simp only [boundArgs, consTy] at h
    cases hb : findBind binds n with
    | none => rw [hb] at h; cases h
    | some t =>
      rw [hb] at h
      simp only [consTyTail] at h
      cases hr : boundArgs rest binds with
      | none => rw [hr] at h; cases h
      | some ts =>
        rw [hr, Option.some.injEq] at h
        subst h
        exact .cons (findBind_sound hb) (boundArgs_sound hr)

theorem noNames_iff (names : List Name) : noNames names = true ↔ names = [] := by
  cases names <;> simp [noNames]

theorem inferInst_sound {fuel : Nat} {decls : Decls} {d : Nat} {fd : FnDecl} {start : List Bind}
    {argTys : Option (List Ty)} {expected : Ty} {inst : Inst}
    (h : inferInst fuel decls d fd start argTys expected = some inst) : InferInst decls d fd start argTys expected inst := by
  unfold inferInst at h
  simp only at h
  by_cases nn : noNames (fd.implParams ++ fd.params) = true
  · rw [if_pos nn, Option.some.injEq] at h
    subst h
    exact .plain ((noNames_iff _).1 nn)
  rw [if_neg nn] at h
  have ne : fd.implParams ++ fd.params ≠ [] := fun e => nn ((noNames_iff _).2 e)
  cases argTys with
  | none => cases h
  | some ts =>
    simp only at h
    cases hp : paramPatterns fuel fd with
    | none => rw [hp] at h; cases h
    | some ps =>
      rw [hp] at h
      simp only [inferRet] at h
      cases hm : matchTys fuel (calleeEnv decls fd) (fd.implParams ++ fd.params) ps ts start with
      | none => rw [hm] at h; cases h
      | some b1 =>
        rw [hm] at h
        simp only at h
        cases hr : retPattern fd with
        | none => rw [hr] at h; cases h
        | some r =>
          rw [hr] at h
          simp only [instFrom, boundOrNone] at h
          cases hm2 : matchTy fuel (calleeEnv decls fd) (fd.implParams ++ fd.params) r expected b1 with
          | none => rw [hm2] at h; cases h
          | some b2 =>
            rw [hm2] at h
            simp only at h
            cases hb : boundArgs (fd.implParams ++ fd.params) b2 with
            | none => rw [hb] at h; cases h
            | some args =>
              rw [hb, Option.some.injEq] at h
              subst h
              exact .infer ne rfl (paramPatterns_sound hp) (matchTys_sound hm) (retPattern_sound hr)
                (matchTy_sound hm2) (boundArgs_sound hb)

/-- `f<T, ...>(args)`: a free function at the type arguments written. -/
def ExplicitInst (env : FrontEnv) (d : Nat) (fd : FnDecl) (targs : List CTree) (inst : Inst) : Prop :=
  ∃ ts, ArgsTy env targs ts ∧ fd.implParams = [] ∧ ts.length = fd.params.length ∧ inst = ⟨d, ts⟩

theorem explicitInst_sound {fuel : Nat} {env : FrontEnv} {d : Nat} {fd : FnDecl} {targs : List CTree} {inst : Inst}
    (h : explicitInst fuel env d fd targs = some inst) : ExplicitInst env d fd targs inst := by
  unfold explicitInst at h
  cases ha : argsTys fuel env targs with
  | none => rw [ha] at h; cases h
  | some ts =>
    rw [ha] at h
    simp only [explicitChecked] at h
    by_cases ok : (noNames fd.implParams && decide (ts.length = fd.params.length)) = true
    · rw [if_pos ok, Option.some.injEq] at h
      simp only [Bool.and_eq_true, noNames_iff, decide_eq_true_eq] at ok
      exact ⟨ts, (tySound fuel).2.2.2.2.2.1 ha, ok.1, ok.2, h.symm⟩
    · rw [if_neg ok] at h; cases h

end Lanius.Mini.Reading
