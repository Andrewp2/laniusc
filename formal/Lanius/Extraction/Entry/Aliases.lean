import Lanius.Extraction.Entry.Pointers
import Lanius.Extraction.Entry.Arguments

namespace Lanius.Extraction.Entry.Pointers

open Lanius.Core Lanius.Semantics Lanius.Memory

def Available (pointers : List Pointer) (state : State) : Prop :=
  ∀ pointer ∈ pointers, pointer.Ready state

theorem Available.transport (ready : Available pointers before) (frame : Frame before after) :
    Available pointers after := fun pointer member => (ready pointer member).transport frame

structure Alias where
  name : Lanius.VarId
  source : Pointer

/-- Shadowed names are removed, never silently retained as ready slices. -/
def Alias.available (alias : Alias) (pointers : List Pointer) : List Pointer :=
  .localValue alias.name :: pointers.filter (fun pointer => pointer.name != alias.name)

theorem Alias.bindAvailable (alias : Alias) (ready : Available pointers state)
    (registry : Allocation.Registry state)
    (bound : (Pointer.localValue alias.name).Ready (state.bindLocal alias.name value)) :
    Available (alias.available pointers) (state.bindLocal alias.name value) := by
  intro pointer member
  rcases List.mem_cons.mp member with equal | member
  · subst pointer; exact bound
  · obtain ⟨member, different⟩ := List.mem_filter.mp member
    have different : alias.name ≠ pointer.name := by simpa [ne_comm] using different
    apply (ready pointer member).bindOther registry alias.name value
    cases pointer <;> exact different

def aliasesStatement : List Alias → Stmt → Stmt
  | [], continuation => continuation
  | alias :: rest, continuation =>
      .letLocal alias.name (.scalar .rawPtr) alias.source.expression
        (aliasesStatement rest continuation)

def aliasesAvailable : List Alias → List Pointer → List Pointer
  | [], pointers => pointers
  | alias :: rest, pointers => aliasesAvailable rest (alias.available pointers)

def AliasesSupported : List Alias → List Pointer → Prop
  | [], _ => True
  | alias :: rest, pointers => alias.source ∈ pointers ∧ AliasesSupported rest (alias.available pointers)

instance aliasesSupportedDecidable (aliases : List Alias) (pointers : List Pointer) : Decidable (AliasesSupported aliases pointers) :=
  match aliases with
  | [] => isTrue trivial
  | alias :: rest =>
      have : Decidable (AliasesSupported rest (alias.available pointers)) :=
        aliasesSupportedDecidable rest (alias.available pointers)
      inferInstanceAs (Decidable (alias.source ∈ pointers ∧ AliasesSupported rest (alias.available pointers)))

structure AliasFrame (aliases : List Alias) (before after : State) : Prop where
  world : after.world = before.world
  remaining : after.heap.remaining = before.heap.remaining
  views : after.i32ArrayViews = before.i32ArrayViews
  locals : ∀ name, name ∉ aliases.map Alias.name → after.local? name = before.local? name
  sliceAlias : ∀ alias ∈ aliases, (aliases.map Alias.name).Nodup →
    ∀ binding, alias.source = .slice binding → binding ∉ aliases.map Alias.name →
    ∀ view ∈ before.i32ArrayViews,
      before.local? binding = some (.slice (.scalar (.signed .i32)) view.root view.projections 0 view.length) →
      after.local? alias.name = some (.pointer view.address)

/-- In particular, the argument-count local survives initialization provided
neither the buffer declarations nor pointer aliases shadow it. -/
theorem AliasFrame.allocatedLocal (retained : AliasFrame aliases allocated after)
    (history : Allocation.HostReady buffers before allocated)
    (initial : Lanius.Properties.StateWellFormed before)
    (empty : before.i32ArrayViews = []) (name : Lanius.VarId)
    (notBuffer : name ∉ buffers.map Allocation.Buffer.binding)
    (notAlias : name ∉ aliases.map Alias.name) (read : before.local? name = some value) :
    after.local? name = some value := by
  rw [retained.locals name notAlias]
  exact history.preserves_local initial notBuffer read (by simp [empty])

theorem aliasesExecute (aliases : List Alias) (program : Program) (before : State)
    (pointers : List Pointer) (continuation : Stmt) (completion : Completion)
    (post : Lanius.World.State → Prop) (registry : Allocation.Registry before)
    (ready : Available pointers before) (supported : AliasesSupported aliases pointers)
    (continuationRun : ∀ middle, Allocation.Registry middle →
      Available (aliasesAvailable aliases pointers) middle →
      AliasFrame aliases before middle →
      Prefix.Reaches program before (aliasesStatement aliases continuation) middle continuation →
      ∃ after, Executes program middle continuation completion after ∧ post after.world) :
    ∃ after, Executes program before (aliasesStatement aliases continuation) completion after ∧
      post after.world := by
  induction aliases generalizing before pointers with
  | nil =>
      exact continuationRun before registry ready
        ⟨rfl, rfl, rfl, (fun _ _ => rfl), (by intro alias member; simp at member)⟩ .here
  | cons alias rest ih =>
      obtain ⟨address, queried, evaluated, nonnull, valid, frame, resolved⟩ :=
        alias.source.evaluates program registry (ready _ supported.1)
      have read : (queried.bindLocal alias.name (.pointer address)).local? alias.name =
          some (.pointer address) := by
        have fresh := Lanius.Properties.bindCell_finds_fresh_cell queried alias.name
          (some (.pointer address)) valid.wellFormed
        simp only [State.bindLocal, State.local?, State.cellId?, State.bindCell,
          List.find?_cons, beq_self_eq_true]
        exact congrArg (fun cell => cell.bind Cell.value) fresh
      have available := alias.bindAvailable (ready.transport frame) valid ⟨address, read, nonnull⟩
      obtain ⟨after, continued, satisfied⟩ := ih
        (queried.bindLocal alias.name (.pointer address)) (alias.available pointers)
        (valid.bindLocal _ _) available supported.2 (by
          intro middle middleValid middleAvailable retained reached
          apply continuationRun middle middleValid middleAvailable ?_ (.letLocal evaluated reached)
          refine ⟨retained.world.trans frame.world, retained.remaining.trans frame.remaining,
            retained.views.trans frame.views, ?_, ?_⟩
          · intro name absent
            have different : alias.name ≠ name := by
              intro equal
              exact absent (by simp [equal])
            have tailAbsent : name ∉ rest.map Alias.name := by
              intro member
              exact absent (List.mem_cons_of_mem _ member)
            exact (retained.locals name tailAbsent).trans
              ((Lanius.Separation.bindLocal_preserves_other_local valid.wellFormed different).trans
                (frame.localRead name))
          · intro selected member names binding source unshadowed view present originalRead
            have distinct := List.nodup_cons.mp names
            have notTail : binding ∉ rest.map Alias.name := by
              intro member
              exact unshadowed (List.mem_cons_of_mem _ member)
            rcases List.mem_cons.mp member with rfl | member
            · have selectedAddress : address = view.address :=
                Pointer.Resolves.sliceAddress (source ▸ resolved) registry present originalRead
              exact (retained.locals selected.name distinct.1).trans (selectedAddress ▸ read)
            · have different : alias.name ≠ binding := by
                intro same
                exact unshadowed (by simp [same])
              have keptRead := (Lanius.Separation.bindLocal_preserves_other_local
                (value := Value.pointer address) valid.wellFormed different).trans
                ((frame.localRead binding).trans originalRead)
              exact retained.sliceAlias selected member distinct.2 binding source notTail view
                (by simpa only [State.bindLocal, State.bindCell, frame.views] using present) keptRead)
      exact ⟨restoreLocals queried after, executesLetLocal evaluated continued, satisfied⟩

structure Preparation where
  aliases : List Alias
  continuation : Stmt

def Preparation.statement (preparation : Preparation) : Stmt :=
  aliasesStatement preparation.aliases preparation.continuation

structure Preparation.Supported (preparation : Preparation) (pointers : List Pointer) : Type where
  aliases : AliasesSupported preparation.aliases pointers

def Preparation.checkSupported? (preparation : Preparation) (pointers : List Pointer) :
    Option (preparation.Supported pointers) :=
  if aliases : AliasesSupported preparation.aliases pointers then
    some ⟨aliases⟩
  else none

theorem availableOfAllocations (history : Allocation.HostReady buffers before ready)
    (names : (buffers.map Allocation.Buffer.binding).Nodup) :
    Available (buffers.map (fun buffer => Pointer.slice buffer.binding)) ready := by
  intro pointer member
  obtain ⟨buffer, bufferMember, rfl⟩ := List.mem_map.mp member
  obtain ⟨view, viewMember, _, read⟩ := history.buffer names bufferMember
  exact ⟨view, viewMember, read⟩

theorem Preparation.executes (preparation : Preparation) (program : Program) (before : State)
    (pointers : List Pointer) (completion : Completion) (post : Lanius.World.State → Prop)
    (registry : Allocation.Registry before) (ready : Available pointers before)
    (supported : AliasesSupported preparation.aliases pointers)
    (continuationRun : ∀ middle, Allocation.Registry middle →
      Available (aliasesAvailable preparation.aliases pointers) middle →
      AliasFrame preparation.aliases before middle →
      Prefix.Reaches program before preparation.statement middle preparation.continuation →
      ∃ after, Executes program middle preparation.continuation completion after ∧ post after.world) :
    ∃ after, Executes program before preparation.statement completion after ∧ post after.world := by
  apply aliasesExecute preparation.aliases program before pointers preparation.continuation
    completion post registry ready supported continuationRun

/-- Match the whole alias prefix without searching past missing bindings. -/
def checkPreparation? : (count : Nat) → (source : Stmt) →
    Option (Source.CheckedStatement Preparation.statement source)
  | 0, source => some ⟨⟨[], source⟩, rfl⟩
  | count + 1, source => do
      let binding ← checkBinding? source
      let rest ← checkPreparation? count binding.locals.continuation
      pure ⟨⟨⟨binding.locals.name, binding.locals.source⟩ :: rest.locals.aliases, rest.locals.continuation⟩,
        binding.exactSource.trans (congrArg
          (Stmt.letLocal binding.locals.name (.scalar .rawPtr) binding.locals.source.expression)
          rest.exactSource)⟩

/-- The real entry prefix, from argc through guarded allocations and aliases.
No intermediate successful execution or non-null pointer is assumed. -/
theorem executeEntry (entry : CheckedArguments program source)
    (allocator : Allocation.CheckedAllocator program) (sequence : Allocation.Sequence)
    (allocationSource : entry.entry.continuation = sequence.statement allocator.function.id)
    (preparation : Preparation) (pointerSource : sequence.continuation = preparation.statement)
    (names : (sequence.buffers.map Allocation.Buffer.binding).Nodup)
    (supported : preparation.Supported (sequence.buffers.map (fun buffer => Pointer.slice buffer.binding)))
    (before : State) (completion : Completion) (post : Lanius.World.State → Prop)
    (wellFormed : Lanius.Properties.StateWellFormed before) (empty : before.i32ArrayViews = [])
    (enough : 1 < before.world.arguments.length) (bounded : before.world.arguments.length < 2 ^ 31)
    (room : ∀ available, before.heap.remaining = some available → Allocation.byteCount sequence.buffers ≤ available)
    (continuationRun : ∀ middle, Allocation.Registry middle →
      Available (aliasesAvailable preparation.aliases
        (sequence.buffers.map (fun buffer => Pointer.slice buffer.binding))) middle →
      (∃ allocated, Allocation.HostReady sequence.buffers (entry.entry.ready before) allocated ∧
        AliasFrame preparation.aliases allocated middle) →
      Prefix.Reaches program before source middle preparation.continuation →
      ∃ after, Executes program middle preparation.continuation completion after ∧ post after.world) :
    ∃ after, Executes program before source completion after ∧ post after.world := by
  apply entry.allocate allocator sequence allocationSource before completion post wellFormed empty enough bounded room
  intro ready history registry allocatedReached
  obtain ⟨after, executed, satisfied⟩ := preparation.executes program ready _ completion post
    registry (availableOfAllocations history names) supported.aliases
    (fun middle valid available retained reached => continuationRun middle valid available ⟨ready, history, retained⟩
      (allocatedReached.trans (by simpa only [pointerSource] using reached)))
  exact ⟨after, pointerSource.symm ▸ executed, satisfied⟩

end Lanius.Extraction.Entry.Pointers
