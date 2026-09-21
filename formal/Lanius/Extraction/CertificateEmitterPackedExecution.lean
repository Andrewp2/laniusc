import Lanius.Extraction.CertificateEmitterExecution
import Lanius.Extraction.CertificateEmitterPackingExecution
import Lanius.Extraction.CertificateRoundTrip

namespace Lanius.Extraction.CertificateEmitterPackedExecution

open Lanius Lanius.Core Lanius.Extraction Lanius.Semantics
open Lanius.Extraction.CertificateEmitterFrame Lanius.Extraction.CertificateEmitterExecution
  Lanius.Extraction.CertificateEmitterPackingExecution Lanius.Extraction.OutputPacking

def sourceCertificateByteValues (bytes : List UInt8) : List Value :=
  bytes.map (fun byte => .signed .i32 (Int.ofNat byte.toNat))

def sourceCertificateEncodedBytes (certificate : Certificate) : List UInt8 :=
  (CertificateRoundTrip.encodeCertificate certificate).toUTF8.data.toList

structure SourceCertificatePackTrace
    (execution : SourceCertificateOrchestration program hexWord hexByte) (body : Stmt) where
  bytes : List UInt8
  steps : List (SourcePackStep program body execution.root)
  final : State
  finalOutput : List Value
  bytesLength : bytes.length = execution.functionFinish
  sourcePrefix : (sourceCertificateElementsOf execution).take bytes.length =
    sourceCertificateByteValues bytes
  initialMemory : execution.functionAfter.cellEntry? execution.root = some
    { id := execution.root,
      value := some (.array (sourceCertificateElementsOf execution)) }
  pack : PackTrace program body execution.root steps execution.functionAfter
    bytes [] final [] finalOutput

private theorem rootBound_after {before after : State} {root : CellId} {value : Value}
    (frame : WriteFrame before after root value) (bound : root < before.nextCell) :
    root < after.nextCell := by
  rcases frame with ⟨middle, caller, _, next, _, _, _, _⟩
  rcases caller.cells with ⟨_, _, frontier, _⟩
  rw [next]; exact Nat.lt_of_lt_of_le bound frontier

theorem sourceCertificatePack_result
    (execution : SourceCertificateOrchestration program hexWord hexByte)
    (trace : SourceCertificatePackTrace execution body) :
    execution.functionAfter.cellEntry? execution.root = some
        { id := execution.root,
          value := some (.array (sourceCertificateElementsOf execution)) } ∧
      trace.bytes.length = execution.functionFinish ∧
      (sourceCertificateElementsOf execution).take trace.bytes.length =
        sourceCertificateByteValues trace.bytes ∧
      trace.finalOutput = pack trace.bytes ∧
      trace.steps.length = (trace.bytes.length + 3) / 4 ∧
      WriteFrame execution.caller trace.final execution.root
        (.array (pack trace.bytes)) := by
  have certificate := sourceCertificate_result_of_orchestration execution
  have afterBound := rootBound_after certificate.2.2 execution.rootBound
  have packed := sourcePackTrace_result trace.pack afterBound
  have countPositive : 0 < (trace.bytes.length + 3) / 4 := by
    rw [trace.bytesLength, certificate.1]
    rcases execution.compactBounds with ⟨compactStart, compactEndBound⟩
    omega
  have stepsNonempty : trace.steps ≠ [] := by
    intro empty
    have lengthZero : trace.steps.length = 0 := by simp [empty]
    omega
  refine ⟨trace.initialMemory, trace.bytesLength, trace.sourcePrefix, ?_, packed.2.1, ?_⟩
  · simpa using packed.1
  rcases packed.2.2 with empty | frame
  · exact False.elim (stepsNonempty empty.1)
  · have packedOutput : trace.finalOutput = pack trace.bytes := by simpa using packed.1
    have finalFrame : WriteFrame execution.functionAfter trace.final execution.root
        (.array (pack trace.bytes)) := by simpa [packedOutput] using frame
    exact WriteFrame.trans certificate.2.2 finalFrame execution.rootBound

theorem sourceCertificatePack_roundtrip
    (execution : SourceCertificateOrchestration program hexWord hexByte)
    (trace : SourceCertificatePackTrace execution body) (certificate : Certificate)
    (bytesEq : trace.bytes =
      (CertificateRoundTrip.encodeCertificate certificate).toUTF8.data.toList)
    (representable : CertificateRoundTrip.Representable certificate) :
    trace.finalOutput = pack (sourceCertificateEncodedBytes certificate) ∧
      WriteFrame execution.caller trace.final execution.root
        (.array (pack (sourceCertificateEncodedBytes certificate))) ∧
      decodeCertificate? (CertificateRoundTrip.encodeCertificate certificate) = some certificate := by
  have packed := sourceCertificatePack_result execution trace
  have output := packed.2.2.2.1
  have frame := packed.2.2.2.2.2
  refine ⟨?_, ?_, CertificateRoundTrip.decodeCertificate_roundtrip certificate representable⟩
  · simpa [sourceCertificateEncodedBytes, bytesEq] using output
  · simpa [sourceCertificateEncodedBytes, bytesEq] using frame

end Lanius.Extraction.CertificateEmitterPackedExecution
