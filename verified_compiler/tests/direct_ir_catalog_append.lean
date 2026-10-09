import verified_compiler.tests.direct_ir_catalog_append_post

namespace IRCatalogAppendProof

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRTypeRefProof
open IRCatalogBuildProof IRBuilderCallProof IRBuilderNavigationProof IRRegionAllocationProof

/-- Copy, both allocator outcomes, structural rejection and the final writes
    use one original-data postcondition. Only live success activates geometry. -/
private theorem actualAllocatedTail (input : Input caller) (active : input.CopyNeeded caller.heap)
    (frame : CallerFrame caller state) (bindings : StageBindings input.toArguments state)
    (available : consumeBudget caller.heap.remaining (input.request * 56) = some budget) :
    ∃ after, RunsStmt extractedProgram state (source.bindingStatement 5)
      (.returned (some (.signed .i32 (input.answer caller.heap)))) after ∧
      FreshCellFrame state after ∧ Post input.toModel caller (input.answer caller.heap)
        after.heap after.world after.i32ArrayViews := by
  classical
  let Q := fun (completion : Completion) (after : State) =>
    completion = .returned (some (.signed .i32 (input.answer caller.heap))) ∧
      FreshCellFrame state after ∧ Post input.toModel caller (input.answer caller.heap)
        after.heap after.world after.i32ArrayViews
  obtain ⟨completion, after, run, returned, cells, post⟩ :=
    actualSourceContinuation (input.buildEntry active frame bindings available) Q (by
      intro current memory
      have rejected := input.rejectionNotSuccess active frame bindings available memory
      have post := input.rejectionPost active frame bindings available memory
      simp only [Q, Model.answer, if_neg rejected, true_and]
      exact ⟨memory.cells.restoreLocals, post⟩) (by
      intro current live
      have successful := input.liveSuccess active frame bindings available live
      let entry := input.storeEntry active frame bindings available successful
      obtain ⟨after, run, stored⟩ := IRCatalogStoreProof.actualStores entry live
      have post := input.successPost active frame bindings available successful live stored
      refine ⟨.returned (some (.signed .i32 input.next.toInt)), after, ?_, ?_⟩
      · change RunsStmt extractedProgram current catalogWrites
          (.returned (some (.signed .i32 input.occupied))) after at run
        simpa only [input.toArguments.occupiedValue active.1] using run
      · simp only [Q, Model.answer, if_pos successful, true_and]
        exact ⟨stored.cells, post⟩)
  subst completion
  exact ⟨after, run, cells, post⟩

/-- The size and first-allocation guards require no source or spare-row reads.
    Their actual effects feed the same fixed original-data postcondition. -/
private theorem actualTail (input : Input caller) (guarded : input.Guarded) (absent : ¬input.Duplicate)
    (frame : CallerFrame caller state) (bindings : StageBindings input.toArguments state) :
    ∃ after, RunsStmt extractedProgram state (source.bindingStatement 5)
      (.returned (some (.signed .i32 (input.answer caller.heap)))) after ∧
      FreshCellFrame state after ∧ Post input.toModel caller (input.answer caller.heap)
        after.heap after.world after.i32ArrayViews := by
  classical
  have requested := input.toArguments.requested guarded
  by_cases sized : input.Sized
  · cases resource : consumeBudget caller.heap.remaining (input.request * 56) with
    | some budget =>
      exact actualAllocatedTail input ⟨guarded, absent, sized, budget, resource⟩ frame bindings resource
    | none =>
      have rejected : ¬input.Success caller.heap := by
        rintro ⟨_, _, _, ⟨first, second, consumed, _⟩, _⟩
        rw [resource] at consumed
        contradiction
      have noCopy : ¬input.CopyNeeded caller.heap := by
        rintro ⟨_, _, _, budget, available⟩
        rw [resource] at available
        contradiction
      have fits : input.request * 56 < 2 ^ 31 := by have upper := sized.2; omega
      have found : state.local? (source.argumentId 3) = some (.signed .i32 input.request) := by
        simpa only [requested] using bindings.eventCount
      let effect := Effect state input.toModel caller (-1)
      have run : ∃ after, RunsStmt extractedProgram state (source.bindingStatement 5)
          (.returned (some (.signed .i32 (-1)))) after ∧ effect state after := by
        apply RunsStmt.letFramedEffect (Effect.scopes _ _ _ _)
          (actualBytes input.request sized.1 fits found frame.currentFormed)
        intro ready pure
        have readyFrame := frame.transPure pure
        core_state prepared
        have preparedFrame : CallerFrame caller prepared :=
          readyFrame.bindLocal (source.bindingId 5) (.signed .i32 (input.request * 56 : Nat))
        have bytesFound : prepared.local? (source.bindingId 5) =
            some (.signed .i32 (input.request * 56 : Nat)) := by core_local
        let allocated := { prepared with world := World.record prepared.world .alloc }
        let completed := allocated.bindLocal (source.bindingId 6) (.pointer 0)
        have memoryFound : completed.local? (source.bindingId 6) = some (.pointer 0) :=
          preparedFrame.currentFormed.bindLocal_local (source.bindingId 6) (.pointer 0)
        have memory : RunsExpr extractedProgram prepared (source.bindingInitializer 6) (.pointer 0) allocated :=
          actualMemoryExhausted input.request fits bytesFound
            (by simpa only [preparedFrame.heap] using resource) (preparedFrame.views.trans input.noViews)
        refine ⟨restoreLocals allocated completed, RunsStmt.sequenceNext
          (IRCatalogCopyProof.actualBytesGuard input.request sized.1 bytesFound)
          (RunsStmt.letLocal (id := source.bindingId 6) (afterInit := allocated) (afterBody := completed) memory ?_), ?_⟩
        · core_stmt
        · refine ⟨?_, input.unchangedPost (after := restoreLocals allocated completed)
            rejected noCopy preparedFrame.heap preparedFrame.views ?_⟩
          · exact (pure.cells.trans (FreshCellFrame.bindLocal ready (source.bindingId 5)
              (.signed .i32 (input.request * 56 : Nat)))).trans
              (FreshCellFrame.bindLocal allocated (source.bindingId 6) (.pointer 0))
          · simp only [Model.expectedWorld, if_pos (And.intro guarded (And.intro absent sized)), resource]
            change World.record prepared.world .alloc = World.record caller.world .alloc
            rw [preparedFrame.world]
      simpa only [effect, Effect, Model.answer, if_neg rejected] using run
  · have rejected : ¬input.Success caller.heap := fun successful => sized successful.2.2.1
    have noCopy : ¬input.CopyNeeded caller.heap := fun active => sized active.2.2.1
    have noAllocation : ¬(input.Guarded ∧ ¬input.Duplicate ∧ input.Sized) := fun active => sized active.2.2
    have bad : input.eventCount.toInt ≤ 0 ∨ 38347922 < input.eventCount.toInt := by
      right
      have positive := guarded.2.2.2.2.2.1
      dsimp only [Arguments.Sized] at sized
      omega
    have sizing := fun (current : State) (formed : current.CellsWellFormed) =>
      actualSizeReject input.eventCount.toInt bad formed
    have countFound := bindings.eventCount
    obtain ⟨after, run, pure⟩ : ∃ after,
        RunsStmt extractedProgram state (source.bindingStatement 5)
          (.returned (some (.signed .i32 (-1)))) after ∧ PureFrame state after := by
      have formed := frame.currentFormed
      core_pure
    have post := input.unchangedPost rejected noCopy (pure.heap.trans frame.heap)
      (pure.views.trans frame.views) (by
        simpa only [Model.expectedWorld, if_neg noAllocation] using pure.world.trans frame.world)
    simpa only [Model.answer, if_neg rejected] using ⟨after, run, pure.cells, post⟩

/-- The scan may return early or reach the allocation tail. Its counter is
    fresh relative to entry, so existing lexical/effect rules handle scope. -/
private theorem actualScannedTail (input : Input caller) (guarded : input.Guarded)
    (frame : CallerFrame caller state) (bindings : StageBindings input.toArguments state) :
    ∃ after, RunsStmt extractedProgram state (source.bindingStatement 4)
      (.returned (some (.signed .i32 (input.answer caller.heap)))) after ∧
      FreshCellFrame state after ∧ Post input.toModel caller (input.answer caller.heap)
        after.heap after.world after.i32ArrayViews := by
  classical
  rw [actualPriorShape]
  change ∃ after, RunsStmt extractedProgram state _ _ after ∧
    Effect state input.toModel caller (input.answer caller.heap) state after
  apply RunsStmt.letEffect (Effect.scopes _ _ _ _)
  · core_run
  · exact frame.currentFormed
  obtain ⟨completion, scanned, run, scanFrame, outcome⟩ :=
    actualScan input guarded frame.currentFormed frame.heap bindings.signature bindings.rows bindings.next
  rcases outcome with ⟨rfl, absent⟩ | ⟨rfl, duplicate⟩
  · have retained := bindings.afterScan scanFrame run.choose_spec.2
    obtain ⟨after, tail, cells, post⟩ := actualTail input guarded absent (frame.trans scanFrame) retained
    exact ⟨after, RunsStmt.sequenceNext run tail, scanFrame.cells.trans cells, post⟩
  · have rejected : ¬input.Success caller.heap := fun success => success.2.1 duplicate
    have noCopy : ¬input.CopyNeeded caller.heap := fun active => active.2.1 duplicate
    have noAllocation : ¬(input.Guarded ∧ ¬input.Duplicate ∧ input.Sized) := fun active => active.2.1 duplicate
    have currentFrame := frame.trans scanFrame
    have post := input.unchangedPost rejected noCopy currentFrame.heap currentFrame.views
      (by simpa only [Model.expectedWorld, if_neg noAllocation] using currentFrame.world)
    simpa only [Effect, Model.answer, if_neg rejected] using
      (show ∃ after, RunsStmt extractedProgram (state.bindLocal priorId (.signed .i32 0))
        (.sequence (.whileLoop scan.1 scan.2) (source.bindingStatement 5))
        (.returned (some (.signed .i32 (-1)))) after ∧ FreshCellFrame state after ∧
        Post input.toModel caller (-1) after.heap after.world after.i32ArrayViews from
        ⟨scanned, RunsStmt.sequenceCompleted run (by simp) _, scanFrame.cells, post⟩)

/-- Total actual public append, with branch-sensitive original storage and
    independent resources/shape. No execution, acceptance or spare decode is a premise. -/
theorem actualAppend (input : Input caller) : ∃ after,
    RunsExpr extractedProgram caller input.call (.signed .i32 (input.answer caller.heap)) after ∧
      FreshCellFrame caller after ∧ Post input.toModel caller (input.answer caller.heap)
        after.heap after.world after.i32ArrayViews ∧ after.locals = caller.locals := by
  classical
  have execution : ∃ after,
      RunsExpr extractedProgram caller input.call (.signed .i32 (input.answer caller.heap)) after ∧
        FreshCellFrame caller after ∧ Post input.toModel caller (input.answer caller.heap)
          after.heap after.world after.i32ArrayViews := by
    by_cases guarded : input.Guarded
    · have formed := input.formed
      have countRead := input.countRead
      unfold Arguments.CountRead at countRead
      core_call_framed (RunsExpr.callStores (Post input.toModel caller (input.answer caller.heap))) source as callee
      have calleeFrame : CallerFrame caller callee := by
        dsimp only [callee]
        apply CallerFrame.bindLocals
        exact ⟨formed, (CallerFrame.refl formed).cells, rfl, rfl, rfl⟩
      change ∃ after, RunsStmt extractedProgram callee _ _ after ∧
        Effect callee input.toModel caller (input.answer caller.heap) callee after
      repeat' (apply RunsStmt.letEffect (Effect.scopes _ _ _ _); core_run; core_formed)
      core_state guardState
      have setup : CallerFrame callee guardState := by
        dsimp only [guardState]
        repeat' (first | exact CallerFrame.refl (state := callee) (by core_formed) | apply CallerFrame.bindLocal)
      apply RunsStmt.guardEffectFalse (Effect.scopes _ _ _ _)
      · unfold Arguments.Guarded at guarded
        apply RunsExpr.booleanPure
        · repeat' (any_goals (first | apply RunsExpr.logicalOrPure | intro middle frame))
          all_goals core_pure_expr
        · core_guard_logic
      intro current pure
      have currentFrame := calleeFrame.trans (setup.transPure pure)
      have bindings : StageBindings input.toArguments current :=
        ⟨by core_local, by core_local, by core_local, by core_local,
          by core_local, by core_local, by core_local⟩
      obtain ⟨after, run, fresh, post⟩ := actualScannedTail input guarded currentFrame bindings
      exact ⟨after, run, (setup.transPure pure).cells.trans fresh, post⟩
    · have rejected : ¬input.Success caller.heap := fun success => guarded success.1
      have noCopy : ¬input.CopyNeeded caller.heap := fun active => guarded active.1
      have noAllocation : ¬(input.Guarded ∧ ¬input.Duplicate ∧ input.Sized) := fun active => guarded active.1
      obtain ⟨after, run, pure⟩ := actualGuardReject input.toArguments input.formed input.countRead guarded
      have post := input.unchangedPost rejected noCopy pure.heap pure.views
        (by simpa only [Model.expectedWorld, if_neg noAllocation] using pure.world)
      simpa only [Model.answer, if_neg rejected] using ⟨after, run, pure.cells, post⟩
  obtain ⟨after, run, cells, post⟩ := execution
  exact ⟨after, run, cells, post, run.choose_spec.2⟩

#print axioms actualAllocatedTail
#print axioms actualTail
#print axioms actualScannedTail
#print axioms actualAppend

end IRCatalogAppendProof
