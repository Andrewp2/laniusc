import Lanius.Extraction.OutputPacking.Entry

namespace Lanius.Extraction.OutputPacking

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

/-- Execute both loops. Clearing supplies the packing invariant; neither
loop execution nor an already-cleared buffer is assumed. -/
theorem clear_then_pack (program : Program) (memory : LoopMemory) (locals : LoopLocals)
    (initial : ClearInvariant clear clearLocals 0 before)
    (sameLocal : clearLocals.workspace = locals.workspace)
    (sameCell : clear.workspaceCell = memory.workspaceCell)
    (sameWords : clear.words = memory.words)
    (sameTail : memory.tail = clear.original.drop clear.words)
    (inputRead : before.local? locals.input = some
      (.slice (.scalar (.signed .i32)) memory.inputCell [] 0 memory.inputValues.length))
    (inputContents : before.cellEntry? memory.inputCell = some {
      id := memory.inputCell, value := some (.array (signedI32Values memory.inputValues)) })
    (lengthRead : before.local? locals.length = some (.signed .i32 memory.bytes.length))
    (inputSeparate : ¬ clear.writes memory.inputCell)
    (stable : ∀ localId ∈ [locals.input, locals.length],
      ∀ cell, before.cellId? localId = some cell → ¬ clear.writes cell)
    (distinct : ∀ localId ∈ [locals.workspace, locals.input, locals.length], locals.cursor ≠ localId) :
    ∃ after, Executes program before
      (.sequence clearLocals.clearLoop
        (.letLocal locals.cursor (.scalar (.signed .i32)) (.value (.signed .i32 0)) locals.loop)) .next after ∧
      after.cellEntry? memory.workspaceCell = some {
        id := memory.workspaceCell, value := some (.array (pack memory.bytes ++ signedI32Values memory.tail)) } ∧
      after.cellEntry? memory.inputCell = some {
        id := memory.inputCell, value := some (.array (signedI32Values memory.inputValues)) } ∧
      ModifiesOnly clear.writes before after ∧ StateWellFormed after := by
  obtain ⟨cleared, clearRun, complete, effect⟩ := executes_clear_loop program clear clearLocals 0 before
    (Nat.zero_le _) initial
  have keptInput := effect.preserves_entry initial.wellFormed inputContents inputSeparate
  have keptRead := effect.preserves_local initial.wellFormed inputRead (stable _ (by simp))
  have keptLength := effect.preserves_local initial.wellFormed lengthRead (stable _ (by simp))
  have workspaceBound := StateWellFormed.cell_lt_next_of_entry complete.wellFormed complete.contents
  have inputBound := StateWellFormed.cell_lt_next_of_entry complete.wellFormed keptInput
  let next : LoopMemory := { memory with
    cursorCell := cleared.nextCell
    workspace_cursor := by rw [← sameCell]; exact Nat.ne_of_lt workspaceBound
    input_cursor := Nat.ne_of_lt inputBound }
  have ready := cleared_packing_entry next locals complete sameLocal sameCell sameWords sameTail rfl
    keptRead keptInput keptLength distinct
  obtain ⟨packed, packedRun, output, input, packedEffect, packedWF⟩ := ready.2 program
  have framed : ModifiesOnly clear.writes cleared packed := packedEffect.weaken (by
    intro cell changed
    exact Or.inl (changed.trans sameCell.symm))
  exact ⟨packed, executesSequence clearRun packedRun, output, input, effect.trans_same framed, packedWF⟩

theorem clear_then_continue (program : Program) (memory : LoopMemory) (locals : LoopLocals)
    {continuation : Stmt} {completion : Completion} {post : Lanius.World.State → Prop}
    (initial : ClearInvariant clear clearLocals 0 before)
    (sameLocal : clearLocals.workspace = locals.workspace)
    (sameCell : clear.workspaceCell = memory.workspaceCell)
    (sameWords : clear.words = memory.words)
    (sameTail : memory.tail = clear.original.drop clear.words)
    (inputRead : before.local? locals.input = some
      (.slice (.scalar (.signed .i32)) memory.inputCell [] 0 memory.inputValues.length))
    (inputContents : before.cellEntry? memory.inputCell = some {
      id := memory.inputCell, value := some (.array (signedI32Values memory.inputValues)) })
    (lengthRead : before.local? locals.length = some (.signed .i32 memory.bytes.length))
    (inputSeparate : ¬ clear.writes memory.inputCell)
    (stable : ∀ localId ∈ [locals.input, locals.length],
      ∀ cell, before.cellId? localId = some cell → ¬ clear.writes cell)
    (distinct : ∀ localId ∈ [locals.workspace, locals.input, locals.length], locals.cursor ≠ localId)
    (continueRun : ∀ (next : LoopMemory) cleared packed,
      next.cursorCell = cleared.nextCell →
      next.workspaceCell = memory.workspaceCell → next.inputCell = memory.inputCell →
      next.bytes = memory.bytes → next.tail = memory.tail → next.inputTail = memory.inputTail →
      ModifiesOnly clear.writes before cleared →
      LoopInvariant next locals next.bytes packed →
      ModifiesOnly next.writes (cleared.bindLocal locals.cursor (.signed .i32 0)) packed →
      ∃ after, Executes program packed continuation completion after ∧ post after.world) :
    ∃ after, Executes program before
      (.sequence clearLocals.clearLoop
        (.letLocal locals.cursor (.scalar (.signed .i32)) (.value (.signed .i32 0))
          (.sequence locals.loop continuation))) completion after ∧ post after.world := by
  obtain ⟨cleared, clearRun, complete, effect⟩ := executes_clear_loop program clear clearLocals 0 before
    (Nat.zero_le _) initial
  have keptInput := effect.preserves_entry initial.wellFormed inputContents inputSeparate
  have keptRead := effect.preserves_local initial.wellFormed inputRead (stable _ (by simp))
  have keptLength := effect.preserves_local initial.wellFormed lengthRead (stable _ (by simp))
  have workspaceBound := StateWellFormed.cell_lt_next_of_entry complete.wellFormed complete.contents
  have inputBound := StateWellFormed.cell_lt_next_of_entry complete.wellFormed keptInput
  let next : LoopMemory := { memory with
    cursorCell := cleared.nextCell
    workspace_cursor := by rw [← sameCell]; exact Nat.ne_of_lt workspaceBound
    input_cursor := Nat.ne_of_lt inputBound }
  have ready := (cleared_packing_entry next locals complete sameLocal sameCell sameWords sameTail rfl
    keptRead keptInput keptLength distinct).1
  obtain ⟨after, run, output⟩ := packing_then_continue program next locals ready
    (fun packed invariant writes => continueRun next cleared packed rfl rfl rfl rfl rfl rfl
      effect invariant writes)
  exact ⟨after, executesSequence clearRun run, output⟩

theorem clear_setup_then_pack (program : Program) (clear : ClearMemory) (clearLocals : LoopLocals)
    (memory : LoopMemory) (locals : LoopLocals)
    (wellFormed : StateWellFormed before) (fresh : clear.cursorCell = before.nextCell)
    (sameLocal : clearLocals.workspace = locals.workspace)
    (sameCell : clear.workspaceCell = memory.workspaceCell)
    (sameWords : clear.words = memory.words)
    (sameTail : memory.tail = clear.original.drop clear.words)
    (workspaceRead : before.local? clearLocals.workspace = some
      (.slice (.scalar (.signed .i32)) clear.workspaceCell [] 0 clear.original.length))
    (workspaceContents : before.cellEntry? clear.workspaceCell = some {
      id := clear.workspaceCell, value := some (.array (signedI32Values clear.original)) })
    (wordsRead : before.local? clearLocals.length = some (.signed .i32 clear.words))
    (inputRead : before.local? locals.input = some
      (.slice (.scalar (.signed .i32)) memory.inputCell [] 0 memory.inputValues.length))
    (inputContents : before.cellEntry? memory.inputCell = some {
      id := memory.inputCell, value := some (.array (signedI32Values memory.inputValues)) })
    (lengthRead : before.local? locals.length = some (.signed .i32 memory.bytes.length))
    (clearDistinct : ∀ localId ∈ [clearLocals.workspace, clearLocals.length, locals.input, locals.length],
      clearLocals.cursor ≠ localId)
    (packDistinct : ∀ localId ∈ [locals.workspace, locals.input, locals.length], locals.cursor ≠ localId) :
    ∃ after, Executes program before
      (.letLocal clearLocals.cursor (.scalar (.signed .i32)) (.value (.signed .i32 0))
        (.sequence clearLocals.clearLoop
          (.letLocal locals.cursor (.scalar (.signed .i32)) (.value (.signed .i32 0)) locals.loop))) .next after ∧
      after.cellEntry? memory.workspaceCell = some {
        id := memory.workspaceCell, value := some (.array (pack memory.bytes ++ signedI32Values memory.tail)) } ∧
      after.cellEntry? memory.inputCell = some {
        id := memory.inputCell, value := some (.array (signedI32Values memory.inputValues)) } ∧
      ModifiesOnly (CellSet.singleton memory.workspaceCell) before after ∧ StateWellFormed after := by
  have initial := clear_cursor_entry clear clearLocals wellFormed fresh workspaceRead workspaceContents wordsRead
    (clearDistinct _ (by simp)) (clearDistinct _ (by simp))
  have inputFrame := clear_cursor_frame clear clearLocals.cursor locals.input wellFormed fresh
    (clearDistinct _ (by simp)) inputRead workspaceContents (by intro impossible; cases impossible)
  have lengthFrame := clear_cursor_frame clear clearLocals.cursor locals.length wellFormed fresh
    (clearDistinct _ (by simp)) lengthRead workspaceContents (by intro impossible; cases impossible)
  have inputStorage := clear_cursor_input clear clearLocals.cursor wellFormed fresh inputContents
    (by rw [sameCell]; exact memory.input_workspace)
  obtain ⟨packed, run, output, input, effect, packedWF⟩ := clear_then_pack program memory locals initial sameLocal sameCell
    sameWords sameTail inputFrame.1 inputStorage.1 lengthFrame.1 inputStorage.2
    (by
      intro localId member
      simp only [List.mem_cons, List.not_mem_nil, or_false] at member
      rcases member with rfl | rfl
      · exact inputFrame.2
      · exact lengthFrame.2) packDistinct
  have combined := (bindLocal_effect before clearLocals.cursor (.signed .i32 0)).trans effect.toStoreEffect
  have closed : ModifiesOnly (CellSet.singleton memory.workspaceCell) before (restoreLocals before packed) :=
    combined.restoreLocals.hideFreshWritesExcept (by
      intro cell changed
      rcases changed with impossible | workspace | cursor
      · exact False.elim impossible
      · exact Or.inl (workspace.trans sameCell)
      · exact Or.inr (by rw [show cell = before.nextCell from cursor.trans fresh]; exact Nat.le_refl _))
  exact ⟨restoreLocals before packed, executesLetLocal (show Evaluates program before
    (.value (.signed .i32 0)) (.signed .i32 0) before from ⟨1, rfl⟩) run, output, input, closed,
    combined.restoreLocals_wellFormed wellFormed packedWF⟩

theorem clear_setup_then_continue (program : Program) (clear : ClearMemory) (clearLocals : LoopLocals)
    (memory : LoopMemory) (locals : LoopLocals)
    {continuation : Stmt} {completion : Completion} {post : Lanius.World.State → Prop}
    (wellFormed : StateWellFormed before) (fresh : clear.cursorCell = before.nextCell)
    (sameLocal : clearLocals.workspace = locals.workspace)
    (sameCell : clear.workspaceCell = memory.workspaceCell)
    (sameWords : clear.words = memory.words)
    (sameTail : memory.tail = clear.original.drop clear.words)
    (workspaceRead : before.local? clearLocals.workspace = some
      (.slice (.scalar (.signed .i32)) clear.workspaceCell [] 0 clear.original.length))
    (workspaceContents : before.cellEntry? clear.workspaceCell = some {
      id := clear.workspaceCell, value := some (.array (signedI32Values clear.original)) })
    (wordsRead : before.local? clearLocals.length = some (.signed .i32 clear.words))
    (inputRead : before.local? locals.input = some
      (.slice (.scalar (.signed .i32)) memory.inputCell [] 0 memory.inputValues.length))
    (inputContents : before.cellEntry? memory.inputCell = some {
      id := memory.inputCell, value := some (.array (signedI32Values memory.inputValues)) })
    (lengthRead : before.local? locals.length = some (.signed .i32 memory.bytes.length))
    (clearDistinct : ∀ localId ∈ [clearLocals.workspace, clearLocals.length, locals.input, locals.length],
      clearLocals.cursor ≠ localId)
    (packDistinct : ∀ localId ∈ [locals.workspace, locals.input, locals.length], locals.cursor ≠ localId)
    (continueRun : ∀ (next : LoopMemory) cleared packed,
      next.cursorCell = cleared.nextCell →
      next.workspaceCell = memory.workspaceCell → next.inputCell = memory.inputCell →
      next.bytes = memory.bytes → next.tail = memory.tail → next.inputTail = memory.inputTail →
      ModifiesOnly clear.writes (before.bindLocal clearLocals.cursor (.signed .i32 0)) cleared →
      LoopInvariant next locals next.bytes packed →
      ModifiesOnly next.writes (cleared.bindLocal locals.cursor (.signed .i32 0)) packed →
      ∃ after, Executes program packed continuation completion after ∧ post after.world) :
    ∃ after, Executes program before
      (.letLocal clearLocals.cursor (.scalar (.signed .i32)) (.value (.signed .i32 0))
        (.sequence clearLocals.clearLoop
          (.letLocal locals.cursor (.scalar (.signed .i32)) (.value (.signed .i32 0))
            (.sequence locals.loop continuation)))) completion after ∧ post after.world := by
  have initial := clear_cursor_entry clear clearLocals wellFormed fresh workspaceRead workspaceContents wordsRead
    (clearDistinct _ (by simp)) (clearDistinct _ (by simp))
  have inputFrame := clear_cursor_frame clear clearLocals.cursor locals.input wellFormed fresh
    (clearDistinct _ (by simp)) inputRead workspaceContents (by intro impossible; cases impossible)
  have lengthFrame := clear_cursor_frame clear clearLocals.cursor locals.length wellFormed fresh
    (clearDistinct _ (by simp)) lengthRead workspaceContents (by intro impossible; cases impossible)
  have inputStorage := clear_cursor_input clear clearLocals.cursor wellFormed fresh inputContents
    (by rw [sameCell]; exact memory.input_workspace)
  obtain ⟨after, run, output⟩ := clear_then_continue program memory locals initial sameLocal sameCell
    sameWords sameTail inputFrame.1 inputStorage.1 lengthFrame.1 inputStorage.2
    (by
      intro localId member
      simp only [List.mem_cons, List.not_mem_nil, or_false] at member
      rcases member with rfl | rfl
      · exact inputFrame.2
      · exact lengthFrame.2) packDistinct continueRun
  exact ⟨restoreLocals before after, executesLetLocal
    (show Evaluates program before (.value (.signed .i32 0)) (.signed .i32 0) before from ⟨1, rfl⟩) run, output⟩

end Lanius.Extraction.OutputPacking
