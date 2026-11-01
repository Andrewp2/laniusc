import Lanius.Mini.Reading.Infer

/-! # The reading is deterministic, F1: names, lists and types

Each relation of the reading gives at most one result for its inputs. This
file has the lookups (`FirstWith` and the named declarations), lists
(`ListRel`, `ItemsIn`), paths, type parameters, type declarations and type
expressions (`TyR`). -/

namespace Lanius.Mini.Reading

open Lanius.Mini Lanius.Mini.Prod

/-! ## Lookups -/

theorem typeNamed_unique {d : Decls} {m : ModPath} {n : Name} {i j : Nat}
    (h₁ : TypeNamed d m n i) (h₂ : TypeNamed d m n j) : i = j := by
  obtain ⟨_, f₁⟩ := h₁
  obtain ⟨_, f₂⟩ := h₂
  exact (firstWith_unique f₁ f₂).1

theorem fnNamed_unique {d : Decls} {m : ModPath} {n : Name} {i j : Nat}
    (h₁ : FnNamed d m n i) (h₂ : FnNamed d m n j) : i = j := by
  obtain ⟨_, f₁⟩ := h₁
  obtain ⟨_, f₂⟩ := h₂
  exact (firstWith_unique f₁ f₂).1

theorem constNamed_unique {d : Decls} {m : ModPath} {n : Name} {a b : ConstDecl}
    (h₁ : ConstNamed d m n a) (h₂ : ConstNamed d m n b) : a = b := by
  obtain ⟨_, f₁⟩ := h₁
  obtain ⟨_, f₂⟩ := h₂
  exact (firstWith_unique f₁ f₂).2

theorem aliasNamed_unique {d : Decls} {m : ModPath} {n : Name} {a b : AliasDecl}
    (h₁ : AliasNamed d m n a) (h₂ : AliasNamed d m n b) : a = b := by
  obtain ⟨_, f₁⟩ := h₁
  obtain ⟨_, f₂⟩ := h₂
  exact (firstWith_unique f₁ f₂).2

/-! ## Lists -/

theorem listRel_unique {α β : Type} {R : α → β → Prop} (h : ∀ a b b', R a b → R a b' → b = b') :
    ∀ {as : List α} {bs bs' : List β}, ListRel R as bs → ListRel R as bs' → bs = bs'
  | [], _, _, .nil, .nil => rfl
  | _ :: _, _, _, .cons r rs, .cons r' rs' => by
    have e := h _ _ _ r r'
    have e' := listRel_unique h rs rs'
    subst e e'
    rfl

theorem itemsIn_unique : ∀ {ks xs ys : List CTree}, ItemsIn ks xs → ItemsIn ks ys → xs = ys
  | [], _, _, .nil, .nil => rfl
  | _, _, _, .link l a b, .link _ a' b' => by rw [itemsIn_unique a a', itemsIn_unique b b']
  | _, _, _, .link l _ _, .item l' _ _ => by rw [l] at l'; cases l'
  | _, _, _, .link l _ _, .skip l' _ _ => by rw [l] at l'; cases l'
  | _, _, _, .item l _ _, .link l' _ _ => by rw [l] at l'; cases l'
  | _, _, _, .item _ _ b, .item _ _ b' => by rw [itemsIn_unique b b']
  | _, _, _, .item _ k _, .skip _ k' _ => by rw [k] at k'; cases k'
  | _, _, _, .skip l _ _, .link l' _ _ => by rw [l] at l'; cases l'
  | _, _, _, .skip _ k _, .item _ k' _ => by rw [k] at k'; cases k'
  | _, _, _, .skip _ _ b, .skip _ _ b' => itemsIn_unique b b'

theorem items_unique {c : CTree} {xs ys : List CTree} (h₁ : Items c xs) (h₂ : Items c ys) : xs = ys :=
  itemsIn_unique h₁ h₂

/-! ## Paths and type parameters -/

theorem pathSpellings_unique : ∀ {segment tail : CTree} {a b : ModPath},
    PathSpellings segment tail a → PathSpellings segment tail b → a = b
  | _, _, _, _, .last _ _, .last _ _ => rfl
  | _, _, _, _, .last _ e, .more _ e' _ => by rw [e] at e'; cases e'
  | _, _, _, _, .more _ e _, .last _ e' => by rw [e] at e'; cases e'
  | _, _, _, _, .more _ _ r, .more _ _ r' => by rw [pathSpellings_unique r r']

theorem typePathSpellings_unique : ∀ {segment tail : CTree} {a b : List Name},
    TypePathSpellings segment tail a → TypePathSpellings segment tail b → a = b
  | _, _, _, _, .last _ _, .last _ _ => rfl
  | _, _, _, _, .last _ e, .more _ e' _ => by rw [e] at e'; cases e'
  | _, _, _, _, .more _ e _, .last _ e' => by rw [e] at e'; cases e'
  | _, _, _, _, .more _ _ r, .more _ _ r' => by rw [typePathSpellings_unique r r']

theorem paramSpellings_unique {items : List CTree} {a b : List Name}
    (h₁ : ParamSpellings items a) (h₂ : ParamSpellings items b) : a = b :=
  listRel_unique (fun _ _ _ r r' => r.2.trans r'.2.symm) h₁ h₂

theorem typeParams_unique {t : CTree} {a b : List Name} (h₁ : TypeParams t a) (h₂ : TypeParams t b) : a = b := by
  obtain ⟨i₁, it₁, p₁⟩ := h₁
  obtain ⟨i₂, it₂, p₂⟩ := h₂
  rw [items_unique it₁ it₂] at p₁
  exact paramSpellings_unique p₁ p₂

theorem freeParams_unique {t : CTree} {a b : List Name} (h₁ : FreeParams t a) (h₂ : FreeParams t b) : a = b := by
  obtain ⟨i₁, it₁, _, p₁⟩ := h₁
  obtain ⟨i₂, it₂, _, p₂⟩ := h₂
  exact typeParams_unique ⟨i₁, it₁, p₁⟩ ⟨i₂, it₂, p₂⟩

/-! ## Type declarations -/

theorem variantPayload_unique {v : CTree} {a b : List CTree} (h₁ : VariantPayload v a) (h₂ : VariantPayload v b) :
    a = b := by
  cases h₁ with
  | unit u => cases h₂ with
    | unit => rfl
    | tuple n _ => exact absurd u n
  | tuple n i => cases h₂ with
    | unit u => exact absurd u n
    | tuple _ i' => exact items_unique i i'

theorem typeDeclR_unique {home : ModPath} {s : CTree} {a b : TypeDecl}
    (h₁ : TypeDeclR home s a) (h₂ : TypeDeclR home s b) : a = b := by
  cases h₁ with
  | struct e _ p f _ => cases h₂ with
    | struct _ _ p' f' _ => rw [freeParams_unique p p', items_unique f f']
    | enum e' => rw [e] at e'; cases e'
  | enum e _ p v pays => cases h₂ with
    | struct e' => rw [e] at e'; cases e'
    | enum _ _ p' v' pays' =>
      rw [freeParams_unique p p']
      have ev := items_unique v v'
      subst ev
      rw [listRel_unique (R := VariantPayload) (fun _ _ _ x y => variantPayload_unique x y) pays pays']

/-! ## Type expressions -/

theorem paramTy_unique {env : FrontEnv} {n : Name} {a b : Ty} (h₁ : ParamTy env n a) (h₂ : ParamTy env n b) :
    a = b := by
  obtain ⟨i, f, s⟩ := h₁
  obtain ⟨j, f', s'⟩ := h₂
  rw [(firstWith_unique f f').1] at s
  exact Option.some.inj (s.symm.trans s')

theorem paramTy_noParam {env : FrontEnv} {n : Name} {t : Ty} (h : ParamTy env n t) (no : NoParam env n) : False := by
  obtain ⟨i, f, s⟩ := h
  rw [no i f] at s
  cases s

theorem bareTy_unique {env : FrontEnv} {ss : List Name} {a b : Ty} (h₁ : BareTy env ss a) (h₂ : BareTy env ss b) :
    a = b := by
  cases h₁ with
  | param p => cases h₂ with
    | param p' => exact paramTy_unique p p'
    | prim no _ => exact (paramTy_noParam p no).elim
    | named ns => exact ((paramTy_noParam p (ns _ rfl).1)).elim
  | prim no l => cases h₂ with
    | param p' => exact (paramTy_noParam p' no).elim
    | prim _ l' => exact Option.some.inj (l.symm.trans l')
    | named ns => rw [(ns _ rfl).2] at l; cases l
  | named ns d _ => cases h₂ with
    | param p' => exact ((paramTy_noParam p' (ns _ rfl).1)).elim
    | prim _ l' => rw [(ns _ rfl).2] at l'; cases l'
    | named _ d' _ => rw [declAt_unique d d']

theorem bareTy_noBareTy {env : FrontEnv} {ss : List Name} {t : Ty} (h : BareTy env ss t) (no : NoBareTy env ss) :
    False := by
  obtain ⟨ns, nd⟩ := no
  cases h with
  | param p => exact paramTy_noParam p (ns _ rfl).1
  | prim _ l => rw [(ns _ rfl).2] at l; cases l
  | named _ d a => exact nd _ d a

theorem declAt_noDeclAt {env : FrontEnv} {ss : List Name} {d : Nat} (h : DeclAt env ss d) (no : NoDeclAt env ss) :
    False := by
  obtain ⟨m, n, r, t, f⟩ := h
  obtain ⟨at', ⟨hm, hn⟩, _⟩ := f
  exact no m n r t (List.mem_of_getElem? at') ⟨hm, hn⟩

mutual
theorem tyR_unique : ∀ {env : FrontEnv} {t : CTree} {a b : Ty}, TyR env t a → TyR env t b → a = b
  | _, _, _, _, .slice _ _ e, .slice _ _ e' => by rw [tyR_unique e e']
  | _, _, _, _, .slice _ q _, .array _ q' _ _ => by rw [q] at q'; cases q'
  | _, _, _, _, .array _ q _ _, .slice _ q' _ => by rw [q] at q'; cases q'
  | _, _, _, _, .array _ _ e l, .array _ _ e' l' => by
    rw [tyR_unique e e', Option.some.inj (l.2.2.symm.trans l'.2.2)]
  | _, _, _, _, .array p .., .bare p' .. => by rw [p] at p'; cases p'
  | _, _, _, _, .array p .., .bareAlias p' .. => by rw [p] at p'; cases p'
  | _, _, _, _, .array p .., .applied p' .. => by rw [p] at p'; cases p'
  | _, _, _, _, .array p .., .appliedAlias p' .. => by rw [p] at p'; cases p'
  | _, _, _, _, .bare p .., .array p' .. => by rw [p] at p'; cases p'
  | _, _, _, _, .bareAlias p .., .array p' .. => by rw [p] at p'; cases p'
  | _, _, _, _, .applied p .., .array p' .. => by rw [p] at p'; cases p'
  | _, _, _, _, .appliedAlias p .., .array p' .. => by rw [p] at p'; cases p'
  | _, _, _, _, .slice p _ _, .bare p' .. => by rw [p] at p'; cases p'
  | _, _, _, _, .slice p _ _, .bareAlias p' .. => by rw [p] at p'; cases p'
  | _, _, _, _, .slice p _ _, .applied p' .. => by rw [p] at p'; cases p'
  | _, _, _, _, .slice p _ _, .appliedAlias p' .. => by rw [p] at p'; cases p'
  | _, _, _, _, .bare p .., .slice p' _ _ => by rw [p] at p'; cases p'
  | _, _, _, _, .bare _ _ s b, .bare _ _ s' b' => by
    rw [typePathSpellings_unique s s'] at b
    exact bareTy_unique b b'
  | _, _, _, _, .bare _ _ s b, .bareAlias _ _ s' no _ => by
    rw [typePathSpellings_unique s s'] at b
    exact (bareTy_noBareTy b no).elim
  | _, _, _, _, .bare _ a .., .applied _ a' .. => by rw [a] at a'; cases a'
  | _, _, _, _, .bare _ a .., .appliedAlias _ a' .. => by rw [a] at a'; cases a'
  | _, _, _, _, .bareAlias p .., .slice p' _ _ => by rw [p] at p'; cases p'
  | _, _, _, _, .bareAlias _ _ s no _, .bare _ _ s' b' => by
    rw [typePathSpellings_unique s s'] at no
    exact (bareTy_noBareTy b' no).elim
  | _, _, _, _, .bareAlias _ _ s _ al, .bareAlias _ _ s' _ al' => by
    rw [typePathSpellings_unique s s'] at al
    exact aliasTy_unique al al'
  | _, _, _, _, .bareAlias _ a .., .applied _ a' .. => by rw [a] at a'; cases a'
  | _, _, _, _, .bareAlias _ a .., .appliedAlias _ a' .. => by rw [a] at a'; cases a'
  | _, _, _, _, .applied p .., .slice p' _ _ => by rw [p] at p'; cases p'
  | _, _, _, _, .applied _ a .., .bare _ a' .. => by rw [a] at a'; cases a'
  | _, _, _, _, .applied _ a .., .bareAlias _ a' .. => by rw [a] at a'; cases a'
  | _, _, _, _, .applied _ _ s i g d _, .applied _ _ s' i' g' d' _ => by
    rw [typePathSpellings_unique s s'] at d
    rw [items_unique i i'] at g
    rw [argsTy_unique g g', declAt_unique d d']
  | _, _, _, _, .applied _ _ s _ _ d _, .appliedAlias _ _ s' _ _ no _ => by
    rw [typePathSpellings_unique s s'] at d
    exact (declAt_noDeclAt d no).elim
  | _, _, _, _, .appliedAlias p .., .slice p' _ _ => by rw [p] at p'; cases p'
  | _, _, _, _, .appliedAlias _ a .., .bare _ a' .. => by rw [a] at a'; cases a'
  | _, _, _, _, .appliedAlias _ a .., .bareAlias _ a' .. => by rw [a] at a'; cases a'
  | _, _, _, _, .appliedAlias _ _ s _ _ no _, .applied _ _ s' _ _ d' _ => by
    rw [typePathSpellings_unique s s'] at no
    exact (declAt_noDeclAt d' no).elim
  | _, _, _, _, .appliedAlias _ _ s i g _ al, .appliedAlias _ _ s' i' g' _ al' => by
    rw [typePathSpellings_unique s s'] at al
    rw [items_unique i i'] at g
    rw [argsTy_unique g g'] at al
    exact aliasTy_unique al al'

theorem aliasTy_unique : ∀ {env : FrontEnv} {ss : List Name} {ts : List Ty} {a b : Ty},
    AliasTy env ss ts a → AliasTy env ss ts b → a = b
  | _, _, _, _, _, .mk r n _ t, .mk r' n' _ t' => by
    obtain ⟨rfl, rfl⟩ := resolves_unique r r'
    rw [aliasNamed_unique n n'] at t
    exact tyR_unique t t'

theorem argsTy_unique : ∀ {env : FrontEnv} {gs : List CTree} {a b : List Ty},
    ArgsTy env gs a → ArgsTy env gs b → a = b
  | _, _, _, _, .nil, .nil => rfl
  | _, _, _, _, .cons _ t r, .cons _ t' r' => by rw [tyR_unique t t', argsTy_unique r r']
end

end Lanius.Mini.Reading
