import Lanius.Semantics.Relocation.State
import Lanius.FunctionalViewCoreStatefulSimulation

namespace Lanius.Semantics.Relocation

open Lanius.Core Lanius.Separation Lanius.FunctionalView.Core

theorem signedI32Values_fixed (symbols : Core.Relocation.Symbols) (entries : List Int) :
    Core.Relocation.values symbols (signedI32Values entries) = signedI32Values entries := by
  simp [signedI32Values, Core.Relocation.values_eq_map, List.map_map,
    Function.comp_def, Core.Relocation.value]

/-- Relocation changes tagged type IDs, not the contents or backing addresses
of the integer buffers owned by a frontend world. -/
theorem world_owns (symbols : Core.Relocation.Symbols)
    (owned : (ReadOnly.World.owns world).holds before) :
    (ReadOnly.World.owns world).holds (state symbols before) := by
  intro id entries found
  rw [cellEntry, owned id entries found]
  simp only [cell, Option.map, Core.Relocation.value, signedI32Values_fixed]

theorem representation_fixed (symbols : Core.Relocation.Symbols)
    (represented : Stateful.Representation layout localCell world environment before)
    (fixed : ∀ index, Core.Relocation.value symbols (environment index) = environment index) :
    Stateful.Representation layout localCell world environment (state symbols before) := by
  constructor
  · exact world_owns symbols represented.worldOwned
  · intro index
    have owned := represented.localOwned index
    constructor
    · exact owned.1
    · rw [cellEntry, owned.2]
      simp [cell, fixed]
  · exact represented.localCellsInjective
  · exact represented.worldLocalsDisjoint

end Lanius.Semantics.Relocation
