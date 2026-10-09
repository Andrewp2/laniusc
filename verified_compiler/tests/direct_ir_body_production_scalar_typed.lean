import verified_compiler.tests.direct_ir_body_production_scalar_inference
import verified_compiler.tests.direct_ir_body_production_scalar_expression

namespace IRBodyProductionScalar

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRBodyProductionInputs IRTypeRefProof IRExpressionKindProof

variable {before after : State}

def typedSource := Extracted.«lowering::body_expression».Functions.«expression».core
def typedCall (input : Inputs) (workspace : Workspace) (locals : Value)
    (count root depth : Nat) (output : Value) (position : Nat) : Expr :=
  .call typedSource.id ([bodyContext input workspace locals, .signed .i32 count,
    .signed .i32 root, output, .signed .i32 position, .signed .i32 depth].map Expr.value)

private def literalTag := source_value Extracted.«verified::surface_expr».Types.«SurfaceExprKind».«Literal» []
private def unaryTag := source_value Extracted.«verified::surface_expr».Types.«SurfaceExprKind».«Unary» []
private def assignTag := source_value Extracted.«verified::surface_expr».Types.«SurfaceExprKind».«Assign» []

/-- Cold inference changes the live cache, not the produced arena/count.
    Cleared-code evidence is intentionally not retained. -/
theorem ProducedNodes.afterCacheWrites (storage : ScalarStorage workspace initial slots)
    (produced : ProducedNodes storage count nodes origin before.heap)
    (used : count ≤ slots) (write : HeapWritesOn before.heap after.heap storage.cacheWrites) :
    ProducedNodes storage count nodes origin after.heap := by
  refine ⟨?_, ?_, produced.2.2.trans ?_⟩
  · intro index inside
    exact (produced.1 index inside).afterFootprint write (by
      intro address lower upper allowed
      rcases allowed with code | depth
      · have := storage.nodeCodes index (Nat.lt_of_lt_of_le inside used); omega
      · have := storage.nodeDepths index (Nat.lt_of_lt_of_le inside used); omega)
  · exact produced.2.1.afterFootprint write (by
      intro address lower upper allowed
      rcases allowed with code | depth
      · have := storage.countCodes; omega
      · have := storage.countDepths; omega)
  · exact write.weaken (fun _ allowed => by
      rcases allowed with code | depth
      · exact Or.inr (Or.inr (Or.inl code))
      · exact Or.inr (Or.inr (Or.inr depth)))

private theorem actualNotAssign (tag : Value) (natural : tag = literalTag ∨ tag = unaryTag)
    (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state
      (.call Extracted.«verified::surface_expr».Functions.«has_kind».core.id [.value tag, .value assignTag])
      (.boolean false) after ∧ PureFrame state after := by
  rcases natural with rfl | rfl <;>
    (core_call_pure Extracted.«verified::surface_expr».Functions.«has_kind».core as callee; core_pure)

/-- The actual typed dispatch changes its fresh TypeRef local, not an old
    caller cell. The final emission/annotation continuation is internal and
    is discharged by the natural-expression producer. -/
theorem actualTypedWith (input : Inputs) (workspace : Workspace) (locals : Value)
    (storage : ScalarStorage workspace before slots) (count root depth position next : Nat)
    (inside : root < count) (bound : count ≤ storage.arena.capacity) (positive : 0 < depth)
    (tag : Value) (natural : tag = literalTag ∨ tag = unaryTag) (operator : Value) (fields : List Value)
    (native : readRawSliceIndex extractedProgram before expressionNodeType storage.arena.nodes storage.arena.capacity root =
      .ok (.structure (match expressionNodeType with | .structure id => id | _ => 0) (tag :: operator :: fields)))
    (kind : Reference) (valid : isValidResult kind = true) (output : Value)
    (warm : ∀ {state : State}, state.heap = before.heap → state.CellsWellFormed → ∃ after,
      RunsExpr extractedProgram state
        (.call Extracted.«lowering::body_expression».Functions.«expression_kind».core.id
          ([bodyContext input workspace locals, .signed .i32 count, .signed .i32 root,
            .signed .i32 depth].map Expr.value)) (known kind) after ∧ PureFrame state after)
    (finish : ∀ {state : State}, state.heap = before.heap → state.CellsWellFormed →
      state.i32ArrayViews = before.i32ArrayViews →
      state.local? (typedSource.argumentId 0) = some (bodyContext input workspace locals) →
      state.local? (typedSource.argumentId 1) = some (.signed .i32 count) →
      state.local? (typedSource.argumentId 2) = some (.signed .i32 root) →
      state.local? (typedSource.argumentId 3) = some output →
      state.local? (typedSource.argumentId 4) = some (.signed .i32 position) →
      state.local? (typedSource.argumentId 5) = some (.signed .i32 depth) →
      state.local? (typedSource.bindingId 2) = some (referenceValue kind) → ∃ after,
      RunsStmt extractedProgram state (typedSource.bindingStatement 4)
        (.returned (some (.signed .i32 next))) after ∧ MemoryEffect relation state after)
    (formed : before.CellsWellFormed) (noViews : before.i32ArrayViews = []) :
    ∃ after, RunsExpr extractedProgram before
      (typedCall input workspace locals count root depth output position) (.signed .i32 next) after ∧
      MemoryEffect relation before after := by
  have notAssign {state : State} (formed : state.CellsWellFormed) := actualNotAssign tag natural formed
  core_facts [storage, storage.arena]
  core_call_framed (RunsExpr.callEffect (MemoryEffect.scopeStable _)) typedSource as callee
  apply RunsStmt.letEffect (MemoryEffect.scopeStable _) (value := storage.arena.value)
  · rw [← storage.arenaValue]; core_run
  · core_formed
  · core_state arenaState
    apply RunsStmt.letEffect (MemoryEffect.scopeStable _)
      (value := .rawSlice expressionNodeType storage.arena.nodes storage.arena.capacity)
    · core_run
    · core_formed
    · core_state nodesState
      apply RunsStmt.guardEffectFalse (MemoryEffect.scopeStable _)
      · core_pure_guard
      · intro stage prefixFrame
        have stageFormed : stage.CellsWellFormed := by core_formed
        let kindState := stage.bindLocal (typedSource.bindingId 2) (referenceValue .Invalid)
        have kindFormed := stageFormed.bindLocal (typedSource.bindingId 2) (referenceValue .Invalid)
        have kindHeap : kindState.heap = before.heap := prefixFrame.heap
        have nativeHere : readRawSliceIndex extractedProgram kindState expressionNodeType
            storage.arena.nodes storage.arena.capacity root =
            .ok (.structure (match expressionNodeType with | .structure id => id | _ => 0) (tag :: operator :: fields)) := by
          simpa only [readRawSliceIndex, kindHeap] using native
        obtain ⟨guarded, guardRun, guardFrame⟩ : ∃ guarded, RunsExpr extractedProgram kindState
            (match typedSource.bindingStatement 2 with
              | .letLocal _ _ _ (.sequence (.ifThenElse condition _ _) _) => condition
              | _ => .value (.boolean true)) (.boolean false) guarded ∧ PureFrame kindState guarded := by
          core_pure_guard
        obtain ⟨cached, cachedRun, cachedFrame⟩ := warm (state := guarded)
          (guardFrame.heap.trans prefixFrame.heap) (by core_formed)
        have inferenceRun : RunsExpr extractedProgram guarded (typedSource.bindingInitializer 3) (known kind) cached := by
          exact RunsExpr.callArguments (by core_arguments) cachedRun
        let inferred := cached.bindLocal (typedSource.bindingId 3) (known kind)
        have inferredFormed : inferred.CellsWellFormed := by core_formed
        obtain ⟨ready, typeRun, typeFrame⟩ := IRExpressionKindProof.actualType .KnownExpression kind
          (before := inferred) inferredFormed
        have typeLocal : RunsExpr extractedProgram inferred
            (.call Extracted.«lowering::body_expression».Functions.«kind_type».core.id
              [.local (typedSource.bindingId 3)]) (referenceValue kind) ready := by
          exact RunsExpr.callArguments (by core_arguments) typeRun
        have kindSlot : inferred.cellId? (typedSource.bindingId 2) = some stage.nextCell := by
          rw [State.bindLocal_cellId_of_ne _ _ _ (by decide)]
          simpa only [State.cellId?, cachedFrame.locals, guardFrame.locals] using
            State.bindLocal_cellId stage (typedSource.bindingId 2) (referenceValue .Invalid)
        have oldKind : inferred.local? (typedSource.bindingId 2) = some (referenceValue .Invalid) := by core_local
        obtain ⟨assigned, assignRun, assignedLocal, assignment⟩ := RunsExpr.assignValueAfter kindSlot oldKind typeLocal
          (typeFrame.views.trans (cachedFrame.views.trans (guardFrame.views.trans (prefixFrame.views.trans noViews))))
        have entry := (((CallerFrame.refl stageFormed).bindLocal (typedSource.bindingId 2) (referenceValue .Invalid)).transPure
          guardFrame).transPure cachedFrame
        have active := (entry.bindLocal (typedSource.bindingId 3) (known kind)).transPure typeFrame
        have readySlot : ready.cellId? (typedSource.bindingId 2) = some stage.nextCell := by
          simpa only [State.cellId?, typeFrame.locals] using kindSlot
        have assignedFrame := active.assignLocalFresh (typedSource.bindingId 2) stage.nextCell
          (referenceValue kind) readySlot (Nat.le_refl _) assignedLocal
        have kindFound := assignLocal_finds_assigned _ _ _ readySlot assignedLocal
        obtain ⟨checked, validRun, validFrame⟩ : ∃ checked, RunsExpr extractedProgram assigned
            (.unary .logicalNot (.call Extracted.«ir::type_ref».Functions.«valid_result».core.id
              [.local (typedSource.bindingId 2)])) (.boolean false) checked ∧ PureFrame assigned checked := by
          core_pure_guard
        let branched := restoreLocals cached checked
        have branchRun : RunsStmt extractedProgram kindState
            (match typedSource.bindingStatement 2 with | .letLocal _ _ _ (.sequence first _) => first | _ => .skip)
            .next branched := by core_stmt_forward
        have branchFrame : CallerFrame stage branched :=
          ⟨stageFormed, assignedFrame.cells.trans validFrame.cells, validFrame.heap.trans assignedFrame.heap,
            validFrame.world.trans assignedFrame.world, validFrame.views.trans assignedFrame.views⟩
        have retainedKind : branched.local? (typedSource.bindingId 2) = some (referenceValue kind) := by
          change (cached.cellId? (typedSource.bindingId 2)).bind checked.cell? = _
          have checkedFound := validFrame.localFound kindFound
          have sameCell : checked.cellId? (typedSource.bindingId 2) = cached.cellId? (typedSource.bindingId 2) := by
            simpa only [State.cellId?, validFrame.locals, assignment.locals, typeFrame.locals] using
              State.bindLocal_cellId_of_ne cached (typedSource.bindingId 2) (typedSource.bindingId 3)
                (by decide) (known kind)
          change (checked.cellId? (typedSource.bindingId 2)).bind checked.cell? = _ at checkedFound
          rwa [sameCell] at checkedFound
        have preserve {id : VarId} {value : Value} (different : typedSource.bindingId 2 ≠ id)
            (found : stage.local? id = some value) : branched.local? id = some value := by
          exact branchFrame.cells.localFoundAt (by
            change cached.cellId? id = stage.cellId? id
            simpa only [State.cellId?, cachedFrame.locals, guardFrame.locals] using
              State.bindLocal_cellId_of_ne stage id (typedSource.bindingId 2) different (referenceValue .Invalid)) value found
        obtain ⟨completed, suffix, effect⟩ := finish (state := branched)
          (branchFrame.heap.trans prefixFrame.heap) (branchFrame.currentFormed)
          (branchFrame.views.trans prefixFrame.views)
          (preserve (by decide) (by core_local)) (preserve (by decide) (by core_local))
          (preserve (by decide) (by core_local)) (preserve (by decide) (by core_local))
          (preserve (by decide) (by core_local)) (preserve (by decide) (by core_local)) retainedKind
        refine ⟨restoreLocals stage completed, ?_, ?_⟩
        · core_stmt_forward
        · exact (MemoryEffect.scopeStable relation).restore stage (effect.prependCaller branchFrame)

#print axioms actualTypedWith
#print axioms ProducedNodes.afterCacheWrites

/-- Close the typed function's final continuation with one real untyped
    emission and its real conditional annotation. The caller derives the warm
    cache entry and emitter from produced nodes and original spelling. -/
theorem actualTypedEmittingWith (input : Inputs) (workspace : Workspace) (locals : Value)
    {emission : Heap → Heap → Prop}
    (storage : ScalarStorage workspace before slots) (count root depth next : Nat)
    (inside : root < count) (bound : count ≤ storage.arena.capacity) (positive : 0 < depth)
    (tag : Value) (natural : tag = literalTag ∨ tag = unaryTag) (operator : Value) (fields : List Value)
    (native : readRawSliceIndex extractedProgram before expressionNodeType storage.arena.nodes storage.arena.capacity root =
      .ok (.structure (match expressionNodeType with | .structure id => id | _ => 0) (tag :: operator :: fields)))
    (kind : Reference) (valid : isValidResult kind = true) (output : IREventStoreProof.Context before)
    (warm : ∀ {state : State}, state.heap = before.heap → state.CellsWellFormed → ∃ after,
      RunsExpr extractedProgram state
        (.call Extracted.«lowering::body_expression».Functions.«expression_kind».core.id
          ([bodyContext input workspace locals, .signed .i32 count, .signed .i32 root,
            .signed .i32 depth].map Expr.value)) (known kind) after ∧ PureFrame state after)
    (allowed : Nat → Prop)
    (emit : ∀ {state : State}, state.heap = before.heap → state.CellsWellFormed →
      state.i32ArrayViews = before.i32ArrayViews → ∃ emitted,
      RunsExpr extractedProgram state
        (untypedCall input workspace locals count root depth output.value output.position)
        (.signed .i32 next) emitted ∧
      MemoryEffect (fun first last => emission first last ∧ HeapWritesOn first last allowed) state emitted)
    (formed : before.CellsWellFormed) (noViews : before.i32ArrayViews = []) :
    ∃ after, RunsExpr extractedProgram before
      (typedCall input workspace locals count root depth output.value output.position) (.signed .i32 next) after ∧
      MemoryEffect (fun first last => ∃ emitted, emission first emitted ∧
        IRResultTypeProof.Recorded (IRResultTypeProof.annotationSlot output) kind emitted last) before after := by
  apply actualTypedWith input workspace locals storage count root depth output.position next
    inside bound positive tag natural operator fields native kind valid output.value warm ?_ formed noViews
  intro state same cells views contextFound countFound rootFound outputFound positionFound depthFound kindFound
  obtain ⟨emitted, emissionRun, emissionEffect⟩ := emit same cells views
  have initial : RunsExpr extractedProgram state (typedSource.bindingInitializer 4) (.signed .i32 next) emitted :=
    RunsExpr.callArguments (by core_arguments) emissionRun
  let annotating := emitted.bindLocal (typedSource.bindingId 4) (.signed .i32 next)
  have emittedOutput := emissionRun.localFound emissionEffect.1 outputFound
  have emittedPosition := emissionRun.localFound emissionEffect.1 positionFound
  have emittedKind := emissionRun.localFound emissionEffect.1 kindFound
  let selected : IREventStoreProof.Context annotating := {
    output with
    eventRoom := emissionEffect.2.2.2.2.readable _ _ (by rw [same]; exact output.eventRoom)
    typeRoom := fun enabled => emissionEffect.2.2.2.2.readable _ _ (by rw [same]; exact output.typeRoom enabled) }
  have annotatingFormed := (emissionEffect.1.after_cellsWellFormed cells).bindLocal (typedSource.bindingId 4) (.signed .i32 next)
  have nextFound := (emissionEffect.1.after_cellsWellFormed cells).bindLocal_local (typedSource.bindingId 4) (.signed .i32 next)
  have validCode : 0 ≤ typeCode kind := of_decide_eq_true valid
  obtain ⟨completed, annotationRun, annotationEffect⟩ := actualAnnotateResult selected next kind validCode
    annotatingFormed emissionEffect.2.2.2.2.unique (emissionEffect.2.2.1.trans (views.trans noViews))
  change RunsExpr extractedProgram annotating
    (.call Extracted.«lowering::body_expression».Functions.«annotate_result».core.id
      ([output.value, .signed .i32 output.position, .signed .i32 next, referenceValue kind].map Expr.value))
    (.signed .i32 next) completed at annotationRun
  have localAnnotation : RunsExpr extractedProgram annotating
      (match typedSource.bindingStatement 4 with | .letLocal _ _ _ (.returnValue (some expression)) => expression | _ => .value .unit)
      (.signed .i32 next) completed := by
    apply RunsExpr.callArguments (middle := annotating)
      (values := [output.value, .signed .i32 output.position, .signed .i32 next, referenceValue kind])
    · core_arguments
    · exact annotationRun
  refine ⟨restoreLocals emitted completed, RunsStmt.letLocal initial (RunsStmt.returnValue localAnnotation),
    (emissionEffect.1.trans (FreshCellFrame.bindLocal emitted _ _)).trans annotationEffect.1,
    annotationEffect.2.1.trans emissionEffect.2.1,
    annotationEffect.2.2.1.trans emissionEffect.2.2.1, ?_⟩
  exact ⟨emitted.heap, emissionEffect.2.2.2.1, annotationEffect.2.2.2⟩

#print axioms actualTypedEmittingWith

private def expectedNodeSource := Extracted.«lowering::body_expression».Functions.«expression_expected».core
def expectedNodeCall (input : Inputs) (workspace : Workspace) (locals : Value)
    (count root depth : Nat) (kind : Reference) (output : Value) (position : Nat) : Expr :=
  .call expectedNodeSource.id ([bodyContext input workspace locals, .signed .i32 count,
    .signed .i32 root, referenceValue kind, output, .signed .i32 position,
    .signed .i32 depth].map Expr.value)

private theorem actualNotCall (tag : Value) (natural : tag = literalTag ∨ tag = unaryTag)
    (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state
      (.call Extracted.«verified::surface_expr».Functions.«has_kind».core.id
        [.value tag, .value (source_value Extracted.«verified::surface_expr».Types.«SurfaceExprKind».«Call» [])])
      (.boolean false) after ∧ PureFrame state after := by
  rcases natural with rfl | rfl <;>
    (core_call_pure Extracted.«verified::surface_expr».Functions.«has_kind».core as callee; core_pure)

/-- The real expected dispatch performs cold inference before typed emission.
    The two actual heap phases are retained separately; pure guards do not
    require an arbitrary heap relation to be reflexive or transitive. -/
theorem actualExpectedWith (input : Inputs) (workspace : Workspace) (locals : Value)
    (storage : ScalarStorage workspace before slots) (count root depth position next : Nat)
    (inside : root < count) (bound : count ≤ storage.arena.capacity) (positive : 0 < depth)
    (tag : Value) (natural : tag = literalTag ∨ tag = unaryTag) (operator : Value) (fields : List Value)
    (native : readRawSliceIndex extractedProgram before expressionNodeType storage.arena.nodes storage.arena.capacity root =
      .ok (.structure (match expressionNodeType with | .structure id => id | _ => 0) (tag :: operator :: fields)))
    (kind : Reference) (scalar : kind = .Bool ∨ kind = .I32) (output : Value)
    (cold : ∀ {state : State}, state.heap = before.heap → state.CellsWellFormed →
      state.i32ArrayViews = before.i32ArrayViews → ∃ cached,
      RunsExpr extractedProgram state
        (.call Extracted.«lowering::body_expression».Functions.«expression_kind».core.id
          ([bodyContext input workspace locals, .signed .i32 count, .signed .i32 root,
            .signed .i32 depth].map Expr.value)) (known kind) cached ∧ MemoryEffect coldRelation state cached)
    (finish : ∀ {origin cached : State}, origin.heap = before.heap →
      MemoryEffect coldRelation origin cached → cached.i32ArrayViews = before.i32ArrayViews → ∀ {state : State},
      state.heap = cached.heap → state.CellsWellFormed → state.i32ArrayViews = cached.i32ArrayViews →
      state.local? (expectedNodeSource.argumentId 0) = some (bodyContext input workspace locals) →
      state.local? (expectedNodeSource.argumentId 1) = some (.signed .i32 count) →
      state.local? (expectedNodeSource.argumentId 2) = some (.signed .i32 root) →
      state.local? (expectedNodeSource.argumentId 3) = some (referenceValue kind) →
      state.local? (expectedNodeSource.argumentId 4) = some output →
      state.local? (expectedNodeSource.argumentId 5) = some (.signed .i32 position) →
      state.local? (expectedNodeSource.argumentId 6) = some (.signed .i32 depth) → ∃ after,
      RunsStmt extractedProgram state (expectedNodeSource.bindingStatement 12)
        (.returned (some (.signed .i32 next))) after ∧ MemoryEffect relation state after)
    (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before
      (expectedNodeCall input workspace locals count root depth kind output position) (.signed .i32 next) after ∧
      MemoryEffect (fun first last => ∃ middle, coldRelation first middle ∧ relation middle last) before after := by
  have pointer : sameType kind .Pointer = false := by rcases scalar with rfl | rfl <;> rfl
  have usize : sameType kind .Usize = false := by rcases scalar with rfl | rfl <;> rfl
  have valid : isValid kind = true := by rcases scalar with rfl | rfl <;> rfl
  have same : sameType kind kind = true := by rcases scalar with rfl | rfl <;> rfl
  have notCall {state : State} (cells : state.CellsWellFormed) := actualNotCall tag natural cells
  have notPointer {state : State} (cells : state.CellsWellFormed) :
      ∃ after, RunsExpr extractedProgram state
        (.call Extracted.«ir::type_ref».Functions.«same».core.id
          [.value (referenceValue kind), .value (referenceValue .Pointer)]) (.boolean false) after ∧
        PureFrame state after := by
    have run := IRTypeRefProof.actualSame kind .Pointer cells
    rw [pointer] at run
    exact run
  have notUsize {state : State} (cells : state.CellsWellFormed) :
      ∃ after, RunsExpr extractedProgram state
        (.call Extracted.«ir::type_ref».Functions.«same».core.id
          [.value (referenceValue kind), .value (referenceValue .Usize)]) (.boolean false) after ∧
        PureFrame state after := by
    have run := IRTypeRefProof.actualSame kind .Usize cells
    rw [usize] at run
    exact run
  have sameKind {state : State} (cells : state.CellsWellFormed) :
      ∃ after, RunsExpr extractedProgram state
        (.call Extracted.«ir::type_ref».Functions.«same».core.id
          [.value (referenceValue kind), .value (referenceValue kind)]) (.boolean true) after ∧
        PureFrame state after := by
    have run := IRTypeRefProof.actualSame kind kind cells
    rw [same] at run
    exact run
  have tagQueries : ∃ literal unary : Bool,
      (∀ {state : State}, state.CellsWellFormed → ∃ after, RunsExpr extractedProgram state
        (.call Extracted.«verified::surface_expr».Functions.«has_kind».core.id
          [.value tag, .value literalTag]) (.boolean literal) after ∧ PureFrame state after) ∧
      (∀ {state : State}, state.CellsWellFormed → ∃ after, RunsExpr extractedProgram state
        (.call Extracted.«verified::surface_expr».Functions.«has_kind».core.id
          [.value tag, .value (source_value Extracted.«verified::surface_expr».Types.«SurfaceExprKind».«Binary» [])])
        (.boolean unary) after ∧ PureFrame state after) := by
    rcases natural with rfl | rfl
    · refine ⟨true, false, ?_, ?_⟩
      all_goals intro state cells; core_call_pure Extracted.«verified::surface_expr».Functions.«has_kind».core as callee; core_pure
    · refine ⟨false, false, ?_, ?_⟩
      all_goals intro state cells; core_call_pure Extracted.«verified::surface_expr».Functions.«has_kind».core as callee; core_pure
  obtain ⟨literal, binary, literalQuery, binaryQuery⟩ := tagQueries
  have nodeRead {state : State} (heap : state.heap = before.heap) :
      readRawSliceIndex extractedProgram state expressionNodeType storage.arena.nodes storage.arena.capacity root =
        .ok (.structure (match expressionNodeType with | .structure id => id | _ => 0) (tag :: operator :: fields)) := by
    simpa only [readRawSliceIndex, heap] using native
  core_facts [storage, storage.arena]
  core_call_framed (RunsExpr.callEffect (MemoryEffect.scopeStable _)) expectedNodeSource as callee
  apply RunsStmt.letEffect (MemoryEffect.scopeStable _) (value := storage.arena.value)
  · rw [← storage.arenaValue]; core_run
  · core_formed
  · apply RunsStmt.letEffect (MemoryEffect.scopeStable _)
      (value := .rawSlice expressionNodeType storage.arena.nodes storage.arena.capacity)
    · core_run
    · core_formed
    · apply RunsStmt.guardEffectFalse (MemoryEffect.scopeStable _)
      · core_pure_guard
      · intro bounded boundFrame
        apply RunsStmt.letFramedEffect (MemoryEffect.scopeStable _)
        · core_pure_expr
        · intro selected nodeFrame
          apply RunsStmt.guardEffectFalse (MemoryEffect.scopeStable _)
          · core_pure_guard
          · intro notPointer pointerFrame
            apply RunsStmt.guardEffectFalse (MemoryEffect.scopeStable _)
            · core_pure_guard
            · intro notUsizeLiteral literalFrame
              apply RunsStmt.guardEffectFalse (MemoryEffect.scopeStable _)
              · core_pure_guard
              · intro notUsizeBinary binaryFrame
                apply RunsStmt.guardEffectTrue (MemoryEffect.scopeStable _) (by intro impossible; cases impossible)
                · core_pure_guard
                · intro ordinary ordinaryFrame
                  obtain ⟨cached, coldRun, coldEffect⟩ := cold (state := ordinary)
                    (by core_frame) (by core_formed) (by core_frame)
                  have initial : RunsExpr extractedProgram ordinary (expectedNodeSource.bindingInitializer 8)
                      (known kind) cached := RunsExpr.callArguments (by core_arguments) coldRun
                  have cachedFormed := coldEffect.1.after_cellsWellFormed (show ordinary.CellsWellFormed from by core_formed)
                  have cachedExpected : cached.local? (expectedNodeSource.argumentId 3) = some (referenceValue kind) :=
                    coldRun.localFound coldEffect.1 (by core_local)
                  let inferred := cached.bindLocal (expectedNodeSource.bindingId 8) (known kind)
                  have inferredFormed : inferred.CellsWellFormed :=
                    cachedFormed.bindLocal _ _
                  have inferredFound := cachedFormed.bindLocal_local
                    (expectedNodeSource.bindingId 8) (known kind)
                  have typeHere := IRExpressionKindProof.actualType (before := inferred) .KnownExpression kind inferredFormed
                  obtain ⟨completed, tailRun, tailEffect⟩ : ∃ completed,
                      RunsStmt extractedProgram inferred (expectedNodeSource.bindingStatement 9)
                        (.returned (some (.signed .i32 next))) completed ∧ MemoryEffect relation inferred completed := by
                    apply RunsStmt.letFramedEffect (MemoryEffect.scopeStable _) (value := referenceValue kind)
                    · core_pure_expr
                    · intro actualState actualFrame
                      apply RunsStmt.guardEffectFalse (MemoryEffect.scopeStable _)
                      · core_pure_guard
                      · intro validState validFrame
                        apply RunsStmt.guardEffectFalse (MemoryEffect.scopeStable _)
                        · core_pure_guard
                        · intro matched matchFrame
                          have preserve {id : VarId} {value : Value}
                              (different8 : expectedNodeSource.bindingId 8 ≠ id)
                              (different9 : expectedNodeSource.bindingId 9 ≠ id)
                              (found : ordinary.local? id = some value) : matched.local? id = some value := by
                            exact matchFrame.localFound (validFrame.localFound
                              (State.bindLocal_local?_of_ne actualState actualFrame.afterFormed
                                id (expectedNodeSource.bindingId 9) value (referenceValue kind) different9
                                (actualFrame.localFound (State.bindLocal_local?_of_ne cached cachedFormed
                                  id (expectedNodeSource.bindingId 8) value (known kind) different8
                                  (coldRun.localFound coldEffect.1 found)))))
                          exact finish (by core_frame) coldEffect
                            (coldEffect.2.2.1.trans (by core_frame))
                            (by core_frame) (by core_formed) (by core_frame)
                            (preserve (by decide) (by decide) (by core_local))
                            (preserve (by decide) (by decide) (by core_local))
                            (preserve (by decide) (by decide) (by core_local))
                            (preserve (by decide) (by decide) (by core_local))
                            (preserve (by decide) (by decide) (by core_local))
                            (preserve (by decide) (by decide) (by core_local))
                            (preserve (by decide) (by decide) (by core_local))
                  refine ⟨restoreLocals cached completed, RunsStmt.letLocal initial tailRun,
                    (coldEffect.1.trans (FreshCellFrame.bindLocal cached _ _)).trans tailEffect.1,
                    tailEffect.2.1.trans coldEffect.2.1, tailEffect.2.2.1.trans coldEffect.2.2.1, ?_⟩
                  exact ⟨cached.heap, coldEffect.2.2.2, tailEffect.2.2.2⟩

#print axioms actualExpectedWith

/-- Discharge the ordinary1247 suffix once: one real typed call followed by
    the second real root annotation. Source cases supply cold/typed contracts,
    not seven local-binding proofs or an assumed annotation execution. -/
theorem actualExpectedEmittingWith {coldRelation typedRelation : Heap → Heap → Prop}
    (input : Inputs) (workspace : Workspace) (locals : Value)
    (storage : ScalarStorage workspace before slots) (count root depth next : Nat)
    (inside : root < count) (bound : count ≤ storage.arena.capacity) (positive : 0 < depth)
    (tag : Value) (natural : tag = literalTag ∨ tag = unaryTag) (operator : Value) (fields : List Value)
    (native : readRawSliceIndex extractedProgram before expressionNodeType storage.arena.nodes storage.arena.capacity root =
      .ok (.structure (match expressionNodeType with | .structure id => id | _ => 0) (tag :: operator :: fields)))
    (kind : Reference) (scalar : kind = .Bool ∨ kind = .I32)
    (output : IREventStoreProof.Context before)
    (cold : ∀ {state : State}, state.heap = before.heap → state.CellsWellFormed →
      state.i32ArrayViews = before.i32ArrayViews → ∃ cached, RunsExpr extractedProgram state
        (.call Extracted.«lowering::body_expression».Functions.«expression_kind».core.id
          ([bodyContext input workspace locals, .signed .i32 count, .signed .i32 root,
            .signed .i32 depth].map Expr.value)) (known kind) cached ∧ MemoryEffect coldRelation state cached)
    (coldAllowed typedAllowed : Nat → Prop)
    (coldWrites : ∀ first last, coldRelation first last → HeapWritesOn first last coldAllowed)
    (typed : ∀ {origin cached : State}, origin.heap = before.heap → MemoryEffect coldRelation origin cached →
      cached.i32ArrayViews = before.i32ArrayViews → ∀ {state : State}, state.heap = cached.heap →
      state.CellsWellFormed → state.i32ArrayViews = cached.i32ArrayViews → ∃ after,
      RunsExpr extractedProgram state (typedCall input workspace locals count root depth output.value output.position)
        (.signed .i32 next) after ∧
      MemoryEffect (fun first last => typedRelation first last ∧ HeapWritesOn first last typedAllowed) state after)
    (formed : before.CellsWellFormed) (noViews : before.i32ArrayViews = []) :
    ∃ after, RunsExpr extractedProgram before
      (expectedNodeCall input workspace locals count root depth kind output.value output.position)
      (.signed .i32 next) after ∧ MemoryEffect (fun first last => ∃ cached emitted,
        coldRelation first cached ∧ typedRelation cached emitted ∧
        IRResultTypeProof.Recorded (IRResultTypeProof.annotationSlot output) kind emitted last) before after := by
  obtain ⟨after, run, effect⟩ := actualExpectedWith
    (relation := fun first last => ∃ emitted, typedRelation first emitted ∧
      IRResultTypeProof.Recorded (IRResultTypeProof.annotationSlot output) kind emitted last)
    input workspace locals storage count root depth output.position next
    inside bound positive tag natural operator fields native kind scalar output.value cold (by
      intro origin cached sameOrigin coldEffect cachedViews state heap cells views
        contextFound countFound rootFound kindFound outputFound positionFound depthFound
      obtain ⟨emitted, typedRun, typedEffect⟩ := typed sameOrigin coldEffect cachedViews heap cells views
      have initial : RunsExpr extractedProgram state (expectedNodeSource.bindingInitializer 12)
          (.signed .i32 next) emitted := RunsExpr.callArguments (by core_arguments) typedRun
      let annotating := emitted.bindLocal (expectedNodeSource.bindingId 12) (.signed .i32 next)
      have emittedOutput := typedRun.localFound typedEffect.1 outputFound
      have emittedPosition := typedRun.localFound typedEffect.1 positionFound
      have emittedKind := typedRun.localFound typedEffect.1 kindFound
      have cachedWrites : HeapWritesOn before.heap cached.heap coldAllowed := by
        simpa only [sameOrigin] using coldWrites _ _ coldEffect.2.2.2
      let selected : IREventStoreProof.Context annotating := {
        output with
        eventRoom := typedEffect.2.2.2.2.readable _ _ (by rw [heap]; exact cachedWrites.readable _ _ output.eventRoom)
        typeRoom := fun enabled => typedEffect.2.2.2.2.readable _ _
          (by rw [heap]; exact cachedWrites.readable _ _ (output.typeRoom enabled)) }
      have annotatingFormed := (typedEffect.1.after_cellsWellFormed cells).bindLocal
        (expectedNodeSource.bindingId 12) (.signed .i32 next)
      have nextFound := (typedEffect.1.after_cellsWellFormed cells).bindLocal_local
        (expectedNodeSource.bindingId 12) (.signed .i32 next)
      have valid : 0 ≤ typeCode kind := by rcases scalar with rfl | rfl <;> decide
      obtain ⟨completed, annotationRun, annotationEffect⟩ := actualAnnotateResult selected next kind valid
        annotatingFormed typedEffect.2.2.2.2.unique
        (typedEffect.2.2.1.trans (views.trans (cachedViews.trans noViews)))
      change RunsExpr extractedProgram annotating
        (.call Extracted.«lowering::body_expression».Functions.«annotate_result».core.id
          ([output.value, .signed .i32 output.position, .signed .i32 next, referenceValue kind].map Expr.value))
        (.signed .i32 next) completed at annotationRun
      have localAnnotation : RunsExpr extractedProgram annotating
          (match expectedNodeSource.bindingStatement 12 with
            | .letLocal _ _ _ (.returnValue (some expression)) => expression | _ => .value .unit)
          (.signed .i32 next) completed := by
        apply RunsExpr.callArguments (middle := annotating)
          (values := [output.value, .signed .i32 output.position, .signed .i32 next, referenceValue kind])
        · core_arguments
        · exact annotationRun
      exact ⟨restoreLocals emitted completed, RunsStmt.letLocal initial (RunsStmt.returnValue localAnnotation),
        (typedEffect.1.trans (FreshCellFrame.bindLocal emitted _ _)).trans annotationEffect.1,
        annotationEffect.2.1.trans typedEffect.2.1, annotationEffect.2.2.1.trans typedEffect.2.2.1,
        emitted.heap, typedEffect.2.2.2.1, annotationEffect.2.2.2⟩) formed
  obtain ⟨cached, first, emitted, second, record⟩ := effect.2.2.2
  exact ⟨after, run, effect.1, effect.2.1, effect.2.2.1, cached, emitted, first, second, record⟩

#print axioms actualExpectedEmittingWith

end IRBodyProductionScalar
