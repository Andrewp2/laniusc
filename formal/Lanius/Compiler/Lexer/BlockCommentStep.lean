import Lanius.Compiler.Lexer.ArtifactComments
import Lanius.Compiler.Lexer.ScanEndValue
import Lanius.Compiler.Lexer.ScannerCondition
import Lanius.Compiler.Lexer.ScannerStep

namespace Lanius.Compiler.Lexer

open Lanius Lanius.Core Lanius.Semantics
open Lanius.Compiler.Lexer.Artifact

theorem blockCommentLoopBody_close
    (program : Program) {caller current : State} {cell : CellId}
    {source : List Byte} {cursor cursorCellId : Nat}
    (_invariant : ScannerInvariant caller current cell source cursor cursorCellId)
    (conditionRun : StableExpr 9 program current Artifact.blockCondition
      (.boolean true) current)
    {callFuel : Nat} {callAfter : State}
    (callRun : StableExpr callFuel program current
      (.call 11 [.binary .add (.local 3) (.value (.signed .i32 2))])
      (successfulScanValue (cursor + 2)) callAfter) :
    StableStmt (max 9 (callFuel + 2) + 2) program current Artifact.blockLoopBody
      (.returned (some (scanEndValue (.success (cursor + 2))))) callAfter := by
  have returned := StableStmt.returnValueSequence program current
    (.call 11 [.binary .add (.local 3) (.value (.signed .i32 2))])
    (successfulScanValue (cursor + 2)) callRun
  have blockReturnEq : Artifact.blockReturn =
      (.sequence (.returnValue (some
        (.call 11 [.binary .add (.local 3) (.value (.signed .i32 2))]))) .skip) := rfl
  rw [← blockReturnEq] at returned
  simpa [Artifact.blockLoopBody, blockReturnEq, successfulScanValue, Nat.add_assoc] using
    (StableStmt.sequence_completed (second := Artifact.scannerLoopBody)
      (StableStmt.ifThenElse_true (elseBranch := .skip) conditionRun returned) (by simp))

theorem blockCommentLoopBody_ordinary
    (program : Program) {caller current : State} {cell : CellId}
    {source : List Byte} {cursor cursorCellId : Nat}
    (invariant : ScannerInvariant caller current cell source cursor cursorCellId)
    (inBounds : cursor < source.length)
    (backing : SourceBacking caller cell (sourceI32Values source))
    (conditionRun : StableExpr 9 program current Artifact.blockCondition
      (.boolean false) current) :
    ∃ after, StableStmt 11 program current Artifact.blockLoopBody .next after ∧
      ScannerInvariant caller after cell source (cursor + 1) cursorCellId := by
  obtain ⟨after, incrementRun, nextInvariant⟩ :=
    scannerLoopBody_step program invariant inBounds backing
  exact ⟨after, by simpa [Artifact.blockLoopBody] using
    (StableStmt.sequence_next
      (StableStmt.ifThenElse_false conditionRun (StableStmt.skip program current)) incrementRun),
    nextInvariant⟩

end Lanius.Compiler.Lexer
