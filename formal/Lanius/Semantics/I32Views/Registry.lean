import Lanius.Semantics.I32Views

namespace Lanius.Semantics

open Lanius.Core Lanius.Memory

theorem syncI32ViewsToHeapFrom_preserves_registry
    (synced : syncI32ViewsToHeapFrom pending before = .ok after) :
    after.i32ArrayViews = before.i32ArrayViews := by
  induction pending generalizing before after with
  | nil => simpa [syncI32ViewsToHeapFrom] using congrArg (fun result =>
      match result with | .ok state => state.i32ArrayViews | .error _ => []) synced.symm
  | cons view rest induction =>
      obtain ⟨_, _, heap, _, _, _, _, remaining⟩ := syncI32ViewsToHeapFrom_cons_invert synced
      exact induction (before := { before with heap }) remaining

theorem syncI32ViewsToHeapFrom_preserves_heapWellFormed
    (wellFormed : HeapWellFormed before.heap)
    (synced : syncI32ViewsToHeapFrom pending before = .ok after) :
    HeapWellFormed after.heap := by
  induction pending generalizing before with
  | nil => simp [syncI32ViewsToHeapFrom] at synced; subst after; exact wellFormed
  | cons view rest induction =>
      obtain ⟨_, _, heap, _, _, _, stored, remaining⟩ := syncI32ViewsToHeapFrom_cons_invert synced
      exact induction (before := { before with heap })
        (Lanius.Properties.storeBytes_preserves_heap_well_formed wellFormed stored) remaining

/-- Successful raw-slice construction registers exactly one view. In
particular, it does not silently coalesce repeated registrations of an address;
the extractor must reuse its existing slice for repeated file reads. -/
theorem mapRawI32Slice_registry
    (mapped : mapRawI32Slice before address length = .done value after) :
    ∃ view, view.address = address ∧ view.root = before.nextCell ∧
      after.nextCell = before.nextCell + 1 ∧
      after.i32ArrayViews = before.i32ArrayViews ++ [view] := by
  unfold mapRawI32Slice at mapped
  split at mapped
  · contradiction
  · cases protection : before.heap.protectAsBorrowed address (length.toNat * 4) 4 with
    | error reason => simp [protection] at mapped
    | ok heap =>
        cases loaded : heap.loadBytes address (length.toNat * 4) with
        | error reason => simp [protection, loaded] at mapped
        | ok bytes =>
            cases decoded : decodeI32Array length.toNat bytes with
            | error reason => simp [protection, loaded, decoded] at mapped
            | ok elements =>
                simp only [protection, loaded, decoded, State.allocateTemporary, Outcome.done.injEq]
                  at mapped
                obtain ⟨_, rfl⟩ := mapped
                exact ⟨_, rfl, rfl, rfl, rfl⟩

theorem mapRawI32Slice_preserves_distinct_addresses
    (distinct : before.i32ArrayViews.Pairwise fun left right => left.address ≠ right.address)
    (fresh : ∀ view ∈ before.i32ArrayViews, view.address ≠ address)
    (mapped : mapRawI32Slice before address length = .done value after) :
    after.i32ArrayViews.Pairwise fun left right => left.address ≠ right.address := by
  obtain ⟨view, viewAddress, _, _, registry⟩ := mapRawI32Slice_registry mapped
  rw [registry, List.pairwise_append]
  refine ⟨distinct, by simp, ?_⟩
  intro old oldMember new newMember
  have same : new = view := by simpa using newMember
  subst new
  simpa [viewAddress] using fresh old oldMember

/-- A raw slice allocates a fresh language-level backing cell as well as
registering its raw address. Existing view roots remain below the new cell
frontier, so repeated bootstrap allocations preserve root uniqueness. -/
theorem mapRawI32Slice_preserves_distinct_roots
    (distinct : before.i32ArrayViews.Pairwise fun left right => left.root ≠ right.root)
    (below : ∀ view ∈ before.i32ArrayViews, view.root < before.nextCell)
    (mapped : mapRawI32Slice before address length = .done value after) :
    (after.i32ArrayViews.Pairwise fun left right => left.root ≠ right.root) ∧
      (∀ view ∈ after.i32ArrayViews, view.root < after.nextCell) := by
  obtain ⟨view, _, root, frontier, registry⟩ := mapRawI32Slice_registry mapped
  constructor
  · rw [registry, List.pairwise_append]
    refine ⟨distinct, by simp, ?_⟩
    intro old oldMember new newMember
    have same : new = view := by simpa using newMember
    subst new
    have oldBelow := below old oldMember
    rw [root]
    exact Nat.ne_of_lt oldBelow
  · intro candidate member
    rw [registry] at member
    rcases List.mem_append.mp member with old | new
    · have oldBelow := below candidate old
      rw [frontier]
      exact Nat.lt_trans oldBelow (Nat.lt_succ_self _)
    · have same : candidate = view := by simpa using new
      subst candidate
      rw [root, frontier]
      exact Nat.lt_succ_self _

/-- Exposing a pointer for a previously registered array synchronizes bytes
without adding any aliasing view to the registry. -/
theorem mapI32ArrayView_existing_registry
    (existing : before.i32ArrayView? root projections = some view)
    (mapped : mapI32ArrayView before root projections elements = .done value after) :
    after.i32ArrayViews = before.i32ArrayViews := by
  unfold mapI32ArrayView at mapped
  rw [existing] at mapped
  cases synced : syncI32ViewsToHeap before with
  | error reason => simp [synced] at mapped
  | ok ready =>
      simp only [synced, Outcome.done.injEq] at mapped
      obtain ⟨_, rfl⟩ := mapped
      exact syncI32ViewsToHeapFrom_preserves_registry synced

theorem i32View_address_below_frontier
    (wellFormed : HeapWellFormed heap)
    (valid : I32ArrayViewBlockWellFormed heap view) :
    view.address < heap.nextAddress := by
  obtain ⟨block, found, _⟩ := valid
  have base : block.base = view.address :=
    beq_iff_eq.mp (List.find?_some (p := fun block : Block => block.base == view.address) found)
  have below := wellFormed.blocksBelowNext block (List.mem_of_find?_eq_some found)
  rw [base] at below
  have positive : 0 < max block.size 1 := by omega
  exact Nat.lt_of_lt_of_le (Nat.lt_add_of_pos_right positive) below

/-- Both paths through array-pointer exposure preserve unique registered
addresses: an existing view is reused, and a new view is allocated beyond
every existing heap block, including zero-byte blocks. -/
theorem mapI32ArrayView_preserves_distinct_addresses
    (wellFormed : HeapWellFormed before.heap)
    (valid : ∀ view ∈ before.i32ArrayViews, I32ArrayViewBlockWellFormed before.heap view)
    (distinct : before.i32ArrayViews.Pairwise fun left right => left.address ≠ right.address)
    (mapped : mapI32ArrayView before root projections elements = .done value after) :
    after.i32ArrayViews.Pairwise fun left right => left.address ≠ right.address := by
  cases existing : before.i32ArrayView? root projections with
  | some view =>
      rw [mapI32ArrayView_existing_registry existing mapped]
      exact distinct
  | none =>
      unfold mapI32ArrayView at mapped
      rw [existing] at mapped
      cases encoded : encodeI32Array elements with
      | error reason => simp [encoded] at mapped
      | ok bytes =>
          simp only [encoded, Heap.mapBorrowed,
            show validAlignment 4 = true by decide, Bool.not_true,
            Bool.false_eq_true, if_false, Outcome.done.injEq] at mapped
          obtain ⟨_, rfl⟩ := mapped
          apply List.pairwise_append.mpr
          refine ⟨distinct, by simp, ?_⟩
          intro old member new selected
          have same : new = ⟨alignUp (max before.heap.nextAddress 1) 4,
              root, projections, elements.length⟩ := by simpa using selected
          subst new
          have oldBelow := i32View_address_below_frontier wellFormed (valid old member)
          have aligned := Lanius.Properties.alignUp_ge (max before.heap.nextAddress 1) 4 (by decide)
          change old.address ≠ alignUp (max before.heap.nextAddress 1) 4
          exact Nat.ne_of_lt (Nat.lt_of_lt_of_le oldBelow
            (Nat.le_trans (Nat.le_max_left _ _) aligned))

theorem mapI32SliceDataPtr_preserves_distinct_addresses
    (wellFormed : HeapWellFormed before.heap)
    (valid : ∀ view ∈ before.i32ArrayViews, I32ArrayViewBlockWellFormed before.heap view)
    (distinct : before.i32ArrayViews.Pairwise fun left right => left.address ≠ right.address)
    (mapped : mapI32SliceDataPtr before cell projections start length = .done value after) :
    after.i32ArrayViews.Pairwise fun left right => left.address ≠ right.address := by
  unfold mapI32SliceDataPtr at mapped
  cases read : readCellProjection before cell projections with
  | error reason => simp [read] at mapped
  | ok content =>
      cases content <;> try simp [read] at mapped
      rename_i elements
      by_cases bound : start + length ≤ elements.length
      · simp only [bound, if_true] at mapped
        cases exposure : mapI32ArrayView before cell projections elements with
        | outOfFuel => simp [exposure] at mapped
        | trapped reason state => simp [exposure] at mapped
        | exited code state => simp [exposure] at mapped
        | done pointer state =>
            cases pointer <;> try simp [exposure] at mapped
            rename_i address
            obtain ⟨_, rfl⟩ := mapped
            exact mapI32ArrayView_preserves_distinct_addresses wellFormed valid distinct exposure
      · simp [bound] at mapped

/-- Pointer exposure for a registered slice reuses its view. Both address
and root uniqueness therefore survive the repeated `read_file` calls. -/
theorem mapI32SliceDataPtr_existing_registry
    (existing : before.i32ArrayView? root projections = some view)
    (mapped : mapI32SliceDataPtr before root projections start length = .done value after) :
    after.i32ArrayViews = before.i32ArrayViews := by
  unfold mapI32SliceDataPtr at mapped
  cases read : readCellProjection before root projections with
  | error reason => simp [read] at mapped
  | ok array =>
      cases array <;> try simp [read] at mapped
      rename_i elements
      split at mapped
      · cases exposure : mapI32ArrayView before root projections elements with
        | outOfFuel => simp [exposure] at mapped
        | trapped reason state => simp [exposure] at mapped
        | exited code state => simp [exposure] at mapped
        | done pointer state =>
            cases pointer <;> try simp [exposure] at mapped
            rename_i address
            obtain ⟨_, rfl⟩ := mapped
            exact mapI32ArrayView_existing_registry existing exposure
      · contradiction

end Lanius.Semantics
