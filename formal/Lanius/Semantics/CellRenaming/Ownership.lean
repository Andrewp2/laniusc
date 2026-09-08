import Lanius.Semantics.CellRenaming.Access
import Lanius.FunctionalViewCoreStatefulSimulation

namespace Lanius.Semantics.CellRenaming
open Lanius.Core Lanius.Separation Lanius.FunctionalView.Core

def world (rename : Permutation boundary) (original : ReadOnly.World) : ReadOnly.World :=
  ⟨fun cell => original.i32Slice? (rename.backward cell)⟩

theorem signedI32Values_fixed (rename : CellId → CellId) (entries : List Int) :
    values rename (signedI32Values entries) = signedI32Values entries := by
  simp [signedI32Values, values_eq_map, List.map_map, Function.comp_def, value]

theorem world_owns (rename : Permutation boundary)
    (owned : (ReadOnly.World.owns original).holds before) :
    (ReadOnly.World.owns (world rename original)).holds (state rename.forward before) := by
  intro id entries found
  have old := owned (rename.backward id) entries found
  have access := cellEntry rename before (rename.backward id)
  rw [rename.rightInverse] at access
  rw [access, old]
  simp only [cell, Option.map, value, signedI32Values_fixed, rename.rightInverse]

theorem world_pair (rename : Permutation boundary)
    (left right : CellId) (leftValues rightValues : List Int) :
    world rename (ReadOnly.World.pair left leftValues right rightValues) =
      ReadOnly.World.pair (rename.forward left) leftValues (rename.forward right) rightValues := by
  apply congrArg ReadOnly.World.mk
  funext id
  have lookup : ∀ root, (rename.backward id = root) ↔ id = rename.forward root := by
    intro root
    constructor
    · intro same
      calc id = rename.forward (rename.backward id) := (rename.rightInverse id).symm
           _ = rename.forward root := congrArg rename.forward same
    · intro same
      rw [same, rename.leftInverse]
  simp only [world, ReadOnly.World.pair, lookup]

theorem representation (rename : Permutation boundary)
    (represented : Stateful.Representation layout localCell original environment before) :
    Stateful.Representation layout (fun index => rename.forward (localCell index))
      (world rename original) (fun index => value rename.forward (environment index))
      (state rename.forward before) := by
  constructor
  · exact world_owns rename represented.worldOwned
  · intro index
    obtain ⟨binding, entry⟩ := represented.localOwned index
    constructor
    · rw [cellId, binding]; rfl
    · rw [cellEntry, entry]; rfl
  · intro left right same
    exact represented.localCellsInjective (rename.injective same)
  · intro id owned localMember
    obtain ⟨index, rfl⟩ := localMember
    apply represented.worldLocalsDisjoint (localCell index)
    · obtain ⟨entries, found⟩ := owned
      exact ⟨entries, by simpa only [world, rename.leftInverse] using found⟩
    · exact ⟨index, rfl⟩

theorem world_inverse (rename : Permutation boundary) (original : ReadOnly.World) :
    world rename.inverse (world rename original) = original := by
  cases original with
  | mk lookup =>
      apply congrArg ReadOnly.World.mk
      funext id
      exact congrArg lookup (rename.leftInverse id)

theorem representation_inverse (rename : Permutation boundary)
    (represented : Stateful.Representation layout (fun index => rename.forward (localCell index))
      (world rename original) (fun index => value rename.forward (environment index)) before) :
    Stateful.Representation layout localCell original environment (state rename.backward before) := by
  have restored := representation rename.inverse represented
  have cells : (fun index => rename.backward (rename.forward (localCell index))) = localCell := by
    funext index
    exact rename.leftInverse (localCell index)
  have entries : (fun index => value rename.backward (value rename.forward (environment index))) = environment := by
    funext index
    exact value_leftInverse _ _ rename.leftInverse (environment index)
  rw [world_inverse] at restored
  simpa only [Permutation.inverse, cells, entries] using restored

end Lanius.Semantics.CellRenaming
