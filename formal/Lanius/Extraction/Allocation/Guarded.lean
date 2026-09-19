import Lanius.Extraction.Allocation.Raw
import Lanius.Separation.LocalCall

namespace Lanius.Extraction.Allocation

open Lanius.Core Lanius.Semantics Lanius.Memory Lanius.Properties Lanius.Separation

/-- Resources after one guarded allocation. The buffer cell survives; its raw
pointer temporary has left scope. Only existing registered roots may refresh. -/
structure Initialized (buffer : Buffer) (before after : State) : Prop where
  registry : Registry after
  world : after.world = Lanius.World.record before.world .alloc
  remaining : after.heap.remaining = before.heap.remaining.map (fun available => available - buffer.count * 4)
  next : after.nextCell = before.nextCell + 3
  locals : after.locals = (buffer.binding, before.nextCell) :: before.locals
  frame : ∀ cell, cell < before.nextCell → (∀ view ∈ before.i32ArrayViews, cell ≠ view.root) →
    after.cellEntry? cell = before.cellEntry? cell
  binding : after.cellEntry? before.nextCell = some {
    id := before.nextCell
    value := some (.slice (.scalar (.signed .i32)) (before.nextCell + 2) [] 0 buffer.count) }
  storage : ∃ address elements,
    after.i32ArrayViews = before.i32ArrayViews ++
      [{ address, root := before.nextCell + 2, projections := [], length := buffer.count }] ∧
    readCellProjection after (before.nextCell + 2) [] = .ok (.array elements) ∧
    elements.length = buffer.count ∧ ∀ element ∈ elements, ∃ value, element = .signed .i32 value

private theorem Step.guardTest (step : Step) (program : Program)
    (read : before.local? step.pointer = some (.pointer address)) :
    Evaluates program before
      (.binary .equal (.local step.pointer) (.value (.pointer null)))
      (.boolean (address == null)) before := by
  apply evaluatesEagerBinary (by decide) (by decide)
    (Lanius.Semantics.evaluatesLocal read)
    (show Evaluates program before (.value (.pointer null)) (.pointer null) before from Lanius.Semantics.evaluatesValue)
  rfl

theorem Step.initializes (step : Step)
    {program : Program} {function : Function} {before : State}
    {bindings : List (Lanius.VarId × Value)}
    (functionFound : program.function? function.id = some function)
    (parametersBound : bindParameters function.parameters
      [.unsigned .usize (step.buffer.count * 4), .unsigned .usize 4] = some bindings)
    (noBody : function.body = none) (host : function.external = some (.host .alloc))
    (initial : Registry before)
    (room : ∀ available, before.heap.remaining = some available → step.buffer.count * 4 ≤ available) :
    ∃ after, Executes program (before.bindUninitialized step.buffer.binding)
      (step.initialize function.id) .next after ∧ Initialized step.buffer before after := by
  let entered := before.bindUninitialized step.buffer.binding
  have enteredValid := initial.bindUninitialized step.buffer.binding
  obtain ⟨address, allocated, called, allocatedValid, world, block, budget, views, next, locals, frame, fresh⟩ :=
    enteredValid.allocateRaw step.buffer.count functionFound parametersBound noBody host room
  have nonnull : address ≠ null := by
    have validBlock := allocatedValid.wellFormed.heapWellFormed.blocksWellFormed _
      (List.mem_of_find?_eq_some block)
    exact validBlock.1
  let bound := allocated.bindLocal step.pointer (.pointer address)
  have boundValid := allocatedValid.bindLocal step.pointer (.pointer address)
  have read : bound.local? step.pointer = some (.pointer address) :=
    bindLocal_finds_local allocated _ _ allocatedValid.wellFormed
  have uninitialized : (Assertion.localPointsTo step.buffer.binding before.nextCell none).holds allocated := by
    constructor
    · simp [State.cellId?, locals, entered, State.bindUninitialized, State.bindCell]
    · have separate : ∀ view ∈ entered.i32ArrayViews, before.nextCell ≠ view.root := by
        intro view member
        exact Ne.symm (Nat.ne_of_lt (initial.root_lt_next member))
      rw [frame before.nextCell separate]
      exact bindCell_finds_fresh_cell before step.buffer.binding none initial.wellFormed
  have owned : (Assertion.localPointsTo step.buffer.binding before.nextCell none).holds bound :=
    bindLocal_preserves_localPointsTo_of_ne allocated _ _ _ _ _
      allocatedValid.wellFormed step.distinct uninitialized
  obtain ⟨mapped, mappedRun, mappedValid, mapEffect, mapBudget, mapNext, elements,
      mappedViews, stored, length, typed⟩ :=
    boundValid.mapRaw block rfl rfl rfl (fun view member => fresh view (by
      simpa only [State.bindLocal, State.bindCell, ← views] using member))
  have rightRun := evaluatesI32SliceFromRawParts
    (show Evaluates program bound (.local step.pointer) (.pointer address) bound from
      Lanius.Semantics.evaluatesLocal read)
    (show Evaluates program bound (.value (.signed .i32 step.buffer.count))
      (.signed .i32 step.buffer.count) bound from Lanius.Semantics.evaluatesValue) mappedRun
  obtain ⟨assigned, assignedRun, ownedResult, effect, assignedEffect, heapFrame, assignedNext⟩ :=
    evaluatesOwnedLocalSet owned rightRun mapEffect
      (mapEffect.preserves_localPointsTo boundValid.wellFormed owned (by simp [CellSet.empty]))
  have root : bound.nextCell = before.nextCell + 2 := by
    simp only [bound, State.bindLocal, State.bindCell, next, entered, State.bindUninitialized]
  have separate : ∀ view ∈ mapped.i32ArrayViews, view.root ≠ before.nextCell := by
    intro view member
    rw [mappedViews] at member
    rcases List.mem_append.mp member with old | new
    · have old : view ∈ before.i32ArrayViews := by
        simpa only [bound, State.bindLocal, State.bindCell, views, State.bindUninitialized] using old
      exact Nat.ne_of_lt (initial.root_lt_next old)
    · simp only [List.mem_singleton] at new
      subst view
      change bound.nextCell ≠ before.nextCell
      rw [root]
      exact Nat.ne_of_gt (Nat.lt_add_of_pos_right (by decide))
  have assignedValid := mappedValid.transport assignedEffect heapFrame (by
    intro view member written
    exact False.elim (separate view member written))
  have domain := (bindLocal_domainExtension allocated step.pointer (.pointer address)).trans effect.domain
  have finalValid := assignedValid.restoreLocals allocated
    (domain.restoreLocals_wellFormed allocatedValid.wellFormed assignedValid.wellFormed)
  have guardRun : Executes program bound step.guard .next bound := by
    have test := step.guardTest program read
    simp only [beq_eq_false_iff_ne.mpr nonnull] at test
    exact executesIfFalse test (executesSkip program bound)
  refine ⟨restoreLocals allocated assigned,
    executesLetLocal called (executesSequence guardRun
      (executesSequence (executesExpression assignedRun) (executesSkip program assigned))),
    ⟨finalValid, ?_, ?_, ?_, ?_, ?_, ?_, ?_⟩⟩
  · exact effect.world.trans world
  · change assigned.heap.remaining = _
    rw [heapFrame.heap, mapBudget]
    exact budget
  · change assigned.nextCell = _
    rw [assignedNext, mapNext, root]
  · exact locals
  · intro cell old apart
    have oldBound : cell < bound.nextCell := by
      rw [root]
      exact Nat.lt_of_lt_of_le old (Nat.le_add_right _ _)
    have untouched : ¬ CellSet.union CellSet.empty (CellSet.singleton before.nextCell) cell := by
      simp [CellSet.union, CellSet.empty, CellSet.singleton, Nat.ne_of_lt old]
    exact (effect.oldCells cell oldBound untouched).trans
      ((bindCell_preserves_old_cell allocated step.pointer (some (.pointer address)) cell
        (by rw [next]; exact Nat.lt_succ_of_lt old)).trans
          ((frame cell apart).trans (bindCell_preserves_old_cell before step.buffer.binding none cell old)))
  · change assigned.cellEntry? before.nextCell = _
    have binding := ownedResult.2
    change assigned.cellEntry? before.nextCell = some {
      id := before.nextCell
      value := some (.slice (.scalar (.signed .i32)) bound.nextCell [] 0 step.buffer.count) } at binding
    simpa only [root] using binding
  · refine ⟨address, elements, ?_, ?_, length, typed⟩
    · change assigned.i32ArrayViews = _
      have actual : assigned.i32ArrayViews = before.i32ArrayViews ++
          [{ address, root := bound.nextCell, projections := [], length := step.buffer.count }] :=
        (heapFrame.views.trans mappedViews).trans (by rw [show bound.i32ArrayViews = before.i32ArrayViews from views])
      simpa only [root] using actual
    · change readCellProjection assigned (before.nextCell + 2) [] = _
      have retained := assignedEffect.oldCells bound.nextCell (by rw [mapNext]; exact Nat.lt_succ_self _)
        (by change bound.nextCell ≠ before.nextCell; rw [root]
            exact Nat.ne_of_gt (Nat.lt_add_of_pos_right (by decide)))
      have read : readCellProjection assigned bound.nextCell [] = .ok (.array elements) := by
        simpa only [readCellProjection, retained] using stored
      simpa only [root] using read

/-- No raw slice is constructed when the host reports exhaustion. The return
also closes both lexical scopes and skips any following allocation or I/O. -/
theorem Step.rejectsExhaustion (step : Step)
    {program : Program} {function : Function} {before : State}
    {bindings : List (Lanius.VarId × Value)} (continuation : Stmt)
    (functionFound : program.function? function.id = some function)
    (parametersBound : bindParameters function.parameters
      [.unsigned .usize (step.buffer.count * 4), .unsigned .usize 4] = some bindings)
    (noBody : function.body = none) (host : function.external = some (.host .alloc))
    (initial : Registry before)
    (budget : before.heap.remaining = some available) (short : available < step.buffer.count * 4) :
    ∃ after, Executes program before (step.statement function.id continuation)
      (.returned (some (.signed .i32 3))) after ∧ Registry after ∧
      after.world = Lanius.World.record before.world .alloc ∧
      after.heap.remaining = before.heap.remaining ∧ after.i32ArrayViews = before.i32ArrayViews ∧
      after.locals = before.locals ∧ after.nextCell = before.nextCell + 2 := by
  let entered := before.bindUninitialized step.buffer.binding
  have enteredValid := initial.bindUninitialized step.buffer.binding
  obtain ⟨allocated, called, allocatedValid, world, remaining, views, next, locals, frame⟩ :=
    enteredValid.allocationExhausted step.buffer.count functionFound parametersBound noBody host budget short
  let bound := allocated.bindLocal step.pointer (.pointer null)
  have boundValid := allocatedValid.bindLocal step.pointer (.pointer null)
  have read : bound.local? step.pointer = some (.pointer null) :=
    bindLocal_finds_local allocated _ _ allocatedValid.wellFormed
  have test := step.guardTest program read
  simp only [beq_self_eq_true] at test
  have guarded : Executes program bound step.guard (.returned (some (.signed .i32 3))) bound :=
    executesIfTrue test (executesSequenceReturned
      (executesReturnValue (show Evaluates program bound (.value (.signed .i32 3))
        (.signed .i32 3) bound from Lanius.Semantics.evaluatesValue)))
  have executed : Executes program before (step.statement function.id continuation)
      (.returned (some (.signed .i32 3))) (restoreLocals before bound) := by
    simpa only [restoreLocals, Step.statement] using
      (executesLetUninitialized (type := .slice (.scalar (.signed .i32)))
        (executesSequenceReturned (executesLetLocal called (executesSequenceReturned guarded))) :
          Executes program before (step.statement function.id continuation)
            (.returned (some (.signed .i32 3))) _)
  have domain : CellDomainExtension before bound :=
    (bindUninitialized_domainExtension before step.buffer.binding).trans
      ((enteredValid.domainOfFrame allocatedValid (by intro view member; simpa only [views] using member)
        (fun cell _ separate => frame cell separate)).trans
          (bindLocal_domainExtension allocated step.pointer (.pointer null)))
  exact ⟨restoreLocals before bound, executed,
    boundValid.restoreLocals before (domain.restoreLocals_wellFormed initial.wellFormed boundValid.wellFormed),
    world, remaining, views, rfl, by
      simp only [restoreLocals, bound, State.bindLocal, State.bindCell, next, State.bindUninitialized]⟩

end Lanius.Extraction.Allocation
