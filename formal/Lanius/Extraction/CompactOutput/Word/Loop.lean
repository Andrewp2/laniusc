import Lanius.Extraction.CompactOutput.Word.Step

namespace Lanius.Extraction.CompactOutput.Word

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

/-- An early full-buffer result stops the actual loop, whereas an empty
remaining suffix completes normally. No iteration is supplied as a premise. -/
theorem execute_loop (byte : CheckedByte program) (digit : CheckedDigit program)
    (owned : Owned memory remaining position contents before) (bounded : remaining ≤ 8) :
    ∃ after, Executes program.core before (loop byte.source.function.id digit.source.function.id)
        (appendAll memory.capacity (hexDigits memory.value remaining) position contents).completion after ∧
      (∃ left, Owned memory left
        (appendAll memory.capacity (hexDigits memory.value remaining) position contents).position
        (appendAll memory.capacity (hexDigits memory.value remaining) position contents).contents after) ∧
      CellEffect memory.writes before after := by
  induction remaining generalizing before position contents with
  | zero =>
    exact ⟨before, executesWhileFalse (by simpa using owned.condition program.core),
      ⟨0, owned⟩, CellEffect.refl owned.wellFormed⟩
  | succ remaining ih =>
    have conditionRun : Evaluates program.core before condition (.boolean true) before := by
      simpa using owned.condition program.core
    obtain ⟨written, assigned, writtenOwned, writeEffect⟩ := append byte digit owned (by omega)
    have guardRun := writtenOwned.failureGuard program.core
    by_cases failed : nextPosition memory.capacity position < 0
    · have nextEq : nextPosition memory.capacity position = -1 := by
        by_cases room : 0 ≤ position ∧ position < memory.capacity
        · simp only [nextPosition, if_pos room] at failed
          omega
        · simp only [nextPosition, if_neg room]
      have run : Executes program.core before (loop byte.source.function.id digit.source.function.id)
          (.returned (some (.signed .i32 (-1)))) written := executesWhileReturned conditionRun
        (executesSequence (executesExpression assigned) (executesSequenceReturned
          (executesIfTrue (by simpa only [failed, decide_true] using guardRun)
            (executesSequenceReturned (executesReturnValue (negativeOne_evaluates program.core written))))))
      refine ⟨written, ?_, ⟨remaining + 1, ?_⟩, writeEffect⟩
      · simpa only [hexDigits, appendAll, if_pos failed, AppendOutcome.completion] using run
      · rw [nextEq] at writtenOwned
        simpa only [hexDigits, appendAll, if_pos failed, AppendOutcome.position, AppendOutcome.contents] using writtenOwned
    · obtain ⟨shifted, decremented, shiftedOwned, shiftEffect⟩ := writtenOwned.decrement (by omega) program.core
      obtain ⟨after, rest, finalOwned, restEffect⟩ := ih shiftedOwned (by omega)
      have stepped : Executes program.core before (step byte.source.function.id digit.source.function.id) .next shifted :=
        executesSequence (executesExpression assigned) (executesSequence
          (executesIfFalse (by simpa only [failed, decide_false] using guardRun) (executesSkip _ _))
          (executesSequence (executesExpression decremented) (executesSkip _ _)))
      exact ⟨after,
        by simpa only [hexDigits, appendAll, if_neg failed, loop] using executesWhileTrueThen conditionRun stepped rest,
        by simpa only [hexDigits, appendAll, if_neg failed] using finalOwned,
        writeEffect.trans (shiftEffect.trans restEffect)⟩

end Lanius.Extraction.CompactOutput.Word
