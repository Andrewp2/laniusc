import Lanius.Extraction.OutputPacking.Pipeline

namespace Lanius.Extraction.OutputPacking

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

/-- Complete preparation prefix, including the checked rounding expression
and both temporary cursor scopes. The following host write is separate. -/
theorem prepare_buffers (program : Program) (memory : LoopMemory) (locals : LoopLocals)
    (wordCount clearCursor : VarId) (original : List Int)
    (wellFormed : StateWellFormed before)
    (bounded : memory.bytes.length ≤ 8388608) (capacity : memory.words ≤ original.length)
    (tailEq : memory.tail = original.drop memory.words)
    (workspaceRead : before.local? locals.workspace = some
      (.slice (.scalar (.signed .i32)) memory.workspaceCell [] 0 original.length))
    (workspaceContents : before.cellEntry? memory.workspaceCell = some {
      id := memory.workspaceCell, value := some (.array (signedI32Values original)) })
    (inputRead : before.local? locals.input = some
      (.slice (.scalar (.signed .i32)) memory.inputCell [] 0 memory.inputValues.length))
    (inputContents : before.cellEntry? memory.inputCell = some {
      id := memory.inputCell, value := some (.array (signedI32Values memory.inputValues)) })
    (lengthRead : before.local? locals.length = some (.signed .i32 memory.bytes.length))
    (wordDistinct : ∀ localId ∈ [locals.workspace, locals.input, locals.length], wordCount ≠ localId)
    (clearDistinct : ∀ localId ∈ [locals.workspace, wordCount, locals.input, locals.length], clearCursor ≠ localId)
    (packDistinct : ∀ localId ∈ [locals.workspace, locals.input, locals.length], locals.cursor ≠ localId) :
    ∃ after, Executes program before
      (.letLocal wordCount (.scalar (.signed .i32))
        (.binary .divide (.binary .add (.local locals.length) (.value (.signed .i32 3)))
          (.value (.signed .i32 4)))
        (.letLocal clearCursor (.scalar (.signed .i32)) (.value (.signed .i32 0))
          (.sequence (LoopLocals.clearLoop ⟨locals.workspace, 0, clearCursor, wordCount⟩)
            (.letLocal locals.cursor (.scalar (.signed .i32)) (.value (.signed .i32 0)) locals.loop)))) .next after ∧
      after.cellEntry? memory.workspaceCell = some {
        id := memory.workspaceCell, value := some (.array (pack memory.bytes ++ signedI32Values memory.tail)) } ∧
      after.cellEntry? memory.inputCell = some {
        id := memory.inputCell, value := some (.array (signedI32Values memory.inputValues)) } ∧
      ModifiesOnly (CellSet.singleton memory.workspaceCell) before after ∧ StateWellFormed after := by
  let entered := before.bindLocal wordCount (.signed .i32 memory.words)
  have enteredWF : StateWellFormed entered := bindLocal_preserves_well_formed _ _ _ wellFormed
  have workspaceBound := StateWellFormed.cell_lt_next_of_entry wellFormed workspaceContents
  have inputBound := StateWellFormed.cell_lt_next_of_entry wellFormed inputContents
  have keptWorkspace : entered.cellEntry? memory.workspaceCell = some {
      id := memory.workspaceCell, value := some (.array (signedI32Values original)) } :=
    ((bindLocal_effect before wordCount (.signed .i32 memory.words)).oldCells _ workspaceBound
      (by simp [CellSet.empty])).trans workspaceContents
  have keptInput : entered.cellEntry? memory.inputCell = some {
      id := memory.inputCell, value := some (.array (signedI32Values memory.inputValues)) } :=
    ((bindLocal_effect before wordCount (.signed .i32 memory.words)).oldCells _ inputBound
      (by simp [CellSet.empty])).trans inputContents
  let clear : ClearMemory := {
    workspaceCell := memory.workspaceCell, cursorCell := entered.nextCell,
    original, words := memory.words, capacity,
    bounded := by have bound := (output_word_bounds memory.bytes.length bounded).2; exact Nat.le_trans bound (by decide)
    distinct := Nat.ne_of_lt (StateWellFormed.cell_lt_next_of_entry enteredWF keptWorkspace) }
  obtain ⟨packed, run, output, input, effect, packedWF⟩ := clear_setup_then_pack program clear
    ⟨locals.workspace, 0, clearCursor, wordCount⟩ memory locals enteredWF rfl rfl rfl rfl tailEq
    ((bindLocal_preserves_other_local wellFormed (wordDistinct _ (by simp))).trans workspaceRead)
    keptWorkspace (bindLocal_finds_local _ _ _ wellFormed)
    ((bindLocal_preserves_other_local wellFormed (wordDistinct _ (by simp))).trans inputRead)
    keptInput ((bindLocal_preserves_other_local wellFormed (wordDistinct _ (by simp))).trans lengthRead)
    clearDistinct packDistinct
  have combined := (bindLocal_effect before wordCount (.signed .i32 memory.words)).trans effect.toStoreEffect
  have closed : ModifiesOnly (CellSet.singleton memory.workspaceCell) before (restoreLocals before packed) :=
    combined.restoreLocals.hideFreshWritesExcept (by
      intro cell changed
      exact Or.inl (changed.elim False.elim id))
  exact ⟨restoreLocals before packed,
    executesLetLocal (evaluates_output_words program before locals.length memory.bytes.length bounded lengthRead) run,
    output, input, closed, combined.restoreLocals_wellFormed wellFormed packedWF⟩

theorem preparation_local_binding (memory : LoopMemory) (locals : LoopLocals)
    (wordCount clearCursor localId : VarId) {before cleared packed : State}
    {clearWrites packWrites : CellSet}
    (wordDifferent : wordCount ≠ localId) (clearDifferent : clearCursor ≠ localId)
    (packDifferent : locals.cursor ≠ localId)
    (clearing : ModifiesOnly clearWrites
      ((before.bindLocal wordCount (.signed .i32 memory.words)).bindLocal clearCursor (.signed .i32 0)) cleared)
    (packing : ModifiesOnly packWrites (cleared.bindLocal locals.cursor (.signed .i32 0)) packed) :
    packed.cellId? localId = before.cellId? localId := by
  calc
    packed.cellId? localId = (cleared.bindLocal locals.cursor (.signed .i32 0)).cellId? localId := by
      simp only [State.cellId?, packing.locals]
    _ = cleared.cellId? localId := bindLocal_preserves_other_cellId _ _ _ _ packDifferent
    _ = ((before.bindLocal wordCount (.signed .i32 memory.words)).bindLocal clearCursor (.signed .i32 0)).cellId? localId := by
      simp only [State.cellId?, clearing.locals]
    _ = (before.bindLocal wordCount (.signed .i32 memory.words)).cellId? localId :=
      bindLocal_preserves_other_cellId _ _ _ _ clearDifferent
    _ = before.cellId? localId := bindLocal_preserves_other_cellId _ _ _ _ wordDifferent

theorem preparation_effect (memory : LoopMemory) (locals : LoopLocals)
    (wordCount clearCursor : VarId) {before cleared packed : State}
    (clear : ClearMemory) (next : LoopMemory)
    (clearSpace : clear.workspaceCell = memory.workspaceCell)
    (clearFresh : clear.cursorCell = (before.bindLocal wordCount (.signed .i32 memory.words)).nextCell)
    (packFresh : next.cursorCell = cleared.nextCell)
    (packSpace : next.workspaceCell = memory.workspaceCell)
    (clearing : ModifiesOnly clear.writes
      ((before.bindLocal wordCount (.signed .i32 memory.words)).bindLocal clearCursor (.signed .i32 0)) cleared)
    (packing : ModifiesOnly next.writes (cleared.bindLocal locals.cursor (.signed .i32 0)) packed) :
    StoreEffect (CellSet.singleton memory.workspaceCell) before packed := by
  have first := bindLocal_effect before wordCount (.signed .i32 memory.words)
  have second := bindLocal_effect (before.bindLocal wordCount (.signed .i32 memory.words)) clearCursor (.signed .i32 0)
  have prefixEffect := (first.trans second).trans clearing.toStoreEffect
  have combined := (prefixEffect.trans (bindLocal_effect cleared locals.cursor (.signed .i32 0))).trans packing.toStoreEffect
  apply combined.hideFreshWritesExcept
  intro cell changed
  by_cases workspace : cell = memory.workspaceCell
  · exact Or.inl workspace
  · right
    have monotone := prefixEffect.nextCell
    have fresh : before.nextCell ≤ clear.cursorCell := by
      rw [clearFresh]
      exact first.nextCell
    simp only [CellSet.union, CellSet.empty, CellSet.singleton, ClearMemory.writes,
      LoopMemory.writes, false_or, or_false] at changed
    rcases changed with (same | same) | same | same
    · exact False.elim (workspace (same.trans clearSpace))
    · exact same ▸ fresh
    · exact False.elim (workspace (same.trans packSpace))
    · rw [same, packFresh]
      exact monotone

/-- Execute the checked preparation with its continuation inside all scopes. -/
theorem prepare_with_continuation (program : Program) (memory : LoopMemory) (locals : LoopLocals)
    (wordCount clearCursor : VarId) (original : List Int)
    {continuation : Stmt} {completion : Completion} {post : Lanius.World.State → Prop}
    (wellFormed : StateWellFormed before)
    (bounded : memory.bytes.length ≤ 8388608) (capacity : memory.words ≤ original.length)
    (tailEq : memory.tail = original.drop memory.words)
    (workspaceRead : before.local? locals.workspace = some
      (.slice (.scalar (.signed .i32)) memory.workspaceCell [] 0 original.length))
    (workspaceContents : before.cellEntry? memory.workspaceCell = some {
      id := memory.workspaceCell, value := some (.array (signedI32Values original)) })
    (inputRead : before.local? locals.input = some
      (.slice (.scalar (.signed .i32)) memory.inputCell [] 0 memory.inputValues.length))
    (inputContents : before.cellEntry? memory.inputCell = some {
      id := memory.inputCell, value := some (.array (signedI32Values memory.inputValues)) })
    (lengthRead : before.local? locals.length = some (.signed .i32 memory.bytes.length))
    (wordDistinct : ∀ localId ∈ [locals.workspace, locals.input, locals.length], wordCount ≠ localId)
    (clearDistinct : ∀ localId ∈ [locals.workspace, wordCount, locals.input, locals.length], clearCursor ≠ localId)
    (packDistinct : ∀ localId ∈ [locals.workspace, locals.input, locals.length], locals.cursor ≠ localId)
    (continueRun : ∀ (clear : ClearMemory) (next : LoopMemory) cleared packed,
      clear.workspaceCell = memory.workspaceCell →
      clear.cursorCell = (before.bindLocal wordCount (.signed .i32 memory.words)).nextCell →
      next.cursorCell = cleared.nextCell →
      next.workspaceCell = memory.workspaceCell → next.inputCell = memory.inputCell →
      next.bytes = memory.bytes → next.tail = memory.tail → next.inputTail = memory.inputTail →
      ModifiesOnly clear.writes
        ((before.bindLocal wordCount (.signed .i32 memory.words)).bindLocal clearCursor (.signed .i32 0)) cleared →
      LoopInvariant next locals next.bytes packed →
      ModifiesOnly next.writes (cleared.bindLocal locals.cursor (.signed .i32 0)) packed →
      StoreEffect (CellSet.singleton memory.workspaceCell) before packed →
      ∃ after, Executes program packed continuation completion after ∧ post after.world) :
    ∃ after, Executes program before
      (Preparation.statement ⟨locals, wordCount, clearCursor, continuation⟩) completion after ∧ post after.world := by
  let entered := before.bindLocal wordCount (.signed .i32 memory.words)
  have enteredWF : StateWellFormed entered := bindLocal_preserves_well_formed _ _ _ wellFormed
  have workspaceBound := StateWellFormed.cell_lt_next_of_entry wellFormed workspaceContents
  have inputBound := StateWellFormed.cell_lt_next_of_entry wellFormed inputContents
  have keptWorkspace : entered.cellEntry? memory.workspaceCell = some {
      id := memory.workspaceCell, value := some (.array (signedI32Values original)) } :=
    ((bindLocal_effect before wordCount (.signed .i32 memory.words)).oldCells _ workspaceBound
      (by simp [CellSet.empty])).trans workspaceContents
  have keptInput : entered.cellEntry? memory.inputCell = some {
      id := memory.inputCell, value := some (.array (signedI32Values memory.inputValues)) } :=
    ((bindLocal_effect before wordCount (.signed .i32 memory.words)).oldCells _ inputBound
      (by simp [CellSet.empty])).trans inputContents
  let clear : ClearMemory := {
    workspaceCell := memory.workspaceCell, cursorCell := entered.nextCell,
    original, words := memory.words, capacity,
    bounded := by have bound := (output_word_bounds memory.bytes.length bounded).2; exact Nat.le_trans bound (by decide)
    distinct := Nat.ne_of_lt (StateWellFormed.cell_lt_next_of_entry enteredWF keptWorkspace) }
  obtain ⟨packed, run, output⟩ := clear_setup_then_continue program clear
    ⟨locals.workspace, 0, clearCursor, wordCount⟩ memory locals enteredWF rfl rfl rfl rfl tailEq
    ((bindLocal_preserves_other_local wellFormed (wordDistinct _ (by simp))).trans workspaceRead)
    keptWorkspace (bindLocal_finds_local _ _ _ wellFormed)
    ((bindLocal_preserves_other_local wellFormed (wordDistinct _ (by simp))).trans inputRead)
    keptInput ((bindLocal_preserves_other_local wellFormed (wordDistinct _ (by simp))).trans lengthRead)
    clearDistinct packDistinct
    (fun next cleared packed fresh workspace input bytes tail inputTail effect invariant writes =>
      continueRun clear next cleared packed rfl rfl fresh workspace input bytes tail inputTail effect invariant writes
        (preparation_effect memory locals wordCount clearCursor clear next rfl rfl fresh workspace effect writes))
  exact ⟨restoreLocals before packed,
    executesLetLocal (evaluates_output_words program before locals.length memory.bytes.length bounded lengthRead) run, output⟩

end Lanius.Extraction.OutputPacking
