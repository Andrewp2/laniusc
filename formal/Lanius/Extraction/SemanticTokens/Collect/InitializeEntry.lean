import Lanius.Extraction.SemanticTokens.Collect.Initialize

namespace Lanius.Extraction.SemanticTokens.Collect

open Lanius Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

/-- Ordinary storage immediately before the source binds its initialization
cursor. The entry constructor derives freshness and the loop's stable locals. -/
structure InitializeEntry (before : State) where
  outputCell : CellId
  original : List Int
  count : Nat
  capacity : count * 2 ≤ original.length
  bounded : count * 2 ≤ 2147483647
  wellFormed : StateWellFormed before
  outputLocal : before.local? 8 = some (.slice i32 outputCell [] 0 original.length)
  contents : before.cellEntry? outputCell = some {
    id := outputCell, value := some (.array (signedI32Values original)) }
  countLocal : before.local? 3 = some (.signed .i32 count)

def InitializeEntry.memory (entry : InitializeEntry before) : InitializeMemory := {
  outputCell := entry.outputCell
  cursorCell := before.nextCell
  original := entry.original
  count := entry.count
  capacity := entry.capacity
  bounded := entry.bounded
  distinct := Nat.ne_of_lt (StateWellFormed.cell_lt_next_of_entry entry.wellFormed entry.contents)
}

theorem InitializeEntry.invariant (entry : InitializeEntry before) :
    InitializeInvariant entry.memory 0 (before.bindLocal 12 (.signed .i32 0)) := by
  have bindingEffect := bindLocal_effect before 12 (.signed .i32 0)
  have contents := (bindingEffect.oldCells entry.outputCell
    (StateWellFormed.cell_lt_next_of_entry entry.wellFormed entry.contents)
    (by simp [CellSet.empty])).trans entry.contents
  refine ⟨bindLocal_preserves_well_formed before _ _ entry.wellFormed,
    (bindLocal_preserves_other_local entry.wellFormed (by decide : (12 : VarId) ≠ 8)).trans entry.outputLocal,
    ?_, ?_,
    (bindLocal_preserves_other_local entry.wellFormed (by decide : (12 : VarId) ≠ 3)).trans entry.countLocal, ?_⟩
  · simpa only [memory, initialized, BufferCopy.buffer, List.replicate_zero, List.length_nil,
      List.drop_zero, List.nil_append] using contents
  · exact bindLocal_owns_fresh before 12 (.signed .i32 0) entry.wellFormed
  · intro localId member cell found changed
    have different : (12 : VarId) ≠ localId := by
      simp only [List.mem_cons, List.not_mem_nil, or_false] at member
      rcases member with rfl | rfl <;> decide
    have original : before.cellId? localId = some cell := by
      simpa only [bindLocal_preserves_other_cellId before 12 localId (.signed .i32 0) different] using found
    rcases changed with output | cursor
    · have distinct : cell ≠ entry.outputCell := by
        simp only [List.mem_cons, List.not_mem_nil, or_false] at member
        rcases member with rfl | rfl
        · exact local_cell_ne_of_distinct_value entry.outputLocal entry.contents (by intro same; cases same) original
        · exact local_cell_ne_of_distinct_value entry.countLocal entry.contents (by intro same; cases same) original
      exact distinct output
    · exact (Nat.ne_of_lt (StateWellFormed.cell_lt_next_of_local_binding localId cell entry.wellFormed original)) cursor

/-- Initialization from ordinary inputs, with no caller-supplied loop
invariant or separation premise for the fresh cursor. The cursor remains live
for the collector's later validation loop. -/
theorem InitializeEntry.execute (entry : InitializeEntry before) (program : Program) :
    ∃ after, Executes program (before.bindLocal 12 (.signed .i32 0)) initializeLoop .next after ∧
      InitializeInvariant entry.memory (entry.count * 2) after ∧
      CellEffect entry.memory.writes (before.bindLocal 12 (.signed .i32 0)) after :=
  initialize_loop program entry.memory entry.invariant (by omega)

/-- Compose the real `let index = 0; initialize; continuation` scope. The
continuation consumes the derived invariant rather than assuming initialization
already happened. Closing the scope hides fresh cursor writes from the caller. -/
theorem InitializeEntry.continue (entry : InitializeEntry before) (program : Program)
    (continuation : ∀ initializedState, InitializeInvariant entry.memory (entry.count * 2) initializedState →
      ∃ after, Executes program initializedState rest completion after ∧
        CellEffect entry.memory.writes initializedState after) :
    ∃ after, Executes program before (declare 12 (number 0) (.sequence initializeLoop rest)) completion after ∧
      CellEffect (CellSet.singleton entry.outputCell) before after := by
  obtain ⟨initializedState, initializedRun, invariant, initializationEffect⟩ := entry.execute program
  obtain ⟨completed, continuationRun, continuationEffect⟩ := continuation initializedState invariant
  have combined := initializationEffect.trans continuationEffect
  have scopedRun := executesLetLocal (type := i32)
    (show Evaluates program before (number 0) (.signed .i32 0) before from ⟨1, rfl⟩)
    (executesSequence initializedRun continuationRun)
  refine ⟨restoreLocals before completed, scopedRun, ?_⟩
  apply (CellEffect.closeLocal before 12 (.signed .i32 0) entry.wellFormed combined).narrow
  intro cell old changed
  rcases changed with output | cursor
  · exact output
  · exact (Nat.ne_of_lt old cursor).elim

end Lanius.Extraction.SemanticTokens.Collect
