import Lanius.Extraction.Allocation.Registry

namespace Lanius.Extraction.Allocation

open Lanius.Core Lanius.Semantics

/-- Resources at each source initializer, retained across its local binding.
This relation contains no assumed allocation or synchronization executions. -/
inductive HostReady : List Buffer → State → State → Prop where
  | nil : HostReady [] state state
  | cons (valid : Registry allocated)
      (world : allocated.world = Lanius.World.record before.world .alloc)
      (remaining : allocated.heap.remaining = before.heap.remaining.map (fun available => available - buffer.count * 4))
      (next : allocated.nextCell = before.nextCell + 1)
      (locals : allocated.locals = before.locals)
      (frame : ∀ cell, cell < before.nextCell → (∀ view ∈ before.i32ArrayViews, cell ≠ view.root) →
        allocated.cellEntry? cell = before.cellEntry? cell)
      (storage : ∃ address elements,
        allocated.i32ArrayViews = before.i32ArrayViews ++
          [{ address, root := before.nextCell, projections := [], length := buffer.count }] ∧
        readCellProjection allocated before.nextCell [] = .ok (.array elements) ∧
        elements.length = buffer.count ∧
        ∀ element ∈ elements, ∃ value, element = .signed .i32 value)
      (rest : HostReady buffers (allocated.bindLocal buffer.binding
        (.slice (.scalar (.signed .i32)) before.nextCell [] 0 buffer.count)) ready) :
      HostReady (buffer :: buffers) before ready

theorem HostReady.preserves_cell (chain : HostReady buffers before ready)
    (old : cell < before.nextCell)
    (separate : ∀ view ∈ before.i32ArrayViews, cell ≠ view.root) :
    ready.cellEntry? cell = before.cellEntry? cell := by
  induction chain with
  | nil => rfl
  | cons valid world remaining next locals frame storage rest ih =>
      refine (ih ?_ ?_).trans ?_
      · simp only [State.bindLocal, State.bindCell]
        rw [next]
        exact Nat.lt_succ_of_lt (Nat.lt_succ_of_lt old)
      · intro view member
        obtain ⟨address, elements, views, _⟩ := storage
        simp only [State.bindLocal, State.bindCell] at member
        rw [views] at member
        rcases List.mem_append.mp member with previous | fresh
        · exact separate view previous
        · simp only [List.mem_singleton] at fresh
          subst view
          exact Nat.ne_of_lt old
      · refine (Lanius.Properties.bindCell_preserves_old_cell _ _ _ _ ?_).trans (frame cell old separate)
        rw [next]
        exact Nat.lt_succ_of_lt old

theorem HostReady.preserves_binding {id : Lanius.VarId} (chain : HostReady buffers before ready)
    (notBound : id ∉ buffers.map Buffer.binding) :
    ready.cellId? id = before.cellId? id := by
  induction chain with
  | nil => rfl
  | cons valid world remaining next locals frame storage rest ih =>
      simp only [List.map_cons, List.mem_cons, not_or] at notBound
      rw [ih notBound.2]
      simp [State.cellId?, State.bindLocal, State.bindCell, Ne.symm notBound.1, locals]

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
  | cons valid world remaining next locals frame storage rest ih =>
      apply ih
      obtain ⟨address, elements, views, _⟩ := storage
      simp only [State.bindLocal, State.bindCell]
      rw [views]
      exact List.mem_append_left _ member

theorem HostReady.head_read (chain : HostReady (buffer :: buffers) before ready)
    (notBound : buffer.binding ∉ buffers.map Buffer.binding) :
    ready.local? buffer.binding =
      some (.slice (.scalar (.signed .i32)) before.nextCell [] 0 buffer.count) := by
  cases chain with
  | cons valid world remaining next locals frame storage rest =>
      apply rest.preserves_local (valid.bindLocal _ _).wellFormed notBound
      · have fresh := Lanius.Properties.bindCell_finds_fresh_cell _ buffer.binding
          (some (.slice (.scalar (.signed .i32)) before.nextCell [] 0 buffer.count)) valid.wellFormed
        simp only [State.bindLocal, State.local?, State.cellId?, State.bindCell,
          List.find?_cons, beq_self_eq_true]
        exact congrArg (fun entry => entry.bind Cell.value) fresh
      · intro cell lookup view member
        simp [State.cellId?, State.bindLocal, State.bindCell] at lookup
        subst cell
        exact Ne.symm (Nat.ne_of_lt (valid.root_lt_next member))

/-- Every allocated buffer can be read through its actual local binding after
the entire sequence, provided the source does not shadow a buffer name. -/
theorem HostReady.buffer {buffer : Buffer} (chain : HostReady buffers before ready)
    (names : (buffers.map Buffer.binding).Nodup) (member : buffer ∈ buffers) :
    ∃ view ∈ ready.i32ArrayViews, view.length = buffer.count ∧
      ready.local? buffer.binding =
        some (.slice (.scalar (.signed .i32)) view.root view.projections 0 view.length) := by
  induction chain with
  | nil => simp at member
  | cons valid world remaining next locals frame storage rest ih =>
      simp only [List.map_cons, List.nodup_cons] at names
      rename_i allocated tail finish head start
      rcases List.mem_cons.mp member with same | member
      · subst buffer
        have read := (HostReady.cons valid world remaining next locals frame storage rest).head_read names.1
        obtain ⟨address, elements, views, stored, length, typed⟩ := storage
        refine ⟨{ address, root := start.nextCell, projections := [], length := head.count },
          rest.preserves_view ?_, rfl, read⟩
        simp only [State.bindLocal, State.bindCell]
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
  | cons valid world remaining next locals frame storage rest ih =>
      simp only [State.bindLocal, State.bindCell] at ih
      rw [ih, remaining]
      simp only [Option.map_map, Function.comp_def, Nat.sub_sub, byteCount]

theorem HostReady.world (chain : HostReady buffers before ready) :
    ready.world = { before.world with calls := before.world.calls ++ List.replicate buffers.length .alloc } := by
  induction chain with
  | nil => simp
  | cons valid world remaining next locals frame storage rest ih =>
      simp only [State.bindLocal, State.bindCell] at ih
      rw [ih, world]
      simp [Lanius.World.record, List.replicate_succ, List.append_assoc]

theorem HostReady.nextCell (chain : HostReady buffers before ready) :
    ready.nextCell = before.nextCell + 2 * buffers.length := by
  induction chain with
  | nil => simp
  | cons valid world remaining next locals frame storage rest ih =>
      simp only [State.bindLocal, State.bindCell] at ih
      rw [ih, next]
      simp [List.length_cons, Nat.mul_add, Nat.add_assoc, Nat.add_comm, Nat.add_left_comm]

/-- Execute the actual nested host-call sequence under one initial budget.
The continuation receives the derived buffer resources inside all scopes. -/
theorem hostSequence_executes
    {program : Program} {function : Function}
    (buffers : List Buffer) (before : State) (continuation : Stmt)
    (completion : Completion) (post : Lanius.World.State → Prop)
    (functionFound : program.function? function.id = some function)
    (parametersBound : ∀ count, ∃ bindings, bindParameters function.parameters
      [.unsigned .usize (count * 4), .unsigned .usize 4] = some bindings)
    (noBody : function.body = none) (host : function.external = some (.host .alloc))
    (initial : Registry before)
    (room : ∀ available, before.heap.remaining = some available → byteCount buffers ≤ available)
    (continuationRun : ∀ ready, HostReady buffers before ready → Registry ready →
      ∃ after, Executes program ready continuation completion after ∧ post after.world) :
    ∃ after, Executes program before (hostStatement function.id buffers continuation) completion after ∧
      post after.world := by
  induction buffers generalizing before with
  | nil => exact continuationRun before .nil initial
  | cons buffer buffers ih =>
      have firstRoom : ∀ available, before.heap.remaining = some available → buffer.count * 4 ≤ available := by
        intro available found
        have := room available found
        simp only [byteCount] at this
        omega
      obtain ⟨bindings, boundParameters⟩ := parametersBound buffer.count
      obtain ⟨allocated, evaluated, valid, world, remaining, next, locals, frame, storage⟩ :=
        Registry.allocate buffer functionFound boundParameters noBody host initial firstRoom
      let bound := allocated.bindLocal buffer.binding
        (.slice (.scalar (.signed .i32)) before.nextCell [] 0 buffer.count)
      have restRoom : ∀ available, bound.heap.remaining = some available → byteCount buffers ≤ available := by
        intro available found
        change allocated.heap.remaining = some available at found
        rw [remaining] at found
        cases budget : before.heap.remaining with
        | none => simp [budget] at found
        | some capacity =>
            have enough := room capacity budget
            simp only [byteCount] at enough
            simp only [budget, Option.map_some, Option.some.injEq] at found
            omega
      obtain ⟨after, executed, satisfied⟩ := ih bound (valid.bindLocal _ _) restRoom
        (fun ready chain registry => continuationRun ready
          (.cons valid world remaining next locals frame storage chain) registry)
      exact ⟨restoreLocals allocated after, executesLetLocal evaluated executed, satisfied⟩

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
      ∃ after, Executes program ready sequence.continuation completion after ∧ post after.world) :
    ∃ after, Executes program before (sequence.statement allocator.function.id) completion after ∧
      post after.world :=
  hostSequence_executes sequence.buffers before sequence.continuation completion post
    allocator.found allocator.parametersBound allocator.noBody allocator.host initial room continuationRun

end Lanius.Extraction.Allocation
