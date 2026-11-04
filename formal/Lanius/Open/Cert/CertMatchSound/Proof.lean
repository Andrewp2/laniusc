import Lanius.Open.Cert.CertMatchSound.Stmt

/-! `CertMatchSound`: every pair on `matchLoop`'s stack is its template's
instance once the loop returns true (induction on its fuel). -/

namespace Lanius.Cert

theorem den_node (M : Model) (w : Words) (σ : Nat → Nat) {n : Int} (n0 : 0 ≤ n) :
    den M w σ n = if head w n = VAR then σ (varIndex w n)
      else M (head w n).toNat ((List.range (arity w (head w n)).toNat).map fun i =>
        if hx : 0 ≤ arg w n i ∧ arg w n i < n then den M w σ (arg w n i) else 0) := by
  rw [den, if_pos n0]

/-- Both of a stack pair's nodes are nodes. -/
def PairOk (w : Words) (q : Int × Int) : Prop := 0 ≤ q.1 ∧ q.1 < nNodes w ∧ 0 ≤ q.2 ∧ q.2 < nNodes w

theorem matchLoop_sound (M : Model) (σ : Nat → Nat) (w : Words) (so nv : Int)
    (nonneg : ∀ i, 0 ≤ rd w i) (ordered : Ordered w) :
    ∀ (fuel : Nat) (stack : List (Int × Int)), (∀ q ∈ stack, PairOk w q) →
      matchLoop w (oNodes w) (oCons w) (oPool w) so nv fuel stack = true →
      ∀ q ∈ stack, den M w σ q.2 = den M w (fun k => den M w σ (rd w (oPool w + so + k))) q.1
  | 0, _, _, h => by simp [matchLoop] at h
  | _ + 1, [], _, _ => by simp
  | fuel + 1, (tt, xx) :: rest, bounds, h => by
    obtain ⟨t0, tLt, x0, xLt⟩ := bounds (tt, xx) (List.mem_cons_self ..)
    have restB : ∀ q ∈ rest, PairOk w q := fun q m => bounds q (List.mem_cons_of_mem _ m)
    simp only [matchLoop] at h
    intro q mem
    by_cases var : rd w (oNodes w + 3 * tt) = VAR
    · simp only [if_pos var] at h
      split at h
      · simp at h
      split at h
      · simp at h
      rename_i sub
      split at h
      · simp at h
      rcases List.mem_cons.1 mem with rfl | m
      · show den M w σ xx = den M w (fun k => den M w σ (rd w (oPool w + so + k))) tt
        have hv : head w tt = VAR := var
        rw [den_node M w _ t0, if_pos hv, varIndex, Int.toNat_of_nonneg (nonneg _)]
        exact congrArg (den M w σ) (Classical.not_not.1 sub).symm
      · exact matchLoop_sound M σ w so nv nonneg ordered fuel rest restB h q m
    · simp only [if_neg var] at h
      split at h
      · simp at h
      rename_i same
      split at h
      · simp at h
      have hd : head w xx = head w tt := Classical.not_not.1 same
      have tv : head w tt ≠ VAR := var
      have xv : head w xx ≠ VAR := hd ▸ tv
      have argT := ordered tt t0 tLt tv
      have argX := ordered xx x0 xLt xv
      have newB : ∀ q ∈ ((List.range (arity w (head w tt)).toNat).map fun (i : Nat) =>
          (arg w tt i, arg w xx i)).reverse ++ rest, PairOk w q := by
        intro q m
        rcases List.mem_append.1 m with m | m
        · obtain ⟨i, hi, rfl⟩ := List.mem_map.1 (List.mem_reverse.1 m)
          have hi' : (i : Int) < arity w (head w tt) := by
            have := List.mem_range.1 hi
            omega
          have a1 := argT i hi'
          have a2 := argX i (hd ▸ hi')
          exact ⟨nonneg _, by omega, nonneg _, by omega⟩
        · exact restB q m
      have ih := matchLoop_sound M σ w so nv nonneg ordered fuel _ newB h
      rcases List.mem_cons.1 mem with rfl | m
      · show den M w σ xx = den M w (fun k => den M w σ (rd w (oPool w + so + k))) tt
        rw [den_node M w _ t0, den_node M w _ x0, if_neg tv, if_neg xv, hd]
        congr 1
        apply List.map_congr_left
        intro i hi
        have hi' : (i : Int) < arity w (head w tt) := by
          have := List.mem_range.1 hi
          omega
        have a1 := argT i hi'
        have a2 := argX i (hd ▸ hi')
        rw [dif_pos (show 0 ≤ arg w xx i ∧ arg w xx i < xx from ⟨nonneg _, a2⟩), dif_pos (show 0 ≤ arg w tt i ∧ arg w tt i < tt from ⟨nonneg _, a1⟩)]
        exact ih (arg w tt i, arg w xx i)
          (List.mem_append_left _ (List.mem_reverse.2 (List.mem_map.2 ⟨i, hi, rfl⟩)))
      · exact ih q (List.mem_append_right _ m)

end Lanius.Cert

theorem Lanius.Open.CertMatchSound.proof : Lanius.Open.CertMatchSound := by
  intro M σ w t so nv x nonneg ordered t0 tLt x0 xLt ⟨fuel, h⟩
  exact Lanius.Cert.matchLoop_sound M σ w so nv nonneg ordered fuel [(t, x)]
    (by simp [Lanius.Cert.PairOk]; omega) h (t, x) (List.mem_singleton_self _)
