import Lanius.Extraction.OutputPacking.Execution
import Lanius.Extraction.OutputPacking.Source

namespace Lanius.Extraction.OutputPacking

open Lanius Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

/-- The complete source loop body advances both the packed prefix and the
owned cursor. Its only writes are the workspace cell and the cursor cell. -/
theorem executes_packing_body
    (program : Program) (before : State) (values : List Int) (locals : LoopLocals)
    (workspaceCell cursorCell : CellId)
    (words : Nat) (processed : List UInt8) (byte : UInt8) (tail : List Value)
    (room : (processed.length + 4) / 4 ≤ words)
    (cursorBound : processed.length + 1 ≤ 2147483647)
    (distinct : workspaceCell ≠ cursorCell)
    (wellFormed : StateWellFormed before)
    (contents : signedI32Values values = workspace words processed tail)
    (workspaceLocal : before.local? locals.workspace = some
      (.slice (.scalar (.signed .i32)) workspaceCell [] 0 values.length))
    (backing : before.cellEntry? workspaceCell = some {
      id := workspaceCell, value := some (.array (signedI32Values values)) })
    (cursor : (Assertion.localPointsTo locals.cursor cursorCell
      (some (.signed .i32 processed.length))).holds before)
    (byteResult : Evaluates program before
      (.index (.local locals.input) (.local locals.cursor))
      (.signed .i32 byte.toNat) before) :
    ∃ after,
      Executes program before locals.body .next after ∧
      StateWellFormed after ∧
      after.cellEntry? workspaceCell = some {
        id := workspaceCell
        value := some (.array (workspace words (processed ++ [byte]) tail))
      } ∧
      (Assertion.localPointsTo locals.cursor cursorCell
        (some (.signed .i32 (processed.length + 1 : Nat)))).holds after ∧
      ModifiesOnly (CellSet.union (CellSet.singleton workspaceCell)
        (CellSet.singleton cursorCell)) before after := by
  have cursorResult : Evaluates program before (.local locals.cursor)
      (.signed .i32 processed.length) before :=
    ⟨1, evalLocal_of_local 0 program before locals.cursor _
      (Assertion.localPointsTo_local _ _ _ _ cursor)⟩
  have four : Evaluates program before (.value (.signed .i32 4)) (.signed .i32 4) before :=
    ⟨1, rfl⟩
  have eight : Evaluates program before (.value (.signed .i32 8)) (.signed .i32 8) before :=
    ⟨1, rfl⟩
  have indexResult := evaluatesNatI32Divide (leftValue := processed.length)
    (rightValue := 4) cursorResult four (by decide) (by omega)
  have laneResult := evaluatesNatI32Remainder (leftValue := processed.length)
    (rightValue := 4) cursorResult four (by decide) (by omega)
  have shiftResult := evaluatesNatI32Multiply (leftValue := processed.length % 4)
    (rightValue := 8) laneResult eight (by omega)
  obtain ⟨packed, assignment, packedWF, packedContents, packEffect⟩ :=
    writes_next_workspace_byte program before values locals.workspace workspaceCell
      _ _ _ words processed byte tail room wellFormed contents workspaceLocal backing
      indexResult byteResult shiftResult
  have cursorStill := packEffect.preserves_localPointsTo wellFormed cursor
    (by simpa [CellSet.singleton, eq_comm] using distinct)
  obtain ⟨after, increment, afterWF, afterCursor, cursorEffect⟩ :=
    executesIncrementOwnedI32Local program packed locals.cursor cursorCell
      processed.length packedWF cursorStill cursorBound
  refine ⟨after, ?_, afterWF, ?_, afterCursor, packEffect.trans cursorEffect⟩
  · exact executesSequence (executesExpression assignment) increment
  · exact cursorEffect.preserves_entry packedWF packedContents
      (by simpa [CellSet.singleton] using distinct)

end Lanius.Extraction.OutputPacking
