import Lanius.Extraction.OutputPacking.Loop
import Lanius.Extraction.ExtractorContract

namespace Lanius.Extraction.OutputPacking

open Lanius Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.Memory

/-- Exact stdout after an observed packing-loop execution. The packed buffer
and its encoding are derived, not assumed. The intervening frame permits the
source's `output_size` local binding but no changes to existing cell contents,
the heap, host world, or registered views. -/
theorem stdout_after_packing
    (program : Program) (memory : LoopMemory) (locals : LoopLocals)
    (before packed ready after : State) (function : Function) (arguments : List Expr)
    (bindings : List (VarId × Value)) (view : I32ArrayView) (result : Value)
    (initial : LoopInvariant memory locals [] before)
    (loop : Executes program before locals.loop .next packed)
    (frame : StoreEffect CellSet.empty packed ready)
    (validViews : ∀ view ∈ before.i32ArrayViews, I32ArrayViewBlockWellFormed before.heap view)
    (distinctViews : before.i32ArrayViews.Pairwise fun left right => left.address ≠ right.address)
    (member : view ∈ before.i32ArrayViews)
    (viewRoot : view.root = memory.workspaceCell) (viewPath : view.projections = [])
    (argumentsResult : Lanius.CallContracts.ArgumentsEvaluateTo program ready arguments
      [.pointer view.address, .unsigned .usize memory.bytes.length] ready)
    (functionFound : program.function? function.id = some function)
    (parametersBound : bindParameters function.parameters
      [.pointer view.address, .unsigned .usize memory.bytes.length] = some bindings)
    (noBody : function.body = none)
    (host : function.external = some (.host .writeStdout))
    (actual : Evaluates program ready (.call function.id arguments) result after) :
    result = Lanius.World.i32Result memory.bytes.length ∧
      after.world = {
        before.world with
        standardOutput := before.world.standardOutput ++ memory.bytes
        calls := before.world.calls ++ [.writeStdout]
      } := by
  obtain ⟨_, complete, effect⟩ := packing_loop_sound program memory locals [] memory.bytes
    before packed (by simp) initial loop
  have packedContents := complete.complete_contents
  have old : memory.workspaceCell < packed.nextCell :=
    complete.wellFormed.cellIdsBelowNext _ (List.mem_of_find?_eq_some packedContents)
  have readyContents := (frame.oldCells memory.workspaceCell old (by simp [CellSet.empty])).trans
    packedContents
  have buffer : readCellProjection ready view.root view.projections =
      .ok (.array (pack memory.bytes ++ signedI32Values memory.tail)) := by
    simp [viewRoot, viewPath, readCellProjection, readyContents, projectedValue]
  have encoding : encodeI32Array (pack memory.bytes ++ signedI32Values memory.tail) =
      .ok ((memory.bytes ++ List.replicate (padding memory.bytes.length) 0) ++
        memory.tail.flatMap i32Bytes) := by
    rw [encodeI32Array_append, encode_pack, encodeSignedI32Values]
  have readyWF : HeapWellFormed ready.heap := by
    rw [frame.heap]
    exact complete.wellFormed.heapWellFormed
  have views : ready.i32ArrayViews = before.i32ArrayViews := frame.views.trans effect.views
  have disjoint := i32Views_disjoint_of_distinct_addresses
    initial.wellFormed.heapWellFormed validViews distinctViews
  have conclusion := ExtractorContract.packed_stdout_call_sound memory.bytes
    (signedI32Values memory.tail) _ argumentsResult functionFound parametersBound noBody host
    readyWF (by simpa [views] using disjoint) (by simpa [views] using member)
    buffer encoding actual
  simpa only [frame.world, effect.world] using conclusion

end Lanius.Extraction.OutputPacking
