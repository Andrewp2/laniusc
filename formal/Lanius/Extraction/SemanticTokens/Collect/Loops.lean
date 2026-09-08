import Lanius.Extraction.SemanticTokens.Collect.ValidationLoop

namespace Lanius.Extraction.SemanticTokens.Collect

open Lanius Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.Compiler.Parser ParserTreeLayout

/-- Ordinary storage after the grammar metadata declarations. Output contents
are arbitrary; every cursor and loop invariant is constructed by execution. -/
structure LoopEntry (data : TraversalData) (before : State) : Prop where
  wellFormed : StateWellFormed before
  grammar : data.grammar.Owns data.grammarCell before
  kinds : I32PrefixLocal before 2 data.kindsCell (data.tokens.map (Int.ofNat ∘ Token.kind))
  records : I32PrefixLocal before 4 data.recordsCell (treeFrom 0 0 data.tree).words
  offsets : I32PrefixLocal before 6 data.offsetsCell ((treeFrom 0 0 data.tree).offsets.map Int.ofNat)
  output : before.local? 8 = some (.slice i32 data.outputCell [] 0 data.original.length)
  backing : before.cellEntry? data.outputCell = some {
    id := data.outputCell, value := some (.array (signedI32Values data.original)) }
  count : before.local? 3 = some (.signed .i32 data.tokens.length)
  wordLength : before.local? 5 = some (.signed .i32 (treeFrom 0 0 data.tree).words.length)
  nodeCount : before.local? 7 = some (.signed .i32 data.collection.records.length)
  kindCount : before.local? 10 = some (.signed .i32 data.grammar.grammar.grammar.n_kinds)
  canonicalOffset : before.local? 11 = some (.signed .i32 data.grammar.layout.canonicalKindsOffset)
  nodesFit : data.collection.records.length ≤ 2147483647
  separate : ∀ cell ∈ [data.grammarCell, data.kindsCell, data.recordsCell, data.offsetsCell], cell ≠ data.outputCell

def LoopEntry.initializer {data : TraversalData} (entry : LoopEntry data before) : InitializeEntry before :=
  ⟨data.outputCell, data.original, data.tokens.length, data.capacity, data.tokensFit,
    entry.wellFormed, entry.output, entry.backing, entry.count⟩

private theorem LoopEntry.local_separate {data : TraversalData} {id : VarId} (entry : LoopEntry data before)
    (member : id ∈ nodeStableIds) (binding : before.cellId? id = some cell) : cell ≠ data.outputCell := by
  simp only [nodeStableIds, List.mem_cons, List.not_mem_nil, or_false] at member
  rcases member with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl
  · exact local_cell_ne_of_distinct_value entry.grammar.unused_local entry.backing (by intro same; cases same) binding
  · exact local_cell_ne_of_distinct_value entry.kinds.unused_local entry.backing (by intro same; cases same) binding
  · exact local_cell_ne_of_distinct_value entry.count entry.backing (by intro same; cases same) binding
  · exact local_cell_ne_of_distinct_value entry.records.unused_local entry.backing (by intro same; cases same) binding
  · exact local_cell_ne_of_distinct_value entry.wordLength entry.backing (by intro same; cases same) binding
  · exact local_cell_ne_of_distinct_value entry.offsets.unused_local entry.backing (by intro same; cases same) binding
  · exact local_cell_ne_of_distinct_value entry.nodeCount entry.backing (by intro same; cases same) binding
  · exact local_cell_ne_of_distinct_value entry.output entry.backing (by intro same; cases same) binding
  · exact local_cell_ne_of_distinct_value entry.kindCount entry.backing (by intro same; cases same) binding
  · exact local_cell_ne_of_distinct_value entry.canonicalOffset entry.backing (by intro same; cases same) binding

private theorem LoopEntry.input_old {data : TraversalData} (entry : LoopEntry data before)
    (member : cell ∈ [data.grammarCell, data.kindsCell, data.recordsCell, data.offsetsCell]) : cell < before.nextCell := by
  simp only [List.mem_cons, List.not_mem_nil, or_false] at member
  rcases member with rfl | rfl | rfl | rfl
  · exact StateWellFormed.cell_lt_next_of_entry entry.wellFormed entry.grammar.unused_backing
  · exact StateWellFormed.cell_lt_next_of_entry entry.wellFormed entry.kinds.unused_backing
  · exact StateWellFormed.cell_lt_next_of_entry entry.wellFormed entry.records.unused_backing
  · exact StateWellFormed.cell_lt_next_of_entry entry.wellFormed entry.offsets.unused_backing

/-- Initialization preserves the parser and grammar resources needed by the
next phase. No independent initialized-buffer premise is introduced. -/
theorem LoopEntry.initialized {data : TraversalData} (entry : LoopEntry data before)
    (invariant : InitializeInvariant entry.initializer.memory (data.tokens.length * 2) after)
    (effect : CellEffect entry.initializer.memory.writes (before.bindLocal 12 (.signed .i32 0)) after) :
    NodeEntry data after := by
  have boundWF := bindLocal_preserves_well_formed before 12 (.signed .i32 0) entry.wellFormed
  have different {id : VarId} (member : id ∈ nodeStableIds) : (12 : VarId) ≠ id := by
    simp only [nodeStableIds, List.mem_cons, List.not_mem_nil, or_false] at member
    dsimp only [VarId] at member ⊢
    omega
  have keep {id : VarId} {value : Value} (member : id ∈ nodeStableIds)
      (found : before.local? id = some value) : after.local? id = some value := by
    apply effect.preserves_local boundWF ((bindLocal_preserves_other_local entry.wellFormed (different member)).trans found)
    intro cell binding changed
    have oldBinding : before.cellId? id = some cell := by
      simpa only [bindLocal_preserves_other_cellId before 12 id (.signed .i32 0) (different member)] using binding
    rcases changed with output | cursor
    · exact entry.local_separate member oldBinding output
    · exact (Nat.ne_of_lt (StateWellFormed.cell_lt_next_of_local_binding id cell entry.wellFormed oldBinding)) cursor
  have inputPreserved {id : VarId} {cell : CellId} {words : List Int}
      (idMember : id ∈ nodeStableIds) (cellMember : cell ∈ [data.grammarCell, data.kindsCell, data.recordsCell, data.offsetsCell])
      (owned : I32PrefixLocal before id cell words) : I32PrefixLocal after id cell words := by
    apply owned.transport (fun _ found => keep idMember found)
    intro contents found
    have old := entry.input_old cellMember
    have boundEntry := ((bindLocal_effect before 12 (.signed .i32 0)).oldCells cell old (by simp [CellSet.empty])).trans found
    exact effect.preserves_entry boundWF boundEntry
      (fun changed => changed.elim (entry.separate cell cellMember) (Nat.ne_of_lt old))
  exact ⟨invariant.wellFormed,
    inputPreserved (by decide) (by simp) entry.grammar,
    inputPreserved (by decide) (by simp) entry.kinds,
    inputPreserved (by decide) (by simp) entry.records,
    inputPreserved (by decide) (by simp) entry.offsets,
    invariant.outputLocal, invariant.contents, keep (by decide) entry.count,
    keep (by decide) entry.wordLength, keep (by decide) entry.nodeCount,
    keep (by decide) entry.kindCount, keep (by decide) entry.canonicalOffset, entry.nodesFit, entry.separate⟩

def loops (symbols : Symbols) : Stmt := declare 12 (number 0) (.sequence initializeLoop (afterInitialization symbols))

/-- All three source loops and their final return, from arbitrary output
storage. Freshness, both traversal invariants, and the final validator inputs
are derived here; only the assignment output changes in the caller's cells. -/
theorem LoopEntry.execute {data : TraversalData} (entry : LoopEntry data before)
    (program : Program) (symbols : Symbols)
    (tokenTag : ParserTreeSource.constantValue program symbols.childToken 1)
    (stateTag : ParserTreeSource.constantValue program symbols.childState 2) :
    ∃ after, Executes program before (loops symbols) (.returned (some (.signed .i32 0))) after ∧
      after.cellEntry? data.outputCell = some {
        id := data.outputCell, value := some (.array (signedI32Values
          (data.collection.assignments.flatMap Assignment.words ++ data.original.drop (data.tokens.length * 2)))) } ∧
      CellEffect (CellSet.singleton data.outputCell) before after := by
  obtain ⟨initializedState, initialization, initializedOwned, initializeEffect⟩ := entry.initializer.execute program
  have nodeEntry := entry.initialized initializedOwned initializeEffect
  have entered := nodeEntry.invariant
  obtain ⟨collected, traversal, collectedOwned, nodeEffect⟩ := nodeEntry.execute program symbols tokenTag stateTag
  have cursorOld : before.nextCell < initializedState.nextCell :=
    StateWellFormed.cell_lt_next_of_entry initializedOwned.wellFormed initializedOwned.cursor.2
  have outputOld : data.outputCell < before.nextCell :=
    StateWellFormed.cell_lt_next_of_entry entry.wellFormed entry.backing
  have cursorEntered := bindLocal_preserves_localPointsTo_of_ne initializedState 13 12 (.signed .i32 0)
    before.nextCell _ initializedOwned.wellFormed (by decide) initializedOwned.cursor
  have cursorCollected := nodeEffect.preserves_localPointsTo entered.wellFormed cursorEntered
    (fun changed => changed.elim (Nat.ne_of_lt outputOld).symm (Nat.ne_of_lt cursorOld))
  have stable : ∀ id ∈ validationStableIds, ∀ cell, collected.cellId? id = some cell → cell ≠ before.nextCell := by
    intro id member cell binding
    have high : id < 12 := by
      simp only [validationStableIds, List.mem_cons, List.not_mem_nil, or_false] at member
      dsimp only [VarId] at member ⊢
      omega
    have nodeDifferent : (13 : VarId) ≠ id := by dsimp only [VarId] at high ⊢; omega
    have cursorDifferent : (12 : VarId) ≠ id := by dsimp only [VarId] at high ⊢; omega
    have atNode : (initializedState.bindLocal 13 (.signed .i32 0)).cellId? id = some cell := by
      simpa only [State.cellId?, nodeEffect.locals] using binding
    have atInitialized : initializedState.cellId? id = some cell := by
      simpa only [bindLocal_preserves_other_cellId initializedState 13 id (.signed .i32 0) nodeDifferent] using atNode
    have atCursor : (before.bindLocal 12 (.signed .i32 0)).cellId? id = some cell := by
      simpa only [State.cellId?, initializeEffect.locals] using atInitialized
    have original : before.cellId? id = some cell := by
      simpa only [bindLocal_preserves_other_cellId before 12 id (.signed .i32 0) cursorDifferent] using atCursor
    exact Nat.ne_of_lt (StateWellFormed.cell_lt_next_of_local_binding id cell entry.wellFormed original)
  let memory : ValidationMemory := {
    data
    cursorCell := before.nextCell
    separate := by
      intro cell member
      simp only [List.mem_cons, List.not_mem_nil, or_false] at member
      rcases member with rfl | rfl | rfl
      · exact Nat.ne_of_lt (entry.input_old (by simp))
      · exact Nat.ne_of_lt (entry.input_old (by simp))
      · exact Nat.ne_of_lt outputOld
  }
  have validationOwned : ValidationOwned memory (data.tokens.length * 2) collected :=
    ⟨collectedOwned.wellFormed, collectedOwned.grammar, collectedOwned.kinds, collectedOwned.assignments,
      cursorCollected, collectedOwned.count, collectedOwned.canonicalOffset, stable⟩
  obtain ⟨ready, reset, zeroCursor, resetEffect⟩ := evaluatesOwnedLocalUpdate validationOwned.wellFormed validationOwned.cursor
    (show Evaluates program collected (number 0) (.signed .i32 0) collected from ⟨1, rfl⟩)
    (show evalAssignValue program.target .set (some (.signed .i32 (Int.ofNat (data.tokens.length * 2)))) (.signed .i32 0) =
      .ok (.signed .i32 0) from rfl)
  have readyOwned : ValidationOwned memory 0 ready := validationOwned.advance resetEffect zeroCursor
  obtain ⟨completed, validation, final, validationEffect⟩ := validation_loop program readyOwned (by omega)
  have finish : Executes program completed (returned (number 0)) (.returned (some (.signed .i32 0))) completed :=
    executesSequenceReturned (executesReturnValue (show Evaluates program completed (number 0) (.signed .i32 0) completed from ⟨1, rfl⟩))
  have lastRun := executesSequence traversal
    (executesSequence (executesExpression reset) (executesSequence validation finish))
  have nodeScope := executesLetLocal (id := 13) (type := i32)
    (show Evaluates program initializedState (number 0) (.signed .i32 0) initializedState from ⟨1, rfl⟩) lastRun
  have indexScope := executesLetLocal (id := 12) (type := i32)
    (show Evaluates program before (number 0) (.signed .i32 0) before from ⟨1, rfl⟩)
    (executesSequence initialization nodeScope)
  let writes := CellSet.union nodeEntry.memory.writes (CellSet.singleton before.nextCell)
  have restEffect := resetEffect.trans validationEffect
  have allNodes : CellEffect writes (initializedState.bindLocal 13 (.signed .i32 0)) completed :=
    (nodeEffect.weaken CellSet.subset_union_left).trans (restEffect.weaken CellSet.subset_union_right)
  have closedNode := CellEffect.closeLocal initializedState 13 (.signed .i32 0) initializedOwned.wellFormed allNodes
  have narrowedNode : CellEffect entry.initializer.memory.writes initializedState (restoreLocals initializedState completed) := by
    apply closedNode.narrow
    intro cell old changed
    rcases changed with (output | node) | cursor
    · exact Or.inl output
    · exact (Nat.ne_of_lt old node).elim
    · exact Or.inr cursor
  have both := initializeEffect.trans narrowedNode
  have closedIndex := CellEffect.closeLocal before 12 (.signed .i32 0) entry.wellFormed both
  have effect : CellEffect (CellSet.singleton data.outputCell) before (restoreLocals before completed) := by
    apply closedIndex.narrow
    intro cell old changed
    exact changed.elim (fun output => output) (fun cursor => (Nat.ne_of_lt old cursor).elim)
  have contents := collectedOwned.finished
  dsimp only [NodeEntry.memory] at contents
  rw [data.collection.written] at contents
  have preserved := restEffect.preserves_entry collectedOwned.wellFormed contents (Nat.ne_of_lt outputOld)
  exact ⟨restoreLocals before completed, indexScope, preserved, effect⟩

end Lanius.Extraction.SemanticTokens.Collect
