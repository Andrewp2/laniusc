import Lanius.Compiler.Lexer.QuotedInner
import Lanius.Compiler.Lexer.QuotedTransport
import Lanius.Compiler.Lexer.QuotedByte

namespace Lanius.Compiler.Lexer

open Lanius Lanius.Core Lanius.Semantics Lanius.Compiler.Lexer.Artifact

private def byteState (current : State) (source : List Byte) (cursor : Nat)
    (inBounds : cursor < source.length) : State :=
  current.bindLocal 6 (.signed .i32 (Int.ofNat (source.get ⟨cursor, inBounds⟩).val))

private theorem initializerRun
    (invariant : QuotedInvariant caller current cell source delimiter cursor escaping cursorCellId escapingCellId)
    (inBounds : cursor < source.length) :
    RunsExpr Artifact.lexerProgram current (.index (.local 0) (.local 4))
      (.signed .i32 (Int.ofNat (source.get ⟨cursor, inBounds⟩).val)) current := by
  obtain ⟨run, frame⟩ := quotedByte_initializer Artifact.lexerProgram invariant inBounds
  exact ⟨2, run, frame.locals⟩

private theorem restoreFrame {caller current completed : State} (frame : CallerFrame caller completed) :
    CallerFrame caller (restoreLocals current completed) :=
  ⟨frame.callerFormed, frame.cells.restoreLocals, (by simpa [restoreLocals] using frame.heap),
    (by simpa [restoreLocals] using frame.world), (by simpa [restoreLocals] using frame.views)⟩

private theorem restoreNext
    (old : QuotedInvariant caller current cell source delimiter cursor escaping cursorCellId escapingCellId)
    (new : QuotedInvariant caller completed cell source delimiter nextCursor nextEscaping cursorCellId escapingCellId)
    (body : RunsStmt Artifact.lexerProgram (byteState current source cursor inBounds)
      Artifact.quotedLoopInner .next completed) :
    QuotedInvariant caller (restoreLocals current completed) cell source delimiter nextCursor nextEscaping
      cursorCellId escapingCellId := by
  obtain ⟨_, _, locals⟩ := body
  have cellEq (id : VarId) (different : id ≠ 6) : completed.cellId? id = current.cellId? id := by
    calc
      completed.cellId? id = (byteState current source cursor inBounds).cellId? id := by
        simp [State.cellId?, locals]
      _ = current.cellId? id := State.bindLocal_cellId_of_ne current id 6 (Ne.symm different) _
  exact old.afterTemporaryAssignmentRestore new (cellEq 0 (by decide)) (cellEq 1 (by decide))
    (cellEq 3 (by decide))

private theorem wrapBody
    (invariant : QuotedInvariant caller current cell source delimiter cursor escaping cursorCellId escapingCellId)
    (inBounds : cursor < source.length) {completion : Completion} {after : State}
    (body : RunsStmt Artifact.lexerProgram (byteState current source cursor inBounds)
      Artifact.quotedLoopInner completion after) :
    RunsStmt Artifact.lexerProgram current Artifact.scanQuotedLoopBody completion
      (restoreLocals current after) := by
  change RunsStmt Artifact.lexerProgram current
    (.letLocal 6 (.scalar (.signed .i32)) (.index (.local 0) (.local 4)) Artifact.quotedLoopInner)
      completion (restoreLocals current after)
  exact RunsStmt.letLocal (initializerRun invariant inBounds) body

theorem scanQuotedLoopBody_escaped
    (invariant : QuotedInvariant caller current cell source delimiter cursor escaping cursorCellId escapingCellId)
    (inBounds : cursor < source.length) (isEscaping : escaping = true) :
    ∃ after, RunsStmt Artifact.lexerProgram current Artifact.scanQuotedLoopBody .next after ∧
      QuotedInvariant caller after cell source delimiter (cursor + 1) false cursorCellId escapingCellId := by
  obtain ⟨bodyAfter, body, nextInvariant⟩ := quotedLoopInner_escaped invariant inBounds isEscaping
  refine ⟨restoreLocals current bodyAfter, wrapBody invariant inBounds body, ?_⟩
  exact restoreNext invariant nextInvariant body

theorem scanQuotedLoopBody_newline
    (invariant : QuotedInvariant caller current cell source delimiter cursor escaping cursorCellId escapingCellId)
    (inBounds : cursor < source.length) (notEscaping : escaping = false)
    (isNewline : Int.ofNat (source.get ⟨cursor, inBounds⟩).val = 10) :
    ∃ after, RunsStmt Artifact.lexerProgram current Artifact.scanQuotedLoopBody
      (.returned (some (failedScanValue cursor))) after ∧ CallerFrame caller after := by
  obtain ⟨bodyAfter, body, frame⟩ := quotedLoopInner_newline invariant inBounds notEscaping isNewline
  refine ⟨restoreLocals current bodyAfter, wrapBody invariant inBounds body, ?_⟩
  exact restoreFrame frame

theorem scanQuotedLoopBody_delimiter
    (invariant : QuotedInvariant caller current cell source delimiter cursor escaping cursorCellId escapingCellId)
    (inBounds : cursor < source.length) (notEscaping : escaping = false)
    (notNewline : Int.ofNat (source.get ⟨cursor, inBounds⟩).val ≠ 10)
    (isDelimiter : Int.ofNat (source.get ⟨cursor, inBounds⟩).val = delimiter) :
    ∃ after, RunsStmt Artifact.lexerProgram current Artifact.scanQuotedLoopBody
      (.returned (some (successfulScanValue (cursor + 1)))) after ∧ CallerFrame caller after := by
  obtain ⟨bodyAfter, body, frame⟩ := quotedLoopInner_delimiter invariant inBounds notEscaping notNewline isDelimiter
  refine ⟨restoreLocals current bodyAfter, wrapBody invariant inBounds body, ?_⟩
  exact restoreFrame frame

theorem scanQuotedLoopBody_backslash
    (invariant : QuotedInvariant caller current cell source delimiter cursor escaping cursorCellId escapingCellId)
    (inBounds : cursor < source.length) (notEscaping : escaping = false)
    (notNewline : Int.ofNat (source.get ⟨cursor, inBounds⟩).val ≠ 10)
    (notDelimiter : Int.ofNat (source.get ⟨cursor, inBounds⟩).val ≠ delimiter)
    (isBackslash : Int.ofNat (source.get ⟨cursor, inBounds⟩).val = 92) :
    ∃ after, RunsStmt Artifact.lexerProgram current Artifact.scanQuotedLoopBody .next after ∧
      QuotedInvariant caller after cell source delimiter (cursor + 1) true cursorCellId escapingCellId := by
  obtain ⟨bodyAfter, body, nextInvariant⟩ := quotedLoopInner_backslash invariant inBounds notEscaping
    notNewline notDelimiter isBackslash
  refine ⟨restoreLocals current bodyAfter, wrapBody invariant inBounds body, ?_⟩
  exact restoreNext invariant nextInvariant body

theorem scanQuotedLoopBody_ordinary
    (invariant : QuotedInvariant caller current cell source delimiter cursor escaping cursorCellId escapingCellId)
    (inBounds : cursor < source.length) (notEscaping : escaping = false)
    (notNewline : Int.ofNat (source.get ⟨cursor, inBounds⟩).val ≠ 10)
    (notDelimiter : Int.ofNat (source.get ⟨cursor, inBounds⟩).val ≠ delimiter)
    (notBackslash : Int.ofNat (source.get ⟨cursor, inBounds⟩).val ≠ 92) :
    ∃ after, RunsStmt Artifact.lexerProgram current Artifact.scanQuotedLoopBody .next after ∧
      QuotedInvariant caller after cell source delimiter (cursor + 1) false cursorCellId escapingCellId := by
  obtain ⟨bodyAfter, body, nextInvariant⟩ := quotedLoopInner_ordinary invariant inBounds notEscaping
    notNewline notDelimiter notBackslash
  refine ⟨restoreLocals current bodyAfter, wrapBody invariant inBounds body, ?_⟩
  exact restoreNext invariant nextInvariant body

end Lanius.Compiler.Lexer
