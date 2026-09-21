import Lanius.Extraction.CertificateEmitterExecution

namespace Lanius.Extraction.CertificateEmitterExecutionTests

open Lanius Lanius.Core Lanius.Extraction Lanius.Semantics
open Lanius.Extraction.CertificateEmitterExecution
open Lanius.Extraction.CertificateEmitterFrame

example {program : Program} {hexWord hexByte : FunctionId}
    (execution : SourceCertificateOrchestration program hexWord hexByte) :
    execution.functionAfter.cellEntry? execution.root = some
      { id := execution.root, value := some (.array (sourceCertificateElements execution.toTrace)) } ∧
    WriteFrame execution.caller execution.functionAfter execution.root
      (.array (sourceCertificateElements execution.toTrace)) := by
  exact (sourceCertificate_result execution).2

end Lanius.Extraction.CertificateEmitterExecutionTests
