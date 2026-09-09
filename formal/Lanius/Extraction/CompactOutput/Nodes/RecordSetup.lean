import Lanius.Extraction.CompactOutput.Nodes.Emit

namespace Lanius.Extraction.CompactOutput.Nodes

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Extraction.SemanticTokens

def recordState (before : State) (record : RecordVisit) : State :=
  before.bindLocal 10 (.signed .i32 record.offset)
def productionState (before : State) (record : RecordVisit) : State :=
  (recordState before record).bindLocal 11 (.signed .i32 record.production)
def headerState (before : State) (record : RecordVisit) : State :=
  (productionState before record).bindLocal 12 (.signed .i32 record.children.length)

theorem read_offset {index : Nat} {record : RecordVisit} (program : Program) (records : List RecordVisit)
    (input : I32PrefixLocal before 2 offsetCell (records.map (fun record => (record.offset : Int))))
    (found : records[index]? = some record)
    (indexRead : before.local? 9 = some (.signed .i32 index)) :
    Evaluates program before (.index (read 2) (read 9)) (.signed .i32 record.offset) before := by
  apply Collect.read_word program input _ _ _ (local_evaluates program indexRead)
  simp only [List.getElem?_map, found, Option.map_some]

theorem initialize_record (program : Program) (memory : HeaderMemory)
    (wellFormed : StateWellFormed before)
    (input : I32PrefixLocal before 0 memory.inputCell memory.words) :
    Evaluates program (recordState before memory.record) (.index (read 0) (read 10))
      (.signed .i32 memory.record.production) (recordState before memory.record) ∧
    Evaluates program (productionState before memory.record) (recordRead 3)
      (.signed .i32 memory.record.children.length) (productionState before memory.record) ∧
    StateWellFormed (headerState before memory.record) ∧
    I32PrefixLocal (headerState before memory.record) 0 memory.inputCell memory.words ∧
    (headerState before memory.record).local? 10 = some (.signed .i32 memory.record.offset) ∧
    (headerState before memory.record).local? 11 = some (.signed .i32 memory.record.production) ∧
    (headerState before memory.record).local? 12 = some (.signed .i32 memory.record.children.length) := by
  have recordWF : StateWellFormed (recordState before memory.record) := bindLocal_preserves_well_formed _ _ _ wellFormed
  have recordInput := input.bindLocal wellFormed 10 (.signed .i32 memory.record.offset) (by decide)
  have recordLocal : (recordState before memory.record).local? 10 = some (.signed .i32 memory.record.offset) :=
    bindLocal_finds_local before _ _ wellFormed
  have productionWF : StateWellFormed (productionState before memory.record) := bindLocal_preserves_well_formed _ _ _ recordWF
  have productionInput := recordInput.bindLocal recordWF 11 (.signed .i32 memory.record.production) (by decide)
  have productionRecord : (productionState before memory.record).local? 10 = some (.signed .i32 memory.record.offset) :=
    (bindLocal_preserves_other_local recordWF (by decide : (11 : VarId) ≠ 10)).trans recordLocal
  exact ⟨(read_header program memory.record recordInput memory.stored recordLocal memory.sizeFit).1,
    (read_header program memory.record productionInput memory.stored productionRecord memory.sizeFit).2.2.2,
    bindLocal_preserves_well_formed _ _ _ productionWF,
    productionInput.bindLocal productionWF 12 (.signed .i32 memory.record.children.length) (by decide),
    (bindLocal_preserves_other_local productionWF (by decide : (12 : VarId) ≠ 10)).trans productionRecord,
    (bindLocal_preserves_other_local productionWF (by decide : (12 : VarId) ≠ 11)).trans
      (bindLocal_finds_local (recordState before memory.record) _ _ recordWF),
    bindLocal_finds_local (productionState before memory.record) _ _ productionWF⟩

theorem prepare_header (program : Program) (memory : HeaderMemory) (wellFormed : StateWellFormed before)
    (input : I32PrefixLocal before 0 memory.inputCell memory.words)
    (room : memory.capacity ≤ contents.length)
    (output : before.local? 5 = some (.slice i32 memory.outputCell [] 0 contents.length))
    (capacity : before.local? 6 = some (.signed .i32 memory.capacity))
    (cursor : (Assertion.localPointsTo 8 memory.cursorCell (some (.signed .i32 position))).holds before)
    (backing : before.cellEntry? memory.outputCell = some {
      id := memory.outputCell, value := some (.array (signedI32Values contents)) })
    (stable : ∀ id ∈ [0, 5, 6], ∀ cell, before.cellId? id = some cell → cell ≠ memory.cursorCell) :
    HeaderOwned memory position contents (headerState before memory.record) := by
  have recordWF : StateWellFormed (recordState before memory.record) := bindLocal_preserves_well_formed _ _ _ wellFormed
  have productionWF : StateWellFormed (productionState before memory.record) := bindLocal_preserves_well_formed _ _ _ recordWF
  obtain ⟨_, _, finalWF, finalInput, record, production, children⟩ := initialize_record program memory wellFormed input
  have keep {id : VarId} {value : Value} (n10 : (10 : VarId) ≠ id) (n11 : (11 : VarId) ≠ id)
      (n12 : (12 : VarId) ≠ id) (found : before.local? id = some value) :
      (headerState before memory.record).local? id = some value :=
    (bindLocal_preserves_other_local productionWF n12).trans
      ((bindLocal_preserves_other_local recordWF n11).trans
        ((bindLocal_preserves_other_local wellFormed n10).trans found))
  have cursorRecord := bindLocal_preserves_localPointsTo_of_ne before 10 8 (.signed .i32 memory.record.offset)
    memory.cursorCell _ wellFormed (by decide) cursor
  have cursorProduction := bindLocal_preserves_localPointsTo_of_ne (recordState before memory.record) 11 8
    (.signed .i32 memory.record.production) memory.cursorCell _ recordWF (by decide) cursorRecord
  have cursorHeader := bindLocal_preserves_localPointsTo_of_ne (productionState before memory.record) 12 8
    (.signed .i32 memory.record.children.length) memory.cursorCell _ productionWF (by decide) cursorProduction
  have backingRecord := ((bindLocal_effect before 10 (.signed .i32 memory.record.offset)).oldCells memory.outputCell
    (StateWellFormed.cell_lt_next_of_entry wellFormed backing) (by simp [CellSet.empty])).trans backing
  have backingProduction := ((bindLocal_effect (recordState before memory.record) 11 (.signed .i32 memory.record.production)).oldCells memory.outputCell
    (StateWellFormed.cell_lt_next_of_entry recordWF backingRecord) (by simp [CellSet.empty])).trans backingRecord
  have backingHeader := ((bindLocal_effect (productionState before memory.record) 12 (.signed .i32 memory.record.children.length)).oldCells memory.outputCell
    (StateWellFormed.cell_lt_next_of_entry productionWF backingProduction) (by simp [CellSet.empty])).trans backingProduction
  refine ⟨finalWF, room, finalInput, record, production, children,
    keep (by decide) (by decide) (by decide) output,
    keep (by decide) (by decide) (by decide) capacity, backingHeader, cursorHeader, ?_⟩
  intro id member cell binding
  have old := StateWellFormed.cell_lt_next_of_entry wellFormed cursor.2
  simp only [List.mem_cons, List.not_mem_nil, or_false] at member
  rcases member with rfl | rfl | rfl | rfl | rfl | rfl
  · apply stable 0 (by simp) cell
    simpa only [headerState, productionState, recordState,
      bindLocal_preserves_other_cellId _ 12 0 _ (by decide),
      bindLocal_preserves_other_cellId _ 11 0 _ (by decide),
      bindLocal_preserves_other_cellId _ 10 0 _ (by decide)] using binding
  · apply stable 5 (by simp) cell
    simpa only [headerState, productionState, recordState,
      bindLocal_preserves_other_cellId _ 12 5 _ (by decide),
      bindLocal_preserves_other_cellId _ 11 5 _ (by decide),
      bindLocal_preserves_other_cellId _ 10 5 _ (by decide)] using binding
  · apply stable 6 (by simp) cell
    simpa only [headerState, productionState, recordState,
      bindLocal_preserves_other_cellId _ 12 6 _ (by decide),
      bindLocal_preserves_other_cellId _ 11 6 _ (by decide),
      bindLocal_preserves_other_cellId _ 10 6 _ (by decide)] using binding
  · have selected : cell = before.nextCell := by
      have original : (recordState before memory.record).cellId? 10 = some cell := by
        simpa only [headerState, productionState,
          bindLocal_preserves_other_cellId _ 12 10 _ (by decide),
          bindLocal_preserves_other_cellId _ 11 10 _ (by decide)] using binding
      exact Option.some.inj (original.symm.trans (bindLocal_owns_fresh before 10 _ wellFormed).1)
    rw [selected]
    exact Ne.symm (Nat.ne_of_lt old)
  · have selected : cell = (recordState before memory.record).nextCell := by
      have original : (productionState before memory.record).cellId? 11 = some cell := by
        simpa only [headerState, bindLocal_preserves_other_cellId _ 12 11 _ (by decide)] using binding
      exact Option.some.inj (original.symm.trans (bindLocal_owns_fresh (recordState before memory.record) 11 _ recordWF).1)
    rw [selected]
    exact Ne.symm (Nat.ne_of_lt (Nat.lt_trans old (Nat.lt_succ_self _)))
  · have selected : cell = (productionState before memory.record).nextCell :=
      Option.some.inj (binding.symm.trans (bindLocal_owns_fresh (productionState before memory.record) 12 _ productionWF).1)
    rw [selected]
    exact Ne.symm (Nat.ne_of_lt (Nat.lt_trans (Nat.lt_trans old (Nat.lt_succ_self _)) (Nat.lt_succ_self _)))

end Lanius.Extraction.CompactOutput.Nodes
