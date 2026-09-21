import Lanius.Compiler.EndToEndCheck
import Lanius.Extraction.CertificateBoundaryBridge

namespace Lanius.Compiler.CertificateEncodingBridge

open Lanius.Compiler.ProgramLowering
open Lanius.Extraction
open Lanius.Extraction.CertificateBoundaryBridge
open Lanius.Extraction.CertificateRoundTrip

/-! An accepted end-to-end result contains the accepted v3 certificate as a
    dependent field.  Reusing that real boundary equality, the generic
    representable encoder round trip identifies the certificate all the way at
    the end-to-end proof spine. -/

theorem check_certificate_exact
    {certificate : Certificate}
    {expectedSources : List SourceFile}
    {resolver : ExternalBehaviorResolver}
    {checked : EndToEndCheck.Checked
      (encodeCertificate certificate) expectedSources resolver}
    (representable : Representable certificate)
    (_accepted : EndToEndCheck.check (encodeCertificate certificate)
      expectedSources resolver = .ok checked) :
    checked.certificate.certificate.certificate = certificate := by
  exact Extraction.CertificateBoundaryBridge.check_certificate_exact
    representable checked.certificate.certificateAccepted

theorem check_certificate_fields_exact
    {certificate : Certificate}
    {expectedSources : List SourceFile}
    {resolver : ExternalBehaviorResolver}
    {checked : EndToEndCheck.Checked
      (encodeCertificate certificate) expectedSources resolver}
    (representable : Representable certificate)
    (accepted : EndToEndCheck.check (encodeCertificate certificate)
      expectedSources resolver = .ok checked) :
    checked.certificate.certificate.certificate.compact = certificate.compact ∧
      checked.certificate.certificate.certificate.transport = certificate.transport ∧
      checked.certificate.certificate.certificate.elf = certificate.elf ∧
      checked.certificate.certificate.certificate.functions = certificate.functions := by
  have exact := check_certificate_exact representable accepted
  rw [exact]
  exact ⟨rfl, rfl, rfl, rfl⟩

end Lanius.Compiler.CertificateEncodingBridge
