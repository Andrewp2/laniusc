import Lanius.Extraction.CertificateEmitterHexWordExecution

namespace Lanius.Extraction.CertificateEmitterHexWordSequenceTests

open Lanius Lanius.Core Lanius.Extraction Lanius.Semantics Lanius.Extraction.CertificateEmitterHexWordExecution Lanius.Extraction.CertificateEmitterHexWord Lanius.Extraction.CertificateEmitterFrame

example {program : Program} {hexWord : FunctionId} {caller : State} {root : CellId} {elements : List Value}
    {capacity position : Nat} {work : List Int} {workLength stride : Nat} {finalEnd : Int} {arguments : List Expr}
    (table : SourceFunctionTable work workLength stride 0 [] finalEnd)
    (step : SourceHexWordStep program hexWord caller root elements capacity position 0 arguments)
    (bound : root < caller.nextCell) : position + 8 + 16 * 0 = position + 8 ∧ step.after.cellEntry? root = some
      { id := root, value := some (.array (hexWordElements elements position 0)) } ∧
    WriteFrame caller step.after root (.array (hexWordElements elements position 0)) := by
  let trace : SourceEmitFunctionsTrace program hexWord root capacity caller elements position work workLength stride 0 [] finalEnd arguments
      (position + 8) step.after :=
    { table := table
      countStep := step
      trace := .nil }
  simpa [trace, sourceEmitFunctionsElements, sourceFunctionWords, sourceFunctionSpans, sourceHexWordElements] using
    sourceEmitFunctions_result trace bound

end Lanius.Extraction.CertificateEmitterHexWordSequenceTests
