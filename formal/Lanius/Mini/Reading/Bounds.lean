import Lanius.Mini.Reading.Det.Base

/-! # The reading, F7: trait bounds

`T: Tr<A, ..>`, in a type parameter list or a `where` clause, requires that
the type `T` stands for has an impl of `Tr` at those arguments
(`Implements`): an `impl<P..> Tr<..> for S where ..` whose trait and type
read as the bound's at some arguments for `P..`, and whose own bounds hold
at them. A trait is named by its module and spelling, a path resolved like a
type path (`Resolves`), and its type arguments (`TraitR` for a bound,
`TraitTyR` for an impl's trait). `FnBound`: the bounds a function instance
must satisfy, its own and, for a method, its impl's. `fnBoundsOk_sound`:
what the builder's check accepts satisfies them. -/

namespace Lanius.Mini.Reading

open Lanius.Mini Lanius.Mini.Prod

/-! ## Traits -/

/-- The spellings of a bound's trait path (`a::b::Tr`). -/
inductive BoundPathSpellings : CTree → CTree → List Name → Prop
  | last {segment tail : CTree} : nodeProd segment = pBoundTypePathIdent → nodeProd tail = pBoundTypePathEnd →
      BoundPathSpellings segment tail [(kidToken segment 0).text]
  | more {segment tail : CTree} {rest : List Name} : nodeProd segment = pBoundTypePathIdent →
      nodeProd tail = pBoundTypePathMore → BoundPathSpellings (kid tail 2) (kid tail 3) rest →
      BoundPathSpellings segment tail ((kidToken segment 0).text :: rest)

theorem boundPathSpellings_sound : ∀ {fuel : Nat} {segment tail : CTree} {ns : List Name},
    boundPathSpellings fuel segment tail = some ns → BoundPathSpellings segment tail ns
  | 0, _, _, _, h => by rw [boundPathSpellings] at h; simp at h
  | f + 1, segment, tail, ns, h => by
    rw [boundPathSpellings] at h
    simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
    by_cases la : nodeProd segment = pBoundTypePathIdent ∧ nodeProd tail = pBoundTypePathEnd
    · rw [if_pos (by simpa using la), Option.some.injEq] at h
      subst h
      exact .last la.1 la.2
    rw [if_neg (by simpa using la)] at h
    by_cases mo : nodeProd segment = pBoundTypePathIdent ∧ nodeProd tail = pBoundTypePathMore
    · rw [if_pos (by simpa using mo)] at h
      simp only [consName, consNameTail] at h
      cases hr : boundPathSpellings f (kid tail 2) (kid tail 3) with
      | none => rw [hr] at h; cases h
      | some r =>
        rw [hr, Option.some.injEq] at h
        subst h
        exact .more mo.1 mo.2 (boundPathSpellings_sound hr)
    rw [if_neg (by simpa using mo)] at h
    cases h

/-- The path `ss` names the trait `tr` at the arguments `ts`: its module and
spelling as a type path's (`Resolves`). -/
def TraitAt (env : FrontEnv) (ss : List Name) (ts : List Ty) (tr : TraitRef) : Prop :=
  ∃ m n, Resolves env.decls env.home ss m n ∧ tr = { home := m, name := n, args := ts }

/-- A bound (`bound_type_expr`) names the trait `tr`: `p::Tr<A, ..>`, each
argument a type. -/
inductive TraitR (env : FrontEnv) : CTree → TraitRef → Prop
  | mk {b : CTree} {ss : List Name} {gs : List CTree} {ts : List Ty} {tr : TraitRef} :
      nodeProd b = pBoundTypeIdent → BoundPathSpellings (kid (kid b 0) 0) (kid (kid b 0) 1) ss →
      Items (kid b 1) gs → ArgsTy env gs ts → TraitAt env ss ts tr → TraitR env b tr

/-- An impl's trait, written as a type expression, names the trait `tr`. -/
inductive TraitTyR (env : FrontEnv) : CTree → TraitRef → Prop
  | mk {t : CTree} {ss : List Name} {gs : List CTree} {ts : List Ty} {tr : TraitRef} :
      nodeProd t = pTypeIdent → TypePathSpellings (kid (kid t 0) 0) (kid (kid t 0) 1) ss →
      Items (kid t 1) gs → ArgsTy env gs ts → TraitAt env ss ts tr → TraitTyR env t tr

theorem argsTys_sound {fuel : Nat} {env : FrontEnv} {gs : List CTree} {ts : List Ty}
    (h : argsTys fuel env gs = some ts) : ArgsTy env gs ts :=
  (tySound fuel).2.2.2.2.2.1 h

theorem traitAt_sound {env : FrontEnv} {segs : Option (List Name)} {args : Option (List Ty)} {tr : TraitRef}
    (h : traitAt env segs args = some tr) : ∃ ss ts, segs = some ss ∧ args = some ts ∧ TraitAt env ss ts tr := by
  simp only [traitAt] at h
  cases segs with
  | none => cases h
  | some ss =>
    simp only at h
    cases hs : splitLast ss with
    | none => rw [hs] at h; cases h
    | some s =>
      rw [hs] at h
      simp only [traitSplit] at h
      cases args with
      | none => cases h
      | some ts =>
        simp only [Option.some.injEq] at h
        exact ⟨ss, ts, rfl, rfl, _, _, resolves_split hs, h.symm⟩

theorem argsOfItems_sound {fuel : Nat} {env : FrontEnv} {c : CTree} {ts : List Ty}
    (h : argsOfItems fuel env (listItems fuel c) = some ts) : ∃ gs, Items c gs ∧ ArgsTy env gs ts := by
  simp only [argsOfItems] at h
  cases hi : listItems fuel c with
  | none => rw [hi] at h; cases h
  | some gs =>
    rw [hi] at h
    exact ⟨gs, listItems_sound hi, argsTys_sound h⟩

theorem traitOfBound_sound {fuel : Nat} {env : FrontEnv} {b : CTree} {tr : TraitRef}
    (h : traitOfBound fuel env b = some tr) : TraitR env b tr := by
  simp only [traitOfBound] at h
  split at h
  · rename_i c
    obtain ⟨ss, ts, hs, ha, at'⟩ := traitAt_sound h
    obtain ⟨gs, it, ar⟩ := argsOfItems_sound ha
    exact .mk c (boundPathSpellings_sound hs) it ar at'
  · cases h

theorem traitOfTy_sound {fuel : Nat} {env : FrontEnv} {t : CTree} {tr : TraitRef}
    (h : traitOfTy fuel env t = some tr) : TraitTyR env t tr := by
  simp only [traitOfTy] at h
  split at h
  · rename_i c
    obtain ⟨ss, ts, hs, ha, at'⟩ := traitAt_sound h
    obtain ⟨gs, it, ar⟩ := argsOfItems_sound ha
    exact .mk c (typePathSpellings_sound hs) it ar at'
  · cases h

/-! ## The bounds an item writes -/

/-- The bound `b` written on the type parameter spelled `n`, among an item's
type parameters `tparams` (`<T: A + B>`) or in its where clause `w`
(`where T: A + B, ..`). -/
inductive BoundOf (tparams w : CTree) : Name → CTree → Prop
  | param {ps : List CTree} {p : CTree} {bs : List CTree} {b : CTree} : Items tparams ps → p ∈ ps →
      nodeProd (kid p 1) = pTypeParamBound → Items (kid (kid p 1) 1) bs → b ∈ bs →
      BoundOf tparams w (kidToken p 0).text b
  | clause {qs : List CTree} {q : CTree} {bs : List CTree} {b : CTree} : nodeProd w = pWhereSome → Items w qs →
      q ∈ qs → Items (kid q 2) bs → b ∈ bs → BoundOf tparams w (kidToken q 0).text b

mutual
/-- The goal's type has an impl of its trait: an impl whose trait and type
read as the goal's, its parameters standing for some `args`, and whose own
bounds hold there. -/
inductive Implements (decls : Decls) : BoundGoal → Prop
  | impl {im : ImplDecl} {args : List Ty} {g : BoundGoal} : im ∈ decls.impls →
      TraitTyR (declScope decls im.home im.params args) (kid im.tree 2) g.traitRef →
      TyR (declScope decls im.home im.params args) (kid im.tree 4) g.ty →
      (∀ n b, BoundOf (kid im.tree 1) (kid im.tree 5) n b → BoundOk decls (declScope decls im.home im.params args) n b) →
      Implements decls g

/-- The bound `b` on the type parameter spelled `n` holds in `env`: the type
`n` stands for has an impl of the trait `b` names. -/
inductive BoundOk (decls : Decls) : FrontEnv → Name → CTree → Prop
  | mk {env : FrontEnv} {n : Name} {b : CTree} {t : Ty} {tr : TraitRef} : ParamTy env n t → TraitR env b tr →
      Implements decls { traitRef := tr, ty := t } → BoundOk decls env n b
end

/-- The bounds a function instance must satisfy: its own type parameters' and
where clause's, and a method's impl's (`implWhere`: the impl's where
clause). -/
inductive FnBound (fd : FnDecl) : Name → CTree → Prop
  | own {n : Name} {b : CTree} : BoundOf (kid fd.tree 2) (kid fd.tree 7) n b → FnBound fd n b
  | impl {n : Name} {b : CTree} : fd.inImpl = true → BoundOf (kid fd.implTree 1) (implWhere fd.implTree) n b →
      FnBound fd n b

/-! ## Soundness of the goals -/

/-- Each bound in `bs` on the parameter `n` is the goal of some member of `gs`. -/
def GoalsFor (env : FrontEnv) (n : Name) (bs : List CTree) (gs : List BoundGoal) : Prop :=
  ∀ b ∈ bs, ∃ g ∈ gs, ParamTy env n g.ty ∧ TraitR env b g.traitRef

theorem goalsOf_sound {fuel : Nat} {env : FrontEnv} {n : Name} :
    ∀ {bs : List CTree} {gs : List BoundGoal}, goalsOf fuel env n bs = some gs → GoalsFor env n bs gs
  | [], _, _ => by intro b m; cases m
  | b :: rest, gs, h => by
    simp only [goalsOf, consGoal] at h
    cases hg : goalAt (paramTy env n) (traitOfBound fuel env b) with
    | none => rw [hg] at h; cases h
    | some g =>
      rw [hg] at h
      simp only [consGoalTail] at h
      cases hr : goalsOf fuel env n rest with
      | none => rw [hr] at h; cases h
      | some gr =>
        rw [hr, Option.some.injEq] at h
        subst h
        have ih := goalsOf_sound hr
        intro b' m
        rcases List.mem_cons.1 m with e | m
        · subst e
          simp only [goalAt] at hg
          cases hp : paramTy env n with
          | none => rw [hp] at hg; cases hg
          | some t =>
            rw [hp] at hg
            simp only at hg
            cases ht : traitOfBound fuel env b' with
            | none => rw [ht] at hg; cases hg
            | some tr =>
              rw [ht, Option.some.injEq] at hg
              subst hg
              exact ⟨_, List.mem_cons_self .., paramTy_sound hp, traitOfBound_sound ht⟩
        · obtain ⟨g', mg, pt, tr⟩ := ih b' m
          exact ⟨g', List.mem_cons_of_mem _ mg, pt, tr⟩

theorem boundGoals_sound {fuel : Nat} {env : FrontEnv} {n : Name} {c : CTree} {gs : List BoundGoal}
    (h : boundGoals fuel env n (listItems fuel c) = some gs) : ∀ bs, Items c bs → GoalsFor env n bs gs := by
  simp only [boundGoals] at h
  cases hi : listItems fuel c with
  | none => rw [hi] at h; cases h
  | some l =>
    rw [hi] at h
    intro bs it
    rw [items_unique it (listItems_sound hi)]
    exact goalsOf_sound h

theorem joinGoals_some {a b : Option (List BoundGoal)} {gs : List BoundGoal} (h : joinGoals a b = some gs) :
    ∃ x y, a = some x ∧ b = some y ∧ gs = x ++ y := by
  cases a with
  | none => cases h
  | some x =>
    cases b with
    | none => cases h
    | some y =>
      simp only [joinGoals, joinGoalsTail, Option.some.injEq] at h
      exact ⟨x, y, rfl, rfl, h.symm⟩

/-- Each bound on a parameter written among `ps` is the goal of some member
of `gs`. -/
def ParamsCovered (env : FrontEnv) (ps : List CTree) (gs : List BoundGoal) : Prop :=
  ∀ p ∈ ps, nodeProd (kid p 1) = pTypeParamBound → ∀ bs, Items (kid (kid p 1) 1) bs →
    GoalsFor env (kidToken p 0).text bs gs

theorem goalsFor_append_left {env : FrontEnv} {n : Name} {bs : List CTree} {x : List BoundGoal} (y : List BoundGoal)
    (h : GoalsFor env n bs x) : GoalsFor env n bs (x ++ y) := by
  intro b m
  obtain ⟨g, mg, r⟩ := h b m
  exact ⟨g, List.mem_append_left _ mg, r⟩

theorem goalsFor_append_right {env : FrontEnv} {n : Name} {bs : List CTree} (x : List BoundGoal) {y : List BoundGoal}
    (h : GoalsFor env n bs y) : GoalsFor env n bs (x ++ y) := by
  intro b m
  obtain ⟨g, mg, r⟩ := h b m
  exact ⟨g, List.mem_append_right _ mg, r⟩

theorem paramsGoals_sound {fuel : Nat} {env : FrontEnv} :
    ∀ {ps : List CTree} {gs : List BoundGoal}, paramsGoals fuel env ps = some gs → ParamsCovered env ps gs
  | [], _, _ => by intro p m; cases m
  | p :: rest, gs, h => by
    simp only [paramsGoals] at h
    obtain ⟨x, y, hx, hy, rfl⟩ := joinGoals_some h
    have ih := paramsGoals_sound hy
    intro p' m pb bs it
    rcases List.mem_cons.1 m with e | m
    · subst e
      simp only [paramGoals] at hx
      rw [if_pos pb] at hx
      exact goalsFor_append_left y (boundGoals_sound hx bs it)
    · exact goalsFor_append_right x (ih p' m pb bs it)

/-- Each bound written in the where clause predicates `qs` is the goal of
some member of `gs`. -/
def PredsCovered (env : FrontEnv) (qs : List CTree) (gs : List BoundGoal) : Prop :=
  ∀ q ∈ qs, ∀ bs, Items (kid q 2) bs → GoalsFor env (kidToken q 0).text bs gs

theorem predsGoals_sound {fuel : Nat} {env : FrontEnv} :
    ∀ {qs : List CTree} {gs : List BoundGoal}, predsGoals fuel env qs = some gs → PredsCovered env qs gs
  | [], _, _ => by intro q m; cases m
  | q :: rest, gs, h => by
    simp only [predsGoals] at h
    obtain ⟨x, y, hx, hy, rfl⟩ := joinGoals_some h
    have ih := predsGoals_sound hy
    intro q' m bs it
    rcases List.mem_cons.1 m with e | m
    · subst e
      exact goalsFor_append_left y (boundGoals_sound hx bs it)
    · exact goalsFor_append_right x (ih q' m bs it)

/-- Each bound an item writes is the goal of some member of `gs`. -/
def BoundsCovered (env : FrontEnv) (tparams w : CTree) (gs : List BoundGoal) : Prop :=
  ∀ n b, BoundOf tparams w n b → ∃ g ∈ gs, ParamTy env n g.ty ∧ TraitR env b g.traitRef

theorem itemGoals_sound {fuel : Nat} {env : FrontEnv} {tparams w : CTree} {gs : List BoundGoal}
    (h : itemGoals fuel env tparams w = some gs) : BoundsCovered env tparams w gs := by
  simp only [itemGoals] at h
  cases hi : listItems fuel tparams with
  | none => rw [hi] at h; cases h
  | some ps =>
    rw [hi] at h
    simp only at h
    obtain ⟨x, y, hx, hy, rfl⟩ := joinGoals_some h
    have pc := paramsGoals_sound hx
    intro n b ob
    cases ob with
    | param it mp pb ib mb =>
      rw [items_unique it (listItems_sound hi)] at mp
      obtain ⟨g, mg, r⟩ := pc _ mp pb _ ib b mb
      exact ⟨g, List.mem_append_left _ mg, r⟩
    | clause ws iw mq ib mb =>
      simp only [whereGoals] at hy
      rw [if_pos ws] at hy
      cases hq : listItems fuel w with
      | none => rw [hq] at hy; cases hy
      | some qs' =>
        rw [hq] at hy
        simp only at hy
        rw [items_unique iw (listItems_sound hq)] at mq
        obtain ⟨g, mg, r⟩ := predsGoals_sound hy _ mq _ ib b mb
        exact ⟨g, List.mem_append_right _ mg, r⟩

/-! ## Soundness of the impl search -/

theorem sameTrait_iff (a b : TraitRef) : sameTrait a b = true ↔ a = b := by
  cases a; cases b
  simp [sameTrait, sameSpellings_iff, sameText_iff, sameTys_iff, and_assoc]

/-- What the impl search finds, at each fuel. -/
def HoldsSound (decls : Decls) (fuel : Nat) : Prop :=
  (∀ {g}, traitHolds fuel decls g = true → Implements decls g) ∧
  (∀ {ims g}, anyImpl fuel decls ims g = true → (∀ im ∈ ims, im ∈ decls.impls) → Implements decls g) ∧
  (∀ {im g}, implGives fuel decls im g = true → im ∈ decls.impls → Implements decls g) ∧
  (∀ {im g env}, implFits fuel decls im g env = true →
    TraitTyR env (kid im.tree 2) g.traitRef ∧ TyR env (kid im.tree 4) g.ty ∧
    ∀ n b, BoundOf (kid im.tree 1) (kid im.tree 5) n b → BoundOk decls env n b) ∧
  (∀ {gs}, goalsHold fuel decls gs = true → ∃ l, gs = some l ∧ ∀ g ∈ l, Implements decls g) ∧
  (∀ {l}, allHold fuel decls l = true → ∀ g ∈ l, Implements decls g)

theorem boundOk_of {decls : Decls} {env : FrontEnv} {tparams w : CTree} {gs : List BoundGoal}
    (cov : BoundsCovered env tparams w gs) (all : ∀ g ∈ gs, Implements decls g) :
    ∀ n b, BoundOf tparams w n b → BoundOk decls env n b := by
  intro n b ob
  obtain ⟨g, mg, pt, tr⟩ := cov n b ob
  exact .mk pt tr (all g mg)

theorem holdsSound (decls : Decls) : ∀ fuel, HoldsSound decls fuel
  | 0 => ⟨fun h => by rw [traitHolds.eq_def] at h; simp at h, fun h _ => by rw [anyImpl.eq_def] at h; simp at h,
      fun h _ => by rw [implGives.eq_def] at h; simp at h, fun h => by rw [implFits.eq_def] at h; simp at h,
      fun h => by rw [goalsHold.eq_def] at h; simp at h, fun h => by rw [allHold.eq_def] at h; simp at h⟩
  | f + 1 => by
    obtain ⟨ihHolds, ihAny, ihGives, ihFits, ihGoals, ihAll⟩ := holdsSound decls f
    refine ⟨?_, ?_, ?_, ?_, ?_, ?_⟩
    · intro g h
      rw [traitHolds.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      exact ihAny h (fun _ m => m)
    · intro ims g h sub
      rw [anyImpl.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      cases ims with
      | nil => simp at h
      | cons im rest =>
        simp only [Bool.or_eq_true] at h
        rcases h with h | h
        · exact ihGives h (sub im (List.mem_cons_self ..))
        · exact ihAny h (fun x m => sub x (List.mem_cons_of_mem _ m))
    · intro im g h mi
      rw [implGives.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      cases ha : implArgs (f + 1) decls im g with
      | none => rw [ha] at h; simp at h
      | some args =>
        rw [ha] at h
        simp only at h
        obtain ⟨tt, ty, bo⟩ := ihFits h
        exact .impl mi tt ty bo
    · intro im g env h
      rw [implFits.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel, Bool.and_eq_true] at h
      obtain ⟨⟨ht, hy⟩, hg⟩ := h
      cases htr : traitOfTy (f + 1) env (kid im.tree 2) with
      | none => rw [htr] at ht; simp [traitIs] at ht
      | some r =>
        rw [htr] at ht
        simp only [traitIs, sameTrait_iff] at ht
        cases hty : tyOf (f + 1) env (kid im.tree 4) with
        | none => rw [hty] at hy; simp [tyIs] at hy
        | some t =>
          rw [hty] at hy
          simp only [tyIs, sameTy_iff] at hy
          obtain ⟨l, hl, all⟩ := ihGoals hg
          subst ht
          subst hy
          exact ⟨traitOfTy_sound htr, tyOf_sound hty, boundOk_of (itemGoals_sound hl) all⟩
    · intro gs h
      rw [goalsHold.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      cases gs with
      | none => simp at h
      | some l => exact ⟨l, rfl, ihAll h⟩
    · intro l h
      rw [allHold.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      cases l with
      | nil => intro g m; cases m
      | cons g rest =>
        simp only [Bool.and_eq_true] at h
        obtain ⟨hg, hr⟩ := h
        have hi := ihHolds hg
        intro g' m
        rcases List.mem_cons.1 m with e | m
        · subst e; exact hi
        · exact ihAll hr g' m

theorem goalsHold_sound {fuel : Nat} {decls : Decls} {env : FrontEnv} {tparams w : CTree}
    (h : goalsHold fuel decls (itemGoals fuel env tparams w) = true) :
    ∀ n b, BoundOf tparams w n b → BoundOk decls env n b := by
  obtain ⟨l, hl, all⟩ := (holdsSound decls fuel).2.2.2.2.1 h
  exact boundOk_of (itemGoals_sound hl) all

/-- The builder's check of a function instance's bounds (`fnBoundsOk`):
every bound it must satisfy holds where its signature is read. -/
theorem fnBoundsOk_sound {fuel : Nat} {decls : Decls} {fd : FnDecl} {env : FrontEnv}
    (h : fnBoundsOk fuel decls fd env = true) : ∀ n b, FnBound fd n b → BoundOk decls env n b := by
  simp only [fnBoundsOk, Bool.and_eq_true, Bool.or_eq_true, Bool.not_eq_true'] at h
  obtain ⟨own, imp⟩ := h
  intro n b fb
  cases fb with
  | own ob => exact goalsHold_sound own n b ob
  | impl ii ob =>
    rcases imp with e | imp
    · rw [ii] at e; cases e
    · exact goalsHold_sound imp n b ob

end Lanius.Mini.Reading
