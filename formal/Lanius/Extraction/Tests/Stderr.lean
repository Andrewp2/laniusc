import Lanius.Extraction.Host.Stderr
import Lanius.Extraction.Tests.Host
import Lean.Util.CollectAxioms

namespace Lanius.Extraction.Tests.Stderr

open Lanius.Core Lanius.Semantics

/-- Check the actual diagnostic host declaration with dirty registered arrays
and nonempty stdout/stderr, source files, and unrelated open handles. -/
def check (program : Program) (function : FunctionId) : IO Unit := do
  unless (Lanius.Extraction.Host.checkExternal? program .writeByte 2 function).isSome do
    throw (IO.userError "diagnostic writer is not the two-argument byte service")
  let values := [-2147483648, -257, -256, -1] ++ (List.range 256).map Int.ofNat ++ [256, 257, 2147483647]
  for value in values do
    let (registered, _) ← Host.prepare {
      arguments := ["extractor", "source.lani"]
      standardInput := [17, 23]
      standardOutput := [65, 66]
      standardError := [67]
      files := [⟨[70], [0, 255, 128]⟩]
      fileHandles := [{ id := 7, path := [70], offset := 2, readable := true }]
      nextFileHandle := 8 } 3
    let before := registered.bindLocal 17 (.signed .i32 (-29))
    let .done (.signed .i32 1) after := evalExpr 60 program before
        (.call function [.value (.signed .i32 2), .value (.signed .i32 value)])
      | throw (IO.userError s!"diagnostic byte call failed for {value}")
    let expected := Lanius.Extraction.Host.stderrWorld before.world value
    unless after.world.standardError == expected.standardError && after.world.calls == expected.calls &&
        after.world.standardOutput == before.world.standardOutput && after.world.standardInput == before.world.standardInput &&
        after.world.arguments == before.world.arguments && after.world.nextFileHandle == before.world.nextFileHandle &&
        after.world.files.map (fun file => (file.path, file.bytes)) == before.world.files.map (fun file => (file.path, file.bytes)) &&
        after.world.fileHandles.map (fun handle => (handle.id, handle.path, handle.offset, handle.readable, handle.writable)) ==
          before.world.fileHandles.map (fun handle => (handle.id, handle.path, handle.offset, handle.readable, handle.writable)) &&
        after.locals == before.locals && after.nextCell == before.nextCell && after.heap.remaining == before.heap.remaining &&
        after.cells.map (fun cell => (cell.id, cell.value)) == before.cells.map (fun cell => (cell.id, cell.value)) &&
        after.i32ArrayViews.map (fun view => (view.address, view.root, view.projections, view.length)) ==
          before.i32ArrayViews.map (fun view => (view.address, view.root, view.projections, view.length)) do
      throw (IO.userError "stderr byte changed stdout, inputs, handles, registered words, or caller bindings")
  IO.println "263 diagnostic-byte executions preserve input files, stdout, handles, and all registered arrays"

private def fixture : Program := {
  functions := [⟨12, [(0, .scalar (.signed .i32)), (1, .scalar (.signed .i32))],
    .scalar (.signed .i32), none, some (.host .writeByte)⟩] }

#eval check fixture 12

run_elab do
  for assumption in ← Lean.collectAxioms ``Lanius.Extraction.Host.evaluatesStderr do
    unless assumption == ``propext || assumption == ``Classical.choice || assumption == ``Quot.sound do
      throwError "Diagnostic byte proof adds unexpected axiom {assumption}"

end Lanius.Extraction.Tests.Stderr
