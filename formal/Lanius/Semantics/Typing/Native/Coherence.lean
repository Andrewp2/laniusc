import Lanius.Semantics.Typing.Native.View
import Lanius.Semantics.Typing.Projection.Identity
import Lanius.Memory.StoreSame

namespace Lanius.Semantics

open Lanius.Core Lanius.Typing Lanius.Memory

theorem I32ArrayView.Coherent.loadBytes {view : I32ArrayView} {state : State} (coherent : view.Coherent state)
    (read : readCellProjection state view.root view.projections = .ok (.array elements))
    (encoded : encodeI32Array elements = .ok bytes) :
    state.heap.loadBytes view.address (view.length * 4) = .ok bytes := by
  obtain ⟨actual, data, actualRead, actualEncoded, loaded⟩ := coherent
  have same : actual = elements := Value.array.inj (Except.ok.inj (actualRead.symm.trans read))
  subst actual
  have same : data = bytes := Except.ok.inj (actualEncoded.symm.trans encoded)
  simpa only [same] using loaded

theorem State.I32ViewsCoherent.withWorld {state : State} {world : World.State}
    (coherent : state.I32ViewsCoherent program types) :
    ({ state with world } : State).I32ViewsCoherent program types :=
  ⟨⟨coherent.store, coherent.unique, coherent.views⟩, coherent.bytes⟩

private theorem flush_same (unique : HeapBlockBasesUnique state.heap)
    (coherent : ∀ view ∈ views, view.Coherent state) : syncI32ViewsToHeapFrom views state = .ok state := by
  induction views with
  | nil => rfl
  | cons view rest ih =>
    obtain ⟨elements, bytes, read, encoded, loaded⟩ := coherent view (by simp)
    have width := (loadBytesFrom_spec loaded).1
    have length : elements.length = view.length := by
      have encodedWidth := encodeI32Array_length encoded
      omega
    have stored := Heap.storeBytes_same (pointer := view.address) (bytes := bytes) unique
      (by simpa only [width] using loaded)
    simpa only [syncI32ViewsToHeapFrom, read, length, bne_self_eq_false, Bool.false_eq_true,
      ↓reduceIte, encoded, stored] using ih (fun other member => coherent other (by simp [member]))

theorem State.I32ViewsCoherent.flush (coherent : state.I32ViewsCoherent program types) :
    syncI32ViewsToHeap state = .ok state := flush_same coherent.unique coherent.bytes

private theorem refresh_same (access : state.I32ViewsAccessible program types)
    (unique : (state.cells.map Cell.id).Nodup)
    (coherent : ∀ view ∈ views, view.Coherent state)
    (registered : ∀ view ∈ views, view ∈ state.i32ArrayViews) :
    syncI32ViewsFromHeapFrom views state = .ok state := by
  induction views with
  | nil => rfl
  | cons view rest ih =>
    obtain ⟨elements, bytes, read, encoded, loaded⟩ := coherent view (by simp)
    obtain ⟨value, actualRead, typed⟩ := (access.views view (registered view (by simp))).1.read access.store
    have same : value = .array elements := Except.ok.inj (actualRead.symm.trans read)
    subst value
    cases typed with
    | array elements element length elementsTyped =>
      have decoded := decodeI32Array_encode elementsTyped encoded
      have written := writeResolvedPlace_read_same (place := {
        root := view.root, projections := view.projections, value := none }) unique read
      simpa only [syncI32ViewsFromHeapFrom, loaded, decoded, written] using
        ih (fun other member => coherent other (by simp [member]))
          (fun other member => registered other (by simp [member]))

theorem State.I32ViewsCoherent.refresh (coherent : state.I32ViewsCoherent program types)
    (unique : (state.cells.map Cell.id).Nodup) : syncI32ViewsFromHeap state = .ok state :=
  refresh_same coherent.toI32ViewsAccessible unique coherent.bytes (fun _ member => member)

#print axioms State.I32ViewsCoherent.flush
#print axioms State.I32ViewsCoherent.refresh
#print axioms I32ArrayView.Coherent.loadBytes

end Lanius.Semantics
