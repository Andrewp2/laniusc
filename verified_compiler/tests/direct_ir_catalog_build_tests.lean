import verified_compiler.tests.direct_ir_catalog_build
import verified_compiler.tests.direct_ir_catalog_copy_domain

namespace IRCatalogBuildTests
open Lanius Lanius.Core Lanius.Memory Lanius.Semantics
open IRCatalogCopyProof IREventStoreProof IRTypeRefProof IRRegionAllocationProof

/-- The accepted independent one-event domain, with a real four-byte second
    allocation budget. No successful copy/build/validation is assumed. -/
def funded : State := { IRCatalogCopyDomain.original with
  heap := { IRCatalogCopyDomain.original.heap with remaining := some 60 } }
def fundedInput : Input funded := {
  count := 1, eventsAddress := 48, eventsLength := 1, events := fun _ => integer 0
  kinds := fun _ => .ExpressionNode, arities := fun _ => 0, rules := fun _ => .NoChildren
  fits := by decide, below := IRCatalogCopyDomain.input.below
  reads := by
    have preserved : HeapReads IRCatalogCopyDomain.original.heap funded.heap := fun _ _ _ read => read
    intro index inside
    exact preserved.rawSlice (IRCatalogCopyDomain.input.reads index inside)
  classified := IRCatalogCopyDomain.input.classified
  capacity := 1, resultAddress := 9999, resultLength := 1, hasResultTypes := false
  annotations := fun _ => .Invalid, represented := IRCatalogCopyDomain.input.represented
  annotationReads := by intro enabled; cases enabled }

theorem independentRoot : fundedInput.toRegion.toSource.Suffix (fun _ => 1) 0 := by
  intro index _ inside
  have zero : index = 0 := by change index < 1 at inside; omega
  subst index
  exact ⟨by decide, by decide, by decide, 1, rfl, .nil⟩

theorem fundedEntry : IRCatalogBuildProof.Entry fundedInput (some 4) := {
  positive := by decide, fits := by decide, pointerFits := by decide
  sourceFound := by rfl, sourceEvents := by rfl, countFound := by rfl, available := by rfl
  formed := by
    change IRCatalogCopyDomain.original.CellsWellFormed
    apply State.CellsWellFormed.bindLocal
    apply State.CellsWellFormed.bindLocal
    apply State.CellsWellFormed.bindLocal
    simp [State.CellsWellFormed]
  unique := by
    intro left leftFound right rightFound _
    simp only [funded, IRCatalogCopyDomain.original, State.bindLocal, State.bindCell,
      List.mem_singleton] at leftFound rightFound
    exact leftFound.trans rightFound.symm
  noViews := rfl }

theorem canonicalSuccess : ∃ after,
    RunsStmt extractedProgram funded
      (IRCatalogCopyProof.prefix (IRCatalogBuildProof.guardedContinuation .skip)) .next after ∧
    IRCatalogBuildProof.StagePost fundedInput (some 4) .next after :=
  IRCatalogBuildProof.actualSuccessStage fundedEntry independentRoot (by rfl) (by decide)

private def parent := source_value Extracted.«ir::body_events».Types.«Event».«ExpressionUnaryPositive» []
private def eventBytes : Value → List UInt8
  | .enumeration _ tag payload => encodeNatLE 4 tag ++ List.replicate 4 165 ++
      (match (payload[0]? : Option Value) with | some (.signed .i32 value) => i32Bytes value | _ => List.replicate 4 0) ++
      List.replicate 28 165
  | _ => []
private def annotationBytes := encodeNatLE 4 8 ++ List.replicate 4 165 ++ i32Bytes 7 ++ List.replicate 4 165

#eval (do
  let probe : Stmt := .returnValue (some (.array .unit
    [.local (source.bindingId 12), .local (source.bindingId 7), .local (source.argumentId 3),
      .local (source.argumentId 1), .local (source.bindingId 0), .local (source.bindingId 1),
      .local (source.bindingId 3)]))
  let cases := [([integer (-7)], 60, true), ([integer (-7)], 56, false),
    ([integer (-7)], 59, false), ([integer 1, integer 2], 120, false), ([parent], 60, false)]
  for (events, budget, succeeds) in cases do
    for enabled in [true, false] do
      let count := events.length
      let originalBytes := events.reverse.flatMap eventBytes ++ List.flatten (List.replicate count annotationBytes)
      let eventAddress := 16 + count * 40 - 8
      let typeAddress := if enabled then 16 + count * 56 - 8 else 9999
      let region := source_value Extracted.«ir::body_events».Types.«Region».mk
        [.rawSlice eventType eventAddress count, .rawSlice referenceType typeAddress count,
          .boolean enabled, .signed .i32 count]
      let countCell := source_value Extracted.«ir::body_catalog».Types.«CountCell».mk [.signed .i32 0]
      let row := source_value Extracted.«ir::body_catalog».Types.«FunctionBody».mk []
      let .structure countId _ := countCell | throw (IO.userError "count-cell type selection")
      let .structure rowId _ := row | throw (IO.userError "catalog-row type selection")
      let countStorage := Value.rawSlice (.structure countId) 256 1
      let rows := Value.rawSlice (.structure rowId) 352 1
      let signature := source_value Extracted.«ir::body_catalog».Types.«FunctionSignature».mk
        [.signed .i32 7, referenceValue .I32, .signed .i32 0]
      let before : State := ({ heap := {
        blocks := [{ base := 16, size := originalBytes.length, alignment := 8, bytes := originalBytes },
          { base := 256, size := 104, alignment := 8, bytes := i32Bytes 0 ++ List.replicate 100 90 }]
        nextAddress := 361, remaining := some budget }, world := { standardOutput := [88] } } : State)
        |>.bindLocal (source.argumentId 2) region |>.bindLocal (source.argumentId 3) (.signed .i32 count)
        |>.bindLocal (source.bindingId 2) (.rawSlice eventType eventAddress count)
        |>.bindLocal (source.argumentId 1) signature |>.bindLocal (source.bindingId 0) countStorage
        |>.bindLocal (source.bindingId 1) rows |>.bindLocal (source.bindingId 3) (.signed .i32 0)
        |>.bindLocal 9 (.signed .i32 91)
      for (event, index) in events.zipIdx do
        unless (readRawSliceIndex extractedProgram before eventType eventAddress count index).toOption == some event do
          throw (IO.userError "build fixture source event encoding")
      if !enabled then
        unless (readRawSliceIndex extractedProgram before referenceType typeAddress count 0).toOption.isNone do
          throw (IO.userError "disabled source annotations are unexpectedly readable")
      let memory := before.heap.allocationAddress 8
      let endpoints := memory + count * 56
      let .done (.returned (some result)) after := execStmt 1000 extractedProgram before
          (IRCatalogCopyProof.prefix (IRCatalogBuildProof.guardedContinuation probe))
        | throw (IO.userError "actual catalog build/guard did not finish")
      if succeeds then
        let expectedTree := IRValidatorProof.treeValue (.rawSlice eventType (memory + count * 40 - 8) count)
          (.rawSlice referenceType (memory + count * 56 - 8) count) true
          (.rawSlice (.scalar (.signed .i32)) endpoints count) count
        unless result == .array [expectedTree, regionValue memory count, .signed .i32 count,
          signature, countStorage, rows, .signed .i32 0] &&
          (readRawSliceIndex extractedProgram after (.scalar (.signed .i32)) endpoints count 0).toOption ==
            some (.signed .i32 1) do throw (IO.userError "live tree/owned/count or physical endpoint changed")
      else
        unless result == .signed .i32 (-1) do throw (IO.userError "rejected build reached the catalog-write continuation")
      for (event, index) in events.zipIdx do
        unless (readRawSliceIndex extractedProgram after eventType (memory + count * 40 - 8) count index).toOption == some event &&
          (readRawSliceIndex extractedProgram after referenceType (memory + count * 56 - 8) count index).toOption ==
            some (if enabled then referenceValue (.Nominal 7) else invalid) do
          throw (IO.userError "build changed copied event or annotation reads")
      for block in before.heap.blocks do
        unless (after.heap.loadBytes block.base block.size).toOption == some block.bytes do
          throw (IO.userError "build changed source/catalog sentinel bytes")
      let secondAllocates := count * 60 ≤ budget
      unless after.locals == before.locals && (before.cells.all fun cell => after.cell? cell.id == cell.value) &&
        after.nextCell ≥ before.nextCell && (after.cells.drop before.cells.length).all (fun cell =>
          before.nextCell ≤ cell.id && cell.id < after.nextCell) &&
        after.heap.blocks.length == before.heap.blocks.length + (if secondAllocates then 2 else 1) &&
        after.heap.remaining == some (budget - count * 56 - (if secondAllocates then count * 4 else 0)) &&
        after.heap.nextAddress == endpoints + (if secondAllocates then count * 4 else 0) &&
        (after.heap.blocks.map (·.base)).eraseDups.length == after.heap.blocks.length &&
        after.heap.blocks.all (fun block => block.base + max block.size 1 ≤ after.heap.nextAddress) &&
        after.world.calls == [.alloc, .alloc] && after.world.standardOutput == [88] && after.i32ArrayViews.isEmpty do
        throw (IO.userError "build caller/memory/allocator frame changed")
  IO.println "catalog-build fixtures: rooted success, forest/malformed rejection, second allocation exhaustion, annotations and frame" : IO Unit)

#print axioms fundedInput
#print axioms independentRoot
#print axioms fundedEntry
#print axioms canonicalSuccess
end IRCatalogBuildTests
