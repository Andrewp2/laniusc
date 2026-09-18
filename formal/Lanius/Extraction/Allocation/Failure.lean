import Lanius.Extraction.Allocation.Sequence

namespace Lanius.Extraction.Allocation

open Lanius.Core Lanius.Semantics Lanius.Properties

/-- If the total byte budget is too small, some guarded allocation returns
code 3. All earlier buffers remain valid, no later continuation executes, and
the only world effects are the allocation calls up to and including failure. -/
theorem hostSequence_rejectsExhaustion
    {program : Program} {function : Function}
    (steps : List Step) (before : State) (continuation : Stmt)
    (functionFound : program.function? function.id = some function)
    (parametersBound : ∀ count, ∃ bindings, bindParameters function.parameters
      [.unsigned .usize (count * 4), .unsigned .usize 4] = some bindings)
    (noBody : function.body = none) (host : function.external = some (.host .alloc))
    (initial : Registry before)
    (budget : before.heap.remaining = some available)
    (short : available < byteCount (steps.map Step.buffer)) :
    ∃ calls after, 0 < calls ∧ calls ≤ steps.length ∧
      Executes program before (hostStatement function.id steps continuation)
        (.returned (some (.signed .i32 3))) after ∧ Registry after ∧
      after.world = { before.world with calls := before.world.calls ++ List.replicate calls .alloc } ∧
      after.locals = before.locals := by
  induction steps generalizing before available with
  | nil => simp [byteCount] at short
  | cons step steps ih =>
      obtain ⟨bindings, bound⟩ := parametersBound step.buffer.count
      by_cases firstShort : available < step.buffer.count * 4
      · obtain ⟨after, executed, valid, world, _, _, locals, _⟩ :=
          step.rejectsExhaustion (hostStatement function.id steps continuation)
            functionFound bound noBody host initial budget firstShort
        exact ⟨1, after, by decide, by simp, executed, valid,
          by simpa [Lanius.World.record] using world, locals⟩
      · have room : ∀ capacity, before.heap.remaining = some capacity → step.buffer.count * 4 ≤ capacity := by
          intro capacity found
          rw [budget] at found
          cases found
          exact Nat.le_of_not_gt firstShort
        obtain ⟨allocated, executed, initialized⟩ :=
          step.initializes functionFound bound noBody host initial room
        have remaining : allocated.heap.remaining = some (available - step.buffer.count * 4) := by
          rw [initialized.remaining, budget]
          rfl
        have tailShort : available - step.buffer.count * 4 < byteCount (steps.map Step.buffer) := by
          simp only [List.map_cons, byteCount] at short
          omega
        obtain ⟨calls, after, positive, bounded, failed, valid, world, locals⟩ :=
          ih allocated initialized.registry remaining tailShort
        have finalValid : Registry (restoreLocals before after) :=
          valid.restoreLocals before ⟨valid.wellFormed.heapWellFormed, valid.wellFormed.cellIdsUnique,
            valid.wellFormed.cellIdsBelowNext, fun binding member => valid.wellFormed.localsReferenceCells binding (by
              rw [locals, initialized.locals]
              exact List.mem_cons_of_mem _ member)⟩
        refine ⟨calls + 1, restoreLocals before after, Nat.zero_lt_succ _, Nat.succ_le_succ bounded,
          executesLetUninitialized (executesSequence executed failed), finalValid, ?_, rfl⟩
        change after.world = _
        rw [world, initialized.world]
        simp [Lanius.World.record, List.replicate_succ, List.append_assoc]

theorem CheckedAllocator.rejectsExhaustion (allocator : CheckedAllocator program)
    (sequence : Sequence) (before : State) (initial : Registry before)
    (budget : before.heap.remaining = some available)
    (short : available < byteCount sequence.buffers) :
    ∃ calls after, 0 < calls ∧ calls ≤ sequence.steps.length ∧
      Executes program before (sequence.statement allocator.function.id)
        (.returned (some (.signed .i32 3))) after ∧ Registry after ∧
      after.world = { before.world with calls := before.world.calls ++ List.replicate calls .alloc } ∧
      after.locals = before.locals :=
  hostSequence_rejectsExhaustion sequence.steps before sequence.continuation allocator.found
    allocator.parametersBound allocator.noBody allocator.host initial budget short

end Lanius.Extraction.Allocation
