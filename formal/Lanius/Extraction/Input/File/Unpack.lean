import Lanius.Extraction.Input.File.Guards
import Lanius.Extraction.Input.Unpack.Initialize

namespace Lanius.Extraction.Input.File

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Extraction.CompactOutput

/-- Append one host-returned chunk at the current total, run the real
compound assignment, and close the unpacking cursor's scope. -/
theorem unpackChunk (program : Program) (invariant : Buffers memory processed before)
    (copied : Host.Copied memory.packed bytes before)
    (countRead : before.local? 9 = some (.signed .i32 bytes.length))
    (capacity : processed.length + bytes.length ≤ memory.capacity) :
    ∃ after, Executes program before unpackAndAdvance .next after ∧
      Buffers memory (processed ++ bytes) after ∧ ModifiesOnly memory.writes before after := by
  let stage : Unpack.Stage := ⟨unpackLocals, updateTotal⟩
  suffices done : ∃ completion after, Executes program before unpackAndAdvance completion after ∧
      completion = .next ∧ Buffers memory (processed ++ bytes) after ∧ ModifiesOnly memory.writes before after by
    obtain ⟨completion, after, run, rfl, buffers, effect⟩ := done
    exact ⟨after, run, buffers, effect⟩
  apply stage.executes ⟨by decide, by decide, by decide, by decide⟩ program before invariant.registry
    invariant.representable memory.packed memory.output bytes processed.length
    (Assertion.localPointsTo_local _ _ _ _ invariant.total) copied invariant.packedMember invariant.outputMember
    memory.outputPacked.symm invariant.packedLocal invariant.outputLocal countRead
    (Nat.le_trans capacity memory.capacityBound) memory.outputBound
    (fun completion after => completion = .next ∧ Buffers memory (processed ++ bytes) after ∧ ModifiesOnly memory.writes before after)
  intro original middle originalLength originalContents registry representable _copied written unpackEffect kept _reached
  have identical : original = memory.outputValues processed := by
    have arrays := originalContents.symm.trans invariant.outputContents
    injection arrays with arrays
    injection arrays with _ values
    injection values with values
    exact signedI32Values_injective (Value.array.inj values)
  subst original
  have oldTotal := StateWellFormed.cell_lt_next_of_entry invariant.registry.wellFormed invariant.total.2
  have readyRegistry := invariant.registry.bindLocal 10 (.signed .i32 0)
  have readyTotal := bindLocal_preserves_localPointsTo_of_ne before 10 5 (.signed .i32 0) memory.totalCell _
    invariant.registry.wellFormed (by decide) invariant.total
  have middleTotal := unpackEffect.preserves_localPointsTo readyRegistry.wellFormed readyTotal
    (show ¬ CellSet.union (CellSet.singleton memory.output.root) (CellSet.singleton before.nextCell) memory.totalCell from
      fun changed => changed.elim memory.outputTotal.symm (Nat.ne_of_lt oldTotal))
  have middleCount : middle.local? 9 = some (.signed .i32 bytes.length) :=
    kept 9 (by decide) _ (by intro elements same; cases same) countRead
  have arithmetic : evalAssignValue program.target .add (some (.signed .i32 processed.length))
      (.signed .i32 bytes.length) = .ok (.signed .i32 (Int.ofNat (processed.length + bytes.length))) := by
    simp only [evalAssignValue, assignOpBinary?, evalBinaryValue, beq_self_eq_true, if_true, evalSignedBinary]
    rw [show (processed.length : Int) + bytes.length = Int.ofNat (processed.length + bytes.length) from by
        simp only [Int.ofNat_eq_natCast, Int.natCast_add],
      wrapSigned_i32_ofNat program.target _
      (Nat.le_trans capacity (Nat.le_trans memory.capacityBound memory.outputBound))]
  obtain ⟨after, updated, valid, totalAfter, updateEffect⟩ := evaluatesUpdateOwnedLocalFromEmpty 5 memory.totalCell .add
    registry.wellFormed middleTotal (local_evaluates program middleCount) registry.wellFormed
    (ModifiesOnly.refl middle) arithmetic
  have noView : ∀ view ∈ middle.i32ArrayViews, ¬ CellSet.singleton memory.totalCell view.root := by
    intro view member same
    change view.root = memory.totalCell at same
    exact registry.notScalar member (same.symm ▸ middleTotal.2)
  have afterRegistry := registry.transport (CellEffect.ofModifiesOnly updateEffect valid)
    (HeapFrame.ofStoreEffect updateEffect.toStoreEffect) (fun view member impossible => False.elim (noView view member impossible))
  have afterRepresentable := representable.transport registry (CellEffect.ofModifiesOnly updateEffect valid)
    (HeapFrame.ofStoreEffect updateEffect.toStoreEffect) (fun view member impossible => False.elim (noView view member impossible))
  have outputAfter := updateEffect.preserves_entry registry.wellFormed written memory.outputTotal
  rw [memory.outputValues_append] at outputAfter
  have combined := ((bindLocal_effect before 10 (.signed .i32 0)).trans unpackEffect.toStoreEffect).trans updateEffect.toStoreEffect
  have scopedEffect : StoreEffect memory.writes before after := combined.hideFreshWritesExcept (by
    intro cell written
    change (False ∨ cell = memory.output.root ∨ cell = before.nextCell) ∨ cell = memory.totalCell at written
    rcases written with (impossible | output | cursor) | total
    · exact False.elim impossible
    · exact Or.inl (Or.inl (Or.inl output))
    · exact Or.inr (cursor ▸ Nat.le_refl _)
    · exact Or.inl (Or.inr total))
  have closedEffect := scopedEffect.restoreLocals
  have closedValid := scopedEffect.domain.restoreLocals_wellFormed invariant.registry.wellFormed valid
  have closedRegistry := afterRegistry.restoreLocals before closedValid
  have closedBuffers := invariant.finish (Host.Effect.ofPure closedEffect closedValid) closedRegistry afterRepresentable
    (by simpa only [List.length_append, Int.ofNat_eq_natCast, State.cellEntry?, restoreLocals] using totalAfter.2)
    outputAfter (by simpa only [List.length_append] using capacity)
  exact ⟨.next, after, executesSequence (executesExpression updated) (executesSkip _ _), rfl, closedBuffers, closedEffect⟩

end Lanius.Extraction.Input.File
