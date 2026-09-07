import Lanius.Memory.Store

namespace Lanius.Semantics

open Lanius.Core Lanius.Memory

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
