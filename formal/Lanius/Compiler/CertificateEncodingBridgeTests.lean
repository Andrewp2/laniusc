import Lanius.Compiler.CertificateEncodingBridge

namespace Lanius.Compiler.CertificateEncodingBridgeTests

open Lanius.Compiler
open Lanius.Compiler.CertificateEncodingBridge
open Lanius.Compiler.ProgramLowering
open Lanius.Extraction
open Lanius.Extraction.CertificateRoundTrip

-- The assumptions retain the authoritative end-to-end checker equality; no
-- fixture or decoder restatement is needed at this layer.
#check check_certificate_exact
#check check_certificate_fields_exact

example
    {certificate : Certificate}
    {expectedSources : List SourceFile}
    {resolver : ExternalBehaviorResolver}
    {checked : EndToEndCheck.Checked
      (encodeCertificate certificate) expectedSources resolver}
    (representable : Representable certificate)
    (accepted : EndToEndCheck.check (encodeCertificate certificate)
      expectedSources resolver = .ok checked) :
    checked.certificate.certificate.certificate = certificate := by
  exact check_certificate_exact representable accepted

end Lanius.Compiler.CertificateEncodingBridgeTests
