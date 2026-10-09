import verified_compiler.tests.direct_ir_catalog_construction
import Lanius.Semantics.ScopedEffect
import Lanius.Semantics.NativeSnapshotFrame

namespace IRBodyProductionProof

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics
open IRCatalogAppendProof IRCatalogConstructionProof

/-- The actual union of workspace writes retains the existing catalog;
    no whole-heap equality or inverse count decoder is required. -/
def catalogAfterWrites (invariant : Invariant catalog next previous before)
    (effect : MemoryEffect (fun old heap => HeapWritesOn old heap allowed) before after)
    (apart : ∀ address, catalog.memory ≤ address → address < catalog.memory + catalog.bytes → ¬allowed address) :
    Invariant catalog next previous after := by
  have write := effect.2.2.2
  obtain ⟨bytes, countBytes⟩ := (invariant.backing.subrange (start := 0) (length := 4)
    (by dsimp only [Catalog.bytes]; omega)).loadBytes
  have oldCount : before.heap.loadBytes catalog.memory 4 = .ok bytes := by
    simpa only [Nat.add_zero] using countBytes
  have newCount := write.loadBytes oldCount (fun offset bound => apart _ (by omega) (by
    dsimp only [Catalog.bytes]; omega))
  have below : HeapBlocksBelowNext after.heap := by
    intro block member
    have masked : { block with bytes := [] } ∈ after.heap.blocks.map (fun item => { item with bytes := [] }) :=
      List.mem_map.mpr ⟨block, member, rfl⟩
    rw [write.layout] at masked
    obtain ⟨old, oldMember, same⟩ := List.mem_map.mp masked
    have shape := congrArg (fun item : Block => item.base + max item.size 1) same
    simpa only [write.frontier, shape] using invariant.below old oldMember
  refine ⟨invariant.supported, invariant.bounds, ?_, write.readable _ _ invariant.backing,
    ?_, effect.1.after_cellsWellFormed invariant.formed, write.unique,
    below, effect.2.2.1.trans invariant.noViews⟩
  · simpa only [readNativeValue, loadNatLE, oldCount, newCount] using invariant.count
  · intro index inside
    exact (invariant.occupied index inside).afterFootprint write (fun address lower upper =>
      apart address (by dsimp only [Catalog.rowBase] at lower; omega) (by
        have := invariant.bounds
        dsimp only [Catalog.rowBase, Catalog.bytes, Catalog.length] at *
        omega))

#print axioms catalogAfterWrites

end IRBodyProductionProof
