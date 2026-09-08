import Lanius.Extraction.SemanticTokens.Collect.TokenAdvance
import Lanius.Separation.SliceStore

namespace Lanius.Extraction.SemanticTokens.Collect

open Lanius Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.Compiler.Parser

/-- The tail of the checked token branch, after its four lexical bindings. -/
def assignmentTail : Stmt :=
  .sequence (reject (binary .notEqual (atIndex 8 (read 23)) (negative 1)))
    (.sequence (.expression (.assign .set (.index (.local 8) (read 23)) (read 20)))
      (.sequence tokenAdvance .skip))

/-- An unused assignment slot receives exactly the semantic kind, then the
actual token scan advances the cursor. The outer traversal must establish
`available` from unique slots and its visited-prefix invariant. -/
theorem token_store_execute {use : Use} {raw canonical : Nat}
    (data : GrammarData) (program : Program)
    (valid : use.Valid data.grammar tokens)
    (rawFound : tokens[use.token]? = some raw)
    (canonicalFound : data.grammar.grammar.canonical_kinds[use.kind]? = some canonical)
    (wellFormed : StateWellFormed before) (owned : data.Owns grammarCell before)
    (cursor : (Assertion.localPointsTo 16 cursorCell (some (.signed .i32 use.position))).holds before)
    (kindRead : before.local? 20 = some (.signed .i32 use.kind))
    (rawRead : before.local? 21 = some (.signed .i32 raw))
    (canonicalRead : before.local? 22 = some (.signed .i32 canonical))
    (slotRead : before.local? 23 = some (.signed .i32 use.slot))
    (outputLocal : before.local? 8 = some (.slice i32 outputCell [] 0 values.length))
    (backing : before.cellEntry? outputCell = some {
      id := outputCell, value := some (.array (signedI32Values values)) })
    (available : values[use.slot]? = some (-1))
    (grammarSeparate : grammarCell ≠ outputCell)
    (bounded : use.finish ≤ 2147483647) :
    ∃ after, Executes program before assignmentTail .next after ∧
      (Assertion.localPointsTo 16 cursorCell (some (.signed .i32 use.finish))).holds after ∧
      after.cellEntry? outputCell = some {
        id := outputCell, value := some (.array (signedI32Values (values.set use.slot use.kind))) } ∧
      CellEffect (CellSet.union (CellSet.singleton outputCell) (CellSet.singleton cursorCell)) before after := by
  have outputOwned : I32PrefixLocal before 8 outputCell values :=
    ⟨values.length, outputLocal, [], by simp, by simpa using backing⟩
  have slot := local_evaluates program slotRead
  have slotValue := read_word program outputOwned (read 23) use.slot available slot
  have guard : Evaluates program before
      (binary .notEqual (atIndex 8 (read 23)) (negative 1)) (.boolean false) before :=
    evaluatesEagerBinary (by decide) (by decide) slotValue (negativeOne_evaluates program before) rfl
  have cursorRead := Assertion.localPointsTo_local _ _ _ _ cursor
  have cursorSeparate : cursorCell ≠ outputCell :=
    local_cell_ne_of_distinct_value cursorRead backing (by intro impossible; cases impossible) cursor.1
  obtain ⟨written, assigned, contents, writeEffect⟩ := evaluatesSliceStore program before before values 8
    (read 23) (read 20) outputCell use.slot use.kind wellFormed
    (List.getElem?_eq_some_iff.mp available).1 outputLocal slot (local_evaluates program kindRead)
    (CellEffect.refl wellFormed) backing
  have cursorStill := writeEffect.preserves_localPointsTo wellFormed cursor cursorSeparate
  have rawStill := writeEffect.preserves_local_of_distinct_value wellFormed rawRead backing
    (by intro impossible; cases impossible)
  have canonicalStill := writeEffect.preserves_local_of_distinct_value wellFormed canonicalRead backing
    (by intro impossible; cases impossible)
  have grammarStill : data.Owns grammarCell written := by
    apply owned.transport
    · intro capacity found
      exact writeEffect.preserves_local_of_distinct_value wellFormed found backing
        (by intro impossible; cases impossible)
    · intro value found
      exact writeEffect.preserves_entry wellFormed found grammarSeparate
  obtain ⟨after, advanced, cursorAfter, advanceEffect⟩ := token_advance_execute data program valid
    rawFound canonicalFound writeEffect.wellFormed grammarStill cursorStill rawStill canonicalStill bounded
  refine ⟨after, ?_, cursorAfter,
    advanceEffect.preserves_entry writeEffect.wellFormed contents (Ne.symm cursorSeparate),
    (writeEffect.weaken CellSet.subset_union_left).trans (advanceEffect.weaken CellSet.subset_union_right)⟩
  exact executesSequence (executesIfFalse guard (executesSkip _ _))
    (executesSequence (executesExpression assigned) (executesSequence advanced (executesSkip _ _)))

end Lanius.Extraction.SemanticTokens.Collect
