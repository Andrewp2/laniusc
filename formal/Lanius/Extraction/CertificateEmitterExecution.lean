import Lanius.Extraction.CertificateEmitterHeaderExecution

namespace Lanius.Extraction.CertificateEmitterExecution

open Lanius Lanius.Core Lanius.Extraction Lanius.Semantics
open Lanius.Extraction.CertificateEmitterFrame
open Lanius.Extraction.CertificateEmitterHeaderExecution
open Lanius.Extraction.CertificateEmitterHexWordExecution
open Lanius.Extraction.CertificateEmitterHexWord

structure SourceCertificateOrchestration (program : Program) (hexWord hexByte : FunctionId) where
  root : CellId
  capacity : Nat
  caller : State
  elements : List Value
  compactEnd : Nat
  compactLength : Int
  rootBound : root < caller.nextCell
  compactBounds : 16 ≤ compactEnd ∧ compactEnd ≤ elements.length
  headerFirst : CertificateEmitterHexWordExecution.SourceHexWordStep program hexWord caller root elements capacity 0 3
    [.local 1, .local 2, .local 3, .constant 0]
  headerSecond : CertificateEmitterHexWordExecution.SourceHexWordStep program hexWord headerFirst.after root
    (hexWordElements elements 0 3) capacity 8 compactLength
    [.local 1, .local 2, .local 4, .local 0]
  transportWords : List Int
  transportWordsLength : Nat
  transportCount : Nat
  transportArgs : List Expr
  transportFinish : Nat
  transportAfter : State
  transport : SourceEmitTransportTrace program hexWord root capacity headerSecond.after
    (headerElements elements 0 compactLength) compactEnd transportWords transportWordsLength
    transportCount transportArgs transportFinish transportAfter
  imageValues : List Nat
  imageLength : Nat
  imageArgs : List Expr
  imageFinish : Nat
  imageAfter : State
  image : SourceEmitImageTrace program hexWord hexByte root capacity transportAfter
    (sourceEmitTransportElements (headerElements elements 0 compactLength) compactEnd
      transportCount (transportWords.take transportCount)) transportFinish imageValues imageLength
    imageArgs imageFinish imageAfter
  functionWork : List Int
  functionWorkLength : Nat
  functionStride : Nat
  functionCount : Nat
  functionStarts : List Int
  functionFinalEnd : Int
  functionArgs : List Expr
  functionFinish : Nat
  functionAfter : State
  functions : SourceEmitFunctionsTrace program hexWord root capacity imageAfter
    (sourceEmitImageElements
      (sourceEmitTransportElements (headerElements elements 0 compactLength) compactEnd
        transportCount (transportWords.take transportCount)) imageFinish imageLength
      (imageValues.take imageLength)) imageFinish functionWork functionWorkLength functionStride functionCount
    functionStarts functionFinalEnd functionArgs functionFinish functionAfter

structure SourceCertificateTrace (program : Program) (hexWord hexByte : FunctionId) where
  orchestration : SourceCertificateOrchestration program hexWord hexByte

def SourceCertificateOrchestration.toTrace
    (execution : SourceCertificateOrchestration program hexWord hexByte) :
    SourceCertificateTrace program hexWord hexByte :=
  { orchestration := execution }

def sourceCertificateElementsOf
    (execution : SourceCertificateOrchestration program hexWord hexByte) : List Value :=
  sourceEmitFunctionsElements
    (sourceEmitImageElements
      (sourceEmitTransportElements (headerElements execution.elements 0 execution.compactLength)
        execution.compactEnd execution.transportCount
        (execution.transportWords.take execution.transportCount))
      execution.imageFinish execution.imageLength (execution.imageValues.take execution.imageLength))
    execution.imageFinish execution.functionCount execution.functionStarts execution.functionFinalEnd

def sourceCertificateElements (trace : SourceCertificateTrace program hexWord hexByte) : List Value :=
  sourceCertificateElementsOf trace.orchestration

private theorem rootBound_after {before after : State} {root : CellId} {value : Value}
    (frame : WriteFrame before after root value) (bound : root < before.nextCell) :
    root < after.nextCell := by
  rcases frame with ⟨middle, caller, _, next, _, _, _, _⟩
  rcases caller.cells with ⟨_, _, frontier, _⟩
  rw [next]
  exact Nat.lt_of_lt_of_le bound frontier

theorem sourceCertificate_result_of_orchestration
    (execution : SourceCertificateOrchestration program hexWord hexByte) :
    execution.functionFinish =
        execution.compactEnd + 8 * (execution.transport.values.length + 1) +
          8 + 2 * execution.image.values.length + 8 + 16 * execution.functionCount ∧
      execution.functionAfter.cellEntry? execution.root = some
        { id := execution.root, value := some (.array (sourceCertificateElementsOf execution)) } ∧
      WriteFrame execution.caller execution.functionAfter execution.root
        (.array (sourceCertificateElementsOf execution)) := by
  rcases execution.compactBounds with ⟨compactStart, compactEndBound⟩
  have headerBounds : 0 + 16 ≤ execution.elements.length := by omega
  have header := emitHeader_hexWord_steps execution.rootBound headerBounds
    execution.headerFirst execution.headerSecond
  have headerFrame := header.2.2.1
  have afterHeaderBound := rootBound_after headerFrame execution.rootBound
  rcases sourceEmitTransport_result execution.transport afterHeaderBound with
    ⟨transportFinishEq, transportMemory, transportFrame⟩
  have afterTransportBound := rootBound_after transportFrame afterHeaderBound
  rcases sourceEmitImage_result execution.image afterTransportBound with
    ⟨imageFinishEq, imageMemory, imageFrame⟩
  have afterImageBound := rootBound_after imageFrame afterTransportBound
  rcases sourceEmitFunctions_result execution.functions afterImageBound with
    ⟨functionFinishEq, functionMemory, functionsFrame⟩
  refine ⟨by omega, ?_, ?_⟩
  · simpa [sourceCertificateElementsOf] using functionMemory
  · simpa [sourceCertificateElementsOf] using
      (WriteFrame.trans (WriteFrame.trans
        (WriteFrame.trans headerFrame transportFrame execution.rootBound)
        imageFrame execution.rootBound) functionsFrame execution.rootBound)

theorem sourceCertificate_result
    (execution : SourceCertificateOrchestration program hexWord hexByte) :
    execution.functionFinish =
        execution.compactEnd + 8 * (execution.transport.values.length + 1) +
          8 + 2 * execution.image.values.length + 8 + 16 * execution.functionCount ∧
      execution.functionAfter.cellEntry? execution.root = some
        { id := execution.root, value := some (.array (sourceCertificateElements execution.toTrace)) } ∧
      WriteFrame execution.caller execution.functionAfter execution.root
        (.array (sourceCertificateElements execution.toTrace)) := by
  simpa [SourceCertificateOrchestration.toTrace, sourceCertificateElements] using
    sourceCertificate_result_of_orchestration execution

end Lanius.Extraction.CertificateEmitterExecution
