import Lanius.Extraction.CompactOutput.Tokens.Scope
import Lanius.Extraction.CompactOutput.Tokens.Write

namespace Lanius.Extraction.CompactOutput.Tokens

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Compiler.Lexer Lanius.Extraction.CanonicalTokens.CanonicalizeModel

structure Entry (before : State) where
  tokens : List RawToken
  index : Nat
  inputCell : CellId
  outputCell : CellId
  cursorCell : CellId
  position : Int
  capacity : Nat
  sourceLength : Nat
  contents : List Int
  wellFormed : StateWellFormed before
  input : I32PrefixLocal before 0 inputCell (encodeTokens tokens)
  indexRead : before.local? 8 = some (.signed .i32 index)
  bound : index < tokens.length
  sizeFit : 3 * tokens.length ≤ 2147483647
  kindFit : tokens[index].kind.gpuCode ≤ 2147483647
  ordered : tokens[index].start ≤ tokens[index].finish
  within : tokens[index].finish ≤ sourceLength
  sourceFit : sourceLength ≤ 2147483647
  sourceRead : before.local? 3 = some (.signed .i32 sourceLength)
  room : capacity ≤ contents.length
  capacityFit : capacity ≤ 2147483647
  cursor : (Assertion.localPointsTo 7 cursorCell (some (.signed .i32 position))).holds before
  outputRead : before.local? 4 = some (.slice i32 outputCell [] 0 contents.length)
  capacityRead : before.local? 5 = some (.signed .i32 capacity)
  stable : ∀ id ∈ [4, 5], ∀ cell, before.cellId? id = some cell → cell ≠ cursorCell
  backing : before.cellEntry? outputCell = some {
    id := outputCell, value := some (.array (signedI32Values contents)) }

def Entry.token (entry : Entry before) : RawToken := entry.tokens[entry.index]'entry.bound
def Entry.scope (entry : Entry before) : State := fieldsState before entry.index entry.token
def Entry.outcome (entry : Entry before) : AppendOutcome :=
  appendAll entry.capacity (encoding entry.token) entry.position entry.contents

theorem Entry.write (entry : Entry before) (word : Word.Checked program byte digit) :
    ∃ first second written,
      Evaluates program.core entry.scope fieldGuard (.boolean false) entry.scope ∧
      Evaluates program.core entry.scope (kindWrite word.source.function.id) .unit first ∧
      Evaluates program.core first (startWrite word.source.function.id) .unit second ∧
      Evaluates program.core second (finishWrite word.source.function.id) .unit written ∧
      (Assertion.localPointsTo 7 entry.cursorCell (some (.signed .i32 entry.outcome.position))).holds written ∧
      written.cellEntry? entry.outputCell = some {
        id := entry.outputCell, value := some (.array (signedI32Values entry.outcome.contents)) } ∧
      CellEffect (CellSet.union (CellSet.singleton entry.outputCell) (CellSet.singleton entry.cursorCell)) entry.scope written := by
  obtain ⟨_, _, _, scopeWF, startRead, finishRead, kindRead, _⟩ := initialize_fields program.core entry.tokens entry.index
    entry.wellFormed entry.input entry.indexRead entry.bound entry.sizeFit
  have rowWF : StateWellFormed (rowState before entry.index) := bindLocal_preserves_well_formed _ _ _ entry.wellFormed
  have startWF : StateWellFormed (startState before entry.index entry.token) := bindLocal_preserves_well_formed _ _ _ rowWF
  have keep {id : VarId} {value : Value} (n9 : (9 : VarId) ≠ id) (n10 : (10 : VarId) ≠ id)
      (n11 : (11 : VarId) ≠ id) (found : before.local? id = some value) : entry.scope.local? id = some value :=
    (bindLocal_preserves_other_local startWF n11).trans
      ((bindLocal_preserves_other_local rowWF n10).trans
        ((bindLocal_preserves_other_local entry.wellFormed n9).trans found))
  have cursorRow := bindLocal_preserves_localPointsTo_of_ne before 9 7
    (.signed .i32 (3 * entry.index : Nat)) entry.cursorCell _ entry.wellFormed (by decide) entry.cursor
  have cursorStart := bindLocal_preserves_localPointsTo_of_ne (rowState before entry.index) 10 7
    (.signed .i32 entry.token.start) entry.cursorCell _ rowWF (by decide) cursorRow
  have cursorScope := bindLocal_preserves_localPointsTo_of_ne (startState before entry.index entry.token) 11 7
    (.signed .i32 entry.token.finish) entry.cursorCell _ startWF (by decide) cursorStart
  have backingRow := ((bindLocal_effect before 9 (.signed .i32 (3 * entry.index : Nat))).oldCells entry.outputCell
    (StateWellFormed.cell_lt_next_of_entry entry.wellFormed entry.backing) (by simp [CellSet.empty])).trans entry.backing
  have backingStart := ((bindLocal_effect (rowState before entry.index) 10 (.signed .i32 entry.token.start)).oldCells entry.outputCell
    (StateWellFormed.cell_lt_next_of_entry rowWF backingRow) (by simp [CellSet.empty])).trans backingRow
  have backingScope := ((bindLocal_effect (startState before entry.index entry.token) 11 (.signed .i32 entry.token.finish)).oldCells entry.outputCell
    (StateWellFormed.cell_lt_next_of_entry startWF backingStart) (by simp [CellSet.empty])).trans backingStart
  have stable : ∀ id ∈ [4, 5, 10, 11], ∀ cell, entry.scope.cellId? id = some cell → cell ≠ entry.cursorCell := by
    intro id member cell binding
    simp only [List.mem_cons, List.not_mem_nil, or_false] at member
    rcases member with rfl | rfl | rfl | rfl
    · apply entry.stable 4 (by simp) cell
      simpa only [scope, fieldsState, startState, rowState,
        bindLocal_preserves_other_cellId _ 11 4 _ (by decide),
        bindLocal_preserves_other_cellId _ 10 4 _ (by decide),
        bindLocal_preserves_other_cellId _ 9 4 _ (by decide)] using binding
    · apply entry.stable 5 (by simp) cell
      simpa only [scope, fieldsState, startState, rowState,
        bindLocal_preserves_other_cellId _ 11 5 _ (by decide),
        bindLocal_preserves_other_cellId _ 10 5 _ (by decide),
        bindLocal_preserves_other_cellId _ 9 5 _ (by decide)] using binding
    · have fresh := (bindLocal_owns_fresh (rowState before entry.index) 10 (.signed .i32 entry.token.start) rowWF).1
      have selected : cell = (rowState before entry.index).nextCell := by
        have binding' : (startState before entry.index entry.token).cellId? 10 = some cell := by
          simpa only [scope, fieldsState, bindLocal_preserves_other_cellId _ 11 10 _ (by decide)] using binding
        exact Option.some.inj (binding'.symm.trans fresh)
      have old := StateWellFormed.cell_lt_next_of_local_binding 7 entry.cursorCell entry.wellFormed entry.cursor.1
      rw [selected]
      exact Ne.symm (Nat.ne_of_lt (Nat.lt_trans old (Nat.lt_succ_self _)))
    · have fresh := (bindLocal_owns_fresh (startState before entry.index entry.token) 11 (.signed .i32 entry.token.finish) startWF).1
      have selected : cell = (startState before entry.index entry.token).nextCell := Option.some.inj (binding.symm.trans fresh)
      have old := StateWellFormed.cell_lt_next_of_local_binding 7 entry.cursorCell entry.wellFormed entry.cursor.1
      rw [selected]
      exact Ne.symm (Nat.ne_of_lt (Nat.lt_trans (Nat.lt_trans old (Nat.lt_succ_self _)) (Nat.lt_succ_self _)))
  obtain ⟨first, second, written, firstRun, secondRun, thirdRun, cursor, backing, effect⟩ := write_fields word entry.token
    entry.capacity entry.position scopeWF entry.kindFit
    (Nat.le_trans entry.ordered (Nat.le_trans entry.within entry.sourceFit)) (Nat.le_trans entry.within entry.sourceFit)
    entry.room entry.capacityFit cursorScope (keep (by decide) (by decide) (by decide) entry.outputRead)
    (keep (by decide) (by decide) (by decide) entry.capacityRead) kindRead startRead finishRead stable backingScope
  exact ⟨first, second, written, fields_valid program.core entry.token entry.sourceLength entry.ordered entry.within
    kindRead startRead finishRead (keep (by decide) (by decide) (by decide) entry.sourceRead),
    firstRun, secondRun, thirdRun, cursor, backing, effect⟩

end Lanius.Extraction.CompactOutput.Tokens
