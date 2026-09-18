import Lanius.Extraction.Entry.Certificate
import Lanius.Extraction.Entry.File.Missing
import Lanius.Extraction.Allocation.Failure
import Lanius.Semantics.Prefix.Return

namespace Lanius.Extraction.Entry
open Lanius Lanius.Core Lanius.Semantics Lanius.Properties
open Lanius.Extraction.ExtractorContract

/-- A classified rejection of the actual executable. Unlike the successful
loading contract, this does not require available files or sufficient resources.
The execution proof excludes both traps and divergence on the covered input. -/
structure RejectedExecution (executable : Lanius.Execution.Executable)
    (before : State) (code : Int) where
  after : State
  evaluated : Evaluates executable.program before
    (.call executable.entrypoint []) (.signed .i32 code) after
  failure : Failure before after code

namespace RejectedExecution

theorem terminates (rejected : RejectedExecution executable before code) :
    ∃ bound, ∀ fuel, bound ≤ fuel →
      Lanius.Execution.run fuel executable before =
        .returned (.signed .i32 code) rejected.after := by
  obtain ⟨bound, evaluated⟩ := rejected.evaluated
  exact ⟨bound, fun fuel enough => by
    simp only [Lanius.Execution.run,
      Lanius.Fuel.evalExpr_done_at_larger_fuel enough evaluated]⟩

/-- At every fuel, rejection is either not yet observed or is exactly the
proved classified return. A trap is not treated as an ordinary failure. -/
theorem observations (rejected : RejectedExecution executable before code) (fuel : Nat) :
    Lanius.Execution.run fuel executable before = .outOfFuel ∨
      Lanius.Execution.run fuel executable before =
        .returned (.signed .i32 code) rejected.after := by
  rcases Run.observation_of_evaluates rejected.evaluated fuel with exhausted | done
  · exact .inl (by simp only [Lanius.Execution.run, exhausted])
  · exact .inr (by simp only [Lanius.Execution.run, done])

theorem contracts (rejected : RejectedExecution executable before code) (fuel : Nat) :
    RunSound before
        (evalExpr fuel executable.program before (.call executable.entrypoint [])) ∧
      RunFailureSafe before
        (evalExpr fuel executable.program before (.call executable.entrypoint [])) := by
  rcases Run.observation_of_evaluates rejected.evaluated fuel with exhausted | done
  · constructor <;> intro result final returned <;> rw [exhausted] at returned <;> contradiction
  · constructor
    · intro result final returned zero
      rw [done] at returned
      cases returned
      exact (rejected.failure.nonzero zero).elim
    · intro result final returned _
      rw [done] at returned
      cases returned
      exact ⟨rejected.failure⟩

end RejectedExecution

/-- The actual checked main rejects zero or one argv entries before any
allocation or file operation. Existing files, handles, outputs, and arbitrary
handle counters need no loading-domain assumptions on this branch. -/
def CheckedExecution.noInputs (checked : CheckedExecution accepted)
    (world : Lanius.World.State) (missing : world.arguments.length ≤ 1) :
    RejectedExecution accepted.entrypoint.executable ({ world } : State) 1 := by
  let before : State := { world }
  have wellFormed := (initial_world_state_has_runtime_type accepted.checked.program.core world).typed.wellFormed
  have body := checked.arguments.rejectsNoInputs before wellFormed rfl missing
  have called := Run.call accepted.analysis rfl body
  refine {
    after := restoreLocals before (restoreLocals
      { before with world := Lanius.World.record world .argc } (checked.arguments.entry.ready before))
    evaluated := by simpa only [accepted.entrypoint.executableDefinition] using called
    failure := {
      nonzero := by decide
      classified := .noInputs
      arguments := rfl
      files := rfl
      handles := rfl
      memorySafe := ⟨empty_heap_well_formed, by intro view member; cases member⟩ } }

/-- Only the argc event changes the modeled external world on this branch. -/
theorem CheckedExecution.noInputs_world (checked : CheckedExecution accepted)
    (world : Lanius.World.State) (missing : world.arguments.length ≤ 1) :
    (checked.noInputs world missing).after.world = Lanius.World.record world .argc := rfl

/-- Insufficient initial allocation budget rejects the actual checked main,
without requiring readable files or fresh handles. Every possible failing
allocation in the source sequence is covered by the same finite proof. -/
theorem CheckedExecution.allocationFailure (checked : CheckedExecution accepted)
    (before : State) (wellFormed : StateWellFormed before)
    (emptyLocals : before.locals = []) (emptyViews : before.i32ArrayViews = [])
    (enough : 1 < before.world.arguments.length) (bounded : before.world.arguments.length < 2 ^ 31)
    (budget : before.heap.remaining = some available)
    (short : available < Allocation.byteCount checked.buffers) :
    ∃ rejected : RejectedExecution accepted.entrypoint.executable before 3,
      ∃ calls, 0 < calls ∧ calls ≤ checked.allocations.locals.steps.length ∧
        rejected.after.world = { before.world with
          calls := before.world.calls ++ [.argc] ++ List.replicate calls .alloc } := by
  let Claim : Prop := ∃ calls after, 0 < calls ∧ calls ≤ checked.allocations.locals.steps.length ∧
    Executes accepted.checked.program.core before accepted.analysis.body (.returned (some (.signed .i32 3))) after ∧
    MemorySafe after ∧ after.world = { before.world with
      calls := before.world.calls ++ [.argc] ++ List.replicate calls .alloc }
  have claim : Claim := by
    obtain ⟨_, _, result⟩ := checked.arguments.executes before (.returned (some (.signed .i32 3)))
      (fun _ => Claim) wellFormed emptyViews enough bounded (by
        intro registry reached
        obtain ⟨calls, after, positive, count, executed, valid, world, _⟩ :=
          checked.allocator.rejectsExhaustion checked.allocations.locals
            (checked.arguments.entry.ready before) registry budget short
        have run : Executes accepted.checked.program.core (checked.arguments.entry.ready before)
            checked.arguments.entry.continuation (.returned (some (.signed .i32 3))) after :=
          checked.allocations.exactSource.symm ▸ executed
        obtain ⟨final, main, same⟩ := reached.completeReturn run
        have safe : MemorySafe final := by
          change MemorySafe (restoreLocals before final)
          rw [same before]
          exact ⟨valid.wellFormed.heapWellFormed, valid.blocks⟩
        have finalWorld : final.world = after.world := by
          simpa only [restoreLocals] using congrArg State.world (same before)
        exact ⟨after, run, calls, final, positive, count, main, safe,
          finalWorld.trans (by simpa [Arguments.ready, State.bindLocal, State.bindCell, Lanius.World.record] using world)⟩)
    exact result
  obtain ⟨calls, after, positive, count, executed, safe, world⟩ := claim
  have evaluated := Run.call accepted.analysis emptyLocals executed
  let rejected : RejectedExecution accepted.entrypoint.executable before 3 := {
    after := restoreLocals before after
    evaluated := by simpa only [accepted.entrypoint.executableDefinition] using evaluated
    failure := {
      nonzero := by decide
      classified := .allocation
      arguments := by simpa only [restoreLocals] using congrArg Lanius.World.State.arguments world
      files := by simpa only [restoreLocals] using congrArg Lanius.World.State.files world
      handles := by simpa only [restoreLocals] using congrArg Lanius.World.State.fileHandles world
      memorySafe := safe } }
  exact ⟨rejected, calls, positive, count, world⟩

/-- The first path is rejected by the actual main before copying argument
bytes or opening any file. No file availability or handle conditions are
needed; startup's memory is unlimited, as in the ordinary loading contract. -/
theorem CheckedExecution.invalidPath (checked : CheckedExecution accepted)
    (world : Lanius.World.State) (enough : 1 < world.arguments.length)
    (bounded : world.arguments.length < 2 ^ 31) (path : String)
    (selected : world.arguments[1]? = some path) (size : path.toUTF8.size ≤ 2147483647)
    (invalid : path.toUTF8.size = 0 ∨ 1025 ≤ path.toUTF8.size) :
    ∃ rejected : RejectedExecution accepted.entrypoint.executable ({ world } : State) 2,
      rejected.after.world = { world with
        calls := world.calls ++ [.argc] ++ List.replicate checked.buffers.length .alloc ++ [.argLen] } := by
  obtain ⟨first, _⟩ := checked.firstFile world enough bounded
  have indexRead : first.state.local? checked.file.pipeline.path.argument = some (.signed .i32 1) :=
    checked.file.advanceRelation.selected ▸ first.indexRead
  have selectedBefore : first.state.world.arguments[1]? = some path := by
    rw [first.world]
    exact selected
  obtain ⟨after, body, registered, _, worldAfter⟩ := checked.file.pipeline.path.rejects
    checked.file.pipeline.length first.state first.registry 1 path indexRead selectedBefore size invalid
  obtain ⟨final, main, same⟩ := first.completeReturn body
  have safe : MemorySafe final := by
    change MemorySafe (restoreLocals ({ world } : State) final)
    rw [same ({ world } : State)]
    exact ⟨registered.wellFormed.heapWellFormed, registered.blocks⟩
  have finalWorld : final.world = { world with
      calls := world.calls ++ [.argc] ++ List.replicate checked.buffers.length .alloc ++ [.argLen] } := by
    have equal : final.world = after.world := by
      simpa only [restoreLocals] using congrArg State.world (same ({ world } : State))
    rw [equal, worldAfter, Lanius.World.record, first.world]
    rfl
  have evaluated := Run.call accepted.analysis rfl main
  let rejected : RejectedExecution accepted.entrypoint.executable ({ world } : State) 2 := {
    after := restoreLocals ({ world } : State) final
    evaluated := by simpa only [accepted.entrypoint.executableDefinition] using evaluated
    failure := {
      nonzero := by decide
      classified := .badPath
      arguments := by simpa only [restoreLocals] using congrArg Lanius.World.State.arguments finalWorld
      files := by simpa only [restoreLocals] using congrArg Lanius.World.State.files finalWorld
      handles := by simpa only [restoreLocals] using congrArg Lanius.World.State.fileHandles finalWorld
      memorySafe := safe } }
  exact ⟨rejected, finalWorld⟩

/-- A valid-length first path absent from the filesystem returns five through
the actual main. Later arguments, file sizes, handle freshness, and handle
representability need no assumptions because the file is never opened. -/
theorem CheckedExecution.missingFile (checked : CheckedExecution accepted)
    (world : Lanius.World.State) (enough : 1 < world.arguments.length)
    (bounded : world.arguments.length < 2 ^ 31) (path : String)
    (selected : world.arguments[1]? = some path) (nonempty : 0 < path.toUTF8.size)
    (fits : path.toUTF8.size ≤ 1024) (missing : world.file? (Lanius.World.utf8Bytes path) = none) :
    ∃ rejected : RejectedExecution accepted.entrypoint.executable ({ world } : State) 5,
      rejected.after.world = { world with
        calls := world.calls ++ [.argc] ++ List.replicate checked.buffers.length .alloc ++ [.argLen, .argRead, .openRead] } := by
  obtain ⟨first, ⟨buffers⟩⟩ := checked.firstFile world enough bounded
  have indexRead : first.state.local? checked.file.pipeline.path.argument = some (.signed .i32 1) :=
    checked.file.advanceRelation.selected ▸ first.indexRead
  have selectedBefore : first.state.world.arguments[1]? = some path := by
    rw [first.world]
    exact selected
  have absent : first.state.world.file? (Lanius.World.utf8Bytes path) = none := by
    rw [first.world]
    exact missing
  obtain ⟨after, body, safe, worldAfter⟩ := checked.file.pipeline.rejectsMissing buffers first.registry
    1 path indexRead selectedBefore nonempty fits absent (by rw [accepted.checked.program.target]; decide)
  obtain ⟨final, main, same⟩ := first.completeReturn body
  have finalSafe : MemorySafe final := by
    change MemorySafe (restoreLocals ({ world } : State) final)
    rw [same ({ world } : State)]
    exact safe
  have finalWorld : final.world = { world with
      calls := world.calls ++ [.argc] ++ List.replicate checked.buffers.length .alloc ++ [.argLen, .argRead, .openRead] } := by
    have equal : final.world = after.world := by
      simpa only [restoreLocals] using congrArg State.world (same ({ world } : State))
    rw [equal, worldAfter, first.world]
    rfl
  have evaluated := Run.call accepted.analysis rfl main
  let rejected : RejectedExecution accepted.entrypoint.executable ({ world } : State) 5 := {
    after := restoreLocals ({ world } : State) final
    evaluated := by simpa only [accepted.entrypoint.executableDefinition] using evaluated
    failure := {
      nonzero := by decide
      classified := .open
      arguments := by simpa only [restoreLocals] using congrArg Lanius.World.State.arguments finalWorld
      files := by simpa only [restoreLocals] using congrArg Lanius.World.State.files finalWorld
      handles := by simpa only [restoreLocals] using congrArg Lanius.World.State.fileHandles finalWorld
      memorySafe := finalSafe } }
  exact ⟨rejected, finalWorld⟩

/-- An invalid/missing path or oversized file after any nonempty loadable prefix forces finite classified
rejection of the actual executable. The existing all-fuel contracts apply.
Earlier frontend or output errors are allowed, and stdout is unchanged. -/
theorem CheckedExecution.laterFailure (checked : CheckedExecution accepted)
    (supported : LaterFailureDomain world) :
    ∃ code, ∃ rejected : RejectedExecution accepted.entrypoint.executable ({ world } : State) code,
      rejected.after.world.standardOutput = world.standardOutput := by
  obtain ⟨code, after, evaluated, ⟨failure⟩, stdout⟩ := checked.rejectsLater world supported
  exact ⟨code, ⟨after, evaluated, failure⟩, stdout⟩

/-- The actual main closes its first oversized file and returns code 6.
The rejected execution retains finite termination and all-fuel safety. -/
theorem CheckedExecution.oversizedFile (checked : CheckedExecution accepted)
    (supported : OversizedFileDomain world) :
    ∃ rejected : RejectedExecution accepted.entrypoint.executable ({ world } : State) 6,
      rejected.after.world.standardOutput = world.standardOutput := by
  obtain ⟨after, evaluated, ⟨failure⟩, stdout⟩ := checked.rejectsOversized world supported
  exact ⟨⟨after, evaluated, failure⟩, stdout⟩

end Lanius.Extraction.Entry
