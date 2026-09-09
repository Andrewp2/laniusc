import Lanius.Extraction.CompactOutput.Nodes.ChildState

namespace Lanius.Extraction.CompactOutput.Nodes

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Extraction.SemanticTokens

def encodeChildren (children : List ChildVisit) : List Nat := children.flatMap encodeChild

def ChildCompleted (memory : ChildMemory) (outcome : AppendOutcome) (after : State) : Prop :=
  match outcome with
  | .done position contents => ChildOwned memory memory.record.children.length position contents after
  | .full _ => True

/-- Execute the actual child loop, including the first capacity failure.
The iteration executions and exact output are derived, not assumed. -/
theorem execute_child_loop (word : Word.Checked program byte digit)
    (tokenConstant : ParserTreeSource.constantValue program.core tokenTag 1)
    (stateConstant : ParserTreeSource.constantValue program.core stateTag 2)
    (remaining : List ChildVisit)
    (owned : ChildOwned memory index position contents before)
    (suffix : memory.record.children.drop index = remaining) :
    ∃ after, Executes program.core before (childLoop word.source.function.id tokenTag stateTag)
        (appendAll memory.capacity (encodeChildren remaining) position contents).completion after ∧
      after.cellEntry? memory.outputCell = some {
        id := memory.outputCell, value := some (.array (signedI32Values
          (appendAll memory.capacity (encodeChildren remaining) position contents).contents)) } ∧
      ChildCompleted memory (appendAll memory.capacity (encodeChildren remaining) position contents) after ∧
      CellEffect memory.writes before after := by
  induction remaining generalizing index position contents before with
  | nil =>
    have finished : index = memory.record.children.length := by
      have length := congrArg List.length suffix
      simp only [List.length_drop, List.length_nil] at length
      have := owned.bound
      omega
    exact ⟨before, executesWhileFalse (by simpa only [finished, ne_eq, not_true_eq_false, decide_false] using owned.condition program.core),
      owned.backing, by simpa only [encodeChildren, List.flatMap_nil, appendAll, ChildCompleted, finished] using owned,
      CellEffect.refl owned.wellFormed⟩
  | cons child rest ih =>
    have bound : index < memory.record.children.length := by
      have length := congrArg List.length suffix
      simp only [List.length_drop, List.length_cons] at length
      omega
    have selected : memory.record.children[index] = child ∧ memory.record.children.drop (index + 1) = rest := by
      rw [List.drop_eq_getElem_cons bound] at suffix
      exact List.cons.inj suffix
    let entry := owned.entry bound
    have chosen : entry.child = child := selected.1
    have conditionRun : Evaluates program.core before childCondition (.boolean true) before := by
      simpa only [ne_eq, show index ≠ memory.record.children.length by omega, not_false_eq_true, decide_true] using owned.condition program.core
    have encoded : appendAll memory.capacity (encodeChildren (child :: rest)) position contents =
        entry.outcome.resume memory.capacity (encodeChildren rest) := by
      change appendAll memory.capacity
        (encodeChild child ++ encodeChildren rest) position contents =
        (appendAll memory.capacity (encodeChild entry.child)
          position contents).resume memory.capacity (encodeChildren rest)
      rw [chosen]
      exact appendAll_append _ _ _ _ _
    cases result : entry.outcome with
    | full retained =>
      obtain ⟨after, run, backing, effect⟩ := entry.failure word tokenConstant stateConstant result
      dsimp only [entry, ChildOwned.entry] at backing effect
      refine ⟨after, ?_, ?_, ?_, effect.weaken CellSet.subset_union_left⟩
      · simpa only [encoded, result, AppendOutcome.resume, AppendOutcome.completion, childLoop] using
          executesWhileReturned conditionRun run
      · simpa only [encoded, result, AppendOutcome.resume, AppendOutcome.contents] using backing
      · simp only [encoded, result, AppendOutcome.resume, ChildCompleted]
    | done nextCursor updated =>
      obtain ⟨advanced, run, backing, cursor, indexOwned, effect⟩ := entry.success word tokenConstant stateConstant owned.indexOwned memory.distinctLocals result
      dsimp only [entry, ChildOwned.entry] at backing cursor indexOwned effect
      have size : updated.length = contents.length := by
        have length := appendAll_length memory.capacity
          (encodeChild entry.child) position contents
        change entry.outcome.contents.length = contents.length at length
        simpa only [result, AppendOutcome.contents] using length
      have advancedOwned := owned.transition effect (by omega) size backing cursor indexOwned
      obtain ⟨after, restRun, restBacking, completed, restEffect⟩ := ih advancedOwned selected.2
      refine ⟨after, ?_, ?_, ?_, effect.trans restEffect⟩
      · simpa only [encoded, result, AppendOutcome.resume, childLoop] using executesWhileTrueThen conditionRun run restRun
      · simpa only [encoded, result, AppendOutcome.resume] using restBacking
      · simpa only [encoded, result, AppendOutcome.resume] using completed

end Lanius.Extraction.CompactOutput.Nodes
