import Lanius.Separation.CellEffect
import Lanius.Semantics.Relocation.State

namespace Lanius.Separation

open Lanius.Core Lanius.Semantics

theorem CellDomainExtension.relocate (extension : CellDomainExtension before after)
    (symbols : Core.Relocation.Symbols) :
    CellDomainExtension (Semantics.Relocation.state symbols before) (Semantics.Relocation.state symbols after) := by
  constructor
  intro entry member
  obtain ⟨original, originalMember, rfl⟩ := List.mem_map.mp member
  obtain ⟨updated, updatedMember, same⟩ := extension.cells original originalMember
  exact ⟨Semantics.Relocation.cell symbols updated, List.mem_map.mpr ⟨updated, updatedMember, rfl⟩, same⟩

/-- Symbol relocation preserves cell identities and therefore preserves
    logical write footprints, caller locals, and the host world. -/
theorem CellEffect.relocate (effect : CellEffect writes before after)
    (symbols : Core.Relocation.Symbols) :
    CellEffect writes (Semantics.Relocation.state symbols before) (Semantics.Relocation.state symbols after) := by
  refine ⟨Semantics.Relocation.state_wellFormed symbols effect.wellFormed,
    effect.locals, effect.world, ?_, effect.nextCell, effect.domain.relocate symbols⟩
  intro cell old untouched
  simp only [Semantics.Relocation.cellEntry, effect.oldCells cell old untouched]

end Lanius.Separation
