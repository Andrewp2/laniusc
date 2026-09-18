import Lanius.Extraction.Host.Representable
import Lanius.Extraction.Host.Layout

namespace Lanius.Extraction.Host

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

/-- The native-memory facts a read-only helper carries to its caller. Fresh
borrowed views are allowed; existing registrations and the allocation budget
remain available. Registry and word-range preservation are conclusions. -/
structure MemoryFrame (before after : State) : Prop where
  registry : Allocation.Registry before → Allocation.Registry after
  representable : Allocation.Registry before → RepresentableViews before → RepresentableViews after
  views : ∃ fresh, after.i32ArrayViews = before.i32ArrayViews ++ fresh
  remaining : after.heap.remaining = before.heap.remaining
  layout : ViewLayout before → ViewLayout after

theorem MemoryFrame.refl (state : State) : MemoryFrame state state :=
  ⟨id, fun _ values => values, ⟨[], (List.append_nil _).symm⟩, rfl, id⟩

theorem MemoryFrame.trans (first : MemoryFrame before middle) (second : MemoryFrame middle after) :
    MemoryFrame before after := by
  obtain ⟨left, leftEq⟩ := first.views
  obtain ⟨right, rightEq⟩ := second.views
  exact ⟨fun initial => second.registry (first.registry initial),
    fun initial values => second.representable (first.registry initial) (first.representable initial values),
    ⟨left ++ right, by rw [rightEq, leftEq, List.append_assoc]⟩,
    second.remaining.trans first.remaining, fun initial => second.layout (first.layout initial)⟩

theorem MemoryFrame.bindLocal (state : State) (id : VarId) (value : Value) :
    MemoryFrame state (state.bindLocal id value) :=
  ⟨fun initial => initial.bindLocal id value,
    fun initial values => values.bindLocal initial id value,
    ⟨[], (List.append_nil _).symm⟩, rfl,
    fun initial => initial.frame ⟨rfl, rfl⟩ (Nat.le_succ _)⟩

theorem MemoryFrame.enterCall (state : State) (bindings : List (VarId × Value)) :
    MemoryFrame state (Lanius.Separation.enterCall state bindings) := by
  refine ⟨fun initial => initial.enterCall bindings,
    fun initial values => values.enterCall initial bindings, ⟨[], ?_⟩, ?_,
    fun initial => initial.frame (HeapFrame.ofStoreEffect (enterCall_effect state bindings))
      (enterCall_effect state bindings).nextCell⟩
  · simpa using (enterCall_effect state bindings).views
  · exact congrArg (fun heap => heap.remaining) (enterCall_effect state bindings).heap

theorem MemoryFrame.restoreLocals (frame : MemoryFrame before after) (caller : State)
    (wellFormed : StateWellFormed (Lanius.Semantics.restoreLocals caller after)) :
    MemoryFrame before (Lanius.Semantics.restoreLocals caller after) :=
  ⟨fun initial => (frame.registry initial).restoreLocals caller wellFormed,
    frame.representable, frame.views, frame.remaining,
    fun initial => (frame.layout initial).frame ⟨rfl, rfl⟩ (Nat.le_refl _)⟩

theorem MemoryFrame.unchanged (effect : CellEffect CellSet.empty before after)
    (frame : HeapFrame before after) : MemoryFrame before after :=
  ⟨fun initial => initial.unchanged effect frame,
    fun initial values => values.transport initial effect frame (fun _ _ impossible => False.elim impossible),
    ⟨[], by simpa using frame.views⟩, congrArg (fun heap => heap.remaining) frame.heap,
    fun initial => initial.frame frame effect.nextCell⟩

theorem MemoryFrame.borrowed (resources : I32BorrowedResources before count after)
    (wellFormed : StateWellFormed after) : MemoryFrame before after := by
  obtain ⟨address, elements, views, rest⟩ := resources.storage
  exact ⟨fun initial => initial.borrowed resources wellFormed,
    fun initial values => values.borrowed initial resources,
    ⟨[ { address, root := before.nextCell, projections := [], length := count } ], views⟩,
    resources.remaining, fun initial => initial.borrowed resources wellFormed⟩

theorem MemoryFrame.scalar (effect : CellEffect (CellSet.singleton cell) before after)
    (frame : HeapFrame before after)
    (contents : before.cellEntry? cell = some { id := cell, value := some (.signed type value) }) :
    MemoryFrame before after := by
  have notWritten (initial : Allocation.Registry before) (view : I32ArrayView)
      (member : view ∈ before.i32ArrayViews) (changed : CellSet.singleton cell view.root) : False := by
    change view.root = cell at changed
    exact initial.notScalar member (changed.symm ▸ contents)
  refine ⟨fun initial => initial.transport effect frame (fun view member changed =>
      False.elim (notWritten initial view member changed)),
    fun initial values => values.transport initial effect frame (fun view member changed =>
      False.elim (notWritten initial view member changed)), ⟨[], ?_⟩, ?_,
    fun initial => initial.frame frame effect.nextCell⟩
  · simpa using frame.views
  · exact congrArg (fun heap => heap.remaining) frame.heap

/-- A same-sized typed array update retains native registration. Its range
obligation concerns the mathematical update, not another execution. -/
theorem MemoryFrame.array (effect : CellEffect (CellSet.singleton cell) before after)
    (frame : HeapFrame before after)
    (original : before.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values values)) })
    (updated : after.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values result)) })
    (length : result.length = values.length)
    (range : (∀ word ∈ values, -2147483648 ≤ word ∧ word ≤ 2147483647) →
      ∀ word ∈ result, -2147483648 ≤ word ∧ word ≤ 2147483647) : MemoryFrame before after := by
  refine ⟨?_, ?_, ⟨[], by simpa using frame.views⟩,
    congrArg (fun heap => heap.remaining) frame.heap,
    fun initial => initial.frame frame effect.nextCell⟩
  · intro initial
    apply initial.transport effect frame
    intro view member changed
    change view.root = cell at changed
    have old : before.cellEntry? view.root = some {
        id := view.root, value := some (.array (signedI32Values values)) } := changed.symm ▸ original
    refine ⟨signedI32Values result, ?_, ?_, ?_⟩
    · simp [readCellProjection, initial.roots view member, changed, updated, projectedValue]
    · simpa only [signedI32Values, List.length_map, length] using initial.arrayLength member old
    · intro element present
      obtain ⟨word, _, rfl⟩ := List.mem_map.mp present
      exact ⟨word, rfl⟩
  · intro initial representable
    apply representable.transport initial effect frame
    intro view member changed words contents
    change view.root = cell at changed
    have old : before.cellEntry? view.root = some {
        id := view.root, value := some (.array (signedI32Values values)) } := changed.symm ▸ original
    have actual : after.cellEntry? view.root = some {
        id := view.root, value := some (.array (signedI32Values result)) } := changed.symm ▸ updated
    have equal : signedI32Values result = signedI32Values words := by
      simpa only [Option.some.injEq, Cell.mk.injEq, true_and, Value.array.injEq] using actual.symm.trans contents
    exact signedI32Values_injective equal ▸ range (representable view member values old)

theorem MemoryFrame.arraySet (effect : CellEffect (CellSet.singleton cell) before after)
    (frame : HeapFrame before after)
    (original : before.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values values)) })
    (updated : after.cellEntry? cell = some {
      id := cell, value := some (.array (signedI32Values (values.set index replacement))) })
    (bounded : -2147483648 ≤ replacement ∧ replacement ≤ 2147483647) : MemoryFrame before after := by
  apply MemoryFrame.array effect frame original updated (List.length_set ..)
  intro range word member
  rcases List.mem_or_eq_of_mem_set member with old | equal
  · exact range word old
  · exact equal.symm ▸ bounded

theorem MemoryFrame.arrayAndScalar
    (effect : CellEffect (CellSet.union (CellSet.singleton arrayCell) (CellSet.singleton scalarCell)) before after)
    (frame : HeapFrame before after)
    (original : before.cellEntry? arrayCell = some { id := arrayCell, value := some (.array (signedI32Values values)) })
    (updated : after.cellEntry? arrayCell = some { id := arrayCell, value := some (.array (signedI32Values result)) })
    (length : result.length = values.length)
    (scalar : before.cellEntry? scalarCell = some { id := scalarCell, value := some (.signed type value) })
    (range : (∀ word ∈ values, -2147483648 ≤ word ∧ word ≤ 2147483647) →
      ∀ word ∈ result, -2147483648 ≤ word ∧ word ≤ 2147483647) : MemoryFrame before after := by
  refine ⟨fun initial => initial.updateArrayAndScalar effect frame original updated length scalar,
    ?_, ⟨[], by simpa using frame.views⟩, congrArg (fun heap => heap.remaining) frame.heap,
    fun initial => initial.frame frame effect.nextCell⟩
  intro initial representable
  apply representable.transport initial effect frame
  intro view member changed words contents
  rcases changed with atArray | atScalar
  · change view.root = arrayCell at atArray
    have old : before.cellEntry? view.root = some {
        id := view.root, value := some (.array (signedI32Values values)) } := atArray.symm ▸ original
    have actual : after.cellEntry? view.root = some {
        id := view.root, value := some (.array (signedI32Values result)) } := atArray.symm ▸ updated
    have equal : signedI32Values result = signedI32Values words := by
      simpa only [Option.some.injEq, Cell.mk.injEq, true_and, Value.array.injEq] using actual.symm.trans contents
    exact signedI32Values_injective equal ▸ range (representable view member values old)
  · change view.root = scalarCell at atScalar
    exact False.elim (initial.notScalar member (atScalar.symm ▸ scalar))

end Lanius.Extraction.Host
