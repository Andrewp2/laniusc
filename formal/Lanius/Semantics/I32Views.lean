import Lanius.Memory.Store
import Lanius.Memory.Access

namespace Lanius.Semantics

open Lanius.Core Lanius.Memory

theorem encodeI32Array_exists {elements : List Value}
    (typed : ∀ element ∈ elements, ∃ value, element = .signed .i32 value) :
    ∃ bytes, encodeI32Array elements = .ok bytes := by
  induction elements with
  | nil => exact ⟨[], rfl⟩
  | cons element rest ih =>
      obtain ⟨value, rfl⟩ := typed element (by simp)
      obtain ⟨bytes, encoded⟩ := ih (fun element member => typed element (by simp [member]))
      exact ⟨i32Bytes value ++ bytes, by simp only [encodeI32Array, encoded]⟩

theorem decodeI32Array_exists {count : Nat} {bytes : List UInt8}
    (width : bytes.length = count * 4) :
    ∃ elements, decodeI32Array count bytes = .ok elements := by
  induction count generalizing bytes with
  | zero =>
      have empty : bytes = [] := List.length_eq_zero_iff.mp (by simpa using width)
      subst bytes
      exact ⟨[], rfl⟩
  | succ count ih =>
      have enough : ¬ bytes.length < 4 := by omega
      obtain ⟨rest, decoded⟩ := ih (bytes := bytes.drop 4) (by
        rw [List.length_drop, width]
        omega)
      exact ⟨.signed .i32 (decodeI32 (bytes.take 4)) :: rest,
        by simp only [decodeI32Array, if_neg enough, decoded]⟩

theorem loadI32View_exists {heap : Heap} {view : I32ArrayView}
    (wellFormed : HeapWellFormed heap)
    (valid : I32ArrayViewBlockWellFormed heap view) :
    ∃ bytes elements, heap.loadBytes view.address (view.length * 4) = .ok bytes ∧
      decodeI32Array view.length bytes = .ok elements := by
  obtain ⟨block, lookup, live, _, size, _⟩ := valid
  have base : block.base = view.address :=
    beq_iff_eq.mp (List.find?_some (p := fun block : Block => block.base == view.address) lookup)
  obtain ⟨bytes, loaded⟩ := heap.loadBytes_exists (pointer := view.address)
    (count := view.length * 4) wellFormed (List.mem_of_find?_eq_some lookup) live
    (by rw [base]; exact Nat.le_refl _) (by rw [base, size]; exact Nat.le_refl _)
  obtain ⟨elements, decoded⟩ := decodeI32Array_exists (heap.loadBytes_length loaded)
  exact ⟨bytes, elements, loaded, decoded⟩

theorem decodeI32Array_shape {count : Nat} {bytes : List UInt8} {elements : List Value}
    (decoded : decodeI32Array count bytes = .ok elements) :
    elements.length = count ∧ ∀ element ∈ elements, ∃ value, element = .signed .i32 value := by
  induction count generalizing bytes elements with
  | zero =>
      simp only [decodeI32Array] at decoded
      split at decoded
      · cases decoded; simp
      · contradiction
  | succ count ih =>
      simp only [decodeI32Array] at decoded
      split at decoded
      · contradiction
      · cases rest : decodeI32Array count (bytes.drop 4) with
        | error reason => simp [rest] at decoded
        | ok tail =>
            simp only [rest, Except.ok.injEq] at decoded
            subst elements
            obtain ⟨length, typed⟩ := ih rest
            refine ⟨by simp [length], ?_⟩
            intro element member
            rcases List.mem_cons.mp member with same | member
            · exact ⟨_, same⟩
            · exact typed element member

/-- Mapping an exact live raw block creates a root-array view and preserves
the surrounding heap validity, local bindings, and world. -/
theorem mapRawI32Slice_exists {state : State} {block : Block} {address count : Nat}
    (wellFormed : HeapWellFormed state.heap)
    (found : state.heap.block? address = some block)
    (live : block.live = true) (size : block.size = count * 4) (alignment : block.alignment = 4) :
    ∃ after, mapRawI32Slice state address count =
      .done (.slice (.scalar (.signed .i32)) state.nextCell [] 0 count) after ∧
      after.i32ArrayViews = state.i32ArrayViews ++
        [{ address, root := state.nextCell, projections := [], length := count }] ∧
      I32ArrayViewBlockWellFormed after.heap
        { address, root := state.nextCell, projections := [], length := count } ∧
      HeapWellFormed after.heap ∧ after.nextCell = state.nextCell + 1 ∧
      after.locals = state.locals ∧ after.world = state.world ∧
      Lanius.Properties.I32ArrayViewBlocksPreserved state.i32ArrayViews state.heap after.heap ∧
      after.heap.remaining = state.heap.remaining ∧
      ∃ elements, after.cells = state.cells ++ [{ id := state.nextCell, value := some (.array elements) }] ∧
        elements.length = count ∧ ∀ element ∈ elements, ∃ value, element = .signed .i32 value := by
  let heap := { state.heap with blocks := replaceBlock state.heap.blocks { block with owned := false } }
  have protection : state.heap.protectAsBorrowed address (count * 4) 4 = .ok heap := by
    simp [Heap.protectAsBorrowed, found, live, size, alignment, heap]
  have valid := Lanius.Properties.protectAsBorrowed_result_view_block_well_formed
    (root := state.nextCell) (projections := []) state.heap heap protection
  obtain ⟨bytes, elements, loaded, decoded⟩ := loadI32View_exists
    (Lanius.Properties.protectAsBorrowed_preserves_heap_well_formed wellFormed protection) valid
  have nonnegative : ¬ (count : Int) < 0 := by omega
  simp only [mapRawI32Slice, if_neg nonnegative, Int.toNat_natCast,
    protection, loaded, decoded, State.allocateTemporary]
  exact ⟨_, rfl, rfl, valid,
    Lanius.Properties.protectAsBorrowed_preserves_heap_well_formed wellFormed protection,
    rfl, rfl, rfl,
    Lanius.Properties.protectAsBorrowed_preserves_i32_array_view_blocks wellFormed protection,
    rfl, elements, rfl, decodeI32Array_shape decoded⟩

theorem mapAllocatedI32Slice_exists {state : State} {heap : Heap} {address count : Nat}
    (wellFormed : HeapWellFormed state.heap)
    (allocated : state.heap.allocate (count * 4) 4 = .allocated address heap) :
    ∃ after, mapRawI32Slice { state with heap } address count =
      .done (.slice (.scalar (.signed .i32)) state.nextCell [] 0 count) after ∧
      HeapWellFormed after.heap ∧
      after.heap.remaining = state.heap.remaining.map (fun available => available - count * 4) := by
  have found := state.heap.allocated_block wellFormed allocated
  have valid : HeapWellFormed heap := by
    simpa only [allocated, Lanius.Properties.AllocationResultWellFormed] using
      Lanius.Properties.allocate_preserves_heap_well_formed wellFormed (size := count * 4) (alignment := 4)
  obtain ⟨after, run, _, _, heapValid, _, _, _, _, remaining, _⟩ :=
    mapRawI32Slice_exists (state := { state with heap }) valid found rfl rfl rfl
  exact ⟨after, run, heapValid, remaining.trans (state.heap.allocate_remaining allocated)⟩

theorem allocateI32Slice_exists {state : State} {count : Nat}
    (wellFormed : HeapWellFormed state.heap)
    (room : ∀ available, state.heap.remaining = some available → count * 4 ≤ available) :
    ∃ address heap after,
      state.heap.allocate (count * 4) 4 = .allocated address heap ∧
      mapRawI32Slice { state with heap } address count =
        .done (.slice (.scalar (.signed .i32)) state.nextCell [] 0 count) after ∧
      HeapWellFormed after.heap ∧
      after.heap.remaining = state.heap.remaining.map (fun available => available - count * 4) := by
  obtain ⟨address, heap, allocated⟩ := state.heap.allocate_exists (alignment := 4) (by decide) room
  obtain ⟨after, mapped, valid, remaining⟩ := mapAllocatedI32Slice_exists wellFormed allocated
  exact ⟨address, heap, after, allocated, mapped, valid, remaining⟩

theorem syncI32ViewsToHeapFrom_exists {pending : List I32ArrayView} {before : State}
    (wellFormed : HeapWellFormed before.heap)
    (blocks : ∀ view ∈ pending, I32ArrayViewBlockWellFormed before.heap view)
    (arrays : ∀ view ∈ pending, ∃ elements,
      readCellProjection before view.root view.projections = .ok (.array elements) ∧
      elements.length = view.length ∧
      ∀ element ∈ elements, ∃ value, element = .signed .i32 value) :
    ∃ after, syncI32ViewsToHeapFrom pending before = .ok after := by
  induction pending generalizing before with
  | nil => exact ⟨before, rfl⟩
  | cons view rest ih =>
      obtain ⟨elements, read, length, typed⟩ := arrays view (by simp)
      obtain ⟨bytes, encoded⟩ := encodeI32Array_exists typed
      have width := Lanius.Properties.encodeI32Array_length encoded
      obtain ⟨heap, stored⟩ := before.heap.storeBytes_view_exists wellFormed
        (blocks view (by simp)) (by rw [width, length]; exact Nat.le_refl _)
      have nextWellFormed := Lanius.Properties.storeBytes_preserves_heap_well_formed wellFormed stored
      have preserved := Lanius.Properties.storeBytes_preserves_i32_array_view_blocks
        (views := rest) wellFormed stored
      obtain ⟨after, completed⟩ := ih (before := { before with heap }) nextWellFormed
        (fun next member => preserved next member (blocks next (by simp [member])))
        (fun next member => arrays next (by simp [member]))
      exact ⟨after, by simp [syncI32ViewsToHeapFrom, read, length, encoded, stored, completed]⟩

theorem syncI32ViewsToHeap_exists {before : State}
    (wellFormed : HeapWellFormed before.heap)
    (blocks : ∀ view ∈ before.i32ArrayViews, I32ArrayViewBlockWellFormed before.heap view)
    (arrays : ∀ view ∈ before.i32ArrayViews, ∃ elements,
      readCellProjection before view.root view.projections = .ok (.array elements) ∧
      elements.length = view.length ∧
      ∀ element ∈ elements, ∃ value, element = .signed .i32 value) :
    ∃ after, syncI32ViewsToHeap before = .ok after :=
  syncI32ViewsToHeapFrom_exists wellFormed blocks arrays

/-- Root-array views, as used by the extractor's borrowed buffers, can always
be refreshed when their cells and backing blocks still exist. -/
theorem syncI32RootViewsFromHeapFrom_exists {pending : List I32ArrayView} {before : State}
    (wellFormed : HeapWellFormed before.heap)
    (blocks : ∀ view ∈ pending, I32ArrayViewBlockWellFormed before.heap view)
    (roots : ∀ view ∈ pending, view.projections = [])
    (cells : ∀ view ∈ pending, ∃ cell, before.cellEntry? view.root = some cell) :
    ∃ after, syncI32ViewsFromHeapFrom pending before = .ok after := by
  induction pending generalizing before with
  | nil => exact ⟨before, rfl⟩
  | cons view rest ih =>
      obtain ⟨bytes, elements, loaded, decoded⟩ := loadI32View_exists wellFormed (blocks view (by simp))
      obtain ⟨cell, found⟩ := cells view (by simp)
      let next : State := { before with cells := replaceCell before.cells view.root (.array elements) }
      have assigned : before.assignCell view.root (.array elements) = some next := by
        simp only [State.assignCell, found, Option.isSome_some, ite_true]
        rfl
      have nextCells : ∀ other ∈ rest, ∃ cell, next.cellEntry? other.root = some cell := by
        intro other member
        by_cases same : other.root = view.root
        · exact ⟨_, by rw [same]; exact Lanius.Properties.assignCell_finds_assigned assigned⟩
        · obtain ⟨entry, lookup⟩ := cells other (by simp [member])
          exact ⟨entry, (Lanius.Properties.assignCell_preserves_other assigned same).trans lookup⟩
      obtain ⟨after, completed⟩ := ih (before := next) wellFormed
        (fun other member => blocks other (by simp [member]))
        (fun other member => roots other (by simp [member])) nextCells
      have root := roots view (by simp)
      exact ⟨after, by simp only [syncI32ViewsFromHeapFrom, loaded, decoded,
        writeResolvedPlace, root, assigned, completed]⟩

/-- Spatial separation of raw views. Structural memory safety alone does not
imply byte coherence if two different cells alias the same raw allocation. -/
def I32ViewRangesDisjoint (left right : I32ArrayView) : Prop :=
  left.address + left.length * 4 ≤ right.address ∨
    right.address + right.length * 4 ≤ left.address

/-- Exact borrowed blocks at distinct addresses cannot overlap in a
well-formed heap. This reduces the extractor's spatial registry obligation
to establishing that it does not register the same raw block twice. -/
theorem i32ViewRangesDisjoint_of_distinct_blocks
    (wellFormed : HeapWellFormed heap)
    (leftValid : I32ArrayViewBlockWellFormed heap left)
    (rightValid : I32ArrayViewBlockWellFormed heap right)
    (different : left.address ≠ right.address) : I32ViewRangesDisjoint left right := by
  obtain ⟨leftBlock, leftFound, _, _, leftSize, _⟩ := leftValid
  obtain ⟨rightBlock, rightFound, _, _, rightSize, _⟩ := rightValid
  have leftBase : leftBlock.base = left.address :=
    beq_iff_eq.mp (List.find?_some (p := fun block : Block => block.base == left.address) leftFound)
  have rightBase : rightBlock.base = right.address :=
    beq_iff_eq.mp (List.find?_some (p := fun block : Block => block.base == right.address) rightFound)
  have blocksDifferent : leftBlock ≠ rightBlock := by
    intro same
    apply different
    rw [← leftBase, ← rightBase, same]
  have separated := wellFormed.blocksDisjoint leftBlock
    (List.mem_of_find?_eq_some leftFound) rightBlock
    (List.mem_of_find?_eq_some rightFound) blocksDifferent
  simpa only [BlockIntervalsDisjoint, I32ViewRangesDisjoint, leftBase, rightBase,
    leftSize, rightSize] using separated

theorem i32Views_disjoint_of_distinct_addresses
    {views : List I32ArrayView}
    (wellFormed : HeapWellFormed heap)
    (valid : ∀ view ∈ views, I32ArrayViewBlockWellFormed heap view)
    (distinct : views.Pairwise fun left right => left.address ≠ right.address) :
    views.Pairwise I32ViewRangesDisjoint := by
  induction views with
  | nil => exact .nil
  | cons first rest induction =>
      obtain ⟨headDifferent, restDifferent⟩ := List.pairwise_cons.mp distinct
      apply List.pairwise_cons.mpr
      constructor
      · intro view member
        exact i32ViewRangesDisjoint_of_distinct_blocks wellFormed
          (valid first (by simp)) (valid view (by simp [member])) (headDifferent view member)
      · exact induction (fun view member => valid view (by simp [member])) restDifferent

theorem syncI32RootViewsFromHeapFrom_preserves_other_cell
    {pending : List I32ArrayView} {before after : State} {cell : CellId}
    (roots : ∀ view ∈ pending, view.projections = [])
    (separate : ∀ view ∈ pending, cell ≠ view.root)
    (synced : syncI32ViewsFromHeapFrom pending before = .ok after) :
    after.cellEntry? cell = before.cellEntry? cell := by
  induction pending generalizing before with
  | nil => cases synced; rfl
  | cons view rest ih =>
      have root := roots view (by simp)
      cases loaded : before.heap.loadBytes view.address (view.length * 4) with
      | error reason => simp [syncI32ViewsFromHeapFrom, loaded] at synced
      | ok bytes =>
          cases decoded : decodeI32Array view.length bytes with
          | error reason => simp [syncI32ViewsFromHeapFrom, loaded, decoded] at synced
          | ok elements =>
              cases assigned : before.assignCell view.root (.array elements) with
              | none => simp [syncI32ViewsFromHeapFrom, loaded, decoded, writeResolvedPlace, root, assigned] at synced
              | some next =>
                  have remaining : syncI32ViewsFromHeapFrom rest next = .ok after := by
                    simpa only [syncI32ViewsFromHeapFrom, loaded, decoded, writeResolvedPlace, root, assigned] using synced
                  exact (ih (fun other member => roots other (by simp [member]))
                    (fun other member => separate other (by simp [member])) remaining).trans
                    (Lanius.Properties.assignCell_preserves_other assigned (separate view (by simp)))

theorem syncI32RootViewsFromHeapFrom_preserves_locals
    {pending : List I32ArrayView} {before after : State}
    (roots : ∀ view ∈ pending, view.projections = [])
    (synced : syncI32ViewsFromHeapFrom pending before = .ok after) :
    after.locals = before.locals := by
  induction pending generalizing before with
  | nil => cases synced; rfl
  | cons view rest ih =>
      have root := roots view (by simp)
      cases loaded : before.heap.loadBytes view.address (view.length * 4) with
      | error reason => simp [syncI32ViewsFromHeapFrom, loaded] at synced
      | ok bytes =>
          cases decoded : decodeI32Array view.length bytes with
          | error reason => simp [syncI32ViewsFromHeapFrom, loaded, decoded] at synced
          | ok elements =>
              cases assigned : before.assignCell view.root (.array elements) with
              | none => simp [syncI32ViewsFromHeapFrom, loaded, decoded, writeResolvedPlace, root, assigned] at synced
              | some next =>
                  have remaining : syncI32ViewsFromHeapFrom rest next = .ok after := by
                    simpa only [syncI32ViewsFromHeapFrom, loaded, decoded, writeResolvedPlace, root, assigned] using synced
                  rw [ih (fun other member => roots other (by simp [member])) remaining,
                    Lanius.Properties.assignCell_state assigned]

/-- Refreshing distinct root cells establishes each array's declared length
and element shape; later refreshes cannot overwrite an earlier root. -/
theorem syncI32RootViewsFromHeapFrom_arrays
    {pending : List I32ArrayView} {before after : State}
    (roots : ∀ view ∈ pending, view.projections = [])
    (distinct : pending.Pairwise fun left right => left.root ≠ right.root)
    (synced : syncI32ViewsFromHeapFrom pending before = .ok after) :
    ∀ view ∈ pending, ∃ elements,
      readCellProjection after view.root view.projections = .ok (.array elements) ∧
      elements.length = view.length ∧
      ∀ element ∈ elements, ∃ value, element = .signed .i32 value := by
  induction pending generalizing before with
  | nil => simp
  | cons view rest ih =>
      have root := roots view (by simp)
      obtain ⟨headDifferent, restDifferent⟩ := List.pairwise_cons.mp distinct
      cases loaded : before.heap.loadBytes view.address (view.length * 4) with
      | error reason => simp [syncI32ViewsFromHeapFrom, loaded] at synced
      | ok bytes =>
          cases decoded : decodeI32Array view.length bytes with
          | error reason => simp [syncI32ViewsFromHeapFrom, loaded, decoded] at synced
          | ok elements =>
              cases assigned : before.assignCell view.root (.array elements) with
              | none => simp [syncI32ViewsFromHeapFrom, loaded, decoded, writeResolvedPlace, root, assigned] at synced
              | some next =>
                  have remaining : syncI32ViewsFromHeapFrom rest next = .ok after := by
                    simpa only [syncI32ViewsFromHeapFrom, loaded, decoded, writeResolvedPlace, root, assigned] using synced
                  have restRoots := fun other member => roots other (List.mem_cons_of_mem view member)
                  have tailArrays := ih restRoots restDifferent remaining
                  intro other member
                  rcases List.mem_cons.mp member with same | inRest
                  · subst other
                    have kept := syncI32RootViewsFromHeapFrom_preserves_other_cell
                      restRoots headDifferent remaining
                    have found := Lanius.Properties.assignCell_finds_assigned assigned
                    refine ⟨elements, ?_, decodeI32Array_shape decoded⟩
                    simp only [readCellProjection, kept, found, root, projectedValue]
                  · exact tailArrays other inRest

theorem syncI32ViewsToHeapFrom_cons_invert
    {view : I32ArrayView} {rest : List I32ArrayView} {before after : State}
    (synced : syncI32ViewsToHeapFrom (view :: rest) before = .ok after) :
    ∃ elements bytes heap,
      readCellProjection before view.root view.projections = .ok (.array elements) ∧
      elements.length = view.length ∧
      encodeI32Array elements = .ok bytes ∧
      before.heap.storeBytes view.address bytes = .ok heap ∧
      syncI32ViewsToHeapFrom rest { before with heap } = .ok after := by
  cases read : readCellProjection before view.root view.projections with
  | error reason => simp [syncI32ViewsToHeapFrom, read] at synced
  | ok value =>
      cases value <;> try simp [syncI32ViewsToHeapFrom, read] at synced
      rename_i elements
      by_cases lengthMatches : elements.length = view.length
      · cases encoded : encodeI32Array elements with
        | error reason => simp [lengthMatches, encoded] at synced
        | ok bytes =>
            cases stored : before.heap.storeBytes view.address bytes with
            | error reason =>
                simp [lengthMatches, encoded, stored] at synced
            | ok heap =>
                exact ⟨elements, bytes, heap, rfl, lengthMatches, encoded, stored,
                  by simpa [syncI32ViewsToHeapFrom, read, lengthMatches, encoded, stored] using synced⟩
      · simp [lengthMatches] at synced

theorem syncI32RootViewsFromHeapFrom_preserves_structure
    {pending : List I32ArrayView} {before after : State}
    (roots : ∀ view ∈ pending, view.projections = [])
    (initial : Lanius.Properties.StateWellFormed before)
    (synced : syncI32ViewsFromHeapFrom pending before = .ok after) :
    Lanius.Properties.StateWellFormed after ∧ after.heap = before.heap ∧
      after.i32ArrayViews = before.i32ArrayViews ∧ after.nextCell = before.nextCell := by
  induction pending generalizing before with
  | nil => cases synced; exact ⟨initial, rfl, rfl, rfl⟩
  | cons view rest ih =>
      have root := roots view (by simp)
      cases loaded : before.heap.loadBytes view.address (view.length * 4) with
      | error reason => simp [syncI32ViewsFromHeapFrom, loaded] at synced
      | ok bytes =>
          cases decoded : decodeI32Array view.length bytes with
          | error reason => simp [syncI32ViewsFromHeapFrom, loaded, decoded] at synced
          | ok elements =>
              cases assigned : before.assignCell view.root (.array elements) with
              | none => simp [syncI32ViewsFromHeapFrom, loaded, decoded, writeResolvedPlace, root, assigned] at synced
              | some next =>
                  have remaining : syncI32ViewsFromHeapFrom rest next = .ok after := by
                    simpa only [syncI32ViewsFromHeapFrom, loaded, decoded, writeResolvedPlace, root, assigned] using synced
                  obtain ⟨valid, heap, registry, nextCell⟩ := ih
                    (fun other member => roots other (by simp [member]))
                    (Lanius.Properties.assignCell_preserves_well_formed initial assigned) remaining
                  rw [Lanius.Properties.assignCell_state assigned] at heap registry nextCell
                  exact ⟨valid, heap, registry, nextCell⟩

theorem syncI32ViewsToHeapFrom_nextCell
    {pending : List I32ArrayView} {before after : State}
    (synced : syncI32ViewsToHeapFrom pending before = .ok after) :
    after.nextCell = before.nextCell := by
  induction pending generalizing before with
  | nil => cases synced; rfl
  | cons view rest ih =>
      obtain ⟨elements, bytes, heap, _, _, _, _, remaining⟩ := syncI32ViewsToHeapFrom_cons_invert synced
      exact ih (before := { before with heap }) remaining

theorem syncI32ViewsToHeapFrom_preserves_storage
    {pending views : List I32ArrayView} {before after : State}
    (wellFormed : HeapWellFormed before.heap)
    (synced : syncI32ViewsToHeapFrom pending before = .ok after) :
    HeapWellFormed after.heap ∧
      Lanius.Properties.I32ArrayViewBlocksPreserved views before.heap after.heap ∧
      after.cells = before.cells ∧ after.i32ArrayViews = before.i32ArrayViews ∧
      after.locals = before.locals := by
  induction pending generalizing before with
  | nil =>
      cases synced
      exact ⟨wellFormed, Lanius.Properties.I32ArrayViewBlocksPreserved.refl _ _, rfl, rfl, rfl⟩
  | cons view rest ih =>
      obtain ⟨elements, bytes, heap, _, _, _, stored, remaining⟩ :=
        syncI32ViewsToHeapFrom_cons_invert synced
      have first := Lanius.Properties.storeBytes_preserves_i32_array_view_blocks
        (views := views) wellFormed stored
      obtain ⟨valid, preserved, cells, registry, locals⟩ := ih
        (Lanius.Properties.storeBytes_preserves_heap_well_formed wellFormed stored) remaining
      exact ⟨valid, first.trans preserved, cells, registry, locals⟩

theorem syncI32ViewsToHeapFrom_remaining
    {pending : List I32ArrayView} {before after : State}
    (synced : syncI32ViewsToHeapFrom pending before = .ok after) :
    after.heap.remaining = before.heap.remaining := by
  induction pending generalizing before with
  | nil => cases synced; rfl
  | cons view rest ih =>
      obtain ⟨elements, bytes, heap, _, _, _, stored, remaining⟩ :=
        syncI32ViewsToHeapFrom_cons_invert synced
      exact (ih remaining).trans (storeBytesFrom_remaining stored)

theorem syncI32ViewsToHeapFrom_preserves_read_outside
    {pending : List I32ArrayView} {before after : State}
    {pointer offset : Nat} {byte : UInt8}
    (wellFormed : HeapWellFormed before.heap)
    (synced : syncI32ViewsToHeapFrom pending before = .ok after)
    (loaded : before.heap.loadByte pointer offset = .ok byte)
    (outside : ∀ view ∈ pending,
      pointer + offset < view.address ∨
        view.address + view.length * 4 ≤ pointer + offset) :
    after.heap.loadByte pointer offset = .ok byte := by
  induction pending generalizing before with
  | nil =>
      simp only [syncI32ViewsToHeapFrom, Except.ok.injEq] at synced
      subst after
      exact loaded
  | cons view rest ih =>
      obtain ⟨elements, bytes, heap, _, lengthMatches, encoded, stored, restSynced⟩ :=
        syncI32ViewsToHeapFrom_cons_invert synced
      have width := Lanius.Properties.encodeI32Array_length encoded
      have away : pointer + offset < view.address + 0 ∨
          view.address + 0 + bytes.length ≤ pointer + offset := by
        simpa only [Nat.add_zero, width, lengthMatches] using outside view (by simp)
      have preserved := storeBytesFrom_preserves_read_outside wellFormed stored loaded away
      exact ih (Lanius.Properties.storeBytes_preserves_heap_well_formed
        wellFormed stored) restSynced preserved
        (fun other member => outside other (by simp [member]))

/-- After a successful synchronization of disjoint views, each view's raw
bytes are exactly the serialization of its language-level cell. This is a
functional-content theorem, not just a memory-safety theorem. -/
theorem syncI32ViewsToHeapFrom_reads_view
    {pending : List I32ArrayView} {before after : State}
    {view : I32ArrayView} {elements : List Value} {bytes : List UInt8}
    (wellFormed : HeapWellFormed before.heap)
    (disjoint : pending.Pairwise I32ViewRangesDisjoint)
    (member : view ∈ pending)
    (read : readCellProjection before view.root view.projections = .ok (.array elements))
    (encoded : encodeI32Array elements = .ok bytes)
    (synced : syncI32ViewsToHeapFrom pending before = .ok after) :
    after.heap.loadBytes view.address bytes.length = .ok bytes := by
  induction pending generalizing before with
  | nil => simp at member
  | cons head rest ih =>
      obtain ⟨headElements, headBytes, heap, headRead, headLength, headEncoded,
        stored, restSynced⟩ := syncI32ViewsToHeapFrom_cons_invert synced
      have nextWellFormed :=
        Lanius.Properties.storeBytes_preserves_heap_well_formed wellFormed stored
      obtain ⟨separated, tailDisjoint⟩ := List.pairwise_cons.mp disjoint
      rcases List.mem_cons.mp member with same | tailMember
      · subst head
        rw [read] at headRead
        cases headRead
        rw [encoded] at headEncoded
        cases headEncoded
        have width : bytes.length = view.length * 4 := by
          simpa only [headLength] using Lanius.Properties.encodeI32Array_length encoded
        apply loadBytesFrom_of_reads
        intro index byte selected
        have indexBound : index < bytes.length := by
          obtain ⟨bound, _⟩ := List.getElem?_eq_some_iff.mp selected
          exact bound
        have firstRead := storeBytesFrom_reads_written wellFormed stored selected
        apply syncI32ViewsToHeapFrom_preserves_read_outside nextWellFormed restSynced firstRead
        intro other otherMember
        have apart := separated other otherMember
        unfold I32ViewRangesDisjoint at apart
        simp only [Nat.zero_add]
        rcases apart with left | right
        · apply Or.inl
          have inView : index < view.length * 4 := by simpa only [width] using indexBound
          exact Nat.lt_of_lt_of_le (Nat.add_lt_add_left inView view.address) left
        · exact Or.inr (Nat.le_trans right (Nat.le_add_right _ _))
      · apply ih (before := { before with heap }) nextWellFormed tailDisjoint
          tailMember _ restSynced
        simpa only [readCellProjection, State.cellEntry?] using read

theorem assignCell_preserves_world
    {before after : State} {cell : CellId} {value : Value}
    (assigned : before.assignCell cell value = some after) :
    after.world = before.world := by
  unfold State.assignCell at assigned
  split at assigned
  · cases Option.some.inj assigned
    rfl
  · contradiction

theorem writeResolvedPlace_assignCell
    {before after : State} {place : ResolvedPlace} {value : Value}
    (written : writeResolvedPlace before place value = .ok after) :
    ∃ updated, before.assignCell place.root updated = some after := by
  cases projections : place.projections with
  | nil =>
      cases assigned : before.assignCell place.root value with
      | none => simp [writeResolvedPlace, projections, assigned] at written
      | some state =>
          simp only [writeResolvedPlace, projections, assigned, Except.ok.injEq] at written
          subst after
          exact ⟨value, assigned⟩
  | cons projection rest =>
      cases found : before.cellEntry? place.root with
      | none => simp [writeResolvedPlace, projections, found] at written
      | some cell =>
          obtain ⟨cellId, contents⟩ := cell
          cases contents with
          | none => simp [writeResolvedPlace, projections, found] at written
          | some rootValue =>
              cases replaced : replaceProjectedValue rootValue place.projections value with
              | error reason =>
                  simp [writeResolvedPlace, projections, found, projections ▸ replaced] at written
              | ok updated =>
                  cases assigned : before.assignCell place.root updated with
                  | none =>
                      simp [writeResolvedPlace, projections, found,
                        projections ▸ replaced, assigned] at written
                  | some state =>
                      have same : state = after := by
                        simpa [writeResolvedPlace, projections, found,
                          projections ▸ replaced, assigned] using written
                      subst after
                      exact ⟨updated, assigned⟩

theorem writeResolvedPlace_preserves_world
    {before after : State} {place : ResolvedPlace} {value : Value}
    (written : writeResolvedPlace before place value = .ok after) :
    after.world = before.world := by
  obtain ⟨_, assigned⟩ := writeResolvedPlace_assignCell written
  exact assignCell_preserves_world assigned

theorem writeResolvedPlace_preserves_heap
    (written : writeResolvedPlace before place value = .ok after) :
    after.heap = before.heap := by
  obtain ⟨_, assigned⟩ := writeResolvedPlace_assignCell written
  rw [Lanius.Properties.assignCell_state assigned]

theorem writeResolvedPlace_preserves_other_cell
    (written : writeResolvedPlace before place value = .ok after)
    (different : cell ≠ place.root) :
    after.cellEntry? cell = before.cellEntry? cell := by
  obtain ⟨_, assigned⟩ := writeResolvedPlace_assignCell written
  exact Lanius.Properties.assignCell_preserves_other assigned different

/-- Refreshing language views after a host call cannot erase or manufacture
host output: it mutates language cells, never the process world. -/
theorem syncI32ViewsFromHeapFrom_preserves_world
    {pending : List I32ArrayView} {before after : State}
    (synced : syncI32ViewsFromHeapFrom pending before = .ok after) :
    after.world = before.world := by
  induction pending generalizing before with
  | nil =>
      simp only [syncI32ViewsFromHeapFrom, Except.ok.injEq] at synced
      subst after
      rfl
  | cons view rest ih =>
      cases loaded : before.heap.loadBytes view.address (view.length * 4) with
      | error reason => simp [syncI32ViewsFromHeapFrom, loaded] at synced
      | ok bytes =>
          cases decoded : decodeI32Array view.length bytes with
          | error reason => simp [syncI32ViewsFromHeapFrom, loaded, decoded] at synced
          | ok elements =>
              cases written : writeResolvedPlace before
                  { root := view.root, projections := view.projections, value := none }
                  (.array elements) with
              | error reason =>
                  simp [syncI32ViewsFromHeapFrom, loaded, decoded, written] at synced
              | ok state =>
                  have restSynced : syncI32ViewsFromHeapFrom rest state = .ok after := by
                    simpa [syncI32ViewsFromHeapFrom, loaded, decoded, written] using synced
                  exact (ih restSynced).trans (writeResolvedPlace_preserves_world written)

theorem syncI32ViewsFromHeap_preserves_world
    {before after : State} (synced : syncI32ViewsFromHeap before = .ok after) :
    after.world = before.world := syncI32ViewsFromHeapFrom_preserves_world synced

end Lanius.Semantics
