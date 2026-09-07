import Lanius.CallContracts.Host
import Lanius.World.FileRead
import Lanius.Semantics.I32Views.Registry
import Lanius.Semantics.I32Views.Refresh
import Lanius.Extraction.Input.Unpacking

namespace Lanius.Extraction.Input

open Lanius Lanius.Core Lanius.Semantics Lanius.Memory

/-- Source-level file-read correctness through both synchronization passes.
The returned language words encode the actual file bytes at the beginning of
the scratch buffer; unused scratch bytes are not mistaken for input. -/
theorem read_call_words
    (program : Program) (before afterArguments after : State)
    (function : Function) (arguments : List Expr) (bindings : List (VarId × Value))
    (view : I32ArrayView) (handleId : Int) (handle : World.FileHandle)
    (file : World.FileEntry) (request : Nat) (result : Value)
    (argumentsResult : CallContracts.ArgumentsEvaluateTo program before arguments
      [.signed .i32 handleId, .pointer view.address, .unsigned .usize request] afterArguments)
    (functionFound : program.function? function.id = some function)
    (parametersBound : bindParameters function.parameters
      [.signed .i32 handleId, .pointer view.address, .unsigned .usize request] = some bindings)
    (noBody : function.body = none) (host : function.external = some (.host .read))
    (wellFormed : HeapWellFormed afterArguments.heap)
    (distinct : afterArguments.i32ArrayViews.Pairwise fun left right => left.root ≠ right.root)
    (member : view ∈ afterArguments.i32ArrayViews) (wholeCell : view.projections = [])
    (capacity : request ≤ view.length * 4)
    (handleFound : afterArguments.world.handle? handleId = some handle)
    (readable : handle.readable = true)
    (fileFound : afterArguments.world.file? handle.path = some file)
    (actual : Evaluates program before (.call function.id arguments) result after) :
    let bytes := (file.bytes.drop handle.offset).take request
    ∃ storage values,
      result = World.i32Result bytes.length ∧
      after.cellEntry? view.root = some {
        id := view.root, value := some (.array (signedI32Values values)) } ∧
      encodeI32Array (signedI32Values values) = .ok storage ∧
      storage.take bytes.length = bytes ∧ values.length = view.length ∧
      after.world = {
        afterArguments.world with
        calls := afterArguments.world.calls ++ [.read]
        fileHandles := World.replaceHandle afterArguments.world.fileHandles {
          handle with offset := handle.offset + bytes.length }
      } := by
  dsimp only
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
  obtain ⟨resultEq, stored, worldEq⟩ :=
    World.read_call_returned_invert readyHandle readable readyFile called
  have readyMember : view ∈ ready.i32ArrayViews := by simpa only [readyRegistry] using member
  obtain ⟨storage, elements, loaded, decoded⟩ :=
    syncI32ViewsFromHeapFrom_view_read readyMember refreshed
  have contents := syncI32ViewsFromHeapFrom_reads_view
    (by simpa only [readyRegistry] using distinct) readyMember wholeCell loaded decoded refreshed
  have prefixRead := Heap.loadBytes_after_store readyWF stored
  have fromStorage := Heap.loadBytes_prefix loaded
    (Nat.le_trans (List.length_take_le request (file.bytes.drop handle.offset)) capacity)
  have bytesEq := Except.ok.inj (fromStorage.symm.trans prefixRead)
  obtain ⟨values, valuesEq, valuesLength⟩ := decode_i32_array_values decoded
  subst elements
  refine ⟨storage, values, resultEq, contents, encode_after_decode_i32_array decoded,
    bytesEq, valuesLength, ?_⟩
  have afterWorld := syncI32ViewsFromHeap_preserves_world refreshed
  change after.world = world at afterWorld
  rw [afterWorld, worldEq, readyWorld]

end Lanius.Extraction.Input
