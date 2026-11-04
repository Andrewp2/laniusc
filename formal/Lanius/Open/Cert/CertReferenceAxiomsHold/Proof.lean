import Lanius.Open.Cert.CertReferenceAxiomsHold.Stmt
import Lanius.Cert.Decode

/-! `CertReferenceAxiomsHold`: each of gen.py's 27 axioms is a fact about
Nat, and a node's value is its tree's (`den_decode`). -/

namespace Lanius.Cert

/-- A statement holds in `M` as trees. -/
def TmHolds (M : Model) (a : List Tm × Tm) : Prop :=
  ∀ σ : Nat → Nat, (∀ h ∈ a.1, denTm M σ h ≠ 0) → denTm M σ a.2 ≠ 0

theorem reference_hold : ∀ a ∈ AxiomsAreReference.referenceAxioms, TmHolds natModel a := by
  simp only [AxiomsAreReference.referenceAxioms, List.forall_mem_cons, List.forall_mem_nil, and_true]
  repeat' apply And.intro
  all_goals
    intro σ hs
    try simp only [List.mem_cons, List.not_mem_nil, or_false, forall_eq_or_imp, forall_eq, List.forall_mem_nil] at hs
    try simp only [denTm, denTms, natModel, List.getD_cons_zero, List.getD_cons_succ, ne_eq, ite_eq_right_iff,
      Classical.not_imp, Nat.one_ne_zero, not_false_eq_true, and_true] at hs ⊢
    try first
    | omega
    | (exact Nat.mul_comm _ _)
    | (exact (Nat.mul_assoc _ _ _).symm)
    | (exact Nat.mul_assoc _ _ _)
    | (rw [Nat.mul_assoc, Nat.two_mul]; done)
    | (rw [Nat.add_mul, Nat.mul_assoc, Nat.two_mul]; omega)
    | (rw [Nat.add_mul, Nat.mul_assoc, Nat.two_mul, Nat.one_mul]; done)
    | (rw [Nat.mul_add]; done)
    | (rw [Nat.add_mul]; done)
    | (simp only [Nat.add_mul, Nat.mul_add, Nat.mul_assoc, Nat.two_mul, Nat.mul_comm] <;> omega)
    | (simp_all; done)

end Lanius.Cert

theorem Lanius.Open.CertReferenceAxiomsHold.proof : Lanius.Open.CertReferenceAxiomsHold := by
  intro w reference r r0 rlt ax σ hyps
  have mem := reference r r0 rlt ax
  have holds := Lanius.Cert.reference_hold _ mem σ (by
    intro h hm
    simp only [Lanius.Cert.statement, List.mem_map, List.mem_range] at hm
    obtain ⟨j, jlt, rfl⟩ := hm
    rw [← Lanius.Cert.den_decode]
    exact hyps j (by omega))
  simp only [Lanius.Cert.statement] at holds
  rw [Lanius.Cert.Holds, Lanius.Cert.den_decode]
  exact holds
