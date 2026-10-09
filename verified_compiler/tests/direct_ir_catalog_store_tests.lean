import verified_compiler.tests.direct_ir_catalog_build_tests
import verified_compiler.tests.direct_ir_catalog_store

namespace IRCatalogStoreTests
open Lanius Lanius.Core Lanius.Memory Lanius.Semantics
open IRCatalogCopyProof IREventStoreProof IRTypeRefProof IRRegionAllocationProof

private def signatureValue (id parameters : Int) (result : Reference) : Value :=
  source_value Extracted.«ir::body_catalog».Types.«FunctionSignature».mk
    [.signed .i32 id, referenceValue result, .signed .i32 parameters]
private def bodyValue (signature tree : Value) : Value :=
  source_value Extracted.«ir::body_catalog».Types.«FunctionBody».mk [signature, tree]
private def countValue (value : Int) : Value :=
  source_value Extracted.«ir::body_catalog».Types.«CountCell».mk [.signed .i32 value]
private def nominalType : Value → Ty
  | .structure id _ => .structure id
  | _ => .unit
private def rowType := nominalType (bodyValue .unit .unit)
private def countType := nominalType (countValue 0)
private def rows := Value.rawSlice rowType 792 3
private def count := Value.rawSlice countType 256 1
private def signature := signatureValue 7 2 (.Nominal 5)

/-- The spare row has an invalid old boolean byte. Count storage has only
    the four written field bytes, with no readable native-record padding. -/
def initial : State :=
  ({ IRCatalogBuildTests.funded with heap := {
    blocks := [{ base := 16, size := 40, alignment := 8, bytes := List.replicate 40 0 },
      { base := 256, size := 4, alignment := 8, bytes := i32Bytes 1 },
      { base := 400, size := 16, alignment := 8, bytes := List.replicate 16 165 },
      { base := 512, size := 288, alignment := 8,
        bytes := List.replicate 160 0 ++ encodeNatLE 4 2 ++ List.replicate 124 0 }]
    nextAddress := 800, remaining := some 60 }, world := { standardOutput := [88] } })
    |>.bindLocal (source.argumentId 1) signature
    |>.bindLocal (source.bindingId 0) count
    |>.bindLocal (source.bindingId 1) rows
    |>.bindLocal (source.bindingId 3) (.signed .i32 1)
    |>.bindLocal 9 (.signed .i32 91)

def initialInput : Input initial := {
  count := 1, eventsAddress := 48, eventsLength := 1, events := fun _ => integer 0
  kinds := fun _ => .ExpressionNode, arities := fun _ => 0, rules := fun _ => .NoChildren
  fits := by decide
  below := by
    intro block found
    simp only [initial, State.bindLocal, State.bindCell, List.mem_cons, List.not_mem_nil, or_false] at found
    rcases found with rfl | rfl | rfl | rfl <;> change _ ≤ 800 <;> decide
  reads := by
    intro index inside
    have zero : index = 0 := by change index < 1 at inside; omega
    subst index
    have snapshot : NativeSnapshot 64 extractedProgram initial.heap eventType 16 (integer 0) 12 :=
      NativeSnapshot.enumSingle (by core_lookup) rfl (by decide) (by rfl)
        (NativeSnapshot.i32 0 (by rfl))
    have width : NativeLayout.valueWords? extractedProgram eventType = some 5 := by decide +kernel
    have location : rawSliceElementAddress? extractedProgram eventType 48 0 = .ok 16 := by
      dsimp only [eventType] at width ⊢
      simp only [rawSliceElementAddress?, width]
      rfl
    change readRawSliceIndex extractedProgram initial eventType 48 1 0 = .ok (integer 0)
    rw [readRawSliceIndex, if_neg (by decide), location]
    exact snapshot.read
  classified := IRCatalogBuildTests.fundedInput.classified
  capacity := 1, resultAddress := 9999, resultLength := 1, hasResultTypes := false
  annotations := fun _ => .Invalid, represented := IRCatalogBuildTests.fundedInput.represented
  annotationReads := by intro enabled; cases enabled }

theorem initialRoot : initialInput.toRegion.toSource.Suffix (fun _ => 1) 0 := by
  intro index _ inside
  have zero : index = 0 := by change index < 1 at inside; omega
  subst index
  exact ⟨by decide, by decide, by decide, 1, rfl, .nil⟩

theorem initialBuildEntry : IRCatalogBuildProof.Entry initialInput (some 4) := {
  positive := by decide, fits := by decide, pointerFits := by decide
  sourceFound := by rfl, sourceEvents := by rfl, countFound := by rfl, available := by rfl
  formed := by
    apply State.CellsWellFormed.bindLocal
    apply State.CellsWellFormed.bindLocal
    apply State.CellsWellFormed.bindLocal
    apply State.CellsWellFormed.bindLocal
    apply State.CellsWellFormed.bindLocal
    exact IRCatalogBuildTests.fundedEntry.formed
  unique := by
    intro left leftFound right rightFound same
    simp only [initial, State.bindLocal, State.bindCell, List.mem_cons, List.not_mem_nil, or_false] at leftFound rightFound
    rcases leftFound with rfl | rfl | rfl | rfl <;>
      rcases rightFound with rfl | rfl | rfl | rfl <;> first | rfl | cases same
  noViews := rfl }

/-- Only writable target bytes, represented caller values and signed
    increment safety are established before the general stage theorem. -/
def initialStoreEntry : IRCatalogStoreProof.Entry initialInput (some 4) := {
  build := initialBuildEntry, id := 7, parameters := 2, result := .Nominal 5
  next := 1, rowsAddress := 792, rowsLength := 3, countAddress := 256, countLength := 1
  incrementFits := by decide, rowBound := by decide, rowFloor := by decide
  countBound := by decide
  rowRoom := Heap.Readable.of_loadBytes
    (bytes := List.replicate 64 0 ++ encodeNatLE 4 2 ++ List.replicate 28 0) (by rfl)
  countRoom := Heap.Readable.of_loadBytes (bytes := i32Bytes 1) (by rfl)
  separate := Or.inr (by decide)
  signatureFound := by rfl, rowsFound := by rfl, countFound := by rfl, nextFound := by rfl }

theorem canonicalSuccess : ∃ after,
    RunsStmt extractedProgram initial (source.bindingStatement 5)
      (.returned (some (.signed .i32 1))) after ∧
    ∃ before, ∃ live : IRCatalogBuildProof.Live initialInput (some 4) before,
      IRCatalogStoreProof.Stored initialStoreEntry live after :=
  IRCatalogStoreProof.actualSuccess initialStoreEntry initialRoot (by rfl) (by decide)

private def seed (state : State) (type : Ty) (base : Nat) (value : Value) : Except Trap State := do
  let heap ← writeNativeValue 64 extractedProgram state state.heap type base value
  pure { state with heap }

#eval (do
  let .error .typeMismatch := readNativeValue 64 extractedProgram initial.heap rowType 608
    | throw (IO.userError "corrupt old spare row unexpectedly decoded")
  unless (initial.heap.loadBytes 256 4).toOption == some (i32Bytes 1) &&
      (initial.heap.loadBytes 256 8).toOption.isNone do
    throw (IO.userError "field-only count fixture has readable record padding")
  let .done (.returned (some (.signed .i32 1))) checked :=
      execStmt 1000 extractedProgram initial (source.bindingStatement 5)
    | throw (IO.userError "corrupt-row/four-byte-count actual stage failed")
  unless (readNativeValue 64 extractedProgram checked.heap rowType 608).toOption.isSome &&
      (readNativeValue 64 extractedProgram checked.heap (.scalar (.signed .i32)) 256).toOption ==
        some (.signed .i32 2) do
    throw (IO.userError "corrupt-row/four-byte-count actual stage read-back failed")
  let cases : List (Nat × List Value × Nat × Bool) := [(1, [integer (-7)], 60, true), (2, [integer 9], 60, true),
    (1, [integer 0], 56, false), (2, [integer 1, integer 2], 120, false)]
  for (next, events, budget, succeeds) in cases do
    for enabled in [true, false] do
      let size := events.length
      let eventAddress := 16 + size * 40 - 8
      let typeAddress := if enabled then 128 + size * 16 - 8 else 9999
      let region := source_value Extracted.«ir::body_events».Types.«Region».mk
        [.rawSlice eventType eventAddress size, .rawSlice referenceType typeAddress size,
          .boolean enabled, .signed .i32 size]
      let newSignature := signatureValue (7 + next) next (if enabled then .Nominal 5 else .Void)
      let oldRows := (List.range 3).map fun (index : Nat) => bodyValue
        (signatureValue (40 + index) index (if index == 1 then .NominalSlice 6 else .Bool))
        (IRValidatorProof.treeValue (.rawSlice eventType (48 + index * 8) (index + 1))
          (.rawSlice referenceType (136 + index * 8) index) (index == 1)
          (.rawSlice (.scalar (.signed .i32)) 192 (index + 1)) (index + 1))
      let before : State := ({ heap := {
        blocks := [{ base := 16, size := size * 40, alignment := 8, bytes := List.replicate (size * 40) 0 },
          { base := 128, size := size * 16, alignment := 8, bytes := List.replicate (size * 16) 0 },
          { base := 192, size := 12, alignment := 4, bytes := i32Bytes 1 ++ i32Bytes 2 ++ i32Bytes 3 },
          { base := 256, size := 4, alignment := 8, bytes := i32Bytes next },
          { base := 400, size := 16, alignment := 8, bytes := List.replicate 16 165 },
          { base := 512, size := 288, alignment := 8, bytes := List.replicate 288 90 }]
        nextAddress := 800, remaining := some budget }, world := { standardOutput := [88] } } : State)
        |>.bindLocal (source.argumentId 2) region |>.bindLocal (source.argumentId 3) (.signed .i32 size)
        |>.bindLocal (source.bindingId 2) (.rawSlice eventType eventAddress size)
        |>.bindLocal (source.argumentId 1) newSignature |>.bindLocal (source.bindingId 0) count
        |>.bindLocal (source.bindingId 1) rows |>.bindLocal (source.bindingId 3) (.signed .i32 next)
        |>.bindLocal 9 (.signed .i32 91)
      let mut before := before
      for (event, index) in events.zipIdx do
        let .ok seeded := seed before eventType (16 + (size - index - 1) * 40) event
          | throw (IO.userError "initial event seeding failed")
        before := seeded
        if enabled then
          let .ok seeded := seed before referenceType (128 + (size - index - 1) * 16) (referenceValue (.Nominal 7))
            | throw (IO.userError "initial annotation seeding failed")
          before := seeded
      for (row, index) in oldRows.zipIdx do
        let .ok seeded := seed before rowType (704 - index * 96) row
          | throw (IO.userError "independent initial row seeding failed")
        before := seeded
        unless (readRawSliceIndex extractedProgram before rowType 792 3 index).toOption == some row do
          throw (IO.userError "initial native row did not decode")
      unless (readNativeValue 64 extractedProgram before.heap (.scalar (.signed .i32)) 256).toOption ==
          some (.signed .i32 next) do
        throw (IO.userError "initial count field did not decode")
      if succeeds then
        let .ok heap := before.heap.storeBytes (704 - next * 96 + 64) (encodeNatLE 4 2)
          | throw (IO.userError "spare-row corruption failed")
        before := { before with heap }
        let .error .typeMismatch := readNativeValue 64 extractedProgram before.heap rowType (704 - next * 96)
          | throw (IO.userError "selected spare row remained decodable")
      if !enabled then
        unless (readRawSliceIndex extractedProgram before referenceType typeAddress size 0).toOption.isNone do
          throw (IO.userError "disabled annotations unexpectedly readable")
      let .done (.returned (some result)) after := execStmt 1000 extractedProgram before (source.bindingStatement 5)
        | throw (IO.userError "actual catalog stage did not finish")
      let memory := before.heap.allocationAddress 8
      let endpoints := memory + size * 56
      let built := IRValidatorProof.treeValue (.rawSlice eventType (memory + size * 40 - 8) size)
        (.rawSlice referenceType (memory + size * 56 - 8) size) true
        (.rawSlice (.scalar (.signed .i32)) endpoints size) size
      unless result == .signed .i32 (if succeeds then next else -1) &&
        (readNativeValue 64 extractedProgram after.heap (.scalar (.signed .i32)) 256).toOption ==
          some (.signed .i32 (if succeeds then next + 1 else next)) do
        throw (IO.userError "actual return/count read-back contract failed")
      for (row, index) in oldRows.zipIdx do
        let expected := if succeeds && index == next then bodyValue newSignature built else row
        unless (readRawSliceIndex extractedProgram after rowType 792 3 index).toOption == some expected do
          throw (IO.userError "selected row or old neighbor native read-back failed")
      for block in before.heap.blocks do
        for offset in List.range block.size do
          let location := block.base + offset
          let target := 704 - next * 96
          let written := succeeds && ((target ≤ location && location < target + 96) ||
            (256 ≤ location && location < 260))
          unless written || (after.heap.loadByte block.base offset).toOption ==
              (before.heap.loadByte block.base offset).toOption do
            throw (IO.userError "byte outside actual row/count union changed")
      for (event, index) in events.zipIdx do
        unless (readRawSliceIndex extractedProgram after eventType (memory + size * 40 - 8) size index).toOption == some event &&
          (readRawSliceIndex extractedProgram after referenceType (memory + size * 56 - 8) size index).toOption ==
            some (referenceValue (if enabled then .Nominal 7 else .Invalid)) do
          throw (IO.userError "catalog stores changed copied event/annotation reads")
      if succeeds then
        unless (readRawSliceIndex extractedProgram after (.scalar (.signed .i32)) endpoints size 0).toOption ==
          some (.signed .i32 1) do throw (IO.userError "catalog stores changed the built endpoint")
        let .done (.returned (some tree)) checkpoint := execStmt 1000 extractedProgram before
            (IRCatalogCopyProof.prefix (IRCatalogBuildProof.guardedContinuation
              (.returnValue (some (.local (source.bindingId 12))))))
          | throw (IO.userError "live pre-store checkpoint did not finish")
        unless tree == built && reprStr after.world == reprStr checkpoint.world &&
          after.i32ArrayViews.isEmpty && checkpoint.i32ArrayViews.isEmpty &&
          after.heap.nextAddress == checkpoint.heap.nextAddress && after.heap.remaining == checkpoint.heap.remaining &&
          after.heap.blocks.map (fun block => (block.base, block.size, block.alignment, block.live)) ==
            checkpoint.heap.blocks.map (fun block => (block.base, block.size, block.alignment, block.live)) do
          throw (IO.userError "store-phase world/views/allocation metadata changed")
      unless after.locals == before.locals && (before.cells.all fun cell => after.cell? cell.id == cell.value) &&
        after.world.calls == [.alloc, .alloc] && after.world.standardOutput == [88] && after.i32ArrayViews.isEmpty do
        throw (IO.userError "catalog stage caller/world/allocator frame failed")
  IO.println "catalog-store fixtures: corrupt spare rows, field-only count storage, native read-back, union frame, annotations, rejection and exhaustion" : IO Unit)

#print axioms initialInput
#print axioms initialRoot
#print axioms initialBuildEntry
#print axioms initialStoreEntry
#print axioms canonicalSuccess
end IRCatalogStoreTests
