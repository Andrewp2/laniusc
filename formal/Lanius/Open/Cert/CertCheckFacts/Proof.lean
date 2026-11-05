import Lanius.Open.Cert.CertCheckFacts.Stmt

/-! `CertCheckFacts`: each loop of `check` returns 0 only when its check
passes at every index from its start to its bound (induction on the loop's
fuel); `check` returning 0 puts those together. -/

namespace Lanius.Cert

theorem rd_past (w : Words) {i : Int} (h : (w.length : Int) ≤ i) : rd w i = 0 := by
  unfold rd
  rw [if_neg (by omega)]
  simp [List.getD_eq_getElem?_getD, List.getElem?_eq_none, show w.length ≤ i.toNat by omega]

theorem negLoop_ok (w : Words) (count : Int) : ∀ (fuel : Nat) (i : Int), negLoop w count fuel i = 0 →
    ∀ j, i ≤ j → j < count → 0 ≤ rd w j
  | 0, _, h => by simp [negLoop] at h
  | fuel + 1, i, h => by
    intro j lo hi
    simp only [negLoop] at h
    split at h
    · split at h
      · omega
      · by_cases e : j = i
        · subst e; omega
        · exact negLoop_ok w count fuel (i + 1) h j (by omega) hi
    · omega

theorem nonneg_of (w : Words) (fuel : Nat) (h : negLoop w w.length fuel 0 = 0) : ∀ i, 0 ≤ rd w i := by
  intro i
  by_cases i0 : i < 0
  · simp [rd, i0]
  by_cases ic : i < w.length
  · exact negLoop_ok w _ fuel 0 h i (by omega) ic
  · rw [rd_past w (by omega)]
    exact Int.le_refl 0

theorem nodeArgLoop_ok (w : Words) (oN oC oP i a ao ar : Int) : ∀ (fuel : Nat) (j0 : Int),
    nodeArgLoop w oN oC oP i a ao ar fuel j0 = 0 → ∀ j, j0 ≤ j → j < ar → rd w (oP + a + j) < i
  | 0, _, h => by simp [nodeArgLoop] at h
  | fuel + 1, j0, h => by
    intro j lo hi
    simp only [nodeArgLoop] at h
    split at h
    · split at h
      · omega
      · split at h
        · omega
        · by_cases e : j = j0
          · subst e; omega
          · exact nodeArgLoop_ok w oN oC oP i a ao ar fuel (j0 + 1) h j (by omega) hi
    · omega

theorem nodeLoop_ok (w : Words) (oN oC oP ns nc nn np : Int) : ∀ (fuel : Nat) (i0 : Int),
    nodeLoop w oN oC oP ns nc nn np fuel i0 = 0 → ∀ n, i0 ≤ n → n < nn → rd w (oN + 3 * n) ≠ VAR →
      ∀ j, 0 ≤ j → j < rd w (oC + 3 * rd w (oN + 3 * n) + 1) → rd w (oP + rd w (oN + 3 * n + 1) + j) < n
  | 0, _, h => by simp [nodeLoop] at h
  | fuel + 1, i0, h => by
    intro n lo hi nv j j0 jlt
    simp only [nodeLoop] at h
    split at h
    · split at h
      · rename_i hv
        split at h
        · omega
        · by_cases e : n = i0
          · subst e; exact absurd hv nv
          · exact nodeLoop_ok w oN oC oP ns nc nn np fuel (i0 + 1) h n (by omega) hi nv j j0 jlt
      · split at h
        · omega
        · split at h
          · omega
          · split at h
            · omega
            · rename_i hc
              by_cases e : n = i0
              · subst e
                exact nodeArgLoop_ok w _ _ _ _ _ _ _ fuel 0 (Classical.not_not.1 hc) j j0 jlt
              · exact nodeLoop_ok w oN oC oP ns nc nn np fuel (i0 + 1) h n (by omega) hi nv j j0 jlt
    · omega

theorem hypLoop_ok (w : Words) (oS oN oC oP nn ho nh : Int) : ∀ (fuel : Nat) (j0 : Int),
    hypLoop w oS oN oC oP nn ho nh fuel j0 = 0 → ∀ j, j0 ≤ j → j < nh → rd w (oP + ho + j) < nn
  | 0, _, h => by simp [hypLoop] at h
  | fuel + 1, j0, h => by
    intro j lo hi
    simp only [hypLoop] at h
    split at h
    · split at h
      · omega
      · split at h
        · omega
        · by_cases e : j = j0
          · subst e; omega
          · exact hypLoop_ok w oS oN oC oP nn ho nh fuel (j0 + 1) h j (by omega) hi
    · omega

theorem premLoop_ok (w : Words) (oN oC oSt oP so nv po rho prevEnd s rnh : Int) (mfuel : Nat) :
    ∀ (fuel : Nat) (k0 : Int), premLoop w oN oC oSt oP so nv po rho prevEnd s rnh mfuel fuel k0 = 0 →
      ∀ k, k0 ≤ k → k < rnh → ∃ p, prevEnd ≤ p ∧ p < s ∧
        matchTemplate w oN oC oP (rd w (oP + rho + k)) so nv (rd w (oSt + 4 * p + 3)) mfuel = true
  | 0, _, h => by simp [premLoop] at h
  | fuel + 1, k0, h => by
    intro k lo hi
    simp only [premLoop] at h
    split at h
    · split at h
      · omega
      · rename_i hp
        split at h
        · omega
        · rename_i hm
          by_cases e : k = k0
          · subst e
            exact ⟨rd w (oP + po + k), by omega, by omega, by simpa using hm⟩
          · exact premLoop_ok w oN oC oSt oP so nv po rho prevEnd s rnh mfuel fuel (k0 + 1) h k (by omega) hi
    · omega

theorem stepLoop_ok (w : Words) (oN oC oR oSt oP nn np nh ho r prevEnd endS : Int) (cfuel : Nat) :
    ∀ (fuel : Nat) (s0 : Int), stepLoop w oN oC oR oSt oP nn np nh ho r prevEnd endS cfuel fuel s0 = 0 →
      ∀ s, s0 ≤ s → s < endS → checkStep w oN oC oR oSt oP nn np nh ho r prevEnd s cfuel = 0
  | 0, _, h => by simp [stepLoop] at h
  | fuel + 1, s0, h => by
    intro s lo hi
    simp only [stepLoop] at h
    split at h
    · split at h
      · omega
      · rename_i hc
        by_cases e : s = s0
        · subst e; exact Classical.not_not.1 hc
        · exact stepLoop_ok w oN oC oR oSt oP nn np nh ho r prevEnd endS cfuel fuel (s0 + 1) h s (by omega) hi
    · omega

theorem checkStep_ok (w : Words) (nonneg : ∀ i, 0 ≤ rd w i) (r prevEnd s : Int) (cfuel : Nat)
    (h : checkStep w (oNodes w) (oCons w) (oRules w) (oSteps w) (oPool w) (nNodes w) (nPool w) (nHyps w r)
      (ruleWord w r 3) r prevEnd s cfuel = 0) : StepOk w r prevEnd s := by
  simp only [checkStep] at h
  simp only [StepOk, result, stepRule, stepSubst, hyp, nHyps, ruleWord, nVars, concl, Matches]
  split at h
  · omega
  rename_i resLt
  split at h
  · rename_i hv
    split at h
    · omega
    rename_i hs
    simp only [nHyps, ruleWord] at hs
    have so0 := nonneg (oSteps w + 4 * s + 1)
    refine ⟨nonneg _, by omega, Or.inl ⟨hv, (rd w (oSteps w + 4 * s + 1)).toNat, by omega, ?_⟩⟩
    rw [Int.toNat_of_nonneg (nonneg _)]
    omega
  split at h
  · omega
  split at h
  · omega
  split at h
  · omega
  split at h
  · omega
  rename_i hm
  refine ⟨nonneg _, by omega, Or.inr ⟨nonneg _, by omega, ⟨cfuel, by simpa using hm⟩, ?_⟩⟩
  intro k klt
  obtain ⟨p, a, b, c⟩ := premLoop_ok w _ _ _ _ _ _ _ _ _ _ _ cfuel cfuel 0 h k (by omega) klt
  exact ⟨p, a, b, cfuel, c⟩

/-- What `ruleLoop` checks of rule `ρ`. -/
def RuleFact (w : Words) (ρ : Int) : Prop :=
  (concl w ρ < nNodes w ∧ ∀ j : Nat, (j : Int) < nHyps w ρ → hyp w ρ j < nNodes w) ∧
  (kind w ρ ≠ 0 → ∃ s0, s0 < ruleEnd w ρ ∧ result w (ruleEnd w ρ - 1) = concl w ρ ∧
      ∀ s, s0 ≤ s → s < ruleEnd w ρ → StepOk w ρ s0 s)

theorem ruleLoop_ok (w : Words) (nonneg : ∀ i, 0 ≤ rd w i) (cfuel : Nat) : ∀ (fuel : Nat) (r prevEnd : Int),
    ruleLoop w (oSorts w) (oNodes w) (oCons w) (oRules w) (oSteps w) (oPool w) (nNodes w) (nRules w) (nSteps w)
      (nPool w) cfuel fuel r prevEnd = 0 → ∀ ρ, r ≤ ρ → ρ < nRules w → RuleFact w ρ
  | 0, _, _, h => by simp [ruleLoop] at h
  | fuel + 1, r, prevEnd, h => by
    intro ρ lo hi
    simp only [ruleLoop] at h
    split at h
    · split at h
      · omega
      rename_i bounds
      split at h
      · omega
      split at h
      · omega
      rename_i hc
      have hyps := hypLoop_ok w _ _ _ _ _ _ _ cfuel 0 (Classical.not_not.1 hc)
      have here : concl w r < nNodes w ∧ ∀ j : Nat, (j : Int) < nHyps w r → hyp w r j < nNodes w := by
        refine ⟨?_, fun j jl => hyps j (by omega) jl⟩
        show rd w (oRules w + 6 * r + 4) < nNodes w
        omega
      split at h
      · rename_i k0
        by_cases e : ρ = r
        · subst e
          refine ⟨here, fun nk => absurd ?_ nk⟩
          simpa [kind, ruleWord] using k0
        · exact ruleLoop_ok w nonneg cfuel fuel (r + 1) prevEnd h ρ (by omega) hi
      split at h
      · omega
      rename_i k1
      split at h
      · omega
      rename_i hs
      split at h
      · omega
      rename_i last
      by_cases e : ρ = r
      · subst e
        refine ⟨here, fun _ => ⟨prevEnd, ?_, ?_, ?_⟩⟩
        · show prevEnd < rd w (oRules w + 6 * ρ + 5)
          omega
        · show rd w (oSteps w + 4 * (rd w (oRules w + 6 * ρ + 5) - 1) + 3) = rd w (oRules w + 6 * ρ + 4)
          omega
        · intro s slo shi
          exact checkStep_ok w nonneg _ _ _ cfuel
            (stepLoop_ok w _ _ _ _ _ _ _ _ _ _ _ _ cfuel cfuel prevEnd (Classical.not_not.1 hs) s slo shi)
      · exact ruleLoop_ok w nonneg cfuel fuel (r + 1) _ h ρ (by omega) hi
    · omega

end Lanius.Cert

open Lanius.Cert in
theorem Lanius.Open.CertCheckFacts.proof : Lanius.Open.CertCheckFacts := by
  intro fuel w h
  simp only [check] at h
  split at h
  · omega
  split at h
  · omega
  rename_i neg
  have nonneg := nonneg_of w fuel (Classical.not_not.1 neg)
  split at h
  · omega
  split at h
  · omega
  split at h
  · omega
  split at h
  · omega
  split at h
  · omega
  rename_i nodes
  have ord := nodeLoop_ok w _ _ _ _ _ _ _ fuel 0 (Classical.not_not.1 nodes)
  have rules := ruleLoop_ok w nonneg fuel fuel 0 0 h
  exact ⟨nonneg, fun n n0 nlt nv i il => ord n n0 nlt nv i (by omega) il,
    fun r r0 rl => (rules r r0 rl).1, fun r r0 rl k => (rules r r0 rl).2 k⟩
