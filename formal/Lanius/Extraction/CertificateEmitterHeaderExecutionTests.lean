import Lanius.Extraction.CertificateEmitterHeaderExecution

namespace Lanius.Extraction.CertificateEmitterHeaderExecutionTests

open Lanius Lanius.Core Lanius.Extraction Lanius.Semantics
open Lanius.Extraction.CertificateEmitterHeaderExecution
open Lanius.Extraction.CertificateEmitterHexWord

example : (headerElements (List.replicate 16 (.signed .i32 0)) 0 0).length = 16 := by
  have h := headerElements_length (List.replicate 16 (.signed .i32 0)) 0 0 (by decide)
  simpa using h

example (program : Program) (hexWord : FunctionId) (caller : Semantics.State)
    (root : CellId) (elements : List Value) (capacity position : Nat) (compactLength : Int)
    (rootBound : root < caller.nextCell) (bounds : position + 16 ≤ elements.length)
    (first : SourceHexWordStep program hexWord caller root elements capacity position 3
      [.local 1, .local 2, .local 3, .constant 0])
    (second : SourceHexWordStep program hexWord first.after root
      (hexWordElements elements position 3) capacity (position + 8) compactLength
      [.local 1, .local 2, .local 4, .local 0]) :
    second.after.cellEntry? root = some
      { id := root, value := some (.array (headerElements elements position compactLength)) } := by
  exact (emitHeader_hexWord_steps rootBound bounds first second).2.1

end Lanius.Extraction.CertificateEmitterHeaderExecutionTests
