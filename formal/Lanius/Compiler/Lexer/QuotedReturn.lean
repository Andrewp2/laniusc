import Lanius.Compiler.Lexer.ArtifactQuoted
import Lanius.Compiler.Lexer.QuotedInvariant
import Lanius.Compiler.Lexer.ScanEndFunctions
import Lanius.Semantics.StmtList

namespace Lanius.Compiler.Lexer

open Lanius Lanius.Core Lanius.Semantics
open Lanius.Compiler.Lexer.Artifact

theorem quotedLoopNewlineReturn_runs
    (invariant : QuotedInvariant caller current cell source delimiter cursor escaping
      cursorCellId escapingCellId) :
    ∃ after, RunsStmt Artifact.lexerProgram current Artifact.quotedLoopNewlineReturn
      (.returned (some (failedScanValue cursor))) after ∧ CallerFrame caller after := by
  have argument : ThresholdPure 1 Artifact.lexerProgram current (.local 4)
      (.signed .i32 (Int.ofNat cursor)) current :=
    ThresholdPure.localValue invariant.frame.currentFormed 4 _ invariant.cursorLocal
  obtain ⟨callFuel, callAfter, callRun⟩ :=
    failedScan_of_argument current (.local 4) cursor argument
  refine ⟨callAfter, ?_, invariant.frame.transPure callRun.frame⟩
  change RunsStmt Artifact.lexerProgram current
    (.sequence (.returnValue (some (.call Artifact.failedScanFunction.id [.local 4]))) .skip)
    (.returned (some (failedScanValue cursor))) callAfter
  exact RunsStmt.returnValueSequence
    (RunsExpr.ofStable callRun.run callRun.frame.locals : RunsExpr Artifact.lexerProgram current
      (.call Artifact.failedScanFunction.id [.local 4])
      (failedScanValue cursor) callAfter)

theorem quotedLoopDelimiterReturn_runs
    (invariant : QuotedInvariant caller current cell source delimiter cursor escaping
      cursorCellId escapingCellId)
    (cursorBound : cursor + 1 < 2 ^ 31) :
    ∃ after, RunsStmt Artifact.lexerProgram current Artifact.quotedLoopDelimiterReturn
      (.returned (some (successfulScanValue (cursor + 1)))) after ∧ CallerFrame caller after := by
  have argument := ThresholdPure.i32LocalAddNat Artifact.lexerProgram current 4 cursor 1
    invariant.cursorLocal invariant.frame.currentFormed cursorBound
  obtain ⟨callFuel, callAfter, callRun⟩ := successfulScan_of_argument current
    (.binary .add (.local 4) (.value (.signed .i32 1))) (cursor + 1) argument
  refine ⟨callAfter, ?_, invariant.frame.transPure callRun.frame⟩
  change RunsStmt Artifact.lexerProgram current
    (.sequence (.returnValue (some (.call Artifact.successfulScanFunction.id
      [.binary .add (.local 4) (.value (.signed .i32 1))]))) .skip)
    (.returned (some (successfulScanValue (cursor + 1)))) callAfter
  exact RunsStmt.returnValueSequence
    (RunsExpr.ofStable callRun.run callRun.frame.locals : RunsExpr Artifact.lexerProgram current
      (.call Artifact.successfulScanFunction.id
        [.binary .add (.local 4) (.value (.signed .i32 1))])
      (successfulScanValue (cursor + 1)) callAfter)

end Lanius.Compiler.Lexer
