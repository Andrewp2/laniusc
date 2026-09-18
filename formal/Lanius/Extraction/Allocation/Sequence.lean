import Lanius.Extraction.Allocation.Guarded
import Lanius.Semantics.Prefix

namespace Lanius.Extraction.Allocation

open Lanius.Core Lanius.Semantics

/-- Resources after each guarded source allocation, with its pointer temporary
out of scope. This relation assumes no allocation or continuation execution. -/
inductive HostReady : List Buffer → State → State → Prop where
  | nil : HostReady [] state state
  | cons (initialized : Initialized buffer before allocated)
      (rest : HostReady buffers allocated ready) : HostReady (buffer :: buffers) before ready

theorem Initialized.local (ready : Initialized buffer before after) :
    after.local? buffer.binding =
      some (.slice (.scalar (.signed .i32)) (before.nextCell + 2) [] 0 buffer.count) := by
  simp [State.local?, State.cellId?, ready.locals, State.cell?, ready.binding]

theorem HostReady.preserves_cell (chain : HostReady buffers before ready)
    (old : cell < before.nextCell)
    (separate : ∀ view ∈ before.i32ArrayViews, cell ≠ view.root) :
    ready.cellEntry? cell = before.cellEntry? cell := by
  induction chain with
  | nil => rfl
  | cons initialized rest ih =>
      refine (ih ?_ ?_).trans (initialized.frame cell old separate)
      · rw [initialized.next]
        exact Nat.lt_of_lt_of_le old (Nat.le_add_right _ _)
      · intro view member
        obtain ⟨address, elements, views, _⟩ := initialized.storage
        rw [views] at member
        rcases List.mem_append.mp member with previous | fresh
        · exact separate view previous
        · simp only [List.mem_singleton] at fresh
          subst view
          exact Nat.ne_of_lt (Nat.lt_of_lt_of_le old (Nat.le_add_right _ _))

theorem HostReady.preserves_binding {id : Lanius.VarId} (chain : HostReady buffers before ready)
    (notBound : id ∉ buffers.map Buffer.binding) :
    ready.cellId? id = before.cellId? id := by
  induction chain with
  | nil => rfl
  | cons initialized rest ih =>
      simp only [List.map_cons, List.mem_cons, not_or] at notBound
      rw [ih notBound.2]
      simp [State.cellId?, initialized.locals, Ne.symm notBound.1]

theorem HostReady.preserves_local {id : Lanius.VarId} (chain : HostReady buffers before ready)
    (initial : Lanius.Properties.StateWellFormed before)
    (notBound : id ∉ buffers.map Buffer.binding)
    (read : before.local? id = some value)
    (separate : ∀ cell, before.cellId? id = some cell →
      ∀ view ∈ before.i32ArrayViews, cell ≠ view.root) :
    ready.local? id = some value := by
  have binding := chain.preserves_binding notBound
  cases lookup : before.cellId? id with
  | none => simp [State.local?, lookup] at read
  | some cell =>
      cases found : before.cellEntry? cell with
      | none => simp [State.local?, lookup, State.cell?, found] at read
      | some entry =>
          have old := Lanius.Properties.found_cell_is_below_next before cell entry initial found
          have kept := chain.preserves_cell old (separate cell lookup)
          simpa only [State.local?, binding, lookup, Option.bind_some, State.cell?, kept] using read

theorem HostReady.preserves_view (chain : HostReady buffers before ready)
    (member : view ∈ before.i32ArrayViews) : view ∈ ready.i32ArrayViews := by
  induction chain with
  | nil => exact member
  | cons initialized rest ih =>
      apply ih
      obtain ⟨address, elements, views, _⟩ := initialized.storage
      rw [views]
      exact List.mem_append_left _ member

theorem HostReady.head_read (chain : HostReady (buffer :: buffers) before ready)
    (notBound : buffer.binding ∉ buffers.map Buffer.binding) :
    ready.local? buffer.binding =
      some (.slice (.scalar (.signed .i32)) (before.nextCell + 2) [] 0 buffer.count) := by
  cases chain with
  | cons initialized rest =>
      apply rest.preserves_local initialized.registry.wellFormed notBound initialized.local
      intro cell lookup view member
      have identity : cell = before.nextCell := by
        simpa [State.cellId?, initialized.locals] using lookup.symm
      subst cell
      intro same
      obtain ⟨values, _, found⟩ := initialized.registry.storage member
      rw [← same, initialized.binding] at found
      cases found

/-- Every allocated buffer can be read through its actual local binding after
the entire sequence, provided the source does not shadow a buffer name. -/
theorem HostReady.buffer {buffer : Buffer} (chain : HostReady buffers before ready)
    (names : (buffers.map Buffer.binding).Nodup) (member : buffer ∈ buffers) :
    ∃ view ∈ ready.i32ArrayViews, view.length = buffer.count ∧
      ready.local? buffer.binding =
        some (.slice (.scalar (.signed .i32)) view.root view.projections 0 view.length) := by
  induction chain with
  | nil => simp at member
  | cons initialized rest ih =>
      simp only [List.map_cons, List.nodup_cons] at names
      rename_i head start allocated tail finish
      rcases List.mem_cons.mp member with same | member
      · subst buffer
        have read := (HostReady.cons initialized rest).head_read names.1
        obtain ⟨address, elements, views, stored, length, typed⟩ := initialized.storage
        refine ⟨{ address, root := start.nextCell + 2, projections := [], length := head.count },
          rest.preserves_view ?_, rfl, read⟩
        rw [views]
        exact List.mem_append_right _ (List.mem_singleton_self _)
      · exact ih names.2 member

theorem HostReady.pointer {buffer : Buffer} (program : Program)
    (chain : HostReady buffers before ready) (registry : Registry ready)
    (names : (buffers.map Buffer.binding).Nodup) (member : buffer ∈ buffers) :
    ∃ address after, Evaluates program ready (.i32SliceDataPtr (.local buffer.binding)) (.pointer address) after ∧
      address ≠ Lanius.Memory.null ∧ Registry after ∧
      after.cells = ready.cells ∧ after.locals = ready.locals ∧
      after.i32ArrayViews = ready.i32ArrayViews ∧ after.nextCell = ready.nextCell ∧
      after.heap.remaining = ready.heap.remaining ∧ after.world = ready.world := by
  obtain ⟨view, registered, length, read⟩ := chain.buffer names member
  obtain ⟨after, evaluated, nonnull, valid, cells, locals, views, next, remaining, world⟩ :=
    registry.evaluatesPointer program registered buffer.binding read
  exact ⟨view.address, after, evaluated, nonnull, valid, cells, locals, views, next, remaining, world⟩

structure DistinctNames (sequence : Sequence) : Type where
  proof : (sequence.buffers.map Buffer.binding).Nodup

def Sequence.distinctNames? (sequence : Sequence) : Option (DistinctNames sequence) :=
  if proof : (sequence.buffers.map Buffer.binding).Nodup then some ⟨proof⟩ else none

theorem HostReady.remaining (chain : HostReady buffers before ready) :
    ready.heap.remaining = before.heap.remaining.map (fun available => available - byteCount buffers) := by
  induction chain with
  | nil => simp [byteCount]
  | cons initialized rest ih =>
      rw [ih, initialized.remaining]
      simp only [Option.map_map, Function.comp_def, Nat.sub_sub, byteCount]

theorem HostReady.world (chain : HostReady buffers before ready) :
    ready.world = { before.world with calls := before.world.calls ++ List.replicate buffers.length .alloc } := by
  induction chain with
  | nil => simp
  | cons initialized rest ih =>
      rw [ih, initialized.world]
      simp [Lanius.World.record, List.replicate_succ, List.append_assoc]

theorem HostReady.nextCell (chain : HostReady buffers before ready) :
    ready.nextCell = before.nextCell + 3 * buffers.length := by
  induction chain with
  | nil => simp
  | cons initialized rest ih =>
      rw [ih, initialized.next]
      simp [List.length_cons, Nat.mul_add, Nat.add_assoc, Nat.add_comm, Nat.add_left_comm]

/-- Execute all guarded allocations under one initial byte budget. The
continuation is reached inside buffer scopes and outside pointer scopes. -/
theorem hostSequence_executes
    {program : Program} {function : Function}
    (steps : List Step) (before : State) (continuation : Stmt)
    (completion : Completion) (post : Lanius.World.State → Prop)
    (functionFound : program.function? function.id = some function)
    (parametersBound : ∀ count, ∃ bindings, bindParameters function.parameters
      [.unsigned .usize (count * 4), .unsigned .usize 4] = some bindings)
    (noBody : function.body = none) (host : function.external = some (.host .alloc))
    (initial : Registry before)
    (room : ∀ available, before.heap.remaining = some available → byteCount (steps.map Step.buffer) ≤ available)
    (continuationRun : ∀ ready, HostReady (steps.map Step.buffer) before ready → Registry ready →
      Prefix.Reaches program before (hostStatement function.id steps continuation) ready continuation →
      ∃ after, Executes program ready continuation completion after ∧ post after.world) :
    ∃ after, Executes program before (hostStatement function.id steps continuation) completion after ∧
      post after.world := by
  induction steps generalizing before with
  | nil => exact continuationRun before .nil initial .here
  | cons step steps ih =>
      have firstRoom : ∀ available, before.heap.remaining = some available → step.buffer.count * 4 ≤ available := by
        intro available found
        have := room available found
        simp only [List.map_cons, byteCount] at this
        omega
      obtain ⟨bindings, boundParameters⟩ := parametersBound step.buffer.count
      obtain ⟨allocated, executed, initialized⟩ :=
        step.initializes functionFound boundParameters noBody host initial firstRoom
      have restRoom : ∀ available, allocated.heap.remaining = some available → byteCount (steps.map Step.buffer) ≤ available := by
        intro available found
        rw [initialized.remaining] at found
        cases budget : before.heap.remaining with
        | none => simp [budget] at found
        | some capacity =>
            have enough := room capacity budget
            simp only [List.map_cons, byteCount] at enough
            simp only [budget, Option.map_some, Option.some.injEq] at found
            omega
      obtain ⟨after, continued, satisfied⟩ := ih allocated initialized.registry restRoom
        (fun ready chain registry reached => continuationRun ready (.cons initialized chain) registry
          (.letUninitialized (.sequence executed reached)))
      exact ⟨restoreLocals before after, executesLetUninitialized (executesSequence executed continued), satisfied⟩

structure CheckedAllocator (program : Program) where
  function : Function
  found : program.function? function.id = some function
  noBody : function.body = none
  host : function.external = some (.host .alloc)
  parametersBound : ∀ count, ∃ bindings, bindParameters function.parameters
    [.unsigned .usize (count * 4), .unsigned .usize 4] = some bindings

def checkAllocator? (program : Program) (id : FunctionId) : Option (CheckedAllocator program) :=
  match found : program.function? id with
  | none => none
  | some function =>
      if shape : function.body = none ∧ function.external = some (.host .alloc) ∧
          function.parameters.length = 2 then
        some ⟨function, by
          have identity : function.id = id := by
            simpa using (List.find?_some found)
          simpa only [identity] using found,
          shape.1, shape.2.1, by
            intro count
            simp only [bindParameters, shape.2.2, List.length_cons, List.length_nil,
              Nat.reduceAdd, BEq.rfl, ite_true]
            exact ⟨_, rfl⟩⟩
      else none

theorem CheckedAllocator.executes (allocator : CheckedAllocator program)
    (sequence : Sequence) (before : State) (completion : Completion)
    (post : Lanius.World.State → Prop)
    (initial : Registry before)
    (room : ∀ available, before.heap.remaining = some available → byteCount sequence.buffers ≤ available)
    (continuationRun : ∀ ready, HostReady sequence.buffers before ready → Registry ready →
      Prefix.Reaches program before (sequence.statement allocator.function.id) ready sequence.continuation →
      ∃ after, Executes program ready sequence.continuation completion after ∧ post after.world) :
    ∃ after, Executes program before (sequence.statement allocator.function.id) completion after ∧
      post after.world :=
  hostSequence_executes sequence.steps before sequence.continuation completion post
    allocator.found allocator.parametersBound allocator.noBody allocator.host initial room continuationRun

end Lanius.Extraction.Allocation
