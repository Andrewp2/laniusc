import Lanius.Semantics.I32Views.Allocation

namespace Lanius.Extraction.Allocation

open Lanius.Core Lanius.Semantics Lanius.Properties

/-! Primitive Core allocation sequences. The extractor's checked source uses
host allocator calls instead; `Source.lean` keeps that distinct representation
explicit. Applying this sequence proof to the source requires accounting for
the host synchronization passes and call-log effects, not just renaming calls.
-/

structure Buffer where
  binding : VarId
  count : Nat

def Buffer.initializer (buffer : Buffer) : Expr :=
  .i32SliceFromRawParts
    (.alloc (.value (.unsigned .usize (buffer.count * 4))) (.value (.unsigned .usize 4)))
    (.value (.signed .i32 buffer.count))

def statement (buffers : List Buffer) (continuation : Stmt) : Stmt :=
  match buffers with
  | [] => continuation
  | buffer :: rest => .letLocal buffer.binding (.slice (.scalar (.signed .i32)))
      buffer.initializer (statement rest continuation)

def byteCount (buffers : List Buffer) : Nat :=
  match buffers with
  | [] => 0
  | buffer :: rest => buffer.count * 4 + byteCount rest

/-- Records each allocation's resources before entering the next lexical scope.
The relation does not assume any expression or statement execution. -/
inductive Ready : List Buffer → State → State → Prop where
  | nil : Ready [] state state
  | cons (resources : I32AllocationResources before buffer.count allocated)
      (rest : Ready buffers
        (allocated.bindLocal buffer.binding
          (.slice (.scalar (.signed .i32)) before.nextCell [] 0 buffer.count)) ready) :
      Ready (buffer :: buffers) before ready

theorem Ready.wellFormed (chain : Ready buffers before ready)
    (initial : StateWellFormed before) : StateWellFormed ready := by
  induction chain with
  | nil => exact initial
  | cons resources rest ih =>
      exact ih (bindLocal_preserves_well_formed _ _ _ resources.wellFormed)

theorem Ready.world (chain : Ready buffers before ready) : ready.world = before.world := by
  induction chain with
  | nil => rfl
  | cons resources rest ih => exact ih.trans resources.world

/-- The registry remains valid as a whole, including buffers allocated before
this sequence and every newly appended buffer. -/
theorem Ready.validViews (chain : Ready buffers before ready)
    (initial : ∀ view ∈ before.i32ArrayViews, I32ArrayViewBlockWellFormed before.heap view) :
    ∀ view ∈ ready.i32ArrayViews, I32ArrayViewBlockWellFormed ready.heap view := by
  induction chain with
  | nil => exact initial
  | cons resources rest ih =>
      apply ih
      obtain ⟨address, elements, views, block, _⟩ := resources.storage
      intro view member
      simp only [State.bindLocal, State.bindCell] at member ⊢
      rw [views] at member
      rcases List.mem_append.mp member with old | fresh
      · exact resources.viewsPreserved view old (initial view old)
      · simp only [List.mem_singleton] at fresh
        subst view
        exact block

theorem Ready.remaining (chain : Ready buffers before ready) :
    ready.heap.remaining = before.heap.remaining.map (fun capacity => capacity - byteCount buffers) := by
  induction chain with
  | nil => simp [byteCount]
  | cons resources rest ih =>
      simp only [State.bindLocal, State.bindCell] at ih
      rw [ih]
      rw [resources.remaining]
      simp only [Option.map_map, Function.comp_def, Nat.sub_sub, byteCount]

/-- A single initial budget suffices for the whole nested allocation sequence.
The continuation runs inside all the buffer scopes, not after they are closed. -/
theorem executes (program : Program) (buffers : List Buffer) (before : State)
    (continuation : Stmt) (completion : Completion) (post : Lanius.World.State → Prop)
    (wellFormed : StateWellFormed before)
    (room : ∀ available, before.heap.remaining = some available → byteCount buffers ≤ available)
    (continuationRun : ∀ ready, Ready buffers before ready →
      ∃ after, Executes program ready continuation completion after ∧ post after.world) :
    ∃ after, Executes program before (statement buffers continuation) completion after ∧ post after.world := by
  induction buffers generalizing before with
  | nil => exact continuationRun before .nil
  | cons buffer buffers ih =>
      have firstRoom : ∀ available, before.heap.remaining = some available → buffer.count * 4 ≤ available := by
        intro available found
        have := room available found
        simp only [byteCount] at this
        omega
      obtain ⟨address, allocated, elements, evaluated, valid, views, block, preserved,
          cells, length, typed, next, locals, world, remaining⟩ :=
        evaluatesAllocatedI32Slice_resources program before buffer.count wellFormed firstRoom
      have resources : I32AllocationResources before buffer.count allocated :=
        ⟨⟨address, elements, views, block, cells, length, typed⟩,
          valid, preserved, next, locals, world, remaining⟩
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
      obtain ⟨after, executed, satisfied⟩ := ih bound
        (bindLocal_preserves_well_formed _ _ _ valid) restRoom
        (fun ready chain => continuationRun ready (.cons resources chain))
      exact ⟨restoreLocals allocated after,
        executesLetLocal evaluated executed, satisfied⟩

end Lanius.Extraction.Allocation
