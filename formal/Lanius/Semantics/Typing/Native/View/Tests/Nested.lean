import Lanius.Semantics.HostCall

namespace Lanius.Semantics.ViewTests.Nested

open Lanius Lanius.Core Lanius.Typing Lanius.Memory

private def i32 : Ty := .scalar (.signed .i32)
private def declaration : StructDecl := { id := 50, fields := [.array (.array i32 2) 2, .scalar .bool] }
private def reader : Function := {
  id := 43, parameters := [(0, .scalar (.signed .i32)), (1, .scalar .rawPtr), (2, .scalar (.unsigned .usize))]
  returnType := i32, body := none, external := some (.host .read) }
private def program : Program := { functions := [reader], structures := [declaration] }
private def row : Value := .array [.signed .i32 0, .signed .i32 0]
private def root : Value := .structure 50 [.array [row, row], .boolean true]
private def view (index : Nat) : I32ArrayView := {
  address := 4 + index * 8, root := 0, projections := [.field 0, .index index], length := 2 }
private def state (bytes : List UInt8) : State := {
  locals := [(7, 0), (8, 0)], cells := [{ id := 0, value := some root }], nextCell := 1
  heap := ({} : Heap).borrowedI32 bytes, i32ArrayViews := [view 0, view 1] }
private def types : CellTypes := fun cell => if cell = 0 then some (.structure 50) else none

private theorem readable (length : bytes.length = 16) : (state bytes).heap.Readable 4 16 := by
  have loaded := Heap.borrowedI32_loadBytes (heap := ({} : Heap))
    (by intro block member; cases member) bytes bytes.length
  simp only [List.take_length] at loaded
  rw [length] at loaded
  exact Heap.Readable.of_loadBytes loaded

private theorem accessible (length : bytes.length = 16) : (state bytes).I32ViewsAccessible program types := by
  refine ⟨?_, by simp [HeapBlockBasesUnique, state, Heap.borrowedI32], ?_⟩
  · intro cell type declared
    by_cases same : cell = 0
    · subst cell
      have sameType : type = .structure 50 := Option.some.inj declared.symm
      subst type
      have zero : ValueHasType program (.signed .i32 0) i32 := .signed .i32 0 (by decide) (by decide)
      have rowTyped : ValueHasType program row (.array i32 2) := .array _ _ rfl (.cons zero (.cons zero .nil))
      exact ⟨some root, rfl, .structure declaration rfl
        (.cons (.array _ _ rfl (.cons rowTyped (.cons rowTyped .nil))) (.cons (.boolean true) .nil))⟩
    · simp only [types, if_neg same] at declared; cases declared
  · intro other member
    simp only [state, List.mem_cons, List.not_mem_nil, or_false] at member
    rcases member with rfl | rfl
    · exact ⟨⟨.structure 50, rfl, .field declaration rfl rfl (.index (by decide) .root),
        by simp [State.cell?, State.cellEntry?, state, view]⟩,
        by simpa [view] using (readable length).subrange (start := 0) (length := 8) (by decide)⟩
    · exact ⟨⟨.structure 50, rfl, .field declaration rfl rfl (.index (by decide) .root),
        by simp [State.cell?, State.cellEntry?, state, view]⟩,
        by simpa [view] using (readable length).subrange (start := 8) (length := 8) (by decide)⟩

private theorem unique (bytes : List UInt8) : (state bytes).I32ViewsUnique := by
  simp [State.I32ViewsUnique, state, view]

private theorem ready (length : bytes.length = 16) : (state bytes).I32ViewsReady program types := by
  refine ⟨accessible length, ?_, unique bytes⟩
  intro block member
  simp only [state, Heap.borrowedI32, List.nil_append, List.mem_singleton] at member
  subst block
  simp [state, Heap.borrowedI32]

private def firstOnly (bytes : List UInt8) : State := { state bytes with i32ArrayViews := [view 0] }

private theorem firstReady (length : bytes.length = 16) : (firstOnly bytes).I32ViewsReady program types :=
  ⟨⟨(accessible length).store, (accessible length).unique, fun other member =>
    (accessible length).views other (by
      simp only [firstOnly, List.mem_singleton] at member; subst other; simp [state])⟩,
    (ready length).below, by simp [State.I32ViewsUnique, firstOnly]⟩

-- Arbitrary host bytes, two independent targets inside one shared aggregate,
-- and two local aliases. The old cell values need not match the native bytes.
theorem refresh (length : bytes.length = 16) : ∃ cells,
    syncI32ViewsFromHeap (state bytes) = .ok { state bytes with cells } ∧
    ({ state bytes with cells } : State).I32ViewsCoherent program types :=
  (accessible length).refreshCoherent (unique bytes)

-- The real modeled reader composes flush, host mutation and refresh for every
-- file environment/handle, without assuming host or synchronization success.
theorem read (length : bytes.length = 16) (world : World.State) (handle : Int) : ∃ value after,
    RunsExpr program { state bytes with world }
      (.call 43 [.value (.signed .i32 handle), .value (.pointer 4), .value (.unsigned .usize 16)]) value after ∧
    after.I32ViewsCoherent program types := by
  obtain ⟨value, after, run, _, coherent, _, _⟩ := RunsExpr.readViews (function := reader) (functionId := 43)
    (bindings := [(0, .signed .i32 handle), (1, .pointer 4), (2, .unsigned .usize 16)])
    rfl rfl rfl rfl ((accessible length).bytesWrite (world := world)
      (BytesWrite.refl (address := 4) (accessible length).unique)) (readable length)
  exact ⟨value, after, run, coherent (unique bytes)⟩

-- This is the actual intrinsic/calling convention used by byte_io.read_file.
-- A nested one-word sub-slice, including its nonzero offset, supplies the range.
theorem readCellSlice (length : bytes.length = 16) (handle : Int) (bound : count ≤ 4) : ∃ value after,
    RunsExpr program (state bytes) (.call 43 [.value (.signed .i32 handle),
      .i32SliceDataPtr (.value (.slice i32 0 [.field 0, .index 1] 1 1)), .value (.unsigned .usize count)]) value after ∧
    after.I32ViewsReady program types ∧ after.I32ViewsCoherent program types ∧
    PointerReadEffect program (state bytes)
      (.i32SliceDataPtr (.value (.slice i32 0 [.field 0, .index 1] 1 1))) handle count value after :=
  RunsExpr.readSlice (function := reader) (functionId := 43)
    (bindings := fun pointer => [(0, .signed .i32 handle), (1, .pointer pointer), (2, .unsigned .usize count)])
    rfl rfl rfl (fun _ => rfl) (.ofStable .value rfl)
    (.cell (.slice ((accessible length).views (view 1) (by simp [state])).1 (by decide))) (ready length) bound

-- The same slice-pointer/read expression also derives its destination when
-- the second nested array has never had a native registration.
theorem readFreshCellSlice (length : bytes.length = 16) (handle : Int) (bound : count ≤ 4) : ∃ value after,
    RunsExpr program (firstOnly bytes) (.call 43 [.value (.signed .i32 handle),
      .i32SliceDataPtr (.value (.slice i32 0 [.field 0, .index 1] 1 1)), .value (.unsigned .usize count)]) value after ∧
    after.I32ViewsReady program types ∧ after.I32ViewsCoherent program types ∧
    PointerReadEffect program (firstOnly bytes)
      (.i32SliceDataPtr (.value (.slice i32 0 [.field 0, .index 1] 1 1))) handle count value after :=
  RunsExpr.readSlice (function := reader) (functionId := 43)
    (bindings := fun pointer => [(0, .signed .i32 handle), (1, .pointer pointer), (2, .unsigned .usize count)])
    rfl rfl rfl (fun _ => rfl) (.ofStable .value rfl)
    (.cell (.slice (show CellTargetValid program types (firstOnly bytes) 0 [.field 0, .index 1] (.array i32 2) from
      ((accessible length).views (view 1) (by simp [state])).1) (by decide))) (firstReady length) bound

-- Raw descriptors follow the extractor's allocated scratch-buffer route.
-- The shared host proof covers every file world, not only successful reads.
theorem readRawSlice (length : bytes.length = 16) (world : World.State) (handle : Int) (bound : count ≤ 16) : ∃ value after,
    RunsExpr program { state bytes with world } (.call 43 [.value (.signed .i32 handle),
      .i32SliceDataPtr (.value (.rawSlice i32 4 4)), .value (.unsigned .usize count)]) value after ∧
    after.I32ViewsReady program types ∧ after.I32ViewsCoherent program types ∧
    PointerReadEffect program { state bytes with world }
      (.i32SliceDataPtr (.value (.rawSlice i32 4 4))) handle count value after :=
  RunsExpr.readSlice (function := reader) (functionId := 43)
    (bindings := fun pointer => [(0, .signed .i32 handle), (1, .pointer pointer), (2, .unsigned .usize count)])
    rfl rfl rfl (fun _ => rfl) (.ofStable .value rfl) (.raw (readable length))
    ⟨((ready length).toI32ViewsAccessible.bytesWrite (world := world)
      (BytesWrite.refl (address := 4) (ready length).unique)), (ready length).below, (ready length).keys⟩ bound

-- First exposure of the second nested array: its sibling's registration and
-- all aliased cell contents remain intact, with a distinct fresh byte range.
theorem mapSecond (length : bytes.length = 16) : ∃ after,
    mapI32ArrayView { state bytes with i32ArrayViews := [view 0] } 0 [.field 0, .index 1]
      [.signed .i32 0, .signed .i32 0] = .done (.pointer 20) after ∧
    after.I32ViewsReady program types ∧ after.heap.Readable 20 8 ∧ after.cells = (state bytes).cells := by
  let before := firstOnly bytes
  have access : before.I32ViewsAccessible program types := (firstReady length).toI32ViewsAccessible
  obtain ⟨data, mapped, finalAccess, readable, below, _, unique⟩ := CellTargetValid.mapFresh (state := before)
    (show CellTargetValid program types before 0 [.field 0, .index 1] (.array i32 2) from
      ((accessible length).views (view 1) (by simp [state])).1) rfl access (ready length).below rfl
  have address : (state bytes).heap.borrowedAddress = 20 := by simp [state, Heap.borrowedI32, length, Heap.borrowedAddress, alignUp]
  refine ⟨_, ?_, ⟨finalAccess, below, unique (firstReady length).keys⟩, ?_, rfl⟩
  · simpa only [before, firstOnly, address] using mapped
  · simpa only [before, firstOnly, address] using readable

#print axioms refresh
#print axioms read
#print axioms readCellSlice
#print axioms readFreshCellSlice
#print axioms readRawSlice
#print axioms mapSecond

end Lanius.Semantics.ViewTests.Nested
