import Lanius.Extraction.CanonicalTokens.Kind.Source

namespace Lanius.Extraction.CanonicalTokens.Kind

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts

def result (source : List Int) (rawKind : Int) (start width : Nat) : Int :=
  if rawKind = 1 then Dispatch.lookup ((source.drop start).take width) Dispatch.referenceRows 1 else rawKind

theorem token_code_range (kind : Lanius.Compiler.TokenKind) :
    -2147483648 ≤ (kind.gpuCode : Int) ∧ (kind.gpuCode : Int) ≤ 2147483647 := by
  cases kind <;> decide

private theorem lookup_range (query : List Int) (table : List Dispatch.Row) (fallback : Int)
    (fallbackBound : -2147483648 ≤ fallback ∧ fallback ≤ 2147483647)
    (bounded : ∀ row ∈ table, -2147483648 ≤ row.2 ∧ row.2 ≤ 2147483647) :
    -2147483648 ≤ Dispatch.lookup query table fallback ∧
      Dispatch.lookup query table fallback ≤ 2147483647 := by
  induction table with
  | nil => exact fallbackBound
  | cons row rest ih =>
      simp only [Dispatch.lookup]
      split
      · exact bounded row (by simp)
      · exact ih (fun other member => bounded other (List.mem_cons_of_mem _ member))

theorem result_range (source : List Int) (rawKind : Int) (start width : Nat)
    (bounded : -2147483648 ≤ rawKind ∧ rawKind ≤ 2147483647) :
    -2147483648 ≤ result source rawKind start width ∧ result source rawKind start width ≤ 2147483647 := by
  unfold result
  split
  · apply lookup_range _ _ _ (by decide)
    intro row member
    obtain ⟨rule, _, rfl⟩ := List.mem_map.mp member
    exact token_code_range rule.kind
  · exact bounded

theorem Checked.executes_body (checked : Checked program functionId keywordId matcher)
    (before : State) (sourceCell : CellId) (source : List Int) (rawKind : Int) (start width : Nat)
    (wellFormed : StateWellFormed before)
    (sourceLocal : before.local? 0 = some
      (.slice (.scalar (.signed .i32)) sourceCell [] 0 source.length))
    (sourceContents : before.cellEntry? sourceCell = some {
      id := sourceCell, value := some (.array (signedI32Values source)) })
    (rawLocal : before.local? 1 = some (.signed .i32 rawKind))
    (startLocal : before.local? 2 = some (.signed .i32 start))
    (endLocal : before.local? 3 = some (.signed .i32 (start + width)))
    (capacity : start + width ≤ source.length) (bounded : source.length ≤ 2147483647) :
    ∃ after, Executes program before (body keywordId checked.identifier)
      (.returned (some (.signed .i32 (result source rawKind start width)))) after ∧ CellEffect CellSet.empty before after ∧
      Host.MemoryFrame before after := by
  have rawResult : Evaluates program before (.local 1) (.signed .i32 rawKind) before :=
    ⟨1, evalLocal_of_local 0 program before _ _ rawLocal⟩
  have identifierResult : Evaluates program before (.constant checked.identifier) (.signed .i32 1) before := by
    refine ⟨1, ?_⟩
    rw [evalExpr.eq_def]
    simp only [checked.identifierFound]
  have tested : Evaluates program before (condition checked.identifier) (.boolean (rawKind == 1)) before :=
    evaluatesEagerBinary (by decide) (by decide) rawResult identifierResult (by rfl)
  by_cases identifier : rawKind = 1
  · have yes : Evaluates program before (condition checked.identifier) (.boolean true) before := by
      simpa only [identifier, BEq.rfl] using tested
    have sourceResult : Evaluates program before (.local 0)
        (.slice (.scalar (.signed .i32)) sourceCell [] 0 source.length) before :=
      ⟨1, evalLocal_of_local 0 program before _ _ sourceLocal⟩
    have startResult : Evaluates program before (.local 2) (.signed .i32 start) before :=
      ⟨1, evalLocal_of_local 0 program before _ _ startLocal⟩
    have endResult : Evaluates program before (.local 3) (.signed .i32 (start + width)) before :=
      ⟨1, evalLocal_of_local 0 program before _ _ endLocal⟩
    have argumentsResult := ArgumentsEvaluateTo.cons sourceResult
      (ArgumentsEvaluateTo.cons startResult (ArgumentsEvaluateTo.singleton endResult))
    obtain ⟨after, called, frame, memory⟩ := checked.keyword.evaluates_call before sourceCell source start width arguments
      wellFormed sourceContents argumentsResult capacity bounded
    refine ⟨after, ?_, frame, memory⟩
    simp only [body, result, if_pos identifier]
    exact executesSequenceReturned (executesIfTrue yes (executesSequenceReturned (executesReturnValue called)))
  · have no : Evaluates program before (condition checked.identifier) (.boolean false) before := by
      simpa only [beq_eq_false_iff_ne.mpr identifier] using tested
    refine ⟨before, ?_, CellEffect.refl wellFormed, Host.MemoryFrame.refl before⟩
    simp only [body, result, if_neg identifier]
    exact executesSequence (executesIfFalse no (executesSkip program before))
      (executesSequenceReturned (executesReturnValue rawResult))

end Lanius.Extraction.CanonicalTokens.Kind
