import Lanius.Mini.Reading.Names

/-! # The reading, V8b: type expressions

`TyR env t ty`: the type expression `t`, read where `env` says (the
declarations, the current module, the type parameters in scope and the types
they stand for), names the type `ty`. A path without arguments is a type
parameter, a primitive type or a declared type without parameters, and else
a type alias; a path with arguments is a declared type of that arity, and
else an alias. An alias is read in its own module, its parameters standing
for the arguments. -/

namespace Lanius.Mini.Reading

open Lanius.Mini Lanius.Mini.Prod

/-! ## Paths -/

/-- The spellings of a type path's segments (`a::b::T`). -/
inductive TypePathSpellings : CTree → CTree → List Name → Prop
  | last {segment tail : CTree} : nodeProd segment = pTypePathIdent → nodeProd tail = pTypePathEnd →
      TypePathSpellings segment tail [(kidToken segment 0).text]
  | more {segment tail : CTree} {rest : List Name} : nodeProd segment = pTypePathIdent → nodeProd tail = pTypePathMore →
      TypePathSpellings (kid tail 2) (kid tail 3) rest →
      TypePathSpellings segment tail ((kidToken segment 0).text :: rest)

/-- The path `ss` names the item `n` of module `m`: `a::b::N` is `N` of
`a::b`, and a single segment `N` is `N` of the current module `here`. -/
def Resolves (here : ModPath) (ss : List Name) (m : ModPath) (n : Name) : Prop :=
  ∃ front, ss = front ++ [n] ∧ m = (if front = [] then here else front)

/-- The type parameter spelled `n` (the first one so spelled) stands for `t`. -/
def ParamTy (env : FrontEnv) (n : Name) (t : Ty) : Prop :=
  ∃ i, FirstWith env.names (· = n) i n ∧ env.subst[i]? = some t

/-- No type parameter in scope is spelled `n` with a type it stands for. -/
def NoParam (env : FrontEnv) (n : Name) : Prop :=
  ∀ i, FirstWith env.names (· = n) i n → env.subst[i]? = none

/-- The primitive types' spellings. -/
def primTys : List (Name × Ty) :=
  [([105, 51, 50], .tyI32), ([98, 111, 111, 108], .tyBool), ([117, 56], .tyUint .uint8),
   ([117, 51, 50], .tyUint .uint32), ([117, 54, 52], .tyUint .uint64), ([117, 115, 105, 122, 101], .tyUint .usize),
   ([112, 116, 114], .tyPtr), ([105, 115, 105, 122, 101], .tyIsize)]

/-- The path names the declared type `d`. -/
def DeclAt (env : FrontEnv) (ss : List Name) (d : Nat) : Prop :=
  ∃ m n, Resolves env.home ss m n ∧ TypeNamed env.decls m n d

/-- The path names no declared type. -/
def NoDeclAt (env : FrontEnv) (ss : List Name) : Prop :=
  ∀ m n, Resolves env.home ss m n → ∀ t ∈ env.decls.types, ¬(t.home = m ∧ t.name = n)

/-- Declared type `d` has `k` type parameters. -/
def Arity (decls : Decls) (d k : Nat) : Prop :=
  ∃ t, decls.types[d]? = some t ∧ t.params.length = k

/-- The path is not a type parameter's or a primitive type's spelling. -/
def NotScalar (env : FrontEnv) (ss : List Name) : Prop :=
  ∀ n, ss = [n] → NoParam env n ∧ primTys.lookup n = none

/-- A path without arguments that names a type without going through an
alias. -/
inductive BareTy (env : FrontEnv) : List Name → Ty → Prop
  | param {n : Name} {t : Ty} : ParamTy env n t → BareTy env [n] t
  | prim {n : Name} {t : Ty} : NoParam env n → primTys.lookup n = some t → BareTy env [n] t
  | named {ss : List Name} {d : Nat} : NotScalar env ss → DeclAt env ss d → Arity env.decls d 0 →
      BareTy env ss (.tyNamed d [])

/-- No `BareTy` reading: not a parameter or primitive, and no declared type
without parameters. -/
def NoBareTy (env : FrontEnv) (ss : List Name) : Prop :=
  NotScalar env ss ∧ ∀ d, DeclAt env ss d → ¬Arity env.decls d 0

/-- The environment an alias's type (or a declaration's field types) is
read in: the declaration's module, its parameters standing for `ts`. -/
abbrev declScope (decls : Decls) (home : ModPath) (params : List Name) (ts : List Ty) : FrontEnv :=
  { decls := decls, home := home, names := params, subst := ts, globals := [], ret := none, base := 0 }

mutual
inductive TyR : FrontEnv → CTree → Ty → Prop
  | slice {env : FrontEnv} {t : CTree} {e : Ty} : nodeProd t = pTypeArray → nodeProd (kid t 2) = pTypeSliceTail →
      TyR env (kid t 1) e → TyR env t (.tySlice e)
  | bare {env : FrontEnv} {t : CTree} {ss : List Name} {ty : Ty} : nodeProd t = pTypeIdent →
      nodeProd (kid t 1) = pTypeArgsNone → TypePathSpellings (kid (kid t 0) 0) (kid (kid t 0) 1) ss →
      BareTy env ss ty → TyR env t ty
  | bareAlias {env : FrontEnv} {t : CTree} {ss : List Name} {ty : Ty} : nodeProd t = pTypeIdent →
      nodeProd (kid t 1) = pTypeArgsNone → TypePathSpellings (kid (kid t 0) 0) (kid (kid t 0) 1) ss →
      NoBareTy env ss → AliasTy env ss [] ty → TyR env t ty
  | applied {env : FrontEnv} {t : CTree} {ss : List Name} {gs : List CTree} {ts : List Ty} {d : Nat} :
      nodeProd t = pTypeIdent → nodeProd (kid t 1) = pTypeArgsSome →
      TypePathSpellings (kid (kid t 0) 0) (kid (kid t 0) 1) ss → Items (kid t 1) gs → ArgsTy env gs ts →
      DeclAt env ss d → Arity env.decls d ts.length → TyR env t (.tyNamed d ts)
  | appliedAlias {env : FrontEnv} {t : CTree} {ss : List Name} {gs : List CTree} {ts : List Ty} {ty : Ty} :
      nodeProd t = pTypeIdent → nodeProd (kid t 1) = pTypeArgsSome →
      TypePathSpellings (kid (kid t 0) 0) (kid (kid t 0) 1) ss → Items (kid t 1) gs → ArgsTy env gs ts →
      NoDeclAt env ss → AliasTy env ss ts ty → TyR env t ty

/-- The alias the path names, at the type arguments `ts`, names `ty`. -/
inductive AliasTy : FrontEnv → List Name → List Ty → Ty → Prop
  | mk {env : FrontEnv} {ss : List Name} {ts : List Ty} {ty : Ty} {m : ModPath} {n : Name} {a : AliasDecl} :
      Resolves env.home ss m n → AliasNamed env.decls m n a → a.params.length = ts.length →
      TyR (declScope env.decls a.home a.params ts) a.ty ty → AliasTy env ss ts ty

/-- Generic arguments, each a type expression. -/
inductive ArgsTy : FrontEnv → List CTree → List Ty → Prop
  | nil {env : FrontEnv} : ArgsTy env [] []
  | cons {env : FrontEnv} {g : CTree} {rest : List CTree} {t : Ty} {ts : List Ty} :
      nodeProd g = pGenericArgumentType → TyR env (kid g 0) t → ArgsTy env rest ts → ArgsTy env (g :: rest) (t :: ts)
end

/-! ## Soundness of the path and name steps -/

theorem typePathSpellings_sound : ∀ {fuel : Nat} {segment tail : CTree} {ns : List Name},
    typePathSpellings fuel segment tail = some ns → TypePathSpellings segment tail ns
  | 0, _, _, _, h => by rw [typePathSpellings] at h; simp at h
  | fuel + 1, segment, tail, ns, h => by
    rw [typePathSpellings] at h
    simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
    by_cases one : nodeProd segment = pTypePathIdent ∧ nodeProd tail = pTypePathEnd
    · rw [if_pos (by simpa using one), Option.some.injEq] at h
      subst h
      exact .last one.1 one.2
    · rw [if_neg (by simpa using one)] at h
      by_cases two : nodeProd segment = pTypePathIdent ∧ nodeProd tail = pTypePathMore
      · rw [if_pos (by simpa using two)] at h
        simp only [consName] at h
        cases hr : typePathSpellings fuel (kid tail 2) (kid tail 3) with
        | none => rw [hr] at h; cases h
        | some rest =>
          rw [hr] at h
          simp only [consNameTail, Option.some.injEq] at h
          subst h
          exact .more two.1 two.2 (typePathSpellings_sound hr)
      · rw [if_neg (by simpa using two)] at h
        cases h

theorem firstWith_unique {α : Type} {xs : List α} {p : α → Prop} {i j : Nat} {x y : α}
    (a : FirstWith xs p i x) (b : FirstWith xs p j y) : i = j ∧ x = y := by
  obtain ⟨ai, ap, abefore⟩ := a
  obtain ⟨bj, bp, bbefore⟩ := b
  have ij : i = j := by
    rcases Nat.lt_trichotomy i j with lt | eq | gt
    · exact absurd ap (bbefore i lt x ai)
    · exact eq
    · exact absurd bp (abefore j gt y bj)
  subst ij
  exact ⟨rfl, Option.some.inj (ai.symm.trans bj)⟩

theorem firstWith_mem {α : Type} {xs : List α} {p : α → Prop} {i : Nat} {x : α} (h : FirstWith xs p i x) :
    x ∈ xs ∧ p x :=
  ⟨List.mem_of_getElem? h.1, h.2.1⟩

theorem splitLast_append : ∀ (front : List Name) (n : Name), splitLast (front ++ [n]) = some ⟨front, n⟩
  | [], n => rfl
  | f :: rest, n => by
    show splitMore f (splitLast (rest ++ [n])) = _
    rw [splitLast_append rest n]
    rfl

theorem splitLast_cons (g : Name) (more : List Name) : ∃ r, splitLast (g :: more) = some r := by
  show ∃ r, splitMore g (splitLast more) = some r
  cases splitLast more <;> simp [splitMore]

theorem splitLast_sound : ∀ {ss : List Name} {s : Split}, splitLast ss = some s → ss = s.home ++ [s.name]
  | [], _, h => by simp [splitLast] at h
  | [f], s, h => by
    simp only [splitLast, splitMore, Option.some.injEq] at h
    subst h
    rfl
  | f :: g :: more, s, h => by
    obtain ⟨r, hr⟩ := splitLast_cons g more
    have e : splitLast (f :: g :: more) = splitMore f (splitLast (g :: more)) := rfl
    rw [e, hr] at h
    simp only [splitMore, Option.some.injEq] at h
    subst h
    simp [splitLast_sound hr]

theorem moduleOr_eq (here front : ModPath) : moduleOr here front = (if front = [] then here else front) := by
  cases front <;> simp [moduleOr]

theorem resolves_split {here : ModPath} {ss : List Name} {s : Split} (h : splitLast ss = some s) :
    Resolves here ss (moduleOr here s.home) s.name :=
  ⟨s.home, splitLast_sound h, moduleOr_eq _ _⟩

theorem resolves_unique {here : ModPath} {ss : List Name} {m m' : ModPath} {n n' : Name}
    (a : Resolves here ss m n) (b : Resolves here ss m' n') : m = m' ∧ n = n' := by
  obtain ⟨f, rfl, rfl⟩ := a
  obtain ⟨f', e, rfl⟩ := b
  obtain ⟨rfl, hn⟩ := List.append_inj' e rfl
  simp at hn
  exact ⟨rfl, hn⟩

theorem resolves_split' {here : ModPath} {ss : List Name} {m : ModPath} {n : Name} (h : Resolves here ss m n) :
    splitLast ss = some ⟨ss.dropLast, n⟩ ∧ m = moduleOr here ss.dropLast := by
  obtain ⟨f, rfl, rfl⟩ := h
  rw [List.dropLast_concat, splitLast_append, moduleOr_eq]
  exact ⟨rfl, rfl⟩

theorem declAt_unique {env : FrontEnv} {ss : List Name} {d d' : Nat} (a : DeclAt env ss d) (b : DeclAt env ss d') :
    d = d' := by
  obtain ⟨m, n, ra, t, fa⟩ := a
  obtain ⟨m', n', rb, t', fb⟩ := b
  obtain ⟨rfl, rfl⟩ := resolves_unique ra rb
  exact (firstWith_unique fa fb).1

theorem typeDeclAt_sound {env : FrontEnv} {ss : List Name} {d : Nat} (h : typeDeclAt env ss = some d) :
    DeclAt env ss d := by
  unfold typeDeclAt at h
  cases hs : splitLast ss with
  | none => rw [hs] at h; cases h
  | some s =>
    rw [hs] at h
    exact ⟨_, _, resolves_split hs, findType_sound h⟩

theorem typeDeclAt_none {env : FrontEnv} {ss : List Name} (h : typeDeclAt env ss = none) : NoDeclAt env ss := by
  intro m n r
  obtain ⟨hs, rfl⟩ := resolves_split' r
  unfold typeDeclAt at h
  rw [hs] at h
  exact findType_none h

theorem noDeclAt_not {env : FrontEnv} {ss : List Name} {d : Nat} (no : NoDeclAt env ss) : ¬DeclAt env ss d := by
  rintro ⟨m, n, r, t, ft⟩
  exact no m n r t (firstWith_mem ft).1 (firstWith_mem ft).2

theorem arityOk_iff (env : FrontEnv) (d : Nat) (ts : List Ty) :
    arityOk env d ts = true ↔ Arity env.decls d ts.length := by
  unfold arityOk Arity
  cases env.decls.types[d]? <;> simp

theorem paramTy_sound {env : FrontEnv} {n : Name} {t : Ty} (h : paramTy env n = some t) : ParamTy env n t := by
  unfold paramTy at h
  cases hp : position env.names n 0 with
  | none => rw [hp] at h; cases h
  | some i => rw [hp] at h; exact ⟨i, position_sound hp, h⟩

theorem paramTy_none {env : FrontEnv} {n : Name} (h : paramTy env n = none) : NoParam env n := by
  intro i fi
  unfold paramTy at h
  cases hp : position env.names n 0 with
  | none => exact absurd (firstWith_mem fi).1 (position_none hp)
  | some j =>
    rw [hp] at h
    rw [(firstWith_unique fi (position_sound hp)).1]
    exact h

theorem lookup_bind {α β : Type} (f : α → Option β) (n : Name) :
    ∀ {tbl : List (Name × α)} {tbl' : List (Name × β)},
      ListRel (fun a b => a.1 = b.1 ∧ f a.2 = some b.2) tbl tbl' → (tbl.lookup n).bind f = tbl'.lookup n
  | _, _, .nil => rfl
  | a :: _, b :: _, .cons ⟨k, v⟩ rest => by
    simp only [List.lookup, k]
    cases n == b.1
    · exact lookup_bind f n rest
    · exact v

theorem primTy_eq (n : Name) : primTy n = primTys.lookup n := by
  unfold primTy
  rw [primitive_eq, ← lookup_bind srcTy n (tbl := primNames) (by
    repeat (first | exact .nil | refine .cons ⟨rfl, rfl⟩ ?_))]
  unfold primName
  cases List.lookup n primNames <;> rfl

theorem singleName_eq : ∀ (ss : List Name), singleName ss = (match ss with | [n] => some n | _ => none)
  | [] => rfl
  | [_] => rfl
  | _ :: _ :: _ => rfl

theorem namedOf_sound {env : FrontEnv} {ss : List Name} {ts : List Ty} {ty : Ty}
    (h : namedOf env (typeDeclAt env ss) (some ts) = some ty) :
    ∃ d, DeclAt env ss d ∧ Arity env.decls d ts.length ∧ ty = .tyNamed d ts := by
  unfold namedOf at h
  cases hd : typeDeclAt env ss with
  | none => rw [hd] at h; cases h
  | some d =>
    rw [hd] at h
    simp only [namedArgs, namedChecked] at h
    by_cases ok : arityOk env d ts = true
    · rw [if_pos ok, Option.some.injEq] at h
      exact ⟨d, typeDeclAt_sound hd, (arityOk_iff _ _ _).1 ok, h.symm⟩
    · rw [if_neg ok] at h; cases h

theorem namedOf_none {env : FrontEnv} {ss : List Name} {ts : List Ty}
    (h : namedOf env (typeDeclAt env ss) (some ts) = none) : ∀ d, DeclAt env ss d → ¬Arity env.decls d ts.length := by
  intro d' at'
  unfold namedOf at h
  cases hd : typeDeclAt env ss with
  | none => exact absurd at' (noDeclAt_not (typeDeclAt_none hd))
  | some d =>
    rw [hd] at h
    simp only [namedArgs, namedChecked] at h
    rw [← declAt_unique (typeDeclAt_sound hd) at', ← arityOk_iff]
    intro ok
    rw [if_pos ok] at h
    cases h

theorem bareTy_sound {env : FrontEnv} {ss : List Name} :
    (∀ {ty}, bareTy env ss = some ty → BareTy env ss ty) ∧ (bareTy env ss = none → NoBareTy env ss) := by
  unfold bareTy
  rw [singleName_eq]
  match ss with
  | [n] =>
    simp only
    cases hp : paramTy env n with
    | some t =>
      refine ⟨fun h => ?_, fun h => by cases h⟩
      cases h
      exact .param (paramTy_sound hp)
    | none =>
      simp only [primOrNamed]
      rw [primTy_eq]
      cases hq : primTys.lookup n with
      | some t =>
        refine ⟨fun h => ?_, fun h => by cases h⟩
        cases h
        exact .prim (paramTy_none hp) hq
      | none =>
        have ns : NotScalar env [n] := fun n' e => by
          cases e
          exact ⟨paramTy_none hp, hq⟩
        refine ⟨fun h => ?_, fun h => ⟨ns, namedOf_none h⟩⟩
        obtain ⟨d, at', ar, rfl⟩ := namedOf_sound h
        exact .named ns at' ar
  | [] =>
    have ns : NotScalar env [] := fun n' e => by cases e
    exact ⟨fun h => by
      obtain ⟨d, at', ar, rfl⟩ := namedOf_sound h
      exact .named ns at' ar, fun h => ⟨ns, namedOf_none h⟩⟩
  | a :: b :: rest =>
    have ns : NotScalar env (a :: b :: rest) := fun n' e => by cases e
    exact ⟨fun h => by
      obtain ⟨d, at', ar, rfl⟩ := namedOf_sound h
      exact .named ns at' ar, fun h => ⟨ns, namedOf_none h⟩⟩

/-! ## Soundness of the type reading -/

/-- What each function of the type reading, at a fuel, establishes. -/
def TySound (fuel : Nat) : Prop :=
  (∀ {env t ty}, tyOf fuel env t = some ty → TyR env t ty) ∧
  (∀ {env segs items ty}, appliedOf fuel env segs items = some ty →
    ∃ ss gs ts, segs = some ss ∧ items = some gs ∧ ArgsTy env gs ts ∧
      ((∃ d, DeclAt env ss d ∧ Arity env.decls d ts.length ∧ ty = .tyNamed d ts) ∨
       (NoDeclAt env ss ∧ AliasTy env ss ts ty))) ∧
  (∀ {env segs ty}, bareOrAlias fuel env segs = some ty →
    ∃ ss, segs = some ss ∧ (BareTy env ss ty ∨ (NoBareTy env ss ∧ AliasTy env ss [] ty))) ∧
  (∀ {env ss args ty}, aliasTy fuel env ss args = some ty → ∃ ts, args = some ts ∧ AliasTy env ss ts ty) ∧
  (∀ {decls a ts ty}, aliasAt fuel decls a ts = some ty →
    a.params.length = ts.length ∧ TyR (declScope decls a.home a.params ts) a.ty ty) ∧
  (∀ {env gs ts}, argsTys fuel env gs = some ts → ArgsTy env gs ts) ∧
  (∀ {env g t}, argTy fuel env g = some t → nodeProd g = pGenericArgumentType ∧ TyR env (kid g 0) t)

theorem tySound : ∀ fuel, TySound fuel
  | 0 => by
    refine ⟨?_, ?_, ?_, ?_, ?_, ?_, ?_⟩ <;> intros <;>
      first
      | (rename_i h; rw [tyOf.eq_def] at h; simp at h)
      | (rename_i h; rw [appliedOf.eq_def] at h; simp at h)
      | (rename_i h; rw [bareOrAlias.eq_def] at h; simp at h)
      | (rename_i h; rw [aliasTy.eq_def] at h; simp at h)
      | (rename_i h; rw [aliasAt.eq_def] at h; simp at h)
      | (rename_i h; rw [argsTys.eq_def] at h; simp at h)
      | (rename_i h; rw [argTy.eq_def] at h; simp at h)
  | f + 1 => by
    obtain ⟨tyOf_ih, appliedOf_ih, bareOrAlias_ih, aliasTy_ih, aliasAt_ih, argsTys_ih, argTy_ih⟩ := tySound f
    refine ⟨?_, ?_, ?_, ?_, ?_, ?_, ?_⟩
    · intro env t ty h
      rw [tyOf.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      by_cases sl : nodeProd t = pTypeArray ∧ nodeProd (kid t 2) = pTypeSliceTail
      · rw [if_pos (by simpa using sl)] at h
        simp only [sliceTy] at h
        cases he : tyOf f env (kid t 1) with
        | none => rw [he] at h; cases h
        | some e =>
          rw [he, Option.some.injEq] at h
          subst h
          exact .slice sl.1 sl.2 (tyOf_ih he)
      rw [if_neg (by simpa using sl)] at h
      by_cases bn : nodeProd t = pTypeIdent ∧ nodeProd (kid t 1) = pTypeArgsNone
      · rw [if_pos (by simpa using bn)] at h
        obtain ⟨ss, hs, r⟩ := bareOrAlias_ih h
        have sp := typePathSpellings_sound hs
        rcases r with b | ⟨nb, al⟩
        · exact .bare bn.1 bn.2 sp b
        · exact .bareAlias bn.1 bn.2 sp nb al
      rw [if_neg (by simpa using bn)] at h
      by_cases ap : nodeProd t = pTypeIdent ∧ nodeProd (kid t 1) = pTypeArgsSome
      · rw [if_pos (by simpa using ap)] at h
        obtain ⟨ss, gs, ts, hs, hg, args, r⟩ := appliedOf_ih h
        have sp := typePathSpellings_sound hs
        have its := listItems_sound hg
        rcases r with ⟨d, at', ar, rfl⟩ | ⟨nd, al⟩
        · exact .applied ap.1 ap.2 sp its args at' ar
        · exact .appliedAlias ap.1 ap.2 sp its args nd al
      rw [if_neg (by simpa using ap)] at h
      cases h
    · intro env segs items ty h
      rw [appliedOf.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      cases segs with
      | none => cases h
      | some ss =>
        cases items with
        | none => cases h
        | some gs =>
          simp only at h
          cases hd : typeDeclAt env ss with
          | some d =>
            rw [hd] at h
            simp only [namedArgs] at h
            cases ha : argsTys f env gs with
            | none => rw [ha] at h; cases h
            | some ts =>
              rw [ha] at h
              simp only [namedChecked] at h
              by_cases ok : arityOk env d ts = true
              · rw [if_pos ok, Option.some.injEq] at h
                exact ⟨ss, gs, ts, rfl, rfl, argsTys_ih ha,
                  .inl ⟨d, typeDeclAt_sound hd, (arityOk_iff _ _ _).1 ok, h.symm⟩⟩
              · rw [if_neg ok] at h; cases h
          | none =>
            rw [hd] at h
            obtain ⟨ts, ha, al⟩ := aliasTy_ih h
            exact ⟨ss, gs, ts, rfl, rfl, argsTys_ih ha, .inr ⟨typeDeclAt_none hd, al⟩⟩
    · intro env segs ty h
      rw [bareOrAlias.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      cases segs with
      | none => cases h
      | some ss =>
        simp only at h
        cases hb : bareTy env ss with
        | some t =>
          rw [hb, Option.some.injEq] at h
          subst h
          exact ⟨ss, rfl, .inl (bareTy_sound.1 hb)⟩
        | none =>
          rw [hb] at h
          obtain ⟨ts, e, al⟩ := aliasTy_ih h
          cases e
          exact ⟨ss, rfl, .inr ⟨bareTy_sound.2 hb, al⟩⟩
    · intro env ss args ty h
      rw [aliasTy.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      cases hs : splitLast ss with
      | none => rw [hs] at h; cases h
      | some s =>
        rw [hs] at h
        simp only at h
        cases hf : findAlias env.decls.aliases (moduleOr env.home s.home) s.name with
        | none => rw [hf] at h; cases h
        | some a =>
          rw [hf] at h
          cases args with
          | none => cases h
          | some ts =>
            simp only at h
            obtain ⟨len, r⟩ := aliasAt_ih h
            exact ⟨ts, rfl, .mk (resolves_split hs) (findAlias_sound hf) len r⟩
    · intro decls a ts ty h
      rw [aliasAt.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      by_cases len : a.params.length = ts.length
      · rw [if_pos len] at h
        exact ⟨len, tyOf_ih h⟩
      · rw [if_neg len] at h; cases h
    · intro env gs ts h
      rw [argsTys.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      cases gs with
      | nil =>
        simp only [Option.some.injEq] at h
        subst h
        exact .nil
      | cons g rest =>
        simp only [consTy] at h
        cases hg : argTy f env g with
        | none => rw [hg] at h; cases h
        | some t =>
          rw [hg] at h
          simp only [consTyTail] at h
          cases hr : argsTys f env rest with
          | none => rw [hr] at h; cases h
          | some tr =>
            rw [hr, Option.some.injEq] at h
            subst h
            obtain ⟨gp, r⟩ := argTy_ih hg
            exact .cons gp r (argsTys_ih hr)
    · intro env g t h
      rw [argTy.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      by_cases gp : nodeProd g = pGenericArgumentType
      · rw [if_pos gp] at h
        exact ⟨gp, tyOf_ih h⟩
      · rw [if_neg gp] at h; cases h

theorem tyOf_sound {fuel : Nat} {env : FrontEnv} {t : CTree} {ty : Ty} (h : tyOf fuel env t = some ty) :
    TyR env t ty :=
  (tySound fuel).1 h

/-- The types of a list of type expressions. -/
theorem tyList_sound : ∀ {fuel : Nat} {env : FrontEnv} {ts : List CTree} {tys : List Ty},
    tyList fuel env ts = some tys → ListRel (TyR env) ts tys
  | 0, _, _, _, h => by rw [tyList.eq_def] at h; simp at h
  | f + 1, env, ts, tys, h => by
    rw [tyList.eq_def] at h
    simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
    cases ts with
    | nil =>
      simp only [Option.some.injEq] at h
      subst h
      exact .nil
    | cons t rest =>
      simp only [consTy] at h
      cases ht : tyOf f env t with
      | none => rw [ht] at h; cases h
      | some ty =>
        rw [ht] at h
        simp only [consTyTail] at h
        cases hr : tyList f env rest with
        | none => rw [hr] at h; cases h
        | some tr =>
          rw [hr, Option.some.injEq] at h
          subst h
          exact .cons (tyOf_sound ht) (tyList_sound hr)

end Lanius.Mini.Reading
