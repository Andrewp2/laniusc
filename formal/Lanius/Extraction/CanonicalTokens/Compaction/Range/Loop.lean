import Lanius.Extraction.CanonicalTokens.Compaction.Range.Advance

namespace Lanius.Extraction.CanonicalTokens.Compaction.Range

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Compiler Lanius.Compiler.Lexer CanonicalizeModel

private theorem condition_result (program : Program) (request : Request) (completed remaining : List RawToken)
    (invariant : LoopState request completed remaining before) :
    Evaluates program before (.binary .less (add (.local 10) (literal 1)) (.local 4))
      (.boolean (decide (completed.length + 1 < request.count))) before := by
  have cursorResult : Evaluates program before (.local 10) (.signed .i32 completed.length) before :=
    ⟨1, evalLocal_of_local 0 program before 10 _ (Assertion.localPointsTo_local _ _ _ _ invariant.cursor)⟩
  have countResult : Evaluates program before (.local 4) (.signed .i32 request.count) before :=
    ⟨1, evalLocal_of_local 0 program before 4 _ invariant.count⟩
  have nextResult := evaluatesNatI32Add (rightValue := 1) cursorResult
    (show Evaluates program before (literal 1) (.signed .i32 1) before from ⟨1, rfl⟩)
    (by have := invariant.length; have := request.recordsFit; omega)
  apply evaluatesEagerBinary (by decide) (by decide) nextResult countResult
  simp [evalBinaryValue, evalSignedBinary]
  omega

/-- Total correctness of the inclusive-range pass, including empty and
singleton streams. The assignment row following a marked range is retained. -/
theorem executes_loop (table : Table program tokens) (request : Request)
    (completed remaining : List RawToken) (before : State)
    (invariant : LoopState request completed remaining before) :
    ∃ after, Executes program before (rangeLoop tokens) .next after ∧
      Storage after request.sourceCell request.recordsCell request.source
        (buffer [] (completed ++ retagInclusiveRanges remaining) request.unused) ∧
      after.local? 4 = some (.signed .i32 request.count) ∧ CellEffect request.writes before after := by
  have condition := condition_result program request completed remaining invariant
  cases remaining with
  | nil =>
      have done : ¬ completed.length + 1 < request.count := by have := invariant.length; simp_all
      refine ⟨before, executesWhileFalse ?_, ?_, invariant.count, CellEffect.refl invariant.storage.wellFormed⟩
      · simpa only [done, decide_false] using condition
      · simpa [buffer, retagInclusiveRanges] using invariant.storage
  | cons current rest =>
      cases rest with
      | nil =>
          have done : ¬ completed.length + 1 < request.count := by have := invariant.length; simp_all
          refine ⟨before, executesWhileFalse ?_, ?_, invariant.count, CellEffect.refl invariant.storage.wellFormed⟩
          · simpa only [done, decide_false] using condition
          · simpa [buffer, retagInclusiveRanges] using invariant.storage
      | cons next rest =>
          have more : completed.length + 1 < request.count := by
            have length := invariant.length
            simp only [List.length_cons] at length
            omega
          have conditionTrue : Evaluates program before
              (.binary .less (add (.local 10) (literal 1)) (.local 4)) (.boolean true) before := by
            simpa only [more, decide_true] using condition
          obtain ⟨middle, step, nextInvariant, stepEffect⟩ := advances table request completed current next rest invariant
          obtain ⟨after, loop, finalStorage, count, loopEffect⟩ := executes_loop table request
            (completed ++ [retag current next]) (next :: rest) middle nextInvariant
          refine ⟨after, executesWhileTrue conditionTrue step loop, ?_, count, stepEffect.trans loopEffect⟩
          simpa only [retag_specification, List.append_assoc, List.singleton_append] using finalStorage
termination_by remaining.length

theorem loop_sound (table : Table program tokens) (request : Request)
    (completed remaining : List RawToken) (before after : State)
    (invariant : LoopState request completed remaining before)
    (actual : Executes program before (rangeLoop tokens) completion after) :
    completion = .next ∧ Storage after request.sourceCell request.recordsCell request.source
        (buffer [] (completed ++ retagInclusiveRanges remaining) request.unused) ∧
      after.local? 4 = some (.signed .i32 request.count) ∧ CellEffect request.writes before after := by
  obtain ⟨expected, run, storage, count, effect⟩ := executes_loop table request completed remaining before invariant
  obtain ⟨sameCompletion, sameState⟩ := Lanius.Fuel.executes_deterministic actual run
  subst after
  exact ⟨sameCompletion, storage, count, effect⟩

end Lanius.Extraction.CanonicalTokens.Compaction.Range
