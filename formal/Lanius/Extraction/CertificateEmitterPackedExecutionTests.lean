import Lanius.Extraction.CertificateEmitterPackedExecution

namespace Lanius.Extraction.CertificateEmitterPackedExecutionTests

open Lanius Lanius.Core Lanius.Extraction Lanius.Semantics
open Lanius.Extraction.CertificateEmitterExecution
open Lanius.Extraction.CertificateEmitterPackedExecution
open Lanius.Extraction.OutputPacking
open Lanius.Extraction.CertificateEmitterFrame

example {program : Program} {hexWord hexByte : FunctionId} {body : Stmt}
    (execution : SourceCertificateOrchestration program hexWord hexByte)
    (trace : SourceCertificatePackTrace execution body) (certificate : Certificate)
    (bytesEq : trace.bytes =
      (CertificateRoundTrip.encodeCertificate certificate).toUTF8.data.toList)
    (representable : CertificateRoundTrip.Representable certificate) :
    trace.finalOutput =
        pack ((CertificateRoundTrip.encodeCertificate certificate).toUTF8.data.toList) ∧
      WriteFrame execution.caller trace.final execution.root
        (.array (pack ((CertificateRoundTrip.encodeCertificate certificate).toUTF8.data.toList))) ∧
      decodeCertificate? (CertificateRoundTrip.encodeCertificate certificate) = some certificate := by
  exact sourceCertificatePack_roundtrip execution trace certificate bytesEq representable

end Lanius.Extraction.CertificateEmitterPackedExecutionTests
