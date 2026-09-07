import Lanius.Extraction.CanonicalTokens.Ascii.Entry
import Lanius.Extraction.CanonicalTokens.Ascii.Loop

namespace Lanius.Extraction.CanonicalTokens.Ascii

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

/-- Correctness of the entire compact comparison body. The only representation
premise is explicit word padding in the supplied string; no helper execution,
packed-buffer correspondence, or loop correctness is assumed. -/
theorem executes_sourceBody (program : Program) (before : State)
    (sourceCell : CellId) (source : List Int) (start : Nat)
    (text : String) (spelling : List UInt8)
    (wellFormed : StateWellFormed before)
    (sourceLocal : before.local? 0 = some
      (.slice (.scalar (.signed .i32)) sourceCell [] 0 source.length))
    (sourceContents : before.cellEntry? sourceCell = some {
      id := sourceCell, value := some (.array (signedI32Values source)) })
    (startLocal : before.local? 1 = some (.signed .i32 start))
    (textLocal : before.local? 2 = some (.string text))
    (lengthLocal : before.local? 3 = some (.signed .i32 spelling.length))
    (capacity : start + spelling.length ≤ source.length)
    (bounded : source.length ≤ 2147483647)
    (countBound : spelling.length + 3 ≤ 2147483647)
    (padded : (Lanius.World.utf8Bytes text).length = ((spelling.length + 3) / 4) * 4)
    (prefixBytes : (Lanius.World.utf8Bytes text).take spelling.length = spelling) :
    ∃ after, Executes program before sourceBody
      (.returned (some (.boolean (matchesBytes source start spelling)))) after ∧
      StateWellFormed after ∧ after.locals = before.locals ∧ after.world = before.world ∧
      (∀ cell, cell < before.nextCell → after.cellEntry? cell = before.cellEntry? cell) ∧
      CellDomainExtension before after ∧ before.nextCell ≤ after.nextCell := by
  obtain ⟨words, ready, initializer, encoded, wordContents, readyWF, readyLocals,
      oldCells, readyNext, readyWorld, readyDomain, readyValues⟩ :=
    evaluates_wordView program before text spelling.length wellFormed textLocal lengthLocal countBound padded
  let view := Value.slice (.scalar (.signed .i32)) before.nextCell [] 0 words.length
  let packed := ready.bindLocal 4 view
  let entered := packed.bindLocal 5 (.signed .i32 0)
  have packedWF := bindLocal_preserves_well_formed ready 4 view readyWF
  have enteredWF := bindLocal_preserves_well_formed packed 5 (.signed .i32 0) packedWF
  have sourceOld := StateWellFormed.cell_lt_next_of_entry wellFormed sourceContents
  have sourceReady : ready.cellEntry? sourceCell = some {
      id := sourceCell, value := some (.array (signedI32Values source)) } :=
    (oldCells sourceCell sourceOld).trans sourceContents
  have sourceBelow : sourceCell < ready.nextCell := by rw [readyNext]; exact Nat.lt_succ_of_lt sourceOld
  have wordBelow : before.nextCell < ready.nextCell := by rw [readyNext]; exact Nat.lt_succ_self _
  have entryReads (id : VarId) (notPacked : 4 ≠ id) (notCursor : 5 ≠ id) :
      entered.local? id = before.local? id := by
    exact (bindLocal_preserves_other_local packedWF notCursor).trans
      ((bindLocal_preserves_other_local readyWF notPacked).trans (readyValues id))
  have entryCells (cell : CellId) (old : cell < ready.nextCell) :
      entered.cellEntry? cell = ready.cellEntry? cell := by
    have packedOld : cell < packed.nextCell := by
      change cell < ready.nextCell + 1
      exact Nat.lt_succ_of_lt old
    exact (bindCell_preserves_old_cell packed 5 (some (.signed .i32 0)) cell packedOld).trans
      (bindCell_preserves_old_cell ready 4 (some view) cell old)
  let buffers : Buffers := {
    sourceCell
    packedCell := before.nextCell
    cursorCell := packed.nextCell
    source
    packed := words
    storage := Lanius.World.utf8Bytes text
    spelling
    start
    encoded
    bytes := prefixBytes
    capacity
    bounded
    source_cursor := by
      change sourceCell ≠ ready.nextCell + 1
      exact Nat.ne_of_lt (Nat.lt_succ_of_lt sourceBelow)
    packed_cursor := by
      change before.nextCell ≠ ready.nextCell + 1
      exact Nat.ne_of_lt (Nat.lt_succ_of_lt wordBelow)
  }
  have invariant : Invariant buffers sourceLocals 0 entered := by
    refine ⟨enteredWF, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_⟩
    · exact (entryReads 0 (by decide) (by decide)).trans sourceLocal
    · exact (entryCells sourceCell sourceBelow).trans sourceReady
    · exact (bindLocal_preserves_other_local packedWF (show 5 ≠ 4 by decide)).trans
        (bindLocal_finds_local ready 4 view readyWF)
    · exact (entryCells before.nextCell wordBelow).trans wordContents
    · exact (entryReads 1 (by decide) (by decide)).trans startLocal
    · exact (entryReads 3 (by decide) (by decide)).trans lengthLocal
    · exact bindLocal_owns_fresh packed 5 (.signed .i32 0) packedWF
    · intro id member cell found same
      have different : 5 ≠ id := by
        simp [sourceLocals] at member
        rcases member with rfl | rfl | rfl | rfl <;> decide
      subst cell
      exact bindLocal_other_cellId_ne_fresh packed 5 id (.signed .i32 0) packedWF different found
  obtain ⟨completed, run, completedWF, effect⟩ := executes_finish program buffers sourceLocals entered
    invariant (by decide) (by decide) (by decide)
  let after := restoreLocals ready (restoreLocals packed completed)
  have body : Executes program before sourceBody
      (.returned (some (.boolean (matchesBytes source start spelling)))) after :=
    executesLetLocal initializer (executesLetLocal
      (show Evaluates program packed (.value (.signed .i32 0)) (.signed .i32 0) packed from ⟨1, rfl⟩) run)
  have domain : CellDomainExtension before completed := readyDomain.trans
    ((bindLocal_domainExtension ready 4 view).trans
      ((bindLocal_domainExtension packed 5 (.signed .i32 0)).trans effect.domain))
  have finalWF : StateWellFormed after := by
    have result := domain.restoreLocals_wellFormed wellFormed completedWF
    simpa only [after, restoreLocals, readyLocals] using result
  refine ⟨after, body, finalWF, readyLocals, ?_, ?_, ?_, ?_⟩
  · exact effect.world.trans readyWorld
  · intro cell old
    have readyOld : cell < ready.nextCell := by rw [readyNext]; exact Nat.lt_succ_of_lt old
    have cursorOld : cell < packed.nextCell := by
      change cell < ready.nextCell + 1
      exact Nat.lt_succ_of_lt readyOld
    have enteredOld : cell < entered.nextCell := by
      change cell < packed.nextCell + 1
      exact Nat.lt_succ_of_lt cursorOld
    exact (effect.oldCells cell enteredOld (Nat.ne_of_lt cursorOld)).trans
      ((entryCells cell readyOld).trans (oldCells cell old))
  · exact domain.restoreLocals.restoreLocals
  · have readyLe : before.nextCell ≤ ready.nextCell := by
      rw [readyNext]
      exact Nat.le_succ _
    have enteredLe : ready.nextCell ≤ entered.nextCell := by
      change ready.nextCell ≤ ready.nextCell + 1 + 1
      exact Nat.le_trans (Nat.le_succ _) (Nat.le_succ _)
    exact Nat.le_trans readyLe (Nat.le_trans enteredLe effect.nextCell)

end Lanius.Extraction.CanonicalTokens.Ascii
