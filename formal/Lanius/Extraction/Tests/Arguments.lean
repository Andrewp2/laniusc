import Lanius.Extraction.Entry.Failure
import Lean.Util.CollectAxioms

namespace Lanius.Extraction.Tests.Arguments
open Lanius.Core Lanius.Semantics Lanius.Extraction.Entry

private def fixtureEntry : Entry.Arguments := ⟨7, 42,
  .returnValue (some (.value (.signed .i32 2)))⟩

private def fixture : Program := { functions := [
  ⟨7, [], .scalar (.signed .i32), none, some (.host .argc)⟩,
  ⟨8, [], .scalar (.signed .i32), some fixtureEntry.statement, none⟩] }

/-- Unrelated host state must not impose file-loading preconditions on the
argument guard. The final fixture deliberately violates handle freshness and
representability; none of those fields is read on the rejection path. -/
private def worlds : List Lanius.World.State :=
  [[], ["extractor"]].flatMap fun arguments => [
    { arguments },
    { arguments, standardOutput := [41, 42], standardError := [255, 0],
      files := [⟨[97], [0, 255, 128]⟩],
      fileHandles := [⟨3, [97], 7, true, false⟩], nextFileHandle := 3 },
    { arguments, standardInput := [99], environment := [("x", "y")],
      files := [⟨[98], [17]⟩], fileHandles := [⟨-1, [98], 100, false, true⟩],
      nextFileHandle := 2 ^ 80, calls := [.close] }]

private def assertUnchanged (world : Lanius.World.State) (after : State) : IO Unit := do
  unless after.world.arguments == world.arguments &&
      after.world.files.map (fun file => (file.path, file.bytes)) ==
        world.files.map (fun file => (file.path, file.bytes)) &&
      after.world.fileHandles.map (fun handle =>
        (handle.id, handle.path, handle.offset, handle.readable, handle.writable)) ==
        world.fileHandles.map (fun handle =>
          (handle.id, handle.path, handle.offset, handle.readable, handle.writable)) &&
      after.world.nextFileHandle == world.nextFileHandle &&
      after.world.standardOutput == world.standardOutput &&
      after.world.standardError == world.standardError &&
      after.world.calls == world.calls ++ [.argc] &&
      after.heap.blocks.isEmpty && after.i32ArrayViews.isEmpty && after.locals.isEmpty do
    throw (IO.userError "no-input rejection changed external inputs, output, handles, or allocated storage")

/-- Run both rejection cases through the whole executable, not just argc or a
handwritten model of the guard. Shared with the exact self-source integration. -/
private def checkRuns (executable : Lanius.Execution.Executable) : IO Unit := do
  for world in worlds do
    let .returned (.signed .i32 1) after := Lanius.Execution.run 32 executable { world }
      | throw (IO.userError "no-input invocation did not terminate with code 1")
    assertUnchanged world after

def check : IO Unit := do
  let some checked := checkArguments? fixture fixtureEntry.statement
    | throw (IO.userError "source-shaped argument guard was rejected")
  for world in worlds do
    if missing : world.arguments.length ≤ 1 then
      have _sourceExecution := checked.rejectsNoInputs ({ world } : State)
        (Lanius.Properties.initial_world_state_has_runtime_type fixture world).typed.wellFormed rfl missing
      pure ()
    else throw (IO.userError "rejection fixture unexpectedly has requested files")
  checkRuns ⟨fixture, 8⟩
  let .returned (.signed .i32 2) _ := Lanius.Execution.run 32 ⟨fixture, 8⟩
      { world := { arguments := ["extractor", "a"] } }
    | throw (IO.userError "valid argument count failed to enter the continuation")
  let changed : Stmt := .letLocal fixtureEntry.count (.scalar (.signed .i32))
    (.call fixtureEntry.function []) (.sequence
      (.ifThenElse (.binary .lessEqual (.local fixtureEntry.count) (.value (.signed .i32 0)))
        (.sequence (.returnValue (some (.value (.signed .i32 1)))) .skip) .skip)
      fixtureEntry.continuation)
  if (checkArguments? fixture changed).isSome then
    throw (IO.userError "changed rejection threshold reused the exact-source proof")
  IO.println "No-input rejection preserves host state in six cases; valid input reaches the continuation and a changed guard is rejected."

def checkExecutable (checked : CheckedExecution accepted) : IO Unit := do
  for world in worlds do
    if missing : world.arguments.length ≤ 1 then
      have _termination := (checked.noInputs world missing).terminates
      have _allFuelContracts := (checked.noInputs world missing).contracts
      have _worldPreserved := checked.noInputs_world world missing
      pure ()
    else throw (IO.userError "rejection fixture unexpectedly has requested files")
  checkRuns accepted.entrypoint.executable
  IO.println "Actual checked extractor rejects no-input invocations with exact code 1, preserved files/handles/output, and no allocations."

#eval check

run_elab do
  for name in #[``CheckedArguments.rejectsNoInputs, ``Run.call,
      ``RejectedExecution.terminates, ``RejectedExecution.observations,
      ``RejectedExecution.contracts, ``CheckedExecution.noInputs,
      ``CheckedExecution.noInputs_world] do
    for assumption in ← Lean.collectAxioms name do
      unless #[``propext, ``Classical.choice, ``Quot.sound].contains assumption do
        throwError "Whole-entrypoint rejection theorem {name} adds unexpected axiom {assumption}"
  Lean.logInfo "The no-input source proof, actual entrypoint connection, and public failure contracts use only standard Lean axioms."

end Lanius.Extraction.Tests.Arguments
