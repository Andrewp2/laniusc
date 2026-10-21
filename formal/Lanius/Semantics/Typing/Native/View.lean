import Lanius.Semantics.Typing.Target
import Lanius.Semantics.Typing.Native.Array
import Lanius.Semantics.Typing.Projection.Frame
import Lanius.Semantics.StmtList
import Lanius.Memory.Read
import Lanius.Memory.Allocation

namespace Lanius.Semantics

open Lanius Lanius.Core Lanius.Typing Lanius.Memory

/-- Enough declared storage for native-view synchronization to be safe.
    This is not byte coherence or exclusive ownership: readable regions may
    overlap. Those stronger properties require their own invariants. -/
structure State.I32ViewsAccessible (state : State) (program : Program) (types : CellTypes) : Prop where
  store : state.CellsHaveTypes program types
  unique : HeapBlockBasesUnique state.heap
  views : ∀ view ∈ state.i32ArrayViews,
    CellTargetValid program types state view.root view.projections
      (.array (.scalar (.signed .i32)) view.length) ∧
    state.heap.Readable view.address (view.length * 4)

/-- Exact agreement between a live array's encoded contents and native bytes. -/
def I32ArrayView.Coherent (view : I32ArrayView) (state : State) : Prop :=
  ∃ elements bytes, readCellProjection state view.root view.projections = .ok (.array elements) ∧
    encodeI32Array elements = .ok bytes ∧ state.heap.loadBytes view.address (view.length * 4) = .ok bytes

structure State.I32ViewsCoherent (state : State) (program : Program) (types : CellTypes) : Prop
    extends state.I32ViewsAccessible program types where
  bytes : ∀ view ∈ state.i32ArrayViews, view.Coherent state

/-- One native registration per canonical root/path; local aliases can still
    refer to that same registration. The mapper's reuse guard enforces this. -/
def State.I32ViewsUnique (state : State) : Prop :=
  (state.i32ArrayViews.map (fun view => (view.root, view.projections))).Nodup

def I32ArrayView.Disjoint (left right : I32ArrayView) : Prop :=
  left.address + left.length * 4 ≤ right.address ∨ right.address + right.length * 4 ≤ left.address

/-- Independently replaceable cell targets. Native ranges need not be disjoint
    when refreshing: all views read from the same fixed heap snapshot. -/
def I32ArrayView.TargetApart (left right : I32ArrayView) : Prop :=
  left.root ≠ right.root ∨ ProjectionApart left.projections right.projections

theorem I32ArrayView.TargetApart.symm {left right : I32ArrayView} (apart : left.TargetApart right) :
    right.TargetApart left := apart.elim (fun different => Or.inl (Ne.symm different)) (fun paths => Or.inr paths.symm)

theorem State.I32ViewsAccessible.targetsApart {state : State} (access : state.I32ViewsAccessible program types)
    (unique : state.I32ViewsUnique) : state.i32ArrayViews.Pairwise I32ArrayView.TargetApart := by
  have distinct : state.i32ArrayViews.Pairwise (fun left right =>
      (left.root, left.projections) ≠ (right.root, right.projections)) := List.pairwise_map.mp unique
  apply distinct.imp_of_mem
  intro left right leftMember rightMember different
  by_cases sameRoot : left.root = right.root
  · obtain ⟨leftType, leftDeclared, leftPath, _⟩ := (access.views left leftMember).1
    obtain ⟨rightType, rightDeclared, rightPath, _⟩ := (access.views right rightMember).1
    rw [sameRoot] at leftDeclared
    have sameType : leftType = rightType := Option.some.inj (leftDeclared.symm.trans rightDeclared)
    subst rightType
    rcases leftPath.i32ArrayApart rightPath with samePath | apart
    · exact (different (Prod.ext sameRoot samePath)).elim
    · exact Or.inr apart
  · exact Or.inl sameRoot

theorem I32ArrayView.Coherent.cellEffect {view : I32ArrayView} {before after : State} {root : Value}
    (coherent : view.Coherent before) (effect : CellEffect before after cell updated)
    (apart : cell ≠ view.root ∨ ProjectionApart destination view.projections)
    (stored : before.cellEntry? cell = some { id := cell, value := some root })
    (written : replaceProjectedValue root destination replacement = .ok updated) : view.Coherent after := by
  obtain ⟨elements, bytes, read, encoded, loaded⟩ := coherent
  exact ⟨elements, bytes, effect.projectedRead apart stored written read, encoded,
    by simpa only [effect.heap] using loaded⟩

theorem State.I32ViewsAccessible.cellEffect {before after : State}
    (access : before.I32ViewsAccessible program types) (effect : CellEffect before after cell updated)
    (declared : types cell = some type) (typed : ValueHasType program updated type) :
    after.I32ViewsAccessible program types :=
  ⟨access.store.cellEffect effect declared typed, by simpa only [effect.heap] using access.unique,
    fun view member => ⟨(access.views view (by simpa only [effect.views] using member)).1.cellEffect effect,
      by simpa only [effect.heap] using (access.views view (by simpa only [effect.views] using member)).2⟩⟩

/-- Byte-only host effects preserve declared cells and all native targets.
    The world is unrestricted here; it is specified by the host contract. -/
theorem State.I32ViewsAccessible.bytesWrite {state : State} {heap : Heap} {world : World.State}
    (access : state.I32ViewsAccessible program types)
    (effect : BytesWrite state.heap heap address bytes) :
    ({ state with heap, world } : State).I32ViewsAccessible program types :=
  ⟨access.store, effect.unique, fun view member =>
    ⟨(access.views view member).1, effect.readable (access.views view member).2⟩⟩

private theorem flushViews (views : List I32ArrayView) (state : State)
    (store : state.CellsHaveTypes program types) (unique : HeapBlockBasesUnique state.heap)
    (valid : ∀ view ∈ views, CellTargetValid program types state view.root view.projections
      (.array (.scalar (.signed .i32)) view.length) ∧ state.heap.Readable view.address (view.length * 4)) :
    ∃ heap, syncI32ViewsToHeapFrom views state = .ok { state with heap } ∧
      HeapBlockBasesUnique heap ∧
      (∀ address count, state.heap.Readable address count → heap.Readable address count) ∧
      (∀ address count bytes, state.heap.loadBytes address count = .ok bytes →
        (∀ view ∈ views, view.address + view.length * 4 ≤ address ∨ address + count ≤ view.address) →
        heap.loadBytes address count = .ok bytes) ∧
      (views.Pairwise I32ArrayView.Disjoint → ∀ view ∈ views, view.Coherent { state with heap }) ∧
      (HeapBlocksBelowNext state.heap → HeapBlocksBelowNext heap) := by
  induction views generalizing state with
  | nil => exact ⟨state.heap, rfl, unique, fun _ _ read => read, fun _ _ _ read _ => read,
      (by intros _ view member; cases member), fun below => below⟩
  | cons view rest ih =>
    obtain ⟨target, readable⟩ := valid view (by simp)
    obtain ⟨value, read, typed⟩ := target.read store
    cases typed with
    | array elements element length elementsTyped =>
      obtain ⟨bytes, encoded, width⟩ := encodeI32Array_typed elementsTyped
      obtain ⟨written, stored, effect⟩ := Heap.storeBytes_of_readable bytes unique (by
        simpa only [Heap.Readable, width] using readable)
      obtain ⟨heap, flushed, finalUnique, retained, framed, coherent, bounded⟩ := ih { state with heap := written } store effect.unique
        (fun other member => ⟨(valid other (by simp [member])).1,
          effect.readable (valid other (by simp [member])).2⟩)
      refine ⟨heap, ?_, finalUnique, fun _ _ old => retained _ _ (effect.readable old), ?_, ?_,
        fun below => bounded (effect.below below)⟩
      · simpa only [syncI32ViewsToHeapFrom, read, length, bne_self_eq_false, Bool.false_eq_true, ↓reduceIte,
          encoded, stored] using flushed
      · intro address count data old apart
        exact framed address count data
          (effect.loadBytes_disjoint old (by simpa only [width] using apart view (by simp)))
          (fun other member => apart other (by simp [member]))
      · intro apart other member
        rcases List.mem_cons.mp member with rfl | member
        · refine ⟨elements, bytes, read, encoded, ?_⟩
          exact framed other.address (other.length * 4) bytes (by simpa only [width] using effect.loadBytes)
            (fun tailView member => Or.symm (List.rel_of_pairwise_cons apart member))
        · exact coherent (List.Pairwise.of_cons apart) other member

/-- Flush every registered view from live typed cells. Only heap contents
    change; all previous readable ranges and declared cells remain usable. -/
theorem State.I32ViewsAccessible.flush (access : state.I32ViewsAccessible program types) :
    ∃ heap, syncI32ViewsToHeap state = .ok { state with heap } ∧
      ({ state with heap } : State).I32ViewsAccessible program types ∧
      (∀ address count, state.heap.Readable address count → heap.Readable address count) ∧
      (HeapBlocksBelowNext state.heap → HeapBlocksBelowNext heap) := by
  obtain ⟨heap, flushed, unique, retained, _, _, bounded⟩ := flushViews state.i32ArrayViews state
    access.store access.unique access.views
  exact ⟨heap, flushed, ⟨access.store, unique, fun view member =>
    ⟨(access.views view member).1, retained _ _ (access.views view member).2⟩⟩, retained, bounded⟩

/-- Flushing distinct native ranges establishes exact byte/cell agreement.
    Aliased locals still share their root and registered view. -/
theorem State.I32ViewsAccessible.flushCoherent (access : state.I32ViewsAccessible program types)
    (apart : state.i32ArrayViews.Pairwise I32ArrayView.Disjoint) :
    ∃ heap, syncI32ViewsToHeap state = .ok { state with heap } ∧
      ({ state with heap } : State).I32ViewsCoherent program types ∧
      (∀ address count, state.heap.Readable address count → heap.Readable address count) ∧
      (HeapBlocksBelowNext state.heap → HeapBlocksBelowNext heap) := by
  obtain ⟨heap, flushed, unique, retained, _, coherent, bounded⟩ := flushViews state.i32ArrayViews state
    access.store access.unique access.views
  exact ⟨heap, flushed, ⟨⟨access.store, unique, fun view member =>
    ⟨(access.views view member).1, retained _ _ (access.views view member).2⟩⟩, coherent apart⟩, retained, bounded⟩

private theorem refreshViews (views : List I32ArrayView) (state : State)
    (access : state.I32ViewsAccessible program types)
    (registered : ∀ view ∈ views, view ∈ state.i32ArrayViews) :
    ∃ cells, syncI32ViewsFromHeapFrom views state = .ok { state with cells } ∧
      ({ state with cells } : State).I32ViewsAccessible program types ∧
      (∀ other, other.Coherent state → (∀ view ∈ views, view.TargetApart other) →
        other.Coherent { state with cells }) ∧
      (views.Pairwise I32ArrayView.TargetApart → ∀ view ∈ views, view.Coherent { state with cells }) := by
  induction views generalizing state with
  | nil => exact ⟨state.cells, rfl, access, fun _ coherent _ => coherent,
      by intros _ view member; cases member⟩
  | cons view rest ih =>
    obtain ⟨target, readable⟩ := access.views view (registered view (by simp))
    obtain ⟨bytes, loaded⟩ := readable.loadBytes
    obtain ⟨elements, decoded, elementsTyped⟩ := decodeI32Array_typed (program := program)
      (loadBytesFrom_spec loaded).1
    obtain ⟨rootType, declared, path, initialized⟩ := target
    obtain ⟨contents, present, rootTyped⟩ := access.store view.root rootType declared
    cases contents with
    | none => simp [State.cell?, present] at initialized
    | some root =>
      obtain ⟨next, updated, written, _, updatedTyped, readBack, replaced, effect⟩ := writeResolvedPlaceNative_typed
        (place := { root := view.root, projections := view.projections, value := none })
        rfl path rootTyped present elementsTyped
      have nextAccess := access.cellEffect effect declared updatedTyped
      obtain ⟨cells, refreshed, finalAccess, framed, coherent⟩ := ih next nextAccess (fun other member => by
        rw [effect.views]; exact registered other (by simp [member]))
      have same : ({ next with cells } : State) = { state with cells } := by
        cases state; cases next
        simp only [State.mk.injEq]
        exact ⟨effect.locals, trivial, effect.nextCell, effect.heap, effect.world, effect.views⟩
      rw [same] at refreshed finalAccess framed coherent
      refine ⟨cells, ?_, finalAccess, ?_, ?_⟩
      · simpa only [syncI32ViewsFromHeapFrom, loaded, decoded,
          show writeResolvedPlace state { root := view.root, projections := view.projections, value := none }
            (.array elements) = .ok next from written] using refreshed
      · intro other old apart
        exact framed other (old.cellEffect effect (apart view (by simp)) present replaced)
          (fun tailView member => apart tailView (by simp [member]))
      · intro apart other member
        rcases List.mem_cons.mp member with rfl | member
        · have ready : other.Coherent next := ⟨elements, bytes, readBack,
            encodeI32Array_decode (loadBytesFrom_spec loaded).1 decoded,
            by simpa only [effect.heap] using loaded⟩
          exact framed other ready (fun tailView member => (List.rel_of_pairwise_cons apart member).symm)
        · exact coherent (List.Pairwise.of_cons apart) other member

/-- Refresh live typed cells from readable native storage, including arbitrary
    host-written bytes. Other state fields are retained, and every registered
    target remains initialized, typed and readable for the next synchronization. -/
theorem State.I32ViewsAccessible.refresh (access : state.I32ViewsAccessible program types) :
    ∃ cells, syncI32ViewsFromHeap state = .ok { state with cells } ∧
      ({ state with cells } : State).I32ViewsAccessible program types ∧
      (state.I32ViewsUnique →
        ({ state with cells } : State).I32ViewsCoherent program types) := by
  obtain ⟨cells, refreshed, finalAccess, _, coherent⟩ := refreshViews state.i32ArrayViews state access (fun _ member => member)
  exact ⟨cells, refreshed, finalAccess, fun unique => ⟨finalAccess, coherent (access.targetsApart unique)⟩⟩

/-- Arbitrary host bytes establish full coherence when registered cell targets
    are independent. No decoder/write/synchronization success is assumed. -/
theorem State.I32ViewsAccessible.refreshCoherent (access : state.I32ViewsAccessible program types)
    (unique : state.I32ViewsUnique) :
    ∃ cells, syncI32ViewsFromHeap state = .ok { state with cells } ∧
      ({ state with cells } : State).I32ViewsCoherent program types := by
  obtain ⟨cells, refreshed, _, coherent⟩ := access.refresh
  exact ⟨cells, refreshed, coherent unique⟩

#print axioms State.I32ViewsAccessible.flush
#print axioms State.I32ViewsAccessible.flushCoherent
#print axioms State.I32ViewsAccessible.refresh
#print axioms State.I32ViewsAccessible.refreshCoherent
#print axioms State.I32ViewsAccessible.targetsApart
#print axioms State.I32ViewsAccessible.cellEffect

end Lanius.Semantics
