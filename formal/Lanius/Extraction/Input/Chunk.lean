import Lanius.Extraction.Input.Read
import Lanius.Extraction.Input.Loop

namespace Lanius.Extraction.Input

open Lanius Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.Memory

/-- Ownership at the source's inner-loop entry. Scratch contents are
deliberately absent: the host-read theorem must supply them. -/
structure CopyEntry (locals : UnpackLocals) (outputCell packedCell cursorCell : CellId)
    (earlier untouched : List Int) (words count : Nat) (state : State) : Prop where
  wellFormed : StateWellFormed state
  capacity : count ≤ untouched.length
  bounded : earlier.length + untouched.length ≤ 2147483647
  output_cursor : outputCell ≠ cursorCell
  packed_output : packedCell ≠ outputCell
  packed_cursor : packedCell ≠ cursorCell
  outputLocal : state.local? locals.output = some
    (.slice (.scalar (.signed .i32)) outputCell [] 0 (earlier.length + untouched.length))
  outputContents : state.cellEntry? outputCell = some {
    id := outputCell, value := some (.array (signedI32Values (earlier ++ untouched))) }
  packedLocal : state.local? locals.packed = some
    (.slice (.scalar (.signed .i32)) packedCell [] 0 words)
  cursor : (Assertion.localPointsTo locals.cursor cursorCell
    (some (.signed .i32 0))).holds state
  total : state.local? locals.total = some (.signed .i32 earlier.length)
  limit : state.local? locals.length = some (.signed .i32 count)
  stable : ∀ localId, localId ∈ [locals.output, locals.packed, locals.total, locals.length] →
    ∀ cell, state.cellId? localId = some cell →
      ¬ (CellSet.union (CellSet.singleton outputCell) (CellSet.singleton cursorCell)) cell

/-- Compose a real Core host read with the actual source unpacking loop.
The scratch representation and copied bytes are derived from that read.
The intervening frame permits new count/cursor locals, not mutation of old
cells or the host world. Enclosing guards still establish `CopyEntry`. -/
theorem unpack_after_read
    (program : Program) (before afterArguments read ready : State)
    (function : Function) (arguments : List Expr) (bindings : List (VarId × Value))
    (view : I32ArrayView) (handleId : Int) (handle : World.FileHandle)
    (file : World.FileEntry) (request : Nat) (result : Value)
    (locals : UnpackLocals) (outputCell cursorCell : CellId) (earlier untouched : List Int)
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
    (actual : Evaluates program before (.call function.id arguments) result read)
    (readWellFormed : StateWellFormed read)
    (frame : StoreEffect CellSet.empty read ready)
    (entry : CopyEntry locals outputCell view.root cursorCell earlier untouched view.length
      ((file.bytes.drop handle.offset).take request).length ready) :
    let bytes := (file.bytes.drop handle.offset).take request
    result = World.i32Result bytes.length ∧ ∃ after,
      Executes program ready locals.loop .next after ∧ StateWellFormed after ∧
      after.cellEntry? outputCell = some {
        id := outputCell, value := some (.array (signedI32Values
          (earlier ++ bytes.map (fun byte => (byte.toNat : Int)) ++ untouched.drop bytes.length))) } ∧
      after.local? locals.cursor = some (.signed .i32 bytes.length) ∧
      after.world = {
        afterArguments.world with
        calls := afterArguments.world.calls ++ [.read]
        fileHandles := World.replaceHandle afterArguments.world.fileHandles {
          handle with offset := handle.offset + bytes.length }
      } := by
  dsimp only
  obtain ⟨storage, values, resultEq, readContents, encoded, sourceBytes, valuesLength, worldEq⟩ :=
    read_call_words program before afterArguments read function arguments bindings view handleId
      handle file request result argumentsResult functionFound parametersBound noBody host
      wellFormed distinct member wholeCell capacity handleFound readable fileFound actual
  let memory : UnpackMemory := {
    outputCell, packedCell := view.root, cursorCell, earlier, untouched, packedValues := values,
    storage, bytes := (file.bytes.drop handle.offset).take request,
    encoded, sourceBytes, capacity := entry.capacity, bounded := entry.bounded,
    output_cursor := entry.output_cursor, packed_output := entry.packed_output,
    packed_cursor := entry.packed_cursor
  }
  have old : view.root < read.nextCell :=
    readWellFormed.cellIdsBelowNext _ (List.mem_of_find?_eq_some readContents)
  have readyContents := (frame.oldCells view.root old (by simp [CellSet.empty])).trans readContents
  have initial : UnpackInvariant memory locals [] ready := by
    refine ⟨entry.wellFormed, entry.outputLocal, ?_, ?_, readyContents, entry.cursor,
      entry.total, entry.limit, entry.stable⟩
    · simpa [memory, copiedBuffer] using entry.outputContents
    · simpa [memory, valuesLength] using entry.packedLocal
  obtain ⟨after, executed, complete, effect⟩ :=
    executes_unpacking_loop program memory locals [] memory.bytes ready (by simp) initial
  refine ⟨resultEq, after, executed, complete.wellFormed, complete.outputContents,
    Assertion.localPointsTo_local _ _ _ _ complete.cursor, ?_⟩
  rw [effect.world, frame.world, worldEq]

end Lanius.Extraction.Input
