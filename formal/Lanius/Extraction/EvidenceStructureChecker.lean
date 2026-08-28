import Lanius.Extraction.CoreChecker

namespace Lanius.Extraction

/-! ## Structural validation for semantic evidence

These checks make the untrusted resolution, typing, and lowering tables safe to
traverse.  They deliberately do not assert that a row's named rule is
semantically correct; the proof-producing source-to-Core checker owns that
responsibility.
-/

def referencesEarlier (index : Nat) (references : List Nat) : Bool :=
  references.all (· < index)

def indexedReferencesEarlier {α : Type}
    (references : α → List Nat) (rows : List α) : Bool :=
  rows.zipIdx.all fun (row, index) => referencesEarlier index (references row)

def resolutionRowsInUnits
    (currentUnit : Nat)
    (surfaceNodeCounts : List Nat)
    (rows : List ResolutionEvidence) : Bool :=
  match surfaceNodeCounts[currentUnit]? with
  | none => false
  | some currentNodeCount =>
      rows.all fun row =>
        row.use_node < currentNodeCount &&
          (match surfaceNodeCounts[row.declaration_unit]? with
          | none => false
          | some declarationNodeCount =>
              row.declaration_node < declarationNodeCount) &&
          row.scope_path.all (·.node < currentNodeCount)

def resolutionRowsInSurface
    (surfaceNodeCount : Nat) (rows : List ResolutionEvidence) : Bool :=
  resolutionRowsInUnits 0 [surfaceNodeCount] rows

def typeRowsInSurface
    (surfaceNodeCount : Nat) (rows : List TypeEvidence) : Bool :=
  rows.all (·.surface_node < surfaceNodeCount)

def loweringRowsInSurface
    (surfaceNodeCount : Nat) (rows : List LoweringEvidence) : Bool :=
  rows.all (·.surface_node < surfaceNodeCount)

def loweringCoversCore
    (program : CoreProgram) (rows : List LoweringEvidence) : Bool :=
  (rows.map (·.core_node)).mergeSort == List.range (coreProgramNodeIds program).length

def typedLoweringRule : LoweringRule → Bool
  | .literal | .local | .unary | .binary | .assignment | .call | .index |
      .field | .aggregate => true
  | .declaration | .statement | .control_flow => false

def typedLoweringRowsHaveTypeEvidence
    (types : List TypeEvidence) (rows : List LoweringEvidence) : Bool :=
  rows.all fun row =>
    !typedLoweringRule row.rule ||
      types.any (·.surface_node == row.surface_node)

def typeRowsHaveLoweringEvidence
    (lowering : List LoweringEvidence) (rows : List TypeEvidence) : Bool :=
  rows.all fun row => lowering.any (·.surface_node == row.surface_node)

def checkEvidenceStructure (artifact : Artifact) : Bool :=
  checkCoreStructure artifact &&
    match collectSurfaceClaims artifact, artifact.core_program with
    | some claims, some program =>
        resolutionRowsInSurface claims.nodes.length artifact.resolutions &&
        typeRowsInSurface claims.nodes.length artifact.types &&
        loweringRowsInSurface claims.nodes.length artifact.lowering &&
        indexedReferencesEarlier (·.premises) artifact.types &&
        indexedReferencesEarlier (·.premises) artifact.lowering &&
        loweringCoversCore program artifact.lowering &&
        typedLoweringRowsHaveTypeEvidence artifact.types artifact.lowering &&
        typeRowsHaveLoweringEvidence artifact.lowering artifact.types
    | _, _ => false

def EvidenceStructureValid (artifact : Artifact) : Prop :=
  CoreStructureValid artifact ∧
    ∃ claims program,
      collectSurfaceClaims artifact = some claims ∧
      artifact.core_program = some program ∧
      resolutionRowsInSurface claims.nodes.length artifact.resolutions = true ∧
      typeRowsInSurface claims.nodes.length artifact.types = true ∧
      loweringRowsInSurface claims.nodes.length artifact.lowering = true ∧
      indexedReferencesEarlier (·.premises) artifact.types = true ∧
      indexedReferencesEarlier (·.premises) artifact.lowering = true ∧
      loweringCoversCore program artifact.lowering = true ∧
      typedLoweringRowsHaveTypeEvidence artifact.types artifact.lowering = true ∧
      typeRowsHaveLoweringEvidence artifact.lowering artifact.types = true

theorem checkEvidenceStructure_sound {artifact : Artifact}
    (accepted : checkEvidenceStructure artifact = true) :
    EvidenceStructureValid artifact := by
  unfold checkEvidenceStructure at accepted
  simp only [Bool.and_eq_true] at accepted
  rcases accepted with ⟨coreAccepted, evidenceAccepted⟩
  refine ⟨checkCoreStructure_sound coreAccepted, ?_⟩
  cases claimsFound : collectSurfaceClaims artifact with
  | none => simp [claimsFound] at evidenceAccepted
  | some claims =>
      cases programFound : artifact.core_program with
      | none => simp [claimsFound, programFound] at evidenceAccepted
      | some program =>
          simp only [claimsFound, programFound, Bool.and_eq_true] at evidenceAccepted
          refine ⟨claims, program, rfl, rfl, ?_⟩
          simpa only [and_assoc] using evidenceAccepted

end Lanius.Extraction
