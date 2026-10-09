import verified_compiler.tests.direct_ir_allocation
import verified_compiler.tests.direct_host_views
import Lanius.Semantics.SourceValue

namespace IRAllocationTests

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRAllocationProof

private def source := Extracted.«verified::host».Functions.«alloc_i32».core
private def builder := Extracted.«ir::body_tree».Functions.«build».core
private def oldHeap : Heap := {
  blocks := [{ base := 4, size := 4, alignment := 4, bytes := [7, 0, 0, 0], owned := false }]
  nextAddress := 8
  remaining := some 8 }
private def before : State := { heap := oldHeap }
private theorem beforeFormed : before.CellsWellFormed := by simp [State.CellsWellFormed, before]
private theorem below : HeapBlocksBelowNext oldHeap := by
  intro block member
  simp only [oldHeap, List.mem_singleton] at member
  subst block
  decide

private theorem storage : before.I32ViewsReady extractedProgram (fun _ => none) := by
  refine ⟨⟨?_, ?_, ?_⟩, below, by simp [State.I32ViewsUnique, before]⟩
  · intro cell type declared; cases declared
  · simp [HeapBlockBasesUnique, before, oldHeap]
  · intro view member; cases member

-- A real old block survives allocating/protecting the two-word endpoint table.
theorem allocateThenBorrow :
    ∃ allocated ready,
      RunsExpr extractedProgram before (.call source.id [.value (.signed .i32 2)]) (.pointer 8) allocated ∧
      RunsExpr extractedProgram allocated (.call Extracted.«verified::host».Functions.«i32_slice_from_raw_parts».core.id
        [.value (.pointer 8), .value (.signed .i32 2)]) (.rawSlice (.scalar (.signed .i32)) 8 2) ready ∧
      ready.heap.Readable 8 8 ∧ ready.heap.loadBytes 4 4 = .ok [7, 0, 0, 0] := by
  obtain ⟨allocated, ready, run, sliceRun, _, _, _, valid, reads, _⟩ := actualScratch
    2 (by decide) (by decide) beforeFormed storage rfl (by intro available same; cases same; decide)
  refine ⟨allocated, ready, run, sliceRun, ?_, ?_⟩
  · cases valid with | raw readable => exact readable
  · exact reads.loadBytes (by rfl)

-- Parameter/body cells and fresh scratch storage retain a preexisting raw
-- descriptor; validity is derived from its old allocation, not shape typing.
theorem retainsOldSlice : ∃ allocated ready,
    RunsExpr extractedProgram before (.call source.id [.value (.signed .i32 2)]) (.pointer 8) allocated ∧
    I32SliceValid extractedProgram (fun _ => none) ready (.rawSlice (.scalar (.signed .i32)) 4 1) 1 := by
  obtain ⟨allocated, ready, allocate, _, cells, _, _, _, reads, _⟩ := actualScratch
    2 (by decide) (by decide) beforeFormed storage rfl (by intro available same; cases same; decide)
  exact ⟨allocated, ready, allocate,
    (I32SliceValid.raw (program := extractedProgram) (types := fun _ => none)
      (Heap.Readable.of_loadBytes (show before.heap.loadBytes 4 4 = .ok [7, 0, 0, 0] from rfl))).retained cells reads⟩

-- The connected actual allocation/constructor/read contract covers every
-- file environment and handle, including invalid handles and empty requests.
theorem readsFreshScratch (world : World.State) (handle : Int) (bound : count ≤ 8) :
    ∃ allocated scratch value after,
      RunsExpr extractedProgram { before with world } (.call source.id [.value (.signed .i32 2)])
        (.pointer 8) allocated ∧
      RunsExpr extractedProgram scratch (.call Extracted.«verified::host».Functions.«read».core.id
        [.value (.signed .i32 handle), .i32SliceDataPtr (.value (.rawSlice (.scalar (.signed .i32)) 8 2)),
          .value (.unsigned .usize count)]) value after ∧
      after.I32ViewsReady extractedProgram (fun _ => none) ∧ after.I32ViewsCoherent extractedProgram (fun _ => none) ∧
      after.heap.Readable 8 8 ∧
      scratch.world = World.record world .alloc ∧
      FileReadResult scratch.heap scratch.world handle 8 count value after.heap after.world := by
  obtain ⟨allocated, scratch, value, after, allocate, _, _, initialized, read, ready, coherent, readable, effect⟩ :=
    HostViewsProof.readScratch (before := { before with world }) (handle := handle)
      2 (by decide) (by decide) beforeFormed ⟨⟨storage.store, storage.unique, storage.views⟩, storage.below, storage.keys⟩
      rfl (by intro available same; cases same; decide) bound
  change RunsExpr extractedProgram scratch (.call Extracted.«verified::host».Functions.«read».core.id
    [.value (.signed .i32 handle), .i32SliceDataPtr (.value (.rawSlice (.scalar (.signed .i32)) before.heap.borrowedAddress 2)),
      .value (.unsigned .usize count)]) value after at read
  change RunsExpr extractedProgram { before with world } (.call source.id [.value (.signed .i32 2)])
    (.pointer before.heap.borrowedAddress) allocated at allocate
  change FileReadResult scratch.heap scratch.world handle before.heap.borrowedAddress count value after.heap after.world at effect
  change after.heap.Readable before.heap.borrowedAddress 8 at readable
  rw [show before.heap.borrowedAddress = 8 from by decide] at read allocate effect readable
  exact ⟨allocated, scratch, value, after, allocate, read, ready, coherent, readable, initialized, effect⟩

private def fileWorld (bytes : List UInt8) (offset : Nat) : World.State := {
  files := [{ path := [65], bytes }]
  fileHandles := [{ id := 9, path := [65], offset, readable := true }] }

private def readWorld (bytes : List UInt8) (offset count : Nat) : World.State := {
  World.record (World.record (fileWorld bytes offset) .alloc) .read with
  fileHandles := [{ id := 9, path := [65], offset := offset + ((bytes.drop offset).take count).length, readable := true }] }

-- Exact data and cursor behavior for every file, initial offset and bounded
-- request. EOF and zero requests are included; host success is derived.
theorem readFreshBytes (bytes : List UInt8) (offset : Nat) (bound : count ≤ 8) :
    ∃ allocated scratch after,
      RunsExpr extractedProgram { before with world := fileWorld bytes offset }
        (.call source.id [.value (.signed .i32 2)]) (.pointer 8) allocated ∧
      RunsExpr extractedProgram scratch (.call Extracted.«verified::host».Functions.«read».core.id
        [.value (.signed .i32 9), .i32SliceDataPtr (.value (.rawSlice (.scalar (.signed .i32)) 8 2)),
          .value (.unsigned .usize count)]) (World.i32Result ((bytes.drop offset).take count).length) after ∧
      after.heap.loadBytes 8 ((bytes.drop offset).take count).length = .ok ((bytes.drop offset).take count) ∧
      after.world = readWorld bytes offset count := by
  obtain ⟨allocated, scratch, value, after, allocate, read, _, _, _, initialized, effect⟩ :=
    readsFreshScratch (fileWorld bytes offset) 9 bound
  rw [initialized] at effect
  have actual : World.readFileBytes (World.record (World.record (fileWorld bytes offset) .alloc) .read) 9 count =
      some ((bytes.drop offset).take count, readWorld bytes offset count) := by rfl
  simp only [FileReadResult, actual] at effect
  obtain ⟨rfl, world, _, written⟩ := effect
  exact ⟨allocated, scratch, after, allocate, read, written.loadBytes, world⟩

-- Invalid handles preserve scratch bytes and only record the read attempt.
theorem readInvalidHandle (bound : count ≤ 8) : ∃ allocated scratch after,
    RunsExpr extractedProgram before (.call source.id [.value (.signed .i32 2)]) (.pointer 8) allocated ∧
    RunsExpr extractedProgram scratch (.call Extracted.«verified::host».Functions.«read».core.id
      [.value (.signed .i32 9), .i32SliceDataPtr (.value (.rawSlice (.scalar (.signed .i32)) 8 2)),
        .value (.unsigned .usize count)]) (World.i32Result (-1)) after ∧
    after.heap = scratch.heap ∧ after.world = World.record scratch.world .read := by
  obtain ⟨allocated, scratch, value, after, allocate, read, _, _, _, initialized, effect⟩ :=
    readsFreshScratch {} 9 bound
  have absent : World.readFileBytes (World.record scratch.world .read) 9 count = none := by
    rw [initialized]; rfl
  simp only [FileReadResult, absent] at effect
  obtain ⟨rfl, heap, world⟩ := effect
  exact ⟨allocated, scratch, after, allocate, read, heap, world⟩

theorem readFitsRequest (world : World.State) (handle : Int) (bound : count ≤ 8) : ∃ scratch number after,
    RunsExpr extractedProgram scratch (.call Extracted.«verified::host».Functions.«read».core.id
      [.value (.signed .i32 handle), .i32SliceDataPtr (.value (.rawSlice (.scalar (.signed .i32)) 8 2)),
        .value (.unsigned .usize count)]) (.signed .i32 number) after ∧
    (number = -1 ∨ 0 ≤ number ∧ number ≤ count) := by
  obtain ⟨_, scratch, value, after, _, read, _, _, _, _, effect⟩ := readsFreshScratch world handle bound
  obtain ⟨number, rfl, range⟩ := effect.returnBound (by omega)
  exact ⟨scratch, number, after, read, range⟩

theorem exhausted : ∃ after,
    RunsExpr extractedProgram ({ heap := { remaining := some 7 } } : State)
      (.call source.id [.value (.signed .i32 2)]) (.pointer 0) after ∧
      after.heap = ({ remaining := some 7 } : Heap) ∧
      after.world = World.record ({} : World.State) .alloc := by
  obtain ⟨after, run, _, heap, world, _⟩ := actualAllocate (before := { heap := { remaining := some 7 } })
    2 (by decide) (by simp [State.CellsWellFormed]) rfl
  exact ⟨after, run, heap, world⟩

example : ∃ after, RunsExpr extractedProgram before (.call source.id [.value (.signed .i32 (-1))])
    (.pointer 0) after ∧ PureFrame before after := actualReject (-1) (by decide) beforeFormed
example : ∃ after, RunsExpr extractedProgram before (.call source.id [.value (.signed .i32 536870912)])
    (.pointer 0) after ∧ PureFrame before after := actualReject 536870912 (by decide) beforeFormed

private def endsHeap : Heap := ({} : Heap).appendI32 [0, 0, 0, 0, 2, 0, 0, 0] false none
private def storeBefore : State := ({ heap := endsHeap } : State)
  |>.bindLocal (builder.bindingId 1) (.rawSlice (.scalar (.signed .i32)) 4 2)
  |>.bindLocal (builder.bindingId 3) (.signed .i32 0)
  |>.bindLocal (builder.bindingId 5) (.signed .i32 2)

-- The child's nonzero endpoint remains intact when its parent is stored.
theorem storePreservesChild : ∃ heap,
    RunsExpr extractedProgram storeBefore (builder.effectExpression 0) .unit { storeBefore with heap } ∧
    heap.loadBytes 8 4 = .ok (i32Bytes 2) ∧
    readRawSliceIndex extractedProgram { storeBefore with heap } (.scalar (.signed .i32)) 4 2 0 =
      .ok (.signed .i32 2) := by
  have initialFormed : ({ heap := endsHeap } : State).CellsWellFormed := by simp [State.CellsWellFormed]
  obtain ⟨heap, run, _, _, parent, preserved⟩ := actualEndpointStore (before := storeBefore)
    2 0 2 4 (by decide) (by decide) (by core_local) (by core_local) (by core_local)
    (Heap.appendI32_readable (by simp [HeapBlocksBelowNext]))
    (Heap.appendI32_unique (by simp [HeapBlocksBelowNext]) (by simp [HeapBlockBasesUnique])) rfl
  exact ⟨heap, run, preserved 1 (by decide) (by decide) _ (by rfl), parent⟩

private def eventType := (Extracted.«ir::body_tree».Functions.«shape».core.parameters[0]?).getD (0, .unit) |>.2
private def referenceType := (Extracted.«ir::type_ref».Functions.«is_invalid».core.parameters[0]?).getD (0, .unit) |>.2
private def emptyRegion := source_value Extracted.«ir::body_events».Types.«Region».mk
  [.rawSlice eventType 0 0, .rawSlice referenceType 0 0, .boolean false, .signed .i32 0]
private def emptyTree := source_value Extracted.«ir::body_tree».Types.«Tree».mk
  [.rawSlice eventType 0 0, .rawSlice referenceType 0 0, .boolean false,
    .rawSlice (.scalar (.signed .i32)) 0 0, .signed .i32 0]

-- Executable source-call regressions, not a substitute for the open builder proof.
#eval (do
  let calls := [Expr.call Extracted.«ir::body_tree».Functions.«empty».core.id [],
    Expr.call builder.id [.value emptyRegion, .value (.signed .i32 0)]]
  for call in calls do
    match evalExpr 30 extractedProgram {} call with
    | .done value after =>
        unless value == emptyTree && after.heap.blocks.isEmpty && after.i32ArrayViews.isEmpty do
          throw (IO.userError "empty tree changed its representation or touched backing storage")
    | _ => throw (IO.userError "empty tree source call did not return normally") : IO Unit)

#print axioms allocateThenBorrow
#print axioms exhausted
#print axioms retainsOldSlice
#print axioms readsFreshScratch
#print axioms readFreshBytes
#print axioms readInvalidHandle
#print axioms readFitsRequest
#print axioms storePreservesChild

end IRAllocationTests
