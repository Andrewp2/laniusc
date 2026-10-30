import Lanius.Mini.Reading.Det.EffParts

/-! # The reading is deterministic, F1: a match's arms

A match has as many arms as its enum has variants, and each variant's arm
names it. An arm names one variant, and an enum's variants have distinct
names, so the arms the variants pick are all the arms, each named by one
variant: two choices of an arm for each variant agree (`arms_unique`). -/

namespace Lanius.Mini.Reading

open Lanius.Mini Lanius.Mini.Prod

section
variable {α β : Type} {N : α → β → Prop}

theorem listRel_mem : ∀ {os : List α} {ns : List β}, ListRel N os ns → ∀ {o : α}, o ∈ os → ∃ n ∈ ns, N o n
  | _, _, .nil, _, m => by cases m
  | _, _, .cons r rest, o, m => by
    rcases List.mem_cons.1 m with rfl | m
    · exact ⟨_, List.mem_cons_self, r⟩
    · obtain ⟨n, mn, r'⟩ := listRel_mem rest m
      exact ⟨n, List.mem_cons_of_mem _ mn, r'⟩

theorem listRel_length : ∀ {os : List α} {ns : List β}, ListRel N os ns → os.length = ns.length
  | _, _, .nil => rfl
  | _, _, .cons _ rest => by simp [listRel_length rest]

variable (fn : ∀ o n n', N o n → N o n' → n = n')
include fn

/-- Among elements named by distinct names, one name names one element. -/
theorem listRel_named_unique : ∀ {os : List α} {ns : List β}, ListRel N os ns → ns.Nodup →
    ∀ {o o' : α} {n : β}, o ∈ os → o' ∈ os → N o n → N o' n → o = o'
  | _, _, .nil, _, _, _, _, m, _, _, _ => by cases m
  | _, _, .cons (a := a) (b := m) r rest, nd, o, o', n, mo, mo', no, no' => by
    have ⟨nm, nd'⟩ := List.nodup_cons.1 nd
    rcases List.mem_cons.1 mo with e | mr
    · rcases List.mem_cons.1 mo' with e' | mr'
      · rw [e, e']
      · subst e
        obtain ⟨k, mk, nk⟩ := listRel_mem rest mr'
        have e₁ := fn _ _ _ r no
        have e₂ := fn _ _ _ no' nk
        subst e₁ e₂
        exact (nm mk).elim
    · rcases List.mem_cons.1 mo' with e' | mr'
      · subst e'
        obtain ⟨k, mk, nk⟩ := listRel_mem rest mr
        have e₁ := fn _ _ _ r no'
        have e₂ := fn _ _ _ no nk
        subst e₁ e₂
        exact (nm mk).elim
      · exact listRel_named_unique rest nd' mr mr' no no'

theorem listRel_nodup : ∀ {os : List α} {ns : List β}, ListRel N os ns → ns.Nodup → os.Nodup
  | _, _, .nil, _ => List.nodup_nil
  | _, _, .cons (a := a) (b := m) r rest, nd => by
    have ⟨nm, nd'⟩ := List.nodup_cons.1 nd
    refine List.nodup_cons.2 ⟨fun ma => ?_, listRel_nodup rest nd'⟩
    obtain ⟨k, mk, nk⟩ := listRel_mem rest ma
    have e := fn _ _ _ r nk
    subst e
    exact nm mk

end

/-- A list without repeats inside another as long is all of it. -/
theorem subset_of_nodup_length {α : Type} [DecidableEq α] :
    ∀ {l m : List α}, l.Nodup → l ⊆ m → l.length = m.length → m ⊆ l
  | [], m, _, _, len => by
    cases m with
    | nil => exact fun _ h => h
    | cons _ _ => simp at len
  | y :: l, m, nd, sub, len => by
    have ⟨ny, nd'⟩ := List.nodup_cons.1 nd
    have ym : y ∈ m := sub List.mem_cons_self
    have sub' : l ⊆ m.erase y := fun x mx => by
      have ne : x ≠ y := fun e => ny (e ▸ mx)
      exact (List.mem_erase_of_ne ne).2 (sub (List.mem_cons_of_mem _ mx))
    have len' : l.length = (m.erase y).length := by
      rw [List.length_erase_of_mem ym]
      simp at len
      omega
    intro x mx
    by_cases e : x = y
    · subst e
      exact List.mem_cons_self
    · exact List.mem_cons_of_mem _ (subset_of_nodup_length nd' sub' len' ((List.mem_erase_of_ne e).2 mx))

theorem arms_unique {α β : Type} [DecidableEq α] {N : α → β → Prop} (fn : ∀ o n n', N o n → N o n' → n = n')
    {ns : List β} (nd : ns.Nodup) {arms : List α} (len : arms.length = ns.length) :
    ∀ {os₁ os₂ : List α}, ListRel N os₁ ns → ListRel N os₂ ns → os₁ ⊆ arms → os₂ ⊆ arms → os₁ = os₂ := by
  intro os₁ os₂ h₁ h₂ s₁ s₂
  have all : arms ⊆ os₁ :=
    subset_of_nodup_length (listRel_nodup fn h₁ nd) s₁ (by rw [listRel_length h₁, len])
  have one : ∀ {o o' : α} {n : β}, o ∈ arms → o' ∈ arms → N o n → N o' n → o = o' :=
    fun mo mo' no no' => listRel_named_unique fn h₁ nd (all mo) (all mo') no no'
  clear all nd len
  induction h₁ generalizing os₂ with
  | nil => cases h₂; rfl
  | cons r _ ih =>
    cases h₂ with
    | cons r' rest' =>
      rw [one (s₁ List.mem_cons_self) (s₂ List.mem_cons_self) r r',
        ih rest' (fun _ m => s₁ (List.mem_cons_of_mem _ m)) (fun _ m => s₂ (List.mem_cons_of_mem _ m))]

/-! ## Parts of arms, paths and peels -/

theorem split_unique {front front' : ModPath} {name name' : Name} (h : front ++ [name] = front' ++ [name']) :
    front = front' ∧ name = name' := by
  have ⟨e, e'⟩ := List.append_inj' h rfl
  cases e'
  exact ⟨e, rfl⟩

theorem pathRefR_spellings : ∀ {segment tail : CTree} {ss : ModPath} {pr : PathRef},
    PathSpellings segment tail ss → PathRefR segment tail pr → pr.segments = ss
  | _, _, _, _, .last _ _, .last _ _ => rfl
  | _, _, _, _, .last p _, .args p' _ _ => by prod_clash
  | _, _, _, _, .last _ t, .more _ t' _ => by prod_clash
  | _, _, _, _, .more _ t _, .last _ t' => by prod_clash
  | _, _, _, _, .more p _ _, .args p' _ _ => by prod_clash
  | _, _, _, _, .more _ _ r, .more _ _ r' => by simp only [pathRefR_spellings r r']

theorem peel_unique : ∀ {c a b : CTree}, Peel c a → Peel c b → a = b
  | _, _, _, .wrap _ p, .wrap _ p' => peel_unique p p'
  | _, _, _, .wrap w _, .bare w' _ _ => by
    exfalso
    simp only [levelProds, List.mem_cons, List.not_mem_nil, or_false] at w w'
    unfold_prods
    omega
  | _, _, _, .wrap w _, .here e => by
    exfalso
    unfold_prods
    omega
  | _, _, _, .bare w _ _, .wrap w' _ => by
    exfalso
    simp only [levelProds, List.mem_cons, List.not_mem_nil, or_false] at w w'
    unfold_prods
    omega
  | _, _, _, .bare _ _ p, .bare _ _ p' => peel_unique p p'
  | _, _, _, .bare w _ _, .here e => by
    exfalso
    simp only [levelProds, List.mem_cons, List.not_mem_nil, or_false] at w
    unfold_prods
    omega
  | _, _, _, .here e, .wrap w _ => by
    exfalso
    unfold_prods
    omega
  | _, _, _, .here e, .bare w _ _ => by
    exfalso
    simp only [levelProds, List.mem_cons, List.not_mem_nil, or_false] at w
    unfold_prods
    omega
  | _, _, _, .here _, .here _ => rfl

theorem effCasts_unique {env : FrontEnv} : ∀ {a : MEff} {tail : CTree} {x y : MEff},
    EffCasts env a tail x → EffCasts env a tail y → x = y
  | _, _, _, _, .done _, .done _ => rfl
  | _, _, _, _, .done k, .step k' _ _ _ => absurd k k'
  | _, _, _, _, .step k _ _ _, .done k' => absurd k' k
  | _, _, _, _, .step _ ct xb rest, .step _ ct' xb' rest' => by
    rw [castType_unique ct ct', xb'] at xb
    cases xb
    exact effCasts_unique rest rest'

theorem bindersR_unique {env : FrontEnv} : ∀ {scope : List Local} {pats : List CTree} {tys : List Ty} {a b : Bound},
    BindersR env scope pats tys a → BindersR env scope pats tys b → a = b
  | _, _, _, _, _, .nil, .nil => rfl
  | _, _, _, _, _, .cons _ _ pn _ _ r, .cons _ _ pn' _ _ r' => by
    obtain ⟨_, _, _, rfl⟩ := pn
    obtain ⟨_, _, _, rfl⟩ := pn'
    rw [bindersR_unique r r']

theorem bindersR_fresh {env : FrontEnv} : ∀ {scope : List Local} {pats : List CTree} {tys : List Ty} {b : Bound},
    BindersR env scope pats tys b → IdsFresh scope → IdsFresh b.scope
  | _, _, _, _, .nil, nd => nd
  | _, _, _, _, .cons (n := n) (t := t) _ _ _ _ fr r, nd =>
    by
      have h := bindersR_fresh r (idsFresh_cons (l := { name := n, id := _, ty := t }) nd fr)
      exact h

/-- What a match keeps of an arm: its binders, its value, and its type when
both readings find one. -/
def ArmAgree (a b : EffArm) : Prop :=
  a.binders = b.binders ∧ a.value = b.value ∧ ∀ s t, a.ty = some s → b.ty = some t → s = t

theorem armsAgree_binders : ∀ {as bs : List EffArm}, ListRel ArmAgree as bs → armBinders as = armBinders bs
  | _, _, .nil => rfl
  | _, _, .cons ag rest => by simp only [armBinders, ag.1, armsAgree_binders rest]

theorem armsAgree_values : ∀ {as bs : List EffArm}, ListRel ArmAgree as bs → armValues as = armValues bs
  | _, _, .nil => rfl
  | _, _, .cons ag rest => by simp only [armValues, ag.2.1, armsAgree_values rest]

theorem armsAgree_resultTy {expected : Option Ty} {as bs : List EffArm} {s t : Ty} (h : ListRel ArmAgree as bs)
    (hs : resultTy expected as = some s) (ht : resultTy expected bs = some t) : s = t := by
  cases expected with
  | some e =>
    simp only [resultTy, Option.some.injEq] at hs ht
    rw [← hs, ← ht]
  | none =>
    cases h with
    | nil => simp [resultTy] at hs
    | cons ag _ =>
      simp only [resultTy] at hs ht
      exact ag.2.2 _ _ hs ht

/-- Arm `o`'s pattern names variant `n` of `owner`. -/
def ArmNames (owner : TypeDecl) (o : CTree) (n : Name) : Prop :=
  ∃ ss, PathSpellings (kid (kid (kid o 0) 0) 0) (kid (kid (kid o 0) 0) 1) ss ∧ ArmNamed ss owner n

theorem armNames_fun {owner : TypeDecl} (o : CTree) (n n' : Name) (h₁ : ArmNames owner o n)
    (h₂ : ArmNames owner o n') : n = n' := by
  obtain ⟨ss, ps, f, e, _⟩ := h₁
  obtain ⟨ss', ps', f', e', _⟩ := h₂
  rw [pathSpellings_unique ps ps', e'] at e
  exact (split_unique e).2.symm

theorem zipVariants_names : ∀ (ns : List Name) (ps : List (List Ty)),
    ((List.zipWith VariantTy.mk ns ps).map (·.name)).Sublist ns
  | [], _ => by simp
  | _ :: _, [] => by simp
  | n :: rest, p :: more => by
    simp only [List.zipWith_cons_cons, List.map_cons]
    exact (zipVariants_names rest more).cons_cons n

end Lanius.Mini.Reading
