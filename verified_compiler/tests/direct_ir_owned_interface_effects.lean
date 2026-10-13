import verified_compiler.tests.direct_ir_owned_interface_producer
import Lanius.Semantics.Representation

namespace IRBodyOwnedProof

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRBodyOwnedInputs
open IRBodyProductionInputs IRBodyProductionProof IRBodyProductionScalar IREventStoreProof
open IRCatalogAppendProof IRCatalogConstructionProof

variable {before after : State} {raw : RawInputs} {workspace : RawWorkspace} {row : AllocationRow}
  {region mutable : Nat → Prop} {catalog : Catalog} {next : Int32} {previous : Nat → PreviousRow}
  {result : Int} {footprint : Footprint}
  {original : OriginalProducer raw workspace row before region mutable catalog}

def OriginalProducer.localHeap
    (original : OriginalProducer raw workspace row before region mutable catalog) (budget : Option Nat) : Heap :=
  (before.heap.allocatedBytes (localBytes original.input.tokenCount) 8 budget).borrowBlock
    (before.heap.allocationAddress 8)

theorem OriginalProducer.requestCount
    (original : OriginalProducer raw workspace row before region mutable catalog) :
    (catalog.model next previous original.request).request = original.body.count := by
  change (Int32.ofNat original.body.count).toInt.toNat = original.body.count
  cases body : original.body <;> rfl

private theorem expectedFrame (model : Model) (below : HeapBlocksBelowNext heap) :
    HeapFrame footprint heap (model.expectedHeap heap) := by
  classical
  unfold Model.expectedHeap
  split
  · cases first : consumeBudget heap.remaining (model.request * 56) with
    | none => exact HeapFrame.refl _ _
    | some budget =>
        have allocated : HeapFrame footprint heap (model.firstHeap heap budget) :=
          HeapFrame.allocatedBorrowed below (by decide : 0 < 8)
        cases second : consumeBudget budget (model.request * 4) with
        | none => simpa only [second] using allocated
        | some remaining =>
            simpa only [second] using allocated.trans
              (HeapFrame.appendI32 (bytes := List.replicate (model.request * 4) 0)
                (owned := false) (budget := remaining))
  · exact HeapFrame.refl _ _

private theorem postFrame (post : Post model caller result heap world views)
    (below : HeapBlocksBelowNext caller.heap)
    (apart : ∀ address, footprint.bytes address → ¬(model.Success caller.heap ∧ model.footprint address)) :
    HeapFrame footprint caller.heap heap := by
  have allocated := expectedFrame (footprint := footprint) model below
  exact ⟨fun p o b inside loaded => post.outside p o b loaded (apart _ inside), post.readable,
    allocated.blocks.trans (BlockObservation.ofLayout (fun _ => rfl) post.metadata.2.2),
    allocated.ownership.trans (BlockObservation.ofLayout (fun _ => rfl) post.metadata.2.2)⟩

/-- One effect bridge for all actual1179 outcomes. Unread future addresses
    may occur in the footprint: freshness is checked only for old successful reads. -/
theorem ProducerObservation.frame (observation : ProducerObservation original next previous result after)
    (below : HeapBlocksBelowNext before.heap)
    (workspaceApart : ∀ address, footprint.bytes address → ¬original.allowed address)
    (catalogApart : ∀ address, footprint.bytes address → next.toInt < catalog.capacity.toInt →
      ¬(catalog.model next previous original.request).footprint address) :
    HeapFrame footprint before.heap after.heap := by
  cases available : consumeBudget before.heap.remaining (localBytes original.input.tokenCount) with
  | none =>
      have unchanged := (observation.2.2.2.1 available).2.1
      rw [unchanged]
      exact HeapFrame.refl _ _
  | some budget =>
      obtain ⟨_, inserted, _⟩ := observation.2.2.2.2.1 budget available
      obtain ⟨produced, stream, _, _, post, _⟩ := inserted.2
      have written := stream.2.2.2
      have allocated : HeapFrame footprint before.heap (original.localHeap budget) :=
        HeapFrame.allocatedBorrowed below (by decide : 0 < 8)
      have production : HeapFrame footprint before.heap produced.heap := by
        refine ⟨?_, fun p n room => written.readable p n (allocated.readable p n room),
          allocated.blocks.trans (BlockObservation.ofLayout (fun _ => rfl) written.layout),
          allocated.ownership.trans (BlockObservation.ofLayout (fun _ => rfl) written.layout)⟩
        intro pointer offset byte inside loaded
        obtain ⟨block, found, _⟩ := Heap.loadByte_ok_iff.mp loaded
        have contains := List.find?_some found
        have bound := below block (List.mem_of_find?_eq_some found)
        have fresh := before.heap.allocationAddress_ge (by decide : 0 < 8)
        simp only [Bool.and_eq_true, decide_eq_true_eq] at contains
        have apart : ¬(original.allowed (pointer + offset) ∨
            before.heap.allocationAddress 8 ≤ pointer + offset ∧
              pointer + offset < before.heap.allocationAddress 8 + 4) := by
          intro changed
          rcases changed with changed | changed
          · exact workspaceApart _ inside changed
          · dsimp only [Address] at *; omega
        rw [written.outside pointer offset apart]
        exact allocated.bytes pointer offset byte inside loaded
      have localBelow : HeapBlocksBelowNext (original.localHeap budget) :=
        (before.heap.allocatedBytes_below below (by decide : 0 < 8)).borrowBlock
      exact production.trans (postFrame post (written.below localBelow)
        (fun address inside changed =>
          catalogApart address inside changed.1.1.2.2.2.2.1 changed.2))

/-- A zero result exposes the same actual funded insertion and represented
    body. It is a consequence of the call observation, not an input premise. -/
theorem ProducerObservation.funded (observation : ProducerObservation original next previous result after)
    (success : result = 0) :
    ∃ budget, consumeBudget before.heap.remaining (localBytes original.input.tokenCount) = some budget ∧
      (catalog.model next previous original.request).Success (original.localHeap budget) ∧
      FunctionInsertion before original.body original.output original.permissions original.input.signature.result
        original.allowed (before.heap.allocationAddress 8) (original.localHeap budget)
        catalog next previous original.request before after ∧
      StoredTerminalRepresentation after.heap (catalog.rowBase next.toInt.toNat)
        (Int32.ofNat original.input.signature.id)
        ((original.localHeap budget).allocationAddress 8 + original.body.count * 40 - 8)
        ((original.localHeap budget).allocationAddress 8 + original.body.count * 56 - 8)
        ((original.localHeap budget).allocationAddress 8 + original.body.count * 56)
        original.body.count original.output.enabled original.body.coreStatement := by
  classical
  cases available : consumeBudget before.heap.remaining (localBytes original.input.tokenCount) with
  | none => have failed := (observation.2.2.2.1 available).1; omega
  | some budget =>
      obtain ⟨answer, insertion, stored⟩ := observation.2.2.2.2.1 budget available
      have successful : (catalog.model next previous original.request).Success (original.localHeap budget) := by
        by_cases reached : (catalog.model next previous original.request).Success (original.localHeap budget)
        · exact reached
        · rw [if_neg (show ¬(catalog.model next previous original.request).Success
            ((before.heap.allocatedBytes (localBytes original.input.tokenCount) 8 budget).borrowBlock
              (before.heap.allocationAddress 8)) from reached)] at answer
          omega
      exact ⟨budget, rfl, successful, insertion, stored successful⟩

private theorem alignmentBounds (address alignment : Nat) (positive : 0 < alignment) :
    address ≤ alignUp address alignment ∧ alignUp address alignment < address + alignment := by
  have remainder := Nat.mod_lt (address + alignment - 1) positive
  have division := Nat.mod_add_div (address + alignment - 1) alignment
  unfold alignUp
  rw [Nat.mul_comm alignment] at division
  omega

private theorem expectedBounds (model : Model) (heap : Heap) (small : model.request ≤ 3) :
    heap.nextAddress ≤ (model.expectedHeap heap).nextAddress ∧
      (model.expectedHeap heap).nextAddress ≤ max heap.nextAddress 1 + 192 := by
  classical
  have first := alignmentBounds (max heap.nextAddress 1) 8 (by decide)
  have original := Nat.le_max_left heap.nextAddress 1
  have positive := Nat.le_max_right heap.nextAddress 1
  have second := alignmentBounds
    (max (heap.allocationAddress 8 + max (model.request * 56) 1) 1) 4 (by decide)
  change max heap.nextAddress 1 ≤ heap.allocationAddress 8 ∧
    heap.allocationAddress 8 < max heap.nextAddress 1 + 8 at first
  dsimp only [Address] at *
  unfold Model.expectedHeap
  split
  · cases one : consumeBudget heap.remaining (model.request * 56) with
    | none => exact ⟨Nat.le_refl _, Nat.le_trans (Nat.le_max_left _ _) (Nat.le_add_right _ _)⟩
    | some budget =>
        cases two : consumeBudget budget (model.request * 4) with
        | none =>
            simp only [two, Arguments.firstHeap, Heap.allocatedBytes, Heap.borrowBlock]
            omega
        | some remaining =>
            simp only [two, Arguments.firstHeap, Heap.allocatedBytes, Heap.borrowBlock,
              Heap.appendI32, Heap.borrowedAddress, List.length_replicate]
            dsimp only [Address] at *
            omega
  · exact ⟨Nat.le_refl _, Nat.le_trans (Nat.le_max_left _ _) (Nat.le_add_right _ _)⟩

/-- All actual outcomes retain enough frontier headroom for the next call;
    no allocation-attempt list is part of the loop invariant. -/
theorem ProducerObservation.frontierBounds (observation : ProducerObservation original next previous result after) :
    before.heap.nextAddress ≤ after.heap.nextAddress ∧
      after.heap.nextAddress ≤ max before.heap.nextAddress 1 + localBytes original.input.tokenCount + 200 := by
  cases available : consumeBudget before.heap.remaining (localBytes original.input.tokenCount) with
  | none =>
      rw [(observation.2.2.2.1 available).2.1]
      exact ⟨Nat.le_refl _, Nat.le_trans (Nat.le_max_left _ _)
        (Nat.le_trans (Nat.le_add_right _ _) (Nat.le_add_right _ _))⟩
  | some budget =>
      obtain ⟨_, inserted, _⟩ := observation.2.2.2.2.1 budget available
      obtain ⟨produced, stream, _, _, post, _⟩ := inserted.2
      have written := stream.2.2.2
      have small : (catalog.model next previous original.request).request ≤ 3 := by
        rw [original.requestCount]
        cases body : original.body <;> simp only [ReturnBody.count] <;> decide
      have bound := expectedBounds (catalog.model next previous original.request) produced.heap small
      rw [← post.metadata.1] at bound
      have size : 1 ≤ localBytes original.input.tokenCount := by unfold localBytes; omega
      have atProduced : produced.heap.nextAddress = before.heap.allocationAddress 8 +
          localBytes original.input.tokenCount := by
        simpa only [Heap.allocatedBytes, Heap.borrowBlock, Nat.max_eq_left size] using written.frontier
      have aligned := alignmentBounds (max before.heap.nextAddress 1) 8 (by decide)
      change max before.heap.nextAddress 1 ≤ before.heap.allocationAddress 8 ∧
        before.heap.allocationAddress 8 < max before.heap.nextAddress 1 + 8 at aligned
      have original := Nat.le_max_left before.heap.nextAddress 1
      dsimp only [Address] at *
      omega

private theorem postCopiedExtent (post : Post model caller result heap world views)
    (successful : model.Success caller.heap) :
    caller.heap.allocationAddress 8 + model.request * 60 ≤ heap.nextAddress := by
  classical
  obtain ⟨first, second, available, endpoints⟩ := successful.2.2.2.1
  have active : model.Guarded ∧ ¬model.Duplicate ∧ model.Sized :=
    ⟨successful.1, successful.2.1, successful.2.2.1⟩
  have aligned := (alignmentBounds
    (max (caller.heap.allocationAddress 8 + max (model.request * 56) 1) 1) 4 (by decide)).1
  rw [post.metadata.1]
  simp only [Model.expectedHeap, if_pos active, available, endpoints, Arguments.firstHeap,
    Heap.allocatedBytes, Heap.borrowBlock, Heap.appendI32, Heap.borrowedAddress, List.length_replicate]
  change caller.heap.allocationAddress 8 + model.request * 60 ≤
    alignUp (max (caller.heap.allocationAddress 8 + max (model.request * 56) 1) 1) 4 + max (model.request * 4) 1
  dsimp only [Address] at *
  omega

/-- The successful observation supplies the three sequential budgets and
    the copied payload bound used by future disjoint-allocation frames. -/
theorem ProducerObservation.successResources (observation : ProducerObservation original next previous result after)
    (success : result = 0) :
    ∃ budget first second,
      consumeBudget before.heap.remaining (localBytes original.input.tokenCount) = some budget ∧
      consumeBudget budget (original.body.count * 56) = some first ∧
      consumeBudget first (original.body.count * 4) = some second ∧
      after.heap.remaining = second ∧
      (original.localHeap budget).allocationAddress 8 + original.body.count * 60 ≤ after.heap.nextAddress := by
  classical
  obtain ⟨budget, localAvailable, successful, inserted, _⟩ := observation.funded success
  obtain ⟨produced, stream, _, _, post, _⟩ := inserted.2
  have written := stream.2.2.2
  have currentSuccess : (catalog.model next previous original.request).Success produced.heap := by
    simpa only [Model.Success, Arguments.BothAvailable, written.budget] using successful
  obtain ⟨first, second, available, endpoints⟩ := currentSuccess.2.2.2.1
  have active : (catalog.model next previous original.request).Guarded ∧
      ¬(catalog.model next previous original.request).Duplicate ∧
        (catalog.model next previous original.request).Sized :=
    ⟨currentSuccess.1, currentSuccess.2.1, currentSuccess.2.2.1⟩
  have localBudget : produced.heap.remaining = budget := by
    simpa only [OriginalProducer.localHeap, Heap.allocatedBytes, Heap.borrowBlock] using written.budget
  have finalBudget : after.heap.remaining = second := by
    simpa only [Model.expectedHeap, if_pos active, available, endpoints, Arguments.firstHeap,
      Heap.allocatedBytes, Heap.borrowBlock, Heap.appendI32] using post.metadata.2.1
  have extent := postCopiedExtent post currentSuccess
  have allocation : produced.heap.allocationAddress 8 = (original.localHeap budget).allocationAddress 8 := by
    simp only [Heap.allocationAddress, written.frontier]
  refine ⟨budget, first, second, localAvailable, ?_, ?_, finalBudget, ?_⟩
  · simpa only [localBudget, original.requestCount] using available
  · simpa only [original.requestCount] using endpoints
  · simpa only [allocation, original.requestCount] using extent

#print axioms ProducerObservation.frame
#print axioms ProducerObservation.funded
#print axioms ProducerObservation.frontierBounds
#print axioms ProducerObservation.successResources

end IRBodyOwnedProof
