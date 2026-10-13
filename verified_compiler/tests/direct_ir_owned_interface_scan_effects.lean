import verified_compiler.tests.direct_ir_owned_interface_scan

namespace IRBodyOwnedProof

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRBodyOwnedInputs
open IRBodyProductionInputs IRBodyProductionProof IRBodyProductionScalar IREventStoreProof
open IRCatalogAppendProof IRCatalogConstructionProof

variable {origin current after : State} {raw : RawInputs} {workspace : RawWorkspace}
  {normal : NormalTable raw.allocationTable origin.heap} {validation : OriginalValidation raw origin}
  {scan : OriginalScan raw workspace normal validation} {cursor : Nat} {inserted : List InsertedBody}

/-- The copied native slices use backward indexing, but every used payload
    lies in the same compact allocation interval. -/
theorem PayloadBytes.copiedBounds
    (stored : PayloadBytes (base + count * 40 - 8) (base + count * 56 - 8)
      (base + count * 56) count address) :
    base ≤ address ∧ address < base + count * 60 := by
  rcases stored with eventRead | typeRead | endRead
  · obtain ⟨index, slot, inside, location, lower, upper⟩ := eventRead
    have layout : NativeLayout.valueWords? extractedProgram IREventStoreProof.eventType = some 5 := by
      decide +kernel
    have computed : rawSliceElementAddress? extractedProgram IREventStoreProof.eventType
        (base + count * 40 - 8) index = .ok (base + (count - index - 1) * 40) :=
      rawSliceElementAddress_of_layout (by rfl) layout (by decide) (by omega) (by omega)
    have same : base + (count - index - 1) * 40 = slot := Except.ok.inj (computed.symm.trans location)
    subst slot
    change base + (count - index - 1) * 40 ≤ address at lower
    change address < base + (count - index - 1) * 40 + 40 at upper
    omega
  · obtain ⟨index, slot, inside, location, lower, upper⟩ := typeRead
    have layout : NativeLayout.valueWords? extractedProgram IREventStoreProof.referenceType = some 2 := by
      decide +kernel
    have computed : rawSliceElementAddress? extractedProgram IREventStoreProof.referenceType
        (base + count * 56 - 8) index = .ok (base + count * 40 + (count - index - 1) * 16) :=
      rawSliceElementAddress_of_layout (by rfl) layout (by decide) (by omega) (by omega)
    have same : base + count * 40 + (count - index - 1) * 16 = slot :=
      Except.ok.inj (computed.symm.trans location)
    subst slot
    change base + count * 40 + (count - index - 1) * 16 ≤ address at lower
    change address < base + count * 40 + (count - index - 1) * 16 + 16 at upper
    omega
  · obtain ⟨index, inside, lower, upper⟩ := endRead
    omega

private theorem footprintBounds (catalog : Catalog) {occupied : Nat} {previous : Nat → PreviousRow}
    {request : Model} (count : (Int32.ofNat occupied).toInt = (occupied : Int))
    (room : (Int32.ofNat occupied).toInt < catalog.capacity.toInt)
    (changed : (catalog.model (Int32.ofNat occupied) previous request).footprint address) :
    catalog.memory ≤ address ∧ address < catalog.memory + catalog.bytes := by
  have inside : occupied < catalog.length := by dsimp only [Catalog.length]; omega
  rcases changed with row | countRead
  · change catalog.memory + catalog.length * 96 + 8 -
      ((Int32.ofNat occupied).toInt.toNat + 1) * 96 ≤ address ∧
      address < catalog.memory + catalog.length * 96 + 8 -
      ((Int32.ofNat occupied).toInt.toNat + 1) * 96 + 96 at row
    rw [count, Int.toNat_natCast, catalog.rowAddress inside] at row
    dsimp only [Catalog.rowBase, Catalog.bytes] at *
    omega
  · change catalog.memory ≤ address ∧ address < catalog.memory + 4 at countRead
    dsimp only [Catalog.bytes]
    omega

private theorem prefixApart (facts : LoopFacts scan cursor inserted heap)
    (covered : (prefixRep inserted).footprint.bytes address) :
    ¬scan.mutable address ∧
      ∀ request : Model, (Int32.ofNat (scan.initialCount.toInt.toNat + inserted.length)).toInt <
        scan.catalog.capacity.toInt →
      ¬(scan.catalog.model (Int32.ofNat (scan.initialCount.toInt.toNat + inserted.length))
        (prefixRows scan.previous scan.initialCount.toInt.toNat inserted) request).footprint address := by
  obtain ⟨index, stored⟩ := covered
  have member : inserted[index.val] ∈ inserted := List.getElem_mem index.isLt
  obtain ⟨memory, floor, extent, events, types, ends⟩ := facts.copied _ member
  change PayloadBytes _ _ _ _ address at stored
  rw [events, types, ends] at stored
  have payload := PayloadBytes.copiedBounds stored
  have catalogBelow : scan.catalog.memory + scan.catalog.bytes ≤ origin.heap.nextAddress :=
    Heap.Readable.belowNext scan.invariant.backing
      (by change 0 < 8 + scan.catalog.length * 96; omega) scan.invariant.below
  constructor
  · intro changed
    have below := scan.mutableBelow address changed
    exact (Nat.not_lt_of_ge (Nat.le_trans floor payload.1)) below
  · intro request room changed
    have backing := footprintBounds scan.catalog facts.catalogState.toInt room changed
    exact (Nat.not_lt_of_ge (Nat.le_trans catalogBelow (Nat.le_trans floor payload.1))) backing.2

private theorem tableCovered
    (covered : (tableRep normal).footprint.bytes address) : scan.region address := by
  simp only [tableRep, Rep.and, Rep.native, Rep.all, Rep.block, Rep.owned,
    Footprint.union, Footprint.iUnion, or_false, exists_false] at covered
  dsimp only [Address] at *
  apply scan.tableCovered address
  · rcases covered with header | ⟨index, row⟩
    · exact header.1
    · dsimp only [AllocationTable.rowBase] at row; omega
  · rcases covered with header | ⟨index, row⟩
    · omega
    · have bound := index.isLt
      dsimp only [AllocationTable.rowBase] at row
      omega

/-- All represented contents are combined before the single actual effect
    bridge. Metadata atoms remain separate from the byte-disjointness proof. -/
private def retainedFootprint (scan : OriginalScan raw workspace normal validation)
    (inserted : List InsertedBody) : Footprint :=
  scan.protected.union ((tableRep normal).footprint.union
    (prefixRep inserted).footprint)

private theorem retainedApart (facts : LoopFacts scan cursor inserted heap)
    (covered : (retainedFootprint scan inserted).bytes address) :
    ¬scan.mutable address ∧
      ∀ request : Model, (Int32.ofNat (scan.initialCount.toInt.toNat + inserted.length)).toInt <
        scan.catalog.capacity.toInt →
      ¬(scan.catalog.model (Int32.ofNat (scan.initialCount.toInt.toNat + inserted.length))
        (prefixRows scan.previous scan.initialCount.toInt.toNat inserted) request).footprint address := by
  have protectedApart (protectedByte : scan.protected.bytes address) :
      ¬scan.mutable address ∧
        ∀ request : Model, (Int32.ofNat (scan.initialCount.toInt.toNat + inserted.length)).toInt <
          scan.catalog.capacity.toInt →
        ¬(scan.catalog.model (Int32.ofNat (scan.initialCount.toInt.toNat + inserted.length))
          (prefixRows scan.previous scan.initialCount.toInt.toNat inserted) request).footprint address :=
    ⟨fun changed => protectedByte (Or.inl changed),
      fun request room changed => protectedByte (Or.inr
        (footprintBounds scan.catalog facts.catalogState.toInt room changed))⟩
  rcases covered with protectedByte | tableByte | prefixByte
  · exact protectedApart protectedByte
  · exact protectedApart (scan.regionProtected (tableCovered tableByte))
  · exact prefixApart facts prefixByte

private theorem prefixRep_append
    (old : (prefixRep entries).holds heap)
    (stored : entry.Payloads heap) :
    (prefixRep (entries ++ [entry])).holds heap := by
  apply prefixRep_ofPayloads
  intro index value found
  by_cases inside : index < entries.length
  · rw [List.getElem?_append_left inside] at found
    exact prefixRep_payloads old found
  · rw [List.getElem?_append_right (by omega : entries.length ≤ index)] at found
    have bound := (List.getElem?_eq_some_iff.mp found).1
    have same : index = entries.length := by simp only [List.length_singleton] at bound; omega
    subst index
    simp only [Nat.sub_self, List.getElem?_cons_zero] at found
    cases found
    exact stored

/-- One actual producer result either hides a safe partial catalog or
    appends the next original selected body. No control or effect trace is
    supplied as an input or retained in the caller invariant. -/
theorem LoopFacts.produce (facts : LoopFacts scan cursor inserted current.heap)
    (inside : cursor < normal.count)
    (chosen : selectedRowBool raw.owner (normal.rowValue cursor) = true)
    (bounds : 0 ≤ (normal.rowValue cursor).coreId.toInt ∧
      (normal.rowValue cursor).coreId.toInt < scan.signatures.index.count.toInt)
    (present : scan.signatures.present cursor inside chosen bounds = true)
    (observed : ProducerObservation
      ((scan.producers cursor inside chosen bounds present).at (after := current) facts.protected
        (fun _ covered => scan.regionProtected covered))
      (Int32.ofNat (scan.initialCount.toInt.toNat + inserted.length))
      (prefixRows scan.previous scan.initialCount.toInt.toNat inserted) result after) :
    ProducerStep scan cursor inserted result after := by
  classical
  let original := scan.producers cursor inside chosen bounds present
  let producer := original.at (after := current) facts.protected (fun _ covered => scan.regionProtected covered)
  let next := Int32.ofNat (scan.initialCount.toInt.toNat + inserted.length)
  let previous := prefixRows scan.previous scan.initialCount.toInt.toNat inserted
  change ProducerObservation producer next previous result after at observed
  have tokenEq : producer.input.tokenCount = raw.tokenCount.toInt.toNat := by
    have same := producer.tokenCount
    omega
  have count := facts.catalogState.toInt
  have idEq : Int32.ofNat producer.input.signature.id = (normal.rowValue cursor).coreId := by
    apply Int32.toInt.inj
    have signature := producer.signatureId
    rw [Int32.toInt_ofNat_of_lt (by have bound := (normal.rowValue cursor).coreId.toInt_lt; omega)]
    exact signature
  have enough (funded : FullFunding scan) : result = 0 := by
    obtain ⟨room, distinct, localBudget, first, second, localAvailable, copyAvailable, endsAvailable, _⟩ :=
      scan.selectedFunding facts.ordered (fun entry member => (facts.source entry member).1)
        inside chosen bounds present funded (facts.funding funded)
    apply observed.2.2.2.2.2 localBudget first second
    · simpa only [tokenEq] using localAvailable
    · exact copyAvailable
    · exact endsAvailable
    · change (Int32.ofNat _).toInt < _
      rw [count]
      dsimp only [Catalog.length] at room
      omega
    · intro index occupied same
      have position : next.toInt.toNat = scan.initialCount.toInt.toNat + inserted.length := by
        rw [count]; exact Int.toNat_natCast _
      rw [position] at occupied
      exact distinct index occupied (Int32.toInt.inj (same.trans (congrArg Int32.toInt idEq)))
  have step : HeapFrame (retainedFootprint scan inserted) current.heap after.heap :=
    observed.frame facts.catalogState.below
      (fun address covered changed => (retainedApart facts covered).1 (producer.mutableCovered address changed))
      (fun address covered room changed => (retainedApart facts covered).2 producer.request room changed)
  have preserved := ((tableRep normal).and (prefixRep inserted)).frame
    ⟨facts.table, facts.stored⟩ step
    ⟨fun _ covered => Or.inr covered, fun _ covered => Or.inr covered, fun _ covered => Or.inr covered⟩
  have protectedAfter := facts.protected.trans (step.restrict
    ⟨fun _ covered => Or.inl covered, fun _ covered => Or.inl covered, fun _ covered => Or.inl covered⟩)
  have safe (invariant : Invariant scan.catalog next previous after) : SafeHeap scan after.heap := by
    refine ⟨inserted, protectedAfter, preserved.1, ?_, preserved.2⟩
    simpa only [next, count, Int.toNat_natCast] using CatalogHeap.ofInvariant invariant
  have frontier := observed.frontierBounds
  have retainedCopied : ∀ entry ∈ inserted, entry.CopyBounds origin.heap.nextAddress after.heap.nextAddress := by
    intro entry member
    obtain ⟨memory, floor, extent, coordinates⟩ := facts.copied entry member
    exact ⟨memory, floor, Nat.le_trans extent frontier.1, coordinates⟩
  cases available : consumeBudget current.heap.remaining (localBytes producer.input.tokenCount) with
  | none =>
      obtain ⟨negative, _, _, invariant⟩ := observed.2.2.2.1 available
      exact Or.inl ⟨negative, safe invariant, fun funded => by have := enough funded; omega⟩
  | some budget =>
      let localHeap := producer.localHeap budget
      let model := scan.catalog.model next previous producer.request
      obtain ⟨answer, insertion, stored⟩ := observed.2.2.2.2.1 budget available
      change result = (if model.Success localHeap then 0 else -1) at answer
      obtain ⟨produced, stream, _, _, post, invariant⟩ := insertion.2
      have write := stream.2.2.2
      change HeapWritesOn localHeap produced.heap _ at write
      have successful : model.Success produced.heap ↔ model.Success localHeap := by
        simp only [Model.Success, Arguments.BothAvailable, write.budget]
      by_cases success : model.Success localHeap
      · have successProduced := successful.mpr success
        have zero : result = 0 := by simpa only [if_pos success] using answer
        let entry : InsertedBody := {
          sourceRow := cursor
          id := Int32.ofNat producer.input.signature.id
          body := producer.body
          surface := original.natural.surface
          events := localHeap.allocationAddress 8 + producer.body.count * 40 - 8
          types := localHeap.allocationAddress 8 + producer.body.count * 56 - 8
          ends := localHeap.allocationAddress 8 + producer.body.count * 56
          annotations := producer.output.enabled }
        have source : scan.Source entry := ⟨inside, chosen, bounds, present, idEq, rfl, rfl, rfl⟩
        have meaning : entry.Meaning := by
          intro context target nextVariable
          change original.body.Meaning original.body.result context nextVariable original.natural.surface
          rw [← original.result]
          exact original.natural.meaning original.body original.selected context target nextVariable
        have nextRoom : scan.initialCount.toInt.toNat + inserted.length < scan.catalog.length := by
          have room := success.1.2.2.2.2.1
          change next.toInt < scan.catalog.capacity.toInt at room
          dsimp only [next] at room
          dsimp only [Catalog.length]
          omega
        have countAfter : scan.catalog.afterCount next previous producer.request produced.heap =
            Int32.ofNat (scan.initialCount.toInt.toNat + (inserted ++ [entry]).length) := by
          rw [Catalog.afterCount, if_pos successProduced]
          simp only [List.length_append, List.length_singleton, ← Int32.ofInt_eq_ofNat]
          apply congrArg Int32.ofInt
          rw [count]
          omega
        have copiedTree : model.copiedTree produced.heap = entry.previous.tree := by
          have address : produced.heap.allocationAddress 8 = localHeap.allocationAddress 8 := by
            simp only [Heap.allocationAddress, write.frontier]
          change IRValidatorProof.treeValue _ _ true _ model.request = _
          rw [address, show model.request = producer.body.count from producer.requestCount]
          rfl
        have previousAfter : scan.catalog.afterRows next previous producer.request produced.heap =
            prefixRows scan.previous scan.initialCount.toInt.toNat (inserted ++ [entry]) := by
          rw [Catalog.afterRows, if_pos successProduced, prefixRows_append]
          have position : next.toInt.toNat = scan.initialCount.toInt.toNat + inserted.length := by
            rw [count]; exact Int.toNat_natCast _
          rw [position]
          funext index
          split
          · change PreviousRow.mk producer.request.id producer.request.parameters
              producer.request.result (model.copiedTree produced.heap) = entry.previous
            rw [copiedTree]
            change PreviousRow.mk (Int32.ofNat producer.input.signature.id) (Int32.ofNat 0)
                producer.input.signature.result entry.previous.tree =
              PreviousRow.mk (Int32.ofNat producer.input.signature.id) (Int32.ofNat 0)
                producer.body.result entry.previous.tree
            exact congrArg (fun reference => PreviousRow.mk (Int32.ofNat producer.input.signature.id)
              (Int32.ofNat 0) reference entry.previous.tree) producer.result
          · rfl
        have newPayloads : entry.Payloads after.heap := ⟨(stored success).payloads, (stored success).resultTypes⟩
        obtain ⟨resourceBudget, first, second, localAvailable, copyAvailable, endsAvailable, finalBudget, extent⟩ :=
          observed.successResources zero
        have sameBudget := Option.some.inj (available.symm.trans localAvailable)
        subst resourceBudget
        have fresh : origin.heap.nextAddress ≤ localHeap.allocationAddress 8 := by
          have start := current.heap.allocationAddress_ge (by decide : 0 < 8)
          have aligned := localHeap.allocationAddress_ge (by decide : 0 < 8)
          have old := facts.frontier.1
          change current.heap.allocationAddress 8 + max (localBytes producer.input.tokenCount) 1 ≤
            localHeap.allocationAddress 8 at aligned
          dsimp only [Address] at start aligned old ⊢
          omega
        have copied : entry.CopyBounds origin.heap.nextAddress after.heap.nextAddress :=
          ⟨localHeap.allocationAddress 8, fresh, extent, rfl, rfl, rfl⟩
        refine Or.inr ⟨zero, entry, rfl, {
          cursorBound := by
            omega
          ordered := facts.ordered.insert chosen rfl
          source := ?_
          «protected» := protectedAfter
          table := preserved.1
          catalogState := by
            rw [countAfter, previousAfter] at invariant
            have fits : scan.initialCount.toInt.toNat + (inserted ++ [entry]).length < 2 ^ 31 := by
              have supported := facts.catalogState.supported
              dsimp only [Catalog.length] at nextRoom
              simp only [List.length_append, List.length_singleton]
              omega
            simpa only [Int32.toInt_ofNat_of_lt fits, Int.toNat_natCast] using CatalogHeap.ofInvariant invariant
          stored := prefixRep_append preserved.2 newPayloads
          copied := ?_
          frontier := ?_
          funding := ?_ }⟩
        · intro value member
          rcases List.mem_append.mp member with oldMember | newMember
          · exact facts.source value oldMember
          · simp only [List.mem_singleton] at newMember; subst value; exact ⟨source, meaning⟩
        · intro value member
          rcases List.mem_append.mp member with oldMember | newMember
          · exact retainedCopied value oldMember
          · simp only [List.mem_singleton] at newMember; subst value; exact copied
        · constructor
          · exact Nat.le_trans facts.frontier.1 frontier.1
          · rw [tokenEq] at frontier
            have old := facts.frontier.2
            have positive := Nat.le_max_right origin.heap.nextAddress 1
            rw [Nat.add_mul, Nat.one_mul]
            dsimp only [Address] at frontier old positive ⊢
            omega
        · intro funded
          have planned := facts.funding funded
          rw [scan.remainingPlan_next facts.ordered inside chosen,
            scan.emittedCount_present inside chosen bounds present] at planned
          obtain ⟨plannedLocal, plannedOne, planned⟩ := planned
          rw [← tokenEq, available] at plannedOne
          cases Option.some.inj plannedOne
          obtain ⟨plannedFirst, plannedTwo, planned⟩ := planned
          change consumeBudget budget (producer.body.count * 56) = some plannedFirst at plannedTwo
          rw [copyAvailable] at plannedTwo
          cases Option.some.inj plannedTwo
          obtain ⟨plannedSecond, plannedThree, tail⟩ := planned
          change consumeBudget first (producer.body.count * 4) = some plannedSecond at plannedThree
          rw [endsAvailable] at plannedThree
          cases Option.some.inj plannedThree
          simpa only [List.length_append, List.length_singleton, finalBudget] using tail
      · have negative : result = -1 := by simpa only [if_neg success] using answer
        have rejected : ¬model.Success produced.heap := fun accepted => success (successful.mp accepted)
        change ¬(scan.catalog.model next previous producer.request).Success produced.heap at rejected
        have countAfter : scan.catalog.afterCount next previous producer.request produced.heap = next := by
          simp only [Catalog.afterCount, if_neg rejected]
        have previousAfter : scan.catalog.afterRows next previous producer.request produced.heap = previous := by
          simp only [Catalog.afterRows, if_neg rejected]
        rw [countAfter, previousAfter] at invariant
        exact Or.inl ⟨negative, safe invariant, fun funded => by have := enough funded; omega⟩

#print axioms PayloadBytes.copiedBounds
#print axioms LoopFacts.produce

end IRBodyOwnedProof
