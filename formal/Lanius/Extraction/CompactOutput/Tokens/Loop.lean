import Lanius.Extraction.CompactOutput.Tokens.State

namespace Lanius.Extraction.CompactOutput.Tokens

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Compiler.Lexer

def encodeAll (tokens : List RawToken) : List Nat :=
  tokens.flatMap (fun assignment => encoding assignment)

def Completed (memory : Memory) (outcome : AppendOutcome) (after : State) : Prop :=
  match outcome with
  | .done position contents => Owned memory memory.tokens.length position contents after
  | .full _ => True

/-- Execute the actual loop to the end of the input suffix or its first
capacity failure. No iteration or successful output is supplied as a premise. -/
theorem execute_loop (word : Word.Checked program byte digit) (remaining : List RawToken)
    (owned : Owned memory index position contents before)
    (suffix : memory.tokens.drop index = remaining) :
    ∃ after, Executes program.core before (loop word.source.function.id)
        (appendAll memory.capacity (encodeAll remaining) position contents).completion after ∧
      after.cellEntry? memory.outputCell = some {
        id := memory.outputCell, value := some (.array (signedI32Values
          (appendAll memory.capacity (encodeAll remaining) position contents).contents)) } ∧
      Completed memory (appendAll memory.capacity (encodeAll remaining) position contents) after ∧
      CellEffect memory.writes before after := by
  induction remaining generalizing index position contents before with
  | nil =>
    have finished : index = memory.tokens.length := by
      have length := congrArg List.length suffix
      simp only [List.length_drop, List.length_nil] at length
      have := owned.bound
      omega
    exact ⟨before, executesWhileFalse (by simpa only [finished, ne_eq, not_true_eq_false, decide_false] using owned.condition program.core),
      owned.backing, by simpa only [encodeAll, List.flatMap_nil, appendAll, Completed, finished] using owned,
      CellEffect.refl owned.wellFormed⟩
  | cons assignment rest ih =>
    have bound : index < memory.tokens.length := by
      have length := congrArg List.length suffix
      simp only [List.length_drop, List.length_cons] at length
      omega
    have selected : memory.tokens[index] = assignment ∧ memory.tokens.drop (index + 1) = rest := by
      rw [List.drop_eq_getElem_cons bound] at suffix
      exact List.cons.inj suffix
    let entry := owned.entry bound
    have chosen : entry.token = assignment := selected.1
    have conditionRun : Evaluates program.core before condition (.boolean true) before := by
      simpa only [ne_eq, show index ≠ memory.tokens.length by omega, not_false_eq_true, decide_true] using owned.condition program.core
    have encoded : appendAll memory.capacity (encodeAll (assignment :: rest)) position contents =
        entry.outcome.resume memory.capacity (encodeAll rest) := by
      change appendAll memory.capacity
        (encoding assignment ++ encodeAll rest) position contents =
        (appendAll memory.capacity (encoding entry.token)
          position contents).resume memory.capacity (encodeAll rest)
      rw [chosen]
      exact appendAll_append _ _ _ _ _
    cases result : entry.outcome with
    | full retained =>
      obtain ⟨after, run, backing, effect⟩ := entry.failure word result
      dsimp only [entry, Owned.entry] at backing effect
      refine ⟨after, ?_, ?_, ?_, effect.weaken CellSet.subset_union_left⟩
      · simpa only [encoded, result, AppendOutcome.resume, AppendOutcome.completion, loop] using
          executesWhileReturned conditionRun run
      · simpa only [encoded, result, AppendOutcome.resume, AppendOutcome.contents] using backing
      · simp only [encoded, result, AppendOutcome.resume, Completed]
    | done nextCursor updated =>
      obtain ⟨advanced, run, backing, cursor, indexOwned, effect⟩ := entry.success word owned.indexOwned memory.distinctLocals result
      dsimp only [entry, Owned.entry] at backing cursor indexOwned effect
      have size : updated.length = contents.length := by
        have length := appendAll_length memory.capacity
          (encoding entry.token) position contents
        change entry.outcome.contents.length = contents.length at length
        simpa only [result, AppendOutcome.contents] using length
      have advancedOwned := owned.transition effect (by omega) size backing cursor indexOwned
      obtain ⟨after, restRun, restBacking, completed, restEffect⟩ := ih advancedOwned selected.2
      refine ⟨after, ?_, ?_, ?_, effect.trans restEffect⟩
      · simpa only [encoded, result, AppendOutcome.resume, loop] using executesWhileTrueThen conditionRun run restRun
      · simpa only [encoded, result, AppendOutcome.resume] using restBacking
      · simpa only [encoded, result, AppendOutcome.resume] using completed

end Lanius.Extraction.CompactOutput.Tokens

