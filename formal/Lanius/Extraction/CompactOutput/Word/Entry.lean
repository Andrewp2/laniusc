import Lanius.Extraction.CompactOutput.Word.Loop

namespace Lanius.Extraction.CompactOutput.Word

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

/-- Ordinary function parameters and backing allocation, before either loop
local exists. Temporary ownership and separation are derived below. -/
structure Entry (state : State) where
  outputCell : CellId
  contents : List Int
  position : Int
  capacity : Nat
  value : Nat
  wellFormed : StateWellFormed state
  room : capacity ≤ contents.length
  capacityFit : capacity ≤ 2147483647
  valueFit : value ≤ 2147483647
  output : state.local? 0 = some (.slice i32 outputCell [] 0 contents.length)
  capacityRead : state.local? 1 = some (.signed .i32 capacity)
  positionRead : state.local? 2 = some (.signed .i32 position)
  valueRead : state.local? 3 = some (.signed .i32 value)
  backing : state.cellEntry? outputCell = some {
    id := outputCell, value := some (.array (signedI32Values contents)) }

def Entry.memory (entry : Entry before) : Memory := {
  outputCell := entry.outputCell
  cursorCell := before.nextCell
  shiftCell := before.nextCell + 1
  capacity := entry.capacity
  value := entry.value
  capacityFit := entry.capacityFit
  valueFit := entry.valueFit
  distinct := Nat.ne_of_lt (Nat.lt_succ_self _)
}

def Entry.entered (entry : Entry before) : State :=
  (before.bindLocal 4 (.signed .i32 entry.position)).bindLocal 5 (.signed .i32 28)

theorem Entry.invariant (entry : Entry before) :
    Owned entry.memory 8 entry.position entry.contents entry.entered := by
  let first := before.bindLocal 4 (.signed .i32 entry.position)
  have firstWF : StateWellFormed first := bindLocal_preserves_well_formed _ _ _ entry.wellFormed
  have keep {id : VarId} {v : Value} (notCursor : (4 : VarId) ≠ id) (notShift : (5 : VarId) ≠ id)
      (found : before.local? id = some v) : entry.entered.local? id = some v :=
    (bindLocal_preserves_other_local firstWF notShift).trans
      ((bindLocal_preserves_other_local entry.wellFormed notCursor).trans found)
  have backingFirst : first.cellEntry? entry.outputCell = some {
      id := entry.outputCell, value := some (.array (signedI32Values entry.contents)) } :=
    ((bindLocal_effect before 4 (.signed .i32 entry.position)).oldCells entry.outputCell
      (StateWellFormed.cell_lt_next_of_entry entry.wellFormed entry.backing) (by simp [CellSet.empty])).trans entry.backing
  refine ⟨bindLocal_preserves_well_formed _ _ _ firstWF, entry.room,
    keep (by decide) (by decide) entry.output, ?_,
    keep (by decide) (by decide) entry.capacityRead, keep (by decide) (by decide) entry.valueRead, ?_, ?_, ?_⟩
  · exact ((bindLocal_effect first 5 (.signed .i32 28)).oldCells entry.outputCell
      (StateWellFormed.cell_lt_next_of_entry firstWF backingFirst) (by simp [CellSet.empty])).trans backingFirst
  · exact bindLocal_preserves_localPointsTo_of_ne first 5 4 (.signed .i32 28) before.nextCell _ firstWF
      (by decide) (bindLocal_owns_fresh before 4 (.signed .i32 entry.position) entry.wellFormed)
  · exact bindLocal_owns_fresh first 5 (.signed .i32 28) firstWF
  · intro id member cell binding
    have notCursor : (4 : VarId) ≠ id := by simp only [List.mem_cons, List.not_mem_nil, or_false] at member; rcases member with rfl | rfl | rfl <;> decide
    have notShift : (5 : VarId) ≠ id := by simp only [List.mem_cons, List.not_mem_nil, or_false] at member; rcases member with rfl | rfl | rfl <;> decide
    have oldBinding : before.cellId? id = some cell := by
      change (first.bindLocal 5 (.signed .i32 28)).cellId? id = some cell at binding
      rw [bindLocal_preserves_other_cellId first 5 id (.signed .i32 28) notShift] at binding
      change (before.bindLocal 4 (.signed .i32 entry.position)).cellId? id = some cell at binding
      rw [bindLocal_preserves_other_cellId before 4 id (.signed .i32 entry.position) notCursor] at binding
      exact binding
    have old := StateWellFormed.cell_lt_next_of_local_binding id cell entry.wellFormed oldBinding
    exact ⟨Nat.ne_of_lt old, Nat.ne_of_lt (Nat.lt_trans old (Nat.lt_succ_self _))⟩

/-- Execute the guard, both local declarations, the complete loop, return,
and both scope closures. No initialized temporary or loop run is assumed. -/
theorem Entry.execute (entry : Entry before) (byte : CheckedByte program) (digit : CheckedDigit program) :
    ∃ after, Executes program.core before (body byte.source.function.id digit.source.function.id)
        (.returned (some (.signed .i32 (appendAll entry.capacity (hexDigits entry.value 8) entry.position entry.contents).position))) after ∧
      after.cellEntry? entry.outputCell = some {
        id := entry.outputCell
        value := some (.array (signedI32Values (appendAll entry.capacity (hexDigits entry.value 8) entry.position entry.contents).contents)) } ∧
      CellEffect (CellSet.singleton entry.outputCell) before after := by
  have passed : Evaluates program.core before (binary .lessEqual (read 3) negativeOne) (.boolean false) before := by
    apply evaluatesEagerBinary (by decide) (by decide) (local_evaluates program.core entry.valueRead)
      (negativeOne_evaluates program.core before)
    simp [evalBinaryValue, evalSignedBinary]
    omega
  obtain ⟨completed, loopRun, ⟨left, finalOwned⟩, effect⟩ := execute_loop byte digit entry.invariant (by decide)
  let first := before.bindLocal 4 (.signed .i32 entry.position)
  have firstWF : StateWellFormed first := bindLocal_preserves_well_formed _ _ _ entry.wellFormed
  have tailRun : Executes program.core entry.entered
      (.sequence (loop byte.source.function.id digit.source.function.id) (returned (read 4)))
      (.returned (some (.signed .i32 (appendAll entry.capacity (hexDigits entry.value 8) entry.position entry.contents).position))) completed := by
    cases result : appendAll entry.capacity (hexDigits entry.value 8) entry.position entry.contents with
    | done position contents =>
      have cursor := local_evaluates program.core (Assertion.localPointsTo_local _ _ _ _ finalOwned.cursor)
      simp only [memory, result, AppendOutcome.position] at cursor
      exact executesSequence (by simpa only [memory, result, AppendOutcome.completion] using loopRun)
        (executesSequenceReturned (executesReturnValue cursor))
    | full contents =>
      simp only [AppendOutcome.position]
      exact executesSequenceReturned (by simpa only [memory, result, AppendOutcome.completion] using loopRun)
  have run := executesSequence (executesIfFalse (thenBranch := returned negativeOne) passed (executesSkip _ _))
    (executesLetLocal (id := 4) (type := i32) (local_evaluates program.core entry.positionRead)
      (executesLetLocal (id := 5) (type := i32)
        (show Evaluates program.core first (number 28) (.signed .i32 28) first from ⟨1, rfl⟩) tailRun))
  have closed := CellEffect.closeLocal before 4 (.signed .i32 entry.position) entry.wellFormed
    (CellEffect.closeLocal first 5 (.signed .i32 28) firstWF effect)
  refine ⟨restoreLocals before completed, run, finalOwned.backing, closed.narrow ?_⟩
  intro cell old changed
  rcases changed with (output | cursor) | shift
  · exact output
  · change cell = before.nextCell at cursor
    exact (Nat.ne_of_lt old cursor).elim
  · change cell = before.nextCell + 1 at shift
    exact (Nat.ne_of_lt (Nat.lt_trans old (Nat.lt_succ_self _)) shift).elim

end Lanius.Extraction.CompactOutput.Word
