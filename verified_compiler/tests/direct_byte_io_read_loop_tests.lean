import verified_compiler.tests.direct_byte_io_read_step

namespace ByteIoReadLoopTests

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics Lanius.Extraction ByteIoReadProof.Loop

private def reader := Extracted.«verified::byte_io».Functions.«read_file».core
private def packed : List UInt8 := [0, 127, 128, 255, 255, 1, 128, 255]
private def caller : State :=
  ({ heap := {
      blocks := [
        { base := 4, size := 8, alignment := 4, bytes := packed, owned := false },
        { base := 16, size := 32, alignment := 4,
          bytes := List.flatten (List.replicate 8 (i32Bytes 11)), owned := false }]
      nextAddress := 48 } } : State)
    |>.bindLocal (reader.argumentId 3) (.rawSlice (.scalar (.signed .i32)) 4 2)
    |>.bindLocal (reader.argumentId 1) (.rawSlice (.scalar (.signed .i32)) 16 8)
    |>.bindLocal (reader.bindingId 2) (.signed .i32 8)
    |>.bindLocal (reader.bindingId 3) (.signed .i32 7)
private def prepared (total count : Nat) : State :=
  caller
    |>.bindLocal (reader.bindingId 1) (.signed .i32 total)
    |>.bindLocal (reader.bindingId 5) (.signed .i32 count)

private def input : Input (prepared 1 6) := {
  address := 4, words := 2, destination := 16, capacity := 8, total := 1, bytes := packed.take 6
  fits := by decide, inputSize := by decide, outputSize := by decide, separate := by decide
  inputRoom := Heap.Readable.of_loadBytes rfl, outputRoom := Heap.Readable.of_loadBytes rfl
  loaded := by rfl, noViews := rfl, packed := rfl, output := rfl, cursor := rfl, count := rfl
  formed := by simp [State.CellsWellFormed, prepared, caller, State.bindLocal, State.bindCell]
  unique := by simp [HeapBlockBasesUnique, prepared, caller, State.bindLocal, State.bindCell] }

-- A proof instance crosses a packed-word boundary, includes both sign-bit
-- lanes and a partial final word, and starts at a nonzero destination cursor.
theorem copiesTwoWords : ∃ after,
    RunsStmt extractedProgram ((prepared 1 6).bindLocal (reader.bindingId 6) (.signed .i32 0))
      (.whileLoop (reader.whileLoop 1).1 (reader.whileLoop 1).2) .next after ∧
    Invariant input after 6 ∧ after.heap.loadBytes 4 8 = .ok packed := by
  obtain ⟨after, run, frame⟩ := run input
  exact ⟨after, run, frame, frame.written.loadBytes_disjoint (by rfl) (Or.inr (by decide))⟩

#print axioms copiesTwoWords

-- This instantiates the actual initializer and total update too; the count
-- temporary is removed when restoring the enclosing scope, not the heap effect.
theorem commitsChunk : ∃ after,
    RunsStmt extractedProgram (prepared 1 6) ByteIoReadProof.ReadStep.continuation .next after ∧
    (restoreLocals (caller.bindLocal (reader.bindingId 1) (.signed .i32 1)) after).local? (reader.bindingId 1) =
      some (.signed .i32 7) ∧ after.local? (reader.bindingId 6) = none ∧
    after.heap.loadBytes 4 8 = .ok packed := by
  have formed : caller.CellsWellFormed := by simp [State.CellsWellFormed, caller, State.bindLocal, State.bindCell]
  obtain ⟨after, execution, counted, written, _, _⟩ := ByteIoReadProof.ReadStep.copy input 8
    (CountedLocal.start formed (reader.bindingId 1) 1) formed
    (FreshCellFrame.bindLocal _ (reader.bindingId 5) (.signed .i32 6)) (by rfl) (by rfl) (by rfl)
    (by decide) (by decide)
  exact ⟨after, execution, counted.counter, by
    have absent : after.cellId? (reader.bindingId 6) = none := by
      simpa only [State.cellId?, execution.choose_spec.2] using
        (show (prepared 1 6).cellId? (reader.bindingId 6) = none from rfl)
    simp only [State.local?, absent, Option.bind_none],
    written.loadBytes_disjoint (by rfl) (Or.inr (by decide))⟩

#print axioms commitsChunk

private def fileCaller : State := {
  caller with world := {
    files := [{ path := [1], bytes := packed.take 6 }]
    fileHandles := [{ id := 3, path := [1], readable := true }] } }
private def readReady : State :=
  fileCaller
    |>.bindLocal (reader.bindingId 1) (.signed .i32 1)
    |>.bindLocal (reader.argumentId 0) (.signed .i32 3)
    |>.bindLocal (reader.bindingId 0) (.pointer 4)
    |>.bindLocal (reader.bindingId 4) (.unsigned .usize 8)
private def readInput : ByteIoReadProof.ReadStep.Input readReady := {
  address := 4, words := 2, destination := 16, capacity := 8, total := 1, handle := 3, request := 8
  capacityFits := by decide, totalBound := by decide, requestFits := by decide, requestRoom := by decide
  separate := by decide, inputRoom := Heap.Readable.of_loadBytes rfl, outputRoom := Heap.Readable.of_loadBytes rfl
  noViews := rfl, packed := rfl, output := rfl, cursor := rfl
  handleFound := rfl, pointerFound := rfl, sizeFound := rfl, requestFound := rfl, remainingFound := rfl
  formed := by simp [State.CellsWellFormed, readReady, fileCaller, caller, State.bindLocal, State.bindCell]
  unique := by simp [HeapBlockBasesUnique, readReady, fileCaller, caller, State.bindLocal, State.bindCell] }

-- This proof starts before the actual host read, not with an assumed count or
-- preloaded chunk. The file model supplies the six bytes and advances its cursor.
theorem readsAndCommits : ∃ after,
    RunsStmt extractedProgram readReady (reader.bindingStatement 5) .next after ∧
    (restoreLocals (fileCaller.bindLocal (reader.bindingId 1) (.signed .i32 1)) after).local? (reader.bindingId 1) =
      some (.signed .i32 7) ∧ after.local? (reader.bindingId 5) = none ∧
    after.heap.loadBytes 20 24 = .ok ((packed.take 6).flatMap encodeByte) ∧
    after.heap.loadBytes 4 6 = .ok (packed.take 6) ∧
    after.world.handle? 3 = some { id := 3, path := [1], readable := true, offset := 6 } := by
  have formed : fileCaller.CellsWellFormed := by
    simp [State.CellsWellFormed, fileCaller, caller, State.bindLocal, State.bindCell]
  have setup : FreshCellFrame (fileCaller.bindLocal (reader.bindingId 1) (.signed .i32 1)) readReady :=
    ((FreshCellFrame.bindLocal _ (reader.argumentId 0) (.signed .i32 3)).trans
      (FreshCellFrame.bindLocal _ (reader.bindingId 0) (.pointer 4))).trans
        (FreshCellFrame.bindLocal _ (reader.bindingId 4) (.unsigned .usize 8))
  obtain ⟨completion, after, execution, value, heap, world, read, worldEq, _, outcome⟩ :=
    ByteIoReadProof.ReadStep.run readInput (CountedLocal.start formed (reader.bindingId 1) 1)
      formed setup rfl
  have reading : World.readFileBytes (World.record readReady.world .read) readInput.handle readInput.request =
      some (packed.take 6, { World.record fileCaller.world .read with
        fileHandles := [{ id := 3, path := [1], readable := true, offset := 6 }] }) := rfl
  have nonempty : packed.take 6 ≠ [] := by decide
  simp only [ByteIoReadProof.ReadStep.Input.specification, reading, if_neg nonempty] at outcome
  refine ⟨after, outcome.1 ▸ execution, outcome.2.1.counter, ?_, outcome.2.2.loadBytes, ?_, ?_⟩
  · have absent : after.cellId? (reader.bindingId 5) = none := by
      simpa only [State.cellId?, execution.choose_spec.2] using
        (show readReady.cellId? (reader.bindingId 5) = none from rfl)
    simp only [State.local?, absent, Option.bind_none]
  · exact outcome.2.2.loadBytes_disjoint (read.success reading (by decide)).2.2.2.loadBytes
      (Or.inr (by decide))
  · exact congrArg (fun w : World.State => w.handle? 3)
      (worldEq.trans (read.success reading (by decide)).2.1)

#print axioms readsAndCommits

private def checkRead (total length offset : Nat) (handle : Int) (readable present : Bool) : IO Unit := do
  let fileBytes : List UInt8 := [0, 127, 128, 255, 255, 1, 128, 255, 42, 9]
  let fileBytes := fileBytes.take length
  let request := min 8 (9 - total)
  let before := { caller with world := {
      files := if present then [{ path := [1], bytes := fileBytes }] else []
      fileHandles := [{ id := 3, path := [1], readable, offset }] } }
    |>.bindLocal (reader.bindingId 1) (.signed .i32 total)
    |>.bindLocal (reader.argumentId 0) (.signed .i32 handle)
    |>.bindLocal (reader.bindingId 0) (.pointer 4)
    |>.bindLocal (reader.bindingId 2) (.signed .i32 request)
    |>.bindLocal (reader.bindingId 3) (.signed .i32 (8 - total : Nat))
    |>.bindLocal (reader.bindingId 4) (.unsigned .usize request)
  let valid := handle == 3 && readable && present
  let delivered := if valid then (fileBytes.drop offset).take request else []
  let copies := valid && !delivered.isEmpty && total + delivered.length ≤ 8
  let expected : Option Int := if !valid then some (-1)
    else if delivered.isEmpty then some total else if !copies then some (-2) else none
  match execStmt 100 extractedProgram before (reader.bindingStatement 5) with
  | .done completion after =>
      let completed : Bool := match completion, expected with
        | .next, none => true
        | .returned (some (.signed .i32 value)), some expected => value == expected
        | _, _ => false
      let output := List.flatten ((List.range 8).map fun slot => i32Bytes
        (if copies && total ≤ slot && slot < total + delivered.length then
          (delivered[slot - total]!).toNat else 11))
      let source := delivered ++ packed.drop delivered.length
      let expectedTotal := if copies then total + delivered.length else total
      let correct : Bool := match after.heap.loadBytes 16 32, after.heap.loadBytes 4 8,
          after.local? (reader.bindingId 1), after.local? (reader.bindingId 5),
          after.local? (reader.bindingId 6), after.world.handle? 3 with
        | .ok actual, .ok scratch, some (.signed .i32 cursor), none, none, some file =>
            completed && actual == output && scratch == source && cursor == expectedTotal &&
              file.offset == offset + delivered.length && after.world.calls == [.read] && after.locals == before.locals
        | _, _, _, _, _, _ => false
      unless correct do throw (IO.userError s!"read/count contract failed: total={total}, length={length}, offset={offset}, handle={handle}, readable={readable}, present={present}")
  | _ => throw (IO.userError "read/count declaration did not complete")

-- Model-based coverage includes partial reads and EOF past the file end. Error
-- and overflow reads must still record the host call/cursor but never copy.
#eval (do
  for total in List.range 9 do
    for length in List.range 11 do
      for offset in List.range 3 do checkRead total length offset 3 true true
    checkRead total 10 0 9 true true
    checkRead total 10 0 3 false true
    checkRead total 10 0 3 true false : IO Unit)

-- Every bounded count/cursor pair, including zero iterations and full output,
-- now executes the complete actual scoped chunk, not just its while loop.
#eval (do
  for total in List.range 9 do
    for count in List.range (9 - total) do
      let base := prepared total count
      match execStmt 100 extractedProgram base (reader.bindingStatement 6) with
      | .done .next after =>
          let expected := List.flatten ((List.range 8).map fun slot =>
            i32Bytes (if total ≤ slot && slot < total + count then (packed[slot - total]!).toNat else 11))
          let correct := match after.heap.loadBytes 16 32, after.heap.loadBytes 4 8,
              after.local? (reader.bindingId 1), after.local? (reader.bindingId 6) with
            | .ok actual, .ok bytes, some (.signed .i32 cursor), none =>
                actual == expected && bytes == packed && cursor == (total + count : Nat)
            | _, _, _, _ => false
          unless correct do throw (IO.userError "copy loop changed its prefix, source bytes or terminal counter")
      | _ => throw (IO.userError "bounded copy loop did not terminate normally") : IO Unit)

-- Invalid counts precede EOF; EOF precedes capacity overflow. None of these
-- returning branches may copy a byte or update the total.
#eval (do
  for (count, request, remaining, result) in
      ([(-7, 8, 7, -1), (-1, 8, 7, -1), (9, 8, 7, -1), (0, -2, 7, -1),
        (0, 0, 0, 1), (0, 8, -1, 1), (1, 8, 0, -2), (8, 8, 7, -2)] : List (Int × Int × Int × Int)) do
    let before := prepared 1 0
      |>.bindLocal (reader.bindingId 5) (.signed .i32 count)
      |>.bindLocal (reader.bindingId 2) (.signed .i32 request)
      |>.bindLocal (reader.bindingId 3) (.signed .i32 remaining)
    match execStmt 100 extractedProgram before ByteIoReadProof.ReadStep.continuation with
    | .done (.returned (some (.signed .i32 actual))) after =>
        let unchanged := match after.heap.loadBytes 4 8, after.heap.loadBytes 16 32,
            after.local? (reader.bindingId 1) with
          | .ok bytes, .ok output, some (.signed .i32 total) =>
              bytes == packed && output == List.flatten (List.replicate 8 (i32Bytes 11)) && total == 1
          | _, _, _ => false
        unless actual == result && unchanged do
          throw (IO.userError "read count rejection changed output, source or total")
    | _ => throw (IO.userError "read count guard did not return its specified result") : IO Unit)

end ByteIoReadLoopTests
