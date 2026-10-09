import verified_compiler.tests.direct_ir_body_production_main_outer
import verified_compiler.tests.direct_ir_body_production_main_return_result
import verified_compiler.tests.direct_ir_body_production_main_producer
import verified_compiler.tests.direct_ir_body_production_main_frame
import verified_compiler.tests.direct_ir_body_production_main_request
import verified_compiler.tests.direct_ir_body_production_inputs_locals_constructor

namespace IRBodyProductionProof

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRBodyProductionInputs
open IREventStoreProof IRTypeRefProof IRCatalogAppendProof IRCatalogConstructionProof
open IRBodyProductionScalar

private theorem catalogReads (invariant : Invariant catalog next previous before)
    (reads : HeapReads before.heap after.heap) (formed : after.CellsWellFormed)
    (unique : HeapBlockBasesUnique after.heap) (below : HeapBlocksBelowNext after.heap)
    (views : after.i32ArrayViews = []) : Invariant catalog next previous after :=
  ⟨invariant.supported, invariant.bounds, reads.nativeValue invariant.count,
    reads.readable invariant.backing, fun index inside =>
      (invariant.occupied index inside).afterHeapReads reads, formed, unique, below, views⟩

/-- The producer boundary retains one native stream and the same public
    catalog post, not the function's temporary binding identities. -/
def FunctionInsertion (anchor : State) (body : ReturnBody) (output : Context anchor)
    (permissions : OutputPermissions output body.count) (result : Reference) (allowed : Nat → Prop)
    (memory : Nat) (localsHeap : Heap)
    (catalog : Catalog) (next : Int32) (previous : Nat → PreviousRow) (request : Model)
    (before after : State) : Prop :=
  FreshCellFrame before after ∧ ∃ produced,
    TerminalStream body output permissions result memory allowed localsHeap produced.heap ∧
    produced.world = World.record anchor.world .alloc ∧ produced.i32ArrayViews = anchor.i32ArrayViews ∧
    Post (catalog.model next previous request) produced
      ((catalog.model next previous request).answer produced.heap) after.heap after.world after.i32ArrayViews ∧
    Invariant catalog (catalog.afterCount next previous request produced.heap)
      (catalog.afterRows next previous request produced.heap) after

private theorem insertedScopes : ScopeStable
    (FunctionInsertion anchor body output permissions result allowed memory localsHeap catalog next previous request) := by
  constructor
  · intro before middle after frame effect
    exact ⟨frame.cells.trans effect.1, effect.2⟩
  · intro before after caller effect
    obtain ⟨produced, stream, world, views, post, invariant⟩ := effect.2
    exact ⟨effect.1, produced, stream, world, views, post,
      ⟨invariant.supported, invariant.bounds, invariant.count, invariant.backing,
        invariant.occupied, invariant.formed, invariant.unique, invariant.below, invariant.noViews⟩⟩

/-- One actual funded1179 setup/insertion proof for the already source-selected
    body. The terminal producer is an internal phase boundary, discharged from
    original syntax by the final natural-body consumer. -/
theorem actualFundedTerminalWith {caller : State} {catalog : Catalog} {next : Int32}
    {previous : Nat → PreviousRow} (input : Inputs) (workspace : Workspace)
    (topology : TerminalTopology input caller.heap declaration)
    (body : ReturnBody) (valid : isValidResult input.signature.result = true)
    (signature : input.signature.Read caller) (tokenBound : input.tokenCount ≤ 89478484)
    (output : Context caller) (zero : output.position = 0)
    (permissions : OutputPermissions output body.count) (allowed : Nat → Prop)
    (events : workspace.events = output.value) (catalogValue : workspace.catalog = catalog.value)
    (invariant : Invariant catalog next previous caller)
    (available : consumeBudget caller.heap.remaining (localBytes input.tokenCount) = some budget)
    (localFits : caller.heap.allocationAddress 8 + localBytes input.tokenCount < 2 ^ 64)
    (copyFits : ((caller.heap.allocatedBytes (localBytes input.tokenCount) 8 budget).borrowBlock
      (caller.heap.allocationAddress 8)).allocationAddress 8 + body.count * 56 < 2 ^ 64)
    (apart : ∀ address, catalog.memory ≤ address → address < catalog.memory + catalog.bytes →
      ¬allowed address)
    (produce : ∀ {current : State}, HeapReads caller.heap current.heap →
      NativeSnapshot 64 extractedProgram current.heap (.scalar (.signed .i32))
        (caller.heap.allocationAddress 8) (.signed .i32 0) 4 →
      current.heap.Readable (caller.heap.allocationAddress 8) 4 →
      current.CellsWellFormed → HeapBlockBasesUnique current.heap → current.i32ArrayViews = [] → ∃ after,
      RunsExpr extractedProgram current
        (terminalBlockCall (bodyContext input workspace
          (localsValue (caller.heap.allocationAddress 8) input.tokenCount))
          topology.block output.value 0 (input.tree.nodeCount - 1))
        (.signed .i32 body.count) after ∧ MemoryEffect
          (TerminalStream body output permissions input.signature.result
            (caller.heap.allocationAddress 8) allowed) current after) :
    let localHeap := (caller.heap.allocatedBytes (localBytes input.tokenCount) 8 budget).borrowBlock
      (caller.heap.allocationAddress 8)
    let request := streamRequest output (Int32.ofNat input.signature.id) input.signature.result body
      (fun index => if index = 0 then .Invalid else input.signature.result)
    let model := catalog.model next previous request
    ∃ after, RunsExpr extractedProgram caller
      (producerCall input workspace declaration input.tree.nodeCount)
      (.signed .i32 (by classical exact if model.Success localHeap then 0 else -1)) after ∧
      FunctionInsertion caller body output permissions input.signature.result allowed
        (caller.heap.allocationAddress 8) localHeap catalog next previous request caller after ∧
      after.locals = caller.locals := by
  classical
  dsimp only
  let memory := caller.heap.allocationAddress 8
  let localHeap := (caller.heap.allocatedBytes (localBytes input.tokenCount) 8 budget).borrowBlock memory
  let request := streamRequest output (Int32.ofNat input.signature.id) input.signature.result body
    (fun index => if index = 0 then .Invalid else input.signature.result)
  let model := catalog.model next previous request
  let result : Int := if model.Success localHeap then 0 else -1
  let effect := FunctionInsertion caller body output permissions input.signature.result allowed
    memory localHeap catalog next previous request
  suffices complete : ∃ after, RunsExpr extractedProgram caller
      (producerCall input workspace declaration input.tree.nodeCount) (.signed .i32 result) after ∧ effect caller after by
    obtain ⟨after, run, post⟩ := complete
    exact ⟨after, run, post, run.choose_spec.2⟩
  have positive := topology.tokensPositive
  have depth := topology.depth
  have fits := input.tree.nodesFit
  have countFits : body.count < 2 ^ 31 := by cases body <;> simp only [ReturnBody.count] <;> decide
  have countPositive : 0 < body.count := by cases body <;> simp only [ReturnBody.count] <;> decide
  have decrement := eval_i32_subNat extractedProgram.target input.tree.nodeCount 1 (by omega) fits
  have callerFormed := invariant.formed
  have validResult {state : State} (formed : state.CellsWellFormed) : ∃ after,
      RunsExpr extractedProgram state
        (.call Extracted.«ir::type_ref».Functions.«valid_result».core.id
          [.value (referenceValue input.signature.result)]) (.boolean true) after ∧ PureFrame state after := by
    have proof := actualValidResult input.signature.result formed
    change ∃ after, RunsExpr extractedProgram state
      (.call Extracted.«ir::type_ref».Functions.«valid_result».core.id
        [.value (referenceValue input.signature.result)])
      (.boolean (isValidResult input.signature.result)) after ∧ PureFrame state after at proof
    simpa only [valid] using proof
  have bytesCast := eval_unsigned_castNat extractedProgram.target .usize .i32 (localBytes input.tokenCount)
    (by change localBytes input.tokenCount < 2 ^ 64; dsimp only [localBytes]; omega)
  have alignmentCast := eval_unsigned_castNat extractedProgram.target .usize .i32 8 (by decide)
  have idFits : input.signature.id < 2 ^ 31 :=
    Nat.lt_trans input.signature.inside input.signature.fits
  have exactId : (Int32.ofNat input.signature.id).toInt = input.signature.id := by
    rw [Int32.toInt_ofNat']
    change (input.signature.id : Int).bmod 4294967296 = input.signature.id
    apply Int.bmod_eq_of_le <;> omega
  have signatureRead := signature
  unfold Signature.Read at signatureRead
  core_facts [input.signature]
  core_call_framed (RunsExpr.callEffect insertedScopes) producerSource as callee
  repeat first
    | (apply RunsStmt.letEffect insertedScopes; core_run; core_formed)
    | (apply RunsStmt.letFramedEffect insertedScopes; core_pure_expr; intro ready frame)
  apply RunsStmt.guardEffectFalse insertedScopes
  · core_pure_guard
  intro supported guardFrame
  repeat first
    | (apply RunsStmt.letEffect insertedScopes; core_run; core_formed)
    | (apply RunsStmt.letFramedEffect insertedScopes; core_pure_expr; intro ready frame)
  core_state ready
  have readyHeap : ready.heap = caller.heap := by core_frame
  have readyWorld : ready.world = caller.world := by core_frame
  have readyViews : ready.i32ArrayViews = caller.i32ArrayViews := by core_frame
  have readyFormed : ready.CellsWellFormed := by core_formed
  have bytesFound : ready.local? (producerSource.bindingId 20) =
      some (.unsigned .usize (localBytes input.tokenCount)) := by core_local
  have alignmentFound : ready.local? (producerSource.bindingId 21) =
      some (.unsigned .usize 8) := by core_local
  have readyDepth : ready.local? (producerSource.argumentId 4) =
      some (.signed .i32 input.tree.nodeCount) := by core_local
  let allocated := { ready with
    heap := ready.heap.allocatedBytes (localBytes input.tokenCount) 8 budget
    world := World.record ready.world .alloc }
  have allocation : RunsExpr extractedProgram ready (producerSource.bindingInitializer 22) (.pointer memory) allocated := by
    apply RunsExpr.callArguments
      (values := [.unsigned .usize (localBytes input.tokenCount), .unsigned .usize 8]) (by core_arguments)
    change RunsExpr extractedProgram ready (.call Extracted.«verified::host».Functions.«alloc».core.id
      [.value (.unsigned .usize (localBytes input.tokenCount)), .value (.unsigned .usize 8)])
      (.pointer memory) allocated
    simpa only [allocated, readyHeap, memory, List.map] using actualLocalAllocation input.tokenCount
      (by rw [readyHeap]; exact available) (readyViews.trans invariant.noViews)
  let bound := allocated.bindLocal (producerSource.bindingId 22) (.pointer memory)
  let tail := match producerSource.bindingStatement 22 with | .letLocal _ _ _ rest => rest | _ => .skip
  suffices rest : ∃ after, RunsStmt extractedProgram bound tail
      (.returned (some (.signed .i32 result))) after ∧ effect bound after by
    obtain ⟨after, run, post⟩ := rest
    exact ⟨restoreLocals allocated after, RunsStmt.letLocal allocation run,
      (show FreshCellFrame ready bound from FreshCellFrame.bindLocal allocated _ _).trans post.1,
      (insertedScopes.restore allocated post).2⟩
  have nonnull : memory ≠ 0 := Nat.ne_of_gt (caller.heap.allocationAddress_pos (by decide : 0 < 8))
  have pointerFound : bound.local? (producerSource.bindingId 22) = some (.pointer memory) :=
    State.bindLocal_local? allocated (by change ready.CellsWellFormed; exact readyFormed) _ _
  apply RunsStmt.guardEffectFalse insertedScopes
  · core_pure_guard
  intro entered frame
  have enteredHeap : entered.heap = caller.heap.allocatedBytes (localBytes input.tokenCount) 8 budget := by
    simpa only [bound, allocated, State.bindLocal, State.bindCell, readyHeap] using frame.heap
  have enteredViews : entered.i32ArrayViews = [] := by
    exact (frame.views.trans readyViews).trans invariant.noViews
  obtain ⟨constructed, constructorRun, constructorEffect⟩ := actualLocalConstructor
    (before := entered) (origin := caller.heap) (budget := budget) input.tokenCount positive tokenBound
    enteredHeap invariant.below invariant.unique localFits (by core_formed)
    enteredViews
  have initialization : RunsExpr extractedProgram entered (producerSource.bindingInitializer 23)
      (localsValue memory input.tokenCount) constructed := by
    apply RunsExpr.callArguments (values := [.pointer memory, .signed .i32 input.tokenCount]) (by core_arguments)
    change RunsExpr extractedProgram entered (.call localsConstructor.id
      [.value (.pointer memory), .value (.signed .i32 input.tokenCount)])
      (localsValue memory input.tokenCount) constructed
    simpa only [memory, List.map] using constructorRun
  let localState := constructed.bindLocal (producerSource.bindingId 23) (localsValue memory input.tokenCount)
  have constructorCells := constructorEffect.1
  have constructedDepth := constructorCells.localFound initialization.choose_spec.2
    (producerSource.argumentId 4) (.signed .i32 input.tree.nodeCount)
    (frame.localFound (State.bindLocal_local?_of_ne allocated
      (show allocated.CellsWellFormed from readyFormed)
      (producerSource.argumentId 4) (producerSource.bindingId 22)
      (.signed .i32 input.tree.nodeCount) (.pointer memory) (by decide)
      (show allocated.local? (producerSource.argumentId 4) =
        some (.signed .i32 input.tree.nodeCount) from readyDepth)))
  have storage := constructorEffect.2.2.2.2.1
  have constructedHeap : constructed.heap = localHeap := by
    simpa only [enteredHeap, memory, localHeap] using constructorEffect.2.2.2.1
  have constructedWorld : constructed.world = World.record caller.world .alloc := by
    simpa only [bound, allocated, State.bindLocal, State.bindCell, readyWorld] using
      constructorEffect.2.1.trans frame.world
  let currentTopology := topology.afterReads storage.reads
  have bodyQuery {current : State} (same : current.heap = constructed.heap) (formed : current.CellsWellFormed) :=
    actualFunctionBody currentTopology.declarationNode currentTopology.declarationProduction currentTopology.declarationBound
      currentTopology.bodyChild currentTopology.bodyKind same formed
  suffices continued : ∃ after, RunsStmt extractedProgram localState (producerSource.bindingStatement 24)
      (.returned (some (.signed .i32 result))) after ∧ effect localState after by
    obtain ⟨after, run, post⟩ := continued
    exact ⟨restoreLocals constructed after, RunsStmt.letLocal initialization run,
      (constructorCells.trans (FreshCellFrame.bindLocal constructed _ _)).trans post.1,
      (insertedScopes.restore constructed post).2⟩
  apply RunsStmt.letFramedEffect insertedScopes
    (value := bodyContext input workspace (localsValue memory input.tokenCount))
  · core_pure_expr
  intro contextual contextFrame
  apply RunsStmt.letEffect insertedScopes (value := .signed .i32 0)
  · core_run
  · core_formed
  core_state parameters
  suffices afterParameters : ∃ after, RunsStmt extractedProgram parameters (producerSource.bindingStatement 29)
      (.returned (some (.signed .i32 result))) after ∧ effect parameters after by
    obtain ⟨after, run, post⟩ := afterParameters
    exact ⟨after, RunsStmt.sequenceNext (RunsStmt.whileFalse (by core_run)) run, post⟩
  apply RunsStmt.letFramedEffect insertedScopes (value := .signed .i32 topology.block)
  · apply RunsExpr.callPureArguments
      (values := [input.tree.value, .signed .i32 declaration]) (by core_arguments)
    change ∃ after, RunsExpr extractedProgram parameters
      (.call Extracted.«verified::surface_declaration».Functions.«function_body».core.id
        [.value input.tree.value, .value (.signed .i32 declaration)])
      (.signed .i32 topology.block) after ∧ PureFrame parameters after
    simpa only [currentTopology, TerminalTopology.afterReads, NativeChild.afterReads,
      topology.bodyIndex] using bodyQuery (current := parameters) (by core_frame) (by core_formed)
  intro queried frame
  core_state producing
  have producingHeap : producing.heap = constructed.heap := by core_frame
  have producingWorld : producing.world = World.record caller.world .alloc := by
    exact (by core_frame : producing.world = constructed.world).trans constructedWorld
  have producingViews : producing.i32ArrayViews = caller.i32ArrayViews := by core_frame
  have reads : HeapReads caller.heap producing.heap := by rw [producingHeap]; exact storage.reads
  have producingInvariant := catalogReads invariant reads (by core_formed)
    (by rw [producingHeap]; exact storage.unique) (by rw [producingHeap]; exact storage.below)
    (producingViews.trans invariant.noViews)
  have workspaceFound : producing.local? (producerSource.argumentId 1) = some workspace.value := by core_local
  have idFound : producing.local? (producerSource.argumentId 3) = some (.signed .i32 input.signature.id) := by core_local
  have recordFound : producing.local? (producerSource.bindingId 18) =
      some (signatureRecord input.signature.id input.signature.result) := by core_local
  have arityFound : producing.local? (producerSource.bindingId 19) = some (.signed .i32 0) := by core_local
  have outputFound : producing.local? (producerSource.bindingId 16) = some output.value := by
    simpa only [events] using
      (show producing.local? (producerSource.bindingId 16) = some workspace.events from by core_local)
  have contextFound : producing.local? (producerSource.bindingId 24) =
      some (bodyContext input workspace (localsValue memory input.tokenCount)) := by core_local
  have bodyFound : producing.local? (producerSource.bindingId 29) = some (.signed .i32 topology.block) := by core_local
  have depthFound : producing.local? (producerSource.argumentId 4) = some (.signed .i32 input.tree.nodeCount) := by core_local
  have fresh : caller.heap.nextAddress ≤ memory := caller.heap.allocationAddress_ge (by decide : 0 < 8)
  have catalogExtent : catalog.memory + catalog.bytes ≤ caller.heap.nextAddress :=
    invariant.backing.belowNext (by change 0 < 8 + catalog.length * 96; omega) invariant.below
  have catalogFresh : catalog.memory + catalog.bytes ≤ memory := Nat.le_trans catalogExtent fresh
  obtain ⟨produced, production, streamEffect⟩ := produce reads
    (by rw [producingHeap]; exact storage.count)
    (by rw [producingHeap]; exact storage.backing.subrange (start := 0) (by simp only [localBytes]; omega))
    producingInvariant.formed producingInvariant.unique producingInvariant.noViews
  have sourceProduction : RunsExpr extractedProgram producing (producerSource.bindingInitializer 30)
      (.signed .i32 body.count) produced := by
    apply RunsExpr.callArguments
      (middle := producing)
      (values := [bodyContext input workspace (localsValue memory input.tokenCount),
        .signed .i32 topology.block, output.value, .signed .i32 0,
        .signed .i32 (input.tree.nodeCount - 1 : Nat)])
      (by core_arguments)
    change RunsExpr extractedProgram producing
      (terminalBlockCall (bodyContext input workspace (localsValue memory input.tokenCount))
        topology.block output.value 0 (input.tree.nodeCount - 1)) (.signed .i32 body.count) produced
    exact production
  have stream : TerminalStream body output permissions input.signature.result memory allowed localHeap produced.heap := by
    simpa only [TerminalStream, producingHeap, constructedHeap, memory] using streamEffect.2.2.2
  have retained := catalogAfterWrites producingInvariant
    (show MemoryEffect (fun old heap => HeapWritesOn old heap _) producing produced from
      ⟨streamEffect.1, streamEffect.2.1, streamEffect.2.2.1, streamEffect.2.2.2.2.2.2⟩)
    (fun address lower upper => by
      have separated := apart address lower upper
      intro inside
      rcases inside with written | count
      · exact separated written
      · exact Nat.not_le_of_lt (Nat.lt_of_lt_of_le upper catalogFresh) count.1)
  let counted := produced.bindLocal (producerSource.bindingId 30) (.signed .i32 body.count)
  have countedFrame := (CallerFrame.refl retained.formed).bindLocal (producerSource.bindingId 30) (.signed .i32 body.count)
  have countedFormed : counted.CellsWellFormed := retained.formed.bindLocal _ _
  have countFound : counted.local? (producerSource.bindingId 30) = some (.signed .i32 body.count) :=
    State.bindLocal_local? produced retained.formed _ _
  let insertionTail := match producerSource.bindingStatement 30 with | .letLocal _ _ _ rest => rest | _ => .skip
  suffices inserted : ∃ after, RunsStmt extractedProgram counted insertionTail
      (.returned (some (.signed .i32 result))) after ∧ effect counted after by
    obtain ⟨after, run, post⟩ := inserted
    exact ⟨restoreLocals produced after, RunsStmt.letLocal sourceProduction run,
      (streamEffect.1.trans (FreshCellFrame.bindLocal produced _ _)).trans post.1,
      (insertedScopes.restore produced post).2⟩
  apply RunsStmt.guardEffectFalse insertedScopes
  · refine ⟨counted, ?_, PureFrame.refl countedFormed⟩
    core_run
  intro insertion frame
  have insertionHeap : insertion.heap = produced.heap := frame.heap.trans countedFrame.heap
  have insertionWorld : insertion.world = produced.world := frame.world.trans countedFrame.world
  have insertionViews : insertion.i32ArrayViews = produced.i32ArrayViews := frame.views.trans countedFrame.views
  have insertionLocal (id : VarId) (value : Value)
      (found : producing.local? id = some value) (different : id ≠ producerSource.bindingId 30) :
      insertion.local? id = some value :=
    frame.localFound (State.bindLocal_local?_of_ne produced retained.formed id (producerSource.bindingId 30)
      value (.signed .i32 body.count) (Ne.symm different) (streamEffect.1.localFound sourceProduction.choose_spec.2 id value found))
  have insertionReads : HeapReads produced.heap insertion.heap := by
    intro pointer offset byte loaded
    simpa only [insertionHeap] using loaded
  have insertionInvariant := catalogReads retained insertionReads frame.afterFormed
    (by simpa only [insertionHeap] using retained.unique) (by simpa only [insertionHeap] using retained.below)
    (insertionViews.trans retained.noViews)
  have insertionStream : TerminalStream body output permissions input.signature.result memory allowed localHeap insertion.heap := by
    simpa only [insertionHeap] using stream
  have evidence : RequestEvidence model insertion insertion.heap := by
    exact streamSnapshotEvidence body output permissions
        (Int32.ofNat input.signature.id) input.signature.result
        (fun index => if index = 0 then .Invalid else input.signature.result)
        insertionStream.1 insertionStream.2.1
        (by simpa only [Heap.allocationAddress, insertionStream.2.2.2.frontier, localHeap, memory] using copyFits)
  have exactCapacity : (Int32.ofNat output.capacity).toInt = output.capacity := by
    rw [Int32.toInt_ofNat']
    change (output.capacity : Int).bmod 4294967296 = output.capacity
    apply Int.bmod_eq_of_le <;> have := output.fits <;> omega
  have requestValues : model.values = [catalog.value,
      source_value Extracted.«ir::body_catalog».Types.«FunctionSignature».mk
        [.signed .i32 input.signature.id, referenceValue input.signature.result, .signed .i32 0],
      output.value, .signed .i32 body.count] := by
    dsimp only [model, Catalog.model, request, streamRequest, ReturnBody.request,
      Arguments.values, Arguments.catalog, Arguments.rows, Arguments.count,
      Arguments.signature, Arguments.region, Catalog.value]
    have countExact : (Int32.ofNat body.count).toInt = body.count := by
      cases body <;> rfl
    simp only [exactId, exactCapacity, Int32.toInt_zero, countExact]
    rfl
  have selectedResult {state : State} (formed : state.CellsWellFormed) : ∃ after,
      RunsExpr extractedProgram state
        (.call Extracted.«lowering::signatures».Functions.«record_result_type».core.id
          [.value (signatureRecord input.signature.id input.signature.result)])
        (referenceValue input.signature.result) after ∧ PureFrame state after := by
    exact actualSignatureResult input.signature.id input.signature.result formed
  have workspaceAtInsertion := insertionLocal (producerSource.argumentId 1) workspace.value workspaceFound (by decide)
  have idAtInsertion := insertionLocal (producerSource.argumentId 3)
    (.signed .i32 input.signature.id) idFound (by decide)
  have recordAtInsertion := insertionLocal (producerSource.bindingId 18)
    (signatureRecord input.signature.id input.signature.result) recordFound (by decide)
  have arityAtInsertion := insertionLocal (producerSource.bindingId 19) (.signed .i32 0) arityFound (by decide)
  have outputAtInsertion := insertionLocal (producerSource.bindingId 16) output.value outputFound (by decide)
  have countAtInsertion := frame.localFound countFound
  simp only [Workspace.value, catalogValue] at workspaceAtInsertion
  let arguments := match producerSource.bindingInitializer 31 with | .call _ args => args | _ => []
  obtain ⟨prepared, preparing, preparation⟩ : ∃ prepared,
      RunsExprs extractedProgram insertion arguments model.values prepared ∧ PureFrame insertion prepared := by
    dsimp only [arguments]
    rw [requestValues]
    core_pure_arguments
  have preparationReads : HeapReads insertion.heap prepared.heap := by
    intro pointer offset byte loaded
    simpa only [preparation.heap] using loaded
  have preparedInvariant := catalogReads insertionInvariant preparationReads preparation.afterFormed
    (by simpa only [preparation.heap] using insertionInvariant.unique)
    (by simpa only [preparation.heap] using insertionInvariant.below)
    (preparation.views.trans insertionInvariant.noViews)
  have preparedEvidence : RequestEvidence model prepared prepared.heap := by
    simpa only [preparation.heap] using evidence.afterReads preparationReads
  obtain ⟨appended, appendRun, appendCells, actualPost, lexical, actualInvariant⟩ :=
    actualMaintainedAppend preparedInvariant request preparedEvidence
  have appendPost : Post model insertion (model.answer insertion.heap) appended.heap appended.world appended.i32ArrayViews := by
    simpa only [preparation.heap] using actualPost.reanchorPure preparation
  have maintained : Invariant catalog (catalog.afterCount next previous request insertion.heap)
      (catalog.afterRows next previous request insertion.heap) appended := by
    simpa only [preparation.heap] using actualInvariant
  have appendedFormed := appendCells.after_cellsWellFormed preparedInvariant.formed
  have appending : RunsExpr extractedProgram insertion (producerSource.bindingInitializer 31)
      (.signed .i32 (model.answer insertion.heap)) appended := by
    apply RunsExpr.callArguments preparing
    change RunsExpr extractedProgram prepared model.call (.signed .i32 (model.answer insertion.heap)) appended
    simpa only [preparation.heap] using appendRun
  have sameSuccess : model.Success insertion.heap ↔ model.Success localHeap := by
    simp only [Model.Success, Arguments.BothAvailable, insertionStream.2.2.2.budget]
  let returned := appended.bindLocal (producerSource.bindingId 31) (.signed .i32 (model.answer insertion.heap))
  let returnTail := match producerSource.bindingStatement 31 with | .letLocal _ _ _ rest => rest | _ => .skip
  obtain ⟨completed, returning, pure⟩ : ∃ completed,
      RunsStmt extractedProgram returned returnTail (.returned (some (.signed .i32 result))) completed ∧
      PureFrame returned completed := by
    change ∃ after, RunsStmt extractedProgram returned producerReturnTail
      (.returned (some (.signed .i32 result))) after ∧ PureFrame returned after
    have answerFound : returned.local? (producerSource.bindingId 31) =
        some (.signed .i32 (model.answer insertion.heap)) :=
      State.bindLocal_local? appended appendedFormed (producerSource.bindingId 31)
        (.signed .i32 (model.answer insertion.heap))
    have returnedFormed : returned.CellsWellFormed := appendedFormed.bindLocal _ _
    by_cases success : model.Success localHeap
    · have actualSuccess := sameSuccess.mpr success
      have nonnegative := invariant.bounds.1
      have answer : model.answer insertion.heap = next.toInt := by
        change (if model.Success insertion.heap then next.toInt else -1) = next.toInt
        exact if_pos actualSuccess
      have found := answerFound.trans (congrArg (fun value : Int => some (Value.signed .i32 value)) answer)
      simpa only [result, if_pos success, if_pos nonnegative] using
        actualProducerReturn (before := returned) next found returnedFormed
    · have actualReject := fun successful => success (sameSuccess.mp successful)
      have negative : (Int32.ofInt (-1)).toInt = -1 := by decide
      have answer : model.answer insertion.heap = (Int32.ofInt (-1)).toInt := by
        change (if model.Success insertion.heap then next.toInt else -1) = (Int32.ofInt (-1)).toInt
        rw [if_neg actualReject, negative]
      have found := answerFound.trans (congrArg (fun value : Int => some (Value.signed .i32 value)) answer)
      simpa only [result, if_neg success, negative,
        if_neg (by decide : ¬0 ≤ (-1 : Int))] using
        actualProducerReturn (before := returned) (Int32.ofInt (-1)) found returnedFormed
  have finalHeap : (restoreLocals appended completed).heap = appended.heap := by
    change completed.heap = appended.heap
    exact pure.heap
  have finalWorld : (restoreLocals appended completed).world = appended.world := by
    change completed.world = appended.world
    exact pure.world
  have finalViews : (restoreLocals appended completed).i32ArrayViews = appended.i32ArrayViews := by
    change completed.i32ArrayViews = appended.i32ArrayViews
    exact pure.views
  refine ⟨restoreLocals appended completed, RunsStmt.letLocal appending returning,
    (((preparation.cells.trans appendCells).trans (FreshCellFrame.bindLocal appended _ _)).trans pure.cells), insertion,
    insertionStream, ?_, ?_, ?_, ?_⟩
  · exact (insertionWorld.trans streamEffect.2.1).trans producingWorld
  · exact (insertionViews.trans streamEffect.2.2.1).trans producingViews
  · simpa only [finalHeap, finalWorld, finalViews] using appendPost
  · exact catalogReads maintained (by rw [finalHeap]; exact HeapReads.refl _)
      (by change completed.CellsWellFormed; exact pure.afterFormed)
      (by rw [finalHeap]; exact maintained.unique)
      (by rw [finalHeap]; exact maintained.below) (finalViews.trans maintained.noViews)

#print axioms actualFundedTerminalWith

/-- The leading locals attempt and the public append's original-input branch
    equations determine the complete observable allocation suffix. -/
theorem FunctionInsertion.observations
    (inserted : FunctionInsertion anchor body output permissions result allowed
      memory localHeap catalog next previous request before after) :
    after.world = (catalog.model next previous request).expectedWorld localHeap
        (World.record anchor.world .alloc) ∧
      after.i32ArrayViews = anchor.i32ArrayViews := by
  obtain ⟨_, produced, stream, world, views, post, _⟩ := inserted
  refine ⟨?_, post.viewsFrame.trans views⟩
  simpa only [Model.expectedWorld, stream.2.2.2.budget, world] using post.worldFrame

#print axioms FunctionInsertion.observations

end IRBodyProductionProof
