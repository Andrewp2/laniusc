import verified_compiler.tests.direct_ir_body_production_main_function
import verified_compiler.tests.direct_ir_body_production_main_representation

namespace IRBodyProductionProof

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRTypeRefProof
open IREventStoreProof IRBodyProductionScalar IRCatalogAppendProof IRCatalogConstructionProof

/-- Independent storage, room and sequential budgets suffice for insertion.
    This does not require a successful producer, append or validator run. -/
theorem streamSufficient (body : ReturnBody) (output : Context anchor)
    (permissions : OutputPermissions output body.count) (id : Int32) (result : Reference)
    {catalog : Catalog} {next : Int32} {previous : Nat → PreviousRow} {heap : Heap}
    (nonnegative : 0 ≤ id.toInt) (valid : isValidResult result = true)
    (occupied : 0 ≤ next.toInt) (room : next.toInt < catalog.capacity.toInt)
    (absent : ∀ index, index < next.toInt.toNat → (previous index).id.toInt ≠ id.toInt)
    (owned : consumeBudget heap.remaining (body.count * 56) = some first)
    (endpoints : consumeBudget first (body.count * 4) = some second) :
    (catalog.model next previous (streamRequest output id result body
      (fun index => if index = 0 then .Invalid else result))).Success heap := by
  have capacity : (Int32.ofNat output.capacity).toInt = output.capacity := by
    rw [Int32.toInt_ofNat']
    change (output.capacity : Int).bmod 4294967296 = output.capacity
    apply Int.bmod_eq_of_le <;> have := output.fits <;> omega
  have count : (Int32.ofNat body.count).toInt = body.count := by cases body <;> rfl
  have requested : (catalog.model next previous (streamRequest output id result body
      (fun index => if index = 0 then .Invalid else result))).request = body.count := by
    change (Int32.ofNat body.count).toInt.toNat = body.count
    cases body <;> rfl
  refine ⟨?_, ?_, ?_, ?_, ?_⟩
  · change 0 ≤ id.toInt ∧ isValidResult result = true ∧ 0 ≤ (0 : Int) ∧
      0 ≤ next.toInt ∧ next.toInt < catalog.capacity.toInt ∧
      0 < (Int32.ofNat body.count).toInt ∧
      (Int32.ofNat body.count).toInt ≤ (Int32.ofNat output.capacity).toInt
    rw [count, capacity]
    refine ⟨nonnegative, valid, by decide, occupied, room, ?_, ?_⟩
    · cases body <;> simp only [ReturnBody.count] <;> decide
    · have := permissions.bound; omega
  · rintro ⟨index, inside, same⟩
    exact absent index inside same
  · change 0 < _ ∧ _ ≤ 38347922
    rw [requested]
    cases body <;> simp only [ReturnBody.count] <;> decide
  · exact ⟨first, second, by simpa only [requested] using owned,
      by simpa only [requested] using endpoints⟩
  · exact body.canonical
      (arguments := (catalog.model next previous (streamRequest output id result body
        (fun index => if index = 0 then .Invalid else result))).toArguments)
      (annotations := fun index => if index = 0 then .Invalid else result)

/-- Interpret the public append retained by the actual generic producer.
    The signature and copied payloads name the same selected Core body; this
    is native representation correspondence, not backend execution. -/
theorem FunctionInsertion.stored (body : ReturnBody) (output : Context anchor)
    (permissions : OutputPermissions output body.count) (id : Int32) (result : Reference)
    (declared : result = body.result)
    (inserted : FunctionInsertion anchor body output permissions result allowed memory localHeap
      catalog next previous (streamRequest output id result body
        (fun index => if index = 0 then .Invalid else result)) before after)
    (successful : (catalog.model next previous (streamRequest output id result body
      (fun index => if index = 0 then .Invalid else result))).Success localHeap) :
    StoredTerminalRepresentation after.heap (catalog.rowBase next.toInt.toNat) id
      (localHeap.allocationAddress 8 + body.count * 40 - 8)
      (localHeap.allocationAddress 8 + body.count * 56 - 8)
      (localHeap.allocationAddress 8 + body.count * 56)
      body.count output.enabled body.coreStatement := by
  obtain ⟨_, produced, stream, _, _, post, _⟩ := inserted
  let annotations : Nat → Reference := fun index => if index = 0 then .Invalid else result
  let model := catalog.model next previous (streamRequest output id result body annotations)
  let arguments := model.toArguments
  have modelEq : ({ body.request arguments annotations with previous } : Model) = model := rfl
  have available : model.Success produced.heap := by
    simpa only [Model.Success, Arguments.BothAvailable, stream.2.2.2.budget] using successful
  have represented := body.storedRepresentation arguments (by rfl) declared annotations
    (fun index inside => by simp only [annotations, declared])
    (by rw [modelEq]; exact post) (by rw [modelEq]; exact available)
  have strict : next.toInt.toNat < catalog.length := by
    have guarded := successful.1
    change 0 ≤ id.toInt ∧ isValidResult result = true ∧ 0 ≤ (0 : Int) ∧
      0 ≤ next.toInt ∧ next.toInt < catalog.capacity.toInt ∧ _ at guarded
    dsimp only [Catalog.length]
    omega
  have row : arguments.rowBase arguments.occupied = catalog.rowBase next.toInt.toNat :=
    catalog.rowAddress strict
  have allocation : produced.heap.allocationAddress 8 = localHeap.allocationAddress 8 := by
    simp only [Heap.allocationAddress, stream.2.2.2.frontier]
  rw [row, allocation] at represented
  exact represented

#print axioms FunctionInsertion.stored
#print axioms streamSufficient

end IRBodyProductionProof
