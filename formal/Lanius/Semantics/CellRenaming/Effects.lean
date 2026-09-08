import Lanius.Semantics.CellRenaming.State
import Lanius.Separation

namespace Lanius.Semantics.CellRenaming
open Lanius.Core Lanius.Separation

theorem domainExtension (rename : CellId → CellId)
    (effect : CellDomainExtension before after) :
    CellDomainExtension (state rename before) (state rename after) := by
  constructor
  intro entry member
  obtain ⟨old, oldMember, rfl⟩ := List.mem_map.mp member
  obtain ⟨next, nextMember, same⟩ := effect.cells old oldMember
  exact ⟨cell rename next, List.mem_map.mpr ⟨next, nextMember, rfl⟩, congrArg rename same⟩

theorem storeEffect (rename : Permutation boundary) (ready : boundary ≤ before.nextCell)
    (effect : StoreEffect writes before after) :
    StoreEffect (fun id => writes (rename.backward id))
      (state rename.forward before) (state rename.forward after) := by
  constructor
  · intro id below unchanged
    have originalBelow : rename.backward id < before.nextCell := by
      by_cases old : id < boundary
      · exact Nat.lt_of_lt_of_le (rename.inverse.below old) ready
      · rw [rename.backward_fresh (Nat.le_of_not_gt old)]
        exact below
    have beforeAccess := cellEntry rename before (rename.backward id)
    have afterAccess := cellEntry rename after (rename.backward id)
    rw [rename.rightInverse] at beforeAccess afterAccess
    rw [afterAccess, beforeAccess, effect.oldCells _ originalBelow unchanged]
  · exact effect.nextCell
  · exact effect.heap
  · exact effect.world
  · change after.i32ArrayViews.map _ = before.i32ArrayViews.map _
    rw [effect.views]
  · exact domainExtension rename.forward effect.domain

theorem modifiesOnly (rename : Permutation boundary) (ready : boundary ≤ before.nextCell)
    (effect : ModifiesOnly writes before after) :
    ModifiesOnly (fun id => writes (rename.backward id))
      (state rename.forward before) (state rename.forward after) := by
  refine ⟨storeEffect rename ready effect.toStoreEffect, ?_⟩
  change after.locals.map _ = before.locals.map _
  rw [effect.locals]

end Lanius.Semantics.CellRenaming
