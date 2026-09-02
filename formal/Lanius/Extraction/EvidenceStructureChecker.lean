import Lanius.Extraction.CoreChecker
import Std.Data.TreeSet.Lemmas
import Std.Data.TreeSet.Raw.Lemmas

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

/-! The definitions above are the simple executable specification.  Running
them directly performs a fresh linear scan for every row.  The indexed
variants below preserve that exact result while using balanced finite sets for
the repeated membership queries. -/

private theorem natContainsMapEqAny {α : Type} (rows : List α)
    (node : α → Nat) (target : Nat) :
    (rows.map node).contains target = rows.any fun row => node row == target := by
  induction rows with
  | nil => rfl
  | cons head tail ih =>
      simp only [List.map_cons, List.contains_cons, List.any_cons, ih]
      rw [BEq.comm]

def typeSurfaceNodes (types : List TypeEvidence) : Std.TreeSet Nat :=
  Std.TreeSet.ofList (types.map (·.surface_node))

def loweringSurfaceNodes (lowering : List LoweringEvidence) : Std.TreeSet Nat :=
  Std.TreeSet.ofList (lowering.map (·.surface_node))

def typedLoweringRowsHaveTypeEvidenceIndexed
    (types : List TypeEvidence) (rows : List LoweringEvidence) : Bool :=
  let nodes := typeSurfaceNodes types
  rows.all fun row =>
    !typedLoweringRule row.rule || nodes.contains row.surface_node

def typeRowsHaveLoweringEvidenceIndexed
    (lowering : List LoweringEvidence) (rows : List TypeEvidence) : Bool :=
  let nodes := loweringSurfaceNodes lowering
  rows.all fun row => nodes.contains row.surface_node

theorem typedLoweringRowsHaveTypeEvidenceIndexed_eq
    (types : List TypeEvidence) (rows : List LoweringEvidence) :
    typedLoweringRowsHaveTypeEvidenceIndexed types rows =
      typedLoweringRowsHaveTypeEvidence types rows := by
  unfold typedLoweringRowsHaveTypeEvidenceIndexed typeSurfaceNodes
  simp only [Std.TreeSet.contains_ofList, natContainsMapEqAny]
  rfl

theorem typeRowsHaveLoweringEvidenceIndexed_eq
    (lowering : List LoweringEvidence) (rows : List TypeEvidence) :
    typeRowsHaveLoweringEvidenceIndexed lowering rows =
      typeRowsHaveLoweringEvidence lowering rows := by
  unfold typeRowsHaveLoweringEvidenceIndexed loweringSurfaceNodes
  simp only [Std.TreeSet.contains_ofList, natContainsMapEqAny]
  rfl

/-! A materialized index moves tree construction out of the hot certificate.
The equality fields are checked once at the data boundary; consumers reduce
only the literal tree lookups. -/

structure EvidenceNodeIndexes
    (types : List TypeEvidence) (lowering : List LoweringEvidence) where
  typeNodes : Std.TreeSet.Raw Nat
  loweringNodes : Std.TreeSet.Raw Nat
  typeNodesCanonical :
    typeNodes = Std.TreeSet.Raw.ofList (types.map (·.surface_node))
  loweringNodesCanonical :
    loweringNodes = Std.TreeSet.Raw.ofList (lowering.map (·.surface_node))

def typedLoweringRowsHaveTypeEvidenceMaterialized
    (typeNodes : Std.TreeSet.Raw Nat) (rows : List LoweringEvidence) : Bool :=
  rows.all fun row =>
    !typedLoweringRule row.rule || typeNodes.contains row.surface_node

def typeRowsHaveLoweringEvidenceMaterialized
    (loweringNodes : Std.TreeSet.Raw Nat) (rows : List TypeEvidence) : Bool :=
  rows.all fun row => loweringNodes.contains row.surface_node

theorem typedLoweringRowsHaveTypeEvidenceMaterialized_eq
    (indexes : EvidenceNodeIndexes types lowering) :
    typedLoweringRowsHaveTypeEvidenceMaterialized indexes.typeNodes lowering =
      typedLoweringRowsHaveTypeEvidence types lowering := by
  unfold typedLoweringRowsHaveTypeEvidenceMaterialized
  rw [indexes.typeNodesCanonical]
  simp only [Std.TreeSet.Raw.contains_ofList, natContainsMapEqAny]
  rfl

theorem typeRowsHaveLoweringEvidenceMaterialized_eq
    (indexes : EvidenceNodeIndexes types lowering) :
    typeRowsHaveLoweringEvidenceMaterialized indexes.loweringNodes types =
      typeRowsHaveLoweringEvidence lowering types := by
  unfold typeRowsHaveLoweringEvidenceMaterialized
  rw [indexes.loweringNodesCanonical]
  simp only [Std.TreeSet.Raw.contains_ofList, natContainsMapEqAny]
  rfl

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
        typedLoweringRowsHaveTypeEvidenceIndexed artifact.types artifact.lowering &&
        typeRowsHaveLoweringEvidenceIndexed artifact.lowering artifact.types
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
          simpa only [and_assoc, typedLoweringRowsHaveTypeEvidenceIndexed_eq,
            typeRowsHaveLoweringEvidenceIndexed_eq] using evidenceAccepted

end Lanius.Extraction
