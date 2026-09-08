import Lanius.Extraction.Parser.Derivation.Advance

namespace Lanius.Extraction.ParserDerivation

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Compiler.Parser Lanius.Extraction.ParserRecognize

def ReaderRuntime.cursorBindings (reader : ReaderRuntime) (stateId count : Nat) : List (VarId × Value) :=
  [(reader.stores.current, .signed .i32 (Int.ofNat stateId)),
    (reader.tail.remaining, .signed .i32 (Int.ofNat count))]

def ReaderRuntime.allocatedCursors (reader : ReaderRuntime) (before : State) : ReaderRuntime :=
  { reader with currentCell := before.nextCell, remainingCell := before.nextCell + 1 }

/-- Reader resources after the header stores, before allocating either
    mutable cursor. No cursor ownership or non-aliasing is assumed here. -/
structure ReaderRuntime.BeforeCursor (reader : ReaderRuntime) (runtime : State) : Prop where
  wellFormed : StateWellFormed runtime
  artifact : RecognizerWorkspaceArtifact reader.layout reader.workspace
    reader.workspaceValues reader.workspaceCell runtime
  outputLocal : runtime.local? reader.stores.output = some
    (.slice parserI32Type reader.outputCell [] 0 reader.outputValues.length)
  workspaceLocal : runtime.local? reader.stores.workspace = some
    (.slice parserI32Type reader.workspaceCell [] 0 reader.workspaceValues.length)
  baseLocal : runtime.local? reader.stores.base = some
    (.signed .i32 (Int.ofNat (stateBase reader.layout.tokenCount)))
  offsetLocal : runtime.local? reader.offsetId = some (.signed .i32 (Int.ofNat reader.offset))
  tokenCountLocal : runtime.local? reader.tokenCountId = some (.signed .i32 (Int.ofNat reader.tokenCount))
  backing : runtime.cellEntry? reader.outputCell = some {
    id := reader.outputCell, value := some (.array (signedI32Values reader.outputValues)) }

/-- Every other local still refers below the original allocation frontier.
    This also supplies separation for production, origin, and saved count. -/
theorem ReaderRuntime.cursor_binding_old (reader : ReaderRuntime) (wellFormed : StateWellFormed before)
    (currentDifferent : reader.stores.current ≠ localId) (remainingDifferent : reader.tail.remaining ≠ localId)
    (binding : (before.bindLocals (reader.cursorBindings stateId count)).cellId? localId = some cell) :
    cell < before.nextCell := by
  have unchanged := bindLocals_preserves_cellId before (reader.cursorBindings stateId count) localId (by
    intro binding member
    simp only [ReaderRuntime.cursorBindings, List.mem_cons, List.not_mem_nil, or_false] at member
    rcases member with rfl | rfl
    · exact currentDifferent
    · exact remainingDifferent)
  exact StateWellFormed.cell_lt_next_of_local_binding localId cell wellFormed (unchanged ▸ binding)

/-- Allocate the two source cursor locals and derive the entire runtime
    frame and its stable-local separation from freshness of their names. -/
theorem ReaderRuntime.BeforeCursor.allocate {reader : ReaderRuntime}
    (entry : reader.BeforeCursor before)
    (different : reader.stores.current ≠ reader.tail.remaining)
    (currentFresh : reader.stores.current ∉ reader.readonlyLocals)
    (remainingFresh : reader.tail.remaining ∉ reader.readonlyLocals)
    (stateId count : Nat) :
    (reader.allocatedCursors before).At stateId count (before.bindLocals (reader.cursorBindings stateId count)) ∧
    (reader.allocatedCursors before).StableLocals (before.bindLocals (reader.cursorBindings stateId count)) ∧
    (reader.allocatedCursors before).currentCell ≠ (reader.allocatedCursors before).remainingCell := by
  have currentNe {localId : VarId} (member : localId ∈ reader.readonlyLocals) : reader.stores.current ≠ localId := by
    intro same
    exact currentFresh (same ▸ member)
  have remainingNe {localId : VarId} (member : localId ∈ reader.readonlyLocals) : reader.tail.remaining ≠ localId := by
    intro same
    exact remainingFresh (same ▸ member)
  have preserve {localId : VarId} {value : Value} (member : localId ∈ reader.readonlyLocals)
      (found : before.local? localId = some value) :
      (before.bindLocals (reader.cursorBindings stateId count)).local? localId = some value := by
    apply bindLocals_preserves_local before (reader.cursorBindings stateId count) localId value entry.wellFormed found
    intro binding present
    simp only [ReaderRuntime.cursorBindings, List.mem_cons, List.not_mem_nil, or_false] at present
    rcases present with rfl | rfl
    · exact currentNe member
    · exact remainingNe member
  have cells {cell : CellId} {value : Value}
      (found : before.cellEntry? cell = some { id := cell, value := some value }) :
      (before.bindLocals (reader.cursorBindings stateId count)).cellEntry? cell = some {
        id := cell, value := some value } :=
    (bindLocals_preserves_old_cell before _ cell
      (StateWellFormed.cell_lt_next_of_entry entry.wellFormed found)).trans found
  have currentOwned := bindLocals_owns_binding before []
    [(reader.tail.remaining, .signed .i32 (Int.ofNat count))]
    reader.stores.current (.signed .i32 (Int.ofNat stateId)) entry.wellFormed (by
      intro binding member
      simp only [List.mem_singleton] at member
      subst binding
      exact Ne.symm different)
  have remainingOwned := bindLocals_owns_binding before
    [(reader.stores.current, .signed .i32 (Int.ofNat stateId))] []
    reader.tail.remaining (.signed .i32 (Int.ofNat count)) entry.wellFormed (by simp)
  refine ⟨⟨bindLocals_preserves_wellFormed _ _ entry.wellFormed,
    ⟨entry.artifact.workspaceLength, entry.artifact.workspaceEncoded, cells entry.artifact.workspaceBacking⟩,
    preserve (by simp [ReaderRuntime.readonlyLocals, ReaderRuntime.allocatedCursors]) entry.outputLocal,
    preserve (by simp [ReaderRuntime.readonlyLocals, ReaderRuntime.allocatedCursors]) entry.workspaceLocal,
    preserve (by simp [ReaderRuntime.readonlyLocals, ReaderRuntime.allocatedCursors]) entry.baseLocal,
    preserve (by simp [ReaderRuntime.readonlyLocals, ReaderRuntime.allocatedCursors]) entry.offsetLocal,
    preserve (by simp [ReaderRuntime.readonlyLocals, ReaderRuntime.allocatedCursors]) entry.tokenCountLocal,
    ?_, ?_, cells entry.backing⟩, ?_, ?_⟩
  · simpa only [ReaderRuntime.allocatedCursors, ReaderRuntime.cursorBindings, List.nil_append,
      List.length_nil, Nat.add_zero] using currentOwned
  · simpa only [ReaderRuntime.allocatedCursors, ReaderRuntime.cursorBindings, List.length_singleton,
      List.cons_append, List.nil_append] using remainingOwned
  · intro localId member cell binding
    have old := reader.cursor_binding_old entry.wellFormed (currentNe member) (remainingNe member) binding
    change cell ≠ before.nextCell ∧ cell ≠ before.nextCell + 1
    exact ⟨Nat.ne_of_lt old, Nat.ne_of_lt (Nat.lt_succ_of_lt old)⟩
  · change before.nextCell ≠ before.nextCell + 1
    exact Nat.ne_of_lt (Nat.lt_succ_self _)

/-- Execute the two source declarations around a checked continuation.
    Cursor mutations are writes to fresh private cells and disappear from
    the caller-visible footprint when both lexical scopes close. -/
theorem ReaderRuntime.BeforeCursor.with_cursors {reader : ReaderRuntime}
    {post : List Cell → Prop}
    (entry : reader.BeforeCursor before)
    (different : reader.stores.current ≠ reader.tail.remaining)
    (currentFresh : reader.stores.current ∉ reader.readonlyLocals)
    (remainingFresh : reader.tail.remaining ∉ reader.readonlyLocals)
    (stateLocal : before.local? stateIdLocal = some (.signed .i32 (Int.ofNat stateId)))
    (countLocal : before.local? countId = some (.signed .i32 (Int.ofNat count)))
    (countUnshadowed : reader.stores.current ≠ countId)
    (continuation :
      let allocated := reader.allocatedCursors before
      let entered := before.bindLocals (reader.cursorBindings stateId count)
      allocated.At stateId count entered → allocated.StableLocals entered →
      allocated.currentCell ≠ allocated.remainingCell →
      ∃ completed, Executes verifiedParserCore entered body completion completed ∧
        post completed.cells ∧
        CellEffect (CellSet.union (CellSet.singleton reader.outputCell)
          (CellSet.union (CellSet.singleton allocated.currentCell) (CellSet.singleton allocated.remainingCell)))
          entered completed) :
    ∃ after, Executes verifiedParserCore before
      (.letLocal reader.stores.current parserI32Type (.local stateIdLocal)
        (.letLocal reader.tail.remaining parserI32Type (.local countId) body)) completion after ∧
      post after.cells ∧ CellEffect (CellSet.singleton reader.outputCell) before after := by
  obtain ⟨held, stable, distinctCells⟩ := entry.allocate different currentFresh remainingFresh stateId count
  obtain ⟨completed, execution, result, effect⟩ := continuation held stable distinctCells
  let first := before.bindLocal reader.stores.current (.signed .i32 (Int.ofNat stateId))
  have firstWF := bindLocal_preserves_well_formed before reader.stores.current
    (.signed .i32 (Int.ofNat stateId)) entry.wellFormed
  have stateRead : Evaluates verifiedParserCore before (.local stateIdLocal)
      (.signed .i32 (Int.ofNat stateId)) before :=
    ⟨1, evalLocal_of_local 0 verifiedParserCore before stateIdLocal _ stateLocal⟩
  have countRead : Evaluates verifiedParserCore first (.local countId) (.signed .i32 (Int.ofNat count)) first :=
    ⟨1, evalLocal_of_local 0 verifiedParserCore first countId _
      ((bindLocal_preserves_other_local entry.wellFormed countUnshadowed).trans countLocal)⟩
  have bodyExecution : Executes verifiedParserCore
      (first.bindLocal reader.tail.remaining (.signed .i32 (Int.ofNat count))) body completion completed := execution
  have closed := CellEffect.closeLocal before reader.stores.current (.signed .i32 (Int.ofNat stateId))
    entry.wellFormed (CellEffect.closeLocal first reader.tail.remaining (.signed .i32 (Int.ofNat count)) firstWF effect)
  refine ⟨_, executesLetLocal stateRead (executesLetLocal countRead bodyExecution), result, closed.narrow ?_⟩
  intro cell old written
  rcases written with output | current | remaining
  · exact output
  · change cell = before.nextCell at current
    exact False.elim ((Nat.ne_of_lt old) current)
  · change cell = before.nextCell + 1 at remaining
    exact False.elim ((Nat.ne_of_lt (Nat.lt_succ_of_lt old)) remaining)

end Lanius.Extraction.ParserDerivation
