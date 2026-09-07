import Lanius.Extraction.CanonicalTokens.Compaction.Advance

namespace Lanius.Extraction.CanonicalTokens.Compaction

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Compiler Lanius.Compiler.Lexer

private theorem condition_result (program : Program) (request : Request) (processed : List RawToken)
    (invariant : LoopState request processed before) :
    Evaluates program before (.binary .less (.local 3) (.local 2))
      (.boolean (decide (processed.length < request.raw.length))) before := by
  have inputResult : Evaluates program before (.local 3) (.signed .i32 processed.length) before :=
    ⟨1, evalLocal_of_local 0 program before 3 _ (Assertion.localPointsTo_local _ _ _ _ invariant.input)⟩
  have countResult : Evaluates program before (.local 2) (.signed .i32 request.raw.length) before :=
    ⟨1, evalLocal_of_local 0 program before 2 _ invariant.count⟩
  apply evaluatesEagerBinary (by decide) (by decide) inputResult countResult
  simp [evalBinaryValue, evalSignedBinary]

/-- Total correctness of the complete filtering/keyword-retagging loop.
The independent lexer specification determines the resulting token prefix. -/
theorem executes_input_loop (trivia : Trivia.Checked program triviaId)
    (kind : Kind.Checked program kindId keywordId matcher)
    (request : Request) (processed remaining : List RawToken) (before : State)
    (shape : request.raw = processed ++ remaining) (invariant : LoopState request processed before) :
    ∃ after, Executes program before (inputLoop triviaId kindId) .next after ∧
      LoopState request request.raw after ∧ CellEffect request.writes before after := by
  have condition := condition_result program request processed invariant
  cases remaining with
  | nil =>
      have complete : request.raw = processed := by simpa using shape
      refine ⟨before, executesWhileFalse ?_, ?_, CellEffect.refl invariant.storage.wellFormed⟩
      · simpa [complete] using condition
      · simpa [complete] using invariant
  | cons token rest =>
      have more : processed.length < request.raw.length := by simp [shape]
      have conditionTrue : Evaluates program before (.binary .less (.local 3) (.local 2)) (.boolean true) before := by
        simpa only [more, decide_true] using condition
      obtain ⟨middle, step, next, stepEffect⟩ := advances trivia kind request processed token rest shape invariant
      have nextShape : request.raw = (processed ++ [token]) ++ rest := by simpa [List.append_assoc] using shape
      obtain ⟨after, loop, complete, loopEffect⟩ := executes_input_loop trivia kind request
        (processed ++ [token]) rest middle nextShape next
      exact ⟨after, executesWhileTrue conditionTrue step loop, complete, stepEffect.trans loopEffect⟩
termination_by remaining.length

theorem input_loop_sound (trivia : Trivia.Checked program triviaId)
    (kind : Kind.Checked program kindId keywordId matcher)
    (request : Request) (processed remaining : List RawToken) (before after : State)
    (shape : request.raw = processed ++ remaining) (invariant : LoopState request processed before)
    (actual : Executes program before (inputLoop triviaId kindId) completion after) :
    completion = .next ∧ LoopState request request.raw after ∧ CellEffect request.writes before after := by
  obtain ⟨expected, run, complete, effect⟩ := executes_input_loop trivia kind request processed remaining before shape invariant
  obtain ⟨sameCompletion, sameState⟩ := Lanius.Fuel.executes_deterministic actual run
  subst after
  exact ⟨sameCompletion, complete, effect⟩

end Lanius.Extraction.CanonicalTokens.Compaction
