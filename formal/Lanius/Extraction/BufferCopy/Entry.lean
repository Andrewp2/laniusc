import Lanius.Extraction.BufferCopy.Loop

namespace Lanius.Extraction.BufferCopy

open Lanius Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

/-- Ordinary caller storage before the source binds its copy cursor. No loop
invariant or local-cell separation certificate is required from the caller. -/
structure Entry (memory : Memory locals) (state : State) : Prop where
  wellFormed : StateWellFormed state
  sourceLocal : state.local? locals.source = some
    (.slice (.scalar (.signed .i32)) memory.sourceCell [] 0 memory.source.length)
  destinationLocal : state.local? locals.destination = some
    (.slice (.scalar (.signed .i32)) memory.destinationCell [] 0 memory.untouched.length)
  sourceContents : state.cellEntry? memory.sourceCell = some {
    id := memory.sourceCell, value := some (.array (signedI32Values memory.source)) }
  destinationContents : state.cellEntry? memory.destinationCell = some {
    id := memory.destinationCell, value := some (.array (signedI32Values memory.untouched)) }
  count : state.local? locals.count = some (.signed .i32 memory.count)
  cursorDistinct : ∀ id ∈ [locals.source, locals.destination, locals.count], locals.cursor ≠ id
  cursorFresh : memory.cursorCell = state.nextCell

theorem Entry.stable_local {locals : Locals} {memory : Memory locals} {before : State}
    (entry : Entry memory before) {id : VarId} {value : Value}
    (found : before.local? id = some value) (notCursor : locals.cursor ≠ id)
    (notArray : value ≠ .array (signedI32Values memory.untouched)) :
    ∀ cell, (before.bindLocal locals.cursor (.signed .i32 0)).cellId? id = some cell →
      ¬ memory.writes cell := by
  intro cell binding changed
  have original : before.cellId? id = some cell := by
    simpa only [bindLocal_preserves_other_cellId before locals.cursor id
      (.signed .i32 0) notCursor] using binding
  rcases changed with destination | cursor
  · exact local_cell_ne_of_distinct_value found entry.destinationContents notArray original destination
  · have old := StateWellFormed.cell_lt_next_of_local_binding id cell entry.wellFormed original
    exact Nat.ne_of_lt old (cursor.trans entry.cursorFresh)

theorem Entry.initialize {locals : Locals} {memory : Memory locals} {before : State}
    (entry : Entry memory before) :
    Invariant memory [] (before.bindLocal locals.cursor (.signed .i32 0)) := by
  have bindingEffect := bindLocal_effect before locals.cursor (.signed .i32 0)
  have sourceReady := (bindingEffect.oldCells memory.sourceCell
    (StateWellFormed.cell_lt_next_of_entry entry.wellFormed entry.sourceContents)
    (by simp [CellSet.empty])).trans entry.sourceContents
  have destinationReady := (bindingEffect.oldCells memory.destinationCell
    (StateWellFormed.cell_lt_next_of_entry entry.wellFormed entry.destinationContents)
    (by simp [CellSet.empty])).trans entry.destinationContents
  refine ⟨bindLocal_preserves_well_formed before _ _ entry.wellFormed,
    (bindLocal_preserves_other_local entry.wellFormed (entry.cursorDistinct _ (by simp))).trans entry.sourceLocal,
    (bindLocal_preserves_other_local entry.wellFormed (entry.cursorDistinct _ (by simp))).trans entry.destinationLocal,
    sourceReady, destinationReady, ?_,
    (bindLocal_preserves_other_local entry.wellFormed (entry.cursorDistinct _ (by simp))).trans entry.count, ?_⟩
  · simpa [entry.cursorFresh] using
      bindLocal_owns_fresh before locals.cursor (.signed .i32 0) entry.wellFormed
  · intro id member cell found changed
    have original : before.cellId? id = some cell := by
      simpa only [bindLocal_preserves_other_cellId before locals.cursor id
        (.signed .i32 0) (entry.cursorDistinct id member)] using found
    rcases changed with destination | cursor
    · have distinct : cell ≠ memory.destinationCell := by
        simp only [List.mem_cons, List.not_mem_nil, or_false] at member
        rcases member with rfl | rfl | rfl
        · exact local_cell_ne_of_distinct_value entry.sourceLocal entry.destinationContents
            (by intro same; cases same) original
        · exact local_cell_ne_of_distinct_value entry.destinationLocal entry.destinationContents
            (by intro same; cases same) original
        · exact local_cell_ne_of_distinct_value entry.count entry.destinationContents
            (by intro same; cases same) original
      exact distinct destination
    · have old := StateWellFormed.cell_lt_next_of_local_binding id cell entry.wellFormed original
      have fresh : cell = before.nextCell := cursor.trans entry.cursorFresh
      exact Nat.ne_of_lt old fresh

/-- Bind the cursor, execute the whole loop, and restore the caller's locals.
Cursor writes are fresh and disappear from the caller-visible write set. -/
theorem executes_scoped_loop (program : Program) (locals : Locals) (memory : Memory locals)
    (before : State) (entry : Entry memory before) :
    ∃ after, Executes program before
        (.letLocal locals.cursor (.scalar (.signed .i32)) (.value (.signed .i32 0)) locals.loop)
        .next after ∧
      after.cellEntry? memory.sourceCell = some {
        id := memory.sourceCell, value := some (.array (signedI32Values memory.source)) } ∧
      after.cellEntry? memory.destinationCell = some {
        id := memory.destinationCell, value := some (.array (signedI32Values (buffer memory.untouched memory.values))) } ∧
      CellEffect (CellSet.singleton memory.destinationCell) before after := by
  obtain ⟨completed, ran, complete, effect⟩ := executes_loop program locals memory [] memory.values
    (before.bindLocal locals.cursor (.signed .i32 0)) rfl entry.initialize
  have scopedRun := executesLetLocal (type := .scalar (.signed .i32))
    (show Evaluates program before (.value (.signed .i32 0)) (.signed .i32 0) before from ⟨1, rfl⟩) ran
  have closed := CellEffect.closeLocal before locals.cursor (.signed .i32 0) entry.wellFormed effect
  refine ⟨restoreLocals before completed, scopedRun, complete.sourceContents, complete.destinationContents, ?_⟩
  apply closed.narrow
  intro cell old written
  rcases written with destination | cursor
  · exact destination
  · have fresh : cell = before.nextCell := cursor.trans entry.cursorFresh
    exact (Nat.ne_of_lt old fresh).elim

end Lanius.Extraction.BufferCopy
