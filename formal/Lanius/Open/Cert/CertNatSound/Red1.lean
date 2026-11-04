import Lanius.Open.Cert.CertNatSound.Stmt
import Lanius.Open.Cert.CertMainFaithful.Stmt
import Lanius.Open.Cert.CertShallowSound.Stmt
import Lanius.Open.Cert.CertReferenceAxiomsHold.Stmt

/-! `CertNatSound` from the checker's faithfulness, its soundness in every
model, and the reference axioms' truth in Nat. -/

theorem Lanius.Open.CertNatSound.red1 (faithful : Lanius.Open.CertMainFaithful)
    (sound : Lanius.Open.CertShallowSound) (axioms : Lanius.Open.CertReferenceAxiomsHold) :
    Lanius.Open.CertNatSound := by
  intro given fuel final runs reference
  obtain ⟨cfuel, accepted⟩ := faithful given fuel final runs
  exact sound _ cfuel _ accepted (axioms _ reference)
