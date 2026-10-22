import Lanius.Std.VecSorted2

/-! # Heapsort on lists

The facts behind `sort`: a max-heap in `[0, cnt)` under "not less than",
`sift_down`'s invariant and its three outcomes, the build phase and the
extraction phase. Elements are read with `elt a i = a.getD i .unit`. -/

namespace Lanius.Std

open Lanius Lanius.Core Lanius.Semantics

/-- `a < b` implies not `b < a`. -/
def Asymm (ltv : Value → Value → Bool) : Prop := ∀ a b, ltv a b = true → ltv b a = false

def elt (a : List Value) (i : Nat) : Value := a.getD i .unit

/-- Exchange the elements at `i` and `j`. -/
def swapAt (a : List Value) (i j : Nat) : List Value := (a.set i (elt a j)).set j (elt a i)

theorem length_swapAt (a : List Value) (i j : Nat) : (swapAt a i j).length = a.length := by
  simp [swapAt]

theorem elt_swapAt {a : List Value} {i j : Nat} (hi : i < a.length) (hj : j < a.length) (k : Nat) :
    elt (swapAt a i j) k = if k = j then elt a i else if k = i then elt a j else elt a k := by
  simp only [elt, swapAt, List.getD_eq_getElem?_getD, List.getElem?_set, List.length_set]
  by_cases kj : k = j
  · subst kj; simp [hj]
  · by_cases ki : k = i
    · subst ki; simp [hi, Ne.symm kj, kj]
    · simp [Ne.symm kj, Ne.symm ki, kj, ki]

theorem swapAt_perm {a : List Value} {i j : Nat} (hi : i < a.length) (hj : j < a.length) :
    (swapAt a i j).Perm a := by
  unfold swapAt elt
  rw [getD_of_lt hi, getD_of_lt hj]
  exact List.set_set_perm hi hj

/-! ## Heaps -/

/-- Every edge `(parent i, i)` inside `[0, cnt)` whose parent is at least
`root` is ordered. -/
def HeapFrom (ltv : Value → Value → Bool) (a : List Value) (root cnt : Nat) : Prop :=
  ∀ i, 0 < i → i < cnt → root ≤ (i - 1) / 2 → ltv (elt a ((i - 1) / 2)) (elt a i) = false

/-- `sift_down`'s state at `j`: ordered except the edges out of `j`, and the
parent of `j` is not less than `j`'s children. -/
def SiftInv (ltv : Value → Value → Bool) (a : List Value) (root cnt j : Nat) : Prop :=
  root ≤ j ∧ j < cnt ∧
    (∀ i, 0 < i → i < cnt → root ≤ (i - 1) / 2 → (i - 1) / 2 ≠ j →
      ltv (elt a ((i - 1) / 2)) (elt a i) = false) ∧
    (root < j → ∀ c, 0 < c → c < cnt → (c - 1) / 2 = j → ltv (elt a ((j - 1) / 2)) (elt a c) = false)

/-- `c` is a child of `j` not less than the other. -/
def MaxChild (ltv : Value → Value → Bool) (a : List Value) (cnt j c : Nat) : Prop :=
  0 < c ∧ c < cnt ∧ (c - 1) / 2 = j ∧
    ∀ d, 0 < d → d < cnt → (d - 1) / 2 = j → ltv (elt a c) (elt a d) = false

theorem Asymm.irrefl {ltv : Value → Value → Bool} (asymm : Asymm ltv) (x : Value) : ltv x x = false := by
  cases h : ltv x x with
  | false => rfl
  | true => have := asymm x x h; rw [h] at this; cases this

theorem maxChild_right {ltv : Value → Value → Bool} (asymm : Asymm ltv) {a : List Value} {cnt j : Nat}
    (inside : 2 * j + 2 < cnt) (less : ltv (elt a (2 * j + 1)) (elt a (2 * j + 2)) = true) :
    MaxChild ltv a cnt j (2 * j + 2) := by
  refine ⟨by omega, inside, by omega, fun d pos dc parent => ?_⟩
  rcases (show d = 2 * j + 1 ∨ d = 2 * j + 2 by omega) with rfl | rfl
  · exact asymm _ _ less
  · exact asymm.irrefl _

theorem maxChild_left {ltv : Value → Value → Bool} (asymm : Asymm ltv) {a : List Value} {cnt j : Nat}
    (inside : 2 * j + 1 < cnt) (notLess : 2 * j + 2 < cnt → ltv (elt a (2 * j + 1)) (elt a (2 * j + 2)) = false) :
    MaxChild ltv a cnt j (2 * j + 1) := by
  refine ⟨by omega, inside, by omega, fun d pos dc parent => ?_⟩
  rcases (show d = 2 * j + 1 ∨ d = 2 * j + 2 by omega) with rfl | rfl
  · exact asymm.irrefl _
  · exact notLess dc

theorem sift_stop {ltv : Value → Value → Bool} (order : NegTrans ltv) {a : List Value} {root cnt j c : Nat}
    (inv : SiftInv ltv a root cnt j) (max : MaxChild ltv a cnt j c)
    (notLess : ltv (elt a j) (elt a c) = false) : HeapFrom ltv a root cnt := by
  obtain ⟨_, _, edges, _⟩ := inv
  obtain ⟨_, _, _, top⟩ := max
  intro i pos ic rootLe
  by_cases pj : (i - 1) / 2 = j
  · rw [pj]
    cases h : ltv (elt a j) (elt a i) with
    | false => rfl
    | true =>
        rcases order _ (elt a c) _ h with h' | h'
        · rw [notLess] at h'; cases h'
        · rw [top i pos ic pj] at h'; cases h'
  · exact edges i pos ic rootLe pj

theorem sift_leaf {ltv : Value → Value → Bool} {a : List Value} {root cnt j : Nat}
    (inv : SiftInv ltv a root cnt j) (leaf : cnt ≤ 2 * j + 1) : HeapFrom ltv a root cnt := by
  obtain ⟨_, _, edges, _⟩ := inv
  intro i pos ic rootLe
  exact edges i pos ic rootLe (by omega)

theorem sift_step {ltv : Value → Value → Bool} (asymm : Asymm ltv) {a : List Value} {root cnt j c : Nat}
    (inv : SiftInv ltv a root cnt j) (max : MaxChild ltv a cnt j c)
    (less : ltv (elt a j) (elt a c) = true) (bound : cnt ≤ a.length) :
    SiftInv ltv (swapAt a j c) root cnt c := by
  obtain ⟨rootLe, jc, edges, above⟩ := inv
  obtain ⟨cpos, ccnt, cparent, top⟩ := max
  have ja : j < a.length := by omega
  have ca : c < a.length := by omega
  have cj : j < c := by omega
  have e := elt_swapAt ja ca
  refine ⟨by omega, ccnt, fun i pos ic rootP pc => ?_, fun _ d dpos dc dparent => ?_⟩
  · by_cases ic' : i = c
    · subst ic'
      rw [cparent, e, e, if_neg (by omega), if_pos rfl, if_pos rfl]
      exact asymm _ _ less
    · by_cases ij : i = j
      · subst ij
        have pLt : (i - 1) / 2 < i := by omega
        rw [e, e, if_neg (by omega), if_neg (by omega), if_neg ic', if_pos rfl]
        exact above (by omega) c cpos ccnt cparent
      · rw [e, e, if_neg ic', if_neg ij, if_neg pc]
        by_cases pj : (i - 1) / 2 = j
        · rw [if_pos pj]; exact top i pos ic pj
        · rw [if_neg pj]; exact edges i pos ic rootP pj
  · rw [cparent, e, e, if_neg (by omega), if_pos rfl, if_neg (by omega), if_neg (by omega)]
    have edge := edges d dpos dc (by omega) (by omega)
    rw [dparent] at edge; exact edge

/-! ## The two phases -/

theorem build_start (ltv : Value → Value → Bool) (a : List Value) (n : Nat) : HeapFrom ltv a (n / 2) n :=
  fun i pos inside le => absurd le (by omega)

theorem build_step {ltv : Value → Value → Bool} {a : List Value} {s n : Nat} (heap : HeapFrom ltv a s n)
    (pos : 0 < s) (inside : s - 1 < n) : SiftInv ltv a (s - 1) n (s - 1) :=
  ⟨Nat.le_refl _, inside, fun i ipos ic le ne => heap i ipos ic (by omega), fun lt => absurd lt (Nat.lt_irrefl _)⟩

theorem heap_root_max {ltv : Value → Value → Bool} (order : NegTrans ltv) (asymm : Asymm ltv)
    {a : List Value} {e : Nat} (heap : HeapFrom ltv a 0 e) : ∀ i, i < e → ltv (elt a 0) (elt a i) = false := by
  intro i
  induction i using Nat.strongRecOn with
  | _ i ih =>
      intro ie
      cases i with
      | zero => exact asymm.irrefl _
      | succ k =>
          have up := ih ((k + 1 - 1) / 2) (by omega) (by omega)
          have edge := heap (k + 1) (by omega) ie (Nat.zero_le _)
          cases h : ltv (elt a 0) (elt a (k + 1)) with
          | false => rfl
          | true =>
              rcases order _ (elt a ((k + 1 - 1) / 2)) _ h with h' | h'
              · rw [up] at h'; cases h'
              · rw [edge] at h'; cases h'

/-- The extraction phase's state at `e`: a heap in `[0, e)`, a sorted
suffix `[e, n)`, and no suffix element less than a prefix element. -/
def SortInv (ltv : Value → Value → Bool) (a : List Value) (e n : Nat) : Prop :=
  HeapFrom ltv a 0 e ∧ (∀ k l, e ≤ k → k < l → l < n → ltv (elt a l) (elt a k) = false) ∧
    (∀ i k, i < e → e ≤ k → k < n → ltv (elt a k) (elt a i) = false)

theorem sort_start {ltv : Value → Value → Bool} {a : List Value} {n : Nat} (heap : HeapFrom ltv a 0 n) :
    SortInv ltv a n n :=
  ⟨heap, fun k l kl _ ln => absurd ln (by omega), fun i k _ nk kn => absurd kn (by omega)⟩

theorem sort_swap {ltv : Value → Value → Bool} {a : List Value} {e n : Nat} (inv : SortInv ltv a e n)
    (more : 1 < e) (bound : e ≤ a.length) : SiftInv ltv (swapAt a 0 (e - 1)) 0 (e - 1) 0 := by
  obtain ⟨heap, _, _⟩ := inv
  have es := elt_swapAt (a := a) (i := 0) (j := e - 1) (by omega) (by omega)
  refine ⟨Nat.le_refl _, by omega, fun i pos ic _ p0 => ?_, fun lt => absurd lt (Nat.lt_irrefl _)⟩
  rw [es, es, if_neg (by omega), if_neg p0, if_neg (by omega), if_neg (by omega)]
  exact heap i pos (by omega) (Nat.zero_le _)

/-- What `sift_down(b, 0, cnt)` leaves: a heap, the prefix's elements from
the prefix, the rest untouched. -/
def Sifted (ltv : Value → Value → Bool) (b c : List Value) (root cnt : Nat) : Prop :=
  c.length = b.length ∧ c.Perm b ∧ HeapFrom ltv c root cnt ∧
    (∀ i, i < cnt → ∃ i', i' < cnt ∧ elt c i = elt b i') ∧ (∀ k, cnt ≤ k → elt c k = elt b k)

theorem sort_after {ltv : Value → Value → Bool} (order : NegTrans ltv) (asymm : Asymm ltv)
    {a c : List Value} {e n : Nat} (inv : SortInv ltv a e n) (more : 1 < e) (bound : e ≤ a.length)
    (sifted : Sifted ltv (swapAt a 0 (e - 1)) c 0 (e - 1)) : SortInv ltv c (e - 1) n := by
  obtain ⟨heap, suffix, split⟩ := inv
  obtain ⟨_, _, heapC, region, untouched⟩ := sifted
  have es := elt_swapAt (a := a) (i := 0) (j := e - 1) (by omega) (by omega)
  have top := heap_root_max order asymm heap
  -- an element of the new prefix is an element of the old prefix
  have fromPrefix : ∀ i, i < e - 1 → ∃ m, m < e ∧ elt c i = elt a m := by
    intro i ie
    obtain ⟨i', i'e, same⟩ := region i ie
    rw [same, es, if_neg (by omega)]
    by_cases zero : i' = 0
    · rw [if_pos zero]; exact ⟨e - 1, by omega, rfl⟩
    · rw [if_neg zero]; exact ⟨i', by omega, rfl⟩
  have last : elt c (e - 1) = elt a 0 := by rw [untouched _ (Nat.le_refl _), es, if_pos rfl]
  have rest : ∀ k, e ≤ k → elt c k = elt a k := fun k ek => by
    rw [untouched k (by omega), es, if_neg (by omega), if_neg (by omega)]
  refine ⟨heapC, fun k l kl lk ln => ?_, fun i k ie ek kn => ?_⟩
  · by_cases first : k = e - 1
    · rw [first, last, rest l (by omega)]
      exact split 0 l (by omega) (by omega) ln
    · rw [rest k (by omega), rest l (by omega)]
      exact suffix k l (by omega) lk ln
  · obtain ⟨m, me, same⟩ := fromPrefix i ie
    rw [same]
    by_cases first : k = e - 1
    · rw [first, last]; exact top m me
    · rw [rest k (by omega)]; exact split m k me (by omega) kn

theorem sort_done {ltv : Value → Value → Bool} {a : List Value} {e : Nat} (inv : SortInv ltv a e a.length)
    (done : e ≤ 1) : Sorted ltv a := by
  obtain ⟨_, suffix, split⟩ := inv
  refine List.pairwise_iff_getElem.mpr fun k l hk hl kl => ?_
  show ltv a[l] a[k] = false
  have r : ltv (elt a l) (elt a k) = false := by
    by_cases ke : e ≤ k
    · exact suffix k l ke kl hl
    · exact split k l (by omega) (by omega) hl
  unfold elt at r
  rwa [getD_of_lt hl, getD_of_lt hk] at r

#print axioms sift_step
#print axioms sort_after
#print axioms sort_done

end Lanius.Std
