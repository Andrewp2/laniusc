import Lanius.Compiler.Lexer.ScannerInvariant
import Lanius.Semantics.Assignment

namespace Lanius.Compiler.Lexer

open Lanius Lanius.Core Lanius.Semantics

/-! Facts at the head of the quoted-string loop (Core locals 4 and 5 are the
    mutable cursor and escaping flag).  The backing is kept at the caller so
    assignment transport can recover it after each fresh-cell update. -/
structure QuotedInvariant
    (caller current : State) (cell : CellId) (source : List Byte)
    (delimiter : Int) (cursor : Nat) (escaping : Bool)
    (cursorCellId escapingCellId : CellId) : Prop where
  frame : CallerFrame caller current
  sourceBacking : SourceBacking caller cell (sourceI32Values source)
  sourceSlice : SourceSlice current 0 cell (sourceI32Values source)
  lengthLocal : current.local? 1 =
    some (.signed .i32 (Int.ofNat source.length))
  delimiterLocal : current.local? 3 = some (.signed .i32 delimiter)
  cursorLocal : current.local? 4 =
    some (.signed .i32 (Int.ofNat cursor))
  escapingLocal : current.local? 5 = some (.boolean escaping)
  cursorCell : current.cellId? 4 = some cursorCellId
  escapingCell : current.cellId? 5 = some escapingCellId
  sourceCursorDistinct : current.cellId? 0 ≠ some cursorCellId
  lengthCursorDistinct : current.cellId? 1 ≠ some cursorCellId
  delimiterCursorDistinct : current.cellId? 3 ≠ some cursorCellId
  escapingCursorDistinct : current.cellId? 5 ≠ some cursorCellId
  sourceEscapingDistinct : current.cellId? 0 ≠ some escapingCellId
  lengthEscapingDistinct : current.cellId? 1 ≠ some escapingCellId
  delimiterEscapingDistinct : current.cellId? 3 ≠ some escapingCellId
  cursorEscapingDistinct : current.cellId? 4 ≠ some escapingCellId
  cursorCellFresh : caller.nextCell ≤ cursorCellId
  escapingCellFresh : caller.nextCell ≤ escapingCellId
  cursorInSource : cursor ≤ source.length
  sourceLengthI32 : source.length < 2 ^ 31

theorem QuotedInvariant.afterPureFrame
    {caller current after : State} {cell : CellId} {source : List Byte}
    {delimiter : Int} {cursor : Nat} {escaping : Bool}
  {cursorCellId escapingCellId : CellId}
    (invariant : QuotedInvariant caller current cell source delimiter cursor escaping
      cursorCellId escapingCellId)
    (pure : PureFrame current after) :
  QuotedInvariant caller after cell source delimiter cursor escaping
      cursorCellId escapingCellId := by
  have cellIdPreserved (id : VarId) : after.cellId? id = current.cellId? id := by
    simpa [State.cellId?, pure.locals]
  refine { invariant with
    frame := invariant.frame.transPure pure
    sourceSlice := invariant.sourceSlice.afterPureFrame pure
    lengthLocal := pure.cells.localFound pure.locals 1 _ invariant.lengthLocal
    delimiterLocal := pure.cells.localFound pure.locals 3 _ invariant.delimiterLocal
    cursorLocal := pure.cells.localFound pure.locals 4 _ invariant.cursorLocal
    escapingLocal := pure.cells.localFound pure.locals 5 _ invariant.escapingLocal
    cursorCell := by simpa [cellIdPreserved] using invariant.cursorCell
    escapingCell := by simpa [cellIdPreserved] using invariant.escapingCell
    sourceCursorDistinct := by simpa [cellIdPreserved] using invariant.sourceCursorDistinct
    lengthCursorDistinct := by simpa [cellIdPreserved] using invariant.lengthCursorDistinct
    delimiterCursorDistinct := by simpa [cellIdPreserved] using invariant.delimiterCursorDistinct
    escapingCursorDistinct := by simpa [cellIdPreserved] using invariant.escapingCursorDistinct
    sourceEscapingDistinct := by simpa [cellIdPreserved] using invariant.sourceEscapingDistinct
    lengthEscapingDistinct := by simpa [cellIdPreserved] using invariant.lengthEscapingDistinct
    delimiterEscapingDistinct := by simpa [cellIdPreserved] using invariant.delimiterEscapingDistinct
    cursorEscapingDistinct := by simpa [cellIdPreserved] using invariant.cursorEscapingDistinct
    }

private theorem afterAssignment
    {caller current after : State} {cell : CellId} {source : List Byte}
    {delimiter : Int} {cursor nextCursor : Nat} {escaping nextEscaping : Bool}
    {cursorCellId escapingCellId assignedCell : CellId} {value : Value}
    (invariant : QuotedInvariant caller current cell source delimiter cursor escaping
      cursorCellId escapingCellId)
    (frame : CallerFrame caller after)
    (assigned : current.assignCell assignedCell value = some after)
    (sourceLocal : after.local? 0 =
      some (i32SliceValue cell (sourceI32Values source)))
    (lengthLocal : after.local? 1 =
      some (.signed .i32 (Int.ofNat source.length)))
    (delimiterLocal : after.local? 3 = some (.signed .i32 delimiter))
    (cursorLocal : after.local? 4 =
      some (.signed .i32 (Int.ofNat nextCursor)))
    (escapingLocal : after.local? 5 = some (.boolean nextEscaping))
    (nextInSource : nextCursor ≤ source.length) :
    QuotedInvariant caller after cell source delimiter nextCursor nextEscaping
      cursorCellId escapingCellId := by
  have cellIdPreserved (id : VarId) : after.cellId? id = current.cellId? id := by
    exact (assignCell_preserves_frame id assigned).2
  refine { invariant with
    frame := frame
    sourceSlice := SourceSlice.ofBacking 0 cell (sourceI32Values source) sourceLocal
      (invariant.sourceBacking.afterCallerFrame frame)
    lengthLocal := lengthLocal
    delimiterLocal := delimiterLocal
    cursorLocal := cursorLocal
    escapingLocal := escapingLocal
    cursorCell := by simpa [cellIdPreserved] using invariant.cursorCell
    escapingCell := by simpa [cellIdPreserved] using invariant.escapingCell
    sourceCursorDistinct := by simpa [cellIdPreserved] using invariant.sourceCursorDistinct
    lengthCursorDistinct := by simpa [cellIdPreserved] using invariant.lengthCursorDistinct
    delimiterCursorDistinct := by simpa [cellIdPreserved] using invariant.delimiterCursorDistinct
    escapingCursorDistinct := by simpa [cellIdPreserved] using invariant.escapingCursorDistinct
    sourceEscapingDistinct := by simpa [cellIdPreserved] using invariant.sourceEscapingDistinct
    lengthEscapingDistinct := by simpa [cellIdPreserved] using invariant.lengthEscapingDistinct
    delimiterEscapingDistinct := by simpa [cellIdPreserved] using invariant.delimiterEscapingDistinct
    cursorEscapingDistinct := by simpa [cellIdPreserved] using invariant.cursorEscapingDistinct
    cursorInSource := nextInSource
    }

theorem QuotedInvariant.afterCursorAssignment
    {caller current after : State} {cell : CellId} {source : List Byte}
    {delimiter : Int} {cursor : Nat} {escaping : Bool}
    {cursorCellId escapingCellId : CellId}
    (invariant : QuotedInvariant caller current cell source delimiter cursor escaping
      cursorCellId escapingCellId)
    (nextCursor : Nat) (nextValue : Value)
    (assigned : current.assignLocal 4 nextValue = some after)
    (valueEq : nextValue = .signed .i32 (Int.ofNat nextCursor))
    (nextInSource : nextCursor ≤ source.length) :
    QuotedInvariant caller after cell source delimiter nextCursor escaping
      cursorCellId escapingCellId := by
  have assignedCell := assignLocal_assignCell 4 cursorCellId nextValue invariant.cursorCell assigned
  have frame := invariant.frame.assignLocalFresh 4 cursorCellId nextValue invariant.cursorCell invariant.cursorCellFresh assigned
  let preserve := fun (id : VarId) (oldValue : Value) (localFound : current.local? id = some oldValue) (different : current.cellId? id ≠ some cursorCellId) => assignCell_preserves_other_local_of_cellId id cursorCellId nextValue assignedCell localFound different
  have sourceLocal := preserve 0 _ invariant.sourceSlice.localFound invariant.sourceCursorDistinct
  have lengthLocal := preserve 1 _ invariant.lengthLocal invariant.lengthCursorDistinct
  have delimiterLocal := preserve 3 _ invariant.delimiterLocal invariant.delimiterCursorDistinct
  have escapingLocal := preserve 5 _ invariant.escapingLocal invariant.escapingCursorDistinct
  have cursorLocal := assignLocal_finds_assigned 4 cursorCellId nextValue invariant.cursorCell assigned
  apply afterAssignment invariant frame assignedCell sourceLocal lengthLocal delimiterLocal (by simpa [valueEq] using cursorLocal) escapingLocal nextInSource

theorem QuotedInvariant.afterEscapingAssignment
    {caller current after : State} {cell : CellId} {source : List Byte}
    {delimiter : Int} {cursor : Nat} {escaping : Bool}
    {cursorCellId escapingCellId : CellId}
    (invariant : QuotedInvariant caller current cell source delimiter cursor escaping
      cursorCellId escapingCellId)
    (nextEscaping : Bool) (nextValue : Value)
    (assigned : current.assignLocal 5 nextValue = some after)
    (valueEq : nextValue = .boolean nextEscaping) :
    QuotedInvariant caller after cell source delimiter cursor nextEscaping
      cursorCellId escapingCellId := by
  have assignedCell := assignLocal_assignCell 5 escapingCellId nextValue invariant.escapingCell assigned
  have frame := invariant.frame.assignLocalFresh 5 escapingCellId nextValue invariant.escapingCell invariant.escapingCellFresh assigned
  let preserve := fun (id : VarId) (oldValue : Value) (localFound : current.local? id = some oldValue) (different : current.cellId? id ≠ some escapingCellId) => assignCell_preserves_other_local_of_cellId id escapingCellId nextValue assignedCell localFound different
  have sourceLocal := preserve 0 _ invariant.sourceSlice.localFound invariant.sourceEscapingDistinct
  have lengthLocal := preserve 1 _ invariant.lengthLocal invariant.lengthEscapingDistinct
  have delimiterLocal := preserve 3 _ invariant.delimiterLocal invariant.delimiterEscapingDistinct
  have cursorLocal := preserve 4 _ invariant.cursorLocal invariant.cursorEscapingDistinct
  have escapingLocal := assignLocal_finds_assigned 5 escapingCellId nextValue invariant.escapingCell assigned
  apply afterAssignment invariant frame assignedCell sourceLocal lengthLocal delimiterLocal cursorLocal (by simpa [valueEq] using escapingLocal) invariant.cursorInSource

end Lanius.Compiler.Lexer
