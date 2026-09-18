import Lanius.Extraction.Host.ReadOnly
import Lanius.Memory.Store

namespace Lanius.Extraction.Host

open Lanius.Core Lanius.Semantics Lanius.Memory Lanius.Properties Lanius.CallContracts

/-- Bytes returned by a host input operation occupy exactly the prefix of
its refreshed packed words. The trailing bytes remain storage, not input. -/
structure Copied (view : I32ArrayView) (bytes : List UInt8) (state : State) : Prop where
  storage : ∃ words raw,
    state.cellEntry? view.root = some { id := view.root, value := some (.array (signedI32Values words)) } ∧
    words.length = view.length ∧ encodeI32Array (signedI32Values words) = .ok raw ∧
    raw.take bytes.length = bytes ∧ ∀ word ∈ words, -2147483648 ≤ word ∧ word ≤ 2147483647

/-- A later host call sees exactly the copied bytes after synchronizing the
packed words again. This closes the copy-to-open path without assuming a raw
heap image that may have become stale. -/
theorem Copied.loadAfterSync (copied : Copied view bytes before) (initial : Allocation.Registry before)
    (disjoint : before.i32ArrayViews.Pairwise I32ViewRangesDisjoint)
    (member : view ∈ before.i32ArrayViews) (synced : syncI32ViewsToHeap before = .ok ready) :
    ready.heap.loadBytes view.address bytes.length = .ok bytes := by
  obtain ⟨words, raw, contents, length, encoded, selected, range⟩ := copied.storage
  have read : readCellProjection before view.root view.projections = .ok (.array (signedI32Values words)) := by
    simp only [readCellProjection, contents, initial.roots view member, projectedValue]
  have loaded := syncI32ViewsToHeapFrom_reads_view initial.wellFormed.heapWellFormed disjoint member read encoded synced
  have capacity : bytes.length ≤ raw.length := by
    rw [← selected]
    simp only [List.length_take]
    exact Nat.min_le_right _ _
  simpa only [selected] using Heap.loadBytes_prefix loaded capacity

theorem copiedAfterRefresh (initial : Allocation.Registry ready)
    (member : view ∈ ready.i32ArrayViews) (capacity : bytes.length ≤ view.length * 4)
    (stored : ready.heap.storeBytes view.address bytes = .ok heap)
    (refreshed : syncI32ViewsFromHeap { ready with heap, world } = .ok after) :
    Copied view bytes after := by
  obtain ⟨raw, elements, loaded, decoded⟩ := syncI32ViewsFromHeapFrom_view_read member refreshed
  have contents := syncI32ViewsFromHeapFrom_reads_view initial.distinct member
    (initial.roots view member) loaded decoded refreshed
  have copiedPrefix := Heap.loadBytes_after_store initial.wellFormed.heapWellFormed stored
  have fromStorage := Heap.loadBytes_prefix loaded capacity
  have bytesEqual := Except.ok.inj (fromStorage.symm.trans copiedPrefix)
  obtain ⟨words, equal, length, range⟩ := Input.decode_i32_array_values decoded
  subst elements
  exact ⟨words, raw, contents, length, Input.encode_after_decode_i32_array decoded, bytesEqual, range⟩

/-- A successful host byte write preserves every disjoint, representable
array through both synchronization passes. -/
theorem copyPreservesView (initial : Allocation.Registry before)
    (synced : syncI32ViewsToHeap before = .ok ready)
    (stored : ready.heap.storeBytes scratch.address bytes = .ok heap)
    (refreshed : syncI32ViewsFromHeap { ready with heap, world } = .ok after)
    (capacity : bytes.length ≤ scratch.length * 4)
    (disjoint : before.i32ArrayViews.Pairwise I32ViewRangesDisjoint)
    (member : kept ∈ before.i32ArrayViews) (apart : I32ViewRangesDisjoint scratch kept)
    (contents : readCellProjection before kept.root kept.projections = .ok (.array (signedI32Values words)))
    (range : ∀ word ∈ words, -2147483648 ≤ word ∧ word ≤ 2147483647) :
    after.cellEntry? kept.root = some { id := kept.root, value := some (.array (signedI32Values words)) } := by
  have readyViews := syncI32ViewsToHeapFrom_preserves_registry synced
  have readyWF := syncI32ViewsToHeapFrom_preserves_heapWellFormed initial.wellFormed.heapWellFormed synced
  have encoded := encodeSignedI32Values words
  have loaded := syncI32ViewsToHeapFrom_reads_view initial.wellFormed.heapWellFormed disjoint member contents encoded synced
  obtain ⟨elements, read, length, _⟩ := initial.arrays kept member
  rw [contents] at read
  cases read
  simp only [signedI32Values, List.length_map] at length
  have width := encodeI32Array_length encoded
  simp only [signedI32Values, List.length_map, length] at width
  have keptRead := Heap.loadBytes_after_store_disjoint readyWF stored loaded (by
    rw [width]
    rcases apart with left | right
    · exact Or.inr (Nat.le_trans (Nat.add_le_add_left capacity _) left)
    · exact Or.inl right)
  rw [width] at keptRead
  have decoded := Input.decode_i32_array_of_encoding words range encoded
  rw [length] at decoded
  exact syncI32ViewsFromHeapFrom_reads_view (before := { ready with heap, world })
    (pending := ready.i32ArrayViews) (by simpa only [readyViews] using initial.distinct)
    (by simpa only [readyViews] using member) (initial.roots kept member) keptRead decoded refreshed

/-- Execute a host input service whose specified action stores a known byte
sequence. Both synchronization passes and the bounded raw write are derived
from the registry; no successful execution is supplied as a premise. -/
theorem evaluatesCopy (initial : Allocation.Registry before)
    (argumentsResult : ArgumentsEvaluateTo program caller arguments values before)
    (functionFound : program.function? function.id = some function)
    (parametersBound : bindParameters function.parameters values = some bindings)
    (noBody : function.body = none) (host : function.external = some (.host service))
    (member : view ∈ before.i32ArrayViews) (capacity : bytes.length ≤ view.length * 4)
    (call : ∀ heap copied, heap.storeBytes view.address bytes = .ok copied →
      Lanius.World.call heap before.world service values = .returned result copied world) :
    ∃ after, Evaluates program caller (.call function.id arguments) result after ∧
      Allocation.Registry after ∧ Frame before after ∧ after.world = world ∧ Copied view bytes after ∧
      PreservesViews before after (I32ViewRangesDisjoint view) := by
  obtain ⟨ready, synced, readyRegistry, cells, locals, views, next, remaining, readyWorld⟩ := initial.synchronize
  have readyMember : view ∈ ready.i32ArrayViews := by simpa only [views] using member
  obtain ⟨heap, stored⟩ := ready.heap.storeBytes_view_exists readyRegistry.wellFormed.heapWellFormed
    (readyRegistry.blocks view readyMember) capacity
  have preserved := storeBytes_preserves_i32_array_view_blocks (views := ready.i32ArrayViews)
    readyRegistry.wellFormed.heapWellFormed stored
  have changed : Allocation.Registry { ready with heap, world } :=
    ⟨⟨storeBytes_preserves_heap_well_formed readyRegistry.wellFormed.heapWellFormed stored,
      readyRegistry.wellFormed.cellIdsUnique, readyRegistry.wellFormed.cellIdsBelowNext,
      readyRegistry.wellFormed.localsReferenceCells⟩,
      fun kept present => preserved kept present (readyRegistry.blocks kept present),
      readyRegistry.roots, readyRegistry.distinct, readyRegistry.arrays, readyRegistry.addresses⟩
  obtain ⟨after, refreshed, afterRegistry, afterHeap, afterViews, afterNext, afterLocals, afterWorld, nonViews⟩ := changed.refresh
  refine ⟨after, evaluatesHostCallReturned argumentsResult functionFound parametersBound noBody host synced
    (by rw [readyWorld]; exact call ready.heap heap stored) refreshed,
    afterRegistry, ?_, afterWorld, copiedAfterRefresh readyRegistry readyMember capacity stored refreshed, ?_⟩
  · refine ⟨afterLocals.trans locals, afterViews.trans views, afterNext.trans next, ?_, ?_,
      representableAfterRefresh changed refreshed⟩
    · exact (congrArg (fun heap => heap.remaining) afterHeap).trans
        ((storeBytesFrom_remaining stored).trans remaining)
    · intro cell apart
      have kept := nonViews cell (fun kept present => apart kept (by simpa only [views] using present))
      simpa only [State.cellEntry?, cells] using kept
  · intro disjoint kept present apart words contents range
    exact copyPreservesView initial synced stored refreshed capacity disjoint present apart contents range

end Lanius.Extraction.Host
