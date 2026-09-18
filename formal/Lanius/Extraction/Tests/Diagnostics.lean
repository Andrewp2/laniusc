import Lanius.Extraction.Diagnostics.Frontend
import Lanius.Extraction.Tests.Host
import Lean.Util.CollectAxioms

namespace Lanius.Extraction.Tests.Diagnostics

open Lanius.Core Lanius.Semantics Lanius.Extraction

/-- Exercise decimal boundaries with registered native arrays and existing
host state. Lean's integer renderer is an independent oracle for the text;
the public proof needs termination and preservation, not exact wording. -/
def checkNatural (program : Program) (function : FunctionId) : IO Unit := do
  let boundaries := (List.range 10).flatMap fun power =>
    let value : Int := 10 ^ power
    [value - 1, value, value + 1]
  let values := [-2147483648, -1, 0, 2147483647] ++ boundaries
  for value in values do
    let (registered, _) ← Host.prepare {
      arguments := ["extractor", "source.lani"]
      standardInput := [128, 255]
      standardOutput := [65, 66]
      standardError := [67]
      files := [⟨[70], [0, 255, 128]⟩]
      fileHandles := [{ id := 7, path := [70], offset := 2, readable := true }]
      nextFileHandle := 8 } 3
    let before := registered.bindLocal 17 (.signed .i32 (-29))
    let .done (.signed .i32 result) after := evalExpr 500 program before
        (.call function [.value (.signed .i32 value)])
      | throw (IO.userError s!"diagnostic natural call trapped or exhausted for {value}")
    let bytes := if value < 0 then [] else Lanius.World.utf8Bytes (toString value ++ "\n")
    let expectedResult : Int := if value < 0 then -1 else bytes.length
    let expectedWorld : Lanius.World.State := { before.world with
      standardError := before.world.standardError ++ bytes
      calls := before.world.calls ++ List.replicate bytes.length .writeByte }
    unless result == expectedResult && reprStr after.world == reprStr expectedWorld &&
        after.locals == before.locals && after.heap.remaining == before.heap.remaining &&
        after.i32ArrayViews.map (fun view => (view.address, view.root, view.projections, view.length)) ==
          before.i32ArrayViews.map (fun view => (view.address, view.root, view.projections, view.length)) do
      throw (IO.userError s!"diagnostic natural changed its result, host inputs, or memory layout for {value}")
    for cell in before.cells do
      unless (after.cellEntry? cell.id).map (fun entry => (entry.id, entry.value)) == some (cell.id, cell.value) do
        throw (IO.userError "diagnostic natural changed a pre-existing caller cell or registered array")
    let .ok synced := syncI32ViewsToHeap after | throw (IO.userError "diagnostic natural left an unsynchronizable view")
    let .ok refreshed := syncI32ViewsFromHeap synced | throw (IO.userError "diagnostic natural left an unreadable native view")
    for view in after.i32ArrayViews do
      unless refreshed.cell? view.root == after.cell? view.root do
        throw (IO.userError "diagnostic natural changed registered words on native round trip")
  IO.println s!"{values.length} diagnostic natural cases pass decimal boundaries, caller preservation, and native round trips"

private def fixture : Program := {
  functions := [
    ⟨12, [(0, .scalar (.signed .i32)), (1, .scalar (.signed .i32))], .scalar (.signed .i32), none, some (.host .writeByte)⟩,
    ⟨13, [(0, .scalar (.signed .i32))], .scalar (.signed .i32), some (Diagnostics.Natural.body 12), none⟩] }

#eval checkNatural fixture 13

def checkFrontend (checked : Diagnostics.CheckedFrontend program typeId argument resultId source) : IO Unit := do
  for changed in [Lanius.Core.Stmt.skip, CompactOutput.returned (CompactOutput.number 28),
      Diagnostics.statement checked.writer.source.source.function.id
        ((checked.accessors.arguments argument resultId).reverse) 28,
      Diagnostics.statement checked.writer.source.source.function.id
        (checked.accessors.arguments argument resultId) 6] do
    if (Diagnostics.checkFrontend? program typeId argument resultId changed).isSome then
      throw (IO.userError "frontend diagnostics accepted missing/reordered calls or the wrong failure code")
  for (index, status, detail, position, nodes, words) in
      ([(1, 1, -1, -1, 0, 0), (127, 6, 93, 65536, 1048576, 1048576),
        (2147483647, 2, 2147483647, 0, 1, 4)] : List (Int × Int × Int × Int × Int × Int)) do
    let (registered, _) ← Host.prepare {
      arguments := ["extractor", "bad.lani"]
      standardOutput := [65, 66]
      standardError := [67]
      files := [⟨[70], [0, 255, 128]⟩]
      fileHandles := [{ id := 7, path := [70], offset := 2, readable := true }]
      nextFileHandle := 8 } 3
    let before := registered.bindLocals [(argument, .signed .i32 index),
      (resultId, Frontend.syntaxResult typeId status detail 31 37 nodes words position)]
    let .done (.returned (some (.signed .i32 28))) after := execStmt 1000 program.core before source
      | throw (IO.userError "complete frontend diagnostic branch trapped, exhausted, or returned another code")
    let bytes := [index, status, detail, position, nodes, words].flatMap fun value =>
      if value < 0 then [] else Lanius.World.utf8Bytes (toString value ++ "\n")
    let expectedWorld : Lanius.World.State := { before.world with
      standardError := before.world.standardError ++ bytes
      calls := before.world.calls ++ List.replicate bytes.length .writeByte }
    unless reprStr after.world == reprStr expectedWorld && after.locals == before.locals &&
        after.heap.remaining == before.heap.remaining do
      throw (IO.userError "frontend diagnostic calls changed their order, host inputs, or caller state")
    for cell in before.cells do
      unless (after.cellEntry? cell.id).map (fun entry => (entry.id, entry.value)) == some (cell.id, cell.value) do
        throw (IO.userError "frontend diagnostic sequence changed an existing cell")
  IO.println "actual six-call frontend diagnostics execute, preserve caller inputs, and reject disconnected source variants"

run_elab do
  for name in #[``Diagnostics.Natural.Checked.write, ``Diagnostics.Argument.bounded,
      ``Diagnostics.sequence, ``Diagnostics.CheckedFrontend.executes,
      ``Lanius.Semantics.Prefix.Reaches.typed] do
    for assumption in ← Lean.collectAxioms name do
      unless assumption == ``propext || assumption == ``Classical.choice || assumption == ``Quot.sound do
        throwError "diagnostic execution proof {name} adds unexpected axiom {assumption}"
  Lean.logInfo "Natural diagnostics and the complete six-call frontend failure branch use only standard Lean axioms."

end Lanius.Extraction.Tests.Diagnostics
