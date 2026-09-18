import Lanius.Extraction.Entry.Run
import Lean.Util.CollectAxioms

namespace Lanius.Extraction.Tests.Output
open Lanius.Core Lanius.Extraction.Entry

/-- Reject disconnected packing inputs and a tail that changes live scratch
bindings or the stdout service. These mutations are applied to actual source. -/
def checkSource (source : Entry.Output.Source program stage) : IO Unit := do
  for changed in [
      { stage with previous := source.preparation.packing.workspace },
      { stage with previous := source.stdout.pointer },
      { stage with capacity := stage.capacity + 1 },
      { stage with continuation := .sequence .skip stage.continuation }] do
    if (Entry.Output.check? program changed).isSome then
      throw (IO.userError "final output accepted changed scope, capacity, or intervening statements")
  for packing in [
      { source.preparation.packing with input := source.preparation.packing.workspace },
      { source.preparation.packing with length := source.preparation.wordCount },
      { source.preparation.packing with cursor := source.stdout.pointer }] do
    let preparation := { source.preparation with packing }
    if (Entry.Output.check? program { stage with continuation := preparation.statement }).isSome then
      throw (IO.userError "final output accepted disconnected input/length or a clobbered stdout pointer")
  for stdout in [
      { source.stdout with length := source.preparation.wordCount },
      { source.stdout with size := source.stdout.pointer },
      { source.stdout with function := program.functions.length + 1000000 }] do
    let preparation := { source.preparation with continuation := stdout.statement }
    if (Entry.Output.check? program { stage with continuation := preparation.statement }).isSome then
      throw (IO.userError "final output accepted a different stdout length, pointer scope, or callee")

run_elab do
  let standard : Array Lean.Name := #[``propext, ``Classical.choice, ``Quot.sound]
  for name in #[``CompactDecode.UnitData.encoding_ascii, ``CompactDecode.renderedPack_bytes,
      ``Entry.Files.History.rendered, ``OutputPacking.prepare_and_write,
      ``Entry.Output.Source.executes, ``Entry.Startup.Ready.completeOutput,
      ``Entry.Run.body_typed, ``Entry.Run.evaluates, ``Entry.Run.observations,
      ``Entry.File.Emit.Stage.executes, ``Entry.Startup.executes] do
    for assumption in ← Lean.collectAxioms name do
      unless standard.contains assumption do
        throwError "Final-output theorem {name} adds unexpected axiom {assumption}"
  Lean.logInfo "Whole main constructs finite execution and the public Success/Failure contracts on its loading/resource domain, using only standard Lean axioms."

end Lanius.Extraction.Tests.Output
