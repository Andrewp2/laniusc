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

/-- Construct the host call from the completed packing invariant. Unlike
`stdout_after_packing`, this does not assume an observed successful call. -/
theorem stdout_from_completed_packing
    (program : Program) (memory : LoopMemory) (locals : LoopLocals)
    (packed ready : State) (function : Function) (arguments : List Expr)
    (bindings : List (VarId × Value)) (view : I32ArrayView)
    (complete : LoopInvariant memory locals memory.bytes packed)
    (frame : StoreEffect CellSet.empty packed ready)
    (validViews : ∀ view ∈ ready.i32ArrayViews, I32ArrayViewBlockWellFormed ready.heap view)
    (distinctViews : ready.i32ArrayViews.Pairwise fun left right => left.address ≠ right.address)
    (roots : ∀ view ∈ ready.i32ArrayViews, view.projections = [])
    (arrays : ∀ view ∈ ready.i32ArrayViews, ∃ elements,
      readCellProjection ready view.root view.projections = .ok (.array elements) ∧
      elements.length = view.length ∧
      ∀ element ∈ elements, ∃ value, element = .signed .i32 value)
    (member : view ∈ ready.i32ArrayViews)
    (viewRoot : view.root = memory.workspaceCell)
    (argumentsResult : Lanius.CallContracts.ArgumentsEvaluateTo program ready arguments
      [.pointer view.address, .unsigned .usize memory.bytes.length] ready)
    (functionFound : program.function? function.id = some function)
    (parametersBound : bindParameters function.parameters
      [.pointer view.address, .unsigned .usize memory.bytes.length] = some bindings)
    (noBody : function.body = none)
    (host : function.external = some (.host .writeStdout)) :
    ∃ after, Evaluates program ready (.call function.id arguments)
      (Lanius.World.i32Result memory.bytes.length) after ∧
      after.world = { packed.world with
        standardOutput := packed.world.standardOutput ++ memory.bytes
        calls := packed.world.calls ++ [.writeStdout] } := by
  have contents := complete.complete_contents
  have old := StateWellFormed.cell_lt_next_of_entry complete.wellFormed contents
  have readyContents := (frame.oldCells memory.workspaceCell old (by simp [CellSet.empty])).trans contents
  have buffer : readCellProjection ready view.root view.projections =
      .ok (.array (pack memory.bytes ++ signedI32Values memory.tail)) := by
    simp [viewRoot, roots view member, readCellProjection, readyContents, projectedValue]
  have readyWF : HeapWellFormed ready.heap := by
    rw [frame.heap]
    exact complete.wellFormed.heapWellFormed
  have disjoint := i32Views_disjoint_of_distinct_addresses readyWF validViews distinctViews
  obtain ⟨after, run, world, _⟩ := ExtractorContract.workspace_stdout_exists memory.bytes memory.tail
    argumentsResult functionFound parametersBound noBody host readyWF disjoint member buffer validViews roots arrays
  exact ⟨after, run, by simpa only [frame.world] using world⟩

theorem i32Result_byte_count {count : Nat} (bounded : count ≤ 8388608) :
    Lanius.World.i32Result count = .signed .i32 count := by
  have lower : (0 : Int) ≤ count := Int.natCast_nonneg _
  have upper : (count : Int) < 2 ^ 32 := by omega
  have sign : ¬ (count : Int) ≥ 2 ^ 31 := by omega
  simp only [Lanius.World.i32Result, Lanius.World.wrapI32,
    Int.emod_eq_of_lt lower upper, if_neg sign]

/-- The successful stdout branch returns zero, rather than the error code 22.
The local read is in the post-call state, as required by left-to-right evaluation. -/
theorem stdout_check_returns_zero
    {program : Program} {before after : State} {call : Expr} {length : VarId} {count : Nat}
    (bounded : count ≤ 8388608)
    (called : Evaluates program before call (Lanius.World.i32Result count) after)
    (lengthRead : after.local? length = some (.signed .i32 count)) :
    Executes program before
      (.sequence (.ifThenElse (.binary .notEqual call (.local length))
        (.sequence (.returnValue (some (.value (.signed .i32 22)))) .skip) .skip)
        (.sequence (.returnValue (some (.value (.signed .i32 0)))) .skip))
      (.returned (some (.signed .i32 0))) after := by
  have result := i32Result_byte_count bounded
  rw [result] at called
  have comparison : Evaluates program before (.binary .notEqual call (.local length)) (.boolean false) after :=
    evaluatesEagerBinary (by decide) (by decide) called
      ⟨1, evalLocal_of_local 0 program after length (.signed .i32 count) lengthRead⟩
      (by simp [evalBinaryValue, scalarEqual])
  exact executesSequence (executesIfFalse comparison (executesSkip program after))
    (executesSequenceReturned (executesReturnValue
      (show Evaluates program after (.value (.signed .i32 0)) (.signed .i32 0) after from ⟨1, rfl⟩)))

theorem evaluates_output_size (program : Program) (state : State) (length : VarId) (count : Nat)
    (fits : count < unsignedModulus program.target .usize)
    (read : state.local? length = some (.signed .i32 count)) :
    Evaluates program state (.cast (.unsigned .usize) (.local length))
      (.unsigned .usize count) state := by
  apply evaluatesCast ⟨1, evalLocal_of_local 0 program state length (.signed .i32 count) read⟩
  have upper : (count : Int) < Int.ofNat (unsignedModulus program.target .usize) := Int.ofNat_lt.mpr fits
  simp only [evalScalarCast, wrapUnsignedInt,
    Int.emod_eq_of_lt (Int.natCast_nonneg count) upper, Int.toNat_natCast]

/-- Preserve the actual explicit cast and the output-size scope around the
host-call continuation. World effects survive scope restoration unchanged. -/
theorem output_size_scope (program : Program) (state : State) (length size : VarId) (count : Nat)
    {body : Stmt} {completion : Completion} {world : Lanius.World.State}
    (fits : count < unsignedModulus program.target .usize)
    (read : state.local? length = some (.signed .i32 count))
    (run : ∃ after, Executes program (state.bindLocal size (.unsigned .usize count)) body completion after ∧
      after.world = world) :
    ∃ after, Executes program state
      (.letLocal size (.scalar (.unsigned .usize)) (.cast (.unsigned .usize) (.local length)) body)
      completion after ∧ after.world = world := by
  obtain ⟨after, executed, output⟩ := run
  exact ⟨restoreLocals state after,
    executesLetLocal (evaluates_output_size program state length count fits read) executed, output⟩

theorem stdout_tail_returns_zero
    {program : Core.Program} {function : Core.Function}
    {before afterArguments : Lanius.Semantics.State}
    {arguments : List Core.Expr} {bindings : List (Lanius.VarId × Core.Value)}
    {view : I32ArrayView} {length : VarId}
    (bytes : List UInt8) (tail : List Int)
    (argumentsResult : Lanius.CallContracts.ArgumentsEvaluateTo program before arguments
      [.pointer view.address, .unsigned .usize bytes.length] afterArguments)
    (functionFound : program.function? function.id = some function)
    (parametersBound : bindParameters function.parameters
      [.pointer view.address, .unsigned .usize bytes.length] = some bindings)
    (noBody : function.body = none)
    (host : function.external = some (.host .writeStdout))
    (wellFormed : HeapWellFormed afterArguments.heap)
    (disjoint : afterArguments.i32ArrayViews.Pairwise I32ViewRangesDisjoint)
    (member : view ∈ afterArguments.i32ArrayViews)
    (packed : readCellProjection afterArguments view.root view.projections =
      .ok (.array (OutputPacking.pack bytes ++ signedI32Values tail)))
    (blocks : ∀ view ∈ afterArguments.i32ArrayViews,
      I32ArrayViewBlockWellFormed afterArguments.heap view)
    (roots : ∀ view ∈ afterArguments.i32ArrayViews, view.projections = [])
    (arrays : ∀ view ∈ afterArguments.i32ArrayViews, ∃ elements,
      readCellProjection afterArguments view.root view.projections = .ok (.array elements) ∧
      elements.length = view.length ∧
      ∀ element ∈ elements, ∃ value, element = .signed .i32 value)
    (bounded : bytes.length ≤ 8388608)
    (lengthRead : afterArguments.local? length = some (.signed .i32 bytes.length))
    (separate : ∀ cell, afterArguments.cellId? length = some cell →
      ∀ other ∈ afterArguments.i32ArrayViews, cell ≠ other.root) :
    ∃ after, Executes program before
      (.sequence (.ifThenElse (.binary .notEqual (.call function.id arguments) (.local length))
        (.sequence (.returnValue (some (.value (.signed .i32 22)))) .skip) .skip)
        (.sequence (.returnValue (some (.value (.signed .i32 0)))) .skip))
      (.returned (some (.signed .i32 0))) after ∧
      after.world = { afterArguments.world with
        standardOutput := afterArguments.world.standardOutput ++ bytes
        calls := afterArguments.world.calls ++ [.writeStdout] } := by
  obtain ⟨after, called, world, cells, locals⟩ := ExtractorContract.workspace_stdout_exists bytes tail
    argumentsResult functionFound parametersBound noBody host wellFormed disjoint member packed blocks roots arrays
  have readAfter : after.local? length = some (.signed .i32 bytes.length) := by
    obtain ⟨cell, binding, value⟩ := Option.bind_eq_some_iff.mp lengthRead
    have bindingAfter : after.cellId? length = some cell := by
      simpa only [State.cellId?, locals] using binding
    have kept := cells cell (separate cell binding)
    simpa only [State.local?, bindingAfter, Option.bind_some, State.cell?, kept] using value
  exact ⟨after, stdout_check_returns_zero bounded called readAfter, world⟩

theorem stdout_arguments (program : Program) (state : State)
    (pointer size : VarId) (address count : Nat)
    (pointerRead : state.local? pointer = some (.pointer address))
    (sizeRead : state.local? size = some (.unsigned .usize count)) :
    Lanius.CallContracts.ArgumentsEvaluateTo program state [.local pointer, .local size]
      [.pointer address, .unsigned .usize count] state :=
  Lanius.CallContracts.ArgumentsEvaluateTo.cons
    ⟨1, evalLocal_of_local 0 program state pointer (.pointer address) pointerRead⟩
    (Lanius.CallContracts.ArgumentsEvaluateTo.singleton
      ⟨1, evalLocal_of_local 0 program state size (.unsigned .usize count) sizeRead⟩)

theorem preserved_local {before after : State} {writes : CellSet} {localId : VarId} {value : Value}
    (wellFormed : StateWellFormed before) (effect : StoreEffect writes before after)
    (binding : after.cellId? localId = before.cellId? localId)
    (read : before.local? localId = some value)
    (outside : ∀ cell, before.cellId? localId = some cell → ¬ writes cell) :
    after.local? localId = some value := by
  have kept := effect.restoreLocals.preserves_local wellFormed read outside
  have same : after.local? localId = (restoreLocals before after).local? localId := by
    simp only [State.local?, binding]
    rfl
  exact same.trans kept

theorem preserved_projection {state after : State} {writes : CellSet} {root : CellId}
    {path : List ValueProjection} {value : Value}
    (wellFormed : StateWellFormed state) (effect : StoreEffect writes state after)
    (outside : ¬ writes root)
    (read : readCellProjection state root path = .ok value) :
    readCellProjection after root path = .ok value := by
  cases found : state.cellEntry? root with
  | none => simp [readCellProjection, found] at read
  | some entry =>
      have id : entry.id = root := by simpa using List.find?_some found
      have old : root < state.nextCell := by
        rw [← id]
        exact wellFormed.cellIdsBelowNext _ (List.mem_of_find?_eq_some found)
      have kept := effect.oldCells root old outside
      simpa only [readCellProjection, kept] using read

theorem bindLocal_preserves_projection {state : State} {root : CellId}
    {path : List ValueProjection} {value : Value}
    (wellFormed : StateWellFormed state) (localId : VarId) (bound : Value)
    (read : readCellProjection state root path = .ok value) :
    readCellProjection (state.bindLocal localId bound) root path = .ok value :=
  preserved_projection wellFormed (bindLocal_effect state localId bound) (by simp [CellSet.empty]) read

theorem LoopInvariant.workspace_view {memory : LoopMemory} {locals : LoopLocals} {state : State}
    {view : I32ArrayView}
    (complete : LoopInvariant memory locals memory.bytes state)
    (root : view.root = memory.workspaceCell) (path : view.projections = [])
    (length : view.length = memory.words + memory.tail.length) :
    ∃ elements, readCellProjection state view.root view.projections = .ok (.array elements) ∧
      elements.length = view.length ∧
      ∀ element ∈ elements, ∃ value, element = .signed .i32 value := by
  refine ⟨pack memory.bytes ++ signedI32Values memory.tail, ?_, ?_, ?_⟩
  · simp [root, path, readCellProjection, complete.complete_contents, projectedValue]
  · simp only [List.length_append, pack_length, signedI32Values, List.length_map, length, LoopMemory.words]
  · obtain ⟨values, packed⟩ := pack_as_i32_values memory.bytes
    intro element member
    rw [← packed] at member
    simp only [signedI32Values, List.mem_append, List.mem_map] at member
    rcases member with ⟨value, _, same⟩ | ⟨value, _, same⟩
    · exact ⟨value, same.symm⟩
    · exact ⟨value, same.symm⟩

theorem LoopInvariant.registered_arrays {memory : LoopMemory} {locals : LoopLocals}
    {before after : State} {writes : CellSet}
    (wellFormed : StateWellFormed before)
    (complete : LoopInvariant memory locals memory.bytes after)
    (effect : StoreEffect writes before after)
    (workspaceMetadata : ∀ view ∈ before.i32ArrayViews, view.root = memory.workspaceCell →
      view.projections = [] ∧ view.length = memory.words + memory.tail.length)
    (outside : ∀ view ∈ before.i32ArrayViews, view.root ≠ memory.workspaceCell → ¬ writes view.root)
    (arrays : ∀ view ∈ before.i32ArrayViews, view.root ≠ memory.workspaceCell → ∃ elements,
      readCellProjection before view.root view.projections = .ok (.array elements) ∧
      elements.length = view.length ∧
      ∀ element ∈ elements, ∃ value, element = .signed .i32 value) :
    ∀ view ∈ after.i32ArrayViews, ∃ elements,
      readCellProjection after view.root view.projections = .ok (.array elements) ∧
      elements.length = view.length ∧
      ∀ element ∈ elements, ∃ value, element = .signed .i32 value := by
  intro view member
  have original : view ∈ before.i32ArrayViews := by simpa only [effect.views] using member
  by_cases workspace : view.root = memory.workspaceCell
  · obtain ⟨path, length⟩ := workspaceMetadata view original workspace
    exact complete.workspace_view workspace path length
  · obtain ⟨elements, read, length, typed⟩ := arrays view original workspace
    exact ⟨elements, preserved_projection wellFormed effect (outside view original workspace) read, length, typed⟩

theorem StdoutTail.executes (source : StdoutTail) (program : Program) (state : State)
    (function : Function) (bindings : List (VarId × Value)) (view : I32ArrayView)
    (bytes : List UInt8) (tail : List Int)
    (wellFormed : StateWellFormed state)
    (fits : bytes.length < unsignedModulus program.target .usize)
    (bounded : bytes.length ≤ 8388608)
    (lengthRead : state.local? source.length = some (.signed .i32 bytes.length))
    (pointerRead : state.local? source.pointer = some (.pointer view.address))
    (differentLength : source.size ≠ source.length) (differentPointer : source.size ≠ source.pointer)
    (functionId : function.id = source.function)
    (functionFound : program.function? function.id = some function)
    (parametersBound : bindParameters function.parameters
      [.pointer view.address, .unsigned .usize bytes.length] = some bindings)
    (noBody : function.body = none) (host : function.external = some (.host .writeStdout))
    (disjoint : state.i32ArrayViews.Pairwise I32ViewRangesDisjoint)
    (member : view ∈ state.i32ArrayViews)
    (packed : readCellProjection state view.root view.projections =
      .ok (.array (pack bytes ++ signedI32Values tail)))
    (blocks : ∀ view ∈ state.i32ArrayViews, I32ArrayViewBlockWellFormed state.heap view)
    (roots : ∀ view ∈ state.i32ArrayViews, view.projections = [])
    (arrays : ∀ view ∈ state.i32ArrayViews, ∃ elements,
      readCellProjection state view.root view.projections = .ok (.array elements) ∧
      elements.length = view.length ∧
      ∀ element ∈ elements, ∃ value, element = .signed .i32 value)
    (separate : ∀ cell, state.cellId? source.length = some cell →
      ∀ other ∈ state.i32ArrayViews, cell ≠ other.root) :
    ∃ after, Executes program state source.statement (.returned (some (.signed .i32 0))) after ∧
      after.world = { state.world with
        standardOutput := state.world.standardOutput ++ bytes
        calls := state.world.calls ++ [.writeStdout] } := by
  have pointer := (bindLocal_preserves_other_local (value := .unsigned .usize bytes.length) wellFormed differentPointer).trans pointerRead
  have length := (bindLocal_preserves_other_local (value := .unsigned .usize bytes.length) wellFormed differentLength).trans lengthRead
  have size := bindLocal_finds_local state source.size (.unsigned .usize bytes.length) wellFormed
  have arguments := stdout_arguments program (state.bindLocal source.size (.unsigned .usize bytes.length)) source.pointer source.size view.address bytes.length pointer size
  obtain ⟨after, run, world⟩ := stdout_tail_returns_zero bytes tail arguments functionFound parametersBound
    noBody host wellFormed.heapWellFormed disjoint member
    (bindLocal_preserves_projection wellFormed source.size _ packed) blocks roots
    (fun other mem => by
      obtain ⟨elements, read, count, typed⟩ := arrays other mem
      exact ⟨elements, bindLocal_preserves_projection wellFormed source.size _ read, count, typed⟩)
    bounded length
    (fun cell binding => separate cell (by
      rw [bindLocal_preserves_other_cellId state source.size source.length _ differentLength] at binding
      exact binding))
  rw [functionId] at run
  exact output_size_scope program state source.length source.size bytes.length fits lengthRead ⟨after, run, world⟩

end Lanius.Extraction.OutputPacking
