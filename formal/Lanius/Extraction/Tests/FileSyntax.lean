import Lanius.Extraction.Entry.File.Syntax
import Lean.Util.CollectAxioms

namespace Lanius.Extraction.Tests.FileSyntax
open Lanius.Core Lanius.Semantics Lanius.Extraction.CompactOutput
open Lanius.Extraction.Entry.File

/-- Small call-administration checks, not a substitute frontend. The eight
slice values carry production capacities without allocating large arrays. -/
def checkStage (function : FunctionId) (stage : Syntax.Stage) : IO Unit := do
  unless (Syntax.check? function (stage.statement function)).isSome do
    throw (IO.userError "exact frontend call site rejected")
  for index in [3, 5, 7, 9, 11, 13, 15, 16] do
    let changed := .letLocal stage.result stage.resultType
      (.call function (stage.arguments.set index (number 17))) stage.continuation
    if (Syntax.check? function changed).isSome then
      throw (IO.userError s!"frontend call site accepted a changed capacity/depth at argument {index}")
  if (Syntax.check? (function + 1) (stage.statement function)).isSome then
    throw (IO.userError "frontend call site accepted a different callee")
  for count in [0, 1, 65536] do
    let buffers : List Value :=
      [.slice i32 101 [] 0 65536, .slice i32 102 [] 0 2179, .slice i32 103 [] 0 65536,
        .slice i32 104 [] 0 65536, .slice i32 105 [] 0 65536, .slice i32 106 [] 0 4194304,
        .slice i32 107 [] 0 1048576, .slice i32 108 [] 0 65536]
    let before := ({} : State).bindLocals ((stage.bufferLocals.zip buffers) ++ [(stage.length, .signed .i32 count)])
    let expected := [buffers[0], .signed .i32 count, buffers[1], .signed .i32 2179,
      buffers[2], .signed .i32 65536, buffers[3], .signed .i32 65536, buffers[4], .signed .i32 65536,
      buffers[5], .signed .i32 4194304, buffers[6], .signed .i32 1048576, buffers[7], .signed .i32 65536, .signed .i32 1024]
    let .done values after := evalExprs 30 {} before stage.arguments
      | throw (IO.userError "frontend call argument evaluation failed")
    unless values == expected && after.cells.map (fun cell => (cell.id, cell.value)) ==
        before.cells.map (fun cell => (cell.id, cell.value)) && after.locals == before.locals && after.nextCell == before.nextCell do
      throw (IO.userError "frontend call mixed logical count, physical capacity, buffer order, or caller locals")

def checkPipeline (pipeline : Load.Pipeline program) (stage : Syntax.Stage) : IO Unit := do
  unless (Syntax.checkRelation? pipeline stage).isSome do
    throw (IO.userError "loaded frontend has disconnected count or shadowed buffer arguments")
  let clobbered := [pipeline.path.length, pipeline.unpack.locals.cursor, pipeline.opened.handle,
    pipeline.read.count, pipeline.read.closed]
  for id in clobbered do
    for changed in [{ stage with source := id }, { stage with grammar := id }, { stage with raw := id },
        { stage with canonical := id }, { stage with kinds := id }, { stage with workspace := id },
        { stage with records := id }, { stage with offsets := id }] do
      if (Syntax.checkRelation? pipeline changed).isSome then
        throw (IO.userError "loaded frontend accepted a buffer argument shadowed by file loading")
  if (Syntax.checkRelation? pipeline { stage with length := pipeline.read.count + 1 }).isSome then
    throw (IO.userError "loaded frontend accepted a count not supplied by the reader")

private def stage : Syntax.Stage := ⟨0, 1, 2, 3, 4, 5, 6, 7, 8, 9, i32, .skip⟩
#eval checkStage 7 stage

run_elab do
  let standard : Array Lean.Name := #[``propext, ``Classical.choice, ``Quot.sound]
  for name in #[``Load.Loaded.frontend_input, ``Syntax.Stage.arguments_evaluate, ``Syntax.Stage.loaded_reads,
      ``Syntax.check?, ``Syntax.checkRelation?] do
    for assumption in ← Lean.collectAxioms name do
      unless standard.contains assumption do
        throwError "file/frontend handoff {name} adds unexpected axiom {assumption}"
  let baseline ← Lean.collectAxioms ``Frontend.CheckedSyntax.call_evaluates
  for name in #[``Load.Loaded.frontend_evaluates, ``Syntax.Stage.executes, ``Syntax.loaded_syntax] do
    let axioms ← Lean.collectAxioms name
    unless axioms.all (fun ax => standard.contains ax || baseline.contains ax) do
      throwError "file/frontend composition {name} adds assumptions beyond its frontend baseline"
  Lean.logInfo "Whole file-load/frontend prefix checked: no added axioms beyond the existing frontend baseline."

end Lanius.Extraction.Tests.FileSyntax
