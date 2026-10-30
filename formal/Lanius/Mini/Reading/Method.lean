import Lanius.Mini.Reading.Det.Infer

/-! # The reading, F1: the method a call names

A method call's function is the one method of that spelling whose impl's
type matches the receiver's (`MethodFor`). The builder decides it with a
three-valued match (`fitTy`): the impl's type fits, binding its parameters;
it does not fit (`misfit`), which is proved by fuel induction with no
adequacy bound; or the match ran out of fuel (`spent`), which rejects the
call. So `MethodFor` states that the method is the only one, and the
reading of a method call is exact. -/

namespace Lanius.Mini.Reading

open Lanius.Mini Lanius.Mini.Prod

theorem isParam_unique {names ss : List Name} {gs : List CTree} {n n' : Name} (h₁ : IsParam names ss gs n)
    (h₂ : IsParam names ss gs n') : n = n' := by
  obtain ⟨e, _, _⟩ := h₁
  obtain ⟨e', _, _⟩ := h₂
  rw [e] at e'
  cases e'
  rfl

theorem isPrim_unique {ss : List Name} {gs : List CTree} {t t' : Ty} (h₁ : IsPrim ss gs t) (h₂ : IsPrim ss gs t') :
    t = t' := by
  obtain ⟨m, e, _, l⟩ := h₁
  obtain ⟨m', e', _, l'⟩ := h₂
  rw [e] at e'
  cases e'
  rw [l] at l'
  cases l'
  rfl

theorem bindTy_none {binds : List Bind} {n : Name} {actual : Ty} {b' : List Bind}
    (h : bindTy binds n actual = none) (m : BindTy binds n actual b') : False := by
  unfold bindTy at h
  cases hf : findBind binds n with
  | none => rw [hf] at h; cases h
  | some t =>
    rw [hf] at h
    simp only [sameOrNone] at h
    have o := findBind_sound hf
    cases m with
    | new u => exact bindOf_unbound o u
    | same o' =>
      rw [bindOf_unique o o', if_pos ((sameTy_iff _ _).2 rfl)] at h
      cases h

/-- What each matcher's fit and misfit say. -/
def FitSound (fuel : Nat) : Prop :=
  (∀ {env names p actual b},
    (∀ {b'}, fitTy fuel env names p actual b = .fits b' → MatchTy env names p actual b b') ∧
    (fitTy fuel env names p actual b = .misfit → ∀ b', ¬MatchTy env names p actual b b')) ∧
  (∀ {env names segs items actual b},
    (∀ {b'}, fitPath fuel env names segs items actual b = .fits b' →
      ∃ ss gs, segs = some ss ∧ items = some gs ∧ NamedMatch env names ss gs actual b b') ∧
    (fitPath fuel env names segs items actual b = .misfit →
      ∃ ss gs, segs = some ss ∧ items = some gs ∧ ∀ b', ¬NamedMatch env names ss gs actual b b')) ∧
  (∀ {env names ss gs actual b},
    (∀ {b'}, fitNamed fuel env names ss gs actual b = .fits b' → NamedMatch env names ss gs actual b b') ∧
    (fitNamed fuel env names ss gs actual b = .misfit → ∀ b', ¬NamedMatch env names ss gs actual b b')) ∧
  (∀ {env names dOpt items aOpt b},
    (∀ {b'}, fitDecl fuel env names dOpt items aOpt b = .fits b' →
      ∃ d a, dOpt = some d ∧ aOpt = some a ∧ d = a.decl ∧ MatchArgs env names items a.args b b') ∧
    (fitDecl fuel env names dOpt items aOpt b = .misfit →
      ∀ b', ¬∃ d a, dOpt = some d ∧ aOpt = some a ∧ d = a.decl ∧ MatchArgs env names items a.args b b')) ∧
  (∀ {env names same items args b},
    (∀ {b'}, fitSameDecl fuel env names same items args b = .fits b' →
      same = true ∧ MatchArgs env names items args b b') ∧
    (fitSameDecl fuel env names same items args b = .misfit →
      ∀ b', ¬(same = true ∧ MatchArgs env names items args b b'))) ∧
  (∀ {env names items actuals b},
    (∀ {b'}, fitArgs fuel env names items actuals b = .fits b' → MatchArgs env names items actuals b b') ∧
    (fitArgs fuel env names items actuals b = .misfit → ∀ b', ¬MatchArgs env names items actuals b b')) ∧
  (∀ {env names g a b},
    (∀ {b'}, fitArg fuel env names g a b = .fits b' →
      nodeProd g = pGenericArgumentType ∧ MatchTy env names (kid g 0) a b b') ∧
    (fitArg fuel env names g a b = .misfit →
      ∀ b', ¬(nodeProd g = pGenericArgumentType ∧ MatchTy env names (kid g 0) a b b'))) ∧
  (∀ {env names items actuals got},
    (∀ {b'}, fitArgsNext fuel env names items actuals got = .fits b' →
      ∃ b, got = .fits b ∧ MatchArgs env names items actuals b b') ∧
    (fitArgsNext fuel env names items actuals got = .misfit →
      got = .misfit ∨ ∃ b, got = .fits b ∧ ∀ b', ¬MatchArgs env names items actuals b b'))

theorem fitSound : ∀ fuel, FitSound fuel
  | 0 => by
    refine ⟨?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_⟩ <;> intros <;> refine ⟨fun h => ?_, fun h => ?_⟩ <;>
      first
      | (rw [fitTy.eq_def] at h; simp at h)
      | (rw [fitPath.eq_def] at h; simp at h)
      | (rw [fitNamed.eq_def] at h; simp at h)
      | (rw [fitDecl.eq_def] at h; simp at h)
      | (rw [fitSameDecl.eq_def] at h; simp at h)
      | (rw [fitArgs.eq_def] at h; simp at h)
      | (rw [fitArg.eq_def] at h; simp at h)
      | (rw [fitArgsNext.eq_def] at h; simp at h)
  | f + 1 => by
    obtain ⟨ty_ih, path_ih, named_ih, decl_ih, same_ih, args_ih, arg_ih, argsNext_ih⟩ := fitSound f
    refine ⟨?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_⟩
    · intro env names p actual b
      rw [fitTy.eq_def]
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel]
      by_cases sl : nodeProd p = pTypeArray ∧ nodeProd (kid p 2) = pTypeSliceTail
      · rw [if_pos (by simpa using sl)]
        have s1 := sl.1
        cases actual with
        | tySlice a =>
          simp only [sliceElem]
          refine ⟨fun h => .slice sl.1 sl.2 (ty_ih.1 h), fun h b' m => ?_⟩
          cases m with
          | slice _ _ m => exact ty_ih.2 h _ m
          | _ => prod_clash
        | _ =>
          simp only [sliceElem]
          refine ⟨fun h => (by cases h), fun _ b' m => ?_⟩
          cases m <;> prod_clash
      rw [if_neg (by simpa using sl)]
      by_cases ti : nodeProd p = pTypeIdent
      · rw [if_pos ti]
        refine ⟨fun h => ?_, fun h b' m => ?_⟩
        · obtain ⟨ss, gs, hs, hg, r⟩ := path_ih.1 h
          have sp := typePathSpellings_sound hs
          have its := listItems_sound hg
          rcases r with ⟨n, ip, bt⟩ | ⟨np, pr, rfl⟩ | ⟨np, nr, d, args, rfl, da, ma⟩
          · exact .param ti sp its ip bt
          · exact .prim ti sp its np pr
          · exact .decl ti sp its np nr da ma
        · obtain ⟨ss, gs, hs, hg, nm⟩ := path_ih.2 h
          have sp := typePathSpellings_sound hs
          have its := listItems_sound hg
          cases m with
          | slice s1 _ _ => prod_clash
          | param _ sp' its' ip bt =>
            have e := typePathSpellings_unique sp' sp
            subst e
            have e := items_unique its' its
            subst e
            exact nm _ (.inl ⟨_, ip, bt⟩)
          | prim _ sp' its' np pr =>
            have e := typePathSpellings_unique sp' sp
            subst e
            have e := items_unique its' its
            subst e
            exact nm _ (.inr (.inl ⟨np, pr, rfl⟩))
          | decl _ sp' its' np nr da ma =>
            have e := typePathSpellings_unique sp' sp
            subst e
            have e := items_unique its' its
            subst e
            exact nm _ (.inr (.inr ⟨np, nr, _, _, rfl, da, ma⟩))
      · rw [if_neg ti]
        refine ⟨fun h => (by cases h), fun _ b' m => ?_⟩
        cases m with
        | slice s1 s2 _ => exact sl ⟨s1, s2⟩
        | param ti' _ _ _ _ => exact ti ti'
        | prim ti' _ _ _ _ => exact ti ti'
        | decl ti' _ _ _ _ _ _ => exact ti ti'
    · intro env names segs items actual b
      rw [fitPath.eq_def]
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel]
      cases segs with
      | none => exact ⟨fun h => (by cases h), fun h => (by cases h)⟩
      | some ss =>
        cases items with
        | none => exact ⟨fun h => (by cases h), fun h => (by cases h)⟩
        | some gs => exact ⟨fun h => ⟨ss, gs, rfl, rfl, named_ih.1 h⟩, fun h => ⟨ss, gs, rfl, rfl, named_ih.2 h⟩⟩
    · intro env names ss gs actual b
      rw [fitNamed.eq_def]
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel]
      cases hp : paramSpelling names ss gs with
      | some n =>
        have ip := paramSpelling_sound.1 hp
        simp only [fitOf]
        cases hb : bindTy b n actual with
        | some b1 =>
          simp only
          refine ⟨fun h => ?_, fun h => (by cases h)⟩
          cases h
          exact .inl ⟨n, ip, bindTy_sound hb⟩
        | none =>
          simp only
          refine ⟨fun h => (by cases h), fun _ b' m => ?_⟩
          rcases m with ⟨n', ip', bt⟩ | ⟨np, _⟩ | ⟨np, _⟩
          · have e := isParam_unique ip ip'
            subst e
            exact bindTy_none hb bt
          · exact np n ip
          · exact np n ip
      | none =>
        have np := paramSpelling_sound.2 hp
        cases hq : barePrim ss gs with
        | some t =>
          simp only [fitIf]
          by_cases s : sameTy t actual = true
          · rw [if_pos s]
            rw [(sameTy_iff _ _).1 s] at hq
            refine ⟨fun h => ?_, fun h => (by cases h)⟩
            cases h
            exact .inr (.inl ⟨np, barePrim_sound.1 hq, rfl⟩)
          · rw [if_neg s]
            refine ⟨fun h => (by cases h), fun _ b' m => ?_⟩
            rcases m with ⟨n, ip, _⟩ | ⟨_, pr, _⟩ | ⟨_, nr, _⟩
            · exact np n ip
            · exact s ((sameTy_iff _ _).2 (isPrim_unique (barePrim_sound.1 hq) pr))
            · exact nr t (barePrim_sound.1 hq)
        | none =>
          simp only
          have nr := barePrim_sound.2 hq
          refine ⟨fun h => ?_, fun h b' m => ?_⟩
          · obtain ⟨d, a, hd, ha, rfl, ma⟩ := decl_ih.1 h
            refine .inr (.inr ⟨np, nr, a.decl, a.args, ?_, typeDeclAt_sound hd, ma⟩)
            unfold namedParts at ha
            cases actual with
            | tyNamed x ys => simp only [Option.some.injEq] at ha; subst ha; rfl
            | tyI32 => cases ha
            | tyBool => cases ha
            | tyUint _ => cases ha
            | tyPtr => cases ha
            | tyIsize => cases ha
            | tySint _ => cases ha
            | tySlice _ => cases ha
          · rcases m with ⟨n, ip, _⟩ | ⟨_, pr, _⟩ | ⟨_, _, d, args, rfl, da, ma⟩
            · exact np n ip
            · exact nr _ pr
            · cases hd : typeDeclAt env ss with
              | none => exact declAt_noDeclAt da (typeDeclAt_none hd)
              | some d' =>
                have e := declAt_unique da (typeDeclAt_sound hd)
                subst e
                rw [hd] at h
                exact decl_ih.2 h b' ⟨d, ⟨d, args⟩, rfl, rfl, rfl, ma⟩
    · intro env names dOpt items aOpt b
      rw [fitDecl.eq_def]
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel]
      cases dOpt with
      | none => exact ⟨fun h => (by cases h), fun _ b' ⟨_, _, e, _⟩ => (by cases e)⟩
      | some d =>
        cases aOpt with
        | none => exact ⟨fun h => (by cases h), fun _ b' ⟨_, _, _, e, _⟩ => (by cases e)⟩
        | some a =>
          refine ⟨fun h => ?_, fun h b' ⟨d', a', e1, e2, e3, ma⟩ => ?_⟩
          · obtain ⟨same, ma⟩ := same_ih.1 h
            exact ⟨d, a, rfl, rfl, by simpa using same, ma⟩
          · cases e1
            cases e2
            exact same_ih.2 h b' ⟨by simpa using e3, ma⟩
    · intro env names same items args b
      rw [fitSameDecl.eq_def]
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel]
      cases same with
      | true => exact ⟨fun h => ⟨rfl, args_ih.1 h⟩, fun h b' ⟨_, ma⟩ => args_ih.2 h b' ma⟩
      | false => exact ⟨fun h => (by cases h), fun _ b' ⟨e, _⟩ => (by cases e)⟩
    · intro env names items actuals b
      rw [fitArgs.eq_def]
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel]
      cases items with
      | nil =>
        cases actuals with
        | nil => exact ⟨fun h => (by cases h; exact .nil), fun h => (by cases h)⟩
        | cons _ _ => exact ⟨fun h => (by cases h), fun _ b' m => (by cases m)⟩
      | cons g rest =>
        cases actuals with
        | nil => exact ⟨fun h => (by cases h), fun _ b' m => (by cases m)⟩
        | cons a more =>
          simp only
          refine ⟨fun h => ?_, fun h b' m => ?_⟩
          · obtain ⟨b1, hb, ma⟩ := argsNext_ih.1 h
            obtain ⟨gp, mt⟩ := arg_ih.1 hb
            exact .cons gp mt ma
          · cases m with
            | cons gp mt ma =>
              rcases argsNext_ih.2 h with hg | ⟨b1, hg, nm⟩
              · exact arg_ih.2 hg _ ⟨gp, mt⟩
              · obtain ⟨_, mt'⟩ := arg_ih.1 hg
                have e := matchTy_unique mt mt'
                subst e
                exact nm _ ma
    · intro env names g a b
      rw [fitArg.eq_def]
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel]
      by_cases gp : nodeProd g = pGenericArgumentType
      · rw [if_pos gp]
        exact ⟨fun h => ⟨gp, ty_ih.1 h⟩, fun h b' ⟨_, mt⟩ => ty_ih.2 h b' mt⟩
      · rw [if_neg gp]
        exact ⟨fun h => (by cases h), fun _ b' ⟨g', _⟩ => gp g'⟩
    · intro env names items actuals got
      rw [fitArgsNext.eq_def]
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel]
      cases got with
      | fits b => exact ⟨fun h => ⟨b, rfl, args_ih.1 h⟩, fun h => .inr ⟨b, rfl, args_ih.2 h⟩⟩
      | misfit => exact ⟨fun h => (by cases h), fun _ => .inl rfl⟩
      | spent => exact ⟨fun h => (by cases h), fun h => (by cases h)⟩

/-! ## Methods -/

/-- The impl of method `fd` is for a type that matches `s`, binding its
parameters. -/
def ImplBinds (decls : Decls) (fd : FnDecl) (s : Ty) (b : List Bind) : Prop :=
  fd.inImpl = true ∧ MatchTy (calleeScope decls fd) fd.implParams fd.selfType s [] b

theorem implBinds_unique {decls : Decls} {fd : FnDecl} {s : Ty} {a b : List Bind} (h₁ : ImplBinds decls fd s a)
    (h₂ : ImplBinds decls fd s b) : a = b :=
  matchTy_unique h₁.2 h₂.2

theorem implFit_fits {fuel : Nat} {decls : Decls} {fd : FnDecl} {s : Ty} {b : List Bind}
    (h : implFit fuel decls fd s = .fits b) : ImplBinds decls fd s b := by
  unfold implFit at h
  by_cases ii : fd.inImpl = true
  · rw [if_pos ii] at h
    exact ⟨ii, (fitSound fuel).1.1 h⟩
  · rw [if_neg ii] at h; cases h

theorem implFit_misfit {fuel : Nat} {decls : Decls} {fd : FnDecl} {s : Ty}
    (h : implFit fuel decls fd s = .misfit) (b : List Bind) : ¬ImplBinds decls fd s b := by
  intro ⟨ii, m⟩
  unfold implFit at h
  rw [if_pos ii] at h
  exact (fitSound fuel).1.2 h b m

theorem isMisfit_iff (f : Fit) : isMisfit f = true ↔ f = .misfit := by
  cases f <;> simp [isMisfit]

theorem noMethod_sound {fuel : Nat} {decls : Decls} {name : Name} {s : Ty} :
    ∀ {fns : List FnDecl}, noMethod fuel decls fns name s = true →
      ∀ (j : Nat) fd b, fns[j]? = some fd → fd.name = name → ¬ImplBinds decls fd s b
  | [], _, _, _, _, e, _ => by simp at e
  | fd :: rest, h, j, g, b, e, n => by
    simp only [noMethod, Bool.and_eq_true, Bool.or_eq_true, Bool.not_eq_true'] at h
    obtain ⟨here, later⟩ := h
    cases j with
    | zero =>
      simp only [List.getElem?_cons_zero, Option.some.injEq] at e
      subst e
      rcases here with ne | mf
      · rw [(sameText_iff _ _).2 n] at ne; cases ne
      · exact implFit_misfit ((isMisfit_iff _).1 mf) b
    | succ j => exact noMethod_sound later j g b (by simpa using e) n

/-- The one method spelled `name` (function `found.decl`, counted from `k`
in `fns`) whose impl's type matches `s`. -/
def MethodFor (decls : Decls) (fns : List FnDecl) (k : Nat) (name : Name) (s : Ty) (found : Found) : Prop :=
  ∃ i fd, fns[i]? = some fd ∧ fd.name = name ∧ ImplBinds decls fd s found.binds ∧ found.decl = k + i ∧
    ∀ j fd' b, j ≠ i → fns[j]? = some fd' → fd'.name = name → ¬ImplBinds decls fd' s b

theorem findMethod_sound {fuel : Nat} {decls : Decls} {name : Name} {s : Ty} :
    ∀ {fns : List FnDecl} {k : Nat} {found : Found}, findMethod fuel decls fns k name s = some found →
      MethodFor decls fns k name s found
  | [], _, _, h => by simp [findMethod] at h
  | fd :: rest, k, found, h => by
    simp only [findMethod] at h
    have later : (∀ b, fd.name = name → ¬ImplBinds decls fd s b) →
        findMethod fuel decls rest (k + 1) name s = some found → MethodFor decls (fd :: rest) k name s found := by
      intro no hr
      obtain ⟨i, g, gi, gn, gb, gd, only⟩ := findMethod_sound hr
      refine ⟨i + 1, g, by simpa using gi, gn, gb, by omega, fun j g' b ne e n => ?_⟩
      cases j with
      | zero =>
        simp only [List.getElem?_cons_zero, Option.some.injEq] at e
        subst e
        exact no b n
      | succ j => exact only j g' b (by omega) (by simpa using e) n
    by_cases e : sameText fd.name name = true
    · rw [if_pos e] at h
      cases hb : implFit fuel decls fd s with
      | fits b =>
        rw [hb] at h
        simp only [uniqueFound] at h
        by_cases u : noMethod fuel decls rest name s = true
        · rw [if_pos u, Option.some.injEq] at h
          subst h
          refine ⟨0, fd, rfl, (sameText_iff _ _).1 e, implFit_fits hb, rfl, fun j g b ne gj n => ?_⟩
          cases j with
          | zero => exact absurd rfl ne
          | succ j => exact noMethod_sound u j g b (by simpa using gj) n
        · rw [if_neg u] at h; cases h
      | misfit =>
        rw [hb] at h
        exact later (fun b _ => implFit_misfit hb b) h
      | spent => rw [hb] at h; cases h
    · rw [if_neg e] at h
      exact later (fun _ n => absurd ((sameText_iff _ _).2 n) e) h

theorem methodFor_unique {decls : Decls} {fns : List FnDecl} {k : Nat} {name : Name} {s : Ty} {a b : Found}
    (h₁ : MethodFor decls fns k name s a) (h₂ : MethodFor decls fns k name s b) : a = b := by
  obtain ⟨i, fd, fi, fn, fb, fdc, only⟩ := h₁
  obtain ⟨i', fd', fi', fn', fb', fdc', _⟩ := h₂
  by_cases ne : i' = i
  · subst ne
    rw [fi] at fi'
    cases fi'
    cases a
    cases b
    simp only at fb fb' fdc fdc' ⊢
    rw [fdc, fdc', implBinds_unique fb fb']
  · exact (only i' fd' b.binds ne fi' fn' fb').elim

end Lanius.Mini.Reading
