import Lanius.Compiler.Lexer.QuotedPlain

namespace Lanius.Compiler.Lexer

open Lanius Lanius.Core Lanius.Semantics Lanius.Compiler.Lexer.Artifact

private theorem conditionRuns {fuel : Nat} (run : ThresholdPure fuel program state expression (.boolean actual) after)
    (eq : actual = expected) : RunsExpr program state expression (.boolean expected) after :=
  ⟨fuel, fun enough bound => by simpa [eq] using run.run enough bound, run.frame.locals⟩

private def byteState (current : State) (source : List Byte) (cursor : Nat) (inBounds : cursor < source.length) : State :=
  current.bindLocal 6 (.signed .i32 (Int.ofNat (source.get ⟨cursor, inBounds⟩).val))

private theorem byteInvariant (invariant : QuotedInvariant caller current cell source delimiter cursor escaping
      cursorCellId escapingCellId) (inBounds : cursor < source.length) :
    QuotedInvariant caller (byteState current source cursor inBounds) cell source delimiter cursor
      escaping cursorCellId escapingCellId := by simpa [byteState] using
    (invariant.afterTemporaryBind (.signed .i32 (Int.ofNat (source.get ⟨cursor, inBounds⟩).val)))

private theorem escapingCondition (invariant : QuotedInvariant caller current cell source delimiter cursor escaping
      cursorCellId escapingCellId) (inBounds : cursor < source.length) (expected : Bool) (eq : escaping = expected) :
    RunsExpr Artifact.lexerProgram (byteState current source cursor inBounds)
      (.local 5) (.boolean expected) (byteState current source cursor inBounds) := by simpa [byteState] using conditionRuns (quotedByte_escaping Artifact.lexerProgram invariant inBounds) eq

private theorem innerFalse
    (condition : RunsExpr program state (.local 5) (.boolean false) state)
    (plain : RunsStmt program state Artifact.quotedLoopPlain completion after) :
    RunsStmt program state Artifact.quotedLoopInner completion after := by
  have branch := RunsStmt.ifThenElseFalse (thenBranch := Artifact.quotedLoopEscaped)
    condition plain
  change RunsStmt program state
    (.sequence (.ifThenElse (.local 5) Artifact.quotedLoopEscaped Artifact.quotedLoopPlain) .skip)
    completion after
  by_cases h : completion = .next
  · subst completion; exact RunsStmt.sequenceNext branch (RunsStmt.skip program after)
  · exact RunsStmt.sequenceCompleted branch h .skip

theorem quotedLoopInner_escaped
    (invariant : QuotedInvariant caller current cell source delimiter cursor escaping
      cursorCellId escapingCellId) (inBounds : cursor < source.length)
    (isEscaping : escaping = true) :
    ∃ after, RunsStmt Artifact.lexerProgram (byteState current source cursor inBounds)
      Artifact.quotedLoopInner .next after ∧
      QuotedInvariant caller after cell source delimiter (cursor + 1) false
        cursorCellId escapingCellId := by
  have tempInvariant := byteInvariant invariant inBounds
  have condition := escapingCondition invariant inBounds true isEscaping
  obtain ⟨setAfter, setAssigned⟩ := assignLocal_exists
    (byteState current source cursor inBounds) 5 (.boolean escaping) (.boolean false)
    escapingCellId tempInvariant.escapingCell tempInvariant.escapingLocal
  obtain ⟨_, setInvariant⟩ := quotedEscapingSet_runs Artifact.lexerProgram tempInvariant
    false setAfter setAssigned
  obtain ⟨after, advanceAssigned⟩ := assignLocal_exists setAfter 4
    (.signed .i32 (Int.ofNat cursor)) (.signed .i32 (Int.ofNat (cursor + 1)))
    cursorCellId setInvariant.cursorCell setInvariant.cursorLocal
  obtain ⟨escaped, finalInvariant⟩ := quotedLoopEscaped_runs Artifact.lexerProgram
    tempInvariant setAfter after (.signed .i32 (Int.ofNat (cursor + 1)))
    setAssigned advanceAssigned rfl (Nat.succ_le_of_lt inBounds)
  have branch := RunsStmt.ifThenElseTrue (elseBranch := Artifact.quotedLoopPlain) condition escaped
  refine ⟨after, ?_, finalInvariant⟩
  change RunsStmt Artifact.lexerProgram (byteState current source cursor inBounds)
    (.sequence (.ifThenElse (.local 5) Artifact.quotedLoopEscaped Artifact.quotedLoopPlain) .skip)
    .next after
  exact RunsStmt.sequenceNext branch (RunsStmt.skip _ after)

theorem quotedLoopInner_newline
    (invariant : QuotedInvariant caller current cell source delimiter cursor escaping
      cursorCellId escapingCellId) (inBounds : cursor < source.length)
    (notEscaping : escaping = false)
    (isNewline : Int.ofNat (source.get ⟨cursor, inBounds⟩).val = 10) :
    ∃ after, RunsStmt Artifact.lexerProgram (byteState current source cursor inBounds)
      Artifact.quotedLoopInner (.returned (some (failedScanValue cursor))) after ∧
      CallerFrame caller after := by
  have condition := escapingCondition invariant inBounds false notEscaping
  obtain ⟨after, plain, frame⟩ := quotedLoopPlain_newline invariant inBounds isNewline
  exact ⟨after, innerFalse condition plain, frame⟩

theorem quotedLoopInner_delimiter
    (invariant : QuotedInvariant caller current cell source delimiter cursor escaping
      cursorCellId escapingCellId) (inBounds : cursor < source.length)
    (notEscaping : escaping = false)
    (notNewline : Int.ofNat (source.get ⟨cursor, inBounds⟩).val ≠ 10)
    (isDelimiter : Int.ofNat (source.get ⟨cursor, inBounds⟩).val = delimiter) :
    ∃ after, RunsStmt Artifact.lexerProgram (byteState current source cursor inBounds)
      Artifact.quotedLoopInner (.returned (some (successfulScanValue (cursor + 1)))) after ∧
      CallerFrame caller after := by
  have condition := escapingCondition invariant inBounds false notEscaping
  obtain ⟨after, plain, frame⟩ := quotedLoopPlain_delimiter invariant inBounds notNewline isDelimiter
  exact ⟨after, innerFalse condition plain, frame⟩

theorem quotedLoopInner_backslash
    (invariant : QuotedInvariant caller current cell source delimiter cursor escaping
      cursorCellId escapingCellId) (inBounds : cursor < source.length)
    (notEscaping : escaping = false)
    (notNewline : Int.ofNat (source.get ⟨cursor, inBounds⟩).val ≠ 10)
    (notDelimiter : Int.ofNat (source.get ⟨cursor, inBounds⟩).val ≠ delimiter)
    (isBackslash : Int.ofNat (source.get ⟨cursor, inBounds⟩).val = 92) :
    ∃ after, RunsStmt Artifact.lexerProgram (byteState current source cursor inBounds)
      Artifact.quotedLoopInner .next after ∧
      QuotedInvariant caller after cell source delimiter (cursor + 1) true
        cursorCellId escapingCellId := by
  have condition := escapingCondition invariant inBounds false notEscaping
  obtain ⟨after, plain, finalInvariant⟩ := quotedLoopPlain_backslash invariant inBounds
    notNewline notDelimiter isBackslash
  exact ⟨after, innerFalse condition plain, finalInvariant⟩

theorem quotedLoopInner_ordinary
    (invariant : QuotedInvariant caller current cell source delimiter cursor escaping
      cursorCellId escapingCellId) (inBounds : cursor < source.length)
    (notEscaping : escaping = false)
    (notNewline : Int.ofNat (source.get ⟨cursor, inBounds⟩).val ≠ 10)
    (notDelimiter : Int.ofNat (source.get ⟨cursor, inBounds⟩).val ≠ delimiter)
    (notBackslash : Int.ofNat (source.get ⟨cursor, inBounds⟩).val ≠ 92) :
    ∃ after, RunsStmt Artifact.lexerProgram (byteState current source cursor inBounds)
      Artifact.quotedLoopInner .next after ∧
      QuotedInvariant caller after cell source delimiter (cursor + 1) false
        cursorCellId escapingCellId := by
  have condition := escapingCondition invariant inBounds false notEscaping
  obtain ⟨after, plain, finalInvariant⟩ := quotedLoopPlain_ordinary invariant inBounds
    notNewline notDelimiter notBackslash notEscaping
  exact ⟨after, innerFalse condition plain, finalInvariant⟩

end Lanius.Compiler.Lexer
