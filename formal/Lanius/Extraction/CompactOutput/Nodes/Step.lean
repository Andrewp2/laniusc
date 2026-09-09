import Lanius.Extraction.CompactOutput.Nodes.RecordSetup

namespace Lanius.Extraction.CompactOutput.Nodes

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Extraction.SemanticTokens

structure RecordEntry (before : State) where
  memory : HeaderMemory
  refs : References memory
  nodeCell : CellId
  offsetCell : CellId
  position : Int
  contents : List Int
  inputLength : Nat
  wellFormed : StateWellFormed before
  input : I32PrefixLocal before 0 memory.inputCell memory.words
  offsets : I32PrefixLocal before 2 offsetCell (refs.records.map (fun record => (record.offset : Int)))
  found : refs.records[refs.node]? = some memory.record
  inputRoom : memory.words.length ≤ inputLength
  inputFit : inputLength ≤ 2147483647
  lengthRead : before.local? 1 = some (.signed .i32 inputLength)
  refsOwned : ReferencesOwned refs before
  room : memory.capacity ≤ contents.length
  output : before.local? 5 = some (.slice i32 memory.outputCell [] 0 contents.length)
  capacity : before.local? 6 = some (.signed .i32 memory.capacity)
  cursor : (Assertion.localPointsTo 8 memory.cursorCell (some (.signed .i32 position))).holds before
  node : (Assertion.localPointsTo 9 nodeCell (some (.signed .i32 refs.node))).holds before
  backing : before.cellEntry? memory.outputCell = some {
    id := memory.outputCell, value := some (.array (signedI32Values contents)) }
  stable : ∀ id ∈ [0, 5, 6], ∀ cell, before.cellId? id = some cell → cell ≠ memory.cursorCell
  distinct : memory.cursorCell ≠ nodeCell
  nextFit : refs.node + 1 ≤ 2147483647

theorem RecordEntry.execute (entry : RecordEntry before) (word : Word.Checked program byte digit)
    (tokenConstant : ParserTreeSource.constantValue program.core tokenTag 1)
    (stateConstant : ParserTreeSource.constantValue program.core stateTag 2) :
    ∃ after, Executes program.core before (step word.source.function.id tokenTag stateTag)
        (appendAll entry.memory.capacity (encodeRecord entry.memory.record) entry.position entry.contents).completion after ∧
      after.cellEntry? entry.memory.outputCell = some {
        id := entry.memory.outputCell, value := some (.array (signedI32Values
          (appendAll entry.memory.capacity (encodeRecord entry.memory.record) entry.position entry.contents).contents)) } ∧
      (∀ result updated, appendAll entry.memory.capacity (encodeRecord entry.memory.record) entry.position entry.contents = .done result updated →
        (Assertion.localPointsTo 8 entry.memory.cursorCell (some (.signed .i32 result))).holds after ∧
        (Assertion.localPointsTo 9 entry.nodeCell (some (.signed .i32 (entry.refs.node + 1 : Nat)))).holds after) ∧
      CellEffect (CellSet.union entry.memory.writes (CellSet.singleton entry.nodeCell)) before after := by
  have offsetRun := read_offset program.core entry.refs.records entry.offsets entry.found entry.refsOwned.node
  obtain ⟨productionRun, childrenRun, headerWF, _, _, _, _⟩ := initialize_record program.core entry.memory entry.wellFormed entry.input
  have recordWF : StateWellFormed (recordState before entry.memory.record) := bindLocal_preserves_well_formed _ _ _ entry.wellFormed
  have productionWF : StateWellFormed (productionState before entry.memory.record) := bindLocal_preserves_well_formed _ _ _ recordWF
  have keep {id : VarId} {value : Value} (n10 : (10 : VarId) ≠ id) (n11 : (11 : VarId) ≠ id)
      (n12 : (12 : VarId) ≠ id) (found : before.local? id = some value) :
      (headerState before entry.memory.record).local? id = some value :=
    (bindLocal_preserves_other_local productionWF n12).trans
      ((bindLocal_preserves_other_local recordWF n11).trans
        ((bindLocal_preserves_other_local entry.wellFormed n10).trans found))
  have held := prepare_header program.core entry.memory entry.wellFormed entry.input entry.room
    entry.output entry.capacity entry.cursor entry.backing entry.stable
  have refs : ReferencesOwned entry.refs (headerState before entry.memory.record) := by
    refine ⟨keep (by decide) (by decide) (by decide) entry.refsOwned.count,
      keep (by decide) (by decide) (by decide) entry.refsOwned.node, ?_⟩
    intro id member cell binding
    apply entry.refsOwned.stable id member cell
    simp only [List.mem_cons, List.not_mem_nil, or_false] at member
    rcases member with rfl | rfl
    · simpa only [headerState, productionState, recordState,
        bindLocal_preserves_other_cellId _ 12 4 _ (by decide),
        bindLocal_preserves_other_cellId _ 11 4 _ (by decide),
        bindLocal_preserves_other_cellId _ 10 4 _ (by decide)] using binding
    · simpa only [headerState, productionState, recordState,
        bindLocal_preserves_other_cellId _ 12 9 _ (by decide),
        bindLocal_preserves_other_cellId _ 11 9 _ (by decide),
        bindLocal_preserves_other_cellId _ 10 9 _ (by decide)] using binding
  have nodeRecord := bindLocal_preserves_localPointsTo_of_ne before 10 9 (.signed .i32 entry.memory.record.offset)
    entry.nodeCell _ entry.wellFormed (by decide) entry.node
  have nodeProduction := bindLocal_preserves_localPointsTo_of_ne (recordState before entry.memory.record) 11 9
    (.signed .i32 entry.memory.record.production) entry.nodeCell _ recordWF (by decide) nodeRecord
  have nodeHeader := bindLocal_preserves_localPointsTo_of_ne (productionState before entry.memory.record) 12 9
    (.signed .i32 entry.memory.record.children.length) entry.nodeCell _ productionWF (by decide) nodeProduction
  have recordGuardRun := record_guard_pass program.core entry.memory.record entry.memory.stored
    entry.inputRoom entry.inputFit (bindLocal_finds_local before _ _ entry.wellFormed)
    ((bindLocal_preserves_other_local entry.wellFormed (by decide : (10 : VarId) ≠ 1)).trans entry.lengthRead)
  have childrenGuardRun := children_guard_pass program.core entry.memory.record entry.memory.stored
    entry.inputRoom entry.inputFit held.record (keep (by decide) (by decide) (by decide) entry.lengthRead)
    held.production held.children
  obtain ⟨written, emitted, backing, advanced, effect⟩ := emit_record held refs word tokenConstant stateConstant
    nodeHeader entry.distinct entry.nextFit
  have run := executesLetLocal (id := 10) (type := i32) offsetRun
    (executesSequence (executesIfFalse (thenBranch := returned negativeOne) recordGuardRun (executesSkip _ _))
      (executesLetLocal (id := 11) (type := i32) productionRun
        (executesLetLocal (id := 12) (type := i32) childrenRun
          (executesSequence (executesIfFalse (thenBranch := returned negativeOne) childrenGuardRun (executesSkip _ _)) emitted))))
  have closed := CellEffect.closeLocal before 10 (.signed .i32 entry.memory.record.offset) entry.wellFormed
    (CellEffect.closeLocal (recordState before entry.memory.record) 11 (.signed .i32 entry.memory.record.production) recordWF
      (CellEffect.closeLocal (productionState before entry.memory.record) 12 (.signed .i32 entry.memory.record.children.length) productionWF effect))
  refine ⟨restoreLocals before written, run, backing, ?_, closed⟩
  intro result updated done
  obtain ⟨cursor, node⟩ := advanced result updated done
  exact ⟨⟨entry.cursor.1, cursor.2⟩, ⟨entry.node.1, node.2⟩⟩

end Lanius.Extraction.CompactOutput.Nodes
