import Lanius.Extraction.CoreChecker
import Lanius.Data.SeqTree
import Std.Data.TreeSet.Lemmas

namespace Lanius.Extraction

open Lanius.Data

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

/-! ## Direct cross-table witnesses

The finite-set fallback above still constructs a global derived structure.
For generated certificates, a smaller proof boundary is enough: the exporter
proposes the exact row that witnesses each cross-table relationship, and the
checker validates that row with a logarithmic lookup in a checked `SeqTree`.
The proposed indexes carry no authority; malformed indexes simply fail.
-/

structure EvidenceWitnessCache where
  leafCapacity : Nat
  types : SeqTree TypeEvidence
  lowering : SeqTree LoweringEvidence
  /-- One proposed type-row index for every lowering row.  The value is ignored
  for lowering rules that do not require type evidence. -/
  loweringTypeRefs : List Nat
  /-- One proposed lowering-row index for every type row. -/
  typeLoweringRefs : List Nat
deriving Repr, Lean.ToExpr

structure EvidenceWitnessView (artifact : Artifact) where
  cache : EvidenceWitnessCache
  typesWellFormed : cache.types.WellFormed cache.leafCapacity
  typesRepresent : cache.types.Represents artifact.types
  loweringWellFormed : cache.lowering.WellFormed cache.leafCapacity
  loweringRepresent : cache.lowering.Represents artifact.lowering

def checkTypedLoweringWitnesses (types : SeqTree TypeEvidence) :
    List LoweringEvidence → List Nat → Bool
  | [], [] => true
  | row :: rows, typeIndex :: typeIndexes =>
      (!typedLoweringRule row.rule ||
        match types.lookup typeIndex with
        | some typeRow => typeRow.surface_node == row.surface_node
        | none => false) &&
      checkTypedLoweringWitnesses types rows typeIndexes
  | _, _ => false

def checkTypeLoweringWitnesses (lowering : SeqTree LoweringEvidence) :
    List TypeEvidence → List Nat → Bool
  | [], [] => true
  | row :: rows, loweringIndex :: loweringIndexes =>
      (match lowering.lookup loweringIndex with
        | some loweringRow => loweringRow.surface_node == row.surface_node
        | none => false) &&
      checkTypeLoweringWitnesses lowering rows loweringIndexes
  | _, _ => false

def checkEvidenceWitnesses (view : EvidenceWitnessView artifact) : Bool :=
  checkTypedLoweringWitnesses view.cache.types artifact.lowering
      view.cache.loweringTypeRefs &&
    checkTypeLoweringWitnesses view.cache.lowering artifact.types
      view.cache.typeLoweringRefs

private theorem typeEvidenceAny_of_lookup
    {tree : SeqTree TypeEvidence} {types : List TypeEvidence}
    (wellFormed : tree.WellFormed leafCapacity)
    (represents : tree.Represents types)
    (found : tree.lookup index = some typeRow)
    (sameNode : (typeRow.surface_node == surfaceNode) = true) :
    types.any (·.surface_node == surfaceNode) = true := by
  apply List.any_eq_true.mpr
  refine ⟨typeRow, ?_, sameNode⟩
  apply List.mem_of_getElem?
  rw [← represents, ← tree.lookup_eq_flatten wellFormed]
  exact found

private theorem loweringEvidenceAny_of_lookup
    {tree : SeqTree LoweringEvidence} {lowering : List LoweringEvidence}
    (wellFormed : tree.WellFormed leafCapacity)
    (represents : tree.Represents lowering)
    (found : tree.lookup index = some loweringRow)
    (sameNode : (loweringRow.surface_node == surfaceNode) = true) :
    lowering.any (·.surface_node == surfaceNode) = true := by
  apply List.any_eq_true.mpr
  refine ⟨loweringRow, ?_, sameNode⟩
  apply List.mem_of_getElem?
  rw [← represents, ← tree.lookup_eq_flatten wellFormed]
  exact found

theorem checkTypedLoweringWitnesses_sound
    {tree : SeqTree TypeEvidence} {types : List TypeEvidence}
    (wellFormed : tree.WellFormed leafCapacity)
    (represents : tree.Represents types)
    (accepted : checkTypedLoweringWitnesses tree rows refs = true) :
    typedLoweringRowsHaveTypeEvidence types rows = true := by
  induction rows generalizing refs with
  | nil =>
      cases refs <;> simp_all [checkTypedLoweringWitnesses,
        typedLoweringRowsHaveTypeEvidence]
  | cons row rows ih =>
      cases refs with
      | nil => simp [checkTypedLoweringWitnesses] at accepted
      | cons typeIndex refs =>
          simp only [checkTypedLoweringWitnesses, Bool.and_eq_true] at accepted
          rcases accepted with ⟨headAccepted, tailAccepted⟩
          have tailSound := ih tailAccepted
          unfold typedLoweringRowsHaveTypeEvidence
          simp only [List.all_cons, Bool.and_eq_true]
          refine ⟨?_, tailSound⟩
          by_cases typed : typedLoweringRule row.rule = true
          · simp only [typed, Bool.not_true, Bool.false_or] at headAccepted ⊢
            cases found : tree.lookup typeIndex with
            | none => simp [found] at headAccepted
            | some typeRow =>
                simp only [found] at headAccepted
                exact typeEvidenceAny_of_lookup wellFormed represents found
                  headAccepted
          · cases ruleResult : typedLoweringRule row.rule <;> simp_all

theorem checkTypeLoweringWitnesses_sound
    {tree : SeqTree LoweringEvidence} {lowering : List LoweringEvidence}
    (wellFormed : tree.WellFormed leafCapacity)
    (represents : tree.Represents lowering)
    (accepted : checkTypeLoweringWitnesses tree rows refs = true) :
    typeRowsHaveLoweringEvidence lowering rows = true := by
  induction rows generalizing refs with
  | nil =>
      cases refs <;> simp_all [checkTypeLoweringWitnesses,
        typeRowsHaveLoweringEvidence]
  | cons row rows ih =>
      cases refs with
      | nil => simp [checkTypeLoweringWitnesses] at accepted
      | cons loweringIndex refs =>
          simp only [checkTypeLoweringWitnesses, Bool.and_eq_true] at accepted
          rcases accepted with ⟨headAccepted, tailAccepted⟩
          have tailSound := ih tailAccepted
          unfold typeRowsHaveLoweringEvidence
          simp only [List.all_cons, Bool.and_eq_true]
          refine ⟨?_, tailSound⟩
          cases found : tree.lookup loweringIndex with
          | none => simp [found] at headAccepted
          | some loweringRow =>
              simp only [found] at headAccepted
              exact loweringEvidenceAny_of_lookup wellFormed represents found
                headAccepted

theorem checkEvidenceWitnesses_sound
    (view : EvidenceWitnessView artifact)
    (accepted : checkEvidenceWitnesses view = true) :
    typedLoweringRowsHaveTypeEvidence artifact.types artifact.lowering = true ∧
      typeRowsHaveLoweringEvidence artifact.lowering artifact.types = true := by
  unfold checkEvidenceWitnesses at accepted
  simp only [Bool.and_eq_true] at accepted
  exact ⟨
    checkTypedLoweringWitnesses_sound view.typesWellFormed
      view.typesRepresent accepted.1,
    checkTypeLoweringWitnesses_sound view.loweringWellFormed
      view.loweringRepresent accepted.2⟩

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
