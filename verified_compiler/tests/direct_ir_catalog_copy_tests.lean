import verified_compiler.tests.direct_ir_catalog_copy_domain
open Lanius Lanius.Core Lanius.Memory Lanius.Semantics
open IREventStoreProof IRTypeRefProof IRRegionAllocationProof
private def copyIntegerBytes (value : Int) : List UInt8 :=
  encodeNatLE 4 0 ++ List.replicate 4 165 ++ i32Bytes value ++ List.replicate 28 165
private def copySourceBytes : List UInt8 :=
  copyIntegerBytes 99 ++ encodeNatLE 4 5 ++ List.replicate 4 165 ++
    encodeNatLE 8 9999 ++ encodeNatLE 8 2 ++ i32Bytes 3 ++ List.replicate 12 165 ++ copyIntegerBytes (-7) ++
    encodeNatLE 4 0 ++ List.replicate 12 165 ++ encodeNatLE 4 8 ++
    List.replicate 4 165 ++ i32Bytes 7 ++ List.replicate 4 165

#eval (do
  let catalog := Extracted.«ir::body_catalog».Functions.«append».core
  let string := source_value Extracted.«ir::body_events».Types.«StringValue».mk
    [.rawSlice (.scalar (.signed .i32)) 9999 2, .signed .i32 3]
  let events := [integer (-7), source_value Extracted.«ir::body_events».Types.«Event».«ExpressionString» [string]]
  let annotations := [referenceValue (.Nominal 7), invalid]
  let probe : Stmt := .returnValue (some (.array .unit
    [.local (catalog.bindingId 7), .local (catalog.argumentId 3), .local (catalog.bindingId 11)]))
  for (count, budget, allocates) in [(0, 112, false), (38347923, 112, false), (2, 111, true)] do
    let before : State := ({ heap := { remaining := some budget }, world := { standardOutput := [88] } } : State)
      |>.bindLocal (catalog.argumentId 3) (.signed .i32 count) |>.bindLocal 9 (.signed .i32 91)
    let .done (.returned (some result)) after := execStmt 600 extractedProgram before (IRCatalogCopyProof.prefix probe)
      | throw (IO.userError "prefix rejection guard did not return")
    unless result == .signed .i32 (-1) && after.locals == before.locals &&
      (before.cells.all fun cell => after.cell? cell.id == cell.value) && after.heap.blocks.isEmpty &&
      after.heap.remaining == some budget && after.heap.nextAddress == before.heap.nextAddress &&
      after.world.calls == (if allocates then [.alloc] else []) && after.world.standardOutput == [88] do
      throw (IO.userError "prefix rejection changed the caller or reached the continuation")
  for enabled in [true, false] do
    let types := Value.rawSlice referenceType (if enabled then 160 else 9999) 2
    let region := source_value Extracted.«ir::body_events».Types.«Region».mk
      [.rawSlice eventType 128 3, types, .boolean enabled, .signed .i32 3]
    let before : State := ({ heap := {
      blocks := [{ base := 16, size := 152, alignment := 8, bytes := copySourceBytes },
        { base := 176, size := 104, alignment := 8, bytes := List.replicate 104 90 }]
      nextAddress := 281, remaining := some 112 }, world := { standardOutput := [88] } } : State)
      |>.bindLocal (catalog.argumentId 2) region |>.bindLocal (catalog.argumentId 3) (.signed .i32 2)
      |>.bindLocal (catalog.bindingId 2) (.rawSlice eventType 128 3) |>.bindLocal 9 (.signed .i32 91)
    match readRawSliceIndex extractedProgram before (.scalar (.signed .i32)) 9999 2 0 with
    | .ok _ => throw (IO.userError "opaque copied descriptor pointee became readable") | .error _ => pure ()
    if !enabled then
      match readRawSliceIndex extractedProgram before referenceType 9999 2 0 with
      | .ok _ => throw (IO.userError "disabled fixture type buffer became readable") | .error _ => pure ()
    let .done (.returned (some (.array [owned, active, index]))) after :=
      execStmt 600 extractedProgram before (IRCatalogCopyProof.prefix probe)
      | throw (IO.userError "actual allocation-copy prefix did not reach its continuation")
    unless owned == regionValue 288 2 && active == .signed .i32 2 && index == .signed .i32 2 do
      throw (IO.userError "cut lost owned/count readiness or copy termination")
    for (position, event) in (List.range 2).zip events do
      let .ok value := readRawSliceIndex extractedProgram after eventType 360 2 position
        | throw (IO.userError "copied event unreadable")
      let .ok annotation := readRawSliceIndex extractedProgram after referenceType 392 2 position
        | throw (IO.userError "copied annotation unreadable")
      let some expected := annotations[position]? | throw (IO.userError "fixture annotation missing")
      unless value == event && annotation == (if enabled then expected else invalid) do
        throw (IO.userError "copy changed an event payload or TypeRef")
    for block in before.heap.blocks do
      let .ok bytes := after.heap.loadBytes block.base block.size | throw (IO.userError "old block unreadable")
      unless bytes == block.bytes do throw (IO.userError "copy changed source/catalog/sentinel bytes")
    unless after.locals == before.locals && (before.cells.all fun cell => after.cell? cell.id == cell.value) &&
      after.nextCell >= before.nextCell && (after.cells.drop before.cells.length).all (fun cell =>
        before.nextCell <= cell.id && cell.id < after.nextCell) && after.heap.blocks.length == before.heap.blocks.length + 1 &&
      after.heap.remaining == some 0 && after.heap.nextAddress == 400 && after.world.calls == [.alloc] &&
      after.world.standardOutput == [88] && after.i32ArrayViews.isEmpty do throw (IO.userError "stage frame changed")
  IO.println "catalog-copy fixtures: 2 annotation modes, opaque descriptor, 3 guard cases, frame and allocation" : IO Unit)
