import Lanius.Extraction.Allocation.Refresh
import Lanius.Extraction.Host.Representable
import Lanius.Extraction.Allocation.Transport
import Lanius.CallContracts.Host
import Lanius.Extraction.Input.Unpacking
import Lanius.Semantics.I32Views.Refresh
import Lanius.Semantics.I32Views.Registry

namespace Lanius.Extraction.Host

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.CallContracts

/-- Source-level host calls retain lexical bindings and non-view cells.
Raw array contents may be refreshed, and host-world changes are explicit in
the call theorem. This deliberately makes no blanket cell-identity claim. -/
structure Frame (before after : State) : Prop where
  locals : after.locals = before.locals
  views : after.i32ArrayViews = before.i32ArrayViews
  next : after.nextCell = before.nextCell
  remaining : after.heap.remaining = before.heap.remaining
  nonViews : ∀ cell, (∀ view ∈ before.i32ArrayViews, cell ≠ view.root) →
    after.cellEntry? cell = before.cellEntry? cell
  representable : RepresentableViews after

/-- Functional preservation for the views outside a host operation's write
range. Disjointness and i32 representability are explicit, separate from the
structural registry that makes synchronization safe. -/
def PreservesViews (before after : State) (untouched : I32ArrayView → Prop) : Prop :=
  before.i32ArrayViews.Pairwise I32ViewRangesDisjoint →
    ∀ kept ∈ before.i32ArrayViews, untouched kept → ∀ words,
    readCellProjection before kept.root kept.projections = .ok (.array (signedI32Values words)) →
    (∀ word ∈ words, -2147483648 ≤ word ∧ word ≤ 2147483647) →
    after.cellEntry? kept.root = some { id := kept.root, value := some (.array (signedI32Values words)) }

theorem Frame.preservesLocal (frame : Frame before after) (initial : Allocation.Registry before)
    {id : Lanius.VarId} (read : before.local? id = some value)
    (notArray : ∀ elements, value ≠ .array elements) : after.local? id = some value := by
  rw [State.local?, Option.bind_eq_some_iff] at read
  obtain ⟨cell, binding, stored⟩ := read
  have separate : ∀ view ∈ before.i32ArrayViews, cell ≠ view.root := by
    intro view member same
    obtain ⟨values, _, contents⟩ := initial.storage member
    have found : before.cell? cell = some (.array (signedI32Values values)) := by
      simp only [State.cell?, same, contents, Option.bind_some]
    rw [found] at stored
    exact notArray _ (Option.some.inj stored).symm
  have afterBinding : after.cellId? id = some cell := by
    simpa only [State.cellId?, frame.locals] using binding
  rw [State.local?, afterBinding]
  simpa only [Option.bind_some, State.cell?, frame.nonViews cell separate] using stored

/-- A service that leaves the byte heap unchanged executes from the registry.
It may inspect synchronized bytes. Both synchronization passes are derived;
the host-specific equation describes its result and world changes. -/
theorem evaluatesReadOnly
    (initial : Allocation.Registry before)
    (argumentsResult : ArgumentsEvaluateTo program caller arguments values before)
    (functionFound : program.function? function.id = some function)
    (parametersBound : bindParameters function.parameters values = some bindings)
    (noBody : function.body = none) (host : function.external = some (.host service))
    (call : ∀ ready, syncI32ViewsToHeap before = .ok ready →
      Lanius.World.call ready.heap ready.world service values = .returned result ready.heap world) :
    ∃ after, Evaluates program caller (.call function.id arguments) result after ∧
      Allocation.Registry after ∧ Frame before after ∧ after.world = world := by
  obtain ⟨ready, synced, readyRegistry, cells, locals, views, next, remaining, readyWorld⟩ := initial.synchronize
  obtain ⟨after, refreshed, afterRegistry, heap, afterViews, afterNext, afterLocals, afterWorld, nonViews⟩ :=
    (readyRegistry.withWorld world).refresh
  refine ⟨after, evaluatesHostCallReturned argumentsResult functionFound parametersBound noBody host synced
    (call ready synced) refreshed, afterRegistry, ?_, afterWorld⟩
  refine ⟨afterLocals.trans locals, afterViews.trans views, afterNext.trans next, ?_, ?_,
    representableAfterRefresh (readyRegistry.withWorld world) refreshed⟩
  · exact (congrArg (fun heap => heap.remaining) heap).trans remaining
  · intro cell apart
    have kept := nonViews cell (fun view member => apart view (by simpa only [views] using member))
    simpa only [State.cellEntry?, cells] using kept

/-- A disjoint, representable array survives a byte-heap-preserving host call
exactly, including the synchronization round trip. Unlike `Frame`, this is
the functional-content guarantee needed to retain grammar/output buffers. -/
theorem readOnlyPreservesView
    (initial : Allocation.Registry before)
    (argumentsResult : ArgumentsEvaluateTo program caller arguments values before)
    (functionFound : program.function? function.id = some function)
    (parametersBound : bindParameters function.parameters values = some bindings)
    (noBody : function.body = none) (host : function.external = some (.host service))
    (call : ∀ ready, syncI32ViewsToHeap before = .ok ready →
      Lanius.World.call ready.heap ready.world service values = .returned result ready.heap world)
    (disjoint : before.i32ArrayViews.Pairwise I32ViewRangesDisjoint)
    (member : view ∈ before.i32ArrayViews)
    (contents : readCellProjection before view.root view.projections = .ok (.array (signedI32Values words)))
    (range : ∀ word ∈ words, -2147483648 ≤ word ∧ word ≤ 2147483647)
    (actual : Evaluates program caller (.call function.id arguments) result after) :
    after.cellEntry? view.root = some { id := view.root, value := some (.array (signedI32Values words)) } := by
  obtain ⟨ready, heap, afterWorld, synced, called, refreshed⟩ :=
    evaluatesHostCallReturned_invert argumentsResult functionFound parametersBound noBody host actual
  have readyWorld := syncI32ViewsToHeap_preserves_world synced
  have readyViews := syncI32ViewsToHeapFrom_preserves_registry synced
  rw [call ready synced] at called
  cases called
  have encoded := encodeSignedI32Values words
  have loaded := syncI32ViewsToHeapFrom_reads_view initial.wellFormed.heapWellFormed
    disjoint member contents encoded synced
  obtain ⟨elements, read, length, _⟩ := initial.arrays view member
  rw [contents] at read
  cases read
  simp only [signedI32Values, List.length_map] at length
  have width := encodeI32Array_length encoded
  simp only [signedI32Values, List.length_map, length] at width
  rw [width] at loaded
  have decoded := Input.decode_i32_array_of_encoding words range encoded
  rw [length] at decoded
  exact syncI32ViewsFromHeapFrom_reads_view (before := { ready with world })
    (pending := ready.i32ArrayViews) (by simpa only [readyViews] using initial.distinct)
    (by simpa only [readyViews] using member) (initial.roots view member) loaded decoded refreshed

end Lanius.Extraction.Host
