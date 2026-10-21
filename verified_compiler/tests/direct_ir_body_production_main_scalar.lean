import verified_compiler.tests.direct_ir_body_production_scalar_typed
import verified_compiler.tests.direct_ir_body_production_scalar_expected

namespace IRBodyProductionScalar

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRBodyProductionInputs IRTypeRefProof IRExpressionKindProof
open IRTypeCacheProof IRTypeCacheStoreProof
open IRTypeCacheFillProof (Literal)
open IRBodyProductionProof (ReturnBody)

variable {before after : State} {input : Inputs}

private theorem depthValue (depth : Nat) (fits : depth < 2 ^ 31) :
    (Int32.ofNat depth).toInt = depth := by
  rw [Int32.toInt_ofNat']
  change (depth : Int).bmod 4294967296 = depth
  apply Int.bmod_eq_of_le <;> omega

private theorem countLeRoute (original : OriginalScalar input before surface expression route) :
    scalarCount expression ≤ route.length := by
  induction original with
  | boolean => simp only [scalarCount, List.length_cons, List.length_nil, Nat.le_refl]
  | integer => simp only [scalarCount, List.length_cons, List.length_nil, Nat.le_refl]
  | negative node production count child kind payload minus minusKind minusPayload minusSpelling operand ih =>
      simp only [scalarCount, List.length_cons] at ih ⊢
      omega
  | wrapper node production slot selected inside child kind payload operand ih =>
      simp only [List.length_cons]
      omega
  | binaryEnd node count left leftKind leftPayload tail tailKind tailPayload ending production operand ih =>
      simp only [List.length_cons]
      omega

/-- The live root entry and the narrower cache footprint are consequences of
    cold inference on the arena actually built and cleared by1249. -/
private def ColdRoot (storage : ScalarStorage workspace initial slots) (count root : Nat)
    (used : count ≤ slots) (inside : root < count) (depth : Int32) (positive : 0 < depth.toInt)
    (kind : Reference) (first last : Heap) : Prop :=
  (∃ middle, Stored (storage.cacheQuery count used root inside depth positive) kind middle last) ∧
  HeapWritesOn first last storage.cacheWrites

private theorem inferProduced (spelling : ScalarSpelling expression kind)
    (storage : ScalarStorage workspace before (scalarCount expression))
    (token : Nat) (prepared : PreparedNodes storage (scalarCount expression) (scalarNodes expression token)
      origin before.heap) (locals : Value) (depth : Nat)
    (enough : scalarCount expression < depth) (fits : depth < 2 ^ 31)
    (formed : before.CellsWellFormed) (unique : HeapBlockBasesUnique before.heap)
    (noViews : before.i32ArrayViews = []) :
    ∃ cached, RunsExpr extractedProgram before
      (inferenceCall input workspace locals (scalarCount expression) (scalarRoot expression) (Int32.ofNat depth))
      (known kind) cached ∧ MemoryEffect
        (ColdRoot storage (scalarCount expression) (scalarRoot expression) (Nat.le_refl _)
          (by unfold scalarRoot scalarCount; split <;> omega) (Int32.ofNat depth)
          (by rw [depthValue depth fits]; have := storage.positive; omega) kind) before cached := by
  have represented := depthValue depth fits
  have positive : 0 < (Int32.ofNat depth).toInt := by rw [represented]; omega
  have nodes index inside := ProducedNodes.nodeRead (before := { before with heap := origin })
    storage prepared.1 (Nat.le_refl _) index inside
  have cleared (index : Nat) (inside : index < scalarCount expression) :
      readRawSliceIndex extractedProgram before (.scalar (.signed .i32))
      storage.codes storage.arena.capacity index = .ok (.signed .i32 (-1)) := by
    simpa only [readRawSliceIndex] using prepared.2 index inside
  let fields : Fin 4 → Value := fun index =>
    if index = 2 then .signed .i32 (Int32.ofNat token).toInt else .signed .i32 (-1)
  cases spelling with
  | boolean flag =>
      simp only [scalarCount, scalarRoot] at nodes cleared enough ⊢
      obtain ⟨cached, run, effect⟩ := actualInferLiteral storage input locals 1 (Nat.le_refl _) 0 (by decide)
        (Int32.ofNat depth) positive (.boolean flag) fields
        (by
          change readRawSliceIndex extractedProgram before expressionNodeType storage.arena.nodes
            storage.arena.capacity 0 = .ok (literalNode (.boolean flag) (Int32.ofNat token))
          exact nodes 0 (by decide)) (cleared 0 (by decide))
        formed unique noViews
      exact ⟨cached, run, effect.1, effect.2.1, effect.2.2.1, ⟨before.heap, effect.2.2.2⟩,
        storage.storedFootprint (count := 1) (root := 0) (Nat.le_refl _) (by decide)
          _ positive effect.2.2.2⟩
  | decimal spelled bound =>
      simp only [scalarCount, scalarRoot] at nodes cleared enough ⊢
      obtain ⟨cached, run, effect⟩ := actualInferLiteral storage input locals 1 (Nat.le_refl _) 0 (by decide)
        (Int32.ofNat depth) positive .integer fields
        (by
          change readRawSliceIndex extractedProgram before expressionNodeType storage.arena.nodes
            storage.arena.capacity 0 = .ok (literalNode .integer (Int32.ofNat token))
          exact nodes 0 (by decide)) (cleared 0 (by decide))
        formed unique noViews
      exact ⟨cached, run, effect.1, effect.2.1, effect.2.2.1, ⟨before.heap, effect.2.2.2⟩,
        storage.storedFootprint (count := 1) (root := 0) (Nat.le_refl _) (by decide)
          _ positive effect.2.2.2⟩
  | negative spelled bound =>
      simp only [scalarCount, scalarRoot] at nodes cleared enough ⊢
      have childRepresented : (Int32.ofNat (depth - 1)).toInt = (depth - 1 : Nat) := by
        exact depthValue (depth - 1) (by omega)
      have childPositive : 0 < (Int32.ofNat (depth - 1)).toInt := by rw [childRepresented]; omega
      obtain ⟨cached, run, effect⟩ := actualInferNegative storage input locals (Int32.ofNat depth)
        (Int32.ofNat (depth - 1)) childPositive (by rw [represented, childRepresented]; omega) fields
        (by
          change readRawSliceIndex extractedProgram before expressionNodeType storage.arena.nodes
            storage.arena.capacity 0 = .ok (literalNode .integer (Int32.ofNat token))
          exact nodes 0 (by decide))
        (by
          have parent := nodes 1 (by decide)
          change readRawSliceIndex extractedProgram before expressionNodeType storage.arena.nodes
            storage.arena.capacity 1 = .ok negateNode
          exact parent) cleared formed unique noViews
      obtain ⟨middle, child, root⟩ := effect.2.2.2
      exact ⟨cached, run, effect.1, effect.2.1, effect.2.2.1, ⟨middle, root⟩,
        (storage.storedFootprint (count := 2) (root := 0) (Nat.le_refl _) (by decide)
          _ childPositive child).trans
          (storage.storedFootprint (count := 2) (root := 1) (Nat.le_refl _) (by decide)
            _ positive root)⟩

private def UntypedHeap (input : Inputs) (storage : ScalarStorage workspace initial slots)
    (output : IREventStoreProof.Context initial) (body : ReturnBody)
    (permissions : OutputPermissions output body.count) (first last : Heap) : Prop :=
  (∀ index, 1 ≤ index → index < body.count → NativeSnapshot 64 extractedProgram last
    IREventStoreProof.eventType (permissions.eventBases index) (body.event index) 40) ∧
  (output.enabled = true → ∀ index, 2 ≤ index → index < body.count → NativeSnapshot 64 extractedProgram last
    IREventStoreProof.referenceType (permissions.typeBases index) (referenceValue input.signature.result) 16) ∧
  HeapWritesOn first last (fun address => storage.writes address ∨ permissions.writesFrom 1 address)

private theorem natBits (number : Nat) :
    (Int32.ofInt number).toBitVec = (Int32.ofNat number).toBitVec :=
  BitVec.ofInt_ofNat 32 number

private theorem appendFootprint (storage : ScalarStorage workspace initial slots)
    (permissions : OutputPermissions output used)
    (index : Nat) (lower : 1 ≤ index) (inside : index < used)
    (effect : IREventStoreProof.appendHeapEffect output.enabled (permissions.eventBases index)
      (permissions.typeBases index) event first last) :
    HeapWritesOn first last (fun address => storage.writes address ∨ permissions.writesFrom 1 address) :=
  effect.footprint.weaken (fun address range => Or.inr ⟨index, lower, inside, range⟩)

private theorem singleUntyped (storage : ScalarStorage workspace initial slots)
    (permissions : OutputPermissions output body.count) (two : body.count = 2)
    (event : body.event 1 = payload)
    (effect : IREventStoreProof.appendHeapEffect output.enabled (permissions.eventBases 1)
      (permissions.typeBases 1) payload first last) : UntypedHeap input storage output body permissions first last := by
  refine ⟨?_, ?_, appendFootprint storage permissions 1 (Nat.le_refl _) (by omega) effect⟩
  · intro index lower upper
    have one : index = 1 := by omega
    subst index
    rw [event]
    exact effect.1
  · intro enabled index lower upper
    omega

/-- Untyped emission is derived from original spelling and the produced native
    arena. The same body selects every native payload, including MIN's collapse. -/
private theorem emitSelected (spelling : ScalarSpelling expression kind) (body : ReturnBody)
    (selected : spelling.Selects body) (declared : kind = input.signature.result)
    (storage : ScalarStorage workspace before (scalarCount expression))
    (sourceToken : ScalarToken input before expression token)
    (produced : ProducedNodes storage (scalarCount expression) (scalarNodes expression token) origin before.heap)
    (output : IREventStoreProof.Context before) (permissions : OutputPermissions output body.count)
    (locals : Value) (depth : Nat) (enough : scalarCount expression < depth)
    (formed : before.CellsWellFormed) (unique : HeapBlockBasesUnique before.heap)
    (noViews : before.i32ArrayViews = []) :
    ∃ after, RunsExpr extractedProgram before
      (untypedCall input workspace locals (scalarCount expression) (scalarRoot expression) depth output.value 1)
      (.signed .i32 body.count) after ∧ MemoryEffect (UntypedHeap input storage output body permissions) before after := by
  have minusOne : (-1 : Int32).toInt = (-1 : Int) := by decide +kernel
  have nodes index inside := ProducedNodes.nodeRead (before := { before with heap := origin })
    storage produced (Nat.le_refl _) index inside
  cases selected with
  | boolean flag =>
      change 1 < depth at enough
      let root := permissions.slot (after := before) 1 (by change 1 < 2; decide) (fun _ _ room => room)
      obtain ⟨after, run, effect⟩ := actualUntypedBoolean input workspace locals storage 1 0 depth (by decide)
        storage.bound (by omega) flag (Int32.ofNat token) root
        (by cases flag <;> simpa only [scalarNodes, literalNode, expressionNode, literalKind,
          Literal.operator, IRLiteralLoweringProof.booleanNode, minusOne, Bool.false_eq_true, if_false, if_true]
            using nodes 0 (by change 0 < 1; decide)) formed unique noViews
      exact ⟨after, run, effect.1, effect.2.1, effect.2.2.1,
        singleUntyped storage permissions rfl rfl effect.2.2.2⟩
  | decimal spelled bound =>
      change 1 < depth at enough
      obtain ⟨originalToken⟩ := sourceToken
      have tokenValue := depthValue token (Nat.lt_trans originalToken.inside originalToken.tokensFit)
      let root := permissions.slot (after := before) 1 (by change 1 < 2; decide) (fun _ _ room => room)
      obtain ⟨after, run, effect⟩ := actualUntypedInteger input workspace locals storage 1 0 depth (by decide)
        storage.bound (by omega) originalToken spelled bound root
        (by simpa only [scalarNodes, literalNode, expressionNode, literalKind,
          Literal.operator, IRLiteralLoweringProof.integerNode, tokenValue, minusOne]
            using nodes 0 (by change 0 < 1; decide))
        formed unique noViews
      exact ⟨after, run, effect.1, effect.2.1, effect.2.2.1,
        singleUntyped storage permissions rfl (by simp only [ReturnBody.event, ReturnBody.leaf, natBits]; rfl)
          effect.2.2.2⟩
  | minimum spelled bound minimum =>
      change 2 < depth at enough
      obtain ⟨originalToken⟩ := sourceToken
      have tokenValue := depthValue token (Nat.lt_trans originalToken.inside originalToken.tokensFit)
      let root := permissions.slot (after := before) 1 (by change 1 < 2; decide) (fun _ _ room => room)
      obtain ⟨after, run, effect⟩ := actualUntypedMinimum input workspace locals storage depth (by omega)
        originalToken (by simpa only [minimum] using spelled) root
        (by
          change readRawSliceIndex extractedProgram before expressionNodeType storage.arena.nodes
            storage.arena.capacity 1 = .ok negateNode
          exact nodes 1 (by change 1 < 2; decide))
        (by simpa only [scalarNodes, if_pos rfl, literalNode, expressionNode, literalKind,
          Literal.operator, IRLiteralLoweringProof.integerNode, tokenValue, minusOne, if_true]
            using nodes 0 (by change 0 < 2; decide))
        formed unique noViews
      exact ⟨after, run, effect.1, effect.2.1, effect.2.2.1,
        singleUntyped storage permissions rfl rfl effect.2.2.2⟩
  | negative spelled bound ordinary =>
      change 2 < depth at enough
      obtain ⟨originalToken⟩ := sourceToken
      have tokenValue := depthValue token (Nat.lt_trans originalToken.inside originalToken.tokensFit)
      obtain ⟨after, run, effect⟩ := actualUntypedNegative input workspace locals storage depth 1 (by omega)
        originalToken spelled ordinary permissions (by change 1 < 3; decide) (by change 1 + 1 < 3; decide)
        (by
          change readRawSliceIndex extractedProgram before expressionNodeType storage.arena.nodes
            storage.arena.capacity 1 = .ok negateNode
          exact nodes 1 (by change 1 < 2; decide))
        (by simpa only [scalarNodes, if_pos rfl, literalNode, expressionNode, literalKind,
          Literal.operator, IRLiteralLoweringProof.integerNode, tokenValue, minusOne, if_true]
            using nodes 0 (by change 0 < 2; decide))
        formed unique noViews
      obtain ⟨first, second, head, tail, record, headNative, tailNative⟩ := effect.2.2.2
      change IREventStoreProof.appendHeapEffect output.enabled (permissions.eventBases 1)
        (permissions.typeBases 1) IREventWriteProof.negateEvent before.heap first at head
      change IREventStoreProof.appendHeapEffect output.enabled (permissions.eventBases 2)
        (permissions.typeBases 2) (IREventStoreProof.integer (Int32.ofNat _).toBitVec) first second at tail
      change NativeSnapshot 64 extractedProgram after.heap IREventStoreProof.eventType
        (permissions.eventBases 1) IREventWriteProof.negateEvent 40 at headNative
      change NativeSnapshot 64 extractedProgram after.heap IREventStoreProof.eventType
        (permissions.eventBases 2) (IREventStoreProof.integer (Int32.ofNat _).toBitVec) 40 at tailNative
      change (if output.enabled then
        NativeSnapshot 64 extractedProgram after.heap IRResultTypeProof.referenceType
          (permissions.typeBases 2) (referenceValue .I32) 16 ∧
          HeapRegionWrite second after.heap (permissions.typeBases 2) 16
        else after.heap = second) at record
      have writes := (appendFootprint storage permissions 1 (by decide) (by change 1 < 3; decide) head).trans
        (appendFootprint storage permissions 2 (by decide) (by change 2 < 3; decide) tail)
      refine ⟨after, run, effect.1, effect.2.1, effect.2.2.1, ?_, ?_, ?_⟩
      · intro index lower upper
        have casesIndex : index = 1 ∨ index = 2 := by change index < 3 at upper; omega
        rcases casesIndex with rfl | rfl
        · simpa only [ReturnBody.event, ReturnBody.leaf, ↓reduceIte, Nat.reduceEqDiff] using headNative
        · simpa only [ReturnBody.event, ReturnBody.leaf, natBits, ↓reduceIte, Nat.reduceEqDiff] using tailNative
      · intro enabled index lower upper
        have two : index = 2 := by change index < 3 at upper; omega
        subst index
        have annotated : NativeSnapshot 64 extractedProgram after.heap IREventStoreProof.referenceType
            (permissions.typeBases 2) (referenceValue .I32) 16 ∧
            HeapRegionWrite second after.heap (permissions.typeBases 2) 16 := by
          simpa only [enabled, if_true,
            show IRResultTypeProof.referenceType = IREventStoreProof.referenceType from rfl] using record
        rw [← declared]
        exact annotated.1
      · cases enabled : output.enabled with
        | false =>
            have same : after.heap = second := by
              simpa only [enabled, Bool.false_eq_true, if_false] using record
            rwa [same]
        | true =>
            have result : NativeSnapshot 64 extractedProgram after.heap IREventStoreProof.referenceType
                (permissions.typeBases 2) (referenceValue .I32) 16 ∧
                HeapRegionWrite second after.heap (permissions.typeBases 2) 16 := by
              simpa only [enabled, if_true,
                show IRResultTypeProof.referenceType = IREventStoreProof.referenceType from rfl] using record
            exact writes.trans (result.2.footprint.weaken (fun address range =>
              Or.inr ⟨2, by decide, by change 2 < 3; decide, Or.inr ⟨enabled, range⟩⟩))

private theorem cacheSubset (storage : ScalarStorage workspace state slots)
    (address : Nat) (allowed : storage.cacheWrites address) : storage.writes address := by
  rcases allowed with code | depth
  · exact Or.inr (Or.inr (Or.inl code))
  · exact Or.inr (Or.inr (Or.inr depth))

private theorem tokenAfterFootprint (spelling : ScalarSpelling expression kind)
    (sourceToken : ScalarToken input before expression token)
    (write : HeapWritesOn before.heap after.heap allowed) (apart : InputApart input allowed) :
    ScalarToken input after expression token := by
  cases spelling with
  | boolean flag =>
      obtain ⟨original⟩ := sourceToken
      exact ⟨original.afterFootprint write apart⟩
  | decimal spelled bound =>
      obtain ⟨original⟩ := sourceToken
      exact ⟨original.afterFootprint write apart⟩
  | negative spelled bound =>
      obtain ⟨original⟩ := sourceToken
      exact ⟨original.afterFootprint write apart⟩

/-- The dispatch tag is read from the produced root, not supplied as another
    syntax model. The payload list remains the actual six-word native node. -/
private theorem rootShape (spelling : ScalarSpelling expression kind) (token : Nat) :
    ∃ tag operator fields,
      (tag = (source_value Extracted.«verified::surface_expr».Types.«SurfaceExprKind».«Literal» []) ∨
        tag = (source_value Extracted.«verified::surface_expr».Types.«SurfaceExprKind».«Unary» [])) ∧
      scalarNodes expression token (scalarRoot expression) =
        .structure (match expressionNodeType with | .structure id => id | _ => 0) (tag :: operator :: fields) := by
  cases spelling with
  | boolean flag =>
      refine ⟨literalKind, (Literal.boolean flag).operator, [.signed .i32 (-1), .signed .i32 (-1),
        .signed .i32 (Int32.ofNat token).toInt, .signed .i32 (-1)], Or.inl rfl, ?_⟩
      rfl
  | decimal spelled bound =>
      refine ⟨literalKind, Literal.integer.operator, [.signed .i32 (-1), .signed .i32 (-1),
        .signed .i32 (Int32.ofNat token).toInt, .signed .i32 (-1)], Or.inl rfl, ?_⟩
      rfl
  | negative spelled bound =>
      refine ⟨source_value Extracted.«verified::surface_expr».Types.«SurfaceExprKind».«Unary» [],
        IRUnaryInferenceProof.Operation.negate.sourceValue, [.signed .i32 0,
          .signed .i32 (-1), .signed .i32 (-1), .signed .i32 (-1)], Or.inr rfl, ?_⟩
      rfl

/-- Close1247 from the actual cleared arena. Cold inference establishes the
    warm entry used by1244; untyped emission and both root annotations are real
    calls. Only the SAME selected body's native relation leaves this phase. -/
private theorem expectedSelected (spelling : ScalarSpelling expression kind) (body : ReturnBody)
    (selected : spelling.Selects body) (declared : kind = input.signature.result)
    (storage : ScalarStorage workspace before (scalarCount expression))
    (sourceToken : ScalarToken input before expression token)
    (prepared : PreparedNodes storage (scalarCount expression) (scalarNodes expression token) origin before.heap)
    (output : IREventStoreProof.Context before) (permissions : OutputPermissions output body.count)
    (apart : InputApart input (fun address => storage.writes address ∨ permissions.writesFrom 1 address))
    (locals : Value) (depth : Nat) (enough : scalarCount expression < depth) (fits : depth < 2 ^ 31)
    (formed : before.CellsWellFormed) (unique : HeapBlockBasesUnique before.heap)
    (noViews : before.i32ArrayViews = []) :
    ∃ after, RunsExpr extractedProgram before
      (expectedNodeCall input workspace locals (scalarCount expression) (scalarRoot expression) depth
        input.signature.result output.value 1) (.signed .i32 body.count) after ∧
      MemoryEffect (NaturalExpectedHeap input storage output body permissions) before after := by
  have countPositive : 0 < scalarCount expression := by unfold scalarCount; split <;> decide
  have inside : scalarRoot expression < scalarCount expression := by unfold scalarRoot; omega
  have expressionInside : 1 < body.count := by cases selected <;> simp only [ReturnBody.count] <;> decide
  have scalar : kind = .Bool ∨ kind = .I32 := by cases spelling <;> simp
  have valid : isValidResult kind = true := by rcases scalar with rfl | rfl <;> decide
  have represented := depthValue depth fits
  have positive : 0 < (Int32.ofNat depth).toInt := by rw [represented]; omega
  let coldRelation := ColdRoot storage (scalarCount expression) (scalarRoot expression)
    (Nat.le_refl _) inside (Int32.ofNat depth) positive kind
  let allowed := fun address => storage.writes address ∨ permissions.writesFrom 1 address
  let root := permissions.slot (after := before) 1 expressionInside (fun _ _ room => room)
  obtain ⟨tag, operator, fields, naturalTag, shape⟩ := rootShape spelling token
  have native : readRawSliceIndex extractedProgram before expressionNodeType storage.arena.nodes
      storage.arena.capacity (scalarRoot expression) =
      .ok (.structure (match expressionNodeType with | .structure id => id | _ => 0) (tag :: operator :: fields)) := by
    rw [← shape]
    exact ProducedNodes.nodeRead (before := { before with heap := origin }) storage prepared.1
      (Nat.le_refl _) _ inside
  have cold {state : State} (same : state.heap = before.heap) (cells : state.CellsWellFormed)
      (views : state.i32ArrayViews = before.i32ArrayViews) : ∃ cached,
      RunsExpr extractedProgram state
        (.call Extracted.«lowering::body_expression».Functions.«expression_kind».core.id
          ([bodyContext input workspace locals, .signed .i32 (scalarCount expression),
            .signed .i32 (scalarRoot expression), .signed .i32 depth].map Expr.value))
        (known kind) cached ∧ MemoryEffect coldRelation state cached := by
    have reads : HeapReads before.heap state.heap := by rw [same]; exact HeapReads.refl _
    obtain ⟨cached, run, effect⟩ := inferProduced spelling (storage.afterReads reads) token
      (by
        change PreparedNodes storage (scalarCount expression) (scalarNodes expression token) origin state.heap
        simpa only [same] using prepared) locals depth enough fits cells
      (by rw [same]; exact unique) (views.trans noViews)
    refine ⟨cached, ?_, effect⟩
    simpa only [inferenceCall, represented] using run
  have coldWrites (first last : Heap) (effect : coldRelation first last) :
      HeapWritesOn first last storage.cacheWrites := effect.2
  have typed {first cached : State} (sameOrigin : first.heap = before.heap)
      (coldEffect : MemoryEffect coldRelation first cached)
      (cachedViews : cached.i32ArrayViews = before.i32ArrayViews)
      {state : State} (heap : state.heap = cached.heap) (cells : state.CellsWellFormed)
      (views : state.i32ArrayViews = cached.i32ArrayViews) : ∃ after,
      RunsExpr extractedProgram state
        (typedCall input workspace locals (scalarCount expression) (scalarRoot expression) depth root.value 1)
        (.signed .i32 body.count) after ∧
      MemoryEffect (fun first last => NaturalExpectedHeap input storage output body permissions first last ∧
        HeapWritesOn first last allowed) state after := by
    have changed : HeapWritesOn before.heap state.heap storage.cacheWrites := by
      rw [heap]
      simpa only [sameOrigin] using coldEffect.2.2.2.2
    let reached := storage.afterFootprint changed
    let mapped := permissions.afterFootprint changed
    let reachedRoot := mapped.slot (after := state) 1 expressionInside (fun _ _ room => room)
    have nodes : ProducedNodes storage (scalarCount expression) (scalarNodes expression token) origin state.heap :=
      ProducedNodes.afterCacheWrites storage prepared.1 (Nat.le_refl _) changed
    have currentToken : ScalarToken input state expression token :=
      tokenAfterFootprint spelling sourceToken changed (apart.mono (fun address range =>
        Or.inl (cacheSubset storage address range)))
    have currentUnique := changed.unique
    have currentViews := views.trans (cachedViews.trans noViews)
    have cleared : readRawSliceIndex extractedProgram before (.scalar (.signed .i32))
        storage.codes storage.arena.capacity (scalarRoot expression) = .ok (.signed .i32 (-1)) := by
      simpa only [readRawSliceIndex] using prepared.2 _ inside
    let slot := storage.cacheSlot (scalarCount expression) (Nat.le_refl _) (scalarRoot expression)
      inside (Int32.ofNat depth) positive cleared
    obtain ⟨storedBefore, stored⟩ := coldEffect.2.2.2.1
    let entry : Entry cached := slot.entry kind valid stored
    have warm {ready : State} (same : ready.heap = state.heap) (readyFormed : ready.CellsWellFormed) :
        ∃ after, RunsExpr extractedProgram ready
          (.call Extracted.«lowering::body_expression».Functions.«expression_kind».core.id
            ([bodyContext input workspace locals, .signed .i32 (scalarCount expression),
              .signed .i32 (scalarRoot expression), .signed .i32 depth].map Expr.value))
          (known kind) after ∧ PureFrame ready after := by
      let here : Entry ready := { entry with
        codeRead := by simpa only [readRawSliceIndex, same, heap] using entry.codeRead
        depthRead := by simpa only [readRawSliceIndex, same, heap] using entry.depthRead }
      have reuse := actualReuse reached input locals here rfl rfl rfl readyFormed
      change ∃ after, RunsExpr extractedProgram ready
        (inferenceCall input workspace locals (scalarCount expression) (scalarRoot expression) (Int32.ofNat depth))
        (known kind) after ∧ PureFrame ready after at reuse
      simpa only [inferenceCall, represented] using reuse
    have emit {ready : State} (same : ready.heap = state.heap) (readyFormed : ready.CellsWellFormed)
        (readyViews : ready.i32ArrayViews = state.i32ArrayViews) : ∃ emitted,
        RunsExpr extractedProgram ready
          (untypedCall input workspace locals (scalarCount expression) (scalarRoot expression) depth reachedRoot.value 1)
          (.signed .i32 body.count) emitted ∧
        MemoryEffect (fun first last => UntypedHeap input storage output body permissions first last ∧
          HeapWritesOn first last allowed) ready emitted := by
      have reads : HeapReads state.heap ready.heap := by rw [same]; exact HeapReads.refl _
      obtain ⟨emitted, run, effect⟩ := emitSelected spelling body selected declared (reached.afterReads reads)
        (tokenAfterFootprint spelling currentToken (by rw [same]; exact HeapWritesOn.refl currentUnique)
          (apart.mono (fun address range => range)))
        (by
          change ProducedNodes storage (scalarCount expression) (scalarNodes expression token) origin ready.heap
          simpa only [same] using nodes) ({ output with
          eventRoom := reads.readable (changed.readable _ _ output.eventRoom)
          typeRoom := fun enabled => reads.readable (changed.readable _ _ (output.typeRoom enabled)) })
        (mapped.afterReads reads) locals depth enough readyFormed (by rw [same]; exact currentUnique)
        (readyViews.trans currentViews)
      exact ⟨emitted, run, effect.1, effect.2.1, effect.2.2.1, effect.2.2.2, effect.2.2.2.2.2⟩
    have nativeHere : readRawSliceIndex extractedProgram state expressionNodeType reached.arena.nodes
        reached.arena.capacity (scalarRoot expression) =
        .ok (.structure (match expressionNodeType with | .structure id => id | _ => 0) (tag :: operator :: fields)) := by
      rw [← shape]
      exact ProducedNodes.nodeRead (before := { state with heap := origin }) reached nodes
        (Nat.le_refl _) _ inside
    obtain ⟨after, run, effect⟩ := actualTypedEmittingWith input workspace locals reached
      (scalarCount expression) (scalarRoot expression) depth body.count inside reached.bound (by omega)
      tag naturalTag operator fields nativeHere kind valid reachedRoot warm allowed emit cells currentViews
    obtain ⟨emitted, untyped, recorded⟩ := effect.2.2.2
    have firstWrites : HeapWritesOn before.heap emitted allowed :=
      (changed.weaken (fun address range => Or.inl (cacheSubset storage address range))).trans untyped.2.2
    have complete := NaturalExpectedHeap.recordRoot storage output body permissions expressionInside
      firstWrites.readable untyped.1 untyped.2.1 untyped.2.2 (by
        cases enabled : output.enabled <;>
          simpa only [declared, reachedRoot, mapped, OutputPermissions.afterFootprint,
            OutputPermissions.slot, IRResultTypeProof.annotationSlot, IRResultTypeProof.Recorded,
            enabled, Bool.false_eq_true, if_true, if_false] using recorded)
    exact ⟨after, run, effect.1, effect.2.1, effect.2.2.1, complete, complete.2.2⟩
  obtain ⟨after, run, effect⟩ := actualExpectedEmittingWith input workspace locals storage
    (scalarCount expression) (scalarRoot expression) depth body.count inside storage.bound (by omega)
    tag naturalTag operator fields native kind scalar root cold storage.cacheWrites allowed coldWrites typed formed noViews
  obtain ⟨cached, emitted, inferred, typedHeap, recorded⟩ := effect.2.2.2
  have written : HeapWritesOn before.heap emitted allowed :=
    (inferred.2.weaken (fun address range => Or.inl (cacheSubset storage address range))).trans typedHeap.2.2
  have complete := NaturalExpectedHeap.recordRoot storage output body permissions expressionInside written.readable
    typedHeap.1 (fun enabled index lower upper => typedHeap.2.1 enabled index (by omega) upper) written (by
      cases enabled : output.enabled <;>
        simpa only [declared, root, OutputPermissions.slot, IRResultTypeProof.annotationSlot,
          IRResultTypeProof.Recorded, enabled, Bool.false_eq_true, if_true, if_false] using recorded)
  refine ⟨after, ?_, effect.1, effect.2.1, effect.2.2.1, complete⟩
  simpa only [← declared, root, OutputPermissions.slot, IREventStoreProof.Context.value] using run

/-- Closed actual1251 production from ORIGINAL natural syntax and spelling.
    No extraction, inference, emitter or annotation run is a public premise. -/
theorem actualNaturalExpected (natural : NaturalScalar input before surface) (body : ReturnBody)
    (selected : natural.spelling.Selects body) (declared : natural.result = input.signature.result)
    (storage : ScalarStorage workspace before (scalarCount natural.expression))
    (output : IREventStoreProof.Context before) (permissions : OutputPermissions output body.count)
    (apart : InputApart input (fun address => storage.writes address ∨ permissions.writesFrom 1 address))
    (locals : Value) (depth : Nat) (enough : natural.route.length < depth) (fits : depth < 2 ^ 31)
    (formed : before.CellsWellFormed) (unique : HeapBlockBasesUnique before.heap)
    (noViews : before.i32ArrayViews = []) :
    ∃ after, RunsExpr extractedProgram before
      (naturalExpectedCall input workspace locals surface depth output.value)
      (.signed .i32 body.count) after ∧
      MemoryEffect (NaturalExpectedHeap input storage output body permissions) before after := by
  have usedDepth := Nat.lt_of_le_of_lt (countLeRoute natural.syntax) enough
  have storageApart := apart.mono (fun address range => Or.inl range)
  apply natural.syntax.actualFromSurfaceExpectedWith storage body output permissions storageApart locals depth enough fits
    ?_ formed unique noViews
  intro origin same token sourceToken state prepared cells views
  have written : HeapWritesOn before.heap state.heap storage.writes := by
    simpa only [same] using prepared.1.2.2
  let reached := storage.afterFootprint written
  let mapped := permissions.afterFootprint written
  let selectedOutput : IREventStoreProof.Context state := { output with
    eventRoom := written.readable _ _ output.eventRoom
    typeRoom := fun enabled => written.readable _ _ (output.typeRoom enabled) }
  have originalWrites : HeapWritesOn origin.heap state.heap storage.writes := prepared.1.2.2
  have currentToken := tokenAfterFootprint natural.spelling sourceToken originalWrites storageApart
  have result := expectedSelected natural.spelling body selected declared reached currentToken prepared selectedOutput
    mapped apart locals depth usedDepth fits cells written.unique (views.trans noViews)
  obtain ⟨after, run, effect⟩ := result
  change MemoryEffect (NaturalExpectedHeap input storage output body permissions) state after at effect
  change RunsExpr extractedProgram state
    (.call Extracted.«lowering::body_expression».Functions.«expression_expected».core.id
      ([bodyContext input workspace locals, .signed .i32 (scalarCount natural.expression),
        .signed .i32 (scalarRoot natural.expression), referenceValue input.signature.result,
        output.value, .signed .i32 1, .signed .i32 depth].map Expr.value))
    (.signed .i32 body.count) after at run
  exact ⟨after, run, effect⟩

#print axioms actualNaturalExpected

end IRBodyProductionScalar
