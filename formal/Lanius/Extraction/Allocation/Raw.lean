import Lanius.Extraction.Allocation.Refresh
import Lanius.Extraction.Allocation.Transport

namespace Lanius.Extraction.Allocation

open Lanius.Core Lanius.Semantics Lanius.Memory Lanius.Properties Lanius.Separation Lanius.CallContracts

/-- A host operation can refresh registered roots without deleting any caller
cell. This is the domain fact needed when closing an allocation's pointer scope. -/
theorem Registry.domainOfFrame (initial : Registry before) (valid : Registry after)
    (views : ∀ view ∈ before.i32ArrayViews, view ∈ after.i32ArrayViews)
    (frame : ∀ cell, cell < before.nextCell → (∀ view ∈ before.i32ArrayViews, cell ≠ view.root) →
      after.cellEntry? cell = before.cellEntry? cell) : CellDomainExtension before after := by
  constructor
  intro entry member
  by_cases registered : ∃ view ∈ before.i32ArrayViews, entry.id = view.root
  · obtain ⟨view, present, identity⟩ := registered
    obtain ⟨values, _, found⟩ := valid.storage (views view present)
    exact ⟨_, List.mem_of_find?_eq_some found, identity.symm⟩
  · have separate : ∀ view ∈ before.i32ArrayViews, entry.id ≠ view.root := by
      intro view present same
      exact registered ⟨view, present, same⟩
    have kept := frame entry.id (initial.wellFormed.cellIdsBelowNext entry member) separate
    cases found : before.cellEntry? entry.id with
    | none =>
        have absent := List.find?_eq_none.mp found entry member
        simp at absent
    | some old =>
        have retained := kept.trans found
        exact ⟨old, List.mem_of_find?_eq_some retained, by simpa using List.find?_some retained⟩

/-- Allocate raw bytes before making a slice. The source must check the
returned pointer before calling the separate registration operation. -/
theorem Registry.allocateRaw
    {program : Program} {function : Function} {before : State}
    {bindings : List (Lanius.VarId × Value)} (count : Nat)
    (functionFound : program.function? function.id = some function)
    (parametersBound : bindParameters function.parameters
      [.unsigned .usize (count * 4), .unsigned .usize 4] = some bindings)
    (noBody : function.body = none) (host : function.external = some (.host .alloc))
    (initial : Registry before)
    (room : ∀ available, before.heap.remaining = some available → count * 4 ≤ available) :
    ∃ address after, Evaluates program before
      (.call function.id [.value (.unsigned .usize (count * 4)), .value (.unsigned .usize 4)])
      (.pointer address) after ∧ Registry after ∧
      after.world = Lanius.World.record before.world .alloc ∧
      after.heap.block? address = some {
        base := address, size := count * 4, alignment := 4, bytes := List.replicate (count * 4) 0 } ∧
      after.heap.remaining = before.heap.remaining.map (fun available => available - count * 4) ∧
      after.i32ArrayViews = before.i32ArrayViews ∧ after.nextCell = before.nextCell ∧
      after.locals = before.locals ∧
      (∀ cell, (∀ view ∈ before.i32ArrayViews, cell ≠ view.root) →
        after.cellEntry? cell = before.cellEntry? cell) ∧
      (∀ view ∈ before.i32ArrayViews, view.address ≠ address) := by
  obtain ⟨address, after, evaluated, world, valid, found, remaining, views, next, locals,
      kept, frame, arrays, fresh⟩ := hostAllocation_exists count functionFound parametersBound
        noBody host initial.wellFormed room initial.blocks initial.roots initial.arrays
  refine ⟨address, after, evaluated, ⟨valid, ?_, ?_, ?_, arrays initial.distinct, ?_⟩,
    world, found, remaining, views, next, locals, frame, fresh⟩
  · intro view member
    rw [views] at member
    exact kept view member (initial.blocks view member)
  · simpa only [views] using initial.roots
  · simpa only [views] using initial.distinct
  · simpa only [views] using initial.addresses

/-- Exhaustion is a normal null return from the actual host call, including
both registry synchronization passes. It does not consume the remaining budget
or create a raw view. -/
theorem Registry.allocationExhausted
    {program : Program} {function : Function} {before : State}
    {bindings : List (Lanius.VarId × Value)} (count : Nat)
    (functionFound : program.function? function.id = some function)
    (parametersBound : bindParameters function.parameters
      [.unsigned .usize (count * 4), .unsigned .usize 4] = some bindings)
    (noBody : function.body = none) (host : function.external = some (.host .alloc))
    (initial : Registry before)
    (budget : before.heap.remaining = some available) (short : available < count * 4) :
    ∃ after, Evaluates program before
      (.call function.id [.value (.unsigned .usize (count * 4)), .value (.unsigned .usize 4)])
      (.pointer null) after ∧ Registry after ∧
      after.world = Lanius.World.record before.world .alloc ∧
      after.heap.remaining = before.heap.remaining ∧ after.i32ArrayViews = before.i32ArrayViews ∧
      after.nextCell = before.nextCell ∧ after.locals = before.locals ∧
      (∀ cell, (∀ view ∈ before.i32ArrayViews, cell ≠ view.root) →
        after.cellEntry? cell = before.cellEntry? cell) := by
  obtain ⟨ready, synced, valid, cells, locals, views, next, remaining, world⟩ := initial.synchronize
  have exhausted : ready.heap.allocate (count * 4) 4 = .exhausted ready.heap := by
    simp [Heap.allocate, show validAlignment 4 = true by decide,
      consumeBudget, remaining, budget, Nat.not_le.mpr short]
  obtain ⟨after, refreshed, afterValid, heap, afterViews, afterNext, afterLocals, afterWorld, frame⟩ :=
    (valid.withWorld (Lanius.World.record ready.world .alloc)).refresh
  have arguments : ArgumentsEvaluateTo program before
      [.value (.unsigned .usize (count * 4)), .value (.unsigned .usize 4)]
      [.unsigned .usize (count * 4), .unsigned .usize 4] before := ⟨3, rfl⟩
  have evaluated := evaluatesHostCallReturned arguments functionFound parametersBound noBody host synced
    (show Lanius.World.call ready.heap ready.world .alloc
      [.unsigned .usize (count * 4), .unsigned .usize 4] =
      .returned (.pointer null) ready.heap (Lanius.World.record ready.world .alloc) by
        simp only [Lanius.World.call, Lanius.World.callSimple, exhausted]) refreshed
  refine ⟨after, evaluated, afterValid, ?_, ?_, afterViews.trans views,
    afterNext.trans next, afterLocals.trans locals, ?_⟩
  · simpa only [world] using afterWorld
  · simpa only [heap] using remaining
  · intro cell separate
    have kept := frame cell (fun view member => separate view (by simpa only [views] using member))
    simpa only [State.cellEntry?, cells] using kept

/-- Register a checked, fresh raw block independently of allocation. This
permits the source null guard to occur between allocation and slice creation. -/
theorem Registry.mapRaw (initial : Registry before)
    (found : before.heap.block? address = some block)
    (live : block.live = true) (size : block.size = count * 4) (alignment : block.alignment = 4)
    (fresh : ∀ view ∈ before.i32ArrayViews, view.address ≠ address) :
    ∃ after, mapRawI32Slice before address count =
      .done (.slice (.scalar (.signed .i32)) before.nextCell [] 0 count) after ∧
      Registry after ∧ CellEffect CellSet.empty before after ∧
      after.heap.remaining = before.heap.remaining ∧ after.nextCell = before.nextCell + 1 ∧
      ∃ elements, after.i32ArrayViews = before.i32ArrayViews ++
        [{ address, root := before.nextCell, projections := [], length := count }] ∧
        readCellProjection after before.nextCell [] = .ok (.array elements) ∧
        elements.length = count ∧ ∀ element ∈ elements, ∃ value, element = .signed .i32 value := by
  obtain ⟨after, mapped, views, validBlock, heapValid, next, locals, world, preserved,
      remaining, elements, cells, length, typed⟩ :=
    mapRawI32Slice_exists initial.wellFormed.heapWellFormed found live size alignment
  have temporary := allocateTemporary_preserves_well_formed before (.array elements) initial.wellFormed
  have valid : StateWellFormed after := by
    constructor
    · exact heapValid
    · simpa only [CellIdsUnique, State.allocateTemporary, cells] using temporary.cellIdsUnique
    · simpa only [CellIdsBelowNext, State.allocateTemporary, cells, next] using temporary.cellIdsBelowNext
    · simpa only [LocalsReferenceCells, State.allocateTemporary, cells, locals] using temporary.localsReferenceCells
  have kept : ∀ cell, cell < before.nextCell → after.cellEntry? cell = before.cellEntry? cell := by
    intro cell old
    simpa only [State.allocateTemporary, State.cellEntry?, cells] using
      allocateTemporary_preserves_old_cell before (.array elements) cell old
  have stored : readCellProjection after before.nextCell [] = .ok (.array elements) := by
    have entry : after.cellEntry? before.nextCell =
        some { id := before.nextCell, value := some (.array elements) } := by
      simpa only [State.allocateTemporary, State.cellEntry?, cells] using
        allocateTemporary_finds_fresh_cell before (.array elements) initial.wellFormed
    simp only [readCellProjection, entry, projectedValue]
  refine ⟨after, mapped, ⟨valid, ?_, ?_, ?_, ?_, ?_⟩,
    ⟨valid, locals, world, fun cell old _ => kept cell old, by rw [next]; exact Nat.le_succ _, ?_⟩,
    remaining, next, elements, views, stored, length, typed⟩
  · intro view member
    rw [views] at member
    rcases List.mem_append.mp member with old | fresh
    · exact preserved view old (initial.blocks view old)
    · simp only [List.mem_singleton] at fresh
      subst view
      exact validBlock
  · intro view member
    rw [views] at member
    rcases List.mem_append.mp member with old | fresh
    · exact initial.roots view old
    · simp only [List.mem_singleton] at fresh
      subst view
      rfl
  · rw [views, List.pairwise_append]
    refine ⟨initial.distinct, by simp, ?_⟩
    intro left member right singleton
    simp only [List.mem_singleton] at singleton
    subst right
    exact Nat.ne_of_lt (initial.root_lt_next member)
  · intro view member
    rw [views] at member
    rcases List.mem_append.mp member with old | fresh
    · obtain ⟨values, read, length, typed⟩ := initial.arrays view old
      exact ⟨values, by simpa only [readCellProjection, kept view.root (initial.root_lt_next old)] using read,
        length, typed⟩
    · simp only [List.mem_singleton] at fresh
      subst view
      exact ⟨elements, stored, length, typed⟩
  · rw [views, List.pairwise_append]
    refine ⟨initial.addresses, by simp, ?_⟩
    intro left member right singleton
    simp only [List.mem_singleton] at singleton
    subst right
    exact fresh left member
  · constructor
    intro entry member
    exact ⟨entry, by rw [cells]; exact List.mem_append_left _ member, rfl⟩

end Lanius.Extraction.Allocation
