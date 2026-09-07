import Lanius.Extraction.CanonicalTokens.Compaction.Body

namespace Lanius.Extraction.CanonicalTokens.Compaction

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.Compiler Lanius.Compiler.Lexer CanonicalizeModel

/-- Callable correctness of the source-checked canonicalizer. Argument
evaluation is pure; helper calls may allocate but cannot modify other caller cells. -/
theorem CheckedSource.evaluates_call
    (checked : CheckedSource program functionId triviaId kindId keywordId matcher)
    (before : State) (sourceCell recordsCell : CellId) (source : List Byte)
    (raw : List RawToken) (unused : List Int) (expressions : List Expr)
    (wellFormed : StateWellFormed before)
    (sourceContents : before.cellEntry? sourceCell = some {
      id := sourceCell, value := some (.array (signedI32Values (sourceIntegers source))) })
    (recordsContents : before.cellEntry? recordsCell = some {
      id := recordsCell, value := some (.array (signedI32Values (encodeTokens raw ++ unused))) })
    (sourceRecords : sourceCell ≠ recordsCell)
    (sourceFits : source.length ≤ 2147483647) (recordsFit : 3 * raw.length + unused.length ≤ 2147483647)
    (spans : ∀ token ∈ raw, token.start ≤ token.finish ∧ token.finish ≤ source.length)
    (argumentsResult : ArgumentsEvaluateTo program before expressions [
      .slice (.scalar (.signed .i32)) sourceCell [] 0 source.length,
      .slice (.scalar (.signed .i32)) recordsCell [] 0 (3 * raw.length + unused.length),
      .signed .i32 raw.length] before) :
    ∃ after, Evaluates program before (.call functionId expressions)
        (.signed .i32 (canonicalizeTokens source raw).length) after ∧
      after.cellEntry? recordsCell = some {
        id := recordsCell, value := some (.array (signedI32Values (compactedBuffer raw unused (canonicalizeTokens source raw)))) } ∧
      CellEffect (CellSet.singleton recordsCell) before after := by
  let sourceValue := Value.slice (.scalar (.signed .i32)) sourceCell [] 0 source.length
  let recordsValue := Value.slice (.scalar (.signed .i32)) recordsCell [] 0 (3 * raw.length + unused.length)
  let bindings : List (VarId × Value) := [(0, sourceValue), (1, recordsValue), (2, .signed .i32 raw.length)]
  let entered := enterCall before bindings
  have enteredWF : StateWellFormed entered := enterCall_preserves_wellFormed wellFormed
  have enterEffect := enterCall_effect before bindings
  have sourceReady := (enterEffect.oldCells sourceCell
    (StateWellFormed.cell_lt_next_of_entry wellFormed sourceContents) (by simp [CellSet.empty])).trans sourceContents
  have recordsReady := (enterEffect.oldCells recordsCell
    (StateWellFormed.cell_lt_next_of_entry wellFormed recordsContents) (by simp [CellSet.empty])).trans recordsContents
  have sourceLocal : entered.local? 0 = some sourceValue :=
    enterCall_local_of_binding before [] [(1, recordsValue), (2, .signed .i32 raw.length)] 0 sourceValue wellFormed (by
      intro binding member
      simp only [List.mem_cons, List.not_mem_nil, or_false] at member
      rcases member with rfl | rfl <;> simp)
  have recordsLocal : entered.local? 1 = some recordsValue :=
    enterCall_local_of_binding before [(0, sourceValue)] [(2, .signed .i32 raw.length)] 1 recordsValue wellFormed (by
      intro binding member; simp_all)
  have countLocal : entered.local? 2 = some (.signed .i32 raw.length) :=
    enterCall_local_of_binding before [(0, sourceValue), (1, recordsValue)] [] 2 (.signed .i32 raw.length) wellFormed (by simp)
  have storage : Storage entered sourceCell recordsCell (sourceIntegers source) (encodeTokens raw ++ unused) := by
    refine ⟨enteredWF, ?_, ?_, sourceReady, recordsReady, ?_, ?_⟩
    · simpa [sourceValue, sourceIntegers] using sourceLocal
    · simpa [recordsValue] using recordsLocal
    · simpa [sourceIntegers] using sourceFits
    · simpa using recordsFit
  obtain ⟨completed, run, contents, effect⟩ := checked.executes_body source raw unused storage sourceRecords countLocal spans
  have parameters : bindParameters (sourceFunction functionId triviaId kindId checked.tokens).parameters
      [sourceValue, recordsValue, .signed .i32 raw.length] = some bindings := rfl
  have called := evaluatesCallReturned argumentsResult checked.found parameters rfl run
  exact ⟨restoreLocals before completed, called, contents, effect.closeCall before bindings wellFormed⟩

end Lanius.Extraction.CanonicalTokens.Compaction
