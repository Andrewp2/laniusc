import Lanius.Open.Cert.CertShallowSound.Stmt
import Lanius.Open.Cert.CertCheckFacts.Stmt
import Lanius.Open.Cert.CertMatchSound.Stmt

/-! `CertShallowSound` from what an accepting check verifies and the
soundness of matching: induction on rules, and within a theorem on its steps. -/

namespace Lanius.Cert

theorem steps_hold {M : Model} {w : Words} (F : CheckFacts w) (msound : Lanius.Open.CertMatchSound)
    {r s0 : Int} (earlier : ∀ ρ, 0 ≤ ρ → ρ < r → RuleHolds M w ρ) (rlt : r < nRules w)
    (ok : ∀ s, s0 ≤ s → s < ruleEnd w r → StepOk w r s0 s)
    {σ : Nat → Nat} (hyps : ∀ j : Nat, (j : Int) < nHyps w r → Holds M w σ (hyp w r j)) :
    ∀ s, s0 ≤ s → s < ruleEnd w r → Holds M w σ (result w s) := by
  intro s
  induction h : (s - s0).toNat using Nat.strongRecOn generalizing s with
  | _ m ih =>
    intro lo hi
    have below : ∀ p, s0 ≤ p → p < s → (p - s0).toNat < m ∧ p < ruleEnd w r := by
      intro p a b; omega
    obtain ⟨res0, resLt, var | ⟨rule0, ruleLt, concl_m, prems⟩⟩ := ok s lo hi
    · obtain ⟨_, j, jlt, same⟩ := var
      rw [← same]
      exact hyps j jlt
    · have ρOk := F.rules (stepRule w s) rule0 (by omega)
      have := msound M σ w _ _ _ _ F.nonneg F.ordered (F.nonneg _) ρOk.1 res0 resLt concl_m
      unfold Holds
      rw [this]
      apply earlier _ rule0 ruleLt
      intro k klt
      obtain ⟨p, plo, phi, pm⟩ := prems k klt
      obtain ⟨p0, pLt, _⟩ := ok p plo (below p plo phi).2
      have eq : den M w σ (result w p) =
          den M w (fun k => den M w σ (rd w (oPool w + stepSubst w s + k))) (hyp w (stepRule w s) k) :=
        msound M σ w _ _ _ _ F.nonneg F.ordered (F.nonneg _) (ρOk.2 k klt) p0 pLt pm
      unfold Holds
      rw [← eq]
      exact ih (p - s0).toNat (below p plo phi).1 p rfl plo (below p plo phi).2

end Lanius.Cert

theorem Lanius.Open.CertShallowSound.red1 (facts : Lanius.Open.CertCheckFacts)
    (msound : Lanius.Open.CertMatchSound) : Lanius.Open.CertShallowSound := by
  intro M fuel w accepted axioms
  have F := facts fuel w accepted
  have all : ∀ r, 0 ≤ r → r < Lanius.Cert.nRules w → Lanius.Cert.RuleHolds M w r := by
    intro r
    induction h : r.toNat using Nat.strongRecOn generalizing r with
    | _ m ih =>
      intro r0 rlt
      by_cases ax : Lanius.Cert.kind w r = 0
      · exact axioms r r0 rlt ax
      · obtain ⟨s0, s0lt, last, ok⟩ := F.theorems r r0 rlt ax
        intro σ hyps
        rw [← last]
        exact Lanius.Cert.steps_hold F msound (fun ρ ρ0 ρlt => ih ρ.toNat (by omega) ρ rfl ρ0 (by omega)) rlt ok hyps
          _ (by omega) (by omega)
  exact fun r r0 rlt _ => all r r0 rlt
