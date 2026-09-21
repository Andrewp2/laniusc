import Lanius.Extraction.CertificateEmitterHexWordExecution

namespace Lanius.Extraction.CertificateEmitterHeaderExecution

open Lanius Lanius.Core Lanius.Extraction Lanius.Semantics
open Lanius.Extraction.CertificateEmitterFrame
open Lanius.Extraction.CertificateEmitterHexWord

abbrev SourceHexWordStep := CertificateEmitterHexWordExecution.SourceHexWordStep

def headerElements (elements : List Value) (position : Nat) (compactLength : Int) : List Value :=
  hexWordElements (hexWordElements elements position 3) (position + 8) compactLength

theorem headerElements_length
    (elements : List Value) (position : Nat) (compactLength : Int)
    (bounds : position + 16 ≤ elements.length) :
    (headerElements elements position compactLength).length = elements.length := by
  have first := hexWordElements_canonical elements position 3 (by omega)
  have second := hexWordElements_canonical
    (hexWordElements elements position 3) (position + 8) compactLength (by
      rw [first.1]
      omega)
  calc
    (headerElements elements position compactLength).length =
        (hexWordElements elements position 3).length := by
          simpa [headerElements] using second.1
    _ = elements.length := first.1

/- The two actual source call shapes are kept explicit, while their execution
   witnesses remain generic.  The second call starts at the position returned
   by the first, so the final result is position + 16. -/
theorem emitHeader_hexWord_steps
    {program : Program} {hexWord : FunctionId} {caller : State} {root : CellId}
    {elements : List Value} {capacity position : Nat} {compactLength : Int}
    (rootBound : root < caller.nextCell)
    (bounds : position + 16 ≤ elements.length)
    (first : SourceHexWordStep program hexWord caller root elements capacity position 3
      [.local 1, .local 2, .local 3, .constant 0])
    (second : SourceHexWordStep program hexWord first.after root
      (hexWordElements elements position 3) capacity (position + 8) compactLength
      [.local 1, .local 2, .local 4, .local 0]) :
    StableExpr second.threshold program first.after
      (.call hexWord [.local 1, .local 2, .local 4, .local 0])
      (.signed .i32 (Int.ofNat (position + 16))) second.after ∧
      second.after.cellEntry? root = some
        { id := root, value := some (.array (headerElements elements position compactLength)) } ∧
      WriteFrame caller second.after root
        (.array (headerElements elements position compactLength)) ∧
      (headerElements elements position compactLength).length = elements.length := by
  have frame := WriteFrame.trans first.frame second.frame rootBound
  refine ⟨?_, ?_, ?_, headerElements_length elements position compactLength bounds⟩
  · simpa [show position + 8 + 8 = position + 16 by omega] using second.stable
  · simpa [headerElements] using second.memory
  · simpa [headerElements] using frame

end Lanius.Extraction.CertificateEmitterHeaderExecution
