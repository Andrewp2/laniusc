import verified_compiler.tests.direct_ir_type_cache
import Lanius.Core.Bindings
import Lanius.Semantics.RawStore
import Lanius.Semantics.ScopedEffect
import Lanius.Extraction.OutputPacking.Byte

namespace IRTypeCacheStoreProof

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRTypeRefProof IRExpressionKindProof IRTypeCacheProof

private def source := Extracted.«lowering::body_expression».Functions.«expression_kind».core
private def uncached := Extracted.«lowering::body_expression».Functions.«expression_kind_uncached».core

/-- A readable, writable cache miss. The two updated words cannot overlap. -/
structure Slot (before : State) extends Query where
  oldCode : Int
  oldDepth : Int
  codeRead : readRawSliceIndex extractedProgram before (.scalar (.signed .i32)) codes capacity node =
    .ok (.signed .i32 oldCode)
  depthRead : readRawSliceIndex extractedProgram before (.scalar (.signed .i32)) depths capacity node =
    .ok (.signed .i32 oldDepth)
  missed : oldCode < 0 ∨ depth.toInt < oldDepth
  codeRoom : before.heap.Readable (codes + node * 4) 4
  depthRoom : before.heap.Readable (depths + node * 4) 4
  separate : codes + node * 4 + 4 ≤ depths + node * 4 ∨ depths + node * 4 + 4 ≤ codes + node * 4

/-- The inference callback is a proved source contract, not cached evidence or
    a new assumption in the closed literal/unary theorems. -/
def Inference (query : Query) (header : Fin 5 → Value) (nodes countCell : Value)
    (unused : List Value) (kind : Reference) (heap : Heap) : Prop :=
  ∀ {state : State}, state.heap = heap → state.CellsWellFormed →
    ∃ after, RunsExpr extractedProgram state
      (.call uncached.id ([query.context header nodes countCell unused, .signed .i32 query.count,
        .signed .i32 query.node, .signed .i32 query.depth.toInt].map Expr.value))
      (known kind) after ∧ PureFrame state after

/-- The parent needs only these storage facts after recursive inference.
    They do not assert that cache bytes, source nodes or bindings are unchanged. -/
structure Writable (query : Query) (heap : Heap) : Prop where
  codes : heap.Readable (query.codes + query.node * 4) 4
  depths : heap.Readable (query.depths + query.node * 4) 4
  unique : HeapBlockBasesUnique heap

/-- Recursive inference may write its children's cache entries. Its proved
    heap relation is retained, rather than replaced by a read-only frame. -/
def EffectfulInference (query : Query) (header : Fin 5 → Value) (nodes countCell : Value)
    (unused : List Value) (kind : Reference) (heap : Heap) (relation : Heap → Heap → Prop) : Prop :=
  ∀ {state : State}, state.heap = heap → state.CellsWellFormed → state.i32ArrayViews = [] →
    ∃ after, RunsExpr extractedProgram state
      (.call uncached.id ([query.context header nodes countCell unused, .signed .i32 query.count,
        .signed .i32 query.node, .signed .i32 query.depth.toInt].map Expr.value))
      (known kind) after ∧ MemoryEffect relation state after ∧ Writable query after.heap

/-- Exactly two cache-word writes, preserving every other byte. -/
def Stored (query : Query) (kind : Reference) (before after : Heap) : Prop :=
  ∃ middle, BytesWrite before middle (query.codes + query.node * 4) (i32Bytes (typeCode kind)) ∧
    BytesWrite middle after (query.depths + query.node * 4) (i32Bytes query.depth.toInt)

def InferredAndStored (query : Query) (kind : Reference) (relation : Heap → Heap → Prop)
    (before after : Heap) : Prop :=
  ∃ inferred, relation before inferred ∧ Stored query kind inferred after

theorem Stored.writable (stored : Stored child kind before after) (ready : Writable parent before) :
    Writable parent after := by
  obtain ⟨middle, code, depth⟩ := stored
  exact ⟨depth.readable (code.readable ready.codes), depth.readable (code.readable ready.depths), depth.unique⟩

theorem typeCodeBits (kind : Reference) :
    (BitVec.ofInt 32 (typeCode kind)).toInt = typeCode kind := by
  apply BitVec.toInt_ofInt_eq_self (by decide)
  all_goals
    cases kind <;> dsimp only [typeCode, nominalCode]
    all_goals first | omega | (split <;> omega)

/-- The real wrapper composes recursive effects with its own two writes.
    Clients must discharge inference and post-inference slot readiness. -/
theorem actualStoreWith (input : Slot before) (header : Fin 5 → Value) (nodes countCell : Value)
    (unused : List Value) (kind : Reference) (supported : isValidResult kind = true)
    (infer : EffectfulInference input.toQuery header nodes countCell unused kind before.heap relation)
    (formed : before.CellsWellFormed) (noViews : before.i32ArrayViews = []) :
    ∃ after, RunsExpr extractedProgram before (input.toQuery.call header nodes countCell unused) (known kind) after ∧
      MemoryEffect (InferredAndStored input.toQuery kind relation) before after := by
  core_facts [input]
  have bound : input.node < input.capacity := by omega
  have nonnegative : 0 ≤ typeCode kind := of_decide_eq_true supported
  let codes := Value.rawSlice (.scalar (.signed .i32)) input.codes input.capacity
  let depths := Value.rawSlice (.scalar (.signed .i32)) input.depths input.capacity
  let bindings := [(source.argumentId 0, (input.toQuery.context header nodes countCell unused)),
    (source.argumentId 1, Value.signed .i32 input.count), (source.argumentId 2, .signed .i32 input.node),
    (source.argumentId 3, .signed .i32 input.depth.toInt)]
  let callee := ({ before with locals := [] }).bindLocals bindings
  let atCodes := callee.bindLocal (source.bindingId 0) codes
  let ready := atCodes.bindLocal (source.bindingId 1) depths
  obtain ⟨inferred, inferenceRun, ⟨inferenceCells, inferenceWorld, inferenceViews, inferenceEffect⟩, writable⟩ :=
    infer (state := ready) rfl (by core_formed) noViews
  let active := inferred.bindLocal (source.bindingId 2) (known kind)
  obtain ⟨coded, codeRun, codeFrame⟩ := actualCode (state := active) kind (by core_formed)
  let writing := coded.bindLocal (source.bindingId 3) (.signed .i32 (typeCode kind))
  have heapSame : writing.heap = inferred.heap := codeFrame.heap
  have viewsSame : writing.i32ArrayViews = [] := codeFrame.views.trans (inferenceViews.trans noViews)
  obtain ⟨firstHeap, firstRun, firstWrite⟩ := RunsExpr.assignRawI32 (program := extractedProgram)
    (before := writing) (indexed := writing) (ready := writing) (expression := .local (source.bindingId 3))
    (sourceId := source.bindingId 0) (indexExpression := .local (source.argumentId 2))
    (by core_local) (by core_run) bound (by rw [heapSame]; exact writable.codes)
    (by rw [heapSame]; exact writable.unique) viewsSame (by core_run)
  let first := { writing with heap := firstHeap }
  obtain ⟨heap, secondRun, secondWrite⟩ := RunsExpr.assignRawI32 (program := extractedProgram)
    (before := first) (indexed := first) (ready := first) (expression := .local (source.argumentId 3))
    (sourceId := source.bindingId 1) (indexExpression := .local (source.argumentId 2))
    (by core_local) (by core_run) bound
    (firstWrite.readable (by rw [heapSame]; exact writable.depths)) firstWrite.unique viewsSame (by core_run)
  let returned := restoreLocals coded { writing with heap }
  have returnedCells : FreshCellFrame active returned := codeFrame.cells.trans
    (FreshCellFrame.bindLocal coded (source.bindingId 3) (.signed .i32 (typeCode kind)))
  have resultFound : active.local? (source.bindingId 2) = some (known kind) := by core_local
  have returnedFound := returnedCells.localFound codeRun.choose_spec.2 _ _ resultFound
  let completed := { writing with heap, locals := callee.locals }
  have body : RunsStmt extractedProgram callee (source.body.getD .skip)
      (.returned (some (known kind))) completed := by core_stmt_forward
  have cells := (FreshCellFrame.bindLocals ({ before with locals := [] }) bindings).trans
    ((FreshCellFrame.bindLocal callee (source.bindingId 0) codes).trans
      ((FreshCellFrame.bindLocal atCodes (source.bindingId 1) depths).trans
        (inferenceCells.trans ((FreshCellFrame.bindLocal inferred (source.bindingId 2)
          (known kind)).trans returnedCells))))
  refine ⟨restoreLocals before completed,
    RunsExpr.call (function := source) (values := [(input.toQuery.context header nodes countCell unused), .signed .i32 input.count,
      .signed .i32 input.node, .signed .i32 input.depth.toInt]) (bindings := bindings)
      (by core_lookup) rfl (RunsExprs.values _) rfl body,
    cells, codeFrame.world.trans inferenceWorld, codeFrame.views.trans inferenceViews,
    inferred.heap, inferenceEffect, firstHeap, ?_, secondWrite⟩
  change BytesWrite writing.heap firstHeap _ _ at firstWrite
  rwa [heapSame] at firstWrite

/-- Read-only inference is a genuine specialization of the effectful wrapper,
    retaining the original exact two-write result. -/
theorem actualStore (input : Slot before) (header : Fin 5 → Value) (nodes countCell : Value)
    (unused : List Value) (kind : Reference) (supported : isValidResult kind = true)
    (infer : Inference input.toQuery header nodes countCell unused kind before.heap)
    (formed : before.CellsWellFormed)
    (unique : HeapBlockBasesUnique before.heap) (noViews : before.i32ArrayViews = []) :
    ∃ after, RunsExpr extractedProgram before (input.toQuery.call header nodes countCell unused) (known kind) after ∧
      MemoryEffect (Stored input.toQuery kind) before after := by
  have effectful : EffectfulInference input.toQuery header nodes countCell unused kind before.heap
      (fun first last => last = first) := by
    intro state same formed _
    obtain ⟨after, run, frame⟩ := infer same formed
    refine ⟨after, run, ⟨frame.cells, frame.world, frame.views, frame.heap⟩, ?_⟩
    rw [frame.heap, same]
    exact ⟨input.codeRoom, input.depthRoom, unique⟩
  obtain ⟨after, run, cells, world, views, middle, same, stored⟩ :=
    actualStoreWith input header nodes countCell unused kind supported effectful formed noViews
  exact ⟨after, run, cells, world, views, by simpa only [same] using stored⟩

/-- The writes establish the lookup invariant; no successful lookup is a
    premise. Read-back comes from the native word codecs and disjointness. -/
def Slot.entry (input : Slot before) (kind : Reference) (supported : isValidResult kind = true)
    (write : Stored input.toQuery kind heap after.heap) :
    Entry after := by
  have bound : input.node < input.capacity := Nat.lt_of_lt_of_le input.inside input.storage
  refine {
    toQuery := input.toQuery
    storedDepth := input.depth
    kind := kind
    sufficient := Int.le_refl _
    supported := supported
    codeRead := ?_
    depthRead := ?_ }
  · obtain ⟨middle, codeWrite, depthWrite⟩ := write
    have codeBytes : after.heap.loadBytes (input.codes + input.node * 4) 4 =
        .ok (i32Bytes (typeCode kind)) :=
      depthWrite.loadBytes_disjoint (by simpa only [i32Bytes, List.length_map, List.length_range] using codeWrite.loadBytes)
        (by simpa only [i32Bytes, List.length_map, List.length_range] using input.separate.symm)
    have represented := typeCodeBits kind
    simpa only [represented] using Lanius.Semantics.readRawSliceIndex_i32Bytes
      extractedProgram after (word := BitVec.ofInt 32 (typeCode kind)) bound
      (by simpa only [represented] using codeBytes)
  · obtain ⟨middle, codeWrite, depthWrite⟩ := write
    simpa only [Int32.toInt_toBitVec] using Lanius.Semantics.readRawSliceIndex_i32Bytes extractedProgram after
      (word := input.depth.toBitVec) bound
      (by simpa only [Int32.toInt_toBitVec, i32Bytes, List.length_map, List.length_range] using depthWrite.loadBytes)

/-- Store a proved inferred type and derive the next real cache hit. -/
theorem actualStoreAndReuse (input : Slot before) (header : Fin 5 → Value) (nodes countCell : Value)
    (unused : List Value) (kind : Reference) (supported : isValidResult kind = true)
    (infer : Inference input.toQuery header nodes countCell unused kind before.heap)
    (formed : before.CellsWellFormed) (unique : HeapBlockBasesUnique before.heap)
    (noViews : before.i32ArrayViews = []) :
    ∃ cached after,
      RunsExpr extractedProgram before (input.toQuery.call header nodes countCell unused) (known kind) cached ∧
      MemoryEffect (Stored input.toQuery kind) before cached ∧
      RunsExpr extractedProgram cached (input.toQuery.call header nodes countCell unused) (known kind) after ∧
      PureFrame cached after := by
  obtain ⟨cached, first, effect⟩ := actualStore input header nodes countCell unused kind supported infer formed unique noViews
  let entry := input.entry kind supported effect.2.2.2
  obtain ⟨after, reuse, pure⟩ := actualHit entry header nodes countCell unused
    (by core_formed)
  exact ⟨cached, after, first, effect, reuse, pure⟩

#print axioms actualStoreWith
#print axioms actualStoreAndReuse

end IRTypeCacheStoreProof
