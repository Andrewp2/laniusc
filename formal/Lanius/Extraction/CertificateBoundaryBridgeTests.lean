import Lanius.Extraction.CertificateBoundaryBridge

namespace Lanius.Extraction.CertificateBoundaryBridgeTests

open Lanius.Extraction
open Lanius.Extraction.CertificateBoundaryBridge
open Lanius.Extraction.CertificateRoundTrip

-- The bridge is phrased over the authoritative checker result rather than a
-- fixture: arbitrary representable certificates may still fail the semantic
-- frontend/backend/core stages.
#check check_certificate_exact
#check check_certificate_fields_exact

example
    {certificate : Certificate}
    {expectedSources : List SourceFile}
    {checked : CertificateBoundary.Checked
      (encodeCertificate certificate) expectedSources}
    (representable : Representable certificate)
    (accepted : CertificateBoundary.check (encodeCertificate certificate)
      expectedSources = .ok checked) :
    checked.certificate = certificate := by
  exact check_certificate_exact representable accepted

end Lanius.Extraction.CertificateBoundaryBridgeTests
