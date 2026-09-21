import Lanius.Compiler.Lexer.QuotedInvariant
import Lanius.Semantics.LocalScope

namespace Lanius.Compiler.Lexer

open Lanius Lanius.Core Lanius.Semantics

theorem QuotedInvariant.afterTemporaryBind
    {caller current : State} {cell : CellId} {source : List Byte} {delimiter : Int}
    {cursor : Nat} {escaping : Bool} {cursorCellId escapingCellId : CellId}
    (old : QuotedInvariant caller current cell source delimiter cursor escaping
      cursorCellId escapingCellId) (byte : Value) :
    QuotedInvariant caller (current.bindLocal 6 byte) cell source delimiter cursor escaping
      cursorCellId escapingCellId := by
  have frame := old.frame.bindLocal 6 byte
  have preserveLocal (id : VarId) (h : 6 ≠ id) (v : Value) (p : current.local? id = some v) :
      (current.bindLocal 6 byte).local? id = some v := by
    exact State.bindLocal_local?_of_ne current old.frame.currentFormed id 6 v byte h p
  have cellIdEq (id : VarId) (different : id ≠ 6) :=
    State.bindLocal_cellId_of_ne current id 6 (Ne.symm different) byte
  refine ⟨frame, old.sourceBacking,
    SourceSlice.ofBacking 0 cell (sourceI32Values source)
      (preserveLocal 0 (by decide) _ old.sourceSlice.localFound)
      (old.sourceBacking.afterCallerFrame frame),
    preserveLocal 1 (by decide) _ old.lengthLocal,
    preserveLocal 3 (by decide) _ old.delimiterLocal,
    preserveLocal 4 (by decide) _ old.cursorLocal,
    preserveLocal 5 (by decide) _ old.escapingLocal,
    ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, old.cursorCellFresh,
    old.escapingCellFresh, old.cursorInSource, old.sourceLengthI32⟩
  all_goals
    simp [cellIdEq, old.cursorCell, old.escapingCell, old.sourceCursorDistinct,
      old.lengthCursorDistinct, old.delimiterCursorDistinct,
      old.sourceEscapingDistinct, old.lengthEscapingDistinct,
      old.delimiterEscapingDistinct] <;>
    first
    | simpa [old.escapingCell] using old.escapingCursorDistinct
    | simpa [old.cursorCell, old.escapingCell] using old.cursorEscapingDistinct

theorem QuotedInvariant.afterTemporaryAssignmentRestore
    {caller current completed : State} {cell : CellId} {source : List Byte}
    {delimiter : Int} {cursor nextCursor : Nat} {escaping nextEscaping : Bool}
    {cursorCellId escapingCellId : CellId}
    (old : QuotedInvariant caller current cell source delimiter cursor escaping
      cursorCellId escapingCellId)
    (new : QuotedInvariant caller completed cell source delimiter nextCursor nextEscaping
      cursorCellId escapingCellId)
    (sourceCellEq : completed.cellId? 0 = current.cellId? 0)
    (lengthCellEq : completed.cellId? 1 = current.cellId? 1)
    (delimiterCellEq : completed.cellId? 3 = current.cellId? 3) :
    QuotedInvariant caller (restoreLocals current completed) cell source delimiter
      nextCursor nextEscaping cursorCellId escapingCellId := by
  rcases old with ⟨oldFrame, oldSourceBacking, oldSourceSlice, oldLengthLocal,
    oldDelimiterLocal, oldCursorLocal, oldEscapingLocal, oldCursorCell, oldEscapingCell,
    oldSourceCursor, oldLengthCursor, oldDelimiterCursor, oldEscapingCursor,
    oldSourceEscaping, oldLengthEscaping, oldDelimiterEscaping, oldCursorEscaping,
    oldCursorFresh, oldEscapingFresh, oldCursorInSource, oldSourceLengthI32⟩
  have frame : CallerFrame caller (restoreLocals current completed) := ⟨
    new.frame.callerFormed, new.frame.cells.restoreLocals,
      by simpa [restoreLocals] using new.frame.heap,
      by simpa [restoreLocals] using new.frame.world,
      by simpa [restoreLocals] using new.frame.views⟩
  have sourceLocal := restoreLocals_local?_of_cellId_eq sourceCellEq new.sourceSlice.localFound
  have lengthLocal := restoreLocals_local?_of_cellId_eq lengthCellEq new.lengthLocal
  have delimiterLocal := restoreLocals_local?_of_cellId_eq delimiterCellEq new.delimiterLocal
  have cursorLocal := restoreLocals_local?_of_cellId_eq (base := current)
    (completed := completed) (by simp only [new.cursorCell, oldCursorCell]) new.cursorLocal
  have escapingLocal := restoreLocals_local?_of_cellId_eq (base := current)
    (completed := completed) (by simp only [new.escapingCell, oldEscapingCell]) new.escapingLocal
  refine ⟨frame, new.sourceBacking,
    SourceSlice.ofBacking 0 cell (sourceI32Values source) sourceLocal
      (new.sourceBacking.afterCallerFrame frame),
    lengthLocal, delimiterLocal, cursorLocal, escapingLocal,
    ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, oldCursorFresh,
    oldEscapingFresh, new.cursorInSource, new.sourceLengthI32⟩
  all_goals simp only [restoreLocals] <;> assumption

end Lanius.Compiler.Lexer
