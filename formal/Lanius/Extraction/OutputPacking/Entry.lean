import Lanius.Extraction.OutputPacking.Preparation
import Lanius.Separation.SliceStore

namespace Lanius.Extraction.OutputPacking

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

/-- Old scalar/slice locals survive clear-cursor allocation and cannot alias
either write target of the clear loop. This derives its caller frame. -/
theorem clear_cursor_frame (memory : ClearMemory) (cursor localId : VarId)
    (wellFormed : StateWellFormed state) (fresh : memory.cursorCell = state.nextCell)
    (different : cursor ≠ localId)
    (read : state.local? localId = some value)
    (contents : state.cellEntry? memory.workspaceCell = some {
      id := memory.workspaceCell, value := some (.array (signedI32Values memory.original)) })
    (notArray : value ≠ .array (signedI32Values memory.original)) :
    (state.bindLocal cursor (.signed .i32 0)).local? localId = some value ∧
    ∀ cell, (state.bindLocal cursor (.signed .i32 0)).cellId? localId = some cell →
      ¬ memory.writes cell := by
  refine ⟨(bindLocal_preserves_other_local wellFormed different).trans read, ?_⟩
  intro cell binding
  rw [bindLocal_preserves_other_cellId state cursor localId (.signed .i32 0) different] at binding
  have old := StateWellFormed.cell_lt_next_of_local_binding localId cell wellFormed binding
  have notWorkspace := local_cell_ne_of_distinct_value read contents notArray binding
  simp only [ClearMemory.writes, CellSet.union, CellSet.singleton, fresh]
  exact fun changed => changed.elim notWorkspace (Nat.ne_of_lt old)

theorem clear_cursor_input (memory : ClearMemory) (cursor : VarId)
    (wellFormed : StateWellFormed state) (fresh : memory.cursorCell = state.nextCell)
    (contents : state.cellEntry? inputCell = some { id := inputCell, value := some value })
    (separate : inputCell ≠ memory.workspaceCell) :
    (state.bindLocal cursor (.signed .i32 0)).cellEntry? inputCell =
      some { id := inputCell, value := some value } ∧ ¬ memory.writes inputCell := by
  have old := StateWellFormed.cell_lt_next_of_entry wellFormed contents
  refine ⟨((bindLocal_effect state cursor (.signed .i32 0)).oldCells inputCell old
    (by simp [CellSet.empty])).trans contents, ?_⟩
  simp only [ClearMemory.writes, CellSet.union, CellSet.singleton, fresh]
  exact fun changed => changed.elim separate (Nat.ne_of_lt old)

/-- Allocate the source's clear cursor and derive its loop invariant from
ordinary workspace contents and the computed word-count local. -/
theorem clear_cursor_entry (memory : ClearMemory) (locals : LoopLocals)
    (wellFormed : StateWellFormed state)
    (fresh : memory.cursorCell = state.nextCell)
    (workspaceRead : state.local? locals.workspace = some
      (.slice (.scalar (.signed .i32)) memory.workspaceCell [] 0 memory.original.length))
    (workspaceContents : state.cellEntry? memory.workspaceCell = some {
      id := memory.workspaceCell, value := some (.array (signedI32Values memory.original)) })
    (lengthRead : state.local? locals.length = some (.signed .i32 memory.words))
    (workspaceDistinct : locals.cursor ≠ locals.workspace)
    (lengthDistinct : locals.cursor ≠ locals.length) :
    ClearInvariant memory locals 0 (state.bindLocal locals.cursor (.signed .i32 0)) := by
  have workspaceBound := StateWellFormed.cell_lt_next_of_entry wellFormed workspaceContents
  refine ⟨bindLocal_preserves_well_formed _ _ _ wellFormed,
    (bindLocal_preserves_other_local wellFormed workspaceDistinct).trans workspaceRead,
    ?_, ?_, (bindLocal_preserves_other_local wellFormed lengthDistinct).trans lengthRead, ?_⟩
  · have preserved := ((bindLocal_effect state locals.cursor (.signed .i32 0)).oldCells
      memory.workspaceCell workspaceBound (by simp [CellSet.empty])).trans workspaceContents
    simpa only [clearedPrefix, List.replicate_zero, List.drop_zero, List.nil_append] using preserved
  · simpa [fresh] using bindLocal_owns_fresh state locals.cursor (.signed .i32 0) wellFormed
  · intro localId member cell binding
    have different : locals.cursor ≠ localId := by
      rcases List.mem_cons.mp member with rfl | rest
      · exact workspaceDistinct
      · have same := List.mem_singleton.mp rest
        exact same ▸ lengthDistinct
    rw [bindLocal_preserves_other_cellId state locals.cursor localId (.signed .i32 0) different] at binding
    have old := StateWellFormed.cell_lt_next_of_local_binding localId cell wellFormed binding
    have notWorkspace : cell ≠ memory.workspaceCell := by
      rcases List.mem_cons.mp member with rfl | rest
      · exact local_cell_ne_of_distinct_value workspaceRead workspaceContents (by intro impossible; cases impossible) binding
      · have same := List.mem_singleton.mp rest
        subst localId
        exact local_cell_ne_of_distinct_value lengthRead workspaceContents (by intro impossible; cases impossible) binding
    simp only [ClearMemory.writes, CellSet.union, CellSet.singleton, fresh]
    exact fun changed => changed.elim notWorkspace (Nat.ne_of_lt old)

theorem packing_cursor_entry (memory : LoopMemory) (locals : LoopLocals)
    (wellFormed : StateWellFormed state)
    (fresh : memory.cursorCell = state.nextCell)
    (workspaceRead : state.local? locals.workspace = some
      (.slice (.scalar (.signed .i32)) memory.workspaceCell [] 0 (memory.words + memory.tail.length)))
    (workspaceContents : state.cellEntry? memory.workspaceCell = some {
      id := memory.workspaceCell,
      value := some (.array (workspace memory.words [] (signedI32Values memory.tail))) })
    (inputRead : state.local? locals.input = some
      (.slice (.scalar (.signed .i32)) memory.inputCell [] 0 memory.inputValues.length))
    (inputContents : state.cellEntry? memory.inputCell = some {
      id := memory.inputCell, value := some (.array (signedI32Values memory.inputValues)) })
    (lengthRead : state.local? locals.length = some (.signed .i32 memory.bytes.length))
    (distinct : ∀ localId ∈ [locals.workspace, locals.input, locals.length], locals.cursor ≠ localId) :
    LoopInvariant memory locals [] (state.bindLocal locals.cursor (.signed .i32 0)) := by
  have workspaceBound := StateWellFormed.cell_lt_next_of_entry wellFormed workspaceContents
  have inputBound := StateWellFormed.cell_lt_next_of_entry wellFormed inputContents
  refine ⟨bindLocal_preserves_well_formed _ _ _ wellFormed,
    (bindLocal_preserves_other_local wellFormed (distinct _ (by simp))).trans workspaceRead,
    ?_, (bindLocal_preserves_other_local wellFormed (distinct _ (by simp))).trans inputRead,
    ?_, ?_, (bindLocal_preserves_other_local wellFormed (distinct _ (by simp))).trans lengthRead, ?_⟩
  · exact ((bindLocal_effect state locals.cursor (.signed .i32 0)).oldCells
      memory.workspaceCell workspaceBound (by simp [CellSet.empty])).trans workspaceContents
  · exact ((bindLocal_effect state locals.cursor (.signed .i32 0)).oldCells
      memory.inputCell inputBound (by simp [CellSet.empty])).trans inputContents
  · simpa [fresh] using bindLocal_owns_fresh state locals.cursor (.signed .i32 0) wellFormed
  · intro localId member cell binding
    rw [bindLocal_preserves_other_cellId state locals.cursor localId (.signed .i32 0) (distinct _ member)] at binding
    have old := StateWellFormed.cell_lt_next_of_local_binding localId cell wellFormed binding
    have notWorkspace : cell ≠ memory.workspaceCell := by
      simp only [List.mem_cons, List.not_mem_nil, or_false] at member
      rcases member with rfl | rfl | rfl
      · exact local_cell_ne_of_distinct_value workspaceRead workspaceContents (by intro impossible; cases impossible) binding
      · exact local_cell_ne_of_distinct_value inputRead workspaceContents (by intro impossible; cases impossible) binding
      · exact local_cell_ne_of_distinct_value lengthRead workspaceContents (by intro impossible; cases impossible) binding
    simp only [LoopMemory.writes, CellSet.union, CellSet.singleton, fresh]
    exact fun changed => changed.elim notWorkspace (Nat.ne_of_lt old)

/-- The completed clear phase supplies the packing workspace and its capacity;
only the still-live source/length locals and fresh cursor are needed. -/
theorem cleared_packing_entry (memory : LoopMemory) (locals : LoopLocals)
    (cleared : ClearInvariant clear clearLocals clear.words state)
    (sameLocal : clearLocals.workspace = locals.workspace)
    (sameCell : clear.workspaceCell = memory.workspaceCell)
    (sameWords : clear.words = memory.words)
    (sameTail : memory.tail = clear.original.drop clear.words)
    (fresh : memory.cursorCell = state.nextCell)
    (inputRead : state.local? locals.input = some
      (.slice (.scalar (.signed .i32)) memory.inputCell [] 0 memory.inputValues.length))
    (inputContents : state.cellEntry? memory.inputCell = some {
      id := memory.inputCell, value := some (.array (signedI32Values memory.inputValues)) })
    (lengthRead : state.local? locals.length = some (.signed .i32 memory.bytes.length))
    (distinct : ∀ localId ∈ [locals.workspace, locals.input, locals.length], locals.cursor ≠ localId) :
    LoopInvariant memory locals [] (state.bindLocal locals.cursor (.signed .i32 0)) ∧
    ∀ program : Program, ∃ after,
      Executes program state
        (.letLocal locals.cursor (.scalar (.signed .i32)) (.value (.signed .i32 0)) locals.loop) .next after ∧
      after.cellEntry? memory.workspaceCell = some {
        id := memory.workspaceCell,
        value := some (.array (pack memory.bytes ++ signedI32Values memory.tail)) } ∧
      after.cellEntry? memory.inputCell = some {
        id := memory.inputCell, value := some (.array (signedI32Values memory.inputValues)) } ∧
      ModifiesOnly (CellSet.singleton memory.workspaceCell) state after ∧ StateWellFormed after := by
  have initial : LoopInvariant memory locals [] (state.bindLocal locals.cursor (.signed .i32 0)) := by
    apply packing_cursor_entry memory locals cleared.wellFormed fresh
    · have size : memory.words + memory.tail.length = clear.original.length := by
        rw [sameTail, List.length_drop, ← sameWords]
        have room := clear.capacity
        omega
      simpa only [sameLocal, sameCell, size] using cleared.workspaceLocal
    · have contents := cleared.initial_packing_contents
      rw [← sameTail] at contents
      simpa only [sameCell, sameWords] using contents
    · exact inputRead
    · exact inputContents
    · exact lengthRead
    · exact distinct
  refine ⟨initial, ?_⟩
  intro program
  obtain ⟨packed, run, complete, effect⟩ := executes_packing_loop program memory locals [] memory.bytes
    (state.bindLocal locals.cursor (.signed .i32 0)) rfl initial
  have combined := (bindLocal_effect state locals.cursor (.signed .i32 0)).trans effect.toStoreEffect
  have closed : ModifiesOnly (CellSet.singleton memory.workspaceCell) state (restoreLocals state packed) :=
    combined.restoreLocals.hideFreshWritesExcept (by
      intro cell changed
      rcases changed with impossible | changed
      · exact False.elim impossible
      · rcases changed with workspace | cursor
        · exact Or.inl workspace
        · exact Or.inr (by rw [show cell = state.nextCell from cursor.trans fresh]; exact Nat.le_refl _))
  exact ⟨restoreLocals state packed, executesLetLocal (show Evaluates program state
      (.value (.signed .i32 0)) (.signed .i32 0) state from ⟨1, rfl⟩) run,
    complete.complete_contents, complete.inputContents, closed,
    combined.restoreLocals_wellFormed cleared.wellFormed complete.wellFormed⟩

/-- Run the continuation while the packing cursor is still in scope. This
matches the source nesting; closing the scope before the host call would not. -/
theorem packing_then_continue (program : Program) (memory : LoopMemory) (locals : LoopLocals)
    {state : State} {continuation : Stmt} {completion : Completion} {post : Lanius.World.State → Prop}
    (initial : LoopInvariant memory locals [] (state.bindLocal locals.cursor (.signed .i32 0)))
    (continueRun : ∀ packed,
      LoopInvariant memory locals memory.bytes packed →
      ModifiesOnly memory.writes (state.bindLocal locals.cursor (.signed .i32 0)) packed →
      ∃ after, Executes program packed continuation completion after ∧ post after.world) :
    ∃ after, Executes program state
      (.letLocal locals.cursor (.scalar (.signed .i32)) (.value (.signed .i32 0))
        (.sequence locals.loop continuation)) completion after ∧ post after.world := by
  obtain ⟨packed, run, complete, effect⟩ := executes_packing_loop program memory locals [] memory.bytes
    (state.bindLocal locals.cursor (.signed .i32 0)) rfl initial
  obtain ⟨after, continued, output⟩ := continueRun packed complete effect
  exact ⟨restoreLocals state after, executesLetLocal
    (show Evaluates program state (.value (.signed .i32 0)) (.signed .i32 0) state from ⟨1, rfl⟩)
    (executesSequence run continued), output⟩

end Lanius.Extraction.OutputPacking
