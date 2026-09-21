import Lanius.Compiler.Lexer.QuotedGuarded
import Lanius.Compiler.Lexer.QuotedByte
import Lanius.Compiler.Lexer.QuotedMutation
import Lanius.Compiler.Lexer.QuotedReturn
import Lanius.Compiler.Lexer.QuotedTransport

namespace Lanius.Compiler.Lexer

open Lanius Lanius.Core Lanius.Semantics
open Lanius.Compiler.Lexer.Artifact

private theorem conditionRuns {fuel : Nat} (run : ThresholdPure fuel program state expression
      (.boolean actual) after)
    (eq : actual = expected) :
    RunsExpr program state expression (.boolean expected) after := by
  exact ⟨fuel, (by intro fuel' bound; simpa [eq] using run.run fuel' bound), run.frame.locals⟩

private def byteState (current : State) (source : List Byte) (cursor : Nat) (inBounds : cursor < source.length) : State :=
  current.bindLocal 6 (.signed .i32 (Int.ofNat (source.get ⟨cursor, inBounds⟩).val))

private theorem byteInvariant (invariant : QuotedInvariant caller current cell source delimiter cursor escaping
      cursorCellId escapingCellId) (inBounds : cursor < source.length) :
    QuotedInvariant caller (byteState current source cursor inBounds) cell source delimiter cursor
      escaping cursorCellId escapingCellId := by
  simpa [byteState] using invariant.afterTemporaryBind
    (.signed .i32 (Int.ofNat (source.get ⟨cursor, inBounds⟩).val))

private theorem plainConditions
    (invariant : QuotedInvariant caller current cell source delimiter cursor escaping
      cursorCellId escapingCellId) (inBounds : cursor < source.length)
    (newlineResult delimiterResult backslashResult : Bool)
    (newlineEq : (Int.ofNat (source.get ⟨cursor, inBounds⟩).val == Int.ofNat 10) = newlineResult)
    (delimiterEq : (Int.ofNat (source.get ⟨cursor, inBounds⟩).val == delimiter) = delimiterResult)
    (backslashEq : (Int.ofNat (source.get ⟨cursor, inBounds⟩).val == Int.ofNat 92) = backslashResult) :
    RunsExpr Artifact.lexerProgram (byteState current source cursor inBounds)
        (.binary .equal (.local 6) (.value (.signed .i32 10))) (.boolean newlineResult)
        (byteState current source cursor inBounds) ∧
    RunsExpr Artifact.lexerProgram (byteState current source cursor inBounds)
        (.binary .equal (.local 6) (.local 3)) (.boolean delimiterResult)
        (byteState current source cursor inBounds) ∧
    RunsExpr Artifact.lexerProgram (byteState current source cursor inBounds)
        (.binary .equal (.local 6) (.value (.signed .i32 92))) (.boolean backslashResult)
        (byteState current source cursor inBounds) := by
  refine ⟨?_, ?_, ?_⟩
  · simpa [byteState] using conditionRuns (quotedByte_newline Artifact.lexerProgram invariant inBounds) newlineEq
  · simpa [byteState] using conditionRuns (quotedByte_delimiter Artifact.lexerProgram invariant inBounds) delimiterEq
  · simpa [byteState] using conditionRuns (quotedByte_backslash Artifact.lexerProgram invariant inBounds) backslashEq

private theorem advanceTail {after state : State}
    (run : RunsStmt Artifact.lexerProgram state quotedLoopAdvance .next after) :
    GuardedChain.Run Artifact.lexerProgram state (.tail (.sequence quotedLoopAdvance .skip)) .next after :=
  .tail (RunsStmt.sequenceNext run (RunsStmt.skip _ after))

theorem quotedLoopPlain_newline
    (invariant : QuotedInvariant caller current cell source delimiter cursor escaping
      cursorCellId escapingCellId) (inBounds : cursor < source.length)
    (isNewline : Int.ofNat (source.get ⟨cursor, inBounds⟩).val = 10) :
    ∃ after, RunsStmt Artifact.lexerProgram (byteState current source cursor inBounds)
      Artifact.quotedLoopPlain (.returned (some (failedScanValue cursor))) after ∧
      CallerFrame caller after := by
  let temp := byteState current source cursor inBounds
  have tempInvariant := byteInvariant invariant inBounds
  obtain ⟨condition', _, _⟩ := plainConditions invariant inBounds true
    (Int.ofNat (source.get ⟨cursor, inBounds⟩).val == delimiter) (Int.ofNat (source.get ⟨cursor, inBounds⟩).val == Int.ofNat 92)
    (by simpa using isNewline) rfl rfl
  obtain ⟨after, body, frame⟩ := quotedLoopNewlineReturn_runs tempInvariant
  have run : GuardedChain.Run Artifact.lexerProgram temp quotedLoopPlainChain
      (.returned (some (failedScanValue cursor))) after :=
    .guardTrueReturn condition' body (by simp)
  exact ⟨after, quotedLoopPlainChain_stable run, frame⟩

theorem quotedLoopPlain_delimiter
    (invariant : QuotedInvariant caller current cell source delimiter cursor escaping
      cursorCellId escapingCellId) (inBounds : cursor < source.length)
    (notNewline : Int.ofNat (source.get ⟨cursor, inBounds⟩).val ≠ 10)
    (isDelimiter : Int.ofNat (source.get ⟨cursor, inBounds⟩).val = delimiter) :
    ∃ after, RunsStmt Artifact.lexerProgram (byteState current source cursor inBounds)
      Artifact.quotedLoopPlain (.returned (some (successfulScanValue (cursor + 1)))) after ∧
      CallerFrame caller after := by
  let temp := byteState current source cursor inBounds
  have tempInvariant := byteInvariant invariant inBounds
  obtain ⟨first', second', _⟩ := plainConditions invariant inBounds false true
    (Int.ofNat (source.get ⟨cursor, inBounds⟩).val == Int.ofNat 92)
    (by simpa using notNewline) (by simpa using isDelimiter) rfl
  have bound : cursor + 1 < 2 ^ 31 :=
    Nat.lt_of_le_of_lt (Nat.succ_le_of_lt inBounds) invariant.sourceLengthI32
  obtain ⟨after, body, frame⟩ := quotedLoopDelimiterReturn_runs tempInvariant bound
  have inner : GuardedChain.Run Artifact.lexerProgram temp
      (.guard (.binary .equal (.local 6) (.local 3)) quotedLoopDelimiterReturn
        (.guard (.binary .equal (.local 6) (.value (.signed .i32 92)))
          quotedLoopBeginEscape (.tail (.sequence quotedLoopAdvance .skip))))
      (.returned (some (successfulScanValue (cursor + 1)))) after :=
    .guardTrueReturn second' body (by simp)
  have run : GuardedChain.Run Artifact.lexerProgram temp quotedLoopPlainChain
      (.returned (some (successfulScanValue (cursor + 1)))) after :=
    .guardFalse first' inner
  exact ⟨after, quotedLoopPlainChain_stable run, frame⟩

theorem quotedLoopPlain_backslash
    (invariant : QuotedInvariant caller current cell source delimiter cursor escaping
      cursorCellId escapingCellId) (inBounds : cursor < source.length)
    (notNewline : Int.ofNat (source.get ⟨cursor, inBounds⟩).val ≠ 10)
    (notDelimiter : Int.ofNat (source.get ⟨cursor, inBounds⟩).val ≠ delimiter)
    (isBackslash : Int.ofNat (source.get ⟨cursor, inBounds⟩).val = 92) :
    ∃ after, RunsStmt Artifact.lexerProgram (byteState current source cursor inBounds)
      Artifact.quotedLoopPlain .next after ∧
      QuotedInvariant caller after cell source delimiter (cursor + 1) true
        cursorCellId escapingCellId := by
  let temp := byteState current source cursor inBounds
  have tempInvariant := byteInvariant invariant inBounds
  obtain ⟨first', second', third'⟩ := plainConditions invariant inBounds false false true
    (by simpa using notNewline) (by simpa using notDelimiter) (by simpa using isBackslash)
  obtain ⟨setAfter, setAssigned⟩ := assignLocal_exists temp 5
    (.boolean escaping) (.boolean true) escapingCellId tempInvariant.escapingCell tempInvariant.escapingLocal
  obtain ⟨setRun, setInvariant⟩ := quotedEscapingSet_runs Artifact.lexerProgram tempInvariant
    true setAfter setAssigned
  have setBody : RunsStmt Artifact.lexerProgram temp quotedLoopBeginEscape .next setAfter := by
    change RunsStmt Artifact.lexerProgram temp (.sequence (.expression (.assign .set (.local 5) (.value (.boolean true)))) .skip) .next setAfter
    exact RunsStmt.sequenceNext setRun (RunsStmt.skip _ setAfter)
  obtain ⟨after, advanceAssigned⟩ := assignLocal_exists setAfter 4
    (.signed .i32 (Int.ofNat cursor)) (.signed .i32 (Int.ofNat (cursor + 1)))
    cursorCellId setInvariant.cursorCell setInvariant.cursorLocal
  obtain ⟨advanceRun, finalInvariant⟩ := quotedCursorAdvance_runs Artifact.lexerProgram
    setInvariant (.signed .i32 (Int.ofNat (cursor + 1))) after advanceAssigned rfl
    (Nat.succ_le_of_lt inBounds)
  have tail := advanceTail advanceRun
  have thirdRun := GuardedChain.Run.guardTrueNext third' setBody tail
  have secondRun := GuardedChain.Run.guardFalse (whenTrue := quotedLoopDelimiterReturn) second' thirdRun
  have run : GuardedChain.Run Artifact.lexerProgram temp quotedLoopPlainChain .next after :=
    .guardFalse first' secondRun
  exact ⟨after, quotedLoopPlainChain_stable run, finalInvariant⟩

theorem quotedLoopPlain_ordinary
    (invariant : QuotedInvariant caller current cell source delimiter cursor escaping
      cursorCellId escapingCellId) (inBounds : cursor < source.length)
    (notNewline : Int.ofNat (source.get ⟨cursor, inBounds⟩).val ≠ 10)
    (notDelimiter : Int.ofNat (source.get ⟨cursor, inBounds⟩).val ≠ delimiter)
    (notBackslash : Int.ofNat (source.get ⟨cursor, inBounds⟩).val ≠ 92)
    (notEscaping : escaping = false) :
    ∃ after, RunsStmt Artifact.lexerProgram (byteState current source cursor inBounds)
      Artifact.quotedLoopPlain .next after ∧
      QuotedInvariant caller after cell source delimiter (cursor + 1) false
        cursorCellId escapingCellId := by
  let temp := byteState current source cursor inBounds
  have tempInvariant := byteInvariant invariant inBounds
  obtain ⟨first', second', third'⟩ := plainConditions invariant inBounds false false false
    (by simpa using notNewline) (by simpa using notDelimiter) (by simpa using notBackslash)
  obtain ⟨after, advanceAssigned⟩ := assignLocal_exists temp 4
    (.signed .i32 (Int.ofNat cursor)) (.signed .i32 (Int.ofNat (cursor + 1)))
    cursorCellId tempInvariant.cursorCell tempInvariant.cursorLocal
  obtain ⟨advanceRun, finalInvariant⟩ := quotedCursorAdvance_runs Artifact.lexerProgram
    tempInvariant (.signed .i32 (Int.ofNat (cursor + 1))) after advanceAssigned rfl
    (Nat.succ_le_of_lt inBounds)
  have tail := advanceTail advanceRun
  have thirdRun := GuardedChain.Run.guardFalse (whenTrue := quotedLoopBeginEscape) third' tail
  have secondRun := GuardedChain.Run.guardFalse (whenTrue := quotedLoopDelimiterReturn) second' thirdRun
  have run : GuardedChain.Run Artifact.lexerProgram temp quotedLoopPlainChain .next after :=
    .guardFalse first' secondRun
  exact ⟨after, quotedLoopPlainChain_stable run, by simpa [notEscaping] using finalInvariant⟩

end Lanius.Compiler.Lexer
