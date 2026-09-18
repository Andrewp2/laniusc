import Lanius.Extraction.Allocation.Failure
import Lanius.Extraction.Entry.Failure
import Lanius.Execution
import Lean.Util.CollectAxioms

namespace Lanius.Extraction.Tests.Allocation
open Lanius.Core Lanius.Semantics Lanius.Extraction.Allocation

private def steps : List Step := [⟨⟨10, 2⟩, 11, by decide⟩, ⟨⟨12, 3⟩, 13, by decide⟩]
private def source : Sequence := ⟨steps, .returnValue (some (.value (.signed .i32 42)))⟩
private def fixture : Program := { functions := [
  ⟨7, [⟨0, .scalar (.unsigned .usize)⟩, ⟨1, .scalar (.unsigned .usize)⟩],
    .scalar .rawPtr, none, some (.host .alloc)⟩,
  ⟨8, [], .scalar (.signed .i32), some (source.statement 7), none⟩] }

example : Lanius.Relational.CoreSuccess.Supported (source.statement 7) = true := by decide

/-- Small finite budgets cover failure before the first buffer, failure after
one registered buffer, exact capacity, and excess capacity. The continuation's
distinct return detects accidental execution after a failed allocation. -/
def check : IO Unit := do
  let some checked := checkSequence? 7 [2, 3] (source.statement 7)
    | throw (IO.userError "guarded allocation source was rejected")
  unless checked.locals.buffers.map Buffer.count == [2, 3] do
    throw (IO.userError "allocation checker lost the source buffer capacities")
  for available in List.range 25 do
    let world : Lanius.World.State := {
      arguments := ["extractor", "missing"], standardOutput := [17, 18], standardError := [19],
      files := [⟨[97], [99]⟩], fileHandles := [⟨5, [97], 0, true, false⟩], calls := [.argc] }
    let before : State := { world, heap := { remaining := some available } }
    let .returned (.signed .i32 code) after := Lanius.Execution.run 64 ⟨fixture, 8⟩ before
      | throw (IO.userError s!"allocation trapped or failed to terminate at byte budget {available}")
    let completed := if available < 8 then 0 else if available < 20 then 1 else 2
    let calls := if available < 8 then 1 else 2
    let spent := if completed == 0 then 0 else if completed == 1 then 8 else 20
    unless code == (if available < 20 then 3 else 42) &&
        after.i32ArrayViews.length == completed && after.heap.blocks.length == completed &&
        after.heap.remaining == some (available - spent) && after.locals.isEmpty &&
        after.world.calls == world.calls ++ List.replicate calls .alloc &&
        after.world.arguments == world.arguments && after.world.standardOutput == world.standardOutput &&
        after.world.standardError == world.standardError &&
        after.world.files.map (fun file => (file.path, file.bytes)) == world.files.map (fun file => (file.path, file.bytes)) &&
        after.world.fileHandles.map (fun handle => (handle.id, handle.offset)) ==
          world.fileHandles.map (fun handle => (handle.id, handle.offset)) do
      throw (IO.userError s!"guarded allocation violated its return/resource/frame contract at byte budget {available}")
  let unguarded : Stmt := .letLocal 10 (.slice (.scalar (.signed .i32)))
    (.i32SliceFromRawParts (.call 7 [.value (.unsigned .usize 8), .value (.unsigned .usize 4)])
      (.value (.signed .i32 2))) .skip
  if (checkSequence? 7 [2] unguarded).isSome then
    throw (IO.userError "unsafe slice-before-null-check ordering reused the source proof")
  let step : Step := ⟨⟨10, 2⟩, 11, by decide⟩
  let .letLocal pointer type initializer (.sequence guard tail) := step.initialize 7
    | throw (IO.userError "guarded fixture lacks an allocation followed by a guard")
  for body in [
      .letLocal pointer type initializer
        (.sequence (.ifThenElse (.binary .equal (.local pointer) (.value (.pointer 0)))
          (.sequence (.returnValue (some (.value (.signed .i32 4)))) .skip) .skip) tail),
      .letLocal pointer type initializer tail,
      .letLocal pointer type initializer (.sequence tail guard)] do
    let changed := .letUninitialized step.buffer.binding (.slice (.scalar (.signed .i32))) (.sequence body .skip)
    if (checkSequence? 7 [2] changed).isSome then
      throw (IO.userError "changed or missing allocation rejection reused the source proof")
  IO.println "Guarded allocations: 25 byte budgets cover both failure positions and success; unsafe/missing/changed guards are rejected."

/-- Exercise the actual source-linked main with exhausted budgets before any
file lookup. The generic theorem additionally covers every later allocation;
these small executions avoid allocating the extractor's large workspaces. -/
def checkExecutable (checked : Entry.CheckedExecution accepted) : IO Unit := do
  for available in [0, 1023, 1024, 5119] do
    let world : Lanius.World.State := {
      arguments := ["extractor", "missing"], standardOutput := [17, 18], standardError := [19],
      files := [⟨[97], [99]⟩], fileHandles := [⟨-1, [97], 100, false, true⟩],
      nextFileHandle := 2 ^ 80, calls := [.close] }
    let before : State := { world, heap := { remaining := some available } }
    have base := (Lanius.Properties.initial_world_state_has_runtime_type accepted.checked.program.core world).typed.wellFormed
    have wellFormed : Lanius.Properties.StateWellFormed before :=
      ⟨⟨base.heapWellFormed.nextAddressPositive, base.heapWellFormed.blockBasesUnique,
        base.heapWellFormed.blocksWellFormed, base.heapWellFormed.blocksDisjoint,
        base.heapWellFormed.blocksBelowNext⟩, base.cellIdsUnique, base.cellIdsBelowNext, base.localsReferenceCells⟩
    if short : available < byteCount checked.buffers then
      have _publicFailure := checked.allocationFailure before wellFormed rfl rfl
        (by change 1 < (2 : Nat); decide) (by change (2 : Nat) < 2 ^ 31; decide) rfl short
      pure ()
    else throw (IO.userError "allocation failure fixture has enough memory for the full source sequence")
    let .returned (.signed .i32 3) after := Lanius.Execution.run 128 accepted.entrypoint.executable before
      | throw (IO.userError s!"actual extractor failed to reject byte budget {available} with code 3")
    let completed := if available < 1024 then 0 else 1
    unless after.locals.isEmpty && after.i32ArrayViews.length == completed &&
        after.heap.blocks.length == completed &&
        after.heap.remaining == some (available - completed * 1024) &&
        after.world.calls == world.calls ++ [.argc] ++ List.replicate (completed + 1) .alloc &&
        after.world.arguments == world.arguments && after.world.standardOutput == world.standardOutput &&
        after.world.standardError == world.standardError &&
        after.world.files.map (fun file => (file.path, file.bytes)) == world.files.map (fun file => (file.path, file.bytes)) &&
        after.world.fileHandles.map (fun handle => (handle.id, handle.offset)) ==
          world.fileHandles.map (fun handle => (handle.id, handle.offset)) do
      throw (IO.userError "actual allocation rejection changed inputs, output, handles, or registered invalid storage")
  IO.println "Actual extractor rejects four exhausted budgets with code 3 before file access; the public theorem covers all allocation positions."

#eval check

run_elab do
  for name in #[``Registry.allocateRaw, ``Registry.allocationExhausted, ``Registry.mapRaw,
      ``Step.initializes, ``Step.rejectsExhaustion, ``hostSequence_executes,
      ``hostSequence_rejectsExhaustion, ``CheckedAllocator.rejectsExhaustion,
      ``Entry.CheckedExecution.allocationFailure,
      ``Lanius.Relational.CoreSuccess.ofExecutes,
      ``Lanius.Relational.CoreSuccess.StmtExecutes.toExecutes] do
    for assumption in ← Lean.collectAxioms name do
      unless #[``propext, ``Classical.choice, ``Quot.sound].contains assumption do
        throwError "Guarded allocation theorem {name} adds unexpected axiom {assumption}"
  Lean.logInfo "Guarded success, exhaustion, and allocation-sequence proofs use only standard Lean axioms."

end Lanius.Extraction.Tests.Allocation
