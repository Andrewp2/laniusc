import verified_compiler.tests.direct_ir_body_production_main_natural
import verified_compiler.tests.direct_ir_body_production_main_output
import verified_compiler.tests.direct_ir_body_production_inputs_frame
import verified_compiler.tests.direct_ir_body_production_main_scalar

namespace IRBodyProductionProof

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRBodyProductionInputs
open IRBodyProductionScalar IREventStoreProof IRTypeRefProof
open IRCatalogAppendProof IRCatalogConstructionProof

/-- Only scalar syntax needs the existing arena/cache storage. Void has no
    unused arena or cache backing requirement. -/
def NaturalReturn.WorkspaceStorage
    (returns : NaturalReturn input caller declaration topology) (workspace : Workspace) : Type :=
  match returns with
  | .void _ _ => PUnit
  | .scalar _ _ _ _ _ _ natural _ _ => ScalarStorage workspace caller (scalarCount natural.expression)

def NaturalReturn.workspaceWrites
    (returns : NaturalReturn input caller declaration topology) (workspace : Workspace) :
    returns.WorkspaceStorage workspace → Nat → Prop := by
  cases returns with
  | void optional result => exact fun _ _ => False
  | scalar root optional bound child kind payload natural result distinct =>
      exact fun storage => storage.writes

/-- Public total-theorem surface. Every premise concerns original native
    inputs, writable used slots, separation, the catalog or address bounds.
    No producer, decoder, inference, expected-expression or validator run is
    supplied. The proof must choose one source-selected body and discharge
    the one funded caller's production phase from closed actual1251. -/
def NaturalFunctionCorrect : Prop :=
  ∀ {caller : State} {catalog : Catalog} {next : Int32} {previous : Nat → PreviousRow}
    (input : Inputs) (workspace : Workspace) (declaration : Nat)
    (natural : NaturalBody input caller declaration)
    (native : NativeSignature input.signature caller.heap)
    (storage : natural.returns.WorkspaceStorage workspace)
    (output : Context caller) (zero : output.position = 0)
    (permissions : ∀ body, natural.Selects body → OutputPermissions output body.count)
    (events : workspace.events = output.value) (catalogValue : workspace.catalog = catalog.value)
    (invariant : Invariant catalog next previous caller)
    (tokenBound : input.tokenCount ≤ 89478484)
    (localFits : caller.heap.allocationAddress 8 + localBytes input.tokenCount < 2 ^ 64)
    (copyFits : ∀ body, natural.Selects body → ∀ budget,
      consumeBudget caller.heap.remaining (localBytes input.tokenCount) = some budget →
      ((caller.heap.allocatedBytes (localBytes input.tokenCount) 8 budget).borrowBlock
        (caller.heap.allocationAddress 8)).allocationAddress 8 + body.count * 56 < 2 ^ 64)
    (apart : ∀ body (selected : natural.Selects body), InputApart input
      (fun address => natural.returns.workspaceWrites workspace storage address ∨
        (permissions body selected).writesFrom 0 address))
    (signatureApart : ∀ body (selected : natural.Selects body), ∀ address,
      native.base ≤ address → address < native.base + 72 →
      ¬(natural.returns.workspaceWrites workspace storage address ∨
        (permissions body selected).writesFrom 0 address))
    (outputApart : ∀ body (selected : natural.Selects body), ∀ address,
      (permissions body selected).writesFrom 0 address →
      ¬natural.returns.workspaceWrites workspace storage address)
    (catalogApart : ∀ body (selected : natural.Selects body), ∀ address,
      catalog.memory ≤ address → address < catalog.memory + catalog.bytes →
      ¬(natural.returns.workspaceWrites workspace storage address ∨
        (permissions body selected).writesFrom 0 address))
    (sourceCatalogApart : ∀ body, natural.Selects body → ∀ address,
      sourceBytes input native address →
      ¬(catalog.model next previous (streamRequest output (Int32.ofNat input.signature.id)
        input.signature.result body (fun index => if index = 0 then .Invalid else input.signature.result))).footprint address),
  ∃ body, ∃ selected : natural.Selects body,
    let used := permissions body selected
    let allowed := fun address => natural.returns.workspaceWrites workspace storage address ∨ used.writesFrom 0 address
    let request := streamRequest output (Int32.ofNat input.signature.id) input.signature.result body
      (fun index => if index = 0 then .Invalid else input.signature.result)
    let model := catalog.model next previous request
    ∃ result : Int, ∃ after : State,
      RunsExpr extractedProgram caller (producerCall input workspace declaration input.tree.nodeCount)
        (.signed .i32 result) after ∧
      FreshCellFrame caller after ∧ after.locals = caller.locals ∧
      after.i32ArrayViews = caller.i32ArrayViews ∧
      (∀ (context : SurfaceElaboration.Context)
        (target : extractedProgram.target = context.target) (nextVariable : VarId),
        body.Meaning input.signature.result context nextVariable natural.surface) ∧
      (∀ pointer offset byte, sourceBytes input native (pointer + offset) →
        caller.heap.loadByte pointer offset = .ok byte → after.heap.loadByte pointer offset = .ok byte) ∧
      input.signature.Read after ∧
      (consumeBudget caller.heap.remaining (localBytes input.tokenCount) = none →
        result = -1 ∧ after.heap = caller.heap ∧
        after.world = World.record caller.world .alloc ∧ Invariant catalog next previous after) ∧
      (∀ budget, consumeBudget caller.heap.remaining (localBytes input.tokenCount) = some budget →
        let localHeap := (caller.heap.allocatedBytes (localBytes input.tokenCount) 8 budget).borrowBlock
          (caller.heap.allocationAddress 8)
        result = (by classical exact if model.Success localHeap then 0 else -1) ∧
        FunctionInsertion caller body output used input.signature.result allowed
          (caller.heap.allocationAddress 8) localHeap catalog next previous request caller after ∧
        after.world = model.expectedWorld localHeap (World.record caller.world .alloc) ∧
        (model.Success localHeap → StoredTerminalRepresentation after.heap
          (catalog.rowBase next.toInt.toNat) (Int32.ofNat input.signature.id)
          (localHeap.allocationAddress 8 + body.count * 40 - 8)
          (localHeap.allocationAddress 8 + body.count * 56 - 8)
          (localHeap.allocationAddress 8 + body.count * 56)
          body.count output.enabled body.coreStatement)) ∧
      (∀ budget first second,
        consumeBudget caller.heap.remaining (localBytes input.tokenCount) = some budget →
        consumeBudget budget (body.count * 56) = some first →
        consumeBudget first (body.count * 4) = some second →
        next.toInt < catalog.capacity.toInt →
        (∀ index, index < next.toInt.toNat →
          (previous index).id.toInt ≠ (Int32.ofNat input.signature.id).toInt) → result = 0)

private theorem naturalProduction {caller current : State}
    (input : Inputs) (workspace : Workspace) (declaration : Nat)
    (natural : NaturalBody input caller declaration) (body : ReturnBody)
    (selected : natural.Selects body) (storage : natural.returns.WorkspaceStorage workspace)
    (output : Context caller) (zero : output.position = 0)
    (permissions : OutputPermissions output body.count)
    (apart : InputApart input (fun address =>
      natural.returns.workspaceWrites workspace storage address ∨ permissions.writesFrom 0 address))
    (outputApart : ∀ address, permissions.writesFrom 0 address →
      ¬natural.returns.workspaceWrites workspace storage address)
    (below : HeapBlocksBelowNext caller.heap) (reads : HeapReads caller.heap current.heap)
    (count : NativeSnapshot 64 extractedProgram current.heap (.scalar (.signed .i32))
      (caller.heap.allocationAddress 8) (.signed .i32 0) 4)
    (room : current.heap.Readable (caller.heap.allocationAddress 8) 4)
    (formed : current.CellsWellFormed) (unique : HeapBlockBasesUnique current.heap)
    (noViews : current.i32ArrayViews = []) : ∃ after,
    RunsExpr extractedProgram current
      (terminalBlockCall (bodyContext input workspace
        (localsValue (caller.heap.allocationAddress 8) input.tokenCount))
        natural.topology.block output.value 0 (input.tree.nodeCount - 1))
      (.signed .i32 body.count) after ∧ MemoryEffect
        (TerminalStream body output permissions input.signature.result
          (caller.heap.allocationAddress 8) (fun address =>
            natural.returns.workspaceWrites workspace storage address ∨ permissions.writesFrom 0 address))
        current after := by
  let memory := caller.heap.allocationAddress 8
  let reached : Context current := { output with
    eventRoom := reads.readable output.eventRoom
    typeRoom := fun enabled => reads.readable (output.typeRoom enabled) }
  let mapped := permissions.afterReads reads
  have first : 0 < body.count := by cases body <;> simp only [ReturnBody.count] <;> decide
  have eventBase : permissions.eventBases 0 = output.eventBase := by
    have original := output.eventLocation
    rw [zero] at original
    exact Except.ok.inj ((permissions.eventLocation 0 first).symm.trans original)
  have typeBase (enabled : output.enabled = true) : permissions.typeBases 0 = output.typeBase := by
    have original := output.typeLocation enabled
    rw [zero] at original
    exact Except.ok.inj ((permissions.typeLocation enabled 0 first).symm.trans original)
  have fresh := caller.heap.allocationAddress_ge (by decide : 0 < 8)
  have eventApart (index : Nat) (inside : index < body.count) :
      permissions.eventBases index + 40 ≤ memory ∨ memory + 4 ≤ permissions.eventBases index :=
    Or.inl (Nat.le_trans ((permissions.eventRoom index inside).belowNext (by decide) below) fresh)
  have typeApart (enabled : output.enabled = true) (index : Nat) (inside : index < body.count) :
      permissions.typeBases index + 16 ≤ memory ∨ memory + 4 ≤ permissions.typeBases index :=
    Or.inl (Nat.le_trans ((permissions.typeRoom enabled index inside).belowNext (by decide) below) fresh)
  rcases natural with ⟨topology, keyword, returns⟩
  cases returns with
  | void optional kind =>
      change body = .void at selected
      subst body
      obtain ⟨after, run, effect⟩ := actualVoidBlock input workspace memory input.tokenCount
        (topology.afterReads reads) optional kind (input.tree.nodeCount - 1)
        (by have := topology.depth; omega) (by have := input.tree.nodesFit; omega)
        reached count room
        (by simpa only [eventBase] using eventApart 0 first)
        (fun enabled => by simpa only [typeBase enabled] using typeApart enabled 0 first)
        formed unique noViews
      have stream : VoidStream output memory current.heap after.heap := by
        simpa only [VoidStream, reached] using effect.2.2.2
      refine ⟨after, ?_, effect.1, effect.2.1, effect.2.2.1, ?_, ?_, stream.2.2.1, ?_⟩
      · simpa only [reached, Context.value, zero, Nat.zero_add, Int.natCast_zero,
          Int.natCast_one, TerminalTopology.afterReads, ReturnBody.count] using run
      · intro index inside
        have initial : index = 0 := by change index < 1 at inside; omega
        subst index
        simpa only [eventBase, ReturnBody.event, if_true] using stream.1
      · intro enabled index inside
        have initial : index = 0 := by change index < 1 at inside; omega
        subst index
        simpa only [typeBase enabled, if_pos rfl, if_true,
          show IREventStoreProof.invalid = referenceValue .Invalid from rfl] using stream.2.1 enabled
      · exact stream.2.2.2.weaken (fun address changed => by
          rcases changed with event | annotation | counter
          · exact Or.inl (Or.inr ⟨0, Nat.zero_le _, first,
              Or.inl (by simpa only [eventBase] using event)⟩)
          · exact Or.inl (Or.inr ⟨0, Nat.zero_le _, first,
              Or.inr ⟨annotation.1, by simpa only [typeBase annotation.1] using annotation.2⟩⟩)
          · exact Or.inr counter)
  | scalar root optional bound child kind payload scalar declared distinct =>
      change scalar.spelling.Selects body at selected
      change ScalarStorage workspace caller (scalarCount scalar.expression) at storage
      have nonvoid : body ≠ .void := by
        rcases scalar with ⟨expression, result, spelling, route, original, nodup⟩
        cases selected <;> intro impossible <;> cases impossible
      have depthBound := scalarDepth topology scalar distinct
      let currentStorage := storage.afterReads reads
      let original := scalar.afterReads reads
      have headerSubset (address : Nat)
          (changed : (output.eventBase ≤ address ∧ address < output.eventBase + 40) ∨
            (output.enabled = true ∧ output.typeBase ≤ address ∧ address < output.typeBase + 16)) :
          storage.writes address ∨ permissions.writesFrom 0 address := by
        apply Or.inr
        refine ⟨0, Nat.zero_le _, first, ?_⟩
        rcases changed with event | annotation
        · exact Or.inl (by simpa only [eventBase] using event)
        · exact Or.inr ⟨annotation.1, by simpa only [typeBase annotation.1] using annotation.2⟩
      obtain ⟨after, run, effect⟩ := actualScalarBlockWith
        (expression := NaturalExpectedHeap input storage output body permissions)
        (extra := storage.writes) input workspace memory input.tokenCount
        (topology.afterReads reads) root optional bound (child.afterReads reads) kind payload
        (input.tree.nodeCount - 1) (by have := topology.depth; omega)
        (by have := input.tree.nodesFit; omega) body nonvoid reached zero mapped
        (by
          intro state header stateFormed stateViews
          have write := header.footprint
          let readyScalar := original.afterFootprint write (apart.mono headerSubset)
          let readyStorage := currentStorage.afterFootprint write
          let readyOutput : Context state := { reached with
            eventRoom := write.readable _ _ reached.eventRoom
            typeRoom := fun enabled => write.readable _ _ (reached.typeRoom enabled) }
          let readyPermissions := mapped.afterFootprint write
          obtain ⟨after, run, effect⟩ := actualNaturalExpected readyScalar body selected declared.symm
            readyStorage readyOutput readyPermissions
            (apart.mono (fun address changed => by
              rcases changed with mutable | ⟨index, positive, inside, slot⟩
              · exact Or.inl mutable
              · exact Or.inr ⟨index, Nat.zero_le _, inside, slot⟩))
            (localsValue memory input.tokenCount) (input.tree.nodeCount - 1 - 3)
            (by simpa only [readyScalar, original, NaturalScalar.afterFootprint,
              NaturalScalar.afterReads] using (show scalar.route.length < input.tree.nodeCount - 1 - 3 by omega))
            (by have := input.tree.nodesFit; omega) stateFormed write.unique (stateViews.trans noViews)
          refine ⟨after, ?_, ?_⟩
          · simpa only [naturalExpectedCall, expectedSource, expectedScalarCall, List.map,
              readyOutput, reached, Context.value] using run
          · change MemoryEffect (NaturalExpectedHeap input storage output body permissions) state after at effect
            exact effect)
        (fun phase => phase.1) (fun phase => phase.2.1) (fun phase => phase.2.2)
        outputApart count room eventApart typeApart formed unique noViews
      refine ⟨after, ?_, ?_⟩
      · simpa only [reached, Context.value, zero, Int.natCast_zero, TerminalTopology.afterReads] using run
      · change MemoryEffect (TerminalStream body output permissions input.signature.result memory
          (fun address => storage.writes address ∨ permissions.writesFrom 0 address)) current after at effect
        exact effect

/-- Total execution from original natural syntax. The scalar production
    phase is closed by actualNaturalExpected, not supplied by the caller. -/
theorem actualNaturalFunction : NaturalFunctionCorrect := by
  unfold NaturalFunctionCorrect
  intro caller catalog next previous input workspace declaration natural native storage output zero
    permissions events catalogValue invariant tokenBound localFits copyFits apart signatureApart
    outputApart catalogApart sourceCatalogApart
  classical
  obtain ⟨body, selected⟩ := natural.selectsExists
  let used := permissions body selected
  let allowed := fun address => natural.returns.workspaceWrites workspace storage address ∨ used.writesFrom 0 address
  let request := streamRequest output (Int32.ofNat input.signature.id) input.signature.result body
    (fun index => if index = 0 then .Invalid else input.signature.result)
  let model := catalog.model next previous request
  have declared : input.signature.result = body.result := by
    rcases natural with ⟨topology, keyword, returns⟩
    cases returns with
    | void optional result =>
        change body = .void at selected
        subst body
        exact result
    | scalar root optional bound child kind payload scalar result distinct =>
        change scalar.spelling.Selects body at selected
        rcases scalar with ⟨expression, resultType, spelling, route, original, nodup⟩
        cases selected <;> simpa only [ReturnBody.result] using result
  have meaning (context : SurfaceElaboration.Context)
      (target : extractedProgram.target = context.target) (nextVariable : VarId) :=
    natural.meaning body selected context target nextVariable
  refine ⟨body, selected, ?_⟩
  dsimp only
  cases resource : consumeBudget caller.heap.remaining (localBytes input.tokenCount) with
  | none =>
      obtain ⟨after, run, cells, heap, world, views, locals⟩ := actualLocalsExhausted
        input workspace declaration input.tree.nodeCount native.read natural.validResult
        natural.topology.tokensPositive tokenBound resource invariant.formed invariant.noViews
      have reads : HeapReads caller.heap after.heap := by rw [heap]; exact HeapReads.refl _
      have maintained : Invariant catalog next previous after :=
        ⟨invariant.supported, invariant.bounds, by simpa only [heap] using invariant.count,
          reads.readable invariant.backing,
          fun index inside => (invariant.occupied index inside).afterHeapReads reads,
          cells.after_cellsWellFormed invariant.formed, by simpa only [heap] using invariant.unique,
          by simpa only [heap] using invariant.below, views.trans invariant.noViews⟩
      refine ⟨-1, after, run, cells, locals, views, meaning, ?_, (native.afterReads reads).read,
        ?_, ?_, ?_⟩
      · intro pointer offset byte inside loaded
        exact reads pointer offset byte loaded
      · intro exhausted
        exact ⟨rfl, heap, world, maintained⟩
      · intro budget available
        cases available
      · intro budget first second available owned endpoints room absent
        cases available
  | some budget =>
      let localHeap := (caller.heap.allocatedBytes (localBytes input.tokenCount) 8 budget).borrowBlock
        (caller.heap.allocationAddress 8)
      obtain ⟨after, run, inserted, locals⟩ := actualFundedTerminalWith input workspace natural.topology body
        natural.validResult native.read tokenBound output zero used allowed events catalogValue invariant
        resource localFits (copyFits body selected budget resource) (catalogApart body selected)
        (fun reads count room formed unique noViews => naturalProduction input workspace declaration
          natural body selected storage output zero used (apart body selected) (outputApart body selected)
          invariant.below reads count room formed unique noViews)
      have observations := inserted.observations
      have actualInserted := inserted
      obtain ⟨cells, produced, stream, producedWorld, producedViews, post, maintained⟩ := actualInserted
      have reads : HeapReads caller.heap localHeap := by
        intro pointer offset byte loaded
        change ((caller.heap.allocatedBytes (localBytes input.tokenCount) 8 budget).borrowBlock
          (caller.heap.allocationAddress 8)).loadByte pointer offset = .ok byte
        rw [Heap.loadByte_borrowBlock]
        exact Heap.allocatedBytes_oldRead loaded
      have readonly := sourceBytes.readonly native invariant.below reads
        (caller.heap.allocationAddress_ge (by decide : 0 < 8)) stream.2.2.2
        (apart body selected) (signatureApart body selected) post (sourceCatalogApart body selected)
      have signature : input.signature.Read after :=
        (native.afterBytes (fun pointer offset byte lower upper loaded =>
          readonly pointer offset byte (Or.inr ⟨lower, upper⟩) loaded)).read
      refine ⟨(if model.Success localHeap then 0 else -1), after, run, cells, locals,
        observations.2, meaning, readonly, signature, ?_, ?_, ?_⟩
      · intro exhausted
        cases exhausted
      · intro actualBudget available
        have same : actualBudget = budget := Option.some.inj available.symm
        subst actualBudget
        exact ⟨rfl, inserted, observations.1, fun successful =>
          FunctionInsertion.stored body output used (Int32.ofNat input.signature.id)
            input.signature.result declared inserted successful⟩
      · intro actualBudget first second available owned endpoints room absent
        have same : actualBudget = budget := Option.some.inj available.symm
        subst actualBudget
        have idFits : input.signature.id < 2 ^ 31 :=
          Nat.lt_trans input.signature.inside input.signature.fits
        have exactId : (Int32.ofNat input.signature.id).toInt = input.signature.id := by
          rw [Int32.toInt_ofNat']
          change (input.signature.id : Int).bmod 4294967296 = input.signature.id
          apply Int.bmod_eq_of_le <;> omega
        have sufficient := streamSufficient body output used (Int32.ofNat input.signature.id)
          input.signature.result (catalog := catalog) (next := next) (previous := previous)
          (heap := localHeap) (by rw [exactId]; exact Int.natCast_nonneg _) natural.validResult
          invariant.bounds.1 room absent
          (by change consumeBudget budget (body.count * 56) = some first; exact owned) endpoints
        exact if_pos sufficient

#print axioms actualNaturalFunction

end IRBodyProductionProof
