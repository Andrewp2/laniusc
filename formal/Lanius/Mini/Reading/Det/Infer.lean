import Lanius.Mini.Reading.Det.Exprs

/-! # The reading is deterministic, F1: expression types and type arguments -/

namespace Lanius.Mini.Reading

open Lanius.Mini Lanius.Mini.Prod

theorem localWithId_unique {scope : List Local} {id : Nat} {a b : Local} (h₁ : LocalWithId scope id a)
    (h₂ : LocalWithId scope id b) : a = b := by
  obtain ⟨_, f⟩ := h₁
  obtain ⟨_, f'⟩ := h₂
  exact (firstWith_unique f f').2

theorem scalarTy_inj {s : SrcType} {a b : Ty} (h₁ : ScalarTy a s) (h₂ : ScalarTy b s) : a = b := by
  cases h₁ <;> cases h₂ <;> rfl

theorem exprTy_unique {decls : Decls} {scope : List Local} :
    ∀ {e : SrcExpr} {a b : Ty}, ExprTy decls scope e a → ExprTy decls scope e b → a = b
  | _, _, _, .int, h₂ => by cases h₂; rfl
  | _, _, _, .boolean, h₂ => by cases h₂; rfl
  | _, _, _, .unsigned, h₂ => by cases h₂; rfl
  | _, _, _, .local l, h₂ => by
    cases h₂ with
    | «local» l' => rw [localWithId_unique l l']
  | _, _, _, .field l e f j, h₂ => by
    cases h₂ with
    | field l' e' f' j' =>
      have el := localWithId_unique l l'
      subst el
      rw [e] at e'
      cases e'
      rw [fieldTys_unique f f'] at j
      rw [j] at j'
      cases j'
      rfl
  | _, _, _, .negate x, h₂ => by
    cases h₂ with
    | negate x' => exact exprTy_unique x x'
  | _, _, _, .not, h₂ => by cases h₂; rfl
  | _, _, _, .compare g, h₂ => by
    cases h₂ with
    | compare _ => rfl
    | left g' _ _ => rw [g] at g'; cases g'
    | right g' _ _ => rw [g] at g'; cases g'
  | _, _, _, .left g n x, h₂ => by
    cases h₂ with
    | compare g' => rw [g] at g'; cases g'
    | left _ _ x' => exact exprTy_unique x x'
    | right _ n' _ => rw [n] at n'; cases n'
  | _, _, _, .right g n x, h₂ => by
    cases h₂ with
    | compare g' => rw [g] at g'; cases g'
    | left _ n' _ => rw [n] at n'; cases n'
    | right _ _ x' => exact exprTy_unique x x'
  | _, _, _, .cast s, h₂ => by
    cases h₂ with
    | cast s' => exact scalarTy_inj s s'
  | _, _, _, .null, h₂ => by cases h₂; rfl

/-! ## Matching type expressions -/

theorem bindOf_unique {binds : List Bind} {n : Name} {a b : Ty} (h₁ : BindOf binds n a) (h₂ : BindOf binds n b) :
    a = b := by
  obtain ⟨_, x, f, rfl⟩ := h₁
  obtain ⟨_, y, f', rfl⟩ := h₂
  rw [(firstWith_unique f f').2]

theorem bindOf_unbound {binds : List Bind} {n : Name} {t : Ty} (h : BindOf binds n t) (u : Unbound binds n) :
    False := by
  obtain ⟨_, x, f, _⟩ := h
  exact u x (firstWith_mem f).1 (firstWith_mem f).2

theorem bindTy_unique {binds : List Bind} {n : Name} {t : Ty} {a b : List Bind} (h₁ : BindTy binds n t a)
    (h₂ : BindTy binds n t b) : a = b := by
  cases h₁ with
  | new u => cases h₂ with
    | new _ => rfl
    | same o => exact (bindOf_unbound o u).elim
  | same o => cases h₂ with
    | new u => exact (bindOf_unbound o u).elim
    | same _ => rfl

mutual
theorem matchTy_unique : ∀ {env : FrontEnv} {names : List Name} {p : CTree} {actual : Ty} {b x y : List Bind},
    MatchTy env names p actual b x → MatchTy env names p actual b y → x = y
  | _, _, _, _, _, _, _, .slice _ _ m, h₂ => by
    cases h₂ with
    | slice _ _ m' => exact matchTy_unique m m'
    | _ => prod_clash
  | _, _, _, _, _, _, _, .param _ s i ip bt, h₂ => by
    cases h₂ with
    | slice => prod_clash
    | param _ s' i' ip' bt' =>
      have es := typePathSpellings_unique s s'
      subst es
      have ei := items_unique i i'
      subst ei
      obtain ⟨e, _, _⟩ := ip
      obtain ⟨e', _, _⟩ := ip'
      rw [e] at e'
      cases e'
      exact bindTy_unique bt bt'
    | prim _ s' i' np _ =>
      rw [typePathSpellings_unique s s', items_unique i i'] at ip
      exact (np _ ip).elim
    | decl _ s' i' np _ _ _ =>
      rw [typePathSpellings_unique s s', items_unique i i'] at ip
      exact (np _ ip).elim
  | _, _, _, _, _, _, _, .prim _ s i np ipr, h₂ => by
    cases h₂ with
    | slice => prod_clash
    | param _ s' i' ip' _ =>
      rw [typePathSpellings_unique s s', items_unique i i'] at np
      exact (np _ ip').elim
    | prim => rfl
    | decl _ s' i' _ npr _ _ =>
      rw [typePathSpellings_unique s s', items_unique i i'] at ipr
      exact (npr _ ipr).elim
  | _, _, _, _, _, _, _, .decl _ s i np npr d ma, h₂ => by
    cases h₂ with
    | param _ s' i' ip' _ =>
      rw [typePathSpellings_unique s s', items_unique i i'] at np
      exact (np _ ip').elim
    | prim _ s' i' _ ipr' =>
      rw [typePathSpellings_unique s s', items_unique i i'] at npr
      exact (npr _ ipr').elim
    | decl _ s' i' _ _ _ ma' =>
      have es := typePathSpellings_unique s s'
      subst es
      have ei := items_unique i i'
      subst ei
      exact matchArgs_unique ma ma'

theorem matchArgs_unique : ∀ {env : FrontEnv} {names : List Name} {gs : List CTree} {args : List Ty} {b x y : List Bind},
    MatchArgs env names gs args b x → MatchArgs env names gs args b y → x = y
  | _, _, _, _, _, _, _, .nil, .nil => rfl
  | _, _, _, _, _, _, _, .cons _ m r, .cons _ m' r' => by
    have e := matchTy_unique m m'
    subst e
    exact matchArgs_unique r r'
end

theorem matchTys_unique {env : FrontEnv} {names : List Name} :
    ∀ {ps : List CTree} {actuals : List Ty} {b x y : List Bind},
      MatchTys env names ps actuals b x → MatchTys env names ps actuals b y → x = y
  | _, _, _, _, _, .nil, .nil => rfl
  | _, _, _, _, _, .cons m r, .cons m' r' => by
    have e := matchTy_unique m m'
    subst e
    exact matchTys_unique r r'

/-! ## Call instances -/

theorem patternOf_unique {fd : FnDecl} {p a b : CTree} (h₁ : PatternOf fd p a) (h₂ : PatternOf fd p b) : a = b := by
  cases h₁ <;> cases h₂ <;> first | rfl | prod_clash

theorem paramPatterns_unique {fd : FnDecl} {a b : List CTree} (h₁ : ParamPatterns fd a) (h₂ : ParamPatterns fd b) :
    a = b := by
  obtain ⟨i, it, r⟩ := h₁
  obtain ⟨i', it', r'⟩ := h₂
  have e := items_unique it it'
  subst e
  exact listRel_unique (R := PatternOf fd) (fun _ _ _ x y => patternOf_unique x y) r r'

theorem retPattern_unique {fd : FnDecl} {a b : CTree} (h₁ : RetPattern fd a) (h₂ : RetPattern fd b) : a = b :=
  h₁.2.trans h₂.2.symm

theorem boundArgs_unique {binds : List Bind} {names : List Name} {a b : List Ty} (h₁ : BoundArgs binds names a)
    (h₂ : BoundArgs binds names b) : a = b :=
  listRel_unique (R := fun n t => BindOf binds n t) (fun _ _ _ x y => bindOf_unique x y) h₁ h₂

theorem inferInst_unique {decls : Decls} {d : Nat} {fd : FnDecl} {start : List Bind} {argTys : Option (List Ty)}
    {expected : Ty} {a b : Inst} (h₁ : InferInst decls d fd start argTys expected a)
    (h₂ : InferInst decls d fd start argTys expected b) : a = b := by
  cases h₁ with
  | plain e => cases h₂ with
    | plain _ => rfl
    | infer ne _ _ _ _ _ _ => exact absurd e ne
  | infer ne a p m r m2 ba => cases h₂ with
    | plain e => exact absurd e ne
    | infer _ a' p' m' r' m2' ba' =>
      rw [a] at a'
      cases a'
      have ep := paramPatterns_unique p p'
      subst ep
      have e1 := matchTys_unique m m'
      subst e1
      have er := retPattern_unique r r'
      subst er
      have e2 := matchTy_unique m2 m2'
      subst e2
      rw [boundArgs_unique ba ba']

theorem explicitInst_unique {env : FrontEnv} {d : Nat} {fd : FnDecl} {targs : List CTree} {a b : Inst}
    (h₁ : ExplicitInst env d fd targs a) (h₂ : ExplicitInst env d fd targs b) : a = b := by
  obtain ⟨ts, r, _, _, rfl⟩ := h₁
  obtain ⟨ts', r', _, _, rfl⟩ := h₂
  rw [argsTy_unique r r']

end Lanius.Mini.Reading
