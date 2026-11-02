import Lanius.Faithful.SelfPre.Files

/-! # Validating the files' parse trees: preconditions (F14)

`attach` walks a cursor over a file's productions and tokens: its index
counts the productions taken, so the index and the productions left stay at
most the file's productions (`attach_ok`), and a `>>` split in two gives a
second half that starts one later and is no `>>` again. `generic_close`
counts open angles and brackets, each at most the tokens it has passed. -/

namespace Lanius.Faithful.SelfPre

open Lanius.Mini
open Lanius.Faithful.Budget
open Lanius.Faithful.SelfBudget

/-- A token starts at most at `M`, and before it if it is a `>>`. -/
def Tok (M : Nat) (t : Token) : Prop := (t.kind = 44 → t.start < M) ∧ t.start ≤ M

/-- The cursor's index and productions left are at most `K`, its tokens at most
`K`, and they start at most at `M`. -/
def CurOk (K M : Nat) (cur : Cursor) : Prop :=
  cur.index + cur.prods.length ≤ K ∧ cur.tokens.length ≤ K ∧ ∀ t ∈ cur.tokens, Tok M t

theorem tok_shrSecond {M : Nat} {t : Token} (h : t.kind = 44) (ht : Tok M t) : Tok M (shrSecond t) := by
  have := ht.1 h
  exact ⟨fun e => absurd (show (13 : Nat) = 44 from e) (by decide), show t.start + 1 ≤ M by omega⟩

/-- **What `attach` leaves is a cursor as good as it was given.** -/
theorem attach_ok {K M : Nat} (g : List Rule) : ∀ (fuel : Nat) (rhs : List Sym) (parent : Nat) (cur : Cursor) (a : Attached),
    CurOk K M cur → attach g fuel rhs parent cur = some a → CurOk K M a.rest
  | 0, _, _, _, _, _, h => by unfold attach at h; simp at h
  | fuel + 1, rhs, parent, cur, a, hc, h => by
    unfold attach at h
    simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
    split at h
    · simp only [Option.some.injEq] at h
      subst h
      exact hc
    · rename_i sym more
      split at h
      · split at h
        · cases h
        · rename_i tok toks e
          obtain ⟨h1, h2, h3⟩ := hc
          rw [e] at h2 h3
          simp only [List.length_cons, List.mem_cons] at h2 h3
          split at h
          · unfold withKid at h
            split at h
            · cases h
            · rename_i a' e'
              simp only [Option.some.injEq] at h
              subst h
              exact attach_ok g fuel more parent ⟨cur.prods, cur.parents, toks, cur.index⟩ a'
                ⟨h1, by simp only; omega, fun t ht => h3 t (.inr ht)⟩ e'
          · split at h
            · rename_i hk
              simp only [Bool.and_eq_true, decide_eq_true_eq] at hk
              unfold withKid at h
              split at h
              · cases h
              · rename_i a' e'
                simp only [Option.some.injEq] at h
                subst h
                refine attach_ok g fuel more parent ⟨cur.prods, cur.parents, shrSecond tok :: toks, cur.index⟩ a'
                  ⟨h1, by simp only [List.length_cons]; omega, ?_⟩ e'
                intro t ht
                simp only [List.mem_cons] at ht
                rcases ht with rfl | ht
                · exact tok_shrSecond hk.1 (h3 tok (.inl rfl))
                · exact h3 t (.inr ht)
            · cases h
      · split at h
        · cases h
        · rename_i p ps ep
          split at h
          · cases h
          · rename_i q qs eq
            split at h
            · cases h
            · split at h
              · cases h
              · rename_i prod _
                split at h
                · cases h
                · split at h
                  · cases h
                  · rename_i a1 e1
                    obtain ⟨h1, h2, h3⟩ := hc
                    rw [ep] at h1
                    simp only [List.length_cons] at h1
                    have c1 := attach_ok g fuel prod.rhs cur.index ⟨ps, qs, cur.tokens, cur.index + 1⟩ a1
                      ⟨by simp only; omega, h2, h3⟩ e1
                    unfold withKid at h
                    split at h
                    · cases h
                    · rename_i a2 e2
                      simp only [Option.some.injEq] at h
                      subst h
                      exact attach_ok g fuel more parent _ a2 c1 e2

/-! ## The preconditions -/

/-- An `if` of propositions, from its two branches (`split` simplifies too much on the long ones). -/
theorem ite_intro {c : Prop} [Decidable c] {p q : Prop} (hp : c → p) (hq : ¬c → q) : if c then p else q :=
  if h : c then (if_pos h).mpr (hp h) else (if_neg h).mpr (hq h)

macro "ites" : tactic => `(tactic| repeat' (apply ite_intro <;> intro _))

theorem pre_length_of_Token : ∀ (n : Nat) (xs : List Token) (b : Nat), xs.length < 2 ^ 63 →
    Pre_length_of_mini_selfhost_Token n xs b
  | 0, _, _, _ => trivial
  | _ + 1, [], _, _ => by simp only [Pre_length_of_mini_selfhost_Token]
  | n + 1, _ :: xs, b, h => by
    simp only [Pre_length_of_mini_selfhost_Token, Pre_plus]
    simp only [List.length_cons] at h
    exact ⟨pre_length_of_Token n xs b (by omega), by omega⟩

theorem pre_generic_close {K : Nat} (hK : K < 2 ^ 63) : ∀ (n : Nat) (ts : List Token) (a d b : Nat),
    a + d + ts.length ≤ K → Pre_generic_close n ts a d b
  | 0, _, _, _, _, _ => trivial
  | _ + 1, [], _, _, _, _ => by simp only [Pre_generic_close]
  | 1, _ :: _, _, _, _, _ => by simp only [Pre_generic_close, Pre_generic_close_at]
  | n + 2, t :: ts, a, d, b, h => by
    simp only [List.length_cons] at h
    have ih := pre_generic_close hK n ts
    simp only [Pre_generic_close, Pre_generic_close_at, Pre_plus]
    ites
    all_goals first
      | trivial
      | exact ih _ _ _ (by omega)
      | exact ⟨by omega, ih _ _ _ (by omega)⟩

theorem pre_generic_open (n : Nat) (ts : List Token) (b : Nat) (h : ts.length < 2 ^ 62) :
    Pre_generic_open n ts b := by
  rcases n with _ | n
  · trivial
  match ts with
  | [] => simp only [Pre_generic_open]
  | t :: ts' =>
    simp only [Pre_generic_open]
    simp only [List.length_cons] at h
    ites
    · exact pre_generic_close (K := 2 ^ 62) (by omega) n _ 1 0 b (by omega)
    · trivial

theorem pre_picks (n p : Nat) (ts : List Token) (b : Nat) (h : ts.length < 2 ^ 62) : Pre_picks n p ts b := by
  rcases n with _ | n
  · trivial
  have path : Pre_generic_path_at n ts b := by
    rcases n with _ | n
    · trivial
    match ts with
    | [] => simp only [Pre_generic_path_at]
    | t :: ts' =>
      simp only [Pre_generic_path_at]
      simp only [List.length_cons] at h
      exact pre_generic_open n ts' b (by omega)
  simp only [Pre_picks]
  ites
  all_goals first
    | trivial
    | exact pre_generic_open n ts b h
    | exact path

theorem pre_attach {K M : Nat} (hK : K < 2 ^ 62) (hM : M < 2 ^ 62) (n : Nat) :
    ∀ (g : List Rule) (fuel : Nat) (syms : List Sym) (parent : Nat) (cur : Cursor) (b : Nat), CurOk K M cur →
      Pre_attach n g fuel syms parent cur b := by
  induction n using Nat.strongRecOn with
  | _ n ih =>
    intro g fuel syms parent cur b hc
    obtain ⟨h1, h2, h3⟩ := hc
    match n with
    | 0 => trivial
    | k + 1 =>
      simp only [Pre_attach]
      split
      · trivial
      · split
        · trivial
        · rename_i s more
          match k with
          | 0 => trivial
          | j + 1 =>
            simp only [Pre_attach_sym]
            split
            · -- a terminal
              rename_i kind
              match j with
              | 0 => trivial
              | i + 1 =>
                simp only [Pre_attach_term]
                split
                · trivial
                · rename_i tok toks e
                  rw [e] at h2 h3
                  simp only [List.length_cons, List.mem_cons] at h2 h3
                  match i with
                  | 0 => trivial
                  | m + 1 =>
                    simp only [Pre_attach_leaf]
                    split
                    · exact ih m (by omega) _ _ _ _ _ _ ⟨h1, by simp only; omega, fun t ht => h3 t (.inr ht)⟩
                    · split
                      · rename_i hk
                        have e44 : Inline.tShr = 44 := rfl
                        simp only [decide_eq_true_eq, e44] at hk
                        split
                        · intro b4 _ _
                          refine ⟨?_, ?_⟩
                          · match m with
                            | 0 => trivial
                            | l + 1 =>
                              simp only [Pre_shr_second, Pre_plus]
                              have := (h3 tok (.inl rfl)).1 hk
                              omega
                          · intro b5 _ _ b6 _ _
                            refine ih m (by omega) _ _ _ _ _ _ ⟨h1, by simp only [List.length_cons]; omega, ?_⟩
                            intro t ht
                            simp only [List.mem_cons] at ht
                            rcases ht with rfl | ht
                            · exact tok_shrSecond hk (h3 tok (.inl rfl))
                            · exact h3 t (.inr ht)
                        · trivial
                      · trivial
            · -- a nonterminal
              rename_i nt
              match j with
              | 0 => trivial
              | i + 1 =>
                simp only [Pre_attach_nonterm]
                split
                · trivial
                · rename_i p ps ep
                  rw [ep] at h1
                  simp only [List.length_cons] at h1
                  match i with
                  | 0 => trivial
                  | m + 1 =>
                    simp only [Pre_attach_parent]
                    split
                    · trivial
                    · rename_i q qs eq
                      match m with
                      | 0 => trivial
                      | l + 1 =>
                        simp only [Pre_attach_prod]
                        split
                        · trivial
                        · refine ⟨pre_picks l p _ b (by omega), ?_⟩
                          split
                          · trivial
                          · split
                            · rename_i prod eprod
                              match l with
                              | 0 => trivial
                              | r + 1 =>
                                simp only [Pre_attach_node, Pre_plus]
                                split
                                · trivial
                                · have c1 : CurOk K M ⟨ps, qs, cur.tokens, cur.index + 1⟩ :=
                                    ⟨by simp only; omega, h2, h3⟩
                                  refine ⟨by omega, ih r (by omega) _ _ _ _ _ _ c1, ?_⟩
                                  intro b1 _ _
                                  match r with
                                  | 0 => trivial
                                  | u + 1 =>
                                    simp only [Pre_attach_after]
                                    split
                                    · rename_i a ea
                                      intro b2 _ _
                                      exact ih u (by omega) _ _ _ _ _ _ (attach_ok g _ _ _ _ a c1 ea)
                                    · trivial
                            · trivial

theorem pre_validate_tree (n : Nat) (g : List Rule) (tokens : List Token) (prods parents : List Nat) (b B : Nat)
    (hsize : tokens.length + prods.length < 2 ^ 61) (hB : B < 2 ^ 61) (htok : ∀ t ∈ tokens, t.start ≤ B) :
    Pre_validate_tree n g tokens prods parents b := by
  rcases n with _ | n
  · trivial
  simp only [Pre_validate_tree, Pre_plus, Pre_times]
  refine ⟨pre_length_of_usize n _ b (by omega), pre_length_of_Token n _ b (by omega), by omega, by omega, by omega, ?_⟩
  intro b1 _ _
  refine pre_attach (K := prods.length + tokens.length) (M := B + 1) (by omega) (by omega) n _ _ _ _ _ b1
    ⟨by simp only; omega, by simp only; omega, fun t ht => ?_⟩
  have := htok t ht
  exact ⟨fun _ => by omega, by omega⟩

theorem pre_validate_files {B : Nat} (hB : B < 2 ^ 61) : ∀ (n : Nat) (g : List Rule) (fs : List FileInput) (b : Nat),
    filesSize fs < 2 ^ 61 → TokensIn B fs → Pre_validate_files n g fs b
  | 0, _, _, _, _, _ => trivial
  | _ + 1, _, [], _, _, _ => by simp only [Pre_validate_files]
  | n + 1, g, f :: fs, b, hs, ht => by
    simp only [filesSize] at hs
    simp only [Pre_validate_files]
    refine ⟨pre_validate_tree n g _ _ _ b B (by omega) hB (fun t h => (ht f List.mem_cons_self t h).1), ?_⟩
    intro b1 _ _
    exact pre_validate_files hB n g fs b1 (by omega) (fun f' hf' => ht f' (List.mem_cons_of_mem _ hf'))

theorem filesFuel_le : ∀ fs : List FileInput, filesFuel fs ≤ 4 * filesSize fs + 16
  | [] => by simp [filesFuel, filesSize]
  | f :: fs => by
    have := filesFuel_le fs
    simp only [filesFuel, filesSize]
    omega

theorem pre_files_fuel : ∀ (n : Nat) (fs : List FileInput) (b : Nat), filesSize fs < 2 ^ 61 → Pre_files_fuel n fs b
  | 0, _, _, _ => trivial
  | _ + 1, [], _, _ => by simp only [Pre_files_fuel]
  | n + 1, f :: fs, b, hs => by
    have := filesFuel_le fs
    simp only [filesSize] at hs
    simp only [Pre_files_fuel, Pre_plus, Pre_times]
    exact ⟨pre_length_of_usize n _ b (by omega), pre_length_of_Token n _ b (by omega), by omega, by omega,
      pre_files_fuel n fs b (by omega), by omega⟩

#print axioms pre_validate_files

end Lanius.Faithful.SelfPre
