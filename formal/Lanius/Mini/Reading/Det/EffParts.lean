import Lanius.Mini.Reading.Det.Agree

/-! # The reading is deterministic, F1: the parts of effectful expressions

Result types, effectful expressions' types, paths, variants by path, and
the expected types, bindings and instances of calls each have one value. -/

namespace Lanius.Mini.Reading

open Lanius.Mini Lanius.Mini.Prod

theorem instRet_unique {decls : Decls} {inst : Inst} {a b : Ty} (h₁ : InstRet decls inst a)
    (h₂ : InstRet decls inst b) : a = b := by
  cases h₁ with
  | diverge f d l =>
    cases h₂ with
    | diverge f' d' l' => rw [l] at l'; cases l'; rfl
    | ret f' d' _ _ => rw [f] at f'; cases f'; rw [d] at d'; cases d'
    | projection f' _ _ _ _ => rw [f] at f'; cases f'
  | ret f d r t =>
    cases h₂ with
    | diverge f' d' _ => rw [f] at f'; cases f'; rw [d] at d'; cases d'
    | ret f' d' r' t' =>
      rw [f] at f'
      cases f'
      rw [retPattern_unique r r'] at t
      exact tyR_unique t t'
    | projection f' _ _ _ _ => rw [f] at f'; cases f'
  | projection f a e fs g =>
    cases h₂ with
    | diverge f' _ _ => rw [f] at f'; cases f'
    | ret f' _ _ _ => rw [f] at f'; cases f'
    | projection _ a' e' fs' g' =>
      rw [a] at a'
      cases a'
      rw [e] at e'
      cases e'
      rw [fieldTys_unique fs fs'] at g
      rw [g] at g'
      cases g'
      rfl

theorem effTy_unique {decls : Decls} {scope : List Local} :
    ∀ {x : MEff} {a b : Ty}, EffTy decls scope x a → EffTy decls scope x b → a = b
  | _, _, _, .pure p, h₂ => by cases h₂ with | pure p' => exact exprTy_unique p p'
  | _, _, _, .call r, h₂ => by cases h₂ with | call r' => exact instRet_unique r r'
  | _, _, _, .compare g, h₂ => by
    cases h₂ with
    | compare _ => rfl
    | left g' _ _ => rw [g] at g'; cases g'
    | right g' _ _ => rw [g] at g'; cases g'
  | _, _, _, .left g bl l, h₂ => by
    cases h₂ with
    | compare g' => rw [g] at g'; cases g'
    | left _ _ l' => exact effTy_unique l l'
    | right _ bl' _ => rw [bl] at bl'; cases bl'
  | _, _, _, .right g bl r, h₂ => by
    cases h₂ with
    | compare g' => rw [g] at g'; cases g'
    | left _ bl' _ => rw [bl] at bl'; cases bl'
    | right _ _ r' => exact effTy_unique r r'
  | _, _, _, .neg a, h₂ => by cases h₂ with | neg a' => exact effTy_unique a a'
  | _, _, _, .not, h₂ => by cases h₂; rfl
  | _, _, _, .cast s, h₂ => by cases h₂ with | cast s' => exact scalarTy_inj s s'
  | _, _, _, .index lw e, h₂ => by
    cases h₂ with
    | index lw' e' =>
      rw [localWithId_unique lw lw', e'] at e
      cases e
      rfl
  | _, _, _, .struct, h₂ => by cases h₂; rfl
  | _, _, _, .variant, h₂ => by cases h₂; rfl
  | _, _, _, .match, h₂ => by cases h₂; rfl
  | _, _, _, .divideLeft bl l, h₂ => by
    cases h₂ with
    | divideLeft _ l' => exact effTy_unique l l'
    | divideRight bl' _ => rw [bl] at bl'; cases bl'
  | _, _, _, .divideRight bl r, h₂ => by
    cases h₂ with
    | divideLeft bl' _ => rw [bl] at bl'; cases bl'
    | divideRight _ r' => exact effTy_unique r r'
  | _, _, _, .stride, h₂ => by cases h₂; rfl
  | _, _, _, .host, h₂ => by cases h₂; rfl

theorem effTys_unique {decls : Decls} {scope : List Local} {xs : List MEff} {a b : List Ty}
    (h₁ : ListRel (EffTy decls scope) xs a) (h₂ : ListRel (EffTy decls scope) xs b) : a = b :=
  listRel_unique (R := EffTy decls scope) (fun _ _ _ x y => effTy_unique x y) h₁ h₂

theorem pathRefR_unique : ∀ {segment tail : CTree} {a b : PathRef},
    PathRefR segment tail a → PathRefR segment tail b → a = b
  | _, _, _, _, .last _ _, .last _ _ => rfl
  | _, _, _, _, .last p _, .args p' _ _ => by prod_clash
  | _, _, _, _, .last _ t, .more _ t' _ => by prod_clash
  | _, _, _, _, .args p _ _, .last p' _ => by prod_clash
  | _, _, _, _, .args _ _ i, .args _ _ i' => by rw [items_unique i i']
  | _, _, _, _, .args p _ _, .more p' _ _ => by prod_clash
  | _, _, _, _, .more _ t _, .last _ t' => by prod_clash
  | _, _, _, _, .more p _ _, .args p' _ _ => by prod_clash
  | _, _, _, _, .more _ _ r, .more _ _ r' => by rw [pathRefR_unique r r']

theorem typeOwner_unique {env : FrontEnv} {front : ModPath} {a b : Name} (h₁ : TypeOwner env front a)
    (h₂ : TypeOwner env front b) : a = b := by
  have e := h₁.1.symm.trans h₂.1
  cases e
  rfl

theorem ownerTy_unique {env : FrontEnv} {n : Name} {a b : Ty} (h₁ : OwnerTy env n a) (h₂ : OwnerTy env n b) :
    a = b := by
  rcases h₁ with p | ⟨np, l⟩ | ⟨np, l, d, at', -, rfl⟩ <;>
    rcases h₂ with p' | ⟨np', l'⟩ | ⟨np', l', d', at'', -, rfl⟩
  · exact paramTy_unique p p'
  · exact (paramTy_noParam p np').elim
  · exact (paramTy_noParam p np').elim
  · exact (paramTy_noParam p' np).elim
  · rw [l] at l'
    cases l'
    rfl
  · rw [l] at l'
    cases l'
  · exact (paramTy_noParam p' np).elim
  · rw [l] at l'
    cases l'
  · rw [declAt_unique at' at'']

theorem bareVariant_unique {d : Decls} {m : ModPath} {name : Name} {a b : VariantAt}
    (h₁ : BareVariant d m name a) (h₂ : BareVariant d m name b) : a = b := by
  cases h₁ with
  | item i h =>
    cases h₂ with
    | item i' h' => rw [i] at i'; cases i'; rw [h] at h'; cases h'; rfl
    | here i' _ => rw [i] at i'; cases i'
    | imported i' _ _ => rw [i] at i'; cases i'
  | here i h =>
    cases h₂ with
    | item i' _ => rw [i] at i'; cases i'
    | here _ h' => rw [h] at h'; cases h'; rfl
    | imported _ h' _ => rw [h] at h'; cases h'
  | imported i h k =>
    cases h₂ with
    | item i' _ => rw [i] at i'; cases i'
    | here _ h' => rw [h] at h'; cases h'
    | imported _ _ k' => rw [k] at k'; cases k'; rfl

theorem enumVariant_unique {env : FrontEnv} {front : ModPath} {name : Name} {a b : VariantAt}
    (h₁ : EnumVariant env front name a) (h₂ : EnumVariant env front name b) : a = b := by
  obtain ⟨da, t, ta, _, fa⟩ := h₁
  obtain ⟨db, t', tb, _, fb⟩ := h₂
  have eo := declAt_unique da db
  rw [eo] at ta
  rw [ta] at tb
  cases tb
  have ei := (firstWith_unique fa fb).1
  cases a
  cases b
  simp only at eo ei
  rw [eo, ei]

theorem variantByPath_unique {env : FrontEnv} {front : ModPath} {name : Name} {a b : VariantAt}
    (h₁ : VariantByPath env front name a) (h₂ : VariantByPath env front name b) : a = b := by
  cases h₁ with
  | bare f bv =>
    cases h₂ with
    | bare _ bv' => exact bareVariant_unique bv bv'
    | enum f' _ => exact absurd f f'
    | module f' _ _ => exact absurd f f'
  | enum f ev =>
    cases h₂ with
    | bare f' _ => exact absurd f' f
    | enum _ ev' => exact enumVariant_unique ev ev'
    | module _ ne _ => exact (ne ⟨a, ev⟩).elim
  | module f ne vs =>
    cases h₂ with
    | bare f' _ => exact absurd f' f
    | enum _ ev' => exact (ne ⟨b, ev'⟩).elim
    | module _ _ vs' => rw [vs] at vs'; cases vs'; rfl

theorem knownTys_unique {P : List Ty → List Ty → Prop} (hp : ∀ args a b, P args a → P args b → a = b)
    {known E E' : Option (List Ty)} (h₁ : KnownTys P known E) (h₂ : KnownTys P known E') : E = E' := by
  rcases h₁ with ⟨kn, rfl⟩ | ⟨args, ts, rfl, p, rfl⟩ <;> rcases h₂ with ⟨kn', rfl⟩ | ⟨args', ts', e, p', rfl⟩
  · rfl
  · rw [kn] at e; cases e
  · cases kn'
  · cases e
    rw [hp _ _ _ p p']

theorem paramExpects_unique {decls : Decls} {fd : FnDecl} {args a b : List Ty} (h₁ : ParamExpects decls fd args a)
    (h₂ : ParamExpects decls fd args b) : a = b := by
  obtain ⟨ps, pp, r⟩ := h₁
  obtain ⟨ps', pp', r'⟩ := h₂
  rw [paramPatterns_unique pp pp'] at r
  exact listRel_unique (R := TyR _) (fun _ _ _ x y => tyR_unique x y) r r'

theorem argExpected_unique {decls : Decls} {fd : FnDecl} {names : List Name} {p : CTree} {b : List Bind} {s t : Ty}
    (h₁ : ArgExpected decls fd names p b s) (h₂ : ArgExpected decls fd names p b t) : s = t := by
  obtain ⟨args, ba, r⟩ := h₁
  obtain ⟨args', ba', r'⟩ := h₂
  rw [boundArgs_unique ba ba'] at r
  exact tyR_unique r r'

theorem argHint_unique {decls : Decls} {fd : FnDecl} {names : List Name} {p : CTree} {b : List Bind}
    {E E' : Option Ty} (h₁ : ArgHint decls fd names p b E) (h₂ : ArgHint decls fd names p b E') : E = E' := by
  rcases h₁ with ⟨nb, rfl⟩ | ⟨t, ae, rfl⟩ <;> rcases h₂ with ⟨nb', rfl⟩ | ⟨t', ae', rfl⟩
  · rfl
  · obtain ⟨args, ba, _⟩ := ae'
    exact (nb args ba).elim
  · obtain ⟨args, ba, _⟩ := ae
    exact (nb' args ba).elim
  · rw [argExpected_unique ae ae']

theorem retBinds_unique {decls : Decls} {fd : FnDecl} {names : List Name} {start : List Bind}
    {expected : Option Ty} {a b : List Bind} (h₁ : RetBinds decls fd names start expected a)
    (h₂ : RetBinds decls fd names start expected b) : a = b := by
  rcases h₁ with ⟨rfl, rfl⟩ | ⟨t, r, rfl, rp, m⟩ <;> rcases h₂ with ⟨e, rfl⟩ | ⟨t', r', e, rp', m'⟩
  · rfl
  · cases e
  · cases e
  · cases e
    rw [retPattern_unique rp rp'] at m
    exact matchTy_unique m m'

theorem bindArg_unique {decls : Decls} {scope : List Local} {fd : FnDecl} {names : List Name} {p : CTree}
    {x : MEff} {b c c' : List Bind} (h₁ : BindArg decls scope fd names p x b c)
    (h₂ : BindArg decls scope fd names p x b c') : c = c' := by
  cases h₁ with
  | bare e =>
    cases h₂ with
    | bare _ => rfl
    | typed e' _ _ => rw [e] at e'; cases e'
  | typed e t m =>
    cases h₂ with
    | bare e' => rw [e] at e'; cases e'
    | typed _ t' m' =>
      rw [effTy_unique t t'] at m
      exact matchTy_unique m m'

theorem declInst_unique {decls : Decls} {scope : List Local} {d : Nat} {t : TypeDecl} {known : Option (List Ty)}
    {ps : Option (List CTree)} {vs : List MEff} {a b : Ty} (h₁ : DeclInst decls scope d t known ps vs a)
    (h₂ : DeclInst decls scope d t known ps vs b) : a = b := by
  cases h₁ with
  | known => cases h₂; rfl
  | inferred r m ba =>
    cases h₂ with
    | inferred r' m' ba' =>
      rw [effTys_unique r r'] at m
      rw [matchTys_unique m m'] at ba
      rw [boundArgs_unique ba ba']

theorem instBound_unique {decls : Decls} {scope : List Local} {d : Nat} {fd : FnDecl} {names : List Name}
    {ps : List CTree} {a : ArgsBound} {i j : Inst} (h₁ : InstBound decls scope d fd names ps a i)
    (h₂ : InstBound decls scope d fd names ps a j) : i = j := by
  cases h₁ with
  | bound ba =>
    cases h₂ with
    | bound ba' => rw [boundArgs_unique ba ba']
    | relit nb _ _ _ => exact (nb _ ba).elim
  | relit nb r m ba =>
    cases h₂ with
    | bound ba' => exact (nb _ ba').elim
    | relit _ r' m' ba' =>
      rw [effTys_unique r r'] at m
      rw [matchTys_unique m m'] at ba
      rw [boundArgs_unique ba ba']

end Lanius.Mini.Reading
