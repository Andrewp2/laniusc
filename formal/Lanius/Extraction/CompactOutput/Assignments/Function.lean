import Lanius.Extraction.CompactOutput.Assignments.Loop
import Lanius.Extraction.CompactOutput.Assignments.Guard

namespace Lanius.Extraction.CompactOutput.Assignments.Function

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Extraction.SemanticTokens

structure Entry (state : State) where
  inputCell : CellId
  outputCell : CellId
  assignments : List Assignment
  contents : List Int
  position : Int
  capacity : Nat
  wellFormed : StateWellFormed state
  room : capacity ≤ contents.length
  capacityFit : capacity ≤ 2147483647
  inputLength : Nat
  inputRoom : 2 * assignments.length ≤ inputLength
  lengthFit : inputLength ≤ 2147483647
  fields : ∀ assignment ∈ assignments, assignment.first ≤ 2147483647 ∧
    -1 ≤ secondWord assignment ∧ secondWord assignment < 2147483647
  distinctBuffers : outputCell ≠ inputCell
  input : I32PrefixLocal state 0 inputCell (assignments.flatMap Assignment.words)
  lengthRead : state.local? 1 = some (.signed .i32 inputLength)
  countRead : state.local? 2 = some (.signed .i32 assignments.length)
  output : state.local? 3 = some (.slice i32 outputCell [] 0 contents.length)
  capacityRead : state.local? 4 = some (.signed .i32 capacity)
  positionRead : state.local? 5 = some (.signed .i32 position)
  backing : state.cellEntry? outputCell = some {
    id := outputCell, value := some (.array (signedI32Values contents)) }

def Entry.memory (entry : Entry before) : Memory := {
  inputCell := entry.inputCell, outputCell := entry.outputCell
  cursorCell := before.nextCell, indexCell := before.nextCell + 1
  assignments := entry.assignments, capacity := entry.capacity
  capacityFit := entry.capacityFit, sizeFit := by have := entry.inputRoom; have := entry.lengthFit; omega
  fields := entry.fields
  distinctLocals := Nat.ne_of_lt (Nat.lt_succ_self _)
  distinctBuffers := entry.distinctBuffers
}

def Entry.entered (entry : Entry before) : State :=
  (before.bindLocal 6 (.signed .i32 entry.position)).bindLocal 7 (.signed .i32 0)

theorem Entry.invariant (entry : Entry before) :
    Owned entry.memory 0 entry.position entry.contents entry.entered := by
  let first := before.bindLocal 6 (.signed .i32 entry.position)
  have firstWF : StateWellFormed first := bindLocal_preserves_well_formed _ _ _ entry.wellFormed
  have keep {id : VarId} {v : Value} (notCursor : (6 : VarId) ≠ id) (notIndex : (7 : VarId) ≠ id)
      (found : before.local? id = some v) : entry.entered.local? id = some v :=
    (bindLocal_preserves_other_local firstWF notIndex).trans
      ((bindLocal_preserves_other_local entry.wellFormed notCursor).trans found)
  have backingFirst : first.cellEntry? entry.outputCell = some {
      id := entry.outputCell, value := some (.array (signedI32Values entry.contents)) } :=
    ((bindLocal_effect before 6 (.signed .i32 entry.position)).oldCells entry.outputCell
      (StateWellFormed.cell_lt_next_of_entry entry.wellFormed entry.backing) (by simp [CellSet.empty])).trans entry.backing
  have inputFirst := entry.input.bindLocal entry.wellFormed 6 (.signed .i32 entry.position) (by decide)
  refine ⟨bindLocal_preserves_well_formed _ _ _ firstWF, Nat.zero_le _, entry.room,
    inputFirst.bindLocal firstWF 7 (.signed .i32 0) (by decide),
    keep (by decide) (by decide) entry.countRead, keep (by decide) (by decide) entry.output,
    keep (by decide) (by decide) entry.capacityRead, ?_, ?_, ?_, ?_⟩
  · exact ((bindLocal_effect first 7 (.signed .i32 0)).oldCells entry.outputCell
      (StateWellFormed.cell_lt_next_of_entry firstWF backingFirst) (by simp [CellSet.empty])).trans backingFirst
  · exact bindLocal_preserves_localPointsTo_of_ne first 7 6 (.signed .i32 0) before.nextCell _ firstWF
      (by decide) (bindLocal_owns_fresh before 6 (.signed .i32 entry.position) entry.wellFormed)
  · exact bindLocal_owns_fresh first 7 (.signed .i32 0) firstWF
  · intro id member cell binding
    have notCursor : (6 : VarId) ≠ id := by
      simp only [List.mem_cons, List.not_mem_nil, or_false] at member
      rcases member with rfl | rfl | rfl | rfl <;> decide
    have notIndex : (7 : VarId) ≠ id := by
      simp only [List.mem_cons, List.not_mem_nil, or_false] at member
      rcases member with rfl | rfl | rfl | rfl <;> decide
    have oldBinding : before.cellId? id = some cell := by
      change (first.bindLocal 7 (.signed .i32 0)).cellId? id = some cell at binding
      rw [bindLocal_preserves_other_cellId first 7 id (.signed .i32 0) notIndex] at binding
      change (before.bindLocal 6 (.signed .i32 entry.position)).cellId? id = some cell at binding
      rw [bindLocal_preserves_other_cellId before 6 id (.signed .i32 entry.position) notCursor] at binding
      exact binding
    have old := StateWellFormed.cell_lt_next_of_local_binding id cell entry.wellFormed oldBinding
    exact ⟨Nat.ne_of_lt old, Nat.ne_of_lt (Nat.lt_trans old (Nat.lt_succ_self _))⟩

/-- Execute the actual entry guard, initial declarations, complete loop,
final return, and local scope closures. -/
theorem Entry.execute (entry : Entry before) (word : Word.Checked program byte digit) :
    ∃ after, Executes program.core before (body word.source.function.id)
        (.returned (some (.signed .i32 (appendAll entry.capacity (encodeAll entry.assignments) entry.position entry.contents).position))) after ∧
      after.cellEntry? entry.outputCell = some {
        id := entry.outputCell, value := some (.array (signedI32Values
          (appendAll entry.capacity (encodeAll entry.assignments) entry.position entry.contents).contents)) } ∧
      CellEffect (CellSet.singleton entry.outputCell) before after := by
  have passed := entry_guard_passes program.core entry.assignments.length entry.inputLength
    entry.inputRoom entry.lengthFit entry.countRead entry.lengthRead
  obtain ⟨completed, loopRun, backing, completedOwned, effect⟩ := execute_loop word entry.assignments entry.invariant rfl
  let first := before.bindLocal 6 (.signed .i32 entry.position)
  have firstWF : StateWellFormed first := bindLocal_preserves_well_formed _ _ _ entry.wellFormed
  have tailRun : Executes program.core entry.entered
      (.sequence (loop word.source.function.id) (returned (read 6)))
      (.returned (some (.signed .i32 (appendAll entry.capacity (encodeAll entry.assignments) entry.position entry.contents).position))) completed := by
    cases result : appendAll entry.capacity (encodeAll entry.assignments) entry.position entry.contents with
    | done position contents =>
      have owned : Owned entry.memory entry.assignments.length position contents completed := by
        simpa only [memory, result, Completed] using completedOwned
      have cursor := local_evaluates program.core (Assertion.localPointsTo_local _ _ _ _ owned.cursor)
      exact executesSequence (by simpa only [memory, result, AppendOutcome.completion] using loopRun)
        (executesSequenceReturned (executesReturnValue cursor))
    | full contents =>
      simp only [AppendOutcome.position]
      exact executesSequenceReturned (by simpa only [memory, result, AppendOutcome.completion] using loopRun)
  have run := executesSequence (executesIfFalse (thenBranch := returned negativeOne) passed (executesSkip _ _))
    (executesLetLocal (id := 6) (type := i32) (local_evaluates program.core entry.positionRead)
      (executesLetLocal (id := 7) (type := i32)
        (show Evaluates program.core first (number 0) (.signed .i32 0) first from ⟨1, rfl⟩) tailRun))
  have closed := CellEffect.closeLocal before 6 (.signed .i32 entry.position) entry.wellFormed
    (CellEffect.closeLocal first 7 (.signed .i32 0) firstWF effect)
  refine ⟨restoreLocals before completed, run, backing, closed.narrow ?_⟩
  intro cell old changed
  rcases changed with (output | cursor) | index
  · exact output
  · change cell = before.nextCell at cursor
    exact (Nat.ne_of_lt old cursor).elim
  · change cell = before.nextCell + 1 at index
    exact (Nat.ne_of_lt (Nat.lt_trans old (Nat.lt_succ_self _)) index).elim

end Lanius.Extraction.CompactOutput.Assignments.Function
