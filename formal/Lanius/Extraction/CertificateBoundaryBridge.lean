import Lanius.Extraction.CertificateRoundTrip

namespace Lanius.Extraction.CertificateBoundaryBridge

open Lanius.Extraction
open Lanius.Extraction.CertificateRoundTrip

/-! `CertificateRoundTrip` establishes the byte-format round trip, while
    `CertificateBoundary.Checked` is the evidence produced by the
    authoritative v3 checker.  Representability alone cannot make the
    frontend/backend/core stages succeed, so this bridge is intentionally
    conditional on the real boundary having accepted the encoded value. -/

theorem check_certificate_exact
    {certificate : Certificate}
    {expectedSources : List SourceFile}
    {checked : CertificateBoundary.Checked
      (encodeCertificate certificate) expectedSources}
    (representable : Representable certificate)
    (_accepted : CertificateBoundary.check (encodeCertificate certificate)
      expectedSources = .ok checked) :
    checked.certificate = certificate := by
  have decoded := checked.decoded
  rw [decodeCertificate_roundtrip certificate representable] at decoded
  exact (Option.some.inj decoded).symm

theorem check_certificate_fields_exact
    {certificate : Certificate}
    {expectedSources : List SourceFile}
    {checked : CertificateBoundary.Checked
      (encodeCertificate certificate) expectedSources}
    (representable : Representable certificate)
    (accepted : CertificateBoundary.check (encodeCertificate certificate)
      expectedSources = .ok checked) :
    checked.certificate.compact = certificate.compact ∧
      checked.certificate.transport = certificate.transport ∧
      checked.certificate.elf = certificate.elf ∧
      checked.certificate.functions = certificate.functions := by
  have exact := check_certificate_exact representable accepted
  rw [exact]
  exact ⟨rfl, rfl, rfl, rfl⟩

end Lanius.Extraction.CertificateBoundaryBridge
