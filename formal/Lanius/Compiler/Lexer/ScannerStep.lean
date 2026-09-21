import Lanius.Compiler.Lexer.ScannerInvariant
import Lanius.Semantics.Assignment
import Lanius.Semantics.Branch
import Lanius.Semantics.MutableLocal
import Lanius.Semantics.ReadOnlySlice

namespace Lanius.Compiler.Lexer

open Lanius Lanius.Core Lanius.Semantics

theorem scannerLoopBody_step
    (program : Program)
    {caller current : State} {cell : CellId} {source : List Byte}
    {cursor : Nat} {cursorCellId : CellId}
    (invariant : ScannerInvariant caller current cell source cursor cursorCellId)
    (inBounds : cursor < source.length)
    (backing : SourceBacking caller cell (sourceI32Values source)) :
    ∃ after,
      (∀ fuel, 4 ≤ fuel →
        execStmt fuel program current Artifact.scannerLoopBody = .done .next after) ∧
      ScannerInvariant caller after cell source (cursor + 1) cursorCellId := by
  let cursorValue : Value := .signed .i32 (Int.ofNat cursor)
  let nextValue : Value := .signed .i32 (wrapSigned program.target .i32 (Int.ofNat cursor + 1))
  obtain ⟨after, assigned⟩ := assignLocal_exists current 3 cursorValue nextValue cursorCellId
    invariant.cursorCell (by simpa [cursorValue] using invariant.cursorLocal)
  have assignedCell := assignLocal_assignCell 3 cursorCellId nextValue
    invariant.cursorCell assigned
  have nextFrame : CallerFrame caller after :=
    invariant.frame.assignLocalFresh 3 cursorCellId nextValue
      invariant.cursorCell invariant.cursorCellFresh assigned
  have sourceLocalAfter := assignCell_preserves_other_local_of_cellId 0 cursorCellId nextValue
    assignedCell invariant.sourceSlice.localFound invariant.sourceCellDistinct
  have sourceAfter : SourceSlice after 0 cell (sourceI32Values source) :=
    SourceSlice.ofBacking 0 cell (sourceI32Values source)
      sourceLocalAfter (backing.afterCallerFrame nextFrame)
  have limitAfter := assignCell_preserves_other_local_of_cellId 1 cursorCellId nextValue
    assignedCell invariant.lengthLocal invariant.lengthCellDistinct
  have cursorCellAfter := assignLocal_finds_assigned 3 cursorCellId nextValue
    invariant.cursorCell assigned
  have addRun := StableExpr.assignAddI32 program current 3 cursorCellId
    (Int.ofNat cursor) 1 after invariant.cursorCell
    (by simpa [cursorValue] using invariant.cursorLocal)
    (by simpa [nextValue] using assigned)
  have skipRun : StableStmt 1 program after .skip .next after :=
    StableStmt.skip program after
  have bodyRun : StableStmt 4 program current Artifact.scannerLoopBody .next after := by
    have expressionRun := StableStmt.expression addRun
    simpa [Artifact.scannerLoopBody] using
      StableStmt.sequence_next expressionRun skipRun
  have nextBound : cursor + 1 < (2 ^ 31 : Nat) := Nat.lt_of_le_of_lt
    (Nat.succ_le_of_lt inBounds) invariant.sourceLengthI32
  have cursorNext : nextValue = .signed .i32 (Int.ofNat (cursor + 1)) := by
    dsimp [nextValue]
    simpa using congrArg (fun value : Int => Value.signed .i32 value)
      (wrapSigned_i32_nat_lt program.target (cursor + 1) nextBound)
  have nextInvariant : ScannerInvariant caller after cell source
      (cursor + 1) cursorCellId := by
    have cellIdPreserved (id : VarId) : after.cellId? id = current.cellId? id :=
      (assignLocal_preserves_frame (protectedId := id) assigned).2
    refine {
      frame := nextFrame
      sourceSlice := sourceAfter
      lengthLocal := limitAfter
      cursorLocal := ?_
      cursorCell := ?_
      sourceCellDistinct := ?_
      lengthCellDistinct := ?_
      cursorCellFresh := invariant.cursorCellFresh
      cursorInSource := Nat.succ_le_of_lt inBounds
      sourceLengthI32 := invariant.sourceLengthI32 }
    · simpa [cursorNext] using cursorCellAfter
    · rw [cellIdPreserved 3, invariant.cursorCell]
    · intro equal
      apply invariant.sourceCellDistinct
      simpa [cellIdPreserved 0] using equal
    · intro equal
      apply invariant.lengthCellDistinct
      simpa [cellIdPreserved 1] using equal
  exact ⟨after, bodyRun, nextInvariant⟩

end Lanius.Compiler.Lexer
