import Lanius.Extraction.Parser.Derivation.Tail
import Lanius.Extraction.Parser.Derivation.Scopes

namespace Lanius.Extraction.ParserDerivation

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Compiler.Parser Lanius.Extraction.ParserRecognize

/-- The complete post-guard source section, including the slot initializer
    and lexical scope. Capacity bounds justify all arithmetic and stores;
    the caller's cursor cells survive scope restoration with updated values. -/
theorem ChildStores.execute_slot {workspace : LogicalWorkspace}
    (stores : ChildStores) (tail : CheckedCursorTail stores)
    (accessor : stores.accessor = extractedParserStateValueFunction.id)
    (selector : stores.selector = 36)
    (artifact : RecognizerWorkspaceArtifact layout workspace workspaceValues workspaceCell before)
    (wellFormed : StateWellFormed before)
    (found : workspace.state? stateId = some state)
    (distinctBuffers : outputCell ≠ workspaceCell)
    (fits : offset + 4 + count * 3 ≤ values.length)
    (capacityBound : values.length ≤ 2147483647)
    (remainingBound : remaining + 1 ≤ count)
    (freshSlot : ∀ localId ∈ [stores.output, stores.workspace, stores.base,
      stores.tag, stores.payload, stores.current, tail.remaining, tail.previous],
      stores.slot ≠ localId)
    (offsetLocal : before.local? offsetId = some (.signed .i32 (Int.ofNat offset)))
    (outputLocal : before.local? stores.output = some (.slice parserI32Type outputCell [] 0 values.length))
    (workspaceLocal : before.local? stores.workspace = some
      (.slice parserI32Type workspaceCell [] 0 workspaceValues.length))
    (baseLocal : before.local? stores.base = some (.signed .i32 (Int.ofNat (stateBase layout.tokenCount))))
    (tagLocal : before.local? stores.tag = some (.signed .i32 (childTag state.child)))
    (payloadLocal : before.local? stores.payload = some (.signed .i32 (childPayload state.child)))
    (currentOwned : (Assertion.localPointsTo stores.current currentCell
      (some (.signed .i32 (Int.ofNat stateId)))).holds before)
    (remainingOwned : (Assertion.localPointsTo tail.remaining remainingCell
      (some (.signed .i32 (Int.ofNat (remaining + 1))))).holds before)
    (distinctCursors : currentCell ≠ remainingCell)
    (previousLocal : before.local? tail.previous = some (.signed .i32 previous))
    (backing : before.cellEntry? outputCell = some {
      id := outputCell, value := some (.array (signedI32Values values)) }) :
    let slot := offset + 4 + remaining * 3
    ∃ after, Executes verifiedParserCore before
      (.letLocal stores.slot parserI32Type
        (.binary .add (.binary .add (.local offsetId) (.value (.signed .i32 4)))
          (.binary .multiply
            (.binary .subtract (.local tail.remaining) (.value (.signed .i32 1)))
            (.value (.signed .i32 3)))) stores.body) .next after ∧
      (Assertion.localPointsTo stores.current currentCell (some (.signed .i32 previous))).holds after ∧
      (Assertion.localPointsTo tail.remaining remainingCell
        (some (.signed .i32 (Int.ofNat remaining)))).holds after ∧
      RecognizerWorkspaceArtifact layout workspace workspaceValues workspaceCell after ∧
      after.cellEntry? outputCell = some {
        id := outputCell, value := some (.array (signedI32Values
          (((values.set slot (childTag state.child)).set (slot + 1)
            (childPayload state.child)).set (slot + 2) (childKind state.child)))) } ∧
      CellEffect (CellSet.union (CellSet.singleton outputCell)
        (CellSet.union (CellSet.singleton currentCell) (CellSet.singleton remainingCell))) before after := by
  let slot := offset + 4 + remaining * 3
  let value := Value.signed .i32 (Int.ofNat slot)
  let entered := before.bindLocal stores.slot value
  have localRead {localId : VarId} {word : Value} (h : before.local? localId = some word) :
      Evaluates verifiedParserCore before (.local localId) word before :=
    ⟨1, evalLocal_of_local 0 verifiedParserCore before localId word h⟩
  have initializer := output_slot_expression (localRead offsetLocal)
    (localRead (Assertion.localPointsTo_local _ _ _ _ remainingOwned))
    (count := (count : Int)) (capacity := (values.length : Int))
    (by change 0 ≤ (offset : Int); omega)
    (by change (offset : Int) + 4 + (count : Int) * 3 ≤ (values.length : Int); omega)
    (by change (values.length : Int) ≤ 2147483647; omega)
    (by change 0 < ((remaining + 1 : Nat) : Int); omega)
    (by change ((remaining + 1 : Nat) : Int) ≤ (count : Int); omega)
  have slotEq : Int.ofNat offset + 4 + (Int.ofNat (remaining + 1) - 1) * 3 = Int.ofNat slot := by
    simp [slot, Int.natCast_add, Int.natCast_mul]
  rw [slotEq] at initializer
  have preserve {localId : VarId} {word : Value}
      (member : localId ∈ [stores.output, stores.workspace, stores.base,
        stores.tag, stores.payload, stores.current, tail.remaining, tail.previous])
      (h : before.local? localId = some word) : entered.local? localId = some word :=
    (bindLocal_preserves_other_local wellFormed (freshSlot localId member)).trans h
  have enteredCurrent := bindLocal_preserves_localPointsTo_of_ne before stores.slot stores.current
    value currentCell _ wellFormed (freshSlot _ (by simp)) currentOwned
  have enteredRemaining := bindLocal_preserves_localPointsTo_of_ne before stores.slot tail.remaining
    value remainingCell _ wellFormed (freshSlot _ (by simp)) remainingOwned
  have enteredBacking : entered.cellEntry? outputCell = some {
      id := outputCell, value := some (.array (signedI32Values values)) } :=
    ((bindLocal_effect before stores.slot value).oldCells outputCell
      (StateWellFormed.cell_lt_next_of_entry wellFormed backing)
      (by simp [CellSet.empty])).trans backing
  obtain ⟨completed, execution, currentAfter, remainingAfter, artifactAfter, backingAfter, effect⟩ :=
    stores.execute_tail tail accessor selector (artifact.bind_local wellFormed stores.slot value)
      (bindLocal_preserves_well_formed _ _ _ wellFormed) found distinctBuffers
      (slot := slot) (by dsimp [slot]; omega) (by dsimp [slot]; omega)
      (preserve (by simp) outputLocal) (preserve (by simp) workspaceLocal)
      (preserve (by simp) baseLocal) (bindLocal_finds_local before stores.slot value wellFormed)
      (preserve (by simp) tagLocal) (preserve (by simp) payloadLocal)
      enteredCurrent enteredRemaining distinctCursors (preserve (by simp) previousLocal)
      (by omega) enteredBacking
  refine ⟨restoreLocals before completed, executesLetLocal initializer execution,
    ⟨currentOwned.1, currentAfter.2⟩, ⟨remainingOwned.1, remainingAfter.2⟩,
    artifactAfter.transfer_cells rfl, backingAfter, ?_⟩
  exact CellEffect.closeLocal before stores.slot value wellFormed effect

end Lanius.Extraction.ParserDerivation
