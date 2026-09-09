import Lanius.Extraction.CompactOutput.Assignments.Read

namespace Lanius.Extraction.CompactOutput.Assignments

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Extraction.SemanticTokens

/-- Resources at the start of an iteration, before its field locals exist. -/
structure Entry (before : State) where
  assignments : List Assignment
  index : Nat
  inputCell : CellId
  outputCell : CellId
  cursorCell : CellId
  position : Int
  capacity : Nat
  contents : List Int
  wellFormed : StateWellFormed before
  input : I32PrefixLocal before 0 inputCell (assignments.flatMap Assignment.words)
  indexRead : before.local? 7 = some (.signed .i32 index)
  bound : index < assignments.length
  sizeFit : 2 * assignments.length ≤ 2147483647
  firstFit : assignments[index].first ≤ 2147483647
  lower : -1 ≤ secondWord assignments[index]
  upper : secondWord assignments[index] < 2147483647
  room : capacity ≤ contents.length
  capacityFit : capacity ≤ 2147483647
  cursor : (Assertion.localPointsTo 6 cursorCell (some (.signed .i32 position))).holds before
  outputRead : before.local? 3 = some (.slice i32 outputCell [] 0 contents.length)
  capacityRead : before.local? 4 = some (.signed .i32 capacity)
  stable : ∀ id ∈ [3, 4], ∀ cell, before.cellId? id = some cell → cell ≠ cursorCell
  backing : before.cellEntry? outputCell = some {
    id := outputCell, value := some (.array (signedI32Values contents)) }

def Entry.assignment (entry : Entry before) : Assignment := entry.assignments[entry.index]'entry.bound
def Entry.scope (entry : Entry before) : State := fieldsState before entry.assignment
def Entry.outcome (entry : Entry before) : AppendOutcome :=
  appendAll entry.capacity (encoding entry.assignment.first (secondWord entry.assignment)) entry.position entry.contents

/-- Derive the guard and both writes in their real lexical scope. Field
bindings and their separation are consequences of the declarations. -/
theorem Entry.write (entry : Entry before) (word : Word.Checked program byte digit) :
    ∃ middle written,
      Evaluates program.core entry.scope fieldGuard (.boolean false) entry.scope ∧
      Evaluates program.core entry.scope (firstWrite word.source.function.id) .unit middle ∧
      Evaluates program.core middle (secondWrite word.source.function.id) .unit written ∧
      (Assertion.localPointsTo 6 entry.cursorCell (some (.signed .i32 entry.outcome.position))).holds written ∧
      written.cellEntry? entry.outputCell = some {
        id := entry.outputCell, value := some (.array (signedI32Values entry.outcome.contents)) } ∧
      CellEffect (CellSet.union (CellSet.singleton entry.outputCell) (CellSet.singleton entry.cursorCell)) entry.scope written := by
  obtain ⟨_, _, scopeWF, firstRead, secondRead, _⟩ := initialize_fields program.core entry.assignments entry.index
    entry.wellFormed entry.input entry.indexRead entry.bound entry.sizeFit
  let firstState := before.bindLocal 8 (.signed .i32 entry.assignment.first)
  have firstWF : StateWellFormed firstState := bindLocal_preserves_well_formed _ _ _ entry.wellFormed
  have keep {id : VarId} {value : Value} (notFirst : (8 : VarId) ≠ id) (notSecond : (9 : VarId) ≠ id)
      (found : before.local? id = some value) : entry.scope.local? id = some value :=
    (bindLocal_preserves_other_local firstWF notSecond).trans
      ((bindLocal_preserves_other_local entry.wellFormed notFirst).trans found)
  have cursorFirst := bindLocal_preserves_localPointsTo_of_ne before 8 6
    (.signed .i32 entry.assignment.first) entry.cursorCell _ entry.wellFormed (by decide) entry.cursor
  have cursorScope := bindLocal_preserves_localPointsTo_of_ne firstState 9 6
    (.signed .i32 (secondWord entry.assignment)) entry.cursorCell _ firstWF (by decide) cursorFirst
  have backingFirst := ((bindLocal_effect before 8 (.signed .i32 entry.assignment.first)).oldCells entry.outputCell
    (StateWellFormed.cell_lt_next_of_entry entry.wellFormed entry.backing) (by simp [CellSet.empty])).trans entry.backing
  have backingScope := ((bindLocal_effect firstState 9 (.signed .i32 (secondWord entry.assignment))).oldCells entry.outputCell
    (StateWellFormed.cell_lt_next_of_entry firstWF backingFirst) (by simp [CellSet.empty])).trans backingFirst
  have stable : ∀ id ∈ [3, 4, 9], ∀ cell, entry.scope.cellId? id = some cell → cell ≠ entry.cursorCell := by
    intro id member cell binding
    simp only [List.mem_cons, List.not_mem_nil, or_false] at member
    rcases member with rfl | rfl | rfl
    · apply entry.stable 3 (by simp) cell
      simpa only [scope, fieldsState, bindLocal_preserves_other_cellId _ 9 3 _ (by decide),
        bindLocal_preserves_other_cellId _ 8 3 _ (by decide)] using binding
    · apply entry.stable 4 (by simp) cell
      simpa only [scope, fieldsState, bindLocal_preserves_other_cellId _ 9 4 _ (by decide),
        bindLocal_preserves_other_cellId _ 8 4 _ (by decide)] using binding
    · have newCell : cell = firstState.nextCell := by
        have fresh := (bindLocal_owns_fresh firstState 9 (.signed .i32 (secondWord entry.assignment)) firstWF).1
        exact Option.some.inj (binding.symm.trans fresh)
      have old := StateWellFormed.cell_lt_next_of_local_binding 6 entry.cursorCell entry.wellFormed entry.cursor.1
      rw [newCell]
      exact Ne.symm (Nat.ne_of_lt (Nat.lt_trans old (Nat.lt_succ_self _)))
  obtain ⟨middle, written, firstRun, secondRun, cursor, backing, effect⟩ := write_fields word entry.assignment.first
    entry.capacity (secondWord entry.assignment) entry.position scopeWF entry.firstFit entry.lower entry.upper
    entry.room entry.capacityFit cursorScope (keep (by decide) (by decide) entry.outputRead)
    (keep (by decide) (by decide) entry.capacityRead) firstRead secondRead stable backingScope
  exact ⟨middle, written, fields_valid program.core _ _ entry.lower firstRead secondRead,
    firstRun, secondRun, cursor, backing, effect⟩

end Lanius.Extraction.CompactOutput.Assignments
