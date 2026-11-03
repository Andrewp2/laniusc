import Lanius.Open.F14.PostFrontEndWords.Stmt
import Lanius.Faithful.SelfPre.Files
import Lanius.Faithful.SelfPre.GenP.SelfP02

/-! # `PostFrontEndWords`: the front end's output is at most its input and cost high

The front end reads the files, validates their trees and builds the program
(`post_build_files`, generated). The reader's and the validator's outputs hold
the tokens, whose starts are numbers (not counted by an M-form bound on their
inputs), so they get bounds of their own here: every token the reader makes is
at most the words high (`readFiles_ok`), and `attach` conses one child for each
cost it pays, so its children are at most its cost higher than its tokens
(`attach_post`), a `>>` split in two paying for its second half's later start. -/

open Lanius.Mini
open Lanius.Faithful.Budget
open Lanius.Faithful.SelfBudget
open Lanius.Faithful.SelfPre

namespace Lanius.Open.PostFrontEndWords

/-- Every token is at most `T` high, and a `>>` starts before `T`. -/
def TokH (T : Nat) (ts : List Token) : Prop :=
  ∀ t ∈ ts, hb t ≤ T ∧ (t.kind = 44 → t.start + 1 ≤ T)

theorem hb_text62 : hb ([62] : List Nat) = 1 := rfl

theorem hb_shrFirst {T : Nat} (hT : 1 ≤ T) {t : Token} (h : hb t ≤ T) : hb (shrFirst t) ≤ T := by
  have := hb_le_Token_start t
  unfold shrFirst
  simp only [hb_Token_mk, hb_text62]
  omega

theorem tokH_shrSecond {T : Nat} (hT : 1 ≤ T) {t : Token} (hk : t.kind = 44)
    (h : hb t ≤ T ∧ (t.kind = 44 → t.start + 1 ≤ T)) :
    hb (shrSecond t) ≤ T ∧ ((shrSecond t).kind = 44 → (shrSecond t).start + 1 ≤ T) := by
  have := h.2 hk
  refine ⟨?_, fun e => absurd (show (13 : Nat) = 44 from e) (by decide)⟩
  unfold shrSecond
  simp only [hb_Token_mk, hb_text62]
  omega

theorem withKid_some {kid : CTree} {r : Option Attached} {a : Attached} (h : withKid kid r = some a) :
    ∃ a', r = some a' ∧ a = ⟨kid :: a'.kids, a'.rest⟩ := by
  cases r with
  | none => simp [withKid] at h
  | some a' =>
    simp only [withKid, Option.some.injEq] at h
    exact ⟨a', rfl, h.symm⟩

theorem cost_with_kid_some {m : Nat} {kid : CTree} {a : Attached}
    (h : Cost_with_kid m kid (some a) < 2 ^ 64) : Cost_with_kid m kid (some a) = 1 := by
  rcases m with _ | m
  · simp only [Cost_with_kid] at h; omega
  · rcases m with _ | m
    · simp only [Cost_with_kid, Cost_cons_of_mini_selfhost_CTree] at h; omega
    · simp only [Cost_with_kid, Cost_cons_of_mini_selfhost_CTree]

/-- **The children `attach` builds are at most its cost higher than its tokens.** -/
theorem attach_post {T : Nat} (hT : 1 ≤ T) (g : List Rule) (n : Nat) :
    ∀ (fuel : Nat) (rhs : List Sym) (parent : Nat) (cur : Cursor) (a : Attached),
      TokH T cur.tokens → Cost_attach n g fuel rhs parent cur < 2 ^ 64 → attach g fuel rhs parent cur = some a →
      hb a.kids ≤ T + Cost_attach n g fuel rhs parent cur ∧ TokH T a.rest.tokens := by
  induction n using Nat.strongRecOn with
  | _ n ih =>
  intro fuel rhs parent cur a hc hC h
  match n with
  | 0 => simp only [Cost_attach] at hC; omega
  | k + 1 =>
  match fuel with
  | 0 => unfold attach at h; simp at h
  | f + 1 =>
  match rhs with
  | [] =>
    unfold attach at h
    simp only [Nat.add_one_ne_zero, if_false, Option.some.injEq] at h
    subst h
    exact ⟨by simp, hc⟩
  | sym :: more =>
  have e0 : Cost_attach (k + 1) g (f + 1) (sym :: more) parent cur = Cost_attach_sym k g f sym more parent cur := by
    simp only [Cost_attach, Nat.add_one_ne_zero, decide_false, Bool.false_eq_true, if_false, Nat.add_sub_cancel]
  rw [e0] at hC ⊢
  unfold attach at h
  simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
  match k with
  | 0 => simp only [Cost_attach_sym] at hC; omega
  | j + 1 =>
  match sym with
  | .term kind =>
    simp only [Cost_attach_sym] at hC ⊢
    match j with
    | 0 => simp only [Cost_attach_term] at hC; omega
    | i + 1 =>
    rcases cur with ⟨ps, qs, toks, idx⟩
    match toks with
    | [] => simp at h
    | tok :: toks =>
      simp only [Cost_attach_term] at hC ⊢
      have htok := hc tok List.mem_cons_self
      have hrest : TokH T toks := fun t ht => hc t (List.mem_cons_of_mem _ ht)
      match i with
      | 0 => simp only [Cost_attach_leaf] at hC; omega
      | m + 1 =>
      by_cases hk : tok.kind = kind
      · simp only [hk, if_true, Cost_attach_leaf, decide_true] at h hC ⊢
        obtain ⟨a', e', rfl⟩ := withKid_some h
        rw [e'] at hC ⊢
        have w := cost_with_kid_some (by omega : Cost_with_kid m (CTree.leaf tok) (some a') < 2 ^ 64)
        have ih' := ih m (by omega) f more parent ⟨ps, qs, toks, idx⟩ a' hrest (by omega) e'
        refine ⟨?_, ih'.2⟩
        simp only [hb_cons, hb_CTree_leaf]
        have := htok.1
        omega
      · simp only [hk, if_false, Cost_attach_leaf, decide_false, Bool.false_eq_true] at h hC ⊢
        by_cases hs : tok.kind = 44 ∧ kind = 13
        · have e44 : Inline.tShr = 44 := rfl
          have e13 : Inline.tGt = 13 := rfl
          simp only [hs, decide_true, Bool.and_self, if_true, e44, e13] at h hC ⊢
          obtain ⟨a', e', rfl⟩ := withKid_some h
          rw [e'] at hC ⊢
          have w := cost_with_kid_some (by omega : Cost_with_kid m (CTree.leaf (shrFirst tok)) (some a') < 2 ^ 64)
          have hc' : TokH T (shrSecond tok :: toks) := by
            intro t ht
            simp only [List.mem_cons] at ht
            rcases ht with rfl | ht
            · exact tokH_shrSecond hT hs.1 htok
            · exact hrest t ht
          have ih' := ih m (by omega) f more parent ⟨ps, qs, shrSecond tok :: toks, idx⟩ a' hc' (by omega) e'
          refine ⟨?_, ih'.2⟩
          simp only [hb_cons, hb_CTree_leaf]
          have := hb_shrFirst hT htok.1
          omega
        · have : (decide (tok.kind = 44) && decide (kind = 13)) = false := by
            simp only [Bool.and_eq_false_iff, decide_eq_false_iff_not]
            omega
          simp only [this, Bool.false_eq_true, if_false] at h
          cases h
  | .nonterm nt =>
    simp only [Cost_attach_sym] at hC ⊢
    match j with
    | 0 => simp only [Cost_attach_nonterm] at hC; omega
    | i + 1 =>
    rcases cur with ⟨ps, qs, toks, idx⟩
    match ps with
    | [] => simp at h
    | p :: ps =>
    simp only [Cost_attach_nonterm] at hC ⊢
    match i with
    | 0 => simp only [Cost_attach_parent] at hC; omega
    | i1 + 1 =>
    match qs with
    | [] => simp at h
    | q :: qs =>
    simp only [Cost_attach_parent] at hC ⊢
    match i1 with
    | 0 => simp only [Cost_attach_prod] at hC; omega
    | i2 + 1 =>
    simp only at h
    by_cases hq : q = parent
    case neg => simp [hq] at h
    by_cases hp : picks p toks = true
    case neg => simp [hp] at h
    simp only [hq, hp, Cost_attach_prod, ne_eq, not_true_eq_false, decide_false, decide_true, Bool.not_true,
      Bool.false_or, Bool.false_eq_true, if_false] at h hC ⊢
    cases eg : g[p]? with
    | none => simp [eg] at h
    | some prod =>
    simp only [eg] at h hC ⊢
    match i2 with
    | 0 => simp only [Cost_attach_node] at hC; omega
    | i3 + 1 =>
    by_cases hl : prod.lhs = nt
    case neg => simp [hl] at h
    simp only [hl, Cost_attach_node, not_true_eq_false, decide_true, Bool.not_true, Bool.false_eq_true,
      if_false] at h hC ⊢
    cases e1 : attach g f prod.rhs idx ⟨ps, qs, toks, idx + 1⟩ with
    | none => simp [e1] at h
    | some a1 =>
    simp only [e1] at h hC ⊢
    match i3 with
    | 0 =>
      simp only [Cost_attach_after] at hC
      exact absurd hC (Nat.not_lt.mpr (Nat.le_add_left _ _))
    | i4 + 1 =>
    simp only [Cost_attach_after] at hC ⊢
    obtain ⟨a2, e2, rfl⟩ := withKid_some h
    rw [e2] at hC ⊢
    have hC' : Cost_attach (i4 + 1) g f prod.rhs idx ⟨ps, qs, toks, idx + 1⟩ +
        (1 + (Cost_attach i4 g f more parent a1.rest + Cost_with_kid i4 (CTree.node p a1.kids) (some a2))) < 2 ^ 64 :=
      hC
    show hb (CTree.node p a1.kids :: a2.kids) ≤ T + (Cost_attach (i4 + 1) g f prod.rhs idx ⟨ps, qs, toks, idx + 1⟩ +
        (1 + (Cost_attach i4 g f more parent a1.rest + Cost_with_kid i4 (CTree.node p a1.kids) (some a2)))) ∧ _
    clear hC
    have w := cost_with_kid_some (by omega : Cost_with_kid i4 (CTree.node p a1.kids) (some a2) < 2 ^ 64)
    have c1 := ih (i4 + 1) (by omega) f prod.rhs idx ⟨ps, qs, toks, idx + 1⟩ a1 hc (by omega) e1
    have c2 := ih i4 (by omega) f more parent a1.rest a2 c1.2 (by omega) e2
    refine ⟨?_, c2.2⟩
    simp only [hb_cons, hb_CTree_node]
    have := c1.1
    have := c2.1
    omega

theorem whole_hb {a : Attached} {root : CTree} (h : whole a = some root) : hb root < hb a.kids := by
  unfold whole at h
  split at h
  · split at h
    · cases h
    · rename_i r more e
      unfold only at h
      split at h
      · simp only [Option.some.injEq] at h
        subst h
        rw [e]
        exact hb_le_of_mem List.mem_cons_self
      · cases h
  · cases h

/-- A tree `validateTree` builds is lower than its tokens' bound and its cost. -/
theorem validateTree_post {T : Nat} (hT : 1 ≤ T) (g : List Rule) (n : Nat) (f : FileInput) {root : CTree}
    (ht : TokH T f.tokens) (hC : Cost_validate_tree n g f.tokens f.prods f.parents < 2 ^ 64)
    (h : validateTree g f.tokens f.prods f.parents = some root) :
    hb root + 1 ≤ T + Cost_validate_tree n g f.tokens f.prods f.parents := by
  rcases n with _ | n
  · simp only [Cost_validate_tree] at hC; omega
  simp only [Cost_validate_tree] at hC ⊢
  unfold validateTree at h
  dsimp only at h
  split at h
  · cases h
  · rename_i a e
    have hc : TokH T (Cursor.mk f.prods f.parents f.tokens 0).tokens := ht
    have ha := attach_post hT g n _ _ _ _ a hc (by omega) e
    have hr := whole_hb h
    omega

theorem cost_cons_root_some {n : Nat} {r : CTree} {rs : List CTree}
    (h : Cost_cons_root n (some r) (some rs) < 2 ^ 64) : Cost_cons_root n (some r) (some rs) = 1 := by
  rcases n with _ | n
  · simp only [Cost_cons_root] at h; omega
  · rcases n with _ | n
    · simp only [Cost_cons_root, Cost_cons_of_mini_selfhost_CTree] at h; omega
    · simp only [Cost_cons_root, Cost_cons_of_mini_selfhost_CTree]

/-- **The trees `validateFiles` builds are lower than their tokens' bound and its cost.** -/
theorem validateFiles_post {T : Nat} (hT : 1 ≤ T) (g : List Rule) : ∀ (n : Nat) (fs : List FileInput) (ts : List CTree),
    (∀ f ∈ fs, TokH T f.tokens) → Cost_validate_files n g fs < 2 ^ 64 → validateFiles g fs = some ts →
    hb ts ≤ T + Cost_validate_files n g fs
  | 0, _, _, _, hC, _ => by simp only [Cost_validate_files] at hC; omega
  | n + 1, [], ts, _, _, h => by
    unfold validateFiles at h
    simp only [Option.some.injEq] at h
    subst h
    simp
  | n + 1, f :: fs, ts, ht, hC, h => by
    simp only [Cost_validate_files] at hC ⊢
    unfold validateFiles at h
    cases er : validateTree g f.tokens f.prods f.parents with
    | none => simp [er, consRoot] at h
    | some r =>
      cases ers : validateFiles g fs with
      | none => simp [er, ers, consRoot] at h
      | some rs =>
        simp only [er, ers, consRoot, Option.some.injEq] at h hC ⊢
        subst h
        have c := cost_cons_root_some (n := n) (r := r) (rs := rs) (by omega)
        have h1 := validateTree_post hT g n f (ht f List.mem_cons_self) (by omega) er
        have h2 := validateFiles_post hT g n fs rs (fun f' hf' => ht f' (List.mem_cons_of_mem _ hf')) (by omega) ers
        simp only [hb_cons]
        omega

theorem hb_nats : ∀ l : List Nat, hb l = l.length
  | [] => rfl
  | a :: l => by simp only [hb_cons, hb_nat, Nat.zero_max, List.length_cons, hb_nats l]

theorem hb_words : ∀ l : List (BitVec 32), hb l = l.length
  | [] => rfl
  | a :: l => by simp only [hb_cons, hb_bitvec, Nat.zero_max, List.length_cons, hb_words l]

end Lanius.Open.PostFrontEndWords

open Lanius.Open.PostFrontEndWords in
theorem Lanius.Open.PostFrontEndWords.proof : Lanius.Open.PostFrontEndWords := by
  intro n g W M _ hW hC
  rcases n with _ | k
  · simp only [Cost_front_end_words] at hC; omega
  simp only [Cost_front_end_words] at hC ⊢
  unfold frontEndWords
  cases hr : readCountedFiles W with
  | none => simp
  | some r =>
  simp only [hr] at hC ⊢
  rcases W with _ | ⟨w, rest⟩
  · simp [readCountedFiles] at hr
  have hr' : readFiles rest (wordNum w) = some r := hr
  have tok := (readFiles_ok rest (wordNum w) r hr').2
  rw [hb_words] at hW
  simp only [List.length_cons] at hW
  have hT : ∀ f ∈ r.files, TokH (rest.length + 1) f.tokens := by
    intro f hf t ht
    have := tok f hf t ht
    cases t with
    | mk kd st tx =>
      simp only [hb_Token_mk, hb_nats] at this ⊢
      omega
  unfold frontEndRead
  rcases k with _ | j
  · simp only [Cost_front_end_read] at hC; omega
  simp only [Cost_front_end_read] at hC ⊢
  cases hrest : r.rest with
  | cons => simp
  | nil =>
  simp only [hrest] at hC ⊢
  unfold frontEndFiles
  rcases j with _ | i
  · simp only [Cost_front_end_files] at hC; omega
  simp only [Cost_front_end_files] at hC ⊢
  cases hv : validateFiles g r.files with
  | none => simp
  | some ts =>
  simp only [hv] at hC ⊢
  have hC' : Cost_read_counted_files (i + 1 + 1) (w :: rest) +
      (Cost_validate_files i g r.files + Cost_build_files i (filesFuel r.files) ts) < 2 ^ 64 := hC
  show hb (buildFiles (filesFuel r.files) ts) ≤ M + (Cost_read_counted_files (i + 1 + 1) (w :: rest) +
      (Cost_validate_files i g r.files + Cost_build_files i (filesFuel r.files) ts))
  clear hC
  have pv := validateFiles_post (T := rest.length + 1) (by omega) g i r.files ts hT (by omega) hv
  have pb := post_build_files i (filesFuel r.files) ts _ pv (by omega)
  omega
