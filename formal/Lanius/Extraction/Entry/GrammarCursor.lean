import Lanius.Extraction.Entry.GrammarString
import Lanius.Semantics.Prefix

namespace Lanius.Extraction.Entry.Grammar

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Extraction.CompactOutput

theorem cursorInvariant (locals : Locals) (memory : Memory locals) (before : State)
    (wellFormed : StateWellFormed before) (fresh : memory.cursorCell = before.nextCell)
    (sourceLocal : before.local? locals.source = some (.slice i32 memory.sourceCell [] 0 memory.source.length))
    (destinationLocal : before.local? locals.destination = some (.slice i32 memory.destinationCell [] 0 memory.untouched.length))
    (sourceContents : before.cellEntry? memory.sourceCell = some {
      id := memory.sourceCell, value := some (.array (signedI32Values memory.source)) })
    (destinationContents : before.cellEntry? memory.destinationCell = some {
      id := memory.destinationCell, value := some (.array (signedI32Values memory.untouched)) })
    (sourceDistinct : locals.cursor ≠ locals.source) (destinationDistinct : locals.cursor ≠ locals.destination) :
    Invariant memory [] (before.bindLocal locals.cursor (.signed .i32 0)) := by
  have sourceRead := (bindLocal_preserves_other_local wellFormed sourceDistinct
    (value := Value.signed .i32 0)).trans sourceLocal
  have destinationRead := (bindLocal_preserves_other_local wellFormed destinationDistinct
    (value := Value.signed .i32 0)).trans destinationLocal
  have sourceKept := ((bindLocal_effect before locals.cursor (.signed .i32 0)).oldCells memory.sourceCell
    (StateWellFormed.cell_lt_next_of_entry wellFormed sourceContents) (by simp [CellSet.empty])).trans sourceContents
  have destinationKept := ((bindLocal_effect before locals.cursor (.signed .i32 0)).oldCells memory.destinationCell
    (StateWellFormed.cell_lt_next_of_entry wellFormed destinationContents) (by simp [CellSet.empty])).trans destinationContents
  refine ⟨bindLocal_preserves_well_formed before _ _ wellFormed, sourceRead, destinationRead,
    sourceKept, ?_, ?_, ?_⟩
  · simpa [Memory.buffer, BufferCopy.buffer] using destinationKept
  · constructor
    · simp [State.cellId?, State.bindLocal, State.bindCell, fresh]
    · simpa [fresh, State.bindLocal] using bindCell_finds_fresh_cell before locals.cursor (some (.signed .i32 0)) wellFormed
  · intro id member cell found changed
    have notCursor : cell ≠ memory.cursorCell := by
      have different : locals.cursor ≠ id := by
        simp only [List.mem_cons, List.not_mem_nil, or_false] at member
        rcases member with rfl | rfl <;> assumption
      have original : before.cellId? id = some cell := by
        simpa [State.cellId?, State.bindLocal, State.bindCell, different] using found
      have old := Lanius.Separation.StateWellFormed.cell_lt_next_of_local_binding id cell wellFormed original
      rw [fresh]
      exact Nat.ne_of_lt old
    have notDestination : cell ≠ memory.destinationCell := by
      simp only [List.mem_cons, List.not_mem_nil, or_false] at member
      rcases member with rfl | rfl
      · exact local_cell_ne_of_distinct_value sourceRead destinationKept (by intro same; cases same) found
      · exact local_cell_ne_of_distinct_value destinationRead destinationKept (by intro same; cases same) found
    exact changed.elim notDestination notCursor

theorem initializeAndLoop (checked : Hex.Checked program) (locals : Locals) (memory : Memory locals)
    (before : State) (continuation : Stmt) (completion : Completion) (post : Lanius.World.State → Prop)
    (wellFormed : StateWellFormed before) (fresh : memory.cursorCell = before.nextCell)
    (sourceLocal : before.local? locals.source = some (.slice i32 memory.sourceCell [] 0 memory.source.length))
    (destinationLocal : before.local? locals.destination = some (.slice i32 memory.destinationCell [] 0 memory.untouched.length))
    (sourceContents : before.cellEntry? memory.sourceCell = some {
      id := memory.sourceCell, value := some (.array (signedI32Values memory.source)) })
    (destinationContents : before.cellEntry? memory.destinationCell = some {
      id := memory.destinationCell, value := some (.array (signedI32Values memory.untouched)) })
    (sourceDistinct : locals.cursor ≠ locals.source) (destinationDistinct : locals.cursor ≠ locals.destination)
    (continuationRun : ∀ middle, Invariant memory memory.values middle →
      CellEffect memory.writes (before.bindLocal locals.cursor (.signed .i32 0)) middle →
      HeapFrame (before.bindLocal locals.cursor (.signed .i32 0)) middle →
      Prefix.Reaches program.core before
        (.letLocal locals.cursor i32 (.value (.signed .i32 0))
          (.sequence (locals.loop checked.source.function.id) continuation)) middle continuation →
      ∃ after, Executes program.core middle continuation completion after ∧ post after.world) :
    ∃ after, Executes program.core before
      (.letLocal locals.cursor i32 (.value (.signed .i32 0))
        (.sequence (locals.loop checked.source.function.id) continuation)) completion after ∧ post after.world := by
  have invariant := cursorInvariant locals memory before wellFormed fresh sourceLocal destinationLocal
    sourceContents destinationContents sourceDistinct destinationDistinct
  obtain ⟨middle, loop, complete, effect, heapFrame⟩ := executesLoop checked locals memory [] memory.values
    (before.bindLocal locals.cursor (.signed .i32 0)) rfl invariant
  obtain ⟨after, continued, satisfied⟩ := continuationRun middle complete effect heapFrame
    (.letLocal (show Evaluates program.core before (.value (.signed .i32 0)) (.signed .i32 0) before from ⟨1, rfl⟩)
      (.sequence loop .here))
  exact ⟨restoreLocals before after, executesLetLocal
    (show Evaluates program.core before (.value (.signed .i32 0)) (.signed .i32 0) before from ⟨1, rfl⟩)
    (executesSequence loop continued), satisfied⟩

end Lanius.Extraction.Entry.Grammar
