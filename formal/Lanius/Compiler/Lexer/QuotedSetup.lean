import Lanius.Compiler.Lexer.QuotedCall
import Lanius.Compiler.Lexer.QuotedInvariant

namespace Lanius.Compiler.Lexer

open Lanius Lanius.Core Lanius.Semantics

def quotedLoopEntry
    (caller : State) (cell : CellId) (source : List Byte) (start : Nat) (delimiter : Int) : State :=
  (quotedCallee caller cell source start delimiter).bindLocal 4
    (.signed .i32 (Int.ofNat (start + 1))) |>.bindLocal 5 (.boolean false)

theorem quotedLoopEntry_invariant
    (caller : State) (cell : CellId) (source : List Byte) (start : Nat) (delimiter : Int)
    (formed : caller.CellsWellFormed) (backing : SourceByteBacking caller cell source)
    (startInSource : start < source.length) (sourceLengthI32 : source.length < 2 ^ 31) :
    QuotedInvariant caller (quotedLoopEntry caller cell source start delimiter)
      cell source delimiter (start + 1) false
      (quotedCallee caller cell source start delimiter).nextCell
      ((quotedCallee caller cell source start delimiter).nextCell + 1) := by
  let callee := quotedCallee caller cell source start delimiter
  let cursorState := callee.bindLocal 4 (.signed .i32 (Int.ofNat (start + 1)))
  let current := cursorState.bindLocal 5 (.boolean false)
  have calleeNextCell : callee.nextCell = caller.nextCell + 4 := by
    simp [callee, quotedCallee, scannerCallee, scannerBindings,
      State.bindLocals_nextCell, State.bindLocal, State.bindCell]
  have cursorNextCell : cursorState.nextCell = callee.nextCell + 1 := by
    simp [cursorState, State.bindLocal, State.bindCell]
  have currentFrame : CallerFrame caller current := by
    simpa [current, cursorState] using
      (quotedCallee_frame caller cell source start delimiter formed).bindLocal 4 _ |>.bindLocal 5 _
  have calleeFormed : callee.CellsWellFormed :=
    (quotedCallee_frame caller cell source start delimiter formed).currentFormed
  have preserve (id : VarId) (value : Value) (different4 : 4 ≠ id)
      (different5 : 5 ≠ id) (found : callee.local? id = some value) :
      current.local? id = some value := by
    simpa [current, cursorState] using
      State.bindLocal_local?_of_ne cursorState (calleeFormed.bindLocal 4 _) id 5 value _ different5
        (State.bindLocal_local?_of_ne callee calleeFormed id 4 value _ different4 found)
  have calleeLocals := quotedCallee_localFacts caller cell source start delimiter formed
  have sourceLocal : current.local? 0 =
      some (i32SliceValue cell (sourceI32Values source)) := by
    simpa [sourceSliceValue] using preserve 0 _ (by decide) (by decide) calleeLocals.1
  have sourceSlice : SourceSlice current 0 cell (sourceI32Values source) :=
    SourceSlice.ofBacking 0 cell (sourceI32Values source) sourceLocal
      (backing.afterCallerFrame currentFrame)
  have lengthLocal : current.local? 1 =
      some (.signed .i32 (Int.ofNat source.length)) :=
    preserve 1 _ (by decide) (by decide) calleeLocals.2.1
  have delimiterLocal : current.local? 3 = some (.signed .i32 delimiter) :=
    preserve 3 _ (by decide) (by decide) calleeLocals.2.2.2
  have cursorLocal : current.local? 4 =
      some (.signed .i32 (Int.ofNat (start + 1))) :=
    by simpa [current] using
      State.bindLocal_local?_of_ne cursorState (calleeFormed.bindLocal 4 _) 4 5 _ _ (by decide)
        (State.bindLocal_local? callee calleeFormed 4 _)
  have escapingLocal : current.local? 5 = some (.boolean false) :=
    by simpa [current] using State.bindLocal_local? cursorState (calleeFormed.bindLocal 4 _) 5 _
  have cursorCell : current.cellId? 4 = some callee.nextCell := by
    simpa [current] using
      (State.bindLocal_cellId_of_ne cursorState 4 5 (by decide) _).trans
        (State.bindLocal_cellId callee 4 _)
  have escapingCell : current.cellId? 5 = some cursorState.nextCell := by
    simpa [current] using State.bindLocal_cellId cursorState 5 _
  have distinctCells :
      current.cellId? 0 ≠ current.cellId? 4 ∧
      current.cellId? 1 ≠ current.cellId? 4 ∧
      current.cellId? 3 ≠ current.cellId? 4 ∧
      current.cellId? 5 ≠ current.cellId? 4 ∧
      current.cellId? 0 ≠ current.cellId? 5 ∧
      current.cellId? 1 ≠ current.cellId? 5 ∧
      current.cellId? 3 ≠ current.cellId? 5 ∧
      current.cellId? 4 ≠ current.cellId? 5 := by
    simp [current, cursorState, callee, quotedCallee, scannerCallee, scannerBindings,
      State.bindLocals, State.bindLocal, State.bindCell, State.cellId?, Nat.add_comm,
      Nat.add_left_comm] <;> omega
  have result : QuotedInvariant caller current cell source delimiter
      (start + 1) false callee.nextCell cursorState.nextCell := {
    frame := currentFrame
    sourceBacking := backing
    sourceSlice := sourceSlice
    lengthLocal := lengthLocal
    delimiterLocal := delimiterLocal
    cursorLocal := cursorLocal
    escapingLocal := escapingLocal
    cursorCell := cursorCell
    escapingCell := escapingCell
    sourceCursorDistinct := distinctCells.1
    lengthCursorDistinct := distinctCells.2.1
    delimiterCursorDistinct := distinctCells.2.2.1
    escapingCursorDistinct := distinctCells.2.2.2.1
    sourceEscapingDistinct := distinctCells.2.2.2.2.1
    lengthEscapingDistinct := distinctCells.2.2.2.2.2.1
    delimiterEscapingDistinct := distinctCells.2.2.2.2.2.2.1
    cursorEscapingDistinct := distinctCells.2.2.2.2.2.2.2
    cursorCellFresh := by
      simpa [calleeNextCell] using Nat.le_add_right caller.nextCell 4
    escapingCellFresh := by
      simpa [cursorNextCell, calleeNextCell, Nat.add_assoc] using Nat.le_add_right caller.nextCell 5
    cursorInSource := Nat.succ_le_of_lt startInSource
    sourceLengthI32 := sourceLengthI32 }
  rw [cursorNextCell] at result
  simpa [current, quotedLoopEntry, callee, cursorState] using result

end Lanius.Compiler.Lexer
