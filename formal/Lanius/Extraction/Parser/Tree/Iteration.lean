import Lanius.Extraction.Parser.Tree.Execution
import Lanius.Separation.LocalStore

namespace Lanius.Extraction.ParserTreeSource

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

private theorem local_read {id : Lanius.VarId} (found : before.local? id = some value) :
    Evaluates program before (.local id) value before :=
  ⟨1, evalLocal_of_local 0 program before id value found⟩

/-- A terminal occurrence makes no recursive call and does not rewrite its
    triple. It advances only the owned child cursor, including the actual slot
    scope, indexed tag read, branch, and checked i32 increment. -/
theorem CheckedVisit.token_iteration (checked : CheckedVisit program)
    (wellFormed : StateWellFormed before)
    (parentLocal : before.local? 10 = some (.signed .i32 (Int.ofNat parentWord)))
    (cursorOwned : (Assertion.localPointsTo 15 cursorCell (some (.signed .i32 (Int.ofNat index)))).holds before)
    (recordsLocal : before.local? 5 = some
      (.slice (.scalar (.signed .i32)) recordsCell [] 0 records.length))
    (recordsBacking : before.cellEntry? recordsCell = some {
      id := recordsCell, value := some (.array (signedI32Values records)) })
    (tagAt : records[parentWord + 4 + index * 3]? = some 1)
    (bounded : records.length ≤ 2147483647) :
    ∃ after, Executes program.core before (childIteration checked.symbols) .next after ∧
      (Assertion.localPointsTo 15 cursorCell (some (.signed .i32 (Int.ofNat (index + 1))))).holds after ∧
      after.cellEntry? recordsCell = some {
        id := recordsCell, value := some (.array (signedI32Values records)) } ∧
      CellEffect (CellSet.singleton cursorCell) before after := by
  let slot := parentWord + 4 + index * 3
  have slotBound : slot < records.length := (List.getElem?_eq_some_iff.mp tagAt).1
  have cursorLocal := Assertion.localPointsTo_local _ _ _ _ cursorOwned
  have slotEvaluation : Evaluates program.core before childSlot (.signed .i32 (Int.ofNat slot)) before := by
    apply evaluatesNatI32Add
    · exact evaluatesNatI32Add (local_read parentLocal) ⟨1, rfl⟩ (by dsimp [slot] at slotBound; omega)
    · exact evaluatesNatI32Multiply (local_read cursorLocal) ⟨1, rfl⟩ (by dsimp [slot] at slotBound; omega)
    · omega
  let entered := before.bindLocal 16 (.signed .i32 (Int.ofNat slot))
  have scopedWF : StateWellFormed entered := bindLocal_preserves_well_formed before 16 _ wellFormed
  have slotLocal : entered.local? 16 = some (.signed .i32 (Int.ofNat slot)) :=
    bindLocal_finds_local before 16 _ wellFormed
  have scopedRecords : entered.local? 5 = some
      (.slice (.scalar (.signed .i32)) recordsCell [] 0 records.length) := by
    exact (bindLocal_preserves_other_local wellFormed (show (16 : Lanius.VarId) ≠ 5 by decide)).trans recordsLocal
  have backing : entered.cellEntry? recordsCell = some {
      id := recordsCell, value := some (.array (signedI32Values records)) } := by
    exact ((bindLocal_effect before 16 (.signed .i32 (Int.ofNat slot))).oldCells recordsCell
      (StateWellFormed.cell_lt_next_of_entry wellFormed recordsBacking) (by simp [CellSet.empty])).trans recordsBacking
  have scopedCursor := bindLocal_preserves_localPointsTo_of_ne before 16 15
    (.signed .i32 (Int.ofNat slot)) cursorCell _ wellFormed (by decide) cursorOwned
  have tagRead : Evaluates program.core entered (.index (.local 5) (.local 16)) (.signed .i32 1) entered := by
    have selected : records.get ⟨slot, slotBound⟩ = 1 := by
      exact (List.getElem?_eq_some_iff.mp tagAt).2
    simpa only [selected] using evaluatesSignedI32SliceIndex program.core entered entered entered records
      (.local 5) (.local 16) recordsCell slot slotBound (local_read scopedRecords) (local_read slotLocal) backing
  have tagDifferent : Evaluates program.core entered
      (.binary .equal (.index (.local 5) (.local 16)) (.constant checked.symbols.childState))
      (.boolean false) entered :=
    evaluatesEagerBinary (by decide) (by decide) tagRead (evaluatesConstant checked.childTag) rfl
  obtain ⟨completed, increment, cursorAfter, incrementEffect⟩ := evaluatesOwnedLocalUpdate scopedWF scopedCursor
    (show Evaluates program.core entered (.value (.signed .i32 1)) (.signed .i32 1) entered from ⟨1, rfl⟩)
    (show evalAssignValue program.core.target .add (some (.signed .i32 (Int.ofNat index))) (.signed .i32 1) =
        .ok (.signed .i32 (Int.ofNat (index + 1))) from by
      simp only [evalAssignValue, assignOpBinary?, evalBinaryValue, evalSignedBinary]
      rw [show Int.ofNat index + 1 = Int.ofNat (index + 1) by simp,
        wrapSigned_i32_ofNat program.core.target (index + 1) (by dsimp [slot] at slotBound; omega)]
      rfl)
  have effect := CellEffect.closeLocal before 16 (.signed .i32 (Int.ofNat slot)) wellFormed incrementEffect
  have recordsDifferent : recordsCell ≠ cursorCell := by
    exact Ne.symm (local_cell_ne_of_distinct_value cursorLocal recordsBacking (by intro impossible; cases impossible) cursorOwned.1)
  refine ⟨restoreLocals before completed, ?_, ⟨cursorOwned.1, cursorAfter.2⟩,
    effect.preserves_entry wellFormed recordsBacking recordsDifferent, effect⟩
  exact executesLetLocal slotEvaluation
    (executesSequence (executesIfFalse tagDifferent (executesSkip _ _))
      (executesSequence (executesExpression increment) (executesSkip _ _)))

end Lanius.Extraction.ParserTreeSource
