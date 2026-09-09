import Lanius.Extraction.CompactOutput.Bytes.State

namespace Lanius.Extraction.CompactOutput.Bytes

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

def encoding (values : List Nat) : List Nat :=
  values.flatMap (fun value => [hexDigit (value / 16), hexDigit (value % 16)])

theorem encoding_cons (value : Nat) (rest : List Nat) :
    encoding (value :: rest) = [hexDigit (value / 16), hexDigit (value % 16)] ++ encoding rest := rfl

/-- Execute all remaining source bytes, stopping at the first capacity error.
The remaining list is the actual input suffix, not a separate assumed trace. -/
theorem execute_loop (hex : CheckedHexByte program byte digit)
    (remaining : List Nat) (owned : Owned memory index position contents before)
    (suffix : memory.values.drop index = remaining) :
    ∃ after, Executes program.core before (loop hex.source.function.id)
        (appendAll memory.capacity (encoding remaining) position contents).completion after ∧
      (∃ finalIndex, Owned memory finalIndex
        (appendAll memory.capacity (encoding remaining) position contents).position
        (appendAll memory.capacity (encoding remaining) position contents).contents after) ∧
      CellEffect memory.writes before after := by
  induction remaining generalizing index position contents before with
  | nil =>
    have finished : index = memory.values.length := by
      have length := congrArg List.length suffix
      simp only [List.length_drop, List.length_nil] at length
      have := owned.bound
      omega
    exact ⟨before, executesWhileFalse (by simpa only [finished, ne_eq, not_true_eq_false, decide_false] using owned.condition program.core),
      ⟨index, owned⟩, CellEffect.refl owned.wellFormed⟩
  | cons value rest ih =>
    have bound : index < memory.values.length := by
      have length := congrArg List.length suffix
      simp only [List.length_drop, List.length_cons] at length
      omega
    have selected : memory.values[index] = value ∧ memory.values.drop (index + 1) = rest := by
      rw [List.drop_eq_getElem_cons bound] at suffix
      exact List.cons.inj suffix
    have conditionRun : Evaluates program.core before condition (.boolean true) before := by
      simpa only [ne_eq, show index ≠ memory.values.length by omega, not_false_eq_true, decide_true] using owned.condition program.core
    obtain ⟨written, assigned, writtenOwned, writeEffect⟩ := owned.append hex bound
    rw [selected.1] at writtenOwned
    have guardRun := writtenOwned.failureGuard program.core
    have encoded := appendAll_append memory.capacity
      [hexDigit (value / 16), hexDigit (value % 16)] (encoding rest) position contents
    rw [appendAll_hexByte] at encoded
    by_cases failed : hexBytePosition memory.capacity position < 0
    · have nextEq : hexBytePosition memory.capacity position = -1 := by
        unfold hexBytePosition nextPosition at failed ⊢
        split <;> split <;> simp_all <;> omega
      have run : Executes program.core before (loop hex.source.function.id)
          (.returned (some (.signed .i32 (-1)))) written := executesWhileReturned conditionRun
        (executesSequence (executesExpression assigned) (executesSequenceReturned
          (executesIfTrue (by simpa only [failed, decide_true] using guardRun)
            (executesSequenceReturned (executesReturnValue (negativeOne_evaluates program.core written))))))
      rw [if_pos failed] at encoded
      refine ⟨written, ?_, ⟨index, ?_⟩, writeEffect⟩
      · simpa only [encoding_cons, encoded, AppendOutcome.resume, AppendOutcome.completion] using run
      · rw [nextEq] at writtenOwned
        simpa only [encoding_cons, encoded, AppendOutcome.resume, AppendOutcome.position, AppendOutcome.contents] using writtenOwned
    · obtain ⟨advanced, incremented, advancedOwned, advanceEffect⟩ := writtenOwned.increment program.core bound
      obtain ⟨after, restRun, finalOwned, restEffect⟩ := ih advancedOwned selected.2
      have stepped : Executes program.core before (step hex.source.function.id) .next advanced :=
        executesSequence (executesExpression assigned) (executesSequence
          (executesIfFalse (by simpa only [failed, decide_false] using guardRun) (executesSkip _ _))
          (executesSequence (executesExpression incremented) (executesSkip _ _)))
      rw [if_neg failed] at encoded
      exact ⟨after,
        by simpa only [encoding_cons, encoded, AppendOutcome.resume, loop] using executesWhileTrueThen conditionRun stepped restRun,
        by simpa only [encoding_cons, encoded, AppendOutcome.resume] using finalOwned,
        writeEffect.trans (advanceEffect.trans restEffect)⟩

end Lanius.Extraction.CompactOutput.Bytes
