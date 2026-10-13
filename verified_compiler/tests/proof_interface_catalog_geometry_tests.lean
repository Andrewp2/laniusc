import verified_compiler.tests.direct_ir_catalog_construction

namespace ProofInterfaceCatalogGeometryTests

open IRCatalogAppendProof IRCatalogConstructionProof

-- A full one-row catalog occupies [96,200). Its unused hypothetical next row
-- is [8,104), so protected source storage at 8 is legitimately outside the
-- real catalog while overlapping that hypothetical write. The separate actual
-- full-capacity execution fixture checks that the implementation rejects it.
private def full : Catalog := { memory := 96, capacity := 1 }

theorem capacityGuardNecessary (request : Model) (previous : Nat → PreviousRow) :
    (∀ address, address = 8 → (1 : Int32).toInt < full.capacity.toInt →
      ¬(full.model 1 previous request).footprint address) ∧
    ¬(∀ address, address = 8 → ¬(full.model 1 previous request).footprint address) ∧
    ¬(full.memory ≤ 8 ∧ 8 < full.memory + full.bytes) := by
  have one : (1 : Int32).toInt = 1 := by decide
  refine ⟨?_, ?_, ?_⟩
  · intro _ _ room
    change (1 : Int) < 1 at room
    omega
  · intro unconditional
    apply unconditional 8 rfl
    simp only [Arguments.footprint, Arguments.rowBase, Arguments.occupied,
      Catalog.model, Catalog.length, full, one]
    left
    decide
  · change ¬(96 ≤ 8 ∧ 8 < 200)
    omega

#print axioms capacityGuardNecessary

end ProofInterfaceCatalogGeometryTests
