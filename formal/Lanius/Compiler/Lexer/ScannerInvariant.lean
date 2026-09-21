import Lanius.Compiler.Lexer.ScannerCall
import Lanius.Semantics.MutableLocal

namespace Lanius.Compiler.Lexer

open Lanius
open Lanius.Core
open Lanius.Semantics

/-! State facts shared by the executable prefix-scanner proofs.  The cursor
    cell is named explicitly because the loop mutates that fresh cell. -/
structure ScannerInvariant
    (caller current : State) (cell : CellId) (source : List Byte)
    (cursor : Nat) (cursorCellId : CellId) : Prop where
  frame : CallerFrame caller current
  sourceSlice : SourceSlice current 0 cell (sourceI32Values source)
  lengthLocal : current.local? 1 =
    some (.signed .i32 (Int.ofNat source.length))
  cursorLocal : current.local? 3 =
    some (.signed .i32 (Int.ofNat cursor))
  cursorCell : current.cellId? 3 = some cursorCellId
  sourceCellDistinct : current.cellId? 0 ≠ some cursorCellId
  lengthCellDistinct : current.cellId? 1 ≠ some cursorCellId
  cursorCellFresh : caller.nextCell ≤ cursorCellId
  cursorInSource : cursor ≤ source.length
  sourceLengthI32 : source.length < 2 ^ 31

theorem ScannerInvariant.afterPureFrame
    {caller current after : State} {cell : CellId} {source : List Byte}
    {cursor : Nat} {cursorCellId : CellId}
    (invariant : ScannerInvariant caller current cell source cursor cursorCellId)
    (pure : PureFrame current after) :
    ScannerInvariant caller after cell source cursor cursorCellId := by
  have cellIdPreserved (id : VarId) : after.cellId? id = current.cellId? id := by simp [State.cellId?, pure.locals]
  refine {
    frame := invariant.frame.transPure pure
    sourceSlice := invariant.sourceSlice.afterPureFrame pure
    lengthLocal := pure.cells.localFound pure.locals 1 _ invariant.lengthLocal
    cursorLocal := pure.cells.localFound pure.locals 3 _ invariant.cursorLocal
    cursorCell := by simpa [cellIdPreserved] using invariant.cursorCell
    sourceCellDistinct := by simpa [cellIdPreserved] using invariant.sourceCellDistinct
    lengthCellDistinct := by simpa [cellIdPreserved] using invariant.lengthCellDistinct
    cursorCellFresh := invariant.cursorCellFresh
    cursorInSource := invariant.cursorInSource
    sourceLengthI32 := invariant.sourceLengthI32
  }

def scannerCalleeWithCursorWidth
    (caller : State) (cell : CellId) (source : List Byte) (start width : Nat) : State :=
  (scannerCallee caller cell source start).bindLocal 3
    (.signed .i32 (Int.ofNat (start + width)))

theorem scannerCalleeWithCursorWidth_invariant
    (caller : State) (cell : CellId) (source : List Byte) (start width : Nat)
    (formed : caller.CellsWellFormed)
    (backing : SourceByteBacking caller cell source)
    (startWithinSource : start + width ≤ source.length)
    (sourceLengthI32 : source.length < 2 ^ 31) :
    ScannerInvariant caller (scannerCalleeWithCursorWidth caller cell source start width)
      cell source (start + width) (scannerCallee caller cell source start).nextCell := by
  let callee := scannerCallee caller cell source start
  let current := callee.bindLocal 3
    (.signed .i32 (Int.ofNat (start + width)))
  have calleeFrame : CallerFrame caller callee := scannerCallee_frame caller cell source start formed
  have calleeFormed : callee.CellsWellFormed := calleeFrame.currentFormed
  have cursorFrame : CallerFrame callee current := (CallerFrame.refl calleeFormed).bindLocal 3 _
  have preserveLocal (id : VarId) (value : Value) (different : 3 ≠ id)
      (found : callee.local? id = some value) : current.local? id = some value :=
    State.bindLocal_local?_of_ne callee calleeFormed id 3 value _ different found
  have sourceAtCurrent : SourceSlice current 0 cell (sourceI32Values source) :=
    (scannerCallee_sourceSlice caller cell source start formed backing).afterCallerFrame cursorFrame
      (preserveLocal 0 _ (by decide)
        (scannerCallee_sourceSlice caller cell source start formed backing).localFound)
  exact {
    frame := by simpa [current, callee, scannerCalleeWithCursorWidth]
      using calleeFrame.trans cursorFrame
    sourceSlice := by simpa [current, callee, scannerCalleeWithCursorWidth] using sourceAtCurrent
    lengthLocal := by simpa [current, callee, scannerCalleeWithCursorWidth] using
      (preserveLocal 1 _ (by decide) ((scannerCallee_localFacts caller cell source start formed).2))
    cursorLocal := State.bindLocal_local? callee calleeFormed 3 _,
    cursorCell := by simpa [current, scannerCalleeWithCursorWidth] using
      State.bindLocal_cellId callee 3 (.signed .i32 (Int.ofNat (start + width)))
    sourceCellDistinct := by
      simp [scannerCalleeWithCursorWidth, current, callee, scannerCallee, scannerBindings, State.bindLocal, State.bindCell,
        State.bindLocals, State.cellId?, Nat.add_comm, Nat.add_left_comm]
    lengthCellDistinct := by
      simp [scannerCalleeWithCursorWidth, current, callee, scannerCallee, scannerBindings, State.bindLocal, State.bindCell,
        State.bindLocals, State.cellId?, Nat.add_comm, Nat.add_left_comm]
    cursorCellFresh := calleeFrame.cells.choose_spec.2.1
    cursorInSource := startWithinSource
    sourceLengthI32 := sourceLengthI32
  }

def scannerCalleeWithCursor
    (caller : State) (cell : CellId) (source : List Byte) (start : Nat) : State :=
  scannerCalleeWithCursorWidth caller cell source start 1

theorem scannerCalleeWithCursor_invariant
    (caller : State) (cell : CellId) (source : List Byte) (start : Nat)
    (formed : caller.CellsWellFormed)
    (backing : SourceByteBacking caller cell source)
    (startInSource : start < source.length)
    (sourceLengthI32 : source.length < 2 ^ 31) :
    ScannerInvariant caller (scannerCalleeWithCursor caller cell source start)
      cell source (start + 1) (scannerCallee caller cell source start).nextCell := by
  simpa [scannerCalleeWithCursor] using
    scannerCalleeWithCursorWidth_invariant caller cell source start 1 formed backing
      (by omega) sourceLengthI32

end Lanius.Compiler.Lexer
