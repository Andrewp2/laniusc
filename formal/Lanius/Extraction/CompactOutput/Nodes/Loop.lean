import Lanius.Extraction.CompactOutput.Nodes.State

namespace Lanius.Extraction.CompactOutput.Nodes

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Extraction.SemanticTokens

def encodeAll (records : List RecordVisit) : List Nat := records.flatMap encodeRecord

def Completed (memory : Memory) (outcome : AppendOutcome) (after : State) : Prop :=
  match outcome with
  | .done position contents => Owned memory memory.records.length position contents after
  | .full _ => True

theorem execute_loop (word : Word.Checked program byte digit)
    (tokenConstant : ParserTreeSource.constantValue program.core tokenTag 1)
    (stateConstant : ParserTreeSource.constantValue program.core stateTag 2)
    (remaining : List RecordVisit) (owned : Owned memory index position contents before)
    (suffix : memory.records.drop index = remaining) :
    ∃ after, Executes program.core before (.whileLoop condition (step word.source.function.id tokenTag stateTag))
        (appendAll memory.capacity (encodeAll remaining) position contents).completion after ∧
      after.cellEntry? memory.outputCell = some {
        id := memory.outputCell, value := some (.array (signedI32Values
          (appendAll memory.capacity (encodeAll remaining) position contents).contents)) } ∧
      Completed memory (appendAll memory.capacity (encodeAll remaining) position contents) after ∧
      CellEffect memory.writes before after := by
  induction remaining generalizing index position contents before with
  | nil =>
    have finished : index = memory.records.length := by
      have length := congrArg List.length suffix
      simp only [List.length_drop, List.length_nil] at length
      have := owned.bound
      omega
    exact ⟨before, executesWhileFalse (by simpa only [finished, ne_eq, not_true_eq_false, decide_false] using owned.condition program.core),
      owned.backing, by simpa only [encodeAll, List.flatMap_nil, appendAll, Completed, finished] using owned,
      CellEffect.refl owned.wellFormed⟩
  | cons record rest ih =>
    have bound : index < memory.records.length := by
      have length := congrArg List.length suffix
      simp only [List.length_drop, List.length_cons] at length
      omega
    have selected : memory.records[index] = record ∧ memory.records.drop (index + 1) = rest := by
      rw [List.drop_eq_getElem_cons bound] at suffix
      exact List.cons.inj suffix
    let entry := owned.entry bound
    have chosen : entry.memory.record = record := selected.1
    have conditionRun : Evaluates program.core before condition (.boolean true) before := by
      simpa only [ne_eq, show index ≠ memory.records.length by omega, not_false_eq_true, decide_true] using owned.condition program.core
    have encoded : appendAll memory.capacity (encodeAll (record :: rest)) position contents =
        (appendAll memory.capacity (encodeRecord record) position contents).resume memory.capacity (encodeAll rest) :=
      appendAll_append _ _ _ _ _
    obtain ⟨advanced, run, backing, successful, effect⟩ := entry.execute word tokenConstant stateConstant
    dsimp only [entry, Owned.entry] at run backing successful effect
    rw [selected.1] at run backing successful
    cases result : appendAll memory.capacity (encodeRecord record) position contents with
    | full retained =>
      refine ⟨advanced, ?_, ?_, ?_, effect⟩
      · simpa only [encoded, result, AppendOutcome.resume, AppendOutcome.completion] using
          executesWhileReturned conditionRun (by simpa only [result, AppendOutcome.completion] using run)
      · simpa only [encoded, result, AppendOutcome.resume, AppendOutcome.contents] using backing
      · simp only [encoded, result, AppendOutcome.resume, Completed]
    | done nextCursor updated =>
      obtain ⟨cursor, node⟩ := successful nextCursor updated result
      have size : updated.length = contents.length := by
        have length := appendAll_length memory.capacity (encodeRecord record) position contents
        simpa only [result, AppendOutcome.contents] using length
      have nextBacking := backing
      rw [result] at nextBacking
      have advancedOwned := owned.transition effect (by omega) size nextBacking cursor node
      obtain ⟨after, restRun, restBacking, completed, restEffect⟩ := ih advancedOwned selected.2
      refine ⟨after, ?_, ?_, ?_, effect.trans restEffect⟩
      · simpa only [encoded, result, AppendOutcome.resume] using executesWhileTrueThen conditionRun
          (by simpa only [result, AppendOutcome.completion] using run) restRun
      · simpa only [encoded, result, AppendOutcome.resume] using restBacking
      · simpa only [encoded, result, AppendOutcome.resume] using completed

end Lanius.Extraction.CompactOutput.Nodes
