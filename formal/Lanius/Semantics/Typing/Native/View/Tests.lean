import Lanius.Semantics.HostCall

namespace Lanius.Semantics.ViewTests

open Lanius Lanius.Core Lanius.Typing Lanius.Memory

private def writer : Function := {
  id := 42
  parameters := [(0, .scalar .rawPtr), (1, .scalar (.unsigned .usize))]
  returnType := .scalar (.signed .i32)
  body := none
  external := some (.host .writeStdout) }
private def reader : Function := {
  id := 43
  parameters := [(0, .scalar (.signed .i32)), (1, .scalar .rawPtr), (2, .scalar (.unsigned .usize))]
  returnType := .scalar (.signed .i32)
  body := none
  external := some (.host .read) }
private def program : Program := { functions := [writer, reader] }
private def i32 : Ty := .scalar (.signed .i32)
private def array (first second : BitVec 32) : Value := .array [.signed .i32 first.toInt, .signed .i32 second.toInt]
private def view : I32ArrayView := { address := 4, root := 0, projections := [], length := 2 }
private def emptyView : I32ArrayView := { address := 999, root := 1, projections := [], length := 0 }
private def types : CellTypes := fun cell =>
  if cell = 0 then some (.array i32 2) else if cell = 1 then some (.array i32 0) else none
private def state (first second : BitVec 32) : State := {
  locals := [(7, 0), (8, 0)], cells := [{ id := 0, value := some (array first second) },
    { id := 1, value := some (.array []) }], nextCell := 2,
  heap := {
    blocks := [
      { base := 4, size := 8, alignment := 4, owned := false, bytes := [11, 22, 33, 44, 55, 66, 77, 88] },
      { base := 16, size := 1, alignment := 1, bytes := [99] }]
    nextAddress := 17 }
  i32ArrayViews := [view, emptyView] }

private theorem wordTyped (word : BitVec 32) : ValueHasType program (.signed .i32 word.toInt) i32 :=
  .signed .i32 word.toInt (BitVec.le_toInt word) BitVec.toInt_le

private theorem accessible (first second : BitVec 32) : (state first second).I32ViewsAccessible program types := by
  refine ⟨?_, by simp [HeapBlockBasesUnique, state], ?_⟩
  · intro cell type declared
    simp only [types] at declared
    split at declared
    · next same =>
        subst cell; cases declared
        exact ⟨some (array first second), rfl, .array _ _ rfl (.cons (wordTyped first) (.cons (wordTyped second) .nil))⟩
    · split at declared
      · next same => subst cell; cases declared; exact ⟨some (.array []), rfl, .array _ _ rfl .nil⟩
      · cases declared
  · intro registered member
    simp only [state, List.mem_cons, List.not_mem_nil, or_false] at member
    rcases member with rfl | rfl
    · exact ⟨⟨.array i32 2, rfl, .root, by simp [State.cell?, State.cellEntry?, state, view]⟩,
        Heap.Readable.of_loadBytes (by rfl)⟩
    · exact ⟨⟨.array i32 0, rfl, .root, by simp [State.cell?, State.cellEntry?, state, emptyView]⟩,
        by intro index bound; simp [emptyView] at bound⟩

-- Arbitrary signed words, aliases, an empty view, and unrelated allocation.
-- No internal encoding/store/synchronization success is an input premise.
theorem flush (first second : BitVec 32) : ∃ heap,
    syncI32ViewsToHeap (state first second) = .ok { state first second with heap } ∧
    ({ state first second with heap } : State).I32ViewsAccessible program types ∧
    heap.Readable 16 1 := by
  obtain ⟨heap, run, valid, retained, _⟩ := (accessible first second).flush
  exact ⟨heap, run, valid, retained 16 1 (Heap.Readable.of_loadBytes (by rfl))⟩

theorem reborrow (first second : BitVec 32) : ∃ heap,
    RunsExpr program (state first second) (.i32ArrayDataPtr (.local 8)) (.pointer 4)
      { state first second with heap } ∧
    ({ state first second with heap } : State).I32ViewsAccessible program types := by
  obtain ⟨heap, flushed, access, _, _⟩ := (accessible first second).flush
  refine ⟨heap, RunsExpr.ofEval (fuel := 2) ?_, access⟩
  rw [evalExpr.eq_def]
  simp only [expressionPlace?, array, evalPlace_local_of_local? 0 program (state first second) .read 8 0
    (array first second) rfl rfl, mapI32ArrayView,
    show (state first second).i32ArrayView? 0 [] = some view from rfl, flushed]
  rfl

theorem refresh (first second : BitVec 32) : ∃ cells,
    syncI32ViewsFromHeap (state first second) = .ok { state first second with cells } ∧
    ({ state first second with cells } : State).I32ViewsAccessible program types ∧
    ((state first second).I32ViewsUnique →
      ({ state first second with cells } : State).I32ViewsCoherent program types) :=
  (accessible first second).refresh

private theorem disjoint (first second : BitVec 32) :
    (state first second).i32ArrayViews.Pairwise I32ArrayView.Disjoint := by
  simp [state, view, emptyView, I32ArrayView.Disjoint]

private theorem unique (first second : BitVec 32) : ((state first second).cells.map Cell.id).Nodup := by
  simp [state]

theorem flushThenRefresh (first second : BitVec 32) : ∃ heap,
    syncI32ViewsToHeap (state first second) = .ok { state first second with heap } ∧
    syncI32ViewsFromHeap { state first second with heap } = .ok { state first second with heap } ∧
    ({ state first second with heap } : State).I32ViewsCoherent program types := by
  obtain ⟨heap, flushed, coherent, _, _⟩ := (accessible first second).flushCoherent (disjoint first second)
  exact ⟨heap, flushed, coherent.refresh (unique first second), coherent⟩

theorem stdoutPreservesCells (first second : BitVec 32) : ∃ bytes heap world,
    RunsExpr program (state first second) (.call 42 [.value (.pointer 4), .value (.unsigned .usize 8)])
      (World.i32Result (8 : Nat)) { state first second with heap, world } ∧
    ({ state first second with heap } : State).I32ViewsCoherent program types ∧
    heap.loadBytes 4 8 = .ok bytes ∧ bytes.length = 8 ∧
    world = { World.record (state first second).world .writeStdout with
      standardOutput := (state first second).world.standardOutput ++ bytes } :=
  RunsExpr.writeStdoutFramed
    (function := writer) (functionId := 42) (bindings := [(0, .pointer 4), (1, .unsigned .usize 8)])
    rfl rfl rfl rfl (accessible first second) (Heap.Readable.of_loadBytes (by rfl))
    (disjoint first second) (unique first second)

-- The contract's coherence fixes the exact bytes, for arbitrary signed words.
example (first second : BitVec 32) (heap : Heap)
    (coherent : ({ state first second with heap } : State).I32ViewsCoherent program types) :
    heap.loadBytes 4 8 = .ok (i32Bytes first.toInt ++ i32Bytes second.toInt) :=
  (coherent.bytes view (by simp [state])).loadBytes (elements := [.signed .i32 first.toInt, .signed .i32 second.toInt])
    (by rfl) (by simp only [encodeI32Array, List.append_nil])

-- A full word with an out-of-range mathematical value is intentionally
-- truncated by encoding. The original-array roundtrip requires actual typing.
example : decodeI32 (i32Bytes 2147483648) = -2147483648 := by
  simp [i32Bytes, List.range_succ, decodeI32]

-- The structural identity law works through a field then an array element.
example (first second : BitVec 32) : replaceProjectedValue
    (.structure 3 [array first second, .boolean true]) [.field 0, .index 1] (.signed .i32 second.toInt) =
    .ok (.structure 3 [array first second, .boolean true]) :=
  replaceProjectedValue_read_same (by rfl)

-- The zero-length array has no view in this fixture. Its first exposure still
-- reserves a fresh address and keeps the nonempty array's existing view usable.
theorem exposeEmpty (first second : BitVec 32) : ∃ after,
    RunsExpr program { state first second with locals := [(9, 1)], i32ArrayViews := [view] }
      (.i32ArrayDataPtr (.local 9)) (.pointer 20) after ∧
    after.I32ViewsAccessible program types ∧ HeapBlocksBelowNext after.heap := by
  have access : ({ state first second with locals := [(9, 1)], i32ArrayViews := [view] } : State).I32ViewsAccessible
      program types := ⟨(accessible first second).store, (accessible first second).unique,
        fun other member => (accessible first second).views other (by
          simp only [state, List.mem_cons, List.not_mem_nil, or_false]
          exact Or.inl (List.mem_singleton.mp member))⟩
  have address : (state first second).heap.borrowedAddress = 20 := by simp [state, Heap.borrowedAddress, alignUp]
  obtain ⟨bytes, mapped, valid, _, below, _, _⟩ := CellTargetValid.mapFresh (cell := 1) (path := []) (count := 0)
    ⟨.array i32 0, rfl, .root, by simp [State.cell?, State.cellEntry?, state]⟩ rfl access
    (by intro block member; simp [state] at member ⊢; rcases member with rfl | rfl <;> decide) rfl
  refine ⟨_, RunsExpr.ofEval (fuel := 2) ?_, valid, below⟩
  rw [evalExpr.eq_def]
  simpa only [address, expressionPlace?, evalPlace_local_of_local? 0 program
    { state first second with locals := [(9, 1)], i32ArrayViews := [view] } .read 9 1 (.array []) rfl rfl] using mapped

theorem stdout (first second : BitVec 32) : ∃ bytes after,
    RunsExpr program (state first second) (.call 42 [.value (.pointer 4), .value (.unsigned .usize 8)])
      (World.i32Result 8) after ∧ after.I32ViewsAccessible program types ∧
      bytes.length = 8 ∧ after.world.standardOutput = bytes := by
  simpa only [Int.cast_ofNat_Int, World.State.standardOutput, state, List.nil_append] using
    RunsExpr.writeStdoutViews (function := writer) (bindings := [(0, .pointer 4), (1, .unsigned .usize 8)])
      rfl rfl rfl rfl (accessible first second) (Heap.Readable.of_loadBytes (by rfl))

-- Any file contents/handles are allowed. Readability, not assumed host success,
-- prevents storage traps; invalid handles produce the specified error value.
theorem read (first second : BitVec 32) (world : World.State) (handle : Int) : ∃ value after,
    RunsExpr program { state first second with world }
      (.call 43 [.value (.signed .i32 handle), .value (.pointer 4), .value (.unsigned .usize 8)])
      value after ∧ after.I32ViewsAccessible program types ∧
      ((state first second).I32ViewsUnique → after.I32ViewsCoherent program types) ∧
      (({ state first second with world } : State).I32ViewsReady program types → after.I32ViewsReady program types) ∧
      ReadEffect { state first second with world } handle 4 8 value after :=
  RunsExpr.readViews (function := reader)
    (bindings := [(0, .signed .i32 handle), (1, .pointer 4), (2, .unsigned .usize 8)])
    rfl rfl rfl rfl ((accessible first second).bytesWrite (world := world)
      (BytesWrite.refl (address := 4) (accessible first second).unique)) (Heap.Readable.of_loadBytes (by rfl))

private def expected (first second : BitVec 32) : State := { state first second with
  heap := { (state first second).heap with blocks := [
    { base := 4, size := 8, alignment := 4, owned := false, bytes := i32Bytes first.toInt ++ i32Bytes second.toInt },
    { base := 16, size := 1, alignment := 1, bytes := [99] }] } }

-- Check real bytes, not just termination or a framed existential. Old native
-- data is deliberately different, and the empty view never touches address 999.
example : syncI32ViewsToHeap (state 37 (-7)) = .ok (expected 37 (-7)) := rfl
example (first second : BitVec 32) :
    (expected first second).heap.loadBytes 4 8 = .ok (i32Bytes first.toInt ++ i32Bytes second.toInt) ∧
    (expected first second).heap.loadByte 16 0 = .ok 99 := ⟨rfl, rfl⟩

-- Host writes change the shared cell, hence both aliases, without changing
-- locals, heap, the allocation frontier or the view registry.
private def hostWritten : State := { state 0 0 with heap := (expected 37 (-7)).heap }
private def refreshed : State := { hostWritten with cells := (state 37 (-7)).cells }
example : syncI32ViewsFromHeap hostWritten = .ok refreshed := by
  have decoded : decodeI32Array 2 (i32Bytes 37 ++ i32Bytes (-7)) =
      .ok [.signed .i32 37, .signed .i32 (-7)] := by
    simp [decodeI32Array, decodeI32, i32Bytes, List.range_succ]
  simp only [syncI32ViewsFromHeap, syncI32ViewsFromHeapFrom, hostWritten, state, view, emptyView,
    show (expected 37 (-7)).heap.loadBytes 4 8 = .ok (i32Bytes 37 ++ i32Bytes (-7)) from rfl,
    decoded]
  rfl
example : refreshed.local? 7 = some (array 37 (-7)) ∧
    refreshed.local? 8 = some (array 37 (-7)) ∧
    refreshed.heap = hostWritten.heap := ⟨rfl, rfl, rfl⟩

example : decodeI32Array 2 [0, 0, 0, 128, 255, 255, 255, 127] =
    .ok [.signed .i32 (-2147483648), .signed .i32 2147483647] := by
  simp [decodeI32Array, decodeI32]
example : decodeI32Array 1 [0, 0, 0] = .error .rawMemoryBounds := rfl
example : decodeI32Array 0 [0] = .error .rawMemoryBounds := rfl

-- Duplicate cell identities make a no-op projected write change the second
-- physical cell. The exact-state refresh law therefore requires uniqueness.
example : writeResolvedPlace
    { cells := [{ id := 0, value := some (.array []) }, { id := 0, value := some (.boolean true) }] }
    { root := 0, projections := [], value := none } (.array []) =
    .ok { cells := [{ id := 0, value := some (.array []) }, { id := 0, value := some (.array []) }] } := rfl

-- Readable but overlapping registrations can encode different arrays into
-- the same bytes. Accessibility alone cannot supply the coherence premise.
example : ¬ ({ view with root := 1 }).Disjoint view := by simp [I32ArrayView.Disjoint, view]

private def overlapping : State := { state 0 1 with
  heap := { blocks := [{ base := 4, size := 12, alignment := 4, owned := false, bytes := List.replicate 12 0 }], nextAddress := 16 }
  i32ArrayViews := [view, { view with address := 8 }] }
private def overlapAfter : State := { overlapping with heap := { overlapping.heap with
  blocks := [{ base := 4, size := 12, alignment := 4, owned := false, bytes := [0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0] }] } }

example : overlapping.I32ViewsAccessible program types := by
  refine ⟨(accessible 0 1).store, by simp [HeapBlockBasesUnique, overlapping], ?_⟩
  intro other member
  simp only [overlapping, List.mem_cons, List.not_mem_nil, or_false] at member
  rcases member with rfl | rfl
  all_goals exact ⟨((accessible 0 1).views view (by simp [state])).1, Heap.Readable.of_loadBytes (by rfl)⟩
example : syncI32ViewsToHeap overlapping = .ok overlapAfter := rfl
example : ¬ view.Coherent overlapAfter := by
  rintro ⟨elements, bytes, read, encoded, loaded⟩
  have same : elements = [.signed .i32 0, .signed .i32 1] := Value.array.inj (Except.ok.inj read.symm)
  subst elements
  have same : bytes = [0, 0, 0, 0, 1, 0, 0, 0] := Except.ok.inj encoded.symm
  subst bytes
  have actual : overlapAfter.heap.loadBytes 4 8 = .ok [0, 0, 0, 0, 0, 0, 0, 0] := rfl
  change overlapAfter.heap.loadBytes 4 8 = .ok [0, 0, 0, 0, 1, 0, 0, 0] at loaded
  rw [actual] at loaded
  have different : ([0, 0, 0, 0, 0, 0, 0, 0] : List UInt8) ≠ [0, 0, 0, 0, 1, 0, 0, 0] := by decide
  exact different (Except.ok.inj loaded)

-- Duplicate root/path registrations are independently ruled out by the
-- mapper invariant, even when their readable native ranges differ.
example : ¬ overlapping.I32ViewsUnique := by simp [State.I32ViewsUnique, overlapping, view]
example : syncI32ViewsFromHeap overlapAfter = .ok overlapAfter := by
  have decoded0 : decodeI32Array 2 [0, 0, 0, 0, 0, 0, 0, 0] = .ok [.signed .i32 0, .signed .i32 0] := by
    simp [decodeI32Array, decodeI32]
  have decoded1 : decodeI32Array 2 [0, 0, 0, 0, 1, 0, 0, 0] = .ok [.signed .i32 0, .signed .i32 1] := by
    simp [decodeI32Array, decodeI32]
  let middle : State := { overlapAfter with cells := (state 0 0).cells }
  have firstLoad : overlapAfter.heap.loadBytes 4 8 = .ok [0, 0, 0, 0, 0, 0, 0, 0] := rfl
  have firstWrite : writeResolvedPlace overlapAfter { root := 0, projections := [], value := none }
      (.array [.signed .i32 0, .signed .i32 0]) = .ok middle := rfl
  have lastLoad : middle.heap.loadBytes 8 8 = .ok [0, 0, 0, 0, 1, 0, 0, 0] := rfl
  have lastWrite : writeResolvedPlace middle { root := 0, projections := [], value := none }
      (.array [.signed .i32 0, .signed .i32 1]) = .ok overlapAfter := rfl
  change syncI32ViewsFromHeapFrom [view, { view with address := 8 }] overlapAfter = .ok overlapAfter
  simp only [syncI32ViewsFromHeapFrom, view, Nat.reduceMul, firstLoad, decoded0, firstWrite,
    lastLoad, decoded1, lastWrite]

-- Typed cells alone do not suffice: wrong lengths and absent heap storage are
-- genuine traps. These states cannot satisfy the accessibility invariant.
private def badLength : State := { state 0 0 with i32ArrayViews := [{ view with length := 3 }] }
private def badAddress : State := { state 0 0 with i32ArrayViews := [{ view with address := 0 }] }
example : syncI32ViewsToHeap badLength = .error .typeMismatch := rfl
example : syncI32ViewsToHeap badAddress = .error .invalidPointer := rfl
example : syncI32ViewsFromHeap badAddress = .error .invalidPointer := rfl
example : ¬ badLength.I32ViewsAccessible program types := by
  intro valid
  obtain ⟨rootType, declared, path, _⟩ := (valid.views { view with length := 3 } (by simp [badLength])).1
  have same : rootType = .array i32 2 := Option.some.inj declared.symm
  subst rootType
  cases path
example : ¬ badAddress.I32ViewsAccessible program types := by
  intro valid
  have readable := (valid.views { view with address := 0 } (by simp [badAddress])).2
  obtain ⟨byte, read⟩ := readable 0 (by decide)
  have actual : badAddress.heap.loadByte 0 0 = .error .invalidPointer := rfl
  rw [actual] at read
  cases read

#print axioms flush
#print axioms refresh
#print axioms reborrow
#print axioms exposeEmpty
#print axioms stdout
#print axioms read
#print axioms flushThenRefresh
#print axioms stdoutPreservesCells

end Lanius.Semantics.ViewTests
