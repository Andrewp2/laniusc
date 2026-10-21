import verified_compiler.tests.direct_ir_catalog_copy

namespace IRCatalogCopyProof
open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IREventStoreProof

/-- Writable buffers and represented values only in the copied prefix.
    The untouched suffix is not decoded or assigned a semantic value. -/
structure Buffer (input : Input original) (heap : Heap) (copied : Nat) : Prop where
  room : heap.Readable input.memory (input.count * 56)
  events : ∀ index, index < copied → NativeSnapshot 64 extractedProgram heap eventType
    (input.eventBase index) (input.events index) 40
  types : ∀ index, index < copied → NativeSnapshot 64 extractedProgram heap referenceType
    (input.typeBase index) (input.annotation index) 16

theorem Buffer.seed (input : Input original) (budget : Option Nat)
    (below : HeapBlocksBelowNext original.heap) : Buffer input (input.freshHeap budget) 0 := by
  have zeros : ∀ offset width, offset + width ≤ input.count * 56 →
      (input.freshHeap budget).loadBytes (input.memory + offset) width =
        .ok (List.replicate width 0) := by
    intro offset width bounds
    dsimp only [Input.freshHeap, Input.memory]
    rw [Heap.loadBytes_borrowBlock]
    exact original.heap.allocatedBytes_zeroRange below (by decide) bounds
  refine ⟨Heap.Readable.of_loadBytes (by simpa only [Nat.add_zero] using zeros 0 (input.count * 56) (by omega)), ?_, ?_⟩
  · intro index inside; omega
  · intro index inside; omega

def Buffer.slot (buffer : Buffer input state.heap copied) (inside : copied < input.count)
    (fits : input.count * 56 < 2 ^ 31) : Context state := {
  position := copied, capacity := input.count, events := input.eventPointer, types := input.typePointer
  typesLength := input.count, enabled := true
  eventBase := input.eventBase copied, typeBase := input.typeBase copied
  bound := inside, fits := by omega
  eventLocation := input.eventLocation inside
  typeBound := fun _ => inside, typeLocation := fun _ => input.typeLocation inside
  eventRoom := by
    simpa only [Input.eventBase] using buffer.room.subrange (start := (input.count - copied - 1) * 40) (by omega :
      (input.count - copied - 1) * 40 + 40 ≤ input.count * 56)
  typeRoom := by
    intro _
    simpa only [Input.typeBase, Nat.add_assoc] using buffer.room.subrange
      (start := input.count * 40 + (input.count - copied - 1) * 16) (by omega :
        input.count * 40 + (input.count - copied - 1) * 16 + 16 ≤ input.count * 56)
  separate := fun _ => Or.inl (by dsimp only [Input.eventBase, Input.typeBase]; omega) }

theorem Buffer.afterPair (buffer : Buffer input before copied) (inside : copied < input.count)
    (eventSnapshot : NativeSnapshot 64 extractedProgram middle eventType
      (input.eventBase copied) (input.events copied) 40)
    (eventWrite : HeapRegionWrite before middle (input.eventBase copied) 40)
    (typeSnapshot : NativeSnapshot 64 extractedProgram after referenceType
      (input.typeBase copied) (input.annotation copied) 16)
    (typeWrite : HeapRegionWrite middle after (input.typeBase copied) 16) :
    Buffer input after (copied + 1) := by
  refine ⟨typeWrite.readable _ _ (eventWrite.readable _ _ buffer.room), ?_, ?_⟩
  · intro index bound
    by_cases same : index = copied
    · subst index
      exact eventSnapshot.afterWrite typeWrite (Or.inl (by
        dsimp only [Input.eventBase, Input.typeBase]; omega))
    · have eventApart : input.eventBase index + 40 ≤ input.eventBase copied ∨
          input.eventBase copied + 40 ≤ input.eventBase index := by
        dsimp only [Input.eventBase]; omega
      have typeApart : input.eventBase index + 40 ≤ input.typeBase copied ∨
          input.typeBase copied + 16 ≤ input.eventBase index := Or.inl (by
        dsimp only [Input.eventBase, Input.typeBase]; omega)
      exact ((buffer.events index (by omega)).afterWrite eventWrite eventApart).afterWrite typeWrite typeApart
  · intro index bound
    by_cases same : index = copied
    · subst index
      exact typeSnapshot
    · have eventApart : input.typeBase index + 16 ≤ input.eventBase copied ∨
          input.eventBase copied + 40 ≤ input.typeBase index := Or.inr (by
        dsimp only [Input.eventBase, Input.typeBase]; omega)
      have typeApart : input.typeBase index + 16 ≤ input.typeBase copied ∨
          input.typeBase copied + 16 ≤ input.typeBase index := by
        dsimp only [Input.typeBase]; omega
      exact ((buffer.types index (by omega)).afterWrite eventWrite eventApart).afterWrite typeWrite typeApart

#print axioms Buffer.seed
#print axioms Buffer.afterPair
end IRCatalogCopyProof
