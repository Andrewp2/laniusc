import verified_compiler.tests.direct_byte_io_read_interface_file

namespace ByteIoReadTotalTests

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics ByteIoReadProof ByteIoReadInterface

private def reader := Extracted.«verified::byte_io».Functions.«read_file».core
private def bytes : List UInt8 := [0, 127, 128, 255, 255, 1, 128, 255, 42, 9, 17, 33]
private def sentinel : List UInt8 := [92, 10, 128, 255]
private def outputHeap (capacity : Nat) : Heap := {
  blocks := [{ base := 16 + max (capacity * 4) 1 + 4, size := 4, alignment := 4, bytes := sentinel }, {
    base := 16, size := capacity * 4, alignment := 4
    bytes := List.flatten (List.replicate capacity (i32Bytes 11)), owned := false }]
  nextAddress := 16 + max (capacity * 4) 1 + 16 }
private def storage (capacity length offset : Nat) (readable present : Bool) : State := {
    heap := (outputHeap capacity).allocatedI32 16384 none
    world := {
      files := if present then [{ path := [1], bytes := bytes.take length }] else []
      fileHandles := [{ id := 3, path := [1], readable, offset }] } }
private def caller (capacity length offset : Nat) (handle : Int) (readable present : Bool) : State :=
  storage capacity length offset readable present
    |>.bindLocal (reader.argumentId 0) (.signed .i32 handle)
    |>.bindLocal (reader.argumentId 1) (.rawSlice (.scalar (.signed .i32)) 16 capacity)
    |>.bindLocal (reader.argumentId 2) (.signed .i32 capacity)
    |>.bindLocal (reader.argumentId 3) (.rawSlice (.scalar (.signed .i32)) (outputHeap capacity).borrowedAddress 16384)
    |>.bindLocal (reader.bindingId 0) (.pointer (outputHeap capacity).borrowedAddress)

-- A real caller has no pre-bound function arguments. Its shadowed total
-- binding and cell must survive the call, including errors and overflow.
private def publicCaller (capacity length offset : Nat) (readable present : Bool) : State :=
  (storage capacity length offset readable present).bindLocal (reader.bindingId 1) (.signed .i32 777)

private def cellValues (state : State) := state.cells.map fun cell => (cell.id, cell.value)
private def heapValues (heap : Heap) :=
  (heap.blocks.map (fun block => (block.base, block.size, block.alignment, block.bytes, block.live, block.owned)),
    heap.nextAddress, heap.remaining)

private theorem below (capacity : Nat) : HeapBlocksBelowNext (outputHeap capacity) := by
  intro block member
  simp only [outputHeap, List.mem_cons, List.not_mem_nil, or_false] at member
  rcases member with rfl | rfl
  · change 16 + max (capacity * 4) 1 + 4 + max 4 1 ≤ 16 + max (capacity * 4) 1 + 16
    omega
  · change 16 + max (capacity * 4) 1 ≤ 16 + max (capacity * 4) 1 + 16
    omega

private theorem unique (capacity : Nat) : HeapBlockBasesUnique (outputHeap capacity) := by
  intro first firstMember second secondMember _
  simp only [outputHeap, List.mem_cons, List.not_mem_nil, or_false] at firstMember secondMember
  rcases firstMember with rfl | rfl <;> rcases secondMember with rfl | rfl <;> simp_all <;> omega

private def context : Context (storage 8 6 0 true true) (caller 8 6 0 3 true true) := {
  address := 64, words := 16384, destination := 16, capacity := 8, handle := 3
  env := (((((LocalEnv.start (by simp [State.CellsWellFormed, storage])).bind
    (reader.argumentId 0) (.signed .i32 3)).bind
    (reader.argumentId 1) (.rawSlice (.scalar (.signed .i32)) 16 8)).bind
    (reader.argumentId 2) (.signed .i32 8)).bind
    (reader.argumentId 3) (.rawSlice (.scalar (.signed .i32)) 64 16384)).bind
    (reader.bindingId 0) (.pointer 64)
  capacityFits := by decide, scratchSize := by decide, separate := by decide
  heap := rfl, world := rfl, views := rfl }

-- The input domain is inhabited by real allocated scratch and output storage.
-- These proofs reuse allocation laws, not reduction of 65,536 literal bytes.
theorem completesActualDeclaration : ∃ value after,
    RunsStmt extractedProgram (caller 8 6 0 3 true true) (reader.bindingStatement 1) (.returned (some value)) after ∧
    Result context.toConfiguration (storage 8 6 0 true true) value after ∧
      after.local? (reader.argumentId 2) = some (.signed .i32 8) := by
  have inputRoom : (caller 8 6 0 3 true true).heap.Readable 64 65536 :=
    Heap.allocatedI32_readable (words := 16384) (budget := none) (below 8)
  have outputRoom : (caller 8 6 0 3 true true).heap.Readable 16 32 :=
    Heap.allocatedI32_oldReadable (heap := outputHeap 8) (words := 16384) (budget := none)
      (Heap.Readable.of_loadBytes
        (show (outputHeap 8).loadBytes 16 32 = .ok (List.flatten (List.replicate 8 (i32Bytes 11))) from rfl))
  obtain ⟨value, after, run, finalEnv, result, _⟩ := declarationTracked context .unobserved True.intro
    ⟨inputRoom, outputRoom⟩
    (Heap.allocatedI32_unique (words := 16384) (budget := none) (below 8) (unique 8)) rfl
  exact ⟨value, after, run, result, finalEnv.read (by rfl)⟩

#print axioms completesActualDeclaration

private def input : Function.Input (publicCaller 8 6 0 true true) := {
  address := 64, words := 16384, destination := 16, capacity := 8, handle := 3
  formed := by simp [State.CellsWellFormed, publicCaller, storage, State.bindLocal, State.bindCell]
  capacityFits := by decide, scratchSize := by decide, separate := by decide
  inputRoom := Heap.allocatedI32_readable (words := 16384) (budget := none) (below 8)
  outputRoom := Heap.allocatedI32_oldReadable (heap := outputHeap 8) (words := 16384) (budget := none)
    (Heap.Readable.of_loadBytes
      (show (outputHeap 8).loadBytes 16 32 = .ok (List.flatten (List.replicate 8 (i32Bytes 11))) from rfl))
  unique := Heap.allocatedI32_unique (words := 16384) (budget := none) (below 8) (unique 8)
  noViews := rfl }

theorem completesActualCall : ∃ value after,
    RunsExpr extractedProgram (publicCaller 8 6 0 true true) (.call reader.id (input.values.map Expr.value)) value after ∧
    Result input.toConfiguration (publicCaller 8 6 0 true true) value after ∧
    after.local? (reader.bindingId 1) = some (.signed .i32 777) := by
  obtain ⟨value, after, run, result, _, _⟩ := Function.call input
  exact ⟨value, after, run, result, result.choose_spec.2.1.localFound run.choose_spec.2 _ _ rfl⟩

#print axioms completesActualCall

-- The frame protects real allocated bytes in the gap between both buffers,
-- not a convex hull that would incorrectly grant permission to that gap.
theorem retainsOutsideStorage : ∃ value after,
    RunsExpr extractedProgram (publicCaller 8 6 0 true true) (.call reader.id (input.values.map Expr.value)) value after ∧
    after.heap.loadBytes 52 4 = .ok sentinel ∧
    after.heap.loadByte 0 0 = (publicCaller 8 6 0 true true).heap.loadByte 0 0 ∧
    after.heap.nextAddress = (publicCaller 8 6 0 true true).heap.nextAddress ∧
    after.heap.remaining = (publicCaller 8 6 0 true true).heap.remaining := by
  obtain ⟨value, after, run, result, _, _⟩ := Function.call input
  obtain ⟨_, _, _, _, _, _, _, _, writes⟩ := result
  refine ⟨value, after, run, writes.loadBytes (by rfl) ?_, writes.outside 0 0 ?_, writes.frontier, writes.budget⟩
  · intro index bound
    change ¬((64 ≤ 52 + index ∧ 52 + index < 64 + 16384 * 4) ∨
      (16 ≤ 52 + index ∧ 52 + index < 16 + 8 * 4))
    omega
  · change ¬((64 ≤ 0 ∧ 0 < 64 + 16384 * 4) ∨ (16 ≤ 0 ∧ 0 < 16 + 8 * 4))
    omega

#print axioms retainsOutsideStorage

private def sourceFile : World.FileEntry := { path := [1], bytes := bytes.take 6 }
private def sourceHandle : World.FileHandle := { id := 3, path := [1], readable := true }

-- The stronger theorem is inhabited by the same actual allocated caller.
-- It proves bytes/cursor/trace, rather than checking an assumed successful run.
theorem readsActualFile : ∃ after,
    RunsExpr extractedProgram (publicCaller 8 6 0 true true) (.call reader.id (input.values.map Expr.value))
      (.signed .i32 6) after ∧
    after.heap.loadBytes 16 24 = .ok ((bytes.take 6).flatMap Loop.encodeByte) ∧
    after.heap.loadByte 16 24 = .ok 11 ∧
    after.world.handle? 3 = some { sourceHandle with offset := 6 } ∧
    after.world.calls = [.read, .read] := by
  have cursor : World.FileCursor (publicCaller 8 6 0 true true).world input.handle sourceFile sourceHandle := ⟨rfl, rfl, rfl⟩
  obtain ⟨value, after, run, _, final, _, _⟩ := File.call input (by decide) cursor (by decide)
  have returned : value = .signed .i32 6 := Option.some.inj (Completion.returned.inj final.1)
  subst value
  exact ⟨after, run, final.loaded (by decide),
    (final.tail (index := 24) (by decide) (by decide)).trans (by rfl), final.2.1.found, final.2.2.1⟩

#print axioms readsActualFile

theorem readTraceBoundaries :
    ([0, 1, 65535, 65536, 65537, 131072].map fun length => (length + 65535) / 65536 + 1) =
      [1, 2, 2, 2, 3, 3] := rfl

-- Cursor updates must use the selected handle even if an environment has
-- duplicate IDs. Zero requests, EOF and past-EOF offsets are distinct cases.
#eval (do
  for length in [0, 1, 3] do
    for offset in [0, 1, 4] do
      for request in [0, 1, 3, 5] do
        let file : World.FileEntry := { path := [1], bytes := bytes.take length }
        let handle : World.FileHandle := { id := 3, path := [1], offset, readable := true }
        let world : World.State := { files := [file], fileHandles := [handle,
          { id := 3, path := [9], offset := 777 }, { id := 7, path := [1], offset := 9, readable := true }] }
        match World.readFileBytes world 3 request with
        | some (delivered, after) =>
            let expected := file.bytes.drop offset |>.take request
            unless delivered == expected && (after.handle? 3).map World.FileHandle.offset == some (offset + expected.length) &&
                (after.handle? 7).map World.FileHandle.offset == some 9 &&
                after.calls == world.calls && reprStr after.files == reprStr world.files do
              throw (IO.userError s!"cursor frame failed: length={length}, offset={offset}, request={request}")
        | none => throw (IO.userError "readable cursor failed") : IO Unit)

-- Invalid storage has an inhabited rejection domain: there is no heap or
-- output argument here, so neither can be silently required by the proof.
private def nullScratch : State := ({} : State)
  |>.bindLocal (reader.argumentId 2) (.signed .i32 8)
  |>.bindLocal (reader.argumentId 3) (.rawSlice (.scalar (.signed .i32)) 0 0)
theorem rejectsUnreadableScratch : ∃ after,
    RunsStmt extractedProgram nullScratch (reader.body.getD .skip)
      (.returned (some (.signed .i32 (-2)))) after ∧ PureFrame nullScratch after :=
  Function.rejectScratch
    (by simp [nullScratch, State.CellsWellFormed, State.bindLocal, State.bindCell]) rfl rfl (by decide)

#print axioms rejectsUnreadableScratch

private def check (capacity length offset : Nat) (handle : Int) (readable present asCall : Bool) : IO Unit := do
  let before := if asCall then publicCaller capacity length offset readable present
    else caller capacity length offset handle readable present
  let available := (bytes.take length).drop offset
  let valid := handle == 3 && readable && present
  let succeeds := valid && available.length ≤ capacity
  let expected : Int := if !valid then -1 else if !succeeds then -2 else available.length
  let observed := if asCall then evalExpr 110 extractedProgram before (.call reader.id [
      .value (.signed .i32 handle), .value (.rawSlice (.scalar (.signed .i32)) 16 capacity),
      .value (.signed .i32 capacity),
      .value (.rawSlice (.scalar (.signed .i32)) (outputHeap capacity).borrowedAddress 16384)])
    else match execStmt 100 extractedProgram before (reader.bindingStatement 1) with
      | .done (.returned (some value)) after => .done value after
      | _ => .outOfFuel
  match observed with
  | .done (.signed .i32 actual) after =>
      let output := if succeeds then (available.flatMap Loop.encodeByte) ++
        List.flatten (List.replicate (capacity - available.length) (i32Bytes 11))
        else List.flatten (List.replicate capacity (i32Bytes 11))
      let correctOutput := match after.heap.loadBytes 16 (capacity * 4) with
        | .ok actual => actual == output
        | _ => false
      let frame := (match after.heap.loadBytes (16 + max (capacity * 4) 1 + 4) 4 with
          | .ok actual => actual == sentinel | _ => false) &&
        reprStr (after.heap.loadByte 0 0) == reprStr (before.heap.loadByte 0 0) &&
        after.heap.nextAddress == before.heap.nextAddress && after.heap.remaining == before.heap.remaining &&
        (after.heap.blocks.map fun block => (block.base, block.size, block.alignment, block.live, block.owned)) ==
          (before.heap.blocks.map fun block => (block.base, block.size, block.alignment, block.live, block.owned))
      let delivered := if valid then min available.length (capacity + 1) else 0
      let cursor := match after.world.handle? 3 with
        | some file => file.offset == offset + delivered
        | none => false
      let calls := if succeeds && !available.isEmpty then [.read, .read] else [.read]
      unless actual == expected && correctOutput && frame && cursor && after.world.calls == calls &&
          after.locals == before.locals && (cellValues after).take before.cells.length == cellValues before &&
          after.local? (reader.bindingId 1) == before.local? (reader.bindingId 1) &&
          after.local? (reader.argumentId 2) == before.local? (reader.argumentId 2) do
        throw (IO.userError s!"whole read failed: call={asCall}, capacity={capacity}, length={length}, offset={offset}, handle={handle}, readable={readable}, present={present}")
  | _ => throw (IO.userError "whole read failed to return")

#eval (do
  for asCall in [false, true] do
    for capacity in List.range 13 do
      for length in List.range 13 do
        for offset in [0, 2, 14] do check capacity length offset 3 true true asCall
      check capacity 12 0 9 true true asCall
      check capacity 12 0 3 false true asCall
      check capacity 12 0 3 true false asCall
  for capacity in [-1, -2147483648, 0, 8] do
    let before := publicCaller 8 6 0 true true
    match evalExpr 110 extractedProgram before (.call reader.id [
        .value (.signed .i32 3), .value (.rawSlice (.scalar (.signed .i32)) 16 8),
        .value (.signed .i32 capacity), .value (.rawSlice (.scalar (.signed .i32)) 0 16384)]) with
    | .done (.signed .i32 (-2)) after =>
        unless heapValues after.heap == heapValues before.heap && reprStr after.world == reprStr before.world &&
            after.locals == before.locals && (cellValues after).take before.cells.length == cellValues before do
          throw (IO.userError "early rejection touched caller stores")
    | _ => throw (IO.userError "early rejection failed") : IO Unit)

#eval IO.println "proof-interface reader total runtime: PASS"

end ByteIoReadTotalTests
