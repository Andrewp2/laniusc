import Lanius.Extraction.Input.Read

namespace Lanius.Extraction.Input

open Lanius Lanius.Core Lanius.Semantics Lanius.Memory

/-- Reading one raw view preserves another disjoint, coherent whole-cell
view through both synchronization passes. This frames source/parser buffers
around the scratch read instead of assuming their contents survived. -/
theorem read_preserves_view
    (program : Program) (before afterArguments after : State)
    (function : Function) (arguments : List Expr) (bindings : List (VarId × Value))
    (scratch kept : I32ArrayView) (handleId : Int) (handle : World.FileHandle)
    (file : World.FileEntry) (request : Nat) (result : Value)
    (values : List Int)
    (argumentsResult : CallContracts.ArgumentsEvaluateTo program before arguments
      [.signed .i32 handleId, .pointer scratch.address, .unsigned .usize request] afterArguments)
    (functionFound : program.function? function.id = some function)
    (parametersBound : bindParameters function.parameters
      [.signed .i32 handleId, .pointer scratch.address, .unsigned .usize request] = some bindings)
    (noBody : function.body = none) (host : function.external = some (.host .read))
    (wellFormed : HeapWellFormed afterArguments.heap)
    (distinct : afterArguments.i32ArrayViews.Pairwise fun left right => left.root ≠ right.root)
    (disjoint : afterArguments.i32ArrayViews.Pairwise I32ViewRangesDisjoint)
    (keptMember : kept ∈ afterArguments.i32ArrayViews)
    (apart : I32ViewRangesDisjoint scratch kept)
    (wholeCell : kept.projections = []) (lengthMatches : values.length = kept.length)
    (contents : readCellProjection afterArguments kept.root kept.projections =
      .ok (.array (signedI32Values values)))
    (range : ∀ word ∈ values, -2147483648 ≤ word ∧ word ≤ 2147483647)
    (capacity : request ≤ scratch.length * 4)
    (handleFound : afterArguments.world.handle? handleId = some handle)
    (readable : handle.readable = true)
    (fileFound : afterArguments.world.file? handle.path = some file)
    (actual : Evaluates program before (.call function.id arguments) result after) :
    after.cellEntry? kept.root = some {
      id := kept.root, value := some (.array (signedI32Values values)) } := by
  let bytes := values.flatMap i32Bytes
  have encoded := encodeSignedI32Values values
  have coherent := decode_i32_array_of_encoding values range encoded
  rw [lengthMatches] at coherent
  obtain ⟨ready, heap, world, synced, called, refreshed⟩ :=
    CallContracts.evaluatesHostCallReturned_invert argumentsResult functionFound
      parametersBound noBody host actual
  have readyWorld := Properties.syncI32ViewsToHeap_preserves_world synced
  have readyRegistry := syncI32ViewsToHeapFrom_preserves_registry synced
  have readyWF := syncI32ViewsToHeapFrom_preserves_heapWellFormed wellFormed synced
  have readyHandle : ready.world.handle? handleId = some handle := by
    simpa only [readyWorld] using handleFound
  have readyFile : ready.world.file? handle.path = some file := by
    simpa only [readyWorld] using fileFound
  obtain ⟨_, stored, _⟩ := World.read_call_returned_invert readyHandle readable readyFile called
  have loaded := syncI32ViewsToHeapFrom_reads_view wellFormed disjoint keptMember contents encoded synced
  have width : bytes.length = kept.length * 4 := by
    simpa only [signedI32Values, List.length_map, lengthMatches] using Properties.encodeI32Array_length encoded
  have keptRead := Heap.loadBytes_after_store_disjoint readyWF stored loaded
    (show kept.address + bytes.length ≤ scratch.address ∨
      scratch.address + ((file.bytes.drop handle.offset).take request).length ≤ kept.address by
      have chunkBound := List.length_take_le request (file.bytes.drop handle.offset)
      rcases apart with before | after
      · exact Or.inr (Nat.le_trans (Nat.add_le_add_left (Nat.le_trans chunkBound capacity) _) before)
      · exact Or.inl (by simpa only [width] using after))
  rw [width] at keptRead
  exact syncI32ViewsFromHeapFrom_reads_view
    (by simpa only [readyRegistry] using distinct)
    (by simpa only [readyRegistry] using keptMember) wholeCell keptRead coherent refreshed

end Lanius.Extraction.Input
